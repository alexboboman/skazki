import { and, asc, count, eq } from "drizzle-orm";
import type { ChildProfileDto, ChildProfileInput } from "../../../../packages/shared/src/index.js";
import type { Db } from "../db/client.js";
import { childProfiles } from "../db/schema.js";

/** Hard cap from the PRD. Per-tier limits (Free 1, Family 3, Family+ 5) arrive with the Entitlement Service. */
export const MAX_PROFILES = 5;

type ProfileRow = typeof childProfiles.$inferSelect;

export class ProfileLimitError extends Error {}

export class ProfileService {
  constructor(private readonly db: Db) {}

  async list(userId: string): Promise<ChildProfileDto[]> {
    const rows = await this.db
      .select()
      .from(childProfiles)
      .where(eq(childProfiles.userId, userId))
      .orderBy(asc(childProfiles.createdAt));
    return rows.map(toDto);
  }

  async get(userId: string, id: string): Promise<ChildProfileDto | undefined> {
    const [row] = await this.db
      .select()
      .from(childProfiles)
      .where(and(eq(childProfiles.id, id), eq(childProfiles.userId, userId)))
      .limit(1);
    return row ? toDto(row) : undefined;
  }

  async create(userId: string, input: ChildProfileInput): Promise<ChildProfileDto> {
    const [{ total }] = await this.db
      .select({ total: count() })
      .from(childProfiles)
      .where(eq(childProfiles.userId, userId));

    if (total >= MAX_PROFILES) {
      throw new ProfileLimitError(`At most ${MAX_PROFILES} child profiles are allowed.`);
    }

    const [row] = await this.db.insert(childProfiles).values({ userId, ...input }).returning();
    return toDto(row);
  }

  async update(userId: string, id: string, input: ChildProfileInput): Promise<ChildProfileDto | undefined> {
    const [row] = await this.db
      .update(childProfiles)
      .set({ ...input, gender: input.gender ?? null, favoriteCharacter: input.favoriteCharacter ?? null, updatedAt: new Date() })
      .where(and(eq(childProfiles.id, id), eq(childProfiles.userId, userId)))
      .returning();
    return row ? toDto(row) : undefined;
  }

  async delete(userId: string, id: string): Promise<boolean> {
    const rows = await this.db
      .delete(childProfiles)
      .where(and(eq(childProfiles.id, id), eq(childProfiles.userId, userId)))
      .returning({ id: childProfiles.id });
    return rows.length > 0;
  }
}

function toDto(row: ProfileRow): ChildProfileDto {
  return {
    id: row.id,
    name: row.name,
    age: row.age,
    gender: row.gender ?? undefined,
    interests: row.interests,
    worlds: row.worlds,
    favoriteCharacter: row.favoriteCharacter ?? undefined,
    language: row.language,
    createdAt: row.createdAt.toISOString()
  };
}
