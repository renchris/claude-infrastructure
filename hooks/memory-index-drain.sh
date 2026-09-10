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

# ── THE ROTOR IS BOUNDED, AND THE BOUND IS ONE SHARED BUDGET ─────────────────────────────────────
# This hook fires on PostToolUse Bash|Write|Edit|MultiEdit — the hottest matcher in the config — and
# it called the rotor UNBOUNDED at both sites below. The rotor is not fast in the case that matters:
# measured 118s under a forced breach, because the hub scan forks one grep per topic file per
# candidate. Past the timeout DECLARED for this hook the harness kills it, and a killed hook renders
# NO additionalContext at all — so the operator learns nothing in precisely the turn the index
# needed attention most. An unbounded call under a declared timeout is a bound owned by the wrong
# party: the deadline exists, it just belongs to something that cannot say why it fired.
#
# The budget is TOTAL across both call sites, not per-call, because it is sized against ONE number —
# the timeout declared in settings.json. Per-call bounds MULTIPLY across the sites that spend them
# (MEMORY.md exoneration-bound-must-fit-what-it-bounds), so two 7s calls under a 10s declaration is
# still a kill. The default is deliberately safe under the UNRAISED declaration of 10: correct
# before migration 0018 runs, and roomier after it raises the declaration to 30 and sets
# MID_DEADLINE_S alongside it in the same settings.json edit, so the two can never drift apart.
#
# No timeout(1) ⇒ run unbounded rather than lose the actuator entirely — the same trade every other
# bounded call in this tree makes (hooks/waiting-recycle.sh, hooks/lib/osa.sh). Resolved by ABSOLUTE
# path as well as PATH: hooks run without Homebrew on PATH, and that is where coreutils installs it.
# Seams: MID_DEADLINE_S · MID_TIMEOUT_BIN (set-but-EMPTY disables the bound verbatim).
MID_DEADLINE_S="${MID_DEADLINE_S:-7}"
case "$MID_DEADLINE_S" in ''|*[!0-9]*) MID_DEADLINE_S=7 ;; esac
if [ -n "${MID_TIMEOUT_BIN+set}" ]; then
  MID_TB="${MID_TIMEOUT_BIN}"
else
  MID_TB=""
  for _c in "$(command -v timeout 2>/dev/null || true)" "$(command -v gtimeout 2>/dev/null || true)" \
            /opt/homebrew/bin/timeout /usr/local/bin/timeout \
            /opt/homebrew/bin/gtimeout /usr/local/bin/gtimeout; do
    [ -n "$_c" ] && [ -x "$_c" ] && { MID_TB="$_c"; break; }
  done
fi
MID_LEFT="$MID_DEADLINE_S"

# mid_rotor <args…> — runs the rotor under whatever is LEFT of the shared budget.
# rc 124 (timeout's own) or 137 (the -k KILL that follows) is a CUT; rc 125 here means the budget
# was already spent and the rotor was never invoked. Every caller must keep those three apart from a
# rotor that RAN and declined: a cut has no verdict, and reporting one would be a claim about work
# that never finished (MEMORY.md claimed-outcome-vs-checked-outcome).
# MID_CAP caps ONE call below the remaining budget. It exists because a purely first-come budget
# starves whichever site runs second, and the sites are not equally consequential: the per-entry
# drain answers "one line is too fat", the whole-index arm answers "the loader is already dropping
# your NEWEST entries". A slow drain must not be able to spend the deadline that belonged to the
# breach. So site 1 is capped at half and site 2 takes whatever is left, which is at least the other
# half — the total still fits the declaration, and neither site can be silently zeroed by the other.
MID_CAP=""
mid_rotor() {
  local b
  if [ -z "$MID_TB" ] || [ ! -x "$MID_TB" ]; then "$ROTOR" "$@"; return $?; fi
  b="$MID_LEFT"
  if [ -n "$MID_CAP" ] && [ "$MID_CAP" -lt "$b" ]; then b="$MID_CAP"; fi
  [ "$b" -gt 0 ] || return 125
  "$MID_TB" -k 2 "$b" "$ROTOR" "$@"
}

# mid_charge <epoch-seconds-taken-before-the-call> — debits what that call actually spent.
# 🚨 IT MUST RUN IN THE PARENT SHELL, immediately after the command substitution, and NOT inside
# mid_rotor. Every call site captures the rotor's stdout, so mid_rotor executes in a SUBSHELL and
# every assignment it makes is discarded at the closing paren
# (MEMORY.md assignment-inside-command-substitution-never-escapes). That is not hypothetical here:
# charging inside mid_rotor measured 6s against a 3s budget, because the second site opened with a
# full fresh MID_LEFT — two per-call bounds wearing the name of one shared one, which is the exact
# multiplication this budget exists to prevent.
mid_charge() {
  local now
  case "${1:-}" in ''|*[!0-9]*) MID_LEFT=0; return 0 ;; esac
  now=$(date +%s 2>/dev/null) || { MID_LEFT=0; return 0; }
  MID_LEFT=$(( MID_LEFT - ( now - $1 ) ))
  [ "$MID_LEFT" -ge 0 ] || MID_LEFT=0
}

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

