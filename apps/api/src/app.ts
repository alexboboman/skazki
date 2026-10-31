import { Hono, type Context, type MiddlewareHandler } from "hono";
import type {
  ApiErrorResponse,
  AuthResponse,
  ChildProfile,
  ChildProfileDto,
  GenerateStoryRequest,
  PaywallErrorResponse,
  Tier,
  UpdateStoryRequest,
  WorldId
} from "../../../packages/shared/src/index.js";
import type { Db } from "./db/client.js";
import type { TextGenerator } from "./services/anthropicTextGenerator.js";
import { createAuthService, type AuthEnv } from "./services/auth.js";
import { EntitlementService, type ReserveResult } from "./services/entitlements.js";
import { DEFAULT_WORLD, WORLD_PROMPTS, wordsForMinutes } from "./services/catalog.js";
import type { ImageGenerator } from "./services/imageGenerator.js";
import type { MediaStore } from "./services/mediaStore.js";
import { ProfileLimitError, ProfileService } from "./services/profileService.js";
import { StoryService } from "./services/storyService.js";
import type { SafetyChecker } from "./services/safetyChecker.js";
import { runStoryPipeline, UnsafeStoryError } from "./services/storyPipeline.js";
import { validateChildProfileInput, validateGenerateStoryBody } from "./validation.js";

export interface AppDeps {
  db: Db;
  mediaStore: MediaStore;
  imageGenerator: ImageGenerator;
  /** Absent when ANTHROPIC_API_KEY is not configured. */
  textGenerator?: TextGenerator;
  safetyChecker?: SafetyChecker;
}

type ErrorStatus = 400 | 401 | 404 | 422 | 500 | 502;

