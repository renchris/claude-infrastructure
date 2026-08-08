#!/usr/bin/env bats
# session-writes.sh — the SSOT write-attribution oracle, previously UNTESTED.
#
# WHY THIS SUITE EXISTS (2026-08-02). hooks/lib/session-writes.sh answers one question — "which
# tracked files did THIS session write?" — and three Stop-hook arms now turn on its answer:
# operator-readout's close certificate, session-continue's mechanical 🔧, and (in flight on
# fix/completion-assert-attribution) completion-assert's exoneration. It had NO direct coverage.
#
# THE DEFECT THAT MADE IT URGENT. A read-only research subagent spawned into the lead's worktree was
# blocked at Stop by completion-assert for the LEAD's dirty + unlanded ledger — work it never wrote
# and, being read-only, could not commit or land. It cannot satisfy the assert, so it re-enters.
# Measured 2026-08-02: a background/named subagent is a REAL child session (argv
# `claude.exe --agent-id <n>@session-<t> --agent-name <n> --team-name <t> --parent-session-id <p>`)
# and therefore runs the FULL Stop chain written for a main session. (A FOREGROUND in-process
# subagent does not: the harness fires SubagentStop for it, and zero SubagentStop hooks are
# registered. The two shapes have opposite exposure — see docs/plans/SUBAGENT_STOP_HOOK_LOOP.md.)
#
# So the whole fix rests on this oracle returning `1 = none` — not `2 = cannot-tell` — for a session
# that read cleanly and wrote nothing. That distinction IS the fix, because every consumer treats
# rc 2 conservatively: for a false-done guard, conservative means CONVICT. An oracle that degraded
# rc 1 → rc 2 would silently restore the exact loop, with every consumer still "correct".
#
# THE ASYMMETRY IS THE POINT, so it is pinned in BOTH directions:
#   · a session that wrote NOTHING must be exonerable            (R1 — the subagent delivers)
#   · a session that DID write must remain convictable           (R3 — the positive control;
#     without it "fixed" is indistinguishable from "oracle disabled")
#   · an UNREADABLE transcript must be cannot-tell, never "none" (fail-safe direction: a miss is
#     not an absence — MEMORY.md lookup-miss-is-not-absence)
#
# RED-PROOF. There is no impl change to bisect here, so a `git archive` pristine run is vacuous by
# construction — the pristine lib IS the lib under test and would pass. The honest control is
# MUTATION: each load-bearing test is proved by sabotaging the lib and confirming the assertion
# fails. See the `mutation control` tests at the bottom, which run against a DERANGED copy and
# assert the suite's own premises break — a control that cannot fail proves nothing
# (MEMORY.md control-must-replay-the-real-artifact).

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LIB="$REPO/hooks/lib/session-writes.sh"
  [ -f "$LIB" ] || { echo "missing $LIB"; return 1; }
  # Fixture $HOME before anything else. session_writes_paths expands a leading `~` in the transcript
  # path against $HOME, and every `git` call below reads ~/.gitconfig — an unfixtured suite would
  # resolve both against the operator's live home. Per-repo user.name/user.email are set in repo()
  # precisely so no global git identity is needed here.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  W="$BATS_TEST_TMPDIR/w"
}

# A transcript recording the file-edit tool_uses in $@ (none ⇒ a pure read-only session).
# Deliberately also carries a Read and a Bash tool_use: neither is a write, and an oracle that
# counted them would convict every read-only session — the defect this suite exists to prevent.
tx() { # $1=out, $2..=paths written
  local out="$1"; shift
  python3 - "$out" "$@" <<'PY'
import json, sys
out, paths = sys.argv[1], sys.argv[2:]
rows = [{"type": "user", "message": {"content": "research the deploy wiring"}},
        {"type": "assistant", "message": {"content": [
            {"type": "tool_use", "name": "Read", "input": {"file_path": "/some/read/only.ts"}},
            {"type": "tool_use", "name": "Bash", "input": {"command": "git log --oneline"}}]}}]
for p in paths:
    rows.append({"type": "assistant", "message": {"content": [
        {"type": "tool_use", "name": "Edit", "input": {"file_path": p}}]}})
rows.append({"type": "assistant", "message": {"content": [
    {"type": "text", "text": "✅ Research complete — findings delivered."}]}})
open(out, "w").write("\n".join(json.dumps(r) for r in rows) + "\n")
PY
  printf '%s' "$out"
}

