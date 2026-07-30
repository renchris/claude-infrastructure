#!/usr/bin/env bash
# session-continue.sh — 🔧 loose-ends continuation loop (agent-set sentinel + Stop-hook actuator).
#
# WHY: a Stop hook fired on its own is SCOPE-BLIND — a shell script can't tell an
# in-scope loose end from an intentional pause or out-of-scope dirt, so a standalone
# one loops on the wrong things (that's why the Session Close Protocol banned it).
# This design keeps scope-judgment with the AGENT: the agent (which classifies each
# close as 🔧 / ✅ / 📦 / ⛔ / 📤) ARMS a sentinel ONLY on 🔧, and this script is a
# dumb actuator — it just blocks the stop and feeds the next step back, with a hard
# loop cap so a stuck gate can never run away.
#
# Agent interface (run from the session's worktree):
#   session-continue.sh set "<the ONE next step>"   # arm — ONLY on the 🔧 state
#   session-continue.sh clear                        # disarm — on ✅/📦/⛔/📤, read-only, or "...and stop"
#   session-continue.sh status                       # inspect
#
# Claude Code calls it with NO args + the Stop JSON on stdin → actuation mode.
#
# Sentinel lives OUTSIDE any repo (per-account state dir: ${CLAUDE_CONFIG_DIR:-~/.claude}/state),
# keyed by config-dir + cwd hash, so it never gets committed and concurrent sessions —
# including different accounts (each with its own CLAUDE_CONFIG_DIR) — don't collide.
#
# HARDENING (a19 D-7/D-8, a17 S-12) beyond the base actuator:
#   (a) KILL-SWITCH — actuation reads the transcript's last genuine user message; an operator
#       "…and stop" / "no auto-continue" / "just do X" / explicit-pause phrase clears the sentinel
#       and allows the stop. Operator stop ALWAYS wins over a stale sentinel (was D-8: the actuator
#       parsed no phrase, so a stale sentinel forced work when told to stop).
#   (b) SID-BIND — `set` records the arming session's id in a `.sid` sidecar; actuation clears AND
#       ignores a sentinel whose sid ≠ the actuating session's (kills S-12 cross-succession
#       inheritance: a recycled successor in the same cwd inheriting the predecessor's sentinel).
#   (c) CAP RE-ARM — a fresh `set` resets `.count`; the block reason instructs re-`set` each 🔧 turn
#       (that reset is how a faithful long grind avoids the cap — D-7). At the cap the hook does NOT
#       give up silently: it emits a final systemMessage naming the re-arm lever, then allows the stop.
#
# NOTE: deliberately NO `set -e` — a Stop hook that exits 2 *blocks the stop*, so an
# accidental non-zero exit could force a false continuation. Every actuation path ends `exit 0`.

# ── Shared sentinel-path SSOT (G-P6-6b / a19 I-1) ─────────────────────────────────
# The sentinel PATH formula lives in hooks/lib/continue-sentinel.sh so boundary-handoff's
# compose-guard computes the IDENTICAL path (it used to hardcode a path this hook never writes →
# a dead no-op guard). Resolve the lib next to this script (works for the repo AND a symlinked
# ~/.claude/hooks/ install), then fall back to the config-dir / ~/.claude hooks/lib.

