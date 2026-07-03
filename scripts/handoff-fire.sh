#!/usr/bin/env bash
# handoff-fire.sh — autonomously launch a Claude Code continuation session in iTerm2.
#
# Generalizes the proven /tmp/fire.sh pattern (2026-07-02 parallel-track launch): open an
# interactive iTerm2 surface (tab / split pane / window) and TYPE the launch command into it via
# osascript `write text`, because the per-account launchers (claude-next, claude-next2/3/4,
# claude-fable*) are zsh FUNCTIONS/ALIASES that only resolve in an interactive shell.
#
#   handoff-fire.sh --prompt-file /tmp/fire-<slug>.txt [options]
#
# Options:
#   --prompt-file F     REQUIRED. File whose content is auto-submitted as the session's first
#                       message via `launcher "$(cat F)"`. Content arrives VERBATIM — command
#                       substitution output is never re-expanded (only trailing newlines strip).
#   --account A         next|next2|next3|next4|auto (default auto). auto = static hint order
#                       next2>next3>next4>next, re-ranked ascending by trailing-5h transcript
#                       activity per config dir (the free draw-proxy; corrects a stale hint).
#   --launcher L        Explicit launcher name (e.g. claude-fable3). Overrides --account/--model
#                       launcher composition; still gets --effort/--model/--extra args appended.
#   --model M           opus|claude-opus-4-8 (launcher default) | fable|claude-fable-5 | other.
#                       fable → claude-fableN launcher (the LAUNCHER prints its ~2× cost warning;
#                       high-effort default; this script warns if the frontier window is closed);
#                       other non-default → appended `--model M` (last-wins).
#   --effort E          low|medium|high|xhigh|max → appended `--effort E` (last-wins over the
#                       launcher-injected default: claude-next=max, claude-fable=high).
#   --cwd PATH          Launch in an EXISTING directory (worktree, repo, or anywhere).
#   --worktree BRANCH   Create <wtroot>/BRANCH off --base serially HERE (race-safe), copy
#                       .env.local, then in-surface: CI=true pnpm install && launch. (fire.sh
#                       pattern: the slow install overlaps across surfaces, the racy
#                       `git worktree add` stays serial in the spawner.)
#   --repo PATH         Repo root for --worktree (default $HOME/Development/reso-management-app).
#   --wtroot PATH       Worktree parent dir (default $HOME/Development/.worktrees).
#   --base REF          Base ref for --worktree (default origin/main; fetched first).
#   --in-place          Prefix CLAUDE_ISOLATION_SKIP=1 (launch in cwd even at the reso primary
#                       root, where claude-next otherwise auto-creates a fresh worktree).
#   --split-right       DEFAULT. Split the CURRENT pane, new pane to the side — the ⌘D
#                       experience: same view, same profile. (AppleScript "split vertically")
#   --split-down        Split the current pane, new pane below (⌘⇧D). ("split horizontally")
#   --tab               New tab in current window (background — not in the current view).
#   --window            New iTerm2 window.
#   --probe             Liveness-probe the account headlessly before firing (haiku, or fable-5
#                       when --model fable). auto: walk the ranked list to the first passing
#                       account. Explicit account: hard-fail with the rejection class.
#   --extra "ARGS"      Extra CLI args typed before the prompt (e.g. --extra "--permission-mode plan").
#   --dry-run           Print the ranked accounts + composed command + surface; execute nothing.
#
# Neither --cwd nor --worktree: the launcher self-routes (at the reso PRIMARY root
# _cc_route_check auto-creates a fresh cc-<ts> worktree; inside an existing worktree or any
# non-reso dir it launches in place).
set -euo pipefail

# Probe binary — MUST match the path claude-next execs in ~/.zshrc (the version-bump procedure
# there repoints two path refs; repoint this one in the same edit or the probe tests a stale build).
BIN="$HOME/.claude-183/node_modules/.bin/claude"
DEFAULT_REPO="$HOME/Development/reso-management-app"
MODEL_CONFIG="$HOME/.claude/model-config.yaml"

PROMPT_FILE="" ACCOUNT="auto" LAUNCHER="" MODEL="" EFFORT="" CWD="" WORKTREE=""
REPO="$DEFAULT_REPO" WTROOT="$HOME/Development/.worktrees" BASE="origin/main"
SURFACE="split-right" PROBE=0 DRY=0 IN_PLACE=0 EXTRA=""

