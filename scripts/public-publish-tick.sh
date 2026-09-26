#!/usr/bin/env bash
# public-publish-tick.sh — the recurring half of the public projection (launchd:
# com.claude.public-publish, declared `staged` in launchd/fleet.manifest until the cutover).
#
# INERT UNTIL THE CUTOVER. It publishes only when $CC_PRIVATE_DIR/public-projection/publish-enabled
# exists, which scripts/public-cutover.sh writes after the operator has renamed the working repo to
# a private origin and created the public repo. Before that, the public URL still serves the
# unredacted working history, and a push there would be refused anyway (not a fast-forward).
#
# Each tick re-projects this checkout's deployed `main` and pushes ONLY a fast-forward
# (scripts/public-publish.sh refuses anything else without an explicit --rebaseline, which this
# tick never passes). A rule-set change therefore stops publishing and says so every tick, until
# the operator re-baselines by hand. Exit: 0 always for "nothing to do"; the publisher's own rc
# otherwise, so a verifier failure surfaces in the fleet's evidence log.
set -uo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SELF_DIR/.." && pwd)"
PRIV="${CC_PRIVATE_DIR:-$HOME/Development/claude-private}"
MARK="$PRIV/public-projection/publish-enabled"
ts() { date -u +%Y-%m-%dT%H:%M:%SZ; }

if [ ! -f "$MARK" ]; then
  echo "$(ts) public-publish-tick: disabled (no $MARK — the cutover has not run)"
  exit 0
fi
SLUG="$(git -C "$REPO" config --get cc.publicRepo 2>/dev/null || true)"
if [ -z "$SLUG" ]; then
  echo "$(ts) public-publish-tick: REFUSED — publish-enabled is set but git config cc.publicRepo is empty"
  exit 1
fi
LOCK="${TMPDIR:-/tmp}/public-publish-tick.lock"
if ! mkdir "$LOCK" 2>/dev/null; then
  echo "$(ts) public-publish-tick: a previous tick still holds $LOCK — skipping"
  exit 0
fi
trap 'rmdir "$LOCK" 2>/dev/null' EXIT
echo "$(ts) public-publish-tick: publishing $REPO main → $SLUG"
bash "$SELF_DIR/public-publish.sh" --src "$REPO" --ref main \
  --public-url "https://github.com/$SLUG.git" --push --confirm "$SLUG"
rc=$?
echo "$(ts) public-publish-tick: rc=$rc"
exit "$rc"
