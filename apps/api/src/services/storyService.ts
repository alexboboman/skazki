import { and, asc, desc, eq, inArray } from "drizzle-orm";
import type {
  GenerateStoryRequest,
  GenerateStoryResponse,
  MediaAsset,
  StoryDto,
  StoryFormat,
  StorySummary,
  UpdateStoryRequest
} from "../../../../packages/shared/src/index.js";
import type { Db } from "../db/client.js";
import { mediaAssets, stories, storyHeroes, storyParts } from "../db/schema.js";

type StoryRow = typeof stories.$inferSelect;
type MediaRow = typeof mediaAssets.$inferSelect;

export interface StoryFilter {
  heroId?: string;
  favorite?: boolean;
}

export class StoryService {
  constructor(private readonly db: Db) {}

  /** Saves a generated story with its single part, heroes and media assets; returns the story id. */
  async save(
    userId: string,
    heroIds: string[],
    world: string | undefined,
    request: GenerateStoryRequest,
    result: GenerateStoryResponse
  ): Promise<string> {
    return this.db.transaction(async (tx) => {
      const [story] = await tx
        .insert(stories)
        .values({
          userId,
          childProfileId: heroIds[0],
          format: request.format,
          title: result.story.title,
          world,
          moral: result.story.moral,
          closing: result.story.closing,
          readingMinutes: result.story.readingMinutes,
          totalParts: 1
        })
        .returning({ id: stories.id });

      if (heroIds.length > 0) {
        await tx
          .insert(storyHeroes)
          .values(heroIds.map((childProfileId, position) => ({ storyId: story.id, childProfileId, position })));
      }

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

  async list(userId: string, filter: StoryFilter = {}): Promise<StorySummary[]> {
    const conditions = [eq(stories.userId, userId)];

    if (filter.heroId) {
      conditions.push(
        inArray(
          stories.id,
          this.db.select({ id: storyHeroes.storyId }).from(storyHeroes).where(eq(storyHeroes.childProfileId, filter.heroId))
        )
      );
    }

    if (filter.favorite !== undefined) {
      conditions.push(eq(stories.isFavorite, filter.favorite));
    }

    const rows = await this.db
      .select()
      .from(stories)
      .where(and(...conditions))
      .orderBy(desc(stories.createdAt));

    if (rows.length === 0) {
      return [];
    }

    const ids = rows.map((row) => row.id);
    const heroes = await this.heroIds(ids);

    const covers = await this.db
      .select({ storyId: storyParts.storyId, url: mediaAssets.url })
      .from(mediaAssets)
      .innerJoin(storyParts, eq(mediaAssets.storyPartId, storyParts.id))
      .where(and(inArray(storyParts.storyId, ids), eq(storyParts.partNumber, 1)))
      .orderBy(asc(mediaAssets.afterParagraph), asc(mediaAssets.createdAt));

    const coverByStory = new Map<string, string>();
    for (const cover of covers) {
      if (!coverByStory.has(cover.storyId)) {
        coverByStory.set(cover.storyId, cover.url);
      }
    }

    return rows.map((row) => toSummary(row, heroes.get(row.id) ?? [], coverByStory.get(row.id)));
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

    const heroes = await this.heroIds([story.id]);

    return {
      ...toSummary(story, heroes.get(story.id) ?? [], media[0]?.url),
      moral: story.moral ?? undefined,
      closing: story.closing ?? undefined,
      totalParts: story.totalParts,
      parts: parts.map((part) => ({
        partNumber: part.partNumber,
        text: part.textContent,
        media: media.filter((asset) => asset.storyPartId === part.id).map(toMediaAsset)
      }))
    };
  }

  /** Returns false when the story does not exist or belongs to someone else. */
  async update(userId: string, id: string, patch: UpdateStoryRequest): Promise<boolean> {
    const rows = await this.db
      .update(stories)
      .set({
        ...(patch.favorite !== undefined ? { isFavorite: patch.favorite } : {}),
        ...(patch.readProgress !== undefined ? { readProgress: patch.readProgress } : {}),
        updatedAt: new Date()
      })
      .where(and(eq(stories.id, id), eq(stories.userId, userId)))
      .returning({ id: stories.id });
    return rows.length > 0;
  }

  async delete(userId: string, id: string): Promise<boolean> {
    const rows = await this.db
      .delete(stories)
      .where(and(eq(stories.id, id), eq(stories.userId, userId)))
      .returning({ id: stories.id });
    return rows.length > 0;
  }

  private async heroIds(storyIds: string[]): Promise<Map<string, string[]>> {
    const rows = await this.db
      .select()
      .from(storyHeroes)
      .where(inArray(storyHeroes.storyId, storyIds))
      .orderBy(asc(storyHeroes.position));

    const byStory = new Map<string, string[]>();
    for (const row of rows) {
      byStory.set(row.storyId, [...(byStory.get(row.storyId) ?? []), row.childProfileId]);
    }
    return byStory;
  }
}

function toSummary(row: StoryRow, heroIds: string[], coverImageUrl?: string): StorySummary {
  return {
    id: row.id,
    title: row.title ?? undefined,
    format: row.format as StoryFormat,
    world: row.world ?? undefined,
    heroIds,
    coverImageUrl,
    readingMinutes: row.readingMinutes,
    favorite: row.isFavorite,
    readProgress: row.readProgress,
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
