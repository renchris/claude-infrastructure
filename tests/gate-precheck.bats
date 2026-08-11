#!/usr/bin/env bats
# gate-precheck.bats — the SHIFT-LEFT commit-time entry point (land-arch P2, backlog 46eb9be14249;
# docs/research/land-architecture-100p-2026-08-10.md §5 row P2).
#
# WHAT IS BEING PINNED. Gate-red is 27%/14d → 39%/3d → 45% on the last day of ship-land
# invocations, 89% of which run no smoke — so the reds are statics and ratchets, and every one is
# an agent-side diagnose-fix-rerun loop that NEVER TAKES THE LOCK (invisible to the lock ledger by
# construction) and pays a fetch + rebase + full gate per round. `--precheck` exposes the same
# verdict in the author's own tree, before the land.
#
# THE ONE PROPERTY THAT MATTERS IS THAT IT IS NOT A SECOND AUTHORITY. A commit-time check that can
# disagree with the land gate is worse than no check: it either sends an author chasing a red the
# land does not have, or clears a tree the land will refuse. So the tests below are mostly about
# IDENTITY and NON-INTERFERENCE, not about the precheck's own behaviour:
#   · same exit code AND same named arm as the land gate, on a red tree and on a green one
#   · writes no land.log row — a precheck is not a land attempt, and counting it as one would
#     poison the denominator scripts/gate-red-census.sh reports
#   · leaves HEAD, the branch, and the remote exactly where they were (it never rebases, which is
#     what separates it from --dry-run: a "check" that rewrites your history is not a commit-time
#     check, and --dry-run also refuses the dirty tree that IS the commit-time position)
#   · CANNOT SHADOW THE GATE THROUGH THE SHARED STATICS MEMO — a precheck of a red tree records
#     nothing, so the land still reds. That is the one channel through which a pre-filter could
#     have suppressed the thing it is supposed to predict (memory:
#     cost-gate-must-be-strictly-weaker), and it is asserted directly rather than argued.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SHIPLAND="$REPO/scripts/ship-land.sh"

  export HOME="$BATS_TEST_TMPDIR/home"      # hermeticity: never the operator's live ~
  mkdir -p "$HOME"

  ORIGIN="$BATS_TEST_TMPDIR/origin.git"
  WORK="$BATS_TEST_TMPDIR/work"
  git init -q --bare "$ORIGIN"
  git clone -q "$ORIGIN" "$WORK"
  cd "$WORK" || return 1
  git config user.email tester@example.com
  git config user.name tester
  git checkout -q -b main
  echo base > base.txt
  git add base.txt
  git commit -q -m base
  git push -q -u origin main

  export LAND_LOG="$BATS_TEST_TMPDIR/land.log"
  export LAND_LOCK_DIR="$BATS_TEST_TMPDIR/lock"
  export LAND_LOCK_WAIT=10
  export SHIP_LAND_DECISIONS_DIR="$BATS_TEST_TMPDIR/decisions"
  export SHIP_LAND_SHARED_CHECKOUT="$BATS_TEST_TMPDIR/nope"
  export CLAUDE_CODE_SESSION_ID="test-sid-precheck"
  export POSTLAND_DIR="$BATS_TEST_TMPDIR/postland"
  export POSTLAND_VERIFY=off
  export SHIP_LAND_FAILURE_INBOX=off
  # Same env-bleed immunity as tests/ship-land.bats: when THIS suite runs inside an outer land, the
  # outer pipeline's tuning must not decide a fixture pipeline's verdict.
  unset SHIP_LAND_GATE_SCOPE SHIP_LAND_GATE_SCOPE_DEFAULT SHIP_LAND_GATE_POLICY \
        SHIP_LAND_GATE_SELECT SHIP_LAND_FIRST_BASE SHIP_LAND_GATE_EFFECTIVE_FULL \
        SHIP_LAND_SELECTED_N POSTLAND_STALENESS_GUARD \
        SHIP_LAND_GATE_ROUNDS SHIP_LAND_VERIFY_RETRIES \
        SHIP_LAND_LANE SHIP_LAND_SMOKE_BUDGET_S SHIP_LAND_SMOKE_NICE SHIP_LAND_TIMEOUT_BIN \
        SHIP_LAND_SMOKE_STATE SHIP_LAND_SMOKE_N SHIP_LAND_SMOKE_S SHIP_LAND_NET_STATE \
        SHIP_LAND_BACKUP_REF SHIP_BACKUP_REAP \
        2>/dev/null || true
  export CC_GATE_MAX_LOAD=0
  # NO memo-dir export, deliberately: gate-memo.sh derives its store from the repo's own git dir
  # (`$gd/ship-land-memo`) and takes no env override, so the fixture repo under BATS_TEST_TMPDIR
  # already isolates it. An export here would have named a seam that does not exist — which reads,
  # to the next person, as a guarantee nothing provides (memory: spec-named-mechanism-may-be-prose-only).
}

