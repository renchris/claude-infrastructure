#!/bin/bash
# 36 — activate the interactive account router: `claude1` pins account 1, bare `claude` routes.
#
# C10. Two surfaces only an operator may change: ~/.zshrc (how every session launches) and the
# accounts.json launcher field (what handoff-fire TYPES into a pane to pin an account). They are
# coupled and must move TOGETHER — flipping the SSOT while the shell still lacks `claude1` would
# leave every dispatched fire typing a command that does not exist, so both happen here, atomically,
# or neither does.
#
#   CONFIRM=1 bash ~/.claude/docs/activation/pending-activation/36-start-latency-router-activate.sh
#
# Reversible in one line: delete the `source .../claude-launcher.zsh` line from ~/.zshrc and re-run
# scripts/gen-account-map.sh after restoring accounts.json from the backup this script writes.
set -euo pipefail

REPO="${CC_REPO:-$HOME/Development/claude-infrastructure}"
ZSHRC="${CC_ZSHRC:-$HOME/.zshrc}"
LIB_LIVE="$HOME/.claude/lib/claude-launcher.zsh"
SRC_LINE="[ -r \"$LIB_LIVE\" ] && source \"$LIB_LIVE\"   # start-latency router (migration 0009)"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"

say() { printf '36: %s\n' "$*"; }
die() { printf '36: ERROR %s\n' "$*" >&2; exit 1; }

[ "${CONFIRM:-}" = 1 ] || {
  cat <<EOF
36: DRY RUN — nothing changed. Re-run with CONFIRM=1 to apply.

  Would append to $ZSHRC:
      $SRC_LINE
  Would set accounts.json accounts[0].launcher: "claude" -> "claude1"
  Would regenerate lib/account-map.generated.sh
  Backups: $ZSHRC.pre-router.$STAMP
           $REPO/accounts.json.pre-router.$STAMP
EOF
  exit 0
}

# ---- preflight: refuse on anything we cannot put back ------------------------------------------
[ -w "$ZSHRC" ]                    || die "$ZSHRC not writable"
[ -r "$LIB_LIVE" ]                 || die "$LIB_LIVE absent — land + deploy-live first (it is an ADD, so it needs the converger to symlink it)"
[ -r "$REPO/accounts.json" ]       || die "$REPO/accounts.json unreadable"
[ -x "$REPO/scripts/gen-account-map.sh" ] || die "gen-account-map.sh missing"
command -v jq >/dev/null           || die "jq required"

# The lib installs the router by COPYING the existing claude() into _claude_pinned. If ~/.zshrc has
# not defined claude() by the time the source line runs, the wrapper is a silent no-op and the
# feature ships dark. Appending puts the line last, which is after the definition — assert it.
grep -q '^claude() {' "$ZSHRC" || die "no 'claude() {' in $ZSHRC — the wrapper would have nothing to wrap"

# ---- step 1: ~/.zshrc ---------------------------------------------------------------------------
if grep -qF 'claude-launcher.zsh' "$ZSHRC"; then
  say "zshrc already sources the launcher lib — leaving it alone (idempotent)"
else
  cp -p "$ZSHRC" "$ZSHRC.pre-router.$STAMP"
  printf '\n# ── interactive account routing (claude1 pins account 1; bare claude routes) ──\n%s\n' \
    "$SRC_LINE" >> "$ZSHRC"
  say "appended the source line to $ZSHRC (backup: $ZSHRC.pre-router.$STAMP)"
fi

# ---- step 2: the SSOT launcher flip -------------------------------------------------------------
cur="$(jq -r '.accounts[0].launcher' "$REPO/accounts.json")"
if [ "$cur" = "claude1" ]; then
  say "accounts.json already pins account 1 to claude1 — leaving it alone"
