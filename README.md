# AGROMAX

Веб и мобильное рабочее пространство агронома: наблюдение → уточнение → подтверждение → повторный осмотр → история поля.

Новая учебная версия. Старые сдачи и интеграции в `Agents/AGROMAX-*` не используются как рабочая база и не изменяются.

## Структура

- `apps/web` — React + TypeScript + Vite.
- `apps/mobile` — Flutter, Riverpod, SQLite, камера и GPS.
- `apps/api` — Hono, Supabase и агент с DeepSeek/MiMo.
- `packages/contracts` — типы, OpenAPI, генерируемые маршруты TypeScript/Dart.
- `supabase` — локальная конфигурация и миграции с RLS.

## Локальный запуск

Нужны Node.js 22+, Docker, Flutter и нативные SDK для нужной платформы. Пакеты фиксируются lock-файлами. Docker должен быть запущен.

```sh
npm ci
npx supabase start
# Заполнить apps/api/.env по apps/api/.env.example.
# Локальные ключи Supabase: npx supabase status (не публиковать вывод).
npm run dev:api
# В другом терминале
npm run dev:web
```

Веб: http://localhost:5173, API: http://localhost:8787. API не выдаёт ключи моделей клиентам. Вход «Демо» создаёт отдельное хозяйство с синтетическими полями.

```sh
cd apps/mobile
flutter pub get
flutter run --dart-define=API_BASE_URL=http://localhost:8787
# Для Android Emulator вместо localhost: http://10.0.2.2:8787
```

Для телефона в одной сети требуется адрес компьютера и явная настройка API origin; публичное развёртывание пока не является частью локального запуска.

## Проверки

```sh
npm run contracts:generate
npm run typecheck
npm test
npm run build
cd apps/mobile
flutter analyze
flutter test
```

Сценарии проверки и фактические результаты — `docs/VERIFICATION.md`. Успешная сборка не означает проверку на телефоне. Доступность провайдеров проверяется отдельно с реальными ключами.

## Ограничения

LiteRT и собственная модель компьютерного зрения — следующий этап. Фото сохраняется как материал наблюдения; диагноз и лечебные назначения не считаются подтверждёнными результатами. Метрики демо не доказывают точность модели или экономию реального хозяйства.
