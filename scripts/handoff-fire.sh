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
#   --worktree BRANCH   Get a worktree for BRANCH. Fast path: when <repo>/scripts/worktree-pool.sh
#                       exists AND --base is origin/main, CLAIM a warm pre-provisioned pool slot
#                       (~3s; node_modules/codegen/.env.local/DB already built; claim is
#                       slot-locked, race-free). Fallback (no pool / custom --base / claim fail):
#                       create <wtroot>/BRANCH off --base serially HERE (race-safe), copy
#                       .env.local, then in-surface: CI=true pnpm install && launch (fire.sh
#                       pattern — installs overlap across surfaces).
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
#   --recycle           RECYCLE the CURRENT session's pane ($ITERM_SESSION_ID, or --session-id
#                       UUID): EXIT + RELAUNCH — never /clear + queued payload. CC's queue is
#                       type-asymmetric (2026-07-03 catnav incident): built-in slash commands
#                       hold until the calling turn ends, but PLAIN TEXT is steered INTO the
#                       still-running turn at the next tool-result boundary — and this script's
#                       own Bash call guarantees that boundary, so a queued payload ran inline
#                       in the OLD context while /clear stayed armed behind it. Instead: arm a
#                       detached watcher, then type /exit (which INTERRUPTS any in-flight turn
#                       and exits in seconds — E2E'd; put report + fallback BEFORE the fire);
#                       the watcher ps-polls the pane's tty until claude exits and types
#                       `cd <cwd> && <launcher> [flags] "$(cat F)"` into the plain SHELL via the
#                       it2 python-API CLI (AppleEvent-free; verified detached). Payload arrives
#                       VERBATIM (multi-line safe — no flatten); model/effort ride as launcher
#                       FLAGS (typed /model+/effort mutated saved defaults); old transcript
#                       stays resumable via --resume. Account defaults to THIS session's
#                       (CLAUDE_CONFIG_DIR-derived); --account/--launcher/--model/--effort/
#                       --extra/--probe all compose. Excludes --worktree/--cwd/surface flags.
#   --session-id UUID   Recycle/self-close target pane (default: $ITERM_SESSION_ID's UUID).
#
# Subcommand:
#   self-close [--session-id UUID] [--allow-dirty]
#                       Close the CURRENT session end-to-end once its work is done — the Agent
#                       Teams assignee pattern for peer sessions. Arms the watcher FIRST, then
#                       types /exit (INTERRUPTS any in-flight turn and exits in seconds — E2E
#                       2026-07-03; graceful: SessionEnd hooks run, transcript stays resumable
#                       via --resume). Watcher: (1) polls the pane's tty until the claude
#                       process is gone (one it2 CR nudge at 60s submits a stranded /exit),
#                       (2) closes the pane via the ~/.claude/bin/it2 shim (modal-free force
#                       close; the window follows automatically when it was the last pane).
#                       CC still alive after ~2min → teammate-style force-close anyway (logged).
#                       Guard: refuses on a DIRTY git tree in cwd unless --allow-dirty. NEVER
#                       pair with --recycle (the recycled pane IS the continuation).
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
SURFACE="split-right" SURFACE_EXPLICIT=0 PROBE=0 DRY=0 IN_PLACE=0 EXTRA="" RECYCLE=0 SESSION_ID=""

