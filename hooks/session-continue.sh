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
    exit 0 ;;
  clear)
    f=$(sentinel_for "$PWD")
    rm -f "$f" "${f}.count" "${f}.sid" 2>/dev/null
    echo "cleared"
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

# No sentinel → the agent did NOT request continuation → allow the stop.
if [ ! -f "$f" ]; then
  rm -f "${f}.count" "${f}.sid" 2>/dev/null
  exit 0
fi

# ── (a) KILL-SWITCH — operator stop ALWAYS wins over a stale sentinel (I-2 / D-8) ──
# Read the LAST genuine user message (string content, or array-of-text; tool_result-only records
# carry no text and are skipped). A kill phrase ⇒ clear + allow. Bias to DETECT: a false positive
# merely allows one stop the model re-arms on its next 🔧 turn; a false negative is the D-8 bug
# (forcing work when told to stop). No transcript path ⇒ skip (can't read) and fall through.
tp=$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null)
case "$tp" in "~"*) tp="$HOME${tp#\~}" ;; esac
if [ -n "$tp" ] && [ -f "$tp" ]; then
  last_user=$(jq -r 'select(.type=="user")
                     | .message.content
                     | if type=="string" then .
                       elif type=="array" then ([.[]?|select(.type=="text")|.text]|join("\n"))
                       else empty end
                     | select(. != "")' "$tp" 2>/dev/null | tail -1)
  # Kill phrases (resident CLAUDE.md kill-switch + explicit-pause list):
  #   …and [then] stop · no auto-continue · just do X · stop here · come back to this · bare stop/halt
  if [ -n "$last_user" ] && printf '%s' "$last_user" | grep -iqE \
      '(^|[^[:alnum:]])and( then)? stop([^[:alnum:]]|$)|no[ _-]?auto[ _-]?continue|(^|[^[:alnum:]])just do [^[:space:]]|(^|[^[:alnum:]])stop here([^[:alnum:]]|$)|come back to this|^[[:space:]]*(stop|halt)[[:space:].!]*$'; then
    rm -f "$f" "${f}.count" "${f}.sid" 2>/dev/null
    printf 'session-continue: kill-switch phrase in last user message — cleared sentinel, allowing stop.\n' >&2
    exit 0
  fi
fi

# ── (b) SID-BIND — a same-cwd successor must not inherit a predecessor's sentinel (S-12) ──
# Clear + allow when the stored arming-sid differs from the actuating session's sid. Acts ONLY when
# BOTH sids are known (a missing sid = no evidence = never a wrong clear).
cur_sid=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)
[ -n "$cur_sid" ] || cur_sid="${CLAUDE_CODE_SESSION_ID:-}"
stored_sid=$(cat "${f}.sid" 2>/dev/null || true)
if [ -n "$stored_sid" ] && [ -n "$cur_sid" ] && [ "$stored_sid" != "$cur_sid" ]; then
  rm -f "$f" "${f}.count" "${f}.sid" 2>/dev/null
  printf 'session-continue: sentinel sid=%s ≠ session sid=%s (inherited across succession) — cleared, allowing stop.\n' "$stored_sid" "$cur_sid" >&2
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
  exit 0   # non-2 exit → does NOT block; the cap is a backstop, not a wedge
fi
n=$((n + 1))
printf '%s' "$n" > "${f}.count"

# ── v2 comms fold (critique B): carry any pending inbox mail in THIS block reason. ───────────────────
# session-continue is the ONE hook already blocking the in-loop desk, so folding delivery here means NO
# competing Stop blocker (no standalone mailbox-drain Stop hook, no 4-hook yield-guards, no wall-clock
# TTL). Lag-ack: promote last cycle's emitted mail to .acked (this Stop proves a turn ran), then take
# this cycle's mail with ack_now=0 (the Stop channel is less certain than additionalContext, so the
# cc-inbox-guard's .acked watch is the backstop). A missing lib just skips the fold — never blocks.
mail=""
_mbxlib="$_scd/lib/mailbox-pending.sh"
[ -f "$_mbxlib" ] || _mbxlib="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/hooks/lib/mailbox-pending.sh"
[ -f "$_mbxlib" ] || _mbxlib="$HOME/.claude/hooks/lib/mailbox-pending.sh"
if [ -f "$_mbxlib" ] && command -v jq >/dev/null 2>&1; then
  # shellcheck source=lib/mailbox-pending.sh
  # shellcheck disable=SC1091
  if . "$_mbxlib" 2>/dev/null; then
    _ouid="${ITERM_SESSION_ID:-}"; _ouid="${_ouid##*:}"
    case "$_ouid" in ''|*[!0-9A-Fa-f-]*) : ;; *)
      mailbox_promote_acked "$_ouid"
      mail="$(mailbox_take "$_ouid" 0)"
    ;; esac
  fi
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
exit 0
