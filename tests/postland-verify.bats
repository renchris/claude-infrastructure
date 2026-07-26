#!/usr/bin/env bats
# postland-verify.sh — the ASYNC POST-LAND VERIFICATION NET.
#
# RED-PROOF suite written against the FROZEN CONTRACT, never against the script:
# every expected value below is derived from a contract clause quoted in a comment
# beside the assertion. Nothing here was obtained by running the SUT first.
#
# CONTRACT (the clause each test binds to):
#   C1 verbs    --run-if-needed | --run <sha> | bisect <file> <good> <bad> |
#               is-green <sha> (0 stamped-green / 1 not) | status | --selftest
#   C2 killsw   POSTLAND_VERIFY=off  =>  immediate exit 0
#   C3 state    $CC_POSTLAND_DIR/{stamps/<tree-sha>.json,last-green,queue,
#               run.lock.d/,flakes.jsonl,runner.log}   (the SUT owns creation)
#   C4 stamp    {tree,commit,verdict:"green"|"red",failing[],ts,run_s,retries,
#               checks,shellcheck_advisory}
#   C5 target   origin/main of $CC_POSTLAND_REPO; ABSTAIN (exit 0) when that
#               TREE already has a stamp
#   C6 mutex    run.lock.d mkdir+pid — a second LIVE instance exits 0 quietly;
#               a DEAD-pid lock is reaped and the run proceeds
#   C7 verdict  `bats tests/` inside the once-created DETACHED $CC_POSTLAND_WORKTREE
#   C8 retries  the failing FILE is re-run alone up to 2 more times;
#               >=2/3 fails => reproducible RED; 1/3 => flake (flakes.jsonl,
#               EXCLUDED from the verdict); all-flake => verdict green
#   C9 green    stamp green + last-green advances to the commit sha
#   C10 red     stamp red, last-green NOT advanced,
#               $CC_PAGES_DIR/postland-red-<culprit12>.page (line 1 = epoch),
#               backlog add attempted via $CC_BACKLOG_BIN, osascript attempted
#   C11 idl     EVERY invocation appends a line to $CC_IDL with
#               check:"postland-verify", decision:"fired"|"abstained"
#   C12 requeue after a run it re-resolves origin/main and loops once if it moved
#   C13 cut     a non-zero run emitting ZERO `not ok` named no failing test => it was
#               TRUNCATED (killed/starved), not red. It stamps verdict "cut" for
#               diagnosability, but a cut is a DIAGNOSTIC, never a verdict: C5's
#               abstain fires only on green|red, so a cut tree is RE-RUN next sweep
#               (abstaining on it strands the tree unverified forever and keeps
#               is-green false, which makes ship-land call the net INERT). Bounded:
#               after $CC_POSTLAND_CUT_MAX consecutive cuts on one tree an honest
#               postland-cut-<tree12>.page that names no test + a cool-off; any real
#               verdict clears both the streak and the page. BOTH stamp-consulting
#               call sites are verdict-aware — the entry gate AND C12's requeue-loop
#               break — so a mid-sweep move onto a cut tree is verified, not dropped.
#
# ISOLATION: scratch bare origin + clone under $BATS_TEST_TMPDIR, fresh $HOME, and
# argv-recording stubs for cc-backlog/osascript/cc-notify on PATH. No real repo, no
# real ~/.claude state, no network. Exit codes are asserted ONLY where the contract
# fixes them (0 for kill-switch/abstain/lock-skip/green); a RED run's exit code is
# unspecified by the contract, so it is deliberately NOT asserted.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SUT="${CC_POSTLAND_BIN:-$REPO/scripts/postland-verify.sh}"
  [ -f "$SUT" ] || skip "postland-verify.sh not present in this worktree"

  export HOME="$BATS_TEST_TMPDIR/home"
  export CC_POSTLAND_DIR="$BATS_TEST_TMPDIR/state"     # C3 — SUT creates it
  export CC_POSTLAND_REPO="$BATS_TEST_TMPDIR/repo"
  export CC_POSTLAND_WORKTREE="$BATS_TEST_TMPDIR/pv-worktree"
  export CC_PAGES_DIR="$BATS_TEST_TMPDIR/pages"        # externally owned dir
  export CC_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  # Admission control OFF: every --run-if-needed below reaches run_target → gate_admit, and this
  # suite runs on exactly the loaded box that makes it defer. Left on, each of those stalls for
  # CC_GATE_ADMIT_MAX_WAIT and the suite reads as hung. Shedding has its own tests (--selftest).
  export CC_GATE_MAX_LOAD=0
  STUB="$BATS_TEST_TMPDIR/bin"; REC="$BATS_TEST_TMPDIR/rec"
  export CC_BACKLOG_BIN="$STUB/cc-backlog"
  mkdir -p "$HOME" "$CC_PAGES_DIR" "$STUB" "$REC"
  local s
  for s in cc-backlog osascript cc-notify; do
    printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "%s/%s.argv"\nexit 0\n' "$REC" "$s" > "$STUB/$s"
    chmod +x "$STUB/$s"
  done
  export PATH="$STUB:$PATH"

  ORIGIN="$BATS_TEST_TMPDIR/origin.git"
  R="$CC_POSTLAND_REPO"
  git init -q --bare "$ORIGIN"
  git clone -q "$ORIGIN" "$R" 2>/dev/null
  git -C "$R" symbolic-ref HEAD refs/heads/main
  git -C "$R" config user.email tester@example.com
  git -C "$R" config user.name tester
  mkdir -p "$R/tests"
  printf '@test "p" { true; }\n' > "$R/tests/ok.bats"   # a passing suite => green
  printf '#!/bin/bash\nexit 0\n' > "$R/foo.sh"; chmod +x "$R/foo.sh"
  push_commit base
}

