#!/bin/bash
# net-recover-arm.sh — D4 of docs/plans/NONLIMIT_RESUME_LADDER.md (T6/W2-C).
#
# WHAT IT REPLACES: the operator noticing the wifi came back. On 2026-09-09 six panes sat blocked on
# a network death and the operator typed the correcting paragraph BY HAND, once per pane, in 93
# seconds. That is a hand-off that makes the human the runtime.
#
# Registered on `SessionStart` AND on `Stop`, both `"asyncRewake": true` (migration 0030). The
# harness backgrounds it, does not block the turn it fires on, does not reap it at that turn's end,
# and — when it exits 2 — synthesizes a turn and wakes the model with this script's STDERR.
#
# ── WHY IT CANNOT BE ARMED AT THE DEATH, WHICH IS THE WHOLE REASON IT IS ARMED HERE ──────────────
# Measured on-box 2026-09-17, CC 2.1.114, four arms with two controls
# (docs/research/api-error-rewake-proof-2026-09.md § Arm 2): **a turn that ends with an API error
# runs NO Stop hook at all** — not even a plain synchronous one — while the identical invocation
# against a healthy endpoint fires every hook in the chain. So nothing can be armed AT the death and
# a design that tried would be a permanent no-op.
#
# The companion measurement is why this file exists rather than being abandoned (§ Arm 1): a watcher
# armed BEFORE the death — at SessionStart — **does** get its `exit 2` honoured afterwards. Control
# (normal turn end) and two independent api-error runs all synthesize the same second turn. That pair
# is the entire design: arm early, survive the death, wake after it.
#
# ── WHY THE STOP RE-ARM NEEDS A GUARD ───────────────────────────────────────────────────────────
# SessionStart arms once, and this watcher is self-disarming (it exits on the first wake or at term),
# so a long-lived session would be deaf from the moment its birth watcher is spent. Stop is the only
# boundary that recurs. But the harness dedupes NOTHING — measured in the P-W2d probe as two `exit
# 2`s on one event and two synthesized turns — so the idempotence has to live HERE, not in the
# registration. Same conclusion, same shape, as hooks/mailbox-wake-arm.sh's claim guard.
#
# ── KILL SWITCH ─────────────────────────────────────────────────────────────────────────────────
#   CC_NET_RECOVER_ARM=0  → a total no-op (exit 0 immediately, no watcher, no wake).
# Anything registered on every session birth needs one.
set -uo pipefail

[ "${CC_NET_RECOVER_ARM:-1}" != 0 ] || exit 0

# stdin fully consumed on EVERY path so the harness never SIGPIPEs us (this file's SIGPIPE discipline,
# inherited from mailbox-wake-arm.sh).
_stdin="$(cat 2>/dev/null || true)"

# ── HEADLESS ONE-SHOT GUARD ─────────────────────────────────────────────────────────────────────
# asyncRewake is honoured only when the session is interactive or has streaming input; in a plain
# one-shot `claude -p` the hook is dispatched SYNCHRONOUSLY and this watch would BLOCK SESSION BIRTH
# for every headless probe and daemon on the box. A one-shot needs no idle wake anyway.
#
# FAIL DIRECTION — cannot resolve an ancestor ⇒ SKIP. Under-arming is recoverable; a wrongly-armed
# SYNC watch wedges a session birth for hours.
#
# ⚠️ THIS IS THE SECOND COPY OF THIS GUARD. The first is hooks/mailbox-wake-arm.sh's, and it is the
# original. It is duplicated rather than factored DELIBERATELY: mailbox-wake-arm.sh is the fleet-wide
# wake path, a change there that lands wrong makes every running session deaf, and that is not a risk
# to take in the same diff that introduces a new hook. Factoring both into hooks/lib/ is a real
# refactor and belongs in its own change with its own gate — when it happens, it must sweep BOTH
# copies (this repo's own rule: a generator fix needs its population enumerated).
if [ "${CC_NET_RECOVER_HARNESS_ARGV+x}" = x ]; then
  _harness="$CC_NET_RECOVER_HARNESS_ARGV"
else
  _harness=""
  _anc="$PPID"; _hops=0
  while [ -n "$_anc" ] && [ "$_anc" != 1 ] && [ "$_hops" -lt 6 ]; do
    _cmdline="$(ps -o command= -p "$_anc" 2>/dev/null || true)"
    case "$_cmdline" in
      *claude*|*node*) _harness="$_cmdline"; break ;;
    esac
    _anc="$(ps -o ppid= -p "$_anc" 2>/dev/null | tr -d ' ')"
    _hops=$((_hops + 1))
  done
fi
[ -n "$_harness" ] || exit 0                       # unresolvable ⇒ skip, never arm
case "$_harness" in
  *--input-format*stream-json*) ;;                 # streaming input ⇒ asyncRewake is honoured
  *' -p '*|*' --print '*|*' -p') exit 0 ;;         # plain one-shot ⇒ dispatched SYNC; do not arm
