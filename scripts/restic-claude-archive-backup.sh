#!/bin/bash
# Phase B Item 3 — weekly restic snapshot of ~/.claude/archives/claude-code/
# to a Backblaze B2 bucket (zero-knowledge encrypted via restic).
#
# Credentials retrieved from macOS Keychain (4 entries):
#   restic-b2-keyid      — B2 application keyID
#   restic-b2-appkey     — B2 applicationKey
#   restic-b2-bucket     — B2 bucket name
#   restic-password      — restic encryption password (LOSS = unrecoverable archive)
#
# Retention: keep-daily 7, keep-weekly 4, keep-monthly 12, keep-yearly 5.
# Excludes: *.bak (backup-before-write artifacts), *.unsigned.sha256 (ad-hoc resign metadata).
# Log: ~/.claude/logs/restic-backup.log
#
# Schedule: launchd com.chrisren.restic-claude-archive (Saturday 02:00).
# Manual: bash ~/.claude/scripts/restic-claude-archive-backup.sh

set -euo pipefail

# Bound the OS-notification fork (machine-wide iTerm2/AppleEvent wedge, 2026-07-26). This one
# targets NotificationCenter rather than iTerm2, so it is not the root cause — but it is an
# AppleEvent fork inside an automated path, and an unbounded one turns a best-effort page into a
# stalled job. Every call site here is already best-effort (`|| true`), so a cut costs at most
# one missed notification and never a wrong verdict. timeout(1) is resolved by ABSOLUTE PATH as
# well as PATH — hooks and launchd jobs run without Homebrew on PATH, where coreutils installs it.
# No timeout(1) ⇒ run unbounded rather than lose notifications entirely.
# Seams: RCB_OSA_TIMEOUT_S · RCB_OSA_TIMEOUT_BIN (set-but-EMPTY disables verbatim).
RCB_OSA_TIMEOUT_S="${RCB_OSA_TIMEOUT_S:-5}"
if [ -n "${RCB_OSA_TIMEOUT_BIN+set}" ]; then
  RCB_OSA_TB="${RCB_OSA_TIMEOUT_BIN}"
else
  RCB_OSA_TB=""
  for _c in "$(command -v timeout 2>/dev/null || true)" "$(command -v gtimeout 2>/dev/null || true)" \
            /opt/homebrew/bin/timeout /usr/local/bin/timeout \
            /opt/homebrew/bin/gtimeout /usr/local/bin/gtimeout; do
    [ -n "$_c" ] && [ -x "$_c" ] && { RCB_OSA_TB="$_c"; break; }
  done
fi
rcb_osa() {
  if [ -z "$RCB_OSA_TB" ] || [ ! -x "$RCB_OSA_TB" ]; then "$@"; return $?; fi
  "$RCB_OSA_TB" -k 3 "$RCB_OSA_TIMEOUT_S" "$@"
}


LOG="$HOME/.claude/logs/restic-backup.log"
mkdir -p "$(dirname "$LOG")"
TS_START=$(date -u +%Y-%m-%dT%H:%M:%SZ)
echo "[$TS_START] === backup start ===" >> "$LOG"

# Resolve credentials from Keychain. Any failure here is fatal.
B2_ACCOUNT_ID=$(security find-generic-password -a "$USER" -s "restic-b2-keyid"  -w 2>/dev/null) || { echo "[$TS_START] FAIL keychain: restic-b2-keyid missing" >> "$LOG"; exit 1; }
B2_ACCOUNT_KEY=$(security find-generic-password -a "$USER" -s "restic-b2-appkey" -w 2>/dev/null) || { echo "[$TS_START] FAIL keychain: restic-b2-appkey missing" >> "$LOG"; exit 1; }
BUCKET=$(security find-generic-password -a "$USER" -s "restic-b2-bucket" -w 2>/dev/null) || { echo "[$TS_START] FAIL keychain: restic-b2-bucket missing" >> "$LOG"; exit 1; }
RESTIC_PASSWORD=$(security find-generic-password -a "$USER" -s "restic-password" -w 2>/dev/null) || { echo "[$TS_START] FAIL keychain: restic-password missing" >> "$LOG"; exit 1; }
export B2_ACCOUNT_ID B2_ACCOUNT_KEY RESTIC_PASSWORD

REPO="b2:${BUCKET}:claude-code-archive"  # brace-wrapped: zsh interprets $BUCKET:c... as modifier; bash safe but defensive
SOURCE="$HOME/.claude/archives/claude-code/"

# Backup pass
if /opt/homebrew/bin/restic -r "$REPO" backup \
     "$SOURCE" \
     --exclude='*.bak' \
     --exclude='*.unsigned.sha256' \
     --tag "scheduled-$(date -u +%Y-%m-%d)" \
     >> "$LOG" 2>&1; then
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] backup OK" >> "$LOG"
else
  RC=$?
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] FAIL backup rc=$RC" >> "$LOG"
  rcb_osa osascript -e "display notification \"restic backup of Claude Code archive failed (rc=$RC). See $LOG\" with title \"Restic Backup FAIL\" sound name \"Funk\"" 2>/dev/null || true
  exit "$RC"
fi

# Prune pass (retention policy)
if /opt/homebrew/bin/restic -r "$REPO" forget \
     --keep-daily 7 --keep-weekly 4 --keep-monthly 12 --keep-yearly 5 \
     --prune \
     >> "$LOG" 2>&1; then
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] forget+prune OK" >> "$LOG"
else
  RC=$?
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] WARN forget+prune rc=$RC (backup succeeded, retention failed)" >> "$LOG"
fi

echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] === backup done ===" >> "$LOG"
