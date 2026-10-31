import { postJson } from "./httpClient.js";

export interface SafetyVerdict {
  safe: boolean;
  reason?: string;
}

export interface SafetyChecker {
  check(input: { text: string; age: number; language: string }): Promise<SafetyVerdict>;
}

interface AnthropicMessageResponse {
  content?: Array<{ type: string; text?: string }>;
  error?: { message?: string };
}

const SYSTEM_PROMPT = `Ты — строгий редактор детской литературы. Тебе дают сказку и возраст ребёнка.
Сказка НЕ подходит, если в ней есть: насилие и жестокость, смерть персонажей, страшные или тревожные сцены, оружие, кровь, ругательства, сексуальные или романтические темы для взрослых, алкоголь, наркотики, запугивание, унижение, опасные для ребёнка действия, которые можно повторить, или призывы к ним. Страшная сцена, которая разрешается в той же сцене безобидно, допустима только для детей от 7 лет.
Сказка на ночь должна успокаивать, а не будоражить.
Ответь одним JSON-объектом без пояснений: {"safe": true|false, "reason": "краткая причина на русском, если safe=false"}.`;

export class AnthropicSafetyChecker implements SafetyChecker {
  constructor(
    private readonly apiKey: string,
    private readonly model = process.env.SAFETY_MODEL ?? process.env.ANTHROPIC_MODEL ?? "claude-haiku-4-5-20251001"
  ) {}

  async check(input: { text: string; age: number; language: string }): Promise<SafetyVerdict> {
    const res = await postJson(
      "https://api.anthropic.com/v1/messages",
      {
        "x-api-key": this.apiKey,
        "anthropic-version": "2023-06-01",
        "content-type": "application/json"
      },
      {
        model: this.model,
        max_tokens: 200,
        system: SYSTEM_PROMPT,
        messages: [
          {
            role: "user",
            content: `Возраст ребёнка: ${input.age}. Язык: ${input.language}.\n\nСказка:\n${input.text}`
          }
        ]
      }
    );

    let data: AnthropicMessageResponse;

    try {
      data = JSON.parse(res.rawBody) as AnthropicMessageResponse;
    } catch {
      throw new Error(`Safety check returned non-JSON response: ${res.rawBody.slice(0, 200)}`);
    }

    if (!res.ok || data.error) {
      throw new Error(data.error?.message ?? `Safety check API returned HTTP ${res.status}`);
    }

    return parseVerdict(data.content?.find((item) => item.type === "text")?.text ?? "");
  }
}

/** Fail closed: anything that is not a clear `{"safe": true}` counts as unsafe. */
export function parseVerdict(raw: string): SafetyVerdict {
  const json = raw.match(/\{[\s\S]*\}/)?.[0];

  if (!json) {
    return { safe: false, reason: "Safety verdict could not be parsed." };
  }

  try {
    const parsed = JSON.parse(json) as { safe?: unknown; reason?: unknown };
    const reason = typeof parsed.reason === "string" ? parsed.reason : undefined;
    return parsed.safe === true ? { safe: true } : { safe: false, reason: reason ?? "Rejected by safety check." };
  } catch {
    return { safe: false, reason: "Safety verdict could not be parsed." };
  }
}
