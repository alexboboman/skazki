import type { GenerateImageInput, GeneratedImage, ImageGenerator, ImageQuality } from "./imageGenerator.js";
import { PhygitalClient, type PhygitalClientOptions } from "./phygitalClient.js";

export interface PhygitalOptions extends PhygitalClientOptions {
  /** Model slug from https://dev.phygital.plus/api/models, e.g. gemini-image. */
  model?: string;
  /** `model_name` param per quality: the Lite model for standard, the Pro model for hd. */
  modelVersions?: Record<ImageQuality, string>;
  estimatedCostUsd?: Record<ImageQuality, number>;
}

/**
 * Images from Phygital+. Written for the `gemini-image` (Nano Banana) model;
 * other text-to-image models take different field names.
 */
export class PhygitalImageGenerator implements ImageGenerator {
  readonly provider = "phygital";
  private readonly client: PhygitalClient;
  private readonly model: string;
  private readonly modelVersions: Record<ImageQuality, string>;
  private readonly cost: Record<ImageQuality, number>;

  constructor(options: PhygitalOptions) {
    this.client = new PhygitalClient(options);
    this.model = options.model ?? "gemini-image";
    this.modelVersions = options.modelVersions ?? { standard: "v3_1_lite", hd: "v3" };
    this.cost = options.estimatedCostUsd ?? { standard: 0, hd: 0 };
  }

  async generateImage(input: GenerateImageInput): Promise<GeneratedImage> {
    const file = await this.client.run(
      this.model,
      { text_prompt: input.prompt },
      { model_name: this.modelVersions[input.quality], ratio: "r_1_1", resolution: "default", web_search: false },
      "image",
      "image/png"
    );
    return { ...file, estimatedCostUsd: this.cost[input.quality] };
  }
}
