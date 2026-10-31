CREATE TABLE "story_arcs" (
	"story_id" uuid PRIMARY KEY NOT NULL,
	"arc_length" integer NOT NULL,
	"status" text DEFAULT 'active' NOT NULL,
	"topic" text,
	"word_count" integer,
	"style_seed" text,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
ALTER TABLE "story_parts" ADD COLUMN "title" text;--> statement-breakpoint
ALTER TABLE "story_parts" ADD COLUMN "closing" text;--> statement-breakpoint
ALTER TABLE "story_parts" ADD COLUMN "summary" text;--> statement-breakpoint
ALTER TABLE "story_arcs" ADD CONSTRAINT "story_arcs_story_id_stories_id_fk" FOREIGN KEY ("story_id") REFERENCES "public"."stories"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "story_parts" ADD CONSTRAINT "story_parts_story_part_unique" UNIQUE("story_id","part_number");