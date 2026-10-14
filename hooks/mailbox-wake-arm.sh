#!/bin/bash
# mailbox-wake-arm.sh — arm this session's inbox watcher BY CONSTRUCTION, at birth, with no model
# action and no operator action.
#
# Registered on `SessionStart` (migration 0007, W1) AND on `Stop` (migration 0012, W2), both with
# `"asyncRewake": true`. The harness then launches it in the BACKGROUND, does not block the turn it
# fires on, does not reap it at the end of that turn, and — when it exits 2 — synthesizes a turn and
# wakes the model with this script's STDERR.
# Proven live on CC 2.1.219 and re-verified on 2.1.220 (the binary this fleet runs):
# docs/research/mechanical-wake-asyncrewake-2026-07-29.md · docs/plans/CROSS_SESSION_COMMS_V2.md §10.
# The Stop half is proven separately (P-W2a–d): docs/research/w2-stop-rewake-proof/.
#
# ── WHY BOTH EVENTS, AND WHY THE STOP ONE NEEDS A GUARD ──────────────────────────────────────────
# SessionStart arms ONCE. The watcher is self-disarming by design (it exits on the first ping, or at
# term), and SessionStart does not recur mid-session — so a long-lived session is deaf from the
# moment its birth watcher is spent until someone types. Stop is the only boundary that recurs at
# every idle, so re-arming there is what makes the wake path a settings fact rather than something a
# model must remember (goal-safe-2way-comms-2026-08-13.md §5).
#
# But the harness dedupes NOTHING: measured in the P-W2d probe, two Stops in one session launched two
# watchers, both fired on the SAME mail line, and each burned its own model turn. So the recurrence
# has to be idempotent HERE — the claim guard below — not in the registration.
#
# ── WHY THIS FILE EXISTS AT ALL (the spec said "just register cc-await-ping") ────────────────────
# The 2026-07-29 remainder specifies W1 as "a SessionStart hook asyncRewake:true running
# cc-await-ping, with the body moved to stderr". That names the stream problem and misses a fatal
# one: THE TWO CONTRACTS ARE INVERTED.
#
#            mail arrived        watch timed out
#   asyncRewake wakes on   →     exit 2                (nothing)
#   cc-await-ping exits    →     exit 0                exit 2
#
# Registered as specified, the hook would be SILENT on every delivered message and fire a SPURIOUS
# wake on every idle timeout — precisely backwards. And cc-await-ping's rc 2 cannot simply be
# re-mapped at the source: it is load-bearing for cc-wait (:138 branches on it) and is documented as
# "the DESIGNED outcome of a watch that ran its full term". So the translation belongs HERE, in an
# adapter, and this file is the whole of it.
#
# ── IDENTITY: ARM ON WHAT THE HARNESS HANDS US, NOT ON WHAT THE ENVIRONMENT HAPPENS TO CARRY ─────
# The sharpest observed defect: a session whose CC process exited and RESUMED came back with
# $ITERM_SESSION_ID unset, so `cc-await-ping` exited 3 ("no uuid given"), the session was absent from
# the registry, and its mail kept arriving at a box nothing watched — unaddressable, with no error
# anyone saw. Any design that derives identity from the environment inherits that.
#
# Every hook is handed the harness payload on stdin, and it carries `session_id` — a durable identity
# that survives the resume the environment variable does not. So: prefer the PANE when we have one
# (cc-await-ping's mailbox_keyset then covers pane AND session — the wider cover), and fall back to
# the harness's own session_id when the environment has lost it. Arming therefore survives the exact
# restart that used to silence it.
#
# ── KILL SWITCH ──────────────────────────────────────────────────────────────────────────────────
#   CC_WAKE_ARM=0   → this hook is a no-op (exit 0 immediately, no watcher, no wake).
# Anything touching the fleet wake path needs one: a wake-path change that lands wrong makes every
# running session deaf, which is the failure this exists to fix, at fleet scale.
set -uo pipefail

