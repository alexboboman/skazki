import type {
  ChildProfile,
  GenerateStoryRequest,
  GenerateStoryResponse,
  MediaAsset,
  PipelineStep,
  PipelineStepName
} from "../../../../packages/shared/src/index.js";
import type { ImageGenerator } from "./imageGenerator.js";
import type { MediaStore } from "./mediaStore.js";
import { parseMediaMarkers, type ImageCue } from "./mediaPrompts.js";
import type { TextGenerator } from "./anthropicTextGenerator.js";

export interface StoryPipelineDeps {
  textGenerator: TextGenerator;
  imageGenerator: ImageGenerator;
  mediaStore: MediaStore;
}

/**
 * Step-based generation: generate_text -> parse_media_prompts -> generate_images.
 * A failed text step fails the request; a failed image step only drops the pictures.
 * Runs inline in the request for now; the same steps move into a BullMQ worker later.
 */
export async function runStoryPipeline(
  request: GenerateStoryRequest,
  deps: StoryPipelineDeps
): Promise<GenerateStoryResponse> {
  const steps: PipelineStep[] = [];
  const wantsImages = request.mediaOptions?.requestedTypes.includes("image") ?? false;

  const textResult = await timed(steps, "generate_text", "anthropic", () => deps.textGenerator.generateStory(request));

  const parsed = await timed(steps, "parse_media_prompts", undefined, async () => parseMediaMarkers(textResult.text));

  let media: MediaAsset[] = [];
  let imageCostUsd = 0;

  if (wantsImages && parsed.images.length > 0) {
    const quality = request.mediaOptions?.imageQuality ?? "standard";
    const generated = await generateImages(parsed.images, request.childProfile, quality, deps, steps);
    media = generated.media;
    imageCostUsd = generated.costUsd;
  } else {
    steps.push({ name: "generate_images", status: "skipped", durationMs: 0 });
  }

  const requestedTypes = request.mediaOptions?.requestedTypes ?? [];

  return {
    story: { title: textResult.title, text: parsed.text },
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

async function generateImages(
  cues: ImageCue[],
  profile: ChildProfile,
  quality: "standard" | "hd",
  deps: StoryPipelineDeps,
  steps: PipelineStep[]
): Promise<{ media: MediaAsset[]; costUsd: number }> {
  const startedAt = Date.now();
  const media: MediaAsset[] = [];
  let costUsd = 0;
  let firstError: string | undefined;

  // Sequential on purpose: keeps provider rate limits and cost predictable in the prototype.
  for (const cue of cues) {
    try {
      const prompt = buildIllustrationPrompt(cue.prompt, profile);
      const image = await deps.imageGenerator.generateImage({ prompt, quality });
      const stored = await deps.mediaStore.save(image.bytes, image.contentType);

      costUsd += image.estimatedCostUsd;
      media.push({
        id: stored.id,
        type: "image",
        variant: quality,
        provider: deps.imageGenerator.provider,
        url: stored.url,
        contentType: image.contentType,
        prompt,
        afterParagraph: cue.afterParagraph
      });
    } catch (error) {
      firstError ??= error instanceof Error ? error.message : "Unknown image generation error.";
    }
  }

  steps.push({
    name: "generate_images",
    status: media.length === cues.length ? "succeeded" : "failed",
    provider: deps.imageGenerator.provider,
    durationMs: Date.now() - startedAt,
    error: firstError
  });

  return { media, costUsd };
}

function buildIllustrationPrompt(scene: string, profile: ChildProfile): string {
  return `Children's book illustration, soft watercolor style, warm colors.
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
