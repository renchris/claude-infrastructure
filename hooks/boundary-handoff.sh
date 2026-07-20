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
# ── CONTEXT-ECON (2026-07-20 — docs/research/context-econ-2026-07-20.md) ──
# Two continuous signals from hooks/lib/context-econ.sh sharpen the static threshold for ALL sessions:
#   • FORECAST-EARLY fire — used ≥ T_MIN (55) AND burn-forecast ≤ LEAD_MIN (20) minutes to the wall ⇒
#     advise BEFORE the static T (73): at high burn a builder can cross 73→90 inside one long turn,
#     and a Stop is exactly the pause-point to act at. Unknown forecast ⇒ static behavior, unchanged.
#   • CONVERSATION-AWARE WORDING — a fresh interactive turn (< CONV_S) means an exchange is in flight:
#     the advisory still fires (at ≥73% it must not vanish mid-dialogue) but tells the model to finish
#     the exchange + persist its decisions FIRST, then /handoff at the exchange's natural end. Wording,
#     never suppression; the model is the pause-point judge.
#
# Env seams (tests): CC_TELEMETRY_DIR · CC_IDL · CC_BOUNDARY_T · CC_BOUNDARY_REARM_DELTA ·
#                    CC_BOUNDARY_LATCH_DIR · CC_BOUNDARY_LOGFILE · CC_CONTINUE_SENTINEL ·
#                    CC_BOUNDARY_T_MIN · CC_BOUNDARY_LEAD_MIN · CC_BOUNDARY_CONV_S · CC_CE_*
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
#
# ── RE-OBSERVED 2026-07-19 (backlog 8a5aaf4eb824 "inert hook boundary-handoff: re-observe") ──
# The wiring prescribed above is DONE: all four config dirs now carry this hook in Stop obj-0 via
# ~/.claude/hooks/… and it is ACTIVELY EVALUATING — 53 IDL evals in ~3h across sessions, so the
# "0 IDL records / never evaluates" concern above is RESOLVED (that note is now historical). All 53
# abstained, but every reason is a HEALTHY condition-not-met (52× below-threshold, 1× no-telemetry)
# with 0 fired → the hook is healthy-DORMANT, not inert; the fire path is intact and simply had no
# session cross the 73% boundary at a committed + green Stop. The C3 `wiring-inert` discovery critic
# that filed the item alarms on disposition==abstained==100% over N≥10 REGARDLESS of reason, so a
# rarely-firing advisory hook is a structural false positive there (systemic follow-on backlogged).
# Residual (operator/C10, live settings.json): ~/.claude also keeps a redundant obj-1 copy at the old
# hardcoded repo-abs path — harmless (both exit 0 + latched), removable at the operator's discretion.
set -uo pipefail

T="${CC_BOUNDARY_T:-73}"                          # fire threshold, used_pct (≤73; autocompact at 90, D-F)
AGE_MAX=180                                        # abstain if telemetry older than this (can't trust stale)
REARM_DELTA="${CC_BOUNDARY_REARM_DELTA:-10}"       # B-2 second re-arm dimension (used_pct climb)
T_MIN="${CC_BOUNDARY_T_MIN:-55}"                   # context-econ: forecast-early fire never below this fill
LEAD_MIN="${CC_BOUNDARY_LEAD_MIN:-20}"             # context-econ: forecast ≤ this many min to the wall ⇒ early fire
CONV_S="${CC_BOUNDARY_CONV_S:-900}"                # context-econ: an interactive turn fresher than this = exchange in flight
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
# shellcheck disable=SC1091  # source path resolved at runtime; static-follow needs -x, ship-land's gate runs without it → SC1091(info) would red a solo change to this file
[ -f "$_blib" ] && . "$_blib" 2>/dev/null || true

# context-econ signal lib (burn/forecast + interactive recency) — same resolution ladder; a missing
# lib degrades every new signal to the static legacy behavior via the command -v guards below.
_celib="$_bscd/lib/context-econ.sh"
[ -f "$_celib" ] || _celib="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/hooks/lib/context-econ.sh"
[ -f "$_celib" ] || _celib="$HOME/.claude/hooks/lib/context-econ.sh"
# shellcheck source=lib/context-econ.sh
# shellcheck disable=SC1091  # runtime-resolved source; the ship gate runs shellcheck without -x
[ -f "$_celib" ] && . "$_celib" 2>/dev/null || true

