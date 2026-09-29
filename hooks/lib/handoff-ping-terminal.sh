# shellcheck shell=bash
# shellcheck disable=SC2034  # constants for the sourcing scripts
# THE TERMINAL HANDOFF-PING VOCABULARY — the one place it is defined.
#
# A fired peer pings its originator with `HANDOFF-PING <slug>: <status>`. It pings more than once:
# at a decision gate, on a blocker, on progress, and at the end. Only the END may discharge the
# originator's custody row (hooks/mailbox-drain.sh), because a returned row stops
# custody-deathwatch.sh watching the peer and lets the lead's close certificate turn green.
# Measured 2026-09-28: a "step 0 part 1 DONE" progress ping returned custody ~2 h before the peer
# finished (docs/plans/CUSTODY_TERMINAL_PING.md).
#
# THE RULE: the status's FIRST whole token, case-insensitive, is one of the words below. A token
# ends at the first character outside [A-Za-z0-9+_-], so `LANDED-UNVERIFIED` (cloud-return.sh's
# unverified wake, on which it deliberately leaves custody open) and `DONE-ish` do not match, and
# a DONE later in the line ("step 0 part 1 DONE") is not the first token.
#
# CONSUMERS: hooks/mailbox-drain.sh (the discharger, in awk — no extra fork per line) and
# scripts/handoff-fire.sh (the back-channel trailer, which prints HANDOFF_PING_TERMINAL_HINT so the
# peer is told the exact final form). An off-vocabulary final ping under-discharges, which is the
# safe direction: self-close still returns by marker and the lead can `cc-custody return`.

# Space-separated, UPPER case; consumers compare against toupper(token).
HANDOFF_PING_TERMINAL_WORDS="DONE LANDED LANDED+VERIFIED CLOSED COMPLETE COMPLETED"
# What the trailer tells the peer. Keep the first word in HANDOFF_PING_TERMINAL_WORDS.
HANDOFF_PING_TERMINAL_HINT="DONE"