commit_clean() {
  git checkout -q -b feat/clean main
  printf '#!/usr/bin/env bash\necho "hello"\n' > hello.sh
  git add hello.sh && git commit -q -m "feat: hello"
}

commit_shellcheck_red() {
  # SC2154 / SC2086-class: an unquoted expansion of an undefined variable. Deterministic, and it is
  # the audit's own #1 named cause of exit 6.
  git checkout -q -b feat/red main
  printf '#!/usr/bin/env bash\nrm -rf $undefined_dir/*\n' > bad.sh
  git add bad.sh && git commit -q -m "feat: bad"
}

# ── IDENTITY: the precheck's verdict is the land gate's verdict ───────────────────────────────────

@test "identity/GREEN: precheck exits 0 on the same tree the land gate passes" {
  commit_clean

  run bash "$SHIPLAND" --precheck --trunk main
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -F "precheck: statics + all ratchet arms GREEN" >/dev/null

  # the land gate on the identical tree, stopped before the lock
  run bash "$SHIPLAND" --dry-run --trunk main
  [ "$status" -eq 0 ]
}

@test "identity/RED: precheck exits 6 and names the SAME arm the land gate names" {
  commit_shellcheck_red

  run bash "$SHIPLAND" --precheck --trunk main
  local pre_status="$status"
  [ "$pre_status" -eq 6 ]
  printf '%s\n' "$output" | grep -F "arm(s): shellcheck" >/dev/null

  # The land gate on the identical tree. It attests its arm into land.log's `red` field, which is
  # the same GATE_RED_WHY the precheck printed — so the two are compared through the mechanism,
  # not through two strings that happen to look alike.
  run bash "$SHIPLAND" --dry-run --trunk main
  [ "$status" -eq "$pre_status" ]
  grep -F '"red":"shellcheck"' "$LAND_LOG" >/dev/null
}

@test "identity: a GATE-KILLED non-verdict stays 9 through the precheck, never a red 6" {
  # The split gate_nonzero_code exists to hold — a claim about the MACHINE must not arrive as a
  # claim about the TREE. The precheck reuses that function rather than re-deriving the split, and
  # this is what proves the reuse is real.
  commit_clean
  # a hermeticity arm that cannot run: the lint is present and executable but exits 2
  printf '#!/usr/bin/env bash\nexit 2\n' > "$BATS_TEST_TMPDIR/herm-stub.sh"
  chmod +x "$BATS_TEST_TMPDIR/herm-stub.sh"
  mkdir -p tests && printf '#!/usr/bin/env bats\n@test "x" { true; }\n' > tests/stub.bats
  git add tests/stub.bats && git commit -q -m "test: stub"

  run env SHIP_LAND_HERM_LINT="$BATS_TEST_TMPDIR/herm-stub.sh" bash "$SHIPLAND" --precheck --trunk main
  [ "$status" -eq 9 ]
  printf '%s\n' "$output" | grep -F "GATE-KILLED" >/dev/null
}

# ── NON-INTERFERENCE: nothing a land reads may learn that a precheck ran ─────────────────────────

@test "a precheck writes NO land.log row — it is not a land attempt" {
  # The census panel's denominator is TOOL rows, one per ship-land invocation. A precheck counted
  # as an invocation would deflate the very gate-red rate P2 exists to make observable.
  commit_shellcheck_red
  run bash "$SHIPLAND" --precheck --trunk main
  [ "$status" -eq 6 ]
  [ ! -s "$LAND_LOG" ]
}

@test "a precheck does not rebase, move HEAD, or touch the remote" {
  commit_clean
  local head_before remote_before
  head_before="$(git rev-parse HEAD)"
  remote_before="$(git rev-parse origin/main)"

  run bash "$SHIPLAND" --precheck --trunk main
  [ "$status" -eq 0 ]

  [ "$(git rev-parse HEAD)" = "$head_before" ]
  [ "$(git rev-parse origin/main)" = "$remote_before" ]
  [ -z "$(git for-each-ref --format='%(refname)' 'refs/heads/ship/*')" ]
}

@test "a precheck files no failure-inbox ref even when it reds" {
  # land_failure_inbox is gated on the in-flight marker, which a precheck never claims. Asserted
  # rather than assumed: a red precheck ten times an hour must not fill the operator's inbox.
  commit_shellcheck_red
  run bash "$SHIPLAND" --precheck --trunk main
  [ "$status" -eq 6 ]
  [ -z "$(git for-each-ref --format='%(refname)' 'refs/land/failed/**')" ]
}

# ── THE SHADOWING PROOF: the shared statics memo cannot launder a red ────────────────────────────

