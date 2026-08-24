#!/usr/bin/env bash
# cloud-brief.sh — THE BOOT CONTRACT, in one place. Sourced, never executed.
#
#   cc_cloud_boot_token            → the stable marker token, for the payload AND the detector
#   cc_cloud_boot_commit_message   → the exact commit message the payload prescribes
#   cc_cloud_return_block  branch  → the payload block: boot contract first, then the return push
#   cc_cloud_boot_only  repo trunk ref → 0 the range is the boot marker and nothing else
#                                        1 it carries work · 2 cannot tell
#
# ── WHY THIS FILE EXISTS ──────────────────────────────────────────────────────────────────────
# CLOUD_OBSERVABILITY.md §4.1 states the contract this repo's whole cloud-observability stack rests
# on: a declared cloud session that has pushed nothing is indistinguishable from one that never
# started, one that died at boot, and one that was refused entitlement — all four read as "no ref",
# and there is no inbound channel to a cloud VM, so the ambiguity cannot be resolved by asking. It
# can only be resolved by CONTRACT: "the session's brief requires its first act to be pushing that
# branch — an empty commit is enough." Absence then becomes informative, and C1 NOT-STARTED means
# what the state table says it means.
#
# That contract was PROSE ONLY (backlog 0c8b39b67665). Measured on trunk before this file existed:
# `grep -rn 'first act\|empty commit' bin/ scripts/ commands/ skills/ templates/` found the phrase
# in NO payload and NO composer. What the two fire legs actually said was:
#
#   · handoff-fire.sh (CLI leg)   a "HOW TO RETURN YOUR WORK … read this before you finish" block
#                                 whose push is the LAST act, not the first.
#   · cc-offload up --via api     nothing at all — `cc-notify --cloud <id> "$(cat "$pf")"` delivers
#                                 the operator's brief verbatim, so the VM was never told the branch
#                                 name, let alone when to push it.
#
# So no-ref could not discriminate never-booted from nothing-to-commit-yet, which is the one
# distinction the state function is organised around. A session working perfectly for twenty
# minutes read NOT-STARTED and invited a re-fire; §11.4's whole negative result ("what is NOT
# established: whether the VM executed at all") is that ambiguity, recorded live.
#
# ── ONE TEXT, TWO LEGS ────────────────────────────────────────────────────────────────────────
# Both legs source this. A contract stated twice is a contract that drifts, and this one already
# drifted before it was ever implemented: the CLI leg's own header records that `switch -c` existed
# ONLY in a prose line of CLOUD_OBSERVABILITY.md for as long as the payload got it wrong.
#
# ── THE BOOT MARKER IS A HEARTBEAT, AND THE LOCAL SIDE MUST KNOW THAT ─────────────────────────
# 🚨 Making the first push mandatory moves a real hazard from "cannot see it" to "sees it too
# early", and the second is worse. scripts/cloud-return.sh calls a session finished on a
# CONJUNCTION whose only load-bearing term is "the pushed sha has been quiet for 180 s" — because
# `worker_status: idle` is measured to be the between-turns state as much as the finished state
# (CLOUD_OBSERVABILITY.md §13.6, two live sessions 14 hours and 4 minutes old both reading idle).
# A boot push at T+30 s followed by three minutes of ordinary thinking satisfies that conjunction
# exactly, so without a discriminator the contract would convert "never returns" into "returns
# immediately, empty, and cuts a live session off" — a false completion, which this stack ranks as
# strictly worse than a stranded one.
#
# `cc_cloud_boot_only` is that discriminator, and it is CONJUNCTIVE for the same reason the
# completion test is. A range counts as boot-only when BOTH hold:
#   · it changes no file at all  — the fact that actually matters: there is nothing to land, and
#                                  landing it would put an empty commit on trunk.
#   · every commit carries the token — so the skip is attributable to OUR contract and can never
#                                  swallow a range some other producer wrote.
# Either half alone would over-reach. The file test alone would silently re-classify any empty
# range this repo has ever landed; the token alone would trust a message over a tree.
#
# THE TOKEN IS IN THE SUBJECT, NOT A TRAILER. scripts/cloud-reconcile.sh re-authors every cloud
# commit and, on a commit-msg refusal, DROPS the inherited trailer block wholesale (§13.5) — a
# trailer is exactly the part of a message this stack already reserves the right to delete. A
# subject survives the rewrite byte-for-byte.

