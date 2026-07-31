#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# 25-telemetry-perms  —  sync the copy-deployed statusline writer so the telemetry dir is minted 0700
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# WHAT: copies the landed repo `statusline.sh` over `~/.claude/statusline.sh`, then tightens the
#   existing telemetry dir to 0700. Idempotent; re-running is a no-op once both are in place.
#
# WHY: codex-security 2026-07-29 finding 2 (CWE-377/CWE-59). `/tmp/cc-telemetry` was mode 0755
#   inside mode-1777 /tmp, holding one `<session-uuid>.json` per live session with its cwd, model
#   and pid. Any local uid could enumerate every live session id — and that enumeration is exactly
#   what made the generated launcher names predictable, which was the finding's whole mechanism.
#   The producers now mint via mktemp, so the names are no longer derivable; this closes the leak
#   itself. The repo writer now creates the dir 0700, but only AT CREATE time (it runs on every TUI
#   redraw — an unconditional chmod would add a fork per render), so an already-existing 0755 dir
#   needs the one-off chmod below.
#
# WHY C10 / why this is not just a land: `~/.claude/statusline.sh` is NOT a symlink into the
#   checkout — install.sh:415 COPY-deploys it (verified: live == repo before this change). Landing
#   the repo copy therefore changes nothing any running session reads. Every telemetry READER
#   (bin/cc-context, cc-board, cc-value, cc-ctx-audit, hooks/waiting-recycle.sh,
#   hooks/boundary-handoff.sh, scripts/lead-supervisor.sh) IS a symlink and goes live on the trunk
#   fast-forward. That asymmetry is also precisely why the finding's suggested PATH move was NOT
#   taken — see the landing commit; mode, not location, is what closes "world-readable" here.
#
# NOT DONE BY THIS SCRIPT (deliberate): the telemetry directory is NOT relocated. Three measured
#   blockers, recorded so a future session does not re-litigate them from scratch:
#     1. bin/cc-ctx-audit keys on CC_CTX_TELEMETRY_DIR, every other consumer on CC_TELEMETRY_DIR —
#        changing the default moves 7 of 8 sites and silently strands the 8th.
#     2. /tmp's reboot-wipe is the ONLY bound on lead-supervisor's DEAD-page population (gc_stale
#        explicitly refuses to reap stranded-dead rows), so a durable dir turns a bounded page into
#        a permanent re-firing one.
#     3. scripts/telemetry-e2e.sh already fails today — it exports a sandbox seam then asserts
#        against the hardcoded literal — so any move is gated behind fixing that first.
#
# UNDO: cp the prior statusline.sh back from the timestamped backup this script writes.
# Mark done:  touch <this file>.done
# ───────────────────────────────────────────────────────────────────────────────────────────────────
set -uo pipefail
REPO="${CC_REPO:-$HOME/Development/claude-infrastructure}"
LIVE="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/statusline.sh"
SRC="$REPO/statusline.sh"
TDIR="${CC_TELEMETRY_DIR:-/tmp/cc-telemetry}"
STAMP="$(date +%Y%m%dT%H%M%S)"
BACKUP="$HOME/.claude/backups/statusline.sh.$STAMP"

[ -f "$SRC" ] || { echo "✗ missing $SRC — land the fix first" >&2; exit 1; }

# The repo copy must already carry the hardening, else this deploys a no-op and reports success.
# The single quotes are deliberate: `$TDIR` is a LITERAL to match in the writer's source, not a
# variable to expand here. (SC2016 reads this as an accident; it is the intent.)
# shellcheck disable=SC2016
grep -q 'chmod 700 "\$TDIR"' "$SRC" || {
  echo "✗ $SRC does not carry the 0700 mint — is the fix landed on this checkout?" >&2; exit 1; }

if [ -f "$LIVE" ] && cmp -s "$SRC" "$LIVE"; then
  echo "= statusline.sh already in sync (no copy needed)"
else
  mkdir -p "$(dirname "$BACKUP")"
  [ -f "$LIVE" ] && { cp -p "$LIVE" "$BACKUP" && echo "  prior copy saved → $BACKUP"; }
  cp "$SRC" "$LIVE" && echo "✓ statusline.sh synced → $LIVE"
fi

# One-off: an ALREADY-EXISTING dir keeps its old mode, because the writer only chmods at create.
if [ -d "$TDIR" ]; then
  if [ -O "$TDIR" ]; then
    chmod 700 "$TDIR" && echo "✓ $TDIR → $(stat -f '%Sp' "$TDIR")"
  else
    echo "✗ $TDIR is not owned by this uid — investigate before trusting it" >&2; exit 1
  fi
else
  echo "= $TDIR absent (next render mints it 0700)"
fi

# Verify: mode is 0700 and the rows are no longer world-readable.
if [ -d "$TDIR" ]; then
  mode="$(stat -f '%Lp' "$TDIR")"
  [ "$mode" = "700" ] && echo "✓ verified: telemetry dir mode $mode" \
                      || { echo "✗ telemetry dir mode is $mode, expected 700" >&2; exit 1; }
fi
echo "→ done. Mark it: touch \"$0.done\""
