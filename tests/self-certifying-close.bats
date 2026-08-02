#!/usr/bin/env bats
# self-certifying-close.bats — the two arms that stop the operator having to ask
# "are we good to close with no remaining tasks, loose-ends, or manual steps?".
#
#   A  operator-readout: a WRITE turn whose ledger is ✅ says SAFE TO CLOSE, verdict FIRST.
#   B  session-continue: a 🔧 attributable to THIS session continues mechanically, with no
#      dependence on the model having armed the sentinel.
#
# Both turn on hooks/lib/session-writes.sh, so its three states are pinned first — including the
# two that must NOT act. Every negative control here is one the positive path could actually fail:
# the sibling-dirt case exercises the same code path as the fires-correctly case and differs only
# in WHO wrote the file, which is the whole claim (MEMORY.md control-must-replay-the-real-artifact).

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  LIB="$REPO/hooks/lib/session-writes.sh"
  CONT="$REPO/hooks/session-continue.sh"
  READOUT="$REPO/hooks/operator-readout.sh"
  # HERMETIC $HOME. Both subjects fall back to `$HOME/.claude/...` for the backlog binary, the
  # durable-DoD dir and the hooks/lib tier, so an unfixtured run reads the operator's live machine —
  # which on this box means ~211 standing backlog items leaking into every assertion, and any write
  # landing in their real config. Fixturing it is also what makes these tests MEAN anything: the
  # ledger's stores are then empty by construction, so a rung is decided by the fixture repo alone.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/cfg"
  export CONTINUE_IDL="$BATS_TEST_TMPDIR/idl.jsonl" CONTINUE_LOG="$BATS_TEST_TMPDIR/c.log"
  export OPREADOUT_IDL="$BATS_TEST_TMPDIR/idl2.jsonl"
  mkdir -p "$CLAUDE_CONFIG_DIR"
  # git needs an identity under the fixtured HOME (no ~/.gitconfig there).
  export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@e.com \
         GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@e.com
  # Pin the UNRELATED Stop arm off. session-continue also hosts the inbox wake floor, which emits
  # its own `decision:block`; counting bare blocks would silently measure that arm instead of this
  # one (it is what made the bound tests read >2 with the budget working perfectly). The assertions
  # below additionally discriminate on the mechanical REASON, so neither guard alone is load-bearing.
  export CC_WAKE_FLOOR=0
  # Terminal-awareness pin (repo convention: a suite must not become a function of the terminal
  # the developer happens to be sitting in).
  unset KITTY_WINDOW_ID
}

# a landed, clean repo with a real upstream — the ✅-shaped git state
mkrepo() {
  local o="$BATS_TEST_TMPDIR/o-$1.git" w="$BATS_TEST_TMPDIR/w-$1"
  git init -q --bare "$o"; git clone -q "$o" "$w" 2>/dev/null
  ( cd "$w" || exit 1; git config user.email t@e.com; git config user.name t; git checkout -q -b main
    echo base > f.txt; echo other > g.txt; git add -A; git commit -q -m base
    git push -q -u origin main ) >/dev/null 2>&1
  printf '%s' "$w"
}

# a transcript recording an Edit of each given path (plus a user turn, so the kill-switch reader
# has something non-empty to read)
mktr() {
  local out="$1"; shift
  python3 - "$out" "$@" <<'PY'
import json, sys
out, paths = sys.argv[1], sys.argv[2:]
rows = [{"type": "user", "message": {"content": "go"}}]
for p in paths:
    rows.append({"type": "assistant", "message": {"content": [
        {"type": "tool_use", "name": "Edit", "input": {"file_path": p}}]}})
rows.append({"type": "assistant", "message": {"content": [{"type": "text", "text": "ok"}]}})
open(out, "w").write("\n".join(json.dumps(r) for r in rows) + "\n")
PY
  printf '%s' "$out"
}

payload() { # $1=cwd $2=transcript
  python3 -c 'import json,sys;print(json.dumps({"session_id":"S1","cwd":sys.argv[1],"transcript_path":sys.argv[2]}))' "$1" "$2"
}

