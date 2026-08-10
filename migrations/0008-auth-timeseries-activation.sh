#!/bin/bash
# migration-class: c10
# migration-step: the per-account auth recorder is built + wired but NOT armed — arming it loads a LaunchAgent and needs one hand-run keychain-ACL check from a non-tty context, which only you can do
# migration-run: CONFIRM=1 bash ~/Development/claude-infrastructure/docs/activation/pending-activation/35-auth-timeseries-activate.sh
# migration-subject: ~/Library/LaunchAgents/com.claude.auth-timeseries.plist
# migration-verify: launchctl list 2>/dev/null | grep -q com.claude.auth-timeseries
#
# WHY THIS IS A MIGRATION AND NOT JUST A PENDING-ACTIVATION SCRIPT
# ─────────────────────────────────────────────────────────────────────────────────────────────
# A pending-activation script is inert until somebody remembers it exists. There are 6 un-run
# entries in that queue right now, 4 of them rotting past 24h — that queue is a place things go
# to be forgotten, which is the precise failure this whole item (MASTER M6, backlog b22e519e06cb)
# is about: a conclusion that reaches no enforcing store changes nothing. A migration is read by
# scripts/deploy-migrations.sh on every 600 s converge, and a `c10` migration files its operator
# step into cc-backlog, where wrap-ledger.sh counts it into the close protocol's 👤 rung. So the
# ask surfaces at every close until it is done, instead of waiting to be rediscovered.
#
# WHY c10 AND NOT mechanical
# ─────────────────────────────────────────────────────────────────────────────────────────────
# It arms a LaunchAgent. migrations/README.md is explicit that a migration touching a launchd
# plist declares c10 and waits for a human, and tests/deploy-migrations.bats test 5 fails a
# `mechanical` that touches a C10 surface. Beyond the rule there is a real reason here: the one
# thing that cannot be verified by any agent is whether `/usr/bin/security` is trusted by the
# keychain items' ACL when there is no interactive session to answer an "allow access" dialog.
# A denial would render as a clean run of NO_ITEM rows — a FALSE "the credential is gone" on
# every account at once, which is exactly the signal this instrument exists to detect. That
# check has to be a hand-run from a non-tty context, and the operator owns it.
#
# WHAT IS ALREADY DONE (nothing below re-does it — this migration only ASSERTS and FILES)
#   * tools/auth/auth-timeseries.sh grew --once and a durable-store seam (AUTH_TS_OUT).
#   * launchd/com.claude.auth-timeseries.plist exists, StartInterval 300, RunAtLoad false.
#   * launchd/fleet.manifest declares it `staged`, so install.sh copies it and deliberately does
#     NOT activate it — cc-fleet emits exactly one UNDECIDED row rather than a fault.
#   * The store is registered in BOTH rotation mechanisms (rotate-autonomy-logs.sh
#     DEFAULT_TARGETS and config/store-bounds.manifest).
#
# THE BLOCKER, PRECISELY: `tools/` is not part of the deployed layer — there is no ~/.claude/tools
# and no ~/.claude/scripts/auth-timeseries.sh. The live layer is reached by PER-FILE symlinks, so
# a newly ADDED file has no link and is absent from every path the box can reach. The plist's
# ProgramArguments points at ~/.claude/scripts/auth-timeseries.sh, and 35-auth-timeseries-activate.sh
# is what creates that symlink. Arming the label without it yields a job that fails every tick.
#
# PRECONDITION RE-DERIVED AT CONSUMPTION, not at authoring (memory
# discovery-critic-premise-goes-stale): a landed sibling may have deployed tools/ or armed the
# label since this was written, and a migration that asserts a stale premise re-files a step that
# is already done. Step 2 therefore reads the live state, and this migration exits 0 — applied,
# nothing to do — when it finds the job already armed.

set -uo pipefail

REPO="${CC_MIGRATION_REPO:-$HOME/Development/claude-infrastructure}"
CLAUDE_DIR="${CC_CLAUDE_DIR:-$HOME/.claude}"
LABEL="com.claude.auth-timeseries"
PLIST="$REPO/launchd/$LABEL.plist"
ACTIVATE="$REPO/docs/activation/pending-activation/35-auth-timeseries-activate.sh"

# ---- step 1: the artifacts this migration presupposes must actually exist -----------------------
for f in "$PLIST" "$ACTIVATE" "$REPO/tools/auth/auth-timeseries.sh"; do
  if [ ! -f "$f" ]; then
    echo "0008: MISSING $f — the wiring commit did not land intact; refusing to file a step for it" >&2
    exit 1
  fi
done

if ! grep -q "^${LABEL}[[:space:]]*|" "$REPO/launchd/fleet.manifest" 2>/dev/null; then
  echo "0008: $LABEL is not declared in launchd/fleet.manifest — install.sh would print it as" >&2
  echo "      UNDECLARED and never activate it. Declare it before filing an activation step." >&2
  exit 1
fi

# ---- step 2: is it already armed? then this migration is a no-op ---------------------------------
if launchctl print "gui/$(id -u)/$LABEL" >/dev/null 2>&1; then
  echo "0008: $LABEL is already loaded — nothing to file, recording as applied"
  exit 0
fi

# The other half of the same question: the symlink the plist depends on. If a sibling deployed
# tools/ wholesale, the operator's remaining work is smaller but not zero (the ACL check stands),
# so this only reports — it does not shrink the step.
if [ -e "$CLAUDE_DIR/scripts/auth-timeseries.sh" ]; then
  echo "0008: note — $CLAUDE_DIR/scripts/auth-timeseries.sh already present (a sibling deployed it)"
else
  echo "0008: $CLAUDE_DIR/scripts/auth-timeseries.sh absent — the activation script must create it"
fi

# ---- step 3: hand it to the operator -------------------------------------------------------------
# The runner reads `# migration-step:` / `# migration-run:` above and files the cc-backlog item
# itself; a c10 body is never executed by deploy-migrations.sh, so reaching here at all means
# somebody ran this file by hand. Say what they should run instead of doing it for them.
echo
echo "0008: $LABEL is BUILT, WIRED and NOT ARMED. It is a c10 — arming is yours."
echo "      Run:  CONFIRM=1 bash $ACTIVATE"
echo "      That script hand-runs one --once batch from a non-tty context FIRST and refuses to"
echo "      arm on anything but OK rows, because a keychain ACL denial under launchd would look"
echo "      exactly like every account having lost its credential."
exit 0
