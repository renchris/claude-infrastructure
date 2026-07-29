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
#   C7 verdict  bats over the TREE CORPUS inside a DETACHED worktree MINTED FOR THIS RUN
#               and REMOVED on exit (v2 §4.2.1 — the reused cell carried cross-tree residue)
#   C18 partition  the corpus is tests/*.bats MINUS scripts/host-suites.manifest, passed to
#               bats as an explicit FILE LIST (never `tests/`); ONE list also indexes
#               suite_file_at, so hang attribution cannot desync from what ran. A missing
#               manifest ⇒ empty ⇒ everything runs (fail-closed toward MORE proof)
#   C19 qos     no admission control anywhere: the singleton must progress at ANY load
#   C20 revert  on a reproducible RED with a BISECTED culprit C, and only then: revert C on
#               its own branch and land it via the land lane. Refused if POSTLAND_AUTOREVERT=off ·
#               C is itself a revert · $CC_POSTLAND_DIR/reverts/<C> exists (never twice) ·
#               POSTLAND_MAX_REVERTS attempts already made this run · no land lane present.
#               An UNDECIDABLE bisect pages + backlogs and attempts ZERO reverts.
#   C21 green   a green stamp also writes <git-common-dir>/gate-green = the COMMIT sha —
#               in v2 the verifier is the only party that can make the full-suite claim
#   C22 prelint the whole-tree meta-lints run STANDALONE before the corpus, own-set seams
#               UNSET (whole-tree strict); non-zero ⇒ named RED that outranks a cut; OUR
#               bound firing proves nothing ⇒ cut, never red and never green
#   C23 ladder  a RETRY whose OWN bound fired decides NOTHING — the same rule C22 applies to a lint
#               and classify_hang applies to the suite run. It is neither a fail (nothing proven) nor
#               a pass (nothing cleared) ⇒ the run downgrades to a CUT and is retried next sweep.
#               The re-run is the failing TEST (`bats -f`), not its whole file, so the bound can
#               actually fit what it bounds; POSTLAND_RETRY_GRANULARITY=file restores file-wide.
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
  # DELIBERATELY NOT setting CC_POSTLAND_WORKTREE: pinning it made every test exercise the
  # fixed-path override and left the DEFAULT mint path — the only one production ever uses —
  # untested. The seam still works and has its own test below; the suite drives the default.
  export CC_PAGES_DIR="$BATS_TEST_TMPDIR/pages"        # externally owned dir
  export CC_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  # v2: there is NO admission control to disable any more (C19) — the old CC_GATE_MAX_LOAD=0 export
  # lived here because every --run-if-needed reached gate_admit and stalled on this very box.
  # AUTO-REVERT OFF BY DEFAULT FOR THIS SUITE (C20): a red fixture must never be one guard away
  # from pushing. The revert tests below opt IN explicitly, so a guard that silently stopped
  # working cannot hide behind a blanket suite-wide switch.
  export POSTLAND_AUTOREVERT=off
  # Per-run worktree cells (C7) land here, so a leak is visible to the tests rather than landing
  # in the developer's real ~/Development/.worktrees.
  export CC_POSTLAND_WT_ROOT="$BATS_TEST_TMPDIR/cells"
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
cells_n()     { find "$CC_POSTLAND_WT_ROOT" -maxdepth 1 -name 'wt-*' 2>/dev/null | wc -l | tr -d ' '; }
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
  [ "$(cells_n)" = "0" ]                 # ...not even a C7 worktree cell was minted
  # (asserted by COUNTING cells, not by `[ ! -e "$CC_POSTLAND_WORKTREE" ]`: with the fixed-path
  # override no longer set, that expands to `[ ! -e "" ]`, which is vacuously true — a dead
  # assertion that would pass just as happily if the kill switch had stopped working.)
}

# ── C7 the fixed-path seam still works (production uses the default; this keeps it from rotting)
@test "C7: CC_POSTLAND_WORKTREE is still honored verbatim as the cell path" {
  export CC_POSTLAND_WORKTREE="$BATS_TEST_TMPDIR/pinned-cell"
  b="$(stub_bats pinned "printf '%s\n' \"\$PWD\" > '$REC/pinned.txt'; printf '1..1\nok 1 p\n'")"
  CC_POSTLAND_BATS="$b" run bash "$SUT" --run-if-needed
  [ "$status" -eq 0 ]
  [ "$(cat "$REC/pinned.txt")" = "$CC_POSTLAND_WORKTREE" ]   # minted AT the pinned path...
  [ ! -d "$CC_POSTLAND_WORKTREE" ]                            # ...and still torn down (C7)
  [ "$(cells_n)" = "0" ]                                      # and nothing under the default root
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
# The cell is EPHEMERAL in v2, so "where did the suite run?" can no longer be answered by
# looking at the filesystem afterwards — by then the correct answer is "nowhere". It is
# answered by a SPY standing in for bats, which records its own cwd/HEAD/detachment at the
# only moment they exist. Asserting the leftovers would have quietly become an assertion
# about teardown rather than about where the verdict was computed.
@test "verification runs in a DETACHED worktree at the target, leaving CC_POSTLAND_REPO untouched" {
  target="$(origin_head)"
  repo_head_before="$(git -C "$R" rev-parse HEAD)"
  b="$(stub_bats spy "{ echo cwd=\$PWD; echo head=\$(git rev-parse HEAD); git symbolic-ref -q HEAD >/dev/null 2>&1 && echo detached=no || echo detached=yes; test -f .git && echo islink=yes || echo islink=no; } > '$REC/where.txt'; printf '1..1\nok 1 p\n'")"
  CC_POSTLAND_BATS="$b" run bash "$SUT" --run-if-needed
  [ "$status" -eq 0 ]
  [ -f "$REC/where.txt" ]                                            # the spy really ran
  grep -q "^head=$target\$"   "$REC/where.txt"                       # C7: at the TARGET sha
  grep -q '^detached=yes$'    "$REC/where.txt"                       # C7: detached
  grep -q '^islink=yes$'      "$REC/where.txt"                       # a linked worktree, not a clone
  # C7: and NOT in the repo — whose working tree is the live ~/.claude layer
  run grep -q "^cwd=$R\$" "$REC/where.txt"
  [ "$status" -ne 0 ]
  [ "$(git -C "$R" rev-parse HEAD)" = "$repo_head_before" ]
  [ -z "$(git -C "$R" status --porcelain)" ]
}

