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
# (launchd/staged/, StartInterval 180), which sweeps the account cache anyway and now writes the board in the same
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
# /usr/bin/shasum is a #! perl script (a kernel-memory leak per exec on macOS 15.8.1); this is Mach-O. Linux: coreutils.
CC_SHA1=/sbin/sha1sum; [ -x "$CC_SHA1" ] || CC_SHA1=sha1sum

BOARD="${CC_ACCOUNTS_BOARD:-/tmp/claude-accounts-board.txt}"
STALE_S="${CC_BOARD_STALE_S:-300}"
HARD_S="${CC_BOARD_HARD_S:-3600}"
# Named here rather than inlined in the message: it is the one thing an operator staring at
# "unavailable" needs, and it is also what a future reader greps for to find the producer.
# No interval in it: "StartInterval 60" sat here for six weeks after the plist moved to 180.
LABEL="com.claude.accounts-keepwarm"
PRODUCER="$LABEL (launchd)"

# WHY the producer is not refreshing, from ONE read of launchd's own record. This hook used to say
# "appears to be down" for every stale board, and on 2026-09-24 that sent the reader to the wrong
# fault: the job was loaded and RUNNING — one tick 3h40m old at 0.04s of CPU, starved at PRI 4 —
# and `launchctl list | grep` shows a PID, which reads as healthy. The three states need three
# different actions, so the message names which one it is. Runs only off the fresh path, and
# `launchctl list <label>` + one `ps` fit easily inside the hook's 5s budget.
producer_read() {  # → PS_STATE (unloaded|running|idle0|failing), PS_PID, PS_ET, PS_RC
  local info
  PS_PID=""; PS_ET=""; PS_RC=""
  info="$(launchctl list "$LABEL" 2>/dev/null)" || { PS_STATE=unloaded; return; }
  PS_PID="$(printf '%s\n' "$info" | sed -n 's/^[[:space:]]*"PID" = \([0-9][0-9]*\);.*/\1/p')"
  if [ -n "$PS_PID" ]; then
    PS_ET="$(ps -o etime= -p "$PS_PID" 2>/dev/null | tr -d ' ')"
    PS_STATE=running; return
  fi
  PS_RC="$(printf '%s\n' "$info" | sed -n 's/^[[:space:]]*"LastExitStatus" = \(-\{0,1\}[0-9][0-9]*\);.*/\1/p')"
  if [ "$PS_RC" = "0" ]; then PS_STATE=idle0; else PS_STATE=failing; fi
}
producer_state() {
  producer_read
  case "$PS_STATE" in
    unloaded) printf 'is NOT LOADED, so nothing refreshes this board.\n  Install: launchctl bootstrap gui/%s ~/Library/LaunchAgents/%s.plist (source: launchd/staged/)' "$UID" "$LABEL" ;;
    running) printf 'is RUNNING but its current tick (pid %s) is %s old, where a healthy one takes seconds:\n  starved or wedged. Restart it: launchctl kickstart -k gui/%s/%s' "$PS_PID" "${PS_ET:-?}" "$UID" "$LABEL" ;;
    idle0) printf 'is loaded and idle, and its last tick exited 0 without refreshing the board.\n  Read the board= field: tail ~/.claude/logs/accounts-keepwarm.out.log' ;;
    *) printf 'is loaded and idle, last exit %s, so its ticks are failing.\n  Read: tail ~/.claude/logs/accounts-keepwarm.err.log' "${PS_RC:-unknown}" ;;
  esac
}

