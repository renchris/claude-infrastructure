#!/usr/bin/env bats
# handoff-fire.sh — the tree a fire LANDS IN must not predate trunk (cc-backlog 6110fc45141e).
#
# THE INCIDENT. On 2026-08-08 a dispatched worker was fired into an already-existing `wt-<id>`
# worktree whose HEAD measured `git rev-list --count HEAD..origin/main` = 735 — eight days of trunk.
# The post-land RED it carried reproduced FAITHFULLY there, because the fix that had landed on trunk
# seven days earlier was simply absent from that tree. Every ordinary check therefore passed: the
# failure was live, the file matched the item, the diagnosis was correct — and the diff it produced
# would have REVERTED two landed generalisations, with a commit message confidently explaining why.
# Only an explicit `git show origin/main:<path>` caught it.
#
# WHY THE GATE IS IN handoff-fire AND NOT ONLY IN cc-dispatch. cc-dispatch fixed its own `--cwd`
# path (backlog 1b00d62958a6). But `--worktree <branch>` is the form the global CLAUDE.md hands
# every lead for a dispatched wave, and its `exists — reused as-is` arm did no fetch, read no base
# and printed no lag — verified on origin/main before this change: a worktree three commits behind
# fires, exit 0, with the readout line `worktree: … (exists — reused as-is)` and nothing else.
#
# WHAT THESE CASES PIN, and why each is not the others:
#   1-3  the LEFTOVER arm (no commits of its own) — announced, and actually CURED. This is the
#        incident's own shape; it needs no threshold and makes no judgment call.
#   4    the POSITIVE CONTROL — a fresh tree says NOTHING. A gate that fired on every fire would
#        carry exactly as many bits as one that never fires (memory: alarm-polarity-and-attention-budget).
#   5-7  the WIP arm — a branch with its own commits, or with uncommitted changes, is somebody's
#        work: warned with the numbers, never rebased, never discarded, and refused only past the
#        catastrophic-case backstop.
#   8    the MODE split — `--cwd` may only ever warn (it is also how a lead re-fires a peer into its
#        own live worktree, which is divergent and dirty on purpose).
#   9-11 the sensor's own failure modes — unknown ≠ stale, not-a-repo ≠ stale, and the kill switch
#        restores the pre-gate behaviour byte for byte.
#
# RED-PROOF (run against the pristine pre-change script recovered with
# `git show origin/main:scripts/handoff-fire.sh`, via HF_OVERRIDE): cases 1, 2, 3, 5, 6, 7, 8 and 9
# FAIL there — there is no `freshness:` field, no refusal and no fast-forward on that tree. Cases 4,
# 10 and 11 PASS on both trees, which is the point of them: they assert behaviour this change must
# NOT alter.
#
# HERMETIC: $HOME is fixtured, and both DEFAULT_REPO and $WTROOT are derived from $HOME by the
# script under test, so no case can read or mutate live worktree state. The fixture repos have a
# LOCAL `refs/remotes/origin/main` and no remote at all, so the gate's `git fetch origin` always
# fails — deliberately: the fetch-failed arm is the one production hits on a flaky network, and it
# must still produce a verdict rather than a hang or a false green.

setup() {
  export CC_FIRE_CAPACITY_GATE=off
  export CC_FIRE_HEADROOM_GATE=off
  SRC="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HF="${HF_OVERRIDE:-$SRC/scripts/handoff-fire.sh}"
  # PHYSICAL $HOME — $BATS_TEST_TMPDIR lives under a /var → /private/var symlink, and the script
  # resolves its paths with `pwd -P`; resolving once here leaves one normal form to assert against.
  # Assigned in TWO steps on purpose, and neither half is cosmetic: `export HOME="$(…)"` is SC2155
  # (the bats-shellcheck ratchet), while the hermeticity ratchet matches only `export HOME=` or
  # `HOME="$BATS…` — so the one-liner that satisfies either gate reds the other. This form gives
  # both the literal they look for and the physical path the assertions need.
  HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  HOME="$(cd "$HOME" && pwd -P)"; export HOME
  mkdir -p "$HOME/.claude/bin"
  # SEAMS THAT DO NOT RESOLVE UNDER $HOME. Fixturing $HOME does not redirect an absolute /tmp
  # default, nor a BARE NAME the subject then executes off the operator's PATH — so the account
  # sweep would otherwise stamp a shared /tmp file and run the DEPLOYED claude-accounts once per
  # case. Absent paths are the right values here: every one of these sensors fails open on a miss.
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/account-sweep.json"
  export CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/absent-claude-accounts"
  export CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/heal-"
  # The it2 shim only has to EXIST (a dry run never invokes it); handoff-fire probes it with sed.
  printf 'REAL_IT2="/nonexistent/it2"\nPYTHON_BIN="/usr/bin/python3"\n' > "$HOME/.claude/bin/it2"
  chmod +x "$HOME/.claude/bin/it2"
  REPO="$HOME/Development/reso-management-app"      # the script's own DEFAULT_REPO, so a fire from
  WTROOT="$HOME/Development/.worktrees"             # inside it resolves to it either way
  mkdir -p "$WTROOT"
  mkfixture "$REPO"
  PAYLOAD="$BATS_TEST_TMPDIR/p.txt"
  echo "TASK — freshness fixture payload." > "$PAYLOAD"
}

