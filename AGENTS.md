# AGENTS.md — техническое описание для ИИ-ассистента

Этот файл — для ИИ (Claude, ChatGPT и т.п.), которому владелец репозитория даёт
задачу «помоги установить/понять эту систему». Здесь — как всё устроено, что где
лежит, как ставится, какие ключи и доступы нужны, и что нельзя ломать. Человеку —
`README.md` (обзор) и `docs/SETUP-KEYS.md` (ключи).

## 1. Что это

Личный ИИ-помощник, живущий на сервере пользователя и общающийся с ним через
Telegram (текст + голос). «Мозг» — Claude Code CLI под подпиской пользователя.
Это НЕ отдельная LLM: система оборачивает Claude Code в Telegram-шлюз и даёт ему
постоянную личность (файлы), память (файлы), навыки (папки) и предохранители (хуки).

## 2. Архитектура и поток сообщения

```
Пользователь (Telegram)
        │  текст / голосовое
        ▼
gateway.py  (Python-процесс, клон qwwiwi/jarvis-telegram-gateway)
        │  • получает update от Telegram Bot API (long-poll)
        │  • проверяет allowlist (только владелец)
        │  • голос → Groq Whisper → текст  [Voice/audio transcript]: ...
        │  • запускает claude -p в workspace агента (с --continue для контекста)
        ▼
Claude Code CLI  (headless, читает workspace: CLAUDE.md + навыки + память)
        │  • выполняет задачу, может звать навыки, запускать bash, писать файлы
        │  • хуки (PreToolUse/PostToolUse) фильтруют опасные команды и ведут лог
        ▼
gateway.py → отправляет ответ обратно в Telegram
```

Ключевой момент: **транскрипцию голоса делает gateway**, а не навык. Агент
получает уже готовый `[Voice/audio transcript]: ...`. Навыков транскрипции нет.

## 3. Структура после установки

`<user>` — имя оператора маленькими буквами (создаётся отдельный системный
пользователь). Всё живёт в его `$HOME`:

```
/home/<user>/
├── claude-gateway/                 # клон qwwiwi/jarvis-telegram-gateway
│   ├── gateway.py                  # сам шлюз (чужой upstream, не редактируем)
│   ├── .venv/                      # python venv шлюза
│   └── config.json                 # конфиг шлюза (собран из config.example.json)
└── .claude-lab/<user>/
    ├── .claude/                    # WORKSPACE агента (его «личность» и мозговые файлы)
    │   ├── CLAUDE.md               # главный системный файл: роль, стиль, правила
    │   ├── core/
    │   │   ├── USER.md             # профиль оператора (заполняется онбордингом)
    │   │   ├── rules.md            # правила/границы
    │   │   ├── MEMORY.md           # долгие заметки (cold, читается по запросу)
    │   │   ├── LEARNINGS.md        # уроки из ошибок
    │   │   ├── warm/decisions.md   # недавние решения
    │   │   └── hot/handoff.md      # передача контекста между сессиями
    │   ├── skills/                 # навыки (папки с SKILL.md + скрипты)
    │   ├── hooks/                  # предохранители (bash-скрипты)
    │   └── settings.json           # регистрация хуков в Claude Code
    └── secrets/                    # ключи (chmod 600), НЕ в git
        ├── telegram-bot-token
        ├── groq-api-key            # опц. (голос)
        └── perplexity-api-key      # опц. (веб-поиск)
```

systemd-сервис: `<user>-gateway.service` (User=<user>, Restart=always).
Логи: `journalctl -u <user>-gateway -f`.

## 4. Процесс установки

Запуск на чистом сервере (Ubuntu 22/24) ПОД ROOT: `sudo bash install.sh`.
Что делает `install.sh` (9 шагов, идемпотентен):

1. Спрашивает: имя оператора, имя агента, Telegram ID (только цифры), токен бота,
   Groq-ключ (опц.). Секретный ввод скрыт. **Не передавать секреты аргументами**
   (попадут в history) — только на запрос.
2. Ставит системные пакеты: python3/venv/pip, git, ffmpeg, curl, jq.
3. Ставит Node.js 20 + Claude Code CLI (`@anthropic-ai/claude-code`), проверяет.
4. Создаёт отдельного пользователя `<user>` (без пароля, без sudo).
5. Клонирует gateway (qwwiwi upstream) под пользователя.
6. Python venv + requirements шлюза.
7. Разворачивает workspace: копирует навыки/память, подставляет плейсхолдеры
   (`{{OPERATOR}}`, `{{AGENT}}`, `{{OWNER_ID}}` в CLAUDE/USER/rules;
   `__SECRETS__` в навыке perplexity; `__OWNER_ID__/__LAB_DIR__/__AGENT__/__OPERATOR__`
   в config.json; `__WS__/__OPERATOR__` в хуках).
