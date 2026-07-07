#!/usr/bin/env bash
# install.sh — разворачивает личного Telegram-агента на Claude Code на чистом сервере
# (Ubuntu 22/24). Создаёт ОТДЕЛЬНОГО непривилегированного пользователя и ставит всё
# под ним (безопаснее, чем под root: предохранители строже, урон ограничен $HOME юзера).
#
# Запуск на СЕРВЕРЕ ПОД ROOT (нужен для создания пользователя и системных пакетов):
#   sudo bash install.sh
# Скрипт спросит имя, Telegram ID, токен бота и Groq-ключ интерактивно.
# НЕ передавай токен в командной строке (BOT_TOKEN='...' bash ...) — он попадёт
# в ~/.bash_history. Вводи по запросу; секретный ввод скрыт (эхо выключено).
#
# Секреты НЕ хранятся в репозитории и НЕ хардкодятся: пишутся в secrets/ (chmod 600).
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a  # apt не виснет на needrestart (Ubuntu 22/24)

GW_REPO="https://github.com/qwwiwi/jarvis-telegram-gateway.git"
HERE="$(cd "$(dirname "$0")" && pwd)"

say(){ printf '\n\033[1;33m== %s\033[0m\n' "$1"; }
ok(){ printf '   \033[1;32m✓ %s\033[0m\n' "$1"; }
ask(){ local __v="$1" __p="$2" __in=""; if [ -n "${!__v:-}" ]; then return; fi; read -rp "   $__p: " __in; printf -v "$__v" '%s' "$__in"; }
ask_secret(){ local __v="$1" __p="$2" __in=""; if [ -n "${!__v:-}" ]; then return; fi; read -rsp "   $__p: " __in; echo; printf -v "$__v" '%s' "$__in"; }

[ "$(id -u)" = 0 ] || { echo "Запусти под root:  sudo bash install.sh"; exit 1; }

say "Данные агента"
ask OPERATOR_NAME "Имя оператора (для кого агент, напр. Abdulmalik)"
ask AGENT_NAME    "Имя агента (Enter = Jarvis)"; AGENT_NAME="${AGENT_NAME:-Jarvis}"
ask OWNER_TG_ID   "Telegram ID оператора (только цифры, узнать: @userinfobot)"
ask_secret BOT_TOKEN "Токен бота от @BotFather (ввод скрыт)"
ask_secret GROQ_KEY  "Groq API key для голосовых (Enter = пропустить, ввод скрыт)"
# Санитизация: имена идут в JSON-строки и в имя пользователя — убираем то, что ломает JSON/shell.
OPERATOR_NAME="$(printf '%s' "$OPERATOR_NAME" | tr -d '"\\')"
AGENT_NAME="$(printf '%s' "$AGENT_NAME" | tr -d '"\\')"
LAB_NAME="$(printf '%s' "$OPERATOR_NAME" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9')"; [ -n "$LAB_NAME" ] || LAB_NAME="agent"
[ -n "${BOT_TOKEN:-}" ] || { echo "BOT_TOKEN обязателен"; exit 1; }
[[ "${OWNER_TG_ID:-}" =~ ^[0-9]+$ ]] || { echo "OWNER_TG_ID должен быть числом (Telegram ID), получено: '${OWNER_TG_ID:-}'"; exit 1; }

AGENT_USER="$LAB_NAME"
UHOME="/home/$AGENT_USER"
GW_DIR="$UHOME/claude-gateway"
LAB_DIR="$UHOME/.claude-lab/$LAB_NAME"
WS_DIR="$LAB_DIR/.claude"
SEC_DIR="$LAB_DIR/secrets"
SVC="${LAB_NAME}-gateway"
asuser(){ sudo -H -u "$AGENT_USER" "$@"; }  # -H: HOME=/home/<юзер> (pip/git/npm пишут в свой кэш, не в /root)

say "1/9 Системные зависимости"
apt-get update -qq
apt-get install -y -qq python3 python3-venv python3-pip git ffmpeg curl jq >/dev/null
ok "python3, git, ffmpeg, curl, jq"

say "2/9 Node.js + Claude Code CLI"
if ! command -v node >/dev/null 2>&1; then
  curl -fsSL https://deb.nodesource.com/setup_20.x | bash - >/dev/null
  apt-get install -y -qq nodejs >/dev/null
fi
ok "node $(node -v)"
command -v claude >/dev/null 2>&1 || npm i -g @anthropic-ai/claude-code >/dev/null 2>&1 || true
command -v claude >/dev/null 2>&1 || { echo "ОШИБКА: не удалось установить claude CLI (проверь сеть/npm)"; exit 1; }
ok "claude CLI: $(command -v claude)"

say "3/9 Пользователь $AGENT_USER"
if id "$AGENT_USER" >/dev/null 2>&1; then ok "уже существует";
else adduser --disabled-password --gecos "" "$AGENT_USER" >/dev/null; ok "создан (без пароля, без sudo)"; fi

say "4/9 Gateway (clone qwwiwi upstream)"
if [ -d "$GW_DIR/.git" ]; then asuser git -C "$GW_DIR" pull --ff-only >/dev/null 2>&1 || true; ok "обновлён";
else asuser git clone --depth 1 "$GW_REPO" "$GW_DIR" >/dev/null 2>&1; ok "склонирован в $GW_DIR"; fi