# THE SAME DIAGNOSIS ABOVE THE BAND (2026-10-22): paragraphs Claude Code wraps itself. fit() wraps
# at the width the pane had when this hook ran, with a two-space hanging indent, and Claude Code
# re-wraps those rows again when the pane narrows later, so the indents landed unevenly
# (`  (launchd) is` beside `and idle, and its last`) and `com.claude.accounts-keepwarm` broke
# mid-token inside the sentence at 30 columns and under (docs/research/accounts-narrow-2026-10-22/).
# So each line here is one unwrapped paragraph led by FIT_RAW (fit passes it through as it is), the
# sentence names the producer in words a narrow row holds, and the one long token, the command to
# run, sits alone on the last line, where any split it must take falls on the command, not the
# sentence. The static path above keeps producer_state's words byte for byte.
FIT_RAW=$'\x1f'
producer_note() {
  local say act cmd
  producer_read
  case "$PS_STATE" in
    unloaded) say="is NOT LOADED, so nothing refreshes this board."
              act="Install it (source: launchd/staged/):"
              cmd="launchctl bootstrap gui/$UID ~/Library/LaunchAgents/$LABEL.plist" ;;
    running) say="is RUNNING but its current tick (pid $PS_PID) is ${PS_ET:-?} old, where a healthy one takes seconds: starved or wedged."
             act="Restart it:"; cmd="launchctl kickstart -k gui/$UID/$LABEL" ;;
    idle0) say="is loaded and idle, and its last tick exited 0 without refreshing the board."
           act="Read the board= field:"; cmd="tail ~/.claude/logs/accounts-keepwarm.out.log" ;;
    *) say="is loaded and idle, last exit ${PS_RC:-unknown}, so its ticks are failing."
       act="Read its error log:"; cmd="tail ~/.claude/logs/accounts-keepwarm.err.log" ;;
  esac
  printf '%saccounts board is stale: its producer, the keepwarm launchd job, %s %s\n%s%s' \
    "$FIT_RAW" "$say" "$act" "$FIT_RAW" "$cmd"
}

# ── NARROW PANES (2026-10-18) ─────────────────────────────────────────────────────────────────
# The board file is 76 cells wide, and a SessionStart systemMessage gets pane − 5 cells (a 5-column
# continuation indent) plus, on line 1 only, the harness's ~31-column `⎿ SessionStart:startup
# says: ` prefix (docs/research/board-render-2026-09-22.md, findings 6-7). So below an 81-column
# pane every grid row wrapped mid-cell, which is the break the operator screenshotted. The producer
# now also writes narrower variants beside the board (`<board>.w<N>`, N = the cell budget each was
# laid out for), and this hook picks the widest one that fits the pane it is drawing into.
#
# THE PANE WIDTH comes from the tty of the claude process that ran this hook: the hook's own stdio
# is a pipe, so we walk up from our parent to the first ancestor that owns a tty and ask the tty
# (`stty -f`, BSD; `-F` is the GNU spelling), ~50 ms. `CC_PANE_COLS` overrides it, the same seam
# `claude-accounts --pane` reads. An unknown width changes nothing: the 76 board, as before.
PANE_GUTTER=5      # continuation indent on every rendered row
PANE_PREFIX=31     # line 1's `⎿ SessionStart:startup says: ` prefix
BOARD_W=76         # the width the main board file is laid out for (bin/claude-accounts NARROW_W)

pane_cols() {
  local p t sz i
  case "${CC_PANE_COLS:-}" in '') ;; *[!0-9]*) return 1 ;; *) printf '%s' "$CC_PANE_COLS"; return 0 ;; esac
  p="${CC_HOOK_PARENT_PID:-$PPID}"
  for i in 1 2 3 4 5; do
    t="$(ps -o tty= -p "$p" 2>/dev/null | tr -d ' ')"
    case "$t" in
      ''|'?'*) ;;
      *) sz="$(stty -f "/dev/$t" size 2>/dev/null || stty -F "/dev/$t" size 2>/dev/null)"
         case "${sz##* }" in ''|*[!0-9]*|0) ;; *) printf '%s' "${sz##* }"; return 0 ;; esac ;;
    esac
    p="$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')"
    case "$p" in ''|*[!0-9]*|0|1) return 1 ;; esac
    : "$i"
  done
  return 1
}
COLS="$(pane_cols 2>/dev/null || true)"

# The narrow variant for this pane, or the board itself. Only a variant written in the SAME
# producer pass as the board counts (mtimes within 60 s): the hook labels the board's age from
# the board's mtime, so a leftover variant from an older producer would print older numbers under
# a fresher label.
pick_board() {
  local use w best="" bm vm f
  [ -n "$COLS" ] || { printf '%s' "$BOARD"; return; }
  use=$(( COLS - PANE_GUTTER ))
  [ "$use" -ge "$BOARD_W" ] && { printf '%s' "$BOARD"; return; }
  bm="$(stat -f %m "$BOARD" 2>/dev/null || stat -c %Y "$BOARD" 2>/dev/null || echo 0)"
  for f in "$BOARD".w[0-9]*; do
    [ -s "$f" ] || continue
    w="${f##*.w}"; case "$w" in *[!0-9]*) continue ;; esac
    vm="$(stat -f %m "$f" 2>/dev/null || stat -c %Y "$f" 2>/dev/null || echo 0)"
    [ $(( bm - vm )) -le 60 ] && [ $(( vm - bm )) -le 60 ] || continue
    # the widest that fits; failing any fit, the narrowest there is
    if [ "$w" -le "$use" ]; then
      case "$best" in ''|-*) best="$w" ;; *) [ "$w" -gt "$best" ] && best="$w" ;; esac
    else
      case "$best" in '') best="-$w" ;; -*) [ "$w" -lt "${best#-}" ] && best="-$w" ;; esac
    fi
  done
  case "$best" in '') printf '%s' "$BOARD" ;; *) printf '%s' "$BOARD.w${best#-}" ;; esac
}

