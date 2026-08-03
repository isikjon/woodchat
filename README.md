# woodchat

**WoodChat** — внутренний мессенджер компании Woodstream (isikjandev).

iOS-приложение работает с собственным сервером `chat.woodstream.online` — чаты, группы,
мегагруппа анонсов «Вудстрим новости», реакции и публикации не зависят от внешних платформ.

## Структура

- `DemoAppSwiftUI/` — приложение WoodChat (SwiftUI): вход, чаты, анонсы
- `Sources/StreamChatSwiftUI/` — UI-слой чата (форк SDK, лицензия — см. LICENSE)
- `branding/` — логотип и иконка WoodChat
- Документы проекта: `AUDIT.md`, `PROJECT_REQUIREMENTS.md`, `IMPLEMENTATION_CHECKLIST.md`,
  `TECHNICAL_PLAN.md`, `WOODSTREAM_APP_API.md`, `WOODCHAT_CHECKLIST.html`

## Сборка

Xcode 16+, схема `DemoAppSwiftUI`:

```bash
xcodebuild -scheme DemoAppSwiftUI -project StreamChatSwiftUI.xcodeproj \
  -destination 'platform=iOS Simulator,name=iPhone 16 Plus' build
```

Сервер: шлюз `stream-gateway` (Node.js) + Laravel backend — см. WOODSTREAM_APP_API.md.

## Тестовые аккаунты

- менеджер: `test-manager@woodchat.local`
- пользователь: `test-user@woodchat.local`
