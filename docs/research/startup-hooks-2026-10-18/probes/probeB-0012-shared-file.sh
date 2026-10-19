#!/bin/bash
# probeB-0012-shared-file.sh — what migrations/0012 does to today's fleet layout, where
# ~/.claude-{next,secondary,tertiary,quaternary}/settings.json are symlinks to ONE real
# ~/.claude/settings.json (0037), while 0012's comment still says "separate REAL files".
#
# Runs 0012 twice in a scratch HOME built from a COPY of the live settings.json (read-only on the
# live side): arm "happy" as the operator would run it, arm "first-fails" with the real file's dir
# made unwritable so the first iteration's backup fails and the loop moves on to a symlinked dir.
# Nothing under the real $HOME is written. Usage: probeB-0012-shared-file.sh <repo> <out-dir>
set -uo pipefail
REPO="$1"; OUT="$2"; mkdir -p "$OUT"
LIVE="$HOME/.claude/settings.json"

arm() { # <name> <break-first: 0|1>
  local name="$1" brk="$2" S H
  S="$(mktemp -d "${TMPDIR:-/tmp}/w6probeB0012.XXXXXX")"; H="$S/home"
  mkdir -p "$H/.claude/hooks"
  cp "$LIVE" "$H/.claude/settings.json"
  cp "$REPO/hooks/mailbox-wake-arm.sh" "$H/.claude/hooks/mailbox-wake-arm.sh"
  chmod +x "$H/.claude/hooks/mailbox-wake-arm.sh"
  for a in next secondary tertiary quaternary; do
    mkdir -p "$H/.claude-$a"; ln -s "$H/.claude/settings.json" "$H/.claude-$a/settings.json"
  done
  [ "$brk" = 1 ] && chmod a-w "$H/.claude"
  {
    echo "### arm=$name"
    echo "--- 0012 output (rc below)"
    HOME="$H" CC_CLAUDE_DIR="$H/.claude" bash "$REPO/migrations/0012-mailbox-wake-arm-stop-rearm.sh" 2>&1
    echo "rc=$?"
    chmod u+w "$H/.claude"
    echo "--- layout after"
    for d in "$H/.claude" "$H"/.claude-*; do
      f="$d/settings.json"
      if [ -L "$f" ]; then kind="symlink -> $(readlink "$f" | sed "s#$S#\$S#")"; else kind="REAL FILE"; fi
      n="$(jq '[.hooks.Stop[].hooks[]? | select((.command // "") | test("mailbox-wake-arm"))] | length' "$f" 2>/dev/null)"
      printf '%s/settings.json: %s; Stop registrations of mailbox-wake-arm: %s\n' "${d#"$H"/}" "$kind" "$n"
    done
    echo "--- backups written"
    find "$H" -name 'settings.json.bak-0012-*' | sed "s#$H/##"
    echo "--- the registered entry"
    jq -c '[.hooks.Stop[].hooks[]? | select((.command // "") | test("mailbox-wake-arm"))]' "$H/.claude/settings.json"
    [ -f "$H/.claude-next/settings.json" ] && [ ! -L "$H/.claude-next/settings.json" ] && \
      jq -c '[.hooks.Stop[].hooks[]? | select((.command // "") | test("mailbox-wake-arm"))]' "$H/.claude-next/settings.json" | sed 's/^/.claude-next (forked) /'
    echo
  } > "$OUT/0012-$name.txt"
  cat "$OUT/0012-$name.txt"
  printf 'scratch: %s\n' "$S"
}
arm happy 0
arm first-fails 1
