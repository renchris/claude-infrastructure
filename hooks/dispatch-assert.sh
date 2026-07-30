#!/usr/bin/env bash
# dispatch-assert.sh — Stop hook: catch NARRATED-NOT-DISPATCHED follow-on work (operator crux
# 2026-07-25: "we are just sitting here on todo items that have no blockers that we should be
# proactively firing off on").
#
# THE DEFECT (the structural asymmetry vs completion-assert): completion-assert works because the
# facts it gates on (dirty tree / unlanded commits / DoD remainder) are written UNAVOIDABLY as a
# side effect of doing the work — git is the scribe, no discipline required. "Identified follow-on
# work" has NO side-effect representation: the disposition contract's R-WORK requires NAMING open
# work and the Follow-On Gate (F1-F4) requires JUDGING it, but no step of either requires a WRITE.
# Naming in prose costs zero and satisfies the contract; prose is write-only (nothing ever drains a
# paragraph — cc-discover greps artifacts, not transcripts); identification and close are different
# turns, so by close the ledger is honestly clean and session-continue never arms (its sentinel is
# downstream of exactly the self-judgment that failed). Live instance: "cc-inbox-guard deserves its
# own scoped pass" — written, F1-F4 satisfied, never fired, until the operator re-asked.
#
# THE FIX: give named-but-undispatched work the same shape as an unlanded commit — a disk fact a
# hook can read. The durable representation ALREADY EXISTS (cc-backlog: open items auto-drain via
# cc-dispatch; cc-decide: decision packets; cc-registry: a fired pane's row). Only the WRITE is
# optional. This hook makes it unavoidable at the identification turn itself: every turn ends with
# a Stop; if THIS turn's text names follow-on work and NO durable record was written since the turn
# began, the close is blocked ONCE with the exact enqueue commands. The only way to discharge is to
# actually write one of the records — gaming the hook IS compliance (completion-assert's property).
#
# ── FIRE PREDICATE ──
#   naming-tell ∧ no-queue-write ∧ ¬kill-switch
#     naming-tell    := follow-on-naming idiom in THIS TURN's main-agent texts (all assistant text
#                       since the last genuine user message — catches mid-grind identification)
#     no-queue-write := zero records since turn-start in ALL of: backlog.jsonl events (any verb —
#                       `block --needs` is a legitimate park), cc-registry rows (a real fire),
#                       cc-decide packets (work reclassified as a decision)
#   The discharge is MECHANICAL (a record with ts/mtime ≥ turn-start appears) — this hook never
#   scope-judges; the model chooses WHICH record fits (dispatch / queue / park-blocked / decide).
#
# ── OBLIGATION STATE (why not a message-hash latch) ── a decision:block reason re-enters the
#   transcript as a user message, resetting the "this turn" window — a hash latch would go blind
#   after its own block. Instead the FIRST fire persists the obligation ($SKEY.pending: turn-start
#   + count); later Stops re-check discharge against the STORED turn-start until discharged or
#   capped (DISPATCH_ASSERT_MAX, default 2 — a false match costs at most 2 blocked stops).
#
# ── SAFETY (house pattern: completion-assert.sh:22-26) ── F fail-safe: block ONLY via
#   {decision:"block"}; EVERY path exits 0; any read/jq failure → abstain; no `set -e` (a Stop hook
#   exiting 2 false-blocks). Kill-switch: operator stop-phrases (session-continue (a) list) AND
#   DISPATCH_ASSERT_DISABLE=1 abstain + clear. Session total cap (MAX_TOTAL, default 6). B-3 one
#   IDL {fired|abstained:<reason>} line per invocation.
#
# Env seams (tests): DISPATCH_ASSERT_STATE_DIR · DISPATCH_ASSERT_IDL · DISPATCH_ASSERT_MAX ·
#   DISPATCH_ASSERT_MAX_TOTAL · DISPATCH_ASSERT_DISABLE · CC_BACKLOG_FILE · CC_REGISTRY_DIR ·
#   CC_DECISIONS_DIR
set -uo pipefail

