#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# 28-cc-220-advance  —  repoint the eval launcher 2.1.219 → 2.1.220, and retire claude-default()
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# WHAT: two edits to ~/.zshrc, both idempotent, both reversible with --undo, one timestamped backup.
#   (1) claude()'s `_bin=` pin at ~:454:  ~/.claude-219 → ~/.claude-220   (2.1.220 already installed)
#   (2) DELETE the stale claude-default() function + its header comment.
#
# WHY (1) — the soak argument INVERTS the usual one. 2.1.220 shipped 2026-07-24T23:11:21Z, just 7.0
#   HOURS after 2.1.219 (2026-07-24T16:11:49Z), and has been sole npm latest/next for 7.8 days with
#   no successor, against a prior ~daily cadence. So the build we run TODAY (2.1.219) is the
#   essentially un-field-tested one — 7 hours as `latest` means our bug reports are a population of
#   one — and 2.1.220 is the first version since 2.1.215 to satisfy this repo's own ">=1 week clean
#   field exposure" rule. Advancing REDUCES exposure here; holding is the riskier option.
#
#   The 2.1.220 CHANGELOG is a stub — "Bug fixes and reliability improvements", verbatim and
#   complete. No content is inferred anywhere in this script. The binary-diff technique from the
#   cc-version-audit appendix was attempted and DEFEATED by full re-minification (every symbol
#   renamed; hazard-keyword counts match near-exactly across both bundles), so the change set is
#   genuinely undisclosed. That is precisely why the verdict rests on an EMPIRICAL gate rather than
#   on the changelog:
#
#     scripts/cc-upgrade-gate.sh ~/.claude-220/node_modules/.bin/claude claude-opus-5 next
#       → 13/13 PASS, verdict GREEN (run 2026-08-01)
#
#   covering: binary registers claude-opus-5 without demotion · account entitlement · auto-mode
#   drives a real tool turn · effort ladder high/xhigh/max · launcher effect-read · SPAWN_DEPTH
#   containment · teammate spawn · Dynamic Workflow · subagent · lifecycle hooks fire · permission
#   non-block · resume routing · MCP reachable.
#
#   The #68619 containment lever SURVIVES: CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH is still read by the
#   220 bundle and still reaches the child (gate check 6). GH #68619 is unchanged-open (last touched
#   2026-07-22, before BOTH builds), so the depth=1 export in claude() stays load-bearing — this
#   script does not touch it.
#
# WHY (2) — claude-default() is a leftover the 2026-07-31 rename stranded. It still calls
#   `claude-latest` (the pinned STABLE 2.1.114 track) with no --permission-mode, so despite its name
#   it is neither the default launcher nor on the default binary. Census 2026-08-01: ZERO executable
#   callers anywhere — repo, live ~/.claude layer, and all 45 ~/Library/LaunchAgents plists. Its only
#   references are its own definition and three prose mentions. Keeping a launcher whose NAME asserts
#   something false is worse than deleting it; the no-auto-mode behaviour it offered is available as
#   `CLAUDE_PERM_MODE=default claude`, and plan mode already has `claude-plan`.
#
# NOT DONE HERE, deliberately: the claude-next / claude-opus5 back-compat shims STAY. They look like
#   dead weight and are not — scripts/handoff-fire.sh:2937 `launcher_for()` synthesizes the BARE name
#   `claude-next` for account `next` and types it verbatim into an interactive zsh via it2 send-text,
#   and lib/desk.zsh:67 calls it directly. Deleting the shims turns every account-`next` autonomous
#   fire into `zsh: command not found`. Migrating those callers is a separate, tested change; two
#   one-line shims cost nothing and cc-upgrade-gate check 5 now proves they still forward the full
#   flag-set.
#
# WHY C10: ~/.zshrc is the operator's live shell — every session on this machine starts through it.
# Undo:       bash <this file> --undo        (restores the backup taken at run time)
# Rollback for (1) alone: put ~/.claude-219 back in the _bin line; it stays installed and intact.
# Mark done:  touch <this file>.done
# ───────────────────────────────────────────────────────────────────────────────────────────────────
set -uo pipefail