# ── B-3 telemetry — one IDL record + one log line per DECISION (audit 09 D-11) ────────────────
# This is the hook that drives the loop: it emits {decision:"block"} up to CLAUDE_CONTINUE_MAX
# times per chain, and it was the ONLY Stop hook writing nothing at all (completion-assert,
# boundary-handoff and anti-deference-nudge all write IDL), so a runaway continuation or a wrongly
# SUPPRESSED one was forensically invisible. Record shape + jq-encoding of every field mirrors
# hooks/completion-assert.sh:39-49 — a step string carrying a quote/newline must never emit a
# malformed IDL line, because one malformed line aborts cc-audit's `jq -rs` slurp and that reads
# as "no records" (silently flipping the un-gameable detector green).
#
# Deliberately NOT logged: the disarmed steady state (actuation with no sentinel). That is the
# common case on EVERY Stop of EVERY session, and the sentinel's absence is itself the record —
# logging it would add a line per turn-close to an already-18 MB IDL while telling us nothing the
# D-11 forensics need. Every state CHANGE is logged: armed · cleared (cli / kill-switch /
# sid-mismatch / cap) · fired.
IDL="${CONTINUE_IDL:-$HOME/.claude/autonomy/idl.jsonl}"
CLOG="${CONTINUE_LOG:-$HOME/.claude/logs/session-continue.log}"
SC_SID="?"
log_idl() { # $1=disposition $2=reason $3=extra JSON OBJECT (optional, jq-built {…}; default {})
  local ts extra
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo '?')"
  extra="${3:-}"; [ -n "$extra" ] || extra='{}'
  mkdir -p "${IDL%/*}" "${CLOG%/*}" 2>/dev/null || true
  printf '[%s] %s sid=%s reason=%s\n' "$ts" "$1" "$SC_SID" "$2" >> "$CLOG" 2>/dev/null || true
  command -v jq >/dev/null 2>&1 || return 0
  jq -cn --arg ts "$ts" --arg sid "$SC_SID" --arg disp "$1" --arg reason "$2" --argjson extra "$extra" \
    '{ts:$ts,hook:"session-continue",sid:$sid,disposition:$disp,reason:$reason} + $extra' \
    >> "$IDL" 2>/dev/null || true
}

_scd="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
_lib="$_scd/lib/continue-sentinel.sh"
[ -f "$_lib" ] || _lib="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/hooks/lib/continue-sentinel.sh"
[ -f "$_lib" ] || _lib="$HOME/.claude/hooks/lib/continue-sentinel.sh"
# shellcheck source=lib/continue-sentinel.sh
# shellcheck disable=SC1091  # source path resolved at runtime (fallback chain); static-follow needs -x, the
# ship-land gate runs shellcheck without it → SC1091(info) would red a change to this file (matches boundary-handoff.sh)
if ! . "$_lib" 2>/dev/null; then
  # Fail LOUD but SAFE: a missing path-SSOT is a misconfig, not a runtime state. A Stop hook must
  # never block on error (→ exit 0 allow); a CLI mode signals the failure to the agent (→ exit 2).
  printf 'session-continue: FATAL — cannot source %s (continuation loop inert).\n' "$_lib" >&2
  log_idl abstained "no-sentinel-lib"
  case "${1:-}" in set|clear|status) exit 2 ;; *) exit 0 ;; esac
fi
mkdir -p "$(continue_state_dir)" 2>/dev/null

# thin local alias → the shared SSOT (keeps the body below unchanged)
sentinel_for() { continue_sentinel_for "$1"; }

# ---- Agent CLI mode -------------------------------------------------------------
case "${1:-}" in
  set)
    f=$(sentinel_for "$PWD")
    printf '%s' "${2:-Continue the in-scope work.}" > "$f"
    rm -f "${f}.count" 2>/dev/null   # fresh chain → reset the loop counter (D-7 re-arm lever)
    # (b) sid-bind: stamp the arming session so a same-cwd successor can't inherit this sentinel.
    # Empty sid ⇒ write no bind (actuation then skips the sid check — conservative, never a wrong clear).
    csid="${CLAUDE_CODE_SESSION_ID:-${CLAUDE_SESSION_ID:-}}"
    if [ -n "$csid" ]; then printf '%s' "$csid" > "${f}.sid"; else rm -f "${f}.sid" 2>/dev/null; fi
    echo "armed → $f"
    SC_SID="${csid:-?}"
    log_idl armed "cli-set" "$(jq -cn --arg s "${2:-Continue the in-scope work.}" --arg c "$PWD" \
      '{step:$s,cwd:$c}' 2>/dev/null)"
    exit 0 ;;
  clear)
    f=$(sentinel_for "$PWD")
    rm -f "$f" "${f}.count" "${f}.sid" 2>/dev/null
    echo "cleared"
    SC_SID="${CLAUDE_CODE_SESSION_ID:-${CLAUDE_SESSION_ID:-?}}"
    log_idl cleared "cli-clear" "$(jq -cn --arg c "$PWD" '{cwd:$c}' 2>/dev/null)"
    exit 0 ;;
  status)
    f=$(sentinel_for "$PWD")
    if [ -f "$f" ]; then
      echo "ARMED ($(cat "${f}.count" 2>/dev/null || echo 0) continuations, sid=$(cat "${f}.sid" 2>/dev/null || echo '?')): $(cat "$f")"
    else echo "inactive"; fi
    exit 0 ;;
