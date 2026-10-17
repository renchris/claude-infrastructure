#!/usr/bin/env bats
# Regression guard for FIRE-FAILED resource cleanup — handoff-fire.sh, backlog f44a901152d9 /
# infra-reliability-audit-2026-07-22 rows 2+3 ("no trap, no release, no worktree remove on any
# failure branch"; verified CONFIRM by raw/v1.md).
#
# THE DEFECT. Every resource a fire acquires is acquired BEFORE the fire can fail — the pool claim
# and `git worktree add` happen during CMD composition, the pane is landed by spawn — and there was
# no `trap` in the script at all. So `payload_lint_gate` exit 4, a `pre_trust` failure, a `spawn`
# return 1 under set -e, and the FIRE-FAILED engagement miss each left behind whatever had been
# claimed: a stranded worktree+branch, a consumed pool slot, and a live task-less pane with NO
# registry row and NO fired-peer marker (both sat on the success branch only) — invisible to
# cc-reaper and to the board, which made it both an unreapable leak and duplicate-fire bait.
#
# WHAT THIS SUITE PINS is the split that makes the fix safe rather than merely tidy: the disposition
# depends on whether a pane was LANDED.
#   · no pane  → the worktree/slot are unused → REMOVE / RETURN them.
#   · pane live → the tree may hold a slow starter's work → KEEP it, and make the PANE VISIBLE
#                 instead (registry row + fired-peer marker). Never a pane close on a negative read.
#
# Technique: a REAL git repo with REAL worktrees, driven through the REAL script, so every assertion
# is a filesystem/git fact rather than a log line. Failures are injected at the payload-lint gate
# (exit 4, the earliest post-acquisition failure) and by extracting fire_cleanup for the pane-live
# branch, which cannot be reached without a real iTerm2 spawn.

setup() {
  # M11 (MACHINE_CAPACITY_V2 §11.3) — a test's environment is PINNED, not ambient. The per-test pins
  # below predate this and are the shape the hermeticity ratchet rejects: they leave every OTHER test in
  # the file reading live machine state. handoff-fire.sh's capacity_gate reads the box's loadavg AND
  # (M10) its memory headroom — the two TERMS of one exit 9 (handoff-fire.sh:4487) — so both are pinned
  # here, for the whole file. tests/handoff-fire-capacity-gate.bats is the ONE place the gate runs ON.
  export CC_FIRE_CAPACITY_GATE=off
  export CC_FIRE_HEADROOM_GATE=off
  # handoff-fire.sh routes every external iTerm2 call through hf_bounded — a timeout(1) wrapper —
  # because a wedged iTerm2 API blocks indefinitely. This suite EXTRACTS fire_cleanup rather than
  # sourcing the script, so that helper is not in scope and the extracted function would die with
  # "hf_bounded: command not found". A passthrough keeps the behaviour byte-identical; the helper's
  # OWN semantics (bound applied, expiry → 124, the disable seam) are covered against the real
  # definition by tests/handoff-fire-it2-bound.bats. Same shape as handoff-selfclose.bats.
  hf_bounded() { "$@"; }
  REPO_SRC="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HF="$REPO_SRC/scripts/handoff-fire.sh"

  # A real repo with one commit on origin/main, plus a real "remote" so `git fetch origin` works.
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
  ORIGIN="$BATS_TEST_TMPDIR/origin.git"
  git init -q --bare --initial-branch=main "$ORIGIN"
  REPO="$BATS_TEST_TMPDIR/repo"
  git init -q --initial-branch=main "$REPO"
  git -C "$REPO" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  git -C "$REPO" remote add origin "$ORIGIN"
  git -C "$REPO" push -q origin main
  git -C "$REPO" fetch -q origin
  WTROOT="$BATS_TEST_TMPDIR/wt"; mkdir -p "$WTROOT"

  PF="$BATS_TEST_TMPDIR/brief.md"
  printf 'do the thing\n' > "$PF"

  # The fake HOME must carry an it2 shim that EXISTS: handoff-fire probes it with
  # `sed … | head -1` under pipefail, so a MISSING file aborts the script long before any of the
  # failure branches under test — which would make every assertion below pass for the wrong reason.
  # (Same requirement fire-autonomy.bats documents.) Carrying a REAL_IT2 line keeps the probe honest.
  HOMEDIR="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOMEDIR/.claude/bin" "$HOMEDIR/.claude/cc-registry" "$HOMEDIR/.claude/cc-fired" \
           "$HOMEDIR/.claude/cc-roles" "$HOMEDIR/.claude/logs"
  cat > "$HOMEDIR/.claude/bin/it2" <<STUB
#!/bin/bash
REAL_IT2="$HOMEDIR/.claude/bin/it2"
exit 0
STUB
  chmod +x "$HOMEDIR/.claude/bin/it2"
  # Fixtured in setup(), not per-invocation: test-hermeticity-lint's rule is that a per-test HOME
  # leaves every OTHER test in the file pointed at the operator's live ~/. The explicit
  # `env HOME="$HOMEDIR"` below is then belt, not the mechanism.
  export HOME="$HOMEDIR"
}