# Print the header comment up to (excluding) the first non-comment sentinel — growth-proof range.
usage() { sed -n '2,/^set -euo pipefail/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

# Shared single-lookup writer: find the session once, type one line into it.
as_write() { # $1=session-uuid $2=text
  osascript - "$1" "$2" <<'AS'
on run argv
  tell application "iTerm2"
    repeat with w in windows
      repeat with t in tabs of w
        repeat with s in sessions of t
          if id of s is (item 1 of argv) then
            tell s to write text (item 2 of argv)
            return
          end if
        end repeat
      end repeat
    end repeat
  end tell
  error "session not found: " & (item 1 of argv)
end run
AS
}

as_tty() { # $1=session-uuid → the pane's tty path (empty when the session is gone)
  osascript - "$1" <<'AS' 2>/dev/null
on run argv
  tell application "iTerm2"
    repeat with w in windows
      repeat with t in tabs of w
        repeat with s in sessions of t
          if id of s is (item 1 of argv) then return tty of s
        end repeat
      end repeat
    end repeat
  end tell
  return ""
end run
AS
}

# Internal: self-close watcher (spawned detached by `self-close`; survives CC's exit via nohup).
# ARCHITECTURAL CONSTRAINT: osascript AppleEvents to iTerm2 fail unreliably from detached/orphaned
# contexts (empirically: 3 detached runs, 3 silent write/lookup failures; foreground never failed).
# So ALL keystrokes happen FOREGROUND at arm time (they queue behind the calling turn), and this
# watcher does ONLY AppleEvent-free work: ps-based tty polling + the it2 shim close (python
# websocket API — proven reliable detached). `sleep` here is plain sleep: no AppleEvents needed.
if [ "${1:-}" = "__selfclose" ]; then
  SID="${2:?__selfclose needs a session id}"
  TTY_PATH="${3:-}"                                # acquired foreground at arm time — trustworthy
  cc_alive() { ps -o comm= -t "$(basename "$TTY_PATH")" 2>/dev/null | grep -qE 'node|claude'; }
  if [ -z "$TTY_PATH" ]; then
    # Truly blind (no tty handed over): NEVER instant-close on a blind read — fixed grace lets
    # the queued /exit land after the calling turn ends, then close teammate-style.
    echo "⚠ no tty handed over — fixed 90s grace, then close" >&2
    sleep 90
  elif ! cc_alive; then
    : # CC already exited before our first look (fast graceful exit, or shell-only pane) → close now
  else
    waited=0
    while [ "$waited" -lt 180 ]; do
      sleep 5; waited=$((waited+5))
      cc_alive || break                            # ps on a known tty is reliable — no flake class
      # One CR nudge at 60s (it2 python API — proven detached): submits a stranded /exit whose
      # Enter a redraw swallowed; a no-op on an empty composer. MUST be \r — Ink ignores \n.
      [ "$waited" = 60 ] && "$HOME/.claude/bin/it2" session send -s "$SID" $'\r' >/dev/null 2>&1 || true
    done
    cc_alive && echo "⚠ CC still alive after ${waited}s — teammate-style force-close" >&2
  fi
  "$HOME/.claude/bin/it2" session close -f -s "$SID"
  exit 0
fi

# Internal: recycle watcher (spawned detached by --recycle). ONLY AppleEvent-free work, same
# constraint as __selfclose: ps-based tty polling + it2 python-API writes (both proven detached).
# Waits for the typed /exit to land (claude process gone from the tty), then types the relaunch
# command into the plain shell. CR nudges via it2 submit a stranded /exit whose Enter a turn-end
# redraw swallowed (~1-in-6) — a no-op on an empty composer, a bare newline in a shell. MUST be
# \r not \n: CC's Ink TUI only binds Enter to CR (verified 2026-07-03 — \n was a no-op on an Ink
# prompt, \r activated it); zsh accepts either.
if [ "${1:-}" = "__recycle" ]; then
  RSID="${2:?__recycle needs a session id}"
  TTY_PATH="${3:?__recycle needs the pane tty}"
  CMDFILE="${4:?__recycle needs the command file}"
  IT2="$HOME/.claude/bin/it2"
  cc_alive() { ps -o comm= -t "$(basename "$TTY_PATH")" 2>/dev/null | grep -qE 'node|claude'; }
  waited=0
  while [ "$waited" -lt 600 ] && cc_alive; do
    sleep 3; waited=$((waited+3))
    case "$waited" in 60|150|300) "$IT2" session send -s "$RSID" $'\r' >/dev/null 2>&1 || true ;; esac
  done
  if cc_alive; then
    echo "!! CC still alive after ${waited}s — giving up. Relaunch manually: $(cat "$CMDFILE")" >&2
    exit 1
  fi
  sleep 2                                        # shell-prompt settle after claude exits
  ok=0
  for _ in 1 2; do
    if "$IT2" session run -s "$RSID" "$(cat "$CMDFILE")" >/dev/null 2>&1; then ok=1; break; fi
    sleep 3
  done
  [ "$ok" = 1 ] || { echo "!! it2 relaunch write failed twice — run manually in the pane: $(cat "$CMDFILE")" >&2; exit 1; }
  echo "→ relaunched in $RSID: $(cat "$CMDFILE")"
  exit 0