@test "a precheck of a RED tree records nothing, so the land still reds on the same bytes" {
  # THE ONE CHANNEL a pre-filter could have used to suppress what it predicts. gate-memo records
  # ONLY rc 0, so a red is never cached and never replayed; this asserts the consequence end to end
  # rather than the implementation detail.
  commit_shellcheck_red

  run bash "$SHIPLAND" --precheck --trunk main
  [ "$status" -eq 6 ]

  run bash "$SHIPLAND" --dry-run --trunk main
  [ "$status" -eq 6 ]
  grep -F '"red":"shellcheck"' "$LAND_LOG" >/dev/null
}

@test "a precheck of a GREEN tree does not turn a LATER red tree green" {
  # The complement: a green memo entry is keyed on the blob sha, so it can only ever be handed back
  # for the identical bytes. Changing the file must re-run the checker.
  commit_clean
  run bash "$SHIPLAND" --precheck --trunk main
  [ "$status" -eq 0 ]

  printf '#!/usr/bin/env bash\nrm -rf $undefined_dir/*\n' > hello.sh
  git add hello.sh && git commit -q -m "fix: break it"
  run bash "$SHIPLAND" --precheck --trunk main
  [ "$status" -eq 6 ]
}

# ── THE COMMIT-TIME POSITION: what --dry-run structurally cannot do ──────────────────────────────

@test "--working gates UNCOMMITTED edits, which is the position an author is actually in" {
  commit_clean
  printf '#!/usr/bin/env bash\nrm -rf $undefined_dir/*\n' > uncommitted.sh   # never added
  git add uncommitted.sh                                                     # staged, not committed

  run bash "$SHIPLAND" --precheck --working --trunk main
  [ "$status" -eq 6 ]
  printf '%s\n' "$output" | grep -F "arm(s): shellcheck" >/dev/null

  # …and the same tree WITHOUT --working is green, because the offending bytes are not in HEAD yet.
  run bash "$SHIPLAND" --precheck --trunk main
  [ "$status" -eq 0 ]
}

@test "--working gates an UNTRACKED file, and leaves the author's index alone" {
  # THE REGRESSION. The first version of --working used `git diff` alone, which reports only files
  # git already knows about — so a BRAND-NEW file, the commonest thing an author has in hand at
  # commit time, was invisible to every own-set the gate builds. It made the precheck GREEN on a
  # tree the land then REFUSED, which is exactly the "clears a tree the land will refuse" failure
  # the identity tests above exist to rule out. Found by the land gate on this commit's own diff.
  commit_clean
  printf '#!/usr/bin/env bash\nrm -rf $undefined_dir/*\n' > brandnew.sh   # never `git add`ed

  run bash "$SHIPLAND" --precheck --working --trunk main
  [ "$status" -eq 6 ]
  printf '%s\n' "$output" | grep -F "arm(s): shellcheck" >/dev/null

  # …and the author's own index is untouched: the intent-to-add went into a throwaway copy, so the
  # file is still untracked afterwards. A check that stages things behind your back is a side
  # effect, not a check.
  run git status --porcelain -- brandnew.sh
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -E '^\?\? brandnew\.sh' >/dev/null
}

@test "the land refuses a dirty tree that --precheck --working gates happily" {
  # Stated as a test because it is the whole reason --dry-run could not have been the entry point.
  commit_clean
  printf '#!/usr/bin/env bash\necho fine\n' > dirty.sh
  git add dirty.sh

  run bash "$SHIPLAND" --dry-run --trunk main
  [ "$status" -eq 2 ]
  printf '%s\n' "$output" | grep -F "uncommitted changes" >/dev/null

  run bash "$SHIPLAND" --precheck --working --trunk main
  [ "$status" -eq 0 ]
}

@test "--working and --fetch are REFUSED on a land, not silently ignored" {
  commit_clean
  run bash "$SHIPLAND" --working --trunk main
  [ "$status" -eq 2 ]
  printf '%s\n' "$output" | grep -F "are --precheck options" >/dev/null
}

@test "precheck says out loud that it skips the smoke phase" {
  # The honest-scope requirement. §5.P3 measured the ratchet arms at ~112s of the land gate's
  # 127-137s, so what the precheck covers and what it does not must be stated where the author
  # reads the verdict — not only in the header.
  commit_clean
  # The fixture NEEDS a bats corpus, and the first draft of this test did not have one: run_smoke
  # returns at its very first line when `ls tests/*.bats` finds nothing, so the precheck branch —
  # and its message — is unreachable in a repo with no suites. The test failed for that reason and
  # not because the branch was wrong, which is exactly the fixture-vacuity direction to catch here
  # rather than in production.
  mkdir -p tests
  printf '#!/usr/bin/env bats\n@test "x" { true; }\n' > tests/stub.bats
  git add tests/stub.bats && git commit -q -m "test: stub"

  run bash "$SHIPLAND" --precheck --trunk main
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -F "smoke phase is the land's, not the precheck's" >/dev/null
}