# A fire that FAILS at the payload-lint gate — the earliest failure AFTER the worktree/slot are
# acquired, so it exercises the no-pane cleanup path end to end through the real script.
# The gate aborts (exit 4) when a payload has a back-channel block that is MALFORMED.
#
# CC_FIRE_CAPACITY_GATE=off is NOT cosmetic: the machine-capacity admission gate (0fc3a3d3) refuses a
# fire with exit 9 BEFORE the worktree is created whenever load/core is over its ceiling. Left on,
# this suite passes on an idle box and fails on a busy one — and the bats gate corpus itself runs
# under exactly the load that trips it (memory gate-admit-ceiling-self-starvation).
fire_that_fails() { # $1=worktree slug  [extra args…]
  local slug="$1"; shift
  local bad="$BATS_TEST_TMPDIR/bad-payload.md"
  printf 'do the thing\n\n## BACK-CHANNEL — ping the originator\n  cc-notify  "HANDOFF-PING: x"\n' > "$bad"
  run env HOME="$HOMEDIR" HANDOFF_ACCOUNT_SWEEP=off CC_FIRE_CAPACITY_GATE=off \
      CC_PAYLOAD_LINT_BIN="$REPO_SRC/scripts/payload-lint.sh" \
      bash "$HF" --prompt-file "$bad" --launcher claude --worktree "$slug" \
      --repo "$REPO" --wtroot "$WTROOT" "$@"
}

# fire_cleanup reads $? to decide whether the fire FAILED. Seed it with `false` inside a subshell
# that has errexit OFF — bats runs each @test under `set -e`, where a bare `( exit 1 )` would abort
# the test before the function is ever called. Side effects land on the real filesystem either way.
run_cleanup() { # $1=output file
  ( set +e; false; fire_cleanup ) > "$1" 2>&1 || true
}

@test "no pane landed: the cold worktree AND its branch are removed, not stranded" {
  fire_that_fails wt-cleanup-cold
  # EXIT 4 specifically = the payload-lint enforce gate, the failure this test means to inject. A
  # bare `-ne 0` would also be satisfied by aborting somewhere earlier, which would make every
  # assertion below pass without the cleanup path ever being the reason.
  [ "$status" -eq 4 ] || { echo "expected the payload-lint abort (4), got $status: $output"; false; }
  [[ "$output" == *"fire-cleanup"* ]] || { echo "no cleanup ran: $output"; false; }
  [ ! -d "$WTROOT/wt-cleanup-cold" ] || { echo "worktree STRANDED at $WTROOT/wt-cleanup-cold"; false; }
  if git -C "$REPO" rev-parse --verify --quiet "refs/heads/wt-cleanup-cold"; then
    echo "branch wt-cleanup-cold STRANDED"; false
  fi
  # …and git's own worktree registry has no leftover administrative entry either.
  if git -C "$REPO" worktree list --porcelain | grep -qF "wt-cleanup-cold"; then
    echo "worktree ADMIN entry stranded"; false
  fi
}

