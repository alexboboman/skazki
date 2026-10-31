export type StoryFormat = "quick_story" | "classic_story" | "story_arc_part";

export type MediaType = "image" | "audio" | "video";

export const WORLD_IDS = ["forest", "ocean", "space", "castle", "clouds", "jungle"] as const;

export type WorldId = (typeof WORLD_IDS)[number];

export type Gender = "boy" | "girl";

/**
 * Hero look picked in the profile editor. Values are indexes into the client palettes:
 * skin 0-4 (light to dark), hair 0-5 (dark brown, brown, chestnut, blond, platinum, black),
 * outfit 0-4 (purple, teal, coral, blue, pink).
 */
export interface Appearance {
  skin: number;
  hair: number;
  hairStyle: "short" | "long";
  outfit: number;
}

export interface ChildProfile {
  name: string;
  age: number;
  language: string;
  interests: string[];
  world: string;
  favoriteCharacter?: string;
  gender?: Gender;
  appearance?: Appearance;
}

export interface MediaOptions {
  requestedTypes: MediaType[];
  imageQuality?: "standard" | "hd";
  audioVoice?: "on_device" | "premium";
}

export interface GenerateStoryRequest {
  /** Main hero. */
  childProfile: ChildProfile;
  /** Other children who are heroes of the same story. */
  companions?: ChildProfile[];
  format: StoryFormat;
  /** What the story is about: a preset like "Не страшно в темноте" or the parent's own words. */
  topic?: string;
  wordCount?: number;
  mediaOptions?: MediaOptions;
}

/** Reading length choices of the "Сочинить" screen. */
export type LengthMinutes = 4 | 7 | 12;

/**
 * Body of POST /v1/stories/generate: one to three saved `profileIds` (the first is the main hero)
 * or an inline `childProfile`. `world` overrides the hero's world for this story;
 * `lengthMinutes` is turned into a word count unless `wordCount` is given.
 */
export type GenerateStoryBody = Omit<GenerateStoryRequest, "childProfile" | "companions"> & {
  world?: WorldId;
  lengthMinutes?: LengthMinutes;
} & (
    | { profileIds: string[]; childProfile?: undefined }
    | { profileIds?: undefined; childProfile: ChildProfile }
  );

export interface StoryUsage {
  inputTokens: number;
  outputTokens: number;
  estimatedCostUsd: number;
}

export type PipelineStepName = "generate_text" | "safety_check" | "parse_media_prompts" | "generate_images";

export type PipelineStepStatus = "succeeded" | "failed" | "skipped";

export interface PipelineStep {
  name: PipelineStepName;
  status: PipelineStepStatus;
  provider?: string;
  durationMs: number;
  error?: string;
}

export interface MediaAsset {
  id: string;
  type: MediaType;
  variant: "standard" | "hd";
  provider: string;
  url: string;
  contentType: string;
  prompt: string;
  /** Position of the illustration in `story.text`: the number of the paragraph it follows. */
  afterParagraph: number;
}

export interface GenerateStoryResponse {
  /** Id of the saved story, see GET /v1/stories/:id. */
  storyId?: string;
  story: {
    title?: string;
    /** Body paragraphs separated by blank lines; no title heading, moral or closing line. */
    text: string;
    moral?: string;
    closing?: string;
    readingMinutes: number;
  };
  media: MediaAsset[];
  usage: StoryUsage;
  mediaPlan: {
    requestedTypes: MediaType[];
    generatedTypes: MediaType[];
    note: string;
  };
  steps: PipelineStep[];
}

export interface ApiErrorResponse {
  error: {
    code: string;
    message: string;
  };
}

export interface ChildProfileInput {
  name: string;
  age: number;
  /** Absent means "not specified". */
  gender?: Gender;
  appearance?: Appearance;
  interests: string[];
  /** World ids, see WORLD_IDS. */
  worlds: WorldId[];
  favoriteCharacter?: string;
  language: string;
}

export interface ChildProfileDto extends ChildProfileInput {
  id: string;
  createdAt: string;
}

export interface AuthResponse {
  token: string;
  user: { id: string; email?: string; anonymous: boolean };
}

export interface StorySummary {
  id: string;
  title?: string;
  format: StoryFormat;
  world?: string;
  /** Saved profiles that are heroes of the story (the first is the main hero). */
  heroIds: string[];
  coverImageUrl?: string;
  readingMinutes: number;
  favorite: boolean;
  /** 0..1 */
  readProgress: number;
  createdAt: string;
}

export interface StoryPartDto {
  partNumber: number;
  text: string;
  media: MediaAsset[];
}

export interface StoryDto extends StorySummary {
  moral?: string;
  closing?: string;
  totalParts: number;
  parts: StoryPartDto[];
}

/** PATCH /v1/stories/:id */
export interface UpdateStoryRequest {
  favorite?: boolean;
  readProgress?: number;
}

export type Tier = "free" | "family" | "family_plus";

export type QuotaFeature = "classic_story" | "quick_story";

export type QuotaPeriod = "day" | "week" | "month";

export interface QuotaStatus {
  feature: QuotaFeature;
  period: QuotaPeriod;
  limit: number;
  used: number;
  /** ISO time when the counter resets. */
  resetsAt: string;
}

/** GET /v1/entitlements: everything the client needs to render the paywall and gate buttons. */
export interface EntitlementsResponse {
  tier: Tier;
  source: "subscription" | "trial" | "free";
  trialEndsAt?: string;
  limits: {
    profiles: { limit: number; used: number };
    activeArcs: number;
    imageQuality: "standard" | "hd";
  };
  quotas: QuotaStatus[];
}

/**
 * HTTP 402 body: the client should show the paywall. `feature` says what was blocked:
 * `profiles`, `story_arc`, `classic_story` or `quick_story`.
 */
export interface PaywallErrorResponse {
  error: {
    code: "limit_reached" | "upgrade_required";
    message: string;
    feature: string;
    tier: Tier;
    limit?: number;
    resetsAt?: string;
  };
}