teardown() {
  # `|| true` matters: an already-exited sleep makes kill the FAILING last command
  # of the && list, which errexit would turn into a spurious test failure.
  [ -f "$BATS_TEST_TMPDIR/live.pid" ] \
    && kill "$(cat "$BATS_TEST_TMPDIR/live.pid")" 2>/dev/null || true
  true
}

# ── fixture helpers ─────────────────────────────────────────────────────────────
push_commit() { git -C "$R" add -A; git -C "$R" commit -q -m "$1"; git -C "$R" push -qf origin HEAD:main; }
origin_head() { git -C "$R" rev-parse origin/main; }
origin_tree() { git -C "$R" rev-parse "origin/main^{tree}"; }
stamps_n()    { find "$CC_POSTLAND_DIR/stamps" -name '*.json' 2>/dev/null | wc -l | tr -d ' '; }
idl_last()    { tail -n1 "$CC_IDL" | jq -r "$1"; }
pages_n()     { find "$CC_PAGES_DIR" -name 'postland-red-*.page' 2>/dev/null | wc -l | tr -d ' '; }
cut_pages_n() { find "$CC_PAGES_DIR" -name 'postland-cut-*.page' 2>/dev/null | wc -l | tr -d ' '; }

# A `bats` stand-in on $CC_POSTLAND_BATS reproducing the fingerprint of a REAL truncation — the
# peer `pkill -9 -f bats-core/bats` this clause exists for: a plan promising N results, fewer
# emitted, ZERO `not ok`, exit 137 (128+SIGKILL). Stubbing the PRODUCER, not the symptom.
stub_bats() {   # $1 = name, $2 = body after the --version guard; echoes the stub's path
  printf '#!/bin/bash\n[ "$1" = "--version" ] && { echo "Bats 1.13.0"; exit 0; }\n%s\n' "$2" \
    > "$STUB/bats-$1"
  chmod +x "$STUB/bats-$1"
  printf '%s' "$STUB/bats-$1"
}

