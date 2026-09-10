#!/bin/bash
# unit-gate.sh — PreToolUse hook, matcher "*". THE BRAKE, THE HALTED STAMP, THE UNIT LEDGER.
#
# Spec: docs/research/oversight-at-scale-2026-08-19.md §5.2 (contract) + §5.3 (namespace).
# Backlog: ad37b0296a56.
#
# WHY A TOOL-GRANULARITY GATE AND NOT A SPAWN GATE (N17/N16, measured in the doc). `PreToolUse`
# DOES fire for a Workflow agent's own tool calls, carrying `agent_type` and a distinct `agent_id`,
# and a `deny` there brakes the unit MID-RUN and beats `--permission-mode bypassPermissions` — the
# fleet's most permissive mode. Our `Agent` spawn matcher, by contrast, fires **0 times** for
# `agent()`. So the kill switch has to live where the work happens, not where it is requested.
#
# 🚨 IT IS A BRAKE, NOT A STOP — and the word matters in every message this file emits. A denied
# tool call does not abort the agent: it keeps its turn, keeps thinking, keeps spending. It removes
# the BLAST RADIUS, not the SPEND. It converts runaway *action* into runaway *talk*.
#
# 🚨 WHY THE STAMP IS NOT OPTIONAL. The measured braked run still wrote `result:"DONE"`, completed,
# and produced a 2,093-byte output with zero side effects. A brake whose runs render as *completed*
# is worse than the runaway it stopped, because it launders a green. Every deny writes
# `units/<id>.halted` so every SEE surface can render **halted**.
#
# ── FAIL-OPEN, DELIBERATELY, AND THE COST OF THAT CHOICE ────────────────────────────────────────
# This is the only hook on this machine that sees EVERY tool call of EVERY class. A fail-CLOSED bug
# here denies every tool call in every session at once, and the only cure — editing settings.json —
# is itself a tool call. So every error path exits 0 (allow). The price is the shape MEMORY.md calls
# `fail-safe-default-mimics-the-healthy-state`: a hook broken into silence is indistinguishable from
# a hook with nothing to brake. That is paid for, not ignored — `cc-halt --selftest` executes this
# file against a fixture HALT and FAILS if the deny does not come back, so the arm has an oracle
# that can go red instead of a default that always looks calm.
#
# ── COST, RE-MEASURED HERE ──────────────────────────────────────────────────────────────────────
# Budget (doc N19): p50 2.85 ms · p90 3.12 ms · max 3.80 ms per tool call, n=60 — a trivial
# `/bin/bash` fork + stdin read. To stay inside it, THE FAST PATH FORKS NOTHING: stdin is read with
# `read -d ''`, the payload is parsed with bash regex, and the three checks are `[ -e ]` builtins.
# No `jq`, no `cat`, no `date`, no subshell. `date` runs only on a deny and on the once-per-unit
# ledger append; both are the exceptional path.
#
# 🚨 QUOTE THE RATIO, NOT THE MILLISECONDS. Re-measured 2026-09-09, n=60 each, interleaved against a
# trivial control on the same box in the same minute: control p50 3.23 ms, this hook p50 4.53 ms —
# **1.40x the control**, p90 5.04 ms. The control itself read 3.23 ms where N19 read 2.85, because
# ambient load is a covariate on this surface and was ~19 here (MEMORY: two-runs-disagreeing-may-be-
# one-curve — a precondition you can only partly satisfy is a covariate in disguise). The absolute
# number will not reproduce; the ratio is the claim, and the re-measure command is one line:
#   for f in /tmp/trivial.sh hooks/unit-gate.sh; do …60 timed `/bin/bash $f` runs, same payload…
# R10 in the doc still stands and is NOT closed by this: both figures are microbenchmarks, and the
# fleet-under-load cost of a `*` matcher across 10 concurrent sessions has never been measured.
set -uo pipefail

CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