# ── C7 lifecycle: minted per run, then removed ──────────────────────────────────
@test "C7: the worktree cell is MINTED for the run and REMOVED afterwards (no residue, no leak)" {
  # the cell must EXIST while the verdict is computed...
  b="$(stub_bats live "printf '%s\n' \"\$PWD\" > '$REC/cell.txt'; printf '1..1\nok 1 p\n'")"
  CC_POSTLAND_BATS="$b" run bash "$SUT" --run-if-needed
  [ "$status" -eq 0 ]
  cell="$(cat "$REC/cell.txt")"
  [ -n "$cell" ]
  # minted where v2 says: a live `[ ]` on prefix-stripping, so a wrong root fails the test
  [ "${cell#"$CC_POSTLAND_WT_ROOT"/wt-run-}" != "$cell" ]
  # ...and be gone afterwards, with git's own worktree list agreeing (a `rm -rf` alone would
  # leave a registered-but-missing worktree that blocks the next `worktree add` on that path).
  [ ! -d "$cell" ]
  run bash -c "git -C '$R' worktree list | grep -cF '$cell'"
  [ "$output" = "0" ]
  [ -z "$(find "$CC_POSTLAND_WT_ROOT" -maxdepth 1 -name 'wt-run-*' 2>/dev/null)" ]
  # POSITIVE CONTROL — a SECOND run mints again rather than reusing: a different path proves
  # freshness, and this test cannot pass by the verifier simply never creating a cell at all.
  CC_POSTLAND_BATS="$b" run bash "$SUT" --run-if-needed        # same tree ⇒ abstains, so move it
  echo moved >> "$R/foo.sh"; push_commit "second tree"
  CC_POSTLAND_BATS="$b" run bash "$SUT" --run-if-needed
  [ "$status" -eq 0 ]
  cell2="$(cat "$REC/cell.txt")"
  [ -n "$cell2" ]
  [ ! -d "$cell2" ]
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

# ── C23 the ladder's OWN bound: a re-run that never returned decides nothing ──────────────────────
# THE 0-GREEN-STAMP DEADLOCK, root-caused 2026-07-29. The ladder re-ran the whole FILE under
# FILE_TO=300 and counted ANY non-zero rc as a fail — 124 included, which `bounded` itself documents
# as "OUR bound fired". Every other 124 site in the SUT already refuses to read its own bound as
# evidence about the tree (C22 prelint ⇒ cut · confirm_hang ⇒ the HUNG discriminator · classify_hang
# case 1 · the stall unify). This was the ONE site that did, and that is the whole deadlock: a suite
# slower than the bound could only ever be CONVICTED, never exonerated — both retries returned 124,
# `fails` reached 3/3, and the tree got a "reproducible RED" that no re-run could ever clear. Result:
# 33 stamps, 0 green EVER, so deploy-live refused forever and the live layer sat 32 commits behind.
# MEASURED: this very suite is ~50 min solo (51 tests × scratch git repos) = 10x the bound, and
# flakes.jsonl 2026-07-28T19:39Z carries `exit 124 / notok=0` for tests/postland-verify.bats at load
# 6.61 — while the LAND gate filed that identical signal correctly as `cut-not-red`. The convicted
# suites were exactly the heaviest ones (waiting-recycle 98 tests, cc-reaper 80, ship-land 74,
# cc-backlog 61, postland-verify 51) — the tell that the bound, not the tree, was doing the deciding.
@test "C23: a retry whose OWN bound fires is a CUT, never a RED (the 0-green-stamp deadlock)" {
  run bash "$SUT" --run-if-needed                  # green baseline => last-green to freeze against
  [ "$status" -eq 0 ]
  green="$(cat "$CC_POSTLAND_DIR/last-green")"
  # Fails FAST the first time, so the corpus TAP names the file and the ladder is entered; then
  # WEDGES on every re-run, so the ladder's OWN bound is the only thing that can end the retry.
  m="$BATS_TEST_TMPDIR/wedge-marker"
  add_stateful_test slowfail "$(printf '#!/bin/bash\nM="%s"\n[ -f "$M" ] && sleep 60\ntouch "$M"\nexit 1\n' "$m")"
  push_commit "a suite too slow for the ladder's bound"
  tree="$(origin_tree)"
  POSTLAND_FILE_TIMEOUT_S=3 POSTLAND_RETRY_TIMEOUT_S=3 run bash "$SUT" --run-if-needed
  run jq -r '.verdict' "$CC_POSTLAND_DIR/stamps/$tree.json"
  [ "$output" = "cut" ]                            # C23: our own bound proves nothing ⇒ cut, and
                                                   # emphatically NOT the red that blocks deploy
  [ "$(pages_n)" = "0" ]                           # C10: pages are RED-only
  [ "$(cat "$CC_POSTLAND_DIR/last-green")" = "$green" ]   # never advances on a non-verdict
}

@test "C23: the re-run is the failing TEST, not its whole file (what makes the bound fit)" {
  run bash "$SUT" --run-if-needed
  [ "$status" -eq 0 ]
  # ONE file, TWO tests: one fails every time, one records every execution of itself.
  wit="$BATS_TEST_TMPDIR/witness"
  printf '@test "boom" { false; }\n@test "wit" { echo x >> "%s"; }\n' "$wit" > "$R/tests/pair.bats"
  push_commit "one failing test beside a witness"
  tree="$(origin_tree)"
  run bash "$SUT" --run-if-needed
  # WITNESS ACCOUNTING (measured, so nobody has to re-derive it): 2 = the corpus run (1) + C20's
  # bisect, which legitimately re-runs the whole FILE to locate the culprit (1). The two RETRIES
  # contribute ZERO, because each re-ran only the named test. The paired file-granularity test below
  # is the control: same fixture, same bisect, 4 — and that delta of exactly 2 IS the retries.
  [ "$(wc -l < "$wit" | tr -d ' ')" = "2" ]
  run jq -r '.verdict' "$CC_POSTLAND_DIR/stamps/$tree.json"
  [ "$output" = "red" ]                            # C8 still convicts: "boom" failed 3/3
}

