#!/bin/bash
# E2E for `handoff-fire.sh self-close` — the SUCCESSION CONTRACT (2026-07-13).
#
# Live-fire proof of the full chain on REAL panes with a fake `claude` binary:
#   verify successor alive → announce (cc-notify: composer+mailbox) → arm setsid watcher →
#   type /exit into the closing pane → watcher closes it → FOCUS hands to the successor.
#
# Why this exists: 3× on 2026-07-13 a close with no declared continuation read to the
# operator as "the handoff killed our session" — the third time the succession had actually
# SUCCEEDED but was invisible (announce died with the closing pane, no focus hand-over).
# This E2E is the un-fakeable check that the legibility chain works end-to-end; run it after
# any change to self-close, the __selfclose watcher, detach(), or the it2 shim.
#
# Mechanics notes (hard-won, same constraints as the main script):
#   - fake claude = a SYMLINK named `claude` → /bin/bash (ps -o comm= shows the symlink path,
#     satisfying the watcher's tty aliveness grep; a COPY of /bin/bash gets SIGKILLed by macOS
#     AMFI — platform binaries may not run from foreign paths, observed 2026-07-13); it runs a
#     read-loop that exits on the typed "/exit" line, exactly like the real TUI's graceful exit.
#   - pane UUIDs come from foreground osascript enumeration (`it2 session list` TRUNCATES ids —
#     observed 2026-07-13); split panes are detected by before/after set difference.
#   - the it2 shim injects the never-prompt Claude-Teammate profile on split, so cleanup closes
#     are modal-free.
# Exit codes: 0 all assertions pass · 4 no iTerm2 session to split from · 1 assertion failure.
set -u

HF="$(cd "$(dirname "$0")" && pwd)/handoff-fire.sh"
IT2="$HOME/.claude/bin/it2"
WORK="/tmp/hfe2e.$$"
PASS=0; FAIL=0
A=""; B=""

say()  { printf '%s\n' "$*"; }
ok()   { PASS=$((PASS+1)); say "  ✓ $*"; }
bad()  { FAIL=$((FAIL+1)); say "  ✗ $*"; }

[ -n "${ITERM_SESSION_ID:-}" ] || { say "!! no \$ITERM_SESSION_ID — run from inside an iTerm2 pane"; exit 4; }
BASE="${ITERM_SESSION_ID##*:}"

list_uuids() {
  osascript <<'AS' 2>/dev/null
tell application "iTerm2"
  set out to ""
  repeat with w in windows
    repeat with t in tabs of w
      repeat with s in sessions of t
        set out to out & (id of s) & linefeed
      end repeat
    end repeat
  end repeat
  return out
end tell
AS
}

pane_tty() { # $1=uuid → tty path or empty
  osascript - "$1" <<'AS' 2>/dev/null
on run argv
  tell application "iTerm2"
    repeat with w in windows
      repeat with t in tabs of w
        repeat with s in sessions of t
          if id of s is (item 1 of argv) then return tty of s
        end repeat
      end repeat
    end repeat
  end tell
  return ""
end run
AS
}

fake_alive() { # $1=uuid → 0 when a `claude` process sits on the pane's tty
  local tty; tty="$(pane_tty "$1")"
  [ -n "$tty" ] && ps -o comm= -t "$(basename "$tty")" 2>/dev/null | grep -qE 'node|claude'
}

split_pane() { # → new pane uuid on stdout (split prints "Created new pane: <id>"; diff fallback)
  local before out new
  before="$(list_uuids)"
  out="$("$IT2" session split -s "$BASE" 2>/dev/null)"
  new="$(grep -oE '[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}' <<<"$out" | head -1)"
  if [ -z "$new" ]; then
    sleep 2
    new="$(comm -13 <(sort <<<"$before") <(list_uuids | sort) | tr -d '\r' | head -1)"
  fi
  printf '%s\n' "$new"
}

