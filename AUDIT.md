# Аудит экосистемы Woodstream Chat (Этап 1)

Дата аудита: 2026-08-02.

## 1. Обнаруженные репозитории и их расположение

| Компонент | Путь | Технологии | Статус |
|---|---|---|---|
| iOS-мессенджер («woodchat») | `~/Desktop/woodchat` | Swift, SwiftUI, StreamChatSwiftUI SDK v5 beta | Стоковый SDK GetStream + демо-приложение. **Не git-репозиторий** |
| Основной backend + сайт магазина | `~/Desktop/woodstream/messenger_v2/woodstream_prod-main` | Laravel 12, PHP 8.2+, Filament 3, Reverb (WebSocket), Sanctum, web-push, MySQL | Рабочий production-код (chat.woodstream.online / woodstream.online). **Не git-репозиторий** |
| Веб-версия мессенджера | `~/Desktop/woodstream/messenger_v2/Woodstream-Messenger-VUE-3` | Vue 3, Pinia, Tailwind, laravel-echo + pusher-js (Reverb), PWA (sw.js) | Рабочая, есть git |
| Node-сервис интеграций | `~/Desktop/woodstream` (src/, dist/, bin/) | Node.js/TypeScript, Express 5, Baileys 7 (WhatsApp), gramjs/Bot API (Telegram) | Рабочий: WhatsApp-альбомы, миграция и автопубликация TG→WA |
| VK-паблишер | `~/Desktop/woodstream/chrome-extension/vk-publisher` + `LocalVkPublisherController`, `TgQueueController` в Laravel | Chrome-расширение + Laravel-очередь | Рабочий локальный пайплайн VK |
| Мост магазина Woodstream (мобильное приложение товаров) | `~/Desktop/woodstream/store-mobile-bridge` | PHP (Laravel-контроллеры: `MobileController` ~2900 строк, `ManagerController`, `ChatService`, `PushNotificationService`) | Выгрузка кода из магазина; в prod-main есть актуальные `MobileController`, `ChatPanelMobileController` |
| Промокоды и подарочные карты | `~/Desktop/woodstream/store-promo-giftcards` + те же модели/миграции уже в prod-main | Laravel-модели, сервисы, Filament-ресурсы, миграции | **Уже реализовано** в prod-main (модели `PromoCode`, `PromoRedemption`, `GiftCard`, `GiftCardTransaction`, `GiftCardDesign`, сервисы, Filament-админка) |

## 2. Архитектура (как есть)

```
┌────────────────────────┐   HTTPS + Reverb WS   ┌──────────────────────────────┐
│ Vue 3 веб-мессенджер   │◄─────────────────────►│ Laravel (chat.woodstream.online)│
│ (chat-panel API)       │                       │  ChatPanelController (3561 стр.)│
└────────────────────────┘                       │  Sanctum, роли user/manager/admin│
┌────────────────────────┐  /chat-panel/mobile-auth│  Reverb broadcast, web-push,    │
│ Приложение Woodstream  │◄─────────────────────►│  mobile push tokens             │
│ (магазин, раздел чатов)│                       │  MySQL (conn. "production")     │
└────────────────────────┘                       └──────────┬───────────────────┘
┌────────────────────────┐                                  │ TG→VK очередь (TelegramVkPost)
│ iOS StreamChatSwiftUI  │──X── НЕ СВЯЗАНО ──X──            │ LocalVkPublisher + chrome-ext
│ (Stream SaaS,          │                                  ▼
│  api key zcgvnykxsfm8) │                       ┌──────────────────────────────┐
└────────────────────────┘                       │ Node-сервис (Express+Baileys)│
                                                 │ /whatsapp/send-album         │
                                                 │ /telegram/migrate-channel    │
                                                 │ TG autopublish → WhatsApp    │
                                                 └──────────────────────────────┘
```

Ключевой факт: **внутренняя система чатов уже существует и не зависит от Telegram/WhatsApp** — это Laravel-backend + Vue-веб. Внешние каналы (WA/TG/VK) уже используются как каналы дистрибуции через отдельные сервисы.

**Главная архитектурная проблема:** iOS-приложение в `woodchat` — это стоковый SDK StreamChatSwiftUI (клон репозитория GetStream, v5 beta) с демо-приложением, работающим через SaaS Stream (внешняя платная платформа, демо-ключ `zcgvnykxsfm8` захардкожен в `DemoUser.swift`). Оно **никак не связано** с внутренним backend. Это противоречит основной цели (независимость от внешних платформ, единый источник данных).

## 3. Модели данных backend (соединение `production`, MySQL)

Чаты: `chat_conversations` (типы: `website_open`, `mobile_app`, `external_private`, `internal_group`, `internal_dm`, `broadcast`), `chat_messages` (reply, цитаты, telegram-статусы), `chat_attachments`, `chat_conversation_participants` (менеджеры, роль owner/member/guest), `chat_conversation_user_participants`, `chat_message_reactions` (unique message+user+emoji), `chat_invite_links`, `chat_push_subscriptions` (VAPID), `chat_mobile_push_tokens`, `chat_user_unread_counts`, `chat_conversation_events`.