esac

# ── identity + the transcript this watcher watches ──────────────────────────────────────────────
# Both come from the harness payload, never from the environment: a session whose process exited and
# RESUMED comes back with $ITERM_SESSION_ID unset, and any design deriving identity from the
# environment inherits that silence (MEMORY.md transplanted-session-loses-dispatch-identity).
_jqget() { # <jq path> → value or empty
  command -v jq >/dev/null 2>&1 || return 1
  printf '%s' "$_stdin" | jq -r "$1 // empty" 2>/dev/null
}
_sid="$(_jqget '.session_id')"
_tp="$(_jqget '.transcript_path')"
[ -n "$_tp" ] && [ -f "$_tp" ] || exit 0           # no transcript to watch ⇒ silent no-op
_sid="${_sid:-$(basename "$_tp" .jsonl)}"

# ── CLAIM GUARD — a no-op whenever a LIVE watcher already covers this session ───────────────────
# `mkdir` is the atomic test-and-set. The pid inside is what makes the latch self-healing: a watcher
# killed with its session leaves the dir behind, and a successor must not be locked out by a
# tombstone. FAIL DIRECTION — cannot tell ⇒ ARM, the same dup-biased choice mailbox-wake-arm makes
# (a visible duplicate reminder beats silent deafness).
_state="${CC_NET_RECOVER_STATE_DIR:-${TMPDIR:-/tmp}/cc-net-recover}"
mkdir -p "$_state" 2>/dev/null || exit 0
_claim="$_state/$_sid.claim"
if mkdir "$_claim" 2>/dev/null; then
  printf '%s' "$$" > "$_claim/pid" 2>/dev/null
else
  _old="$(cat "$_claim/pid" 2>/dev/null || true)"
  case "$_old" in
    ''|*[!0-9]*) rmdir "$_claim" 2>/dev/null; mkdir "$_claim" 2>/dev/null || exit 0
                 printf '%s' "$$" > "$_claim/pid" 2>/dev/null ;;
    *) if kill -0 "$_old" 2>/dev/null; then exit 0; fi   # a live watcher already covers this session
       printf '%s' "$$" > "$_claim/pid" 2>/dev/null ;;   # tombstone ⇒ adopt it
  esac
fi
# shellcheck disable=SC2064  # $_claim is expanded NOW on purpose: the trap must name this claim
trap "rm -rf '$_claim' 2>/dev/null" EXIT INT TERM

# ── the lib + the probe ─────────────────────────────────────────────────────────────────────────
# Repo-relative FIRST: a brand-new tracked file is not symlinked into the live ~/.claude layer until
# install.sh runs, so a live-layer-first order would ship pointing at a path that does not execute
# yet — which reads GREEN and does nothing.
# Both resolvers take a VALUE seam with ${VAR+set}, so a set-but-EMPTY value is honoured verbatim and
# a test can exercise the "cannot resolve" branch without moving files around. A seam that cannot
# turn a thing OFF is not a seam (the cc-await-ping IT2_BIN pattern).
if [ "${CC_NET_RECOVER_LIB+x}" = x ]; then
  _lib="$CC_NET_RECOVER_LIB"
else
_lib=""
for _c in "$(dirname "$0")/../scripts/limit-recover/lr-lib.sh" \
          "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/scripts/limit-recover/lr-lib.sh" \
          "$HOME/.claude/scripts/limit-recover/lr-lib.sh"; do
  [ -f "$_c" ] && { _lib="$_c"; break; }
done
fi
[ -n "$_lib" ] && [ -f "$_lib" ] || exit 0
# shellcheck source=../scripts/limit-recover/lr-lib.sh
# shellcheck disable=SC1090,SC1091
. "$_lib" 2>/dev/null || exit 0
command -v lr_last_api_error >/dev/null 2>&1 || exit 0   # lib too old ⇒ silent, never a false wake

if [ "${CC_NET_RECOVER_PROBE+x}" = x ]; then
  _probe="$CC_NET_RECOVER_PROBE"
else
_probe=""
for _c in "$(dirname "$0")/../scripts/limit-recover/lr-probe.sh" \
          "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/scripts/limit-recover/lr-probe.sh" \
          "$HOME/.claude/scripts/limit-recover/lr-probe.sh"; do
  [ -x "$_c" ] && { _probe="$_c"; break; }
done
fi
[ -n "$_probe" ] && [ -x "$_probe" ] || exit 0

