import {
  ARC_LENGTHS,
  WORLD_IDS,
  type ArcLength,
  type Appearance,
  type ChildProfileInput,
  type Gender,
  type GenerateStoryBody,
  type LengthMinutes,
  type MediaOptions,
  type WorldId
} from "../../../packages/shared/src/index.js";
import { HAIR_COUNT, OUTFIT_COUNT, SKIN_COUNT } from "./services/catalog.js";

export const MAX_HEROES = 3;
const MAX_TOPIC_LENGTH = 300;

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

  if (!Array.isArray(body.worlds) || !body.worlds.every(isWorldId)) {
    return { ok: false, message: `worlds must be an array of: ${WORLD_IDS.join(", ")}.` };
  }

  if (body.gender !== undefined && body.gender !== null && body.gender !== "boy" && body.gender !== "girl" && body.gender !== "none") {
    return { ok: false, message: "gender must be boy, girl or none." };
  }

  const appearance = validateAppearance(body.appearance);

  if (!appearance.ok) {
    return appearance;
  }

  return {
    ok: true,
    value: {
      name: body.name.trim(),
      age: body.age,
      gender: body.gender === "boy" || body.gender === "girl" ? body.gender : undefined,
      appearance: appearance.value,
      interests: body.interests,
      worlds: body.worlds,
      favoriteCharacter: isNonEmptyString(body.favoriteCharacter) ? body.favoriteCharacter : undefined,
      language: body.language
    }
  };
}

export function validateAppearance(value: unknown): Validated<Appearance | undefined> {
  if (value === undefined || value === null) {
    return { ok: true, value: undefined };
  }

  if (!isRecord(value)) {
    return { ok: false, message: "appearance must be an object." };
  }

  const inRange = (v: unknown, count: number): v is number => typeof v === "number" && Number.isInteger(v) && v >= 0 && v < count;

  if (!inRange(value.skin, SKIN_COUNT) || !inRange(value.hair, HAIR_COUNT) || !inRange(value.outfit, OUTFIT_COUNT)) {
    return {
      ok: false,
      message: `appearance.skin must be 0-${SKIN_COUNT - 1}, hair 0-${HAIR_COUNT - 1} and outfit 0-${OUTFIT_COUNT - 1}.`
    };
  }

  if (value.hairStyle !== "short" && value.hairStyle !== "long") {
    return { ok: false, message: "appearance.hairStyle must be short or long." };
  }

  return { ok: true, value: { skin: value.skin, hair: value.hair, hairStyle: value.hairStyle, outfit: value.outfit } };
}

export function validateMediaOptions(value: unknown): MediaOptions | undefined {
  if (!isRecord(value)) {
    return undefined;
  }

  return {
    requestedTypes: Array.isArray(value.requestedTypes) ? value.requestedTypes.filter(isMediaType) : [],
    imageQuality: value.imageQuality === "hd" ? "hd" : "standard"
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

  if (body.lengthMinutes !== undefined && body.lengthMinutes !== 4 && body.lengthMinutes !== 7 && body.lengthMinutes !== 12) {
    return { ok: false, message: "lengthMinutes must be 4, 7 or 12." };
  }

  if (body.world !== undefined && !isWorldId(body.world)) {
    return { ok: false, message: `world must be one of: ${WORLD_IDS.join(", ")}.` };
  }

  if (body.topic !== undefined && (typeof body.topic !== "string" || body.topic.length > MAX_TOPIC_LENGTH)) {
    return { ok: false, message: `topic must be a string of at most ${MAX_TOPIC_LENGTH} characters.` };
  }

  if (body.format === "story_arc_part" && !ARC_LENGTHS.includes(body.arcLength as ArcLength)) {
    return { ok: false, message: `arcLength must be one of: ${ARC_LENGTHS.join(", ")}.` };
  }

  const common = {
    format: body.format,
    arcLength: body.format === "story_arc_part" ? (body.arcLength as ArcLength) : undefined,
    wordCount: body.wordCount,
    lengthMinutes: body.lengthMinutes as LengthMinutes | undefined,
    world: body.world as WorldId | undefined,
    topic: typeof body.topic === "string" && body.topic.trim() ? body.topic.trim() : undefined,
    mediaOptions: validateMediaOptions(body.mediaOptions)
  };

  if (body.profileIds !== undefined) {
    const ids = body.profileIds;

    if (!Array.isArray(ids) || ids.length < 1 || ids.length > MAX_HEROES || !ids.every(isNonEmptyString) || new Set(ids).size !== ids.length) {
      return { ok: false, message: `profileIds must be 1 to ${MAX_HEROES} distinct profile ids.` };
    }

    return { ok: true, value: { ...common, profileIds: ids } };
  }

  if (body.format === "story_arc_part") {
    // The next parts are written for the same heroes, so they have to be saved profiles.
    return { ok: false, message: "A series needs saved profiles: send profileIds." };
  }

  const childProfile = body.childProfile;

  if (!isRecord(childProfile)) {
    return { ok: false, message: "profileIds or childProfile is required." };
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

  const appearance = validateAppearance(childProfile.appearance);

  if (!appearance.ok) {
    return appearance;
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
        favoriteCharacter: isNonEmptyString(childProfile.favoriteCharacter) ? childProfile.favoriteCharacter : undefined,
        gender: childProfile.gender === "boy" || childProfile.gender === "girl" ? (childProfile.gender as Gender) : undefined,
        appearance: appearance.value
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

function isWorldId(value: unknown): value is WorldId {
  return typeof value === "string" && (WORLD_IDS as readonly string[]).includes(value);
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
