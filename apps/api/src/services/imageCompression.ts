import sharp from "sharp";
import type { GenerateImageInput, GeneratedImage, ImageGenerator } from "./imageGenerator.js";

const RASTER_TYPES = new Set(["image/png", "image/jpeg"]);

export interface CompressionOptions {
  /** Longest side in pixels; larger pictures are scaled down, smaller ones are left alone. */
  maxSide?: number;
  quality?: number;
}

/**
 * Wraps a provider and re-encodes its PNG/JPEG pictures as WebP: a 2 MB Phygital+ PNG becomes
 * about 100-200 KB, which matters on a phone. Other formats (the mock's SVG, WebP) pass through,
 * and if encoding fails the original picture is kept: a heavy picture beats a missing one.
 */
export class CompressingImageGenerator implements ImageGenerator {
  constructor(
    private readonly inner: ImageGenerator,
    private readonly options: CompressionOptions = {}
  ) {}

  get provider(): string {
    return this.inner.provider;
  }

  async generateImage(input: GenerateImageInput): Promise<GeneratedImage> {
    const image = await this.inner.generateImage(input);

    if (!RASTER_TYPES.has(image.contentType)) {
      return image;
    }

    try {
      const bytes = await sharp(image.bytes)
        .resize({ width: this.options.maxSide ?? 1280, height: this.options.maxSide ?? 1280, fit: "inside", withoutEnlargement: true })
        .webp({ quality: this.options.quality ?? 82 })
        .toBuffer();

      return { ...image, bytes, contentType: "image/webp" };
    } catch (error) {
      console.warn(`Image compression skipped: ${error instanceof Error ? error.message : error}`);
      return image;
    }
  }
}
