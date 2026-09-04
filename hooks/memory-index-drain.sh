#!/usr/bin/env bash
# memory-index-drain.sh — PostToolUse: DETECT the auto-loaded index growing, AT THE WRITE, whichever
# door wrote it, and ACTUATE in the same turn.
#
# ── THE LEAK THIS CLOSES ─────────────────────────────────────────────────────────────────────────
# hooks/lib/memory-index-budget.sh is a PreToolUse gate and it is a good one — for the doors it can
# see. It cannot see Bash. The observed appends are `cd <…>/memory && … >> MEMORY.md`, and they are
# not rare: measured 1 in 6 index writes. Two independent reasons that door cannot simply be closed
# where it opens, both settled and not to be relitigated:
#
#   · A PreToolUse matcher on a Bash COMMAND STRING is a denylist over spellings. The relative
#     `>> MEMORY.md` form above is one spelling; `>>"$m"`, `tee -a`, `python3 -c`, a heredoc and a
#     `sed -i` are others. Denylists enumerate spellings, never the class
#     (MEMORY.md denylist-enumerates-spellings-not-the-class), and this one would be refusing an
#     act it can only guess at from a string.
#   · Nothing upstream will close it either. The product's own PostToolUse memory-size callback
#     registers on Read/Glob/Grep/Edit/Write. Bash is absent from that layer AND from ours.
#
# So the gate stays where it is and this hook covers the door it cannot reach — not by parsing the
# command, but by looking at the FILE. Whatever wrote it, the mtime moved. That is what makes this
# door-agnostic: it has no opinion about which tool ran.
#
# ── WHY POSTTOOLUSE AND NOT THE NEXT PROMPT ──────────────────────────────────────────────────────
# The obvious siting is UserPromptSubmit, where hooks/memory-nudge.sh already measures this exactly
# right. That is a full turn after the write, and it is the DEAD CLASS: a rule enforced somewhere
# other than where the act happens is detection, not a gate
# (MEMORY.md enforcement-must-live-at-the-chokepoint). memory-nudge has the record to prove it —
# twelve hand-compactions in fourteen days, four ledger items for one condition, and its only output
# channel is additionalContext, so it is structurally incapable of refusing or fixing anything.
# PostToolUse is one event later than the write and the file is on disk: it is the first moment the
# question "how big is it now" has a true answer.
#
# ── AND WHY IT ACTUATES RATHER THAN WARNS ────────────────────────────────────────────────────────
# Detection without an actuator is worth zero here, and that is measured, not asserted: the advisory
# has been correct and ignored for a month. The actuator is `cc-memory-rotate --drain-oversized`,
# which MOVES an over-cap index line to the project's always-loaded rules file, verbatim. It is
# non-lossy in the strong sense — the destination still loads unprompted, so nothing is shortened,
# nothing is archived, and no human is asked to judge anything. See that flag's header for why the
# tail guard must yield on that path and what still binds absolutely.
#
# ── FAIL-SAFE SHAPE ──────────────────────────────────────────────────────────────────────────────
# PostToolUse fires on the hottest path in the system, so the common case is ONE stat and an exit.
# Nothing is measured unless the stat differs from the last one recorded for that index. Every
# unresolvable, unreadable, jq-less or rotor-less path exits 0 silently: a side-car must never fail
# wider than itself (MEMORY.md addon-failure-exceeds-its-blast-radius), and the cost of a missed
# drain is one oversized line the next write catches.
set -uo pipefail

# Builtin read, NOT `$(cat)` — same reason hooks/log-bash.sh gives: command substitution forks AND
# execs on a path that fires on every tool call. `read -d ''` returns non-zero at EOF, the normal
# case, hence `|| true`.
IFS= read -r -d '' INPUT || true

command -v jq >/dev/null 2>&1 || exit 0

CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null) || CWD=""
[ -n "$CWD" ] && [ -d "$CWD" ] || CWD="$PWD"

CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

