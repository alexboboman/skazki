# Технический план и роадмап — «Сказочник»

**Версия:** 0.1  
**Дата:** 2026-05-31

---

## 1. Стек технологий

### Frontend (iOS-приложение)

| Слой | Технология | Обоснование |
|---|---|---|
| UI Framework | **SwiftUI** | Нативный iPhone UI (iPad позже), анимации, поддержка Dynamic Type |
| Навигация | NavigationStack + TabView | iOS 16+ стандарт |
| Локальное хранилище | SwiftData (iOS 17+) | Современная замена CoreData, удобно для профилей и историй |
| iCloud sync | CloudKit (через SwiftData) | Синхронизация между устройствами семьи |
| Подписки | StoreKit 2 | Apple IAP, Family Sharing |
| Push Notifications | APNs (UserNotifications) | Ежевечерние напоминания |
| Аналитика | Amplitude или Firebase Analytics | Воронки, retention, paywall performance |
| Attribution | AppsFlyer | Paid UA, SKAdNetwork, deferred deep links |
| Remote Config | Firebase Remote Config или backend config | Feature flags, лимиты, A/B тесты |
| TTS (v2) | AVSpeechSynthesizer или ElevenLabs | Аудио-чтение |

### Backend

| Слой | Технология | Обоснование |
|---|---|---|
| Runtime | **Node.js 22 + TypeScript** | Быстрая разработка, богатая экосистема |
| Framework | **Hono** (или Fastify) | Лёгкий, edge-ready, хорошо типизирован |
| Хостинг | **Railway** или **Fly.io** | Простой деплой, автомасштабирование |
| БД | **PostgreSQL** (Neon serverless) | Хранение профилей, историй, подписок |
| ORM | **Drizzle ORM** | Типобезопасный, быстрый |
| Кэш | **Redis** (Upstash) | Кэш промптов, rate limiting |
| Очередь задач | **BullMQ** | Генерация историй в фоне |
| Auth | JWT + Apple Sign In | Аутентификация пользователей |
| Entitlements | StoreKit 2 + App Store Server Notifications v2 | Server-side доступ к paid-функциям |
| Analytics events | Server-side event dispatcher | Надёжные события генерации, подписок и ошибок |
| Хранилище файлов | **Cloudflare R2** | Хранение изображений, аудио, будущих видео |

### AI-провайдеры

| Задача | Провайдер | Модель |
|---|---|---|
| Генерация текста сказки | **Anthropic Claude** | claude-sonnet-4-6 |
| Генерация иллюстраций | **Phygital+** | `gemini-image` (async task API); OpenAI gpt-image-1 остаётся запасным провайдером |
| Озвучка (premium, Family+) | **Phygital+** | `gemini-tts` (Aoede, gemini_2_5_pro_tts), ElevenLabs доступен через тот же API; голос на устройстве — AVSpeechSynthesizer |
| Резервный генератор изображений | **Flux** (Black Forest Labs) via Replicate | flux-1.1-pro |
| Аудио/TTS | AVSpeechSynthesizer / ElevenLabs | on-device для базового TTS, cloud voices для premium |
| Видео (future) | TBD | подключается через VideoGenerator-интерфейс |
| Safety classifier | Claude (встроенный) | — |

> **Решение по изображениям (факт):** основной провайдер — Phygital+ (один ключ, много моделей; ~13 с на картинку), OpenAI подключается через `IMAGE_PROVIDER=openai`. Стоимость картинки у Phygital+ ещё не измерена.
>
> **Примечание по изображениям (исходное):** gpt-image-1 — новая модель OpenAI с высоким качеством. Flux — быстрая и дешёвая альтернатива. Рекомендуется A/B тест по качеству + стоимости.

---

## 2. Архитектура системы (высокий уровень)