fi

# self-close — arm the detached watcher that retires this session once the calling turn ends.
if [ "${1:-}" = "self-close" ]; then
  shift
  SC_SID="" SC_ALLOW_DIRTY=0 SC_DRY=0
  while [ $# -gt 0 ]; do case "$1" in
    --session-id)  SC_SID="${2:?--session-id needs a value}"; shift 2 ;;
    --allow-dirty) SC_ALLOW_DIRTY=1; shift ;;
    --dry-run)     SC_DRY=1; shift ;;
    *) echo "!! unknown self-close arg: $1" >&2; exit 1 ;;
  esac; done
  ITSID="${ITERM_SESSION_ID:-}"
  SC_SID="${SC_SID:-${ITSID##*:}}"
  [ -n "$SC_SID" ] || { echo "!! self-close needs \$ITERM_SESSION_ID or --session-id" >&2; exit 1; }
  # A session about to evaporate must not hold un-persisted work. (Committed-not-pushed is fine —
  # commits survive the pane; uncommitted edits do too, but silently, which is how work gets lost.)
  if [ "$SC_ALLOW_DIRTY" = 0 ] && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    if [ -n "$(git status --porcelain 2>/dev/null | head -1)" ]; then
      echo "!! refusing self-close: dirty git tree in $(pwd) — commit/stash first, or --allow-dirty" >&2
      exit 1
    fi
  fi
  if [ "$SC_DRY" = 1 ]; then
    echo "── dry run (self-close) ─────────────────────────"
    echo "pane:  $SC_SID"
    echo "chain: arm watcher → FOREGROUND /exit (interrupts any in-flight turn, exits in seconds) → detached ps-poll ≤180s (CR nudge @60s) → it2 force-close pane"
    exit 0
  fi
  # Keystrokes FOREGROUND (detached osascript AppleEvents fail silently — see __selfclose header).
  # ORDER IS LOAD-BEARING: watcher FIRST, /exit LAST — a typed /exit INTERRUPTS the in-flight
  # turn and exits within seconds (E2E 2026-07-03; it does NOT enqueue-to-turn-end like /clear),
  # so in own-pane use the interrupt can kill this Bash tool at /exit+ε. Arm before typing.
  SC_TTY="$(as_tty "$SC_SID")"
  SC_LOG="/tmp/handoff-selfclose-$SC_SID-$(date +%s).log"
  if [ -n "$SC_TTY" ] && ! ps -o comm= -t "$(basename "$SC_TTY")" 2>/dev/null | grep -qE 'node|claude'; then
    # No CC on the pane (shell-only, or still launching): typing /exit would hit the SHELL and
    # vanish (observed). Nothing to exit gracefully — the watcher closes the pane directly.
    echo "→ no CC on $SC_TTY — skipping /exit, closing pane directly" >&2
    nohup "$0" __selfclose "$SC_SID" "$SC_TTY" >"$SC_LOG" 2>&1 &
    disown 2>/dev/null || true
  else
    nohup "$0" __selfclose "$SC_SID" "$SC_TTY" >"$SC_LOG" 2>&1 &
    SC_WATCHER=$!
    disown 2>/dev/null || true
    echo "→ self-close armed for $SC_SID: watcher (ps-poll + shim close) detached (log: $SC_LOG)"
    wrote=0
    for _ in 1 2 3; do
      if as_write "$SC_SID" "/exit" 2>/dev/null; then wrote=1; break; fi
      osascript -e 'delay 2' >/dev/null 2>&1
    done
    # /exit untypeable → un-arm: otherwise the watcher force-closes a healthy session at 180s.
    [ "$wrote" = 1 ] || { kill "$SC_WATCHER" 2>/dev/null; echo "!! could not type /exit into $SC_SID — watcher disarmed" >&2; exit 1; }
    # Anti-strand best-effort (may not run if the interrupt kills us first — the watcher's CR
    # nudge at 60s covers a stranded /exit).
    osascript -e 'delay 1.5' >/dev/null 2>&1
    as_write "$SC_SID" "" 2>/dev/null || true
  fi
  exit 0