[ "${CC_WAKE_ARM:-1}" != 0 ] || exit 0

# ── HEADLESS ONE-SHOT GUARD (2026-08-10) ─────────────────────────────────────────────────────────
# asyncRewake is honored ONLY when the session is interactive or has streaming input. Read out of
# the 2.1.220 binary: the dispatch gate is `(e.async || e.asyncRewake && K) && !d` with
# `K = !_n() || r2r()` where `_n() = !Mt.isInteractive` and `r2r() = Mt.hasStreamingInput`. In a
# plain one-shot `claude -p`, K is FALSE — the hook is dispatched SYNCHRONOUSLY, and the ~4 h watch
# below would BLOCK SESSION BIRTH for every headless probe and daemon on the box. A one-shot needs
# no idle wake anyway: it runs one turn and exits.
#
# Oracle: the harness process's OWN argv — the first claude/node ancestor — the only place print
# mode is visible from inside a hook (MEMORY.md version-identity-is-the-running-process). Test
# seam: CC_WAKE_ARM_HARNESS_ARGV substitutes the argv without walking ps.
#
# ── …AND EVERY OTHER NON-INTERACTIVE MODE (2026-10-14) ───────────────────────────────────────────
# `-p` is not the only way in. 2.1.293's interactivity predicate is
# `t4e(){… return n||t||o||!process.stdout.isTTY}`: a session with NO -p whose stdout is a pipe is
# non-interactive too, and it dispatched this hook SYNC. Pane 434 was exactly that — a successor
# whose stdout was the operator's `| tee`; the argv-only guard armed, and the watch blocked its
# birth for 6 min until another session killed it (docs/research/recycle-failure-2026-10-14.md
# § Q2). Two more oracles close it, either one sufficient:
#   - CLAUDE_CODE_ENTRYPOINT=sdk-cli. The binary sets it from the same flag (`e?"sdk-cli":"cli"`).
#     PROBED LIVE 2026-10-14 on 2.1.293 (pty stdin, stdout piped, no -p): the hook saw sdk-cli even
#     though the launching shell exported cli — the harness sets it, it is not inherited.
#   - the harness process's fd 1 is not a tty (`lsof -d 1`), the predicate itself, read directly.
#     Test seam: CC_WAKE_ARM_HARNESS_FD1 substitutes fd 1's name (same `+x` semantics as the argv).
# Streaming input (`--input-format stream-json`) still arms in every mode: the dispatcher backgrounds
# an asyncRewake hook when interactive OR streaming (`so=!Ee()||Zlt()`).
#
# FAIL DIRECTION — cannot resolve an ancestor ⇒ SKIP (exit 0). A skipped arm restores the
# pre-registration status quo (the nag + boundary drain still exist); a wrongly-armed SYNC watch
# wedges a session birth for hours. Under-arming is recoverable, over-arming is not.
#
# (The guard runs AFTER the stdin read below — every exit path must have consumed the payload
# first, per this file's SIGPIPE discipline.)

# ── stdin: fully consumed so the harness never SIGPIPEs, whether or not we use it ────────────────
_stdin="$(cat 2>/dev/null || true)"

# `+x` not `:-`: SET-but-EMPTY means "provably unresolvable" and is honored verbatim, so a test can
# exercise the fail-closed branch without fixturing ps (the cc-await-ping IT2_BIN `${VAR-}` pattern —
# a test that cannot turn the oracle off cannot prove the fail-closed direction exists).
_harness_pid=""
if [ "${CC_WAKE_ARM_HARNESS_ARGV+x}" = x ]; then
  _harness="$CC_WAKE_ARM_HARNESS_ARGV"
