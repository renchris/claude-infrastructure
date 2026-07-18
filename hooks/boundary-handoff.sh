#!/bin/bash
# boundary-handoff.sh — advisory Stop-hook: at a COMMITTED + GREEN boundary, when a session's OWN
# context fill has crossed its plan-declared threshold, advise it to run the /handoff rails before
# auto-compaction discards accumulated context.
#
# ── WHAT IT STRUCTURALLY CANNOT SEE (blind-check pre-mortem, audit §3i / blueprint §3.2) ──
# B-1  It fires on the **Stop** event, so a session HUNG MID-TURN never reaches Stop and this hook
#      NEVER RUNS for exactly the sessions most likely to be past their boundary (trigger == failure,
#      same shape as "no render ⇒ no telemetry"). ⇒ This hook is a REFINEMENT, never the carrier
#      (invariant 4); the SUPERVISOR independently covers 'past-threshold ∧ not-Stopping'. Do not
#      make this the sole boundary mechanism.
# B-2  A one-shot latch keyed on HEAD-sha alone SILENCES ITSELF in the dangerous state: a session
#      that gets the advisory, ignores it, and keeps working WITHOUT committing leaves HEAD unchanged
#      ⇒ the latch holds ⇒ the hook never re-advises — quiet exactly when it should get louder. So the
#      latch carries a SECOND re-arm dimension: a used_pct delta (default +10). It re-fires as an
#      ignored session fills further.
# B-3  Every invocation emits {fired|abstained:<reason>} to the IDL. Without it, "didn't fire" and
#      "never evaluated" are the same observation (the D9 blind-verifier shape, in the primitive whose
#      whole job is to fire). Alarm on abstained==100% over N≥10 (the ship-gate rule).
#
# Delivery: one-shot-latched {decision:"block"} (D-C — additionalContext is inert/probe-gated on
# 2.1.207; the latch is what makes a block ADVISORY-not-looping — an UNLATCHED block is the banned
# infinite-loop anti-pattern). Exit 0 ALWAYS: a Stop hook must never cost a session.
#
# Env seams (tests): CC_TELEMETRY_DIR · CC_IDL · CC_BOUNDARY_T · CC_BOUNDARY_REARM_DELTA ·
#                    CC_BOUNDARY_LATCH_DIR · CC_BOUNDARY_LOGFILE · CC_CONTINUE_SENTINEL
#
# ── CC_BOUNDARY_DIRS_NOTE (G-P6-5b / a19 live table) — REGISTER ON ALL FOUR CONFIG DIRS ──
# The desk runs on .claude-secondary / -tertiary, which today carry NO boundary hook at all; it
# lives only on ~/.claude, in a SEPARATE matcher-null Stop object via a hardcoded abs path → 0 IDL
# records in prod (empirically never evaluates). Move it into the SAME Stop array as session-continue
# + anti-deference (obj-1), path ~/.claude/hooks/…, in every dir. Non-interactive apply (per dir):
#   for d in ~/.claude ~/.claude-secondary ~/.claude-tertiary ~/.claude-quaternary; do
#     f="$d/settings.json"
#     jq '(.hooks.Stop[0].hooks) |= (if any(.[]; .command|test("boundary-handoff")) then .
#          else . + [{type:"command",command:"~/.claude/hooks/boundary-handoff.sh",timeout:10}] end)' \
#        "$f" > "$f.tmp" && mv "$f.tmp" "$f"
#   done
# Full wiring + rollback: docs/activation/fm1b-activate-snippet.md (wiring is the operator's — C10).
set -uo pipefail

