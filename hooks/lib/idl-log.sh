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
# ⚠️ THE SECOND SENTENCE OF THAT INVARIANT IS NOW HISTORY, AND IS KEPT BECAUSE IT IS THE RATIONALE,
# NOT BECAUSE IT IS STILL THE CONSEQUENCE (W3-B17, 2026-09-09). Both named consumers were since made
# tolerant and neither can abort any more: bin/cc-audit reads `[inputs | fromjson?]` per record and
# `warn_malformed()` REPORTS the skipped count, and scripts/idl-abstain-alarm.sh reads
# `fromjson? // empty` and prints raw-vs-parsed. The encoding invariant above is unchanged and still
# binds every field — what changed is that a breach now degrades a census by a counted stratum
# instead of silently zeroing it. tests/idl-record-size.bats holds the chokepoint lint that stops a
# NEW silent slurp from being introduced. Do not act on the old consequence without re-reading those
# two readers (memory: resident-policy-must-not-restate-perishable-facts).
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
#   log_idl_fixed <disposition> <reason>
#       log_idl for the commonest record (no extra, no merge), in one printf — see its comment.
#   _IDL_NOW
#       Optional: a caller that already read the clock may set this to its `date -u
#       +%Y-%m-%dT%H:%M:%SZ` string, and every record then carries it instead of forking `date`
#       again. Deliberately NOT reset on source or by idl_init, so a caller that re-sources the
#       lib keeps it; unset, behaviour is unchanged.
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
# ── THE SIZE ASSERTION (W3-B17, on W2-B17's number) ──────────────────────────────────────────────
# O_APPEND makes a write atomic only while the record fits the writer's stdio buffer (4,096 B here).
# Above it the line goes out as >=2 write() calls and a concurrent producer on the shared fd can land
# BETWEEN them, splicing both records. W2-B17 measured exactly that: a 6,679-byte backlog-health
# record cut at byte 4096 by a waiting-recycle append, after which jq exits 5 at that line and every
# census redirecting stderr silently drops 12.33% of the store.
#
# THE REFUSAL NEVER TRUNCATES. A truncated JSON line IS the defect this guards -- it would be
# indistinguishable from the splice, and unlike the splice it would be minted deliberately. An
# oversized record is DROPPED and replaced by a short, valid `idl-oversize` record naming the hook,
# the kind and the byte count, so the store carries the evidence that something tried.
#
# The threshold is 4,000 rather than 4,096: a guard sitting exactly on the boundary it protects has
# no headroom for the envelope a caller adds after the check.
idl_max_bytes() {
  local max="${CC_IDL_MAX_BYTES:-4000}"
  case "$max" in ''|*[!0-9]*) max=4000 ;; esac
  printf '%s' "$max"
}

# Append ONE already-built record line, refusing the size class that cannot be appended atomically.
# rc 0 = appended, rc 1 = refused (and an idl-oversize record was written in its place).
# Never fails the caller in a way that could break a hook: every I/O path is swallowed.
idl_guarded_append() { # <idl-path> <hook> <kind> <record-json>
  local path="$1" hook="$2" kind="$3" rec="$4" max n ts
  max="$(idl_max_bytes)"
  n="$(printf '%s' "$rec" | wc -c | tr -d ' ')"
  case "$n" in ''|*[!0-9]*) n=0 ;; esac
  if [ "$n" -le "$max" ]; then
    printf '%s\n' "$rec" >> "$path" 2>/dev/null || true
    return 0
  fi
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo '?')"
  jq -cn --arg ts "$ts" --arg hook "$hook" --arg kind "$kind" \
         --argjson bytes "$n" --argjson max "$max" \
    '{ts:$ts,hook:$hook,disposition:"idl-oversize",
      reason:"record refused: an append this size is not atomic on the shared fd",
      kind:$kind,bytes:$bytes,max:$max}' >> "$path" 2>/dev/null || true
  return 1
}

