// Тест генерации сказки через Claude API
// Запуск: ANTHROPIC_API_KEY=... node test_story.js

const https = require("https");

const API_KEY = process.env.ANTHROPIC_API_KEY;

if (!API_KEY) {
  console.error("Ошибка: задайте ANTHROPIC_API_KEY перед запуском.");
  console.error("Пример: ANTHROPIC_API_KEY=... node test_story.js");
  process.exit(1);
}

const childProfile = {
  name: "Саша",
  age: 5,
  language: "Русский",
  interests: ["динозавры", "космос"],
  world: "волшебный лес с говорящими животными",
  favorite_character: "дракончик Рекс"
};

const systemPrompt = `Ты — опытный детский писатель. Пиши сказки для детей возраста ${childProfile.age} лет.
Язык: ${childProfile.language}. Стиль: мягкий, добрый, с моральным выводом в конце.
Имя главного героя: ${childProfile.name}.
Мир: ${childProfile.world}.
Интересы ребёнка: ${childProfile.interests.join(", ")}.
Любимый персонаж: ${childProfile.favorite_character}.
Длина: 600-700 слов.
Не используй страшных, тёмных или жестоких элементов.
Придумай название сказки.`;

function postJson(url, headers, body) {
  return new Promise((resolve, reject) => {
    const requestBody = JSON.stringify(body);
    const req = https.request(
      url,
      {
        method: "POST",
        headers: {
          ...headers,
          "content-length": Buffer.byteLength(requestBody)
        }
      },
      (res) => {
        let rawBody = "";

        res.setEncoding("utf8");
        res.on("data", (chunk) => {
          rawBody += chunk;
        });
        res.on("end", () => {
          resolve({ ok: res.statusCode >= 200 && res.statusCode < 300, status: res.statusCode, rawBody });
        });
      }
    );

    req.on("error", reject);
    req.write(requestBody);
    req.end();
  });
}

async function generateStory() {
  console.log("Генерирую сказку...\n");

  const res = await postJson(
    "https://api.anthropic.com/v1/messages",
    {
      "x-api-key": API_KEY,
      "anthropic-version": "2023-06-01",
      "content-type": "application/json"
    },
    {
      model: "claude-haiku-4-5-20251001",
      max_tokens: 1500,
      system: systemPrompt,
      messages: [{ role: "user", content: "Напиши короткую сказку на ночь для ребёнка по профилю выше." }]
    }
  );

  const rawBody = res.rawBody;
  let data;

  try {
    data = JSON.parse(rawBody);
  } catch {
    console.error("Ошибка: Anthropic API вернул не JSON.");
    console.error(rawBody);
    return;
  }

  if (!res.ok) {
    console.error(`Ошибка HTTP ${res.status}:`, JSON.stringify(data, null, 2));
    return;
  }

  if (data.error) {
    console.error("Ошибка:", JSON.stringify(data.error, null, 2));
    return;
  }

  console.log("=== СКАЗКА ===\n");
  console.log(data.content[0].text);
  console.log("\n=== СТАТИСТИКА ===");
  console.log(`Input tokens: ${data.usage.input_tokens}`);
  console.log(`Output tokens: ${data.usage.output_tokens}`);
  const cost = (data.usage.input_tokens * 0.0000008) + (data.usage.output_tokens * 0.000004);
  console.log(`Стоимость: $${cost.toFixed(5)}`);
}

generateStory();
