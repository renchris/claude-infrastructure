#!/usr/bin/env bash
# Author identity for the agent fleet. Mirrors robobun's OBSERVED setup.
# robobun is a plain User (performed_via_github_app null on 600/600 sampled comments),
# NOT a GitHub App -- which keeps commits human-shaped and avoids installation-token plumbing.
set -euo pipefail
: "${BOT_USER:?e.g. acmebot}" "${BOT_TOKEN:?fine-grained PAT}" "${BOT_USER_ID:?numeric GitHub user id}"

# --- PAT scopes, minimum viable (set these in the GitHub UI, repo-scoped):
#       Contents:      Read and write   (push branches)
#       Pull requests: Read and write   (open, comment, assign)
#       Issues:        Read and write   (triage, close)
#       Metadata:      Read
#     Do NOT grant Administration. Do NOT put the account in a team with merge rights.
#     The merge boundary is the single safety property that makes high volume tractable.

# --- SSH SIGNING key (signing only -- do NOT register it as an authentication key).
#     robobun's is titled "Robobun on farm signing key", created 2026-05-04, which dates
#     the current architecture.
ssh-keygen -t ed25519 -C "${BOT_USER} farm signing key" -f ~/.ssh/farm_signing -N ""
gh api -X POST /user/ssh_signing_keys \
  -f title="${BOT_USER} farm signing key" \
  -f key="$(cat ~/.ssh/farm_signing.pub)"

# --- Per-worker git config: ONE identity across the whole fleet, not one per worker.
git config --global user.name  "${BOT_USER}"
git config --global user.email "${BOT_USER_ID}+${BOT_USER}@users.noreply.github.com"  # noreply, not the profile email
git config --global gpg.format ssh
git config --global user.signingkey ~/.ssh/farm_signing.pub
git config --global commit.gpgsign true

# --- Push over HTTPS with the token (matches robobun's pusher_type: "user").
git config --global credential.helper store
printf 'https://%s:%s@github.com\n' "$BOT_USER" "$BOT_TOKEN" > ~/.git-credentials
chmod 600 ~/.git-credentials

# --- Strip attribution trailers: robobun's current commits carry none.
cat > ~/.git-commit-msg-hook <<'HOOK'
#!/bin/sh
grep -qE 'Co-Authored-By: Claude|Generated with' "$1" && {
  echo "error: attribution trailer is stripped by policy - see prompts/task.md rule 5"; exit 1; }
exit 0
HOOK
chmod +x ~/.git-commit-msg-hook
echo "OK. Now install github.com/apps/claude as the REVIEWER identity - do not reuse this account for review."
