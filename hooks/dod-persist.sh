#!/usr/bin/env bash
# dod-persist.sh — durable frozen-DoD carrier (a19 §2 HOP A-E: the 100/100 contract dies at the 90%
# auto-compact with no plan file — "inline-only DoD evaporates with zero advisory and zero
# re-injection"). This hook is the durable, self-reconstructing home the contract lacked.
#
# THREE modes:
#   SessionStart : if a durable DoD file exists for this worktree, re-inject its verbatim content as
#                  additionalContext → the frozen scope re-enters EVERY fresh / recycled / compacted
#                  session mechanically (closes HOP A "zero re-injection" + HOP E recycle loss).
#   PreCompact   : extract the newest `Scope (frozen):` line from the transcript (mechanical grep, NO
#                  model call) and APPEND it (timestamped, INTEGRATE-never-overwrite) to the durable
#                  file IF ABSENT-or-stale → the contract survives the 90% auto-compact summarizer.
#                  ALSO captures every DISTINCT `Scope (grown): +<item>` line (Follow-On Gate F1-F4
#                  PASS growth, CLAUDE.md Session Close Protocol) — gate-passed scope growth survives
#                  compaction/recycle exactly like the frozen baseline, so a successor never mistakes
#                  authorized grown work for out-of-scope drift.
#   set "<scope>": CLI for the desk playbook / /handoff capture to freeze a scope explicitly.
#   path [cwd]   : print the resolved durable-DoD path (debug / playbook / tests).
#
# PATH CONTRACT — MUST match scripts/wrap-ledger.sh:87-93 (and thus hooks/completion-assert.sh, which
# reads the ledger). Producer (this) and consumers resolve the SAME file:
#   ${WRAP_DOD_FILE} if set, else ${WRAP_DOD_DIR:-~/.claude/autonomy/dod}/<hash(git-toplevel|cwd)>.md
#
# Fail-safe: hook modes ALWAYS exit 0 (a PreCompact/SessionStart hook must never cost a session); any
# jq/read failure degrades to a silent no-op. No `set -e`. The dedup (skip when the scope is
# unchanged) keeps the durable file small — it accumulates only DISTINCT frozen scopes.
#
# Env seams (tests): WRAP_DOD_FILE · WRAP_DOD_DIR — SHARED with wrap-ledger, so a test that points
# both at one file proves the producer↔consumer contract end-to-end.
set -uo pipefail

# ── DoD path — the SHARED lib (CLOSE_INTEGRITY W3): repo-identity key, legacy read-fallback ──
# Was an inline path-hash formula duplicated in wrap-ledger.sh behind a MUST-match comment — and
# path-keying meant a fresh worktree started on a BLANK scope contract (generator G2). Both sides
# now source hooks/lib/dod-path.sh; the inline fallback below preserves the exact legacy formula
# for a live layer that has not yet linked the new lib (an ADD gets no converge budget).
_dpd="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
_dplib="$_dpd/lib/dod-path.sh"
[ -f "$_dplib" ] || { _dpt="$0"; [ -L "$_dpt" ] && _dpt="$(readlink "$_dpt")"
  _dplib="$(cd "$(dirname "$_dpt")" 2>/dev/null && pwd)/lib/dod-path.sh"; }
[ -f "$_dplib" ] || _dplib="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/hooks/lib/dod-path.sh"
[ -f "$_dplib" ] || _dplib="$HOME/.claude/hooks/lib/dod-path.sh"
# shellcheck source=lib/dod-path.sh
# shellcheck disable=SC1090,SC1091
if ! . "$_dplib" 2>/dev/null; then
  dod_path_for() {  # legacy fallback — byte-equivalent to the pre-W3 formula, read==write
    local dir top hash
    if [ -n "${WRAP_DOD_FILE:-}" ]; then printf '%s' "$WRAP_DOD_FILE"; return; fi
    dir="${WRAP_DOD_DIR:-$HOME/.claude/autonomy/dod}"
    top="$(git -C "$1" rev-parse --show-toplevel 2>/dev/null || printf '%s' "$1")"
    hash="$(printf '%s' "$top" | shasum 2>/dev/null | cut -c1-16)"
    printf '%s/%s.md' "$dir" "${hash:-unknown}"
  }
  dod_read_files() { local f; f="$(dod_path_for "$1" read)"; [ -f "$f" ] && printf '%s\n' "$f"; return 0; }