8. Пишет секреты в `secrets/` (chmod 600), собирает `config.json`.
9. Ставит 3 хука и systemd-сервис, передаёт владение файлами пользователю.

Финальный РУЧНОЙ шаг (нельзя автоматизировать — интерактивный вход):
```
sudo -iu <user>      # войти под пользователем агента
claude               # залогиниться аккаунтом Claude ОПЕРАТОРА, потом /exit
exit
systemctl restart <user>-gateway
```
После этого агент отвечает в Telegram.

## 5. Навыки (skills/)

Каждый навык — папка с `SKILL.md` (YAML-заголовок name+description задаёт триггеры).
Claude Code сам решает, когда вызвать, по описанию. Набор из коробки:

- `onboarding` — первый запуск: агент сам расспрашивает оператора и заполняет
  `core/USER.md`, снимает маркер `NOT_YET_ONBOARDED`.
- `perplexity-research` — веб-поиск через Perplexity Sonar. Нужен ключ
  `perplexity-api-key`. Триггеры: «поищи», «ресёрч», «факт-чек», «актуально ли».
- `markdown-new` — чистое извлечение текста статьи по URL.
- `youtube-transcript` — транскрипт YouTube-видео (нужна своя авторизация, см. SETUP-KEYS).
- `quick-reminders` — разовые напоминания через cron.

Голос НЕ навык — его обрабатывает gateway (Groq Whisper).

## 6. Память

- **IDENTITY** (всегда в контексте, через @include): CLAUDE.md, USER.md, rules.md.
- **COLD** (читается по запросу): MEMORY.md, LEARNINGS.md.
- Принцип: урок из ошибки → правка файла (LEARNINGS.md/rules.md), а не «запомню в уме».
- **Опционально — семантическая память** (не входит в шаблон): внешний сервис
  (напр. OpenViking) для поиска по смыслу через тысячи записей. Отдельная установка
  + свой ключ (OpenAI-embeddings), ~$5/мес. Ставить только при упоре в файловую память.

## 7. Ключи и доступы

Обязательное:
- **Подписка Claude** (Max/Pro) — аккаунт ОПЕРАТОРА, вход через `claude` (creds в
  `~/.claude/.credentials.json`). НЕ чужой аккаунт (риск бана за impossible-travel).
- **Telegram-бот** — токен от @BotFather → `secrets/telegram-bot-token`.
- **Telegram ID оператора** — allowlist в config.json (только он может писать боту).
- **root на сервере** — только для установки (создать пользователя, пакеты). Рантайм
  идёт под непривилегированным `<user>`.

Опциональное:
- **Groq** (`secrets/groq-api-key`) — голосовые. Бесплатно, console.groq.com. Читает gateway → нужен restart.
- **Perplexity** (`secrets/perplexity-api-key`) — веб-поиск. Платно по расходу. Читает навык → restart не нужен.
- **OpenAI** — только если подключают семантическую память (OpenViking).

## 8. Что ИИ обязан соблюдать при работе с этой системой

- Секреты НИКОГДА не печатать в stdout/лог/чат. Читать из файла в момент использования.
- `secrets/` — chmod 600, вне git (`.gitignore` уже это закрывает). Не коммитить ключи.
- `gateway.py` — чужой upstream (qwwiwi). Не форкать/не править в этом репо; при
  нужде — параметры через config.json.
- Хуки — предохранитель, не замена осторожности. `block-dangerous` (PreToolUse→Bash)
  блокирует rm -rf/DROP/force-push и т.п.; `protect-files` предупреждает о правках
  чувствительных файлов; `log-commands` (PostToolUse→Bash) ведёт аудит-лог.
- Деструктив (rm -rf, DROP TABLE, снос данных) — только с явного подтверждения оператора.
- Плейсхолдеры (`{{...}}`, `__...__`) в шаблонах подставляет install.sh — не хардкодить
  реальные значения в `*.template` / `config.example.json`.

## 9. Диагностика

- Сервис жив? `systemctl status <user>-gateway`
- Логи в реальном времени: `journalctl -u <user>-gateway -f`
- Не отвечает на голос: проверь `secrets/groq-api-key` и лог на `GROQ key missing`.
- Не отвечает вообще: (1) `claude` залогинен под `<user>`? (2) токен бота верный?
  (3) Telegram ID оператора в allowlist config.json? (4) сервис перезапущен?
- Аудит команд агента: `<workspace>/logs/` (пишет хук log-commands).