say "5/9 Python venv (под пользователем)"
asuser python3 -m venv "$GW_DIR/.venv"
asuser "$GW_DIR/.venv/bin/pip" install -q --upgrade pip >/dev/null
[ -f "$GW_DIR/requirements.txt" ] && asuser "$GW_DIR/.venv/bin/pip" install -q -r "$GW_DIR/requirements.txt" >/dev/null
ok "venv готов"

say "6/9 Workspace + подстановка данных"
asuser mkdir -p "$WS_DIR/core/warm" "$WS_DIR/core/hot" "$WS_DIR/skills" "$WS_DIR/hooks" "$SEC_DIR"
chmod 700 "$SEC_DIR"
cp -r "$HERE"/workspace/skills/. "$WS_DIR/skills/"
# Навык perplexity-research читает ключ из папки секретов агента — подставляем реальный путь.
[ -f "$WS_DIR/skills/perplexity-research/SKILL.md" ] && \
  sed -i "s#__SECRETS__#${SEC_DIR}#g" "$WS_DIR/skills/perplexity-research/SKILL.md"
cp "$HERE"/workspace/core/*.md "$WS_DIR/core/" 2>/dev/null || true
cp "$HERE"/workspace/core/warm/*.md "$WS_DIR/core/warm/" 2>/dev/null || true
cp "$HERE"/workspace/core/hot/*.md "$WS_DIR/core/hot/" 2>/dev/null || true
subst(){ sed -e "s#{{OPERATOR}}#${OPERATOR_NAME}#g" -e "s#{{AGENT}}#${AGENT_NAME}#g" -e "s#{{OWNER_ID}}#${OWNER_TG_ID}#g" "$1"; }
subst "$HERE/workspace/CLAUDE.md.template"     > "$WS_DIR/CLAUDE.md"
subst "$HERE/workspace/core/USER.md.template"  > "$WS_DIR/core/USER.md"
subst "$HERE/workspace/core/rules.md.template" > "$WS_DIR/core/rules.md"
ok "workspace развёрнут под $OPERATOR_NAME"

say "7/9 Секреты + config"
printf '%s' "$BOT_TOKEN" > "$SEC_DIR/telegram-bot-token"; chmod 600 "$SEC_DIR/telegram-bot-token"
if [ -n "${GROQ_KEY:-}" ]; then printf '%s' "$GROQ_KEY" > "$SEC_DIR/groq-api-key"; chmod 600 "$SEC_DIR/groq-api-key"; ok "bot token + groq key"; else printf '   ! groq key пропущен (добавь позже в %s/groq-api-key)\n' "$SEC_DIR"; fi
sed -e "s#__OWNER_ID__#${OWNER_TG_ID}#g" -e "s#__LAB_DIR__#${LAB_DIR}#g" -e "s#__AGENT__#${AGENT_NAME}#g" -e "s#__OPERATOR__#${OPERATOR_NAME}#g" "$HERE/config.example.json" > "$GW_DIR/config.json"
ok "config.json собран"

say "8/9 Хуки безопасности"
for h in block-dangerous protect-files log-commands; do
  sed -e "s#__WS__#${WS_DIR}#g" -e "s#__OPERATOR__#${OPERATOR_NAME}#g" "$HERE/hooks/$h.sh" > "$WS_DIR/hooks/$h.sh"
  chmod +x "$WS_DIR/hooks/$h.sh"
done
sed -e "s#__WS__#${WS_DIR}#g" "$HERE/workspace/settings.json.template" > "$WS_DIR/settings.json"
# всё в домашней папке юзера — его владение
chown -R "$AGENT_USER:$AGENT_USER" "$UHOME/claude-gateway" "$UHOME/.claude-lab"
ok "3 хука включены, права переданы $AGENT_USER"

say "9/9 systemd-сервис (User=$AGENT_USER, без root-костылей)"
UNIT="/etc/systemd/system/${SVC}.service"
tee "$UNIT" >/dev/null <<EOF
[Unit]
Description=${AGENT_NAME} Telegram Gateway (${OPERATOR_NAME})
After=network-online.target
Wants=network-online.target
[Service]
Type=simple
User=${AGENT_USER}
WorkingDirectory=${GW_DIR}
ExecStart=${GW_DIR}/.venv/bin/python ${GW_DIR}/gateway.py
Restart=always
RestartSec=5
Environment=PYTHONUNBUFFERED=1
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable "$SVC" >/dev/null 2>&1
ok "сервис ${SVC} установлен"

cat <<MSG

$(printf '\033[1;33m')ОСТАЛСЯ ОДИН РУЧНОЙ ШАГ — вход в Claude под пользователем:$(printf '\033[0m')
   1) sudo -iu ${AGENT_USER}      # переключиться на пользователя агента
   2) claude                      # войти аккаунтом ОПЕРАТОРА (его подписка Claude)
   3) выйти из claude (/exit), затем: exit
   4) systemctl restart ${SVC}
   5) ${OPERATOR_NAME} пишет боту в Telegram — ${AGENT_NAME} отвечает.

Логи:    journalctl -u ${SVC} -f
Секреты: ${SEC_DIR}
Юзер:    ${AGENT_USER} (без пароля и без sudo — агент изолирован в своём \$HOME)
MSG