T="${CC_BOUNDARY_T:-73}"                          # fire threshold, used_pct (≤73; autocompact at 90, D-F)
AGE_MAX=180                                        # abstain if telemetry older than this (can't trust stale)
REARM_DELTA="${CC_BOUNDARY_REARM_DELTA:-10}"       # B-2 second re-arm dimension (used_pct climb)
IDL="${CC_IDL:-$HOME/.claude/autonomy/idl.jsonl}"
LATCH_DIR="${CC_BOUNDARY_LATCH_DIR:-$HOME/.claude/autonomy/boundary-latch}"
TEL_DIR="${CC_TELEMETRY_DIR:-/tmp/cc-telemetry}"

# Shared sentinel-path SSOT — lets the compose-guard below check session-continue's REAL path
# (G-P6-6b). Resolve next to this script (repo + symlinked ~/.claude/hooks/ install), then fall back.
_bscd="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
_blib="$_bscd/lib/continue-sentinel.sh"
[ -f "$_blib" ] || _blib="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/hooks/lib/continue-sentinel.sh"
[ -f "$_blib" ] || _blib="$HOME/.claude/hooks/lib/continue-sentinel.sh"
# shellcheck source=lib/continue-sentinel.sh
[ -f "$_blib" ] && . "$_blib" 2>/dev/null || true

stdin_json="$(cat 2>/dev/null || true)"
sid="$(printf '%s' "$stdin_json" | jq -r '.session_id // empty' 2>/dev/null || true)"

# ── B-3: one IDL line per invocation. Never fails the hook. ──
log_idl() { # $1=disposition  $2=reason  $3=extra-json-fields(optional, leading comma-free)
  mkdir -p "$(dirname "$IDL")" 2>/dev/null || true
  local ts; ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '{"ts":"%s","hook":"boundary-handoff","sid":"%s","disposition":"%s","reason":"%s"%s}\n' \
    "$ts" "${sid:-?}" "$1" "$2" "${3:+,$3}" >> "$IDL" 2>/dev/null || true
}
abstain() { log_idl abstained "$1"; exit 0; }     # abstained = evaluated but did not fire (LOGGED, not silent)

command -v jq >/dev/null 2>&1 || { log_idl abstained "no-jq"; exit 0; }
[ -n "$sid" ] || abstain "no-session-id"

tel="$TEL_DIR/$sid.json"
[ -f "$tel" ] || abstain "no-telemetry"

# ── (c) threshold + freshness — an old number is not evidence of the current fill ──
now="$(date +%s)"
ts="$(jq -r '.ts // 0' "$tel" 2>/dev/null || echo 0)"; ts="${ts%.*}"
[ -n "$ts" ] || ts=0
age=$(( now - ts ))
[ "$age" -le "$AGE_MAX" ] || abstain "stale-telemetry:${age}s"
used="$(jq -r '.used_pct // 0' "$tel" 2>/dev/null || echo 0)"; used="${used%.*}"
case "$used" in ''|*[!0-9]*) used=0 ;; esac
[ "$used" -ge "$T" ] || abstain "below-threshold:${used}<${T}"

# ── repo resolution (session's cwd; --git-common-dir so linked worktrees resolve the shared gitdir) ──
cwd="$(jq -r '.cwd // empty' "$tel" 2>/dev/null || true)"
{ [ -n "$cwd" ] && [ -d "$cwd" ]; } || abstain "no-cwd"

# ── Compose-guard (G-P6-6b / a19 I-1): if session-continue's 🔧 loop is armed for THIS cwd, it owns
#    the next turn — yield, don't double-inject. Check its REAL sentinel path (test override
#    CC_CONTINUE_SENTINEL wins; else the shared SSOT hooks/lib/continue-sentinel.sh). The old guard
#    hardcoded ~/.claude/hooks/.session-continue-armed — a path session-continue never writes → the
#    guard was a dead no-op that let both hooks block one Stop. Placed after cwd resolution so it can
#    compute the cwd-keyed path; still BEFORE the latch/fire, so an armed session is never advised. ──
if [ -n "${CC_CONTINUE_SENTINEL:-}" ]; then
  sc_sentinel="$CC_CONTINUE_SENTINEL"