else
  _harness=""
  _anc="$PPID"; _hops=0
  while [ -n "$_anc" ] && [ "$_anc" != 1 ] && [ "$_hops" -lt 6 ]; do
    _cmdline="$(ps -o command= -p "$_anc" 2>/dev/null || true)"
    case "$_cmdline" in
      *claude*|*node*) _harness="$_cmdline"; _harness_pid="$_anc"; break ;;
    esac
    _anc="$(ps -o ppid= -p "$_anc" 2>/dev/null | tr -d ' ' || true)"
    _hops=$(( _hops + 1 ))
  done
fi
[ -n "$_harness" ] || exit 0   # unresolvable dispatch mode → skip (under-arm, never wedge)
case "$_harness" in
  *--input-format*stream-json*) : ;;  # streaming input ⇒ K true ⇒ async dispatch is honored
  *)
    case " $_harness " in
      *" -p "*|*" --print "*) exit 0 ;;   # one-shot print ⇒ SYNC dispatch ⇒ arming would block birth
    esac
    # No -p, but stdout not a tty is the same mode (header, 2026-10-14). Entrypoint first: free.
    [ "${CLAUDE_CODE_ENTRYPOINT:-}" != sdk-cli ] || exit 0
    if [ "${CC_WAKE_ARM_HARNESS_FD1+x}" = x ]; then
      _fd1="$CC_WAKE_ARM_HARNESS_FD1"
    elif [ -n "$_harness_pid" ]; then
      _fd1="$(lsof -w -a -p "$_harness_pid" -d 1 -Fn 2>/dev/null | sed -n 's/^n//p' | head -n 1)"
    else
      _fd1=""
    fi
    case "$_fd1" in
      /dev/tty*|/dev/pts/*) : ;;   # the TUI's terminal ⇒ interactive ⇒ async dispatch
      *) exit 0 ;;                 # a pipe, a file, or unresolvable ⇒ skip (under-arm, never wedge)
    esac
    ;;
esac

_sid=""
if command -v jq >/dev/null 2>&1; then
  _sid="$(printf '%s' "$_stdin" | jq -r '.session_id // empty' 2>/dev/null || true)"
fi
case "$_sid" in *[!0-9A-Fa-f-]*) _sid="" ;; esac

_pane="${CC_PANE_ID:-${ITERM_SESSION_ID:-}}"; _pane="${_pane##*:}"
# ADDRESS SHAPE: a safe filename component, NOT "hex-shaped". `hdl-<hex>` is a real pane
# address (bin/cc-pane-headless:124/:197); the hex spelling refused it. SSOT rationale:
# hooks/session-register.sh. Backlog 4b9d5e93b40a (writer) + 5d1b5dd9b3db (this consumer).
case "$_pane" in ''|.|..|.*|*[!A-Za-z0-9._-]*) _pane="" ;; esac

# PRECEDENCE, and the reason for it: cc-await-ping given a PANE watches mailbox_keyset(pane) = the
# pane box AND its aliased session box, which is the full cover. Given a SESSION it can only watch
# the session box, because a session key has no alias trail pointing anywhere. So the pane is the
# better argument whenever it exists; session_id is the fallback that makes a resumed, pane-less
# session armable at all rather than silently deaf.
_key="${_pane:-$_sid}"
if [ -z "$_key" ]; then
  # Neither identity is available. Do NOT wake for this: a wake costs a model turn, this fires at
  # BIRTH, and a sidechain/subagent session legitimately has neither id — waking each one would burn
  # a turn per spawn (the exact defect session-continue.sh:240-312 already carries). Record it
  # durably instead, so "could not arm" is distinguishable from "nothing arrived" by a reader that
  # costs nothing. Absence must be loud, but it must also carry existence evidence: this marker is
  # written by a hook that provably RAN, which "no watcher heartbeat" alone never establishes.
  _mdir="${CC_MAILBOX_DIR:-$HOME/.claude/mailbox}"
  mkdir -p "$_mdir" 2>/dev/null \
    && printf '%s unaddressable: no pane id in env and no session_id on stdin\n' \
         "$(date '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null)" \
         >> "$_mdir/.unaddressable" 2>/dev/null || true
  exit 0
fi

# ── CLAIM GUARD (W2) — a no-op whenever a LIVE watcher already covers this inbox ─────────────────
# Registered on Stop, this hook fires at EVERY idle boundary, and the harness starts a fresh process
# each time. Without a guard a session accumulates one watcher per stop, all watching the same box:
# measured in the P-W2d probe as two `exit 2`s on one mail line and two synthesized turns. A wake
# costs a model turn, so a duplicate wake is a duplicate turn — the alarm-polarity failure of a
# mechanism that is supposed to make idleness cheap.
#
# The predicate is the lib's `mailbox_wake_armed` (SSOT — hooks/lib/mailbox-pending.sh), the same one
# cc-notify, mailbox-drain and the wake floor read: fresh heartbeat AND a live pid. Re-deriving it
# here would be the fourth copy of a definition whose whole point is that its readers cannot disagree.
# It is asked over the KEYSET, not the single key, because the birth watcher may have armed on the
# pane while a resumed stop resolves the session id (or the reverse) — one key answers one of those
# and not the other, which is exactly the half-coverage cc-await-ping beats every key to abolish.
#
# FAIL DIRECTION — cannot tell ⇒ ARM. Inverted from the headless guard above, and deliberately: there
# the unknown risks WEDGING a session for hours, here it risks one duplicate reminder. This substrate
# is dup-biased throughout ("a visible dup over a silent loss"), and a guard that suppressed the arm
# on a missing lib would turn a packaging slip into fleet-wide deafness.
_armed_already() {   # <key> → 0 = a live watcher already covers this inbox, 1 = arm
  local _lib _k
  _lib="$(dirname "$0")/lib/mailbox-pending.sh"
  [ -f "$_lib" ] || _lib="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/hooks/lib/mailbox-pending.sh"
  [ -f "$_lib" ] || _lib="$HOME/.claude/hooks/lib/mailbox-pending.sh"
  [ -f "$_lib" ] || return 1
  # shellcheck source=lib/mailbox-pending.sh
  # shellcheck disable=SC1091
  . "$_lib" 2>/dev/null || return 1
  command -v mailbox_wake_armed >/dev/null 2>&1 || return 1
  for _k in $(mailbox_keyset "$1" 2>/dev/null || printf '%s\n' "$1"); do
    mailbox_wake_armed "$_k" && return 0
  done
  return 1
}
if _armed_already "$_key"; then exit 0; fi

# ── locate the watcher ───────────────────────────────────────────────────────────────────────────
# Same candidate order every hook here uses. A brand-new tracked file is not symlinked into the live
# ~/.claude layer until install.sh runs, so the repo-relative path is tried FIRST — otherwise this
# would ship pointing at a path that does not execute yet, which reads GREEN and does nothing.
_ping=""
for _c in "$(dirname "$0")/../bin/cc-await-ping" \
          "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/bin/cc-await-ping" \
          "$HOME/.claude/bin/cc-await-ping"; do
  [ -x "$_c" ] && { _ping="$_c"; break; }
done
[ -n "$_ping" ] || exit 0     # nothing to arm with: silent no-op, never a spurious wake

# ── bounds ───────────────────────────────────────────────────────────────────────────────────────
# The harness's own per-hook `timeout` also bounds this process, and whether it KILLS a backgrounded
# asyncRewake hook is explicitly NOT established by the 2026-07-29 probe (it never reached its
# timeout). So the watcher's own bound is set strictly UNDER the registered hook timeout: whichever
# limit actually binds, we exit through our own clean path (rc 2 → silent exit 0) rather than being
# reaped mid-watch. Degrade quietly; never wake to say nothing happened.
_to="${CC_WAKE_ARM_TIMEOUT:-14340}"        # 3h59m — the migration registers timeout 14400
case "$_to" in ''|*[!0-9]*) _to=14340 ;; esac
_iv="${CC_WAKE_ARM_INTERVAL:-15}"
case "$_iv" in ''|*[!0-9]*) _iv=15 ;; esac

# ── the watch ────────────────────────────────────────────────────────────────────────────────────
# stdout is CAPTURED, never passed through: the harness drops an asyncRewake hook's stdout and
# carries only stderr into the synthesized turn (measured — W0-PROBE-WAKE-STDOUT appears 0 times in
# the proof transcript, the STDERR variant twice). cc-await-ping prints the mail body on stdout, so
# passing it through unchanged is precisely how this would wake the model with an empty reminder.
_errf="$(mktemp "${TMPDIR:-/tmp}/wake-arm.XXXXXX" 2>/dev/null)" || _errf=/dev/null
_body="$("$_ping" "$_key" --timeout "$_to" --interval "$_iv" 2>"$_errf")"; _rc=$?
# The watcher's own verdict, read before the file goes. A STOOD-DOWN watcher (this inbox's own
# `cc-await-ping --stand-down`, or the idle-scoped awaiter seeing a new turn) exits 0 with NO body and
# consumed nothing — waking on that was the bare "📬 peer mail" with "(…returned no body…)" that made
# up 15 of 26 measured wakes (docs/research/peer-mail-headline-2026-10-10/slot-lag-ack.md). Nothing is
# lost by staying quiet: no cursor moved, so any pending mail surfaces at the next boundary.
_stood=0
[ "$_errf" != /dev/null ] && grep -q 'verdict=stood-down' "$_errf" 2>/dev/null && _stood=1
[ "$_errf" != /dev/null ] && rm -f "$_errf"
[ "$_rc" = 0 ] && [ -z "$_body" ] && [ "$_stood" = 1 ] && exit 0

case "$_rc" in
  0|4)
    # MAIL. rc 4 is "delivered but the shared cursor could not be advanced" — that is a dup risk, not
    # a loss, and it is still mail: surfacing it is strictly better than swallowing it.
    [ -n "$_body" ] || _body="(the watcher reported mail but returned no body — read it with: cc-mail)"
    # HEADLINES (2026-10-11). The operator-visible row of an asyncRewake wake is the STATIC
    # `rewakeSummary` from settings — Claude Code 2.1.293 honours a per-wake summary only from an
    # official-marketplace plugin (slot-rewake.md) — so the per-mail headline has to reach the
    # operator through the woken session itself: the headlines lead the body, and mail from another
    # session's pane carries the instruction to acknowledge it in one chat line.
    _mhl="$(dirname "$0")/lib/mail_headline.py"
    [ -f "$_mhl" ] || _mhl="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/hooks/lib/mail_headline.py"
    [ -f "$_mhl" ] || _mhl="$HOME/.claude/hooks/lib/mail_headline.py"
    _own_pane="${CC_PANE_ID:-${ITERM_SESSION_ID:-${KITTY_WINDOW_ID:-}}}"; _own_pane="${_own_pane##*:}"
    _rendered=""
    [ -f "$_mhl" ] && _rendered="$(printf '%s\n' "$_body" | python3 "$_mhl" wake --own "$_own_pane" 2>/dev/null)"
    [ -n "$_rendered" ] && _body="$_rendered"
    printf '%s\n' "$_body" >&2
    [ "$_rc" = 4 ] && printf '%s\n' \
      "⚠ the shared cursor could not be advanced — you may see this mail again (a dup, never a loss)." >&2
    exit 2                                  # ← THE WAKE. The one exit code the harness acts on.
    ;;
  5)
    # ORPHANED — the session that armed this watcher is provably gone. It exited WITHOUT consuming,
    # deliberately, so the mail stays unacked for the successor to adopt. Waking a session about a
    # predecessor's mail it did not receive would be a false positive.
    exit 0
    ;;
  *)
    # 2 = timed out (the designed end of a watch that ran its term) · 3 = no uuid · anything else.
    # All silent: exit 0 leaves the session exactly as it was, with no synthesized turn.
    exit 0
    ;;
esac