# Deref through the live symlink so a sibling ADDED in the same diff resolves in the CHECKOUT the
# moment the trunk fast-forwards, rather than staying invisible until the converger links it
# (MEMORY.md convergence-counter-measures-distance-not-delivery). Same pattern as
# hooks/memory-nudge.sh's _mn_deref.
_mid_deref() {
  local p="$1" t n=0
  readlink -f "$p" 2>/dev/null && return 0
  while [ -L "$p" ] && [ "$n" -lt 20 ]; do
    t="$(readlink "$p")"
    case "$t" in /*) p="$t" ;; *) p="$(dirname "$p")/$t" ;; esac
    n=$(( n + 1 ))
  done
  printf '%s\n' "$p"
}
_MID_DIR="$(dirname "$(_mid_deref "${BASH_SOURCE[0]}")")"

# Test readability FIRST. `.` is a POSIX special builtin: one that fails terminates a
# non-interactive shell BEFORE any `||` is consulted, so `. <missing> || fallback` is not a
# fallback at all — the exact inert guard memory-nudge.sh:126 documents having shipped.
_mid_src() {
  local f="$_MID_DIR/$1"
  [ -r "$f" ] || f="$CFG/hooks/$1"
  [ -r "$f" ] || return 1
  # shellcheck source=/dev/null
  . "$f" 2>/dev/null || return 1
}
_mid_src lib/memory-index-locate.sh  || exit 0
_mid_src lib/memory-index-measure.sh || exit 0

LOC=$(mil_locate "$CWD") || exit 0
MEM="${LOC%%	*}"
[ -n "$MEM" ] && [ -f "$MEM" ] || exit 0

# ── The stat gate: one syscall on the common path ────────────────────────────────────────────────
# mtime alone is not enough. A `>>` and the rotor's own temp+rename can both land inside one
# filesystem timestamp granularity, so the stamp carries SIZE too — a same-second write that
# changes the length is still a change. (This is a change DETECTOR, not a liveness proxy: it is
# read before the work, not after it — MEMORY.md liveness-proxy-cannot-be-output-age.)
_mid_stat() {
  local v
  v=$(stat -f '%m %z' -- "$1" 2>/dev/null) || v=""
  case "$v" in *[!0-9\ ]*|'') v="" ;; esac
  if [ -n "$v" ]; then printf '%s' "$v"; return 0; fi
  stat -c '%Y %s' -- "$1" 2>/dev/null
}

STATE_DIR="${MEMORY_DRAIN_STATE_DIR:-$CFG/state}"
mkdir -p "$STATE_DIR" 2>/dev/null || exit 0
# 🚨 THE LENGTH GUARD IS LOAD-BEARING, and its absence is silent. `${k: -120}` on bash 3.2 — the
# macOS system bash — returns the EMPTY STRING when k is shorter than 120, not the whole string
# (measured: `k=abcdefghij; echo "${k: -40}"` prints nothing). Unguarded, every index whose path is
# under 120 chars collapses to the same stamp file, so two projects share one change detector and
# each one's write reads as "already seen" for the other. The `${#MEM}` prefix keeps the tail-slice
# case honest too: a collision would then need the same path LENGTH and the same last 120 chars.
KEY="${MEM//\//-}"
if [ "${#KEY}" -gt 120 ]; then KEY="${KEY: -120}"; fi
STAMP="$STATE_DIR/memdrain-${#MEM}-${KEY}.stat"

NOWSTAT=$(_mid_stat "$MEM") || NOWSTAT=""
[ -n "$NOWSTAT" ] || exit 0
WAS=$(cat "$STAMP" 2>/dev/null) || WAS=""
if [ "$NOWSTAT" = "$WAS" ]; then exit 0; fi
# Record BEFORE acting. If the rotor below dies, the next write's stat differs from what we stored
# and re-arms this hook anyway; recording after would let a crash loop re-run the actuator on the
# identical file every tool call.
printf '%s' "$NOWSTAT" >"$STAMP" 2>/dev/null || true

# ── The rotor is the arbiter, not a second predicate here ────────────────────────────────────────
# This hook does NOT re-derive "is there an over-cap entry" before calling. Sampling a condition and
# then acting on it races the actuator that owns it, and a second implementation of the predicate is
# a second definition of the thing (MEMORY.md make-the-actuator-the-arbiter). `--drain-oversized`
# exits `verdict=noop` cheaply when there is nothing to route, which is the common case.
ROTOR="${MEMORY_ROTATE_BIN:-}"
if [ -z "$ROTOR" ]; then
  for c in "$_MID_DIR/../bin/cc-memory-rotate" "$CFG/bin/cc-memory-rotate"; do
    if [ -x "$c" ]; then ROTOR="$c"; break; fi
  done
fi
[ -n "$ROTOR" ] && [ -x "$ROTOR" ] || exit 0

# ── The destination, and why its root is resolved DIFFERENTLY from the index's ───────────────────
# The index is keyed on the MAIN worktree (mil_locate resolves through the git COMMON dir, because
# that is what the harness slugifies). The rules file is not: `.claude/rules/` is loaded from the
# repo the SESSION is in, so on a linked worktree the two roots are genuinely different files and
# using the index's root would write the rule into a checkout this session never reads. Hence
# `--show-toplevel` here against `--git-common-dir` there — the difference is the point.
#
# CWD is the last fallback and it is load-bearing, not decoration: a project that is not a git repo
# resolves nothing from git, and without this the hook detects the write correctly and then exits
# silently for want of somewhere to put it — a detector with no actuator, which is the exact class
# this wave exists to end.
PROJ="${CLAUDE_PROJECT_DIR:-}"
if [ -z "$PROJ" ]; then
  PROJ=$(cd "$CWD" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null) || PROJ=""
fi
[ -n "$PROJ" ] || PROJ="$CWD"
RULES="${MEMORY_RULES_FILE:-}"
if [ -z "$RULES" ] && [ -n "$PROJ" ]; then
  RULES="$PROJ/.claude/rules/agent-operating-lessons.md"
fi
[ -n "$RULES" ] || exit 0

DV=$("$ROTOR" "$MEM" --drain-oversized --rules-file "$RULES" 2>/dev/null) || true
[ -n "${DV:-}" ] || DV=""

CTX=""
case "$DV" in
  verdict=drained*)
    FILES=$(printf '%s' "$DV" | sed -n 's/.* files=\([^ ]*\).*/\1/p')
    CTX="MEMORY INDEX DRAINED (automatic, this turn): the index line(s) you just wrote were over the per-entry buffer cap, so ${FILES:-they} moved VERBATIM to ${RULES}. Nothing was shortened and nothing was archived — that file is ALWAYS LOADED, so the rule still fires unprompted; only its surface changed. Restore = paste the line back into MEMORY.md. Write the next durable rule straight to ${RULES} and keep the MEMORY.md bullet short, and this stops happening. Verdict: ${DV}"
    ;;
  verdict=exhausted*)
    CTX="MEMORY INDEX — an entry you just wrote is over the per-entry buffer cap and could NOT be routed automatically. Every over-cap line is vetoed: PINNED, the feedback-/reference-/user- name convention and an operator-voice \`type:\` stamp are absolute at the routing gate, and an unparseable or dangling line is reported, never touched. Move it by hand to ${RULES} (append VERBATIM, delete the MEMORY.md line in the same edit) or shorten the hook and leave the rule in its topic file. Verdict: ${DV}"
    ;;
