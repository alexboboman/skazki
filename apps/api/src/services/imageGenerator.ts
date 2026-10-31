import { postJson } from "./httpClient.js";
import { PhygitalImageGenerator } from "./phygitalImageGenerator.js";

export type ImageQuality = "standard" | "hd";

export interface GenerateImageInput {
  prompt: string;
  quality: ImageQuality;
}

export interface GeneratedImage {
  bytes: Buffer;
  contentType: string;
  estimatedCostUsd: number;
}

export interface ImageGenerator {
  readonly provider: string;
  generateImage(input: GenerateImageInput): Promise<GeneratedImage>;
}

interface OpenAIImageResponse {
  data?: Array<{ b64_json?: string }>;
  error?: { message?: string };
}

// Approximate gpt-image-1 prices for a 1024x1024 image, USD.
const OPENAI_COST_USD: Record<ImageQuality, number> = { standard: 0.042, hd: 0.167 };
const OPENAI_QUALITY: Record<ImageQuality, string> = { standard: "medium", hd: "high" };

export class OpenAIImageGenerator implements ImageGenerator {
  readonly provider = "openai";

  constructor(
    private readonly apiKey: string,
    private readonly model = process.env.OPENAI_IMAGE_MODEL ?? "gpt-image-1"
  ) {}

  async generateImage(input: GenerateImageInput): Promise<GeneratedImage> {
    const res = await postJson(
      "https://api.openai.com/v1/images/generations",
      {
        authorization: `Bearer ${this.apiKey}`,
        "content-type": "application/json"
      },
      {
        model: this.model,
        prompt: input.prompt,
        size: "1024x1024",
        quality: OPENAI_QUALITY[input.quality],
        output_format: "webp",
        output_compression: 80,
        n: 1
      }
    );

    const data = parseOpenAIResponse(res.rawBody);

    if (!res.ok || data.error) {
      throw new Error(data.error?.message ?? `OpenAI Images API returned HTTP ${res.status}`);
    }

    const b64 = data.data?.[0]?.b64_json;

    if (!b64) {
      throw new Error("OpenAI Images API response did not include an image.");
    }

    return {
      bytes: Buffer.from(b64, "base64"),
      contentType: "image/webp",
      estimatedCostUsd: OPENAI_COST_USD[input.quality]
    };
  }
}

/** Offline placeholder so the pipeline can run end to end without an image API key. */
export class MockImageGenerator implements ImageGenerator {
  readonly provider = "mock";

  async generateImage(input: GenerateImageInput): Promise<GeneratedImage> {
    const caption = escapeXml(input.prompt.slice(0, 120));
    const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <rect width="1024" height="1024" fill="#f3e9d8"/>
  <text x="512" y="480" font-family="sans-serif" font-size="40" text-anchor="middle" fill="#7a5c3a">Mock illustration</text>
  <text x="512" y="540" font-family="sans-serif" font-size="22" text-anchor="middle" fill="#7a5c3a">${caption}</text>
</svg>`;

    return { bytes: Buffer.from(svg, "utf8"), contentType: "image/svg+xml", estimatedCostUsd: 0 };
  }
}

export function createImageGenerator(env: NodeJS.ProcessEnv = process.env): ImageGenerator {
  const provider = env.IMAGE_PROVIDER || (env.PHYGITAL_API_KEY ? "phygital" : env.OPENAI_API_KEY ? "openai" : "mock");

  if (provider === "phygital") {
    if (!env.PHYGITAL_API_KEY) {
      throw new Error("IMAGE_PROVIDER=phygital requires PHYGITAL_API_KEY.");
    }
    return new PhygitalImageGenerator({
      apiKey: env.PHYGITAL_API_KEY,
      baseUrl: env.PHYGITAL_BASE_URL || undefined,
      model: env.PHYGITAL_IMAGE_MODEL || undefined,
      modelVersions:
        env.PHYGITAL_MODEL_STANDARD || env.PHYGITAL_MODEL_HD
          ? { standard: env.PHYGITAL_MODEL_STANDARD || "v3_1_lite", hd: env.PHYGITAL_MODEL_HD || "v3" }
          : undefined
    });
  }

  if (provider === "openai") {
    if (!env.OPENAI_API_KEY) {
      throw new Error("IMAGE_PROVIDER=openai requires OPENAI_API_KEY.");
    }
    return new OpenAIImageGenerator(env.OPENAI_API_KEY);
  }

  if (provider === "mock") {
    return new MockImageGenerator();
  }

  throw new Error(`Unknown IMAGE_PROVIDER "${provider}". Use phygital, openai or mock.`);
}

function parseOpenAIResponse(rawBody: string): OpenAIImageResponse {
  try {
    return JSON.parse(rawBody) as OpenAIImageResponse;
  } catch {
    throw new Error(`OpenAI Images API returned non-JSON response: ${rawBody.slice(0, 200)}`);
  }
}

function escapeXml(value: string): string {
  return value.replace(/[<>&"']/g, (char) => `&#${char.charCodeAt(0)};`);
}
