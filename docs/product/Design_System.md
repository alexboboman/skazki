# Design System — Bedtime Stories AI

**Версия:** 0.1  
**Статус:** Draft  
**Платформа MVP:** iPadOS / SwiftUI

---

## 1. Design Principles

1. **Calm first.** UI должен помогать родителю и ребёнку успокоиться, а не стимулировать бесконечное взаимодействие.
2. **Parent-controlled.** Генерация, подписки, видео и privacy-настройки управляются родителем.
3. **Readable at night.** Текст, контраст, spacing и яркость оптимизируются под вечернее чтение.
4. **Soft monetization.** Paywall объясняет ценность, но не мешает читать уже созданные истории.
5. **Media-ready.** Компоненты должны поддерживать текст, изображения, аудио и будущие видео без отдельного UI-подхода для каждого типа.

---

## 2. Visual Direction

**Настроение:** тёплая bedtime-сказка, мягкий свет, бумажная книжность, спокойные иллюстрации.

**Не использовать в MVP:**
- агрессивные яркие CTA;
- игровые streak-механики;
- шумные анимации;
- scary/dark визуальные темы;
- автозапуск видео или звука.

---

## 3. Цветовая Палитра

| Token | Light | Dark / Night | Использование |
|---|---|---|---|
| `background.primary` | `#FFF8EF` | `#151824` | Основной фон |
| `background.card` | `#FFFFFF` | `#202435` | Карточки |
| `text.primary` | `#2B2118` | `#F6EBDD` | Основной текст |
| `text.secondary` | `#6D6258` | `#B7AFA4` | Вторичный текст |
| `accent.primary` | `#8B6EDB` | `#B8A7FF` | Primary actions |
| `accent.warm` | `#F2A65A` | `#E6A85C` | Highlights, bedtime warmth |
| `border.soft` | `#E8DCCF` | `#33384D` | Разделители |
| `success` | `#4F9D69` | `#7BCB94` | Успешные состояния |
| `error` | `#C75C5C` | `#FF8A8A` | Ошибки |

Nightlight mode должен снижать яркость и уходить в тёплые тона, без чисто белых поверхностей.

---

## 4. Typography

| Role | iPad Size | Weight | Notes |
|---|---:|---|---|
| Display | 34 | Semibold | Onboarding, paywall hero |
| Title | 28 | Semibold | Заголовки экранов |
| Section Title | 22 | Semibold | Блоки Home/Library |
| Body | 19 | Regular | Основной UI-текст |
| Reading Body | 23–30 | Regular | Настраивается родителем |
| Caption | 15 | Regular | Подсказки, metadata |

SwiftUI должен поддерживать Dynamic Type. Reading Mode обязан иметь отдельный control для размера текста.

---

## 5. Layout

**iPad baseline:**
- Max content width: `760–900 pt`
- Card radius: `24 pt`
- Primary page padding: `32 pt`
- Card padding: `20–28 pt`
- Vertical rhythm: `12 / 16 / 24 / 32 pt`

**Navigation:**
- `TabView` для Home, Library, Settings.
- Reading Mode — full-screen detail.
- Paywall — modal sheet/full-screen в зависимости от контекста.

---

## 6. Core Components

### 6.1 Primary Button

Использование: основное действие на экране.

**States:**
- default
- pressed
- loading
- disabled

**Examples:**
- `Сгенерировать сказку`
- `Попробовать 7 дней бесплатно`
- `Создать профиль`

---

### 6.2 Secondary Button

Использование: альтернативное действие без потери контекста.

**Examples:**
- `Продолжить с Free`
- `Изменить параметры`
- `Позже`

---

### 6.3 Story Card

Показывает историю в Home/Library.

**Content:**
- title
- child name
- format
- date
- progress/read state
- media badges: image/audio/video
- offline indicator

---

### 6.4 Child Profile Card

Показывает активного ребёнка и быстрый switch.

**Content:**
- name
- age
- language
- interests preview
- subscription/profile limit indicator when relevant

---

### 6.5 Interest Chip

Multi-select для интересов и миров.

**States:**
- default
- selected
- disabled

---

### 6.6 Generation Progress

Показывает этап генерации без технического шума.

**Steps:**
- `Готовим идею сказки...`
- `Пишем добрую историю...`
- `Проверяем безопасность...`
- `Добавляем иллюстрации...`
- `Сохраняем в библиотеку...`

---

### 6.7 Media Block

Универсальный контейнер для `image`, `audio`, `video`.

**Rules:**
- Image: lazy loading, placeholder, offline cache indicator.
- Audio: play/pause, progress, sleep timer.
- Video: no autoplay, visible parent-controlled play button.

---

### 6.8 Paywall Plan Card

**Content:**
- plan name
- price monthly/yearly
- key benefits
- trial badge
- selected state

---

## 7. Screen Templates

### Home Template

```text
[Profile switcher]
[Hero card: bedtime CTA]
[Quick options]
[Continue reading]
[Story Arc teaser]
```

### Reading Template

```text
[Minimal top bar]
[Story title]
[Story content]
[Inline media blocks]
[Reading controls]
```

### Paywall Template

```text
[Contextual headline]
[Benefits]
[Plan cards]
[Primary CTA]
[Secondary Free action]
[Restore / Terms / Privacy]
```

---

## 8. Accessibility

- Dynamic Type everywhere.
- VoiceOver labels for story controls, paywall actions and media.
- No critical information by color alone.
- Touch targets at least `44 x 44 pt`.
- Nightlight mode must preserve readable contrast.
- Video/audio controls must be keyboard and switch-control friendly.

---

## 9. Motion

Use subtle motion only:
- gentle fade/slide between onboarding screens;
- soft progress animation during generation;
- no flashing, bouncing or reward-style animations at bedtime;
- respect Reduce Motion.

---

## 10. Future Figma / Claude Design Handoff

When moving into visual design, create frames in this order:

1. Onboarding
2. Profile Creation
3. Home
4. Generation Loading
5. Reading Mode
6. Library
7. Paywall
8. Settings

Each frame should include light and night variants where relevant. Components should map back to the Core Components section above, so SwiftUI implementation can use the same structure.
