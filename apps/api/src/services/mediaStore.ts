import { randomUUID } from "node:crypto";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";

export interface StoredMedia {
  id: string;
  url: string;
}

/** Where generated files live. A local folder now; Cloudflare R2 later behind the same interface. */
export interface MediaStore {
  save(bytes: Buffer, contentType: string): Promise<StoredMedia>;
  read(fileName: string): Promise<{ bytes: Buffer; contentType: string } | undefined>;
}

const EXTENSIONS: Record<string, string> = {
  "image/webp": "webp",
  "image/png": "png",
  "image/jpeg": "jpg",
  "image/svg+xml": "svg"
};

const FILE_NAME = /^[0-9a-f-]{36}\.(webp|png|jpg|svg)$/;

export class LocalMediaStore implements MediaStore {
  constructor(private readonly dir = process.env.MEDIA_DIR ?? path.resolve("apps/api/.media")) {}

  async save(bytes: Buffer, contentType: string): Promise<StoredMedia> {
    const extension = EXTENSIONS[contentType];

    if (!extension) {
      throw new Error(`Unsupported media type: ${contentType}`);
    }

    const id = randomUUID();
    await mkdir(this.dir, { recursive: true });
    await writeFile(path.join(this.dir, `${id}.${extension}`), bytes);

    return { id, url: `/v1/media/${id}.${extension}` };
  }

  async read(fileName: string): Promise<{ bytes: Buffer; contentType: string } | undefined> {
    if (!FILE_NAME.test(fileName)) {
      return undefined;
    }

    const extension = fileName.split(".").pop() as string;
    const contentType = Object.keys(EXTENSIONS).find((type) => EXTENSIONS[type] === extension) as string;

    try {
      return { bytes: await readFile(path.join(this.dir, fileName)), contentType };
    } catch {
      return undefined;
    }
  }
}
