#!/usr/bin/env bash
# install.sh — разворачивает личного Telegram-агента на Claude Code на чистом сервере
# (Ubuntu 22/24). Универсальный установщик: спрашивает данные оператора и всё настраивает.
#
# Запуск на СЕРВЕРЕ (обычно под root), из папки репозитория:
#   bash install.sh
# Можно передать значения заранее через окружение (иначе спросит интерактивно):
#   OPERATOR_NAME='Abdulmalik' OWNER_TG_ID='123' BOT_TOKEN='...' GROQ_KEY='...' bash install.sh
#
# Секреты НЕ хранятся в репозитории и НЕ хардкодятся: пишутся в secrets/ (chmod 600).
set -euo pipefail

GW_REPO="https://github.com/qwwiwi/jarvis-telegram-gateway.git"
HERE="$(cd "$(dirname "$0")" && pwd)"
HOME_DIR="${HOME}"

say(){ printf '\n\033[1;33m== %s\033[0m\n' "$1"; }
ok(){ printf '   \033[1;32m✓ %s\033[0m\n' "$1"; }
ask(){ # ask VAR "prompt" [silent]
  local __v="$1" __p="$2" __s="${3:-}" __in=""
  if [ -n "${!__v:-}" ]; then return; fi
  if [ "$__s" = "silent" ]; then read -rsp "   $__p: " __in; echo; else read -rp "   $__p: " __in; fi
  printf -v "$__v" '%s' "$__in"
}

say "Данные агента"
ask OPERATOR_NAME "Имя оператора (для кого агент, напр. Abdulmalik)"
ask AGENT_NAME    "Имя агента (Enter = Jarvis)"; AGENT_NAME="${AGENT_NAME:-Jarvis}"
ask OWNER_TG_ID   "Telegram ID оператора (узнать: напиши @userinfobot)"
ask BOT_TOKEN     "Токен бота от @BotFather"
ask GROQ_KEY      "Groq API key для голосовых (Enter = пропустить, добавишь позже)"
LAB_NAME="$(printf '%s' "$OPERATOR_NAME" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9')"
[ -n "$LAB_NAME" ] || LAB_NAME="agent"
GW_DIR="${HOME_DIR}/claude-gateway"
LAB_DIR="${HOME_DIR}/.claude-lab/${LAB_NAME}"
WS_DIR="${LAB_DIR}/.claude"
SEC_DIR="${LAB_DIR}/secrets"
RUN_USER="$(id -un)"
SVC="${LAB_NAME}-gateway"

[ -n "${BOT_TOKEN:-}" ] || { echo "BOT_TOKEN обязателен"; exit 1; }
[ -n "${OWNER_TG_ID:-}" ] || { echo "OWNER_TG_ID обязателен"; exit 1; }

say "1/8 Системные зависимости"
sudo apt-get update -qq
sudo apt-get install -y -qq python3 python3-venv python3-pip git ffmpeg curl jq >/dev/null
ok "python3, git, ffmpeg, curl, jq"

say "2/8 Node.js + Claude Code CLI"
if ! command -v node >/dev/null 2>&1; then
  curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash - >/dev/null
  sudo apt-get install -y -qq nodejs >/dev/null
fi
ok "node $(node -v)"
command -v claude >/dev/null 2>&1 || sudo npm i -g @anthropic-ai/claude-code >/dev/null 2>&1
ok "claude CLI: $(command -v claude)"

say "3/8 Gateway (clone qwwiwi upstream)"
if [ -d "$GW_DIR/.git" ]; then git -C "$GW_DIR" pull --ff-only >/dev/null 2>&1 || true; ok "обновлён";
else git clone --depth 1 "$GW_REPO" "$GW_DIR" >/dev/null 2>&1; ok "склонирован в $GW_DIR"; fi

say "4/8 Python venv"
python3 -m venv "$GW_DIR/.venv"
"$GW_DIR/.venv/bin/pip" install -q --upgrade pip >/dev/null
[ -f "$GW_DIR/requirements.txt" ] && "$GW_DIR/.venv/bin/pip" install -q -r "$GW_DIR/requirements.txt" >/dev/null
ok "venv готов"