# ── the oracle: three states ─────────────────────────────────────────────────────────────────────

@test "oracle: reports the paths this session wrote (rc 0)" {
  w="$(mkrepo o1)"; tr="$(mktr "$BATS_TEST_TMPDIR/t1.jsonl" "$w/f.txt")"
  run bash -c ". '$LIB'; session_writes_paths '$tr'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"$w/f.txt"* ]]
}

@test "oracle: a transcript with no file-edit tool_use is 'none' (rc 1), not 'cannot tell'" {
  tr="$(mktr "$BATS_TEST_TMPDIR/t2.jsonl")"
  run bash -c ". '$LIB'; session_writes_paths '$tr'"
  [ "$status" -eq 1 ]
}

@test "oracle: an unreadable transcript is 'cannot tell' (rc 2), never 'none'" {
  run bash -c ". '$LIB'; session_writes_paths /nonexistent/nope.jsonl"
  [ "$status" -eq 2 ]
}

@test "oracle: attribution excludes a file this session did NOT write" {
  w="$(mkrepo o3)"; tr="$(mktr "$BATS_TEST_TMPDIR/t3.jsonl" "$w/f.txt")"
  ( cd "$w" || exit 1; echo mine >> f.txt; echo sibling >> g.txt )
  run bash -c ". '$LIB'; session_dirty_mine '$tr' '$w'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"f.txt"* ]] || false
  # THE CLAIM: g.txt is dirty in the very same tree and must not appear.
  [[ "$output" != *"g.txt"* ]]
}

@test "oracle: only-sibling dirt is empty (rc 1) — the false-conviction guard" {
  w="$(mkrepo o4)"; tr="$(mktr "$BATS_TEST_TMPDIR/t4.jsonl" "$w/f.txt")"
  ( cd "$w" || exit 1; echo sibling >> g.txt )
  run bash -c ". '$LIB'; session_dirty_mine '$tr' '$w'"
  [ "$status" -eq 1 ]
}

@test "oracle: a symlinked path still intersects (physical-vs-logical spelling)" {
  w="$(mkrepo o5)"
  ln -s "$w" "$BATS_TEST_TMPDIR/link"
  # the transcript records the LOGICAL path (through the symlink); git reports the PHYSICAL one.
  tr="$(mktr "$BATS_TEST_TMPDIR/t5.jsonl" "$BATS_TEST_TMPDIR/link/f.txt")"
  ( cd "$w" || exit 1; echo mine >> f.txt )
  run bash -c ". '$LIB'; session_dirty_mine '$tr' '$w'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"f.txt"* ]]
}

# ── ARM B: mechanical 🔧 continuation ────────────────────────────────────────────────────────────

@test "B: uncommitted file I wrote this turn BLOCKS the stop (no sentinel armed)" {
  w="$(mkrepo b1)"; tr="$(mktr "$BATS_TEST_TMPDIR/b1.jsonl" "$w/f.txt")"
  ( cd "$w" || exit 1; echo mine >> f.txt )
  run bash -c "payload() { python3 -c 'import json,sys;print(json.dumps({\"session_id\":\"S1\",\"cwd\":sys.argv[1],\"transcript_path\":sys.argv[2]}))' \"\$1\" \"\$2\"; }; payload '$w' '$tr' | bash '$CONT'"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.decision == "block"' >/dev/null
  printf '%s' "$output" | jq -r '.reason' | grep -q 'f.txt'
}

@test "B: a sibling's dirty file does NOT block (attribution, not just dirtiness)" {
  w="$(mkrepo b2)"; tr="$(mktr "$BATS_TEST_TMPDIR/b2.jsonl" "$w/f.txt")"
  ( cd "$w" || exit 1; echo sibling >> g.txt )     # dirty, but NOT written by this session
  run bash -c "python3 -c 'import json,sys;print(json.dumps({\"session_id\":\"S1\",\"cwd\":sys.argv[1],\"transcript_path\":sys.argv[2]}))' '$w' '$tr' | bash '$CONT'"
  [ "$status" -eq 0 ]
  # It may still emit the (unrelated, pre-existing) wake-floor advisory; what it must NOT do is
  # claim a loose end. Assert on the CONTENT, so this stays a real control rather than a
  # tautology about emptiness.
  ! printf '%s' "$output" | jq -r '.reason // ""' 2>/dev/null | grep -q 'uncommitted'
}