# _idl_mkparent — create the IDL's directory only when it is missing. Builtin path arithmetic and a
# builtin `-d` test: this runs on every record of every prompt hook, and `mkdir -p "$(dirname …)"`
# cost two process creations per record to do nothing on all but the first.
_idl_mkparent() {
  local d
  case "$_IDL_PATH" in */*) d="${_IDL_PATH%/*}" ;; *) d=. ;; esac
  [ -n "$d" ] || d=/
  [ -d "$d" ] || mkdir -p "$d" 2>/dev/null || true
}

log_idl() {
  [ "$_IDL_OFF" = 1 ] && return 0
  _idl_mkparent
  local ts extra sidval merge
  ts="${_IDL_NOW:-}"
  [ -n "$ts" ] || ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo '?')"
  extra="${3:-}"; [ -n "$extra" ] || extra='{}'
  sidval="${!_IDL_SID_VAR:-?}"; [ -n "$sidval" ] || sidval='?'
  merge='{}'
  if [ -n "$_IDL_MERGE_VAR" ]; then merge="${!_IDL_MERGE_VAR:-}"; [ -n "$merge" ] || merge='{}'; fi
  # $merge BEFORE $extra: a call site can still override a merged field.
  local _rec
  _rec="$(jq -cn --arg ts "$ts" --arg hook "$_IDL_HOOK" --arg sid "$sidval" \
         --arg disp "$1" --arg reason "$2" --argjson merge "$merge" --argjson extra "$extra" \
    '{ts:$ts,hook:$hook,sid:$sid,disposition:$disp,reason:$reason} + $merge + $extra' 2>/dev/null)"
  [ -n "$_rec" ] || return 0
  idl_guarded_append "$_IDL_PATH" "$_IDL_HOOK" "$1" "$_rec" || true
}

# log_idl_fixed <disposition> <reason> — the same record log_idl writes when there is no extra and
# no merge object, built by ONE printf instead of forking jq + wc + tr (+ date without _IDL_NOW).
# It is the per-prompt abstain row of the UserPromptSubmit hooks, written on every prompt of every
# session, which is where those forks were paid (docs/research/load-hook-timeouts-2026-10-11).
# Byte-identical to log_idl, and only taken when that is provable: `jq -c` keeps key order and emits
# no whitespace, and no character in [A-Za-z0-9_.:?-] is ever escaped by JSON, so printf of those
# fields IS the encoding. Any other byte in any field, or a merge slot, hands the call to log_idl,
# which encodes it — the invariant at the top of this file still binds every field. The record is
# pure ASCII, so its length is its byte count and the size guard needs no `wc`.
log_idl_fixed() {
  [ "$_IDL_OFF" = 1 ] && return 0
  # C locale: the charset test below must be byte-wise (a UTF-8 collation range can admit more than
  # ASCII), and ${#rec} must count bytes.
  local LC_ALL=C
  local ts sidval rec max="${CC_IDL_MAX_BYTES:-4000}"   # the idl_max_bytes rule, without its subshell
  case "$max" in ''|*[!0-9]*) max=4000 ;; esac
  sidval="${!_IDL_SID_VAR:-?}"; [ -n "$sidval" ] || sidval='?'
  ts="${_IDL_NOW:-}"
  [ -n "$ts" ] || ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo '?')"
  if [ -n "$_IDL_MERGE_VAR" ]; then log_idl "$@"; return 0; fi
  case "$ts$_IDL_HOOK$sidval${1:-}${2:-}" in *[!A-Za-z0-9_.:?-]*) log_idl "$@"; return 0 ;; esac
  printf -v rec '{"ts":"%s","hook":"%s","sid":"%s","disposition":"%s","reason":"%s"}' \
    "$ts" "$_IDL_HOOK" "$sidval" "${1:-}" "${2:-}"
  if [ "${#rec}" -gt "$max" ]; then log_idl "$@"; return 0; fi
  _idl_mkparent
  printf '%s\n' "$rec" >> "$_IDL_PATH" 2>/dev/null || true
}

# abstained = evaluated but did not fire (LOGGED, never silent). "didn't fire" must never be
# confusable with "never evaluated" — that ambiguity is what the IDL exists to remove.
abstain() { log_idl abstained "$1"; exit 0; }