@test "RED-PROOF: pre-fix the same failure stranded both (this is what the guard catches)" {
  # A guard that cannot fail on the old code proves nothing. Replay the identical failure against the
  # PRE-FIX script recovered from git, and assert it leaks — so this suite is pinned to a real defect
  # rather than to the current implementation's log strings.
  # CC_PAYLOAD_LINT_BIN is passed EXPLICITLY (see fire_that_fails): the pre-fix copy lives in a temp
  # dir, where the sibling payload-lint.sh does not resolve, so without it the two sides would fail at
  # DIFFERENT gates and the comparison would be meaningless. (The pre-fix run then sails past the lint
  # gate into a spawn failure — which strands the worktree just the same, audit row 3's own scenario:
  # "anchor pane gone → spawn returns 1 → set -e aborts → worktree + branch leak".)
  # The pre-fix rev is DERIVED, never hardcoded. A literal sha does not survive a rebase — this
  # branch was rebased once already and every sha changed, which would have turned this RED-proof
  # into a permanent `skip`: the one failure mode a guard must not have, because it looks like a pass.
  # Pickaxe the commit that INTRODUCED fire_cleanup and take its parent; that is the pre-fix tree by
  # construction, in any history that contains the fix.
  local old="$BATS_TEST_TMPDIR/handoff-fire-prefix.sh" introduced
  introduced="$(git -C "$REPO_SRC" log --reverse --format=%H -S'fire_cleanup() {' -- scripts/handoff-fire.sh 2>/dev/null | head -1)"
  [ -n "$introduced" ] || { echo "could not locate the commit that introduced fire_cleanup"; false; }
  git -C "$REPO_SRC" show "$introduced^:scripts/handoff-fire.sh" > "$old" 2>/dev/null \
    || { echo "could not recover the pre-fix tree at $introduced^"; false; }
  # Positive control on the control itself: the recovered tree must genuinely LACK the fix, else this
  # test would "prove" the leak against a copy that already cleans up.
  if grep -q 'fire_cleanup() {' "$old"; then
    echo "the recovered pre-fix tree ALREADY has fire_cleanup — the control is not a control"; false
  fi
  local bad="$BATS_TEST_TMPDIR/bad-payload.md"
  printf 'do the thing\n\n## BACK-CHANNEL — ping the originator\n  cc-notify  "HANDOFF-PING: x"\n' > "$bad"
  run env HOME="$HOMEDIR" HANDOFF_ACCOUNT_SWEEP=off CC_FIRE_CAPACITY_GATE=off \
      CC_PAYLOAD_LINT_BIN="$REPO_SRC/scripts/payload-lint.sh" \
      bash "$old" --prompt-file "$bad" --launcher claude --worktree wt-cleanup-red \
      --repo "$REPO" --wtroot "$WTROOT"
  [ "$status" -eq 4 ] || skip "pre-fix build aborted at $status, not the payload-lint gate"
  [ -d "$WTROOT/wt-cleanup-red" ] || { echo "pre-fix run did not even create the worktree"; false; }
  git -C "$REPO" rev-parse --verify --quiet "refs/heads/wt-cleanup-red" >/dev/null \
    || { echo "expected the PRE-FIX run to strand the branch"; false; }
  # clean up after the deliberate leak so the suite leaves nothing behind
  git -C "$REPO" worktree remove --force "$WTROOT/wt-cleanup-red" >/dev/null 2>&1 || true
  git -C "$REPO" branch -D wt-cleanup-red >/dev/null 2>&1 || true
}