fi

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
  --tab)         SURFACE="tab"; SURFACE_EXPLICIT=1; shift ;;
  --split-right) SURFACE="split-right"; SURFACE_EXPLICIT=1; shift ;;
  --split-down)  SURFACE="split-down"; SURFACE_EXPLICIT=1; shift ;;
  --window)      SURFACE="window"; SURFACE_EXPLICIT=1; shift ;;
  --probe)       PROBE=1; shift ;;
  --recycle)     RECYCLE=1; shift ;;
  --session-id)  SESSION_ID="${2:?--session-id needs a value}"; shift 2 ;;
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

env_account() { # reverse of cfg_dir: THIS session's account from its own CLAUDE_CONFIG_DIR
  case "${CLAUDE_CONFIG_DIR:-}" in
    "$HOME/.claude-next")       echo next ;;
    "$HOME/.claude-secondary")  echo next2 ;;
    "$HOME/.claude-tertiary")   echo next3 ;;
    "$HOME/.claude-quaternary") echo next4 ;;
    *) return 1 ;; esac; }

# ---- recycle mode pre-pass: exit + relaunch in the CURRENT pane ------------------------------
# WHY exit+relaunch, not /clear + queued payload (the 2026-07-03 catnav incident): CC's message
# queue is TYPE-ASYMMETRIC — built-in slash commands hold until the calling turn ends, but plain
# text is STEERED into the still-running turn at the next tool-result boundary (delivered as a
# queued_command attachment). The old design typed /clear + payload from inside this script's
# own Bash call, so that call's result boundary deterministically injected the payload INLINE
# (the model kept working in the OLD context) while /clear stayed queued behind it, armed to
# wipe everything at turn end. The Jul-2 verification missed this because its busy turn was
# pure text generation — no tool boundary, so nothing steered. The only queue semantic this
# design still relies on is /exit (a built-in) holding to turn end — the exact behavior the
# incident re-confirmed and self-close's E2E proved. Everything after the exit is queue-free.
# The relaunch composes through the normal account/launcher/flag machinery below; SID + account
# defaulting happen here, execution happens in recycle_fire at the bottom.
SID=""
if [ "$RECYCLE" = 1 ]; then
  [ -n "$WORKTREE$CWD" ] && { echo "!! --recycle excludes --worktree/--cwd (same pane = same dir)" >&2; exit 1; }
  [ "$SURFACE_EXPLICIT" = 1 ] && { echo "!! --recycle excludes surface flags (same pane by definition)" >&2; exit 1; }
  ITSID="${ITERM_SESSION_ID:-}"
  SID="${SESSION_ID:-${ITSID##*:}}"
  [ -n "$SID" ] || { echo "!! --recycle needs \$ITERM_SESSION_ID or --session-id" >&2; exit 1; }
  IN_PLACE=1                                     # relaunch stays in this pane's dir by definition
  if [ -z "$LAUNCHER" ] && [ "$ACCOUNT" = "auto" ]; then
    ACCOUNT="$(env_account)" \
      || { echo "!! --recycle: can't derive this session's account from CLAUDE_CONFIG_DIR='${CLAUDE_CONFIG_DIR:-}' — pass --account or --launcher" >&2; exit 1; }
  fi
