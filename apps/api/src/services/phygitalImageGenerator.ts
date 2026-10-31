import type { GenerateImageInput, GeneratedImage, ImageGenerator, ImageQuality } from "./imageGenerator.js";

type FetchLike = (url: string, init?: RequestInit) => Promise<Response>;

interface TaskResponse {
  task_id?: number;
  status?: string;
  error_message?: string | null;
  outputs?: Array<{ links?: string[] }> | null;
}

export interface PhygitalOptions {
  apiKey: string;
  baseUrl?: string;
  /** Model slug from https://dev.phygital.plus/api/models, e.g. gemini-image. */
  model?: string;
  /** `model_name` param per quality: the Lite model for standard, the Pro model for hd. */
  modelVersions?: Record<ImageQuality, string>;
  estimatedCostUsd?: Record<ImageQuality, number>;
  pollIntervalMs?: number;
  timeoutMs?: number;
  fetch?: FetchLike;
}

const TERMINAL_FAILURES = new Set(["failed", "error", "cancelled", "canceled"]);

/**
 * Phygital+ API: POST /api/models/{slug} returns a task id, GET /api/tasks/{id} is polled until the
 * status is "done" and carries signed links to the files. The key goes in the X-Api-Key header.
 * Written for the `gemini-image` (Nano Banana) model; other text-to-image models take different field names.
 */
export class PhygitalImageGenerator implements ImageGenerator {
  readonly provider = "phygital";
  private readonly baseUrl: string;
  private readonly model: string;
  private readonly modelVersions: Record<ImageQuality, string>;
  private readonly cost: Record<ImageQuality, number>;
  private readonly pollIntervalMs: number;
  private readonly timeoutMs: number;
  private readonly fetchImpl: FetchLike;
  private readonly apiKey: string;

  constructor(options: PhygitalOptions) {
    this.apiKey = options.apiKey;
    this.baseUrl = (options.baseUrl ?? "https://dev.phygital.plus").replace(/\/$/, "");
    this.model = options.model ?? "gemini-image";
    this.modelVersions = options.modelVersions ?? { standard: "v3_1_lite", hd: "v3" };
    this.cost = options.estimatedCostUsd ?? { standard: 0, hd: 0 };
    this.pollIntervalMs = options.pollIntervalMs ?? 2000;
    this.timeoutMs = options.timeoutMs ?? 120_000;
    this.fetchImpl = options.fetch ?? ((url, init) => fetch(url, init));
  }

  async generateImage(input: GenerateImageInput): Promise<GeneratedImage> {
    const taskId = await this.createTask(input);
    const url = await this.waitForResult(taskId);
    const image = await this.fetchImpl(url);

    if (!image.ok) {
      throw new Error(`Phygital+ result download failed with HTTP ${image.status}.`);
    }

    const contentType = (image.headers.get("content-type") ?? "image/png").split(";")[0].trim();
    return {
      bytes: Buffer.from(await image.arrayBuffer()),
      contentType,
      estimatedCostUsd: this.cost[input.quality]
    };
  }

  private async createTask(input: GenerateImageInput): Promise<number> {
    const res = await this.fetchImpl(`${this.baseUrl}/api/models/${this.model}`, {
      method: "POST",
      headers: { "content-type": "application/json", "x-api-key": this.apiKey },
      body: JSON.stringify({
        inputs: { text_prompt: input.prompt },
        params: { model_name: this.modelVersions[input.quality], ratio: "r_1_1", resolution: "default", web_search: false }
      })
    });
    const body = await readJson<TaskResponse & { detail?: unknown }>(res);

    if (!res.ok || typeof body.task_id !== "number") {
      throw new Error(`Phygital+ rejected the task (HTTP ${res.status}): ${describe(body)}`);
    }

    return body.task_id;
  }

  private async waitForResult(taskId: number): Promise<string> {
    const deadline = Date.now() + this.timeoutMs;

    while (Date.now() < deadline) {
      await sleep(this.pollIntervalMs);
      const res = await this.fetchImpl(`${this.baseUrl}/api/tasks/${taskId}`, { headers: { "x-api-key": this.apiKey } });
      const task = await readJson<TaskResponse>(res);

      if (!res.ok) {
        throw new Error(`Phygital+ task ${taskId} status check failed (HTTP ${res.status}): ${describe(task)}`);
      }

      if (task.status === "done") {
        const link = task.outputs?.flatMap((output) => output.links ?? [])[0];

        if (!link) {
          throw new Error(`Phygital+ task ${taskId} finished without an image.`);
        }

        return link;
      }

      if (task.status && TERMINAL_FAILURES.has(task.status)) {
        throw new Error(`Phygital+ task ${taskId} ${task.status}: ${task.error_message ?? "no details"}`);
      }
    }

    throw new Error(`Phygital+ task ${taskId} did not finish within ${Math.round(this.timeoutMs / 1000)} s.`);
  }
}

async function readJson<T>(res: Response): Promise<T> {
  const text = await res.text();

  try {
    return JSON.parse(text) as T;
  } catch {
    return { raw: text.slice(0, 200) } as T;
  }
}

function describe(body: unknown): string {
  return JSON.stringify(body).slice(0, 200);
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