@test "no pane landed: an EXISTING worktree this fire did not create is left ALONE" {
  # The trap arms only after a successful `git worktree add`, and only for WT_SETUP=cold. A re-fire
  # onto an existing tree must never remove it — that tree can hold another session's work, and
  # removing it would turn a failed fire into data loss.
  git -C "$REPO" worktree add -q "$WTROOT/wt-cleanup-existing" -b wt-cleanup-existing origin/main
  printf 'someone else work in progress\n' > "$WTROOT/wt-cleanup-existing/WIP.txt"
  fire_that_fails wt-cleanup-existing
  [ "$status" -eq 4 ] || { echo "expected the payload-lint abort (4), got $status: $output"; false; }
  [ -d "$WTROOT/wt-cleanup-existing" ] || { echo "an EXISTING worktree was destroyed"; false; }
  [ -f "$WTROOT/wt-cleanup-existing/WIP.txt" ] || { echo "another session's work was destroyed"; false; }
  git -C "$REPO" rev-parse --verify --quiet refs/heads/wt-cleanup-existing >/dev/null \
    || { echo "an EXISTING branch was deleted"; false; }
}

@test "a SUCCESSFUL dry run cleans up nothing (the trap is disarmed on rc 0)" {
  run env HOME="$HOMEDIR" HANDOFF_ACCOUNT_SWEEP=off CC_FIRE_CAPACITY_GATE=off \
      CC_PAYLOAD_LINT_BIN="$REPO_SRC/scripts/payload-lint.sh" \
      bash "$HF" --prompt-file "$PF" --launcher claude --worktree wt-cleanup-dry \
      --repo "$REPO" --wtroot "$WTROOT" --dry-run
  [ "$status" -eq 0 ]
  ! [[ "$output" == *"fire-cleanup"* ]] || { echo "cleanup ran on a successful run"; false; }
}

# ── the POOL leg: a claim CONSUMES a slot by switching its branch; the release RESTORES it ────────

@test "no pane landed: a consumed pool slot is RETURNED to the pool, directory intact" {
  # worktree-pool.sh's contract (its own header + slot_live): a slot is the worktree wt-pool-N ON
  # branch pool/slot-N. Removing the directory would DESTROY the slot; the release is to restore its
  # identity. Build a real slot, hand it to fire_cleanup as a consumed claim, assert both facts.
  eval "$(sed -n '/^fire_cleanup() {/,/^}/p' "$HF")"
  local slot="$WTROOT/wt-pool-7"
  git -C "$REPO" worktree add -q "$slot" -b pool/slot-7 origin/main
  git -C "$slot" switch -q -C wt-consumed-slug            # exactly what `claim` does
  [ "$(git -C "$slot" branch --show-current)" = "wt-consumed-slug" ]

  FIRE_CLEAN_DONE=0; FIRE_CLEAN_WT=""; FIRE_CLEAN_POOL="$slot"
  FIRE_CLEAN_BRANCH="wt-consumed-slug"; SPAWNED_PANE=""
  run_cleanup "$BATS_TEST_TMPDIR/pool.out"

  [ -d "$slot" ] || { echo "the pool slot DIRECTORY was destroyed"; false; }
  [ "$(git -C "$slot" branch --show-current)" = "pool/slot-7" ] \
    || { echo "slot identity NOT restored: $(git -C "$slot" branch --show-current)"; cat "$BATS_TEST_TMPDIR/pool.out"; false; }
  if git -C "$slot" rev-parse --verify --quiet refs/heads/wt-consumed-slug; then
    echo "the stranded claim branch survived"; false
  fi
  grep -q "RETURNED" "$BATS_TEST_TMPDIR/pool.out"
}

# ── the PANE-LIVE leg: visibility, never a kill ───────────────────────────────────────────────────

