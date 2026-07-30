#!/usr/bin/env bash
# idl-log.sh — SSOT for the B-3 IDL disposition writer (`log_idl` + `abstain`).
#
# WHY (consolidation audit 02, backlog b13787e71c9f): this function body existed as FOUR
# byte-lockstep copies (boundary-handoff, waiting-recycle, completion-assert,
# anti-deference-nudge) plus a fifth near-copy in operator-readout. They all carry the same
# load-bearing invariant, spelled out in each copy's own comment:
#
#     jq-encode EVERY field. A value carrying a " / backslash / newline must never be able to
#     emit a malformed IDL line — ONE malformed line aborts the cc-audit `jq -rs` slurp, which
#     then reads as "no records" and silently flips D9 / the abstain alarm GREEN, defeating the
#     un-gameable detector.
#
# An invariant that must hold identically in five places is exactly what a lib is for: before
# this file, fixing one copy left four wrong. Behaviour is PRESERVED — the emitted record is
# byte-identical to what each copy produced. This is a pure extraction, not a redesign.
#
# Deliberately a plain `jq` append and NOT a call to `cc-idl append` (which advertises itself as
# the canonical writer): this runs on the Stop path of every session, and adding a perl+jq fork
# there is the failure mode that blocked every gate for five days. cc-idl already covers these
# writers via its periodic `seal` — by its own design note, "the ~14 existing writers stay
# UNCHANGED".
#
# ── Caller contract ──
#   idl_init <idl-path> <hook-name> [sid-var-name] [merge-var-name]
#       Call ONCE after sourcing, before any log_idl/abstain.
#         <idl-path>      absolute path to the IDL jsonl. Each caller keeps its OWN env seam
#                         (CC_IDL / CC_WR_IDL / COMPLETION_IDL / ANTIDEF_IDL) and passes it here.
#         <hook-name>     literal recorded in `.hook`.
#         [sid-var-name]  NAME of the caller's session-id variable, read by indirection at CALL
#                         time so a sid assigned later is still picked up. Default "SID";
#                         boundary-handoff passes "sid". Unset/empty records "?", never a
#                         missing field.
#         [merge-var-name] NAME of a caller variable holding a JSON OBJECT to merge into EVERY
#                         record, also read at CALL time. This exists for the size axis
#                         (boundary-handoff / waiting-recycle pass "SIZE_JSON"): the measurement
#                         is published into that variable partway through the hook, and merging it
#                         HERE rather than at ~12 call sites is what makes "every eval records what
#                         it measured" hold BY CONSTRUCTION — a dormant threshold must never be
#                         indistinguishable from broken wiring. Merged BEFORE $extra, so a call
#                         site can still override a field. Omitted ⇒ `{}` ⇒ output is byte-identical
#                         to a caller that never had the slot.
#   idl_disable
#       Suppress the append entirely — for a non-hook mode that must write no telemetry
#       (operator-readout's `--render` pull surface). Call after idl_init.
#
# An explicit init (rather than ambient IDL_*/hook globals) is deliberate: the caller's variables
# stay visibly *used*, so shellcheck does not report SC2034 on every contract variable in a hook
# it cannot statically follow into this lib. Pure definitions only — no side effects on source
# (safe under `set -u`).

_IDL_PATH=""; _IDL_HOOK="?"; _IDL_SID_VAR="SID"; _IDL_MERGE_VAR=""; _IDL_OFF=0

idl_init() {
  _IDL_PATH="$1"
  _IDL_HOOK="$2"
  _IDL_SID_VAR="${3:-SID}"
  _IDL_MERGE_VAR="${4:-}"
  _IDL_OFF=0
}

idl_disable() { _IDL_OFF=1; }

# Append ONE disposition record. $1=disposition $2=reason $3=extra JSON OBJECT (jq-built, default {}).
# Never fails the caller: every failure path is swallowed — telemetry must not be able to break a hook.
log_idl() {
  [ "$_IDL_OFF" = 1 ] && return 0
  mkdir -p "$(dirname "$_IDL_PATH")" 2>/dev/null || true
  local ts extra sidval merge
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo '?')"
  extra="${3:-}"; [ -n "$extra" ] || extra='{}'
  sidval="${!_IDL_SID_VAR:-?}"; [ -n "$sidval" ] || sidval='?'
  merge='{}'
  if [ -n "$_IDL_MERGE_VAR" ]; then merge="${!_IDL_MERGE_VAR:-}"; [ -n "$merge" ] || merge='{}'; fi
  # $merge BEFORE $extra: a call site can still override a merged field.
  jq -cn --arg ts "$ts" --arg hook "$_IDL_HOOK" --arg sid "$sidval" \
         --arg disp "$1" --arg reason "$2" --argjson merge "$merge" --argjson extra "$extra" \
    '{ts:$ts,hook:$hook,sid:$sid,disposition:$disp,reason:$reason} + $merge + $extra' \
    >> "$_IDL_PATH" 2>/dev/null || true
}

# abstained = evaluated but did not fire (LOGGED, never silent). "didn't fire" must never be
# confusable with "never evaluated" — that ambiguity is what the IDL exists to remove.
abstain() { log_idl abstained "$1"; exit 0; }