await_shell() { # $1=uuid — the typed launch is LOST if it lands before zsh finishes init
  local n=0 tty
  while [ "$n" -lt 15 ]; do
    tty="$(pane_tty "$1")"
    if [ -n "$tty" ] && ps -o comm= -t "$(basename "$tty")" 2>/dev/null | grep -qE '(zsh|bash)$'; then
      sleep 1   # prompt settle after the shell process appears
      return 0
    fi
    n=$((n+1)); sleep 1
  done
  return 1
}

start_fake() { # $1=uuid — launch fake claude; one retry (a first send can be redraw-eaten)
  local try
  for try in 1 2; do
    "$IT2" session run -s "$1" "$FAKE_CMD" >/dev/null 2>&1
    local n=0
    while [ "$n" -lt 6 ]; do
      fake_alive "$1" && return 0
      n=$((n+1)); sleep 1
    done
  done
  return 1
}

cleanup() {
  for p in "$A" "$B"; do
    [ -n "$p" ] && [ -n "$(pane_tty "$p")" ] && "$IT2" session close -f -s "$p" >/dev/null 2>&1
  done
  [ -n "${B:-}" ] && rm -f "$HOME/.claude/mailbox/$B.md"
  rm -rf "$WORK"
}
trap cleanup EXIT

say "── handoff self-close succession E2E ──────────────────"
mkdir -p "$WORK" && cd "$WORK"
ln -sf /bin/bash "$WORK/claude"
FAKE_CMD="$WORK/claude -c 'while read -r l; do case \"\$l\" in /exit) exit 0;; esac; done'"

say "→ creating scratch panes A (predecessor) + B (successor) off $BASE"
A="$(split_pane)"; B="$(split_pane)"
[ -n "$A" ] && [ -n "$B" ] && [ "$A" != "$B" ] || { bad "pane creation failed (A='$A' B='$B')"; exit 1; }
await_shell "$A" && await_shell "$B" || { bad "pane shells never became ready"; exit 1; }
start_fake "$A" && start_fake "$B" || { bad "fake claude did not start on both panes"; exit 1; }
ok "fake claude alive on both panes (A=$A B=$B)"

say "→ T-live-1: self-close A with successor B (full chain)"
OUT="$("$HF" self-close --session-id "$A" --successor "$B" 2>&1)"; RC=$?
say "$OUT" | sed 's/^/    │ /'
[ "$RC" = 0 ] && ok "self-close returned 0" || bad "self-close returned $RC"
grep -q "successor verified alive: $B" <<<"$OUT" && ok "successor liveness verified pre-/exit" || bad "missing successor verification"
grep -qE "succession announced into $B|mailbox record \+ post-close focus" <<<"$OUT" && ok "succession announce attempted (composer or mailbox)" || bad "no succession announce"
LOG="$(grep -oE '/tmp/handoff-selfclose-[^ )]*\.log' <<<"$OUT" | head -1)"
[ -n "$LOG" ] && ok "watcher log: $LOG" || bad "no watcher log path in output"

say "→ awaiting watcher: pane A closes, focus hands to B (≤40s)"
n=0; while [ -n "$(pane_tty "$A")" ] && [ "$n" -lt 40 ]; do n=$((n+1)); sleep 1; done
[ -z "$(pane_tty "$A")" ] && ok "pane A closed by watcher (${n}s)" || bad "pane A still open after 40s"
sleep 2
if [ -n "$LOG" ]; then
  grep -q "→ focus handed to successor $B" "$LOG" 2>/dev/null && ok "focus hand-over logged" || bad "focus hand-over missing from log: $(tail -2 "$LOG" 2>/dev/null | tr '\n' ' ')"
fi
fake_alive "$B" && ok "successor B untouched and alive" || bad "successor B died — succession destroyed the survivor"
grep -q "HANDOFF-SUCCESSION" "$HOME/.claude/mailbox/$B.md" 2>/dev/null && ok "mailbox record present for B" || bad "no HANDOFF-SUCCESSION mailbox record for B"

say "── result: $PASS passed, $FAIL failed ─────────────────"
[ "$FAIL" = 0 ]
