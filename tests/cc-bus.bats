#!/usr/bin/env bats
# cc-bus — git-as-the-bus interop for sessions that are NOT on this box.
#
# `cc-bus --selftest` carries the mechanism proofs (one-writer sharding, secret refusal,
# addressing, work-fold, bridge idempotence). These bats add CLI-level regression on the
# contract a cloud session actually depends on, plus the two properties a selftest running
# inside one process cannot honestly assert:
#   * that a REAL concurrent git rebase of two actors' shards merges clean (the whole
#     premise — asserted here against a real bare repo, with a positive control that a
#     shared file DOES conflict), and
#   * that nothing reaches the operator's live stores.
#
# Every test is hermetic: CC_BUS_DIR under BATS_TEST_TMPDIR, and the two bridge helpers are
# stubbed. Nothing here may touch ~/.claude.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  BUS="$REPO/bin/cc-bus"
  # Keep a handle on the operator's REAL home before fixturing, so the hermeticity test
  # below can still assert against the store that actually matters.
  REAL_HOME="$HOME"
  # Fixture $HOME. This is load-bearing, not ceremony: cc-bus's resolve_helper falls back to
  # $HOME/.claude/bin/{cc-backlog,cc-notify}, and drain's applied-cursor defaults to
  # $HOME/.claude/autonomy/bus-applied — so any test that forgot to stub would otherwise
  # drive the operator's LIVE ledger and mailbox.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_BUS_DIR="$BATS_TEST_TMPDIR/bus"
  export CC_BUS_APPLIED_FILE="$BATS_TEST_TMPDIR/applied"
  export CC_BUS_ACTOR=tester

  # THE ROUND-TRIP PROBE. One string, used by every read-path test below, carrying all three
  # characters that json_escape transforms — so a reader that handles two of them still goes
  # red. The escaped quote is the one that matters most: it is what makes `[^"]*` stop early,
  # which is how a delivered message came out as `he said \` for a year.
  HOSTILE='he said "hi" \ then left
and wrote a second line'
  printf '%s' "$HOSTILE" > "$BATS_TEST_TMPDIR/want"
}

@test "selftest passes 22/22 (a zero-check suite must not 'pass')" {
  run "$BUS" --selftest
  [ "$status" -eq 0 ]
  n="$(printf '%s' "$output" | grep -c '^  ok ')"
  [ "$n" -eq 22 ]
}

@test "the derived actor id is stable across invocations (no CC_BUS_ACTOR)" {
  # The defect this pins: a process-keyed id mints a shard per emit and makes inbox/ack/
  # drain address a stranger. Asserted in BOTH derivation paths — a checkout, and not.
  a="$(cd "$BATS_TEST_TMPDIR" && env -u CC_BUS_ACTOR "$BUS" whoami)"
  b="$(cd "$BATS_TEST_TMPDIR" && env -u CC_BUS_ACTOR "$BUS" whoami)"
  [ -n "$a" ]
  [ "$a" = "$b" ]
  c="$(cd "$REPO" && env -u CC_BUS_ACTOR CC_BUS_DIR="$REPO/bus" "$BUS" whoami)"
  d="$(cd "$REPO" && env -u CC_BUS_ACTOR CC_BUS_DIR="$REPO/bus" "$BUS" whoami)"
  [ "$c" = "$d" ]
}

@test "whoami is stable within a session and honors CC_BUS_ACTOR" {
  run "$BUS" whoami
  [ "$status" -eq 0 ]
  [ "$output" = "tester" ]
}