# a tests/ helper whose exit code is driven by an out-of-worktree state file, so it
# survives the SUT's fresh checkout and its per-file retry ladder (C8)
add_stateful_test() {   # $1 = basename, $2 = body of the helper script
  printf '%s\n' "$2" > "$R/tests/$1-helper.sh"
  chmod +x "$R/tests/$1-helper.sh"
  printf '@test "%s" { run bash "$BATS_TEST_DIRNAME/%s-helper.sh"; [ "$status" -eq 0 ]; }\n' \
    "$1" "$1" > "$R/tests/$1.bats"
}

# ── C2 kill switch ──────────────────────────────────────────────────────────────
@test "POSTLAND_VERIFY=off is an immediate no-op exit 0" {
  run env POSTLAND_VERIFY=off bash "$SUT" --run-if-needed
  [ "$status" -eq 0 ]                    # C2
  [ "$(stamps_n)" = "0" ]                # no verification happened...
  [ ! -e "$CC_POSTLAND_WORKTREE" ]       # ...not even the C7 worktree
}

# ── C9 green ────────────────────────────────────────────────────────────────────
@test "green run stamps the target TREE green, full schema, and advances last-green" {
  target="$(origin_head)"; tree="$(origin_tree)"
  run bash "$SUT" --run-if-needed
  [ "$status" -eq 0 ]
  s="$CC_POSTLAND_DIR/stamps/$tree.json"          # C3: stamps/<tree-sha>.json
  [ -f "$s" ]
  run jq -r '.verdict' "$s"; [ "$output" = "green" ]     # C9 (tests/ok.bats passes)
  run jq -r '.tree'    "$s"; [ "$output" = "$tree" ]     # C4
  run jq -r '.commit'  "$s"; [ "$output" = "$target" ]   # C4
  # C4 — the full stamp field set, so a partial writer goes RED here
  run jq -e 'has("tree") and has("commit") and has("verdict") and has("failing")
             and has("ts") and has("run_s") and has("retries") and has("checks")
             and has("shellcheck_advisory")' "$s"
  [ "$status" -eq 0 ]
  [ "$(cat "$CC_POSTLAND_DIR/last-green")" = "$target" ] # C9: last-green = commit sha
}

# ── C1 is-green ─────────────────────────────────────────────────────────────────
@test "is-green: 0 for a stamped-green sha, 1 for an unverified one" {
  target="$(origin_head)"
  run bash "$SUT" --run-if-needed
  [ "$status" -eq 0 ]
  run bash "$SUT" is-green "$target"
  [ "$status" -eq 0 ]                              # C1: stamped green => 0
  # an unverified commit: real sha, real (different) tree, never run through the net
  echo change >> "$R/foo.sh"
  git -C "$R" add -A; git -C "$R" commit -q -m unverified
  run bash "$SUT" is-green "$(git -C "$R" rev-parse HEAD)"
  [ "$status" -eq 1 ]                              # C1: not stamped => 1
}

# ── C5 abstain ──────────────────────────────────────────────────────────────────
@test "re-invocation on an already-stamped tree abstains without re-running" {
  run bash "$SUT" --run-if-needed
  [ "$status" -eq 0 ]
  before="$(stamps_n)"
  run bash "$SUT" --run-if-needed
  [ "$status" -eq 0 ]                              # C5: abstain is exit 0
  [ "$(stamps_n)" = "$before" ]                    # no second verification
  [ "$(idl_last '.decision')" = "abstained" ]      # C11
}

# ── C11 IDL ─────────────────────────────────────────────────────────────────────
@test "every invocation appends one postland-verify IDL line" {
  run bash "$SUT" --run-if-needed
  [ "$status" -eq 0 ]
  [ -f "$CC_IDL" ]
  # grep -c '' (not wc -l) so a final unterminated line still counts
  [ "$(grep -c '' "$CC_IDL")" = "1" ]              # C11: one line per invocation
  [ "$(idl_last '.check')" = "postland-verify" ]
  [ "$(idl_last '.decision')" = "fired" ]          # C11: it ran
  run bash "$SUT" --run-if-needed
  [ "$(grep -c '' "$CC_IDL")" = "2" ]              # the abstain also records
}