@test "pane live + engagement missed: pane made VISIBLE (row + marker), worktree KEPT" {
  # The engagement miss is a NEGATIVE READ — a transcript we could not see inside the window — so a
  # slow cold install that engages seconds later must not be killed and must not lose its tree.
  eval "$(sed -n '/^ensure_registration() {/,/^}/p' "$HF")"
  eval "$(sed -n '/^mark_fired_peer() {/,/^}/p' "$HF")"
  eval "$(sed -n '/^fire_cleanup() {/,/^}/p' "$HF")"
  local reg="$BATS_TEST_TMPDIR/reg" fired="$BATS_TEST_TMPDIR/fired"
  mkdir -p "$reg" "$fired" "$WTROOT/wt-live-pane"

  FIRE_CLEAN_DONE=0; FIRE_CLEAN_POOL=""; FIRE_CLEAN_WT="$WTROOT/wt-live-pane"
  FIRE_CLEAN_BRANCH="wt-live-pane"; REPO="$REPO"
  SPAWNED_PANE="AAAABBBB-1111-2222-3333-444455556666"
  REG_DIR="$reg"; FIRED_DIR="$fired"; LAUNCH_DIR="$WTROOT/wt-live-pane"; CMD="claude"
  FIRING_SID="ORIGIN-PANE"; PROMPT_FILE="$PF"; WANT_SELF_RETIRE=1
  run_cleanup "$BATS_TEST_TMPDIR/live.out"

  [ -f "$reg/$SPAWNED_PANE.json" ] || { echo "no registry row → pane invisible to the reaper"; cat "$BATS_TEST_TMPDIR/live.out"; false; }
  [ -f "$fired/$SPAWNED_PANE.json" ] || { echo "no fired-peer marker → cc-reaper cannot auto-reap"; false; }
  [ -d "$WTROOT/wt-live-pane" ] || { echo "the worktree was removed from under a LIVE pane"; false; }
  grep -q "made VISIBLE" "$BATS_TEST_TMPDIR/live.out"
  grep -q "KEPT" "$BATS_TEST_TMPDIR/live.out"
}

@test "pane live: --no-self-retire leaves NO fired-peer marker, and says so" {
  # mark_fired_peer is fail-safe by construction: no marker ⇒ cc-reaper treats the pane as an
  # operator session and never auto-reaps it. Preserving that means the FAILED path must not invent
  # one — so the gap has to be NAMED with a hand-close command instead.
  eval "$(sed -n '/^ensure_registration() {/,/^}/p' "$HF")"
  eval "$(sed -n '/^mark_fired_peer() {/,/^}/p' "$HF")"
  eval "$(sed -n '/^fire_cleanup() {/,/^}/p' "$HF")"
  local reg="$BATS_TEST_TMPDIR/reg2" fired="$BATS_TEST_TMPDIR/fired2"
  mkdir -p "$reg" "$fired"
  FIRE_CLEAN_DONE=0; FIRE_CLEAN_POOL=""; FIRE_CLEAN_WT=""; FIRE_CLEAN_BRANCH=""
  SPAWNED_PANE="CCCCDDDD-1111-2222-3333-444455556666"
  REG_DIR="$reg"; FIRED_DIR="$fired"; LAUNCH_DIR="/tmp"; CMD="claude"
  FIRING_SID="ORIGIN-PANE"; PROMPT_FILE="$PF"; WANT_SELF_RETIRE=0
  run_cleanup "$BATS_TEST_TMPDIR/nosr.out"

  [ -f "$reg/$SPAWNED_PANE.json" ]                       # still made visible
  [ ! -f "$fired/$SPAWNED_PANE.json" ]                   # but never auto-reapable
  grep -q "NOT auto-reapable" "$BATS_TEST_TMPDIR/nosr.out"
  grep -q "it2 session close -f -s $SPAWNED_PANE" "$BATS_TEST_TMPDIR/nosr.out"   # exact hand-close cmd
}