esac

# ---- Stop-hook actuation mode (no recognized arg; JSON on stdin) ----------------
input=$(cat 2>/dev/null || printf '{}')
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
[ -n "$cwd" ] || cwd="$PWD"
f=$(sentinel_for "$cwd")
cur_sid=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)
[ -n "$cur_sid" ] || cur_sid="${CLAUDE_CODE_SESSION_ID:-}"
# SC_SID — the telemetry's sid field. Aliased to $cur_sid rather than re-parsed: the cherry-picked
# commit (cd064644) computed its own SC_SID from the same stdin, but trunk had since hoisted
# $cur_sid for the SID-BIND path. Two independent parses of one value is how they drift.
SC_SID="${cur_sid:-?}"

# ── SHARED kill-switch detection (hoisted for the WAKE FLOOR) ─────────────────────────────────────
# Was inline in the sentinel path only. The wake floor below can also BLOCK a stop, so it must honour
# the same operator override — a floor that blocks after the operator typed "stop" would be the D-8
# bug in a new place. One definition, two callers.
# Kill phrases (resident CLAUDE.md kill-switch + explicit-pause list):
#   …and [then] stop · no auto-continue · just do X · stop here · come back to this · bare stop/halt
KILL_RE='(^|[^[:alnum:]])and( then)? stop([^[:alnum:]]|$)|no[ _-]?auto[ _-]?continue|(^|[^[:alnum:]])just do [^[:space:]]|(^|[^[:alnum:]])stop here([^[:alnum:]]|$)|come back to this|^[[:space:]]*(stop|halt)[[:space:].!]*$'
# Read the LAST genuine user message (string content, or array-of-text; tool_result-only records
# carry no text and are skipped). No transcript path ⇒ can't read ⇒ caller falls through.
last_user_msg() {
  local tp
  tp=$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null)
  case "$tp" in "~"*) tp="$HOME${tp#\~}" ;; esac
  [ -n "$tp" ] && [ -f "$tp" ] || return 1
  jq -r 'select(.type=="user")
         | .message.content
         | if type=="string" then .
           elif type=="array" then ([.[]?|select(.type=="text")|.text]|join("\n"))
           else empty end
         | select(. != "")' "$tp" 2>/dev/null | tail -1
}
# Bias to DETECT: a false positive merely allows one stop the model re-arms on its next 🔧 turn; a
# false negative is the D-8 bug (forcing work when told to stop).
kill_switch_active() {
  local m; m="$(last_user_msg)" || return 1
  [ -n "$m" ] || return 1
  printf '%s' "$m" | grep -iqE "$KILL_RE"
}

