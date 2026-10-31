import { and, asc, desc, eq, inArray } from "drizzle-orm";
import type {
  GenerateStoryRequest,
  GenerateStoryResponse,
  MediaAsset,
  StoryDto,
  StoryFormat,
  StorySummary
} from "../../../../packages/shared/src/index.js";
import type { Db } from "../db/client.js";
import { mediaAssets, stories, storyParts } from "../db/schema.js";

type StoryRow = typeof stories.$inferSelect;
type MediaRow = typeof mediaAssets.$inferSelect;

export class StoryService {
  constructor(private readonly db: Db) {}

  /** Saves a generated story with its single part and media assets; returns the story id. */
  async save(
    userId: string,
    childProfileId: string | undefined,
    request: GenerateStoryRequest,
    result: GenerateStoryResponse
  ): Promise<string> {
    return this.db.transaction(async (tx) => {
      const [story] = await tx
        .insert(stories)
        .values({ userId, childProfileId, format: request.format, title: result.story.title, totalParts: 1 })
        .returning({ id: stories.id });

      const [part] = await tx
        .insert(storyParts)
        .values({ storyId: story.id, partNumber: 1, textContent: result.story.text, unlockedAt: new Date() })
        .returning({ id: storyParts.id });

      if (result.media.length > 0) {
        await tx.insert(mediaAssets).values(
          result.media.map((asset) => ({
            id: asset.id,
            storyPartId: part.id,
            type: asset.type,
            variant: asset.variant,
            provider: asset.provider,
            url: asset.url,
            contentType: asset.contentType,
            prompt: asset.prompt,
            afterParagraph: asset.afterParagraph
          }))
        );
      }

      return story.id;
    });
  }

  async list(userId: string, childProfileId?: string): Promise<StorySummary[]> {
    const rows = await this.db
      .select()
      .from(stories)
      .where(
        childProfileId
          ? and(eq(stories.userId, userId), eq(stories.childProfileId, childProfileId))
          : eq(stories.userId, userId)
      )
      .orderBy(desc(stories.createdAt));

    if (rows.length === 0) {
      return [];
    }

    const covers = await this.db
      .select({ storyId: storyParts.storyId, url: mediaAssets.url })
      .from(mediaAssets)
      .innerJoin(storyParts, eq(mediaAssets.storyPartId, storyParts.id))
      .where(and(inArray(storyParts.storyId, rows.map((row) => row.id)), eq(storyParts.partNumber, 1)))
      .orderBy(asc(mediaAssets.afterParagraph), asc(mediaAssets.createdAt));

    const coverByStory = new Map<string, string>();
    for (const cover of covers) {
      if (!coverByStory.has(cover.storyId)) {
        coverByStory.set(cover.storyId, cover.url);
      }
    }

    return rows.map((row) => toSummary(row, coverByStory.get(row.id)));
  }

  async get(userId: string, id: string): Promise<StoryDto | undefined> {
    const [story] = await this.db
      .select()
      .from(stories)
      .where(and(eq(stories.id, id), eq(stories.userId, userId)))
      .limit(1);

    if (!story) {
      return undefined;
    }

    const parts = await this.db
      .select()
      .from(storyParts)
      .where(eq(storyParts.storyId, story.id))
      .orderBy(asc(storyParts.partNumber));

    const media = parts.length
      ? await this.db
          .select()
          .from(mediaAssets)
          .where(inArray(mediaAssets.storyPartId, parts.map((part) => part.id)))
          .orderBy(asc(mediaAssets.afterParagraph), asc(mediaAssets.createdAt))
      : [];

    const firstImage = media[0]?.url;

    return {
      ...toSummary(story, firstImage),
      totalParts: story.totalParts,
      parts: parts.map((part) => ({
        partNumber: part.partNumber,
        text: part.textContent,
        media: media.filter((asset) => asset.storyPartId === part.id).map(toMediaAsset)
      }))
    };
  }

  async delete(userId: string, id: string): Promise<boolean> {
    const rows = await this.db
      .delete(stories)
      .where(and(eq(stories.id, id), eq(stories.userId, userId)))
      .returning({ id: stories.id });
    return rows.length > 0;
  }
}

function toSummary(row: StoryRow, coverImageUrl?: string): StorySummary {
  return {
    id: row.id,
    title: row.title ?? undefined,
    format: row.format as StoryFormat,
    childProfileId: row.childProfileId ?? undefined,
    coverImageUrl,
    createdAt: row.createdAt.toISOString()
  };
}

function toMediaAsset(row: MediaRow): MediaAsset {
  return {
    id: row.id,
    type: row.type as MediaAsset["type"],
    variant: row.variant as MediaAsset["variant"],
    provider: row.provider,
    url: row.url,
    contentType: row.contentType,
    prompt: row.prompt ?? "",
    afterParagraph: row.afterParagraph ?? 1
  };
}