```
[iOS App / SwiftUI]
      │  HTTPS + JWT
      ▼
[API Gateway — Hono/Node.js]
      │
  ┌───┴──────────────────────────────┐
  │ Auth Service                      │
  │ Profile Service                   │
  │ Story Service                     │
  │ Entitlement Service               │
  │ Media Service                     │
  │ Analytics Service                 │
  │ Attribution Service               │
  │ Feature Flag / Remote Config      │
  └───┬──────────────────────────────┘
      │
  ┌───┴───────────────┐
  │  BullMQ Queue     │  ← story/media jobs ставятся в очередь
  └───┬───────────────┘
      │
  ┌───┴──────────────────────────────────────┐
  │  Generation Worker                        │
  │  1. build_prompt                          │
  │  2. generate_text                         │
  │  3. safety_check                          │
  │  4. parse_media_prompts                   │
  │  5. generate_images / audio / video       │
  │  6. persist_story_and_media               │
  │  7. notify_parent                         │
  │  8. track_events                          │
  └──────────────────────────────────────────┘
```

### 2.1 Основные сервисы

| Сервис | Ответственность |
|---|---|
| Auth Service | Apple Sign In, JWT, сессии пользователя |
| Profile Service | Профили детей, ограничения по количеству профилей |
| Story Service | API генерации, история, чтение, статусы jobs |
| Entitlement Service | Проверка подписки, лимитов, trial, grace period, restore purchases |
| Media Service | Универсальная работа с image/audio/video assets, R2, CDN, variants |
| Analytics Service | Единая отправка client/server событий в Amplitude/Firebase |
| Attribution Service | AppsFlyer, SKAdNetwork, install source, campaign mapping |
| Feature Flag / Remote Config | A/B тесты, лимиты тарифов, выбор AI-провайдеров |

Перед запуском генерации API всегда вызывает Entitlement Service. Worker выполняет только те шаги, которые разрешены тарифом и remote config: например, Free может получить standard images, Family — HD images, Family+ — premium voices.

### 2.2 Интеграционные границы

Внешние провайдеры подключаются через интерфейсы, а не напрямую из бизнес-логики:

```ts
interface TextGenerator { generateStory(input): Promise<TextResult> }
interface ImageGenerator { generateImage(input): Promise<MediaResult> }
interface AudioGenerator { generateAudio(input): Promise<MediaResult> }
interface VideoGenerator { generateVideo(input): Promise<MediaResult> }
interface AnalyticsProvider { track(event): Promise<void> }
interface AttributionProvider { identifyInstall(input): Promise<void> }
```

Это позволяет менять Claude Haiku/Sonnet, OpenAI/Flux, AVSpeech/ElevenLabs, Amplitude/Firebase и AppsFlyer/Branch без изменения Story Service.

---

## 3. Структура базы данных (основные таблицы)

```sql
-- Пользователи
users (id, apple_id, email, trial_ends_at, created_at, updated_at)

-- Атрибуция и consent
user_attribution (user_id, appsflyer_id, anonymous_id, att_status, install_source, campaign_id, media_source, created_at)
user_consents (user_id, analytics_allowed, personalized_marketing_allowed, updated_at)

-- Профили детей
child_profiles (id, user_id, name, age, gender, appearance jsonb, interests[], worlds[], favorite_character, language, created_at)

-- Подписки и entitlement-правила
subscriptions (id, user_id, product_id, tier, status, original_transaction_id, expires_at, grace_period_expires_at, created_at, updated_at)
entitlements (id, user_id, feature_key, limit_value, expires_at, source, created_at)
usage_counters (id, user_id, feature_key, period_start, period_end, count, limit_value)
feature_flags (key, enabled, rollout_percentage, config_json, updated_at)

-- Истории
stories (id, user_id, child_profile_id, format, title, world, moral, closing, reading_minutes, is_favorite, read_progress, total_parts, status, created_at, updated_at)

-- Герои истории (одна сказка может быть про нескольких детей)
story_heroes (story_id, child_profile_id, position)

-- Части истории
story_parts (id, story_id, part_number, text_content, unlocked_at, read_at, created_at)

-- Медиа-ассеты: изображения, аудио, будущие видео
media_assets (
  id,
  story_part_id,
  type,              -- image | audio | video
  variant,           -- standard | hd | thumbnail | premium_voice | preview
  provider,
  url,
  content_type,
  after_paragraph,   -- абзац текста, после которого показывается иллюстрация
  width,
  height,
  duration_sec,
  prompt,
  style_seed,
  status,
  created_at
)

-- Серии (Story Arc метаданные)
story_arcs (story_id, arc_length, status, topic, word_count, style_seed)  -- реализовано; next_part_date не нужен: части пишутся по запросу родителя
story_parts (+ title, closing, summary)  -- summary и style_seed питают следующую часть

-- Jobs генерации
generation_jobs (id, user_id, story_id, type, status, requested_media[], current_step, error_code, created_at, updated_at)
generation_job_steps (id, job_id, step_name, status, provider, started_at, finished_at, error_json)
```

