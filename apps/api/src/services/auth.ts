import { randomBytes } from "node:crypto";
import { and, eq, isNull } from "drizzle-orm";
import type { MiddlewareHandler } from "hono";
import { sign, verify, verifyWithJwks } from "hono/jwt";
import type { Db } from "../db/client.js";
import { users } from "../db/schema.js";
import { TRIAL_DAYS } from "./entitlements.js";

const APPLE_ISSUER = "https://appleid.apple.com";
const APPLE_JWKS_URI = "https://appleid.apple.com/auth/keys";
const TOKEN_TTL_SECONDS = 60 * 60 * 24 * 30;

export type AuthEnv = { Variables: { userId: string } };

export interface AuthUser {
  id: string;
  email?: string;
  /** True until an Apple ID is linked to the account. */
  anonymous: boolean;
}

export interface AuthService {
  readonly devLoginEnabled: boolean;
  /** Creates a guest account: onboarding and the first story happen before any sign-in. */
  createAnonymous(): Promise<{ token: string; user: AuthUser }>;
  /**
   * Signs in with Apple. With `currentUserId` (a guest account) the Apple ID is linked to that account,
   * keeping its profiles, stories and trial. If the Apple ID already belongs to another account, that
   * account is returned instead and the guest data is not merged.
   */
  loginWithApple(identityToken: string, currentUserId?: string): Promise<{ token: string; user: AuthUser }>;
  /** Second half of the Apple flow, after the identity token has been verified. Exposed for tests. */
  completeAppleLogin(appleSubject: string, email: string | undefined, currentUserId?: string): Promise<{ token: string; user: AuthUser }>;
  /** Resolves the user id from an `Authorization: Bearer` header value, if it is valid. */
  userIdFromHeader(header: string | undefined): Promise<string | undefined>;
  loginDev(name: string): Promise<{ token: string; user: AuthUser }>;
  requireAuth: MiddlewareHandler<AuthEnv>;
}

export function createAuthService(db: Db, env: NodeJS.ProcessEnv = process.env): AuthService {
  const production = env.NODE_ENV === "production";
  const secret = env.JWT_SECRET ?? (production ? undefined : randomBytes(32).toString("hex"));

  if (!secret) {
    throw new Error("JWT_SECRET is required in production.");
  }

  if (!env.JWT_SECRET) {
    console.warn("JWT_SECRET is not set: using a random secret, tokens stop working after restart.");
  }

  const devLoginEnabled = !production && env.AUTH_DEV_LOGIN === "1";

  async function issue(user: AuthUser) {
    const now = Math.floor(Date.now() / 1000);
    const token = await sign({ sub: user.id, iat: now, exp: now + TOKEN_TTL_SECONDS }, secret as string, "HS256");
    return { token, user };
  }

  const trialEnd = () => new Date(Date.now() + TRIAL_DAYS * 24 * 3600 * 1000);

  const toAuthUser = (row: typeof users.$inferSelect): AuthUser => ({
    id: row.id,
    email: row.email ?? undefined,
    anonymous: row.appleId === null
  });

  async function upsertUser(appleId: string, email?: string): Promise<AuthUser> {
    const [row] = await db
      .insert(users)
      .values({ appleId, email, trialEndsAt: trialEnd() })
      .onConflictDoUpdate({
        target: users.appleId,
        set: { updatedAt: new Date(), ...(email ? { email } : {}) }
      })
      .returning();

    return toAuthUser(row);
  }

  async function userIdFromHeader(header: string | undefined): Promise<string | undefined> {
    const token = header?.startsWith("Bearer ") ? header.slice(7) : undefined;

    if (!token) {
      return undefined;
    }

    try {
      const payload = await verify(token, secret as string, "HS256");
      const [user] = await db.select({ id: users.id }).from(users).where(eq(users.id, String(payload.sub))).limit(1);
      return user?.id;
    } catch {
      return undefined;
    }
  }

  async function completeAppleLogin(appleSubject: string, email: string | undefined, currentUserId?: string) {
    const [existing] = await db.select().from(users).where(eq(users.appleId, appleSubject)).limit(1);

    if (!existing && currentUserId) {
      const [linked] = await db
        .update(users)
        .set({ appleId: appleSubject, ...(email ? { email } : {}), updatedAt: new Date() })
        .where(and(eq(users.id, currentUserId), isNull(users.appleId)))
        .returning();

      if (linked) {
        return issue(toAuthUser(linked));
      }
    }

    return issue(await upsertUser(appleSubject, email));
  }

  return {
    devLoginEnabled,
    userIdFromHeader,

    async createAnonymous() {
      const [row] = await db.insert(users).values({ trialEndsAt: trialEnd() }).returning();
      return issue(toAuthUser(row));
    },

    async loginWithApple(identityToken, currentUserId) {
      const audience = env.APPLE_BUNDLE_ID;

      if (!audience) {
        throw new Error("APPLE_BUNDLE_ID is not configured.");
      }

      const payload = await verifyWithJwks(identityToken, {
        jwks_uri: APPLE_JWKS_URI,
        allowedAlgorithms: ["RS256"],
        verification: { iss: APPLE_ISSUER, aud: audience }
      });

      if (typeof payload.sub !== "string") {
        throw new Error("Apple identity token has no subject.");
      }

      return completeAppleLogin(payload.sub, typeof payload.email === "string" ? payload.email : undefined, currentUserId);
    },

    completeAppleLogin,

    async loginDev(name) {
      return issue(await upsertUser(`dev:${name}`));
    },

    requireAuth: async (c, next) => {
      const userId = await userIdFromHeader(c.req.header("authorization"));

      if (!userId) {
        return c.json({ error: { code: "unauthorized", message: "Missing, invalid or expired bearer token." } }, 401);
      }

      c.set("userId", userId);
      await next();
    }
  };
}
