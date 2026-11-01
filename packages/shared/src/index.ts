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

/** Number of parts a series can have. The app offers the short ones first. */
export const ARC_LENGTHS = [3, 5, 7, 14, 30] as const;

export type ArcLength = (typeof ARC_LENGTHS)[number];

/** What the text generator needs to write one part of a series that holds together. */
export interface ArcContext {
  length: number;
  /** 1-based number of the part being written. */
  partNumber: number;
  /** Title of the series, once part 1 has named it. */
  title?: string;
  /** Short English description of the recurring characters and the setting, written with part 1. */
  seed?: string;
  /** Summaries of the latest parts before this one, oldest first. */
  previousSummaries: string[];
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
  /** Set for parts of a series. */
  arc?: ArcContext;
}

/** Reading length choices of the "Сочинить" screen. */
export type LengthMinutes = 4 | 7 | 12;

/**
 * Body of POST /v1/stories/generate: one to three saved `profileIds` (the first is the main hero)
 * or an inline `childProfile`. `world` overrides the hero's world for this story;
 * `lengthMinutes` is turned into a word count unless `wordCount` is given.
 */
export type GenerateStoryBody = Omit<GenerateStoryRequest, "childProfile" | "companions" | "arc"> & {
  world?: WorldId;
  lengthMinutes?: LengthMinutes;
  /** Required for `story_arc_part`: how many parts the series has. Starts the series with its part 1. */
  arcLength?: ArcLength;
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

export interface StoryArcInfo {
  /** Parts the series will have. */
  length: number;
  /** Parts written so far. */
  partsReady: number;
  status: "active" | "completed";
}

export interface GenerateStoryResponse {
  /** Id of the saved story, see GET /v1/stories/:id. */
  storyId?: string;
  /** Number of the part this response holds (series only). */
  partNumber?: number;
  arc?: StoryArcInfo;
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
  /** Present for a series. */
  arc?: StoryArcInfo;
  createdAt: string;
}

export interface StoryPartDto {
  partNumber: number;
  /** Name of this part (series only). */
  title?: string;
  text: string;
  /** Good-night line of this part (series only; a single story keeps it on the story). */
  closing?: string;
  read: boolean;
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
  /** Marks this part of a series as read; readProgress then follows the share of read parts. */
  readPart?: number;
}

export type Tier = "free" | "family" | "family_plus";

/**
 * App Store product ids of the auto-renewable subscriptions (one subscription group, so a user holds one at a time)
 * and the tier each one unlocks. The same ids are created in App Store Connect and in the app's StoreKit file.
 */
export const SUBSCRIPTION_PRODUCT_TIERS = {
  family_monthly: "family",
  family_yearly: "family",
  family_plus_monthly: "family_plus",
  family_plus_yearly: "family_plus"
} as const satisfies Record<string, Exclude<Tier, "free">>;

export type SubscriptionProductId = keyof typeof SUBSCRIPTION_PRODUCT_TIERS;

/** POST /v1/subscription/sync: signed transactions (`jwsRepresentation`) from StoreKit 2; answered with EntitlementsResponse. */
export interface SyncSubscriptionRequest {
  transactions: string[];
}

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
    /** How many series can be unfinished at once. */
    activeArcs: number;
    activeArcsUsed?: number;
    imageQuality: "standard" | "hd";
    /** Neural narration (POST /v1/stories/:id/audio); the system voice on the device needs no plan. */
    premiumVoice?: boolean;
  };
  quotas: QuotaStatus[];
}

/**
 * HTTP 402 body: the client should show the paywall. `feature` says what was blocked:
 * `profiles`, `story_arc`, `classic_story`, `quick_story` or `premium_voice`. For `story_arc` with `limit_reached` the user
 * already has `limit` unfinished series.
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