say "5/8 Workspace + подстановка данных"
mkdir -p "$WS_DIR/core/warm" "$WS_DIR/core/hot" "$WS_DIR/skills" "$WS_DIR/hooks" "$SEC_DIR"; chmod 700 "$SEC_DIR"
cp -r "$HERE"/workspace/skills/. "$WS_DIR/skills/"
cp "$HERE"/workspace/core/*.md "$WS_DIR/core/" 2>/dev/null || true
cp "$HERE"/workspace/core/warm/*.md "$WS_DIR/core/warm/" 2>/dev/null || true
cp "$HERE"/workspace/core/hot/*.md "$WS_DIR/core/hot/" 2>/dev/null || true
subst(){ sed -e "s#{{OPERATOR}}#${OPERATOR_NAME}#g" -e "s#{{AGENT}}#${AGENT_NAME}#g" -e "s#{{OWNER_ID}}#${OWNER_TG_ID}#g" "$1"; }
subst "$HERE/workspace/CLAUDE.md.template"    > "$WS_DIR/CLAUDE.md"
subst "$HERE/workspace/core/USER.md.template" > "$WS_DIR/core/USER.md"
subst "$HERE/workspace/core/rules.md.template">"$WS_DIR/core/rules.md"
ok "workspace развёрнут под $OPERATOR_NAME"

say "6/8 Секреты + config"
printf '%s' "$BOT_TOKEN" > "$SEC_DIR/telegram-bot-token"; chmod 600 "$SEC_DIR/telegram-bot-token"
if [ -n "${GROQ_KEY:-}" ]; then printf '%s' "$GROQ_KEY" > "$SEC_DIR/groq-api-key"; chmod 600 "$SEC_DIR/groq-api-key"; ok "bot token + groq key"; else printf '   ! groq key пропущен (голос выкл до добавления в %s/groq-api-key)\n' "$SEC_DIR"; fi
sed -e "s#__OWNER_ID__#${OWNER_TG_ID}#g" -e "s#__LAB_DIR__#${LAB_DIR}#g" -e "s#__AGENT__#${AGENT_NAME}#g" -e "s#__OPERATOR__#${OPERATOR_NAME}#g" "$HERE/config.example.json" > "$GW_DIR/config.json"
ok "config.json собран"

say "7/8 Хуки безопасности"
for h in block-dangerous protect-files log-commands; do
  sed -e "s#__WS__#${WS_DIR}#g" -e "s#__OPERATOR__#${OPERATOR_NAME}#g" "$HERE/hooks/$h.sh" > "$WS_DIR/hooks/$h.sh"
  chmod +x "$WS_DIR/hooks/$h.sh"
done
sed -e "s#__WS__#${WS_DIR}#g" "$HERE/workspace/settings.json.template" > "$WS_DIR/settings.json"
ok "3 хука включены"

say "8/8 systemd-сервис"
UNIT="/etc/systemd/system/${SVC}.service"
sudo tee "$UNIT" >/dev/null <<EOF
[Unit]
Description=${AGENT_NAME} Telegram Gateway (${OPERATOR_NAME})
After=network-online.target
Wants=network-online.target
[Service]
Type=simple
User=${RUN_USER}
WorkingDirectory=${GW_DIR}
ExecStart=${GW_DIR}/.venv/bin/python ${GW_DIR}/gateway.py
Restart=always
RestartSec=5
Environment=PYTHONUNBUFFERED=1
$([ "$RUN_USER" = "root" ] && echo 'Environment=IS_SANDBOX=1')
[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable "$SVC" >/dev/null 2>&1
ok "сервис ${SVC} установлен"

cat <<MSG

$(printf '\033[1;33m')ОСТАЛСЯ ОДИН РУЧНОЙ ШАГ — вход в Claude:$(printf '\033[0m')
   1) claude            # войди аккаунтом ОПЕРАТОРА (его подписка Claude)
   2) выйди из claude (/exit)
   3) sudo systemctl restart ${SVC}
   4) ${OPERATOR_NAME} пишет боту в Telegram — ${AGENT_NAME} отвечает.

Логи:   journalctl -u ${SVC} -f
Секреты: ${SEC_DIR}
MSG