else
  [ "$cur" = "claude" ] || die "accounts[0].launcher is '$cur', expected 'claude' — refusing to guess"
  cp -p "$REPO/accounts.json" "$REPO/accounts.json.pre-router.$STAMP"
  tmp="$(mktemp "${TMPDIR:-/tmp}/accounts.XXXXXX")"
  # `aliases` deliberately UNTOUCHED. It is a config-dir-BASENAME alias consumed only by
  # cc_acct_name_for_dir_basename (~/.claude -> "claude" -> next); it is not a launcher alias and
  # never was, so removing it here would break dir attribution while rescuing nothing.
  jq '.accounts[0].launcher = "claude1"' "$REPO/accounts.json" > "$tmp"
  jq -e '.accounts[0].launcher == "claude1"' "$tmp" >/dev/null || die "flip did not take"
  mv "$tmp" "$REPO/accounts.json"
  say "accounts.json accounts[0].launcher: claude -> claude1 (backup: accounts.json.pre-router.$STAMP)"
fi

# ---- step 3: regenerate the derived map ---------------------------------------------------------
( cd "$REPO" && bash scripts/gen-account-map.sh >/dev/null ) || die "gen-account-map.sh failed"
grep -q 'claude1' "$REPO/lib/account-map.generated.sh" || die "generated map does not mention claude1"
say "regenerated lib/account-map.generated.sh"

# ---- step 4: prove it, in this shell, before claiming anything ----------------------------------
# `grep 'x' >/dev/null`, NOT `grep -q`: under `set -euo pipefail` an early-exiting consumer
# SIGPIPEs the producer, and pipefail then makes the whole pipeline non-zero — so the condition
# would read FALSE on a MATCH and this check would report failure exactly when it succeeded.
if zsh -fc "claude() { print \"cfg=\${CLAUDE_CONFIG_DIR:-unset}\" }; source '$LIB_LIVE'; claude1" \
     2>/dev/null | grep 'claude-next' >/dev/null; then
  say "VERIFIED: claude1 pins ~/.claude-next"
else
  die "claude1 did not pin account 1 — the zshrc line is in place but the lib is not behaving; revert with the backups above"
fi

# ---- step 5: the keep-warm producer (optional but strongly recommended) ------------------------
# Without it the router abstains whenever the cache has rolled, which means `claude` falls back to
# the pinned account most of the time — correct, but the feature is then mostly inert.
PLIST_SRC="$REPO/launchd/staged/com.claude.accounts-keepwarm.plist"
PLIST_DST="$HOME/Library/LaunchAgents/com.claude.accounts-keepwarm.plist"
if [ "${KEEPWARM:-1}" = 0 ]; then
  say "keep-warm SKIPPED (KEEPWARM=0) — routing will abstain to the pinned account when the cache is cold"
elif launchctl print "gui/$(id -u)/com.claude.accounts-keepwarm" >/dev/null 2>&1; then
  say "keep-warm already loaded — leaving it alone"
else
  [ -r "$PLIST_SRC" ] || die "$PLIST_SRC missing"
  mkdir -p "$HOME/Library/LaunchAgents" "$HOME/.claude/logs"
  cp "$PLIST_SRC" "$PLIST_DST"
  launchctl bootstrap "gui/$(id -u)" "$PLIST_DST" 2>/dev/null || launchctl load "$PLIST_DST" 2>/dev/null || true
  if launchctl print "gui/$(id -u)/com.claude.accounts-keepwarm" >/dev/null 2>&1; then
    say "keep-warm LOADED (StartInterval 60, refresh-ahead --max-age 30)"
  else
    say "keep-warm copy in place but NOT loaded — load it with:"
    say "  launchctl bootstrap gui/$(id -u) $PLIST_DST"
  fi
fi

say "DONE. Open a NEW shell (or: source $ZSHRC) — claude1 = account 1, bare claude routes."
say "Kill switch if it ever misbehaves:  export CC_CLAUDE_ROUTE=off"
say "Stop the warmer:  launchctl bootout gui/$(id -u)/com.claude.accounts-keepwarm"
