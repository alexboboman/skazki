import { serve } from "@hono/node-server";
import { Hono, type Context } from "hono";
import type { ApiErrorResponse, GenerateStoryRequest } from "../../../packages/shared/src/index.js";
import { AnthropicTextGenerator } from "./services/anthropicTextGenerator.js";

const app = new Hono();

app.get("/health", (c) => {
  return c.json({ status: "ok" });
});

app.post("/v1/stories/generate", async (c) => {
  const apiKey = process.env.ANTHROPIC_API_KEY;

  if (!apiKey) {
    return errorResponse(c, 500, "missing_api_key", "ANTHROPIC_API_KEY is not configured.");
  }

  const body = await safeJson(c.req);
  const request = validateGenerateStoryRequest(body);

  if (!request.ok) {
    return errorResponse(c, 400, "invalid_request", request.message);
  }

  try {
    const generator = new AnthropicTextGenerator(apiKey);
    const response = await generator.generateStory(request.value);
    return c.json(response);
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unknown generation error.";
    return errorResponse(c, 502, "story_generation_failed", message);
  }
});

const port = Number(process.env.PORT ?? 3000);

serve({ fetch: app.fetch, port });
console.log(`API listening on http://localhost:${port}`);

async function safeJson(req: { json: () => Promise<unknown> }): Promise<unknown> {
  try {
    return await req.json();
  } catch {
    return undefined;
  }
}

function validateGenerateStoryRequest(
  body: unknown
): { ok: true; value: GenerateStoryRequest } | { ok: false; message: string } {
  if (!isRecord(body)) {
    return { ok: false, message: "Request body must be a JSON object." };
  }

  const childProfile = body.childProfile;

  if (!isRecord(childProfile)) {
    return { ok: false, message: "childProfile is required." };
  }

  if (!isNonEmptyString(childProfile.name)) {
    return { ok: false, message: "childProfile.name must be a non-empty string." };
  }

  if (typeof childProfile.age !== "number" || childProfile.age < 2 || childProfile.age > 12) {
    return { ok: false, message: "childProfile.age must be a number between 2 and 12." };
  }

  if (!isNonEmptyString(childProfile.language)) {
    return { ok: false, message: "childProfile.language must be a non-empty string." };
  }

  if (!Array.isArray(childProfile.interests) || !childProfile.interests.every(isNonEmptyString)) {
    return { ok: false, message: "childProfile.interests must be an array of strings." };
  }

  if (!isNonEmptyString(childProfile.world)) {
    return { ok: false, message: "childProfile.world must be a non-empty string." };
  }

  if (!isStoryFormat(body.format)) {
    return { ok: false, message: "format must be quick_story, classic_story, or story_arc_part." };
  }

  if (body.wordCount !== undefined && (typeof body.wordCount !== "number" || body.wordCount < 200 || body.wordCount > 1200)) {
    return { ok: false, message: "wordCount must be a number between 200 and 1200." };
  }

  return {
    ok: true,
    value: {
      childProfile: {
        name: childProfile.name,
        age: childProfile.age,
        language: childProfile.language,
        interests: childProfile.interests,
        world: childProfile.world,
        favoriteCharacter: isNonEmptyString(childProfile.favoriteCharacter) ? childProfile.favoriteCharacter : undefined
      },
      format: body.format,
      wordCount: body.wordCount,
      mediaOptions: isRecord(body.mediaOptions)
        ? {
            requestedTypes: Array.isArray(body.mediaOptions.requestedTypes)
              ? body.mediaOptions.requestedTypes.filter(isMediaType)
              : []
          }
        : undefined
    }
  };
}

function errorResponse(c: Context, status: 400 | 500 | 502, code: string, message: string) {
  const payload: ApiErrorResponse = { error: { code, message } };
  return c.json(payload, status);
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isNonEmptyString(value: unknown): value is string {
  return typeof value === "string" && value.trim().length > 0;
}

function isStoryFormat(value: unknown): value is GenerateStoryRequest["format"] {
  return value === "quick_story" || value === "classic_story" || value === "story_arc_part";
}

function isMediaType(value: unknown): value is "image" | "audio" | "video" {
  return value === "image" || value === "audio" || value === "video";
}
