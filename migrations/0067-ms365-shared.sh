#!/bin/bash
# migration-class: c10
# migration-step: cut every session over to ONE shared ms365 MCP server (com.claude.mcp-ms365: mcp-proxy on 127.0.0.1 over one stdio ms-365-mcp-server) — installs mcp-proxy, writes a 0600 key, runs the tools/list cutover gate and refuses on a failure, loads the launchd job, registers hooks/ms365-shared-guard.sh in ~/.claude/settings.json, writes the activation marker and re-renders every account config. launchctl and settings.json are machine-wide, so this is yours
# migration-run: bash ~/Development/claude-infrastructure/migrations/0067-ms365-shared.sh --confirm ms365-shared
# migration-subject: ~/Development/claude-infrastructure/launchd/staged/com.claude.mcp-ms365.plist
# migration-verify: bash ~/Development/claude-infrastructure/migrations/0067-ms365-shared.sh --verify
# migration-batch-hold: manual — the gate needs a multi-account MSAL cache and spawns a live server; launchctl is machine-wide
#
# ══ 0067 — one shared ms365 server (docs/research/load-root-cause-2026-10-17/DESIGN.md row X4) ══
# 29 stdio children (~857 MB RSS, p99 12.4 s connect) become 1-2 processes. The gate is the whole
# point: `scripts/mcp-ms365-proxy.sh gate` must show tools/list through the proxy byte-equal to a
# direct stdio spawn (names and inputSchema, 188 tools incl. download-bytes-to-file and
# verify-login) with `account` on every Graph tool. A single-account start fails it. If it fails,
# NOTHING session-facing changes: the fallback is per-account children (row note X4), never a deny.
#
#   0067-ms365-shared.sh [--dry-run | --verify | --confirm ms365-shared]
#
# Order, so every failure leaves sessions on stdio: 1 install mcp-proxy · 2 key file (0600, kept if
# present) · 3 gate · 4 load the job and read it back · 5 register the guard (backup, verify by
# content) · 6 marker · 7 re-render + --check. Idempotent; re-run after any refusal.
# Undo: rm ~/.claude/state/ms365-shared.active; bash ~/.claude/scripts/mcp-ssot-wire.sh;
#       launchctl bootout gui/$(id -u)/com.claude.mcp-ms365 (the guard is inert without the marker).
# Seams: CC_0067_LAUNCHCTL · CC_MIGRATION_LA_DIR · CC_MIGRATION_REPO · CC_SETTINGS_PARITY_BIN · HOME.
set -uo pipefail

N=0067
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="${CC_MIGRATION_REPO:-$(cd "$here/.." && pwd)}"
LC="${CC_0067_LAUNCHCTL:-launchctl}"
LA="${CC_MIGRATION_LA_DIR:-$HOME/Library/LaunchAgents}"
parity="${CC_SETTINGS_PARITY_BIN:-$HOME/.claude/bin/cc-settings-parity}"
LABEL="com.claude.mcp-ms365"; DOMAIN="gui/$(id -u)"
src="$REPO/launchd/staged/$LABEL.plist"; dst="$LA/$LABEL.plist"
KEY="$HOME/.claude/state/ms365-proxy.key"; MARKER="$HOME/.claude/state/ms365-shared.active"
# shellcheck disable=SC2088  # the literal "~/" is what settings.json stores; Claude Code expands it
CMD='~/.claude/hooks/ms365-shared-guard.sh'
MATCHER='mcp__ms365__.*'
f="$HOME/.claude/settings.json"
BIN="$HOME/Library/Application Support/fnm/aliases/default/bin"
PVER="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["shared"]["ms365"]["proxy_version"])' "$REPO/mcp-servers.json")"

say() { printf '%s: %s\n' "$N" "$*"; }
die() { printf '%s: %s\n' "$N" "$*" >&2; exit "${2:-1}"; }

mode=""
case "${1:-}" in
  ''|--dry-run) mode=dry ;;
  --verify) mode=verify ;;
  --confirm) [ "${2:-}" = ms365-shared ] || die "--confirm must name its target: --confirm ms365-shared" 2; mode=apply ;;
  *) die "unknown argument $1 (use --dry-run, --verify or --confirm ms365-shared)" 2 ;;
esac

registered() {
  jq -e --arg c "$CMD" --arg m "$MATCHER" '[.hooks.PreToolUse[]? | select(.matcher == $m) | .hooks[]?.command] | any(. == $c)' "$1" >/dev/null 2>&1
}
if [ "$mode" = verify ]; then
  [ -e "$MARKER" ] && "$LC" print "$DOMAIN/$LABEL" >/dev/null 2>&1 && registered "$f" \
    && bash "$REPO/scripts/mcp-ssot-wire.sh" --check >/dev/null 2>&1; exit $?
fi

[ -f "$src" ] || die "MISSING $src — the wiring commit did not land intact; refusing"
for p in "$HOME/.claude/hooks/ms365-shared-guard.sh" "$HOME/.claude/scripts/mcp-ms365-proxy.sh"; do
  [ -x "$p" ] || die "REFUSED — the live layer lacks $p; converge first: bash $REPO/scripts/deploy-live.sh" 4
