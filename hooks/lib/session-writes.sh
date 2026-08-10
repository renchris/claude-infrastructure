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
# ── TWO SCOPES, AND PICKING THE WRONG ONE FAILS LOUD ─────────────────────────────────────────────
# The two arms above ask questions with DIFFERENT time spans, and for a year this file offered only
# the wider one:
#
#   arm (B) mechanical 🔧 asks a SESSION question — "is any file I wrote, at any point, still
#     uncommitted?". Bounding that to the current turn would un-arm it the moment the session had
#     one conversational turn, silently, in the unsafe direction. `session_writes_paths` /
#     `session_dirty_mine` keep that span and MUST NOT be narrowed.
#   arm (A) the close certificate asks a TURN question — protocol E0 suppresses the readout on a
#     read-only TURN. Answering it with the session-scoped oracle is the defect fixed here
#     (2026-08-08): once a session performed a single edit, EVERY later Stop read rc 0 — including
#     a purely conversational close — so the certificate degraded to fire-always, which is the
#     alarm-polarity failure it was built to avoid. Measured before the fix on a two-turn fixture
#     whose last turn was pure conversation: `✅ SAFE TO CLOSE` rendered on 4 of 4 consecutive
#     closes. Undamped, too — the certificate `exit 0`s ahead of operator-readout's latch write, so
#     nothing throttled the repeat.
#
# `session_writes_paths_turn` / `session_wrote_here_this_turn` are the turn-scoped pair. The old
# boolean `session_wrote_files` was DELETED rather than left beside them: its name reads like a
# turn question, it had exactly one caller, and that caller was the bug. A removed name fails loud
# (`command not found` ⇒ rc 127 ⇒ no arm matches ⇒ conservative), where a retained one fails by
# being picked again.
#
# Pure function definitions only — no side effects on source (safe under `set -u`).

# Bound every read: this runs from a Stop hook on every turn close, and a wedged read must never
# hold the close open. No `timeout` on PATH ⇒ run unbounded rather than lose the signal (mirrors
# scripts/wrap-ledger.sh:140).
_sw_bounded() { local s="$1"; shift
  if command -v timeout >/dev/null 2>&1; then timeout "$s" "$@"; else "$@"; fi
}