@test "C23: POSTLAND_RETRY_GRANULARITY=file restores the whole-file re-run" {
  run bash "$SUT" --run-if-needed
  [ "$status" -eq 0 ]
  wit="$BATS_TEST_TMPDIR/witness2"
  printf '@test "boom" { false; }\n@test "wit" { echo x >> "%s"; }\n' "$wit" > "$R/tests/pair2.bats"
  push_commit "the granularity seam"
  POSTLAND_RETRY_GRANULARITY=file run bash "$SUT" --run-if-needed
  # 4 = corpus (1) + TWO WHOLE-FILE retries (2) + the bisect's whole-file run (1). Against the
  # test-granular default the same fixture yields 2 — the seam is what moves those two executions.
  [ "$(wc -l < "$wit" | tr -d ' ')" = "4" ]
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

# ── PATH NORMALIZATION (the 0-green-stamp root cause, reproduced 2026-07-26) ────────────────────
# The verdict is only meaningful if the suite runs in the environment a real session runs in. Driven
# from a daemon/launchd-ish context, PATH lacked $HOME/.claude/bin and $HOME/bin, so suites shelling
# out to cc-* helpers failed; the retry ladder then convicted them at >=2/3 (a PATH-dependent
# failure reproduces every time), writing a HARD red. 15/15 stamps were red while trunk measured
# 2096 ok / 0 not-ok. These lock the normalization in — and lock in that it never SUBTRACTS.

@test "PATH normalization: a daemon-like PATH gains \$HOME/.claude/bin before bats runs" {
  grep -q 'PATH NORMALIZATION' "$SUT"          # block must EXIST — else this test is vacuous
  mkdir -p "$HOME/.claude/bin" "$HOME/bin"
  run env -i HOME="$HOME" PATH="/usr/bin:/bin" TERM=dumb bash -c \
    "sed -n '/PATH NORMALIZATION/,/^export PATH\$/p' '$SUT' > '$BATS_TEST_TMPDIR/norm.sh'; . '$BATS_TEST_TMPDIR/norm.sh'; printf '%s' \"\$PATH\""
  [ "$status" -eq 0 ]
  # `|| false` on every NON-FINAL [[ ]]: `[[` is a bash KEYWORD, so the ERR trap never fires for it
  # and a bare non-final [[ ]] is a DEAD assertion that can never fail the test. Only the LAST one
  # is live unaided, being the test's exit status. tests/bats-assert-liveness.bats ratchets this.
  [[ "$output" == *"$HOME/.claude/bin"* ]] || false
  [[ "$output" == *"$HOME/bin"* ]] || false
  [[ "$output" == *"/usr/bin"* ]]                     # PREPEND-only: the original entries survive
}

@test "PATH normalization: idempotent — an already-normalized PATH is not duplicated" {
  grep -q 'PATH NORMALIZATION' "$SUT"          # block must EXIST — else this test is vacuous
  mkdir -p "$HOME/.claude/bin"
  run env -i HOME="$HOME" PATH="$HOME/.claude/bin:/usr/bin:/bin" TERM=dumb bash -c \
    "sed -n '/PATH NORMALIZATION/,/^export PATH\$/p' '$SUT' > '$BATS_TEST_TMPDIR/norm.sh'; . '$BATS_TEST_TMPDIR/norm.sh'; printf '%s' \"\$PATH\" | tr ':' '\n' | grep -c \"^$HOME/.claude/bin\$\""
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]                                 # exactly once, not twice
}

@test "PATH normalization: CC_POSTLAND_PATH overrides wholesale (explicit beats inferred)" {
  grep -q 'PATH NORMALIZATION' "$SUT"          # block must EXIST — else this test is vacuous
  run env -i HOME="$HOME" PATH="/usr/bin:/bin" CC_POSTLAND_PATH="/only/this" TERM=dumb bash -c \
    "sed -n '/PATH NORMALIZATION/,/^export PATH\$/p' '$SUT' > '$BATS_TEST_TMPDIR/norm.sh'; . '$BATS_TEST_TMPDIR/norm.sh'; printf '%s' \"\$PATH\""
  [ "$status" -eq 0 ]
  [ "$output" = "/only/this" ]
}

@test "PATH normalization: a nonexistent dir is never added (no phantom entries)" {
  grep -q 'PATH NORMALIZATION' "$SUT"          # block must EXIST — else this test is vacuous
  rm -rf "$HOME/bin"
  run env -i HOME="$HOME" PATH="/usr/bin:/bin" TERM=dumb bash -c \
    "sed -n '/PATH NORMALIZATION/,/^export PATH\$/p' '$SUT' > '$BATS_TEST_TMPDIR/norm.sh'; . '$BATS_TEST_TMPDIR/norm.sh'; printf '%s' \"\$PATH\""
  [ "$status" -eq 0 ]
  [[ "$output" != *"$HOME/bin:"* ]]
}

# ── C15–C17 HUNG: the one state carved OUT of the cut population ────────────────
# C13 above settled "a truncated run is not a RED". These settle the split INSIDE that
# population: a MACHINE event (peer pkill / OOM / starvation) stays a CUT — unactionable,
# retried, cooled off — while a suite that genuinely never RETURNS, and whose suspect file
# wedges AGAIN alone on a pristine checkout, is a proven property of the TREE. Retrying is
# the right answer to the first and the one answer guaranteed never to clear the second.
# A stub `bats` on the SUT's own $CC_POSTLAND_BATS seam gives the death SHAPES exactly; the
# real signal (a genuine SIGKILL) and the real bound (a genuine timeout(1) expiry) are NOT
# stubbed, and the first test is a positive control against the REAL producer.
stub_bats_mode() {   # $1 = mode; writes $BATS_TEST_TMPDIR/stub-bats and exports the seam
  cat > "$BATS_TEST_TMPDIR/stub-bats" <<'STUB'
#!/bin/bash
case "$1" in --version) echo "Bats 0.0.0-stub"; exit 0 ;; --count) echo 1; exit 0 ;; esac
case "${PV_STUB_MODE:-}" in
  # the plan line and then nothing — only the SUT's own bound can end it
  hung)     echo "1..3"; sleep 60 ;;
  # a hang whose TAP ALSO carries a job-control line — the C16 ordering case. On some
  # bats/shell combinations timeout(1)'s own SIGTERM makes the hang print exactly this,
  # so a signal-first ladder would misfile every such hang as a machine cut.
  hungsig)  echo "1..3"; echo "bats: line 336: 42124 Terminated: 15   exec bats-exec-suite"; sleep 60 ;;
  # planned, completed nothing, exit 1, NOBODY signalled it (the no-timeout leg)
  stall)    echo "1..3"; exit 1 ;;
  # wedges as a SUITE, completes as a FILE => the confirm re-run must exonerate it.
  # v2 passes the corpus as an explicit FILE LIST, never the literal `tests/` (C18), so the
  # discriminator is ARGUMENT COUNT: >1 path = the suite run, exactly 1 = the confirm re-run.
  # Keying on "tests/" was keying on the v1 invocation SHAPE, and it silently stopped matching
  # the producer — the stub then completed instantly and the hang it exists to fake never
  # happened. A fixture is a claim about the real producer; when the producer changes shape the
  # fixture must be re-derived from it, not left passing for a new reason.
  flaky)    if [ "$#" -gt 1 ] || [ "${1:-}" = "tests/" ]; then echo "1..3"; sleep 60; else echo "1..1"; echo "ok 1 a"; exit 0; fi ;;
  # bats OUTLIVED the child it lost: rc is a plain 1, the only trace is the shell's
  # job-control line. This is the literal 9c5d0ba74e79 observation.
  survivor) echo "1..3"; echo "ok 1 a"
            echo "bats: line 336: 42124 Killed: 9   exec bats-exec-suite"; exit 1 ;;
  # the SAME words, but as a TEST'S OWN captured output (`# `-prefixed) — this repo has
  # reaper suites that print exactly this, and it must NOT read as a signal.
  reaper)   echo "1..3"; echo "ok 1 a"; echo "# Killed: 9"; exit 1 ;;
  *)        echo "1..3"; echo "ok 1 a"; exit 1 ;;