fi
# Lineage fallbacks for a live layer whose lib predates the succession filter (row 4de3d0f9c0e1).
# Both degrade to the PRE-filter behaviour — unfiltered content, own toplevel only — because the
# fail-open direction here is "keeps the crosstalk", never "loses a contract you own".
command -v dod_toplevel >/dev/null 2>&1 || dod_toplevel() {
  local t; t="$(git -C "${1:-.}" rev-parse --show-toplevel 2>/dev/null)" || t=""
  [ -n "$t" ] || t="${1:-.}"; printf '%s' "$t"; }
command -v dod_filter_for >/dev/null 2>&1 || dod_filter_for() {
  [ -f "${2:-}" ] && { cat "$2" 2>/dev/null || true; }; return 0; }
command -v dod_read_content >/dev/null 2>&1 || dod_read_content() {
  local f; while IFS= read -r f; do [ -n "$f" ] && [ -f "$f" ] || continue
    cat "$f" 2>/dev/null || true; printf '\n'; done <<DPRC
$(dod_read_files "${1:-$PWD}")
DPRC
  return 0; }
dod_file_for() { dod_path_for "$1" write; }   # the canonical path — where new captures go

# ── newest "Scope (frozen): …" line already recorded — reads the STREAM on stdin ──
# Took a FILE argument until the lineage filter landed; every caller now pipes the
# LINEAGE-FILTERED stream (dod_filter_for) instead, so the argument had no remaining reader. Left
# as a dual-mode `"$@"` it would be dead surface AND a shellcheck SC2120 on every land.
last_recorded_scope() { grep -aoE 'Scope \(frozen\):.*' 2>/dev/null | tail -1; }

# ── newest "Scope (frozen): …" line stated anywhere in a transcript (all text records) ──
extract_scope() {  # $1 = transcript path
  jq -r 'select(.type=="assistant" or .type=="user")
         | .message.content
         | if type=="string" then .
           elif type=="array" then ([.[]?|select(.type=="text")|.text]|join("\n"))
           else empty end' "$1" 2>/dev/null \
    | grep -aoE 'Scope \(frozen\):.*' | tail -1
}

# ── all DISTINCT "Scope (grown): …" lines in a transcript (Follow-On Gate growth; many per session) ──
extract_grown() {  # $1 = transcript path
  jq -r 'select(.type=="assistant" or .type=="user")
         | .message.content
         | if type=="string" then .
           elif type=="array" then ([.[]?|select(.type=="text")|.text]|join("\n"))
           else empty end' "$1" 2>/dev/null \
    | grep -aoE 'Scope \(grown\):.*' | awk '!seen[$0]++'
}

# ── append (INTEGRATE, timestamped) — never overwrite prior captures ──
# PER-CAPTURE PROVENANCE (docs/research/dod-crosstalk-2026-08-18.md §4.1, prerequisite 1). The store
# is repo-KEYED (hooks/lib/dod-path.sh, W3), so every worktree of one repo appends here — 101 of them
# for this repo, 15 distinct frozen scopes in one file. The writing cwd was recorded only in the FILE
# HEADER, i.e. for the FIRST writer, so no reader could attribute a capture to a wave and no read-side
# rule against the crosstalk had an input to key on, however clever. Each block now names the toplevel
# that wrote it (and the session when the caller knows one).
# STRICTLY ADDITIVE — it rides the `## ` header line, which no consumer parses: readers grep the
# `Scope (frozen|grown):` lines (last_recorded_scope, wrap-ledger REMAINDER counts `- [ ]` boxes only),
# and this adds neither. Pinned by the reader-neutrality control in tests/dod-persist.bats.
persist_dod() {  # $1=file  $2=scope  $3=cwd  $4=source-label  [$5=session-id, "" when unknown]
  local ts prov top sid
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo '?')"
  # a linked worktree's toplevel IS the worktree root — exactly the identity the repo key collapses.
  # ONE author (hooks/lib/dod-path.sh dod_toplevel): the lineage filter compares against this stamp
  # BYTE-EQUAL, so a second copy of the formula would not be a style problem — it would be a silent
  # filter miss, which is the same class of defect the path formula's own two copies were.
  top="$(dod_toplevel "$3")"
  prov=" · toplevel=${top}"
  sid="${5:-}"
  if [ -n "$sid" ]; then prov="${prov} · session=${sid}"; fi
  mkdir -p "$(dirname "$1")" 2>/dev/null || true
  if [ ! -f "$1" ]; then
    {
      printf '# Durable frozen DoD — %s\n' "$3"
      printf '# producer: dod-persist.sh · consumers: wrap-ledger.sh, completion-assert.sh\n'
      printf '# INTEGRATE-only: each capture APPENDS below; history is never rewritten (a19 HOP A).\n\n'
    } > "$1" 2>/dev/null || return 0
  fi
  printf '## %s (%s)%s\n%s\n\n' "$ts" "$4" "$prov" "$2" >> "$1" 2>/dev/null || true
}

