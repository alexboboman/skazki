import type { GenerateStoryRequest } from "../../../../packages/shared/src/index.js";
import type { TextGenerator, TextResult } from "./anthropicTextGenerator.js";
import type { SafetyChecker } from "./safetyChecker.js";

/** Offline stand-in for Claude so the app and the API can be tried without keys (TEXT_PROVIDER=mock, never in production). */
export class MockTextGenerator implements TextGenerator {
  async generateStory(request: GenerateStoryRequest): Promise<TextResult> {
    const heroes = [request.childProfile, ...(request.companions ?? [])];
    const names = heroes.map((hero) => hero.name).join(" и ");
    const first = heroes[0].name;
    const topic = request.topic ? ` Сегодня сказка была о том, что важно: ${request.topic.toLowerCase()}.` : "";
    const title = `${names} и звёздная пещера`;

    const text = `# ${title}

Когда над миром зажглись первые звёзды, ${names} услышали тихий шёпот ветра. «Идём, — позвал он, — я покажу самое волшебное место».${topic}

[IMAGE: a small child follows a glowing path through a quiet forest at dusk]

Рядом семенил маленький друг — дракончик Рекс, чешуя которого блестела, словно изумруды. Вместе они прошли мимо спящих цветов и сонных светлячков.

Внутри пещеры потолок мерцал тысячами огоньков. «Это светлячки, — прошептал Рекс. — Они зажигаются, когда кто-то по-настоящему добр».

[IMAGE: a cave ceiling full of tiny glowing fireflies and a small green dragon]

${first} тихонько погладил дракончика по голове и почувствовал, как тёплая сонливость укрывает, словно мягкое одеяло. Светлячки гасли один за другим, и пещера наполнилась покоем.

[MORAL: Даже когда мы отдыхаем, жизнь остаётся волшебной, а доброта светит ярче звёзд.]
[CLOSING: Спи сладко. Пусть тебе приснятся звёзды и добрые драконы…]`;

    return { title, text, usage: { inputTokens: 0, outputTokens: 0, estimatedCostUsd: 0 } };
  }
}

export class MockSafetyChecker implements SafetyChecker {
  async check() {
    return { safe: true };
  }
}