esac
exit 0
STUB
  chmod +x "$BATS_TEST_TMPDIR/stub-bats"
  export CC_POSTLAND_BATS="$BATS_TEST_TMPDIR/stub-bats" PV_STUB_MODE="$1"
}
hung_pages_n() { find "$CC_PAGES_DIR" -name 'postland-hung-*.page' 2>/dev/null | wc -l | tr -d ' '; }

@test "C15/C16 REAL hang (real bats, real timeout): HUNG naming the file, not a CUT" {
  run bash "$SUT" --run-if-needed                  # green baseline
  [ "$status" -eq 0 ]
  green="$(cat "$CC_POSTLAND_DIR/last-green")"
  printf '@test "wedge" { sleep 60; }\n' > "$R/tests/wedge.bats"
  push_commit "a suite that wedges"
  tree="$(origin_tree)"
  POSTLAND_SUITE_TIMEOUT_S=6 POSTLAND_FILE_TIMEOUT_S=6 run bash "$SUT" --run-if-needed
  s="$CC_POSTLAND_DIR/stamps/$tree.json"
  [ -f "$s" ]
  run jq -r '.verdict' "$s"; [ "$output" = "hung" ]                 # C15
  run jq -r '.failing[0]' "$s"; [ "$output" = "tests/wedge.bats" ]  # names the FILE that wedged
  [ "$(cat "$CC_POSTLAND_DIR/last-green")" = "$green" ]             # C15: last-green frozen
  [ "$(pages_n)" = "0" ]                                            # C13: NOT a RED
  [ "$(cut_pages_n)" = "0" ]                                        # ...and NOT a machine cut
  [ -n "$(find "$CC_PAGES_DIR" -name 'postland-hung-wedge-*.page' 2>/dev/null)" ]
  # POSITIVE CONTROL on the REAL producer: real bats, real wedge, real timeout(1) — the bound
  # genuinely fires rather than the 124 arriving from somewhere in the fixture. It runs against
  # the fixture repo's own copy of the suite, because the verifier's cell no longer outlives the
  # run (C7); pointing it at that path would have made the control assert teardown, not wedging.
  tb="$(command -v timeout || command -v gtimeout || echo /opt/homebrew/bin/timeout)"
  run env -u TMPDIR "$tb" -k 2 4 bats "$R/tests/wedge.bats"
  [ "$status" -eq 124 ]
}

@test "C16: rc 124 outranks a job-control line in the TAP — hang, not cut" {
  # THE ORDERING GUARD. timeout(1) SIGTERMs the whole group, so on some bats/shell
  # combinations a hang's own TAP carries `Terminated: 15`; a signal-first ladder would
  # then misfile every hang as a machine cut and send it to the wrong owner forever.
  # Asserted as a CODE property: this TAP has both, and rc 124 must win. Swap the two
  # branches in classify_hang and this test goes red (verdict becomes "cut").
  run bash "$SUT" --run-if-needed
  [ "$status" -eq 0 ]
  echo hsf > "$R/hungsig-fixture"; push_commit "hang that also prints a signal line"
  tree="$(origin_tree)"
  stub_bats_mode hungsig
  POSTLAND_SUITE_TIMEOUT_S=4 POSTLAND_FILE_TIMEOUT_S=4 run bash "$SUT" --run-if-needed
  run jq -r '.verdict' "$CC_POSTLAND_DIR/stamps/$tree.json"
  [ "$output" = "hung" ]
  page="$(find "$CC_PAGES_DIR" -name 'postland-hung-*.page' | head -1)"
  [ -n "$page" ]
  grep -q 'timeout:4s' "$page"                      # attributed to OUR bound, not to sig:15
}

@test "STALL bound: a wedge is cut on TAP silence in seconds, not on the wall backstop" {
  # The primary bound is PROGRESS (POSTLAND_STALL_S), not duration. Discriminator vs the old
  # wall-only code: the wall here is 60s, so ONLY the stall path can produce a verdict this fast —
  # run_s in the stamp must be well under the wall. Same hung classification, same named file.
  run bash "$SUT" --run-if-needed
  [ "$status" -eq 0 ]
  printf '@test "wedge" { sleep 60; }\n' > "$R/tests/wedge.bats"
  push_commit "a suite that wedges (stall path)"
  tree="$(origin_tree)"
  POSTLAND_STALL_S=3 POSTLAND_STALL_POLL_S=1 POSTLAND_SUITE_TIMEOUT_S=60 POSTLAND_FILE_TIMEOUT_S=6 \
    run bash "$SUT" --run-if-needed
  s="$CC_POSTLAND_DIR/stamps/$tree.json"
  [ -f "$s" ]
  run jq -r '.verdict' "$s"; [ "$output" = "hung" ]
  run jq -r '.failing[0]' "$s"; [ "$output" = "tests/wedge.bats" ]
  run jq -r '.run_s' "$s"; [ "$output" -lt 30 ] || false   # the WALL (60s) provably did not fire
}

@test "STALL bound: slow-but-PROGRESSING corpus is never cut (non-regression control)" {
  # The other half of the split the stall bound exists for: each test completes within the stall
  # window, so progress keeps resetting the clock and the run finishes GREEN even though its total
  # wall exceeds several stall windows. (Passes pre-change too — this is the control that pins the
  # stall bound to STALLS; the discriminating half is the run_s assertion above.)
  run bash "$SUT" --run-if-needed
  [ "$status" -eq 0 ]
  printf '@test "s1" { sleep 2; }\n@test "s2" { sleep 2; }\n@test "s3" { sleep 2; }\n@test "s4" { sleep 2; }\n' \
    > "$R/tests/slowly.bats"
  push_commit "a slow but progressing suite"
  tree="$(origin_tree)"
  POSTLAND_STALL_S=4 POSTLAND_STALL_POLL_S=1 POSTLAND_SUITE_TIMEOUT_S=120 POSTLAND_FILE_TIMEOUT_S=30 \
    run bash "$SUT" --run-if-needed
  run jq -r '.verdict' "$CC_POSTLAND_DIR/stamps/$tree.json"
  [ "$output" = "green" ]
}

