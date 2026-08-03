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
#        CC_KITTY_LOGIN_RC · CC_KITTY_SHIM_DIR

set -uo pipefail

REPO="$(cd "$(dirname "$(readlink -f "$0" 2>/dev/null || printf '%s' "$0")")/.." && pwd)"
KCONF_DIR="${CC_KITTY_CONFIG_DIR:-$HOME/.config/kitty}"
BIN_DIR="${CC_KITTY_BIN_DIR:-$HOME/.claude/bin}"

# ── EPHEMERAL-TREE GUARD ─────────────────────────────────────────────────────────────────────────
# REPO above is derived from $0, so this script links the live layer at WHATEVER TREE IT WAS RUN
# FROM. postland-verify runs the corpus (and install.sh, which calls this script) inside a
# throwaway worktree at ~/.claude/autonomy/postland/wt-run-$$ — so a verification run silently
# repointed the operator's LIVE config at a directory that is later deleted.
#
# Measured 2026-08-01: ~/.config/kitty/kitty.conf and ~/.claude/bin/it2-kitty both pointed into
# wt-run-26747. The operator's terminal reverted to kitty's stock defaults with no error anywhere —
# the file on disk in the real checkout was still correct, so every by-content check passed while
# the live layer read a stale 11,776-byte copy. Once that worktree is reaped the links DANGLE and
# kitty starts with no config at all.
#
# The guard is scoped to the dangerous EFFECT (writing the operator's REAL live layer), NOT to
# "am I running from an unusual directory" — a location-keyed refusal would fire on the verifier
# corpus itself, which runs from a throwaway worktree BY CONSTRUCTION and is perfectly legitimate
# so long as it has fixtured its seams. REAL_HOME comes from the passwd DB via ~user expansion, not
# from $HOME, precisely so a hermetic test that fixtures HOME writes to its tmpdir and sails past.
# --check is a read-only probe and stays legal from anywhere; --apply and --undo both MUTATE the
# live layer (--undo would delete the operator's links), so both are guarded.
REAL_HOME="$(eval printf '%s' "~$(id -un)" 2>/dev/null || printf '%s' "$HOME")"
[ "${1:-}" = "--check" ] && REPO_GUARD_SKIP=1 || REPO_GUARD_SKIP=0
[ "$REPO_GUARD_SKIP" = 1 ] || case "$REPO" in
  "$REAL_HOME"/.claude/autonomy/postland/wt-run-*|"$REAL_HOME"/.claude/autonomy/postland/wt-revert-*)
    case "$KCONF_DIR/|$BIN_DIR/" in
      *"$REAL_HOME"/*)
        printf 'kitty-setup: REFUSING to link the live layer from an ephemeral verifier worktree\n' >&2
        printf '  repo   : %s\n' "$REPO" >&2
        printf '  target : %s , %s\n' "$KCONF_DIR" "$BIN_DIR" >&2
        printf '  why    : this tree is deleted after the run; the links would dangle.\n' >&2
        printf '  fix    : deploy from the canonical checkout, or fixture CC_KITTY_CONFIG_DIR\n' >&2
        printf '           and CC_KITTY_BIN_DIR if this is a test.\n' >&2
        exit 3 ;;
    esac ;;
esac
SHELL_RC="${CC_KITTY_SHELL_RC:-$HOME/.zshrc}"
BLOCK_ID="cc-kitty-agent-teams"
# Step 3b writes to the LOGIN rc, which is a DIFFERENT file from SHELL_RC on purpose — see §3b.
LOGIN_RC="${CC_KITTY_LOGIN_RC:-$HOME/.zprofile}"
SHIM_DIR="${CC_KITTY_SHIM_DIR:-$HOME/.claude/shims}"
PATH_BLOCK_ID="cc-it2-login-path"

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
  for f in it2-kitty cc-term kitty-split-cwd.sh; do
    [ -L "$BIN_DIR/$f" ] && { rm -f "$BIN_DIR/$f"; ok "removed $BIN_DIR/$f"; }
  done
  if grep -q "$BLOCK_ID" "$SHELL_RC" 2>/dev/null; then
    cp "$SHELL_RC" "$SHELL_RC.bak-kitty-undo"
    # Delete the whole keyed block, inclusive of its markers.
    sed -i '' "/# >>> $BLOCK_ID >>>/,/# <<< $BLOCK_ID <<</d" "$SHELL_RC"
    ok "removed the $BLOCK_ID block from $SHELL_RC (backup: $SHELL_RC.bak-kitty-undo)"
  fi
  # 3b's two artifacts. The shim dir itself is removed only when EMPTY — `rmdir` refuses a dir
  # holding anything else, so a second tool that later parks a shim here is never collaterally
  # deleted by an undo of this one.
  [ -L "$SHIM_DIR/it2" ] && { rm -f "$SHIM_DIR/it2"; ok "removed $SHIM_DIR/it2"; }
  rmdir "$SHIM_DIR" 2>/dev/null && ok "removed empty $SHIM_DIR"
  if grep -q "$PATH_BLOCK_ID" "$LOGIN_RC" 2>/dev/null; then
    cp "$LOGIN_RC" "$LOGIN_RC.bak-kitty-undo"
    sed -i '' "/# >>> $PATH_BLOCK_ID >>>/,/# <<< $PATH_BLOCK_ID <<</d" "$LOGIN_RC"
    ok "removed the $PATH_BLOCK_ID block from $LOGIN_RC (backup: $LOGIN_RC.bak-kitty-undo)"
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
  # cc-in-kitty answers "is this process genuinely inside a kitty pane?" and is what both halves of
  # the divert consult. install.sh's bin/cc-* glob also deploys it; linking it here too keeps this
  # script's promise of being ONE command, and `ln -sfn` makes the overlap a no-op.
  ln -sfn "$REPO/bin/cc-in-kitty" "$BIN_DIR/cc-in-kitty"
  # kitty.conf's cmd+D / cmd+shift+D bindings name this script as the program they launch, so a
  # missing link is not a degraded split — it is a split that cannot open at all. It lives under
  # $BIN_DIR because the conf resolves it as ${HOME}/.claude/bin/..., which is how the conf stays
  # free of a hardcoded home path (verified: kitty DOES expand ${HOME} in launch argv, 0.48.2).
  ln -sfn "$REPO/bin/kitty-split-cwd.sh" "$BIN_DIR/kitty-split-cwd.sh"
  # NOTE: no separate pane adapter is linked here. bin/cc-pane is the repo's terminal-agnostic
  # seam and install.sh already deploys it; because its iterm2 driver shells out to
  # $HOME/.claude/bin/it2, the divert above makes cc-pane work on kitty with no kitty driver.
  # An earlier draft linked a second adapter here and would have dangled on a fresh clone.
fi
grep -q "TERMINAL DISPATCH" "$BIN_DIR/it2" 2>/dev/null \
  && ok "$BIN_DIR/it2 carries the kitty divert" || no "$BIN_DIR/it2 has no kitty divert"
[ -x "$BIN_DIR/it2-kitty" ] && ok "it2-kitty deployed" || no "it2-kitty missing at $BIN_DIR"
# -x follows the symlink, so this fails on a DANGLING link as well as on absence — the two ways
# cmd+D breaks. Reported here rather than under step 1 because the link, not the conf, is the artifact.
[ -x "$BIN_DIR/kitty-split-cwd.sh" ] && ok "kitty-split-cwd.sh deployed (cmd+D lands in the main checkout)" \
                                     || no "kitty-split-cwd.sh missing at $BIN_DIR — cmd+D cannot open a split"
# The wrapper is a COPY (refreshed only by this script or install.sh) while it2-kitty is a SYMLINK
# that tracks the repo live, so the two halves CAN skew. Assert the copy is a version that verifies
# the terminal before diverting — a stale copy still diverts on $KITTY_WINDOW_ID alone, which is
# inherited by every iTerm2 pane launched from kitty and takes Agent Teams down at USE time.
[ -x "$BIN_DIR/cc-in-kitty" ] && ok "cc-in-kitty deployed (terminal identity by ancestry)" \
                              || no "cc-in-kitty missing at $BIN_DIR — the divert cannot verify the terminal"
grep -q "cc-in-kitty" "$BIN_DIR/it2" 2>/dev/null \
  && ok "$BIN_DIR/it2 verifies the terminal before diverting" \
  || no "$BIN_DIR/it2 is a STALE COPY that diverts on \$KITTY_WINDOW_ID alone — re-run --apply"
# A DANGLING symlink is the failure this checks for, not mere absence: -x follows the link, so a
# link pointing at a file that no longer exists reports missing rather than passing on the name.
if [ -e "$BIN_DIR/cc-term" ] || [ -L "$BIN_DIR/cc-term" ]; then
  [ -x "$BIN_DIR/cc-term" ] || no "$BIN_DIR/cc-term is a DANGLING symlink — remove it (superseded by cc-pane)"
fi

# ── 3. the env var Claude Code's iTerm2 check reads ──────────────────────────────────────────────
hdr "3. pane identity for Claude Code"
# Write $HOME back as a literal so the block survives a HOME that differs at shell-startup time.
CC_IN_KITTY_RC="${BIN_DIR/#$HOME/\$HOME}/cc-in-kitty"
read -r -d '' RC_BLOCK <<EOF
# >>> $BLOCK_ID >>>
# Claude Code gates its iTerm2 pane backend on an ENV VAR (it never handshakes with iTerm2):
#   TERM_PROGRAM==="iTerm.app" || !!ITERM_SESSION_ID || terminal==="iTerm.app"
# and derives the leader pane id as ITERM_SESSION_ID.slice(indexOf(":")+1) — so the COLON IS
# REQUIRED; without one it returns null and silently splits from whatever pane is active.
# ~/.claude/bin/it2 then translates every backend call into \`kitty @\`.
#
# The override is UNCONDITIONAL inside kitty. It used to be guarded by \`[ -z "\$ITERM_SESSION_ID" ]\`,
# which reads as conservative and is in fact the bug: a kitty pane launched from iTerm2 INHERITS
# that variable, so the guard preserved a stale iTerm2 pane UUID, Claude Code sliced it out as the
# leader pane, and handed it to a kitty translator that cannot map it — every teammate spawn died
# with "not a kitty window id" while the backend probe stayed green. Inside kitty, KITTY_WINDOW_ID
# is the only authority on which pane this is.
#
# cc-in-kitty is what decides "inside kitty", by ANCESTRY rather than by \$KITTY_WINDOW_ID — which
# iTerm2 also inherits, permanently, when it is launched from a kitty pane. If it is missing we
# change nothing: a WRONG ITERM_SESSION_ID is worse than none, since iTerm2 wrote a correct one.
if [ -n "\${KITTY_WINDOW_ID:-}" ] && [ -x "$CC_IN_KITTY_RC" ] && "$CC_IN_KITTY_RC"; then
  export ITERM_SESSION_ID="w0t0p0:\$KITTY_WINDOW_ID"
fi
# <<< $BLOCK_ID <<<
EOF
if [ "$MODE" = apply ]; then
  if ! grep -q "$BLOCK_ID" "$SHELL_RC" 2>/dev/null; then
    cp "$SHELL_RC" "$SHELL_RC.bak-kitty-$(date +%Y%m%d%H%M%S)" 2>/dev/null
    printf '\n%s\n' "$RC_BLOCK" >> "$SHELL_RC"
  elif ! grep -q "cc-in-kitty" "$SHELL_RC" 2>/dev/null; then
    # UPGRADE IN PLACE. Idempotence by "block already present" is not enough once the block's
    # CONTENT is the defect: every existing ~/.zshrc carries the stale-guard version, and skipping
    # on the marker alone would mean this fix never reaches a single machine that already ran the
    # old setup. Splice between the markers rather than appending a second block — two blocks would
    # both run, and the survivor would depend on their order.
    cp "$SHELL_RC" "$SHELL_RC.bak-kitty-$(date +%Y%m%d%H%M%S)" 2>/dev/null
    RC_BLOCK="$RC_BLOCK" python3 - "$SHELL_RC" "$BLOCK_ID" <<'PY'
import os, re, sys
path, block_id = sys.argv[1], sys.argv[2]
src = open(path).read()
pat = re.compile(r"^# >>> %s >>>\n.*?^# <<< %s <<<\n?" % (re.escape(block_id), re.escape(block_id)),
                 re.S | re.M)
new, n = pat.subn(lambda _: os.environ["RC_BLOCK"] + "\n", src)
if n != 1:
    print("   could not splice the %s block (%d matches) — left untouched" % (block_id, n))
    sys.exit(0)
open(path, "w").write(new)
PY
  fi
fi
if ! grep -q "$BLOCK_ID" "$SHELL_RC" 2>/dev/null; then
  no "$SHELL_RC has no $BLOCK_ID block"
elif ! grep -q "cc-in-kitty" "$SHELL_RC" 2>/dev/null; then
  # The stale block is WORSE than no block on a kitty pane opened from iTerm2: it leaves the
  # inherited iTerm2 UUID in place and the failure surfaces only at spawn time.
  no "$SHELL_RC has the STALE $BLOCK_ID block (keeps an inherited iTerm2 id) — re-run --apply"
else
  ok "$SHELL_RC exports ITERM_SESSION_ID inside kitty (verified by ancestry)"
fi

# ── 3b. login-shell PATH precedence — the step without which NONE of step 2 runs ─────────────────
# Steps 1-3 can all be green while Agent Teams still fails with
#   'teammateMode is set to "iterm2" but the it2 CLI is not reachable'
# because Claude Code never resolves `it2` the way your prompt does. Read out of the live 2.1.219
# binary (function Uor), the gate is:
#
#   r = $SHELL -lc "command -v it2"        ← LOGIN shell, non-interactive, 2s timeout
#       ...last non-empty line, .at(-1)
#   o = r || "it2"
#   run `<o> session list`                 ← A DEEP PROBE. Resolution alone is NOT the contract;
#                                            the process must EXIT 0. (bin/it2-kitty's header
#                                            documented resolution-only — that was stale.)
#   on success: the RESOLVED PATH is cached and used for every later it2 call.
#
# Two consequences, both load-bearing:
#
#   (a) `zsh -lc` is login-but-NOT-interactive, so it reads .zshenv/.zprofile and NEVER .zshrc.
#       ~/.claude/bin is added to PATH only in .zshrc (line ~267), while .zprofile prepends
#       ~/.local/bin — which on this box holds a uv-installed REAL it2. So the login shell resolved
#       /Users/chrisren/.local/bin/it2, the real iTerm2 client, which inside kitty fails its probe
#       with `Not running inside iTerm2 or Python API not enabled` (rc=2) and takes Agent Teams
#       down with it. Measured 2026-07-31: real it2 `session list` rc=2, our wrapper rc=0.
#   (b) Because the resolved path is CACHED, losing this race does not merely fail on kitty — on
#       iTerm2 it silently BYPASSES bin/it2-wrapper, forfeiting all three of its interceptions
#       (never-prompt profile, force=True close, and the 30s process bound whose absence produced
#       the 2026-07-25 fleet-wide deadlock). This step is therefore a fix for BOTH terminals.
#
# WHY A ONE-ENTRY SHIM DIR AND NOT `PATH=$HOME/.claude/bin:$PATH` IN .zprofile.
# The broad fix would make the login PATH agree with the interactive one, which is tempting — but
# ~/.claude/bin also contains `bats` (a symlink to cc-bats, the QoS chokepoint). Prepending the
# whole dir would silently change which `bats` every login-shell gate runs, moving gate processes
# into a taskpolicy band as a side effect of an unrelated terminal fix. cc-bats defends itself
# against self-shadowing, so it would not fork-bomb — but a blast radius wider than the defect is
# how an add-on takes down more than itself. Exactly one name needs to change, so exactly one name
# does. Add a second symlink here only when a second name is PROVEN to need it.
hdr "3b. login-shell PATH precedence (the it2 Claude Code actually runs)"
if [ "$MODE" = apply ]; then
  mkdir -p "$SHIM_DIR"
  ln -sfn "$BIN_DIR/it2" "$SHIM_DIR/it2"
  if ! grep -q "$PATH_BLOCK_ID" "$LOGIN_RC" 2>/dev/null; then
    [ -e "$LOGIN_RC" ] && cp "$LOGIN_RC" "$LOGIN_RC.bak-kitty-$(date +%Y%m%d%H%M%S)"
    cat >> "$LOGIN_RC" <<EOF

# >>> $PATH_BLOCK_ID >>>
# Claude Code resolves the it2 it will drive with \`\$SHELL -lc "command -v it2"\` — a login,
# NON-interactive shell, which never reads .zshrc. Without this line that lookup finds whichever
# it2 an earlier PATH entry owns (here: ~/.local/bin, a uv tool), NOT the wrapper, and Agent Teams
# dies with "the it2 CLI is not reachable" on kitty / silently loses the wrapper's interceptions on
# iTerm2. Must stay AFTER any other PATH prepend in this file to actually win.
export PATH="$SHIM_DIR:\$PATH"
# <<< $PATH_BLOCK_ID <<<
EOF
  fi
fi
[ "$(readlink "$SHIM_DIR/it2" 2>/dev/null)" = "$BIN_DIR/it2" ] \
  && ok "$SHIM_DIR/it2 -> $BIN_DIR/it2" || no "$SHIM_DIR/it2 does not point at the wrapper"
grep -q "$PATH_BLOCK_ID" "$LOGIN_RC" 2>/dev/null \
  && ok "$LOGIN_RC prepends $SHIM_DIR" || no "$LOGIN_RC has no $PATH_BLOCK_ID block"

# The un-fakeable assertion: replay Claude Code's OWN gate rather than checking that files exist.
# A file-existence check would have passed all through the outage this step fixes.
probe_shell="${SHELL:-/bin/zsh}"
probe_r=$("$probe_shell" -lc 'command -v it2' 2>/dev/null | tr -d '\r' | awk 'NF' | tail -1)
probe_o="${probe_r:-it2}"
case "$probe_r" in
  "$SHIM_DIR/it2"|"$BIN_DIR/it2") ok "login-shell it2 resolves to the wrapper ($probe_r)" ;;
  "") no "login-shell 'command -v it2' found NOTHING — Claude Code would fall back to bare 'it2'" ;;
  *)  no "login-shell it2 resolves to $probe_r — NOT the wrapper; Claude Code will drive that instead" ;;
esac
if probe_out=$("$probe_o" session list 2>&1) && [ -n "$probe_out" ]; then
  ok "'$(basename "$probe_o") session list' exits 0 ($(printf '%s' "$probe_out" | grep -c .) panes) — Uor() would pass"
else
  no "'$probe_o session list' FAILED — Uor() returns false and teammateMode=iterm2 will throw: ${probe_out%%$'\n'*}"
fi

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
#
# THIS SECTION EXERCISES THE USE PATH, NOT THE PROBE PATH. `session list` returning rc 0 is what
# Claude Code caches availability from, and it is ALSO what stayed green through the whole 2026-07-31
# outage while every single spawn failed. A checker that stops at the probe reproduces the defect it
# is supposed to catch, so when we are genuinely in kitty this does a real split → id → close round
# trip. Seam: CC_KITTY_NO_SPAWN_CHECK=1 skips it.
hdr "5. live state (needs a kitty RESTART to become true)"
# THE VERDICT IS THREE-VALUED AND THIS READS IT AS SUCH. `cc-in-kitty && …` collapses rc 1 (kitty is
# genuinely not an ancestor) with rc 2 and with the file being ABSENT — and absence is the normal
# state of a machine running --check BEFORE --apply. Collapsed, the else-branch printed
# "KITTY_* present but INHERITED — this is not a kitty pane" inside a genuine kitty pane, i.e. the
# checker asserted the wrong terminal because its verifier was missing. That is the same shape as
# the outage this whole file exists to fix: a confident sentence built on an unasked question. The
# deployed copy stays the authority (step 5 judges the LIVE layer, not the repo) — its absence is
# reported as UNVERIFIABLE, never as a terminal.
if [ -x "$BIN_DIR/cc-in-kitty" ]; then
  "$BIN_DIR/cc-in-kitty"; term_rc=$?
else
  term_rc=127
fi
if [ "$term_rc" = 0 ]; then
  if [ -n "${KITTY_LISTEN_ON:-}" ]; then
    ok "control socket live: $KITTY_LISTEN_ON"
  else
    no "INERT — this kitty has no control socket; it started before the config. RESTART kitty."
  fi
  # The id must MAP to this window, not merely exist. A non-empty ITERM_SESSION_ID inherited from an
  # iTerm2 ancestor passes "is set" and then fails every spawn — which is how the 2026-07-31 outage
  # stayed invisible to a checker that only asked whether the variable was populated.
  #
  # These are the ASSERTION that step 3's block took effect in THIS pane, so they must read the BARE
  # variable. Adding the `${CC_PANE_ID:-…}` fallback the ratchet normally wants would make the check
  # report green whenever CC_PANE_ID happened to be set by anything else — it would stop measuring
  # the thing it exists to measure. Each bare read therefore carries the per-line marker; the ratchet
  # (tests/cc-pane.bats) filters by LINE, deliberately, so a genuine bare read added here later is
  # still caught.
  want="w0t0p0:$KITTY_WINDOW_ID"
  if [ "${ITERM_SESSION_ID:-}" = "$want" ]; then  # cc-pane-id-lint:allow
    ok "ITERM_SESSION_ID=$ITERM_SESSION_ID (maps to this kitty window)"
  elif [ -n "${ITERM_SESSION_ID:-}" ]; then  # cc-pane-id-lint:allow
    no "ITERM_SESSION_ID=$ITERM_SESSION_ID does NOT map to kitty window $KITTY_WINDOW_ID (want $want) — inherited from an iTerm2 ancestor; open a NEW shell after --apply"
  else
    no "ITERM_SESSION_ID unset in this pane (new shell needed)"
  fi

  if [ -n "${CC_KITTY_NO_SPAWN_CHECK:-}" ]; then
    info "spawn round-trip skipped (CC_KITTY_NO_SPAWN_CHECK set)"
  elif [ ! -x "$BIN_DIR/it2" ]; then
    no "no $BIN_DIR/it2 to round-trip through"
  elif [ "${ITERM_SESSION_ID:-}" != "$want" ]; then  # cc-pane-id-lint:allow
    info "spawn round-trip skipped — the leader id above is wrong, so it would prove nothing"
  else
    # Exactly what ITermBackend does for the first teammate: slice the id at the colon, split -v.
    split_out="$("$BIN_DIR/it2" session split -v -s "${ITERM_SESSION_ID##*:}" 2>&1)"
    new_pane=""
    case "$split_out" in *"Created new pane: "*) new_pane="${split_out##*Created new pane: }" ;; esac
    new_pane="${new_pane%%[!0-9]*}"
    if [ -z "$new_pane" ]; then
      no "spawn round-trip FAILED — the state where 'session list' is green and every teammate spawn dies: $split_out"
    elif close_out="$("$BIN_DIR/it2" session close -f -s "$new_pane" 2>&1)"; then
      ok "spawn round-trip: split → pane $new_pane → closed (Agent Teams can really spawn)"
    else
      no "spawn round-trip: pane $new_pane was created but NOT closed — close it by hand: $close_out"
    fi
  fi

  # ── THE DAEMON-ENVIRONMENT PROBE ────────────────────────────────────────────────────────────────
  # Every check above runs with the OPERATOR's PATH, and that is exactly why they all stayed green
  # through the 2026-08-01 outage: `bin/it2-kitty` resolved the kitty binary by BARE NAME, so it
  # worked from a shell (Homebrew on PATH) and did not exist for hooks and launchd jobs, which run
  # with `/usr/bin:/bin:/usr/sbin:/sbin`. Those are precisely the callers that close teammate panes
  # — teammate-auto-shutdown, cc-teardown, cc-reaper, handoff-fire — so the whole auto-close path was
  # dead while this script reported a healthy kitty. A live teammate pane sat open for 3h09m with its
  # 653 MB claude.exe resident.
  #
  # So the probe REPLAYS THE CALLER'S ENVIRONMENT rather than the operator's: same binary, same verb,
  # PATH stripped to what launchd actually hands a job. Checking that files exist is what stayed green.
  #
  # cc-pane-id-lint:allow — the `${ITERM_SESSION_ID:-}` below is NOT the bare pane-id read that
  # tests/cc-pane.bats forbids. That ratchet exists to stop code ADDRESSING a pane by reading its own
  # ITERM_SESSION_ID without the CC_PANE_ID fallback. Here the value is being PROPAGATED into an
  # `env -i` child, and propagating it verbatim is the entire point: the probe's contract (three lines
  # up) is to replay the caller's environment exactly. Substituting CC_PANE_ID would make the probe
  # test an environment no caller ever has — the precise defect it was written to catch. Marked rather
  # than rewritten, because the ratchet is right about the pattern and wrong only about this instance.
  if [ ! -x "$BIN_DIR/it2" ]; then
    :   # already reported above
  elif dp_out="$(env -i HOME="$HOME" PATH=/usr/bin:/bin:/usr/sbin:/sbin \
        KITTY_WINDOW_ID="${KITTY_WINDOW_ID:-}" KITTY_PID="${KITTY_PID:-}" \
        KITTY_LISTEN_ON="${KITTY_LISTEN_ON:-}" ITERM_SESSION_ID="${ITERM_SESSION_ID:-}" `# cc-pane-id-lint:allow — propagation, not a pane-id read; see the block above` \
        "$BIN_DIR/it2" session list 2>&1)"; then
    ok "daemon-PATH probe: 'session list' works with no Homebrew on PATH ($(printf '%s' "$dp_out" | grep -c .) panes) — hooks and launchd can drive kitty"
  else
    no "daemon-PATH probe FAILED — hooks and launchd cannot drive kitty, so NO teammate pane will ever auto-close (this is invisible to every other check here): $dp_out"
  fi
elif [ "$term_rc" = 1 ] && [ -n "${KITTY_WINDOW_ID:-}" ]; then
  # The polluted case, and the reason this branch is not simply "not in kitty": the vars are all
  # here, so the OLD check called this a live kitty pane and every downstream tool agreed. Reaching
  # it requires a DEFINITIVE rc 1 from a deployed verifier — an inference, not a default.
  info "KITTY_* present but INHERITED — this is not a kitty pane:"
  # `--why` exits NON-ZERO by design: it is a predicate that also explains itself. A `|| fallback`
  # here therefore fires on a SUCCESSFUL diagnostic and prints both, which it did — capture first,
  # then judge on emptiness (memory: claimed-outcome-vs-checked-outcome).
  why="$("$BIN_DIR/cc-in-kitty" --why 2>/dev/null)"
  info "  ${why:-cc-in-kitty produced no reason}"
  info "  the it2 divert is correctly INERT here; iTerm2 keeps its own pane identity"
elif [ -n "${KITTY_WINDOW_ID:-}" ]; then
  # rc 2 (walk failed) or 127 (not deployed). Both mean the terminal is UNKNOWN, which is a third
  # state and not a quieter way of saying iTerm2. It is also why nothing below ran: the spawn
  # round-trip is the one check that proves the USE path, and it is not skipped for a green reason.
  if [ "$term_rc" = 127 ]; then
    no "terminal UNVERIFIABLE — $BIN_DIR/cc-in-kitty is not deployed, so live state cannot be judged (run --apply)"
  else
    why="$("$BIN_DIR/cc-in-kitty" --why 2>/dev/null)"
    no "terminal UNVERIFIABLE (cc-in-kitty rc $term_rc): ${why:-no reason given}"
  fi
  info "  the spawn round-trip did NOT run — this section proved nothing either way"
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