# ── C1 status ───────────────────────────────────────────────────────────────────
@test "status is a read-only report that exits 0" {
  run bash "$SUT" --run-if-needed
  [ "$status" -eq 0 ]
  before="$(stamps_n)"
  run bash "$SUT" status
  [ "$status" -eq 0 ]                              # C1
  [ "$(stamps_n)" = "$before" ]                    # reporting verifies nothing
}

# ── C7 worktree ─────────────────────────────────────────────────────────────────
@test "verification runs in a DETACHED worktree, leaving CC_POSTLAND_REPO untouched" {
  target="$(origin_head)"
  repo_head_before="$(git -C "$R" rev-parse HEAD)"
  run bash "$SUT" --run-if-needed
  [ "$status" -eq 0 ]
  [ -d "$CC_POSTLAND_WORKTREE" ]                                     # C7
  [ "$(git -C "$CC_POSTLAND_WORKTREE" rev-parse HEAD)" = "$target" ] # checked out the target
  run git -C "$CC_POSTLAND_WORKTREE" symbolic-ref -q HEAD
  [ "$status" -ne 0 ]                                              # C7: detached
  git -C "$R" worktree list | grep -q "$(basename "$CC_POSTLAND_WORKTREE")"
  # ...and the repo's own checkout is not where tests ran
  [ "$(git -C "$R" rev-parse HEAD)" = "$repo_head_before" ]
  [ -z "$(git -C "$R" status --porcelain)" ]
}

# ── C5 tree-keying ──────────────────────────────────────────────────────────────
@test "stamps key on TREE: an amended commit (same tree, new sha) abstains" {
  run bash "$SUT" --run-if-needed
  [ "$status" -eq 0 ]
  before="$(stamps_n)"; tree_before="$(origin_tree)"; head_before="$(origin_head)"
  # --amend with no staged change => identical tree, different commit sha
  git -C "$R" commit -q --amend -m "same tree, new sha"
  git -C "$R" push -qf origin HEAD:main
  [ "$(origin_tree)" = "$tree_before" ]            # fixture invariant: tree unchanged
  [ "$(origin_head)" != "$head_before" ]           # fixture invariant: sha changed
  run bash "$SUT" --run-if-needed
  [ "$status" -eq 0 ]
  [ "$(stamps_n)" = "$before" ]                    # C5: keyed on tree, not commit
  [ "$(idl_last '.decision')" = "abstained" ]      # C11
}

# ── C12 requeue ─────────────────────────────────────────────────────────────────
@test "a target that moved after a green run is verified on the next invocation" {
  run bash "$SUT" --run-if-needed
  [ "$status" -eq 0 ]
  [ "$(stamps_n)" = "1" ]
  echo moved >> "$R/foo.sh"                        # new tree => supersession
  push_commit "superseding commit"
  moved_tree="$(origin_tree)"
  run bash "$SUT" --run-if-needed
  [ "$status" -eq 0 ]
  [ "$(stamps_n)" = "2" ]                          # C12: the new tree is verified too
  [ -f "$CC_POSTLAND_DIR/stamps/$moved_tree.json" ]
}

# ── C6 mutex ────────────────────────────────────────────────────────────────────
@test "a LIVE run.lock.d holder makes the second instance exit 0 without running" {
  mkdir -p "$CC_POSTLAND_DIR/run.lock.d"
  sleep 300 >/dev/null 2>&1 &
  live=$!
  echo "$live" > "$BATS_TEST_TMPDIR/live.pid"      # teardown kills it
  echo "$live" > "$CC_POSTLAND_DIR/run.lock.d/pid" # a lock held by a LIVE pid
  run bash "$SUT" --run-if-needed
  [ "$status" -eq 0 ]                              # C6: quiet exit 0
  [ "$(stamps_n)" = "0" ]                          # it did NOT verify
  [ ! -f "$CC_POSTLAND_DIR/last-green" ]
}