STATE_DIR="${DISPATCH_ASSERT_STATE_DIR:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/state/dispatch-assert}"
IDL="${DISPATCH_ASSERT_IDL:-$HOME/.claude/autonomy/idl.jsonl}"
MAX="${DISPATCH_ASSERT_MAX:-2}"
MAX_TOTAL="${DISPATCH_ASSERT_MAX_TOTAL:-6}"
BLG_FILE="${CC_BACKLOG_FILE:-$HOME/.claude/autonomy/backlog.jsonl}"
REG_DIR="${CC_REGISTRY_DIR:-$HOME/.claude/cc-registry}"
DEC_DIR="${CC_DECISIONS_DIR:-$HOME/.claude/autonomy/decisions}"
CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SID="?"

input="$(cat 2>/dev/null || printf '{}')"

log_idl() { # $1=disposition $2=reason $3=extra JSON OBJECT (optional, jq-built; default {})
  mkdir -p "$(dirname "$IDL")" 2>/dev/null || true
  local ts extra; ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo '?')"
  extra="${3:-}"; [ -n "$extra" ] || extra='{}'
  # jq-encode EVERY field (house rule): one malformed line aborts the cc-audit jq -rs slurp.
  jq -cn --arg ts "$ts" --arg sid "$SID" --arg disp "$1" --arg reason "$2" --argjson extra "$extra" \
    '{ts:$ts,hook:"dispatch-assert",sid:$sid,disposition:$disp,reason:$reason} + $extra' \
    >> "$IDL" 2>/dev/null || true
}
abstain() { log_idl abstained "$1"; exit 0; }

[ "${DISPATCH_ASSERT_DISABLE:-0}" = "1" ] && abstain "disabled"
command -v jq >/dev/null 2>&1 || abstain "no-jq"

SID="$(printf '%s' "$input" | jq -r '.session_id // "?"' 2>/dev/null || echo '?')"
TP="$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null || true)"
CWD="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null || true)"

[ -n "$TP" ] || abstain "no-transcript-path"
case "$TP" in "~"*) TP="$HOME${TP#\~}" ;; esac
[ -f "$TP" ] || abstain "transcript-missing"

# iso_cut <iso> → seconds-precision prefix (19 chars) for cross-format lexicographic compare
# (transcripts stamp millis, ledgers stamp whole seconds — the shared prefix orders correctly).
iso_cut() { printf '%s' "$1" | cut -c1-19; }
# iso_epoch <iso-seconds-prefix> → epoch (BSD then GNU), "" on failure.
iso_epoch() {
  date -j -u -f %Y-%m-%dT%H:%M:%S "$1" +%s 2>/dev/null \
    || date -u -d "${1}Z" +%s 2>/dev/null || true
}

# ── Turn window: ts of the last GENUINE user message (string content, or array carrying a text
#    item — tool_result-only records are not the user speaking). Main agent only. ──
T_TURN="$(jq -r 'select(.type=="user" and (.isSidechain != true))
                 | select(((.message.content|type)=="string")
                          or ([.message.content[]?|select(.type=="text")]|length > 0))
                 | .timestamp // empty' "$TP" 2>/dev/null | tail -1 || true)"
[ -n "$T_TURN" ] || abstain "no-user-turn"

# ── The last genuine user message TEXT (kill-switch source; session-continue (a) list). ──
LAST_USER="$(jq -r 'select(.type=="user" and (.isSidechain != true))
                    | .message.content
                    | if type=="string" then .
                      elif type=="array" then ([.[]?|select(.type=="text")|.text]|join("\n"))
                      else empty end
                    | select(. != "")' "$TP" 2>/dev/null | tail -1 || true)"
kill_switch() {
  [ -n "$LAST_USER" ] || return 1
  printf '%s' "$LAST_USER" | grep -iqE \
    '(^|[^[:alnum:]])and( then)? stop([^[:alnum:]]|$)|no[ _-]?auto[ _-]?continue|(^|[^[:alnum:]])just do [^[:space:]]|(^|[^[:alnum:]])stop here([^[:alnum:]]|$)|come back to this|^[[:space:]]*(stop|halt)[[:space:].!]*$'
}

