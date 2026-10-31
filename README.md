# Bedtime Stories AI

Early prototype for the "Сказочник" product.

## Current Prototype

The project now has a small API scaffold:

- `apps/api` — Hono API prototype.
- `packages/shared` — shared request/response contracts.
- `scripts/test_story.js` — old one-off Claude prompt spike.
- `docs/product` — PRD and technical architecture.
- `docs/stories` — generated story samples.

The API currently generates text only. Images, audio, video, entitlements, analytics and attribution are represented in the contracts/architecture docs, but are not implemented as runtime services yet.

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

Healthcheck:

```bash
curl http://localhost:3000/health
```

Generate a story:

```bash
curl -X POST http://localhost:3000/v1/stories/generate \
  -H "content-type: application/json" \
  -d '{
    "format": "quick_story",
    "wordCount": 600,
    "childProfile": {
      "name": "Саша",
      "age": 5,
      "language": "Русский",
      "interests": ["динозавры", "космос"],
      "world": "волшебный лес с говорящими животными",
      "favoriteCharacter": "дракончик Рекс"
    },
    "mediaOptions": {
      "requestedTypes": []
    }
  }'
```

## Verify

```bash
npm run typecheck
```
