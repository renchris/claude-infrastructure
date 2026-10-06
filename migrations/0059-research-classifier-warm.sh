#!/bin/bash
# migration-class: c10
# migration-step: the re-ask router's resident classifier (com.claude.research-classifier-warm) is built and staged but not loaded; installing and loading it is yours, and gate row 15's final reading on held-out set v2 waits for it
# migration-run: bash ~/Development/claude-infrastructure/migrations/0059-research-classifier-warm.sh
# migration-subject: ~/Library/LaunchAgents/com.claude.research-classifier-warm.plist
# migration-verify: /usr/bin/python3 ~/.claude/scripts/research-kit/classifier-warm.py ping >/dev/null 2>&1
#
# WHAT THIS LOADS (decision 4bf73c4e55d5 option 3; docs/plans/RESEARCH_PROGRAM_BUILD.md wave E1c)
# ───────────────────────────────────────────────────────────────
# One launchd job, `/bin/bash ~/.claude/scripts/research-kit/jobs/classifier-warm.sh`, which execs
# `classifier-warm.py serve`: a daemon that keeps two classifier processes started ahead of the
# prompt, so the router's label does not pay a 2-4 s cold start inside its 9 s limit. Each process
# labels one prompt and is ended. With the daemon absent, busy or failing, router.py makes the cold
# call it makes today, so loading this changes latency and nothing else; `launchctl bootout
# gui/$(id -u)/com.claude.research-classifier-warm` undoes it.
# The SSOT plist lives in launchd/staged/, outside install.sh's launchd/*.plist glob, because a copy
# into ~/Library/LaunchAgents is itself an activation at the next login (tests/install-staged-plist.bats).
# c10 because loading a plist is an operator step (migrations/README.md).
#
#   0059-research-classifier-warm.sh [--dry-run]
#
# --dry-run prints what a real run would do and touches nothing. A real run refuses until the live
# layer carries the runner and the daemon, then copies the plist into ~/Library/LaunchAgents and
# bootstraps it; a label already loaded from identical bytes is left alone, so a re-run is a no-op.
# The effect is read back by a different call than the one that made it: `classifier-warm.py ping`
# must report an ANSWERED classification, not a live process (wave E1f; incident 2026-10-05: the
# first activation read "ready 2" back from a daemon whose processes were logged out). A start is
# an account ranking, a login probe and the daemon's own first round-trip, so this waits up to 90 s.
# A job already loaded from identical bytes whose daemon is not READY is restarted once
# (`launchctl kickstart -k`), so a re-run is how the job is moved onto newly converged code; one
# that is ready is left alone and the re-run is a no-op. Not ready is `ping` exiting non-zero: no
# worker answering, or (wave E1g) a daemon that answers but still runs older code in memory, which
# `ping` tells by the daemon not serving each kind of call or by its classifier configuration
# differing from the code on disk. Until E1g a loaded daemon that answered on old code read as
# ready, and a re-run restarted nothing.
# Exit 1 when the label is not loaded or no worker answers.
set -uo pipefail

REPO="${CC_MIGRATION_REPO:-$HOME/Development/claude-infrastructure}"
LA="${CC_MIGRATION_LA_DIR:-$HOME/Library/LaunchAgents}"
RUNNER="$HOME/.claude/scripts/research-kit/jobs/classifier-warm.sh"
DAEMON="$HOME/.claude/scripts/research-kit/classifier-warm.py"
LABEL="com.claude.research-classifier-warm"
PING_TRIES="${CC_MIGRATION_PING_TRIES:-90}"

dry=0
case "${1:-}" in
  --dry-run) dry=1 ;;
  '') ;;
  *) echo "usage: 0059-research-classifier-warm.sh [--dry-run]" >&2; exit 2 ;;
esac

uid="$(id -u)"
src="$REPO/launchd/staged/$LABEL.plist"
dst="$LA/$LABEL.plist"
if [ ! -f "$src" ]; then
  echo "0059: MISSING $src — the wiring commit did not land intact; refusing" >&2
  exit 1
fi

if [ "$dry" -eq 1 ]; then
  for f in "$RUNNER" "$DAEMON"; do
    if [ -f "$f" ]; then echo "0059: live layer has $f"; else echo "0059: live layer LACKS $f — a real run would refuse"; fi
  done
  echo "0059: would install $src -> $dst and bootstrap gui/$uid/$LABEL, then wait for the daemon's ping"
  exit 0
fi

for f in "$RUNNER" "$DAEMON"; do
  if [ ! -f "$f" ]; then
    echo "0059: $f is not in the live layer yet — converge first (bash $REPO/scripts/deploy-live.sh), then re-run" >&2
    exit 1
  fi
done

mkdir -p "$LA" "$HOME/.claude/logs"
if launchctl print "gui/$uid/$LABEL" >/dev/null 2>&1 && cmp -s "$src" "$dst"; then
  echo "0059: $LABEL already loaded from the repo plist"
  if ! /usr/bin/python3 "$DAEMON" ping >/dev/null 2>&1; then
    if ! launchctl kickstart -k "gui/$uid/$LABEL"; then
      echo "0059: $LABEL is loaded but not ready, and its restart FAILED" >&2
      exit 1
    fi
    echo "0059: $LABEL was loaded but not answering on the live code; restarted on the live code"
  fi
else
  launchctl bootout "gui/$uid/$LABEL" >/dev/null 2>&1 || true   # a stale copy is replaced, not doubled
  cp "$src" "$dst"
  if ! launchctl bootstrap "gui/$uid" "$dst"; then
    echo "0059: bootstrap of $LABEL FAILED" >&2
    exit 1
  fi
  if ! launchctl print "gui/$uid/$LABEL" >/dev/null 2>&1; then
    echo "0059: $LABEL bootstrapped but launchctl print cannot see it" >&2
    exit 1
  fi
  echo "0059: $LABEL loaded"
fi

i=0
while [ "$i" -lt "$PING_TRIES" ]; do
  if out="$(/usr/bin/python3 "$DAEMON" ping 2>/dev/null)"; then
    echo "0059: the daemon answers ($out)"
    exit 0
  fi
  i=$((i + 1))
  sleep 1
done
echo "0059: $LABEL is loaded but no worker answered a classification in ${PING_TRIES} s — read $HOME/.claude/logs/research-classifier-warm.err.log" >&2
exit 1