fi

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
if [ "$RECYCLE" = 1 ]; then
  # Same pane, same dir: $PWD is the session's working dir (the harness re-pins the Bash tool
  # cwd to it). PREFIX carries CLAUDE_ISOLATION_SKIP=1 (IN_PLACE forced in the pre-pass) so a
  # repo-root relaunch can't auto-create a fresh worktree out from under the continuation.
  CMD="cd $(printf %q "$PWD") && ${PREFIX}${LAUNCHER}${ARGS} \"\$(cat $QP)\""
elif [ -n "$WORKTREE" ]; then
  WT="$WTROOT/$WORKTREE"
  WT_SETUP="cold"                    # cold | pool | existing — decides whether the pane installs
  POOL="$REPO/scripts/worktree-pool.sh"
  POOL_ELIGIBLE=0
  [ -x "$POOL" ] && [ "$BASE" = "origin/main" ] && POOL_ELIGIBLE=1   # pool slots sit AT origin/main;
                                                                     # a custom --base (frozen fork ref) needs the cold path
  if [ -d "$WT" ]; then
    WT_SETUP="existing"
  elif [ "$DRY" = 1 ]; then
    [ "$POOL_ELIGIBLE" = 1 ] && WT_SETUP="pool"
  elif [ "$POOL_ELIGIBLE" = 1 ] && claimed="$("$POOL" claim "$WORKTREE" 2>/dev/null)" \
       && [ -n "$claimed" ] && [ -d "$claimed" ]; then
    WT="$claimed"; WT_SETUP="pool"   # fully provisioned — no in-pane install needed
  fi
  if [ "$WT_SETUP" = "cold" ] && [ "$DRY" = 0 ]; then
    git -C "$REPO" fetch origin -q || echo "⚠ fetch failed — basing off last-fetched $BASE" >&2
    ( cd "$REPO" && git worktree add "$WT" -b "$WORKTREE" "$BASE" >/dev/null )
    [ -f "$REPO/.env.local" ] && { cp "$REPO/.env.local" "$WT/.env.local"; chmod 600 "$WT/.env.local"; }
  fi
  if [ "$WT_SETUP" = "cold" ]; then
    CMD="cd $(printf %q "$WT") && CI=true pnpm install --frozen-lockfile && ${PREFIX}${LAUNCHER}${ARGS} \"\$(cat $QP)\""
  else
    CMD="cd $(printf %q "$WT") && ${PREFIX}${LAUNCHER}${ARGS} \"\$(cat $QP)\""
  fi
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