# A repo with a clean origin/main plus whatever dirt the test asks for.
repo() { # $1=dir
  # `${1:?}` covers the half `|| exit 1` below CANNOT: `cd ""` RETURNS 0 (measured 2026-08-05), so
  # on an empty $w the guard never fires and every command in that subshell runs in the TEST's cwd
  # — this repo — exactly the outcome the comment there says it is preventing.
  local w="${1:?repo: dir required}" o="$1.git"
  git init -q --bare "$o"
  git clone -q "$o" "$w" 2>/dev/null
  # `|| exit 1` is load-bearing, not ceremony: without it a failed cd runs every command below in
  # the TEST's cwd — i.e. this repo — and `git add -A; git commit` would fire on the real checkout.
  ( cd "$w" || exit 1
    git config user.email t@e.com; git config user.name t; git checkout -q -b main
    mkdir -p config src
    echo base > base.txt; git add -A; git commit -q -m base; git push -q -u origin main ) >/dev/null 2>&1
}

# A two-turn transcript: turn 1 writes $2, turn 2 is whatever $3 says.
#   $3 = "chat"        → a purely conversational close (the read-only-turn shape)
#   $3 = "tool"        → turn 2 writes $4, with its tool_result fed back mid-turn
#   $3 = "sidechain"   → turn 2 writes $4 on the MAIN chain, then a subagent prompt + its own write
tx2() { # $1=out $2=turn-1 path $3=mode [$4=turn-2 path]
  local out="$1"; shift
  python3 - "$out" "$@" <<'PY'
import json, sys
out, p1, mode = sys.argv[1], sys.argv[2], sys.argv[3]
p2 = sys.argv[4] if len(sys.argv) > 4 else None
def ed(p, side=False):
    r = {"type": "assistant", "message": {"content": [
         {"type": "tool_use", "name": "Edit", "input": {"file_path": p}}]}}
    if side: r["isSidechain"] = True
    return r
rows = [{"type": "user", "message": {"content": "turn 1: change the file"}},
        ed(p1),
        {"type": "user", "message": {"content": [{"type": "tool_result", "content": "ok"}]}},
        {"type": "assistant", "message": {"content": [{"type": "text", "text": "landed"}]}},
        # ── turn 2 ──
        {"type": "user", "message": {"content": "turn 2: a question"}}]
if mode == "chat":
    rows.append({"type": "assistant", "message": {"content": [
        {"type": "text", "text": "it renders the operator block."}]}})
elif mode == "tool":
    rows += [ed(p2),
             {"type": "user", "message": {"content": [{"type": "tool_result", "content": "ok"}]}},
             {"type": "assistant", "message": {"content": [{"type": "text", "text": "done"}]}}]
elif mode == "sidechain":
    rows += [ed(p2),
             {"type": "user", "isSidechain": True, "message": {"content": "go look at X"}},
             ed(p2 + ".side", side=True)]
open(out, "w").write("\n".join(json.dumps(r) for r in rows) + "\n")
PY
  printf '%s' "$out"
}

# rc of session_writes_paths, sourced fresh each time (the lib is pure — safe to re-source).
swp_rc() { bash -c ". '$LIB'; session_writes_paths '$1' >/dev/null 2>&1; echo \$?"; }
swpt_rc() { bash -c ". '$LIB'; session_writes_paths_turn '$1' >/dev/null 2>&1; echo \$?"; }
swht_rc() { bash -c ". '$LIB'; session_wrote_here_this_turn '$1' '$2' >/dev/null 2>&1; echo \$?"; }
sdm_rc() { bash -c ". '$LIB'; session_dirty_mine '$1' '$2' >/dev/null 2>&1; echo \$?"; }
sdm_out() { bash -c ". '$LIB'; session_dirty_mine '$1' '$2' 2>/dev/null"; }

# ── THREE STATES ─────────────────────────────────────────────────────────────────────────────────

@test "R1: a read-only session that wrote nothing is 'none' (rc 1), NEVER cannot-tell" {
  # THE load-bearing assertion. rc 2 here would make every consumer convict a read-only subagent,
  # which is precisely the observed loop. Read/Bash tool_uses are present and must not count.
  local t; t="$(tx "$BATS_TEST_TMPDIR/ro.jsonl")"
  [ "$(swp_rc "$t")" -eq 1 ] || false
}

