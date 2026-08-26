#!/usr/bin/env bash
# cloud-brief.sh — THE off-box trailer that every cloud brief carries. Sourced, never executed.
#
#   cc_cloud_brief_trailer  <branch>            → the trailer, on stdout
#   cc_cloud_brief_payload  <branch> <brief>    → <brief>, a blank line, then the trailer
#
# ── WHY THIS FILE EXISTS ──────────────────────────────────────────────────────────────────────
# CLOUD_OBSERVABILITY.md §4.1 is the load-bearing sentence of the whole design:
#
#     "A declared cloud session that has pushed nothing is indistinguishable from one that never
#      started, one that died at boot, and one that was refused entitlement. All four read as 'no
#      ref'. There is no inbound channel to a cloud VM, so this cannot be resolved by asking. It
#      can only be resolved by CONTRACT: the fire declares a branch and a boot budget, and the
#      session's brief requires its FIRST act to be pushing that branch — an empty commit is
#      enough."
#
# That contract was PROSE ONLY (backlog `0c8b39b67665`). Measured 2026-08-26 on trunk:
#
#   * `grep -rn 'allow-empty' bin/ scripts/ commands/ hooks/` returned six hits and not one of them
#     was on a fire path — three are `cc-value` fixtures, two are `telemetry-e2e.sh` fixtures, one
#     is `cc-cloud`'s own selftest seed.
#   * `scripts/handoff-fire.sh`'s CLI-lane payload (the `HOW TO RETURN YOUR WORK` block) instructed
#     `git switch -c` + `git push`, but as the RETURN channel — "Push whatever you have before you
#     finish". A push at the END is not a boot beacon; it is the deliverable.
#   * `bin/cc-offload`'s API lane — the DEFAULT lane (`cmd_up`'s `via="${CC_OFFLOAD_VIA:-api}"`)
#     — delivered `cc-notify --cloud "$sid" "$(cat "$pf")"`, i.e. the operator's brief VERBATIM,
#     with no trailer of any kind. That lane carried neither the contract nor the return channel.
#
# So `C1 NOT-STARTED` — the one arm of §4.3 whose whole meaning is "this session never booted" —
# was computed over sessions that had never been told to produce the evidence it reads. A healthy
# VM that had simply not committed anything yet was indistinguishable from a VM that never
# existed, and the C1 row's recover action is "re-fire" — so the failure mode was re-firing
# underneath a live session and spending an account's quota twice.
#
# ── ONE COMPOSER, NOT TWO ─────────────────────────────────────────────────────────────────────
# The two lanes reach the VM by different routes (CLI create carries the payload in argv; the API
# create authorises the branch in `outcomes.git_info.branches` and delivers the brief afterwards
# over `cc-notify --cloud`), and the trailer is the ONE thing that must be byte-identical on both:
# §4.3's state function is a single function over a single declaration store, so a lane whose
# trailer differs is a lane whose C1 verdict means something different, and no consumer can tell
# which. This file is the same factoring `scripts/lib/cloud-create.sh` is, for the same reason
# CLOUD_OBSERVABILITY.md §10.4 gave: written once, or it drifts.
#
# ── WHY THE BEACON IS RE-RUN-SAFE ─────────────────────────────────────────────────────────────
# `git switch -c <b>` fails outright when `<b>` already exists, and on the API lane it often DOES:
# `scripts/cloud-create-api.py` sets `reuse_outcome_branches: true` and names the branch at create,
# so the VM can legitimately start already on it. A bare `switch -c` there aborts the beacon at its
# first line and the session proceeds with no beacon at all — the exact silence this contract
# exists to remove. The `|| git switch` fallback is therefore not defensive style; it is what makes
# the instruction executable on both lanes.

# The literal the trailer is recognised by. Both the fire paths and tests/cloud-brief.bats assert
# on THIS, so a trailer that silently stopped carrying the contract is a red test rather than a
# quiet regression six weeks later.
CC_CLOUD_BEACON_MARK='YOUR FIRST ACT'

cc_cloud_brief_trailer() { # $1=branch → the trailer on stdout
  local b="${1:-}"
  [ -n "$b" ] || { echo "cc_cloud_brief_trailer: a branch is REQUIRED (a trailer naming no branch instructs a push to nowhere)" >&2; return 2; }
  case "$b" in *[[:space:]]*) echo "cc_cloud_brief_trailer: whitespace in branch '$b'" >&2; return 2 ;; esac

  cat <<TRAILER
── HOW TO RETURN YOUR WORK (this session runs off-box; read this BEFORE you start) ──
You are running in an Anthropic-managed VM. Nothing on the operator's machine can see your
filesystem, your processes or your terminal, and you cannot run this repo's /ship. Your ONLY
channel back is a git push, and it must go to exactly this branch:

    $b

🚨 ${CC_CLOUD_BEACON_MARK} — before you read a file, before you plan, before any work:

    git switch -c $b 2>/dev/null || git switch $b
    git commit --allow-empty -m 'boot: $b'
    git push -u origin HEAD

That empty commit is a BOOT BEACON, not a deliverable, and pushing it is the first thing you do.
The firing side watches this branch and nothing else. Until it appears, "no ref on that branch" is
indistinguishable from a VM that never started, one that died at boot, and one that was refused
entitlement — so a healthy session that has simply not committed anything yet gets reported as
NOT-STARTED, and the recovery for that verdict is to re-fire, on top of you. The beacon is what
makes your silence afterwards mean "still working" rather than "never booted". Run it even if you
believe you are already on that branch; all three lines above are safe to re-run.

Then do the work, and push again whenever you have something — at minimum once before you finish,
even if the work is incomplete. An unpushed cloud session leaves no trace of any kind: the
container is reclaimed and nothing on the operator's machine ever saw it. A local reconciler
(scripts/cloud-reconcile.sh) discovers this branch and hands it to the sanctioned local lander.
TRAILER
}

cc_cloud_brief_payload() { # $1=branch $2=brief → brief + blank line + trailer
  local b="${1:-}" brief="${2:-}" trailer
  trailer="$(cc_cloud_brief_trailer "$b")" || return $?
  printf '%s\n\n%s\n' "$brief" "$trailer"
}