elif command -v continue_sentinel_for >/dev/null 2>&1; then
  sc_sentinel="$(continue_sentinel_for "$cwd")"
else
  sc_sentinel=""     # sentinel lib unavailable → cannot compute; skip (logged), never wrongly suppress
fi
{ [ -n "$sc_sentinel" ] && [ -f "$sc_sentinel" ]; } && abstain "continue-hook-armed"

head="$(git -C "$cwd" rev-parse HEAD 2>/dev/null || true)"
[ -n "$head" ] || abstain "not-a-repo"
gitdir="$(git -C "$cwd" rev-parse --git-common-dir 2>/dev/null || true)"
case "$gitdir" in /*) ;; *) gitdir="$cwd/$gitdir" ;; esac

# ── (a) committed + green + no live teammates — never advise handoff on an UNPROVEN-green tree ──
[ -z "$(git -C "$cwd" status --porcelain 2>/dev/null)" ] || abstain "dirty-tree"
green="$(cat "$gitdir/gate-green" 2>/dev/null || true)"
[ "$green" = "$head" ] || abstain "gate-not-green-at-head"
busy=0
while IFS= read -r w; do
  [ -n "$w" ] && [ -f "$w/.teammate-busy" ] && busy=1
done < <(git -C "$cwd" worktree list --porcelain 2>/dev/null | awk '/^worktree /{print $2}')
[ "$busy" = 0 ] || abstain "live-teammates"

# ── (b) the narrative log head == HEAD (the work is RECORDED, not merely committed) ──
# Best-effort: if a log file is configured/known, the commit that last touched it must BE HEAD, else
# the session committed code but has not written up the boundary — abstain rather than advise a handoff
# that would strand the un-narrated state.
logfile="${CC_BOUNDARY_LOGFILE:-}"
if [ -n "$logfile" ] && [ -f "$cwd/$logfile" ]; then
  loghead="$(git -C "$cwd" rev-parse HEAD 2>/dev/null)"
  logtouch="$(git -C "$cwd" log -1 --format=%H -- "$logfile" 2>/dev/null || true)"
  [ "$logtouch" = "$loghead" ] || abstain "log-head-lags:$logfile"
fi

# ── B-2: one-shot latch (hash(configdir|cwd)-HEADsha) + used_pct-delta re-arm ──
cfg="$(jq -r '.config_dir // empty' "$tel" 2>/dev/null || true)"
key="$(printf '%s|%s' "$cfg" "$cwd" | shasum 2>/dev/null | cut -c1-16)"
latch="$LATCH_DIR/${key}-${head}"
mkdir -p "$LATCH_DIR" 2>/dev/null || true
if [ -f "$latch" ]; then
  last_used="$(cat "$latch" 2>/dev/null || echo 0)"; case "$last_used" in ''|*[!0-9]*) last_used=0 ;; esac
  # re-arm ONLY if fill climbed ≥ REARM_DELTA since the last fire — so an ignored session gets the
  # advisory again as it fills, instead of the latch going silent on an unchanged HEAD (B-2).
  [ "$(( used - last_used ))" -ge "$REARM_DELTA" ] || abstain "latched:used=${used},last=${last_used},need=+${REARM_DELTA}"
fi

# ── FIRE — record the fill at fire-time (the re-arm baseline), log, then advise via latched block ──
printf '%s' "$used" > "$latch" 2>/dev/null || true
log_idl fired "past-boundary" "\"used_pct\":${used},\"threshold\":${T},\"head\":\"${head:0:8}\""
reason="⚑ Boundary reached — context ${used}% ≥ ${T}% at a committed + green boundary (HEAD ${head:0:8}). Run the /handoff rails now to preserve state into a successor before auto-compaction. (Advisory: if you have a genuine reason to keep working, do so — this re-arms at +${REARM_DELTA}% fill.)"
jq -nc --arg r "$reason" '{decision:"block",reason:$r,systemMessage:$r}'
exit 0
