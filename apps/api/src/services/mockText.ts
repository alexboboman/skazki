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

    if (request.arc) {
      return { title, text: mockPart(request, names), usage: { inputTokens: 0, outputTokens: 0, estimatedCostUsd: 0 } };
    }

    const text = `# ${title}

Когда над миром зажглись первые звёзды, тихий шёпот ветра позвал ${names}. «Идём, — сказал он, — я покажу самое волшебное место».${topic}

[IMAGE: a small child follows a glowing path through a quiet forest at dusk]

Рядом семенил маленький друг — дракончик Рекс, чешуя которого блестела, словно изумруды. Вместе они прошли мимо спящих цветов и сонных светлячков.

Внутри пещеры потолок мерцал тысячами огоньков. «Это светлячки, — прошептал Рекс. — Они зажигаются, когда кто-то по-настоящему добр».

[IMAGE: a cave ceiling full of tiny glowing fireflies and a small green dragon]

Тёплая сонливость укрыла ${first}, словно мягкое одеяло. Светлячки гасли один за другим, и пещера наполнилась покоем.

[MORAL: Даже когда мы отдыхаем, жизнь остаётся волшебной, а доброта светит ярче звёзд.]
[CLOSING: Спи сладко. Пусть тебе приснятся звёзды и добрые драконы…]`;

    return { title, text, usage: { inputTokens: 0, outputTokens: 0, estimatedCostUsd: 0 } };
  }
}

function mockPart(request: GenerateStoryRequest, names: string): string {
  const arc = request.arc!;
  const last = arc.partNumber === arc.length;
  const heading = arc.partNumber === 1 ? `${names} и звёздная пещера` : `Ночь ${arc.partNumber}: огоньки ведут дальше`;
  const lines = [
    `# ${heading}`,
    `В ${arc.partNumber}-й вечер ${names} снова отправились к дракончику Рексу. Ветер был тихим, а звёзды светили ярче вчерашнего.`,
    "[IMAGE: a small child and a green dragon walk under a sky full of stars]",
    last
      ? "Они дошли до самой яркой звезды, и все огоньки собрались вместе, чтобы сказать спасибо. Так закончилось их путешествие."
      : "Они нашли новую тропинку, которая мерцала в темноте, и решили, что завтра пойдут по ней дальше.",
    "[IMAGE: a glowing path winding between sleepy flowers]"
  ];

  if (arc.partNumber === 1) {
    lines.push("[SEED: a small child and Rex, a friendly green dragon with emerald scales, in a quiet night forest with a glowing cave]");
  }

  lines.push(`[SUMMARY: В части ${arc.partNumber} ${names} шли за огоньками вместе с Рексом.]`);

  if (last) {
    lines.push("[MORAL: Вместе любой путь становится волшебным.]");
  }

  lines.push("[CLOSING: Спи сладко, завтра нас ждёт продолжение.]");
  return lines.join("\n\n");
}

export class MockSafetyChecker implements SafetyChecker {
  async check() {
    return { safe: true };
  }
}
