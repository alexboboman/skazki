import { and, asc, count, desc, eq, inArray, sql } from "drizzle-orm";
import type {
  GenerateStoryRequest,
  GenerateStoryResponse,
  MediaAsset,
  StoryArcInfo,
  StoryDto,
  StoryFormat,
  StoryPartDto,
  StorySummary,
  UpdateStoryRequest
} from "../../../../packages/shared/src/index.js";
import type { Db } from "../db/client.js";
import { mediaAssets, stories, storyArcs, storyHeroes, storyParts } from "../db/schema.js";
import { narrationText } from "./narrationText.js";

type StoryRow = typeof stories.$inferSelect;
type MediaRow = typeof mediaAssets.$inferSelect;
type PartRow = typeof storyParts.$inferSelect;

/** Another request already wrote this part of the series (a double tap, or two devices). */
export class PartConflictError extends Error {}

/** Everything the next part of a series is written from. */
export interface ArcState {
  storyId: string;
  title?: string;
  world?: string;
  heroIds: string[];
  length: number;
  status: "active" | "completed";
  topic?: string;
  wordCount?: number;
  seed?: string;
  partsReady: number;
  /** Summaries of the latest parts, oldest first. */
  recentSummaries: string[];
}

const SUMMARIES_FOR_NEXT_PART = 3;

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
      const storyId = await insertStory(tx, userId, heroIds, world, request.format, result, 1);
      await insertPart(tx, storyId, 1, result, {});
      return storyId;
    });
  }

  /** Saves part 1 of a new series together with the arc record the next parts are written from. */
  async saveSeries(
    userId: string,
    heroIds: string[],
    world: string | undefined,
    arc: { length: number; topic?: string; wordCount?: number },
    result: GenerateStoryResponse,
    notes: { summary?: string; seed?: string }
  ): Promise<string> {
    return this.db.transaction(async (tx) => {
      const storyId = await insertStory(tx, userId, heroIds, world, "story_arc_part", { ...result, story: { ...result.story, moral: undefined, closing: result.story.closing } }, arc.length);
      await tx.insert(storyArcs).values({
        storyId,
        arcLength: arc.length,
        topic: arc.topic,
        wordCount: arc.wordCount,
        styleSeed: notes.seed
      });
      await insertPart(tx, storyId, 1, result, { title: result.story.title, summary: notes.summary });
      return storyId;
    });
  }

  /** What the next part is written from; undefined when the story is not a series of this user. */
  async arcState(userId: string, storyId: string): Promise<ArcState | undefined> {
    const [row] = await this.db
      .select({ story: stories, arc: storyArcs })
      .from(stories)
      .innerJoin(storyArcs, eq(storyArcs.storyId, stories.id))
      .where(and(eq(stories.id, storyId), eq(stories.userId, userId)))
      .limit(1);

    if (!row) {
      return undefined;
    }

    const parts = await this.db
      .select({ partNumber: storyParts.partNumber, summary: storyParts.summary })
      .from(storyParts)
      .where(eq(storyParts.storyId, storyId))
      .orderBy(asc(storyParts.partNumber));
    const heroes = await this.heroIds([storyId]);

    return {
      storyId,
      title: row.story.title ?? undefined,
      world: row.story.world ?? undefined,
      heroIds: heroes.get(storyId) ?? [],
      length: row.arc.arcLength,
      status: row.arc.status as ArcState["status"],
      topic: row.arc.topic ?? undefined,
      wordCount: row.arc.wordCount ?? undefined,
      seed: row.arc.styleSeed ?? undefined,
      partsReady: parts.length,
      recentSummaries: parts
        .slice(-SUMMARIES_FOR_NEXT_PART)
        .map((part) => part.summary)
        .filter((summary): summary is string => Boolean(summary))
    };
  }

  /** Appends the next part; the last one completes the series and gives it its moral. */
  async addPart(
    storyId: string,
    partNumber: number,
    result: GenerateStoryResponse,
    notes: { summary?: string }
  ): Promise<void> {
    try {
      await this.db.transaction(async (tx) => {
        const [arc] = await tx.select().from(storyArcs).where(eq(storyArcs.storyId, storyId)).limit(1);
        const last = partNumber === arc.arcLength;

        await insertPart(tx, storyId, partNumber, result, { title: result.story.title, summary: notes.summary });
        await tx
          .update(stories)
          .set({
            closing: result.story.closing,
            ...(last ? { moral: result.story.moral } : {}),
            updatedAt: new Date()
          })
          .where(eq(stories.id, storyId));

        if (last) {
          await tx.update(storyArcs).set({ status: "completed", updatedAt: new Date() }).where(eq(storyArcs.storyId, storyId));
        }
      });
    } catch (error) {
      if (isUniqueViolation(error)) {
        throw new PartConflictError(`Part ${partNumber} already exists.`);
      }
      throw error;
    }
  }

  /** The text of one part as a narrator reads it, and its narration file if there is one already. */
  async narrationSource(
    userId: string,
    storyId: string,
    partNumber: number
  ): Promise<{ partId: string; text: string; audio?: MediaAsset } | undefined> {
    const [row] = await this.db
      .select({ story: stories, part: storyParts, arc: storyArcs })
      .from(stories)
      .innerJoin(storyParts, eq(storyParts.storyId, stories.id))
      .leftJoin(storyArcs, eq(storyArcs.storyId, stories.id))
      .where(and(eq(stories.id, storyId), eq(stories.userId, userId), eq(storyParts.partNumber, partNumber)))
      .limit(1);

    if (!row) {
      return undefined;
    }

    const isSeries = row.arc !== null;
    const isLast = isSeries && partNumber === row.arc?.arcLength;
    const [audio] = await this.db
      .select()
      .from(mediaAssets)
      .where(and(eq(mediaAssets.storyPartId, row.part.id), eq(mediaAssets.type, "audio")))
      .limit(1);

    return {
      partId: row.part.id,
      text: narrationText({
        title: (isSeries ? row.part.title : row.story.title) ?? undefined,
        text: row.part.textContent,
        // A series gives its moral with the last part only.
        moral: (isSeries ? (isLast ? row.story.moral : undefined) : row.story.moral) ?? undefined,
        closing: (row.part.closing ?? row.story.closing) ?? undefined,
        partNumber: isSeries ? partNumber : undefined
      }),
      audio: audio ? toMediaAsset(audio) : undefined
    };
  }

  async addAudio(partId: string, asset: MediaAsset): Promise<void> {
    await this.db.insert(mediaAssets).values({
      id: asset.id,
      storyPartId: partId,
      type: "audio",
      variant: asset.variant,
      provider: asset.provider,
      url: asset.url,
      contentType: asset.contentType
    });
  }

  /** Series of this user that are not finished yet. */
  async countActiveArcs(userId: string): Promise<number> {
    const [row] = await this.db
      .select({ total: count() })
      .from(storyArcs)
      .innerJoin(stories, eq(stories.id, storyArcs.storyId))
      .where(and(eq(stories.userId, userId), eq(storyArcs.status, "active")));
    return row.total;
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
    const arcs = await this.arcInfos(ids);

    const covers = await this.db
      .select({ storyId: storyParts.storyId, url: mediaAssets.url })
      .from(mediaAssets)
      .innerJoin(storyParts, eq(mediaAssets.storyPartId, storyParts.id))
      .where(and(inArray(storyParts.storyId, ids), eq(storyParts.partNumber, 1), eq(mediaAssets.type, "image")))
      .orderBy(asc(mediaAssets.afterParagraph), asc(mediaAssets.createdAt));

    const coverByStory = new Map<string, string>();
    for (const cover of covers) {
      if (!coverByStory.has(cover.storyId)) {
        coverByStory.set(cover.storyId, cover.url);
      }
    }

    return rows.map((row) => toSummary(row, heroes.get(row.id) ?? [], coverByStory.get(row.id), arcs.get(row.id)));
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
    const arcs = await this.arcInfos([story.id]);

    return {
      ...toSummary(story, heroes.get(story.id) ?? [], media.find((asset) => asset.type === "image")?.url, arcs.get(story.id)),
      moral: story.moral ?? undefined,
      closing: story.closing ?? undefined,
      totalParts: story.totalParts,
      parts: parts.map((part) => toPartDto(part, media.filter((asset) => asset.storyPartId === part.id)))
    };
  }

  /** Returns false when the story does not exist or belongs to someone else. */
  async update(userId: string, id: string, patch: UpdateStoryRequest): Promise<boolean> {
    return this.db.transaction(async (tx) => {
      const rows = await tx
        .update(stories)
        .set({
          ...(patch.favorite !== undefined ? { isFavorite: patch.favorite } : {}),
          ...(patch.readProgress !== undefined ? { readProgress: patch.readProgress } : {}),
          updatedAt: new Date()
        })
        .where(and(eq(stories.id, id), eq(stories.userId, userId)))
        .returning({ id: stories.id });

      if (rows.length === 0) {
        return false;
      }

      if (patch.readPart !== undefined) {
        await tx
          .update(storyParts)
          .set({ readAt: new Date() })
          .where(and(eq(storyParts.storyId, id), eq(storyParts.partNumber, patch.readPart), sql`${storyParts.readAt} is null`));

        const [arc] = await tx.select({ length: storyArcs.arcLength }).from(storyArcs).where(eq(storyArcs.storyId, id)).limit(1);

        if (arc) {
          const [{ read }] = await tx
            .select({ read: count() })
            .from(storyParts)
            .where(and(eq(storyParts.storyId, id), sql`${storyParts.readAt} is not null`));
          await tx.update(stories).set({ readProgress: Math.min(1, read / arc.length) }).where(eq(stories.id, id));
        }
      }

      return true;
    });
  }

  async delete(userId: string, id: string): Promise<boolean> {
    const rows = await this.db
      .delete(stories)
      .where(and(eq(stories.id, id), eq(stories.userId, userId)))
      .returning({ id: stories.id });
    return rows.length > 0;
  }

  private async arcInfos(storyIds: string[]): Promise<Map<string, StoryArcInfo>> {
    const arcs = await this.db.select().from(storyArcs).where(inArray(storyArcs.storyId, storyIds));
    const result = new Map<string, StoryArcInfo>();

    if (arcs.length === 0) {
      return result;
    }

    const counts = await this.db
      .select({ storyId: storyParts.storyId, total: count() })
      .from(storyParts)
      .where(inArray(storyParts.storyId, arcs.map((arc) => arc.storyId)))
      .groupBy(storyParts.storyId);
    const partsByStory = new Map(counts.map((row) => [row.storyId, row.total]));

    for (const arc of arcs) {
      result.set(arc.storyId, {
        length: arc.arcLength,
        partsReady: partsByStory.get(arc.storyId) ?? 0,
        status: arc.status as StoryArcInfo["status"]
      });
    }

    return result;
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

function toSummary(row: StoryRow, heroIds: string[], coverImageUrl?: string, arc?: StoryArcInfo): StorySummary {
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
    arc,
    createdAt: row.createdAt.toISOString()
  };
}