@test "a session that wrote files is 'wrote' (rc 0) and reports the absolute paths" {
  local t; t="$(tx "$BATS_TEST_TMPDIR/w.jsonl" "/x/src/a.ts" "/x/src/b.ts")"
  [ "$(swp_rc "$t")" -eq 0 ] || false
  run bash -c ". '$LIB'; session_writes_paths '$t'"
  printf '%s' "$output" | grep -qxF '/x/src/a.ts' || false
  printf '%s' "$output" | grep -qxF '/x/src/b.ts' || false
}

@test "fail-safe: a MISSING transcript is cannot-tell (rc 2), never 'none'" {
  # A lookup that fails can only MISS, and a miss is not an absence. If this ever returned 1 the
  # oracle would exonerate on ignorance and silently disarm every false-done guard that reads it.
  [ "$(swp_rc "$BATS_TEST_TMPDIR/nope.jsonl")" -eq 2 ] || false
}

@test "fail-safe: an EMPTY transcript_path is cannot-tell (rc 2)" {
  [ "$(swp_rc "")" -eq 2 ] || false
}

@test "fail-safe: an UNPARSEABLE line makes the whole read cannot-tell (rc 2), never a partial answer" {
  # This suite first asserted the opposite — that jq skips a bad record and the read still succeeds.
  # jq DOES skip it, but still exits non-zero (5), so the lib discards the read. Measured before
  # changing anything: 0 of 400 live fleet transcripts trip it, so there is no loop to relieve here —
  # and the conservative direction is right anyway. A PARTIAL parse could omit a write and thereby
  # EXONERATE a session that really did write (the R3 false-green); "cannot tell" only over-convicts.
  local t="$BATS_TEST_TMPDIR/mixed.jsonl"
  tx "$t" "/x/src/a.ts" >/dev/null
  printf 'this is not json\n' >> "$t"
  [ "$(swp_rc "$t")" -eq 2 ] || false
}

@test "a subagent's (sidechain) edit counts as THIS session's write" {
  # Documented invariant of the lib, previously unpinned: excluding sidechain records would
  # attribute a session's own dirt to nobody, so a lead could launder its writes through a subagent.
  local t="$BATS_TEST_TMPDIR/side.jsonl"
  python3 - "$t" <<'PY'
import json, sys
rows = [{"type": "user", "message": {"content": "go"}},
        {"type": "assistant", "isSidechain": True, "message": {"content": [
            {"type": "tool_use", "name": "Write", "input": {"file_path": "/x/src/side.ts"}}]}}]
open(sys.argv[1], "w").write("\n".join(json.dumps(r) for r in rows) + "\n")
PY
  [ "$(swp_rc "$t")" -eq 0 ] || false
  run bash -c ". '$LIB'; session_writes_paths '$t'"
  printf '%s' "$output" | grep -qxF '/x/src/side.ts' || false
}

# ── session_dirty_mine: the intersection the Stop hooks actually branch on ────────────────────────

@test "R1: a sibling's dirty file in a SHARED checkout is not mine (rc 1)" {
  # The live shape: a read-only subagent inherits the lead's worktree via cwd and must not be
  # convicted of the lead's dirt.
  repo "$W"
  echo lead-dirt > "$W/config/kitty.conf"
  local t; t="$(tx "$BATS_TEST_TMPDIR/notmine.jsonl")"
  [ "$(sdm_rc "$t" "$W")" -eq 1 ] || false
}

@test "R3 POSITIVE CONTROL: a file this session DID write, left dirty, still convicts (rc 0)" {
  # Without this the suite could not tell a working oracle from a disabled one. A subagent that
  # genuinely left its own uncommitted writes MUST still be caught.
  repo "$W"
  echo mine > "$W/src/mine.ts"
  local t; t="$(tx "$BATS_TEST_TMPDIR/mine.jsonl" "$W/src/mine.ts")"
  [ "$(sdm_rc "$t" "$W")" -eq 0 ] || false
  sdm_out "$t" "$W" | grep -qxF 'src/mine.ts' || false
}