`story_parts` не хранит `illustration_url` напрямую: все медиа идут через `media_assets`. Это важно для TTS, видео, нескольких вариантов качества и повторной генерации отдельных assets.

---

## 4. Стратегия промптинга (Claude)

### 4.1 Системный промпт (упрощённо)

```
Ты — опытный детский писатель. Пиши сказки для детей возраста {age} лет.
Язык: {language}. Стиль: мягкий, добрый, с моральным выводом в конце.
Имя главного героя: {child_name}.
Мир: {world} (например, «волшебный лес с говорящими животными»).
Интересы ребёнка: {interests}.
Длина части: {word_count} слов.
Не используй страшных, тёмных или жестоких элементов.
Пронумеруй места для иллюстраций тегом [ILLUSTRATION: краткое описание сцены на английском].
```

### 4.2 Промпт для иллюстраций (Phygital+ `gemini-image`)

```
Children's book illustration, soft watercolor style, warm colors.
Characters: {описание каждого героя: имя, возраст, пол, кожа, волосы, одежда}.   // собирает сервер (describeHero), не модель
Recurring characters and setting of the whole series (keep them the same): {seed}.  // только для серий
Scene: {scene_description_from_claude}.
World: {world_style}.
Age-appropriate, gentle, no scary elements, no text or letters in the image.
Style: Studio Ghibli inspired, storybook.
```

Картинки одной сказки генерируются параллельно и сохраняются в порядке маркеров. PNG ~2 МБ от провайдера перекодируется в WebP (до 1280 px, качество 82, `sharp`), итог ~250 КБ.

### 4.3 Consistency seed для сериалов

Для сериалов Claude получает в каждой части (реализовано):
- `style_seed` — короткое английское описание постоянных героев и места действия; Claude возвращает его маркером `[SEED: …]` в части 1, хранится в `story_arcs.style_seed`, подставляется в каждый промпт текста и иллюстраций
- Краткие итоги трёх последних частей (`[SUMMARY: …]`, 2–3 предложения, хранятся в `story_parts.summary`) и название серии
- Для части N из L добавляется указание: часть 1 задаёт героев и мир и заканчивается мягко, без тревоги; средние части продолжают без пересказа; последняя заканчивает все линии и даёт мораль
- Это обеспечивает связность без дорогих long context-запросов. Проверено живьём на трёх частях: герои и сюжет сохраняются

### 4.4 Media prompts

Claude должен возвращать структурированные маркеры для будущих медиа:

```
[IMAGE: short English scene description]
[AUDIO_CUE: calm bedtime narration, optional]
[VIDEO_CUE: future short animated scene, optional]
```

Реально используются: `IMAGE`, `MORAL`, `CLOSING` и для серий `SEED`, `SUMMARY`. `AUDIO_CUE` и `VIDEO_CUE` сохраняются как metadata, но worker игнорирует их до включения соответствующего feature flag.

