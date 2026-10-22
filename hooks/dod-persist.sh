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
# /usr/bin/shasum is a #! perl script (a kernel-memory leak per exec on macOS 15.8.1); this is Mach-O. Linux: coreutils.
CC_SHA1=/sbin/sha1sum; [ -x "$CC_SHA1" ] || CC_SHA1=sha1sum

# ── PHASE TIMING + CHECKPOINT (docs/research/startup-hooks-2026-10-18/README.md §2 #17) ──────────
# The harness cancels this SessionStart hook at 5 s and discards ALL of its output: 18 cancels in two
# days, about 15 of them sessions that were owed a DoD (A5-F4), and no record of where the time went.
# Each SessionStart now appends one JSON line of per-phase milliseconds to CC_DOD_TIMING_LOG
# (default ~/.claude/logs/dod-persist-timing.jsonl, rotated by scripts/rotate-autonomy-logs.sh; set
# it empty to disable), and at each phase boundary past CC_DOD_CHECKPOINT_MS (default 3500; 0 or a
# non-number disables) it stops and emits a short labelled pointer to the store instead of being
# cancelled into nothing. Builtins only (EPOCHREALTIME, or SECONDS under bash 3.2), so a healthy
# start pays no spawn and no model token for either.
_dod_t_now() {
  local t="${EPOCHREALTIME:-}"; t="${t//[!0-9]/}"
  if [ -n "$t" ]; then _DOD_NOW="$t"; else _DOD_NOW=$(( SECONDS * 1000000 )); fi
}
_dod_t_now; _DOD_T0="$_DOD_NOW"; _DOD_TL="$_DOD_NOW"; _DOD_PHASES=""
_dod_mark() {  # $1=phase → its milliseconds since the previous mark, kept for the timing line
  _dod_t_now
  _DOD_PHASES="${_DOD_PHASES:+${_DOD_PHASES},}\"$1\":$(( (_DOD_NOW - _DOD_TL) / 1000 ))"
  _DOD_TL="$_DOD_NOW"
}
# shellcheck disable=SC2329  # reached through the EXIT trap's _dod_finish
_dod_timing_log() {  # $1=outcome → one line in the timing log (never creates its directory)
  local f="${CC_DOD_TIMING_LOG-$HOME/.claude/logs/dod-persist-timing.jsonl}" ts s=""
  [ -n "$f" ] && [ -d "${f%/*}" ] || return 0
  ts="${EPOCHREALTIME:-}"; ts="${ts%%[.,]*}"; case "$ts" in ''|*[!0-9]*) ts=null ;; esac
  case "${sid:-}" in ''|*[!A-Za-z0-9-]*) ;; *) s=",\"sid\":\"${sid}\"" ;; esac
  printf '{"ts":%s%s,"outcome":"%s","total_ms":%s,"phases":{%s}}\n' "$ts" "$s" "$1" \
    "$(( (_DOD_TL - _DOD_T0) / 1000 ))" "$_DOD_PHASES" >> "$f" 2>/dev/null || true
}
_dod_checkpoint() {  # $1=phase just finished — past the budget, point at the store and stop (SessionStart only)
  local max="${CC_DOD_CHECKPOINT_MS:-3500}" ms f1
  _dod_mark "$1"
  case "$max" in ''|*[!0-9]*|0) return 0 ;; esac
  ms=$(( (_DOD_TL - _DOD_T0) / 1000 ))
  [ "$ms" -ge "$max" ] || return 0
  _DOD_NEXT_PHASE=""   # the phase is already marked; _dod_finish only writes the line
  _dod_read_files_var "$cwd"
  f1="${_DOD_RF_LIST%%"$_dod_nl"*}"
  if [ -z "$f1" ]; then _DOD_OUTCOME=checkpoint-empty; exit 0; fi
  _DOD_OUTCOME=checkpoint
  f1="DoD not injected: dod-persist stopped at its ${max} ms checkpoint (${1}, ${ms} ms) instead of being cancelled. Your frozen scope is in $(_dod_tilde "$f1"); \`~/.claude/hooks/dod-persist.sh get\` prints it."
  if command -v ss_owed >/dev/null 2>&1; then ss_owed $(( ${#f1} + 1 )); fi
  jq -nc --arg c "$f1" '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$c}}' 2>/dev/null || true
  exit 0
}
# The SessionStart arm's EXIT trap: mark the phase in flight, then write the one timing line, on
# every exit path (render done, nothing to inject, checkpoint). It REPLACES the startup sentinel's
# own `trap 'ss_end $?' EXIT` (armed earlier in the arm), so it ends the sentinel too; ss_end is a
# no-op when the sentinel never began.
_DOD_NEXT_PHASE=render; _DOD_OUTCOME=ok
# shellcheck disable=SC2329  # invoked by `trap '_dod_finish $?' EXIT`
_dod_finish() {  # $1=the exit status
  [ -z "$_DOD_NEXT_PHASE" ] || _dod_mark "$_DOD_NEXT_PHASE"
  _dod_timing_log "$_DOD_OUTCOME"
  if command -v ss_end >/dev/null 2>&1; then ss_end "${1:-0}"; fi
}

# ── DoD path — the SHARED lib (CLOSE_INTEGRITY W3): repo-identity key, legacy read-fallback ──
# Was an inline path-hash formula duplicated in wrap-ledger.sh behind a MUST-match comment — and
# path-keying meant a fresh worktree started on a BLANK scope contract (generator G2). Both sides
# now source hooks/lib/dod-path.sh; the inline fallback below preserves the exact legacy formula
# for a live layer that has not yet linked the new lib (an ADD gets no converge budget).
case "$0" in */*) _dpd="${0%/*}" ;; *) _dpd=. ;; esac   # dirname without the fork
_dpd="$(cd "$_dpd" 2>/dev/null && pwd)"
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
    hash="$(printf '%s' "$top" | "$CC_SHA1" 2>/dev/null | cut -c1-16)"
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
# Memo fallbacks for a live layer whose lib predates dod_prime (README §2 #17): no memo, same answers.
command -v dod_prime >/dev/null 2>&1 || dod_prime() { return 0; }
command -v _dod_memo_hit >/dev/null 2>&1 || _dod_memo_hit() { return 1; }
command -v _dod_read_files_var >/dev/null 2>&1 || _dod_read_files_var() {
  _DOD_RF_LIST="$(dod_read_files "${1:-.}")"; return 0; }
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

# ── CC_DOD_LINEAGE_ONLY — inject only this session's own lineage (DEFAULT ON; =0 restores the old frame) ──
# ON BY DEFAULT since 2026-09-24 (token-efficiency wave 2, item 3; conviction 91%). Offline probe
# (docs/research/token-efficiency-2026-09-23/eval/wave2/dod-lineage-probe.md, 24 runs, blind-judged):
# with a pooled worktree's UNRELATED contract in the store, the old frame dragged it into the answer
# in 4 of 6 runs and lineage-only in 0 of 6, at equal success; with the worktree's OWN plan scope
# written by a session outside the lineage, lineage-only hid it and scored 5 of 6 on the plan-status
# task (T10's known baseline miss) against 6 of 6. In production 7 of 8 injected contracts were
# unrelated (measure/hooks.md §4). The pointer line still names the store for a session that wants it.
# The toplevel filter (dod_filter_for) separates WORKTREES, not sessions: every session started in one
# checkout shares its toplevel, and a capture with no provenance is kept rather than guessed at.
# Measured over 14 days, the injected "THE CURRENT CONTRACT" was one of 43 contracts, the top one shown
# to 248 sessions, and a hand check found 7 of 8 sampled sessions working on something unrelated
# (docs/research/token-efficiency-2026-09-23/measure/hooks.md §4 "Frozen DoD", §5 row 8). Under the
# flag a block is kept only when its header names a session of this LINEAGE (`· session=<sid>`,
# written by PreCompact and `set`) or names a toplevel that dod_lineage_ancestors lists as a RECORDED
# PREDECESSOR of this worktree (a fired or recycled-into-a-new-worktree wave inherits its predecessor,
# as the default filter already allows). The session lineage is this session plus the sessions that
# held this pane before it, read from the mailbox alias trail (mailbox_alias_trail, which
# mailbox-drain.sh appends at every boundary). That trail is what carries the /handoff capture
# (commands/handoff.md T-P4-4): the predecessor's `set` is stamped with ITS session id, and a
# same-pane recycle successor finds that id on the trail. Own-toplevel captures from other sessions,
# and captures with no provenance, are left out. When no block survives, the session gets a one-line
# pointer to the store instead of the text. The files are unchanged, and wrap-ledger and
# completion-assert read them directly, not this injection.
#
# Under the flag the write-side dedup (`set`, PreCompact) compares against this session's OWN
# captures instead of the worktree-filtered stream. Otherwise a session restating a scope that a
# sibling session in the same worktree had already captured would write nothing, and the injection
# above would then have nothing of its own to show after compaction.
_dod_nl="$(printf '\nx')"; _dod_nl="${_dod_nl%x}"
# One awk pass, not a bash `while read`: stdin here is always a PIPE, where bash's read consumes one
# byte per syscall, so the ~114 KB live store cost ~0.18s per call and SessionStart makes 2-3 calls
# (measured 2026-09-25; dod-persist was the heaviest SessionStart hook and hit its 5s timeout 66
# times in four days, which holds back every other SessionStart message). The id sets travel
# through the environment because they contain newlines, which `awk -v` would mangle. Byte
# semantics (LC_ALL=C) so the multibyte ' · ' separators match exactly as the bash patterns did,
# and every membership test is a literal index(), never a regex. `index(S, "\n" x "\n")` is the
# old `case "$S" in *"${nl}${x}${nl}"*`, including the empty-toplevel case the bash form matched.
_dod_lineage_blocks() {  # $1=lineage session ids  $2=predecessor toplevels (both newline-framed); stdin → kept blocks
  DOD_LB_SIDS="${1:-}" DOD_LB_PRED="${2:-}" LC_ALL=C awk '
    function field(line, key,    i, rest, j) {   # the value after the FIRST key, up to the next " · "
      i = index(line, key); if (!i) return ""
      rest = substr(line, i + length(key)); j = index(rest, " · ")
      return j ? substr(rest, 1, j - 1) : rest
    }
    BEGIN { sids = ENVIRON["DOD_LB_SIDS"]; pred = ENVIRON["DOD_LB_PRED"]; keep = 0 }
    # a second file'"'"'s header, when dod_read_content concatenates two stores: not part of the
    # block above it
    index($0, "# Durable frozen DoD") == 1 { keep = 0 }
    index($0, "## ") == 1 {
      keep = 0
      if (index($0, " · session=")) {
        s = field($0, " · session=")
        if (s != "" && index(sids, "\n" s "\n")) keep = 1
      }
      if (!keep && index($0, " · toplevel=")) {
        if (index(pred, "\n" field($0, " · toplevel=") "\n")) keep = 1
      }
    }
    keep { print }
  '
  return 0
}
# Lines outside every '## ' block, other than the file headers: a legacy boxes-only checklist or a
# pre-provenance scope. The lineage filter cannot attribute them, so it leaves them out and says so.
# The same pass also counts the '## ' header lines (`grep -c '^## '`), so the injection reads both
# numbers from one spawn.
_dod_head_and_unblocked_count() {  # stdin → "<headers> <unblocked>"
  awk '/^## / {h++}
       /^# Durable frozen DoD/ {inb=0; next}
       /^## / {inb=1; next}
       !inb && !/^#/ && NF {n++}
       END {print h+0, n+0}' 2>/dev/null || printf '0 0\n'
}
# This session plus the newest CC_DOD_LINEAGE_PANE_MAX (3) sessions that held this pane before it,
# newline-framed. Bounded because a pane can be reused for unrelated work over its life; the same
# bound as the mailbox's own pull-adoption (CC_MBX_ALIAS_MAX_PRED). No pane, no library, or no trail
# ⇒ this session alone. Prints one id per line; callers add the newline framing, since a command
# substitution strips the trailing one.
_dod_lineage_sids() {  # $1=own sid
  local pane lib max n=0 q
  [ -n "${1:-}" ] && printf '%s\n' "$1"
  pane="${CC_PANE_ID:-${ITERM_SESSION_ID:-}}"; pane="${pane##*:}"
  [ -n "$pane" ] || return 0
  if ! command -v mailbox_alias_trail >/dev/null 2>&1; then
    lib="$_dpd/lib/mailbox-pending.sh"
    [ -f "$lib" ] || lib="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/hooks/lib/mailbox-pending.sh"
    [ -f "$lib" ] || lib="$HOME/.claude/hooks/lib/mailbox-pending.sh"
    # shellcheck source=lib/mailbox-pending.sh
    # shellcheck disable=SC1090,SC1091
    [ -f "$lib" ] && . "$lib" 2>/dev/null
  fi
  command -v mailbox_alias_trail >/dev/null 2>&1 || return 0
  max="${CC_DOD_LINEAGE_PANE_MAX:-3}"; case "$max" in ''|*[!0-9]*) max=3 ;; esac
  while IFS= read -r q; do
    [ -n "$q" ] || continue
    [ "$q" = "${1:-}" ] && continue
    [ "$n" -ge "$max" ] && break
    printf '%s\n' "$q"; n=$((n + 1))
  done <<DODTRAIL
$(mailbox_alias_trail "$pane" 2>/dev/null || true)
DODTRAIL
  return 0
}
_dod_lineage_pred() {  # $1=cwd → recorded predecessor toplevels, one per line
  # strict predecessors only: line 1 of dod_lineage_ancestors is this worktree itself, whose other
  # sessions are exactly the captures this mode leaves out
  if command -v dod_lineage_ancestors >/dev/null 2>&1; then
    dod_lineage_ancestors "$1" | tail -n +2
  fi
  return 0
}
# The stream the write-side dedup compares against: this session's own captures under the flag (when
# the session id is known), the worktree-filtered stream otherwise.
_dod_dedup_stream() {  # $1=cwd  $2=file  $3=own sid
  if [ "${CC_DOD_LINEAGE_ONLY:-1}" = 1 ] && [ -n "${3:-}" ]; then
    dod_filter_for "$1" "$2" | _dod_lineage_blocks "${_dod_nl}${3}${_dod_nl}" "${_dod_nl}"
  else
    dod_filter_for "$1" "$2"
  fi
}
# ── injection budget: the newest captures that fit, newest FIRST ──
# Past Claude Code's 10,000-char cap a hook's additionalContext is swapped for a 2,000-char preview
# of its HEAD. Rendered oldest-first, that head held the frame and then the OLDEST captures, so the
# newest ones never reached the model: 26 of 26 lineage injections 2026-10-02..04 were over the cap,
# up to 58 KB (docs/research/claude-api-audit-2026-10-04/shard-hooks-a.md, hooks-a-11). The store
# keeps every capture; only the injection is cut, and its header says how many it shows.
# Order is by the '## <ISO ts>' header, not stream position: dod_read_content puts the repo-key store
# BEFORE this toplevel's legacy file, so reversing the stream would rank the legacy (older) captures
# newest. Lines outside any block (a legacy checklist or pre-provenance scope) form one unit that
# ranks oldest; file headers ('# …') are dropped. ALWAYS kept, whatever the budget: every capture
# newer than the newest one holding a 'Scope (frozen):' line (its 'Scope (grown):' growth extends
# the contract) and, at minimum, the newest capture. Older ones are added newest-first while they
# fit, stopping at the first that does not. Lengths are BYTES (LC_ALL=C), never fewer than chars.
# STRICT ($2=1, what both injections now use, with budget 0): the always-kept set WITHOUT the
# "at minimum the newest" floor when the newest capture is itself the newest frozen one. That capture
# is the contract the head already quotes, so the floor only repeated it: the newest history block
# restated THE CURRENT CONTRACT in 205 of 205 measured lineage injections
# (docs/research/startup-hooks-2026-10-18/A4-tokens.md § Skeptic verdicts, A4-R1).
_dod_newest_within() {  # $1=char budget for the history body  [$2=1 strict]; stdin → units, newest first, blank-separated
  DOD_NW_MAX="${1:-0}" DOD_NW_STRICT="${2:-0}" LC_ALL=C awk '
    BEGIN { max = ENVIRON["DOD_NW_MAX"] + 0; strict = (ENVIRON["DOD_NW_STRICT"] == "1"); n = 0; cur = 0; leg = ""; legfz = 0 }
    index($0, "## ") == 1 {
      n++; cur = n; key[n] = ($2 ~ /^[0-9]/) ? $2 : ""; txt[n] = $0; fz[n] = 0; next
    }
    index($0, "# ") == 1 { cur = 0; next }
    cur == 0 {
      if (NF) { leg = (leg == "") ? $0 : leg "\n" $0; if (index($0, "Scope (frozen):")) legfz = 1 }
      next
    }
    { txt[cur] = txt[cur] "\n" $0; if (index($0, "Scope (frozen):")) fz[cur] = 1 }
    END {
      if (leg != "") { n++; key[n] = ""; txt[n] = leg; fz[n] = legfz }
      if (n == 0) exit
      # stable insertion sort by timestamp; the legacy unit (empty key) ranks oldest
      for (i = 1; i <= n; i++) { sub(/(\n[ \t]*)+$/, "", txt[i]); ord[i] = i }
      for (i = 2; i <= n; i++) {
        v = ord[i]; j = i - 1
        while (j >= 1 && (key[ord[j]] "") > (key[v] "")) { ord[j + 1] = ord[j]; j-- }
        ord[j + 1] = v
      }
      fl = n
      for (i = n; i >= 1; i--) if (fz[ord[i]]) { fl = i + 1; break }
      if (fl > n && strict) exit
      if (fl > n) fl = n
      used = 0
      for (i = n; i >= fl; i--) used += length(txt[ord[i]]) + 2
      lo = fl
      for (i = fl - 1; i >= 1; i--) {
        if (used + length(txt[ord[i]]) + 2 > max) break
        used += length(txt[ord[i]]) + 2; lo = i
      }
      for (i = n; i >= lo; i--) { printf "%s", txt[ord[i]]; if (i > lo) printf "\n\n" }
      printf "\n"
    }
  '
  return 0
}
# HISTORY BECOMES A POINTER (docs/research/startup-hooks-2026-10-18/README.md §2 #5, A4-tokens.md R1).
# The optional older captures this used to fit under CC_DOD_INJECT_MAX_CHARS were ~4,180 of a mean
# 5,212 injected chars, re-read at every start, and only ever context: the binding part is the
# contract head plus the always-kept captures after it, which still arrive in full. Everything else
# is one line naming how many were left out and where to read them. The store keeps every capture,
# and wrap-ledger and completion-assert read the store, never this injection.
# $4 counts the captures the frame does not already quote: the one whose 'Scope (frozen):' line the
# lead quotes is shown there, so callers leave it out of the total.
_dod_frame_pointer() {  # $1=frame + lead  $2,$3=intro around the kept count  $4=total captures not quoted  $5=pointer after the omitted count; stdin → captures
  local shown nshow omit
  shown="$(_dod_newest_within 0 1)"
  nshow="$(printf '%s\n' "$shown" | grep -c '^## ' 2>/dev/null || true)"
  case "$nshow" in ''|*[!0-9]*) nshow=0 ;; esac
  omit=$(( ${4:-0} - nshow )); [ "$omit" -gt 0 ] || omit=0
  printf '%s\n\n' "$1"
  [ -n "$shown" ] && printf '%s%s%s\n\n%s\n\n' "$2" "$nshow" "$3" "$shown"
  printf 'History: %s%s' "$omit" "$5"
}
_dod_tilde() {  # $1=path → the same path with a leading $HOME shown as '~' (the pointer is read, not run)
  case "$1" in "$HOME"/*) printf '~%s' "${1#"$HOME"}" ;; *) printf '%s' "$1" ;; esac
}
# newest frozen line among the blocks one lineage admits, per source with the repo-key store first, as
# the default frame computes it
_dod_lineage_scope() {  # $1=cwd  $2=lineage session ids  $3=predecessor toplevels (both newline-framed)
  local f s=""
  while IFS= read -r f; do
    [ -n "$f" ] && [ -f "$f" ] || continue
    s="$(dod_filter_for "$1" "$f" | _dod_lineage_blocks "$2" "$3" | last_recorded_scope)"
    [ -n "$s" ] && break
  done <<LOSCOPEEOF
$(dod_read_files "$1")
LOSCOPEEOF
  printf '%s' "$s"
}
_dod_inject_lineage_only() {  # $1=cwd  $2=own sid  $3=content (already toplevel-filtered)
  local pred sids kept own cur pcur files f1 nall ncap nun unote framed _lead _pre _cnt
  if _dod_memo_hit "$1"; then   # the primed walk minus its first line: `tail -n +2` without the forks
    pred="$_dod_nl"
    case "$_DOD_M_ANC" in *"$_dod_nl"*) pred="${_dod_nl}${_DOD_M_ANC#*"$_dod_nl"}" ;; esac
    pred="${pred}${_dod_nl}"
  else
    pred="${_dod_nl}$(_dod_lineage_pred "$1")${_dod_nl}"
  fi
  sids="${_dod_nl}$(_dod_lineage_sids "$2")${_dod_nl}"
  kept="$(printf '%s\n' "$3" | _dod_lineage_blocks "$sids" "$pred")"
  _dod_read_files_var "$1"
  files="${_DOD_RF_LIST//"$_dod_nl"/ }"   # `paste -sd' '`
  _cnt="$(printf '%s\n' "$3" | _dod_head_and_unblocked_count)"
  nall="${_cnt%% *}"; nun="${_cnt##* }"
  case "$nall" in ''|*[!0-9]*) nall=0 ;; esac
  case "$nun" in ''|*[!0-9]*) nun=0 ;; esac
  unote=""
  [ "$nun" -gt 0 ] && unote=" ${nun} line(s) outside any capture block (a legacy checklist or pre-provenance scope) are left out too."
  if [ -z "$kept" ]; then
    # SHORT NOTICE (README §2 #5, A4 R2 option a): it was ~333 chars of explanation for "nothing is
    # injected", read 111 times in two days. What the session can act on is the count and the store,
    # so that is all it says: ≤100 chars on the live path. Lines outside any block (a legacy checklist)
    # count as one more capture, the unit _dod_newest_within also makes of them; the first file is the
    # repo-key store, where new captures go.
    f1="${_DOD_RF_LIST%%"$_dod_nl"*}"
    jq -nc --arg c "No DoD of this lineage; $(( nall + (nun > 0) )) other capture(s) in $(_dod_tilde "$f1")" \
      '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$c}}' 2>/dev/null || true
    return 0
  fi
  # PREDECESSOR CAPTURES NEVER BIND (README §2 #5 interim fix, A4-R1b skeptic verdict). The
  # predecessor-worktree rule is TRANSITIVE (26 ancestor toplevels measured for one worktree), so the
  # newest frozen line it admitted was, in >=120 of 205 lineage injections, an unrelated wave's
  # contract presented as "this is what binds you". The contract head and the always-kept captures
  # after it now come from this session's lineage alone (the session ids, no predecessor toplevels);
  # a predecessor's newest contract is shown, when this lineage has none, as prior context only.
  own="$(printf '%s\n' "$3" | _dod_lineage_blocks "$sids" "$_dod_nl")"
  _dod_checkpoint lineage
  # One read source (the usual case): $3 IS that source's filtered content, so the per-source scope
  # equals the newest frozen line of the blocks already in hand — `own` for the contract, `kept` for a
  # predecessor's — and re-filtering the store to find it again is skipped. Two sources keep the
  # per-source precedence (repo-key store first) through _dod_lineage_scope.
  case "$_DOD_RF_LIST" in
    *"$_dod_nl"*)
      cur="$(_dod_lineage_scope "$1" "$sids" "$_dod_nl")"
      pcur=""
      [ -n "$cur" ] || pcur="$(_dod_lineage_scope "$1" "$sids" "$pred")" ;;
    *)
      cur="$(printf '%s\n' "$own" | last_recorded_scope)"
      pcur=""
      [ -n "$cur" ] || pcur="$(printf '%s\n' "$kept" | last_recorded_scope)" ;;
  esac
  _dod_checkpoint scope
  ncap="$(printf '%s\n' "$kept" | grep -c '^## ' 2>/dev/null || true)"
  case "$ncap" in ''|*[!0-9]*) ncap=0 ;; esac
  if [ -n "$cur" ]; then
    _lead="THE CURRENT CONTRACT — this is what binds you, and every 'Scope (grown): +<item>' line extends it (Follow-On Gate F1-F4 PASS — already authorized, do NOT re-ask). Do NOT narrow it or declare done until ALL of it is met:

    $cur"
  else
    _lead="THE CURRENT CONTRACT is not recorded — this session's lineage has no 'Scope (frozen):' line yet. Treat anything below as context only, and freeze a scope before claiming completeness."
    [ -z "$pcur" ] || _lead="${_lead}

Prior context only, NOT binding — the newest contract of a recorded predecessor worktree (it is yours only if you freeze it as your own scope): ${pcur}"
  fi
  _pre="Durable frozen DoD for this session — re-injected across recycle and compaction as the completeness baseline.

$_lead"
  framed="$(printf '%s\n' "$own" | _dod_frame_pointer "$_pre" \
    "Below, newest first, in full: " " capture(s) of this session's lineage — every one newer than its newest 'Scope (frozen):' line, or the newest alone when it has none." \
    "$(( ncap - (${#cur} + ${#pcur} > 0) ))" " other capture(s) of this lineage (this session, a session that held this pane before it, or a recorded predecessor worktree) are not shown, and $(( nall - ncap )) from this worktree's other sessions or with no provenance are left out (CC_DOD_LINEAGE_ONLY=1).${unote} Read them in the store: ${files} (\`~/.claude/hooks/dod-persist.sh get\` prints this worktree's newest frozen line).")"
  command -v ss_owed >/dev/null 2>&1 && ss_owed $(( ${#framed} + 1 ))
  jq -nc --arg c "$framed" '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$c}}' 2>/dev/null || true
  return 0
}

# ── CLI modes ──
case "${1:-}" in
  set)
    scope="${2:-}"
    [ -n "$scope" ] || { printf 'usage: dod-persist.sh set "<Scope (frozen): DoD>"\n' >&2; exit 2; }
    case "$scope" in *"Scope (frozen):"*|*"Scope (grown):"*) ;; *) scope="Scope (frozen): $scope" ;; esac
    dod_prime "$PWD"
    f="$(dod_path_for "$PWD" write)"
    # The dedup compares against MY OWN last capture, not the file's. Unfiltered it would read a
    # concurrent sibling's identical scope as "unchanged", skip the write, and leave this wave with
    # no capture of its own — which the lineage filter would then correctly show as a BLANK
    # contract. Filtering here is what stops the crosstalk fix from manufacturing that hole.
    # Under CC_DOD_LINEAGE_ONLY=1 "my own" narrows to this session's captures (see the block above).
    if [ -f "$f" ] && [ "$scope" = "$(_dod_dedup_stream "$PWD" "$f" "${CLAUDE_CODE_SESSION_ID:-}" | last_recorded_scope)" ]; then
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
    dod_prime "$_gc"
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
IFS= read -r -d '' input || true   # the whole payload, without a `cat` fork (EOF ends the read)
# ONE jq for every payload field (README §2 #17; the mailbox-drain.sh one-parse pattern), split with
# parameter expansion rather than `read`, which would collapse an empty field between two tabs. A row
# that is not exactly one line of five fields, or that @tsv had to escape (a backslash), takes the old
# field-by-field parse, so an odd payload reads exactly as it always did.
_dod_tab="$(printf '\tx')"; _dod_tab="${_dod_tab%x}"
_row="$(printf '%s' "$input" | jq -r '[(.hook_event_name // ""), (.cwd // ""), (.session_id // ""), (.transcript_path // ""), (.trigger // "auto")] | @tsv' 2>/dev/null)" || _row=""
_tabs="${_row//[!$_dod_tab]/}"
case "$_row" in *"\\"*|*"$_dod_nl"*) _tabs="" ;; esac
if [ "${#_tabs}" -eq 4 ]; then
  event="${_row%%"$_dod_tab"*}"; _row="${_row#*"$_dod_tab"}"
  cwd="${_row%%"$_dod_tab"*}"; _row="${_row#*"$_dod_tab"}"
  sid="${_row%%"$_dod_tab"*}"; _row="${_row#*"$_dod_tab"}"
  tp="${_row%%"$_dod_tab"*}"; trigger="${_row#*"$_dod_tab"}"
else
  event="$(printf '%s' "$input" | jq -r '.hook_event_name // empty' 2>/dev/null || true)"
  cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null || true)"
  sid="$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null || true)"
  tp="$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null || true)"
  trigger="$(printf '%s' "$input" | jq -r '.trigger // "auto"' 2>/dev/null || echo auto)"
fi
[ -n "$cwd" ] || cwd="$PWD"
# per-capture provenance: the hook payload is authoritative; the env is the fallback (a hook runs as a
# child of the session it belongs to). Empty when neither knows — the field is then OMITTED, never
# emitted blank, so a reader can distinguish "no session recorded" from "session recorded as nothing".
_ss_sid="$sid"   # the startup sentinel keys on the PAYLOAD's id only, never the env fallback
[ -n "$sid" ] || sid="${CLAUDE_CODE_SESSION_ID:-}"

case "$event" in
  SessionStart)
    # Start/done markers, so a harness cancel of this hook is reportable (hooks/lib/startup-sentinel.sh;
    # docs/research/startup-hooks-2026-10-18/README.md §5 unit 3.1). 5000 ms = its registration timeout.
    # No transcript path: this hook's parse does not read it, and the sentinel takes it from the first
    # writer that has one. Owed = the injected context, set just before each emit below.
    if [ -f "$_dpd/lib/startup-sentinel.sh" ]; then
      # shellcheck source=lib/startup-sentinel.sh disable=SC1091  # runtime-resolved beside this file
      . "$_dpd/lib/startup-sentinel.sh" 2>/dev/null && ss_begin dod-persist 5000 "$_ss_sid"
    fi
    # W3: inject BOTH read sources (repo-key store first, then this toplevel's legacy) — the
    # lossless half of the migration: per-toplevel history keeps injecting exactly where it always
    # did, while every worktree of the repo now shares the repo-key captures.
    # LINEAGE-FILTERED (row 4de3d0f9c0e1, prerequisite 2). The repo key is byte-equal across every
    # worktree of the repo, so this used to hand a session every CONCURRENT wave's contract too —
    # 101 worktrees, 15 distinct frozen scopes, and no input existed to tell them apart. There is
    # one now: dod_read_content keeps this wave's captures and its recorded predecessors', drops a
    # foreign wave's, and keeps anything unattributable (see hooks/lib/dod-path.sh § FAIL-OPEN).
    _dod_mark parse
    trap '_dod_finish $?' EXIT
    dod_prime "$cwd"
    _dod_checkpoint prime
    content="$(dod_read_content "$cwd")"
    if [ -z "$content" ]; then _DOD_NEXT_PHASE="read"; _DOD_OUTCOME="empty"; exit 0; fi
    _dod_checkpoint read
    if [ "${CC_DOD_LINEAGE_ONLY:-1}" = 1 ]; then
      _dod_inject_lineage_only "$cwd" "$sid" "$content"
      exit 0
    fi
    # NEWEST-WINS FRAME (docs/research/dod-crosstalk-2026-08-18.md §2, §5 adjacent finding). This
    # used to declare "Every 'Scope (frozen):' line below is binding … do NOT narrow scope or
    # declare done until ALL of it is met" over the WHOLE file. The store is repo-KEYED, so that
    # file is shared by every worktree of the repo — 101 of them here, 15 distinct frozen scopes —
    # and the claim was therefore false for all but one: a session was handed concurrent and
    # finished waves' contracts as its own, every SessionStart, and could not tell them apart.
    # It also contradicted THIS SCRIPT: `get` and last_recorded_scope both already return the
    # NEWEST frozen line only. The frame now says what the rest of the store has always meant.
    # The history is reframed as context rather than dropped, and the store keeps all of it; the
    # injection carries every capture after the newest frozen one in full (_dod_newest_within strict,
    # same rule as above) and names the rest in a one-line pointer (_dod_frame_pointer,
    # docs/research/startup-hooks-2026-10-18/README.md §2 #5).
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
      _lead="THE CURRENT CONTRACT is not recorded — no 'Scope (frozen):' line exists in this store yet. Treat anything below as context only, and freeze a scope before claiming completeness."
    fi
    _files="$(dod_read_files "$cwd" | paste -sd' ' - 2>/dev/null)"
    _pre="Durable frozen DoD for this worktree — re-injected across recycle and compaction as the completeness baseline.

$_lead"
    framed="$(printf '%s\n' "$content" | _dod_frame_pointer "$_pre" \
      "Below, newest first, in full: " " capture(s) of this worktree — every one newer than its newest 'Scope (frozen):' line, or the newest alone when it has none. Each '## ' block names the toplevel that wrote it." \
      "$(( ncap - (${#cur} > 0) ))" " other capture(s) of this wave's INTEGRATE-only history, from its own worktree and its RECORDED PREDECESSORS, are not shown. They are prior CONTEXT, NOT additional binding scope — a predecessor's finished contract is not yours to complete. A concurrent wave's captures are filtered out mechanically. Read them in the store: ${_files} (\`~/.claude/hooks/dod-persist.sh get\` prints this worktree's newest frozen line).")"
    command -v ss_owed >/dev/null 2>&1 && ss_owed $(( ${#framed} + 1 ))
    jq -nc --arg c "$framed" '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$c}}' 2>/dev/null || true
    exit 0 ;;
  PreCompact)
    case "$tp" in "~"*) tp="$HOME${tp#\~}" ;; esac
    { [ -n "$tp" ] && [ -f "$tp" ]; } || exit 0
    dod_prime "$cwd"
    f="$(dod_path_for "$cwd" write)"
    scope="$(extract_scope "$tp")"
    if [ -n "$scope" ]; then
      # filtered, for the same reason `set` is: an identical scope frozen by a CONCURRENT wave must
      # not read as "already recorded" and leave this wave with no capture of its own (narrowed to this
      # session's captures under CC_DOD_LINEAGE_ONLY=1)
      if ! { [ -f "$f" ] && [ "$scope" = "$(_dod_dedup_stream "$cwd" "$f" "$sid" | last_recorded_scope)" ]; }; then
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
        _gseen="$(_dod_dedup_stream "$cwd" "$f" "$sid" | grep -cF -- "$g" 2>/dev/null || true)"
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