# Print the header comment up to (excluding) the first non-comment sentinel — growth-proof range.
usage() { sed -n '2,/^set -euo pipefail/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

EXPLICIT_LAUNCHER=0
while [ $# -gt 0 ]; do case "$1" in
  --prompt-file) PROMPT_FILE="${2:?--prompt-file needs a value}"; shift 2 ;;
  --account)     ACCOUNT="${2:?--account needs a value}"; shift 2 ;;
  --launcher)    LAUNCHER="${2:?--launcher needs a value}"; EXPLICIT_LAUNCHER=1; shift 2 ;;
  --model)       MODEL="${2:?--model needs a value}"; shift 2 ;;
  --effort)      EFFORT="${2:?--effort needs a value}"; shift 2 ;;
  --cwd)         CWD="${2:?--cwd needs a value}"; shift 2 ;;
  --worktree)    WORKTREE="${2:?--worktree needs a value}"; shift 2 ;;
  --repo)        REPO="${2:?--repo needs a value}"; shift 2 ;;
  --wtroot)      WTROOT="${2:?--wtroot needs a value}"; shift 2 ;;
  --base)        BASE="${2:?--base needs a value}"; shift 2 ;;
  --in-place)    IN_PLACE=1; shift ;;
  --tab)         SURFACE="tab"; shift ;;
  --split-right) SURFACE="split-right"; shift ;;
  --split-down)  SURFACE="split-down"; shift ;;
  --window)      SURFACE="window"; shift ;;
  --probe)       PROBE=1; shift ;;
  --extra)       EXTRA="${2:?--extra needs a value}"; shift 2 ;;
  --dry-run)     DRY=1; shift ;;
  -h|--help)     usage ;;
  *) echo "!! unknown arg: $1" >&2; usage 1 ;;
esac; done

[ -n "$PROMPT_FILE" ] || { echo "!! --prompt-file is required" >&2; usage 1; }
[ -f "$PROMPT_FILE" ] || { echo "!! missing prompt file: $PROMPT_FILE" >&2; exit 1; }
[ -n "$CWD" ] && [ -n "$WORKTREE" ] && { echo "!! --cwd and --worktree are mutually exclusive" >&2; exit 1; }
if [ -n "$WORKTREE" ] && ! git check-ref-format --branch "$WORKTREE" >/dev/null 2>&1; then
  echo "!! invalid branch name for --worktree: $WORKTREE" >&2; exit 1
fi

# ---- model normalization -------------------------------------------------------------------
case "$MODEL" in
  fable) MODEL="claude-fable-5" ;;
  opus)  MODEL="claude-opus-4-8" ;;
esac

# ---- account maps + activity proxy ---------------------------------------------------------
cfg_dir() { case "$1" in
  next)  echo "$HOME/.claude-next" ;;
  next2) echo "$HOME/.claude-secondary" ;;
  next3) echo "$HOME/.claude-tertiary" ;;
  next4) echo "$HOME/.claude-quaternary" ;;
  *) return 1 ;; esac; }

# Account 1 (.claude-next) mirrors projects/ back into ~/.claude — read activity there.
proj_dir() { case "$1" in next) echo "$HOME/.claude/projects" ;; *) echo "$(cfg_dir "$1")/projects" ;; esac; }

activity() { find "$(proj_dir "$1")" -name '*.jsonl' -mmin -300 2>/dev/null | wc -l | tr -d ' '; }

# Static hint order (favor next2, spread, next1 LAST — out_of_credits), re-ranked ascending by
# live 5h activity; tie-break = the explicit hint-index key (-k2,2n). Emits "account count" lines
# so callers reuse the counts without re-running the find traversals.
ranked_accounts() {
  local i=0 a
  for a in next2 next3 next4 next; do
    printf '%s %s %s\n' "$(activity "$a")" "$i" "$a"; i=$((i+1))
  done | sort -s -k1,1n -k2,2n | awk '{print $3, $1}'
}

launcher_for() { # $1=account — compose launcher name from account + model
  local suffix=""
  case "$1" in next2) suffix="2" ;; next3) suffix="3" ;; next4) suffix="4" ;; esac
  if [ "$MODEL" = "claude-fable-5" ]; then echo "claude-fable${suffix}"; else echo "claude-next${suffix}"; fi
}

# ---- liveness probe (headless, same binary the launchers exec) ------------------------------
# One probe per decision; writes a tiny session into the account's projects dir (cwd /tmp).
# perl alarm survives exec → SIGALRM kills a hung probe (macOS has no GNU timeout).
probe_account() { # $1=account → 0 pass; prints rejection class on fail
  local dir out probe_model="claude-haiku-4-5"
  [ "$MODEL" = "claude-fable-5" ] && probe_model="claude-fable-5"
  dir="$(cfg_dir "$1")"
  if out="$(cd /tmp && CLAUDE_CONFIG_DIR="$dir" DISABLE_AUTOUPDATER=1 \
      perl -e 'alarm 90; exec @ARGV' "$BIN" -p 'Reply with exactly: ok' \
      --model "$probe_model" --max-turns 1 --output-format json 2>&1)" \
     && printf '%s' "$out" | grep -q '"is_error":false'; then
    return 0
  fi
  case "$out" in
    *"usage limit"*)                    echo "rate-limited" ;;
    *"may not exist"*|*"have access"*)  echo "model-unavailable ($probe_model)" ;;
    *"login"*|*"authent"*|*"OAuth"*)    echo "auth-expired (needs /login)" ;;
    *)                                  echo "unknown: $(printf '%s' "$out" | head -c 200)" ;;
  esac
  return 1
}