Парсер (`mediaPrompts.ts`) вырезает маркеры из текста и выбрасывает «горизонтальные линии» `---`, которые модель иногда ставит перед маркерами. В промпт добавлен запрет эмодзи: текст читается вслух.

---

## 5. Unit Economics (оценка)

### Стоимость генерации одной короткой сказки

| Операция | Стоимость |
|---|---|
| Claude Sonnet (700 слов out + 200 in) | ~$0.004 |
| gpt-image-1 × 3 иллюстрации | ~$0.12 |
| **Итого** | **~$0.13** |

### Дополнительные медиа

| Медиа | Стратегия |
|---|---|
| Standard images | Доступны Free/Family, низкое разрешение, aggressive caching |
| HD images | Family+, либо Family при fair use лимитах |
| On-device TTS | Низкая marginal cost, можно включать для Family |
| Premium voices | Family+ или add-on, лимитируется по минутам |
| Видео | Future add-on, только асинхронно и с отдельными лимитами |

> **Что неизвестно.** Стоимость картинки и озвучки в Phygital+ не измерена (`estimatedCostUsd` для них считается как 0), поэтому цифры в этом разделе пока для gpt-image-1 и Sonnet. Модель текста в проде: Claude Haiku 4.5 (≈ $0.004 за сказку).

### Стоимость одной части сериала

| Операция | Стоимость |
|---|---|
| Claude Sonnet (500 слов out) | ~$0.003 |
| gpt-image-1 × 1.5 иллюстрации | ~$0.06 |
| **Итого** | **~$0.06** |

### Break-even при тарифе Family ($6.99/мес)

- Маржа Apple 30% → чистые $4.89
- Инфраструктура + backend ~$0.50 / пользователь / мес
- Остаток на AI: **$4.39**
- Это ~33 короткие сказки или ~73 части сериала в месяц
- Средний пользователь: ~15–20 частей/мес → маржа ≈ **55–60%** ✓

---

## 6. Роадмап

### Phase 0 — Исследование (2 нед)
- [ ] Финализация PRD и дизайна
- [x] Выбор Image API: Phygital+ (gemini-image); A/B с другими моделями Phygital+ — позже
- [ ] Прототип промпта (10 тест-историй, ручная оценка качества)
- [ ] Утвердить event taxonomy и privacy-safe analytics schema
- [ ] Спроектировать entitlement matrix и usage limits
- [ ] Выбрать analytics provider и AppsFlyer setup
- [ ] Регистрация Apple Developer account, настройка TestFlight
- [ ] Настройка StoreKit sandbox (локальный файл `ios/StoreKit/Skazochnik.storekit` есть; продукты, песочница и URL уведомлений в App Store Connect не заведены)

