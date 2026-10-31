import { PhygitalClient, type PhygitalClientOptions } from "./phygitalClient.js";

export interface GenerateSpeechInput {
  text: string;
}

export interface GeneratedSpeech {
  bytes: Buffer;
  contentType: string;
  estimatedCostUsd: number;
}

/** Turns text into a narration file. One call takes a limited amount of text, see `splitForSpeech`. */
export interface SpeechGenerator {
  readonly provider: string;
  /** Characters one call can take. */
  readonly maxChars: number;
  generateSpeech(input: GenerateSpeechInput): Promise<GeneratedSpeech>;
}

export interface PhygitalSpeechOptions extends PhygitalClientOptions {
  /** Model slug, see https://dev.phygital.plus/api/models. */
  model?: string;
  /** Gemini model behind the slug. */
  engine?: string;
  voice?: string;
  languageCode?: string;
  /** How to read: a plain-words instruction that Gemini TTS follows. */
  style?: string;
  speakingRate?: number;
  estimatedCostUsd?: number;
}

export const DEFAULT_NARRATION_STYLE =
  "Читай как добрая мама сказку на ночь: тихо, тепло, неторопливо, с мягкой улыбкой в голосе.";

/** Gemini TTS through Phygital+. The voice was picked by ear (Aoede on the Pro model, read as a bedtime story). */
export class PhygitalSpeechGenerator implements SpeechGenerator {
  readonly provider = "phygital";
  /** Voicing takes about 8 s per 100 characters, so a story is cut into short pieces that run side by side. */
  readonly maxChars = 600;
  private readonly client: PhygitalClient;
  private readonly options: Required<Omit<PhygitalSpeechOptions, keyof PhygitalClientOptions>>;

  constructor(options: PhygitalSpeechOptions) {
    this.client = new PhygitalClient({ timeoutMs: 240_000, ...options });
    this.options = {
      model: options.model ?? "gemini-tts",
      engine: options.engine ?? "gemini_2_5_pro_tts",
      voice: options.voice ?? "Aoede",
      languageCode: options.languageCode ?? "ru_RU",
      style: options.style ?? DEFAULT_NARRATION_STYLE,
      speakingRate: options.speakingRate ?? 1,
      estimatedCostUsd: options.estimatedCostUsd ?? 0
    };
  }

  async generateSpeech(input: GenerateSpeechInput): Promise<GeneratedSpeech> {
    const file = await this.client.run(
      this.options.model,
      { text: input.text, prompt: this.options.style },
      {
        model: this.options.engine,
        voice: this.options.voice,
        language_code: this.options.languageCode,
        audio_encoding: "MP3",
        speaking_rate: this.options.speakingRate
      },
      "audio",
      "audio/mpeg"
    );
    return { ...file, estimatedCostUsd: this.options.estimatedCostUsd };
  }
}

/** Absent without a Phygital+ key: premium voice is then reported as unavailable. `TTS_PROVIDER=none` switches it off. */
export function createSpeechGenerator(env: NodeJS.ProcessEnv = process.env): SpeechGenerator | undefined {
  const provider = env.TTS_PROVIDER || (env.PHYGITAL_API_KEY ? "phygital" : "none");

  if (provider === "none") {
    return undefined;
  }

  if (provider !== "phygital") {
    throw new Error(`Unknown TTS_PROVIDER "${provider}". Use phygital or none.`);
  }

  if (!env.PHYGITAL_API_KEY) {
    throw new Error("TTS_PROVIDER=phygital requires PHYGITAL_API_KEY.");
  }

  return new PhygitalSpeechGenerator({
    apiKey: env.PHYGITAL_API_KEY,
    baseUrl: env.PHYGITAL_BASE_URL || undefined,
    model: env.PHYGITAL_TTS_MODEL || undefined,
    engine: env.PHYGITAL_TTS_ENGINE || undefined,
    voice: env.PHYGITAL_TTS_VOICE || undefined,
    languageCode: env.PHYGITAL_TTS_LANGUAGE || undefined,
    style: env.PHYGITAL_TTS_STYLE || undefined
  });
}
