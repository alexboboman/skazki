ALTER TABLE "subscriptions" ADD COLUMN "environment" text;--> statement-breakpoint
ALTER TABLE "subscriptions" ADD COLUMN "last_signed_at" timestamp with time zone;