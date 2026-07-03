#!/bin/bash
# Stop Hook — Cache Expiry Tracker
# Records timestamp after every Claude response so the UserPromptSubmit
# hook can detect idle gaps that exceed the 5-minute prompt cache TTL.

date +%s > "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.last-interaction"
exit 0
