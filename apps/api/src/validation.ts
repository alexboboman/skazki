import type { ChildProfileInput, GenerateStoryBody } from "../../../packages/shared/src/index.js";

export type Validated<T> = { ok: true; value: T } | { ok: false; message: string };

export function validateChildProfileInput(body: unknown): Validated<ChildProfileInput> {
  if (!isRecord(body)) {
    return { ok: false, message: "Request body must be a JSON object." };
  }

  if (!isNonEmptyString(body.name)) {
    return { ok: false, message: "name must be a non-empty string." };
  }

  if (typeof body.age !== "number" || !Number.isInteger(body.age) || body.age < 2 || body.age > 12) {
    return { ok: false, message: "age must be an integer between 2 and 12." };
  }

  if (!isNonEmptyString(body.language)) {
    return { ok: false, message: "language must be a non-empty string." };
  }

  if (!isStringArray(body.interests)) {
    return { ok: false, message: "interests must be an array of strings." };
  }

  if (!isStringArray(body.worlds)) {
    return { ok: false, message: "worlds must be an array of strings." };
  }

  if (body.gender !== undefined && !isNonEmptyString(body.gender)) {
    return { ok: false, message: "gender must be a non-empty string when provided." };
  }

  return {
    ok: true,
    value: {
      name: body.name.trim(),
      age: body.age,
      gender: body.gender,
      interests: body.interests,
      worlds: body.worlds,
      favoriteCharacter: isNonEmptyString(body.favoriteCharacter) ? body.favoriteCharacter : undefined,
      language: body.language
    }
  };
}

export function validateGenerateStoryBody(body: unknown): Validated<GenerateStoryBody> {
  if (!isRecord(body)) {
    return { ok: false, message: "Request body must be a JSON object." };
  }

  if (!isStoryFormat(body.format)) {
    return { ok: false, message: "format must be quick_story, classic_story, or story_arc_part." };
  }

  if (body.wordCount !== undefined && (typeof body.wordCount !== "number" || body.wordCount < 200 || body.wordCount > 1200)) {
    return { ok: false, message: "wordCount must be a number between 200 and 1200." };
  }

  const common = {
    format: body.format,
    wordCount: body.wordCount,
    mediaOptions: isRecord(body.mediaOptions)
      ? {
          requestedTypes: Array.isArray(body.mediaOptions.requestedTypes)
            ? body.mediaOptions.requestedTypes.filter(isMediaType)
            : [],
          imageQuality: body.mediaOptions.imageQuality === "hd" ? ("hd" as const) : ("standard" as const)
        }
      : undefined
  };

  if (body.profileId !== undefined) {
    if (!isNonEmptyString(body.profileId)) {
      return { ok: false, message: "profileId must be a non-empty string." };
    }

    return { ok: true, value: { ...common, profileId: body.profileId } };
  }

  const childProfile = body.childProfile;

  if (!isRecord(childProfile)) {
    return { ok: false, message: "profileId or childProfile is required." };
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

  if (!isStringArray(childProfile.interests)) {
    return { ok: false, message: "childProfile.interests must be an array of strings." };
  }

  if (!isNonEmptyString(childProfile.world)) {
    return { ok: false, message: "childProfile.world must be a non-empty string." };
  }

  return {
    ok: true,
    value: {
      ...common,
      childProfile: {
        name: childProfile.name,
        age: childProfile.age,
        language: childProfile.language,
        interests: childProfile.interests,
        world: childProfile.world,
        favoriteCharacter: isNonEmptyString(childProfile.favoriteCharacter) ? childProfile.favoriteCharacter : undefined
      }
    }
  };
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isNonEmptyString(value: unknown): value is string {
  return typeof value === "string" && value.trim().length > 0;
}

function isStringArray(value: unknown): value is string[] {
  return Array.isArray(value) && value.every(isNonEmptyString);
}

function isStoryFormat(value: unknown): value is GenerateStoryBody["format"] {
  return value === "quick_story" || value === "classic_story" || value === "story_arc_part";
}

function isMediaType(value: unknown): value is "image" | "audio" | "video" {
  return value === "image" || value === "audio" || value === "video";
}