# _sw_paths <transcript_path> <true|false turn-bounded>
#   The ONE reader. Both public scopes delegate here so the file-edit tool list can never diverge
#   between them — a turn oracle that recognised three of the four write tools would fail in the
#   loud direction and look identical to the session one at a glance.
_sw_paths() {
  local tp="${1:-}" turn="${2:-false}" out rc
  command -v jq >/dev/null 2>&1 || return 2
  case "$tp" in "~"*) tp="$HOME${tp#\~}" ;; esac
  [ -n "$tp" ] && [ -f "$tp" ] || return 2

  # `.input.edits` (MultiEdit) still carries the target in `.input.file_path`, so one selector
  # covers all four tools. `-n` + `reduce inputs` streams the file exactly as the previous filter
  # did (lazy, constant-ish memory, deliberately NOT `jq -s`) while carrying the one piece of state
  # a turn boundary needs: reset the accumulator when a new turn starts.
  #
  # WHAT COUNTS AS A TURN BOUNDARY — a main-chain `user` record that carries no `tool_result`.
  # A tool_result-bearing user record is the harness feeding a tool's output back INSIDE the turn,
  # so it must not reset; a string-content or text-content one is a fresh input to the model.
  # Two deliberate calls, both in the withhold-the-certificate (safe) direction:
  #   · `isMeta` records COUNT as boundaries. Slash-command bodies and Stop-hook `decision:block`
  #     feedback both arrive that way and both genuinely start a new turn. Where one does not
  #     (an `[Image: …]` attachment landing at the same timestamp as its prompt) the extra reset is
  #     harmless, because it lands before any assistant work in that turn.
  #   · SIDECHAIN user records never reset. A subagent's prompt is not a main-turn boundary, and
  #     letting it reset would drop main-chain writes that preceded the subagent. Sidechain WRITES
  #     still count, exactly as in session scope (the invariant pinned above).
  # Records that are neither `user` nor `assistant` (attachment, system, last-prompt, …) pass
  # through untouched — they are transcript bookkeeping, not turns.
  # SC2016 disabled for the filter body only: `$r` and `$turn` are jq bindings (`reduce … as $r`,
  # `--argjson turn`), so shell expansion is exactly what must NOT happen. ship-land runs
  # `shellcheck` bare, where an info is a hard RED, so this is load-bearing rather than tidy.
  # shellcheck disable=SC2016
  out="$(_sw_bounded "${SESSION_WRITES_TIMEOUT_S:-5}" jq -rn --argjson turn "$turn" '
      reduce inputs as $r ([];
        if $turn and ($r.type=="user") and ($r.isSidechain != true)
           and ( (($r.message.content|type) != "array")
                 or (([$r.message.content[] | select(.type=="tool_result")] | length) == 0) )
        then []
        elif $r.type=="assistant"
        then . + [ $r.message.content[]?
                   | select(.type=="tool_use")
                   | select(.name|test("^(Write|Edit|MultiEdit|NotebookEdit)$"))
                   | (.input.file_path // .input.notebook_path // empty)
                   | select(. != "") ]
        else . end)
      | .[]
    ' "$tp" 2>/dev/null)"; rc=$?
  # A non-zero jq exit means the read FAILED — that is cannot-tell, never "no writes". Getting this
  # branch wrong is how an unreadable transcript would silently certify a close as safe.
  [ "$rc" -eq 0 ] || return 2
  out="$(printf '%s' "$out" | sort -u)"
  [ -n "$out" ] || return 1
  printf '%s\n' "$out"
  return 0
}

# session_writes_paths <transcript_path>
#   SESSION scope — every file this session wrote, at any point.
#   stdout: absolute paths, one per line, de-duplicated.
#   rc: 0 wrote · 1 none · 2 cannot-tell   (see THREE STATES above)
#   This is the span arm (B) needs. Do NOT narrow it (see TWO SCOPES above).
session_writes_paths() { _sw_paths "${1:-}" false; }

# session_writes_paths_turn <transcript_path>
#   TURN scope — only the files written since the last main-chain user input.
#   rc: 0 wrote · 1 none · 2 cannot-tell
session_writes_paths_turn() { _sw_paths "${1:-}" true; }

# _sw_canon <path>
#   The transcript records a path as the tool was GIVEN it (logical); git and the filesystem answer
#   physically. Resolves the DIRECTORY and re-appends the basename, so a path whose file was just
#   deleted still canonicalises (its parent almost always survives). An unresolvable dir falls back
#   to the raw path: a miss, never a false hit.
_sw_canon() {
  local p="${1:-}" d b phys
  [ -n "$p" ] || return 1
  d="$(dirname "$p")"; b="$(basename "$p")"
  phys="$(cd "$d" 2>/dev/null && pwd -P 2>/dev/null)"
  if [ -n "$phys" ]; then printf '%s/%s\n' "$phys" "$b"; else printf '%s\n' "$p"; fi
}