# Read the whole payload with no fork. `read -d ''` returns non-zero at EOF without a NUL, which is
# the normal case here — the data is in PAYLOAD either way, so the status is deliberately discarded.
PAYLOAD=''
IFS= read -r -d '' PAYLOAD || true
# NOTE there is deliberately no `[ -n "$PAYLOAD" ] || exit 0` here. An empty or unparseable payload
# yields no identity, so it can never MANUFACTURE a brake — but it must not DISSOLVE one either. The
# fleet check below needs no identity at all, so garbage input under an explicit fleet HALT is still
# denied. An early return here would have made "send the hook something it cannot parse" a bypass of
# the one control that is supposed to reach every class (caught by tests/unit-gate.bats case 20,
# which asserts BOTH arms: allow when nothing is set, deny when the operator has set one).

# ── identity extraction ─────────────────────────────────────────────────────────────────────────
# Scan the payload PREFIX, cut at `"tool_input"`, not the whole thing. A regex over the full payload
# is the `pgrep-f-matches-agent-briefs` defect in another costume: `tool_input.prompt` carries whole
# briefs, so a prompt that merely QUOTES `"agent_id": "..."` — this file's own header would do it —
# would be read as the caller's identity and could brake or mis-attribute an innocent session. CC
# emits the identity fields before `tool_input`; if that ever inverts, the fields simply come back
# empty and the hook allows, which is the safe direction. The value charset is constrained for the
# same reason, and doubles as the path guard below.
_needle='"tool_input"'
IDSCAN="${PAYLOAD%%"$_needle"*}"
[ -n "$IDSCAN" ] || IDSCAN="$PAYLOAD"

# It ASSIGNS to _FV rather than echoing, and the callers below do not use `$( )`. That is a
# measurement, not a style preference: a command substitution forks a subshell, so the echo-and-
# capture shape cost four forks on the fast path — measured 7.83 ms p50 against a 3.35 ms trivial
# control on the same box and minute, i.e. 2.34x the control. Assigning instead measures 1.40x
# (4.53 vs 3.23 ms p50). The header above claims the fast path forks nothing; this is what makes
# that sentence true rather than aspirational. The residual 1.4x is bash doing real work — four
# regex matches over the payload prefix — and is not a fork; it is the honest price of the identity
# read, and it is stated rather than rounded to the number that would have sounded better.
_field() { # $1 = top-level key → sets _FV to its string value, or ''
  _FV=''
  local re="\"$1\"[[:space:]]*:[[:space:]]*\"([A-Za-z0-9@:._-]{1,128})\""
  [[ $IDSCAN =~ $re ]] && _FV="${BASH_REMATCH[1]}"
  return 0
}

_FV=''
_field session_id; SESSION_ID="$_FV"
_field agent_id;   AGENT_ID="$_FV"
_field agent_type; AGENT_TYPE="$_FV"
_field tool_name;  TOOL_NAME="$_FV"

# `.` and `..` pass the charset above and would make `HALT.d/<id>` name a DIRECTORY, which `[ -e ]`
# reports present — a brake nobody set, on every session at once. Reject them by name.
case "$SESSION_ID" in .|..) SESSION_ID='' ;; esac
case "$AGENT_ID"   in .|..) AGENT_ID='' ;; esac

# The unit's own address: an in-process agent has one, a main session falls back to its session id.
# This IS the id §5.3 is about — `cc-teardown:194` refuses a name it cannot verify precisely because
# no store has ever said what an in-process unit is or who owns it.
UNIT_ID="${AGENT_ID:-$SESSION_ID}"

# ── the exemption, and why it is not a command-text match ───────────────────────────────────────
# "The cure must not be blocked by the flag" (§5.2). This repo has shipped the opposite twice
# (`guard-refusal-fires-on-its-own-harness`, `denylist-enumerates-spellings-not-the-class`), and
# both times the fix that failed was a text match: a denylist enumerates SPELLINGS, so the cure
# `rm ~/.claude/HALT` and the runaway `rm -rf /` are one grep apart and the guard denied its own
# remedy. The exemption is therefore an IDENTITY, checked two ways:
#   · CC_UNIT_GATE_EXEMPT — an env stamp that must EQUAL this call's session or unit id. Equality,
#     not truthiness: a bare `=1` inherited by every child would exempt the whole process tree,
#     which is the runaway wearing the operator's badge.
#   · the halt file's own `exempt_session=` line — whoever SET a brake is never braked by it, so the
#     setter can always clear it. Written by `cc-halt`; a hand-`touch`ed HALT carries no line and
#     nothing is exempt, which is correct and is why `cc-halt clear` exists as a plain-shell verb.
EXEMPT="${CC_UNIT_GATE_EXEMPT:-}"
if [ -n "$EXEMPT" ] && { [ "$EXEMPT" = "$SESSION_ID" ] || [ "$EXEMPT" = "$UNIT_ID" ]; }; then
  exit 0
