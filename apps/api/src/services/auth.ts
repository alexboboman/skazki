import { randomBytes } from "node:crypto";
import { eq } from "drizzle-orm";
import type { MiddlewareHandler } from "hono";
import { sign, verify, verifyWithJwks } from "hono/jwt";
import type { Db } from "../db/client.js";
import { users } from "../db/schema.js";

const APPLE_ISSUER = "https://appleid.apple.com";
const APPLE_JWKS_URI = "https://appleid.apple.com/auth/keys";
const TOKEN_TTL_SECONDS = 60 * 60 * 24 * 30;

export type AuthEnv = { Variables: { userId: string } };

export interface AuthUser {
  id: string;
  email?: string;
}

export interface AuthService {
  readonly devLoginEnabled: boolean;
  loginWithApple(identityToken: string): Promise<{ token: string; user: AuthUser }>;
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

  async function upsertUser(appleId: string, email?: string): Promise<AuthUser> {
    const [row] = await db
      .insert(users)
      .values({ appleId, email })
      .onConflictDoUpdate({
        target: users.appleId,
        set: { updatedAt: new Date(), ...(email ? { email } : {}) }
      })
      .returning();

    return { id: row.id, email: row.email ?? undefined };
  }

  return {
    devLoginEnabled,

    async loginWithApple(identityToken) {
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

      return issue(await upsertUser(payload.sub, typeof payload.email === "string" ? payload.email : undefined));
    },

    async loginDev(name) {
      return issue(await upsertUser(`dev:${name}`));
    },

    requireAuth: async (c, next) => {
      const header = c.req.header("authorization") ?? "";
      const token = header.startsWith("Bearer ") ? header.slice(7) : undefined;

      if (!token) {
        return c.json({ error: { code: "unauthorized", message: "Missing bearer token." } }, 401);
      }

      try {
        const payload = await verify(token, secret, "HS256");
        const [user] = await db.select({ id: users.id }).from(users).where(eq(users.id, String(payload.sub))).limit(1);

        if (!user) {
          throw new Error("Unknown user.");
        }

        c.set("userId", user.id);
      } catch {
        return c.json({ error: { code: "unauthorized", message: "Invalid or expired token." } }, 401);
      }

      await next();
    }
  };
}