# Fit a message to the pane at WORD boundaries, so the terminal never wraps it mid-word. Lines
# carrying SGR are the producer's laid-out grid and pass through untouched (pick_board already
# chose a variant that fits); plain prose — the age, staleness and producer lines this hook writes
# — is re-wrapped with a hanging indent two past its own. A single token wider than the pane (a
# path, a command) is never split: broken, it would no longer paste. And when line 1 cannot share
# its row with the harness prefix, the message starts on the next row instead.
fit() {  # <message> → the message fitted to $COLS, or unchanged when the width is unknown
  [ -n "$COLS" ] || { printf '%s' "$1"; return; }
  local LC_ALL=en_US.UTF-8
  local use=$(( COLS - PANE_GUTTER )) line ind word cur out="" first="" n=0
  while IFS= read -r line || [ -n "$line" ]; do
    n=$(( n + 1 ))
    if [ "$n" -eq 1 ]; then
      first="$(printf '%s' "${line#"$FIT_RAW"}" | sed $'s/\033\\[[0-9;]*m//g')"
    fi
    case "$line" in *$'\033'*|"$FIT_RAW"*) out="$out$line"$'\n'; continue ;; esac
    if [ "${#line}" -le "$use" ]; then out="$out$line"$'\n'; continue; fi
    ind="${line%%[! ]*}"; cur="$ind"
    set -f
    # shellcheck disable=SC2086  # word-splitting the prose IS the point
    for word in $line; do
      if [ "$cur" = "$ind" ] || [ "$cur" = "$ind  " ]; then cur="$cur$word"
      elif [ $(( ${#cur} + 1 + ${#word} )) -le "$use" ]; then cur="$cur $word"
      else out="$out$cur"$'\n'; cur="$ind  $word"
      fi
    done
    set +f
    out="$out$cur"$'\n'
  done <<EOF
$1
EOF
  out="${out%$'\n'}"
  [ $(( ${#first} + PANE_PREFIX )) -gt "$COLS" ] && out=$'\n'"$out"
  printf '%s' "$out"
}

emit() {  # <message> → the ONE sanctioned channel, top-level, never nested, never additionalContext
  local m
  m="$(fit "${DL_BANNER:-}${SH_FLEET:-}$1")"
  jq -nc --arg m "${m//"$FIT_RAW"/}" '{systemMessage:$m}' 2>/dev/null || true
  exit 0
}

input="$(cat 2>/dev/null || true)"

# ── DEADLINE BANNER (personal/deadlines/DESIGN-2026-09-29.md §4.4) ──────────────────────────────
# Prepends `dl render`'s pre-rendered .state/banner.txt to whatever this hook emits. Only a `cat`:
# no Python under this hook's 5 s timeout. With banner.txt absent DL_BANNER is empty and every
# output below is byte-identical to the board without this block (test A13).
# GATED so headless runs cannot use it up: CLAUDE_CODE_ENTRYPOINT=cli (headless `claude -p` reports
# sdk-cli; when the variable is unset, the parent's argv must carry no -p/--print), not a fired peer
# (oi_origin_class), and a cwd outside /tmp. LATCH on (date, content hash): once a day in the first
# real interactive session, and again whenever the content changes. Subshell + `|| true`: a fault
# here costs the banner, never the board.
dl_banner() {
  local f latch cur cwd ent pane lib tp
  f="${DL_DIR:-$HOME/Development/personal/deadlines}/.state/banner.txt"
  [ -s "$f" ] || return 0
  ent="${CLAUDE_CODE_ENTRYPOINT:-}"
  if [ -z "$ent" ]; then
    ps -o args= -p "${CC_HOOK_PARENT_PID:-$PPID}" 2>/dev/null | grep -E '(^|[[:space:]])(-p|--print)([[:space:]]|$)' >/dev/null && return 0
  elif [ "$ent" != cli ]; then return 0; fi
  cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)"; cwd="${cwd:-$PWD}"
  case "$cwd/" in /tmp/*|/private/tmp/*) return 0 ;; esac
  lib="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/lib/origin-identity.sh"
  [ -f "$lib" ] || { lib="$0"; [ -L "$lib" ] && lib="$(readlink "$lib")"
    lib="$(cd "$(dirname "$lib")" 2>/dev/null && pwd)/lib/origin-identity.sh"; }
  # shellcheck source=lib/origin-identity.sh
  # shellcheck disable=SC1091
  . "$lib" 2>/dev/null || return 0
  pane="${CC_PANE_ID:-${ITERM_SESSION_ID:-}}"; pane="${pane##*:}"
  tp="$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null)"
  [ "$(oi_origin_class "$pane" "$cwd" "$tp")" = fired-peer ] && return 0
  cur="$(date +%F) $("${CC_SHA1:-/sbin/sha1sum}" < "$f" 2>/dev/null | cut -c1-16)"
  latch="${f%/*}/banner-latch"
  [ "$(cat "$latch" 2>/dev/null)" = "$cur" ] && return 0
  # The latch is spent only on PROOF that the banner reached the session (README §5 unit 5.4): this
  # child's output rides the dispatcher's, which can be cancelled after this line. With a session id
  # and hooks/lib/startup-proof.sh, file the latch write as a proof request on the banner's first
  # line; session-beat's worker writes the latch once the transcript holds it. Otherwise latch now.
  local first sid spl
  first="$(sed -n '/[^[:space:]]/{p;q;}' "$f" 2>/dev/null)"
  sid="$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)"
  spl="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/lib/startup-proof.sh"
  # shellcheck source=lib/startup-proof.sh disable=SC1091  # runtime-resolved beside this file
  if ! { [ -n "$first" ] && [ -f "$spl" ] && . "$spl" 2>/dev/null \
         && sp_request "$sid" dl-banner "$first" write "$latch" "$cur"; }; then
    printf '%s\n' "$cur" > "$latch" 2>/dev/null || true
  fi
  printf '%s\n' "$(cat "$f")"
}

# `compact` is excluded and the other sources are not. A board answers "which account am I on and
# what is left" — a question a human asks when a session BEGINS (startup), when it is reset
# (clear), or when it is picked back up (resume). A compaction is none of those: same session,
# same account, mid-task, and the operator is usually not even looking. Firing there would spend
# the board's whole value, which is that its appearance means something.
src="$(printf '%s' "$input" | jq -r '.source // ""' 2>/dev/null || true)"
[ "$src" = "compact" ] && exit 0

# ── STARTUP-HEALTH FLEET LINE (docs/research/startup-hooks-2026-10-18/README.md §5 unit 3.5) ───────
# One `cat` of the line `cc-startup-health --fleet` folds off the hook path on every keepwarm tick:
# startup hook losses since the operator's last `cc-startup-health --ack` (gap-G4: ~94% of own-hook
# startup drops happen in panes no person is shown to watch, so this board is how they reach one).
# Prefixed to EVERY emit below, outside the staleness bands: a loss count is not a rolling quota, so
# withholding a stale board's numbers must not withhold it. A fold older than 2 ticks (keepwarm runs
# every 180 s) says so instead of vanishing. Neither file present ⇒ the fold never ran here, and
# every output below is byte-identical to the board without this block.
sh_fleet() {
  local r="${CC_STARTUP_HEALTH_DIR:-$HOME/.claude/state/startup-health}" m
  [ -e "$r/fleet.stamp" ] || [ -e "$r/fleet-line.txt" ] || return 0
  m="$(stat -f %m "$r/fleet.stamp" 2>/dev/null || echo 0)"
  if [ $(( $(date +%s) - m )) -gt "${CC_STARTUP_FLEET_STALE_S:-360}" ]; then
    if [ "$m" -gt 0 ]; then printf 'startup-health fold stale since %s\n' "$(date -r "$m" '+%m-%d %H:%M')"
    else printf 'startup-health fold stale since never\n'; fi
    return 0
  fi
  [ -s "$r/fleet-line.txt" ] && printf '%s\n' "$(cat "$r/fleet-line.txt")"
  # The span guard (#25) shares the fold and its freshness: a line only when a load band is over target.
  [ -s "$r/span-line.txt" ] && printf '%s\n' "$(cat "$r/span-line.txt")"
  return 0
}
SH_FLEET="$( (sh_fleet) 2>/dev/null || true)"
[ -n "$SH_FLEET" ] && SH_FLEET="$SH_FLEET
"

DL_BANNER="$( (dl_banner) 2>/dev/null || true)"
[ -n "$DL_BANNER" ] && DL_BANNER="$DL_BANNER
"

now="$(date +%s)"

# ── THE DATED STAMP (2026-10-24, operator ask) ─────────────────────────────────────────────────
# This message stays in the scrollback for the life of the session, and every age in it ("47
# seconds ago", "STALE by 10m") is relative to a moment the reader can no longer see. So the
# first line names that moment as wall-clock time with the day: when the quota was read and, when
# that differs, when the session opened. Read back hours later, the board's age is one subtraction.
when() {  # <epoch> [<epoch it shares a day with>] → "Sat Oct 24 11:55", or "11:55" on the same day
  local d
  [ -n "${2:-}" ] && [ "$(date -r "$1" +%F 2>/dev/null)" = "$(date -r "$2" +%F 2>/dev/null)" ] \
    && { date -r "$1" '+%H:%M' 2>/dev/null; return; }
  d="$(date -r "$1" +%d 2>/dev/null)"
  date -r "$1" "+%a %b ${d#0} %H:%M" 2>/dev/null
}
stamp() {  # [<board epoch>] → the dated first line
  local o
  o="$(when "$now")"
  [ -n "${1:-}" ] || { printf 'Session opened %s\n' "$o"; return; }
  [ "$(when "$1" "$now")" = "$(when "$now" "$now")" ] && { printf 'As of %s\n' "$o"; return; }
  printf 'As of %s · session opened %s\n' "$(when "$1")" "$(when "$now" "$1")"
}

[ -f "$BOARD" ] || emit "$(stamp)
accounts board unavailable — nothing pre-rendered at $BOARD.
  Producer $PRODUCER $(producer_state)
  For the live table right now, run: claude-accounts"

# BSD stat first (this fleet is Darwin), GNU second, and a FAILURE to read the mtime is treated
# as unknown-age rather than as age 0. Defaulting to 0 would render an ancient board as fresh —
# the single worst outcome available to this hook, reached by the most forgettable line in it.
mtime="$(stat -f %m "$BOARD" 2>/dev/null || stat -c %Y "$BOARD" 2>/dev/null || echo "")"
if [ -z "$mtime" ]; then
  emit "$(stamp)
accounts board found but its age is unreadable ($BOARD) — numbers withheld.
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

body="$(cat "$(pick_board)" 2>/dev/null || true)"
# Emptiness by a glob, never by stripping: `${body//[[:space:]]/}` is superlinear on /bin/bash 3.2
# (0.9 s on a 2 KB board, 6.5 s at 4 KB; docs/research/sessionstart-readout-2026-10-06, R1), so
# every byte added to the board would have cost startup time wherever this runs under 3.2.
if case "$body" in *[![:space:]]*) false ;; *) true ;; esac; then
  emit "$(stamp "$mtime")
accounts board at $BOARD is EMPTY — the producer wrote nothing.
  Producer: $PRODUCER. For the live table, run: claude-accounts"
fi

if [ "$age" -ge "$HARD_S" ]; then
  # NUMBERS SUPPRESSED, deliberately. Everything this board reports is a percentage of a window
  # that rolls — the 5h one every five hours — so past the hard band the figures are not merely
  # old, they can be describing a window that no longer exists.
  emit "$(stamp "$mtime")
accounts board is $(fmt_age "$age") old — numbers withheld as unsafe to read (the 5h
  window it reports rolls every 5h, so a board this old can describe a window that has ended).
  Producer $PRODUCER $(producer_state)
  For the live table, run: claude-accounts"
fi

# ── THE BAND (2026-10-21, docs/research/accounts-board-band-2026-10-21/) ──────────────────────
# Everything here is static text, hard-wrapped at the width the pane had at startup, and Claude
# Code has no render component for a SessionStart message, so a pane widened later keeps a ~45-cell
# board. mods/accounts-readout draws the board instead, as a band above the prompt that re-lays out
# at every width change and goes away at the first prompt (not a fired pane's brief, which claude
# submits at launch: the mod's grace window, 2026-10-23). HANDSHAKE, measured in a pty: the mod's
# `classic.SessionStart` hook runs ABOVE the settings hooks (chain: managed, modules, settings), so
# it stamps `<sid>.board-band.req` with this session's id BEFORE this hook runs, and after it returns
# reads the snapshot this hook leaves. Only on the fresh and STALE paths (a hard, empty or
# unreadable board keeps its static, labelled text above), only when the ladder was written in the
# board's own producer pass, and only once the snapshot is in place does the grid leave the
# systemMessage: never both, never neither. No stamp (no mod, CC_MODS=off, `claude -p`) and every
# byte below is today's.
#
# A STALE BOARD GOES TO THE BAND TOO (2026-10-22). It used to take the static path, and Claude Code
# re-wrapped that grid at a narrow pane: columns scattered across rows, `28d 13h` split in two,
# `claude-accounts --re|adout` cut mid-word (docs/research/accounts-narrow-2026-10-22/, P3). The
# band labels it itself: the mod reads the age from the snapshot's mtime (`cp -p` keeps the board's)
# and draws its `⚠ STALE` head, re-evaluated while it waits. What the band cannot know is WHY the
# producer is behind, so that diagnosis stays here as static prose, wrapped at words.
#
# THE BAND IS OPT-IN; THE GRID IS BACK IN THE HEADER (operator ruling 2026-10-23, decision
# 9ee7197568c1). The operator wants the board ALWAYS visible, after every prompt, under the Clawd
# header in the `SessionStart:startup says:` block. The band could not give that: the mod cleared
# it at the first prompt, and its `[-]` collapse is Claude Code's (docs/research/startup-readout-
# visibility-2026-10-23.md). A hook row is never removed by the TUI. Accepted cost: the static grid
# keeps its startup numbers and startup width, so a pane narrowed later re-wraps it, and only
# `claude-accounts --readout` redraws it live. CC_BOARD_BAND=on restores the band.
band_handoff() {
  local sid stem dir req lad snap now qm lm
  [ "${CC_BOARD_BAND:-off}" = on ] || return 1
  sid="$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)"
  stem="$(printf '%s' "$sid" | tr -cd 'A-Za-z0-9_-')"
  [ -n "$stem" ] || return 1
  dir="${CC_PANE_DIR:-/tmp/claude-accounts-pane}"
  req="$dir/$stem.board-band.req"
  [ "$(cat "$req" 2>/dev/null)" = "$sid" ] || return 1
  now="$(date +%s)"
  qm="$(stat -f %m "$req" 2>/dev/null || stat -c %Y "$req" 2>/dev/null || echo 0)"
  [ $(( now - qm )) -le "${CC_BOARD_BAND_REQ_S:-30}" ] || return 1     # a leftover, not this start's
  lad="$BOARD.ladder.json"
  [ -s "$lad" ] || return 1
  lm="$(stat -f %m "$lad" 2>/dev/null || stat -c %Y "$lad" 2>/dev/null || echo 0)"
  [ $(( mtime - lm )) -le 60 ] && [ $(( lm - mtime )) -le 60 ] || return 1
  snap="$dir/$stem.board-band.json"
  cp -p "$lad" "$snap.$$" 2>/dev/null && mv -f "$snap.$$" "$snap" 2>/dev/null \
    || { rm -f "$snap.$$" 2>/dev/null; return 1; }
}
if band_handoff; then
  band_msg="${DL_BANNER:-}${SH_FLEET:-}"     # the banner and the fleet line stay static text
  [ "$age" -ge "$STALE_S" ] && band_msg="${band_msg}$(producer_note)
"
  [ -n "$band_msg" ] || exit 0
  DL_BANNER=""; SH_FLEET=""
  emit "${band_msg%$'\n'}"
fi

if [ "$age" -ge "$STALE_S" ]; then
  emit "$(stamp "$mtime")
⚠ STALE by $(fmt_age "$age") — the numbers below are last-known, not current.
  Producer $PRODUCER $(producer_state)
  Live table: claude-accounts

$body"
fi

emit "$(stamp "$mtime")
$body"
