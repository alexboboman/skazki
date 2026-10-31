type FetchLike = (url: string, init?: RequestInit) => Promise<Response>;

interface TaskResponse {
  task_id?: number;
  status?: string;
  error_message?: string | null;
  outputs?: Array<{ links?: string[] }> | null;
}

export interface PhygitalClientOptions {
  apiKey: string;
  baseUrl?: string;
  pollIntervalMs?: number;
  timeoutMs?: number;
  fetch?: FetchLike;
}

export interface PhygitalFile {
  bytes: Buffer;
  contentType: string;
}

const TERMINAL_FAILURES = new Set(["failed", "error", "cancelled", "canceled"]);

/**
 * Phygital+ API: POST /api/models/{slug} returns a task id, GET /api/tasks/{id} is polled until the
 * status is "done" and carries signed links to the files. The key goes in the X-Api-Key header.
 * Every model takes its own `inputs` and `params`; see https://dev.phygital.plus/api/models/{slug}.
 */
export class PhygitalClient {
  private readonly apiKey: string;
  private readonly baseUrl: string;
  private readonly pollIntervalMs: number;
  private readonly timeoutMs: number;
  private readonly fetchImpl: FetchLike;

  constructor(options: PhygitalClientOptions) {
    this.apiKey = options.apiKey;
    this.baseUrl = (options.baseUrl ?? "https://dev.phygital.plus").replace(/\/$/, "");
    this.pollIntervalMs = options.pollIntervalMs ?? 2000;
    this.timeoutMs = options.timeoutMs ?? 120_000;
    this.fetchImpl = options.fetch ?? ((url, init) => fetch(url, init));
  }

  /** Runs one task and downloads its first output file. `kind` only words the error messages. */
  async run(
    slug: string,
    inputs: Record<string, unknown>,
    params: Record<string, unknown>,
    kind: "image" | "audio",
    fallbackContentType: string
  ): Promise<PhygitalFile> {
    const taskId = await this.createTask(slug, inputs, params);
    const url = await this.waitForResult(taskId, kind);
    const file = await this.fetchImpl(url);

    if (!file.ok) {
      throw new Error(`Phygital+ result download failed with HTTP ${file.status}.`);
    }

    const contentType = (file.headers.get("content-type") ?? fallbackContentType).split(";")[0].trim();
    return { bytes: Buffer.from(await file.arrayBuffer()), contentType };
  }

  private async createTask(slug: string, inputs: Record<string, unknown>, params: Record<string, unknown>): Promise<number> {
    const res = await this.fetchImpl(`${this.baseUrl}/api/models/${slug}`, {
      method: "POST",
      headers: { "content-type": "application/json", "x-api-key": this.apiKey },
      body: JSON.stringify({ inputs, params })
    });
    const body = await readJson<TaskResponse & { detail?: unknown }>(res);

    if (!res.ok || typeof body.task_id !== "number") {
      throw new Error(`Phygital+ rejected the task (HTTP ${res.status}): ${describe(body)}`);
    }

    return body.task_id;
  }

  private async waitForResult(taskId: number, kind: string): Promise<string> {
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
          throw new Error(`Phygital+ task ${taskId} finished without an ${kind}.`);
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
