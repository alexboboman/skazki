# Сказочник (Bedtime Stories AI)

iPad-приложение, которое генерирует персонализированные сказки на ночь с иллюстрациями. Подробности в `docs/product/PRD_BedtimeStories.md`.

## Стек
- Backend: Node.js 22 + TypeScript, Hono (`apps/api`), общие типы в `packages/shared`
- Текст сказок: Anthropic Claude
- Планируется: iPad-приложение на SwiftUI (отдельная папка `ios/`), иллюстрации, аудио, подписки (StoreKit 2)
- Реализованы: генерация текста и картинок, JWT-авторизация (Apple Sign In + dev-вход), профили детей и библиотека историй (Drizzle + Postgres/PGlite). Аудио, видео, подписки/entitlements и аналитика описаны лишь в документах

## Команды
```bash
npm install
cp .env.example .env   # вписать ANTHROPIC_API_KEY (БД локально не нужна: встроенный PGlite)
npm run dev:api        # запуск API
npm run typecheck
npm run db:generate    # после правки apps/api/src/db/schema.ts
```

## Правила
- Любое значимое изменение продукта или архитектуры обновляет документацию в том же шаге (куда что писать — в `README.md`, раздел Documentation Rule)
- Корень держим маленьким: новые файлы кладём в существующие папки, новые top-level файлы только для конфигов
- Реальный `.env` не коммитить, ключи не печатать в чат
- Язык сказок и документов по умолчанию — русский
