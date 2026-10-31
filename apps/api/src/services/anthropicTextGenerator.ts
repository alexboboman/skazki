import type { ChildProfile, GenerateStoryRequest, GenerateStoryResponse } from "../../../../packages/shared/src/index.js";
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

export interface TextGenerator {
  generateStory(request: GenerateStoryRequest): Promise<GenerateStoryResponse>;
}

export class AnthropicTextGenerator implements TextGenerator {
  constructor(
    private readonly apiKey: string,
    private readonly model = process.env.ANTHROPIC_MODEL ?? "claude-haiku-4-5-20251001"
  ) {}

  async generateStory(request: GenerateStoryRequest): Promise<GenerateStoryResponse> {
    const system = buildSystemPrompt(request.childProfile, request.wordCount ?? 700);
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
        max_tokens: 1600,
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
      story: {
        title: extractMarkdownTitle(text),
        text
      },
      usage: {
        inputTokens,
        outputTokens,
        estimatedCostUsd: estimateHaikuCost(inputTokens, outputTokens)
      },
      mediaPlan: {
        requestedTypes: request.mediaOptions?.requestedTypes ?? [],
        generatedTypes: [],
        note: "API prototype generates text only. Media assets will be produced by the worker pipeline later."
      }
    };
  }
}

function buildSystemPrompt(childProfile: ChildProfile, wordCount: number): string {
  const favoriteCharacter = childProfile.favoriteCharacter
    ? `Любимый персонаж: ${childProfile.favoriteCharacter}.`
    : "Любимый персонаж не задан.";

  return `Ты — опытный детский писатель. Пиши сказки для детей возраста ${childProfile.age} лет.
Язык: ${childProfile.language}. Стиль: мягкий, добрый, с моральным выводом в конце.
Имя главного героя: ${childProfile.name}.
Мир: ${childProfile.world}.
Интересы ребёнка: ${childProfile.interests.join(", ")}.
${favoriteCharacter}
Длина: около ${wordCount} слов.
Не используй страшных, тёмных или жестоких элементов.
Придумай название сказки.`;
}

function buildUserPrompt(request: GenerateStoryRequest): string {
  const mediaNote = request.mediaOptions?.requestedTypes.length
    ? `Пока не генерируй медиа, но можешь отметить подходящие места для будущих медиа типов: ${request.mediaOptions.requestedTypes.join(", ")}.`
    : "Пиши только текст сказки, без изображений, аудио и видео.";

  return `Напиши сказку на ночь по профилю ребёнка.
Формат: ${request.format}.
${mediaNote}`;
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
