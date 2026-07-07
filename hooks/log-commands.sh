#!/usr/bin/env bash
# PostToolUse hook for Bash -- audit log of executed commands.
# Stdin: JSON { tool_name, tool_input: { command, ... }, tool_response }.
# Output: appends one line per command to a rotating log.
# Exit 0 always.
#
# Philosophy: cheap audit trail. If something breaks, __OPERATOR__ can `tail` the log
# to see what the agent ran. Not a security boundary -- block-dangerous.sh
# handles that.

set +e

[ "$(command -v jq)" ] || exit 0

# Read stdin once -- jq cannot be called twice on the same pipe.
INPUT=$(cat)
CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null) || exit 0
[ -z "$CMD" ] && exit 0

LOG_DIR="__WS__/logs"
LOG="$LOG_DIR/bash-commands.log"
mkdir -p "$LOG_DIR"

# Rotate when log exceeds 5 MB.
if [ -f "$LOG" ] && [ "$(stat -c %s "$LOG" 2>/dev/null || echo 0)" -gt 5242880 ]; then
    mv "$LOG" "$LOG.$(date -u +%Y%m%d-%H%M%S)"
    # Keep last 5 rotated logs.
    ls -1t "$LOG".* 2>/dev/null | tail -n +6 | xargs -r rm -f
fi

TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
SID=$(printf '%s' "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null) || SID="unknown"
[ -z "$SID" ] && SID="unknown"

# Single-line command record. Replace newlines so each command = one log line.
ONE_LINE=$(printf '%s' "$CMD" | tr '\n' ' ' | tr -s ' ')
echo "[$TS] [$SID] $ONE_LINE" >> "$LOG"

exit 0
