#!/usr/bin/env bash
# kitty-setup.sh — one command to make kitty a first-class terminal for this toolchain.
#
#   scripts/kitty-setup.sh            apply (idempotent — safe to re-run any number of times)
#   scripts/kitty-setup.sh --check    report only; exits 1 if anything is missing or INERT
#   scripts/kitty-setup.sh --undo     revert everything this script does
#
# WHAT IT WIRES, AND WHY EACH PIECE IS LOAD-BEARING
#   1. kitty.conf            cmd+D / cmd+shift+D splits + the `splits` layout they require, and the
#                            control socket that handoff / self-recycle cannot work without.
#   2. it2-kitty + wrapper   Claude Code's Agent Teams pane backend shells out to a PATH-resolved
#                            `it2`. Answering that contract against `kitty @` turns assignee
#                            sessions into NATIVE, VISIBLE kitty split panes.
#   3. ITERM_SESSION_ID      the env var Claude Code's iTerm2 check reads (it performs no handshake
#                            with iTerm2). Per-pane, because each pane must report its own id.
#   4. teammateMode          "tmux" routes assignees into a DETACHED session — invisible. "iterm2"
#                            selects the backend that now speaks kitty.
#
# THE ONE STEP THIS SCRIPT CANNOT DO FOR YOU is restarting kitty. `allow_remote_control` and
# `listen_on` are the two options kitty refuses to reload ("Changing this option by reloading the
# config is not supported"), and a restart closes every pane — including, usually, the session
# running this script. Reloading with Ctrl+Cmd+, is NOT a substitute: measured 2026-07-31, it leaves
# an already-open tab in its old layout, where cmd+D silently splits the WRONG WAY because
# --location=vsplit is ignored outside the `splits` layout. So the script reports that step; it
# never pretends to have done it, and --check treats a missing socket as INERT rather than OK.
#
# IDEMPOTENCE IS THE POINT. A setup step a new user cannot safely re-run is a setup step they get
# stuck on: every action below is either a symlink (rewritten), a keyed block in a dotfile (matched
# and skipped), or a JSON key (set to a fixed value). Nothing appends twice.
#
# Seams: CC_KITTY_CONFIG_DIR · CC_KITTY_BIN_DIR · CC_KITTY_SHELL_RC · CC_KITTY_SETTINGS

set -uo pipefail

REPO="$(cd "$(dirname "$(readlink -f "$0" 2>/dev/null || printf '%s' "$0")")/.." && pwd)"
KCONF_DIR="${CC_KITTY_CONFIG_DIR:-$HOME/.config/kitty}"
BIN_DIR="${CC_KITTY_BIN_DIR:-$HOME/.claude/bin}"
SHELL_RC="${CC_KITTY_SHELL_RC:-$HOME/.zshrc}"
BLOCK_ID="cc-kitty-agent-teams"

MODE=apply
case "${1:-}" in
  --check) MODE=check ;; --undo) MODE=undo ;; ""|--apply) MODE=apply ;;
  -h|--help) sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  *) printf 'kitty-setup: unknown option %s\n' "$1" >&2; exit 2 ;;
esac

pass=0; miss=0
ok(){   printf '  \033[32m✓\033[0m %s\n' "$*"; pass=$((pass+1)); }
no(){   printf '  \033[31m✗\033[0m %s\n' "$*"; miss=$((miss+1)); }
info(){ printf '  \033[2m·\033[0m %s\n' "$*"; }
hdr(){  printf '\n\033[1m%s\033[0m\n' "$*"; }

settings_files() {
  if [ -n "${CC_KITTY_SETTINGS:-}" ]; then printf '%s\n' "$CC_KITTY_SETTINGS"; return; fi
  # Every config dir this operator shards across; a teammateMode set in only one of them means the
  # behaviour depends on which account launched the session.
  for d in "$HOME/.claude" "$HOME/.claude-next" "$HOME/.claude-secondary" \
           "$HOME/.claude-tertiary" "$HOME/.claude-quaternary"; do
    [ -f "$d/settings.json" ] && printf '%s\n' "$d/settings.json"
  done
}

# ── preflight ────────────────────────────────────────────────────────────────────────────────────
hdr "kitty-setup ($MODE)  repo=$REPO"
if ! command -v kitty >/dev/null 2>&1 && [ ! -x /Applications/kitty.app/Contents/MacOS/kitty ]; then
  no "kitty is not installed — brew install --cask kitty"
  exit 1