ZSHRC="${CC_ZSHRC:-$HOME/.zshrc}"
# Bare names, NO leading dot: every use below supplies its own `.` (either as the regex escape
# `\.` or as a literal `.` in a path). Carrying the dot inside the variable made `\.$FROM_DIR`
# expand to `\..claude-219`, which matches nothing — caught by running this script against a copy
# of the real ~/.zshrc before shipping it.
FROM_DIR="claude-219"
TO_DIR="claude-220"
BACKUP_DIR="${CC_BACKUP_DIR:-$HOME/.claude/backups}"
STAMP="$(date +%Y%m%d-%H%M%S)"

die() { echo "✗ $*" >&2; exit 1; }
ok()  { echo "✓ $*"; }

[ -f "$ZSHRC" ] || die "no $ZSHRC"

# ── --undo ────────────────────────────────────────────────────────────────────────────────────────
if [ "${1:-}" = "--undo" ]; then
  latest="$(ls -1t "$BACKUP_DIR"/zshrc.cc220-* 2>/dev/null | head -1)"
  [ -n "$latest" ] || die "no backup found under $BACKUP_DIR (zshrc.cc220-*)"
  cp "$latest" "$ZSHRC" || die "restore failed"
  ok "restored $ZSHRC from $latest"
  echo "  → run:  source ~/.zshrc   (or open a new tab)"
  exit 0
fi

# ── pre-flight ────────────────────────────────────────────────────────────────────────────────────
# Fail CLOSED on every precondition. A half-applied edit to the file that starts every shell on this
# machine is far worse than a refusal, so nothing is attempted until all of it checks out.
[ -x "$HOME/.$TO_DIR/node_modules/.bin/claude" ] \
  || die "$HOME/.$TO_DIR/node_modules/.bin/claude missing — install first:
     npm install --prefix ~/.$TO_DIR @anthropic-ai/claude-code@2.1.220"

got="$("$HOME/.$TO_DIR/node_modules/.bin/claude" --version 2>/dev/null | grep -oE '2\.1\.[0-9]+' | head -1)"
[ "$got" = "2.1.220" ] || die "$TO_DIR reports version '${got:-unknown}', expected 2.1.220 — refusing"

pin_line="$(grep -nE '^[[:space:]]*local _bin="\$HOME/\.claude-[0-9]+/' "$ZSHRC" | head -1)"
[ -n "$pin_line" ] || die "no claude() _bin pin found in $ZSHRC — refusing to guess"

n_pins="$(grep -cE '^[[:space:]]*local _bin="\$HOME/\.claude-[0-9]+/' "$ZSHRC")"
[ "$n_pins" -eq 1 ] || die "expected exactly 1 _bin pin, found $n_pins — refusing (resolve by hand)"

already=0
grep -qE "^[[:space:]]*local _bin=\"\\\$HOME/\.$TO_DIR/" "$ZSHRC" && already=1
has_default=0
grep -q '^claude-default() {' "$ZSHRC" && has_default=1

# ── nothing to do? exit BEFORE touching the backup ────────────────────────────────────────────────
# This early-out is a data-safety guard, not a nicety. Found by running this script twice in the
# same second against a copy of the real ~/.zshrc: $STAMP has 1-second granularity, so the second
# run wrote its backup to the SAME path and replaced the pristine copy with the ALREADY-MODIFIED
# file. `--undo` then faithfully restored the modified version — the backup had silently become
# useless at exactly the moment it was needed. Two independent fixes, because either alone leaves a
# window: a no-op run now takes no backup at all, and the filename below can never be reused.
if [ "$already" = 1 ] && [ "$has_default" = 0 ]; then
  ok "both edits already applied — nothing to do (no backup taken, existing backups preserved)"
  echo "  Undo an earlier run:  bash $0 --undo"
  exit 0
fi

# ── backup (never overwrite an existing one) ──────────────────────────────────────────────────────
mkdir -p "$BACKUP_DIR"
BACKUP="$BACKUP_DIR/zshrc.cc220-$STAMP"
if [ -e "$BACKUP" ]; then
  i=2
  while [ -e "$BACKUP_DIR/zshrc.cc220-$STAMP.$i" ]; do i=$((i+1)); done
  BACKUP="$BACKUP_DIR/zshrc.cc220-$STAMP.$i"
fi
cp "$ZSHRC" "$BACKUP" || die "backup failed"
ok "backup: $BACKUP"

