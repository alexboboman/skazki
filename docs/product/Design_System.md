# Design System — Bedtime Stories AI

**Версия:** 0.1  
**Статус:** Draft  
**Платформа MVP:** iOS (iPhone) / SwiftUI. iPad — следующий этап, размеры ниже помечены отдельно

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

Актуальные значения цветов, радиусов и анимаций v1 лежат в `docs/design/prototype/styles.css` (ночная палитра: `--bg-0 #100c1f`, `--bg-1 #1a1430`, `--accent #B8A7FF`, `--gold #E6A85C`, `--text #F6EBDD`).

## 4. Typography

Шрифты по прототипу: **Lora** (serif: заголовки, поля ввода, текст сказки) и **Onest** (sans: интерфейс). Оба открытые, нужно подключить в бандл iOS-приложения.

| Role | iPhone (v1) | iPad (позже) | Шрифт, начертание |
|---|---:|---:|---|
| Display | 33 | 34 | Lora Medium |
| Title | 27 | 28 | Lora Medium |
| Section Title | 22 | 22 | Lora Medium |
| Body | 16.5 | 19 | Onest Regular |
| Reading Body | 19, настраивается | 23–30 | Lora Regular, межстрочный 1.72 |
| Caption | 13.5 | 15 | Onest Regular |
| Kicker | 13, капс, трекинг 0.18em | 13 | Onest SemiBold |

SwiftUI должен поддерживать Dynamic Type. Reading Mode обязан иметь отдельный control для размера текста.

---

## 5. Layout

**iPhone baseline (прототип, экран 402×874):**
- Page padding: `26 pt`
- Card radius: `26 pt`, tile radius: `22 pt`, кнопки и чипы: pill, высота кнопки `56 pt`
- Card padding: `18–22 pt`
- Фон экрана: радиальный градиент `bg-2 → bg-1 → bg-0`, поверх «северное сияние» (размытые пятна) и мерцающие звёзды

**iPad (следующий этап):**
- Max content width: `760–900 pt`
- Card radius: `24 pt`
- Primary page padding: `32 pt`
- Card padding: `20–28 pt`
- Vertical rhythm: `12 / 16 / 24 / 32 pt`

**Navigation:**
- Нижняя панель из прототипа: «Сегодня», «Сказки», «Сочинить» (центральная золотая кнопка), «Дети»; настройки открываются из «Сегодня». Прежний `TabView` для Home, Library, Settings остаётся как вариант для iPad.
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
