#!/usr/bin/env bash
# cloud-contract.sh — THE absence contract, as code. Sourced, never executed.
#
#   cc_cloud_return_contract <branch>   → the block appended to every cloud brief, on stdout
#   cc_cloud_seed_message    <branch>   → the seed commit's message (one line)
#
# ── WHY THIS FILE EXISTS ──────────────────────────────────────────────────────────────────────
# CLOUD_OBSERVABILITY.md §4.1 states the one thing that makes an ABSENT ref informative:
#
#   "the fire declares a branch and a boot budget, and the session's brief requires its FIRST ACT
#    to be pushing that branch — an empty commit is enough. Absence then becomes informative: no
#    ref inside the budget is BOOTING (expected); no ref past it is NOT-STARTED (actionable)."
#
# That contract was PROSE ONLY. Nothing composed it into a brief, on either fire leg:
#   * scripts/handoff-fire.sh appended a "HOW TO RETURN YOUR WORK" block whose push is the LAST
#     act ("Push whatever you have before you finish") — so the ref appears, if at all, only after
#     the work is done, and its absence says nothing about whether the VM ever booted.
#   * bin/cc-offload's API leg (`--via api`, the default) delivered the brief VERBATIM with no
#     return instructions of any kind.
# So C1 NOT-STARTED — the one row this whole instrument emits as ACTIONABLE — could not mean
# "never booted". It meant "no ref", which a session that booted, worked for an hour and ended
# without pushing produces identically. That is not hypothetical: bin/cc-cloud's own `inbox` note
# records 222 of 262 live sessions on 2026-08-27 ending a turn at `need_input` — they had worked
# and asked a question — every one of them filed NOT-STARTED.
#
# ── WHY THE SEED IS AN EMPTY COMMIT AND NOT THE WORK ──────────────────────────────────────────
# The signal has to be emitted BEFORE the work, because the whole point is to separate "the VM
# never ran" from "the VM ran and produced nothing pushable". A first push that waits for real
# content cannot do that — it is the failing design, restated. An empty commit costs one object,
# carries no tree change, and is the smallest thing that can move a remote ref.
#
# ── WHY ONE COMPOSER RATHER THAN A BLOCK PER LEG ──────────────────────────────────────────────
# The defect being fixed IS a divergence between two legs and a document. Two copies of a contract
# is one copy plus a future divergence, and the leg that lost it (the API one) is the DEFAULT leg.
# The contract is text a VM reads, so its single source of truth is a function that emits text.
#
# ── THE SPELLING IS DEFENSIVE ON PURPOSE ──────────────────────────────────────────────────────
# `switch -c` FAILS when the branch already exists, and the two legs differ on whether it does:
# the CLI leg's branch is invented by the firing side and cannot exist on the VM, but the API leg
# names the branch in the create body's `outcomes.git_info.branches`
# (scripts/cloud-create-api.py:355), which authorises — and may materialise — it. One spelling has
# to work on both, so the fallback is part of the contract, not a nicety. Same for the push: `-u
# origin HEAD` pushes the branch the VM is actually on, never a ref name this side invented and
# nothing holds (backlog 7c6ff16259a0).

# The seed's message is a CONVENIENCE for a human reading `git log`, never a machine contract.
# Consumers that must recognise a seed-only branch test its CONTENT (an empty range diff against
# trunk — scripts/cloud-reconcile.sh's SEEDED arm), because a VM that reworded the message would
# otherwise turn a boot signal into a landable-looking result.
cc_cloud_seed_message() { # <branch> → one line
  printf 'chore: cloud session boot marker (%s)' "${1:-unknown}"
}

cc_cloud_return_contract() { # <branch> → the block, on stdout
  local branch="${1:-}"
  [ -n "$branch" ] || return 2
  cat <<EOF
── HOW TO RETURN YOUR WORK (this session runs off-box; read this BEFORE you start) ──
You are running in an Anthropic-managed VM. Nothing on the operator's machine can see your
filesystem, your processes or your terminal, and you cannot run this repo's /ship. Your ONLY
channel back is a git push, and it must go to exactly this branch:

    $branch

🚨 YOUR FIRST ACT IS THE PUSH, BEFORE ANY WORK. Run these three lines now — before you read the
brief again, before you open a file, before you plan anything:

    git switch -c $branch 2>/dev/null || git switch $branch
    git commit --allow-empty -m "$(cc_cloud_seed_message "$branch")"
    git push -u origin HEAD

That empty commit is not busywork and it is not optional. The firing side watches exactly one
thing — whether that ref appears — and it cannot ask you anything: there is no inbound channel to
this VM. Until the ref exists, a session that booted and is working reads IDENTICALLY to one that
never started, one that died at boot, and one that was refused entitlement, so the operator is
told your session never ran. Pushing first is what makes the difference visible, and it takes one
second.

If any of those three lines FAILS, that failure is the most valuable thing you can report: say so
in your final message, with the exact error, before doing anything else.

THEN do the work. Commit and push to the same branch as you go, and push whatever you have before
you finish even if the work is incomplete — an unpushed cloud session leaves no trace of any kind.
A local reconciler (scripts/cloud-reconcile.sh) discovers the branch and lands it.
EOF
}