### Phase 1 — MVP (6–8 нед)
- [x] Backend: Auth (Apple Sign In + JWT) — `POST /v1/auth/apple` верифицирует identity token по JWKS Apple и выдаёт свой JWT; проверен только dev-вход, с реальным токеном Apple ещё не прогонялся
- [x] Backend: Entitlement Service + usage counters — матрица тарифов в коде (`entitlements.ts`), квоты в `usage_counters`, ответ 402 для пейволла, `GET /v1/entitlements`; источник подписки (StoreKit) подключится вместе с webhook-интеграцией, пока триал 7 дней и dev-переключатель тарифа
- [ ] Backend: Story generation worker (Claude + Image) как step-based pipeline — шаги `generate_text` → `safety_check` → `parse_media_prompts` → `generate_images` реализованы inline в API (`apps/api/src/services/storyPipeline.ts`), осталось вынести в BullMQ-воркер (сознательно отложено: для беты синхронной генерации достаточно, переход на jobs меняет контракт для клиента), добавить `build_prompt`, `persist_story_and_media`
- [x] Backend: Profiles + библиотека историй (Drizzle, Postgres/PGlite) — `/v1/profiles`, `/v1/stories`, лимит 5 профилей, тарифные лимиты придут с Entitlement Service
- [ ] Backend: Media Service (`media_assets`, R2, variants) — таблица `media_assets` есть (картинки и аудио, файлы png/webp/jpg/svg/mp3/wav/m4a), WebP-сжатие картинок сделано; `MediaStore` пока локальная папка (`apps/api/.media`) и `GET /v1/media/:fileName`, R2 и variants впереди
- [x] Backend: StoreKit 2 + App Store Server Notifications v2 — `POST /v1/subscription/sync` (подписанные транзакции из приложения) и `POST /v1/webhooks/apple`; подпись проверяется своим кодом до Apple Root CA G3 (`appStore.ts`), статусы и идемпотентность в `subscriptionService.ts`. Не сделано: Server API (запрос статуса у Apple), App Attest, очередь повторов
- [ ] Backend: Analytics Service для server-side событий
- [x] iOS: Онбординг + создание профиля ребёнка — экраны и API-клиент в `ios/`, проверено в симуляторе iPhone 16 Pro (Xcode 16.4)
- [x] iOS: Экран генерации сказки (Quick Story) — экран «Создаём сказку», путь первой сказки и экран «Сочинить» (герои, формат, тема, мир, длина)
- [x] iOS: Reading Mode (текст + иллюстрации) — мораль, финальная фраза, размер текста; тёмный/светлый режим по времени суток и закладка впереди
- [x] iOS: Библиотека историй — вкладки «Сегодня», «Сказки», «Дети», избранное, прогресс, поиск, удаление, редактирование профиля, офлайн-кэш
- [x] iOS: Пейволл + подписка — StoreKit 2 (`SubscriptionStore`, `StoreKitStorefront`): Family и Family+, год и месяц, цены из магазина, покупка, restore, `Transaction.updates`, синхронизация при запуске; на живой StoreKit в симуляторе не прогонялось (нужен запуск из Xcode со схемой, где подключён `Skazochnik.storekit`)
- [ ] iOS: Analytics SDK + AppsFlyer + ATT prompt timing
- [ ] TestFlight beta (20–50 пользователей)

### Phase 2 — Сериалы и polish (4–6 нед)
- [x] Story Arc: сериалы — бэкенд (`story_arcs`, `POST /v1/stories/:id/parts`, лимиты активных серий) и iOS (формат на «Сочинить», экран серии). Блокировки по дням и push-напоминаний нет
- [ ] Push Notifications: ежевечерние напоминания
- [ ] «Режим ночника» (тёмный UI)
- [ ] iCloud sync
- [ ] Экспорт в PDF
- [x] On-device TTS и audio playback model — `NarrationController`, `AVSpeechBackend`, фоновое воспроизведение, плеер в читалке
- [ ] Feature flags / Remote Config для лимитов и A/B тестов
- [ ] App Store Submit

### Phase 3 — Рост (после запуска, 2–3 мес)
- [x] Premium TTS аудио-чтение — Gemini TTS (Aoede) через Phygital+; ElevenLabs доступен через тот же API. Сделано раньше плана
- [ ] Испанский / Французский языки
- [ ] Социальный шаринг (истории → картинка для Instagram)
- [ ] «Дневник историй» — красивый архив
- [ ] Family Sharing полная поддержка
- [ ] Paywall experiments и cohort-based pricing tests

### Phase 4 — Монетизация 2.0 (6+ мес)
- [ ] Коллекции стилей иллюстраций (акварель, комикс, пиксель)
- [ ] Создание собственных миров
- [ ] Видео-сцены как premium add-on / Family+ experiment
- [ ] B2B: лицензия для детских садов

---

## 7. Команда и роли

