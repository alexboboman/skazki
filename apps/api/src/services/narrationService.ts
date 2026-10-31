import type { MediaAsset } from "../../../../packages/shared/src/index.js";
import type { MediaStore } from "./mediaStore.js";
import { splitForSpeech } from "./narrationText.js";
import type { SpeechGenerator } from "./speechGenerator.js";
import type { StoryService } from "./storyService.js";

export type NarrationResult = { status: "ready"; audio: MediaAsset } | { status: "processing" };

/** Pieces of one story voiced at the same time; the provider takes minutes for a long text, seconds for a short one. */
const PARALLEL_PIECES = 6;

/**
 * Premium narration of one part of a story. Voicing takes from half a minute to a few minutes, so a request
 * starts the work and waits only a moment: if the file is not ready the answer is "processing" and the
 * client asks again. The finished file is stored like a picture and attached to the part, so every later
 * request (and every device) gets the same file.
 */
export class NarrationService {
  /** Parts being voiced right now; repeated requests join the same work. */
  private readonly inflight = new Map<string, Promise<MediaAsset>>();
  /** Why the last attempt for a part failed, handed to the next request once. */
  private readonly failures = new Map<string, string>();

  constructor(
    private readonly stories: StoryService,
    private readonly store: MediaStore,
    private readonly speech: SpeechGenerator,
    /** How long a request waits for a result before answering "processing". */
    private readonly waitMs = 2500
  ) {}

  /** The narration of a part; undefined when the story or the part does not exist (or is not the user's). */
  async request(userId: string, storyId: string, partNumber: number): Promise<NarrationResult | undefined> {
    const source = await this.stories.narrationSource(userId, storyId, partNumber);

    if (!source) {
      return undefined;
    }

    if (source.audio) {
      return { status: "ready", audio: source.audio };
    }

    const failure = this.failures.get(source.partId);

    if (failure) {
      this.failures.delete(source.partId);
      throw new Error(failure);
    }

    let job = this.inflight.get(source.partId);

    if (!job) {
      job = this.generate(source.partId, source.text);
      this.inflight.set(source.partId, job);
      job
        .catch((error: unknown) => this.failures.set(source.partId, error instanceof Error ? error.message : "Unknown narration error."))
        .finally(() => this.inflight.delete(source.partId));
    }

    try {
      const finished = await Promise.race([job.then((audio) => ({ audio })), sleep(this.waitMs).then(() => undefined)]);
      return finished ? { status: "ready", audio: finished.audio } : { status: "processing" };
    } catch (error) {
      // This request sees the failure itself, so it is not kept for the next one.
      this.failures.delete(source.partId);
      throw error;
    }
  }

  private async generate(partId: string, text: string): Promise<MediaAsset> {
    const pieces = splitForSpeech(text, this.speech.maxChars);
    const spoken = await mapWithLimit(pieces, PARALLEL_PIECES, (piece) => this.speech.generateSpeech({ text: piece }));
    const bytes = Buffer.concat(spoken.map((item, index) => (index === 0 ? item.bytes : stripId3(item.bytes))));
    const contentType = spoken[0].contentType;
    const stored = await this.store.save(bytes, contentType);

    const asset: MediaAsset = {
      id: stored.id,
      type: "audio",
      variant: "standard",
      provider: this.speech.provider,
      url: stored.url,
      contentType,
      prompt: "",
      afterParagraph: 0
    };

    await this.stories.addAudio(partId, asset);
    return asset;
  }
}

async function mapWithLimit<T, R>(items: T[], limit: number, run: (item: T) => Promise<R>): Promise<R[]> {
  const results = new Array<R>(items.length);
  let next = 0;

  await Promise.all(
    Array.from({ length: Math.min(limit, items.length) }, async () => {
      while (next < items.length) {
        const index = next++;
        results[index] = await run(items[index]);
      }
    })
  );

  return results;
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

/** The ID3v2 tag at the start of an MP3 chunk would sit in the middle of the joined file. */
export function stripId3(bytes: Buffer): Buffer {
  if (bytes.length > 10 && bytes.toString("latin1", 0, 3) === "ID3") {
    const size = ((bytes[6] & 0x7f) << 21) | ((bytes[7] & 0x7f) << 14) | ((bytes[8] & 0x7f) << 7) | (bytes[9] & 0x7f);
    return bytes.subarray(10 + size);
  }

  return bytes;
}