# session_wrote_here_this_turn <transcript_path> [repo_dir]
#   The close certificate's question, in full: "did this session write a file THIS TURN, inside the
#   tree this close is about?"  rc: 0 yes · 1 no · 2 cannot-tell
#
#   WHY THE REPO ARGUMENT EXISTS. The certificate's every other fact comes from a ledger computed
#   for `cwd`; the write-turn gate was the one input scoped to the whole machine, so a session could
#   certify a close about tree X on the strength of writes that all landed somewhere else. Measured
#   2026-08-03 on session 7868b45e (cwd = the claude-infrastructure checkout): six written paths,
#   five under an unrelated worktree and one in a /tmp scratchpad, NONE in cwd — yet the gate read
#   rc 0. Scratchpad writes are the same class: protocol E0 turns on TRACKED writes, and a /tmp file
#   is not tracked work in any tree.
#
#   Passing no repo_dir keeps the turn bound and drops the location bound — the honest answer when
#   the caller has no tree in mind. A repo_dir that will not resolve is rc 2, never an unscoped
#   fallback: silently widening a gate that was asked to narrow is how one arrives back here.
session_wrote_here_this_turn() {
  local tp="${1:-}" dir="${2:-}" mine rc top p c
  mine="$(session_writes_paths_turn "$tp")"; rc=$?
  [ "$rc" -eq 0 ] || return "$rc"
  [ -n "$dir" ] || return 0

  command -v git >/dev/null 2>&1 || return 2
  top="$(cd "$dir" 2>/dev/null && _sw_bounded 5 git rev-parse --show-toplevel 2>/dev/null)" || return 2
  [ -n "$top" ] || return 2
  top="$(cd "$top" 2>/dev/null && pwd -P 2>/dev/null)" || return 2
  [ -n "$top" ] || return 2

  while IFS= read -r p; do
    [ -n "$p" ] || continue
    c="$(_sw_canon "$p")"
    # `"$top"` is quoted inside the pattern so a path containing glob metacharacters stays literal.
    case "$c" in "$top"/*) return 0 ;; esac
  done <<EOF
$mine
EOF
  return 1
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

  # Canonicalise the transcript side to match git's physical spelling — see `_sw_canon`, which is
  # shared with the certificate's repo filter so the two can never disagree about what one path is.
  # No associative-array memo — macOS ships bash 3.2, and the written-path set is small and already
  # de-duplicated, so a subshell per path is cheaper than a portability problem.
  local _p mine_c=""
  while IFS= read -r _p; do
    [ -n "$_p" ] || continue
    mine_c="${mine_c}$(_sw_canon "$_p")"$'\n'
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

# session_unlanded_mine <transcript_path> <repo_dir> <trunk_ref>
#   The commit-side twin of session_dirty_mine (CLOSE_INTEGRITY W2b): do the commits ahead of
#   <trunk_ref> touch anything THIS session wrote?  rc: 0 mine · 1 not mine · 2 cannot-tell.
#
#   EXTRACTED from hooks/completion-assert.sh's `_ca_mine unlanded` branch — verbatim algorithm —
#   because session-continue's ship floor asks the SAME question, and two inline copies of a
#   load-bearing intersection is how they rot apart (the third-copy trap agent-identity.sh names).
#   The canonicalisation story from that branch holds here and is load-bearing, not tidy:
#   `git rev-parse --show-toplevel` answers PHYSICALLY, the transcript records paths LOGICALLY
#   (macOS /tmp→/private/tmp; this repo's live layer is symlinks), so both sides go through
#   _sw_canon or the intersection reads empty FOREVER — a fail-GREEN defect only the "a commit this
#   session DID write must still convict" control catches.
session_unlanded_mine() {
  local tp="${1:-}" dir="${2:-}" trunk="${3:-}" out rc top f
  [ -n "$trunk" ] || return 2
  command -v git >/dev/null 2>&1 || return 2
  out="$(session_writes_paths "$tp")"; rc=$?
  [ "$rc" -eq 2 ] && return 2
  [ "$rc" -eq 1 ] && return 1
  top="$(cd "$dir" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null)" || return 2
  [ -n "$top" ] || return 2
  top="$(cd "$top" 2>/dev/null && pwd -P 2>/dev/null || printf '%s' "$top")"
  local _p canon=""
  while IFS= read -r _p; do
    [ -n "$_p" ] || continue
    canon="${canon}$(_sw_canon "$_p")"$'\n'
  done <<EOF
$out
EOF
  out="$canon"
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    printf '%s\n' "$out" | grep -qxF "$top/$f" && return 0
  done <<EOF
$( cd "$top" 2>/dev/null && _sw_bounded 5 git diff --name-only "$trunk"..HEAD 2>/dev/null )
EOF
  return 1
}
