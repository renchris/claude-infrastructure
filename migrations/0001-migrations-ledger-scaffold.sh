#!/bin/bash
# migration-class: mechanical
# migration-verify: for d in applied failed staged superseded; do [ -d "${CC_MIGRATION_STATE:-$HOME/.claude/autonomy/migrations}/$d" ] || exit 1; done
# migration-conflict: for d in applied failed staged superseded; do p="${CC_MIGRATION_STATE:-$HOME/.claude/autonomy/migrations}/$d"; if [ -e "$p" ] && [ ! -d "$p" ]; then exit 0; fi; done; exit 1
#
# 0001 — create the migration ledger's own directories, and prove the mechanical path end to end.
#
# THE ORACLE (added 2026-08-11). A `mechanical` migration is not exempt from declaring one. Without
# it scripts/registration-state.sh reports 0001 `unverifiable` — and this one is `applied` in the
# ledger, so the unanswerable question is the sharpest form of the question that check exists to
# ask: the ledger asserts the round trip completed, and nothing could confirm the four directories
# it asserts about are there. That is the `not-delivered` shape (ledger=applied, effect absent), and
# the state most worth being able to see, since the runner scaffolds defensively and would mask a
# lost ledger on the NEXT converge rather than at the one that lost it.
#
# WHY THE VERIFIER SPELLS THE PATH THE WAY THE BODY DOES, not the way registration-state.sh does.
# That script derives its own STATE as `${CC_MIGRATION_STATE:-${CC_CLAUDE_DIR:-$HOME/.claude}/…}`
# and re-runs each declared verifier once per config dir with CC_CLAUDE_DIR re-aimed. This ledger is
# NOT per-config-dir — there is one, under $HOME/.claude, exactly as line 19 below resolves it — so
# a CC_CLAUDE_DIR-aware spelling would look for four ledgers that were never meant to exist and
# report `partial` forever. Mirroring the body keeps one derivation of one fact; CC_MIGRATION_STATE
# is still honoured, which is what keeps the suite's fixture hermetic.
#
# WHY A CONFLICT ORACLE HERE, where the effect is only a directory. Because a wrong value at this
# key is possible and is silent: a plain FILE at `staged/` (a stray redirect, a restored backup)
# leaves `mkdir -p` failing and every ledger write for that state landing nowhere. Without the
# conflict arm that reads `not-delivered` — "nothing registered it" — and sends a reader looking for
# a converge that never ran, instead of at the one path that is the wrong type.
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
