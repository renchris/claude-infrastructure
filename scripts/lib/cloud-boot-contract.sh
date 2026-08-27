#!/usr/bin/env bash
# cloud-boot-contract.sh — THE boot contract, in one place. Sourced, never executed.
#
#   CC_CLOUD_BOOT_CONTRACT             the token recorded on the declaration (`first-push`)
#   cc_cloud_boot_contract <branch>    the clause a cloud brief must carry, on stdout
#
# ── WHY THIS FILE EXISTS ─────────────────────────────────────────────────────────────────────────
# CLOUD_OBSERVABILITY.md §4.1 is the load-bearing paragraph of that whole document: a declared cloud
# session that has pushed nothing is indistinguishable from one that never started, one that died at
# boot, and one that was refused entitlement — all four are `ls-remote` rc=0 with empty stdout — and
# because there is no inbound channel to a cloud VM the ambiguity "can only be resolved by CONTRACT:
# the fire declares a branch and a boot budget, and the session's brief requires its FIRST ACT to be
# pushing that branch". C1 NOT-STARTED means "never booted" ONLY because of that sentence.
#
# The sentence was never code. Measured on trunk 2026-08-27: `grep -rni 'first act' bin/ scripts/`
# returned three hits and not one of them is a cloud brief, and the only place a fire told a session
# to push at all was handoff-fire.sh's return block, which says *"Push whatever you have BEFORE YOU
# FINISH"* — the opposite end of the session. So the observable the state function keys on was
# produced, if at all, at the END of the work, while the verdict that reads its absence fires after
# **15 minutes** (`CC_CLOUD_BOOT_S`, 900). A healthy session doing an ordinary backlog item is
# therefore convicted NOT-STARTED as a matter of course, and the state means only "has not finished
# yet". The live board says exactly that: **65 of 84 non-retired declarations read NOT-STARTED**
# (docs/research/breaking-the-ceiling-2026-08-19/B2-cloud-economics.md §2.6) against a mature-window
# push rate of **80%** — an alarm that fires on the healthy majority, which carries as many bits as
# one that never fires.
#
# §12.5 is the same defect with the receipt attached: thirteen sessions were read as inert, and when
# the operator finally opened one in the web UI it had done the entire brief and been refused at the
# push by the git proxy. *"Every instrument this box owns is a ref-watcher, so 'did not push' and
# 'did not run' produce byte-identical evidence here."* The contract is what makes the ref-watcher's
# silence mean something, and it has to be DELIVERED to mean it.
#
# ── WHY ONE FILE AND NOT TWO COPIES ──────────────────────────────────────────────────────────────
# Two fire paths compose a cloud brief — `handoff-fire.sh --cloud` (the CLI/bundle leg) and
# `cc-offload up` (the API leg, which is the production path today). §5.1 records what happened the
# last time one observable had two implementations: `bin/cc-cloud-watch` was deleted because "two
# tools reading one observable set drift and a caller cannot tell which is authoritative." A
# contract is worse than an observable that way — a wording that drifts on one leg silently unmakes
# the verdict for every session fired through it, and nothing downstream can tell. So the clause has
# ONE producer, and the token a declaration records is the same string this file exports.
#
# ── WHY THE FIRST ACT PUBLISHES A BRANCH AND NOT AN EMPTY COMMIT ─────────────────────────────────
# §4.1 says "an empty commit is enough", and it is — as a statement of how little is needed. It is
# not what this ships, for a reason downstream of that paragraph: `scripts/cloud-reconcile.sh`
# replays EVERY commit in `merge-base..branch` onto trunk with `git commit-tree` (:551), so a boot
# commit is not a signal that stops at the remote — it becomes an empty commit on origin/main, once
# per landed cloud session, ~8 times a day at the mature-window rate. Publishing the branch with no
# commit on it produces the same observable (the ref appears; `ls-remote` answers) and leaves the
# landing path with an empty range, which `re_author` already returns 0 on and the lander already
# reports as "nothing to land" (cloud-reconcile.sh:579 records that exact case as known and
# harmless). The cheaper signal is also the one with no downstream cost.
#
# It is still a real push, so it still proves everything the empty commit would have: that the VM
# booted, that its clone has a remote, and that the git proxy will inject a credential for this repo
# — which is the precise thing §12.5's 403 refused, and the fault this contract exists to surface
# within seconds instead of never.
#
# ── THE `switch -c … || switch` IS NOT DEFENSIVE PADDING ─────────────────────────────────────────
# The two legs hand the VM different starting states. The CLI/bundle leg uploads a tree with no
# remote at all (§12.5: "its clone had no remotes"), so the branch does not exist and must be
# created. The API leg names the branch in the create body's `outcomes.git_info.branches`
# (scripts/cloud-create-api.py:357), and §13.4 measured that a remote-TRACKING ref is seeded at
# provision time — so `git switch -c` there fails on a name that already exists locally. One block
# has to work in both worlds or the contract is delivered to one leg and not the other.
# shellcheck disable=SC2034  # consumed by the SOURCING script (the fire legs pass it to
# `cc-cloud declare --boot-contract`), not here. It lives beside the clause on purpose: producer and
# consumer must agree on one string, and a fire that hardcodes 'first-push' while the clause is
# reworded is exactly the drift this one-file rule exists to prevent.
CC_CLOUD_BOOT_CONTRACT="first-push"

# cc_cloud_boot_contract <branch> → the clause, on stdout. rc 2 with no branch: a contract that
# names no branch is not a weaker contract, it is none at all — the session would publish something
# nothing declared, and the watcher would go on reading absence.
cc_cloud_boot_contract() {
  local b="${1:-}"
  [ -n "$b" ] || return 2
  cat <<EOF
── FIRST ACT — PUBLISH YOUR BRANCH BEFORE YOU DO ANYTHING ELSE ──
Before you read a file, plan, or think about the task below, run exactly this:

    git switch -c $b 2>/dev/null || git switch $b
    git push -u origin HEAD

That publishes the branch with nothing on it yet and takes about a second. Do it FIRST — not after
the work, not once there is something worth showing.

This is not bookkeeping. Nothing on the machine that fired you can see your VM: not your files, not
your processes, not your terminal. The ONE thing it can observe is this branch on the remote. Until
that push lands you are indistinguishable from a session that never booted at all, so the watcher
reports you NOT-STARTED and your work is re-fired somewhere else while you are still doing it.
Pushing first is what makes your silence afterwards mean "still working" rather than "never existed".

If that push FAILS, say so in your first message and stop. A push failure here is the one fault you
cannot report any other way, and it is not hypothetical: a session whose repository was not attached
at create time is refused by the git proxy with \`403 … not in this session's authorized repository
set\`, and everything it goes on to do strands in the container when it is reclaimed.

Then do the task. Commit and push your work to this same branch as you go — it is your only channel
home, and a local reconciler lands it from there.
EOF
}
