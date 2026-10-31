import { index, integer, pgTable, text, timestamp, uuid } from "drizzle-orm/pg-core";

const createdAt = () => timestamp("created_at", { withTimezone: true }).notNull().defaultNow();
const updatedAt = () => timestamp("updated_at", { withTimezone: true }).notNull().defaultNow();

export const users = pgTable("users", {
  id: uuid("id").primaryKey().defaultRandom(),
  appleId: text("apple_id").unique(),
  email: text("email"),
  createdAt: createdAt(),
  updatedAt: updatedAt()
});

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
    totalParts: integer("total_parts").notNull().default(1),
    status: text("status").notNull().default("ready"),
    createdAt: createdAt(),
    updatedAt: updatedAt()
  },
  (table) => [index("stories_user_id_created_at_idx").on(table.userId, table.createdAt)]
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