# g <repo> <args…> — git with a TRANSIENT identity. Never `git -C "$x" config user.email …`: an
# empty $x makes `git -C ""` a documented NO-OP that writes into the CURRENT repo instead, and ~100
# linked worktrees here share one .git/config (the 2026-08-05 identity leak).
g() { local r="${1:?repo required}"; shift; git -C "$r" -c user.email=f@x -c user.name=f "$@"; }

# mkfixture <dir> — a repo whose HEAD is `origin/main`, plus TRUNK_N further commits on that ref.
# Everything below moves a worktree BACKWARD off it, so "behind" is a fact and not a naming claim.
mkfixture() {
  : "${1:?mkfixture: repo path required}"
  mkdir -p "$1"
  g "$1" init -q -b main
  echo x > "$1/f"; g "$1" add f; g "$1" commit -qm init
  BASE_OLD="$(g "$1" rev-parse HEAD)"
  local i
  for i in 1 2 3 4 5; do echo "$i" >> "$1/f"; g "$1" commit -qam "trunk $i"; done
  g "$1" update-ref refs/remotes/origin/main HEAD
  BASE_TIP="$(g "$1" rev-parse HEAD)"
}

# stale_wt <name> — a worktree cut from BASE_OLD: five commits behind origin/main, none of its own.
# This is the incident's shape (a fresh cut that simply aged), at a scale a test can read.
stale_wt() { g "$REPO" worktree add -q -b "$1" "$WTROOT/$1" "$BASE_OLD"; }

# diverge <name> <n> — give an existing worktree <n> commits of its OWN on top of its stale base.
diverge() { local i; for ((i=0; i<$2; i++)); do echo "own$i" >> "$WTROOT/$1/f"; g "$WTROOT/$1" commit -qam "own $i"; done; }

lag_of() { git -C "$WTROOT/$1" rev-list --count HEAD..origin/main; }

# fire <cwd> [args…] — the real script, from <cwd>, with the ambient gates pinned off.
fire() {
  local at="$1"; shift
  run env -u ITERM_SESSION_ID CC_FIRE_CAPACITY_GATE=off HANDOFF_ACCOUNT_SWEEP=off \
      bash -c "cd '$at' && bash '$HF' --prompt-file '$PAYLOAD' --session-id 'w0t0p0:FIX' \"\$@\"" _ "$@"
}

# ── 1-3: the LEFTOVER arm — the incident's own shape ────────────────────────────────────────────

@test "1 a --worktree fire into a tree BEHIND the base says so in the readout, not 'reused as-is'" {
  stale_wt wt-x
  fire "$REPO" --dry-run --worktree wt-x
  [ "$status" -eq 0 ]
  # The field itself — the one the operator reads before firing. On origin/main it does not exist.
  echo "$output" | grep -q "^freshness: STALE by 5 commit(s) behind origin/main" || false
  echo "$output" | grep -q "no commits of its own — would be fast-forwarded" || false
}

@test "2 a real (non-dry) fire CURES it — the tree is fast-forwarded before the worker sees it" {
  # The behaviour, not the message. The fire itself then fails (no live pane in a fixture), which is
  # why the assertion is on the tree: the cure must be complete BEFORE anything is launched, or a
  # worker could still be handed the stale tree by a fire that succeeds.
  stale_wt wt-x
  [ "$(lag_of wt-x)" -eq 5 ]
  fire "$REPO" --worktree wt-x
  [ "$(lag_of wt-x)" -eq 0 ]
  [ "$(git -C "$WTROOT/wt-x" rev-parse HEAD)" = "$BASE_TIP" ]
  echo "$output" | grep -q "was 5 commit(s) behind origin/main with no commits of its own — fast-forwarded" || false
}

@test "3 the fetch could not run, and the verdict says the lag is a FLOOR rather than claiming none" {
  # The fixture has no remote, so `git fetch origin` fails on every case in this file. A sensor that
  # cannot refresh its base must not report `fresh`; it reports what it CAN prove and labels it.
  stale_wt wt-x
  fire "$REPO" --dry-run --worktree wt-x
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "fetch failed — measured against the LAST-FETCHED origin/main, so this lag is a floor" || false
}

# ── 4: the POSITIVE CONTROL ─────────────────────────────────────────────────────────────────────

@test "4 POSITIVE CONTROL — a tree AT the base is fired into silently, with no freshness field" {
  # Without this, cases 1-3 would also pass if the gate simply shouted on every fire.
  g "$REPO" worktree add -q -b wt-fresh "$WTROOT/wt-fresh" "$BASE_TIP"
  fire "$REPO" --dry-run --worktree wt-fresh
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "worktree: $WTROOT/wt-fresh  (exists — reused as-is)" || false
  ! echo "$output" | grep -q "^freshness:" || false
  ! echo "$output" | grep -qi "STALE" || false
}