| Роль | Кто нужен | Занятость |
|---|---|---|
| iOS Developer (SwiftUI) | 1 | Full-time |
| Backend Developer (Node.js) | 1 | Full-time |
| Prompt Engineer / AI | 0.5 | Part-time |
| Designer (Figma) | 0.5 | Part-time |
| Product Owner | 1 | Full-time |

*Минимальная команда для MVP: 2 разработчика + PM*

---

## 8. Риски технические

| Риск | Митигация |
|---|---|
| Claude API rate limits при пиковой нагрузке | BullMQ очередь, exponential backoff, кэш похожих запросов |
| Image API нестабильный (gpt-image-1 новый) | Fallback на Flux через Replicate |
| Стоимость изображений выходит за бюджет | Уменьшить кол-во иллюстраций для Free, сжатие WebP |
| Apple review отклонение | Чёткий onboarding с age gate, COPPA compliance |
| Оффлайн доступ | Сохранение всего контента локально в SwiftData |
| StoreKit webhook задержался или потерялся | Periodic entitlement sync, idempotency по transaction_id |
| ATT opt-out снижает точность paid UA | SKAdNetwork, агрегированные cohorts, server-side purchase events |
| COPPA/GDPR-K конфликтует с аналитикой | Не отправлять PII/child text, consent controls, privacy review до beta |
| Видео и premium voices повышают стоимость | Отдельные usage limits, async jobs, add-on pricing, cost monitoring |
| Озвучка медленная: ~8 с на 100 символов (целая часть одним куском > 5 минут) | Текст режется на куски до 600 символов, 6 озвучиваются параллельно (часть на 3,6 мин за ~75 с), эндпоинт отвечает 202 и приложение опрашивает; файл хранится, повторов нет |
| Цена картинки и минуты озвучки в Phygital+ неизвестна | Замерить по счёту Phygital+ до запуска платных тарифов; `estimatedCostUsd` пока 0; лимит минут премиум-голоса |
| Один ключ Phygital+ на картинки и озвучку, нет лимитов запросов в документации | Параллелизм ограничен, ошибки провайдера дают 502 и повтор, картинки не блокируют сказку |
| Гостевые аккаунты: каждый вызов `/auth/anonymous` даёт новый 7-дневный триал | Rate limiting по IP, App Attest / DeviceCheck перед запуском, привязка триала к Apple ID после входа |
| Feature flags ломают paywall/entitlements | Server-side source of truth, audit log, rollback config |

---

## 9. Расширяемость и новые фичи

### 9.1 Provider interfaces

Каждый внешний сервис должен быть адаптером за стабильным интерфейсом. Бизнес-логика не должна знать конкретный SDK Anthropic, OpenAI, AppsFlyer или Amplitude.

| Интерфейс | Возможные реализации |
|---|---|
| `TextGenerator` | Claude Haiku, Claude Sonnet |
| `ImageGenerator` | Phygital+ (gemini-image), OpenAI gpt-image-1, mock |
| `AudioGenerator` | AVSpeechSynthesizer metadata, ElevenLabs |
| `VideoGenerator` | Future provider |
| `AnalyticsProvider` | Amplitude, Firebase |
| `AttributionProvider` | AppsFlyer, Branch |

### 9.2 Step-based worker

Worker выполняет генерацию как граф шагов, а не как один большой процесс:

```
build_prompt
  → generate_text
  → safety_check
  → parse_media_prompts
  → generate_images
  → generate_audio
  → generate_video
  → persist_story_and_media
  → notify_parent
  → track_events
```

Каждый шаг идемпотентен и сохраняет статус в `generation_job_steps`. Если image provider упал, можно повторить только `generate_images`, не регенерируя текст.

### 9.3 Feature flags и product config

Remote config хранит:
- лимиты по тарифам (`quick_story_per_week`, `max_active_arcs`, `premium_voice_minutes`);
- включение новых медиа (`audio_enabled`, `video_enabled`);
- выбор provider (`image_provider=openai|flux`, `text_model=haiku|sonnet`);
- A/B тесты paywall copy, trial length и onboarding flow.