@test "a DEAD-pid run.lock.d is reaped and the run proceeds" {
  mkdir -p "$CC_POSTLAND_DIR/run.lock.d"
  bash -c 'exit 0' & dead=$!; wait "$dead" 2>/dev/null || true
  echo "$dead" > "$CC_POSTLAND_DIR/run.lock.d/pid"   # pid is gone => stale lock
  run bash "$SUT" --run-if-needed
  [ "$status" -eq 0 ]
  [ "$(stamps_n)" = "1" ]                          # C6: reaped, verification ran
  [ -f "$CC_POSTLAND_DIR/stamps/$(origin_tree).json" ]
}

# ── C10 red ─────────────────────────────────────────────────────────────────────
@test "RED run: red stamp, last-green FROZEN, page file + backlog add fired" {
  run bash "$SUT" --run-if-needed                  # establish a green baseline
  [ "$status" -eq 0 ]
  green="$(cat "$CC_POSTLAND_DIR/last-green")"
  printf '@test "f" { false; }\n' > "$R/tests/bad.bats"   # fails 3/3 => C8 red
  push_commit "the culprit"
  bad="$(origin_head)"; badtree="$(origin_tree)"
  run bash "$SUT" --run-if-needed                  # exit code on RED: unspecified
  s="$CC_POSTLAND_DIR/stamps/$badtree.json"
  [ -f "$s" ]
  run jq -r '.verdict' "$s"; [ "$output" = "red" ]                 # C10
  run jq -e '.failing | length > 0' "$s"; [ "$status" -eq 0 ]      # C4: names the file
  [ "$(cat "$CC_POSTLAND_DIR/last-green")" = "$green" ]            # C10: NOT advanced
  # C10: $CC_PAGES_DIR/postland-red-<culprit12>.page, line 1 = epoch seconds
  page="$CC_PAGES_DIR/postland-red-${bad:0:12}.page"
  [ -f "$page" ]
  head -n1 "$page" | grep -qE '^[0-9]{10,}$'
  grep -q "${bad:0:12}" "$REC/cc-backlog.argv"                     # C10: backlog add
  [ -f "$REC/osascript.argv" ]                                     # C10: notify attempt
}

# ── C8 flake ────────────────────────────────────────────────────────────────────
@test "1-of-3 flake is excluded from the verdict: green stamp, flakes.jsonl, no page" {
  # fails only on its FIRST ever run => 1 fail / 3 attempts => flake, not red
  m="$BATS_TEST_TMPDIR/flake-marker"
  add_stateful_test flaky "$(printf '#!/bin/bash\nM="%s"\n[ -f "$M" ] && exit 0\ntouch "$M"\nexit 1\n' "$m")"
  push_commit "flaky suite"
  tree="$(origin_tree)"; target="$(origin_head)"
  run bash "$SUT" --run-if-needed
  [ "$status" -eq 0 ]
  run jq -r '.verdict' "$CC_POSTLAND_DIR/stamps/$tree.json"
  [ "$output" = "green" ]                          # C8: all-flake => green
  [ -s "$CC_POSTLAND_DIR/flakes.jsonl" ]           # C8: the flake is recorded...
  grep -q flaky "$CC_POSTLAND_DIR/flakes.jsonl"    # ...and names the file
  [ "$(pages_n)" = "0" ]                           # C10 pages are RED-only
  [ "$(cat "$CC_POSTLAND_DIR/last-green")" = "$target" ] # C9 still advances
}

