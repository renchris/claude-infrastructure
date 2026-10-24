#!/bin/bash
# Stop Hook — Cache Expiry Tracker
# Records timestamp after every Claude response so the UserPromptSubmit
# hook can detect idle gaps that exceed the prompt cache TTL — ~1 hour on a Claude
# subscription, NOT the 5 minutes this comment used to claim (see the corrected
# cache-expiry-warning.sh header and USAGE_TELEMETRY_100P §2.4 for the measurement).

#
# It also feeds the idle-gap ledger behind the log-only cache keepalive (docs/plans/USAGE_LEVERS.md
# § W3, hooks/lib/idle_gap.py): this Stop closes the session's previous idle gap and opens the next.
# The ledger is a passenger here because this hook is already registered on every account; it is
# bounded (4 s alarm inside the 5 s hook timeout), writes nothing to stdout, and cannot fail the hook.
# Off switch: CC_IDLE_KEEPALIVE=off.

date +%s > "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.last-interaction"
_ig="${BASH_SOURCE[0]%/*}/lib/idle_gap.py"
if [ "${CC_IDLE_KEEPALIVE:-shadow}" != off ] && [ -f "$_ig" ]; then
  /usr/bin/env python3 -I "$_ig" stop >/dev/null 2>&1 || true
fi
exit 0