@test "pane live: the pane is NEVER closed by default (kill is opt-in only)" {
  eval "$(sed -n '/^ensure_registration() {/,/^}/p' "$HF")"
  eval "$(sed -n '/^mark_fired_peer() {/,/^}/p' "$HF")"
  eval "$(sed -n '/^fire_cleanup() {/,/^}/p' "$HF")"
  # 2026-08-07: fire_cleanup no longer calls the it2 shim directly — every pane close in this script
  # now goes through hf_close_pane, which guards the target and writes a durable attribution row
  # (docs/plans/PANE_THEFT_2026-08-07.md). This test's SUBJECT is unchanged — "never by default,
  # opt-in closes" — so it must eval the new helpers rather than pin the old transport shape, or it
  # would go green by calling nothing at all (memory: stale-assertion-becomes-an-inverted-guard).
  eval "$(sed -n '/^hf_pane_agent_owned() {/,/^}/p' "$HF")"
  eval "$(sed -n '/^hf_close_pane() {/,/^}/p' "$HF")"
  eval "$(sed -n '/^hf_close_attrib() {/,/^}/p' "$HF")"
  in_kitty() { return 1; }
  kt_window_field() { return 0; }
  export CC_CLOSE_ATTRIB_LOG="$BATS_TEST_TMPDIR/close-attrib.jsonl"
  local h="$BATS_TEST_TMPDIR/home-kill"; mkdir -p "$h/.claude/bin"
  cat > "$h/.claude/bin/it2" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$HOME/it2-calls.log"
SH
  chmod +x "$h/.claude/bin/it2"
  mkdir -p "$BATS_TEST_TMPDIR/reg3" "$BATS_TEST_TMPDIR/fired3"
  FIRE_CLEAN_DONE=0; FIRE_CLEAN_POOL=""; FIRE_CLEAN_WT=""; FIRE_CLEAN_BRANCH=""
  SPAWNED_PANE="EEEEFFFF-1111-2222-3333-444455556666"
  REG_DIR="$BATS_TEST_TMPDIR/reg3"; FIRED_DIR="$BATS_TEST_TMPDIR/fired3"
  # EXPORTED rather than plain assignments: run_cleanup is eval'd out of handoff-fire.sh
  # above, so shellcheck cannot see the consumer and reads all five as dead (SC2034).
  # export is shellcheck's own documented remedy and is behaviour-neutral here, since the
  # subshell already inherited them. Pre-existing; it surfaced only because the
  # claude-next to claude rename rewrote this line and the land gate is own-scope.
  export LAUNCH_DIR="/tmp" CMD="claude" FIRING_SID="ORIGIN" PROMPT_FILE="$PF" WANT_SELF_RETIRE=1
  HOME="$h" run_cleanup /dev/null
  [ ! -f "$h/it2-calls.log" ] || { echo "the live pane was CLOSED on a negative read"; false; }

  # …and the documented opt-in does close it.
  FIRE_CLEAN_DONE=0; FIRE_FAILED_CLOSE_PANE=1
  HOME="$h" run_cleanup /dev/null
  grep -q "session close -f -s $SPAWNED_PANE" "$h/it2-calls.log"
}

# ── W2 X6: the TOMBSTONE before the cold-worktree remove (docs/research/load-root-cause-2026-10-17/
#    W2-CONTRACT.md). Every store is under $BATS_TEST_TMPDIR; the library is the repo's own. ─────────
tomb_env() {
  local t="$BATS_TEST_TMPDIR/wtstore"
  export WT_LEDGER="$t/ledger.jsonl" WT_TOMB_DIR="$t/tomb" WT_STATE_DIR="$t/state" \
    WT_EVENTS_FILE="$t/state/events.jsonl" WT_WAKE_FILE="$t/state/wake" WT_PARK_INDEX="$t/park-index" \
    WT_PARK_ROOT="$t/parked" WT_CONFIG_ROOTS="$HOMEDIR/.claude" WT_CRASH_LOG="$t/crashes.jsonl" \
    WT_RESUME_DEBT_DIR="$t/rdebt" WT_LR_DIR="$t/lr" WT_RECYCLE_FAILED_DIR="$t/rfail" \
    WT_BOOT_RESUME_DIR="$t/boot" WT_BACKLOG="$t/backlog.jsonl"
  mkdir -p "$t"
}