export function createApp(deps: AppDeps) {
  const app = new Hono<AuthEnv>();
  const auth = createAuthService(deps.db);
  const profiles = new ProfileService(deps.db);
  const stories = new StoryService(deps.db);
  const entitlements = new EntitlementService(deps.db);

  app.get("/health", (c) => c.json({ status: "ok" }));

  app.get("/v1/media/:fileName", async (c) => {
    const file = await deps.mediaStore.read(c.req.param("fileName"));

    if (!file) {
      return errorResponse(c, 404, "media_not_found", "Media file not found.");
    }

    return c.body(new Uint8Array(file.bytes), 200, {
      "content-type": file.contentType,
      "cache-control": "public, max-age=31536000, immutable"
    });
  });

  // --- Auth ---

  // Guest account for onboarding; the client keeps the token in the Keychain.
  app.post("/v1/auth/anonymous", async (c) => {
    const response: AuthResponse = await auth.createAnonymous();
    return c.json(response, 201);
  });

  // With a guest bearer token the Apple ID is linked to that account; without one it is a plain sign-in.
  app.post("/v1/auth/apple", async (c) => {
    const body = await safeJson(c.req);
    const identityToken = isRecord(body) ? body.identityToken : undefined;

    if (typeof identityToken !== "string" || identityToken.length === 0) {
      return errorResponse(c, 400, "invalid_request", "identityToken is required.");
    }

    try {
      const currentUserId = await auth.userIdFromHeader(c.req.header("authorization"));
      const response: AuthResponse = await auth.loginWithApple(identityToken, currentUserId);
      return c.json(response);
    } catch {
      return errorResponse(c, 401, "invalid_apple_token", "Apple identity token could not be verified.");
    }
  });

  if (auth.devLoginEnabled) {
    app.post("/v1/auth/dev", async (c) => {
      const body = await safeJson(c.req);
      const name = isRecord(body) && typeof body.name === "string" && body.name.trim() ? body.name.trim() : "dev";
      const response: AuthResponse = await auth.loginDev(name);
      return c.json(response);
    });

    app.put("/v1/dev/subscription", auth.requireAuth, async (c) => {
      const body = await safeJson(c.req);
      const tier = isRecord(body) ? body.tier : undefined;

      if (tier !== "free" && tier !== "family" && tier !== "family_plus") {
        return errorResponse(c, 400, "invalid_request", "tier must be free, family or family_plus.");
      }

      await entitlements.devSetTier(c.get("userId"), tier);
      return c.json(await entitlements.snapshot(c.get("userId")));
    });
  }

  // --- Entitlements ---

  app.get("/v1/entitlements", auth.requireAuth, async (c) => c.json(await entitlements.snapshot(c.get("userId"))));

  // Postgres rejects malformed uuids with an error, so answer 404 before touching the database.
  app.use("/v1/profiles/:id", uuidGuard("profile_not_found", "Profile not found."));
  app.use("/v1/stories/:id", async (c, next) => {
    if (c.req.param("id") === "generate") {
      return next();
    }
    return uuidGuard("story_not_found", "Story not found.")(c, next);
  });

  // --- Child profiles ---

  app.get("/v1/profiles", auth.requireAuth, async (c) => c.json({ profiles: await profiles.list(c.get("userId")) }));

  app.post("/v1/profiles", auth.requireAuth, async (c) => {
    const input = validateChildProfileInput(await safeJson(c.req));

    if (!input.ok) {
      return errorResponse(c, 400, "invalid_request", input.message);
    }

    const userId = c.get("userId");
    const { tier, limit } = await entitlements.profileLimit(userId);

    try {
      return c.json(await profiles.create(userId, input.value, limit), 201);
    } catch (error) {
      if (error instanceof ProfileLimitError) {
        return paywallResponse(c, {
          code: "limit_reached",
          message: error.message,
          feature: "profiles",
          tier,
          limit: error.limit
        });
      }
      throw error;
    }
  });

  app.get("/v1/profiles/:id", auth.requireAuth, async (c) => {
    const profile = await profiles.get(c.get("userId"), c.req.param("id"));
    return profile ? c.json(profile) : errorResponse(c, 404, "profile_not_found", "Profile not found.");
  });

  app.put("/v1/profiles/:id", auth.requireAuth, async (c) => {
    const input = validateChildProfileInput(await safeJson(c.req));

    if (!input.ok) {
      return errorResponse(c, 400, "invalid_request", input.message);
    }

    const profile = await profiles.update(c.get("userId"), c.req.param("id"), input.value);
    return profile ? c.json(profile) : errorResponse(c, 404, "profile_not_found", "Profile not found.");
  });

  app.delete("/v1/profiles/:id", auth.requireAuth, async (c) => {
    const deleted = await profiles.delete(c.get("userId"), c.req.param("id"));
    return deleted ? c.body(null, 204) : errorResponse(c, 404, "profile_not_found", "Profile not found.");
  });

  // --- Stories ---

  app.post("/v1/stories/generate", auth.requireAuth, async (c) => {
    if (!deps.textGenerator || !deps.safetyChecker) {
      return errorResponse(c, 500, "missing_api_key", "ANTHROPIC_API_KEY is not configured.");
    }

    const body = validateGenerateStoryBody(await safeJson(c.req));

    if (!body.ok) {
      return errorResponse(c, 400, "invalid_request", body.message);
    }

    const userId = c.get("userId");
    let heroes: ChildProfile[];
    let heroIds: string[] = [];
    let worldId: WorldId | undefined = body.value.world;

    if (body.value.profileIds) {
      const saved: ChildProfileDto[] = [];

      for (const id of body.value.profileIds) {
        const profile = UUID.test(id) ? await profiles.get(userId, id) : undefined;

        if (!profile) {
          return errorResponse(c, 404, "profile_not_found", "Profile not found.");
        }

        saved.push(profile);
      }

      heroIds = saved.map((profile) => profile.id);
      worldId ??= saved[0].worlds[0] ?? DEFAULT_WORLD;
      heroes = saved.map((profile) => ({
        name: profile.name,
        age: profile.age,
        language: profile.language,
        interests: profile.interests,
        world: WORLD_PROMPTS[worldId as WorldId],
        favoriteCharacter: profile.favoriteCharacter,
        gender: profile.gender,
        appearance: profile.appearance
      }));
    } else {
      const inline = body.value.childProfile as ChildProfile;
      heroes = [worldId ? { ...inline, world: WORLD_PROMPTS[worldId] } : inline];
    }

    const reservation = await entitlements.reserve(userId, body.value.format);

    if (!reservation.ok) {
      return paywallResponse(c, reservationToPaywall(reservation));
    }

    try {
      const maxQuality = await entitlements.maxImageQuality(userId);
      const mediaOptions = body.value.mediaOptions && {
        ...body.value.mediaOptions,
        imageQuality: maxQuality === "standard" ? ("standard" as const) : body.value.mediaOptions.imageQuality
      };

      const request: GenerateStoryRequest = {
        childProfile: heroes[0],
        companions: heroes.slice(1),
        format: body.value.format,
        topic: body.value.topic,
        wordCount: body.value.wordCount ?? (body.value.lengthMinutes ? wordsForMinutes(body.value.lengthMinutes) : undefined),
        mediaOptions
      };

      const result = await runStoryPipeline(request, {
        textGenerator: deps.textGenerator,
        safetyChecker: deps.safetyChecker,
        imageGenerator: deps.imageGenerator,
        mediaStore: deps.mediaStore
      });
      const storyId = await stories.save(userId, heroIds, worldId, request, result);
      return c.json({ ...result, storyId });
    } catch (error) {
      await entitlements.refund(userId, reservation);

      if (error instanceof UnsafeStoryError) {
        return errorResponse(c, 422, "story_rejected", error.message);
      }

      const message = error instanceof Error ? error.message : "Unknown generation error.";
      return errorResponse(c, 502, "story_generation_failed", message);
    }
  });

  app.get("/v1/stories", auth.requireAuth, async (c) => {
    const profileId = c.req.query("profileId");
    const favorite = c.req.query("favorite");

    if (profileId !== undefined && !UUID.test(profileId)) {
      return errorResponse(c, 400, "invalid_request", "profileId must be a uuid.");
    }

    if (favorite !== undefined && favorite !== "true" && favorite !== "false") {
      return errorResponse(c, 400, "invalid_request", "favorite must be true or false.");
    }

    return c.json({
      stories: await stories.list(c.get("userId"), {
        heroId: profileId,
        favorite: favorite === undefined ? undefined : favorite === "true"
      })
    });
  });

  app.get("/v1/stories/:id", auth.requireAuth, async (c) => {
    const story = await stories.get(c.get("userId"), c.req.param("id"));
    return story ? c.json(story) : errorResponse(c, 404, "story_not_found", "Story not found.");
  });

  app.patch("/v1/stories/:id", auth.requireAuth, async (c) => {
    const body = await safeJson(c.req);
    const patch: UpdateStoryRequest = {};

    if (!isRecord(body)) {
      return errorResponse(c, 400, "invalid_request", "Request body must be a JSON object.");
    }

    if (body.favorite !== undefined) {
      if (typeof body.favorite !== "boolean") {
        return errorResponse(c, 400, "invalid_request", "favorite must be a boolean.");
      }
      patch.favorite = body.favorite;
    }

    if (body.readProgress !== undefined) {
      if (typeof body.readProgress !== "number" || body.readProgress < 0 || body.readProgress > 1) {
        return errorResponse(c, 400, "invalid_request", "readProgress must be a number between 0 and 1.");
      }
      patch.readProgress = body.readProgress;
    }

    if (patch.favorite === undefined && patch.readProgress === undefined) {
      return errorResponse(c, 400, "invalid_request", "Nothing to update: send favorite and/or readProgress.");
    }

    const updated = await stories.update(c.get("userId"), c.req.param("id"), patch);
    const story = updated ? await stories.get(c.get("userId"), c.req.param("id")) : undefined;
    return story ? c.json(story) : errorResponse(c, 404, "story_not_found", "Story not found.");
  });

  app.delete("/v1/stories/:id", auth.requireAuth, async (c) => {
    const deleted = await stories.delete(c.get("userId"), c.req.param("id"));
    return deleted ? c.body(null, 204) : errorResponse(c, 404, "story_not_found", "Story not found.");
  });

  app.onError((error, c) => {
    console.error(error);
    return errorResponse(c, 500, "internal_error", "Internal server error.");
  });

  return app;
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function uuidGuard(code: string, message: string): MiddlewareHandler {
  return async (c, next) => {
    if (!UUID.test(c.req.param("id") ?? "")) {
      return errorResponse(c, 404, code, message);
    }
    await next();
  };
}

function paywallResponse(c: Context, error: PaywallErrorResponse["error"]) {
  const payload: PaywallErrorResponse = { error };
  return c.json(payload, 402);
}

function reservationToPaywall(result: Extract<ReserveResult, { ok: false }>): PaywallErrorResponse["error"] {
  const tier: Tier = result.tier;

  if (result.reason === "upgrade_required") {
    return { code: "upgrade_required", message: "Story arcs need a paid plan.", feature: result.feature, tier };
  }

  return {
    code: "limit_reached",
    message: `Limit for ${result.feature} reached on the ${tier} plan.`,
    feature: result.feature,
    tier,
    limit: result.limit,
    resetsAt: result.resetsAt?.toISOString()
  };
}

async function safeJson(req: { json: () => Promise<unknown> }): Promise<unknown> {
  try {
    return await req.json();
  } catch {
    return undefined;
  }
}

function errorResponse(c: Context, status: ErrorStatus, code: string, message: string) {
  const payload: ApiErrorResponse = { error: { code, message } };
  return c.json(payload, status);
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