@test "2-of-3 failures are reproducible RED, not a flake" {
  run bash "$SUT" --run-if-needed                  # green baseline => a bisect floor
  [ "$status" -eq 0 ]
  green="$(cat "$CC_POSTLAND_DIR/last-green")"
  # fails attempts 1 and 2, passes attempt 3 => 2/3 => RED (the C8 boundary case;
  # a SUT that short-circuits at 2 fails never reaches attempt 3 — still RED)
  c="$BATS_TEST_TMPDIR/counter"
  add_stateful_test twofail "$(printf '#!/bin/bash\nC="%s"\nn=$(cat "$C" 2>/dev/null || echo 0)\nn=$((n+1))\necho "$n" > "$C"\n[ "$n" -ge 3 ] && exit 0\nexit 1\n' "$c")"
  push_commit "reproducibly failing suite"
  tree="$(origin_tree)"
  run bash "$SUT" --run-if-needed
  run jq -r '.verdict' "$CC_POSTLAND_DIR/stamps/$tree.json"
  [ "$output" = "red" ]                            # C8: >=2/3 => reproducible RED
  [ "$(pages_n)" = "1" ]                           # C10
  [ "$(cat "$CC_POSTLAND_DIR/last-green")" = "$green" ]   # C10: NOT advanced
  [ ! -s "$CC_POSTLAND_DIR/flakes.jsonl" ] || ! grep -q twofail "$CC_POSTLAND_DIR/flakes.jsonl"
}

# ── C13 CUT ≠ RED ────────────────────────────────────────────────────────────────────────────
# A TAP with ZERO `not ok` in a non-zero run was TRUNCATED (killed/starved), not failed.
# Stamping it red is a lie with teeth: the red stamp is what deploy-live.sh and ship-land's
# postland_net_live read, so with every run cut NO GREEN STAMP CAN EVER EXIST — deploy-live
# refuses forever and the liveness guard silently reads "not adopted ⇒ trust". (Measured
# 2026-07-26: 4 of the last 5 runner.log verdicts were `failing=tests/ retries=0` — all cuts.)
@test "C13: a TRUNCATED run (non-zero, ZERO not-ok) stamps CUT — not red — and never pages" {
  fake="$BATS_TEST_TMPDIR/bats-cut"
  # NOTE: must answer --version — env_fingerprint() parses it into the stamp's JSON, and a
  # fake that echoes TAP there corrupts the stamp (cost one red test to learn).
  printf '#!/bin/bash\n[ "$1" = --version ] && { echo "Bats 1.13.0"; exit 0; }\nexit 1\n' > "$fake"
  chmod +x "$fake"                                                 # rc=1 with ZERO output
  tree="$(origin_tree)"
  run env CC_POSTLAND_BATS="$fake" bash "$SUT" --run-if-needed
  s="$CC_POSTLAND_DIR/stamps/$tree.json"
  [ -f "$s" ]
  run jq -r '.verdict' "$s"; [ "$output" = "cut" ]               # NOT "red"
  [ ! -f "$CC_POSTLAND_DIR/last-green" ]                          # a cut earns nothing
  [ "$(find "$CC_PAGES_DIR" -name 'postland-red-*' | wc -l | tr -d ' ')" = "0" ]
}

@test "C13 control: a run with a REAL not-ok still stamps RED (the cut path must not swallow it)" {
  fake="$BATS_TEST_TMPDIR/bats-red"
  printf '#!/bin/bash\n[ "$1" = --version ] && { echo "Bats 1.13.0"; exit 0; }\necho "1..1"\necho "not ok 1 boom"\necho "# (in test file tests/ok.bats, line 2)"\nexit 1\n' > "$fake"
  chmod +x "$fake"
  tree="$(origin_tree)"
  run env CC_POSTLAND_BATS="$fake" bash "$SUT" --run-if-needed
  s="$CC_POSTLAND_DIR/stamps/$tree.json"
  [ -f "$s" ]
  run jq -r '.verdict' "$s"; [ "$output" = "red" ]
}

