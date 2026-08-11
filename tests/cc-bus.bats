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

@test "selftest passes 20/20 (a zero-check suite must not 'pass')" {
  run "$BUS" --selftest
  [ "$status" -eq 0 ]
  n="$(printf '%s' "$output" | grep -c '^  ok ')"
  [ "$n" -eq 20 ]
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
