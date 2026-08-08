#!/usr/bin/env bats
# handoff-fire.sh — WHICH REPO a --worktree fire targets (cc-backlog cb5a49f6f862).
#
# WHY THIS EXISTS: $REPO was initialised to a hardcoded DEFAULT_REPO (reso-management-app) and only
# ever moved off it by an explicit --repo. Every other consumer of $REPO — the cold `git worktree
# add`, the .env.local copy, the worktree-pool claim, the self-routing landing dir — therefore
# targeted reso no matter which repo the fire came FROM. Verified 2026-07-24: a
# claude-infrastructure /handoff landed its peer in .worktrees/wt-pool-2, whose git-common-dir is
# reso-management-app/.git, with none of this repo's files in it. The fire printed "→ fired". All
# ten pool slots on this box are reso's, so every cross-repo --worktree fire claimed one.
#
# TWO INDEPENDENT DEFECTS, TWO SETS OF CASES:
#   1-4  the CAUSE — $REPO must be resolved from the firing session's own checkout, with
#        DEFAULT_REPO surviving only as the outside-a-git-repo fallback.
#   5-7  the CONSEQUENCE — $WTROOT is shared by every repo on this box (142 worktrees across 6
#        repos on 2026-07-29) under generic names (wt-pool-N; `chore`; `fix`), so a pool slot or an
#        existing path is only usable when its git-common-dir says it belongs to the resolved
#        $REPO. These hold even if the resolution above were wrong again.
#
# HERMETIC BY CONSTRUCTION: $HOME is fixtured, and DEFAULT_REPO/$WTROOT are both derived from $HOME
# by the script — so "reso" here is a two-commit fixture repo, never the operator's real checkout,
# and no case can read or mutate live worktree state. Every case is --dry-run (no session fires)
# with the capacity gate and the account sweep off (ambient load and the network must not decide a
# repo-resolution verdict).
#
# RED-PROOF (run 2026-07-29 against the pristine pre-change script recovered with
# `git show origin/main:scripts/handoff-fire.sh` — 3470 lines, 0 occurrences of REPO_EXPLICIT):
# 7 of these 8 cases FAIL there. Case 1's fire, from a repo with no pool of its own, reported
#   worktree: POOL CLAIM at fire time (scripts/worktree-pool.sh claim wt-x …)
# against the DEFAULT repo's pool — the 2026-07-24 incident, reproduced in a fixture. 1-4 also
# fail for want of any `repo:` line at all (the field had no producer, so the wrong repo was not
# merely chosen, it was invisible); 5-6 fail on eligibility decided against the wrong repo; 7 exits
# 0 and fires INTO the foreign checkout instead of refusing. Only case 8 passes on both trees —
# it asserts behaviour this change must NOT alter, so its passing there is the point.

