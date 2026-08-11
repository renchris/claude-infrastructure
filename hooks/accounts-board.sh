#!/usr/bin/env bash
# accounts-board.sh — SessionStart hook: print the /accounts board at session start, at ZERO model
# token cost and ~zero latency.
#
# ── THE CHANNEL, AND WHY IT IS THE TOP-LEVEL KEY ──────────────────────────────────────────────
# Proven at source under a real pty, transcript inspected (docs/research/R5b-sessionstart-render-
# probe.py; DESK_ROUTER_AND_STARTUP_V1 §2.7). Three candidate channels, three different fates:
#
#   top-level `systemMessage`          → attachment.type = hook_system_message
#                                        RENDERS in the operator's terminal (inside the alt-screen,
#                                        so it survives the switch) · 0 model tokens          ✅
#   `hookSpecificOutput.systemMessage` → never promoted; only echoed in raw stdout.
#                                        SILENTLY IGNORED — no error, no output, no clue.      ❌
#   `additionalContext`                → attachment.type = hook_additional_context
#                                        enters MODEL CONTEXT, i.e. this board would be billed
#                                        as input tokens on every single session start.        ❌
#
# The nested form is the dangerous one precisely because it fails silently and looks correct —
# docs/research/R5-startup-print.md documented that shape, from the published schema rather than
# from a measurement, and it is wrong. If this hook ever stops appearing, check that shape FIRST.
# `additionalContext` is not merely wasteful here: the board is 20-odd lines of numbers the model
# has no use for, re-billed at every /clear.
#
# ── WHY THIS HOOK MAY NOT CALL claude-accounts ────────────────────────────────────────────────
# `claude-accounts --readout` measured 5.33s against this hook's 5s timeout and was KILLED in the
# probe. A hook that shells out to it recreates exactly the class of defect W0 had just removed
# (a 21-29s SessionStart, hooks dying on their own timeouts). So the read is a `cat` of a file
# somebody else already rendered — the producer is the `com.claude.accounts-keepwarm` launchd job
# (StartInterval 60), which sweeps the account cache anyway and now writes the board in the same
# pass. tests/accounts-board.bats asserts this hook forks NO claude-accounts, with a positive
# control proving that fixture can actually see such a call.
#
# ── STALENESS IS VISIBLE, IN TWO BANDS ────────────────────────────────────────────────────────
# A board that silently prints stale numbers is worse than no board: it is read at a glance, by
# someone who did not ask for it, and it is the only account figure they will see before choosing
# what to run. So age is never hidden, and past a point the numbers are withheld rather than
# labelled:
#   fresh (< CC_BOARD_STALE_S, default 300 = 5 producer ticks)  → print as rendered
#   stale (< CC_BOARD_HARD_S, default 3600)                     → print, under a loud age line
#   ancient (>= CC_BOARD_HARD_S) / missing                      → ONE line, numbers SUPPRESSED
# The hard band exists because the 5h window it reports on resets every 5 hours: an hour-old
# board can be wrong by a whole window, and at that point "labelled but shown" is still a number
# a human will act on. The board itself carries the second, independent staleness axis — how old
# the QUOTA SWEEP was when it rendered (its header line, plus the existing `*` / `↻ poll
# throttled` semantics). This hook owns only how old the FILE is. They are different failures:
# a fresh file can hold stale quota, and a stale file can hold quota that was fresh when written.
#
# Always exits 0 and never blocks. A startup convenience must not be able to stop a session.
set -uo pipefail

BOARD="${CC_ACCOUNTS_BOARD:-/tmp/claude-accounts-board.txt}"
STALE_S="${CC_BOARD_STALE_S:-300}"
HARD_S="${CC_BOARD_HARD_S:-3600}"
# Named here rather than inlined in the message: it is the one thing an operator staring at
# "unavailable" needs, and it is also what a future reader greps for to find the producer.
PRODUCER="com.claude.accounts-keepwarm (launchd, StartInterval 60)"

emit() {  # <message> → the ONE sanctioned channel, top-level, never nested, never additionalContext
  jq -nc --arg m "$1" '{systemMessage:$m}' 2>/dev/null || true
  exit 0
}

input="$(cat 2>/dev/null || true)"

# `compact` is excluded and the other sources are not. A board answers "which account am I on and
# what is left" — a question a human asks when a session BEGINS (startup), when it is reset
# (clear), or when it is picked back up (resume). A compaction is none of those: same session,
# same account, mid-task, and the operator is usually not even looking. Firing there would spend
# the board's whole value, which is that its appearance means something.
src="$(printf '%s' "$input" | jq -r '.source // ""' 2>/dev/null || true)"
[ "$src" = "compact" ] && exit 0

[ -f "$BOARD" ] || emit "accounts board unavailable — nothing pre-rendered at $BOARD.
  Producer: $PRODUCER. Check: launchctl list | grep accounts-keepwarm
  For the live table right now, run: claude-accounts"

now="$(date +%s)"
# BSD stat first (this fleet is Darwin), GNU second, and a FAILURE to read the mtime is treated
# as unknown-age rather than as age 0. Defaulting to 0 would render an ancient board as fresh —
# the single worst outcome available to this hook, reached by the most forgettable line in it.
mtime="$(stat -f %m "$BOARD" 2>/dev/null || stat -c %Y "$BOARD" 2>/dev/null || echo "")"
if [ -z "$mtime" ]; then
  emit "accounts board found but its age is unreadable ($BOARD) — numbers withheld.
  An unknown-age board cannot be labelled honestly, and an unlabelled one gets believed.
  For the live table, run: claude-accounts"
fi

age=$(( now - mtime ))
[ "$age" -lt 0 ] && age=0          # clock skew / a file stamped in the future is not 'fresh in the past'

fmt_age() {  # seconds → the coarsest form that still answers "should I trust this?"
  if   [ "$1" -lt 120 ];  then printf '%ss' "$1"
  elif [ "$1" -lt 7200 ]; then printf '%sm' "$(( $1 / 60 ))"
  else                         printf '%sh' "$(( $1 / 3600 ))"
  fi
}

body="$(cat "$BOARD" 2>/dev/null || true)"
if [ -z "${body//[[:space:]]/}" ]; then
  emit "accounts board at $BOARD is EMPTY — the producer wrote nothing.
  Producer: $PRODUCER. For the live table, run: claude-accounts"
fi

if [ "$age" -ge "$HARD_S" ]; then
  # NUMBERS SUPPRESSED, deliberately. Everything this board reports is a percentage of a window
  # that rolls — the 5h one every five hours — so past the hard band the figures are not merely
  # old, they can be describing a window that no longer exists.
  emit "accounts board is $(fmt_age "$age") old — numbers withheld as unsafe to read (the 5h
  window it reports rolls every 5h, so a board this old can describe a window that has ended).
  Producer $PRODUCER appears to be down. Check: launchctl list | grep accounts-keepwarm
  For the live table, run: claude-accounts"
fi

if [ "$age" -ge "$STALE_S" ]; then
  emit "⚠ STALE by $(fmt_age "$age") — $PRODUCER has not refreshed this board; the numbers below
  are last-known, not current. Live table: claude-accounts

$body"
fi

emit "$body"
