import { serve } from "@hono/node-server";
import { createApp } from "./app.js";
import { createDb } from "./db/client.js";
import { AnthropicTextGenerator } from "./services/anthropicTextGenerator.js";
import { createImageGenerator } from "./services/imageGenerator.js";
import { LocalMediaStore } from "./services/mediaStore.js";
import { AnthropicSafetyChecker } from "./services/safetyChecker.js";

const apiKey = process.env.ANTHROPIC_API_KEY;

const app = createApp({
  db: await createDb(),
  mediaStore: new LocalMediaStore(),
  imageGenerator: createImageGenerator(),
  textGenerator: apiKey ? new AnthropicTextGenerator(apiKey) : undefined,
  safetyChecker: apiKey ? new AnthropicSafetyChecker(apiKey) : undefined
});

const port = Number(process.env.PORT ?? 3000);

serve({ fetch: app.fetch, port });
console.log(`API listening on http://localhost:${port}`);
