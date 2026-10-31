# iOS-приложение «Сказочник»

SwiftUI, iPhone-first (iPad позже), iOS 17+. Референс экранов: `docs/design/prototype/` и `docs/product/UI_Flow.md`.

## Структура

```text
ios/
  Package.swift            Swift Package: весь код приложения
  Sources/SkazochnikCore/  Модели API, APIClient, сессия (Keychain). Без UI
  Sources/SkazochnikUI/    Дизайн-система, экраны, RootView
  Tests/                   Тесты ядра (фикстуры с реального API) и рендер экранов
  App/                     Точка входа приложения (@main) и конфиг
  project.yml              XcodeGen: описание Xcode-проекта
```

Код лежит в пакете, а не в Xcode-проекте, чтобы ядро и экраны собирались и тестировались без Xcode (`swift build`, `swift test` на macOS). `.xcodeproj` генерируется из `project.yml` и не хранится в репозитории.

## Что сделано

- `SkazochnikCore`: модели (зеркало `packages/shared`), `APIClient` (гостевой вход, профили, сказки, entitlements, ошибки 402/422/401), токен в Keychain.
- `SkazochnikUI`: ночная тема, кнопки, чипы, аватар героя, онбординг (приветствие, 3 слайда, имя, возраст, внешность, интересы, мир), `RootView`.
- Онбординг создаёт гостевой аккаунт и профиль через API. Дальше пока заглушка «Профиль создан»: экраны генерации, чтения, «Сегодня», «Сказки», «Сочинить», «Дети» и пейволл — следующие шаги.

## Запуск на iPhone

Нужен Xcode 16 или новее.

```bash
brew install xcodegen
cd ios && xcodegen
open Skazochnik.xcodeproj
```

API для симулятора:

```bash
AUTH_DEV_LOGIN=1 ANTHROPIC_API_KEY=... npm run dev:api
```

Симулятор ходит на `http://localhost:3000`; адрес меняется ключом `API_BASE_URL` в `project.yml`. Bundle id `com.example.skazochnik` и версия — заглушки, их нужно заменить до TestFlight.

## Проверки без Xcode

```bash
cd ios
swift build
swift test
```

- Тесты ядра читают `Tests/SkazochnikCoreTests/Fixtures/*.json`. Это настоящие ответы `apps/api`, поэтому тесты падают, когда контракт API и Swift-модели расходятся. Фикстуры снимаются скриптом на tsx с in-memory БД и фейковым Claude (в репозиторий скрипт не входит; при смене контракта их нужно обновить).
- `ScreenRenderTests` рисует экраны в iPhone-размере через `ImageRenderer`. Чтобы посмотреть картинки: `RENDER_DIR=/tmp/renders swift test --filter ScreenRenderTests`. Ограничения рендера: нативное текстовое поле выводится жёлтой заглушкой, `ScrollView` разворачивается плоско (`snapshotMode`).

## Не проверено

Приложение не запускалось в симуляторе и на устройстве (на машине, где писался код, нет Xcode). Проверены сборка пакета и тесты на macOS, типизация точки входа и снимки экранов. Поведение клавиатуры, жестов, анимаций и шрифтов нужно смотреть в симуляторе. Шрифты Lora и Onest пока не подключены, вместо них системные serif и sans (`Theme.serif`, `Theme.sans`).
