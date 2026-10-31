import type {
  ChildProfile,
  GenerateStoryRequest,
  GenerateStoryResponse,
  MediaAsset,
  PipelineStep,
  PipelineStepName
} from "../../../../packages/shared/src/index.js";
import { describeHero, readingMinutes } from "./catalog.js";
import type { ImageGenerator } from "./imageGenerator.js";
import type { MediaStore } from "./mediaStore.js";
import { parseMediaMarkers, type ImageCue } from "./mediaPrompts.js";
import type { TextGenerator, TextResult } from "./anthropicTextGenerator.js";
import type { SafetyChecker } from "./safetyChecker.js";

export interface StoryPipelineDeps {
  textGenerator: TextGenerator;
  safetyChecker: SafetyChecker;
  imageGenerator: ImageGenerator;
  mediaStore: MediaStore;
}

export class UnsafeStoryError extends Error {}

/** The text is regenerated this many times when the safety check rejects it. */
const SAFETY_RETRIES = 1;

/**
 * Step-based generation: generate_text -> safety_check -> parse_media_prompts -> generate_images.
 * A failed text or safety step fails the request (the safety check fails closed); a failed image
 * step only drops the pictures.
 * Runs inline in the request for now; the same steps move into a BullMQ worker later.
 */
export async function runStoryPipeline(
  request: GenerateStoryRequest,
  deps: StoryPipelineDeps
): Promise<GenerateStoryResponse> {
  const steps: PipelineStep[] = [];
  const wantsImages = request.mediaOptions?.requestedTypes.includes("image") ?? false;

  const textResult = await generateSafeText(request, deps, steps);

  const parsed = await timed(steps, "parse_media_prompts", undefined, async () => parseMediaMarkers(textResult.text));

  let media: MediaAsset[] = [];
  let imageCostUsd = 0;

  if (wantsImages && parsed.images.length > 0) {
    const quality = request.mediaOptions?.imageQuality ?? "standard";
    const heroes = [request.childProfile, ...(request.companions ?? [])];
    const generated = await generateImages(parsed.images, request.childProfile, heroes, quality, deps, steps);
    media = generated.media;
    imageCostUsd = generated.costUsd;
  } else {
    steps.push({ name: "generate_images", status: "skipped", durationMs: 0 });
  }

  const requestedTypes = request.mediaOptions?.requestedTypes ?? [];

  return {
    story: {
      title: parsed.title ?? textResult.title,
      text: parsed.text,
      moral: parsed.moral,
      closing: parsed.closing,
      readingMinutes: readingMinutes([parsed.text, parsed.moral, parsed.closing].filter(Boolean).join(" "))
    },
    media,
    usage: {
      ...textResult.usage,
      estimatedCostUsd: textResult.usage.estimatedCostUsd + imageCostUsd
    },
    mediaPlan: {
      requestedTypes,
      generatedTypes: media.length > 0 ? ["image"] : [],
      note: mediaNote(requestedTypes, media.length, steps)
    },
    steps
  };
}

async function generateSafeText(
  request: GenerateStoryRequest,
  deps: StoryPipelineDeps,
  steps: PipelineStep[]
): Promise<TextResult> {
  let usage = { inputTokens: 0, outputTokens: 0, estimatedCostUsd: 0 };
  let lastReason: string | undefined;

  for (let attempt = 0; attempt <= SAFETY_RETRIES; attempt++) {
    const text = await timed(steps, "generate_text", "anthropic", () => deps.textGenerator.generateStory(request));
    usage = {
      inputTokens: usage.inputTokens + text.usage.inputTokens,
      outputTokens: usage.outputTokens + text.usage.outputTokens,
      estimatedCostUsd: usage.estimatedCostUsd + text.usage.estimatedCostUsd
    };

    const startedAt = Date.now();
    let verdict;

    try {
      verdict = await deps.safetyChecker.check({
        text: text.text,
        age: request.childProfile.age,
        language: request.childProfile.language
      });
    } catch (error) {
      steps.push({
        name: "safety_check",
        status: "failed",
        provider: "anthropic",
        durationMs: Date.now() - startedAt,
        error: error instanceof Error ? error.message : "Unknown error."
      });
      throw error;
    }

    steps.push({
      name: "safety_check",
      status: verdict.safe ? "succeeded" : "failed",
      provider: "anthropic",
      durationMs: Date.now() - startedAt,
      error: verdict.safe ? undefined : verdict.reason
    });

    if (verdict.safe) {
      return { ...text, usage };
    }

    lastReason = verdict.reason;
  }

  throw new UnsafeStoryError(`Story was rejected by the safety check: ${lastReason ?? "unsafe content"}`);
}