@test "tombstone: no pane landed → a handoff-fire row is written, THEN the cold worktree removed" {
  tomb_env
  fire_that_fails wt-tomb-cold
  [ "$status" -eq 4 ] || { echo "expected the payload-lint abort (4), got $status: $output"; false; }
  [ ! -d "$WTROOT/wt-tomb-cold" ] || { echo "worktree STRANDED: $output"; false; }
  local row
  row="$(jq -c 'select(.actor=="handoff-fire")' "$WT_LEDGER")"
  [ "$(jq -r .event <<<"$row")" = worktree-disposed ]
  [ "$(jq -r .reason <<<"$row")" = failed-fire ]
  [[ "$(jq -r .path <<<"$row")" == */wt-tomb-cold ]] || false
  [[ "$output" == *"cold worktree REMOVED ($WTROOT/wt-tomb-cold, tombstone $(jq -r .id <<<"$row"))"* ]] || false
}

@test "tombstone: an unwritable ledger KEEPS the cold worktree, with the hand-cleanup line" {
  tomb_env
  mkdir -p "$BATS_TEST_TMPDIR/ro"; chmod 555 "$BATS_TEST_TMPDIR/ro"
  export WT_LEDGER="$BATS_TEST_TMPDIR/ro/ledger.jsonl"
  fire_that_fails wt-tomb-ro
  chmod 755 "$BATS_TEST_TMPDIR/ro"
  [ "$status" -eq 4 ] || { echo "expected the payload-lint abort (4), got $status: $output"; false; }
  [ -d "$WTROOT/wt-tomb-ro" ] || { echo "removed WITHOUT its record"; false; }
  [[ "$output" == *"cold worktree $WTROOT/wt-tomb-ro KEPT (tombstone failed) — clean up by hand"* ]] || false
}

@test "tombstone: ignored residue in a failed fire's cold tree is moved into the tombstone, not deleted" {
  tomb_env
  eval "$(sed -n '/^fire_cleanup() {/,/^}/p' "$HF")"
  HF_DIR="$REPO_SRC/scripts"
  local wt="$WTROOT/wt-tomb-residue"
  git -C "$REPO" worktree add -q "$wt" -b wt-tomb-residue origin/main
  mkdir -p "$(git -C "$wt" rev-parse --path-format=absolute --git-common-dir)/info"
  printf 'out/\n' >> "$(git -C "$wt" rev-parse --path-format=absolute --git-common-dir)/info/exclude"
  mkdir -p "$wt/out"; printf 'made by the dead session\n' > "$wt/out/report.txt"
  FIRE_CLEAN_DONE=0; FIRE_CLEAN_POOL=""; FIRE_CLEAN_WT="$wt"; FIRE_CLEAN_BRANCH="wt-tomb-residue"; SPAWNED_PANE=""
  run_cleanup "$BATS_TEST_TMPDIR/residue.out"
  [ ! -d "$wt" ] || { cat "$BATS_TEST_TMPDIR/residue.out"; false; }
  local id
  id="$(jq -r 'select(.actor=="handoff-fire") | .id' "$WT_LEDGER")"
  [ "$(cat "$WT_TOMB_DIR/$id/residue/out/report.txt")" = 'made by the dead session' ]
}

# `git worktree add` writes logs/HEAD at once, so the tree a fire minted seconds ago always reads as
# owner-pinned (< 60 min). The fire IS that owner (wt_pinned --self-owned), so the tree is still removed.
@test "tombstone: a just-minted cold tree (FRESH logs/HEAD, not backdated) is tombstoned and removed" {
  tomb_env
  eval "$(sed -n '/^fire_cleanup() {/,/^}/p' "$HF")"
  HF_DIR="$REPO_SRC/scripts"
  local wt="$WTROOT/wt-tomb-fresh" gd
  git -C "$REPO" worktree add -q "$wt" -b wt-tomb-fresh origin/main
  gd="$(git -C "$wt" rev-parse --absolute-git-dir)"
  [ $(( $(date +%s) - $(stat -f %m "$gd/logs/HEAD") )) -lt 60 ]
  FIRE_CLEAN_DONE=0; FIRE_CLEAN_POOL=""; FIRE_CLEAN_WT="$wt"; FIRE_CLEAN_BRANCH="wt-tomb-fresh"; SPAWNED_PANE=""
  run_cleanup "$BATS_TEST_TMPDIR/fresh.out"
  [ ! -d "$wt" ] || { cat "$BATS_TEST_TMPDIR/fresh.out"; false; }
  [ "$(jq -r 'select(.actor=="handoff-fire") | .reason' "$WT_LEDGER")" = failed-fire ]
  ! grep -q 'pinned: owner' "$BATS_TEST_TMPDIR/fresh.out" || false
}