@test "C15: a HUNG tree is ABSTAINED as a real verdict, never re-run forever" {
  # the counterpart to C13's "a cut tree is RETRIED": a hang is PROVEN about the tree, so
  # re-running it every sweep re-proves a decided fact and burns a full suite per tick.
  run bash "$SUT" --run-if-needed
  [ "$status" -eq 0 ]
  printf '@test "wedge" { sleep 60; }\n' > "$R/tests/wedge.bats"
  push_commit "a suite that wedges"
  POSTLAND_SUITE_TIMEOUT_S=6 POSTLAND_FILE_TIMEOUT_S=6 run bash "$SUT" --run-if-needed
  n1="$(stamps_n)"
  POSTLAND_SUITE_TIMEOUT_S=6 run bash "$SUT" --run-if-needed
  [ "$status" -eq 0 ]
  [ "$(idl_last '.reason')" = "already-stamped" ]   # abstained, unlike a cut
  [ "$(stamps_n)" = "$n1" ]
}

@test "C15: cut and hung route to DIFFERENT owners (cut=quiet box, hung=timeout-wrap)" {
  run bash "$SUT" --run-if-needed
  [ "$status" -eq 0 ]
  echo hf > "$R/hung-fixture"; push_commit "hung fixture"
  tree="$(origin_tree)"
  stub_bats_mode hung
  POSTLAND_SUITE_TIMEOUT_S=4 POSTLAND_FILE_TIMEOUT_S=4 run bash "$SUT" --run-if-needed
  run jq -r '.verdict' "$CC_POSTLAND_DIR/stamps/$tree.json"
  [ "$output" = "hung" ]
  page="$(find "$CC_PAGES_DIR" -name 'postland-hung-*.page' | head -1)"
  [ -n "$page" ]
  grep -q 'un-stubbed external seam' "$page"        # the HUNG repair...
  grep -q 'timeout-wrap' "$page"
  grep -q 'NOT a cut' "$page"
  run grep -ci 'Re-run on a quiet box' "$page"      # ...and NOT the CUT repair
  [ "$status" -eq 1 ]                               # 1 = matched nothing (2 = no such file)
  [ -f "$REC/cc-backlog.argv" ]
  grep -q 'HUNG' "$REC/cc-backlog.argv"
  run grep -c 'post-land RED' "$REC/cc-backlog.argv"
  [ "$status" -eq 1 ]                               # C13: never filed as a RED
}

@test "C15: a hang candidate whose file does NOT wedge alone degrades to a CUT" {
  run bash "$SUT" --run-if-needed
  [ "$status" -eq 0 ]
  # TWO suites, deliberately: the stub tells "the SUITE run" from "the confirm re-run" by argument
  # count (v2 passes a file LIST, never `tests/`), and with a one-suite corpus those two are
  # byte-identical invocations — the fixture could not express the distinction it exists to test.
  printf '@test "second" { true; }\n' > "$R/tests/second.bats"
  echo ff > "$R/flaky-fixture"; push_commit "suite wedges, file does not"
  tree="$(origin_tree)"
  stub_bats_mode flaky
  POSTLAND_SUITE_TIMEOUT_S=4 POSTLAND_FILE_TIMEOUT_S=4 run bash "$SUT" --run-if-needed
  run jq -r '.verdict' "$CC_POSTLAND_DIR/stamps/$tree.json"
  [ "$output" = "cut" ]                             # unproven => we refuse to invent a hang
  [ "$(hung_pages_n)" = "0" ]
  [ "$(pages_n)" = "0" ]
}

@test "C15: a job-control death line stays a CUT even when bats itself exits 1" {
  # the live 9c5d0ba74e79 shape: the suite ran, the child was SIGKILLed, bats survived and
  # returned a plain 1 — so rc alone says nothing and only the TAP carries the evidence.
  # A signal is a MACHINE event: it must reach the cut path, never be promoted to a hang.
  run bash "$SUT" --run-if-needed
  [ "$status" -eq 0 ]
  echo svf > "$R/survivor-fixture"; push_commit "survivor fixture"
  tree="$(origin_tree)"
  stub_bats_mode survivor
  run bash "$SUT" --run-if-needed
  run jq -r '.verdict' "$CC_POSTLAND_DIR/stamps/$tree.json"
  [ "$output" = "cut" ]
  [ "$(hung_pages_n)" = "0" ]                       # named from the TAP, not from rc
  [ "$(pages_n)" = "0" ]                            # and emphatically not the RED it used to be
}

@test "C15: a test's OWN '# Killed: 9' output is not mistaken for a signal" {
  # the false-positive guard: this repo has reaper/kill suites that print those words, and
  # bats prefixes captured test output with '# '. Reading it as a signal is harmless HERE
  # (both roads end at a cut) but it would silently disarm the hang ladder's ordering.
  run bash "$SUT" --run-if-needed
  [ "$status" -eq 0 ]
  echo rf > "$R/reaper-fixture"; push_commit "reaper-output fixture"
  tree="$(origin_tree)"
  stub_bats_mode reaper
  run bash "$SUT" --run-if-needed
  [ "$status" -eq 0 ]
  run jq -r '.verdict' "$CC_POSTLAND_DIR/stamps/$tree.json"
  [ "$output" = "cut" ]                             # partial progress, no real signal
  # POSITIVE CONTROL on the discriminator itself: the same words WITHOUT the '# ' prefix
  # must match, so this test cannot pass by the regex simply never matching anything.
  printf '1..3\nok 1 a\n# Killed: 9\n' > "$BATS_TEST_TMPDIR/reaper.tap"
  run grep -aE '^[^#]*(Killed|Terminated): *[0-9]+' "$BATS_TEST_TMPDIR/reaper.tap"
  [ "$status" -eq 1 ]                               # the test's OWN output: NOT a signal
  printf '1..3\nok 1 a\nbats: 42 Killed: 9 exec\n' > "$BATS_TEST_TMPDIR/real.tap"
  run grep -aE '^[^#]*(Killed|Terminated): *[0-9]+' "$BATS_TEST_TMPDIR/real.tap"
  [ "$status" -eq 0 ]                               # the shell's job-control line: IS a signal
}

