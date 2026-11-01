import { Hono, type Context, type MiddlewareHandler } from "hono";
import { WORLD_IDS } from "../../../packages/shared/src/index.js";
import type {
  ApiErrorResponse,
  AuthResponse,
  ChildProfile,
  ChildProfileDto,
  GenerateStoryRequest,
  GenerateStoryResponse,
  MediaOptions,
  PaywallErrorResponse,
  Tier,
  UpdateStoryRequest,
  WorldId
} from "../../../packages/shared/src/index.js";
import type { Db } from "./db/client.js";
import type { TextGenerator } from "./services/anthropicTextGenerator.js";
import { createAppStoreVerifier, type AppStoreVerifier } from "./services/appStore.js";
import { createAuthService, type AuthEnv } from "./services/auth.js";
import { EntitlementService, type ReserveResult } from "./services/entitlements.js";
import { DEFAULT_WORLD, WORLD_PROMPTS, wordsForMinutes } from "./services/catalog.js";
import type { ImageGenerator } from "./services/imageGenerator.js";
import { NarrationService } from "./services/narrationService.js";
import type { SpeechGenerator } from "./services/speechGenerator.js";
import type { MediaStore } from "./services/mediaStore.js";
import { ProfileLimitError, ProfileService } from "./services/profileService.js";
import { PurchasesUnavailableError, SubscriptionService } from "./services/subscriptionService.js";
import { PartConflictError, StoryService } from "./services/storyService.js";
import type { SafetyChecker } from "./services/safetyChecker.js";
import { runStoryPipeline, UnsafeStoryError, type StoryPipelineResult } from "./services/storyPipeline.js";
import { validateChildProfileInput, validateGenerateStoryBody, validateMediaOptions } from "./validation.js";

export interface AppDeps {
  db: Db;
  mediaStore: MediaStore;
  imageGenerator: ImageGenerator;
  /** Absent when ANTHROPIC_API_KEY is not configured. */
  textGenerator?: TextGenerator;
  safetyChecker?: SafetyChecker;
  /** Absent without a Phygital+ key: premium narration is then unavailable (503). */
  speechGenerator?: SpeechGenerator;
  /** Checks App Store signatures; defaults to the real chain check against Apple Root CA - G3. */
  appStoreVerifier?: AppStoreVerifier;
  /** Bundle id the purchases must belong to; defaults to APPLE_BUNDLE_ID. Without it purchases are unavailable (503). */
  appleBundleId?: string;
  /** How long POST /v1/stories/:id/audio waits for the narration before answering 202 (default 2.5 s). */
  narrationWaitMs?: number;
}

type ErrorStatus = 400 | 401 | 404 | 409 | 422 | 500 | 502 | 503;

