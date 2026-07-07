#!/usr/bin/env bash
# PreToolUse hook for Bash -- block clearly destructive commands.
# Stdin: JSON { hook_event_name, session_id, tool_name, tool_input: { command, ... } }.
# Exit 2 with stderr = block. Exit 0 = allow.
#
# Philosophy: catch obvious wide-blast-radius commands. Not a complete sandbox --
# the model already follows rules.md. This is belt-and-suspenders for autonomous
# mistakes (e.g., agent decides to "clean up" $HOME).

set +e

[ "$(command -v jq)" ] || exit 0

CMD=$(jq -r '.tool_input.command // empty' 2>/dev/null) || exit 0
[ -z "$CMD" ] && exit 0

block() {
    echo "BLOCKED by block-dangerous hook: $1" >&2
    echo "Command: $CMD" >&2
    echo "If this is intentional, ask __OPERATOR__ first. Override path: edit hooks/block-dangerous.sh or run via a separate non-hooked shell." >&2
    exit 2
}

# Recursive removal of system roots / home / wildcards.
# Match: rm with -r/-rf/-fr flags followed by a dangerous target.
RM_FLAGS='-[a-zA-Z]*r[a-zA-Z]*|-[a-zA-Z]*R[a-zA-Z]*'
DANGEROUS_TARGETS='/|/\*|~|~/\*|/root|/root/\*|\$HOME|\$HOME/\*|\*|\.|\./\*'
if echo "$CMD" | grep -Eq "(^|[[:space:]])rm[[:space:]]+($RM_FLAGS)[[:space:]]+($DANGEROUS_TARGETS)([[:space:]]|;|&|\$|\|)"; then
    block "recursive rm targeting system root, home, or wildcard"
fi

# Destructive SQL.
echo "$CMD" | grep -iEq '\b(DROP|TRUNCATE)[[:space:]]+(TABLE|DATABASE|SCHEMA)\b' && \
    block "destructive SQL (DROP/TRUNCATE TABLE|DATABASE|SCHEMA)"

# Fork bomb.
echo "$CMD" | grep -Eq ':\(\)[[:space:]]*\{[[:space:]]*:\|:' && \
    block "fork bomb"

# Disk overwrite.
echo "$CMD" | grep -Eq 'dd[[:space:]]+.*of=/dev/(sd|nvme|hd|vd|xvd)' && \
    block "raw disk write via dd"
echo "$CMD" | grep -Eq 'mkfs\.' && \
    block "filesystem format (mkfs)"

# Force push.
echo "$CMD" | grep -Eq 'git[[:space:]]+push.*--force([[:space:]]|$)' && \
    block "git push --force (forbidden by rules.md without explicit approval)"

# History rewrite on pushed commits.
echo "$CMD" | grep -Eq 'git[[:space:]]+(rebase[[:space:]]+-i|filter-branch|reset[[:space:]]+--hard[[:space:]]+origin)' && \
    block "git history rewrite (forbidden by rules.md without explicit approval)"

exit 0