# The token. One spelling, referenced by both the payload and the detector, so a change to it
# cannot leave the two disagreeing.
cc_cloud_boot_token() { printf '%s' 'cc-cloud-boot'; }

# Conventional Commits, lowercase after the type — githooks/commit-msg is installed in this repo
# and the VM's clone may well have it on core.hooksPath. A boot commit that the repo's own hook
# refuses would strand the session at its first instruction.
cc_cloud_boot_commit_message() { printf 'chore(cloud): boot marker [%s]' "$(cc_cloud_boot_token)"; }

# The payload block. Emitted on stdout; the caller concatenates it after the operator's brief.
cc_cloud_return_block() {  # <branch>
  local branch="${1:?cc_cloud_return_block: a branch is required}"
  cat <<EOF

── HOW TO RETURN YOUR WORK (this session runs off-box; read this FIRST, before anything else) ──
You are running in an Anthropic-managed VM. Nothing on the operator's machine can see your
filesystem, your processes or your terminal, and you cannot run this repo's /ship. Your ONLY
channel back is a git push, and it must go to exactly this branch:

    $branch

That name was assigned by the firing side and is already declared as the one ref watched for your
progress. A push anywhere else is invisible and your work will strand.

🚨 YOUR FIRST ACT IS TO PUT THAT BRANCH ON THE REMOTE — before you read the repo, before you plan,
before the first edit. Run exactly this, now:

    git switch -c $branch
    git commit --allow-empty -m "$(cc_cloud_boot_commit_message)"
    git push -u origin HEAD

WHY THE ORDER IS THE POINT, and it is not ceremony. The firing side has no inbound channel to this
VM: it cannot ask you anything. A branch that is absent from the remote is indistinguishable from a
session that never booted, one that died at boot, and one that was refused entitlement — all four
read as "no ref". That first push is the only evidence that you exist. Without it a session working
perfectly for twenty minutes is reported NOT-STARTED and re-fired, and a session that genuinely
never booted is indistinguishable from you. The commit is empty ON PURPOSE: it carries no work, it
is a heartbeat, and the local side knows to treat it as one and will not mistake it for a result.

Then do the work and push it to that SAME branch as you go:

    git push

Push whatever you have before you finish, even if the work is incomplete; an unpushed cloud session
leaves no trace of any kind. A local reconciler (scripts/cloud-reconcile.sh) discovers the branch,
re-authors it and lands it.
EOF
}

# 0 = the range <trunk>..<ref> is the boot marker and nothing else · 1 = it carries work ·
# 2 = cannot tell (no repo, no merge-base, git could not answer). 2 is never read as 0 by any
# caller: an unmeasurable range is not an empty one.
cc_cloud_boot_only() {  # <repo> <trunk-ref> <ref>
  local repo="${1:-}" trunk="${2:-}" ref="${3:-}" git_bin="${GIT_BIN:-git}"
  local base subjects tok n_all n_tok
  [ -n "$repo" ] && [ -d "$repo" ] || return 2
  [ -n "$trunk" ] && [ -n "$ref" ] || return 2
  base="$("$git_bin" -C "$repo" merge-base "$trunk" "$ref" 2>/dev/null)" || return 2
  [ -n "$base" ] || return 2

  # THE TREE TEST FIRST, because it is the one that decides whether landing this would put an empty
  # commit on trunk. Deletions count as changes (no --diff-filter here): a range that only deletes
  # is real work, and reading it as boot-only would strand it.
  local changed
  changed="$("$git_bin" -C "$repo" diff --name-only "$base..$ref" 2>/dev/null)" || return 2
  [ -z "$changed" ] || return 1

  subjects="$("$git_bin" -C "$repo" log --format=%s "$base..$ref" 2>/dev/null)" || return 2
  # An EMPTY range is not boot-only — it is nothing at all, and the lander's own "nothing to land"
  # is the honest report of it. Manufacturing a boot-only verdict here would rename a pre-existing
  # state after this contract.
  [ -n "$subjects" ] || return 1

  tok="$(cc_cloud_boot_token)"
  n_all="$(printf '%s\n' "$subjects" | grep -c .)"
  n_tok="$(printf '%s\n' "$subjects" | grep -cF "$tok")"
  [ "$n_all" = "$n_tok" ] || return 1
  return 0
}