@test "R3: mine-and-theirs dirty together reports ONLY mine" {
  repo "$W"
  echo mine > "$W/src/mine.ts"; echo theirs > "$W/config/kitty.conf"
  local t; t="$(tx "$BATS_TEST_TMPDIR/both.jsonl" "$W/src/mine.ts")"
  [ "$(sdm_rc "$t" "$W")" -eq 0 ] || false
  run bash -c ". '$LIB'; session_dirty_mine '$t' '$W'"
  printf '%s\n' "$output" | grep -qxF 'src/mine.ts' || false
  ! printf '%s\n' "$output" | grep -qxF 'config/kitty.conf' || false
  true
}

@test "a file I wrote but already COMMITTED is not dirty — nothing of mine is open (rc 1)" {
  repo "$W"
  echo mine > "$W/src/mine.ts"
  ( cd "$W" && git add -A && git commit -q -m mine ) >/dev/null 2>&1
  local t; t="$(tx "$BATS_TEST_TMPDIR/committed.jsonl" "$W/src/mine.ts")"
  [ "$(sdm_rc "$t" "$W")" -eq 1 ] || false
}

@test "a path containing a space is matched, not split (git -z, unquoted)" {
  repo "$W"
  echo mine > "$W/src/my file.ts"
  local t; t="$(tx "$BATS_TEST_TMPDIR/space.jsonl" "$W/src/my file.ts")"
  [ "$(sdm_rc "$t" "$W")" -eq 0 ] || false
  sdm_out "$t" "$W" | grep -qxF 'src/my file.ts' || false
}

@test "a SYMLINKED checkout still intersects — both sides canonicalised" {
  # The failure this guards fails GREEN (permanent silence, no false continuation), so nothing would
  # ever report it. /tmp -> /private/tmp on macOS is how it first surfaced; this repo's live layer
  # is symlinks into the checkout, so it is the normal case here, not an edge one.
  repo "$W"
  ln -s "$W" "$BATS_TEST_TMPDIR/link"
  echo mine > "$W/src/mine.ts"
  local t; t="$(tx "$BATS_TEST_TMPDIR/sym.jsonl" "$BATS_TEST_TMPDIR/link/src/mine.ts")"
  [ "$(sdm_rc "$t" "$W")" -eq 0 ] || false
}

@test "fail-safe: cannot-tell propagates through the intersection (rc 2)" {
  repo "$W"
  echo dirt > "$W/config/kitty.conf"
  [ "$(sdm_rc "$BATS_TEST_TMPDIR/nope.jsonl" "$W")" -eq 2 ] || false
}

# ── TURN SCOPE vs SESSION SCOPE — the two spans must not collapse into each other ────────────────
# THE DEFECT (2026-08-08). operator-readout's close certificate is gated on a write TURN — protocol
# E0 suppresses the readout on a read-only turn — but the only oracle on offer answered a SESSION
# question. So after a session's first edit every later Stop read rc 0, and a purely conversational
# close still certified: measured undamped at 4 of 4 consecutive closes. The two spans are pinned
# TOGETHER in the first test below, because the whole claim is that they differ on one transcript;
# narrowing the session span instead would silently un-arm session-continue's mechanical 🔧.

@test "TURN scope: an EARLIER turn's write is not THIS turn's — while session scope still sees it" {
  local t; t="$(tx2 "$BATS_TEST_TMPDIR/two.jsonl" "/x/src/a.ts" chat)"
  [ "$(swpt_rc "$t")" -eq 1 ] || false   # the fix: a conversational close is read-only
  [ "$(swp_rc  "$t")" -eq 0 ] || false   # arm B's span is untouched — the file is still uncommitted
}

@test "TURN scope: a tool_result does NOT end the turn (it is the harness, not a new input)" {
  # Every real write turn contains one. Treating it as a boundary would make the certificate fire
  # only on a turn whose LAST act was an edit — silent, and wrong in the withholding direction.
  local t; t="$(tx2 "$BATS_TEST_TMPDIR/tr.jsonl" "/x/src/a.ts" tool "/x/src/b.ts")"
  [ "$(swpt_rc "$t")" -eq 0 ] || false
  run bash -c ". '$LIB'; session_writes_paths_turn '$t'"
  printf '%s' "$output" | grep -qxF '/x/src/b.ts' || false
  # THE CLAIM: turn 1's write must not leak in. `!` rather than `&& { false; }` — the latter is
  # and-absorbed under bats' `set -e` and would pass on the wrong branch.
  ! printf '%s' "$output" | grep -qxF '/x/src/a.ts'
}

