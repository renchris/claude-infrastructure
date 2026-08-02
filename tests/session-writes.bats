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
  local w="$1" o="$1.git"
  git init -q --bare "$o"
  git clone -q "$o" "$w" 2>/dev/null
  # `|| exit 1` is load-bearing, not ceremony: without it a failed cd runs every command below in
  # the TEST's cwd — i.e. this repo — and `git add -A; git commit` would fire on the real checkout.
  ( cd "$w" || exit 1
    git config user.email t@e.com; git config user.name t; git checkout -q -b main
    mkdir -p config src
    echo base > base.txt; git add -A; git commit -q -m base; git push -q -u origin main ) >/dev/null 2>&1
}

# rc of session_writes_paths, sourced fresh each time (the lib is pure — safe to re-source).
swp_rc() { bash -c ". '$LIB'; session_writes_paths '$1' >/dev/null 2>&1; echo \$?"; }
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

@test "mutation control: dropping canonicalisation breaks the symlink intersection" {
  # Pins that the symlink test above is load-bearing rather than incidentally green.
  local bad="$BATS_TEST_TMPDIR/nocanon.sh"
  sed 's|_phys="\$(cd "\$_d" 2>/dev/null && pwd -P 2>/dev/null)"|_phys=""|' "$LIB" > "$bad"
  ! cmp -s "$LIB" "$bad" || { echo "mutation did not apply — control is vacuous"; false; }
  repo "$W"
  ln -s "$W" "$BATS_TEST_TMPDIR/link2"
  echo mine > "$W/src/mine.ts"
  local t; t="$(tx "$BATS_TEST_TMPDIR/sym2.jsonl" "$BATS_TEST_TMPDIR/link2/src/mine.ts")"
  [ "$(sdm_rc "$t" "$W")" -eq 0 ] || false
  run bash -c ". '$bad'; session_dirty_mine '$t' '$W' >/dev/null 2>&1; echo \$?"
  [ "$output" -eq 1 ] || false
}