esac

# ── Second actuation: the WHOLE-INDEX caps, in the same turn ─────────────────────────────────────
# The drain answers a PER-ENTRY condition. An index can be under that cap on every line and still be
# past the loader's 25000-unit / 200-line caps, which is the state where the newest entries are
# already invisible. cc-memory-rotate's ordinary mode is the remedy and it is unchanged here — the
# only thing this adds is WHEN it runs. hooks/memory-nudge.sh would run it on the next prompt; a
# turn later is a turn in which every further append lands in the tail the loader already dropped.
M=$(mim_measure_file "$MEM" 2>/dev/null) || M=""
if [ -n "$M" ]; then
  U="${M%% *}"; L="${M##* }"
  LIM=$(mim_limit 2>/dev/null) || LIM=""
  LLIM=$(mim_line_limit 2>/dev/null) || LLIM=""
  if [ -n "$LIM" ] && [ -n "$LLIM" ]; then
    if [ "$U" -gt "$LIM" ] 2>/dev/null || [ "$L" -gt "$LLIM" ] 2>/dev/null; then
      RV=$("$ROTOR" "$MEM" 2>/dev/null) || true
      case "${RV:-}" in
        verdict=rotated*)
          CTX="${CTX:+$CTX }MEMORY INDEX WAS OVER ITS LOADER CAP (${U}/${LIM} chars, ${L}/${LLIM} lines) and was AUTO-ROTATED in this turn: ${RV#verdict=rotated }. Moved lines are VERBATIM in the cold record — restore = paste the line back."
          ;;
        *)
          CTX="${CTX:+$CTX }🚨 MEMORY INDEX IS OVER ITS LOADER CAP — ${U}/${LIM} chars, ${L}/${LLIM} lines. Past either cap the loader SILENTLY DROPS THE TAIL, the NEWEST entries, so anything you append now is written into the invisible tail. Auto-rotation ran and could NOT clear it (${RV:-no verdict}). Route a durable rule to ${RULES} instead, or apply ONE-IN-ONE-OUT before appending anything else."
          ;;
      esac
    fi
  fi
fi

# Re-record: either actuator above may have rewritten the index, and the stamp taken before they
# ran now describes a file that no longer exists. Leaving it stale would re-arm this hook on the
# next tool call over a change THIS HOOK made — an actuator triggering on its own output.
NS=$(_mid_stat "$MEM") || NS=""
if [ -n "$NS" ]; then printf '%s' "$NS" >"$STAMP" 2>/dev/null || true; fi

[ -n "$CTX" ] || exit 0
jq -cn --arg ctx "$CTX" \
  '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$ctx}}'
exit 0