# Any OTHER pin still binds: a session that crashed in the tree and never resumed keeps it, with the
# hand-cleanup line, and no tombstone is written.
@test "tombstone: a crash-pinned cold tree is KEPT with the hand-cleanup line, no row" {
  tomb_env
  eval "$(sed -n '/^fire_cleanup() {/,/^}/p' "$HF")"
  HF_DIR="$REPO_SRC/scripts"
  local wt="$WTROOT/wt-tomb-pin" sid=sidCRASH d slug now
  git -C "$REPO" worktree add -q "$wt" -b wt-tomb-pin origin/main
  now="$(date +%s)"
  for d in "$wt" "$(cd "$wt" && pwd -P)"; do
    slug="$(printf '%s' "$d" | sed 's#[/.]#-#g')"
    mkdir -p "$HOMEDIR/.claude/projects/$slug"
    printf '{"type":"user","cwd":"%s"}\n' "$d" > "$HOMEDIR/.claude/projects/$slug/$sid.jsonl"
    touch -t "$(date -r $((now - 7200)) +%Y%m%d%H%M)" "$HOMEDIR/.claude/projects/$slug/$sid.jsonl"
  done
  printf '{"ts":"%s","class":"CRASH","sid":"%s"}\n' "$(date -u -r $((now - 3600)) +%Y-%m-%dT%H:%M:%SZ)" "$sid" \
    > "$WT_CRASH_LOG"
  FIRE_CLEAN_DONE=0; FIRE_CLEAN_POOL=""; FIRE_CLEAN_WT="$wt"; FIRE_CLEAN_BRANCH="wt-tomb-pin"; SPAWNED_PANE=""
  run_cleanup "$BATS_TEST_TMPDIR/pin.out"
  [ -d "$wt" ] || { cat "$BATS_TEST_TMPDIR/pin.out"; false; }
  grep -qF "cold worktree $wt KEPT (pinned: crash sid=$sid" "$BATS_TEST_TMPDIR/pin.out"
  grep -qF "clean up by hand: git -C $REPO worktree remove --force $wt" "$BATS_TEST_TMPDIR/pin.out"
  [ ! -e "$WT_LEDGER" ]
}

@test "RED control: the pre-tombstone fire_cleanup removes the same cold worktree with NO row" {
  tomb_env
  local old="$BATS_TEST_TMPDIR/handoff-fire-pretomb.sh"
  git -C "$REPO_SRC" show 7fa90e0c2:scripts/handoff-fire.sh > "$old"
  local bad="$BATS_TEST_TMPDIR/bad-payload.md"
  printf 'do the thing\n\n## BACK-CHANNEL — ping the originator\n  cc-notify  "HANDOFF-PING: x"\n' > "$bad"
  run env HOME="$HOMEDIR" HANDOFF_ACCOUNT_SWEEP=off CC_FIRE_CAPACITY_GATE=off \
      CC_PAYLOAD_LINT_BIN="$REPO_SRC/scripts/payload-lint.sh" \
      bash "$old" --prompt-file "$bad" --launcher claude --worktree wt-tomb-red \
      --repo "$REPO" --wtroot "$WTROOT"
  [ "$status" -eq 4 ] || { echo "control aborted at $status, not the payload-lint gate: $output"; false; }
  [ ! -d "$WTROOT/wt-tomb-red" ]                          # removed…
  [ ! -e "$WT_LEDGER" ]                                   # …with no record of it
}