# Recycle executor: /exit foreground (held built-in — queues behind the calling turn, runs at
# turn end; keystrokes MUST be foreground, detached AppleEvents fail silently), then a detached
# watcher (__recycle) that ps-polls until claude exits and it2-types the relaunch into the shell.
recycle_fire() {
  local tty cmdfile log ts wrote
  ts="$(date +%s)"
  cmdfile="/tmp/handoff-recycle-cmd-$SID-$ts.sh"
  log="/tmp/handoff-recycle-$SID-$ts.log"
  printf '%s\n' "$CMD" > "$cmdfile"
  tty="$(as_tty "$SID")"
  [ -n "$tty" ] || { echo "!! recycle: session $SID not found in iTerm2" >&2; exit 1; }
  if ! ps -o comm= -t "$(basename "$tty")" 2>/dev/null | grep -qE 'node|claude'; then
    # No CC on the pane (shell-only): nothing to /exit — type the relaunch right now.
    "$HOME/.claude/bin/it2" session run -s "$SID" "$CMD" \
      || { echo "!! recycle: it2 write into $SID failed — run manually: $CMD" >&2; exit 1; }
    echo "→ recycled (no CC was running): typed relaunch into $SID"
    return 0
  fi
  # ORDER IS LOAD-BEARING: watcher FIRST, /exit LAST. A typed /exit INTERRUPTS the in-flight
  # turn and exits within seconds (E2E 2026-07-03 — twice: the busy turn died with no output
  # persisted; /exit does NOT enqueue-to-turn-end the way /clear does). When this script runs
  # in its OWN pane, that interrupt can kill this very Bash tool at /exit+ε — so everything
  # that must survive (watcher, user-facing fallback line) happens BEFORE the /exit keystroke.
  nohup "$0" __recycle "$SID" "$tty" "$cmdfile" >"$log" 2>&1 &
  WATCHER_PID=$!
  disown 2>/dev/null || true
  echo "→ recycle armed for $SID: watcher relaunches $LAUNCHER once claude exits (log: $log)"
  echo "  manual fallback if no relaunch appears: $CMD"
  wrote=0
  for _ in 1 2 3; do
    if as_write "$SID" "/exit" 2>/dev/null; then wrote=1; break; fi
    osascript -e 'delay 2' >/dev/null 2>&1
  done
  # /exit untypeable → un-arm: a live watcher would eventually type the relaunch into a still-
  # running CC session's composer.
  [ "$wrote" = 1 ] || { kill "$WATCHER_PID" 2>/dev/null; echo "!! recycle: could not type /exit into $SID — watcher disarmed" >&2; exit 1; }
  # Anti-strand best-effort: may never run if the interrupt kills us first — the watcher's CR
  # nudges (@60/150/300s) cover a stranded /exit either way.
  osascript -e 'delay 1.5' >/dev/null 2>&1
  as_write "$SID" "" 2>/dev/null || true
}

if [ "$DRY" = 1 ]; then
  echo "── dry run ──────────────────────────────────────"
  [ -n "$RANKED" ] && { echo "account ranking (5h-activity asc):"; printf '%s\n' "$RANKED" | while read -r a c; do echo "  $a  activity=$c"; done; }
  echo "account:  ${CHOSEN:-auto}"
  echo "launcher: $LAUNCHER"
  if [ "$RECYCLE" = 1 ]; then
    echo "surface:  (recycle — this pane: $SID)"
    echo "chain:    arm watcher → FOREGROUND /exit (interrupts any in-flight turn, exits in seconds — emit report/fallback BEFORE firing) → detached ps-poll ≤600s (CR nudges @60/150/300s) → it2-typed relaunch into the shell"
  else
    echo "surface:  $SURFACE"
  fi
  if [ "$PROBE" = 1 ]; then
    pm="claude-haiku-4-5"; [ "$FABLE_EFFECTIVE" = 1 ] && pm="claude-fable-5"
    if [ "$EXPLICIT_LAUNCHER" = 1 ]; then echo "probe:    SKIPPED (explicit --launcher gives no account to probe)"
    elif [ -n "$NAMES" ]; then echo "probe:    SKIPPED in dry-run (would probe $pm walking: $(printf '%s' "$NAMES" | tr '\n' ' '))"
    else echo "probe:    SKIPPED in dry-run (would probe $pm on $CHOSEN)"; fi
  fi
  if [ -n "$WORKTREE" ]; then
    case "$WT_SETUP" in
      pool)     echo "worktree: POOL CLAIM at fire time (scripts/worktree-pool.sh claim $WORKTREE — path printed by claim; no in-pane install)" ;;
      existing) echo "worktree: $WT  (exists — reused as-is)" ;;
      *)        echo "worktree: $WT  (cold: off $BASE, created at fire time + in-pane install)" ;;
    esac
  fi
  echo "command:  $CMD"
elif [ "$RECYCLE" = 1 ]; then
  recycle_fire
else
  spawn
  DEST="${CWD:-$REPO (self-routing)}"; [ -n "$WORKTREE" ] && DEST="$WT ($WT_SETUP)"
  echo "→ fired: $LAUNCHER @ $DEST  (surface: $SURFACE, account: $CHOSEN, prompt: $PROMPT_FILE)"
fi