# ---- pick the account ------------------------------------------------------------------------
CHOSEN="" RANKED="" NAMES="" reason=""
if [ -n "$LAUNCHER" ]; then
  CHOSEN="(explicit launcher)"
  # (dry-run prints the same notice in its readout — don't say it twice)
  [ "$PROBE" = 1 ] && [ "$DRY" = 0 ] && echo "⚠ --probe skipped: explicit --launcher gives no account to probe (use --account instead)" >&2
elif [ "$ACCOUNT" != "auto" ]; then
  cfg_dir "$ACCOUNT" >/dev/null || { echo "!! unknown account: $ACCOUNT (next|next2|next3|next4|auto)" >&2; exit 1; }
  CHOSEN="$ACCOUNT"
  if [ "$PROBE" = 1 ] && [ "$DRY" = 0 ]; then
    reason="$(probe_account "$ACCOUNT")" || { echo "✗ probe FAILED on $ACCOUNT: $reason" >&2; exit 1; }
  fi
  LAUNCHER="$(launcher_for "$ACCOUNT")"
else
  RANKED="$(ranked_accounts)"                                  # "account count" per line, sorted
  NAMES="$(printf '%s\n' "$RANKED" | awk '{print $1}')"
  if [ "$PROBE" = 1 ] && [ "$DRY" = 0 ]; then
    for a in $NAMES; do
      if reason="$(probe_account "$a")"; then CHOSEN="$a"; break
      else echo "→ probe rejected $a: $reason (walking on)" >&2; fi
    done
    [ -n "$CHOSEN" ] || { echo "✗ all 4 accounts failed the probe — stop and report, don't queue." >&2; exit 1; }
  else
    CHOSEN="$(printf '%s\n' "$NAMES" | head -1)"
  fi
  LAUNCHER="$(launcher_for "$CHOSEN")"
fi

# Fable is window-gated: warn (not block — the hard gate is the API rejection) when the SSOT says
# the frontier window is closed. Gate on the EFFECTIVE launcher family or an explicit fable model.
case "$LAUNCHER" in claude-fable*) FABLE_EFFECTIVE=1 ;; *) FABLE_EFFECTIVE=0 ;; esac
[ "$MODEL" = "claude-fable-5" ] && FABLE_EFFECTIVE=1
if [ "$FABLE_EFFECTIVE" = 1 ] && [ -f "$MODEL_CONFIG" ]; then
  active="$(awk '/^frontier_access:/{f=1} f && /active:/{print $2; exit}' "$MODEL_CONFIG")"
  [ "$active" = "true" ] || echo "⚠️  frontier_access.active != true in $MODEL_CONFIG — Fable will likely reject ('model may not exist or you may not have access'). Use --probe, or flip the SSOT first." >&2
fi

# ---- compose the typed command ---------------------------------------------------------------
ARGS=""
[ -n "$EFFORT" ] && ARGS="$ARGS --effort $EFFORT"
if [ -n "$MODEL" ]; then
  if [ "$EXPLICIT_LAUNCHER" = 1 ]; then
    # Explicit launcher may carry a different model family — always append (last-wins, harmless
    # when redundant) so `--launcher claude-fable3 --model opus` really runs Opus.
    ARGS="$ARGS --model $MODEL"
  elif [ "$MODEL" != "claude-fable-5" ] && [ "$MODEL" != "claude-opus-4-8" ]; then
    ARGS="$ARGS --model $MODEL"   # non-default model on a claude-nextN launcher
  fi
fi
[ -n "$EXTRA" ] && ARGS="$ARGS $EXTRA"

PREFIX=""
[ "$IN_PLACE" = 1 ] && PREFIX="CLAUDE_ISOLATION_SKIP=1 "