@test "B: a clean landed tree does NOT block" {
  w="$(mkrepo b3)"; tr="$(mktr "$BATS_TEST_TMPDIR/b3.jsonl" "$w/f.txt")"
  run bash -c "python3 -c 'import json,sys;print(json.dumps({\"session_id\":\"S1\",\"cwd\":sys.argv[1],\"transcript_path\":sys.argv[2]}))' '$w' '$tr' | bash '$CONT'"
  [ "$status" -eq 0 ]
  ! printf '%s' "$output" | jq -r '.reason // ""' 2>/dev/null | grep -q 'uncommitted'
}

@test "B: CC_MECH_CONTINUE=0 disables the arm entirely (kill switch)" {
  w="$(mkrepo b4)"; tr="$(mktr "$BATS_TEST_TMPDIR/b4.jsonl" "$w/f.txt")"
  ( cd "$w" || exit 1; echo mine >> f.txt )
  run bash -c "CC_MECH_CONTINUE=0 python3 -c 'import json,sys;print(json.dumps({\"session_id\":\"S1\",\"cwd\":sys.argv[1],\"transcript_path\":sys.argv[2]}))' '$w' '$tr' | CC_MECH_CONTINUE=0 bash '$CONT'"
  [ "$status" -eq 0 ]
  ! printf '%s' "$output" | jq -r '.reason // ""' 2>/dev/null | grep -q 'uncommitted'
}

@test "B: an operator kill phrase wins over attributable dirt" {
  w="$(mkrepo b5)"; tr="$BATS_TEST_TMPDIR/b5.jsonl"
  ( cd "$w" || exit 1; echo mine >> f.txt )
  python3 - "$tr" "$w/f.txt" <<'PY'
import json, sys
out, p = sys.argv[1], sys.argv[2]
rows = [{"type": "assistant", "message": {"content": [
            {"type": "tool_use", "name": "Edit", "input": {"file_path": p}}]}},
        {"type": "user", "message": {"content": "leave it, stop here"}}]
open(out, "w").write("\n".join(json.dumps(r) for r in rows) + "\n")
PY
  run bash -c "python3 -c 'import json,sys;print(json.dumps({\"session_id\":\"S1\",\"cwd\":sys.argv[1],\"transcript_path\":sys.argv[2]}))' '$w' '$tr' | bash '$CONT'"
  [ "$status" -eq 0 ]
  ! printf '%s' "$output" | jq -r '.reason // ""' 2>/dev/null | grep -q 'uncommitted'
}

@test "B: the loop is bounded — it stops blocking at CLAUDE_CONTINUE_MAX" {
  w="$(mkrepo b6)"; tr="$(mktr "$BATS_TEST_TMPDIR/b6.jsonl" "$w/f.txt")"
  ( cd "$w" || exit 1; echo mine >> f.txt )
  pl="$(payload "$w" "$tr")"
  blocked=0
  for _ in 1 2 3 4 5 6; do
    out="$(printf '%s' "$pl" | CC_MECH_MAX=1 CLAUDE_CONTINUE_MAX=2 bash "$CONT" 2>/dev/null || true)"
    # Count only MECHANICAL blocks. session-continue hosts other arms that also emit
    # decision:block, so a bare `.decision == "block"` would measure whichever arm happened to
    # fire and pass or fail for the wrong reason.
    printf '%s' "$out" | jq -r '.reason // ""' 2>/dev/null | grep -q 'uncommitted' && blocked=$((blocked+1))
  done
  # Without a bound this blocks all six times. Both factors are pinned because the bound is their
  # PRODUCT (see the next test); leaving either to its default would make this assertion drift with
  # a config change rather than with the behaviour it is meant to hold.
  [ "$blocked" -le 2 ]
  [ "$blocked" -ge 1 ]
}

