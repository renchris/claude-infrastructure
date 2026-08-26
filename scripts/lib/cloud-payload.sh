#!/usr/bin/env bash
# cloud-payload.sh — THE off-box brief contract. Sourced, never executed.
#
#   cc_cloud_boot_block   <branch>              → the FIRST-ACT block (stdout)
#   cc_cloud_return_block <branch>              → the RETURN block (stdout)
#   cc_cloud_payload      <brief-file> <branch> → brief + boot block + return block (stdout)
#
# ── WHY THIS FILE EXISTS ─────────────────────────────────────────────────────────────────────────
# CLOUD_OBSERVABILITY.md §4.1 is the load-bearing sentence of the whole cloud subsystem:
#
#     "It can only be resolved by contract: the fire declares a branch and a boot budget, and the
#      session's brief requires its FIRST act to be pushing that branch — an empty commit is
#      enough. Absence then becomes informative: no ref inside the budget is BOOTING (expected);
#      no ref past it is NOT-STARTED (actionable)."
#
# That contract was PROSE ONLY for two weeks (backlog `0c8b39b67665`). Neither lane implemented it:
#
#   · the CLI lane (handoff-fire.sh --cloud) appended a return block that said "Push whatever you
#     have BEFORE YOU FINISH" — the push as a LAST act, which is the exact inversion. A session that
#     boots and works for three hours pushes nothing until the end, so `cc-cloud` reads C1
#     NOT-STARTED over a perfectly healthy session for the whole of its boot budget and past it.
#   · the API lane (cc-offload up --via api) delivered `cat "$brief"` VERBATIM — no return
#     instruction of any kind. The branch is authorised at create in `outcomes.git_info.branches`,
#     but nothing ever told the session that the branch existed, let alone to push it first.
#
# §4.3's state function is a total function over ONE observable — does the ref exist, and has it
# advanced — so without the first act, C1 NOT-STARTED cannot mean "never booted". It collapses into
# "never booted, OR booted and has nothing to commit yet, OR booted and is three hours into a task".
# Those have opposite cures (re-fire vs. leave it alone), and the re-fire spends an account's rate
# limit on a duplicate of a session that is already running. §11.4's first live fire terminated on
# exactly that ambiguity and the document says so in the same breath: NOT-STARTED "means the
# declared ref never appeared — NOT that the session did nothing", and this box "structurally cannot
# find out" which.
#
# ── WHAT THE EMPTY COMMIT BUYS, stated as the state function reads it ────────────────────────────
# With the first act implemented, absence and presence both carry a fact instead of a disjunction:
#
#   no ref, inside boot budget   C2 BOOTING       expected; the VM is still coming up
#   no ref, past boot budget     C1 NOT-STARTED   the VM never reached a shell — RE-FIRE IS CORRECT
#   ref exists, sha quiet        C4 STALLED       it booted and then stopped — DO NOT RE-FIRE
#
# The middle row is the one this file exists for, and the third row is the one it makes reachable at
# all: before the boot push, a booted-then-wedged session was indistinguishable from a VM that never
# started, so `cc-cloud` could never emit STALLED for a cloud session that had not yet pushed work.
#
# ── ONE OWNER, TWO LANES ─────────────────────────────────────────────────────────────────────────
# Both lanes source THIS file. A second copy of the contract text is the failure this repo has paid
# for before (§5.1: `cc-cloud-watch` was deleted because two tools reading one observable set drift
# and a caller cannot tell which is authoritative). The branch name is the only parameter; the
# contract is not per-caller policy.
#
# The block is deliberately IMPERATIVE and carries its own WHY. A cloud session is a peer running
# this repo's own standards, and a step whose reason is withheld is the first one dropped when the
# brief gets interesting — which is precisely when the observability matters.

# Function definitions only — no side effects, so a second `.` is idempotent by construction and
# there is no source guard to get wrong. The CLI lane sources this beside cloud-create.sh and
# cc-offload sources it at load; both may end up doing so twice in one process.

# The FIRST ACT. Emitted BEFORE the brief's own text on purpose — a model reads top-down, and this
# is the one instruction whose value is entirely in being executed before anything else.
cc_cloud_boot_block() { # $1 = the assigned branch
  local br="${1:?cc_cloud_boot_block: branch is required}"
  cat <<EOF
── FIRST ACT — RUN THIS BEFORE ANYTHING ELSE (this session runs off-box) ──
You are running in an Anthropic-managed VM. Nothing on the operator's machine can see your
filesystem, your processes or your terminal. The ONE thing that box can observe about you is a
branch on the git remote. So before you read the task below, before you plan, and before you edit
anything, run exactly this — it costs one second:

    git switch -c $br || git switch $br
    git commit --allow-empty -m "chore: cloud session booted ($br)"
    git push -u origin HEAD

WHY FIRST, and not when you finish: the firing side cannot tell a VM that never booted from one
that booted and has not committed yet — both are "no ref on the remote". That empty commit is the
only thing that separates them. Until it lands you read as NOT-STARTED and may be re-fired (a
second VM doing your work, on the same account's rate limit) or reaped; once it lands, silence
reads as STALLED against a session that is known to exist.

$br was assigned by the firing side and is already declared as the branch watched for your
progress. Do not rename it and do not push anywhere else. If git refuses the commit for want of an
identity, set one and retry — do not skip this step and do not defer it.
EOF
}

# The RETURN block. Unchanged in substance from the one that shipped inline in handoff-fire.sh —
# the boot push makes a session OBSERVABLE, this is what makes its WORK reachable.
cc_cloud_return_block() { # $1 = the assigned branch
  local br="${1:?cc_cloud_return_block: branch is required}"
  cat <<EOF
── HOW TO RETURN YOUR WORK (read this before you finish) ──
You cannot run this repo's /ship, and there is no route from your VM back to the operator's box.
Your push IS your back-channel: a local reconciler (scripts/cloud-reconcile.sh) discovers $br on
the remote and hands it to the sanctioned local lander.

    git push -u origin HEAD        # same branch you created as your first act

Push whatever you have before you finish, even if the work is incomplete. An unpushed cloud session
leaves no trace of any kind — no transcript this box can open, no commit, nothing.
EOF
}

# The whole payload: FIRST ACT · the brief · HOW TO RETURN. The boot block leads because it is the
# only part whose correctness depends on when it is read.
cc_cloud_payload() { # $1 = file holding the brief, $2 = the assigned branch
  local pf="${1:?cc_cloud_payload: brief file is required}"
  local br="${2:?cc_cloud_payload: branch is required}"
  [ -r "$pf" ] || return 1
  cc_cloud_boot_block "$br"
  printf '\n'
  cat "$pf"
  printf '\n'
  cc_cloud_return_block "$br"
}