@test "an actor id is derived without CC_BUS_ACTOR and is filename-safe" {
  run env -u CC_BUS_ACTOR "$BUS" whoami
  [ "$status" -eq 0 ]
  [ -n "$output" ]
  # A shard filename must not contain a path separator or a leading dot.
  [[ "$output" != */* ]] || false
  [[ "$output" != .* ]]
}

# ── the actor-id gate (the WRITE side of the escaping contract) ─────────────────────────
# The tests above exercise only the DERIVED id, which was always sanitised. The override was
# not: $CC_BUS_ACTOR reached the JSON record, the shard FILENAME and `git add` unchecked. These
# drive the override path, at the CLI, in both hostile shapes — and then check the gate did not
# become a blanket refusal, which is the failure mode a one-sided test would call a pass.

@test "GATE: a quote in CC_BUS_ACTOR is REFUSED (exit 2) and writes no record" {
  # The exact filed repro. Before the gate: `{"actor":"ev"il",...}`, which no JSON parser
  # accepts, in a shard literally named `ev"il.jsonl`.
  run env CC_BUS_ACTOR='ev"il' "$BUS" emit note --body hi
  [ "$status" -eq 2 ]
  [[ "$output" == *"not a usable actor id"* ]] || false
  # Proven to be a refusal, not a mangled success: NO shard exists under any name.
  n="$(find "$CC_BUS_DIR" -name '*.jsonl' 2>/dev/null | wc -l | tr -d ' ')"
  [ "$n" -eq 0 ]
}

@test "GATE: CC_BUS_ACTOR cannot walk the shard out of the bus directory" {
  # The half the filed item did not name and the more damaging one: `shard_for` pastes the
  # actor straight into a path, so `..` wrote a real record OUTSIDE bus/actors/ — invisible to
  # every fold (which globs actors/*.jsonl) and a path `sync --push` would hand to `git add`.
  mkdir -p "$BATS_TEST_TMPDIR/esc"
  run env CC_BUS_ACTOR='../../esc/pwned' "$BUS" emit note --body hi
  [ "$status" -eq 2 ]
  n="$(find "$BATS_TEST_TMPDIR" -name '*.jsonl' 2>/dev/null | wc -l | tr -d ' ')"
  [ "$n" -eq 0 ]
}

@test "GATE: uppercase is REFUSED rather than lowercased (case-insensitive FS collision)" {
  # Not pedantry about charset. On macOS `Alpha.jsonl` and `alpha.jsonl` are ONE file, so
  # silently lowercasing would let two distinct actor ids share a shard — the exact
  # cross-write the one-writer law exists to make impossible, visible only on the operator's box.
  run env CC_BUS_ACTOR='Alpha' "$BUS" whoami
  [ "$status" -eq 2 ]
  [[ "$output" == *"outside [a-z0-9-]"* ]]
}

@test "GATE: DISCRIMINATES — a legitimate actor id still emits and folds" {
  # A gate that refused everything would pass all three tests above. This is the control.
  run env CC_BUS_ACTOR=mymac-wt-5341a9e5fc4d "$BUS" emit note --body hi
  [ "$status" -eq 0 ]
  [ "$output" = "mymac-wt-5341a9e5fc4d:1" ]
  [ -f "$CC_BUS_DIR/actors/mymac-wt-5341a9e5fc4d.jsonl" ]
  run python3 -c "import json,sys; json.loads(open(sys.argv[1]).readline())" \
    "$CC_BUS_DIR/actors/mymac-wt-5341a9e5fc4d.jsonl"
  [ "$status" -eq 0 ]
}

@test "GATE: it fires on EVERY verb, not just emit (it runs before dispatch)" {
  # A gate placed inside cmd_emit would leave `sync`, `drain` and `whoami` reaching shard_for()
  # with the hostile id. Checked on a read verb, where nothing is written and a miss is silent.
  for verb in whoami inbox sync drain; do
    run env CC_BUS_ACTOR='ev"il' "$BUS" "$verb"
    [ "$status" -eq 2 ]
    [[ "$output" == *"not a usable actor id"* ]] || false
  done
}

@test "the derived actor id satisfies the same contract the gate enforces on an override" {
  # The two halves must not drift: the accepted charset IS what derivation produces, so a
  # derived id must never be one the gate would refuse. Driven from a checkout whose basename
  # is itself hostile — a worktree called `WT Foo.Bar` is an ordinary thing for someone to make,
  # and it is the input that sends derivation through every branch of the sanitiser at once
  # (uppercase, space, dot, and an over-long run).
  d="$BATS_TEST_TMPDIR/WT Foo.Bar-$(printf 'x%.0s' $(seq 1 80))"
  mkdir -p "$d" && git -C "$d" init -q
  a="$(cd "$d" && env -u CC_BUS_ACTOR CC_BUS_DIR="$d/bus" "$BUS" whoami)"
  [ -n "$a" ]
  [ "${#a}" -le 64 ]
  [[ "$a" != -* ]] || false
  printf '%s' "$a" | LC_ALL=C grep -qE '^[a-z0-9-]+$'
  # …and the gate itself must accept it — the no-drift assertion, stated as the gate's own verdict
  # rather than a second copy of its rule.
  run env CC_BUS_ACTOR="$a" CC_BUS_DIR="$d/bus" "$BUS" whoami
  [ "$status" -eq 0 ]
  [ "$output" = "$a" ]
}

@test "emit returns a globally-unique id of the form <actor>:<seq>" {
  run "$BUS" emit note --body "first"
  [ "$status" -eq 0 ]
  [ "$output" = "tester:1" ]
}

@test "a record lands in the emitting actor's own shard and is valid JSON" {
  "$BUS" emit note --body "hello" >/dev/null
  [ -f "$CC_BUS_DIR/actors/tester.jsonl" ]
  run python3 -c "import json,sys; json.loads(open(sys.argv[1]).readline())" "$CC_BUS_DIR/actors/tester.jsonl"
  [ "$status" -eq 0 ]
}

@test "a body containing quotes, backslashes and newlines survives as valid JSON" {
  "$BUS" post peer 'he said "hi\there" and
then a newline' >/dev/null
  run python3 -c "
import json,sys
r=json.loads(open(sys.argv[1]).readline())
assert '\"' in r['body'], r
assert '\n' in r['body'], r
print('ok')" "$CC_BUS_DIR/actors/tester.jsonl"
  [ "$status" -eq 0 ]
}

# ── the READ path ───────────────────────────────────────────────────────────────────────
# The test above proves only the WRITER. It passed for as long as the reader was broken,
# because a correctly-escaped record on disk says nothing about what comes back OUT of it:
# every consumer pulled fields back with `"key":"\([^"]*\)"`, a class that cannot see `\"`,
# and none of them unescaped. `post beta 'he said "hi" then left'` was delivered as
# `he said \`. These four tests drive the CONSUMERS, so the writer's escaping and the
# reader's unescaping are pinned as one contract rather than two independent half-truths.

@test "READ PATH: inbox delivers a hostile body VERBATIM (not truncated at the escaped quote)" {
  CC_BUS_ACTOR=remote "$BUS" post tester "$HOSTILE" >/dev/null
  run "$BUS" inbox
  [ "$status" -eq 0 ]
  [[ "$output" == *"$HOSTILE"* ]]
}

@test "READ PATH: work --json emits VALID JSON for hostile evidence and round-trips it" {
  CC_BUS_ACTOR=remote "$BUS" "done" I-9 --evidence "$HOSTILE" >/dev/null
  "$BUS" work --json > "$BATS_TEST_TMPDIR/work.json"
  # Two independent failures are possible and both must be caught: output no parser accepts
  # (a raw `"` interpolated into the emitter), and output that parses but lost bytes.
  run python3 -c '
import json, sys
want = open(sys.argv[2]).read()
rows = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
assert len(rows) == 1, rows
assert rows[0]["evidence"] == want, (rows[0]["evidence"], want)
assert rows[0]["item"] == "I-9", rows
' "$BATS_TEST_TMPDIR/work.json" "$BATS_TEST_TMPDIR/want"
  [ "$status" -eq 0 ]
}

@test "READ PATH: actors --json emits VALID JSON for a hostile note and round-trips it" {
  "$BUS" hello --note "$HOSTILE" >/dev/null
  "$BUS" actors --json > "$BATS_TEST_TMPDIR/actors.json"
  run python3 -c '
import json, sys
want = open(sys.argv[2]).read()
rows = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
assert len(rows) == 1, rows
assert rows[0]["note"] == want, (rows[0]["note"], want)
assert rows[0]["actor"] == "tester", rows
' "$BATS_TEST_TMPDIR/actors.json" "$BATS_TEST_TMPDIR/want"
  [ "$status" -eq 0 ]
}

@test "a secret-shaped body is REFUSED with exit 3 and writes nothing" {
  run "$BUS" post peer "here is ghp_abcdefghij0123456789 for you"
  [ "$status" -eq 3 ]
  [[ "$output" == *REFUSED* ]] || false
  [ ! -f "$CC_BUS_DIR/actors/tester.jsonl" ]
}

@test "an ordinary body is NOT refused (the guard is not a blanket denial)" {
  run "$BUS" post peer "ordinary status update, no credentials here"
  [ "$status" -eq 0 ]
  [ -f "$CC_BUS_DIR/actors/tester.jsonl" ]
}

# ── the secret gate, at the size it is actually for ─────────────────────────────────────────────
# The two tests above pin the gate on ~40-byte bodies, and a 40-byte body is the one regime in which
# the gate cannot fail. Measured 2026-08-28, the REAL binary, 1,000 trials per cell at load ~28-30
# (probe254-cond2.sh), on the pre-fix `printf '%s' "$text" | grep -qE "$SECRET_RE"`:
#
#     multi-line, secret on line 1, 120,000 B   1,000/1,000 WROTE THE SECRET
#     multi-line, secret on line 1, 223,869 B   1,000/1,000 WROTE THE SECRET
#     multi-line, NO secret,        223,869 B       0/1,000 wrong
#     SINGLE-line, secret at head,  223,869 B       0/1,000 wrong
#     multi-line, secret on the LAST line,      0/1,000 wrong
#     multi-line, secret on line 1,  37,121 B       0/1,000 wrong
#
# Three things that table says, and the size below is chosen from it rather than picked:
#   * It is not a race. 1,000/1,000 is deterministic; `grep -q` exits on the first match and
#     pipefail promotes the producer's SIGPIPE, so the `if` reads FALSE and scrub falls through
#     and RETURNS THE TEXT. The record is written to what this file calls a PUBLIC, append-only
#     git history that a push cannot take back.
#   * Only a body that CARRIES a secret can invert, because only a match makes grep exit early.
#     Every size ever measured for this site was measured over ordinary traffic — the population
#     that is correct at every size — so no sample of ordinary records could ever have ranked it.
#   * The decision unit is the LINE, not the byte: 223,869 B on one line is safe and the same
#     223,869 B over 3,293 lines is not.
# 120,000 B / 1,766 lines is past the always-inverted floor and well under ARG_MAX (1,048,576), so
# this arm is deterministic by construction rather than one-in-twenty. It survives any rewording of
# the fix because it drives the real CLI and asserts the CONTRACT, not a spelling.
@test "the secret gate REFUSES a credential in a LARGE multi-line body (the regime it is actually for)" {
  big="$(awk 'BEGIN{
    printf "%s\n", "ghp_abcdefghij0123456789"
    line = "the quick brown fox jumps over the lazy dog and files a backlog row"
    n = 25
    while (n < 120000) { printf "%s\n", line; n += length(line) + 1 }
  }')"
  [ "${#big}" -gt 119000 ]
  nl="$(printf '%s' "$big" | grep -c '')"
  [ "$nl" -gt 1000 ]
  run "$BUS" post peer "$big"
  [ "$status" -eq 3 ]
  [[ "$output" == *REFUSED* ]] || false
  [ ! -f "$CC_BUS_DIR/actors/tester.jsonl" ]
}

# The NEG control for the arm above. Without it that arm passes on a gate that refuses EVERYTHING,
# which is the failure a one-sided size test would call a fix (#233's scar, and the same reason the
# 40-byte pair above has two halves). Same size, same line count, no credential.
@test "a large CLEAN body is still accepted (the size arm cannot pass by refusing everything)" {
  big="$(awk 'BEGIN{
    line = "the quick brown fox jumps over the lazy dog and files a backlog row"
    n = 0
    while (n < 120000) { printf "%s\n", line; n += length(line) + 1 }
  }')"
  [ "${#big}" -gt 119000 ]
  run "$BUS" post peer "$big"
  [ "$status" -eq 0 ]
  [ -f "$CC_BUS_DIR/actors/tester.jsonl" ]
}

# The class arm, scoped to EXACTLY the two function bodies this change drains — never file-wide.
# A file-wide count would convict the --selftest assertion at :1008, which is a different case: its
# feed is the selftest's own two-record fixture bus and its inversion is a loud false `badp`, the
# safe direction. A gate whose span exceeds its subject convicts its neighbours (#242's scar).
@test "scrub and cmd_inbox ask their questions without piping into an early-exiting reader" {
  for fn in scrub cmd_inbox; do
    body="$(awk -v f="$fn" '$0 ~ "^" f "\\(\\) \\{" { inb = 1 } inb { print } inb && /^\}/ { exit }' "$REPO/bin/cc-bus")"
    # The extraction must have found something, or this arm passes vacuously on an empty string.
    [ -n "$body" ] || false
    [ "$(printf '%s\n' "$body" | grep -c '')" -gt 3 ]
    # COMMENT LINES ARE STRIPPED FIRST, and that is load-bearing rather than tidiness: the drained
    # site now carries a comment quoting the hazardous spelling in order to explain it, so a raw
    # count over the body convicts the FIXED file on its own documentation. This arm went red for
    # exactly that reason before the strip existed — one hit, and it was the comment.
    code="$(printf '%s\n' "$body" | grep -v '^[[:space:]]*#')"
    [ -n "$code" ] || false
    # `grep -c`, never `grep -q`: a bare assertion on a zero count fails the test itself.
    [ "$(printf '%s\n' "$code" | grep -cE '\|[[:space:]]*(/usr/bin/|/bin/)?g?e?f?grep[[:space:]]+-[A-Za-z]*q')" -eq 0 ]
  done
}

@test "done requires --evidence" {
  run "$BUS" "done" SOME-ITEM
  [ "$status" -eq 2 ]
  [[ "$output" == *evidence* ]]
}

@test "work folds last-transition-wins across two actors" {
  CC_BUS_ACTOR=a "$BUS" claim I-1 >/dev/null
  CC_BUS_ACTOR=b "$BUS" claim I-2 >/dev/null
  CC_BUS_ACTOR=a "$BUS" "done"  I-1 --evidence sha123 >/dev/null
  run "$BUS" work
  [ "$status" -eq 0 ]
  [[ "$output" == *"I-1"*"done"* ]] || false
  [[ "$output" == *"I-2"*"claimed"*"b"* ]]
}

@test "an absent bus is an empty fold, not an error (the fresh-clone state)" {
  run env CC_BUS_DIR="$BATS_TEST_TMPDIR/nonexistent" "$BUS" fold --json
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "an unknown verb exits 2 rather than doing something surprising" {
  run "$BUS" frobnicate
  [ "$status" -eq 2 ]
}

@test "ASYMMETRY: fold --refs reads a shard that exists ONLY on another branch" {
  # Anthropic's cloud proxy pins a sandbox's `git push` to its own working branch, so an
  # off-box worker's records never reach trunk by its own action. This is the read path that
  # makes those records visible, and the control is the default fold, which must NOT see them.
  command -v git >/dev/null || skip "git unavailable"
  g() { git -c user.email=t@example.com -c user.name=T "$@"; }
  local root="$BATS_TEST_TMPDIR/refs"; mkdir -p "$root"; cd "$root"
  git init -q .; mkdir -p bus/actors
  echo '{"seed":1}' > bus/actors/seed.jsonl; g add -A; g commit -qm seed

  # A "cloud worker" lands a record on ITS OWN branch only.
  g checkout -q -b cloud-worker
  CC_BUS_DIR="$root/bus" CC_BUS_ACTOR=cloud-9 "$BUS" "done" ITEM-X --evidence cafe123 >/dev/null
  g add -A; g commit -qm "cloud shard"
  g checkout -q master 2>/dev/null || g checkout -q main

  # CONTROL: the default worktree fold must NOT see it (else --refs proves nothing).
  run env CC_BUS_DIR="$root/bus" "$BUS" fold --json
  [ "$status" -eq 0 ]
  [[ "$output" != *cafe123* ]] || false

  # SUBJECT: --refs reaches into the branch and finds it.
  run env CC_BUS_DIR="$root/bus" CC_BUS_REF_GLOB='refs/heads/*' "$BUS" fold --json --refs
  [ "$status" -eq 0 ]
  [[ "$output" == *cafe123* ]]
}

@test "the SHIPPED default ref glob reaches a real remote-tracking branch" {
  # REGRESSION. Both --refs tests above pin CC_BUS_REF_GLOB='refs/heads/*' — one segment
  # deep, where a single `*` suffices — so neither could see that the SHIPPED default was
  # `refs/remotes/*`, which git's for-each-ref matches with wildmatch under WM_PATHNAME.
  # There `*` does not cross a `/`, and every remote-tracking ref is at least
  # `refs/remotes/<remote>/<branch>` — so the default matched ZERO refs and `fold --refs`,
  # the entire cloud→local read path, was a silent no-op in production while the suite was
  # green. This test therefore pins NO glob: it asserts the default itself.
  command -v git >/dev/null || skip "git unavailable"
  g() { git -c user.email=t@example.com -c user.name=T "$@"; }
  local root="$BATS_TEST_TMPDIR/shipped"; mkdir -p "$root"; cd "$root"
  git init -q --bare origin.git
  git clone -q origin.git work 2>/dev/null; cd work
  mkdir -p bus/actors; echo '{"seed":1}' > bus/actors/seed.jsonl
  g add -A; g commit -qm seed; git push -q origin HEAD:refs/heads/main

  # A cloud worker pushes to a SLASHED branch name — the real shape the proxy pins it to,
  # and one that `refs/remotes/*` cannot match even at the remote/branch level.
  g checkout -q -b claude/fire-20260829T000000Z-1
  CC_BUS_DIR="$root/work/bus" CC_BUS_ACTOR=vm-x "$BUS" "done" ITEM-Z --evidence d00dfeed >/dev/null
  g add -A; g commit -qm "cloud shard"
  git push -q origin HEAD:refs/heads/claude/fire-20260829T000000Z-1

  # Return to a tree WITHOUT the record, and fetch so it exists only as a remote-tracking ref.
  g checkout -q main 2>/dev/null || g checkout -q master
  git fetch -q origin
  grep -q d00dfeed bus/actors/*.jsonl && false   # CONTROL: not in the worktree

  # CONTROL: the plain worktree fold must not see it.
  run env CC_BUS_DIR="$root/work/bus" "$BUS" fold --json
  [ "$status" -eq 0 ]
  [[ "$output" != *d00dfeed* ]] || false

  # SUBJECT: --refs with NO CC_BUS_REF_GLOB override — the shipped default must reach it.
  run env CC_BUS_DIR="$root/work/bus" "$BUS" fold --json --refs
  [ "$status" -eq 0 ]
  [[ "$output" == *d00dfeed* ]]
}

@test "folding across refs de-duplicates a record present on several branches" {
  command -v git >/dev/null || skip "git unavailable"
  g() { git -c user.email=t@example.com -c user.name=T "$@"; }
  local root="$BATS_TEST_TMPDIR/dedupe"; mkdir -p "$root"; cd "$root"
  git init -q .; mkdir -p bus/actors
  CC_BUS_DIR="$root/bus" CC_BUS_ACTOR=w1 "$BUS" "done" ITEM-Y --evidence beef999 >/dev/null
  g add -A; g commit -qm rec
  g branch -q copy-a; g branch -q copy-b   # same record now reachable from three refs

  run env CC_BUS_DIR="$root/bus" CC_BUS_REF_GLOB='refs/heads/*' "$BUS" fold --json --refs
  [ "$status" -eq 0 ]
  n="$(printf '%s\n' "$output" | grep -c beef999)"
  [ "$n" -eq 1 ]
}

# ── the premise: two actors' shards really do merge through git ─────────────────────────

@test "PREMISE: concurrent shards rebase clean, while a shared file CONFLICTS (control)" {
  command -v git >/dev/null || skip "git unavailable"
  g() { git -c user.email=t@example.com -c user.name=T "$@"; }
  local root="$BATS_TEST_TMPDIR/premise"
  mkdir -p "$root"; cd "$root"
  git init -q --bare origin.git
  git clone -q origin.git A; git clone -q origin.git B

  cd A
  mkdir -p bus/actors; echo '{"seed":0}' > shared.jsonl; echo '{"seed":0}' > bus/actors/seed.jsonl
  g add -A; g commit -qm seed; git push -q origin HEAD:refs/heads/main
  git checkout -q -B main; git branch -q --set-upstream-to=origin/main main
  cd ../B; git fetch -q origin; git checkout -q -B main origin/main
  git branch -q --set-upstream-to=origin/main main

  # CONTROL: one shared file, two appenders → must conflict. If this does not fire, the
  # subject case below proves nothing.
  cd ../A; echo '{"a":1}' >> shared.jsonl; g commit -qam A; git push -q
  cd ../B; echo '{"b":1}' >> shared.jsonl; g commit -qam B
  run g pull --rebase
  [ "$status" -ne 0 ]
  [ -n "$(git diff --name-only --diff-filter=U)" ]
  git rebase --abort || true
  git reset -q --hard origin/main

  # SUBJECT: per-actor shards, two appenders → must merge clean and push.
  cd ../A
  CC_BUS_DIR="$PWD/bus" CC_BUS_ACTOR=alpha "$BUS" post beta "from A" >/dev/null
  g add -A; g commit -qm "alpha shard"; git push -q
  cd ../B; git fetch -q
  CC_BUS_DIR="$PWD/bus" CC_BUS_ACTOR=beta "$BUS" post alpha "from B" >/dev/null
  g add -A; g commit -qm "beta shard"
  run g pull --rebase
  [ "$status" -eq 0 ]
  [ -z "$(git diff --name-only --diff-filter=U)" ]
  run git push -q
  [ "$status" -eq 0 ]

  # And both actors' records survive the merge — a clean rebase that dropped one would
  # pass every assertion above.
  run env CC_BUS_DIR="$PWD/bus" "$BUS" fold --json
  [ "$status" -eq 0 ]
  [[ "$output" == *"from A"* ]] || false
  [[ "$output" == *"from B"* ]]
}

# ── the bridge, with the local tools stubbed ────────────────────────────────────────────

stub_helpers() {
  mkdir -p "$BATS_TEST_TMPDIR/stub"
  cat > "$BATS_TEST_TMPDIR/stub/cc-backlog" <<'STUB'
#!/bin/bash
echo "$*" >> "$CALLS"
# HOSTILE1's title is written as the real ledger would write it — ESCAPED. cc-bus must decode
# it before re-emitting, or it publishes a doubly-escaped (or truncated) title onto the bus.
# Emitted via cat, not printf: printf would eat the backslashes in the format string.
[ "${1:-}" = "list" ] && cat <<'JSON'
[{"id":"ABC123","title":"an offered item","dodRef":"docs/p.md"},{"id":"HOSTILE1","title":"a \"quoted\" title with \\ backslash","dodRef":"docs/p.md"}]
JSON
exit 0
STUB
  cat > "$BATS_TEST_TMPDIR/stub/cc-notify" <<'STUB'
#!/bin/bash
echo "$*" >> "$CALLS"
echo "cc-notify: verdict=delivered enqueued=1" >&2
exit 0
STUB
  chmod +x "$BATS_TEST_TMPDIR/stub/cc-backlog" "$BATS_TEST_TMPDIR/stub/cc-notify"
  export CALLS="$BATS_TEST_TMPDIR/calls.log"; : > "$CALLS"
  export CC_BUS_BACKLOG_BIN="$BATS_TEST_TMPDIR/stub/cc-backlog"
  export CC_BUS_NOTIFY_BIN="$BATS_TEST_TMPDIR/stub/cc-notify"
}

@test "drain without --apply calls no local tool" {
  stub_helpers
  CC_BUS_ACTOR=remote "$BUS" "done" ABC123 --evidence deadbee >/dev/null
  run "$BUS" drain
  [ "$status" -eq 0 ]
  [[ "$output" == *would* ]] || false
  [ ! -s "$CALLS" ]
}

@test "drain --apply closes the item through cc-backlog with the remote's evidence" {
  stub_helpers
  CC_BUS_ACTOR=remote "$BUS" "done" ABC123 --evidence deadbee >/dev/null
  run "$BUS" drain --apply
  [ "$status" -eq 0 ]
  grep -q 'done ABC123 --evidence deadbee' "$CALLS"
}

@test "drain --apply twice is idempotent (the poll-loop safety property)" {
  stub_helpers
  CC_BUS_ACTOR=remote "$BUS" "done" ABC123 --evidence deadbee >/dev/null
  "$BUS" drain --apply >/dev/null
  : > "$CALLS"
  run "$BUS" drain --apply
  [ "$status" -eq 0 ]
  [ ! -s "$CALLS" ]
}

@test "READ PATH: drain hands the hostile body to cc-notify VERBATIM (dry-run and --apply)" {
  stub_helpers
  CC_BUS_ACTOR=remote "$BUS" post tester "$HOSTILE" >/dev/null

  run "$BUS" drain
  [ "$status" -eq 0 ]
  [[ "$output" == *"$HOSTILE"* ]] || false

  run "$BUS" drain --apply
  [ "$status" -eq 0 ]
  # The stub logs "$*", so this asserts what the LOCAL mailbox would actually have received.
  grep -qF 'he said "hi" \ then left' "$CALLS"
  grep -qF 'and wrote a second line' "$CALLS"
}

@test "READ PATH: offer decodes the ledger's ESCAPED title before republishing it" {
  stub_helpers
  run "$BUS" offer HOSTILE1
  [ "$status" -eq 0 ]
  # The bus record must be valid JSON whose body is the title the ledger meant — neither
  # truncated at `a \` nor double-escaped into `a \\"quoted\\"`.
  run python3 -c '
import json, sys
rows = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
offers = [r for r in rows if r["kind"] == "offer"]
assert len(offers) == 1, rows
assert offers[0]["body"] == "a \"quoted\" title with \\ backslash", offers[0]["body"]
assert offers[0]["item"] == "HOSTILE1", offers
' "$CC_BUS_DIR/actors/tester.jsonl"
  [ "$status" -eq 0 ]
}

@test "offer refuses an id the local ledger does not hold" {
  stub_helpers
  run "$BUS" offer NOSUCH
  [ "$status" -eq 2 ]
  [[ "$output" == *"no such item"* ]]
}

@test "offer publishes the ledger's title, not a caller-supplied string" {
  stub_helpers
  run "$BUS" offer ABC123
  [ "$status" -eq 0 ]
  grep -q '"kind":"offer"' "$CC_BUS_DIR/actors/tester.jsonl"
  grep -q 'an offered item' "$CC_BUS_DIR/actors/tester.jsonl"
}

@test "HERMETIC: cc-bus wrote none of its own artifacts into the live stores" {
  # The guard this repo learned by having a suite put 510 records in the live alarm store.
  #
  # SPAN NOTE — the first cut of this test grepped all of ~/.claude/autonomy/ for
  # "BATS_TEST_TMPDIR" and failed, convicting cc-bus for two things it did not do: a peer's
  # backlog item whose PROSE discusses that variable, and a postland verifier worktree that
  # is a full checkout of this repo and so contains tests/*.bats verbatim. An assertion whose
  # span exceeds its subject is a tripwire for other people's work, not a guard on mine.
  # So: assert cc-bus's OWN default artifacts, which only cc-bus can create.

  # (1) The applied-cursor's default path, checked against the REAL home (setup() fixtures
  #     $HOME, which prevents the leak; this proves it never happened).
  [ ! -e "$REAL_HOME/.claude/autonomy/bus-applied" ]
  [ ! -e "$HOME/.claude/autonomy/bus-applied" ]

  # (2) No test actor leaked a shard into the repo's real bus.
  [ ! -e "$REPO/bus/actors/tester.jsonl" ]
  [ ! -e "$REPO/bus/actors/cloud-9.jsonl" ]
  [ ! -e "$REPO/bus/actors/remote.jsonl" ]

  # (3) The default bus resolves inside a repo, never into $HOME.
  run env -u CC_BUS_DIR bash -c "cd '$REPO' && '$BUS' where"
  [ "$status" -eq 0 ]
  [ "$output" = "$REPO/bus" ]
}