@test "C17: the suite run is really bounded, with the configured seconds" {
  # a RECORDING timeout(1) — proves the bound is actually applied and carries
  # POSTLAND_SUITE_TIMEOUT_S, rather than trusting that a 124 came from somewhere.
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "%s/timeout.argv"\nexec %s "$@"\n' \
    "$REC" "$(command -v timeout || command -v gtimeout || echo /opt/homebrew/bin/timeout)" \
    > "$STUB/rec-timeout"
  chmod +x "$STUB/rec-timeout"
  CC_POSTLAND_TIMEOUT_BIN="$STUB/rec-timeout" POSTLAND_SUITE_TIMEOUT_S=77 run bash "$SUT" --run-if-needed
  [ "$status" -eq 0 ]
  [ -f "$REC/timeout.argv" ]                        # C17: the bound was applied at all...
  grep -q -- '-k 10 77 ' "$REC/timeout.argv"        # ...with the configured budget
}

@test "C17: unbounded, a hang candidate degrades to a CUT — HUNG is never fabricated" {
  run bash "$SUT" --run-if-needed
  [ "$status" -eq 0 ]
  green="$(cat "$CC_POSTLAND_DIR/last-green")"
  echo sf > "$R/stall-fixture"; push_commit "stall fixture"
  tree="$(origin_tree)"
  stub_bats_mode stall                              # planned 3, completed 0, exit 1, NO signal
  # set-but-EMPTY is honored verbatim => no timeout(1) at all => nothing can ever return 124
  CC_POSTLAND_TIMEOUT_BIN= run bash "$SUT" --run-if-needed
  [ "$status" -eq 0 ]
  run jq -r '.verdict' "$CC_POSTLAND_DIR/stamps/$tree.json"
  [ "$output" = "cut" ]                             # C17: unprovable => never a hang verdict
  [ "$(pages_n)" = "0" ]                            # C13: and emphatically not a RED
  [ "$(hung_pages_n)" = "0" ]
  [ "$(cat "$CC_POSTLAND_DIR/last-green")" = "$green" ]
}

# ════ v2 (LAND_PIPELINE_V2 §4.2) ═════════════════════════════════════════════════════════════════
# C18 partition · C19 no admission control · C20 auto-revert · C21 gate-green · C22 pre-corpus lints.
# Every one carries a POSITIVE CONTROL, because each is a test that a thing does NOT happen — and an
# absence-assertion passes just as happily when the mechanism is dead as when it is working.

# ── C18 partition ───────────────────────────────────────────────────────────────
@test "C18: the corpus is tests/*.bats MINUS the manifest — the LIST bats receives proves it" {
  printf '@test "h" { true; }\n' > "$R/tests/hostonly.bats"
  printf '@test "t" { true; }\n' > "$R/tests/treeonly.bats"
  mkdir -p "$R/scripts"
  printf '# host suites\ntests/hostonly.bats\n' > "$R/scripts/host-suites.manifest"
  push_commit "a partitioned tree"
  b="$(stub_bats argv "printf '%s\n' \"\$@\" > '$REC/argv.txt'; printf '1..1\nok 1 p\n'")"
  CC_POSTLAND_BATS="$b" run bash "$SUT" --run-if-needed
  [ "$status" -eq 0 ]
  [ -f "$REC/argv.txt" ]
  run grep -cxF 'tests/treeonly.bats' "$REC/argv.txt"; [ "$output" = "1" ]  # tree suite: RAN
  run grep -cxF 'tests/ok.bats'       "$REC/argv.txt"; [ "$output" = "1" ]
  run grep -cxF 'tests/hostonly.bats' "$REC/argv.txt"; [ "$output" = "0" ]  # host suite: EXCLUDED
  run grep -cxF 'tests/'              "$REC/argv.txt"; [ "$output" = "0" ]  # never the DIRECTORY
  # POSITIVE CONTROL — the identical tree with the manifest REMOVED must run hostonly. Without it
  # this test would pass if the corpus were empty, or if hostonly.bats had simply never existed.
  git -C "$R" rm -q "$R/scripts/host-suites.manifest"
  push_commit "no manifest ⇒ everything runs"
  CC_POSTLAND_BATS="$b" run bash "$SUT" --run-if-needed
  [ "$status" -eq 0 ]
  run grep -cxF 'tests/hostonly.bats' "$REC/argv.txt"; [ "$output" = "1" ]  # missing ⇒ MORE proof
}

# ── C19 no admission control ────────────────────────────────────────────────────
@test "C19: no admission control survives anywhere in the runner (it must never wait on load)" {
  run grep -cE '^[[:space:]]*gate_admit' "$SUT"
  [ "$output" = "0" ]
  # POSITIVE CONTROL on the PATTERN: it must match a real call site, else this test is a
  # tautology that would keep passing if the regex silently stopped matching anything.
  printf 'x() {\n  gate_admit "full suite"\n}\n' > "$BATS_TEST_TMPDIR/probe.sh"
  run grep -cE '^[[:space:]]*gate_admit' "$BATS_TEST_TMPDIR/probe.sh"
  [ "$output" = "1" ]
  # and no load-polling loop survives under another name
  run grep -cE 'CC_GATE_ADMIT_MAX_WAIT|CC_GATE_ADMIT_POLL|ADMIT-DEFER|ADMIT-PROCEED' "$SUT"
  [ "$output" = "0" ]
}