# ── C13 a CUT stamp is a DIAGNOSTIC, never a verdict ────────────────────────────
# c605a2e correctly reclassified signal-death as CUT rather than RED, and stamps
# `cut` for diagnosability. But C5's abstain keyed on stamp EXISTENCE, so the very
# next sweep abstained and the tree was NEVER re-verified — is-green stayed false,
# which drives ship-land to call the whole net INERT and degrade gates scoped→FULL.
# ASSERTION FORM: bats runs under errexit, where a non-final `[[ ]]`/`!`/`A && B` is
# errexit-EXEMPT and therefore DEAD. Everything below is a live `[ ]` or `run` + `[ ]`.

@test "C13: a cut tree is RETRIED on the next sweep, never abstained as already-stamped" {
  b="$(stub_bats killed "printf '1..3\nok 1 a\n'; exit 137")"
  export CC_POSTLAND_BATS="$b"
  tree="$(origin_tree)"
  run bash "$SUT" --run-if-needed                        # sweep 1 → the cut
  [ "$status" -eq 0 ]
  run jq -r '.verdict' "$CC_POSTLAND_DIR/stamps/$tree.json"
  [ "$output" = "cut" ]                                  # trunk's diagnostic stamp is kept
  run bash "$SUT" --run-if-needed                        # sweep 2 → MUST re-run
  [ "$status" -eq 0 ]
  [ "$(idl_last '.reason')" != "already-stamped" ]       # THE regression: it stranded here
  [ "$(pages_n)" = "0" ]                                 # a cut is still never a RED page
}

@test "C13: a REAL verdict (green/red) still abstains — the fix must not disable C5" {
  run bash "$SUT" --run-if-needed                        # real bats → green
  [ "$status" -eq 0 ]
  before="$(stamps_n)"
  run bash "$SUT" --run-if-needed
  [ "$status" -eq 0 ]
  [ "$(stamps_n)" = "$before" ]                          # C5 intact: no second verification
  [ "$(idl_last '.reason')" = "already-stamped" ]
}

@test "C13: after CUT_MAX consecutive cuts an HONEST page is written, then the box cools off" {
  b="$(stub_bats killed "printf '1..3\nok 1 a\n'; exit 137")"
  export CC_POSTLAND_BATS="$b" CC_POSTLAND_CUT_MAX=1
  run bash "$SUT" --run-if-needed
  [ "$(cut_pages_n)" = "1" ]
  p="$(find "$CC_PAGES_DIR" -name 'postland-cut-*.page' | head -1)"
  head -1 "$p" | grep -qE '^[0-9]+$'                     # page protocol: line 1 is an epoch
  grep -q 'NOT a test failure' "$p"
  run grep -c '^failing:' "$p"
  [ "$output" = "0" ]                                    # it never claims a named failing test
  run bash "$SUT" --run-if-needed                        # a hostile box is not re-fed every tick
  [ "$status" -eq 0 ]
  [ "$(idl_last '.reason')" = "cut-cooloff" ]
}

@test "C13: a green after cuts clears the streak and the standing cut page" {
  b="$(stub_bats killed "printf '1..3\nok 1 a\n'; exit 137")"
  # CUT_COOLOFF=0 so the streak still PAGES at CUT_MAX but the next sweep is not deferred —
  # this test is about a green superseding a cut, not about the cool-off (covered above).
  export CC_POSTLAND_CUT_MAX=1 CC_POSTLAND_CUT_COOLOFF=0
  CC_POSTLAND_BATS="$b" run bash "$SUT" --run-if-needed
  [ "$(cut_pages_n)" = "1" ]
  run bash "$SUT" --run-if-needed                        # real bats now → a genuine green
  [ "$status" -eq 0 ]
  tree="$(origin_tree)"
  run jq -r '.verdict' "$CC_POSTLAND_DIR/stamps/$tree.json"
  [ "$output" = "green" ]                                # the cut stamp is superseded
  [ "$(cut_pages_n)" = "0" ]                             # standing cut page cleared
  [ ! -f "$CC_POSTLAND_DIR/cuts" ]                       # streak reset
}