# ── v2 comms LAG-ACK (UNCONDITIONAL — must run on EVERY Stop, before the exits below) ────────────────
# A Stop proves a turn ran, so whatever the drain SURFACED last cycle (.seen) is now CONSUMED (.acked).
# Since mailbox-drain acks nothing (ack_now=0), .acked advances ONLY here — and a Stop with NO armed
# continuation is the COMMON case, so gating this on the sentinel (as the mail FOLD below is) would leave
# .acked lagging .seen forever and make cc-inbox-guard false-alarm on already-consumed mail. Promoting is
# safe unconditionally: it only advances .acked→.seen (never past what was emitted), so it can never mark
# undelivered mail consumed. TAKING new mail stays gated in the fold (a take whose body is NOT delivered
# in a decision:block reason would advance .seen and silently DROP the mail). Missing lib ⇒ skip; never block.
_mbxlib="$_scd/lib/mailbox-pending.sh"
[ -f "$_mbxlib" ] || _mbxlib="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/hooks/lib/mailbox-pending.sh"
[ -f "$_mbxlib" ] || _mbxlib="$HOME/.claude/hooks/lib/mailbox-pending.sh"
_ouid="${ITERM_SESSION_ID:-}"; _ouid="${_ouid##*:}"
if [ -f "$_mbxlib" ] && command -v jq >/dev/null 2>&1; then
  # shellcheck source=lib/mailbox-pending.sh
  # shellcheck disable=SC1091
  if . "$_mbxlib" 2>/dev/null; then
    # CANONICALISE the box key before ANY use below (2026-07-29). _ouid above is the PANE uuid, but
    # mailbox-drain.sh reads the SESSION-keyed box whenever it knows its session id (its :64-68,
    # CC_MBX_SESSION_KEY default 1) and writes the pane→session alias on the way. So the two hooks
    # named DIFFERENT keys for one mechanism: the WAKE FLOOR below advertised a PANE-keyed
    # `cc-await-ping` arm while the drain read the SESSION-keyed box. Following that advice arms a
    # watcher on a key nothing writes to, and because each side then checks its OWN key the nudge
    # recurs forever while the operator believes they are armed. (Cost two wrong arms in one session
    # before it was traced.) `bin/cc-await-ping` resolves NO alias — it watches the key it is handed
    # literally — so the resolution has to happen HERE, at the single place _ouid is derived, rather
    # than being fixed up in the watcher or duplicated per call site.
    # mailbox_resolve_key is the lib's one implementation of that mapping; reusing it is what stops
    # the two hooks drifting apart again. It falls back to the pane when no alias exists, so a
    # never-drained pane still resolves to its own box.
    case "$_ouid" in
      ''|*[!0-9A-Fa-f-]*) : ;;
      *) if command -v mailbox_resolve_key >/dev/null 2>&1; then
           _rk="$(mailbox_resolve_key "$_ouid" 2>/dev/null || true)"
           # Adopt ONLY a valid uuid: an empty or malformed resolve must never blank the key, or every
           # guard below would skip and the wake floor would go silently inert — the exact class of
           # failure this hook exists to prevent.
           case "$_rk" in ''|*[!0-9A-Fa-f-]*) : ;; *) _ouid="$_rk" ;; esac
           unset _rk
         fi ;;
    esac
    case "$_ouid" in ''|*[!0-9A-Fa-f-]*) : ;; *) mailbox_promote_acked "$_ouid" ;; esac
  fi
fi