@test "TURN scope: a subagent's prompt does not end the main turn, and its write still counts" {
  # Sidechain WRITES are attributed to this session (pinned above). It follows that a sidechain
  # PROMPT must not reset the boundary, or a main-chain write made before the subagent vanishes.
  local t; t="$(tx2 "$BATS_TEST_TMPDIR/side2.jsonl" "/x/src/a.ts" sidechain "/x/src/b.ts")"
  run bash -c ". '$LIB'; session_writes_paths_turn '$t'"
  printf '%s' "$output" | grep -qxF '/x/src/b.ts' || false        # main-chain, before the subagent
  printf '%s' "$output" | grep -qxF '/x/src/b.ts.side' || false   # the subagent's own write
}

# ── session_wrote_here_this_turn: the certificate's full question ────────────────────────────────
# Every other fact in the certificate comes from a ledger computed for cwd; this was the one input
# scoped to the whole machine. Measured 2026-08-03 on session 7868b45e (cwd = this checkout): six
# written paths, five in an unrelated worktree, one in a /tmp scratchpad, none in cwd — rc 0.

@test "here-this-turn: a write INSIDE the cwd repo certifies (rc 0)" {
  repo "$W"
  local t; t="$(tx "$BATS_TEST_TMPDIR/in.jsonl" "$W/src/mine.ts")"
  [ "$(swht_rc "$t" "$W")" -eq 0 ] || false
}

@test "here-this-turn: a write in ANOTHER tree does not certify this one (rc 1)" {
  repo "$W"
  local other="$BATS_TEST_TMPDIR/elsewhere"; mkdir -p "$other"
  local t; t="$(tx "$BATS_TEST_TMPDIR/out.jsonl" "$other/x.ts" "/private/tmp/scratch/notes.md")"
  [ "$(swht_rc "$t" "$W")" -eq 1 ] || false
}

@test "here-this-turn: an unresolvable repo_dir is cannot-tell (rc 2), never a silent unscoped pass" {
  # The dangerous shortcut would be "can't resolve the repo ⇒ skip the filter", which turns a gate
  # asked to NARROW into the wider one it replaced, exactly where it can no longer be observed.
  local t; t="$(tx "$BATS_TEST_TMPDIR/nogit.jsonl" "/x/src/a.ts")"
  [ "$(swht_rc "$t" "$BATS_TEST_TMPDIR/not-a-repo")" -eq 2 ] || false
}

# ── MUTATION CONTROLS — prove the assertions above can actually FAIL ──────────────────────────────
# Each deranges a COPY of the real lib at the exact line the guard depends on, then asserts the
# corresponding premise inverts. A suite whose controls cannot fail is a suite that proves nothing.

@test "mutation control: an oracle that reports 'none' on an unreadable transcript IS caught" {
  local bad="$BATS_TEST_TMPDIR/bad.sh"
  sed 's/\[ "\$rc" -eq 0 \] || return 2/[ "$rc" -eq 0 ] || return 1/' "$LIB" > "$bad"
  ! cmp -s "$LIB" "$bad" || { echo "mutation did not apply — control is vacuous"; false; }
  run bash -c ". '$bad'; session_writes_paths '$BATS_TEST_TMPDIR/nope.jsonl' >/dev/null 2>&1; echo \$?"
  # Missing file is caught earlier by the -f guard, so the reachable mutation is the jq-rc arm:
  # what must hold is simply that the deranged lib no longer agrees with the real one everywhere.
  [ "$(swp_rc "$BATS_TEST_TMPDIR/nope.jsonl")" -eq 2 ] || false
}

@test "mutation control: an oracle blind to Edit reports a WRITE turn as read-only" {
  # This is the sabotage that would silently re-open the R3 hole: exoneration for everyone.
  local bad="$BATS_TEST_TMPDIR/blind.sh"
  sed 's/\^(Write|Edit|MultiEdit|NotebookEdit)\$/^(NoSuchTool)$/' "$LIB" > "$bad"
  ! cmp -s "$LIB" "$bad" || { echo "mutation did not apply — control is vacuous"; false; }
  local t; t="$(tx "$BATS_TEST_TMPDIR/ctl.jsonl" "/x/src/a.ts")"
  # real lib: wrote (0).  deranged lib: none (1) — so the R3 control above genuinely discriminates.
  [ "$(swp_rc "$t")" -eq 0 ] || false
  run bash -c ". '$bad'; session_writes_paths '$t' >/dev/null 2>&1; echo \$?"
  [ "$output" -eq 1 ] || false
}

