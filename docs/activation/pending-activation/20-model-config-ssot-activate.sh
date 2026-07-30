#!/usr/bin/env bash
# 20-model-config-ssot-activate.sh — swap the LIVE model-config.yaml from a real, unversioned file
# to a symlink into the checkout, completing the consolidation-audit-02 SSOT unification.
#
# WHY (backlog b13787e71c9f). Before this: `templates/model-config.yaml` claimed "Single source of
# truth" in its first line, while `~/.claude/model-config.yaml` was a separate 36 KB REAL file that
# every consumer actually read (bin/cc-route, bin/claude-accounts, bin/claude-bump-models,
# scripts/claude-lint-models.sh, scripts/route-safety-gate.sh, hooks/frontier-spawn-gate.sh,
# hooks/frontier-status.sh, scripts/effort-parity-assert.sh). The two had drifted in BOTH
# directions:
#   • live-only  — the Opus 5 activation (opus_latest/prior/staged, fallback, non_firstParty_max,
#                  lead_default, default_teammate, teammate_*, research_worker). It existed in NO
#                  committed file: one `rm` from unrecoverable.
#   • repo-only  — the 2026-07-24 settings-floor findings + the effort-parity-assert mechanism.
# 10-opus5-activate.sh was marked `.done` on 2026-07-25 while its own REMAINING step ("the live edit
# must reach trunk, else it drifts") was never performed — so it drifted for four days. Worse, that
# step's procedure was `cp ~/.claude/model-config.yaml → templates/`, which would have DESTROYED the
# repo-only prose.
#
# Both sides are now merged into ONE versioned file at the repo root (`model-config.yaml`, alongside
# accounts.json), with every routing value byte-identical to what the live file already served — so
# this swap changes NO model routing. install.sh links it exactly as it links accounts.json.
#
# C10 — an agent stages this, the OPERATOR runs it: it mutates the live ~/.claude layer.
# Idempotent. Fail-closed: it refuses unless the repo file is present AND its routing values match
# the live file's, and it always leaves a timestamped backup of the real file it replaces.

set -uo pipefail

REPO="${CC_SHARED_CHECKOUT:-$HOME/Development/claude-infrastructure}"
CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SRC="$REPO/model-config.yaml"
DST="$CFG/model-config.yaml"
BAK="$DST.prelink-bak.$(date -u +%Y%m%dT%H%M%SZ)"

die() { printf '✗ %s\n' "$1" >&2; exit 1; }

printf '→ model-config SSOT activation\n  repo: %s\n  live: %s\n' "$SRC" "$DST"

[ -f "$SRC" ] || die "repo SSOT missing: $SRC — land the consolidation commit first (git pull in $REPO)."

# Already a symlink to the right place? Nothing to do.
if [ -L "$DST" ]; then
  cur="$(readlink "$DST" 2>/dev/null || true)"
  [ "$cur" = "$SRC" ] && { printf '✓ already linked → %s (no-op)\n' "$cur"; exit 0; }
  die "live path is a symlink to an UNEXPECTED target ($cur). Inspect by hand; refusing to clobber."
fi

[ -f "$DST" ] || die "live file missing entirely: $DST — nothing to migrate (run install.sh instead)."

# ── FAIL-CLOSED GUARD: every routing value the fleet depends on must already be identical, so the
#    swap cannot change how anything is routed. Compare the values, not the bytes (the repo copy
#    deliberately carries extra prose the live file lacks).
KEYS="frontier_latest frontier_prior opus_latest opus_prior opus_staged sonnet_latest sonnet_prior
      haiku_latest fallback lead_default default_teammate teammate_mechanical teammate_research
      research_worker non_firstParty_max"
val() {  # $1=file $2=key → first value, comments stripped
  grep -E "^[[:space:]]*$2:" "$1" 2>/dev/null | head -1 | sed 's/^[^:]*://; s/#.*//' \
    | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'
}
mismatch=0 compared=0
for k in $KEYS; do
  a="$(val "$SRC" "$k")"; b="$(val "$DST" "$k")"
  if [ -z "$a$b" ]; then printf '  ⚠ %s: absent from BOTH files — cannot compare\n' "$k"; mismatch=1; continue; fi
  compared=$((compared + 1))
  [ "$a" = "$b" ] || { printf '  ✗ %s: repo=[%s] live=[%s]\n' "$k" "$a" "$b"; mismatch=1; }
done
printf '  routing keys compared: %s\n' "$compared"
[ "$compared" -ge 15 ] || die "only $compared/15 routing keys were comparable — refusing (a silent
  parse failure would make this guard vacuously green)."
[ "$mismatch" -eq 0 ] || die "routing values differ between repo and live (above). Reconcile them in
  the repo file and re-run — never let this swap change routing."
printf '  ✓ all %s routing values identical — swap is routing-neutral\n' "$compared"

# ── the swap: back up the real file, then link.
cp -p "$DST" "$BAK" || die "backup failed ($BAK) — refusing to replace the live file."
printf '  ✓ backup: %s\n' "$BAK"
rm -f "$DST" || die "could not remove the live real file."
ln -s "$SRC" "$DST" || die "symlink creation failed — RESTORE NOW: cp -p '$BAK' '$DST'"

# ── verify by CONTENT, not by exit code.
[ -L "$DST" ] && [ "$(readlink "$DST")" = "$SRC" ] \
  || die "post-swap verify failed — RESTORE NOW: cp -p '$BAK' '$DST'"
grep -qE "^[[:space:]]*opus_latest:" "$DST" \
  || die "linked file is not readable as a model-config — RESTORE NOW: cp -p '$BAK' '$DST'"

printf '✓ done — %s → %s\n' "$DST" "$SRC"
printf '  live model-config.yaml is now versioned; edits land in the repo and reach trunk via /ship.\n'
printf '  Backup retained at %s (delete once you are satisfied).\n' "$BAK"