@test "B: the bound is the PRODUCT of both caps, and each factor really moves it" {
  # The first cut of this arm zeroed `.count` on every mechanical arm, so the continuation cap
  # cleared the sentinel and the very next Stop re-armed with a fresh chain — an unbounded loop in
  # which compliance reset its own budget (MEMORY.md bounded-gate-unbounded-by-compliance). The
  # bound that actually holds is CC_MECH_MAX × CLAUDE_CONTINUE_MAX, so BOTH factors are pinned, and
  # the second half is the positive control: if `blocked` were limited by anything other than the
  # product, raising a factor would not move it and the first half would pass vacuously.
  run_n() { # $1=mech $2=cont $3=tag → echoes the number of blocked stops in 8 tries
    local w tr pl out n=0
    w="$(mkrepo "$3")"; tr="$(mktr "$BATS_TEST_TMPDIR/$3.jsonl" "$w/f.txt")"
    ( cd "$w" || exit 1; echo mine >> f.txt )    # stays dirty throughout — the model never complies
    pl="$(payload "$w" "$tr")"
    for _ in 1 2 3 4 5 6 7 8; do
      out="$(printf '%s' "$pl" | CC_MECH_MAX="$1" CLAUDE_CONTINUE_MAX="$2" bash "$CONT" 2>/dev/null || true)"
      printf '%s' "$out" | jq -r '.reason // ""' 2>/dev/null | grep -q 'uncommitted' && n=$((n+1))
    done
    printf '%s' "$n"
  }
  one="$(run_n 1 2 p1)"
  two="$(run_n 2 2 p2)"
  [ "$one" -ge 1 ]; [ "$one" -le 2 ]     # 1 × 2 — without the surviving budget this is 8
  [ "$two" -gt "$one" ]; [ "$two" -le 4 ] # 2 × 2 — the factor moves the bound
}

@test "B: 'clear' spends the mechanical budget — an off switch, not a snooze" {
  w="$(mkrepo b8)"; tr="$(mktr "$BATS_TEST_TMPDIR/b8.jsonl" "$w/f.txt")"
  ( cd "$w" || exit 1; echo mine >> f.txt )
  pl="$(payload "$w" "$tr")"
  printf '%s' "$pl" | CLAUDE_CODE_SESSION_ID=S1 bash "$CONT" >/dev/null 2>&1 || true  # arms + blocks
  ( cd "$w" || exit 1; CLAUDE_CODE_SESSION_ID=S1 bash "$CONT" clear >/dev/null 2>&1 )           # "it's deliberate"
  # The tree is STILL dirty, so a snooze would re-block right here.
  run bash -c "printf '%s' '$pl' | CLAUDE_CODE_SESSION_ID=S1 bash '$CONT'"
  [ "$status" -eq 0 ]
  ! printf '%s' "$output" | jq -r '.reason // ""' 2>/dev/null | grep -q 'uncommitted'
}

# ── ARM A: the affirmative close certificate ─────────────────────────────────────────────────────

@test "A: WRITE turn + ✅ ledger renders SAFE TO CLOSE, and the verdict comes FIRST" {
  w="$(mkrepo a1)"; tr="$(mktr "$BATS_TEST_TMPDIR/a1.jsonl" "$w/f.txt")"
  run bash -c "python3 -c 'import json,sys;print(json.dumps({\"session_id\":\"S1\",\"cwd\":sys.argv[1],\"transcript_path\":sys.argv[2]}))' '$w' '$tr' | bash '$READOUT'"
  [ "$status" -eq 0 ]
  msg="$(printf '%s' "$output" | jq -r '.systemMessage // ""')"
  printf '%s' "$msg" | grep -q 'SAFE TO CLOSE'
  # Answer-first: the verdict must be on line 1, and ahead of any standing-pile counts.
  head1="$(printf '%s' "$msg" | head -1)"
  printf '%s' "$head1" | grep -q 'SAFE TO CLOSE'
}

