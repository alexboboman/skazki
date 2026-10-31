# Bedtime Stories AI

Early prototype for the "Сказочник" product.

## Current Prototype

The project now has a small API scaffold:

- `apps/api` — Hono API prototype.
- `ios/` — iPhone app in SwiftUI (iPad later); onboarding and the API client are built, see `ios/README.md`.
- `packages/shared` — shared request/response contracts.
- `scripts/test_story.js` — old one-off Claude prompt spike.
- `docs/product` — PRD and technical architecture.
- `docs/stories` — generated story samples.

The API has JWT auth, child profiles, a story library (Postgres via Drizzle) and generates text (Claude) and illustrations (Phygital+ `gemini-image`, OpenAI `gpt-image-1`, or an offline mock) in one step-based pipeline: `generate_text` → `safety_check` → `parse_media_prompts` → `generate_images`. Entitlements (tier limits and quotas) are enforced server-side. Audio, video, the StoreKit integration, analytics and attribution are represented in the contracts/architecture docs, but are not implemented as runtime services yet.

Data and auth notes:

- DB: Drizzle ORM over Postgres. With `DATABASE_URL` set (Neon in production) it uses `pg`; without it the API runs an embedded PGlite database in `apps/api/.data/pglite` (git-ignored), so local dev needs no Postgres. Migrations in `apps/api/drizzle/` are applied on startup; after editing `apps/api/src/db/schema.ts` run `npm run db:generate`.
- Guest accounts: the design lets a parent finish onboarding and read the first story before signing in, so the client calls `POST /v1/auth/anonymous` on first launch and keeps the returned token in the Keychain. A guest account gets the 7-day trial like any other. Later `POST /v1/auth/apple` sent **with the guest bearer token** links the Apple ID to that same account (profiles, stories and trial are kept); if that Apple ID already has an account, that account is returned instead and the guest data is not merged. Risk: every guest call starts a new trial, so before launch it needs rate limiting and App Attest / DeviceCheck.
- Auth: `POST /v1/auth/apple` verifies an Apple identity token (RS256 via Apple JWKS, `iss`/`aud` checked against `APPLE_BUNDLE_ID`) and returns our own HS256 JWT (90 days, `JWT_SECRET`). The Apple flow is implemented but not yet tested against a real Apple token. For local work set `AUTH_DEV_LOGIN=1` to enable `POST /v1/auth/dev` (disabled when `NODE_ENV=production`).
- Every `/v1/profiles` and `/v1/stories` route needs `Authorization: Bearer <token>` and only sees the caller's own data.
- Entitlements: the tier comes from an active row in `subscriptions` (written by the future StoreKit / App Store Server Notifications integration), else a 7-day Family trial from first sign-in (`users.trial_ends_at`), else Free. The matrix from the PRD lives in `TIERS` in `apps/api/src/services/entitlements.ts` (profiles 1/3/5, Quick Story 3 per week on Free, Classic 1 per day on Free, arcs paid only, HD images paid only, "unlimited" = 100 per month fair use); it moves to remote config later. Quotas are counted in `usage_counters` (UTC day / Monday-based week / month), taken atomically before generation and given back if generation fails. `GET /v1/entitlements` returns the tier, limits and current usage for the client.
- Paywall contract: when a limit blocks an action the API answers **HTTP 402** with `{ error: { code: "limit_reached" | "upgrade_required", feature, tier, limit?, resetsAt? } }`; `feature` is `profiles`, `story_arc`, `classic_story` or `quick_story`. Reading existing stories is never blocked.
- Dev only (`AUTH_DEV_LOGIN=1`): `PUT /v1/dev/subscription` with `{ "tier": "free" | "family" | "family_plus" }` switches the caller's tier and ends the trial, to test limits without StoreKit.

Pipeline notes:

- Claude puts the title first as `# Title` and ends the text with `[MORAL: ...]` and `[CLOSING: ...]` markers, which become separate fields (the reading screen shows them as "Мораль сказки" and the closing line).
- Claude marks illustration spots with `[IMAGE: ...]` in the text; the pipeline strips the markers and generates one image per marker (3 for quick/classic stories, 2 for arc parts). `[AUDIO_CUE]` / `[VIDEO_CUE]` are parsed and ignored.
- `safety_check` asks Claude to review the draft for the child's age (violence, scary scenes, etc.). An unsafe draft is regenerated once; a second rejection returns **422** `story_rejected`, and a safety service outage fails the request (fail closed). Token usage of all attempts is summed into `usage`.
- A failed image step does not fail the request: the story is returned without pictures and the step is marked `failed` in `steps`.
- Generated files go through the `MediaStore` interface. The local implementation writes to `apps/api/.media/` (git-ignored) and serves files at `GET /v1/media/:fileName`; Cloudflare R2 replaces it later.
- The pipeline runs inline in the HTTP request. Moving it into a BullMQ worker is still open (see Phase 1 in the tech plan).

## Project Structure

Keep the root small and predictable:

```text
apps/
  api/              Hono API prototype
ios/                SwiftUI app (Swift Package + XcodeGen spec), see ios/README.md
packages/
  shared/           Shared TypeScript contracts
docs/
  product/          PRD, architecture, roadmap
  stories/          Generated story samples
scripts/            One-off local test scripts
```

Root files are only for repository-level config and entry documentation: `README.md`, `package.json`, `package-lock.json`, `tsconfig.json`, `.env.example`, `.gitignore`.

## Documentation Rule

Every meaningful product or architecture change should update documentation in the same step:

- Product requirements go to `docs/product/PRD_BedtimeStories.md`.
- Architecture, integrations, data model and roadmap go to `docs/product/TechPlan_BedtimeStories.md`.
- UI flows and screen behavior go to `docs/product/UI_Flow.md`.
- Visual language and reusable components go to `docs/product/Design_System.md`.
- Runtime instructions and folder conventions go to `README.md`.
- Generated examples go to `docs/stories`.

Avoid creating new top-level files unless they are project config. Prefer adding a focused file inside the existing folder tree.

## Product Docs

- `docs/product/PRD_BedtimeStories.md` — product requirements.
- `docs/product/TechPlan_BedtimeStories.md` — architecture, data model, roadmap.
- `docs/product/UI_Flow.md` — MVP screens, navigation, states, paywall points.
- `docs/product/Design_System.md` — visual direction, tokens, core components.

## Requirements

- Node.js 22+
- Anthropic API key

## Setup

```bash
npm install
cp .env.example .env
```

Put your real key in `.env` or export it in the shell.

## Run API

```bash
ANTHROPIC_API_KEY=... npm run dev:api
```

No keys yet? `TEXT_PROVIDER=mock IMAGE_PROVIDER=mock` serves a canned story and placeholder images, so the app can be tried end to end (ignored in production). Dev-only `TRIAL_DAYS=0` starts new accounts on Free (instead of the 7-day Family trial) to try the limits and the paywall. The iOS app is covered in `ios/README.md`.

The server loads `.env` itself on start (`apps/api/src/loadEnv.ts`); variables already set in the environment win.

Images: `IMAGE_PROVIDER` picks `phygital`, `openai` or `mock`. When it is empty the first provider with a key wins: `PHYGITAL_API_KEY`, then `OPENAI_API_KEY`, else the offline mock (visible as `provider: "mock"` in `steps`).
- **Phygital+** (`dev.phygital.plus`) is an async task API: the generator creates a task (`POST /api/models/gemini-image`, `X-Api-Key`), polls `/api/tasks/{id}` and downloads the first output link. Standard quality uses `model_name=v3_1_lite`, HD uses `v3` (override with `PHYGITAL_MODEL_STANDARD/HD`). One image takes about 13 s and comes back as a ~2 MB PNG; the cost per image is not known yet, so `usage.estimatedCostUsd` counts it as 0.
- Phygital+ pictures are re-encoded as WebP (longest side at most 1280 px, quality 82) by `CompressingImageGenerator` before they are stored, so a picture weighs about 100-300 KB instead of 2 MB. SVG and WebP pass through; if encoding fails the original is kept.
- The illustrations of one story are generated in parallel and keep the order of their `[IMAGE: …]` markers; a failed one is skipped and marks the `generate_images` step as failed.

Healthcheck:

```bash
curl http://localhost:3000/health
```

Log in (dev), create a profile and generate a story:

```bash
AUTH_DEV_LOGIN=1 ANTHROPIC_API_KEY=... npm run dev:api   # in another terminal

TOKEN=$(curl -s -X POST http://localhost:3000/v1/auth/dev \
  -H "content-type: application/json" -d '{"name":"me"}' | node -pe 'JSON.parse(require("fs").readFileSync(0)).token')

PROFILE=$(curl -s -X POST http://localhost:3000/v1/profiles \
  -H "authorization: Bearer $TOKEN" -H "content-type: application/json" \
  -d '{
    "name": "Саша",
    "age": 5,
    "language": "Русский",
    "interests": ["динозавры", "космос"],
    "gender": "girl",
    "appearance": { "skin": 1, "hair": 3, "hairStyle": "long", "outfit": 0 },
    "worlds": ["forest"],
    "favoriteCharacter": "дракончик Рекс"
  }' | node -pe 'JSON.parse(require("fs").readFileSync(0)).id')

curl -X POST http://localhost:3000/v1/stories/generate \
  -H "authorization: Bearer $TOKEN" -H "content-type: application/json" \
  -d "{\"profileIds\": [\"$PROFILE\"], \"format\": \"quick_story\", \"topic\": \"Не страшно в темноте\", \"lengthMinutes\": 7, \"mediaOptions\": {\"requestedTypes\": [\"image\"]}}"
```

Generate body (mirrors the "Сочинить" screen):

- `profileIds`: 1 to 3 saved profiles; the first is the main hero, the others are told in the same story and the story appears in each one's library. Instead, an inline `childProfile` (`name`, `age`, `language`, `interests`, `world`, optional `favoriteCharacter`, `gender`, `appearance`) is accepted; such stories are saved without profile links.
- `format`: `quick_story`, `classic_story` or `story_arc_part`. `story_arc_part` starts a series (see below), needs `arcLength` and saved `profileIds`.
- `arcLength`: parts in the series, one of 3, 5, 7, 14, 30 (the app offers 3, 5 and 7).
- `topic`: a preset ("Не страшно в темноте") or the parent's own words, up to 300 characters.
- `lengthMinutes`: 4, 7 or 12, turned into about 450 / 780 / 1200 words (about 110 words a minute). An explicit `wordCount` (200 to 1200) wins.
- `world`: one of `forest`, `ocean`, `space`, `castle`, `clouds`, `jungle`; overrides the hero's own world for this story. The ids are `WORLD_IDS` in `packages/shared`, the story prompt text for each is in `apps/api/src/services/catalog.ts`.
- `mediaOptions`: `requestedTypes` (`image`), `imageQuality` (`standard` or `hd`; clamped to the tier).

Hero look: `appearance` holds palette indexes that match the client (skin 0 to 4, hair 0 to 5, `hairStyle` short or long, outfit 0 to 4; see `docs/design/prototype/ui.jsx`). The server turns it, with `gender` (`boy`, `girl`, or absent for "not specified") and age, into an English description that is written into every illustration prompt, so the hero looks the same on every picture.

Endpoints (all under `/v1`, all except `auth/*` and `media/*` need a bearer token):

| Method | Path | Purpose |
|---|---|---|
| POST | `/auth/anonymous` | Guest account, returns `{ token, user }` |
| POST | `/auth/refresh` | New token for a valid one; the app calls it on every launch, so a guest account only expires after 90 days without opening the app |
| POST | `/auth/apple`, `/auth/dev` | Sign in / link Apple ID to the guest (send the guest token); dev login |
| GET | `/entitlements` | Tier, limits and usage (for the paywall) |
| PUT | `/dev/subscription` | Dev only: switch tier |
| GET, POST | `/profiles` | List / create child profiles |
| GET, PUT, DELETE | `/profiles/:id` | Read / replace / delete a profile |
| POST | `/stories/generate` | Generate and save a story (returns `storyId`); with `format: story_arc_part` it starts a series with part 1 |
| POST | `/stories/:id/parts` | Write the next part of a series (body: optional `mediaOptions`) |
| GET | `/stories?profileId=&favorite=` | Library list with `coverImageUrl`, `heroIds`, `world`, `readingMinutes`, `favorite`, `readProgress` |
| GET, PATCH, DELETE | `/stories/:id` | Full story with parts, media, `moral`, `closing` / update `favorite`, `readProgress` (0 to 1) and `readPart` (marks a part of a series read) / delete |
| POST | `/stories/:id/audio` | Premium narration of one part (Family+), body `{ "part": 1 }`: 200 with the audio asset, or 202 `{ "status": "processing" }` while it is being voiced |
| GET | `/media/:fileName` | Generated image and audio files |