# ── WAKE FLOOR (v3 R1) — a session must not reach IDLE without a wake path ────────────────────────
# THE DEFECT IT CLOSES: the wake mechanism works (proved end-to-end 2026-07-26 on CC 2.1.219 —
# armed watcher → cc-notify write → detected in one poll → exit → harness task-completion
# notification re-invoked the model), but NOTHING actuated it. Every cc-await-ping call site in the
# repo was a doc telling the model to arm, or a lint detecting that it hadn't. Measured result:
# 0 armed watchers across 74 mailboxes holding 1,300 unacked lines. A capability that depends on an
# agent choosing to invoke it before every idle is inert by construction.
#
# WHY HERE and not a new hook: mailbox-drain.sh:8-10 (critique fix B) forbids a COMPETING Stop
# blocker — in-loop mail delivery was deliberately folded into this hook, the ONE that already
# blocks at Stop. The floor folds into the same place for the same reason.
#
# WHY IT MUST RECUR: cc-await-ping deletes its own .watching in its EXIT trap (correctly — a stale
# heartbeat would make cc-notify promise a wake that cannot happen). So a session is deaf again the
# instant it has been woken. Arming once per session is insufficient BY CONSTRUCTION; the floor
# re-checks at every idle transition.
#
# BOUNDED, and it degrades to LOUD rather than looping (the session-continue.sh:33 shape):
#   · only a pane with an inbox identity, only when the lib+jq are present  → else silently allow
#   · only when NOT already armed                                          → armed clears the budget
#   · only on the FIRST idle of this session, or when mail is actually pending
#   · at most CC_WAKE_FLOOR_MAX attempts per session, no sooner than CC_WAKE_FLOOR_TTL_S apart
#   · NEVER after an operator kill-switch phrase (kill_switch_active) — that stop was asked for
#   · budget exhausted ⇒ a human-visible systemMessage naming the lever, then ALLOW the stop
# A repeating Stop hook is not evidence that more work exists, so this one can only ever fire a
# bounded number of times and then get out of the way.
#
# TIMEOUT CHOICE: the suggested arm uses a LONG timeout on purpose. cc-await-ping's timeout exit is
# itself a task completion, so it also wakes the model — a short timeout would churn every idle
# session in the fleet on a fixed period. Long timeout ⇒ a timeout-wake is a rare, self-healing
# re-arm rather than a treadmill.
# Seams (tests): CC_WAKE_FLOOR (0 disables) · CC_WAKE_FLOOR_MAX · CC_WAKE_FLOOR_TTL_S ·
#                CC_WAKE_FLOOR_TIMEOUT_S · CC_MAILBOX_DIR.
wake_floor() { # → echoes JSON on stdout when it wants to BLOCK; otherwise silent. Never fails.
  [ "${CC_WAKE_FLOOR:-1}" = 1 ] || return 0
  command -v jq >/dev/null 2>&1 || return 0
  command -v mailbox_wake_armed >/dev/null 2>&1 || return 0
  case "$_ouid" in ''|*[!0-9A-Fa-f-]*) return 0 ;; esac

  local mbxd sf now cnt ts prev_sid maxa ttl pend armcmd reason warnmsg
  mbxd="${CC_MAILBOX_DIR:-$HOME/.claude/mailbox}"
  sf="$mbxd/$_ouid.wakefloor"

  # Already reachable → clear the budget so a LATER unarmed episode starts fresh (self-healing).
  if mailbox_wake_armed "$_ouid"; then rm -f "$sf" 2>/dev/null; return 0; fi

  now="$(date +%s 2>/dev/null || echo 0)"
  cnt=0; ts=0; prev_sid=""
  if [ -f "$sf" ]; then
    prev_sid="$(sed -n 's/^sid=//p' "$sf" 2>/dev/null | head -n1)"
    cnt="$(sed -n 's/^count=//p' "$sf" 2>/dev/null | head -n1)"
    ts="$(sed -n 's/^ts=//p'    "$sf" 2>/dev/null | head -n1)"
  fi
  case "$cnt" in ''|*[!0-9]*) cnt=0 ;; esac
  case "$ts"  in ''|*[!0-9]*) ts=0  ;; esac
  # A new session in the same pane gets a FRESH budget (the .sid discipline of the sentinel, applied
  # here: a successor must not inherit a predecessor's exhausted attempts).
  [ -n "$prev_sid" ] && [ -n "$cur_sid" ] && [ "$prev_sid" != "$cur_sid" ] && { cnt=0; ts=0; }

  pend="$(mailbox_pending_count "$_ouid" 2>/dev/null || echo 0)"
  case "$pend" in ''|*[!0-9]*) pend=0 ;; esac

  # Fire on the first idle of the session, or any idle where mail is actually waiting. Otherwise a
  # session that already declined once is left alone.
  [ "$cnt" -eq 0 ] || [ "$pend" -gt 0 ] || return 0

  maxa="${CC_WAKE_FLOOR_MAX:-2}"; case "$maxa" in ''|*[!0-9]*) maxa=2 ;; esac
  ttl="${CC_WAKE_FLOOR_TTL_S:-600}"; case "$ttl" in ''|*[!0-9]*) ttl=600 ;; esac
  # Absolute, not "~/…": the model pastes this verbatim, and a tilde inside a quoted string is not a
  # path (SC2088). $HOME also keeps the message truthful under a fixture $HOME in the suites.
  armcmd="$HOME/.claude/bin/cc-await-ping $_ouid --timeout ${CC_WAKE_FLOOR_TIMEOUT_S:-14400} --interval 15"

  # Budget exhausted → do NOT block. Say it where a human can see it, then allow the stop.
  if [ "$cnt" -ge "$maxa" ]; then
    warnmsg="⚠ No inbox wake path armed — peers can write to this session but nothing will wake it. Mail will sit until your next turn. Arm it with: ${armcmd}"
    [ "$pend" -gt 0 ] && warnmsg="⚠ ${pend} message(s) waiting and NO wake path armed — nothing will wake this session. Arm it with: ${armcmd}"
    printf 'session-continue: wake floor exhausted (%s/%s) — allowing stop, unarmed.\n' "$cnt" "$maxa" >&2
    jq -nc --arg m "$warnmsg" '{systemMessage:$m}' 2>/dev/null || true
    return 0
  fi
  # Re-attempt no sooner than the TTL (a burst of short turns must not re-block every one of them).
  [ "$(( now - ts ))" -ge "$ttl" ] 2>/dev/null || return 0
  # The operator asked to stop → never block; the exhausted-branch warning is the right surface.
  if kill_switch_active; then
    jq -nc --arg m "⚠ No inbox wake path armed — this session will not be woken by peer mail. Arm: ${armcmd}" '{systemMessage:$m}' 2>/dev/null || true
    return 0
  fi

  printf 'sid=%s\ncount=%s\nts=%s\n' "$cur_sid" "$(( cnt + 1 ))" "$now" > "$sf" 2>/dev/null || true

  reason="🔔 WAKE FLOOR — you are about to go idle with NO wake path armed, so a peer's message would land in your inbox and sit there unread until someone types at you.