@test "A: READ-ONLY turn never claims safe-to-close" {
  w="$(mkrepo a2)"; tr="$(mktr "$BATS_TEST_TMPDIR/a2.jsonl")"
  run bash -c "python3 -c 'import json,sys;print(json.dumps({\"session_id\":\"S1\",\"cwd\":sys.argv[1],\"transcript_path\":sys.argv[2]}))' '$w' '$tr' | bash '$READOUT'"
  [ "$status" -eq 0 ]
  ! printf '%s' "$output" | jq -r '.systemMessage // ""' 2>/dev/null | grep -q 'SAFE TO CLOSE'
}

@test "A: cannot-tell (no transcript) never claims safe-to-close" {
  w="$(mkrepo a3)"
  run bash -c "printf '{\"session_id\":\"S1\",\"cwd\":\"$w\"}' | bash '$READOUT'"
  [ "$status" -eq 0 ]
  ! printf '%s' "$output" | jq -r '.systemMessage // ""' 2>/dev/null | grep -q 'SAFE TO CLOSE'
}

@test "A: a DIRTY write turn is never certified" {
  w="$(mkrepo a4)"; tr="$(mktr "$BATS_TEST_TMPDIR/a4.jsonl" "$w/f.txt")"
  ( cd "$w" || exit 1; echo mine >> f.txt )
  run bash -c "python3 -c 'import json,sys;print(json.dumps({\"session_id\":\"S1\",\"cwd\":sys.argv[1],\"transcript_path\":sys.argv[2]}))' '$w' '$tr' | bash '$READOUT'"
  [ "$status" -eq 0 ]
  ! printf '%s' "$output" | jq -r '.systemMessage // ""' 2>/dev/null | grep -q 'SAFE TO CLOSE'
}

@test "A: committed-but-unlanded (📦) is never certified" {
  w="$(mkrepo a5)"; tr="$(mktr "$BATS_TEST_TMPDIR/a5.jsonl" "$w/f.txt")"
  ( cd "$w" || exit 1; echo mine >> f.txt; git add -A; git commit -q -m parked )
  run bash -c "python3 -c 'import json,sys;print(json.dumps({\"session_id\":\"S1\",\"cwd\":sys.argv[1],\"transcript_path\":sys.argv[2]}))' '$w' '$tr' | bash '$READOUT'"
  [ "$status" -eq 0 ]
  ! printf '%s' "$output" | jq -r '.systemMessage // ""' 2>/dev/null | grep -q 'SAFE TO CLOSE'
}

@test "A: CC_CLOSE_CERT=0 disables the certificate (kill switch)" {
  w="$(mkrepo a6)"; tr="$(mktr "$BATS_TEST_TMPDIR/a6.jsonl" "$w/f.txt")"
  run bash -c "python3 -c 'import json,sys;print(json.dumps({\"session_id\":\"S1\",\"cwd\":sys.argv[1],\"transcript_path\":sys.argv[2]}))' '$w' '$tr' | CC_CLOSE_CERT=0 bash '$READOUT'"
  [ "$status" -eq 0 ]
  ! printf '%s' "$output" | jq -r '.systemMessage // ""' 2>/dev/null | grep -q 'SAFE TO CLOSE'
}

@test "A: the readout stays pure-advisory — it never emits decision:block" {
  w="$(mkrepo a7)"; tr="$(mktr "$BATS_TEST_TMPDIR/a7.jsonl" "$w/f.txt")"
  run bash -c "python3 -c 'import json,sys;print(json.dumps({\"session_id\":\"S1\",\"cwd\":sys.argv[1],\"transcript_path\":sys.argv[2]}))' '$w' '$tr' | bash '$READOUT'"
  [ "$status" -eq 0 ]
  if [ -n "$output" ]; then
    printf '%s' "$output" | jq -e 'has("decision") | not' >/dev/null
  fi
}
