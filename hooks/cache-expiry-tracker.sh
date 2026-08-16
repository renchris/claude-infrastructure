#!/bin/bash
# Stop Hook — Cache Expiry Tracker
# Records timestamp after every Claude response so the UserPromptSubmit
# hook can detect idle gaps that exceed the prompt cache TTL — ~1 hour on a Claude
# subscription, NOT the 5 minutes this comment used to claim (see the corrected
# cache-expiry-warning.sh header and USAGE_TELEMETRY_100P §2.4 for the measurement).

date +%s > "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.last-interaction"
exit 0