# ── CLI modes ──
case "${1:-}" in
  set)
    scope="${2:-}"
    [ -n "$scope" ] || { printf 'usage: dod-persist.sh set "<Scope (frozen): DoD>"\n' >&2; exit 2; }
    case "$scope" in *"Scope (frozen):"*|*"Scope (grown):"*) ;; *) scope="Scope (frozen): $scope" ;; esac
    f="$(dod_path_for "$PWD" write)"
    # The dedup compares against MY OWN last capture, not the file's. Unfiltered it would read a
    # concurrent sibling's identical scope as "unchanged", skip the write, and leave this wave with
    # no capture of its own — which the lineage filter would then correctly show as a BLANK
    # contract. Filtering here is what stops the crosstalk fix from manufacturing that hole.
    if [ -f "$f" ] && [ "$scope" = "$(dod_filter_for "$PWD" "$f" | last_recorded_scope)" ]; then
      printf 'unchanged → %s\n' "$f"; exit 0
    fi
    persist_dod "$f" "$scope" "$PWD" "manual-set" "${CLAUDE_CODE_SESSION_ID:-}"
    printf 'captured → %s\n' "$f"
    exit 0 ;;
  path)
    dod_file_for "${2:-$PWD}"; printf '\n'; exit 0 ;;
  get)
    # Print the current frozen DoD line for a cwd — SSOT read for the /handoff + waiting-recycle
    # DoD-carry (T-P4-4). Empty output (exit 0) = no DoD recorded yet; callers degrade gracefully.
    # W3: two read sources — the repo-key store (new captures) wins; this toplevel's legacy file
    # answers only when the new store has no scope yet.
    _g=""; _gc="${2:-$PWD}"
    while IFS= read -r _gf; do
      [ -n "$_gf" ] || continue
      _g="$(dod_filter_for "$_gc" "$_gf" | last_recorded_scope)"
      [ -n "$_g" ] && break
    done <<GETEOF
$(dod_read_files "$_gc")
GETEOF
    printf '%s\n' "$_g"; exit 0 ;;
esac

# ── Hook modes (JSON on stdin; dispatch by hook_event_name) ──
command -v jq >/dev/null 2>&1 || exit 0
input="$(cat 2>/dev/null || printf '{}')"
event="$(printf '%s' "$input" | jq -r '.hook_event_name // empty' 2>/dev/null || true)"
cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null || true)"
[ -n "$cwd" ] || cwd="$PWD"
# per-capture provenance: the hook payload is authoritative; the env is the fallback (a hook runs as a
# child of the session it belongs to). Empty when neither knows — the field is then OMITTED, never
# emitted blank, so a reader can distinguish "no session recorded" from "session recorded as nothing".
sid="$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null || true)"
[ -n "$sid" ] || sid="${CLAUDE_CODE_SESSION_ID:-}"

case "$event" in
  SessionStart)
    # W3: inject BOTH read sources (repo-key store first, then this toplevel's legacy) — the
    # lossless half of the migration: per-toplevel history keeps injecting exactly where it always
    # did, while every worktree of the repo now shares the repo-key captures.
    # LINEAGE-FILTERED (row 4de3d0f9c0e1, prerequisite 2). The repo key is byte-equal across every
    # worktree of the repo, so this used to hand a session every CONCURRENT wave's contract too —
    # 101 worktrees, 15 distinct frozen scopes, and no input existed to tell them apart. There is
    # one now: dod_read_content keeps this wave's captures and its recorded predecessors', drops a
    # foreign wave's, and keeps anything unattributable (see hooks/lib/dod-path.sh § FAIL-OPEN).
    content="$(dod_read_content "$cwd")"
    [ -n "$content" ] || exit 0
    # NEWEST-WINS FRAME (docs/research/dod-crosstalk-2026-08-18.md §2, §5 adjacent finding). This
    # used to declare "Every 'Scope (frozen):' line below is binding … do NOT narrow scope or
    # declare done until ALL of it is met" over the WHOLE file. The store is repo-KEYED, so that
    # file is shared by every worktree of the repo — 101 of them here, 15 distinct frozen scopes —
    # and the claim was therefore false for all but one: a session was handed concurrent and
    # finished waves' contracts as its own, every SessionStart, and could not tell them apart.
    # It also contradicted THIS SCRIPT: `get` and last_recorded_scope both already return the
    # NEWEST frozen line only. The frame now says what the rest of the store has always meant.
    # LOSSLESS — the full history is still injected verbatim, reframed as context rather than
    # dropped, so nothing a successor legitimately inherits can go missing.
    cur=""
    while IFS= read -r _cf; do
      [ -n "$_cf" ] && [ -f "$_cf" ] || continue
      cur="$(dod_filter_for "$cwd" "$_cf" | last_recorded_scope)"
      [ -n "$cur" ] && break
    done <<CUREOF