fi

# ── undo ─────────────────────────────────────────────────────────────────────────────────────────
if [ "$MODE" = undo ]; then
  hdr "reverting"
  [ -L "$KCONF_DIR/kitty.conf" ] && { rm -f "$KCONF_DIR/kitty.conf"; ok "removed kitty.conf symlink"; }
  for f in it2-kitty cc-term; do
    [ -L "$BIN_DIR/$f" ] && { rm -f "$BIN_DIR/$f"; ok "removed $BIN_DIR/$f"; }
  done
  if grep -q "$BLOCK_ID" "$SHELL_RC" 2>/dev/null; then
    cp "$SHELL_RC" "$SHELL_RC.bak-kitty-undo"
    # Delete the whole keyed block, inclusive of its markers.
    sed -i '' "/# >>> $BLOCK_ID >>>/,/# <<< $BLOCK_ID <<</d" "$SHELL_RC"
    ok "removed the $BLOCK_ID block from $SHELL_RC (backup: $SHELL_RC.bak-kitty-undo)"
  fi
  info "teammateMode left as-is — set it yourself if you want tmux back"
  info "restart kitty for the config removal to take effect"
  exit 0
fi

# ── 1. kitty.conf ────────────────────────────────────────────────────────────────────────────────
hdr "1. kitty.conf"
SRC_CONF="$REPO/config/kitty.conf"
if [ "$MODE" = apply ]; then
  mkdir -p "$KCONF_DIR"
  if [ -e "$KCONF_DIR/kitty.conf" ] && [ ! -L "$KCONF_DIR/kitty.conf" ]; then
    # A real file is someone's hand-written config. Never clobber it — that is the kind of silent
    # loss this repo's File Update Rule exists to prevent.
    cp "$KCONF_DIR/kitty.conf" "$KCONF_DIR/kitty.conf.pre-cc-$(date +%Y%m%d%H%M%S)"
    info "existing real kitty.conf backed up alongside it"
  fi
  ln -sfn "$SRC_CONF" "$KCONF_DIR/kitty.conf"
fi
if [ "$(readlink "$KCONF_DIR/kitty.conf" 2>/dev/null)" = "$SRC_CONF" ]; then
  ok "kitty.conf -> repo SSOT"
else no "kitty.conf is not linked to $SRC_CONF"; fi

# ── 2. the it2 translator ────────────────────────────────────────────────────────────────────────
hdr "2. Agent Teams pane backend (native kitty splits)"
if [ "$MODE" = apply ]; then
  mkdir -p "$BIN_DIR"
  # ~/.claude/bin/it2 is historically a real COPY of bin/it2-wrapper, not a symlink, so it must be
  # refreshed explicitly or the kitty divert never reaches the live layer.
  cp "$REPO/bin/it2-wrapper" "$BIN_DIR/it2" && chmod +x "$BIN_DIR/it2"
  ln -sfn "$REPO/bin/it2-kitty" "$BIN_DIR/it2-kitty"
  # NOTE: no separate pane adapter is linked here. bin/cc-pane is the repo's terminal-agnostic
  # seam and install.sh already deploys it; because its iterm2 driver shells out to
  # $HOME/.claude/bin/it2, the divert above makes cc-pane work on kitty with no kitty driver.
  # An earlier draft linked a second adapter here and would have dangled on a fresh clone.
fi
grep -q "TERMINAL DISPATCH" "$BIN_DIR/it2" 2>/dev/null \
  && ok "$BIN_DIR/it2 carries the kitty divert" || no "$BIN_DIR/it2 has no kitty divert"
[ -x "$BIN_DIR/it2-kitty" ] && ok "it2-kitty deployed" || no "it2-kitty missing at $BIN_DIR"
# A DANGLING symlink is the failure this checks for, not mere absence: -x follows the link, so a
# link pointing at a file that no longer exists reports missing rather than passing on the name.
if [ -e "$BIN_DIR/cc-term" ] || [ -L "$BIN_DIR/cc-term" ]; then
  [ -x "$BIN_DIR/cc-term" ] || no "$BIN_DIR/cc-term is a DANGLING symlink — remove it (superseded by cc-pane)"