function toPartDto(part: PartRow, media: MediaRow[]): StoryPartDto {
  return {
    partNumber: part.partNumber,
    title: part.title ?? undefined,
    text: part.textContent,
    closing: part.closing ?? undefined,
    read: part.readAt !== null,
    media: media.map(toMediaAsset)
  };
}

type Tx = Parameters<Parameters<Db["transaction"]>[0]>[0];

async function insertStory(
  tx: Tx,
  userId: string,
  heroIds: string[],
  world: string | undefined,
  format: StoryFormat,
  result: GenerateStoryResponse,
  totalParts: number
): Promise<string> {
  const [story] = await tx
    .insert(stories)
    .values({
      userId,
      childProfileId: heroIds[0],
      format,
      title: result.story.title,
      world,
      moral: result.story.moral,
      closing: result.story.closing,
      readingMinutes: result.story.readingMinutes,
      totalParts
    })
    .returning({ id: stories.id });

  if (heroIds.length > 0) {
    await tx.insert(storyHeroes).values(heroIds.map((childProfileId, position) => ({ storyId: story.id, childProfileId, position })));
  }

  return story.id;
}

async function insertPart(
  tx: Tx,
  storyId: string,
  partNumber: number,
  result: GenerateStoryResponse,
  series: { title?: string; summary?: string }
): Promise<void> {
  const [part] = await tx
    .insert(storyParts)
    .values({
      storyId,
      partNumber,
      textContent: result.story.text,
      title: series.title,
      closing: series.title === undefined ? undefined : result.story.closing,
      summary: series.summary,
      unlockedAt: new Date()
    })
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
}

function isUniqueViolation(error: unknown): boolean {
  const code = (error as { code?: string; cause?: { code?: string } } | undefined);
  return code?.code === "23505" || code?.cause?.code === "23505";
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
