export type StoryFormat = "quick_story" | "classic_story" | "story_arc_part";

export type MediaType = "image" | "audio" | "video";

export interface ChildProfile {
  name: string;
  age: number;
  language: string;
  interests: string[];
  world: string;
  favoriteCharacter?: string;
}

export interface MediaOptions {
  requestedTypes: MediaType[];
  imageQuality?: "standard" | "hd";
  audioVoice?: "on_device" | "premium";
}

export interface GenerateStoryRequest {
  childProfile: ChildProfile;
  format: StoryFormat;
  wordCount?: number;
  mediaOptions?: MediaOptions;
}

/** Body of POST /v1/stories/generate: a saved `profileId` or an inline `childProfile`. */
export type GenerateStoryBody = Omit<GenerateStoryRequest, "childProfile"> &
  ({ profileId: string; childProfile?: undefined } | { profileId?: undefined; childProfile: ChildProfile });

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
    text: string;
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
  gender?: string;
  interests: string[];
  worlds: string[];
  favoriteCharacter?: string;
  language: string;
}

export interface ChildProfileDto extends ChildProfileInput {
  id: string;
  createdAt: string;
}

export interface AuthResponse {
  token: string;
  user: { id: string; email?: string };
}

export interface StorySummary {
  id: string;
  title?: string;
  format: StoryFormat;
  childProfileId?: string;
  coverImageUrl?: string;
  createdAt: string;
}

export interface StoryPartDto {
  partNumber: number;
  text: string;
  media: MediaAsset[];
}

export interface StoryDto extends StorySummary {
  totalParts: number;
  parts: StoryPartDto[];
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