Entitlement Service остаётся source of truth: даже если клиент показывает кнопку, backend повторно проверяет доступ перед дорогими AI-операциями.

### 9.4 API versioning

Публичные API начинаются с `/v1`: `/v1/profiles`, `/v1/stories`, `/v1/entitlements`, `/v1/media`, `/v1/events`. Новые фичи добавляются расширением response schema и feature flags; breaking changes идут в новую версию API.

### 9.5 Рекомендуемая структура репозитория

```
/ios                — SwiftUI, StoreKit, AppsFlyer, analytics SDK (Swift Package + XcodeGen)
/apps/api          — Hono, auth, entitlements, story APIs
/packages/worker   — BullMQ step pipeline
/packages/shared   — event names, entitlements, API types
```

---

## 10. Журнал решений

| Решение | Почему |
|---|---|
| iPhone-first, iPad позже | Прототип дизайна сделан под iPhone; документы приведены к нему |
| Гостевой аккаунт до входа, Apple ID привязывается позже | Родитель проходит онбординг и читает первую сказку без регистрации |
| Тексты: Claude Haiku 4.5; безопасность: вторым запросом, отказ закрывает доступ (fail closed) | Дёшево и быстро, сказка не показывается без проверки |
| Картинки: Phygital+ `gemini-image` (v3_1_lite для standard, v3 для hd), WebP на сервере | Один ключ даёт все модели; качество проверено глазами; PNG 2 МБ слишком тяжёл |
| Картинки одной сказки параллельно | 3 картинки ~13 с каждая, последовательно было бы ~40 с |
| Серия = сказка с форматом `story_arc_part` и записью в `story_arcs` | Библиотека, прогресс и удаление работают как у обычных сказок |
| Части серии пишутся по запросу, без блокировки по дням | Родитель решает, когда продолжать; блокировку можно добавить позже без смены API |
| Серия только для сохранённых профилей | Следующие части должны писаться для тех же героев |
| Связность серии: `SEED` + три последних `SUMMARY`, а не длинный контекст | Дёшево, проверено на живых частях |
| Голос устройства бесплатен всем, премиум-голос Family+ | Системный голос ничего не стоит; премиум стоит денег провайдеру |
| Премиум-голос: Gemini TTS, Aoede, модель Pro, подсказка «читай как добрая мама» (вариант 5 из пяти образцов, выбран на слух) | Системный голос звучал «как робот»; образцы сравнивались вживую |
| Озвучка асинхронна: 202 `processing` и опрос раз в ~5 с | Часть озвучивается ~75 с, запрос не должен висеть |
| Озвучка режется на куски до 600 символов и склеивается (ID3 удаляется) | Время растёт линейно с длиной текста, параллельные куски быстрее |
| Один файл озвучки на часть, хранится в `media_assets` и в `Caches/narration` | Повторное прослушивание мгновенное и офлайн |
| Подписки: приложение отдаёт серверу подписанные транзакции StoreKit 2, сервер проверяет подпись Apple сам (цепочка до Apple Root CA G3 + маркерные OID) | Источник истины по тарифу на сервере; не нужен Server API и ключи Apple для старта |
| Тестовый триал остаётся серверным, у продуктов Apple нет introductory offer | Триал без карты по PRD; два триала подряд не нужны |
| Во время billing retry без grace period доступа нет; во время grace period есть | Так ведёт себя App Store; PRD это допускает |
| Restore переносит подписку на текущий аккаунт | Подписанная транзакция приходит только с устройства Apple ID-владельца; иначе потерянный гостевой аккаунт навсегда держал бы подписку |
| Ключи только в `.env` (в git не попадает), сервер сам читает `.env` | Ключи нельзя печатать в чат и коммитить; ключи, вставленные в чат, лучше перевыпустить |