$(dod_read_files "$cwd")
CUREOF
    ncap="$(printf '%s' "$content" | grep -c '^## ' 2>/dev/null || echo 0)"
    case "$ncap" in ''|*[!0-9]*) ncap=0 ;; esac
    if [ -n "$cur" ]; then
      _lead="THE CURRENT CONTRACT — this is what binds you, and every 'Scope (grown): +<item>' line extends it (Follow-On Gate F1-F4 PASS — already authorized, do NOT re-ask). Do NOT narrow it or declare done until ALL of it is met:

    $cur"
    else
      # no frozen line anywhere (a grown-only store): name no contract rather than invent one
      _lead="THE CURRENT CONTRACT is not recorded — no 'Scope (frozen):' line exists in this store yet. Treat the history below as context only, and freeze a scope before claiming completeness."
    fi
    framed="Durable frozen DoD for this worktree — re-injected across recycle/compaction as the completeness baseline (a19 HOP A).

$_lead

Everything below is this wave's INTEGRATE-only history — ${ncap} capture(s) from its own worktree and its RECORDED PREDECESSORS, newest last. A concurrent wave's captures are filtered out mechanically, so nothing below belongs to a sibling; captures written before this store recorded provenance carry no toplevel and are kept rather than guessed at. It is prior CONTEXT, NOT additional binding scope — a predecessor's finished contract is not yours to complete. Each '## ' block names the toplevel that wrote it.

$content"
    jq -nc --arg c "$framed" '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$c}}' 2>/dev/null || true
    exit 0 ;;
  PreCompact)
    tp="$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null || true)"
    case "$tp" in "~"*) tp="$HOME${tp#\~}" ;; esac
    trigger="$(printf '%s' "$input" | jq -r '.trigger // "auto"' 2>/dev/null || echo auto)"
    { [ -n "$tp" ] && [ -f "$tp" ]; } || exit 0
    f="$(dod_path_for "$cwd" write)"
    scope="$(extract_scope "$tp")"
    if [ -n "$scope" ]; then
      # filtered, for the same reason `set` is: an identical scope frozen by a CONCURRENT wave must
      # not read as "already recorded" and leave this wave with no capture of its own
      if ! { [ -f "$f" ] && [ "$scope" = "$(dod_filter_for "$cwd" "$f" | last_recorded_scope)" ]; }; then
        persist_dod "$f" "$scope" "$cwd" "PreCompact:${trigger}" "$sid"
      fi
    fi
    # Follow-On Gate growth: each DISTINCT grown line appends exactly once (INTEGRATE)
    while IFS= read -r g; do
      [ -n "$g" ] || continue
      # COUNT, never `grep -q`: this file runs under `set -o pipefail`, and -q exits on the first
      # match, so the upstream filter takes SIGPIPE and the whole pipeline reports FAILURE on the
      # very input it just matched — a dedup that silently re-appends every grown line forever.
      # Caught by tests/dod-persist.bats case 16, which counts the appends.
      if [ -f "$f" ]; then
        _gseen="$(dod_filter_for "$cwd" "$f" | grep -cF -- "$g" 2>/dev/null || true)"
        case "${_gseen:-0}" in ''|*[!0-9]*) _gseen=0 ;; esac
        [ "$_gseen" -gt 0 ] && continue
      fi
      persist_dod "$f" "$g" "$cwd" "PreCompact:${trigger}:grown" "$sid"
    done <<GROWN_EOF
$(extract_grown "$tp")
GROWN_EOF
    exit 0 ;;
  *)
    exit 0 ;;
esac