setup() {
  # M11 (MACHINE_CAPACITY_V2 §11.3) — a test's environment is PINNED, not ambient. The per-test pins
  # below predate this and are the shape the hermeticity ratchet rejects: they leave every OTHER test in
  # the file reading live machine state. handoff-fire.sh's capacity_gate reads the box's loadavg AND
  # (M10) its memory headroom — the two TERMS of one exit 9 (handoff-fire.sh:4487) — so both are pinned
  # here, for the whole file. tests/handoff-fire-capacity-gate.bats is the ONE place the gate runs ON.
  export CC_FIRE_CAPACITY_GATE=off
  export CC_FIRE_HEADROOM_GATE=off
  SRC="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HF="$SRC/scripts/handoff-fire.sh"
  # HERMETICITY (ratchet): handoff-fire resolves the registry, roles, mailbox and projects dirs —
  # AND both DEFAULT_REPO and $WTROOT — under $HOME. Fixturing it is what makes the repo fixtures
  # below load-bearing instead of decorative. Must precede every invocation.
  # PHYSICAL $HOME. $BATS_TEST_TMPDIR lives under /var/folders, which is a symlink to
  # /private/var/folders — so the script's `pwd -P` resolution and git's absolute paths both come
  # back /private-prefixed while a template-built path does not. Two normal forms of one path, and
  # every assertion below would be comparing them. Resolve ONCE, here, so there is only one form.
  mkdir -p "$BATS_TEST_TMPDIR/home"
  export HOME="$(cd "$BATS_TEST_TMPDIR/home" && pwd -P)"
  mkdir -p "$HOME/.claude/bin"
  # The it2 shim must EXIST — handoff-fire probes it with `sed … | head -1` under `set -o
  # pipefail`, so an absent file aborts the whole script (fire-autonomy.bats documents the same
  # requirement). A dry run never invokes it; only the probe has to find something to read.
  printf 'REAL_IT2="/nonexistent/it2"\nPYTHON_BIN="/usr/bin/python3"\n' > "$HOME/.claude/bin/it2"
  chmod +x "$HOME/.claude/bin/it2"
  # The script's own defaults, restated so the assertions name what the script will compute.
  DEFAULT_REPO="$HOME/Development/reso-management-app"
  OTHER_REPO="$HOME/Development/other-repo"
  WTROOT="$HOME/Development/.worktrees"
  mkdir -p "$WTROOT"
  mkfixture "$DEFAULT_REPO"
  mkfixture "$OTHER_REPO"
  PAYLOAD="$BATS_TEST_TMPDIR/p.txt"
  echo "TASK — repo-resolution fixture payload." > "$PAYLOAD"
}

# mkfixture <dir> — a real git repo with a commit and an origin/main, the shape --worktree needs.
mkfixture() {
  # `git -C ""` is a NO-OP, not an error — an empty $1 would write this identity into the cwd repo.
  : "${1:?mkfixture: repo path required}"
  mkdir -p "$1"
  git -C "$1" init -q -b main
  git -C "$1" config user.email f@x; git -C "$1" config user.name f
  echo x > "$1/f"; git -C "$1" add f; git -C "$1" commit -qm init
  # origin/main as a local ref: the pool-eligibility test is `BASE = origin/main`, a string compare,
  # but `git worktree add` in a non-dry case would need the ref to exist.
  git -C "$1" update-ref refs/remotes/origin/main HEAD
}

# with_pool <repo> — give <repo> an executable scripts/worktree-pool.sh. Its body is never run by a
# dry-run (which stops at WT_SETUP=pool), so a stub that only proves executability is honest here.
with_pool() {
  mkdir -p "$1/scripts"
  printf '#!/bin/bash\necho "$HOME/unused"\n' > "$1/scripts/worktree-pool.sh"
  chmod +x "$1/scripts/worktree-pool.sh"
}

# slot <owner-repo> <path> — a real linked worktree, so git-common-dir ownership is a fact and not
# a naming convention.
slot() { git -C "$1" worktree add -q -b "wt-$(basename "$2")" "$2" HEAD; }

# fire <cwd> [args...] — the real script, from <cwd>, dry, with the ambient gates pinned off.
fire() {
  local at="$1"; shift
  run env -u ITERM_SESSION_ID CC_FIRE_CAPACITY_GATE=off HANDOFF_ACCOUNT_SWEEP=off \
      bash -c "cd '$at' && bash '$HF' --prompt-file '$PAYLOAD' --dry-run --session-id 'w0t0p0:FIX' \"\$@\"" _ "$@"
}

# ── 1-4: the CAUSE — $REPO comes from the firing session ────────────────────────────────────────

@test "1 a --worktree fire from ANOTHER repo targets THAT repo, not the hardcoded default" {
  with_pool "$DEFAULT_REPO"          # the default repo has a pool; the firing repo does not
  fire "$OTHER_REPO" --worktree wt-x
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "^repo:     $OTHER_REPO " || false
  echo "$output" | grep -q "resolved from the firing session's cwd" || false
  # and therefore NOT the default repo's pool — the 2026-07-24 misfire in one line
  ! echo "$output" | grep -q "POOL CLAIM" || false
  echo "$output" | grep -q "worktree: $WTROOT/wt-x  (cold" || false
}