export function createApp(deps: AppDeps) {
  const app = new Hono<AuthEnv>();
  const auth = createAuthService(deps.db);
  const profiles = new ProfileService(deps.db);
  const stories = new StoryService(deps.db);
  const entitlements = new EntitlementService(deps.db);
  const purchases = new SubscriptionService(
    deps.db,
    deps.appStoreVerifier ?? createAppStoreVerifier(),
    deps.appleBundleId ?? process.env.APPLE_BUNDLE_ID
  );
  const narration = deps.speechGenerator && new NarrationService(stories, deps.mediaStore, deps.speechGenerator, deps.narrationWaitMs);

  function pipelineDeps() {
    return {
      textGenerator: deps.textGenerator!,
      safetyChecker: deps.safetyChecker!,
      imageGenerator: deps.imageGenerator,
      mediaStore: deps.mediaStore
    };
  }

  /** The picture quality never exceeds what the tier allows. */
  async function limitMedia(userId: string, options: MediaOptions | undefined): Promise<MediaOptions | undefined> {
    if (!options) {
      return undefined;
    }

    const max = await entitlements.maxImageQuality(userId);
    return { ...options, imageQuality: max === "standard" ? "standard" : options.imageQuality };
  }

  function generationError(c: Context, error: unknown) {
    if (error instanceof UnsafeStoryError) {
      return errorResponse(c, 422, "story_rejected", error.message);
    }

    return errorResponse(c, 502, "story_generation_failed", error instanceof Error ? error.message : "Unknown generation error.");
  }

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

  // Called by the app on every launch so an account that is used regularly never loses its token.
  app.post("/v1/auth/refresh", auth.requireAuth, async (c) => {
    const response: AuthResponse = await auth.refresh(c.get("userId"));
    return c.json(response);
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

  // --- Subscriptions (StoreKit 2) ---

  // The app sends the signed transactions it holds after a purchase, on restore and on launch; the tier follows.
  app.post("/v1/subscription/sync", auth.requireAuth, async (c) => {
    const body = await safeJson(c.req);
    const transactions = isRecord(body) ? body.transactions : undefined;

    if (!Array.isArray(transactions) || transactions.length > 20 || !transactions.every((item) => typeof item === "string")) {
      return errorResponse(c, 400, "invalid_request", "transactions must be an array of up to 20 signed transactions.");
    }

    try {
      const applied = await purchases.sync(c.get("userId"), transactions as string[]);

      if (transactions.length > 0 && applied === 0) {
        return errorResponse(c, 400, "invalid_transaction", "None of the transactions could be verified.");
      }
    } catch (error) {
      if (error instanceof PurchasesUnavailableError) {
        return errorResponse(c, 503, "purchases_unavailable", "Purchases are not configured on the server.");
      }
      throw error;
    }

    return c.json(await entitlements.snapshot(c.get("userId")));
  });

  // App Store Server Notifications v2. Apple signs the payload, so the signature is the authentication.
  app.post("/v1/webhooks/apple", async (c) => {
    const body = await safeJson(c.req);
    const signedPayload = isRecord(body) ? body.signedPayload : undefined;

    if (typeof signedPayload !== "string" || signedPayload.length === 0) {
      return errorResponse(c, 400, "invalid_request", "signedPayload is required.");
    }

    try {
      await purchases.handleNotification(signedPayload);
    } catch (error) {
      if (error instanceof PurchasesUnavailableError) {
        return errorResponse(c, 503, "purchases_unavailable", "Purchases are not configured on the server.");
      }
      return errorResponse(c, 400, "invalid_notification", "Notification could not be verified.");
    }

    return c.json({ ok: true });
  });

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
      heroes = saved.map((profile) => toHero(profile, worldId as WorldId));
    } else {
      const inline = body.value.childProfile as ChildProfile;
      heroes = [worldId ? { ...inline, world: WORLD_PROMPTS[worldId] } : inline];
    }

    const reservation = await entitlements.reserve(userId, body.value.format);

    if (!reservation.ok) {
      return paywallResponse(c, reservationToPaywall(reservation));
    }

    const arcLength = body.value.arcLength;

    if (arcLength) {
      const slot = await entitlements.canStartArc(userId, await stories.countActiveArcs(userId));

      if (!slot.ok) {
        return paywallResponse(c, reservationToPaywall(slot));
      }
    }

    try {
      const wordCount = body.value.wordCount ?? (body.value.lengthMinutes ? wordsForMinutes(body.value.lengthMinutes) : undefined);
      const request: GenerateStoryRequest = {
        childProfile: heroes[0],
        companions: heroes.slice(1),
        format: body.value.format,
        topic: body.value.topic,
        wordCount,
        mediaOptions: await limitMedia(userId, body.value.mediaOptions),
        arc: arcLength ? { length: arcLength, partNumber: 1, previousSummaries: [] } : undefined
      };

      const { notes, ...result } = await runStoryPipeline(request, pipelineDeps());

      if (arcLength) {
        const storyId = await stories.saveSeries(userId, heroIds, worldId, { length: arcLength, topic: body.value.topic, wordCount }, result, notes);
        return c.json({ ...result, storyId, partNumber: 1, arc: { length: arcLength, partsReady: 1, status: "active" } } satisfies GenerateStoryResponse);
      }

      const storyId = await stories.save(userId, heroIds, worldId, request, result);
      return c.json({ ...result, storyId });
    } catch (error) {
      await entitlements.refund(userId, reservation);
      return generationError(c, error);
    }
  });

  /** Writes the next part of a series. */
  app.post("/v1/stories/:id/parts", auth.requireAuth, uuidGuard("story_not_found", "Story not found."), async (c) => {
    if (!deps.textGenerator || !deps.safetyChecker) {
      return errorResponse(c, 500, "missing_api_key", "ANTHROPIC_API_KEY is not configured.");
    }

    const userId = c.get("userId");
    const state = await stories.arcState(userId, c.req.param("id"));

    if (!state) {
      return errorResponse(c, 404, "story_not_found", "Series not found.");
    }

    if (state.status === "completed" || state.partsReady >= state.length) {
      return errorResponse(c, 409, "arc_completed", "All parts of this series are already written.");
    }

    const reservation = await entitlements.reserve(userId, "story_arc_part");

    if (!reservation.ok) {
      return paywallResponse(c, reservationToPaywall(reservation));
    }

    const worldId = isWorldId(state.world) ? state.world : DEFAULT_WORLD;
    const saved: ChildProfileDto[] = [];

    for (const id of state.heroIds) {
      const profile = await profiles.get(userId, id);

      if (profile) {
        saved.push(profile);
      }
    }

    if (saved.length === 0) {
      return errorResponse(c, 409, "heroes_missing", "The heroes of this series were deleted.");
    }

    const partNumber = state.partsReady + 1;
    const requestBody = await safeJson(c.req);

    try {
      const request: GenerateStoryRequest = {
        childProfile: toHero(saved[0], worldId),
        companions: saved.slice(1).map((profile) => toHero(profile, worldId)),
        format: "story_arc_part",
        topic: state.topic,
        wordCount: state.wordCount,
        mediaOptions: await limitMedia(userId, isRecord(requestBody) ? validateMediaOptions(requestBody.mediaOptions) : undefined),
        arc: { length: state.length, partNumber, title: state.title, seed: state.seed, previousSummaries: state.recentSummaries }
      };

      const { notes, ...result } = await runStoryPipeline(request, pipelineDeps());
      await stories.addPart(state.storyId, partNumber, result, notes);

      const last = partNumber === state.length;
      return c.json({
        ...result,
        storyId: state.storyId,
        partNumber,
        arc: { length: state.length, partsReady: partNumber, status: last ? "completed" : "active" }
      } satisfies GenerateStoryResponse);
    } catch (error) {
      if (error instanceof PartConflictError) {
        return errorResponse(c, 409, "part_conflict", error.message);
      }

      return generationError(c, error);
    }
  });

  /**
   * Premium narration of one part (Family+). Answers 200 with the audio asset, or 202 `{status: "processing"}`
   * while it is being voiced (ask again, about every 5 s). Voiced once, then served from the stored file.
   */
  app.post("/v1/stories/:id/audio", auth.requireAuth, uuidGuard("story_not_found", "Story not found."), async (c) => {
    const body = await safeJson(c.req);
    const part = isRecord(body) && body.part !== undefined ? body.part : 1;

    if (typeof part !== "number" || !Number.isInteger(part) || part < 1) {
      return errorResponse(c, 400, "invalid_request", "part must be a positive integer.");
    }

    const userId = c.get("userId");
    const allowed = await entitlements.canUsePremiumVoice(userId);

    if (!allowed.ok) {
      return paywallResponse(c, reservationToPaywall(allowed));
    }

    if (!narration) {
      return errorResponse(c, 503, "premium_voice_unavailable", "Premium narration is not configured on this server.");
    }

    try {
      const result = await narration.request(userId, c.req.param("id"), part);

      if (!result) {
        return errorResponse(c, 404, "story_not_found", "Story or part not found.");
      }

      return result.status === "ready" ? c.json(result.audio) : c.json({ status: "processing" }, 202);
    } catch (error) {
      return errorResponse(c, 502, "audio_generation_failed", error instanceof Error ? error.message : "Unknown narration error.");
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

    if (body.readPart !== undefined) {
      if (typeof body.readPart !== "number" || !Number.isInteger(body.readPart) || body.readPart < 1) {
        return errorResponse(c, 400, "invalid_request", "readPart must be a positive integer.");
      }
      patch.readPart = body.readPart;
    }

    if (patch.favorite === undefined && patch.readProgress === undefined && patch.readPart === undefined) {
      return errorResponse(c, 400, "invalid_request", "Nothing to update: send favorite, readProgress and/or readPart.");
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

function toHero(profile: ChildProfileDto, world: WorldId): ChildProfile {
  return {
    name: profile.name,
    age: profile.age,
    language: profile.language,
    interests: profile.interests,
    world: WORLD_PROMPTS[world],
    favoriteCharacter: profile.favoriteCharacter,
    gender: profile.gender,
    appearance: profile.appearance
  };
}

function isWorldId(value: unknown): value is WorldId {
  return typeof value === "string" && (WORLD_IDS as readonly string[]).includes(value);
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
    const message = result.feature === "premium_voice" ? "Premium narration needs the Family+ plan." : "Story arcs need a paid plan.";
    return { code: "upgrade_required", message, feature: result.feature, tier };
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