async function generateImages(
  cues: ImageCue[],
  profile: ChildProfile,
  heroes: ChildProfile[],
  quality: "standard" | "hd",
  deps: StoryPipelineDeps,
  steps: PipelineStep[]
): Promise<{ media: MediaAsset[]; costUsd: number }> {
  const startedAt = Date.now();
  let firstError: string | undefined;

  // Pictures are independent, and a provider call takes seconds, so they run side by side (a story has
  // two or three). Results keep the order of the illustration markers.
  const results = await Promise.all(
    cues.map(async (cue): Promise<{ asset: MediaAsset; costUsd: number } | undefined> => {
      try {
        const prompt = buildIllustrationPrompt(cue.prompt, profile, heroes);
        const image = await deps.imageGenerator.generateImage({ prompt, quality });
        const stored = await deps.mediaStore.save(image.bytes, image.contentType);

        return {
          costUsd: image.estimatedCostUsd,
          asset: {
            id: stored.id,
            type: "image",
            variant: quality,
            provider: deps.imageGenerator.provider,
            url: stored.url,
            contentType: image.contentType,
            prompt,
            afterParagraph: cue.afterParagraph
          }
        };
      } catch (error) {
        firstError ??= error instanceof Error ? error.message : "Unknown image generation error.";
        return undefined;
      }
    })
  );

  const done = results.filter((result): result is { asset: MediaAsset; costUsd: number } => result !== undefined);
  const media = done.map((result) => result.asset);
  const costUsd = done.reduce((sum, result) => sum + result.costUsd, 0);

  steps.push({
    name: "generate_images",
    status: media.length === cues.length ? "succeeded" : "failed",
    provider: deps.imageGenerator.provider,
    durationMs: Date.now() - startedAt,
    error: firstError
  });

  return { media, costUsd };
}

/** The look of every hero is fixed here, not left to the model, so they stay the same in all pictures. */
function buildIllustrationPrompt(scene: string, profile: ChildProfile, heroes: ChildProfile[]): string {
  return `Children's book illustration, soft watercolor style, warm colors.
Characters: ${heroes.map(describeHero).join("; ")}.
Scene: ${scene}.
World: ${profile.world}.
Age-appropriate, gentle, no scary elements, no text or letters in the image.
Style: Studio Ghibli inspired, storybook.`;
}

async function timed<T>(
  steps: PipelineStep[],
  name: PipelineStepName,
  provider: string | undefined,
  run: () => Promise<T>
): Promise<T> {
  const startedAt = Date.now();

  try {
    const result = await run();
    steps.push({ name, status: "succeeded", provider, durationMs: Date.now() - startedAt });
    return result;
  } catch (error) {
    steps.push({
      name,
      status: "failed",
      provider,
      durationMs: Date.now() - startedAt,
      error: error instanceof Error ? error.message : "Unknown error."
    });
    throw error;
  }
}

function mediaNote(requestedTypes: string[], generatedImages: number, steps: PipelineStep[]): string {
  const imageStep = steps.find((step) => step.name === "generate_images");

  if (imageStep?.status === "failed") {
    return `Generated ${generatedImages} image(s); some illustrations failed: ${imageStep.error}`;
  }

  if (generatedImages > 0) {
    return "Text and images generated. Audio and video are not implemented yet.";
  }

  if (requestedTypes.includes("image")) {
    return "Images were requested, but the story text contained no illustration markers.";
  }

  return requestedTypes.length > 0
    ? "Only image generation is implemented; audio and video requests are ignored."
    : "Text only.";
}