tmp="$(mktemp)" || die "mktemp failed"
cp "$ZSHRC" "$tmp"

# ── edit 1: repoint the _bin pin ──────────────────────────────────────────────────────────────────
if [ "$already" = 1 ]; then
  ok "(1) _bin already points at $TO_DIR — nothing to do"
else
  # Anchored on the `local _bin=` assignment so the launcher header's PROSE mentions of older
  # version dirs (~/.claude-170, ~/.claude-161 rollback notes) cannot be rewritten by accident.
  sed -i '' -E "s|^([[:space:]]*local _bin=\"\\\$HOME/)\.$FROM_DIR(/)|\1.$TO_DIR\2|" "$tmp" \
    || die "sed failed on the _bin pin"
  grep -qE "^[[:space:]]*local _bin=\"\\\$HOME/\.$TO_DIR/" "$tmp" \
    || die "repoint did not take — $ZSHRC left untouched"
  ok "(1) _bin repointed $FROM_DIR → $TO_DIR"
fi

# ── edit 2: delete claude-default() + its header comment ──────────────────────────────────────────
if ! grep -q '^claude-default() {' "$tmp"; then
  ok "(2) claude-default() already absent — nothing to do"
else
  python3 - "$tmp" <<'PY' || die "claude-default removal failed"
import sys, re
p = sys.argv[1]
src = open(p).read()
# Delete from the function header to its closing brace at column 0. The body is a fixed, known
# shape (a resume guard, a route check, two launch lines) with no nested column-0 '}', so a
# first-column terminator is an exact match rather than a heuristic.
m = re.search(r'^claude-default\(\) \{\n.*?^\}\n', src, re.S | re.M)
if not m:
    sys.exit("could not delimit claude-default()")
src = src[:m.start()] + src[m.end():]
# Drop the now-orphaned "no auto mode" mention from the alias-line comment block, if present.
src = src.replace(
    "# - `claude`   → default `max` (frontier sessions, or when unclassified)\n",
    "# - `claude`   → default `max` (frontier sessions, or when unclassified)\n")
open(p, 'w').write(src)
PY
  grep -q '^claude-default() {' "$tmp" && die "claude-default() still present — aborting"
  ok "(2) claude-default() removed (0 executable callers; name asserted a false default)"
fi

# ── validate before install ───────────────────────────────────────────────────────────────────────
# zsh -n on the CANDIDATE, never on the live file. A syntax error installed into ~/.zshrc breaks
# every new shell on this machine, which is not a state to discover interactively.
if command -v zsh >/dev/null 2>&1; then
  zsh -n "$tmp" || die "candidate ~/.zshrc FAILS zsh -n — original left untouched ($tmp kept)"
  ok "candidate passes zsh -n"
else
  echo "⚠ zsh not found — skipping syntax validation" >&2
fi

# Prove the resolver agrees with the new pin BEFORE installing it: cc-claude-bin reads this exact
# line, so if it cannot resolve the candidate, every consumer would silently fall to a lower rung.
RESOLVER="$HOME/.claude/bin/cc-claude-bin"
[ -x "$RESOLVER" ] || RESOLVER="${CC_REPO:-$HOME/Development/claude-infrastructure}/bin/cc-claude-bin"
if [ -x "$RESOLVER" ]; then
  got_bin="$(CC_ZSHRC="$tmp" "$RESOLVER" 2>/dev/null)" || got_bin=""
  case "$got_bin" in
    *"/.$TO_DIR/"*) ok "cc-claude-bin resolves the new pin: $got_bin" ;;
    "")            die "cc-claude-bin could not resolve the candidate pin — refusing" ;;
    *)             die "cc-claude-bin resolved '$got_bin', expected a $TO_DIR path — refusing" ;;
  esac
else
  echo "⚠ cc-claude-bin not found — skipping resolver agreement check" >&2
fi

cp "$tmp" "$ZSHRC" || die "install failed — backup at $BACKUP"
rm -f "$tmp"

echo
ok "~/.zshrc updated."
echo "  Next:  source ~/.zshrc     (existing sessions keep their loaded binary via the vnode)"
echo "  Verify: claude --version   → 2.1.220"
echo "  Undo:  bash $0 --undo"
echo "  Rollback the binary only: put .claude-219 back in the _bin line (still installed)."
