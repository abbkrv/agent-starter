#!/usr/bin/env bash
# PreToolUse hook for Edit | Write -- warn (do not block) on RED-zone file writes.
# Stdin: JSON { tool_name, tool_input: { file_path, ... } }.
# Stdout = system reminder visible to model; exit 0 always (does not block).
#
# Philosophy: RED-zone discipline is enforced by the model via rules.md.
# This hook is a loud detector for autonomous edits that slipped past
# instruction-following. Adam can review and roll back if a violation appears
# in the log.

set +e

[ "$(command -v jq)" ] || exit 0

FILE=$(jq -r '.tool_input.file_path // empty' 2>/dev/null) || exit 0
[ -z "$FILE" ] && exit 0

LOG="__WS__/logs/red-zone-edits.log"
mkdir -p "$(dirname "$LOG")"

case "$FILE" in
    */CLAUDE.md|*/rules.md|*/USER.md|*/settings.json|__WS__/CLAUDE.md)
        TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
        echo "[$TS] RED-zone edit attempted: $FILE" >> "$LOG"
        echo "<red-zone-warning>About to edit RED-zone file: $FILE. Per rules.md, RED-zone edits require __OPERATOR__'s approval. Make sure this is explicitly authorized in the current session.</red-zone-warning>"
        ;;
esac

exit 0
