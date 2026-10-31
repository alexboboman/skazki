CREATE TABLE "story_heroes" (
	"story_id" uuid NOT NULL,
	"child_profile_id" uuid NOT NULL,
	"position" integer DEFAULT 0 NOT NULL,
	CONSTRAINT "story_heroes_story_id_child_profile_id_pk" PRIMARY KEY("story_id","child_profile_id")
);
--> statement-breakpoint
ALTER TABLE "child_profiles" ADD COLUMN "appearance" jsonb;--> statement-breakpoint
ALTER TABLE "stories" ADD COLUMN "world" text;--> statement-breakpoint
ALTER TABLE "stories" ADD COLUMN "moral" text;--> statement-breakpoint
ALTER TABLE "stories" ADD COLUMN "closing" text;--> statement-breakpoint
ALTER TABLE "stories" ADD COLUMN "reading_minutes" integer DEFAULT 5 NOT NULL;--> statement-breakpoint
ALTER TABLE "stories" ADD COLUMN "is_favorite" boolean DEFAULT false NOT NULL;--> statement-breakpoint
ALTER TABLE "stories" ADD COLUMN "read_progress" real DEFAULT 0 NOT NULL;--> statement-breakpoint
ALTER TABLE "story_heroes" ADD CONSTRAINT "story_heroes_story_id_stories_id_fk" FOREIGN KEY ("story_id") REFERENCES "public"."stories"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "story_heroes" ADD CONSTRAINT "story_heroes_child_profile_id_child_profiles_id_fk" FOREIGN KEY ("child_profile_id") REFERENCES "public"."child_profiles"("id") ON DELETE cascade ON UPDATE no action;