@test "2 POSITIVE CONTROL — a fire from the default repo still resolves to it, and still pools" {
  with_pool "$DEFAULT_REPO"
  fire "$DEFAULT_REPO" --worktree wt-x
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "^repo:     $DEFAULT_REPO " || false
  echo "$output" | grep -q "POOL CLAIM" || false
}

@test "3 a fire from a LINKED WORKTREE resolves to the checkout that owns it, not the worktree" {
  # $REPO is used for `git worktree add`, .env.local and scripts/ — all main-checkout things.
  slot "$OTHER_REPO" "$WTROOT/linked"
  fire "$WTROOT/linked" --worktree wt-x
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "^repo:     $OTHER_REPO " || false
}

@test "4 outside any git repo, DEFAULT_REPO is the FALLBACK — and an explicit --repo always wins" {
  mkdir -p "$BATS_TEST_TMPDIR/nogit"
  fire "$BATS_TEST_TMPDIR/nogit" --worktree wt-x
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "^repo:     $DEFAULT_REPO " || false
  echo "$output" | grep -q "default (cwd is not a git repo)" || false
  # explicit --repo overrides a resolvable cwd (the desk firing another repo's work)
  fire "$OTHER_REPO" --worktree wt-x --repo "$DEFAULT_REPO"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "^repo:     $DEFAULT_REPO  (explicit --repo)" || false
}

# ── 5-7: the CONSEQUENCE — ownership in a $WTROOT shared by every repo ──────────────────────────

@test "5 a pool whose SLOTS belong to another repo is refused even when \$REPO owns the script" {
  # The exact incident state, minus the resolution bug: the firing repo has its own pool.sh, but
  # the wt-pool-N slots in the shared $WTROOT are the OTHER repo's. An executable pool script
  # proves a pool exists; it never proved the slots were ours.
  with_pool "$OTHER_REPO"
  slot "$DEFAULT_REPO" "$WTROOT/wt-pool-1"
  fire "$OTHER_REPO" --worktree wt-x
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "pool slot $WTROOT/wt-pool-1 belongs to $DEFAULT_REPO" || false
  ! echo "$output" | grep -q "POOL CLAIM" || false
  echo "$output" | grep -q "worktree: $WTROOT/wt-x  (cold" || false
}

@test "6 POSITIVE CONTROL — a pool whose slots ARE the resolved repo's stays eligible" {
  # Without this, case 5 would also pass if the gate simply refused every pool.
  with_pool "$OTHER_REPO"
  slot "$OTHER_REPO" "$WTROOT/wt-pool-1"
  fire "$OTHER_REPO" --worktree wt-x
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q "belongs to" || false
  echo "$output" | grep -q "POOL CLAIM" || false
}

@test "7 an EXISTING \$WTROOT path owned by another repo is REFUSED, never reused" {
  # `chore`, `fix`, `docs` are names several repos pick, and the shared $WTROOT resolves them by
  # name alone — so reuse is the wrong-repo defect again, reached by collision instead of default.
  slot "$DEFAULT_REPO" "$WTROOT/chore"
  fire "$OTHER_REPO" --worktree chore
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "a worktree of $DEFAULT_REPO — not $OTHER_REPO" || false
  echo "$output" | grep -q "Refusing to fire into another repo's checkout" || false
}

@test "8 POSITIVE CONTROL — an existing path owned by the resolved repo is still reused as-is" {
  slot "$OTHER_REPO" "$WTROOT/chore"
  fire "$OTHER_REPO" --worktree chore
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "worktree: $WTROOT/chore  (exists — reused as-is)" || false
}