# Paths are typed into an interactive zsh line — %q-quote them so spaces/metachars can't split
# or execute (conventional slugs pass through unchanged).
QP="$(printf %q "$PROMPT_FILE")"
if [ -n "$WORKTREE" ]; then
  WT="$WTROOT/$WORKTREE"
  if [ "$DRY" = 0 ] && [ ! -d "$WT" ]; then
    git -C "$REPO" fetch origin -q || echo "⚠ fetch failed — basing off last-fetched $BASE" >&2
    ( cd "$REPO" && git worktree add "$WT" -b "$WORKTREE" "$BASE" >/dev/null )
    [ -f "$REPO/.env.local" ] && { cp "$REPO/.env.local" "$WT/.env.local"; chmod 600 "$WT/.env.local"; }
  fi
  CMD="cd $(printf %q "$WT") && CI=true pnpm install --frozen-lockfile && ${PREFIX}${LAUNCHER}${ARGS} \"\$(cat $QP)\""
elif [ -n "$CWD" ]; then
  CMD="cd $(printf %q "$CWD") && ${PREFIX}${LAUNCHER}${ARGS} \"\$(cat $QP)\""
else
  # Land in the repo root and let the launcher self-route (_cc_route_check auto-creates a fresh
  # cc-<ts> worktree there; --in-place launches in the root itself).
  CMD="cd $(printf %q "$REPO") && ${PREFIX}${LAUNCHER}${ARGS} \"\$(cat $QP)\""
fi

# ---- spawn the surface -----------------------------------------------------------------------
# Escaping (load-bearing, in this order): backslashes first, then double-quotes.
# The typed line stays short + single-line; the multi-line prompt travels via $(cat file).
ESC="$(printf '%s' "$CMD" | sed 's/\\/\\\\/g; s/"/\\"/g')"

spawn() { case "$SURFACE" in
  tab)  # fire.sh recipe + zero-window fallback (fresh window IS the surface then)
    osascript -e 'tell application "iTerm2"' \
              -e 'activate' \
              -e 'if (count of windows) = 0 then' \
              -e 'create window with default profile' \
              -e 'else' \
              -e 'tell current window to create tab with default profile' \
              -e 'end if' \
              -e "tell current session of current window to write text \"$ESC\"" \
              -e 'end tell' >/dev/null ;;
  split-right|split-down)
    local dir="vertically"; [ "$SURFACE" = "split-down" ] && dir="horizontally"
    # `with same profile` = ⌘D semantics (inherit the pane you split from, not the default).
    # MUST capture the returned session — after a split, `current session` is still the OLD pane.
    # Zero windows → nothing to split; fall back to a fresh window.
    osascript -e 'tell application "iTerm2"' \
              -e 'activate' \
              -e 'if (count of windows) = 0 then' \
              -e 'create window with default profile' \
              -e "tell current session of current window to write text \"$ESC\"" \
              -e 'else' \
              -e 'tell current session of current window' \
              -e "set newSess to split ${dir} with same profile" \
              -e 'end tell' \
              -e "tell newSess to write text \"$ESC\"" \
              -e 'end if' \
              -e 'end tell' >/dev/null ;;
  window)
    osascript -e 'tell application "iTerm2"' \
              -e 'activate' \
              -e 'set newWin to (create window with default profile)' \
              -e "tell current session of newWin to write text \"$ESC\"" \
              -e 'end tell' >/dev/null ;;
esac; }

if [ "$DRY" = 1 ]; then
  echo "── dry run ──────────────────────────────────────"
  [ -n "$RANKED" ] && { echo "account ranking (5h-activity asc):"; printf '%s\n' "$RANKED" | while read -r a c; do echo "  $a  activity=$c"; done; }
  echo "account:  ${CHOSEN:-auto}"
  echo "launcher: $LAUNCHER"
  echo "surface:  $SURFACE"
  if [ "$PROBE" = 1 ]; then
    pm="claude-haiku-4-5"; [ "$FABLE_EFFECTIVE" = 1 ] && pm="claude-fable-5"
    if [ "$EXPLICIT_LAUNCHER" = 1 ]; then echo "probe:    SKIPPED (explicit --launcher gives no account to probe)"
    elif [ -n "$NAMES" ]; then echo "probe:    SKIPPED in dry-run (would probe $pm walking: $(printf '%s' "$NAMES" | tr '\n' ' '))"
    else echo "probe:    SKIPPED in dry-run (would probe $pm on $CHOSEN)"; fi
  fi
  [ -n "$WORKTREE" ] && echo "worktree: $WTROOT/$WORKTREE  (off $BASE, created at fire time)"
  echo "command:  $CMD"
else
  spawn
  DEST="${CWD:-$REPO (self-routing)}"; [ -n "$WORKTREE" ] && DEST="$WTROOT/$WORKTREE"
  echo "→ fired: $LAUNCHER @ $DEST  (surface: $SURFACE, account: $CHOSEN, prompt: $PROMPT_FILE)"
fi