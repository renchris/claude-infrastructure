#!/bin/bash
# migration-class: mechanical
#
# 0001 — create the migration ledger's own directories, and prove the mechanical path end to end.
#
# WHY THIS IS A MIGRATION AND NOT A `mkdir -p` IN THE RUNNER: it is, in the runner, too — the runner
# scaffolds defensively before it writes. This migration exists so the FIRST real converge exercises
# the whole mechanical round trip (discover → class-check → run → ledger applied → never re-run)
# against something that cannot break anything. A mechanism whose happy path has never executed on
# the real box is indistinguishable from one that does not work; that is the class this whole
# directory exists to leave.
#
# It also creates `superseded/`, which the materialise phase writes overwrite backups into. That one
# is load-bearing rather than cosmetic: without it the first CONTENT-DRIFT refresh silently loses the
# operator's prior copy, and the reversibility that makes repo-authoritative safe is the whole reason
# the phase is allowed to overwrite at all.
set -uo pipefail

STATE="${CC_MIGRATION_STATE:-$HOME/.claude/autonomy/migrations}"

for d in applied failed staged superseded; do
  mkdir -p "$STATE/$d" || { printf '0001: cannot create %s/%s\n' "$STATE" "$d" >&2; exit 1; }
done

# Idempotent by construction: `mkdir -p` on an existing directory is a no-op, so a second run after a
# lost ledger is safe. Report only what a reader could not already infer.
printf '0001: migration ledger scaffolded at %s (applied/ failed/ staged/ superseded/)\n' "$STATE"