fi

# ── 3. the env var Claude Code's iTerm2 check reads ──────────────────────────────────────────────
hdr "3. pane identity for Claude Code"
if [ "$MODE" = apply ] && ! grep -q "$BLOCK_ID" "$SHELL_RC" 2>/dev/null; then
  cp "$SHELL_RC" "$SHELL_RC.bak-kitty-$(date +%Y%m%d%H%M%S)" 2>/dev/null
  cat >> "$SHELL_RC" <<EOF

# >>> $BLOCK_ID >>>
# Claude Code gates its iTerm2 pane backend on an ENV VAR (it never handshakes with iTerm2):
#   TERM_PROGRAM==="iTerm.app" || !!ITERM_SESSION_ID || terminal==="iTerm.app"
# and derives the leader pane id as ITERM_SESSION_ID.slice(indexOf(":")+1) — so the COLON IS
# REQUIRED; without one it returns null and silently splits from whatever pane is active.
# ~/.claude/bin/it2 then translates every backend call into \`kitty @\`.
if [ -n "\${KITTY_WINDOW_ID:-}" ] && [ -z "\${ITERM_SESSION_ID:-}" ]; then
  export ITERM_SESSION_ID="w0t0p0:\$KITTY_WINDOW_ID"
fi
# <<< $BLOCK_ID <<<
EOF
fi
grep -q "$BLOCK_ID" "$SHELL_RC" 2>/dev/null \
  && ok "$SHELL_RC exports ITERM_SESSION_ID inside kitty" || no "$SHELL_RC has no $BLOCK_ID block"

# ── 4. teammateMode ──────────────────────────────────────────────────────────────────────────────
hdr "4. teammateMode (decides whether you SEE your assignees)"
while IFS= read -r S; do
  [ -n "$S" ] || continue
  if [ "$MODE" = apply ]; then
    cp "$S" "$S.bak-kitty-$(date +%Y%m%d%H%M%S)"
    python3 - "$S" <<'PY'
import json,sys
p=sys.argv[1]
try: d=json.load(open(p))
except Exception as e:
    print("   could not parse %s: %s" % (p,e)); sys.exit(0)
d["teammateMode"]="iterm2"
json.dump(d,open(p,"w"),indent=2)
PY
  fi
  cur=$(python3 -c 'import json,sys
try: print(json.load(open(sys.argv[1])).get("teammateMode"))
except Exception: print("unreadable")' "$S")
  [ "$cur" = "iterm2" ] && ok "$(basename "$(dirname "$S")")/settings.json teammateMode=iterm2" \
                        || no "$(basename "$(dirname "$S")")/settings.json teammateMode=$cur (want iterm2)"
done <<EOF
$(settings_files)
EOF

# ── 5. the live state — is any of it actually ON? ────────────────────────────────────────────────
# Config on disk is NOT the same claim as config loaded. A setup that reports green while the
# running kitty predates the config is exactly how the operator lost a window on 2026-07-31.
hdr "5. live state (needs a kitty RESTART to become true)"
if [ -n "${KITTY_WINDOW_ID:-}" ]; then
  if [ -n "${KITTY_LISTEN_ON:-}" ]; then
    ok "control socket live: $KITTY_LISTEN_ON"
  else
    no "INERT — this kitty has no control socket; it started before the config. RESTART kitty."
  fi
  [ -n "${ITERM_SESSION_ID:-}" ] && ok "ITERM_SESSION_ID=$ITERM_SESSION_ID" \
                                 || no "ITERM_SESSION_ID unset in this pane (new shell needed)"
else
  info "not running inside kitty — cannot judge live state from here"
fi

printf '\n\033[1m%d ok, %d missing\033[0m\n' "$pass" "$miss"
if [ "$miss" -gt 0 ]; then
  cat <<'EOF'

NEXT: quit kitty completely (Cmd+Q) and reopen it.
  allow_remote_control and listen_on are the only two options kitty cannot reload, and Ctrl+Cmd+,
  is not a substitute — it leaves an open tab in its old layout, where cmd+D splits the wrong way.
Then re-run:  scripts/kitty-setup.sh --check
EOF
  exit 1
fi
printf '\nAll wired and live. cmd+D splits right, cmd+shift+D splits down.\n'
exit 0