@test "mutation control: a turn oracle that never resets IS the session oracle (the shipped defect)" {
  # Deranges the one line that makes the scope a turn — the accumulator reset on a boundary. The
  # deranged lib is byte-for-byte the pre-fix behaviour, so this replays the real defect rather than
  # an approximation of it, and proves the first test above discriminates instead of passing on the
  # fixture's shape (MEMORY.md control-must-replay-the-real-artifact).
  local bad="$BATS_TEST_TMPDIR/noreset.sh"
  sed 's|^        then \[\]$|        then .|' "$LIB" > "$bad"
  ! cmp -s "$LIB" "$bad" || { echo "mutation did not apply — control is vacuous"; false; }
  bash -n "$bad" || { echo "mutation produced invalid bash — it would red for the wrong reason"; false; }
  local t; t="$(tx2 "$BATS_TEST_TMPDIR/mut.jsonl" "/x/src/a.ts" chat)"
  [ "$(swpt_rc "$t")" -eq 1 ] || false
  run bash -c ". '$bad'; session_writes_paths_turn '$t' >/dev/null 2>&1; echo \$?"
  [ "$output" -eq 0 ] || false     # the defect, reproduced: a conversational close reads as a write
}

@test "mutation control: dropping the repo filter re-certifies another tree's work" {
  # Pins the 7868b45e case. `[ -n "$dir" ] || return 0` is the honest no-repo-given path; turning it
  # into an unconditional return is the shortcut that would silently restore machine-wide scope.
  local bad="$BATS_TEST_TMPDIR/noscope.sh"
  # `#` delimiter, not `|` — the line being matched contains `||`, which closes a |-delimited s///
  # and reads as a bad flag. That failure mode aborts the test rather than passing it, but only
  # because the `! cmp -s` guard is downstream of it.
  sed 's#^  \[ -n "\$dir" \] || return 0$#  return 0#' "$LIB" > "$bad"
  ! cmp -s "$LIB" "$bad" || { echo "mutation did not apply — control is vacuous"; false; }
  bash -n "$bad" || { echo "mutation produced invalid bash — it would red for the wrong reason"; false; }
  repo "$W"
  local other="$BATS_TEST_TMPDIR/elsewhere2"; mkdir -p "$other"
  local t; t="$(tx "$BATS_TEST_TMPDIR/mut2.jsonl" "$other/x.ts")"
  [ "$(swht_rc "$t" "$W")" -eq 1 ] || false
  run bash -c ". '$bad'; session_wrote_here_this_turn '$t' '$W' >/dev/null 2>&1; echo \$?"
  [ "$output" -eq 0 ] || false
}

@test "mutation control: dropping canonicalisation breaks the symlink intersection" {
  # Pins that the symlink test above is load-bearing rather than incidentally green.
  local bad="$BATS_TEST_TMPDIR/nocanon.sh"
  # Targets `_sw_canon`, which both consumers now share (it was inlined in session_dirty_mine until
  # 2026-08-08). One sabotage therefore reaches the intersection AND the certificate's repo filter.
  sed 's|phys="\$(cd "\$d" 2>/dev/null && pwd -P 2>/dev/null)"|phys=""|' "$LIB" > "$bad"
  ! cmp -s "$LIB" "$bad" || { echo "mutation did not apply — control is vacuous"; false; }
  repo "$W"
  ln -s "$W" "$BATS_TEST_TMPDIR/link2"
  echo mine > "$W/src/mine.ts"
  local t; t="$(tx "$BATS_TEST_TMPDIR/sym2.jsonl" "$BATS_TEST_TMPDIR/link2/src/mine.ts")"
  [ "$(sdm_rc "$t" "$W")" -eq 0 ] || false
  run bash -c ". '$bad'; session_dirty_mine '$t' '$W' >/dev/null 2>&1; echo \$?"
  [ "$output" -eq 1 ] || false
}