# ── 5-7: the WIP arm — never rebase or discard work the actuator did not create ─────────────────

@test "5 a branch with commits OF ITS OWN is warned about with the numbers — and still fired" {
  # A live branch a few commits behind trunk is the normal state of work in flight. Refusing it
  # would make the gate fire on the healthy population, which is how a guard's refusal ends up
  # hitting its own harness. It warns, and it leaves the branch exactly where it was.
  stale_wt wt-x; diverge wt-x 2
  local head_before; head_before="$(git -C "$WTROOT/wt-x" rev-parse HEAD)"
  fire "$REPO" --dry-run --worktree wt-x
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "^freshness: STALE: 5 commit(s) behind origin/main, 2 of its own" || false
  [ "$(git -C "$WTROOT/wt-x" rev-parse HEAD)" = "$head_before" ]
}

@test "6 UNCOMMITTED changes make it WIP too — the tree is warned about, never fast-forwarded" {
  # own=0 but dirty: a leftover path with somebody's unsaved edits in it. The leftover arm's cure
  # must not reach this case — a `merge --ff-only` over uncommitted work is a destructive act taken
  # by an unattended actuator over work it did not create.
  stale_wt wt-x
  echo "unsaved" >> "$WTROOT/wt-x/f"
  fire "$REPO" --dry-run --worktree wt-x
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "uncommitted changes present" || false
  [ "$(lag_of wt-x)" -eq 5 ]
  grep -q unsaved "$WTROOT/wt-x/f" || false
}

@test "7 …but past CC_FIRE_WT_STALE_MAX a divergent tree is REFUSED, and nothing is launched" {
  # The backstop for the catastrophic case (735), not a hygiene threshold — hence a threshold that
  # production never trips and this case sets explicitly.
  stale_wt wt-x; diverge wt-x 1
  run env -u ITERM_SESSION_ID CC_FIRE_CAPACITY_GATE=off HANDOFF_ACCOUNT_SWEEP=off CC_FIRE_WT_STALE_MAX=2 \
      bash -c "cd '$REPO' && bash '$HF' --prompt-file '$PAYLOAD' --session-id 'w0t0p0:FIX' --dry-run --worktree wt-x"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "exceeds CC_FIRE_WT_STALE_MAX=2 — refusing" || false
  ! echo "$output" | grep -q "^command:" || false
}

# ── 8: the MODE split ───────────────────────────────────────────────────────────────────────────

@test "8 --cwd WARNS at any lag and never refuses — it is also how a live peer is re-fired" {
  stale_wt wt-x; diverge wt-x 1
  run env -u ITERM_SESSION_ID CC_FIRE_CAPACITY_GATE=off HANDOFF_ACCOUNT_SWEEP=off CC_FIRE_WT_STALE_MAX=2 \
      bash -c "cd '$REPO' && bash '$HF' --prompt-file '$PAYLOAD' --session-id 'w0t0p0:FIX' --dry-run --cwd '$WTROOT/wt-x'"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "5 commit(s) behind origin/main, 1 of its own" || false
  ! echo "$output" | grep -q "refusing" || false
  echo "$output" | grep -q "^command:" || false
}

# ── 9-11: the sensor's own failure modes ────────────────────────────────────────────────────────

@test "9 an UNRESOLVABLE base is announced as UNKNOWN and still fires — it is not read as stale" {
  # `merge-base --is-ancestor` exits 0 / 1 / something-else, and folding the third into `no` is how
  # a sensor that cannot READ reports ABSENT. A missing base ref must not manufacture a refusal.
  stale_wt wt-x
  g "$REPO" update-ref -d refs/remotes/origin/main
  fire "$REPO" --dry-run --worktree wt-x
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "freshness UNKNOWN" || false
  echo "$output" | grep -q "^command:" || false
}

@test "10 a --cwd that is not a git worktree at all is silent — there is no base to be behind" {
  mkdir -p "$BATS_TEST_TMPDIR/nogit"
  fire "$REPO" --dry-run --cwd "$BATS_TEST_TMPDIR/nogit"
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q "freshness" || false
}

@test "11 KILL SWITCH — CC_FIRE_WT_FRESH=off restores the pre-gate behaviour exactly" {
  stale_wt wt-x
  run env -u ITERM_SESSION_ID CC_FIRE_CAPACITY_GATE=off HANDOFF_ACCOUNT_SWEEP=off CC_FIRE_WT_FRESH=off \
      bash -c "cd '$REPO' && bash '$HF' --prompt-file '$PAYLOAD' --session-id 'w0t0p0:FIX' --dry-run --worktree wt-x"
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q "freshness" || false
  echo "$output" | grep -q "worktree: $WTROOT/wt-x  (exists — reused as-is)" || false
  [ "$(lag_of wt-x)" -eq 5 ]
}