stdin_json="$(cat 2>/dev/null || true)"
sid="$(printf '%s' "$stdin_json" | jq -r '.session_id // empty' 2>/dev/null || true)"
tp="$(printf '%s' "$stdin_json" | jq -r '.transcript_path // empty' 2>/dev/null || true)"

# ── B-3: one IDL line per invocation. Never fails the hook. ──
log_idl() { # $1=disposition  $2=reason  $3=extra JSON OBJECT (optional, jq-built {…}; default {})
  mkdir -p "$(dirname "$IDL")" 2>/dev/null || true
  local ts extra; ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  extra="${3:-}"; [ -n "$extra" ] || extra='{}'
  # jq-encode EVERY field: a value carrying a " / backslash / newline then can NEVER emit a
  # malformed IDL line — one malformed line aborts the cc-audit four-zeros `jq -rs` slurp, which
  # reads as "no records" and silently flips D9/the alarm GREEN (defeats the un-gameable detector).
  jq -cn --arg ts "$ts" --arg sid "${sid:-?}" --arg disp "$1" --arg reason "$2" --argjson extra "$extra" \
    '{ts:$ts,hook:"boundary-handoff",sid:$sid,disposition:$disp,reason:$reason} + $extra' \
    >> "$IDL" 2>/dev/null || true
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

# ── context-econ: sample velocity + forecast; fire EARLY (used ≥ T_MIN ∧ forecast ≤ LEAD_MIN) or at
#    the static T as before. Unknown forecast (-1) never triggers — static behavior preserved. ──
burn_x100=0; forecast_min=-1
if command -v ce_sample >/dev/null 2>&1; then
  ce_sample "$tel" || true
  _bf="$(ce_burn "$tel" 2>/dev/null || printf '0 -1')"
  burn_x100="${_bf%% *}"; forecast_min="${_bf##* }"
  case "$burn_x100" in ''|*[!0-9]*) burn_x100=0 ;; esac
  case "$forecast_min" in -1) ;; ''|*[!0-9]*) forecast_min=-1 ;; esac
fi
early=0
if [ "$used" -lt "$T" ]; then
  if [ "$used" -ge "$T_MIN" ] && [ "$forecast_min" -ge 0 ] && [ "$forecast_min" -le "$LEAD_MIN" ]; then
    early=1
  else
    abstain "below-threshold:${used}<${T}"
  fi
fi

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

# ── context-econ: is an exchange in flight? (wording only — never suppression; see header) ──
conv_age=""
if command -v ce_last_interactive_age >/dev/null 2>&1 && [ -n "$tp" ]; then
  case "$tp" in "~"*) tp="$HOME${tp#\~}" ;; esac
  [ -f "$tp" ] && conv_age="$(ce_last_interactive_age "$tp")"
  case "$conv_age" in *[!0-9]*) conv_age="" ;; esac
fi

# ── FIRE — record the fill at fire-time (the re-arm baseline), log, then advise via latched block ──
printf '%s' "$used" > "$latch" 2>/dev/null || true
log_idl fired "past-boundary" \
  "$(jq -cn --argjson used "$used" --argjson threshold "$T" --arg head "${head:0:8}" \
      --argjson burn "$burn_x100" --argjson fc "$forecast_min" --argjson early "$early" --arg conv "${conv_age:-}" \
      '{used_pct:$used,threshold:$threshold,head:$head,burn_x100:$burn,forecast_min:$fc,early:($early==1),conv_age_s:$conv}')"
if [ "$early" = 1 ]; then
  why="context ${used}% BURNING toward the ${CC_CE_WALL:-88}% auto-compact wall — forecast ≤${forecast_min}min at the observed rate"
else
  why="context ${used}% ≥ ${T}%"
fi
reason="⚑ Boundary reached — ${why} at a committed + green boundary (HEAD ${head:0:8}). Run the /handoff rails now to preserve state into a successor before auto-compaction. (Advisory: if you have a genuine reason to keep working, do so — this re-arms at +${REARM_DELTA}% fill.)"
if [ -n "$conv_age" ] && [ "$conv_age" -lt "$CONV_S" ] 2>/dev/null; then
  reason="${reason}
⚑ An operator/peer exchange is in flight (last interactive turn ${conv_age}s ago): do NOT cut it — finish the exchange, persist the decisions it produced (dod-persist / plan / memory), THEN run /handoff at its natural end."
fi
jq -nc --arg r "$reason" '{decision:"block",reason:$r,systemMessage:$r}'
exit 0
