import type { ChildProfile, GenerateStoryRequest, StoryUsage } from "../../../../packages/shared/src/index.js";
import { postJson } from "./httpClient.js";

interface AnthropicMessageResponse {
  content?: Array<{ type: string; text?: string }>;
  usage?: {
    input_tokens?: number;
    output_tokens?: number;
  };
  error?: {
    type?: string;
    message?: string;
  };
}

export interface TextResult {
  title?: string;
  /** Raw model output: may still contain [IMAGE: ...] style media markers. */
  text: string;
  usage: StoryUsage;
}

export interface TextGenerator {
  generateStory(request: GenerateStoryRequest): Promise<TextResult>;
}

const IMAGES_PER_FORMAT: Record<GenerateStoryRequest["format"], number> = {
  quick_story: 3,
  classic_story: 3,
  story_arc_part: 2
};

export class AnthropicTextGenerator implements TextGenerator {
  constructor(
    private readonly apiKey: string,
    private readonly model = process.env.ANTHROPIC_MODEL ?? "claude-haiku-4-5-20251001"
  ) {}

  async generateStory(request: GenerateStoryRequest): Promise<TextResult> {
    const wordCount = request.wordCount ?? 700;
    const system = buildSystemPrompt(request, wordCount);
    const userPrompt = buildUserPrompt(request);

    const res = await postJson(
      "https://api.anthropic.com/v1/messages",
      {
        "x-api-key": this.apiKey,
        "anthropic-version": "2023-06-01",
        "content-type": "application/json"
      },
      {
        model: this.model,
        max_tokens: Math.ceil(wordCount * 3.5) + 400,
        system,
        messages: [{ role: "user", content: userPrompt }]
      }
    );

    const data = parseAnthropicResponse(res.rawBody);

    if (!res.ok || data.error) {
      const message = data.error?.message ?? `Anthropic API returned HTTP ${res.status}`;
      throw new Error(message);
    }

    const text = data.content?.find((item) => item.type === "text")?.text;

    if (!text) {
      throw new Error("Anthropic API response did not include story text.");
    }

    const inputTokens = data.usage?.input_tokens ?? 0;
    const outputTokens = data.usage?.output_tokens ?? 0;

    return {
      title: extractMarkdownTitle(text),
      text,
      usage: {
        inputTokens,
        outputTokens,
        estimatedCostUsd: estimateHaikuCost(inputTokens, outputTokens)
      }
    };
  }
}

function buildSystemPrompt(request: GenerateStoryRequest, wordCount: number): string {
  const heroes = [request.childProfile, ...(request.companions ?? [])];
  // The story must suit the youngest listener.
  const age = Math.min(...heroes.map((hero) => hero.age));

  return `Ты — опытный детский писатель. Пиши сказки для детей возраста ${age} лет.
Язык: ${request.childProfile.language}. Стиль: мягкий, добрый, успокаивающий — это сказка на ночь.
${heroes.length > 1 ? "Главные герои — дети, все они действуют в сказке вместе:" : "Главный герой — ребёнок:"}
${heroes.map(describeHeroRu).join("\n")}
Мир: ${request.childProfile.world}.
${request.topic ? `Тема сказки: ${request.topic}.` : "Тема — на твой выбор, добрая и волшебная."}
Длина: около ${wordCount} слов.
Не используй страшных, тёмных или жестоких элементов.
Придумай название сказки и поставь его первой строкой в виде "# Название".
Мораль и финальное пожелание не пиши в тексте сказки, а выдай отдельными маркерами в самом конце, каждый с новой строки:
[MORAL: одно-два предложения о том, чему учит сказка]
[CLOSING: короткое пожелание спокойной ночи]`;
}

function describeHeroRu(hero: ChildProfile): string {
  const gender = hero.gender === "boy" ? "мальчик" : hero.gender === "girl" ? "девочка" : undefined;
  const parts = [
    `- ${hero.name}`,
    `${hero.age} ${hero.age === 1 ? "год" : hero.age < 5 ? "года" : "лет"}`,
    ...(gender ? [`${gender}, согласуй местоимения`] : []),
    ...(hero.interests.length ? [`любит: ${hero.interests.join(", ")}`] : []),
    ...(hero.favoriteCharacter ? [`любимый персонаж: ${hero.favoriteCharacter}`] : [])
  ];
  return parts.join(", ");
}

function buildUserPrompt(request: GenerateStoryRequest): string {
  const requested = request.mediaOptions?.requestedTypes ?? [];
  const notes: string[] = [];

  if (requested.includes("image")) {
    notes.push(
      `Расставь ровно ${IMAGES_PER_FORMAT[request.format]} маркера иллюстраций, каждый отдельной строкой после абзаца, который он иллюстрирует: [IMAGE: short scene description in English].`,
      "В каждом маркере описывай только сцену и действие, внешность героев уже известна художнику и добавляется автоматически.",
      "Не вставляй маркеры в заголовок и в последний абзац."
    );
  }

  if (requested.includes("audio")) {
    notes.push("Можешь добавить один маркер [AUDIO_CUE: calm bedtime narration notes]. Он пока не используется.");
  }

  if (requested.includes("video")) {
    notes.push("Можешь добавить один маркер [VIDEO_CUE: short animated scene idea]. Он пока не используется.");
  }

  if (notes.length === 0) {
    notes.push("Пиши только текст сказки, без изображений, аудио и видео.");
  }

  return `Напиши сказку на ночь по профилю ребёнка.
Формат: ${request.format}.
${notes.join("\n")}`;
}

function parseAnthropicResponse(rawBody: string): AnthropicMessageResponse {
  try {
    return JSON.parse(rawBody) as AnthropicMessageResponse;
  } catch {
    throw new Error(`Anthropic API returned non-JSON response: ${rawBody}`);
  }
}

function extractMarkdownTitle(text: string): string | undefined {
  const firstLine = text.split("\n").find((line) => line.trim().length > 0);
  return firstLine?.replace(/^#+\s*/, "").trim();
}

function estimateHaikuCost(inputTokens: number, outputTokens: number): number {
  return inputTokens * 0.0000008 + outputTokens * 0.000004;
}