fi

# ── the three checks (§5.2 "Check"): fleet · session · unit. Miss on all three ⇒ allow. ──────────
HALT_FILE=''; HALT_SCOPE=''
if   [ -e "$CFG/HALT" ];                                    then HALT_FILE="$CFG/HALT";                    HALT_SCOPE='fleet'
elif [ -n "$SESSION_ID" ] && [ -e "$CFG/HALT.d/$SESSION_ID" ]; then HALT_FILE="$CFG/HALT.d/$SESSION_ID";   HALT_SCOPE='session'
elif [ -n "$AGENT_ID" ]   && [ -e "$CFG/HALT.d/$AGENT_ID" ];   then HALT_FILE="$CFG/HALT.d/$AGENT_ID";     HALT_SCOPE='unit'
fi

# ── §5.2 "Register": one ledger row on the FIRST tool call carrying an agent_id ─────────────────
# This is the namespace §5.3 needs and it costs one `[ -e ]` plus, once per unit, one append. It
# runs on the ALLOW path too — a unit that is never braked is exactly the unit the operator most
# needs to be able to name.
if [ -n "$AGENT_ID" ] && [ ! -e "$CFG/units/$AGENT_ID.seen" ]; then
  if mkdir -p "$CFG/units" "$CFG/logs" 2>/dev/null; then
    _ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)" || _ts=''
    _row="{\"ts\":\"$_ts\",\"unit_id\":\"$AGENT_ID\",\"agent_type\":\"${AGENT_TYPE:-unknown}\",\"session_id\":\"${SESSION_ID:-unknown}\",\"first_tool\":\"${TOOL_NAME:-unknown}\",\"halted\":false}"
    # SIZE BOUND, not truncation (MEMORY: append atomicity ends at the stdio buffer). Past the
    # writer's stdio buffer a single append is >=2 `write()` calls, so a concurrent appender on the
    # shared fd can land BETWEEN them and splice the record — one unparseable line that every census
    # then drops silently. Every field above is charset-constrained, so this can only trip if the
    # payload shape changes; refusing the row is right, cutting a JSON line in half is not.
    if [ "${#_row}" -le 4000 ]; then
      printf '%s\n' "$_row" >> "$CFG/logs/units.jsonl" 2>/dev/null || true
      : > "$CFG/units/$AGENT_ID.seen" 2>/dev/null || true
    fi
  fi
fi

[ -n "$HALT_SCOPE" ] || exit 0

# ── braked ──────────────────────────────────────────────────────────────────────────────────────
# Prefer the timestamp cc-halt recorded IN the file: it says when the brake was SET, which is the
# fact the operator needs, and reading it costs no fork where `date` would.
HALT_TS=''
while IFS= read -r _l || [ -n "$_l" ]; do
  case "$_l" in
    ts=*)             HALT_TS="${_l#ts=}" ;;
    exempt_session=*) [ "${_l#exempt_session=}" = "$SESSION_ID" ] && exit 0 ;;
  esac
done < "$HALT_FILE" 2>/dev/null
[ -n "$HALT_TS" ] || HALT_TS="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)"

# The stamp. Written BEFORE the deny is emitted: if this process dies between the two, the surface
# that renders the unit must still say halted rather than completed.
if [ -n "$UNIT_ID" ] && mkdir -p "$CFG/units" 2>/dev/null; then
  printf '%s\t%s\t%s\n' "$HALT_TS" "$HALT_SCOPE" "${TOOL_NAME:-unknown}" \
    >> "$CFG/units/$UNIT_ID.halted" 2>/dev/null || true
fi

# A PreToolUse hook signals a block through this JSON, never through an exit code.
printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"BRAKED: HALT %s — set by cc-halt at %s. This is a BRAKE, not a stop: your turn continues and your spend continues, only the tool call is refused. Stop working and report. Clear it from a plain shell with: cc-halt clear %s"}}\n' \
  "$HALT_SCOPE" "$HALT_TS" "$HALT_SCOPE"
exit 0