# ── the turn-end gate, and why it FAILS OPEN ────────────────────────────────────────────────────
# § W1.2 gates the wake on `[api-error ∧ turn_duration ∧ 2 greens]`: a synthesized prompt landing in
# a LIVE turn is queued rather than lost, but it must not fire the audit before the retry ladder has
# resolved, and `system`/`turn_duration` is the structural, spelling-free turn-END marker
# (lr-audit.py:122-128).
#
# 🚨 MEASURED 2026-09-17: `turn_duration` is absent from BOTH probe arms INCLUDING THE CONTROL, so in
# some shapes it is never emitted at all — it is a property of the SHAPE, not of how the turn ended.
# A gate written as "wait for a turn_duration after the api error" is therefore UNREACHABLE BY
# CONSTRUCTION in any transcript that emits none, and an unreachable gate is a hook that reads as
# registered and never fires: the exact trap this plan exists to close.
#
# So: if the transcript carries turn_duration records AT ALL, require one at or after the api-error
# record (the strict reading, which is what a real interactive transcript gets — Finding 2 measured
# 24 of them in 52e35019). If it carries none, this discriminator does not exist here and the gate
# degrades to `lr_last_api_error`'s own test, which already answers "the last assistant record is an
# api error". Absence of a discriminator is a fact about the instrument, never a verdict about the
# subject.
_turn_ended_after() { # $1=transcript $2=api-error ISO timestamp → 0 = ended (or undecidable), 1 = still in flight
  tail -c "${LR_TAIL_BYTES:-131072}" "$1" 2>/dev/null | /usr/bin/python3 -c '
import json, sys
ts = sys.argv[1]
seen = False
for line in sys.stdin:
    if "turn_duration" not in line: continue
    try: d = json.loads(line)
    except Exception: continue          # a tail starts mid-record; a partial line is not a verdict
    if d.get("subtype") != "turn_duration": continue
    seen = True
    if (d.get("timestamp") or "") >= ts:
        sys.exit(0)                     # a turn ENDED at or after the error ⇒ the ladder resolved
sys.exit(1 if seen else 0)              # none at all ⇒ FAIL OPEN; some but all older ⇒ in flight
' "$2"
}

# ── bounds ──────────────────────────────────────────────────────────────────────────────────────
# Strictly UNDER the registered hook timeout, so whichever limit binds we leave through our own clean
# path rather than being reaped mid-watch. Degrade quietly; never wake to say nothing happened.
_to="${CC_NET_RECOVER_TIMEOUT:-14340}"     # 3h59m — the migration registers timeout 14400
case "$_to" in ''|*[!0-9]*) _to=14340 ;; esac
_iv="${CC_NET_RECOVER_INTERVAL:-20}"
case "$_iv" in ''|*[!0-9]*) _iv=20 ;; esac

# ── the watch ───────────────────────────────────────────────────────────────────────────────────
_deadline=$(( $(date +%s) + _to ))
while [ "$(date +%s)" -lt "$_deadline" ]; do
  if _rec="$(lr_last_api_error "$_tp" 2>/dev/null)"; then
    _uuid="${_rec%%	*}"
    _rest="${_rec#*	}"; _err="${_rest%%	*}"
    _ts="${_rec##*	}"
    # NEVER TWICE ON ONE uuid. The latch is per death record, not per session: latching the session
    # would go silent on every later death, and latching nothing would re-wake on every poll for as
    # long as the record is the tail (memory: alarm-polarity-and-attention-budget).
    if [ ! -e "$_state/$_sid.woke.$_uuid" ]; then
      if _turn_ended_after "$_tp" "$_ts"; then
        # The CONTROL, and it is necessary rather than decorative: the stall's own text can never say
        # whether it will clear, so only a request-independent reachability check can. Two greens,
        # spaced, unauthenticated — it spends no quota and cannot touch a rate-limit window.
        if "$_probe" >/dev/null 2>&1; then
          : > "$_state/$_sid.woke.$_uuid" 2>/dev/null
          # STDERR ONLY. The harness drops an asyncRewake hook's stdout and carries only stderr into
          # the synthesized turn (measured — the STDOUT variant appears 0 times in the W0 proof).
          printf '%s\n' \
            "🔌 The API path is reachable again, and this session's last turn died on it (${_err}, ${_ts})." \
            "Your context still holds the PRE-DEATH narrative: it reads plausible, and it is the thing" \
            "most likely to make you satisfice on the units you happen to remember. Do NOT reconcile" \
            "from it. Audit DISK first, then reconcile:" \
            "" \
            "    /recover        (or /limit-recover until \`recover\` is live in this config dir)" \
            "" \
            "Every delegated unit that is not provably COMPLETE on disk is re-run — accepting partial" \
            "results is banned. This notice fires ONCE per death record." >&2
          exit 2                               # ← THE WAKE. The one exit code the harness acts on.
        fi
      fi
    fi
  fi
  sleep "$_iv"
done
exit 0                                          # term reached, nothing to say: never a spurious wake
