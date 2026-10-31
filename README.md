# Bedtime Stories AI

Early prototype for the "Сказочник" product.

## Current Prototype

The project now has a small API scaffold:

- `apps/api` — Hono API prototype.
- `packages/shared` — shared request/response contracts.
- `scripts/test_story.js` — old one-off Claude prompt spike.
- `docs/product` — PRD and technical architecture.
- `docs/stories` — generated story samples.

The API has JWT auth, child profiles, a story library (Postgres via Drizzle) and generates text (Claude) and illustrations (OpenAI `gpt-image-1`, or an offline mock) in one step-based pipeline: `generate_text` → `parse_media_prompts` → `generate_images`. Audio, video, entitlements, analytics and attribution are represented in the contracts/architecture docs, but are not implemented as runtime services yet.

Data and auth notes:

- DB: Drizzle ORM over Postgres. With `DATABASE_URL` set (Neon in production) it uses `pg`; without it the API runs an embedded PGlite database in `apps/api/.data/pglite` (git-ignored), so local dev needs no Postgres. Migrations in `apps/api/drizzle/` are applied on startup; after editing `apps/api/src/db/schema.ts` run `npm run db:generate`.
- Auth: `POST /v1/auth/apple` verifies an Apple identity token (RS256 via Apple JWKS, `iss`/`aud` checked against `APPLE_BUNDLE_ID`) and returns our own HS256 JWT (30 days, `JWT_SECRET`). The Apple flow is implemented but not yet tested against a real Apple token. For local work set `AUTH_DEV_LOGIN=1` to enable `POST /v1/auth/dev` (disabled when `NODE_ENV=production`).
- Every `/v1/profiles` and `/v1/stories` route needs `Authorization: Bearer <token>` and only sees the caller's own data.
- Limits: at most 5 child profiles per user for now. Per-tier limits (Free/Family/Family+) arrive with the Entitlement Service.

Pipeline notes:

- Claude marks illustration spots with `[IMAGE: ...]` in the text; the pipeline strips the markers and generates one image per marker (3 for quick/classic stories, 2 for arc parts). `[AUDIO_CUE]` / `[VIDEO_CUE]` are parsed and ignored.
- A failed image step does not fail the request: the story is returned without pictures and the step is marked `failed` in `steps`.
- Generated files go through the `MediaStore` interface. The local implementation writes to `apps/api/.media/` (git-ignored) and serves files at `GET /v1/media/:fileName`; Cloudflare R2 replaces it later.
- The pipeline runs inline in the HTTP request. Moving it into a BullMQ worker is still open (see Phase 1 in the tech plan).

## Project Structure

Keep the root small and predictable:

```text
apps/
  api/              Hono API prototype
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

Images: set `OPENAI_API_KEY` to use `gpt-image-1`, or `IMAGE_PROVIDER=mock` for offline placeholders. Without a key the API falls back to the mock provider (visible as `provider: "mock"` in `steps`).

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
    "worlds": ["волшебный лес с говорящими животными"],
    "favoriteCharacter": "дракончик Рекс"
  }' | node -pe 'JSON.parse(require("fs").readFileSync(0)).id')

curl -X POST http://localhost:3000/v1/stories/generate \
  -H "authorization: Bearer $TOKEN" -H "content-type: application/json" \
  -d "{\"profileId\": \"$PROFILE\", \"format\": \"quick_story\", \"wordCount\": 600, \"mediaOptions\": {\"requestedTypes\": [\"image\"]}}"
```

Instead of `profileId` the generate body also accepts an inline `childProfile` (`name`, `age`, `language`, `interests`, `world`, optional `favoriteCharacter`); such stories are saved without a profile link.

Endpoints (all under `/v1`, all except `auth/*` and `media/*` need a bearer token):

| Method | Path | Purpose |
|---|---|---|
| POST | `/auth/apple`, `/auth/dev` | Sign in, returns `{ token, user }` |
| GET, POST | `/profiles` | List / create child profiles |
| GET, PUT, DELETE | `/profiles/:id` | Read / replace / delete a profile |
| POST | `/stories/generate` | Generate and save a story (returns `storyId`) |
| GET | `/stories?profileId=` | Library list with `coverImageUrl` |
| GET, DELETE | `/stories/:id` | Full story with parts and media / delete |
| GET | `/media/:fileName` | Generated image files |

The generate response contains `storyId`, `story.text` (markers removed), `media[]` (each asset with `url` and `afterParagraph`: the paragraph of `story.text`, split by blank lines, that the image follows), `usage` and `steps`.

## Verify

```bash
npm run typecheck
```
