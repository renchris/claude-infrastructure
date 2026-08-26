#!/usr/bin/env bash
# cloud-brief.sh — THE BOOT CONTRACT, in ONE place, for every producer of a cloud brief.
# Sourced, never executed. Pure: it composes text, reads nothing, writes nothing.
#
#   cc_cloud_boot_contract <branch>   → the FIRST-ACT block, on stdout (rc 2 with no branch)
#   cc_cloud_boot_marker              → the one grep-able string every such block carries
#
# ── WHY THIS FILE EXISTS ────────────────────────────────────────────────────────────────────────
# CLOUD_OBSERVABILITY.md §4.1 is the load-bearing paragraph of the whole cloud observability stack:
#
#   "A declared cloud session that has pushed nothing is indistinguishable from one that never
#    started, one that died at boot, and one that was refused entitlement. All four read as 'no
#    ref'. … It can only be resolved by CONTRACT: the fire declares a branch and a boot budget, and
#    the session's brief requires its FIRST ACT to be pushing that branch — an empty commit is
#    enough."
#
# That contract was PROSE ONLY. It was written in §4.1, restated as step 2 of §8's fire-time
# protocol, and implemented by nobody: `grep -rn 'allow-empty' bin/ scripts/` found exactly one
# hit, in cc-cloud's own selftest fixture. Both real brief producers shipped without it —
# handoff-fire.sh's payload instructed the push as the LAST act ("read this before you finish"),
# and `cc-offload up` delivered the task file verbatim with no return instruction at all — so the
# state function's C1 arm rested on a promise no brief had ever made.
#
# ── WHAT THAT COST, MEASURED ────────────────────────────────────────────────────────────────────
# bin/cc-eligible:404-416, over the whole live cloud population on 2026-08-23: of the 133 sessions
# reading `NOT-STARTED`, 130 still answer `GET /v1/code/sessions/<id>` and 119 read
# `environment_kind: anthropic_cloud` AND `sources: 1` — real VMs, attached repo, fully able to
# push. They booted, read the brief, found the item's project absent and correctly stopped. Their
# own words: "reso-management-app repo absent in cloud VM; backlog item unreachable". One of them
# spent $2.00 reaching that verdict. `NOT-STARTED` named none of it, because a session that
# correctly declines the work commits nothing to push, and "committed nothing" and "never booted"
# are the same observation when nothing was ever required to be pushed FIRST.
#
# So the boot push is not bookkeeping. It is the single bit that makes every later absence mean
# something: with it, no ref past the boot budget is genuinely "never started", and a session that
# booted and then produced nothing is a ref frozen at its receipt — C4 STALLED, a different verdict
# with a different cure.
#
# ── ONE TEXT, TWO PRODUCERS ─────────────────────────────────────────────────────────────────────
# handoff-fire.sh (the CLI leg) and `cc-offload up` (the API leg) both compose briefs, and a
# contract written twice is a contract that drifts — the defect this repo has already paid for with
# two tools reading one observable set (bin/cc-cloud's own header, on the deleted cc-cloud-watch).
# Neither may hand-roll the wording; both source this.
#
# ── THE RECEIPT LANDS, AND THAT IS DELIBERATE ───────────────────────────────────────────────────
# `git rebase` keeps an originally-empty commit (measured on git 2.43), so the receipt rides the
# branch through cloud-reconcile's re-author replay and onto trunk as one empty `chore:` commit per
# landed cloud session. It is left there rather than filtered out at land time: the lander's replay
# is the one place cloud commits are reconstructed, and teaching it to drop a commit by message
# would make a lie of the receipt the moment a session pushed nothing else. One empty commit naming
# where an off-box session began is provenance, at the same grain as the Cloud-session trailer the
# lander already writes.
#
# ── WHAT THE WORDING MUST NOT DO ────────────────────────────────────────────────────────────────
# The commit message is written INSIDE this repo's own commit-msg hook (githooks/commit-msg), which
# refuses `claude.ai/code` and AI-authorship trailers, and cloud-reconcile refuses a land it cannot
# re-author. So the receipt's message carries no URL, no session id and no trailer — a plain
# lowercase Conventional Commits subject, which is also what CLAUDE.md § Git Commit Messages wants.

# The marker every emitted block carries. A test asserts on THIS, not on a re-typed sentence, so a
# reworded contract cannot silently stop being one.
cc_cloud_boot_marker() { printf 'FIRST ACT — BEFORE ANY WORK'; }

# cc_cloud_boot_contract <branch> → the block. rc 2 when no branch is named: a contract that told
# the VM to push "the branch" would be exactly the un-pushable instruction §4.1 is written against.
cc_cloud_boot_contract() {
  local br="${1:-}"
  [ -n "$br" ] || return 2
  cat <<EOF
── $(cc_cloud_boot_marker) (this session runs off-box) ──
Run these three commands NOW, before you read the brief below and before you touch anything:

    git switch -c $br
    git commit --allow-empty -m 'chore: boot receipt for an off-box session'
    git push -u origin HEAD

WHY, so you do not skip it as ceremony: the firing side watches exactly that branch and has no
other channel to you. Until it appears, "this session never booted", "it died at boot", "it was
refused entitlement" and "it is working fine and has nothing to commit yet" are ONE observation on
this side, and the observer must either alarm on healthy sessions or stay silent over dead ones.
The empty commit costs nothing and is what tells those four apart: it is a boot receipt, not work.

Push it FIRST — before reading further, before any investigation, and before deciding whether the
task is even doable here. A session that reads the brief, finds it cannot proceed and stops without
pushing is indistinguishable from one that never ran at all; that exact case is why this block
exists. If you then find you cannot do the work, say so in a commit on this branch and push that
too — a pushed refusal is a finding, and an unpushed one is nothing.
EOF
}
