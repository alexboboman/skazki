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

export interface StoryUsage {
  inputTokens: number;
  outputTokens: number;
  estimatedCostUsd: number;
}

export interface GenerateStoryResponse {
  story: {
    title?: string;
    text: string;
  };
  usage: StoryUsage;
  mediaPlan: {
    requestedTypes: MediaType[];
    generatedTypes: MediaType[];
    note: string;
  };
}

export interface ApiErrorResponse {
  error: {
    code: string;
    message: string;
  };
}