# The entry gate is not the only place the stamp is consulted: C12's requeue loop asks the same
# question about the tree the target MOVED to, and asked it by EXISTENCE. Fixing only the gate
# leaves the second actuator keyed on the old predicate — the moved head is dropped unverified
# for that sweep. Enumerate call sites, not mechanisms.
@test "C13: the REQUEUE loop is verdict-aware too — a move onto a CUT tree is still verified" {
  base_head="$(origin_head)"
  # 1. a REAL cut stamp for the moved-to tree, written by the real producer (never hand-forged)
  echo moved >> "$R/foo.sh"
  push_commit "the superseding commit"
  moved_head="$(origin_head)"; moved_tree="$(origin_tree)"
  b="$(stub_bats killed "printf '1..3\nok 1 a\n'; exit 137")"
  CC_POSTLAND_BATS="$b" run bash "$SUT" --run-if-needed
  run jq -r '.verdict' "$CC_POSTLAND_DIR/stamps/$moved_tree.json"
  [ "$output" = "cut" ]                                  # precondition, asserted not assumed
  # 2. rewind origin so the sweep STARTS on the unstamped base and the move lands on the cut tree
  git -C "$R" push -qf origin "$base_head:main"
  rm -f "$CC_POSTLAND_DIR/cuts"                          # isolate the loop from the cool-off path
  # 3. a stub that moves origin/main DURING the run — the C12 race, reproduced by the producer
  b2="$(stub_bats mover "git -C '$R' push -qf origin '$moved_head:main' >/dev/null 2>&1
printf '1..1\nok 1 p\n'")"
  CC_POSTLAND_BATS="$b2" run bash "$SUT" --run-if-needed
  [ "$status" -eq 0 ]
  [ "$(origin_head)" = "$moved_head" ]                   # the move really happened mid-sweep
  # THE regression: an existence-keyed break leaves this "cut" — the head lands unverified.
  run jq -r '.verdict' "$CC_POSTLAND_DIR/stamps/$moved_tree.json"
  [ "$output" = "green" ]
}

# The control above emits a `# (in test file …)` diagnostic, so it exercises the ATTRIBUTED
# path and leaves the boundary itself unguarded. This is the boundary: `not ok` present,
# diagnostic ABSENT. Both cases reach classify_failures with an EMPTY `pairs`, so a predicate
# keyed on attribution ("no failing FILE ⇒ no verdict") collapses them and silently discards a
# real regression — no stamp, no page, the tree re-verified forever. Only a predicate keyed on
# the `not ok` COUNT keeps them apart. Guarding it here is the point: the collapse was live
# once, and nothing in the suite would have caught its return.
@test "C13b: a not-ok with NO file diagnostic stays RED and carries the test NAME" {
  fake="$BATS_TEST_TMPDIR/bats-nodiag"
  printf '#!/bin/bash\n[ "$1" = --version ] && { echo "Bats 1.13.0"; exit 0; }\necho "1..1"\necho "not ok 1 boom"\nexit 1\n' > "$fake"
  chmod +x "$fake"                                    # a NAMED failure, with nothing to attribute it to
  tree="$(origin_tree)"
  run env CC_POSTLAND_BATS="$fake" bash "$SUT" --run-if-needed
  s="$CC_POSTLAND_DIR/stamps/$tree.json"
  [ -f "$s" ]                                         # NOT the cut path: a stamp must exist
  run jq -r '.verdict' "$s"; [ "$output" = "red" ]    # C10 — a named failure is a verdict
  [ ! -f "$CC_POSTLAND_DIR/last-green" ]              # C10 — last-green NOT advanced
  [ "$(pages_n)" = "1" ]                              # C10 — it PAGES (the swallow paged nothing)
  # and the page is actionable: TAP named the test, so the page must not say "(unattributed)".
  grep -q 'boom' "$CC_PAGES_DIR"/postland-red-*.page || false
}
