# API-контракт: анонсы, публикации, промокоды (для клиентов Woodstream)

Базовый URL: `https://chat.woodstream.online/api/chat-panel`
Аутентификация: Bearer-токен Sanctum.
- Веб/новые клиенты: `POST /login` → токен.
- Приложение Woodstream (магазин): `POST /mobile-auth` c `mobile_access_token` клиента (мост уже существует) → `access_token`.

Все новые endpoint'ы реализованы и покрыты тестами в `woodstream_prod-main` (коммиты `5a7f88f`, `d6b403a`).

## 1. Лента анонсов (для раздела чатов приложения Woodstream, iOS и веба)

`GET /announcements?limit=20&before_id=<id>`

Ответ:
```json
{
  "success": true,
  "items": [
    {
      "id": 12,
      "body": "Текст анонса",
      "attachments": [
        {"type": "image", "order": 0, "url": "https://.../storage/publications/xxx.jpg",
         "path": "storage/publications/xxx.jpg", "mime_type": "image/jpeg", "size": 123456}
      ],
      "comments_enabled": true,
      "published_at": "2026-08-02T10:00:00+00:00",
      "internal_message_id": 501,
      "conversation_id": 7
    }
  ],
  "next_before_id": 3
}
```
- Сортировка: новые сверху (`published_at desc`). Пагинация курсором `before_id`.
- Источник — внутренний backend; Telegram не участвует.
- Рекомендуется клиентское кеширование ленты и превью изображений.

`POST /publications/{id}/viewed` — отметить просмотр (для статистики охвата). Идемпотентно.

## 2. Публикации (только manager/admin; для остальных — 403)

| Метод | Путь | Назначение |
|---|---|---|
| GET | `/publications?status=` | Список с результатами каналов, автором, просмотрами |
| POST | `/publications` | Создать: `body`, `attachments[]` (multipart, до 10 фото ≤15 МБ), `channels[]` из `internal,whatsapp,telegram,vk,site`, `comments_enabled`, `publish_now` или `scheduled_at`+`timezone` |
| GET | `/publications/{id}` | Карточка |
| PATCH | `/publications/{id}` | Правка текста/каналов (черновик/запланирована); `comments_enabled` — в любом статусе; правка текста после публикации обновляет сообщение мегагруппы |
| DELETE | `/publications/{id}` | Удалить (удаляет и сообщение мегагруппы) |
| POST | `/publications/{id}/publish` | Опубликовать сейчас |
| POST | `/publications/{id}/schedule` | `scheduled_at`, `timezone` (хранится в UTC) |
| POST | `/publications/{id}/cancel` | Отменить черновик/запланированную |
| POST | `/publications/{id}/retry-channel` | `channel` — повторная отправка только в один канал |
| GET | `/publications/{id}/stats` | Просмотры, уникальные, реакции, комментарии, статусы каналов, ошибки |

Статусы публикации: `draft, scheduled, publishing, published, partially_published, failed, cancelled`.
Статусы канала: `pending, sending, published, error, disabled, retry_required`.

## 3. Комментарии и реакции в мегагруппе

Комментарий — обычное сообщение в broadcast-чате с `reply_to_message_id`, указывающим на `internal_message_id` публикации (или на другой комментарий этой публикации):
`POST /message/{conversation_id}` с `message`, `reply_to_message_id`.

Серверные правила (уже включены):
- обычный пользователь не может отправить свободное сообщение в broadcast — 403;
- комментарий к публикации с выключенными комментариями — 403 «Комментарии к этой публикации отключены»;
- клиент должен скрывать поле ввода, если `comments_enabled=false`.

Реакции (существующий endpoint): `POST /messages/{messageId}/reaction` с `emoji` (toggle). Realtime — канал Reverb `private-chat.conversation.{id}`, события `MessageSent`, `MessageChanged`.

## 4. Промокоды и подарочные карты (только manager/admin)

| Метод | Путь | Назначение |
|---|---|---|
| GET | `/promo-tools/search?q=CODE` | Поиск по коду среди промокодов и карт (мин. 3 символа) |
| GET | `/promo-tools/promo-codes/{id}` | Статус, срок, лимиты, клиент, история применений |
| POST | `/promo-tools/promo-codes/{id}/check` | `client_id?`, `order_amount` → применимость и размер скидки |
| POST | `/promo-tools/promo-codes/{id}/redeem` | Транзакционное применение; повторное применение одноразового кода → 422 |
| GET | `/promo-tools/gift-cards/{id}` | Баланс, номинал, статус, срок, история операций |
| POST | `/promo-tools/gift-cards/{id}/activate` | Активация (защита от повторной — транзакция + lockForUpdate) |
| POST | `/promo-tools/gift-cards/{id}/redeem` | `amount`, `order_id?` — списание; больше остатка не спишется |

Все операции пишутся в журнал `chat_audit_logs` (кто, что, когда, метаданные).

## 5. Изменения, необходимые в клиенте приложения Woodstream (репозиторий недоступен)

1. В разделе чатов добавить экран «Анонсы»: запрос `GET /announcements` после `mobile-auth`, рендер текста, дат и альбомов (сетка превью → полноэкранный просмотр со свайпом, порядок по `order`).
2. Пагинация: подгрузка по `next_before_id`; pull-to-refresh.
3. Кеш: хранить последнюю страницу локально, изображения — в дисковом кеше.
4. Отправлять `POST /publications/{id}/viewed` при фактическом показе анонса.
5. Убрать любые чтения анонсов из Telegram, если они были.

## 6. Переменные окружения backend (новые)

```
WHATSAPP_ALBUM_SERVICE_URL=   # URL Node-сервиса Baileys (например http://127.0.0.1:3000)
WHATSAPP_ANNOUNCE_JID=        # JID группы WhatsApp, например 120363408082173885@g.us
TELEGRAM_ANNOUNCE_CHAT_ID=    # ID Telegram-канала анонсов (например -1001442605708)
# уже существующие: TELEGRAM_BOT_TOKEN / TELEGRAM_POST_BOT_TOKEN, ключи Green API,
# LOCAL_VK_AUTOPUBLISH_ENABLED (включает VK-канал)
```

Миграции: `php artisan migrate --force` (4 новые таблицы: `publications`, `publication_channel_results`, `publication_views`, `chat_audit_logs`). Планировщик: убедиться, что systemd/cron вызывает `php artisan schedule:run` каждую минуту — команда `publications:process-due` уже зарегистрирована.