Arm your inbox watcher NOW, then stop. Run it as a Bash tool call with run_in_background=true:

  ${armcmd}

It blocks until a line lands in your inbox, prints it, and exits — and that exit rides the harness's task-completion notification back into you. That IS the wake; it is the only way an external write can reach an idle session.

Re-arm after every wake: the watcher removes its own heartbeat when it exits, so once it has woken you, you are deaf again until you arm a new one."
  [ "$pend" -gt 0 ] && reason="📬 ${pend} message(s) are pending in your inbox RIGHT NOW.

${reason}"
  jq -nc --arg r "$reason" --arg m "🔔 Wake floor: arming this session's inbox watcher (no wake path was armed)." \
    '{decision:"block",reason:$r,systemMessage:$m}'
  return 1
}

# No sentinel → the agent did NOT request continuation → the session is going IDLE. This is the one
# transition the wake floor guards; a sentinel-blocked stop is not idle, so it needs no floor.
if [ ! -f "$f" ]; then
  rm -f "${f}.count" "${f}.sid" 2>/dev/null
  if ! _wf_json="$(wake_floor)"; then
    printf '%s' "$_wf_json"
    exit 0        # decision:block travels in the JSON; the hook itself always exits 0
  fi
  [ -n "${_wf_json:-}" ] && printf '%s' "$_wf_json"
  exit 0
fi

# ── (a) KILL-SWITCH — operator stop ALWAYS wins over a stale sentinel (I-2 / D-8) ──
# A kill phrase ⇒ clear + allow. (Detection is the shared kill_switch_active above, which the wake
# floor also consults so it can never block a stop the operator asked for.)
if kill_switch_active; then
  rm -f "$f" "${f}.count" "${f}.sid" 2>/dev/null
  printf 'session-continue: kill-switch phrase in last user message — cleared sentinel, allowing stop.\n' >&2
  log_idl cleared "kill-switch"
  exit 0
fi
# NOTE ON THIS RESOLUTION (cherry-pick cd064644): the picked commit carried its own INLINE copy of
# the kill-phrase detection here. Trunk had since hoisted that logic into the shared
# kill_switch_active() above — deliberately, so the WAKE FLOOR consults the same predicate and can
# never block a stop the operator asked for. Trunk's structure is kept and only the telemetry line
# (`log_idl cleared "kill-switch"`) is grafted on; re-introducing the inline copy would have
# resurrected a second, drifting definition of the one predicate that must never disagree with
# itself.

# ── (b) SID-BIND — a same-cwd successor must not inherit a predecessor's sentinel (S-12) ──
# Clear + allow when the stored arming-sid differs from the actuating session's sid. Acts ONLY when
# BOTH sids are known (a missing sid = no evidence = never a wrong clear). $cur_sid is computed above.
stored_sid=$(cat "${f}.sid" 2>/dev/null || true)
if [ -n "$stored_sid" ] && [ -n "$cur_sid" ] && [ "$stored_sid" != "$cur_sid" ]; then
  rm -f "$f" "${f}.count" "${f}.sid" 2>/dev/null
  printf 'session-continue: sentinel sid=%s ≠ session sid=%s (inherited across succession) — cleared, allowing stop.\n' "$stored_sid" "$cur_sid" >&2
  log_idl cleared "sid-mismatch" "$(jq -cn --arg a "$stored_sid" --arg b "$cur_sid" \
    '{stored_sid:$a,session_sid:$b}' 2>/dev/null)"
  exit 0
