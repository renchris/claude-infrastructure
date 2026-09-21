#!/bin/bash
# migration-class: c10
# migration-step: register hooks/mail-images-auto.sh as a PostToolUse hook so an ms365 single-message read automatically extracts that email's images and tells the model to Read them — it edits settings.json, which is C10
# migration-run: bash ~/Development/claude-infrastructure/migrations/0033-mail-images-auto.sh
# migration-subject: ~/.claude/hooks/mail-images-auto.sh
# migration-verify: jq -e '[.hooks.PostToolUse[]?|select(.matcher|test("get-mail-message"))|.hooks[]?.command]|any(test("mail-images-auto"))' "$HOME/.claude/settings.json" >/dev/null
# migration-conflict: jq -e '[.hooks.PostToolUse[]?|.hooks[]?.command]|any(test("mail-images-auto"))' "$HOME/.claude/settings.json" >/dev/null
#
# 0033 — read the email's IMAGES, mechanically.
# Subject: hooks/mail-images-auto.sh · bin/cc-mail-images · scripts/lib/ms365_stdio.py
#
# WHAT IT FIXES. Reading an email's text and reporting it as read is a PARTIAL read whenever the
# payload is in the picture — which for a newsletter, a design hand-off, a scanned invoice or a
# pasted screenshot is the common case, not the edge. CLAUDE.md § Email already states the rule in
# prose, and prose is forgettable by construction: it depends on the model remembering, and the
# operator's ruling (2026-09-20) is precisely that nobody should have to remember —
# "the human NEVER extracts emails via cli — it's solely for you, zero human in the loop."
#
# WHY A HOOK RATHER THAN A BETTER RULE. The failure is silent and self-confirming: a text-only read
# produces a fluent, complete-looking summary, so neither the model nor the operator can tell from
# the output that half the message was never opened. Nothing in the close ledger can see it either —
# no gate, no rung, no backlog row keys on "did you look at the attachments". A PostToolUse hook
# fires on the tool call itself, which is the one moment the omission is still detectable.
#
# SCOPE, deliberately narrow. Matches get-mail-message and get-mail-message-mime ONLY. A LIST read
# returns many messages and must never trigger N extractions — arm 2 of the test asserts silence
# there. Extraction is idempotent per (messageId, day), so re-reading a thread costs one manifest
# stat, not a re-download.
#
# RESIDUAL, stated rather than hidden: this adds one node spawn + one Graph call to a single-message
# read, and remote images cost a round-trip each (trackers are pattern-filtered, not fetched). On a
# mail with no images the hook exits silent. Kill switch: CC_MAIL_IMAGES_AUTO=0.
set -euo pipefail

S="$HOME/.claude/settings.json"
# The tilde must NOT expand: this string is written into settings.json as a
# literal, and Claude Code expands `~` in a hook command itself. Measured on the
# live file: 90 of 98 registered hook commands are stored in tilde form, 8
# absolute — so expanding here would write the minority spelling and diverge
# from every sibling hook. shellcheck is right about the shell mechanism and
# wrong about the destination, which is JSON.
# shellcheck disable=SC2088
H='~/.claude/hooks/mail-images-auto.sh'

[ -f "$S" ] || { echo "no settings.json at $S" >&2; exit 1; }
command -v jq >/dev/null || { echo "jq required" >&2; exit 1; }

if jq -e '[.hooks.PostToolUse[]?|.hooks[]?.command]|any(test("mail-images-auto"))' "$S" >/dev/null; then
  echo "0033: already registered — nothing to do"; exit 0
fi

BAK="$S.bak-0033-$(date -u +%Y%m%d%H%M%S)"
cp -p "$S" "$BAK"
echo "0033: backup $BAK"

tmp="$(mktemp)"
jq --arg cmd "$H" '
  .hooks //= {} |
  .hooks.PostToolUse //= [] |
  .hooks.PostToolUse += [{
    "matcher": "mcp__ms365__get-mail-message.*",
    "hooks": [{"type": "command", "command": $cmd}]
  }]
' "$S" > "$tmp"

jq -e . "$tmp" >/dev/null || { echo "0033: produced invalid JSON — aborting, settings untouched" >&2; rm -f "$tmp"; exit 1; }
mv "$tmp" "$S"

if jq -e '[.hooks.PostToolUse[]?|select(.matcher|test("get-mail-message"))|.hooks[]?.command]|any(test("mail-images-auto"))' "$S" >/dev/null; then
  echo "0033: registered. New sessions pick it up; existing ones keep their loaded config."
  echo "0033: revert -> cp -p $BAK $S"
else
  echo "0033: verification FAILED — restoring $BAK" >&2; cp -p "$BAK" "$S"; exit 1
fi