MID_CAP=$(( (MID_DEADLINE_S + 1) / 2 ))
MID_T0=$(date +%s 2>/dev/null) || MID_T0=""
DV=$(mid_rotor "$MEM" --drain-oversized --rules-file "$RULES" 2>/dev/null); DRC=$?
mid_charge "$MID_T0"
[ -n "${DV:-}" ] || DV=""

CTX=""
# A CUT is REPORTED, never swallowed. The whole reason this hook actuates rather than warns is that
# a silent non-event is worth zero here; a cut that renders nothing is that same non-event with
# extra steps, and it is the failure the declared-timeout kill produced before the bound existed.
case "$DRC" in
  124|137)
    CTX="MEMORY INDEX DRAIN WAS CUT at its share of the ${MID_DEADLINE_S}s rotor budget and did NOT reach a verdict — an over-cap entry may still be sitting in the auto-loaded index. Nothing was moved and nothing was lost. Run it by hand to see what it would do: cc-memory-rotate <index> --drain-oversized --rules-file ${RULES}"
    ;;
esac
case "$DV" in
  verdict=drained*)
    FILES=$(printf '%s' "$DV" | sed -n 's/.* files=\([^ ]*\).*/\1/p')
    CTX="MEMORY INDEX DRAINED (automatic, this turn): the index line(s) you just wrote were over the per-entry buffer cap, so ${FILES:-they} moved VERBATIM to ${RULES}. Nothing was shortened and nothing was archived — that file is ALWAYS LOADED, so the rule still fires unprompted; only its surface changed. Restore = paste the line back into MEMORY.md. Write the next durable rule straight to ${RULES} and keep the MEMORY.md bullet short, and this stops happening. Verdict: ${DV}"
    ;;
  verdict=already-cited*)
    # Distinct from `exhausted` because the REMEDY is the opposite one. `exhausted` tells the
    # operator to append the line verbatim to the rules file; here the rules file ALREADY cites
    # that topic, so appending is precisely the duplicate the rotor's `already-cited` veto exists
    # to prevent. The body is reachable from an always-loaded surface, so the index line is pure
    # cost and the only action is to delete it. The rotor will not delete it for you — the
    # report-never-touch rule is what keeps a routing bug from eating an entry.
    CTX="MEMORY INDEX — the over-cap entry you just wrote is ALREADY CITED in ${RULES}, which is always loaded, so its rule is firing already and the MEMORY.md line is duplicate context. Nothing was moved and nothing is broken. Do NOT append it to ${RULES} again: DELETE the MEMORY.md bullet, or fold anything the incumbent citation is missing INTO that existing line rather than beside it. Verdict: ${DV}"
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
      # `--rules-file` is passed here too, and it is not decoration: ordinary rotation now ROUTES
      # what route_veto allows to the always-loaded rules file and cold-records only the rest, so
      # without this the whole-index remedy would still be a pure demotion on the one path that
      # already knows where this project's rules file is. The rotor degrades to the cold record on
      # its own if the destination is unusable, so passing it can only add the routing option.
      MID_CAP=""
      MID_T0=$(date +%s 2>/dev/null) || MID_T0=""
      RV=$(mid_rotor "$MEM" --rules-file "$RULES" 2>/dev/null); RRC=$?
      mid_charge "$MID_T0"
      # Three not-a-verdict outcomes, kept apart from each other and from a rotor that declined.
      RCUT=""
      case "$RRC" in
        124|137) RV=""; RCUT="was CUT at its share of the ${MID_DEADLINE_S}s rotor budget and did NOT reach a verdict" ;;
        125)     RV=""; RCUT="did NOT run — the ${MID_DEADLINE_S}s rotor budget was already spent by the per-entry drain above" ;;
      esac
      case "${RV:-}" in
        verdict=rotated*)
          CTX="${CTX:+$CTX }MEMORY INDEX WAS OVER ITS LOADER CAP (${U}/${LIM} chars, ${L}/${LLIM} lines) and was AUTO-ROTATED in this turn: ${RV#verdict=rotated }. Moved lines are VERBATIM in the cold record — restore = paste the line back."
          ;;
        *)
          WHY="ran and could NOT clear it (${RV:-no verdict})"
          [ -n "$RCUT" ] && WHY="$RCUT"
          CTX="${CTX:+$CTX }🚨 MEMORY INDEX IS OVER ITS LOADER CAP — ${U}/${LIM} chars, ${L}/${LLIM} lines. Past either cap the loader SILENTLY DROPS THE TAIL, the NEWEST entries, so anything you append now is written into the invisible tail. Auto-rotation ${WHY}. Route a durable rule to ${RULES} instead, or apply ONE-IN-ONE-OUT before appending anything else."
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
