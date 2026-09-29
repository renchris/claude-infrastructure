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
# launchd runs this through the ~/.claude/scripts/ symlink, where an unresolved dirname/.. is
# ~/.claude — not a git repo — so cc.publicRepo read empty and every tick REFUSED. Resolve every
# hop first (loop from scripts/ship-land.sh `_resolve_self`; no `readlink -f`, this box is BSD).
_self="${BASH_SOURCE[0]}"
while [ -L "$_self" ]; do
  _d="$(cd "$(dirname "$_self")" && pwd)"
  _self="$(readlink "$_self")"
  case "$_self" in /*) ;; *) _self="$_d/$_self" ;; esac
done
SELF_DIR="$(cd "$(dirname "$_self")" && pwd)"
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
# No lock of its own: launchd never runs two instances of one label, so a tick-only lock protected
# nothing, while the race that mattered (a tick beside a MANUAL publish) went through it. The one
# lock is inside public-publish.sh, shared by every --push caller.
#
# The publisher runs in its OWN process group (job control on), and a TERM/INT to the tick is
# forwarded to that whole group, then waited for. Without this a TERM'd tick exits alone and leaves
# git-filter-repo running, orphaned, still holding the publish lock for a live pid.
echo "$(ts) public-publish-tick: publishing $REPO main → $SLUG"
set -m
bash "$SELF_DIR/public-publish.sh" --src "$REPO" --ref main \
  --public-url "https://github.com/$SLUG.git" --push --confirm "$SLUG" &
pub=$!
set +m
trap 'kill -TERM -- "-$pub" 2>/dev/null' TERM INT
wait "$pub"; rc=$?
# A trapped signal interrupts `wait` early; keep waiting until the publisher has actually exited so
# its cleanup (build dir, lock) runs first and its real exit status is the one reported.
while kill -0 "$pub" 2>/dev/null; do wait "$pub"; rc=$?; done
echo "$(ts) public-publish-tick: rc=$rc"
exit "$rc"
