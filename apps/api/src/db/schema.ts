import { boolean, index, integer, jsonb, pgTable, primaryKey, real, text, timestamp, unique, uuid } from "drizzle-orm/pg-core";
import type { Appearance } from "../../../../packages/shared/src/index.js";

const createdAt = () => timestamp("created_at", { withTimezone: true }).notNull().defaultNow();
const updatedAt = () => timestamp("updated_at", { withTimezone: true }).notNull().defaultNow();

export const users = pgTable("users", {
  id: uuid("id").primaryKey().defaultRandom(),
  appleId: text("apple_id").unique(),
  email: text("email"),
  trialEndsAt: timestamp("trial_ends_at", { withTimezone: true }),
  createdAt: createdAt(),
  updatedAt: updatedAt()
});

/** Written by the StoreKit / App Store Server Notifications integration (not built yet) and by the dev endpoint. */
export const subscriptions = pgTable(
  "subscriptions",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    userId: uuid("user_id")
      .notNull()
      .references(() => users.id, { onDelete: "cascade" }),
    productId: text("product_id").notNull(),
    tier: text("tier").notNull(),
    status: text("status").notNull(),
    originalTransactionId: text("original_transaction_id").unique(),
    expiresAt: timestamp("expires_at", { withTimezone: true }),
    gracePeriodExpiresAt: timestamp("grace_period_expires_at", { withTimezone: true }),
    createdAt: createdAt(),
    updatedAt: updatedAt()
  },
  (table) => [index("subscriptions_user_id_idx").on(table.userId)]
);

export const usageCounters = pgTable(
  "usage_counters",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    userId: uuid("user_id")
      .notNull()
      .references(() => users.id, { onDelete: "cascade" }),
    featureKey: text("feature_key").notNull(),
    periodStart: timestamp("period_start", { withTimezone: true }).notNull(),
    periodEnd: timestamp("period_end", { withTimezone: true }).notNull(),
    count: integer("count").notNull().default(0),
    limitValue: integer("limit_value").notNull()
  },
  (table) => [unique("usage_counters_user_feature_period_unique").on(table.userId, table.featureKey, table.periodStart)]
);

export const childProfiles = pgTable(
  "child_profiles",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    userId: uuid("user_id")
      .notNull()
      .references(() => users.id, { onDelete: "cascade" }),
    name: text("name").notNull(),
    age: integer("age").notNull(),
    gender: text("gender"),
    appearance: jsonb("appearance").$type<Appearance>(),
    interests: text("interests").array().notNull().default([]),
    worlds: text("worlds").array().notNull().default([]),
    favoriteCharacter: text("favorite_character"),
    language: text("language").notNull(),
    createdAt: createdAt(),
    updatedAt: updatedAt()
  },
  (table) => [index("child_profiles_user_id_idx").on(table.userId)]
);

export const stories = pgTable(
  "stories",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    userId: uuid("user_id")
      .notNull()
      .references(() => users.id, { onDelete: "cascade" }),
    childProfileId: uuid("child_profile_id").references(() => childProfiles.id, { onDelete: "set null" }),
    format: text("format").notNull(),
    title: text("title"),
    world: text("world"),
    moral: text("moral"),
    closing: text("closing"),
    readingMinutes: integer("reading_minutes").notNull().default(5),
    isFavorite: boolean("is_favorite").notNull().default(false),
    readProgress: real("read_progress").notNull().default(0),
    totalParts: integer("total_parts").notNull().default(1),
    status: text("status").notNull().default("ready"),
    createdAt: createdAt(),
    updatedAt: updatedAt()
  },
  (table) => [index("stories_user_id_created_at_idx").on(table.userId, table.createdAt)]
);

/** All children who are heroes of a story, so it shows up in each of their libraries. */
export const storyHeroes = pgTable(
  "story_heroes",
  {
    storyId: uuid("story_id")
      .notNull()
      .references(() => stories.id, { onDelete: "cascade" }),
    childProfileId: uuid("child_profile_id")
      .notNull()
      .references(() => childProfiles.id, { onDelete: "cascade" }),
    position: integer("position").notNull().default(0)
  },
  (table) => [primaryKey({ columns: [table.storyId, table.childProfileId] })]
);

export const storyParts = pgTable(
  "story_parts",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    storyId: uuid("story_id")
      .notNull()
      .references(() => stories.id, { onDelete: "cascade" }),
    partNumber: integer("part_number").notNull(),
    textContent: text("text_content").notNull(),
    unlockedAt: timestamp("unlocked_at", { withTimezone: true }),
    readAt: timestamp("read_at", { withTimezone: true }),
    createdAt: createdAt()
  },
  (table) => [index("story_parts_story_id_idx").on(table.storyId)]
);

export const mediaAssets = pgTable(
  "media_assets",
  {
    id: uuid("id").primaryKey(),
    storyPartId: uuid("story_part_id")
      .notNull()
      .references(() => storyParts.id, { onDelete: "cascade" }),
    type: text("type").notNull(),
    variant: text("variant").notNull(),
    provider: text("provider").notNull(),
    url: text("url").notNull(),
    contentType: text("content_type").notNull(),
    prompt: text("prompt"),
    afterParagraph: integer("after_paragraph"),
    status: text("status").notNull().default("ready"),
    createdAt: createdAt()
  },
  (table) => [index("media_assets_story_part_id_idx").on(table.storyPartId)]
);