mkdir -p "$STATE_DIR" 2>/dev/null || true
find "$STATE_DIR" \( -name '*.pending' -o -name '*.fired' \) -mtime +7 -delete 2>/dev/null || true
SKEY="$(printf '%s|%s|%s' "$CFG" "$SID" "$CWD" | shasum 2>/dev/null | cut -c1-16)"
[ -n "$SKEY" ] || abstain "no-skey"
PENDING="$STATE_DIR/$SKEY.pending"
FIREDLOG="$STATE_DIR/$SKEY.fired"

# ── discharged_since <iso-seconds-prefix> → 0 when ANY durable record exists at/after it. ──
discharged_since() {
  local since="$1" since_ep f m
  # (1) backlog event — any verb; the ledger was engaged. EXCEPT a worker's own claim re-key
  # (`reclaim:true`, cc-backlog reclaim): that record is written by a SessionStart hook, not by the
  # model deciding anything, so it is not evidence that identified work was enqueued. A /compact or
  # resume mid-turn re-fires SessionStart, and counting its re-key would discharge this obligation
  # with a record the model never authored — the one way to satisfy the guard without doing the thing.
  if [ -f "$BLG_FILE" ]; then
    jq -e --arg t "$since" 'select(((.ts // "")[0:19]) >= $t and (.reclaim // false) != true)' \
      "$BLG_FILE" >/dev/null 2>&1 && return 0
  fi
  # (2) cc-registry row — a pane was actually fired (mtime ≥ turn-start).
  since_ep="$(iso_epoch "$since")"
  if [ -n "$since_ep" ] && [ -d "$REG_DIR" ]; then
    for f in "$REG_DIR"/*.json; do
      [ -e "$f" ] || continue
      m="$(stat -f %m "$f" 2>/dev/null || stat -c %Y "$f" 2>/dev/null || echo 0)"
      case "$m" in ''|*[!0-9]*) m=0 ;; esac
      [ "$m" -ge "$since_ep" ] && return 0
    done
  fi
  # (3) cc-decide packet — the work was reclassified as a decision.
  if [ -d "$DEC_DIR" ]; then
    for f in "$DEC_DIR"/*.json; do
      [ -e "$f" ] || continue
      jq -e --arg t "$since" '((.created // "")[0:19]) >= $t' "$f" >/dev/null 2>&1 && return 0
    done
  fi
  return 1
}

# ── Pending obligation from a PRIOR fire: re-check against the STORED turn-start. ──
if [ -f "$PENDING" ]; then
  read -r p_since p_count < "$PENDING" 2>/dev/null || { p_since=""; p_count=0; }
  case "$p_count" in ''|*[!0-9]*) p_count=0 ;; esac
  if kill_switch; then rm -f "$PENDING" 2>/dev/null; abstain "kill-switch"; fi
  if [ -z "$p_since" ]; then rm -f "$PENDING" 2>/dev/null; abstain "pending-corrupt"; fi
  if discharged_since "$p_since"; then rm -f "$PENDING" 2>/dev/null; abstain "discharged"; fi
  if [ "$p_count" -ge "$MAX" ]; then rm -f "$PENDING" 2>/dev/null; abstain "capped:${p_count}>=${MAX}"; fi
  p_count=$((p_count + 1))
  printf '%s %s\n' "$p_since" "$p_count" > "$PENDING" 2>/dev/null || true
  log_idl fired "undischarged-obligation" \
    "$(jq -cn --arg since "$p_since" --argjson count "$p_count" --argjson max "$MAX" \
        '{since:$since,count:$count,max:$max}' 2>/dev/null || echo '{}')"
  reason="Dispatch-assert (re-check ${p_count}/${MAX}): the follow-on work this session named is STILL not durable — no backlog event, no fired-pane registry row, no decision packet since it was named. Prose is write-only; nothing drains a paragraph. Write ONE record now: \`cc-backlog add --title \"<one-line>\" --project \"<project-basename>\" --source \"$SID\"\` (auto-drains via cc-dispatch) — or fire it, or \`cc-backlog block <id> --needs \"<operator step>\"\` after adding, or \`cc-decide open --class C --what \"…\"\` if it is a decision. If nothing was actually named (false match), close again — this check stops at the cap."
  jq -nc --arg r "$reason" '{decision:"block",reason:$r}'
  exit 0
fi

# ── Fresh scan: THIS turn's main-agent texts (all assistant text at/after the turn start). ──
T19="$(iso_cut "$T_TURN")"
TURN_TEXT="$(jq -r --arg t "$T19" \
  'select(.type=="assistant" and (.isSidechain != true) and (((.timestamp // "")[0:19]) >= $t))
   | [.message.content[]? | select(.type=="text") | .text] | join("\n")
   | select(. != "")' "$TP" 2>/dev/null || true)"
[ -n "$TURN_TEXT" ] || abstain "no-assistant-text"

# Follow-on-naming idioms. Broad by design (completion-assert doctrine: broad matcher, fact gate) —
# but each alternative is a WORK-NAMING shape, not a generic close: naming a pass/session/task that
# this turn is NOT doing. ERE only (no lookaheads — an invalid ERE fails a guard OPEN, memory
# grep-lookahead-fails-open).
NAME_TELL='deserves (its|a) own|(its|their) own (scoped |dedicated |separate )?(pass|session|track|task)|worth (a |an |its own )?(separate|scoped|dedicated|follow-?up|deeper|future) (pass|session|task|track|look|investigation)|(should|could|would|can|will) be (a |its own |another )?(separate|follow-?up|future|later) (task|pass|session|track|item|effort|piece)|for (a |the )?(later|future|another|separate|next) (pass|session|turn|track|sweep)|add (it|this|that) to the backlog|should be (backlogged|queued|enqueued|dispatched|fired)|(park|punt|defer)(ing|red|ed)? (this|that|it) (for|until|to)|follow-?(up|on) (work|item|task|candidate)|left? (this|that|it) for (a )?(future|later|another)|(fire|dispatch|spawn|hand) (it|this|that|one) off (later|separately|as)'
printf '%s' "$TURN_TEXT" | grep -iqE "$NAME_TELL" || abstain "no-naming-tell"

kill_switch && abstain "kill-switch"
discharged_since "$T19" && abstain "already-recorded"

# Session total cap — bounds worst-case interactive annoyance across many naming turns.
NTOT="$(grep -c . "$FIREDLOG" 2>/dev/null || echo 0)"; case "$NTOT" in ''|*[!0-9]*) NTOT=0 ;; esac
[ "$NTOT" -ge "$MAX_TOTAL" ] && abstain "total-capped:${NTOT}>=${MAX_TOTAL}"

# ── FIRE: persist the obligation, log, block with the exact enqueue commands. ──
printf '%s 1\n' "$T19" > "$PENDING" 2>/dev/null || true
printf '%s\n' "$T19" >> "$FIREDLOG" 2>/dev/null || true
log_idl fired "narrated-not-dispatched" \
  "$(jq -cn --arg since "$T19" --argjson total "$((NTOT+1))" '{since:$since,session_fires:$total}' \
      2>/dev/null || echo '{}')"

reason="Dispatch-assert: this turn NAMES follow-on work, but no durable record of it exists — no backlog event, no fired pane, no decision packet since the turn began. A paragraph is not a queue: nothing drains prose (operator crux 2026-07-25 — the cc-inbox-guard pass sat narrated, undispatched, until the operator re-asked). Before closing, make it durable — ONE of: (a) dispatchable now → fire it; (b) queue it → \`cc-backlog add --title \"<one-line>\" --project \"<project-basename>\" --dod-ref \"<doc#anchor>\" --source \"$SID\"\` (cc-dispatch auto-drains open items); (c) operator-gated → add, then \`cc-backlog block <id> --needs \"<exact operator step>\"\`; (d) a decision, not work → \`cc-decide open --class C --what \"…\"\`. Then close normally. False match (nothing actually named)? Close again — this check re-fires at most $((MAX-1)) more time(s). (dispatch-assert 1/${MAX})"

jq -nc --arg r "$reason" '{decision:"block",reason:$r}'
exit 0
