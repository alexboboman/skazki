# Сказочник (Bedtime Stories AI)

iPhone-приложение (iPad позже), которое генерирует персонализированные сказки на ночь с иллюстрациями. Подробности в `docs/product/PRD_BedtimeStories.md`.

## Стек
- Backend: Node.js 22 + TypeScript, Hono (`apps/api`), общие типы в `packages/shared`
- Текст сказок: Anthropic Claude
- iOS-приложение на SwiftUI, сначала iPhone, iPad позже (папка `ios/`: Swift Package + XcodeGen, подробности в `ios/README.md`; сборка в Xcode 16+, тесты через `swift test`), иллюстрации, аудио, подписки (StoreKit 2)
- Реализованы: генерация текста (Claude) и картинок (Phygital+ или OpenAI), JWT-авторизация (Apple Sign In + dev-вход), профили детей и библиотека историй (Drizzle + Postgres/PGlite), safety-проверка текста, тарифные лимиты и квоты (entitlements, ответ 402 для пейволла). Серии (story_arc_part, части по запросу), чтение вслух на устройстве (AVSpeechSynthesizer) и премиум-озвучка Family+ (Gemini TTS через Phygital+, асинхронно). Видео, интеграция StoreKit, очередь BullMQ и аналитика описаны лишь в документах

## Команды
```bash
npm install
cp .env.example .env   # вписать ANTHROPIC_API_KEY и PHYGITAL_API_KEY (БД локально не нужна: встроенный PGlite)
npm run dev:api        # запуск API
npm run typecheck
npm test               # тесты API, ключи и сеть не нужны
(cd ios && swift test) # тесты iOS-ядра и рендер экранов
npm run db:generate    # после правки apps/api/src/db/schema.ts
```

## Правила
- Любое значимое изменение продукта или архитектуры обновляет документацию в том же шаге (куда что писать — в `README.md`, раздел Documentation Rule)
- Корень держим маленьким: новые файлы кладём в существующие папки, новые top-level файлы только для конфигов
- Реальный `.env` не коммитить, ключи не печатать в чат
- Язык сказок и документов по умолчанию — русский