The generate response contains `storyId`, `story` (`title`, `text` as body paragraphs without the heading, `moral`, `closing`, `readingMinutes`), `media[]` (each asset with `url` and `afterParagraph`: the paragraph of `story.text`, split by blank lines, that the image follows), `usage` and `steps`.

### Series

A series is a story with `format: story_arc_part` and a row in `story_arcs` (length, status, topic, word count, style seed). Its parts live in `story_parts` (`title`, `closing`, `summary`, `read`).

- `POST /v1/stories/generate` with `arcLength` writes part 1 and answers with `storyId`, `partNumber: 1` and `arc: { length, partsReady, status }`. `POST /v1/stories/:id/parts` writes the next part for the same heroes, world, topic and length; the response has the same shape (`partNumber`, `arc`). The parent asks for each part, so a series moves at the pace of the evenings (no daily lock yet). Part `length` completes the series (`status: completed`), gives it its `moral`, and further requests get **409** `arc_completed`.
- Consistency without long contexts: part 1 also returns `[SEED: …]` (the recurring characters and the setting, in English), and every part returns `[SUMMARY: …]`. The next part gets the seed, the series title and the summaries of the latest three parts; the seed is also written into every illustration prompt. The markers are stored, never shown.
- Limits: a series needs a paid tier (**402** `upgrade_required`, feature `story_arc`); the number of unfinished series is capped (Family 1, Family+ 3; **402** `limit_reached`, feature `story_arc`, `limit`). `GET /entitlements` shows `limits.activeArcs` and `activeArcsUsed`. Parts have no quota of their own. Finishing a series frees its slot.
- Heroes: a series needs saved profiles (inline `childProfile` is rejected). If its profiles are deleted, the next part answers **409** `heroes_missing`. Two simultaneous requests for the same part: one wins, the other gets **409** `part_conflict`. A failed part (Claude, safety) changes nothing and can be retried.
- Reading progress: the app sends `PATCH /stories/:id {"readPart": n}` when a part is finished; `readProgress` becomes the share of read parts.

### Premium narration

The app reads stories aloud with the system voice for everyone (on the device, free). Family+ also gets a neural voice: `POST /v1/stories/:id/audio` with `{ "part": n }` (default 1; the part number of a series).

- Voice: Gemini TTS through Phygital+ (`gemini-tts`, engine `gemini_2_5_pro_tts`, voice `Aoede`, `ru_RU`), told to "read like a kind mother a bedtime story". Picked by ear from five samples; override with `PHYGITAL_TTS_*` (see `.env.example`), `TTS_PROVIDER=none` switches it off (the endpoint then answers 503 `premium_voice_unavailable`).
- Text: the name (with "Часть N." for a series part), the paragraphs, the moral (a series gives it with its last part) and the good-night line; illustrations and markers are not read.
- Time: voicing takes about 8 seconds per 100 characters, so the text is cut into pieces of at most 600 characters on paragraph borders and the pieces are voiced side by side (6 at a time), then joined into one MP3. A 3.6-minute part took 76 seconds. That is too long for one request, so the endpoint waits 2.5 s and otherwise answers **202** `{ "status": "processing" }`; the client asks again about every 5 s until it gets **200** with the asset (`type: "audio"`, `url`, `contentType: "audio/mpeg"`). Asking again never starts a second generation. A failed attempt is reported (**502** `audio_generation_failed`) to the next request, then the part can be retried.
- Stored once: the file is saved like a picture and attached to the part (`media_assets`, `type = audio`), so it also shows up in `GET /stories/:id` under `parts[].media`, and every device gets the same file. Audio is never used as a cover.
- Plan: Family+ only (**402** `upgrade_required`, feature `premium_voice`); `GET /entitlements` shows `limits.premiumVoice`. The cost per minute at Phygital+ is not known yet, so it is not counted in `usage`.

## Verify

```bash
npm run typecheck
npm test
```

`npm test` runs `apps/api/test/` (node:test) against an in-memory PGlite database with fake Claude and a mock image provider, so it needs no API keys or network.