fi

# ── (c) CAP — hard loop cap (guards a stuck gate / non-progressing agent), with a NAMED re-arm ──
MAX="${CLAUDE_CONTINUE_MAX:-8}"
n=$(cat "${f}.count" 2>/dev/null); [ -n "$n" ] || n=0
case "$n" in ''|*[!0-9]*) n=0 ;; esac
if [ "$n" -ge "$MAX" ]; then
  step=$(cat "$f" 2>/dev/null)
  rm -f "$f" "${f}.count" "${f}.sid" 2>/dev/null
  # NOT a silent give-up (D-7): name the re-arm lever, then ALLOW the stop (non-blocking).
  capmsg="session-continue: hit the continuation cap (${MAX}); allowing this stop. If in-scope work genuinely remains, re-arm with \`session-continue.sh set \"<next step>\"\` (a fresh set zeroes .count). Last step was: ${step}"
  printf '%s\n' "$capmsg" >&2
  jq -nc --arg m "$capmsg" '{systemMessage:$m}' 2>/dev/null || true
  log_idl cleared "cap-reached" "$(jq -cn --argjson n "$n" --argjson m "$MAX" --arg s "$step" \
    '{count:$n,max:$m,step:$s}' 2>/dev/null)"
  exit 0   # non-2 exit → does NOT block; the cap is a backstop, not a wedge
fi
n=$((n + 1))
printf '%s' "$n" > "${f}.count"

# ── v2 comms fold (critique B): carry any pending inbox mail in THIS block reason. ───────────────────
# session-continue is the ONE hook already blocking the in-loop desk, so folding delivery here means NO
# competing Stop blocker (no standalone mailbox-drain Stop hook, no 4-hook yield-guards, no wall-clock
# TTL). The lag-ack (promote .acked=.seen) already ran UNCONDITIONALLY above; here we only TAKE this
# cycle's NEW mail with ack_now=0 (the Stop channel is less certain than additionalContext, so the
# cc-inbox-guard's .acked watch is the backstop). The lib is already sourced and $_ouid computed above;
# a take is confined HERE because its body is about to be delivered in the decision:block reason below.
mail=""
if command -v mailbox_take >/dev/null 2>&1; then
  case "$_ouid" in ''|*[!0-9A-Fa-f-]*) : ;; *) mail="$(mailbox_take "$_ouid" 0)" ;; esac
fi

step=$(cat "$f")
reason="🔧 Loose ends remain — do NOT stop yet. Next: ${step}

Re-arm each 🔧 turn: run \`~/.claude/hooks/session-continue.sh set \"<next step>\"\` to refresh the step AND reset the continuation counter (a fresh set zeroes .count — this is how a long grind stays under the ${MAX}-cap). When done (✅/📦), blocked on the user (⛔), or out of context (📤), run \`~/.claude/hooks/session-continue.sh clear\` so the session can close. (continuation ${n}/${MAX})"

# v2 fold: PREPEND pending peer mail (higher priority than self-continuation — a peer is trying to reach
# you). The re-arm reminder stays in $reason below it, so folding never starves the continuation counter (F14).
if [ -n "$mail" ]; then
  _mn="$(printf '%s\n' "$mail" | grep -c '')"
  reason="📬 INBOX — ${_mn} new peer message(s), delivered as CONTEXT (never typed into your input):
${mail}

Triage these first (a reaper/supervisor page, a back-channel ping, a peer) — reply with cc-notify <uuid> \"…\" — THEN continue the loop below.

${reason}"
fi

# decision:block blocks the stop; reason is fed back to the model as the next turn.
jq -nc --arg r "$reason" '{decision:"block",reason:$r}'
log_idl fired "continue" "$(jq -cn --argjson n "$n" --argjson m "$MAX" --arg s "$step" \
  --argjson mail "$([ -n "$mail" ] && printf 'true' || printf 'false')" \
  '{count:$n,max:$m,step:$s,mail_folded:$mail}' 2>/dev/null)"
exit 0
