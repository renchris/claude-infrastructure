#!/usr/bin/env bash
# session-writes.sh — SSOT oracle: "which tracked files did THIS session write?"
#
# WHY IT EXISTS. Two Stop-hook arms need the same fact and neither could get it:
#
#   (A) operator-readout's affirmative close certificate must render on a WRITE turn and stay
#       silent on a read-only one. A certificate that fires at every close carries exactly as many
#       bits as one that never fires (MEMORY.md alarm-polarity-and-attention-budget).
#   (B) session-continue's MECHANICAL 🔧 arm must distinguish "I left my own work uncommitted"
#       from "a sibling session dirtied the shared checkout". Without that split it would loop
#       forever on someone else's dirt — the infinite-loop-wearing-diligence's-clothes case
#       CLAUDE.md § Session Close names by name, and the live defect already filed as task #105
#       ("completion-assert convicts worktree sessions for a sibling's dirty tree").
#
# THE SOURCE IS THE TRANSCRIPT, NOT A NEW STORE. The Stop payload already carries
# `transcript_path`, and every Write/Edit/MultiEdit/NotebookEdit tool_use in it records the path it
# wrote. So this needs no PostToolUse hook, no per-edit cost, no state file to go stale, and it is
# session-scoped and crash-proof by construction. Measured 2026-08-01: 66 ms over a 10 MB
# transcript; fleet median transcript is 0.2 MB, p95 2.0 MB, max 33.9 MB.
#
# ── THREE STATES, NEVER TWO ──────────────────────────────────────────────────────────────────────
#   rc 0  wrote      — at least one file-edit tool_use; paths on stdout
#   rc 1  none       — the transcript read cleanly and contains no file-edit tool_use
#   rc 2  cannot-tell— no jq / no transcript / read error / timeout
# A lookup that fails can only MISS, and a miss is not an absence (MEMORY.md lookup-miss-is-not-
# absence). Callers MUST branch on all three; both current callers treat rc 2 as "do nothing",
# which is the conservative direction for each — (A) renders no certificate rather than asserting
# safe-to-close on an unknown, and (B) blocks no stop rather than forcing a loop on ignorance.
#
# ── KNOWN COVERAGE RESIDUE (named, not silently absorbed) ────────────────────────────────────────
# A file written ONLY through Bash (`sed -i`, a heredoc, `git checkout`) is invisible here — the
# transcript records the command, not its filesystem effect, and parsing shell to find writes is
# the prescribed-remedy-worse-than-the-bug class. Both consumers degrade SAFELY on that miss:
# (A) withholds a certificate it cannot justify, (B) declines to force a continuation. Neither
# fails loud, so this residue costs coverage, never correctness.
#
# Sidechain (subagent) records are DELIBERATELY INCLUDED: a subagent's edit is this session's
# write, and excluding it would attribute the session's own dirt to nobody.
#
# Pure function definitions only — no side effects on source (safe under `set -u`).

# Bound every read: this runs from a Stop hook on every turn close, and a wedged read must never
# hold the close open. No `timeout` on PATH ⇒ run unbounded rather than lose the signal (mirrors
# scripts/wrap-ledger.sh:140).
_sw_bounded() { local s="$1"; shift
  if command -v timeout >/dev/null 2>&1; then timeout "$s" "$@"; else "$@"; fi
}

# session_writes_paths <transcript_path>
#   stdout: absolute paths written this session, one per line, de-duplicated.
#   rc: 0 wrote · 1 none · 2 cannot-tell   (see THREE STATES above)
session_writes_paths() {
  local tp="${1:-}" out rc
  command -v jq >/dev/null 2>&1 || return 2
  case "$tp" in "~"*) tp="$HOME${tp#\~}" ;; esac
  [ -n "$tp" ] && [ -f "$tp" ] || return 2

  # `.input.edits` (MultiEdit) still carries the target in `.input.file_path`, so one selector
  # covers all four tools. A record that fails to parse is skipped by jq rather than aborting the
  # slurp — this is a line-delimited stream, deliberately NOT `jq -s`.
  out="$(_sw_bounded "${SESSION_WRITES_TIMEOUT_S:-5}" jq -r '
      select(.type=="assistant")
      | .message.content[]?
      | select(.type=="tool_use")
      | select(.name|test("^(Write|Edit|MultiEdit|NotebookEdit)$"))
      | (.input.file_path // .input.notebook_path // empty)
      | select(. != "")
    ' "$tp" 2>/dev/null)"; rc=$?
  # A non-zero jq exit means the read FAILED — that is cannot-tell, never "no writes". Getting this
  # branch wrong is how an unreadable transcript would silently certify a close as safe.
  [ "$rc" -eq 0 ] || return 2
  out="$(printf '%s' "$out" | sort -u)"
  [ -n "$out" ] || return 1
  printf '%s\n' "$out"
  return 0
}

# session_wrote_files <transcript_path>
#   Boolean form of the above, for callers that need only the write-turn question.
#   rc: 0 wrote · 1 none · 2 cannot-tell
session_wrote_files() {
  local rc
  session_writes_paths "${1:-}" >/dev/null 2>&1; rc=$?
  return $rc
}