# ── C21 gate-green ──────────────────────────────────────────────────────────────
@test "C21: a GREEN stamp writes <git-common-dir>/gate-green = the COMMIT sha; a RED never does" {
  gc="$(git -C "$R" rev-parse --git-common-dir)"
  case "$gc" in /*) ;; *) gc="$R/$gc" ;; esac
  rm -f "$gc/gate-green"
  target="$(origin_head)"
  run bash "$SUT" --run-if-needed
  [ "$status" -eq 0 ]
  [ -f "$gc/gate-green" ]
  [ "$(cat "$gc/gate-green")" = "$target" ]        # the COMMIT — what the consumers compare to HEAD
  [ "$(cat "$gc/gate-green")" != "$(origin_tree)" ] # ...explicitly NOT the tree the stamp is keyed on
  # CONTROL: an unproven tree must never advance the marker (the whole point of the claim).
  printf '@test "f" { false; }\n' > "$R/tests/bad.bats"
  push_commit "a red tree"
  run bash "$SUT" --run-if-needed
  [ "$(cat "$gc/gate-green")" = "$target" ]        # still the last PROVEN commit
}

# ── C20 auto-revert ─────────────────────────────────────────────────────────────
# A stub land lane on the CC_POSTLAND_SHIP_BIN seam. It RECORDS the cwd/branch/subject it was
# invoked with — the contract is "landed FROM the revert worktree, on the revert's own branch" —
# and then really pushes, so "trunk healed" is observed end-to-end rather than mocked away.
ship_stub() {
  printf '#!/bin/bash\n{ echo "cwd=$PWD"; echo "branch=$(git rev-parse --abbrev-ref HEAD)"; echo "subject=$(git log -1 --format=%%s)"; } >> "%s/ship.argv"\ngit push -q origin HEAD:main\n' \
    "$REC" > "$STUB/ship-land"
  chmod +x "$STUB/ship-land"
  export CC_POSTLAND_SHIP_BIN="$STUB/ship-land"
}
# A green baseline FIRST: last-green is the bisect floor, and with no floor there is no bisected
# culprit and therefore (by the bisected-culprit-only guard) no revert at all.
arv_red() {   # [subject] → echoes the culprit sha
  bash "$SUT" --run-if-needed >/dev/null 2>&1 || true
  printf '@test "boom" { false; }\n' > "$R/tests/bad.bats"
  push_commit "${1:-the culprit}"
  origin_head
}
ship_field() { sed -n "s/^$1=//p" "$REC/ship.argv" | head -1; }

@test "C20: a reproducible RED with a BISECTED culprit is reverted and landed via the land lane" {
  ship_stub
  culprit="$(arv_red)"
  run env POSTLAND_AUTOREVERT=on bash "$SUT" --run-if-needed
  [ -f "$REC/ship.argv" ]                                     # the land lane WAS invoked...
  [ "$(ship_field branch)" = "postland-revert-${culprit:0:12}" ]   # ...on the revert's own branch
  cwd="$(ship_field cwd)"
  [ "${cwd#"$CC_POSTLAND_WT_ROOT"/wt-revert-}" != "$cwd" ]    # ...from the revert worktree
  run bash -c "sed -n 's/^subject=//p' '$REC/ship.argv' | head -1 | grep -c '^Revert '"
  [ "$output" = "1" ]
  git -C "$R" fetch -q origin
  run bash -c "git -C '$R' log -1 --format=%s origin/main | grep -c '^Revert '"
  [ "$output" = "1" ]                                          # trunk actually HEALED
  [ -f "$CC_POSTLAND_DIR/reverts/$culprit" ]                   # marker, keyed on the culprit
  run grep -c '^land_exit=0$' "$CC_POSTLAND_DIR/reverts/$culprit"
  [ "$output" = "1" ]
  [ "$(cells_n)" = "0" ]                                       # both cells torn down
}

@test "C20: NEVER TWICE — a culprit with a marker is refused on every later encounter" {
  ship_stub
  culprit="$(arv_red)"
  run env POSTLAND_AUTOREVERT=on bash "$SUT" --run-if-needed
  [ -s "$REC/ship.argv" ]                                      # control: the first one DID revert
  [ -f "$CC_POSTLAND_DIR/reverts/$culprit" ]
  # re-present the SAME culprit as trunk, unstamped, so everything but the marker says "revert it"
  git -C "$R" push -qf origin "$culprit:main"
  rm -f "$CC_POSTLAND_DIR/stamps"/*.json
  : > "$REC/ship.argv"
  run env POSTLAND_AUTOREVERT=on bash "$SUT" --run-if-needed
  [ ! -s "$REC/ship.argv" ]                                    # ZERO land-lane invocations
}

@test "C20: a culprit that is ITSELF a revert is refused (that is how a revert war starts)" {
  ship_stub
  culprit="$(arv_red 'Revert "an earlier commit"')"
  run env POSTLAND_AUTOREVERT=on bash "$SUT" --run-if-needed
  [ ! -f "$REC/ship.argv" ]                                    # nothing landed
  [ -z "$(find "$CC_POSTLAND_DIR/reverts" -type f 2>/dev/null)" ]
  [ "$(pages_n)" = "1" ]                                       # ...but the RED is still paged
}

@test "C20: POSTLAND_AUTOREVERT=off refuses the revert while still paging and backlogging" {
  ship_stub
  arv_red >/dev/null
  run env POSTLAND_AUTOREVERT=off bash "$SUT" --run-if-needed
  [ ! -f "$REC/ship.argv" ]                                    # the kill switch holds
  [ -z "$(find "$CC_POSTLAND_DIR/reverts" -type f 2>/dev/null)" ]
  [ "$(pages_n)" = "1" ]                                       # the net still reports
  [ -f "$REC/cc-backlog.argv" ]
}

@test "C20: the per-run cap refuses once it is reached (and does NOT refuse below it)" {
  # At most one culprit is convicted per run_target, so the cap is exercised at its BOUNDARY:
  # 0 must refuse the very first attempt, 1 must allow it. Same fixture, same wiring, so the
  # refusal below can only be the cap — the default (2) is exercised by the happy path above.
  ship_stub
  arv_red >/dev/null
  run env POSTLAND_AUTOREVERT=on POSTLAND_MAX_REVERTS=0 bash "$SUT" --run-if-needed
  [ ! -f "$REC/ship.argv" ]                                    # capped ⇒ no attempt
  [ -z "$(find "$CC_POSTLAND_DIR/reverts" -type f 2>/dev/null)" ]
  # POSITIVE CONTROL at the other side of the boundary
  rm -f "$CC_POSTLAND_DIR/stamps"/*.json
  run env POSTLAND_AUTOREVERT=on POSTLAND_MAX_REVERTS=1 bash "$SUT" --run-if-needed
  [ -s "$REC/ship.argv" ]                                      # under the cap ⇒ it reverts
}

@test "C20: an UNDECIDABLE bisect pages and backlogs but attempts ZERO reverts" {
  # The pin: red_actions falls back to the TARGET sha for paging when bisect cannot decide, and
  # reverting that fallback would revert a tip nothing convicted. With no last-green there is no
  # bisect floor, which is exactly the first-ever-run shape.
  ship_stub
  base="$(origin_head)"
  printf '@test "f" { false; }\n' > "$R/tests/bad.bats"
  push_commit "red, with no green floor to bisect from"
  [ ! -f "$CC_POSTLAND_DIR/last-green" ]                       # precondition, asserted not assumed
  run env POSTLAND_AUTOREVERT=on bash "$SUT" --run-if-needed
  [ "$(pages_n)" = "1" ]                                       # it PAGES...
  [ -f "$REC/cc-backlog.argv" ]                                # ...and BACKLOGS...
  [ ! -f "$REC/ship.argv" ]                                    # ...and reverts NOTHING
  [ -z "$(find "$CC_POSTLAND_DIR/reverts" -type f 2>/dev/null)" ]
  # POSITIVE CONTROL: the same red, now WITH a green floor, must revert — otherwise this test
  # would pass identically if auto-revert were dead in every case, which is the failure it guards.
  git -C "$R" reset -q --hard "$base"
  git -C "$R" push -qf origin HEAD:main
  bash "$SUT" --run-if-needed >/dev/null 2>&1 || true          # green ⇒ last-green exists
  [ -f "$CC_POSTLAND_DIR/last-green" ]
  printf '@test "f2" { false; }\n' > "$R/tests/bad2.bats"
  push_commit "the control culprit"
  run env POSTLAND_AUTOREVERT=on bash "$SUT" --run-if-needed
  [ -s "$REC/ship.argv" ]                                      # decidable ⇒ a revert IS attempted
}

# ── C22 pre-corpus whole-tree meta-lints ────────────────────────────────────────
prelint_stub() { # <body> — installs it as the tree's walltime lint and lands it
  mkdir -p "$R/scripts"
  printf '#!/bin/bash\n%s\n' "$1" > "$R/scripts/test-walltime-lint.sh"
  chmod +x "$R/scripts/test-walltime-lint.sh"
  push_commit "prelint fixture"
}

@test "C22: a whole-tree lint RED is a named RED that OUTRANKS a cut, and skips the corpus" {
  prelint_stub 'echo "  RATCHET stale entry"; exit 1'
  tree="$(origin_tree)"
  # a bats stub whose own shape is a CUT (plan, partial progress, SIGKILL): were the lint verdict
  # dropped, this run would be filed "cut" — nothing proven — instead of a named red.
  b="$(stub_bats cutter "printf '1..3\nok 1 a\n'; exit 137")"
  CC_POSTLAND_BATS="$b" run bash "$SUT" --run-if-needed
  run jq -r '.verdict' "$CC_POSTLAND_DIR/stamps/$tree.json"
  [ "$output" = "red" ]
  run jq -r '.failing[0]' "$CC_POSTLAND_DIR/stamps/$tree.json"
  [ "$output" = "scripts/test-walltime-lint.sh" ]              # the stamp NAMES the lint
  [ ! -f "$CC_POSTLAND_DIR/last-green" ]
}

@test "C22: OUR OWN lint bound firing is a CUT — a timeout we imposed proves nothing" {
  prelint_stub 'sleep 30'
  tree="$(origin_tree)"
  run env CC_POSTLAND_LINT_TIMEOUT_S=1 bash "$SUT" --run-if-needed
  run jq -r '.verdict' "$CC_POSTLAND_DIR/stamps/$tree.json"
  [ "$output" = "cut" ]                                        # never a RED: it forges no finding
  [ "$(pages_n)" = "0" ]
  [ ! -f "$CC_POSTLAND_DIR/last-green" ]                       # ...and never a GREEN either
  # POSITIVE CONTROL: the same lint, failing FAST, is a red — so "cut" above is a statement about
  # the BOUND, not evidence that a lint can never redden a verdict.
  prelint_stub 'exit 1'
  tree2="$(origin_tree)"
  run env CC_POSTLAND_LINT_TIMEOUT_S=30 bash "$SUT" --run-if-needed
  run jq -r '.verdict' "$CC_POSTLAND_DIR/stamps/$tree2.json"
  [ "$output" = "red" ]
}

@test "C22: a lint exit 2 is a NON-VERDICT, never a RED (a check that could not run must not revert)" {
  # Backlog b4e49b4b5014. Both lints publish `0 clean · 1 violation · 2 unusable`, and only 1 is a
  # claim about the TREE. Exit 2 is the fork-pressure case afaf40de carved out INSIDE the lint: a
  # `grep` that cannot run is not a leak. Filing it as FAILING re-creates that conflation one layer
  # out, and here it reaches red_actions — so a check that never ran could auto-revert a good trunk
  # commit. RED-proved: before the fix this stamped `red` naming the lint.
  prelint_stub 'echo "test-walltime-lint: ⛔ UNUSABLE — a predicate failed to run" >&2; exit 2'
  tree="$(origin_tree)"
  run bash "$SUT" --run-if-needed
  run jq -r '.verdict' "$CC_POSTLAND_DIR/stamps/$tree.json"
  [ "$output" = "cut" ]                                        # not a red: it forges no finding
  [ ! -f "$CC_POSTLAND_DIR/last-green" ]                       # ...and not a green either
  # The revert consequence is deliberately NOT asserted here: a revert additionally needs the C20
  # scaffolding (ship_stub + a green baseline, without which there is no bisected culprit and so no
  # revert at all), so a `ship.argv` assertion in THIS fixture would pass whatever the mapping does
  # — vacuous. `verdict != red` is the load-bearing claim; C20 owns "a red reaches the land lane".
  # POSITIVE CONTROL: the same lint exiting 1 IS a red naming it — so "cut" above is a statement
  # about the exit CODE, not evidence that a lint can never redden a verdict.
  prelint_stub 'echo "  RATCHET stale entry"; exit 1'
  tree2="$(origin_tree)"
  run bash "$SUT" --run-if-needed
  run jq -r '.verdict' "$CC_POSTLAND_DIR/stamps/$tree2.json"
  [ "$output" = "red" ]
  run jq -r '.failing[0]' "$CC_POSTLAND_DIR/stamps/$tree2.json"
  [ "$output" = "scripts/test-walltime-lint.sh" ]
}

@test "C22: an unexpected lint exit (127 — not executable) is a NON-VERDICT too, never a RED" {
  # The `*)` arm. 126/127/137 are all "the check could not be MADE"; only 1 is a verdict. Without
  # this arm a lint that lost its interpreter would revert a commit for the tree's sins.
  prelint_stub 'exit 127'
  tree="$(origin_tree)"
  run bash "$SUT" --run-if-needed
  run jq -r '.verdict' "$CC_POSTLAND_DIR/stamps/$tree.json"
  [ "$output" = "cut" ] || false
  [ ! -f "$CC_POSTLAND_DIR/last-green" ] || false
}

@test "C22: the lint runs whole-tree STRICT — an inherited own-set cannot narrow it" {
  # Both lints distinguish own-set ABSENT (judge the whole tree) from set-but-EMPTY (judge
  # nothing) via ${VAR+set}. If the verifier leaked its own environment through, a lander's
  # own-set would silently reduce the trunk verdict to that lander's diff.
  prelint_stub 'printf "own=%s herm=%s scope=%s argv=%s\n" "${CC_WALLTIME_OWN+SET}" "${CC_HERM_OWN+SET}" "${SHIP_LAND_HERM_OWN_SCOPE+SET}" "$*" > "$PLREC"; exit 0'
  run env PLREC="$REC/lintenv.txt" CC_WALLTIME_OWN=tests/someone-elses.bats \
      CC_HERM_OWN=tests/someone-elses.bats SHIP_LAND_HERM_OWN_SCOPE=off \
      bash "$SUT" --run-if-needed
  [ "$status" -eq 0 ]
  [ -f "$REC/lintenv.txt" ]
  [ "$(cat "$REC/lintenv.txt")" = "own= herm= scope= argv=tests" ]   # all three arrived UNSET
}