Пользователи/роли: `users.role` ∈ {user, manager, admin} + `users.is_admin`; `managers`, `duty_managers` (дежурные), `clients` (клиенты магазина, мост через `mobile_access_token`).

Публикации/интеграции: `telegram_vk_posts` (очередь TG→VK со статусами), блог/статьи с `published_at`.

Промокоды/карты: `promo_codes`, `promo_redemptions`, `gift_cards`, `gift_card_transactions`, `gift_card_designs`.

## 4. Существующий API (основное, `routes/api.php`)

- `/api/chat-panel/*` (Sanctum): login, mobile-auth, join-by-link, me, conversations, messages (пагинация), send/edit/delete/forward, реакции (toggle), typing, участники, create-group/create-internal, direct-conversation, invite links, push (key/subscribe/badge), stats, users CRUD (admin).
- `/api/.../chat/*` — чаты мобильного приложения магазина (`MobileController`): start/list/messages/send/close.
- Node-сервис: `POST /whatsapp/send-album`, `POST /telegram/migrate-channel`, `POST /telegram/send-post-by-link`, webhook `/api/telegram/post-webhook`, VK-очередь для расширения.

## 5. Что уже работает (покрытие требований)

| Требование ТЗ | Статус |
|---|---|
| 1. Внутренние чаты (личные, группы, realtime, reply, forward, unread, пагинация) | Есть на backend + веб. Нет в iOS (не подключено) |
| 2. Роли user/manager/admin, проверки на сервере | Частично: роли есть, `requireAdmin()` есть, но матрица прав неполная (создание групп доступно менеджерам — проверить создание обычным пользователем) |
| 3. Мегагруппа анонсов | Частично: тип `broadcast` существует; нет сущности «публикация», нет черновиков/статусов |
| 4. Отложенные публикации | Нет (есть только очередь TG→VK для другого пайплайна) |
| 5. Единый центр публикаций | Нет. Есть разрозненные каналы: TG→WA (Node), TG→VK (Laravel+расширение). Источник сейчас — Telegram-канал, а должен быть внутренний backend |
| 6. Анонсы в приложении Woodstream | Частично: мост `mobile-auth` есть, раздел чатов в приложении магазина есть; вывода broadcast-анонсов как ленты нет |
| 7. Фотоальбомы | Частично: WA-альбомы в Node-сервисе есть; в чат-моделях `chat_attachments` есть, единый «альбом» как сущность — проверить; в iOS нет |
| 8. Комментарии к публикациям + вкл/выкл | Нет |
| 9. Реакции | Есть на backend (toggle, unique) и в веб; realtime — проверить; в iOS — есть в SDK Stream, но это другая система |
| 10. Статистика публикаций | Частично: `getStats` по чатам есть; просмотры/охват публикаций — нет |
| 11. Промокоды и подарочные карты | В значительной мере есть (модели, сервисы, транзакции, Filament-админка). Нет API для менеджеров в чат-панели |
| 12. Веб-версия | Есть и покрывает чаты; функций публикаций/статистики/промокодов в ней нет |
| 13. Русская локализация | Веб и backend — русские. iOS SDK — только `en.lproj` |
| 14. Push-уведомления | Веб (VAPID) и мобильные токены есть; по публикациям/комментариям — нет |
| 15. Backend и безопасность | Основа есть (Sanctum, роли); требуется аудит: IDOR, rate limiting, журнал действий менеджеров, логирование в `temp_ai.log` (плохо), секреты в `.env` в папке, `auth_info_baileys` (сессия WhatsApp) в открытом виде |
| 16. App Store | Не готово: приложение — демо SDK, bundle id, signing, privacy — всё демо-значения |
| 17. Тесты | Laravel: phpunit присутствует; Node/Vue: нет; iOS: тесты SDK (снапшоты), не приложения |

## 6. Обнаруженные проблемы

1. **iOS-приложение не является продуктом** — это SDK-репозиторий GetStream с демо. Подключение к внутреннему Laravel API у StreamChatSwiftUI невозможно (SDK жёстко привязан к Stream SaaS). Нужно решение (см. открытые вопросы в PROJECT_REQUIREMENTS.md).
2. Источником публикаций сейчас является Telegram-канал (пайплайны TG→WA, TG→VK) — прямо противоречит требованию «данные не должны браться из Telegram».
3. `woodstream_prod-main` и Node-сервис — не под git; правки рискованны, нет истории.
4. Секреты: `.env` с боевыми ключами лежит в папках, WhatsApp-сессия `auth_info_baileys/` в открытом виде, demo API key захардкожен в Swift.
5. Отладочное логирование в `ChatMessage::booted()` пишет в `temp_ai.log` в корне проекта на каждое сообщение — деградация производительности и мусор.
6. Двойные копии кода: `store-mobile-bridge` и `store-promo-giftcards` дублируют файлы prod-main (риск рассинхронизации; источник истины — prod-main).
7. Нет очереди фоновых задач для публикаций (Laravel scheduler используется, но воркеры очередей для чатов не настроены — проверить `QUEUE_CONNECTION`).
8. Локальная среда: PHP 8.5 / Composer / Node есть; локальной MySQL-базы `new_woodstre` может не быть — миграции локально не проверить без дампа.