# session_dirty_mine <transcript_path> [repo_dir]
#   The intersection that arm (B) turns on: tracked paths that are BOTH dirty in the work tree AND
#   written by this session. stdout = repo-relative paths, one per line.
#   rc: 0 non-empty · 1 empty (nothing of mine is dirty) · 2 cannot-tell
#
#   Porcelain parsing, deliberately explicit about the two shapes that bite:
#     · a rename prints `R  old -> new` — the NEW path is the one on disk;
#     · a path with a space/quote is emitted QUOTED by git. `core.quotePath=false` plus -z gives
#       NUL-delimited, unquoted, literal paths, which removes both failure modes at the source
#       rather than by unescaping after the fact.
#
#   BOTH SIDES ARE CANONICALISED BEFORE COMPARISON, and that is load-bearing rather than tidy.
#   `git rev-parse --show-toplevel` answers with the PHYSICAL path, while the transcript records the
#   path as the tool was given it — the LOGICAL one. On any symlinked checkout the two spellings of
#   one file never compare equal, so the intersection reads empty forever and this whole arm goes
#   silently inert. That is not hypothetical here: /tmp is a symlink to /private/tmp on macOS (which
#   is how this surfaced), and this repo's entire live layer is symlinks into the checkout. The
#   failure mode is the dangerous polarity — it fails GREEN (no false continuation, just permanent
#   silence), so nothing would ever have reported it.
session_dirty_mine() {
  local tp="${1:-}" dir="${2:-$PWD}" mine top rc
  command -v git >/dev/null 2>&1 || return 2

  mine="$(session_writes_paths "$tp")"; rc=$?
  [ "$rc" -eq 2 ] && return 2
  [ "$rc" -eq 1 ] && return 1

  top="$(cd "$dir" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null)" || return 2
  [ -n "$top" ] || return 2

  # Canonicalise the transcript side to match git's physical spelling. Resolves the DIRECTORY and
  # re-appends the basename, so a path whose file was DELETED this turn still canonicalises (its
  # parent almost always survives) — a deletion is exactly the dirt this arm must not miss.
  # An unresolvable dir falls back to the raw path: a miss, never a false hit.
  # No associative-array memo — macOS ships bash 3.2, and the written-path set is small and already
  # de-duplicated, so a subshell per path is cheaper than a portability problem.
  local _p _d _b _phys mine_c=""
  while IFS= read -r _p; do
    [ -n "$_p" ] || continue
    _d="$(dirname "$_p")"; _b="$(basename "$_p")"
    _phys="$(cd "$_d" 2>/dev/null && pwd -P 2>/dev/null)"
    if [ -n "$_phys" ]; then mine_c="${mine_c}${_phys}/${_b}"$'\n'
    else mine_c="${mine_c}${_p}"$'\n'; fi
  done <<EOF
$mine
EOF
  mine="$mine_c"

  # -z: NUL-delimited records, each `XY<space>path`; a rename/copy emits `XY<space>NEW<NUL>OLD<NUL>`,
  # i.e. the OLD path arrives as its own bare record with NO status prefix.
  #
  # -uall IS LOAD-BEARING, not tidiness (2026-08-02). git's DEFAULT untracked mode collapses a wholly
  # untracked directory to a single directory record — `?? src/` — instead of the files inside it. The
  # intersection below compares FILE paths, so a session that created `src/mine.ts` in a NEW directory
  # matched nothing and was reported as "nothing of mine is dirty". That is the FALSE-GREEN direction:
  # it EXONERATES a session that really did leave its own uncommitted work, which is precisely the
  # difference between this oracle working and this oracle being disabled (the R3 positive control).
  # Creating a file in a new directory is ordinary — a new docs/ subdir, a new fixture dir — so this
  # was not an edge case, and like every other failure mode in this file it fails silently green.
  #
  # THE OUTPUT GOES TO A FILE, NEVER A VARIABLE. Command substitution strips NUL bytes, so
  # `porc="$(git status -z)"` silently concatenates every record into one string and the
  # intersection below reads empty forever — a defect that fails GREEN (no false continuation,
  # just permanent silence) and would therefore never have surfaced on its own.
  local tmpf
  tmpf="$(mktemp "${TMPDIR:-/tmp}/sw-porc.XXXXXX" 2>/dev/null)" || return 2
  if ! ( cd "$top" 2>/dev/null && _sw_bounded 5 git -c core.quotePath=false status --porcelain -z -uall ) >"$tmpf" 2>/dev/null; then
    rm -f "$tmpf" 2>/dev/null; return 2
  fi

  local hit=0 rel abs rec skip_next=0
  while IFS= read -r -d '' rec; do
    [ -n "$rec" ] || continue
    # Consume a rename/copy's trailing OLD-path record explicitly rather than letting the 3-char
    # strip mangle it into a near-path that "probably" matches nothing.
    if [ "$skip_next" -eq 1 ]; then skip_next=0; continue; fi
    case "$rec" in [RC]*) skip_next=1 ;; esac
    rel="${rec:3}"                     # strip the 2-char status + its separating space
    [ -n "$rel" ] || continue
    abs="$top/$rel"
    # Compare on the ABSOLUTE path: the transcript records absolute paths, porcelain records
    # repo-relative ones, and comparing the two forms directly is how an intersection silently
    # reads empty forever.
    if printf '%s\n' "$mine" | grep -qxF "$abs"; then
      printf '%s\n' "$rel"; hit=1
    fi
  done < "$tmpf"
  rm -f "$tmpf" 2>/dev/null
  [ "$hit" -eq 1 ] && return 0
  return 1
}