done
if [ "$mode" = dry ]; then
  say "would: npm install -g mcp-proxy@$PVER · write $KEY (0600) if absent · run the gate (refuse on FAIL)"
  say "would: install $dst + bootstrap $DOMAIN · append $CMD to .hooks.PreToolUse ($MATCHER) · touch $MARKER · re-render"
  say "dry run — nothing changed; act with: bash $REPO/migrations/0067-ms365-shared.sh --confirm ms365-shared"
  exit 0
fi
"$parity" check >/dev/null 2>&1 || die "REFUSED — accounts do not all share $f ($parity check failed); converge with 0037 first" 3

# 1. mcp-proxy beside ms-365-mcp-server, under the same node the job's PATH names.
if [ "$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["version"])' "$BIN/../lib/node_modules/mcp-proxy/package.json" 2>/dev/null)" != "$PVER" ]; then
  PATH="$BIN:$PATH" npm install -g "mcp-proxy@$PVER" >/dev/null 2>&1 || die "npm install -g mcp-proxy@$PVER FAILED — nothing else changed"
fi
say "mcp-proxy $PVER installed"
# 2. The key: 0600 from birth, never on argv.
if [ ! -s "$KEY" ]; then
  mkdir -p "$(dirname "$KEY")" && (umask 077; python3 -c 'import secrets;print(secrets.token_hex(32))' > "$KEY") || die "key write FAILED"
fi
chmod 600 "$KEY"
# 3. The gate. A FAIL stops here, with every session still on stdio.
out="$(PATH="$BIN:$PATH" bash "$REPO/scripts/mcp-ms365-proxy.sh" gate)"; rc=$?
printf '%s\n' "$out"
[ "$rc" -eq 0 ] || die "gate FAILED — nothing session-facing changed. Fallback per DESIGN row note X4 (per-account children); a deny is not the fallback"
# 4. Load the job and read it back by a different call.
mkdir -p "$LA" "$HOME/.claude/logs" || die "mkdir FAILED"
if ! cmp -s "$src" "$dst"; then
  "$LC" bootout "$DOMAIN/$LABEL" >/dev/null 2>&1
  cp "$src" "$dst.tmp.$$" && mv -f "$dst.tmp.$$" "$dst" || die "install of $dst FAILED"
fi
"$LC" print "$DOMAIN/$LABEL" >/dev/null 2>&1 || "$LC" bootstrap "$DOMAIN" "$dst" || die "bootstrap of $LABEL FAILED"
i=0; while ! "$LC" print "$DOMAIN/$LABEL" 2>/dev/null | grep -q 'state = running'; do
  [ "$i" -ge 30 ] && die "$LABEL not running 30 s after bootstrap — read $HOME/.claude/logs/mcp-ms365.err.log"
  sleep 1; i=$((i + 1))
done
say "$LABEL loaded and running"
# 5. Register the guard (pattern of 0061): backup, append one entry, verify the rest is unchanged.
real="$f"; if [ -L "$f" ]; then t="$(readlink "$f")"; case "$t" in /*) real="$t" ;; *) real="$(dirname "$f")/$t" ;; esac; fi
if ! registered "$real"; then
  ENTRY=$(jq -nc --arg c "$CMD" --arg m "$MATCHER" '{matcher:$m,hooks:[{type:"command",command:$c,timeout:5}]}')
  bdir="$HOME/.claude/backups/ms365-shared-$N-$(date +%Y%m%d%H%M%S)"
  mkdir -p "$bdir" && cp -p "$real" "$bdir/settings.json" || die "backup FAILED"
  tmp="$(dirname "$real")/.settings.json.tmp-$N-$$"
  jq --argjson e "$ENTRY" '.hooks.PreToolUse = ((.hooks.PreToolUse // []) + [$e])' "$real" > "$tmp" || { rm -f "$tmp"; die "jq edit FAILED"; }
  [ "$(jq -S 'del(.hooks.PreToolUse)' "$real")" = "$(jq -S 'del(.hooks.PreToolUse)' "$tmp")" ] \
    && [ "$(jq -c --argjson e "$ENTRY" '(.hooks.PreToolUse // []) + [$e]' "$real")" = "$(jq -c '.hooks.PreToolUse' "$tmp")" ] \
    || { rm -f "$tmp"; die "settings edit did not verify by content — nothing written"; }
  mv "$tmp" "$real" || die "settings write FAILED"
  say "guard registered (backup: $bdir/settings.json)"
fi
# 6-7. Activate and re-render; --check must agree with the http form.
touch "$MARKER" || die "marker write FAILED"
bash "$REPO/scripts/mcp-ssot-wire.sh" && bash "$REPO/scripts/mcp-ssot-wire.sh" --check \
  || die "re-render did not check green — undo: rm $MARKER; bash $REPO/scripts/mcp-ssot-wire.sh"
say "done — NEW sessions connect to the shared server; running sessions keep their stdio child until they end"
