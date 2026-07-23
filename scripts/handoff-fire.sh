#!/usr/bin/env bash
# shellcheck disable=SC2009  # file-wide: `ps -o comm= -t <tty>` is a controlling-TTY process lookup
#   that pgrep cannot express (pgrep matches by name/args, not by tty). Correct + intentional here.
# handoff-fire.sh — autonomously launch a Claude Code continuation session in iTerm2.
#
# Generalizes the proven /tmp/fire.sh pattern (2026-07-02 parallel-track launch): open an
# interactive iTerm2 surface (tab / split pane / window) and TYPE the launch command into it via
# the it2 API (bracketed-paste + echo-verify), because the per-account launchers (claude-next,
# claude-next2/3/4, claude-fable*) are zsh FUNCTIONS/ALIASES that only resolve in an interactive shell.
#
#   handoff-fire.sh --prompt-file /tmp/fire-<slug>.txt [options]
#
# Options:
#   --prompt-file F     REQUIRED. File whose content is auto-submitted as the session's first
#                       message via `launcher "$(cat F)"`. Content arrives VERBATIM — command
#                       substitution output is never re-expanded (only trailing newlines strip).
#   --account A         next|next2|next3|next4|auto (default auto). auto = live-limit ranking
#                       via `claude-accounts --rank` (5h/weekly/Fable headroom + resets + live
#                       session spread; fable ranking when --model fable). Degrades to the
#                       trailing-5h transcript-activity proxy ONLY when live limits are
#                       unreadable; halts (never fires blind) when limits say NO account is
#                       routable. Static hint orders are retired — they went stale in 48h.
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
#   --follow            OPT-IN. "The operator is WATCHING this fire — land their view on the
#                       continuation": RAISE + focus the new surface (⌘D split of the firing pane by
#                       default) exactly as a manual /handoff wants. WITHOUT --follow the fire is
#                       AUTONOMOUS and NEVER steals focus (C1, 2026-07-19, the ttys018 mis-inject):
#                       the default surface becomes a BACKGROUND tab (not a split of the operator's
#                       active pane), nothing is raised (no `session focus`/order_window_front=True),
#                       and the operator-focused session is captured before + asserted unchanged after
#                       the fire (fail-loud on any steal). Only /handoff (operator-initiated) passes it.
#   --split-right       The --follow DEFAULT + the STANDING operator preference for MANUAL handoffs.
#                       ⌘D-split the FIRING pane — THIS session's own pane, located via $ITERM_SESSION_ID
#                       — new pane to the RIGHT, SAME TAB, SAME PROFILE, IN THE OPERATOR'S WINDOW.
#                       Resolved + split via the it2 python API (get_session_by_id, atomic); if the
#                       anchor is gone it RETRIES once after a settle then FAILS LOUD — it NEVER fires
#                       into another window (the "separate window" complaint this default exists to
#                       kill). An EXPLICIT --split-right WITHOUT --follow still splits, but restores +
#                       asserts the operator's focus (never raises). AUTONOMOUS fires that pass no
#                       surface flag get --tab-style background instead (see --follow).
#   --split-down        Split the firing pane, new pane below (⌘⇧D). Same it2 path + fail-loud.
#   --tab               Background tab in the FIRING pane's window (not the current view); fails loud
#                       rather than drifting to another window. WITH --follow it raises the tab; the
#                       AUTONOMOUS default already IS a background tab, so an explicit autonomous --tab
#                       is the same background surface (opt-in for --follow: pair with --surface-reason).
#   --window            OPT-IN (pair with --surface-reason). Fresh iTerm2 window — the ONLY surface
#                       that deliberately does NOT anchor to the firing pane. WITHOUT --follow it is
#                       created without activating iTerm2 (background).
#   --surface-reason R  Why a non-default surface (--tab/--window) was chosen — e.g. sliver-avoidance
#                       for many parallel fires. Recorded in the fire summary; silences the advisory
#                       that otherwise warns a --tab/--window handoff is overriding the ⌘D default.
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
#   --notify-back [UUID] Two-way sugar: append a back-channel trailer to a COPY of the prompt
#                       (never the caller's file) telling the fired session to ping the
#                       ORIGINATOR via `cc-notify <UUID> "HANDOFF-PING <slug>: <status>"` on
#                       completion / decision gate / blocker. UUID defaults to THIS firing pane
#                       ($ITERM_SESSION_ID / --session-id). Pair with `cc-await-ping` on the
#                       originator for a modal-safe wake. See docs/plans/TWO_WAY_SESSION_COMMS_PLAN.md.
#   --self-retire       DEFAULT for non-recycle fires. Append a SELF-RETIRE directive to the prompt
#   --no-self-retire    copy: the fired PEER drives its trivial pre-authorized tail, then runs
#                       `self-close --terminal` on its OWN pane instead of idling. --notify-back
#                       SIGNALS done; it does NOT CLOSE (the 2026-07-17 idle-fleet incident: five
#                       peers pinged then idled on a deferred "heads-up"). Auto-OFF for --recycle
#                       (the recycled pane IS the continuation). --no-self-retire opts out.
#
# Subcommand:
#   self-close (--successor UUID | --terminal) [--session-id UUID] [--no-notify]
#              [--dirty-owner successor] [--allow-dirty] [--dry-run]
#                       Close the CURRENT session end-to-end once its work is done — the Agent
#                       Teams assignee pattern for peer sessions. Arms the watcher FIRST, then
#                       types /exit (INTERRUPTS any in-flight turn and exits in seconds — E2E
#                       2026-07-03; graceful: SessionEnd hooks run, transcript stays resumable
#                       via --resume). Watcher: (1) polls the pane's tty until the claude
#                       process is gone (one it2 CR nudge at 60s submits a stranded /exit),
#                       (2) closes the pane via the ~/.claude/bin/it2 shim (modal-free force
#                       close; the window follows automatically when it was the last pane),
#                       (3) with --successor: FOCUSES the successor pane so the operator's
#                       view lands ON the continuation, never on an empty gap.
#                       CC still alive after ~2min → teammate-style force-close anyway (logged).
#                       SUCCESSION CONTRACT (2026-07-13, third "where did my session go"
#                       incident): a pane close is operator-visible surface — the caller MUST
#                       declare what continues the work. --successor <pane-uuid> is verified
#                       ALIVE (pane resolvable + claude on its tty) BEFORE /exit is typed and
#                       the succession is announced INTO the successor via cc-notify (the
#                       report emitted in the dying pane dies with it; the surviving
#                       transcript is where the operator will look). --terminal declares
#                       end-of-line (nothing continues). Bare self-close exits 2.
#                       Guard: refuses on a DIRTY git tree in cwd (exit 1). On a SHARED
#                       checkout where the dirt is a live successor's in-flight work, pass
#                       --dirty-owner successor (requires --successor; asserts the close
#                       loses nothing because the owner survives). --allow-dirty stays the
#                       blunt override (un-persisted work may be lost). NEVER pair with
#                       --recycle (the recycled pane IS the continuation).
#   land (--branch NAME | --worktree PATH) [--repo P] [--trunk B] [--dry-run]
#                       DESK-LOCAL LAND (cc-backlog c06778fd13a7). Land a worktree's committed,
#                       gate-green work onto origin/<trunk> via the sanctioned scripts/ship-land.sh,
#                       reached through this ALREADY-allow-listed script so the desk (stuck in the
#                       shared checkout on `main`, where a direct push is classifier-denied and the
#                       hook-allowed HEAD:main shape is cwd-unreachable) lands autonomously. The
#                       whole pipeline runs as a SUBPROCESS of this one approved Bash call, so it
#                       never re-enters the classifier; ship-land.sh's provable safety envelope
#                       (shared-checkout/dirty refusal, escalation-PARK, gate, content-verify,
#                       stranded-sweep, rollback, land.log) is unchanged. Delegates to the sibling
#                       scripts/desk-land.sh (run `handoff-fire.sh land --help` for its full contract).
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
# Cross-account comms substrate (FIXED $HOME/.claude — cross-account addressing, never
# $CLAUDE_CONFIG_DIR). Env-overridable for tests.
REG_DIR="${CC_REGISTRY_DIR:-$HOME/.claude/cc-registry}"
CC_ROLES_DIR="${CC_ROLES_DIR:-$HOME/.claude/cc-roles}"
FIRED_DIR="${CC_FIRED_DIR:-$HOME/.claude/cc-fired}"   # T-P3-4 fired-peer markers (read by bin/cc-reaper)

# This script is symlinked into ~/.claude/scripts; resolve its REAL dir so the sibling comms-safety
# tools it now wires — payload-lint.sh (F3, T-P2-5) and completion-push.sh (F5, T-P2-1) — are found
# beside the actual file (NOT via $REPO, which is the TARGET-of-fire repo). Env-overridable for tests.
HF_SELF="$0"; while [ -L "$HF_SELF" ]; do _hf_t="$(readlink "$HF_SELF")"; case "$_hf_t" in /*) HF_SELF="$_hf_t" ;; *) HF_SELF="$(dirname "$HF_SELF")/$_hf_t" ;; esac; done
HF_DIR="$(cd "$(dirname "$HF_SELF")" && pwd)"
PAYLOAD_LINT_BIN="${CC_PAYLOAD_LINT_BIN:-$HF_DIR/payload-lint.sh}"
COMPLETION_PUSH_BIN="${CC_COMPLETION_PUSH_BIN:-$HF_DIR/completion-push.sh}"

# ---- Part A2: pre-handoff account sweep config (all env-overridable for tests) -----------------
# The cross-account visibility + auto-heal that runs BEFORE a fire (see pre_fire_account_sweep).
# Was CC_ACCOUNTS_BIN explicitly provided? A bats run must NEVER poll the REAL claude-accounts (live
# network sweep + a possible real Phase-1 relogin side effect) — so under bats the sweep runs ONLY
# when a test opts in by pointing CC_ACCOUNTS_BIN at a stub (captured here, before defaulting).
CC_ACCOUNTS_BIN_EXPLICIT=0; [ -n "${CC_ACCOUNTS_BIN:-}" ] && CC_ACCOUNTS_BIN_EXPLICIT=1
CC_ACCOUNTS_BIN="${CC_ACCOUNTS_BIN:-claude-accounts}"          # the dashboard/prober/router SSOT
CC_SECURITY_BIN="${CC_SECURITY_BIN:-security}"                 # macOS keychain reader (Phase-1 relogin)
CC_ACCOUNTS_JSON="${CC_ACCOUNTS_JSON:-$HOME/.claude/accounts.json}"        # accounts SSOT (keychain -a account)
ACCOUNT_SWEEP="${HANDOFF_ACCOUNT_SWEEP:-on}"                   # off = skip the sweep entirely
ACCOUNT_SWEEP_THROTTLE_S="${HANDOFF_ACCOUNT_SWEEP_THROTTLE_S:-60}"  # reuse the last sweep within this window (wave anti-stampede; 0 = always fresh)
ACCOUNT_SWEEP_STAMP="${HANDOFF_ACCOUNT_SWEEP_STAMP:-/tmp/handoff-account-sweep.json}"
ACCOUNT_SWEEP_RELOGIN_TIMEOUT_S="${HANDOFF_RELOGIN_TIMEOUT_S:-90}"  # per-account Phase-1 relogin ceiling
# The per-account lock the Phase-1 relogin flocks. DEFAULT MUST equal claude-accounts heal()'s path
# (`/tmp/claude-accounts-heal-<acct>.lock`) so the two never log in the same account at once — only
# override in tests (production leaving this default is what makes the interlock real).
CC_HEAL_LOCK_PREFIX="${CC_HEAL_LOCK_PREFIX:-/tmp/claude-accounts-heal-}"

PROMPT_FILE="" ACCOUNT="auto" LAUNCHER="" MODEL="" EFFORT="" CWD="" WORKTREE=""
REPO="$DEFAULT_REPO" WTROOT="$HOME/Development/.worktrees" BASE="origin/main"
SURFACE="split-right" SURFACE_EXPLICIT=0 SURFACE_REASON="" PROBE=0 DRY=0 IN_PLACE=0 EXTRA="" RECYCLE=0 SESSION_ID=""
NOTIFY_BACK="" SELF_RETIRE=1 AS_ROLE="" FOLLOW=0
SPAWNED_PANE="" ENGAGE_VERIFY=0 FIRE_MARKER=""
ACCOUNT_SWEEP_BRIDGE=""    # Part A2: embeddable "## ACCOUNT STATE" section (non-empty ⟺ ≥1 stranded account)

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
  # LOAD-ROBUST (T-P2-1, 2026-07-19; same class as cc-run 846380c6308f). iTerm2's AppleScript bridge
  # intermittently errors NON-ZERO under concurrent-session contention. Every caller assigns bare —
  # `SUC_TTY="$(as_tty …)"` (successor-liveness gate), `SC_TTY=` / `tty=` (self-close + recycle) — so a
  # non-zero return would trip `set -e` (line 140) and abort with the LEAKED osascript exit code instead
  # of the caller's own classification. That is exactly how the self-close successor-liveness gate leaked
  # a non-3 exit under load and RED-flaked the shared ship-land gate. So as_tty NEVER trips set -e: it
  # RETRIES a failed (non-zero) query a bounded number of times and ALWAYS exits 0, printing the resolved
  # tty or empty. A genuinely ABSENT pane returns immediately (the query SUCCEEDS — exit 0 — with empty
  # output, never retried); only a FAILED query is retried, so a real, alive successor still resolves
  # through a transient bridge hiccup rather than being spuriously judged dead.
  local out n=0 max="${HANDOFF_TTY_RETRIES:-5}"
  while [ "$n" -lt "$max" ]; do
    n=$((n + 1))
    # `if out=$(…)` runs the query in an if-condition ⇒ set -e is suppressed for it; a non-zero query
    # falls through to the retry instead of aborting. A successful query (incl. empty = pane absent) wins.
    if out="$(_as_tty_query "$1")"; then printf '%s' "$out"; return 0; fi
    [ "$n" -lt "$max" ] && /bin/sleep "${HANDOFF_TTY_RETRY_SLEEP_S:-0.3}"
  done
  return 0   # query never succeeded (iTerm2 wedged) → nothing printed = empty tty; the caller aborts safely
}

# Raw single pane→tty query (the osascript), split out so as_tty's retry / set-e-safety wrapper is
# testable. SELFTEST SEAM: while the countdown file $HANDOFF_TTY_FAIL_FILE holds a positive integer this
# returns NON-ZERO (modelling the AppleScript bridge erroring under load) and decrements it — so as_tty's
# load-robustness is RED-provable without real contention (tests/handoff-fire-completion-push.bats). Inert
# unless the var is set.
_as_tty_query() { # $1=session-uuid → tty on stdout; non-zero when the query itself failed
  if [ -n "${HANDOFF_TTY_FAIL_FILE:-}" ]; then
    local left; left="$(cat "$HANDOFF_TTY_FAIL_FILE" 2>/dev/null || printf '0')"
    if [ "${left:-0}" -gt 0 ] 2>/dev/null; then
      printf '%s' "$((left - 1))" > "$HANDOFF_TTY_FAIL_FILE"
      return 1
    fi
  fi
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

# Detached-watcher spawner. nohup+disown is NOT enough: when the typed /exit interrupts the
# in-flight Bash tool call running this script, CC reaps the tool call's entire process GROUP
# with SIGKILL — a nohup'd child shares that pgid (and its PPID is this script while the script
# still runs), so the watcher dies instantly: 0-byte log, no error, no relaunch, stranded pane.
# Observed 2× 2026-07-13 (both same-pane recycles, 10:29 + 15:07); reproduced synthetically the
# same day (group SIGKILL kills the nohup sibling; a start_new_session child survives). The
# 2026-07-12 successes merely WON the race — the script returned before CC processed /exit, so
# the watcher had already reparented to launchd. setsid gives the watcher its OWN session+pgid
# and PPID 1 immediately: immune to group kill and parent-tree walk alike, no race to win.
detach() { # $1=logfile  $2...=command  → prints watcher pid on stdout
  /usr/bin/python3 - "$@" <<'PY'
import subprocess, sys
log = open(sys.argv[1], 'ab', 0)
p = subprocess.Popen(sys.argv[2:], start_new_session=True,
                     stdout=log, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL)
print(p.pid)
PY
}

# Arm handshake: a watcher's FIRST act is writing an "→ armed:" heartbeat to its log; /exit is
# typed ONLY after that line exists. A watcher that cannot even write its log must never be
# trusted as the sole continuation path. (Healthy write lands in ms; 5s ceiling.)
await_armed() { # $1=logfile → 0 once armed, 1 on timeout
  local n=0
  while [ "$n" -lt 25 ]; do
    grep -q '^→ armed:' "$1" 2>/dev/null && return 0
    /bin/sleep 0.2; n=$((n+1))
  done
  return 1
}

# ---- reliable launch-command injection (INC ttys018, 2026-07-19) ------------------------------
# Typing a launch command into an interactive zsh as a raw async_send_text CHAR-STREAM races the
# target shell's ZLE: zsh-autosuggestions + zsh-syntax-highlighting recompute per keystroke and
# `setopt CORRECT` spell-prompts the first word (all three are live in ~/.zshrc). On a freshly-split
# pane whose .zshrc is still loading, that race TRANSPOSES characters — observed `cd` → `ould ocd` —
# CORRECT then holds the mangled first word at a [nyae] prompt and the tail of the line (including
# the `"$(cat …)"`) spills out of its quotes, so the brief floods the shell as raw commands and the
# launcher never starts (item e4c7e7fb41bd; worker left task-less). Two composed defenses, both from
# stock it2 primitives (no it2-package edit):
#   BRACKETED PASTE — wrap the command in ESC[200~ … ESC[201~ so ZLE inserts it as ONE literal block
#     with NO per-character widget firing (autosuggest / highlight / correct all sit out a paste); the
#     command lands intact regardless of shell-init timing or plugins.
#   ECHO-VERIFY before submit — read the pane back and confirm the intact command is on the input line
#     BEFORE the CR. A half-ready shell that dropped the paste never gets an Enter; clear the line and
#     retry with a longer settle. The destructive keystroke (Enter — which makes the shell RUN the
#     line and `cat` the brief) is gated on proof, so a mangled line is NEVER executed.
# This composes with the C1 no-focus-steal surface work (background tab, no raise): a background fresh
# zsh still races ZLE, so intact injection is needed even once focus-steal is gone. Timings are env-
# overridable so tests run in ms (IT2_BIN seam). ESC = $'\x1b'.
BP_START=$'\x1b[200~'
BP_END=$'\x1b[201~'
it2_type_verified() { # $1=it2-bin $2=session-id $3=command → 0 verified+submitted / 1 fail-loud
  local it2="$1" id="$2" cmd="$3" attempt mode reread want
  # nlines=500 reads the WHOLE visible screen, not the last N rows: a freshly-split pane's prompt +
  # input line sit at the TOP (row 0-1) with blank rows below, so a small "last N" window reads only
  # blanks and never sees the command (live-verified 2026-07-19). 500 > any pane height, so it2's
  # `read -n` returns every visible line and grep finds the command wherever the prompt is.
  local attempts="${FIRE_TYPE_ATTEMPTS:-4}" settle="${FIRE_TYPE_SETTLE:-0.5}" nlines="${FIRE_TYPE_READLINES:-500}"
  local presettle="${FIRE_TYPE_PRESETTLE:-0.12}"
  want="$(printf '%s' "$cmd" | tr -d '[:space:]')"
  [ -n "$want" ] || return 1
  for attempt in $(seq 1 "$attempts"); do
    # Final attempt degrades to a plain (un-bracketed) char-send — covers the exotic case of a shell
    # with bracketed paste disabled; echo-verify still gates the CR so the fallback is never unsafe.
    mode="paste"; [ "$attempt" -ge "$attempts" ] && mode="plain"
    "$it2" session send -s "$id" $'\x15' >/dev/null 2>&1 || true    # Ctrl-U: scrub any partial line
    /bin/sleep "$presettle"
    if [ "$mode" = "paste" ]; then
      "$it2" session send -s "$id" "${BP_START}${cmd}${BP_END}" >/dev/null 2>&1 || { /bin/sleep "$settle"; continue; }
    else
      "$it2" session send -s "$id" "$cmd" >/dev/null 2>&1 || { /bin/sleep "$settle"; continue; }
    fi
    /bin/sleep "$settle"
    reread="$("$it2" session read -s "$id" -n "$nlines" 2>/dev/null | tr -d '[:space:]' || true)"
    if printf '%s' "$reread" | grep -qF -- "$want"; then
      "$it2" session send -s "$id" $'\r' >/dev/null 2>&1 && return 0   # verified → submit
    fi
    "$it2" session send -s "$id" $'\x15' >/dev/null 2>&1 || true    # scrub the mangled/half line
    /bin/sleep "$settle"
  done
  return 1
}

# INC-4 engagement RESEND: re-inject the (multi-line) BRIEF into what should be the fired session's
# claude composer. Same bracketed-paste atomicity so that IF claude has not yet taken the pane (still
# a shell) the brief lands as ONE inert buffer blob instead of flooding line-by-line as commands (the
# ttys018 catastrophe). No echo-verify here — the target is Ink's composer, not a shell input line —
# but bracketed paste alone removes the flood. CR submits (Ink binds Enter to CR).
it2_paste_submit() { # $1=it2-bin $2=session-id $3=text → 0 pasted+submitted / 1 send failed
  local it2="$1" id="$2" text="$3"
  "$it2" session send -s "$id" "${BP_START}${text}${BP_END}" >/dev/null 2>&1 || return 1
  /bin/sleep "${FIRE_TYPE_SETTLE:-0.5}"
  "$it2" session send -s "$id" $'\r' >/dev/null 2>&1
}

# ---- P0-11 engagement verification (FM2 / INC-4 cold-fire auto-submit race) -------------------
# A non-recycle fire types the launch command + focuses, then historically printed "→ fired"
# UNCONDITIONALLY. But a cold --worktree fire can race CC boot: the auto-submit keystroke is lost
# and the pane sits at an empty composer forever — 0 commits, no ping, LOOKS fired
# (cold-worktree-fire-autosubmit-race, INC-4 2026-07-17). Prove ENGAGEMENT before the success
# line by transcript-birth — the fired prompt carries a unique marker; when a JSONL under the
# target account's projects dir contains it, the session actually ingested the brief. A cc-registry
# row for the fired pane bearing a session_id is an equivalent positive. The marker is globally
# unique and is NEVER echoed to this session's own stream, so only the FIRED session's transcript
# can hold it (this session merely wrote it into a launch-time file the launcher `cat`s at exec).
#
# BIRTH IS NOT ENGAGEMENT (item ff2d6609a33e). Both signals above prove only that a transcript/row
# came into EXISTENCE — attachment + system rows land, and the registry row is written by the
# SessionStart hook, before the model has done anything. A fire whose first prompt was REJECTED (the
# /goal >4000-char cap — memory handoff-fire-goal-prefix-trap) or never submitted at all is born
# with exactly those rows and then idles forever, so the birth-check silently defeated
# verify_engagement's one re-type recovery. Engagement now requires a real first ASSISTANT turn.
assistant_turn_in() { # $1=transcript jsonl → 0 a content-bearing assistant turn exists / 1 none
  local f="$1"
  [ -s "$f" ] || return 1
  if command -v jq >/dev/null 2>&1; then
    # `first(inputs|…)` short-circuits on the first hit — never slurps a large transcript.
    [ "$(jq -rn 'first(inputs
                   | select(.type == "assistant"
                            and (((.message.content? // .content? // "") | tostring | length) > 0))
                   | "1")' "$f" 2>/dev/null)" = 1 ] && return 0
    return 1
  fi
  grep -q '"type":"assistant"' "$f"   # jq-less fallback: still a turn-check, never mere existence
}

engagement_seen() { # $1=projects-dir $2=marker $3=registry-dir $4=fired-pane → 0 engaged / 1 not
  local pdir="$1" marker="$2" regdir="$3" pane="$4" hit rsid
  # (a) the transcript carrying the marker must ALSO show an assistant turn (ingested AND ran).
  if [ -n "$marker" ] && [ -d "$pdir" ]; then
    while IFS= read -r hit; do
      [ -n "$hit" ] || continue
      assistant_turn_in "$hit" && return 0
    done <<EOF
$(find "$pdir" -name '*.jsonl' -type f -exec grep -lF -- "$marker" {} + 2>/dev/null)
EOF
  fi
  # (b) a cc-registry row's (non-null) session_id NAMES a transcript — that transcript must show an
  #     assistant turn too. The row alone is the SessionStart hook's own output: pure birth.
  if [ -n "$pane" ] && [ -n "$regdir" ] && [ -f "$regdir/$pane.json" ] && command -v jq >/dev/null 2>&1; then
    rsid="$(jq -r '.session_id // empty' "$regdir/$pane.json" 2>/dev/null)"
    if [ -n "$rsid" ] && [ -d "$pdir" ]; then
      while IFS= read -r hit; do
        [ -n "$hit" ] || continue
        assistant_turn_in "$hit" && return 0
      done <<EOF
$(find "$pdir" -name "$rsid.jsonl" -type f 2>/dev/null)
EOF
    fi
  fi
  return 1
}

# Poll for engagement ≤timeout; on a miss re-type the prompt ONCE into the fired pane (the exact
# INC-4 recovery), re-poll ≤retry, then return 1 (caller FAILS LOUD — never a false "→ fired").
# All windows are env-overridable so tests run in seconds.
verify_engagement() { # $1=projects $2=marker $3=regdir $4=pane $5=it2-bin $6=resend-text → 0/1
  local pdir="$1" marker="$2" regdir="$3" pane="$4" it2="$5" resend="$6"
  local timeout="${FIRE_ENGAGE_TIMEOUT:-120}" retry="${FIRE_ENGAGE_RETRY:-60}" interval="${FIRE_ENGAGE_INTERVAL:-3}"
  local t=0
  while [ "$t" -lt "$timeout" ]; do
    engagement_seen "$pdir" "$marker" "$regdir" "$pane" && return 0
    /bin/sleep "$interval"; t=$((t + interval))
  done
  echo "⚠ fired session not engaged after ${timeout}s — re-typing the prompt once (INC-4 recovery)" >&2
  if [ -n "$pane" ] && [ -n "$it2" ] && [ -n "$resend" ]; then
    it2_paste_submit "$it2" "$pane" "$resend" || true   # bracketed-paste: no flood if pane is still a shell
  fi
  t=0
  while [ "$t" -lt "$retry" ]; do
    engagement_seen "$pdir" "$marker" "$regdir" "$pane" && return 0
    /bin/sleep "$interval"; t=$((t + interval))
  done
  return 1
}

# ---- P0-12 registration guarantee ------------------------------------------------------------
# After engagement, guarantee the fired pane is VISIBLE in the cross-account registry so the
# reaper/board can see it (a never-registered pane is invisible to the whole classify/reap stack —
# a18 L-2). Poll ≤timeout for the SessionStart P8 row; if none appears, write a PROVISIONAL row
# the P8 register() overwrites atomically on its next run. No pid (that is P8's authoritative
# liveness field) — presence must not encode liveness (session-register P8 rule).
ensure_registration() { # $1=regdir $2=pane $3=name $4=cwd $5=cmd → best-effort, always 0
  local regdir="$1" pane="$2" name="$3" cwd="$4" cmd="$5" tmp t=0
  local timeout="${FIRE_REG_TIMEOUT:-30}" interval="${FIRE_REG_INTERVAL:-3}"
  [ -n "$pane" ] && [ -n "$regdir" ] || return 0
  command -v jq >/dev/null 2>&1 || return 0
  [ -f "$regdir/$pane.json" ] && return 0
  while [ "$t" -lt "$timeout" ]; do
    /bin/sleep "$interval"; t=$((t + interval))
    [ -f "$regdir/$pane.json" ] && return 0
  done
  mkdir -p "$regdir" 2>/dev/null || return 0
  tmp="$regdir/.$pane.prov.$$"
  if jq -n --arg paneUUID "$pane" --arg name "$name" --arg cwd "$cwd" --arg cmd "$cmd" \
        '{paneUUID:$paneUUID, name:$name, cwd:$cwd, cmd:$cmd, provisional:true}' > "$tmp" 2>/dev/null \
     && [ -s "$tmp" ]; then
    mv -f "$tmp" "$regdir/$pane.json" 2>/dev/null || rm -f "$tmp" 2>/dev/null
    echo "→ provisional registry row written for $pane (SessionStart P8 register replaces it)" >&2
  else
    rm -f "$tmp" 2>/dev/null
  fi
  return 0
}

# ---- T-P3-4 fired-peer marker (the cc-reaper auto-reap key) -----------------------------------
# A fire that carries the SELF-RETIRE trailer creates a PEER WORKER — a session explicitly told
# "you are NOT an idle human-in-the-loop pane: finish, report, close yourself". cc-reaper may
# therefore AUTO-REAP it once it is finished + landed + its own tracked tree is clean, instead of
# paging the operator to hand-confirm-close every one (13+ piled up by 2026-07-20, each surfaced
# through a keystroke injection that corrupts the operator's terminal).
#
# The marker is written by the SPAWNER — the only process that can know a session was FIRED rather
# than started by a human — and keyed by the fired pane UUID. Deliberately NOT a cc-registry field:
# SessionStart's register() rewrites that row wholesale and would clobber it.
#
# FAIL-SAFE BY CONSTRUCTION: absence ⇒ unmarked ⇒ cc-reaper treats it as an operator session ⇒ NEVER
# auto-reaped. An operator's shell launch, `claude -w`, a --recycle continuation and a
# --no-self-retire fire all leave no marker, and nothing anywhere infers one from session state —
# so a session cannot earn the marker by behaving like a worker.
mark_fired_peer() { # $1=fired-dir $2=fired-pane $3=cwd $4=firing-pane → best-effort, always 0
  local dir="$1" pane="$2" cwd="$3" by="$4" tmp
  [ -n "$dir" ] && [ -n "$pane" ] || return 0
  case "$pane" in *[!0-9A-Fa-f-]*) return 0 ;; esac    # UUID-shaped only — never a path fragment
  command -v jq >/dev/null 2>&1 || return 0
  mkdir -p "$dir" 2>/dev/null || return 0
  tmp="$dir/.$pane.$$"
  if jq -n --arg paneUUID "$pane" --arg cwd "$cwd" --arg firedBy "$by" \
        --arg firedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)" \
        '{paneUUID:$paneUUID, cwd:$cwd, firedBy:$firedBy, firedAt:$firedAt, selfRetire:true}' \
        > "$tmp" 2>/dev/null && [ -s "$tmp" ]; then
    mv -f "$tmp" "$dir/$pane.json" 2>/dev/null || rm -f "$tmp" 2>/dev/null
  else
    rm -f "$tmp" 2>/dev/null
  fi
  return 0
}

# ---- P0-15 role indirection (SO-1 ping-to-dead-pane break) ------------------------------------
# A role file names the CURRENT pane for a logical role (e.g. "operator"); role-addressed pings
# follow it, so a recycle/self-close that moves the desk to a new pane never strands a pending
# ping on yesterday's pane. handoff-fire keeps the mapping current: --as-role writes the FIRED
# pane at every fire; recycle/self-close scan+repoint any role still naming the OLD pane.
write_role() { # $1=roles-dir $2=role $3=pane
  local dir="$1" role="$2" pane="$3" tmp
  [ -n "$dir" ] && [ -n "$role" ] && [ -n "$pane" ] || return 0
  mkdir -p "$dir" 2>/dev/null || return 0
  tmp="$dir/.$role.$$"
  if printf '%s\n' "$pane" > "$tmp" 2>/dev/null; then
    mv -f "$tmp" "$dir/$role" 2>/dev/null || rm -f "$tmp" 2>/dev/null
  else
    rm -f "$tmp" 2>/dev/null
  fi
  return 0
}
refresh_roles_for() { # $1=roles-dir $2=old-pane $3=new-pane → repoint every role naming OLD to NEW
  local dir="$1" old="$2" new="$3" f cur
  [ -d "$dir" ] && [ -n "$old" ] && [ -n "$new" ] || return 0
  for f in "$dir"/*; do
    [ -f "$f" ] || continue
    cur="$(head -n1 "$f" 2>/dev/null | tr -d '[:space:]')"
    [ "$cur" = "$old" ] && write_role "$dir" "$(basename "$f")" "$new"
  done
  return 0
}

# v3 D1 — the MAILBOX twin of refresh_roles_for. Repointing roles fixes ROLE-addressed mail, but a peer
# holding the closing pane's raw UUID (every back-channel ping ever fired carries one) would still
# enqueue into a box that no longer drains — that is the class that stranded 631/206/155 lines in the
# former-desk boxes. The `.forward` pointer makes those raw-UUID sends follow the succession too, and
# lets the successor's SessionStart adopt whatever the predecessor never consumed.
# Best-effort by construction: a missing lib / unwritable dir must NEVER abort a close.
write_forward_for() { # $1=old-pane $2=new-pane
  local old="$1" new="$2" lib
  [ -n "$old" ] && [ -n "$new" ] && [ "$old" != "$new" ] || return 0   # --terminal / --recycle: nothing to forward
  for lib in "$HF_DIR/../hooks/lib/mailbox-pending.sh" \
             "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/hooks/lib/mailbox-pending.sh" \
             "$HOME/.claude/hooks/lib/mailbox-pending.sh"; do
    # shellcheck disable=SC1090,SC1091
    [ -f "$lib" ] && { . "$lib" 2>/dev/null || true; break; }
  done
  command -v mailbox_write_forward >/dev/null 2>&1 || return 0
  mailbox_write_forward "$old" "$new" 2>/dev/null || true
  return 0
}

# ---- teardown marker (MARKER CONTRACT v1; reader = tm-watchdog) -------------------------------
# A self-close/recycle types /exit, which INTERRUPTS the in-flight turn and kills the pane mid-Bash
# — to the crash watchdog that death is indistinguishable from a real CC crash (false CRASHes), and
# a fire that never engages leaves no telemetry. This drops DETERMINISTIC teardown evidence
# immediately BEFORE the first /exit keystroke so the reader classifies a planned teardown, not a
# crash. KEY = $SESSION_ID (the CC session id the watchdog keys on — the same var FIRING_SID prefers
# at line 1596) when non-empty; when empty (the REAL self-close path — line 192 blanks it), the sid
# is recovered from the pane's registry row, which at write time still holds the DYING session's
# session_id (an in-place recycle's successor overwrites that row seconds later, which would strand
# a pane-only marker — the reader's reverse-lookup would then resolve the SUCCESSOR's sid). When a
# sid is known (either way) BOTH <sid>.json and <pane>.json are written so the reader's direct sid
# check hits regardless of registry churn; key_kind records each file's own key, and BOTH pane+sid
# go in the body so the reader can match on either. FULLY GUARDED — a marker write can NEVER block
# or fail a close. Writers never delete markers; the reader GCs them.
write_teardown_marker() { # $1=pane-uuid  $2=mode (terminal|successor|recycle)
  local _pane="${1:-}" _mode="${2:-}" _sid _dir="$HOME/.claude/watchdog/teardown" _ts
  _sid="${SESSION_ID:-}"
  if [ -z "$_sid" ] && [ -n "$_pane" ]; then
    # registry rows are pretty-printed ("session_id": "<sid>" — note the space): match tolerantly
    _sid=$(grep -oE '"session_id":[[:space:]]*"[^"]+"' \
             "${CC_REGISTRY_DIR:-$HOME/.claude/cc-registry}/$_pane.json" 2>/dev/null \
           | head -1 | sed -E 's/.*"([^"]+)"$/\1/') || true
  fi
  { [ -n "$_sid" ] || [ -n "$_pane" ]; } || return 0
  mkdir -p "$_dir" 2>/dev/null || true
  _ts="$(date -u +%FT%TZ)"
  if [ -n "$_sid" ]; then
    printf '{"key_kind":"sid","pane":"%s","sid":"%s","mode":"%s","ts":"%s"}\n' \
      "$_pane" "$_sid" "$_mode" "$_ts" > "$_dir/$_sid.json" 2>/dev/null || true
  fi
  if [ -n "$_pane" ]; then
    printf '{"key_kind":"pane","pane":"%s","sid":"%s","mode":"%s","ts":"%s"}\n' \
      "$_pane" "$_sid" "$_mode" "$_ts" > "$_dir/$_pane.json" 2>/dev/null || true
  fi
  return 0
}

# ---- P0-16 /goal >4000-char guard (a19 D-11) -------------------------------------------------
# A /goal payload line whose condition exceeds the harness's 4000-char cap is a SILENT dead fire —
# the successor spawns task-less and idles believing nothing to do (observed 2026-07-10). Hard-fail
# PRE-fire, naming the size and the pointer-form fix.
check_goal_length() { # $1=prompt-file → 0 ok, 1 (loud) if a /goal line body exceeds the cap
  local pf="$1" limit="${GOAL_MAX_CHARS:-4000}" line body chars bytes
  [ -f "$pf" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      /goal|/goal\ *)
        body="${line#/goal}"; body="${body# }"
        chars=${#body}
        if [ "$chars" -gt "$limit" ]; then
          bytes=$(printf '%s' "$body" | wc -c | tr -d ' ')
          echo "!! /goal condition is ${chars} chars (${bytes} bytes) — the harness HARD-CAPS /goal at ${limit} chars; over-cap is a SILENT dead fire (the pane spawns task-less and idles). a19 D-11 / observed 2026-07-10." >&2
          echo "   Fix: use the POINTER form — '/goal read <plan/brief path> § \"Definition of Done\" and satisfy every item' — keeping the literal condition <=${limit} chars." >&2
          return 1
        fi ;;
    esac
  done < "$pf"
  return 0
}

# ---- P0-16b slash-command HEAD guard (item ff2d6609a33e) --------------------------------------
# check_goal_length above measures a /goal LINE's own body — but the live failure is one level up:
# when the payload's FIRST line is a slash command, the harness parses the WHOLE submission as that
# command, so a short `/goal do the thing.` followed by a 6000-char brief blows the 4000-char cap on
# text the line-scan never counted. The prompt is rejected, nothing submits, and the pane idles at an
# empty composer looking fired (memory handoff-fire-goal-prefix-trap). Briefs must start with PLAIN
# TEXT; a /goal head over the cap is REFUSED (never a silent dead fire), any other slash head warns.
check_slash_head() { # $1=prompt-file → 0 ok/warned, 1 (loud) if a /goal head would exceed the cap
  local pf="$1" limit="${GOAL_MAX_CHARS:-4000}" line head total
  [ -f "$pf" ] || return 0
  [ "${FIRE_ALLOW_SLASH_HEAD:-0}" = 1 ] && return 0
  # first NON-EMPTY line — leading blank lines do not change how the harness parses the payload.
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in ''|[[:space:]]*) [ -z "${line//[[:space:]]/}" ] && continue ;; esac
    break
  done < "$pf"
  case "$line" in /*) : ;; *) return 0 ;; esac
  head="${line%%[[:space:]]*}"
  total=$(wc -c < "$pf" | tr -d ' ')
  if [ "$head" = "/goal" ] && [ "$total" -gt "$limit" ]; then
    echo "!! prompt STARTS with $head and the whole payload is ${total} chars — the harness parses the ENTIRE submission as $head and HARD-CAPS it at ${limit}, so this fire would be REJECTED and the pane would idle at an empty composer (memory handoff-fire-goal-prefix-trap)." >&2
    echo "   Fix: start the brief with PLAIN TEXT (move /goal to its own short pointer line, or drop it) — e.g. 'TASK — <one line>. …', keeping any /goal condition <=${limit} chars." >&2
    return 1
  fi
  echo "⚠ prompt starts with the slash command '$head' — the harness parses the whole submission as a command, not a brief. Prefer a PLAIN-TEXT first line (handoff-fire-goal-prefix-trap)." >&2
  return 0
}

# ---- T-P2-5 (F3 / G-P2-5): payload back-channel lint PRE-FIRE ---------------------------------
# The W5 incident ROOT: a successor-fire payload DROPPED the back-channel block (a cc-notify recipe +
# a resolvable desk target), so the fired successor had no VERIFIED channel to the desk and its
# terminal announce silently degraded (SendMessage → disk-truth); the desk learned of the ship 50 min
# late FROM THE OPERATOR. payload-lint.sh (F5's sibling) makes that RED — but until this caller nothing
# linted a payload before firing (the tool was DEAD in the live loop, p02 G-P2-5).
# We gate a fire ONLY when the payload INTENDS a back-channel — it references cc-notify, or it prescribes
# a SendMessage terminal-announce (the W5 degrade, F3/a). A pure one-way fire (no such reference) is NOT
# gated: fire-and-forget is the documented default (commands/handoff.md §8), and one-way payloads legitimately
# carry no back-channel. payload-lint accepts role-indirection (cc-roles/<role>, --role) so every /goal
# fire — which resolves the desk via `cat ~/.claude/cc-roles/desk`, not a frozen uuid — passes.
#   $1 = payload file   $2 = mode: 'enforce' (abort a RED-with-intent fire, return 4) | 'preview' (report only)
payload_lint_gate() {
  local pf="$1" mode="$2" out rc intent=0
  [ -x "$PAYLOAD_LINT_BIN" ] || return 0     # lint tool absent → cannot gate (best-effort; upstream -f/-s guards ran)
  if out="$("$PAYLOAD_LINT_BIN" "$pf" 2>&1)"; then rc=0; else rc=$?; fi
  [ "$rc" -eq 0 ] && return 0                # GREEN — a well-formed (or one-way, no-cc-notify) block; nothing to say
  # RED (1) or INDETERMINATE (2). Intent = a prescriptive SendMessage terminal-announce (F3/a, the W5 bug
  # regardless of intent) OR a cc-notify reference (the payload MEANT to announce back but botched the block).
  if printf '%s' "$out" | grep -q 'F3/a' || grep -qE 'cc-notify' "$pf" 2>/dev/null; then intent=1; fi
  if [ "$rc" -eq 1 ] && [ "$intent" = 1 ]; then
    if [ "$mode" = enforce ]; then
      echo "!! handoff-fire ABORTED (F3 / T-P2-5): the fired payload's back-channel is malformed — a fired successor could NOT reliably announce to the desk (the W5 root)." >&2
      printf '%s\n' "$out" >&2
      echo "!! Fix the payload: a real back-channel — cc-notify <desk-uuid>, or the desk ROLE (cc-notify \"\$(cat ~/.claude/cc-roles/desk)\" / --role desk) — and NEVER prescribe SendMessage for a desk/terminal announce. For a deliberate one-way fire, drop the cc-notify reference." >&2
      return 4
    fi
    echo "payload-lint (preview): WOULD BLOCK this fire — RED, back-channel intended but malformed:" >&2
    printf '%s\n' "$out" >&2
    return 0
  fi
  # RED with no back-channel intent (a one-way fire), or INDETERMINATE → LOUD note, never block.
  if [ "$rc" -eq 2 ]; then
    echo "⚠ payload-lint: INDETERMINATE — $out (proceeding; the empty/missing prompt guards already passed)" >&2
  else
    echo "⚠ payload-lint (advisory): one-way fire with no back-channel block — a fired session cannot announce back. Add --notify-back or a cc-notify recipe if a completion ping is expected." >&2
  fi
  return 0
}

# Internal: self-close watcher (spawned via detach() = setsid; nohup alone dies with the tool
# call's process group when /exit interrupts the calling turn — see detach() header).
# ARCHITECTURAL CONSTRAINT: osascript AppleEvents to iTerm2 fail unreliably from detached/orphaned
# contexts (empirically: 3 detached runs, 3 silent write/lookup failures; foreground never failed).
# So ALL keystrokes happen FOREGROUND at arm time (they queue behind the calling turn), and this
# watcher does ONLY AppleEvent-free work: ps-based tty polling + the it2 shim close (python
# websocket API — proven reliable detached). `sleep` here is plain sleep: no AppleEvents needed.
if [ "${1:-}" = "__selfclose" ]; then
  SID="${2:?__selfclose needs a session id}"
  TTY_PATH="${3:-}"                                # acquired foreground at arm time — trustworthy
  SUCCESSOR="${4:-}"                               # verified-alive pane to focus after the close
  echo "→ armed: __selfclose pid=$$ sid=$SID tty=${TTY_PATH:-none} successor=${SUCCESSOR:-none}"
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
  if [ -n "$SUCCESSOR" ]; then
    # Succession legibility: land the operator's view ON the continuation. it2 python-API CLI
    # only (AppleEvent-free — proven detached); best-effort: the announce already sits in the
    # successor's transcript/mailbox even if this focus fails.
    if "$HOME/.claude/bin/it2" session focus "$SUCCESSOR" >/dev/null 2>&1; then
      echo "→ focus handed to successor $SUCCESSOR"
    else
      echo "⚠ focus hand-over to $SUCCESSOR failed (pane gone or it2 error) — succession is announced in its transcript/mailbox"
    fi
  fi
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
  echo "→ armed: __recycle pid=$$ pgid=$(ps -o pgid= -p $$ | tr -d ' ') sid=$RSID tty=$TTY_PATH"
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
  echo "→ claude exited after ${waited}s — typing relaunch"
  sleep 2                                        # shell-prompt settle after claude exits
  ok=0
  for _ in 1 2; do
    if it2_type_verified "$IT2" "$RSID" "$(cat "$CMDFILE")"; then ok=1; break; fi
    sleep 3
  done
  [ "$ok" = 1 ] || { echo "!! it2 relaunch write failed twice — run manually in the pane: $(cat "$CMDFILE")" >&2; exit 1; }
  echo "→ relaunch typed into $RSID: $(cat "$CMDFILE")"
  # Confirm the successor actually STARTS — a mistyped launcher, missing shell function, or
  # auth bounce otherwise dies silently and strands the pane at a prompt. One guarded retype
  # (skipped if claude appeared meanwhile — a late first launch must not get a second prompt
  # typed into its composer), then scream INTO THE PANE via it2 (the one write path proven
  # reliable detached) so a human at the pane sees the fallback even without the log.
  up=0
  for _ in $(seq 1 15); do sleep 3; if cc_alive; then up=1; break; fi; done
  if [ "$up" = 0 ] && ! cc_alive; then
    echo "⚠ no claude on $TTY_PATH 45s after relaunch — retyping once"
    it2_type_verified "$IT2" "$RSID" "$(cat "$CMDFILE")" || true
    for _ in $(seq 1 15); do sleep 3; if cc_alive; then up=1; break; fi; done
  fi
  if [ "$up" = 1 ] || cc_alive; then
    echo "→ relaunched + CONFIRMED in $RSID (claude process on tty)"
    exit 0
  fi
  "$IT2" session run -s "$RSID" "# HANDOFF RELAUNCH FAILED — run manually: $(cat "$CMDFILE")" >/dev/null 2>&1 || true
  echo "!! relaunch typed but no claude process appeared within 90s — fallback comment typed into pane" >&2
  exit 1
fi

# ---- Part A2: pre-handoff account sweep -------------------------------------------------------
# Before a fire we CANNOT hand off blind to a stranded account: `claude-accounts` drops an account
# whose auth is broken (logged-out / token-invalid / keychain-error) from routing AND hides its
# quota, so a wave silently over-loads the survivors while a whole account's headroom is stranded.
# This sweep runs `claude-accounts --fresh --json` (which auto-heals STALE accounts in-process and
# repopulates the shared cache the subsequent `--rank` reads), then for each still-broken account
# either (a) runs account-relogin Phase-1 headlessly — the SAME rotation-safe `claude auth login`
# refresh grant `claude-accounts` heal() does, gated to a present refresh token + ZERO live sessions
# + the SAME per-account lock — or (b) emits ONE bridge line (account + last-known quota + relogin
# pointer) that gets embedded in the fired brief so the successor can re-auth or route around it.
# SAFE-BY-CONSTRUCTION: the sweep NEVER blocks/aborts a fire (best-effort, returns 0 on any error);
# the relogin is fail-CLOSED (acts only on provably-recoverable state via the official binary, never
# a raw token POST, never under a live CC that owns the token lifecycle). Design: docs/research/
# desk-anti-hitl-2026-07-19.md Part A (rec. 2). Last-known quota for a stranded account now comes from
# the durable last-good ledger (rec. 1, landed e98f366): claude-accounts stamps stale_quota + weekly_pct
# + quota_as_of onto the `--fresh --json` rows this sweep already fetches, sourced from its TTL-free
# ~/.claude/logs/claude-accounts-lastgood.json — not the decaying /tmp cache .prev snapshot.

# The macOS keychain `-a` account for the Phase-1 relogin read (mirrors claude-accounts read_creds):
# env override wins (tests), else the accounts SSOT, else the login user.
_sweep_keychain_account() {
  [ -n "${CC_KEYCHAIN_ACCOUNT:-}" ] && { printf '%s' "$CC_KEYCHAIN_ACCOUNT"; return 0; }
  local v=""
  if command -v jq >/dev/null 2>&1 && [ -f "$CC_ACCOUNTS_JSON" ]; then
    v="$(jq -r '.keychain_account // empty' "$CC_ACCOUNTS_JSON" 2>/dev/null || true)"
  fi
  [ -n "$v" ] && { printf '%s' "$v"; return 0; }
  printf '%s' "${USER:-chrisren}"
}

# Last-known weekly% for a now-broken account, read from the durable last-good ledger as surfaced on
# the in-hand `--fresh --json` rows (Part-A1, e98f366): claude-accounts' inherit_lastgood stamps a
# broken row with stale_quota + weekly_pct + quota_as_of from its TTL-free ledger (with a .prev
# fallback baked in on the claude-accounts side). Unlike the old direct .prev read this survives a
# /tmp-sweep/reboot and does not decay after one sweep. The `@ HH:MM` recency stamp — re-derived from
# quota_as_of in local time, mirroring the dashboard table — lets the successor weigh how stale the
# number is. "weekly n/a" when no good sweep ever recorded the account.
_sweep_lastknown_weekly() { # $1=acct  $2=sweep-json (the --fresh --json already fetched at call time)
  local a="$1" j="${2:-}" wp="" asof="" stamp="" base="" epoch=""
  command -v jq >/dev/null 2>&1 || { printf 'weekly n/a'; return 0; }
  wp="$(printf '%s' "$j" | jq -r --arg a "$a" \
    '.rows[]? | select(.acct==$a and .stale_quota==true) | .weekly_pct // empty' 2>/dev/null || true)"
  case "$wp" in ''|null) printf 'weekly n/a'; return 0 ;; esac
  asof="$(printf '%s' "$j" | jq -r --arg a "$a" \
    '.rows[]? | select(.acct==$a) | .quota_as_of // empty' 2>/dev/null || true)"
  # quota_as_of is ISO-8601 UTC (…T…+00:00). Take the first 19 chars (YYYY-MM-DDTHH:MM:SS), parse as
  # UTC, render local — "HH:MM" when captured today, else "Mon DD". Unparseable/absent ⇒ omit "@ …".
  if [ -n "$asof" ] && [ "$asof" != null ]; then
    base="${asof:0:19}"
    epoch="$(date -j -u -f '%Y-%m-%dT%H:%M:%S' "$base" +%s 2>/dev/null || true)"
    if [ -n "$epoch" ]; then
      if [ "$(date -r "$epoch" +%Y%m%d 2>/dev/null)" = "$(date +%Y%m%d)" ]; then
        stamp=" @ $(date -r "$epoch" +%H:%M 2>/dev/null)"
      else
        stamp=" @ $(date -r "$epoch" '+%a %d' 2>/dev/null)"
      fi
    fi
  fi
  printf 'weekly ~%s%%%s' "$wp" "$stamp"
}

_sweep_write_stamp() { # $1=epoch-ts  $2=bridge-section — throttle stamp so a wave reuses one sweep
  command -v jq >/dev/null 2>&1 || return 0
  local tmp="$ACCOUNT_SWEEP_STAMP.$$.tmp"
  if jq -cn --argjson ts "${1:-0}" --arg bridge "${2:-}" '{ts:$ts, bridge:$bridge}' > "$tmp" 2>/dev/null; then
    mv -f "$tmp" "$ACCOUNT_SWEEP_STAMP" 2>/dev/null || rm -f "$tmp" 2>/dev/null
  else
    rm -f "$tmp" 2>/dev/null
  fi
  return 0
}

# Phase-1 headless relogin for ONE account — the official-binary refresh grant, done in Python so it
# interlocks with claude-accounts heal() on the EXACT same fcntl lock + reads the refresh token from
# the SAME keychain item. Exit: 0 healed · 3 deferred (another heal/login in flight) · 1 failed
# (no/invalid refresh token, revoked grant, timeout). Prints a short detail on non-zero.
phase1_relogin() { # $1=acct $2=config_dir $3=keychain_service $4=keychain_account $5=claude_bin $6=oauth_scopes
  CC_SECURITY_BIN="$CC_SECURITY_BIN" SVC="$3" KCA="$4" CFGDIR="$2" CBIN="$5" SCOPES="$6" \
  RELOGIN_TIMEOUT="$ACCOUNT_SWEEP_RELOGIN_TIMEOUT_S" HEAL_LOCK_PREFIX="$CC_HEAL_LOCK_PREFIX" \
  /usr/bin/python3 - "$1" <<'PY'
import os, sys, json, subprocess, fcntl
sec = os.environ.get("CC_SECURITY_BIN") or "security"
svc, kca, cfgdir = os.environ["SVC"], os.environ["KCA"], os.environ["CFGDIR"]
cbin, scopes = os.environ["CBIN"], os.environ["SCOPES"]
acct = sys.argv[1]
try:
    timeout = int(os.environ.get("RELOGIN_TIMEOUT", "90"))
except ValueError:
    timeout = 90
if not (cfgdir and svc and cbin):
    print("missing relogin-info (config_dir/keychain_service/claude_bin)"); sys.exit(1)
# 1. read the refresh token from the SAME keychain item claude-accounts reads (never a raw POST)
try:
    p = subprocess.run([sec, "find-generic-password", "-s", svc, "-a", kca, "-w"],
                       capture_output=True, text=True, timeout=10)
except Exception as e:                                   # noqa: BLE001 — best-effort, any failure = no heal
    print(f"keychain read error: {type(e).__name__}"); sys.exit(1)
if p.returncode != 0:
    print("keychain read failed (no item / locked)"); sys.exit(1)
try:
    rt = (json.loads(p.stdout).get("claudeAiOauth") or {}).get("refreshToken")
except (ValueError, AttributeError):
    rt = None
if not rt:
    print("no refresh token in keychain"); sys.exit(1)
# 2. serialize on the EXACT lock claude-accounts heal() uses — never two logins on one account
lock_path = os.environ.get("HEAL_LOCK_PREFIX", "/tmp/claude-accounts-heal-") + acct + ".lock"
try:
    lock = open(lock_path, "w")
    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
except BlockingIOError:
    print("another heal/login in flight"); sys.exit(3)
except OSError as e:
    print(f"lock error: {type(e).__name__}"); sys.exit(1)
# 3. the rotation-safe refresh grant — the binary persists the (possibly rotated) tokens itself
env = os.environ.copy()
env["CLAUDE_CONFIG_DIR"] = cfgdir
env["CLAUDE_CODE_OAUTH_REFRESH_TOKEN"] = rt
env["CLAUDE_CODE_OAUTH_SCOPES"] = scopes
try:
    r = subprocess.run([cbin, "auth", "login"], env=env, capture_output=True,
                       text=True, timeout=timeout)
except subprocess.TimeoutExpired:
    print("relogin timed out"); sys.exit(1)
except Exception as e:                                   # noqa: BLE001
    print(f"relogin error: {type(e).__name__}"); sys.exit(1)
out = (r.stdout + r.stderr).strip()
if r.returncode == 0 and "Login successful" in out:
    sys.exit(0)
print((out.splitlines() or [f"rc={r.returncode}"])[-1][:120]); sys.exit(1)
PY
}

# Orchestrator. Sets ACCOUNT_SWEEP_BRIDGE to the embeddable "## ACCOUNT STATE" section (non-empty
# ONLY when ≥1 account is stranded). Always returns 0 — a sweep failure must never block a fire.
# $1="force" bypasses the throttle (the manual `account-sweep` subcommand passes it).
pre_fire_account_sweep() {
  local force="${1:-}"
  ACCOUNT_SWEEP_BRIDGE=""
  [ "$ACCOUNT_SWEEP" = off ] && { echo "→ pre-fire account sweep: OFF (HANDOFF_ACCOUNT_SWEEP=off)" >&2; return 0; }
  # Test isolation: under bats, never touch the REAL claude-accounts (network + a possible real
  # relogin as a test side effect). A test that exercises the sweep opts in via a CC_ACCOUNTS_BIN
  # stub; production never sets BATS_TEST_TMPDIR, so it is unaffected.
  if [ -n "${BATS_TEST_TMPDIR:-}" ] && [ "${CC_ACCOUNTS_BIN_EXPLICIT:-0}" != 1 ]; then
    echo "→ pre-fire account sweep: skipped (bats env, no CC_ACCOUNTS_BIN stub)" >&2; return 0
  fi
  command -v jq >/dev/null 2>&1 || { echo "→ pre-fire account sweep: skipped (jq not found)" >&2; return 0; }
  command -v "$CC_ACCOUNTS_BIN" >/dev/null 2>&1 || { echo "→ pre-fire account sweep: skipped ($CC_ACCOUNTS_BIN not on PATH)" >&2; return 0; }

  local now; now="$(date +%s)"
  # throttle: reuse the last sweep's bridge within the window so a wave doesn't stampede the endpoint
  if [ "$force" != force ] && [ "${ACCOUNT_SWEEP_THROTTLE_S:-0}" -gt 0 ] && [ -f "$ACCOUNT_SWEEP_STAMP" ]; then
    local ts age
    ts="$(jq -r '.ts // 0' "$ACCOUNT_SWEEP_STAMP" 2>/dev/null || echo 0)"; ts="${ts%.*}"
    age=$(( now - ${ts:-0} ))
    if [ "$age" -ge 0 ] && [ "$age" -lt "$ACCOUNT_SWEEP_THROTTLE_S" ]; then
      ACCOUNT_SWEEP_BRIDGE="$(jq -r '.bridge // ""' "$ACCOUNT_SWEEP_STAMP" 2>/dev/null || true)"
      local note=""; [ -n "$ACCOUNT_SWEEP_BRIDGE" ] && note=" — stranded account(s), see bridge"
      echo "→ pre-fire account sweep: reused (${age}s < ${ACCOUNT_SWEEP_THROTTLE_S}s throttle)$note" >&2
      return 0
    fi
  fi

  # 1. live sweep + auto-heal (STALE accounts self-heal inside --fresh; the shared cache is rewritten)
  local json total broken
  json="$("$CC_ACCOUNTS_BIN" --fresh --json 2>/dev/null || true)"
  [ -n "$json" ] || { echo "⚠ pre-fire account sweep: '$CC_ACCOUNTS_BIN --fresh --json' returned nothing — skipping (fire proceeds)" >&2; return 0; }
  total="$(printf '%s' "$json" | jq -r '.rows | length' 2>/dev/null || echo 0)"
  broken="$(printf '%s' "$json" | jq -r '.rows[] | select(.auth=="logged-out" or .auth=="token-invalid" or .auth=="keychain-error") | [.acct, .auth, (.k // 0)] | @tsv' 2>/dev/null || true)"
  if [ -z "$broken" ]; then
    echo "→ pre-fire account sweep: ${total:-?}/${total:-?} accounts healthy (or auto-healed)" >&2
    _sweep_write_stamp "$now" ""
    return 0
  fi

  # 2. per broken account: Phase-1 headless relogin when eligible, else a bridge line
  local healed=0 stranded=0 stranded_lines="" summary=""
  local acct auth k info hrt kstate cfgdir svc cbin scopes kca lastknown rc detail why
  while IFS="$(printf '\t')" read -r acct auth k; do
    [ -n "$acct" ] || continue
    info="$("$CC_ACCOUNTS_BIN" --relogin-info "$acct" 2>/dev/null || true)"
    hrt="$(printf '%s' "$info" | jq -r '.has_refresh_token // false' 2>/dev/null || echo false)"
    kstate="$(printf '%s' "$info" | jq -r '.keychain_state // "unknown"' 2>/dev/null || echo unknown)"
    cfgdir="$(printf '%s' "$info" | jq -r '.config_dir // ""' 2>/dev/null || true)"
    svc="$(printf '%s' "$info" | jq -r '.keychain_service // ""' 2>/dev/null || true)"
    cbin="$(printf '%s' "$info" | jq -r '.claude_bin // ""' 2>/dev/null || true)"
    scopes="$(printf '%s' "$info" | jq -r '.oauth_scopes // ""' 2>/dev/null || true)"
    kca="$(_sweep_keychain_account)"
    lastknown="$(_sweep_lastknown_weekly "$acct" "$json")"

    # Phase-1 eligibility: refresh token present + keychain readable + ZERO live sessions (a live CC
    # owns the token lifecycle — never relogin under it; heal()'s k==0 gate). logged-out/keychain-error
    # inherently fail has_refresh_token, so this branch is reached only by a recoverable token-invalid.
    if [ "$hrt" = true ] && [ "$kstate" = present ] && [ "${k:-0}" = 0 ] && [ -n "$cfgdir$svc$cbin" ]; then
      rc=0; detail="$(phase1_relogin "$acct" "$cfgdir" "$svc" "$kca" "$cbin" "$scopes")" || rc=$?
      if [ "$rc" = 0 ]; then
        healed=$((healed+1)); summary="$summary ✓$acct(healed)"
        echo "→ pre-fire account sweep: $acct was $auth → healed via Phase-1 headless relogin" >&2
        continue
      elif [ "$rc" = 3 ]; then
        summary="$summary ↻$acct(deferred)"
        echo "→ pre-fire account sweep: $acct $auth — Phase-1 relogin deferred (${detail:-in flight})" >&2
        continue
      fi
      stranded=$((stranded+1)); summary="$summary ⚠$acct($auth,relogin-failed)"
      stranded_lines="$stranded_lines
- $acct — $auth · Phase-1 headless relogin FAILED (${detail:-unknown}) · last-known $lastknown · fix: \`$CC_ACCOUNTS_BIN --relogin-info $acct\` → account-relogin skill (Phase 2, browser)"
    else
      why="no refresh token — headless relogin N/A"
      [ "${k:-0}" != 0 ] && why="$k live session(s) — token owned by a running CC (never relogin under it)"
      stranded=$((stranded+1)); summary="$summary ⚠$acct($auth)"
      stranded_lines="$stranded_lines
- $acct — $auth · $why · last-known $lastknown · fix: \`$CC_ACCOUNTS_BIN --relogin-info $acct\` → account-relogin skill (Phase 2, browser)"
    fi
  done <<EOF
$broken
EOF

  # 3. assemble the embeddable bridge section (only the actionable stranded lines)
  if [ "$stranded" -gt 0 ]; then
    ACCOUNT_SWEEP_BRIDGE="$(printf '## ACCOUNT STATE — pre-fire sweep (%d of %s account(s) NOT routable)\nQuota is stranded on these — before routing further work here, re-auth or route around them:%s' "$stranded" "${total:-?}" "$stranded_lines")"
  fi
  local routable=$(( ${total:-0} - stranded ))
  echo "⚠ pre-fire account sweep: ${routable}/${total:-?} routable · healed=$healed stranded=$stranded ·$summary" >&2
  _sweep_write_stamp "$now" "$ACCOUNT_SWEEP_BRIDGE"
  return 0
}

# account-sweep — manual/test entrypoint: run the sweep now, print the embeddable bridge section to
# stdout (empty when all accounts are routable), exit 0. Fresh by default (bypasses the wave throttle);
# `--throttled` respects it (the exact path a fire takes). Used by /handoff and tests.
if [ "${1:-}" = "account-sweep" ]; then
  if [ "${2:-}" = "--throttled" ]; then pre_fire_account_sweep; else pre_fire_account_sweep force; fi
  [ -n "$ACCOUNT_SWEEP_BRIDGE" ] && printf '%s\n' "$ACCOUNT_SWEEP_BRIDGE"
  exit 0
fi

# land — desk-local land helper (cc-backlog c06778fd13a7). Land a worktree's committed, gate-green
# work onto origin/<trunk> via the sanctioned scripts/ship-land.sh, reached through THIS
# allow-listed entry (Bash(~/.claude/scripts/handoff-fire.sh:*)) so the desk — which lives in the
# shared checkout on `main`, where a direct `git push` is classifier-denied and the hook-allowed
# HEAD:main shape is unreachable (wrong cwd) — can land its own work autonomously. Thin by design:
# all logic + fail-closed guards live in the sibling scripts/desk-land.sh, run as a SUBPROCESS of
# this one approved Bash call, so the land never re-enters the auto-mode classifier. desk-land's
# exit code passes through verbatim (2/3/5/6/7/8 from the ship rail; 64/65/66 = desk-land preflight).
if [ "${1:-}" = "land" ]; then
  shift
  exec "$HF_DIR/desk-land.sh" "$@"
fi

# self-close — arm the detached watcher that retires this session once the calling turn ends.
if [ "${1:-}" = "self-close" ]; then
  shift
  SC_SID="" SC_ALLOW_DIRTY=0 SC_DRY=0 SC_SUCCESSOR="" SC_TERMINAL=0 SC_NO_NOTIFY=0 SC_DIRTY_OWNER=""
  while [ $# -gt 0 ]; do case "$1" in
    --session-id)  SC_SID="${2:?--session-id needs a value}"; shift 2 ;;
    --successor)   SC_SUCCESSOR="${2:?--successor needs a pane uuid}"; shift 2 ;;
    --terminal)    SC_TERMINAL=1; shift ;;
    --no-notify)   SC_NO_NOTIFY=1; shift ;;
    --dirty-owner) SC_DIRTY_OWNER="${2:?--dirty-owner needs a value (successor)}"; shift 2 ;;
    --allow-dirty) SC_ALLOW_DIRTY=1; shift ;;
    --dry-run)     SC_DRY=1; shift ;;
    *) echo "!! unknown self-close arg: $1" >&2; exit 1 ;;
  esac; done
  ITSID="${ITERM_SESSION_ID:-}"
  SC_SID="${SC_SID:-${ITSID##*:}}"
  [ -n "$SC_SID" ] || { echo "!! self-close needs \$ITERM_SESSION_ID or --session-id" >&2; exit 1; }
  # SUCCESSION STATEMENT (mandatory). A pane close is operator-visible surface: 3× on 2026-07-13
  # a close with no declared continuation read as "the handoff killed our session" — twice a real
  # stranding (pre-setsid recycle watcher), once a PERFECT succession whose successor was simply
  # invisible (the announce died with the closing pane; no focus hand-over). The caller must say
  # what continues the work; "I just close" is not a state this tool accepts.
  if [ -n "$SC_SUCCESSOR" ] && [ "$SC_TERMINAL" = 1 ]; then
    echo "!! self-close: --successor and --terminal are mutually exclusive" >&2; exit 2
  fi
  if [ -z "$SC_SUCCESSOR" ] && [ "$SC_TERMINAL" = 0 ]; then
    cat >&2 <<'USAGE'
!! self-close REFUSED: no succession statement.
!!   --successor <pane-uuid>  the live continuation session's pane — verified alive, announced
!!                            (cc-notify into ITS transcript + mailbox), focused after the close
!!   --terminal               end-of-line: nothing continues this session's work
!! (memory: handoff-succession-legibility, 2026-07-13)
USAGE
    exit 2
  fi
  if [ -n "$SC_DIRTY_OWNER" ] && { [ "$SC_DIRTY_OWNER" != "successor" ] || [ -z "$SC_SUCCESSOR" ]; }; then
    echo "!! self-close: --dirty-owner takes exactly 'successor' and requires --successor" >&2; exit 2
  fi
  if [ "$SC_SUCCESSOR" = "$SC_SID" ]; then
    echo "!! self-close: successor must be a DIFFERENT pane than the one closing (use --recycle for in-place continuation)" >&2; exit 2
  fi
  # Successor liveness gate — BEFORE any side effect: pane resolvable AND a claude on its tty.
  # The irreversible step is gated on positive proof the survivor is alive (same rule as the
  # recycle watcher's armed-heartbeat: verify the EFFECT, never the intention).
  SUC_TTY=""
  if [ -n "$SC_SUCCESSOR" ]; then
    SUC_TTY="$(as_tty "$SC_SUCCESSOR")"
    if [ -z "$SUC_TTY" ]; then
      echo "!! self-close ABORTED: successor pane $SC_SUCCESSOR not found in iTerm2 — the continuation is NOT there; fix the uuid, or --terminal if truly nothing continues" >&2
      exit 3
    fi
    if ! ps -o comm= -t "$(basename "$SUC_TTY")" 2>/dev/null | grep -qE 'node|claude'; then
      echo "!! self-close ABORTED: no live claude on successor pane $SC_SUCCESSOR ($SUC_TTY) — refusing to close a session whose continuation is not running" >&2
      exit 3
    fi
    echo "→ successor verified alive: $SC_SUCCESSOR (tty $SUC_TTY)"
  fi
  # A session about to evaporate must not hold un-persisted work. (Committed-not-pushed is fine —
  # commits survive the pane; uncommitted edits do too, but silently, which is how work gets lost.)
  # SHARED-CHECKOUT REALITY (23:02 2026-07-13): the dirt in cwd may be a LIVE successor's
  # in-flight work, not this session's — --dirty-owner successor asserts exactly that (owner
  # verified alive above), keeping --allow-dirty for the genuinely lossy override.
  if [ "$SC_ALLOW_DIRTY" = 0 ] && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    # --untracked-files=no (2026-07-20): the refusal exists to stop a close from evaporating
    # UNCOMMITTED work — that means TRACKED modifications. An untracked file survives the close
    # untouched on disk, and in a shared checkout it is usually a SIBLING's scratch litter, not
    # ours; counting it made a finished session permanently unable to self-close (the pile-up
    # this fix ends). --allow-dirty remains for the genuinely lossy override.
    if [ -n "$(git status --porcelain --untracked-files=no 2>/dev/null | head -1)" ]; then
      if [ "$SC_DIRTY_OWNER" = "successor" ]; then
        echo "→ dirty tree in $(pwd) asserted owned by successor $SC_SUCCESSOR (verified alive) — the close loses nothing; proceeding"
      else
        cat >&2 <<MSG
!! refusing self-close: dirty git tree in $(pwd) — commit/stash first, or:
!!   --dirty-owner successor  the dirt is the SUCCESSOR's in-flight work on this shared checkout
!!                            (requires --successor; verified-alive owner survives the close)
!!   --allow-dirty            blunt override — un-persisted work may be lost
MSG
        exit 1
      fi
    fi
  fi
  SC_LOG="/tmp/handoff-selfclose-$SC_SID-$(date +%s).log"
  if [ "$SC_DRY" = 1 ]; then
    echo "── dry run (self-close) ─────────────────────────"
    echo "pane:      $SC_SID"
    if [ -n "$SC_SUCCESSOR" ]; then
      echo "successor: $SC_SUCCESSOR (tty $SUC_TTY — claude VERIFIED alive)"
      echo "roles:     repoint any cc-roles/* naming $SC_SID → $SC_SUCCESSOR (P0-15)"
      echo "chain:     announce succession into successor (cc-notify) → arm watcher → FOREGROUND /exit (interrupts any in-flight turn, exits in seconds) → detached ps-poll ≤180s (CR nudge @60s) → it2 force-close pane → FOCUS successor"
    else
      echo "successor: none (--terminal: end-of-line, nothing continues this session's work)"
      echo "completion: push a program-terminal completion to the '${CC_COMPLETION_ROLE:-desk}' role via completion-push (F5 / T-P2-1) — VERIFIED-or-LOUD, never silent"
      echo "chain:     completion-push → arm watcher → FOREGROUND /exit (interrupts any in-flight turn, exits in seconds) → detached ps-poll ≤180s (CR nudge @60s) → it2 force-close pane"
    fi
    exit 0
  fi
  # T-P2-1 (F5 / G-P2-1): a --terminal close is a PROGRAM-TERMINAL completion — nothing continues this
  # session's work — so push it to the desk via completion-push (F5 → cc-announce F1). Until this caller
  # NOTHING fired completion-push (it was DEAD in the loop, p02 §2c): a terminal event reached the desk
  # only on the next reload or from the operator (the W5 50-min-late ship). Fired BEFORE the /exit chain
  # (a typed /exit can interrupt this Bash tool at +ε) with capture-before-notify. NON-FATAL: a push
  # failure is recorded LOUD (completion-push exit 5) but never aborts the close — the pane must retire.
  # A --successor close is NOT terminal (work continues in the successor) → no push. The desk role is the
  # freshest target (kept current by P0-15's role-writer); a stale role degrades LOUD, never silent.
  if [ "$SC_TERMINAL" = 1 ] && [ -x "$COMPLETION_PUSH_BIN" ]; then
    if "$COMPLETION_PUSH_BIN" fire --role "${CC_COMPLETION_ROLE:-desk}" --from handoff-fire \
         --event "session $SC_SID self-closed (--terminal: nothing continues)" --detail "cwd $(pwd)"; then
      echo "→ terminal completion pushed to the '${CC_COMPLETION_ROLE:-desk}' role (F5 / T-P2-1)"
    else
      echo "⚠ terminal completion push did NOT verify (recorded LOUD by completion-push, never silent) — proceeding with the close" >&2
    fi
  fi
  # P0-15: the pane is about to close — repoint every role still naming it to the (verified-alive)
  # successor, so a role-addressed ping lands on the continuation, never on the dead pane (SO-1).
  # A --terminal close has no successor → refresh_roles_for no-ops (nothing continues).
  refresh_roles_for "$CC_ROLES_DIR" "$SC_SID" "$SC_SUCCESSOR"
  # …and the same for raw-UUID senders: leave a forward pointer on the closing pane's inbox (D1).
  write_forward_for "$SC_SID" "$SC_SUCCESSOR"
  # Succession announce — INTO the survivor, BEFORE the close chain starts. The report emitted
  # in the closing pane dies with the pane (observed 23:03 2026-07-13); the successor's
  # v2: cc-notify ENQUEUES to the successor's inbox (drained as context at its next boundary / by its
  # cc-await-ping watcher) — NO keystroke into its composer, so it can never corrupt the successor's
  # input. Failure degrades loudly but does NOT abort the close (the inbox record + post-close focus
  # still carry the succession).
  if [ -n "$SC_SUCCESSOR" ] && [ "$SC_NO_NOTIFY" = 0 ]; then
    if [ -x "$HOME/.claude/bin/cc-notify" ]; then
      if "$HOME/.claude/bin/cc-notify" "$SC_SUCCESSOR" "HANDOFF-SUCCESSION: predecessor pane $SC_SID is self-closing now ($(date '+%H:%M:%S')) — you are the active continuation of its work; the operator's view will be focused here. Close log: $SC_LOG" >/dev/null 2>&1; then
        echo "→ succession announced into $SC_SUCCESSOR's inbox (drains as context at its next boundary)"
      else
        echo "⚠ cc-notify to successor did not land (unresolvable/unwritable?) — mailbox record + post-close focus still carry the succession" >&2
      fi
    else
      echo "⚠ cc-notify unavailable — succession carried by post-close focus only" >&2
    fi
  fi
  # Keystrokes FOREGROUND (detached osascript AppleEvents fail silently — see __selfclose header).
  # ORDER IS LOAD-BEARING: watcher FIRST, /exit LAST — a typed /exit INTERRUPTS the in-flight
  # turn and exits within seconds (E2E 2026-07-03; it does NOT enqueue-to-turn-end like /clear),
  # so in own-pane use the interrupt can kill this Bash tool at /exit+ε. Arm before typing.
  SC_TTY="$(as_tty "$SC_SID")"
  if [ -n "$SC_TTY" ] && ! ps -o comm= -t "$(basename "$SC_TTY")" 2>/dev/null | grep -qE 'node|claude'; then
    # No CC on the pane (shell-only, or still launching): typing /exit would hit the SHELL and
    # vanish (observed). Nothing to exit gracefully — the watcher closes the pane directly.
    echo "→ no CC on $SC_TTY — skipping /exit, closing pane directly" >&2
    detach "$SC_LOG" "$0" __selfclose "$SC_SID" "$SC_TTY" "$SC_SUCCESSOR" >/dev/null
  else
    SC_WATCHER="$(detach "$SC_LOG" "$0" __selfclose "$SC_SID" "$SC_TTY" "$SC_SUCCESSOR")"
    if ! await_armed "$SC_LOG"; then
      kill "$SC_WATCHER" 2>/dev/null || true
      echo "!! self-close ABORTED: watcher heartbeat never appeared ($SC_LOG) — /exit NOT typed, session stays alive" >&2
      exit 1
    fi
    echo "→ self-close armed for $SC_SID: watcher pid $SC_WATCHER session-detached, heartbeat verified (log: $SC_LOG)"
    [ -n "$SC_SUCCESSOR" ] && echo "→ post-close: operator focus hands to successor $SC_SUCCESSOR" || echo "→ post-close: terminal (nothing continues this session's work)"
    # Teardown marker BEFORE the first /exit — the crash watchdog must read a planned self-close,
    # not a CRASH (the /exit interrupt kills this pane mid-Bash). Guarded: never blocks the close.
    write_teardown_marker "$SC_SID" "$([ "$SC_TERMINAL" = 1 ] && echo terminal || echo successor)" || true
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
  --surface-reason) SURFACE_REASON="${2:?--surface-reason needs a value}"; shift 2 ;;
  --probe)       PROBE=1; shift ;;
  --recycle)     RECYCLE=1; shift ;;
  --session-id)  SESSION_ID="${2:?--session-id needs a value}"; shift 2 ;;
  --notify-back) NOTIFY_BACK="${2:-}"; case "$NOTIFY_BACK" in ""|--*) NOTIFY_BACK="__self__"; shift ;; *) shift 2 ;; esac ;;
  --self-retire)    SELF_RETIRE=1; shift ;;
  --no-self-retire) SELF_RETIRE=0; shift ;;
  --as-role)     AS_ROLE="${2:?--as-role needs a value}"; shift 2 ;;
  --extra)       EXTRA="${2:?--extra needs a value}"; shift 2 ;;
  --follow)      FOLLOW=1; shift ;;
  --dry-run)     DRY=1; shift ;;
  -h|--help)     usage ;;
  *) echo "!! unknown arg: $1" >&2; usage 1 ;;
esac; done

[ -n "$PROMPT_FILE" ] || { echo "!! --prompt-file is required" >&2; usage 1; }
[ -f "$PROMPT_FILE" ] || { echo "!! missing prompt file: $PROMPT_FILE" >&2; exit 1; }
# FM-D (Fable panel 2026-07-19): an EMPTY prompt file passed the [ -f ] check and fired `claude ""` →
# a task-less-idle successor (the same class the /goal-over-cap guard documents). Reject empty BEFORE
# any side effect — every fire mode, incl. the deterministic waiting-recycle Stage-2 fire.
[ -s "$PROMPT_FILE" ] || { echo "!! empty prompt file: $PROMPT_FILE — an empty payload fires a task-less successor (FM-D)" >&2; exit 1; }
# P0-16: reject an over-cap /goal payload BEFORE any side effect (covers every fire mode).
check_goal_length "$PROMPT_FILE" || exit 1
check_slash_head  "$PROMPT_FILE" || exit 1
[ -n "$CWD" ] && [ -n "$WORKTREE" ] && { echo "!! --cwd and --worktree are mutually exclusive" >&2; exit 1; }
if [ -n "$WORKTREE" ] && ! git check-ref-format --branch "$WORKTREE" >/dev/null 2>&1; then
  echo "!! invalid branch name for --worktree: $WORKTREE" >&2; exit 1
fi

# ---- C1 (no-focus-steal): autonomous default surface --------------------------------------
# An AUTONOMOUS fire (no --follow) must NEVER split/raise the operator's active pane (the ttys018
# mis-inject, 2026-07-19). So when the operator is not following: the DEFAULT surface (no explicit
# flag) becomes a BACKGROUND tab, and an EXPLICIT --tab is likewise that background surface. Explicit
# --split-right/--split-down/--window stay as chosen but are fired without a raise + focus-asserted
# (see spawn). --follow (manual /handoff) keeps the split-right ⌘D preference + the raise, unchanged.
if [ "$RECYCLE" = 0 ] && [ "$FOLLOW" = 0 ] && { [ "$SURFACE_EXPLICIT" = 0 ] || [ "$SURFACE" = tab ]; }; then
  SURFACE="bg-tab"
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

# Account ranking. PRIMARY = claude-accounts --rank (live limits: weekly/Fable headroom ×
# reset urgency × 5h-safety × live-session spread; shared 90s cache so waves don't stampede
# the endpoint). Kind follows the model (fable fires rank on the Fable sub-cap). FALLBACK =
# ascending trailing-5h transcript activity, ONLY when live limits are unreadable (tool
# missing / endpoint down = rank exit 3). Rank exit 2 = data fine but NO account routable by
# policy (exhausted/cutoff/window) → return 1: the caller HALTS rather than firing blind.
# Never a static account order (two static lists contradicted each other within 48h).
# Output: line 1 = "# <source label>", then "account score" lines best-first.
ranked_accounts() {
  local kind=general out rc
  [ "$MODEL" = "claude-fable-5" ] && kind=fable
  if command -v claude-accounts >/dev/null 2>&1; then
    out="$(claude-accounts --rank "$kind" 2>/tmp/handoff-rank-err.$$)"; rc=$?
    if [ "$rc" = 0 ] && [ -n "$out" ]; then
      rm -f "/tmp/handoff-rank-err.$$"
      printf '# live-limits (%s)\n%s\n' "$kind" "$out"; return 0
    fi
    if [ "$rc" = 2 ]; then
      echo "✗ claude-accounts: NO account routable for $kind — $(cat "/tmp/handoff-rank-err.$$" 2>/dev/null)" >&2
      rm -f "/tmp/handoff-rank-err.$$"; return 1
    fi
    # exit 3 / other: live limits unreadable → degrade, but surface WHY first
    [ -s "/tmp/handoff-rank-err.$$" ] && echo "⚠ rank degraded (rc=$rc): $(cat "/tmp/handoff-rank-err.$$")" >&2
    rm -f "/tmp/handoff-rank-err.$$"
  fi
  # Tie-break order = the SSOT operator spend priority (accounts.json _order), NOT the retired
  # next2-first hint — on an idle machine (all-zero activity) the order IS the ranking.
  local i=0 a
  {
    printf '# activity-proxy (DEGRADED: live limits unavailable)\n'
    for a in next next4 next3 next2; do
      printf '%s %s %s\n' "$(activity "$a")" "$i" "$a"; i=$((i+1))
    done | sort -s -k1,1n -k2,2n | awk '{print $3, $1}'
  }
}

launcher_for() { # $1=account — compose launcher name from account + model
  local suffix=""
  case "$1" in next2) suffix="2" ;; next3) suffix="3" ;; next4) suffix="4" ;; esac
  if [ "$MODEL" = "claude-fable-5" ]; then echo "claude-fable${suffix}"; else echo "claude-next${suffix}"; fi
}

# ---- fire autonomy: pre-trust the launch dir -------------------------------------------------
# Claude Code shows a workspace-TRUST dialog on first launch in an untrusted directory — a gate
# SEPARATE from --permission-mode auto, so a fired peer would STALL there forever (never runs,
# never pings back on a --notify-back handoff). Fix: mark the launch dir trusted in the TARGET
# account's config BEFORE spawning, so the session skips the dialog and runs headless. Surgical —
# sets ONLY hasTrustDialogAccepted (tool prompts still apply; this is NOT --dangerously-skip-
# permissions). Idempotent + race-avoidant: skips the write entirely when the dir is already trusted.
config_dir_for_launcher() { # $1=launcher name → the account's config dir (by trailing digit)
  case "$1" in
    *2) echo "$HOME/.claude-secondary" ;;
    *3) echo "$HOME/.claude-tertiary" ;;
    *4) echo "$HOME/.claude-quaternary" ;;
    *)  echo "$HOME/.claude" ;;
  esac
}
pre_trust() { # $1=launch dir  $2=config dir
  local dir="$1" cfg="$2/.claude.json" tmp rdir
  [ -n "$dir" ] || return 0
  command -v jq >/dev/null 2>&1 || return 0
  [ -f "$cfg" ] || return 0
  # Canonicalize: Claude Code keys trust by the RESOLVED physical path (node process.cwd()),
  # so on macOS `cd /tmp/x` is trusted as /private/tmp/x (/tmp → /private/tmp symlink), and any
  # symlinked worktree parent likewise. Trust the resolved path so the entry actually matches.
  rdir="$(cd "$dir" 2>/dev/null && pwd -P)" && [ -n "$rdir" ] && dir="$rdir"
  [ "$(jq -r --arg d "$dir" '.projects[$d].hasTrustDialogAccepted // false' "$cfg" 2>/dev/null)" = "true" ] && return 0
  tmp="$cfg.nb-trust.$$"
  if jq --arg d "$dir" '.projects[$d] = ((.projects[$d] // {}) + {hasTrustDialogAccepted:true, hasCompletedProjectOnboarding:true})' \
        "$cfg" > "$tmp" 2>/dev/null && [ -s "$tmp" ]; then
    mv -f "$tmp" "$cfg" 2>/dev/null || rm -f "$tmp"
    echo "→ pre-trusted $dir in $(basename "$2") (fired session skips the workspace-trust dialog)" >&2
  else
    rm -f "$tmp" 2>/dev/null
  fi
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

# ---- Part A2: pre-handoff account sweep (auto-heal + stranded-account bridge) ------------------
# Runs BEFORE ranking so a token-invalid account healed by a headless Phase-1 relogin is written to
# the shared cache the `--rank` below reads, and any un-healable account is bridge-lined into the
# fired brief. Best-effort + non-fatal; skipped for --recycle (same-account continuation — no pick)
# and dry-run (no polling). Sets ACCOUNT_SWEEP_BRIDGE, embedded into $PF_NB in the trailer block.
if [ "$RECYCLE" = 0 ] && [ "$DRY" = 0 ]; then
  pre_fire_account_sweep || true
fi

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
  RANKED_ALL="$(ranked_accounts)" \
    || { echo "✗ halting fire: no routable account (see claude-accounts reasons above)" >&2; exit 1; }
  RANK_SRC="$(printf '%s\n' "$RANKED_ALL" | sed -n '1s/^# //p')"
  RANKED="$(printf '%s\n' "$RANKED_ALL" | tail -n +2)"         # "account score|count" best-first
  NAMES="$(printf '%s\n' "$RANKED" | awk '{print $1}')"
  if [ "$PROBE" = 1 ] && [ "$DRY" = 0 ]; then
    for a in $NAMES; do
      if reason="$(probe_account "$a")"; then CHOSEN="$a"; break
      else echo "→ probe rejected $a: $reason (walking on)" >&2; fi
    done
    [ -n "$CHOSEN" ] || { echo "✗ all $(printf '%s\n' "$NAMES" | grep -c .) ranked accounts failed the probe (others excluded by rank policy) — stop and report, don't queue." >&2; exit 1; }
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
  # match ONLY the real key (indented `active: <val>`), never a comment that mentions
  # `active:false` — the Jul-9 window-extension comment did exactly that and false-warned.
  # exactly-2-space indent = a DIRECT child of frontier_access (a deeper-nested sub-map's
  # own `active:` key must not match)
  active="$(awk '/^frontier_access:/{f=1} f && /^  active:[[:space:]]/{print $2; exit} f && /^[^[:space:]#]/ && !/^frontier_access:/{exit}' "$MODEL_CONFIG")"
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

# ---- prompt trailers: back-channel ping (--notify-back) + self-retire (default) ---------------
# Append to a COPY of the prompt (NEVER the caller's file): (a) if --notify-back, a recipe telling
# the fired session to ping the ORIGINATOR via cc-notify on completion / decision gate / blocker;
# (b) unless --no-self-retire or --recycle, a SELF-RETIRE directive so a fired PEER drives its
# trivial pre-authorized tail then self-closes its OWN pane instead of idling — because --notify-back
# SIGNALS done but does NOT CLOSE (five peers pinged then idled on a deferred "heads-up", 2026-07-17).
# Done BEFORE QP so the copy is what the fired launcher reads. --recycle is the continuation, never
# self-retires. BACK_SID mirrors FIRING_SID (the spawn anchor), computed inline to stay self-contained.
WANT_SELF_RETIRE=0
[ "$SELF_RETIRE" = 1 ] && [ "$RECYCLE" = 0 ] && WANT_SELF_RETIRE=1
# P0-11 engagement verify is active for every REAL (non-dry) non-recycle fire — it needs the
# marker embedded in a COPY of the prompt (never the caller's file), so a copy is made even when
# no trailer is requested (--no-self-retire without --notify-back). Dry runs make no copy (nothing
# fires), preserving the "original used as-is" contract the notify-back tests assert.
[ "$RECYCLE" = 0 ] && [ "$DRY" = 0 ] && ENGAGE_VERIFY=1
if [ -n "$NOTIFY_BACK" ] || [ "$WANT_SELF_RETIRE" = 1 ] || [ "$ENGAGE_VERIFY" = 1 ]; then
  [ -f "$PROMPT_FILE" ] || { echo "!! prompt trailer: prompt file not found: $PROMPT_FILE" >&2; exit 1; }
  PF_NB="$(mktemp "${TMPDIR:-/tmp}/handoff-prompt-nb-XXXXXX")" || { echo "!! prompt trailer: mktemp failed" >&2; exit 1; }
  cp "$PROMPT_FILE" "$PF_NB" || { echo "!! prompt trailer: could not copy prompt" >&2; exit 1; }
  if [ -n "$NOTIFY_BACK" ]; then
    BACK_SID="$NOTIFY_BACK"
    if [ "$BACK_SID" = "__self__" ]; then
      _nb_it="${ITERM_SESSION_ID:-}"
      BACK_SID="${SESSION_ID:-${_nb_it##*:}}"
    fi
    [ -n "$BACK_SID" ] || { echo "!! --notify-back: no \$ITERM_SESSION_ID and no UUID given" >&2; exit 1; }
    NB_SLUG="$(basename "${PROMPT_FILE%.*}")"
    # shellcheck disable=SC2016  # $HOME below is LITERAL guidance for the fired reader, not shell expansions
    {
      printf '\n'
      printf '## BACK-CHANNEL — ping the originator (%s)\n' "$BACK_SID"
      printf '%s\n' 'On completion, at a decision gate, or on a blocker, ping the session that fired this handoff:'
      printf '  cc-notify %s "HANDOFF-PING %s: <one-line status>"\n' "$BACK_SID" "$NB_SLUG"
      printf '%s\n' '(cc-notify is on PATH at $HOME/.claude/bin/cc-notify — v2 INBOX transport: it'
      printf '%s\n' "APPENDS the ping to the originator's inbox \$HOME/.claude/mailbox/<uuid>.md;"
      printf '%s\n' 'NO keystrokes — nothing is ever typed into any composer. The originator reads it'
      printf '%s\n' 'at its next safe boundary (SessionStart / UserPromptSubmit / its Stop-fold), or'
      printf '%s\n' 'within seconds if it armed cc-await-ping (the mailbox write wakes the watcher).'
      printf '%s\n' 'Trust the stderr verdict: "wake-path armed" = instant; "NO watcher armed" ='
      printf '%s\n' 'lands next turn; "mailbox only" = target gone — surface that in YOUR report and'
      printf '%s\n' 'do NOT hand-write mailbox files yourself.)'
    } >> "$PF_NB"
  fi
  if [ "$WANT_SELF_RETIRE" = 1 ]; then
    # shellcheck disable=SC2016  # $HOME below is LITERAL guidance for the fired reader, not a shell expansion
    {
      printf '\n'
      printf '## ON COMPLETION — SELF-RETIRE (do NOT idle)\n'
      printf '%s\n' 'You are a fired PEER session: the desk drives you to DONE and you CLOSE YOURSELF — you are'
      printf '%s\n' 'NOT an idle human-in-the-loop pane. When your work is finished (and you have pinged back if'
      printf '%s\n' 'asked to):'
      printf '%s\n' '  1. DRIVE any trivial, pre-authorized remaining step to a clean terminal state (push / ff /'
      printf '%s\n' '     land per the standing values). NEVER finish on a "say the word" / "heads-up" and sit'
      printf '%s\n' '     idle — that is the deference defect. A step that is GENUINELY the operator'"'"'s call is'
      printf '%s\n' '     surfaced in your ping, not a reason to idle.'
      printf '%s\n' '  2. Then retire your OWN pane (work must be committed/clean — self-close refuses a dirty tree):'
      printf '%s\n' '       $HOME/.claude/scripts/handoff-fire.sh self-close --terminal'
      printf '%s\n' 'Report, finish the trivial tail, close. Do not wait idle for input that is not coming.'
    } >> "$PF_NB"
  fi
  # Part A2: embed the pre-fire account-state bridge (only present when ≥1 account is stranded) so the
  # successor sees which accounts are NOT routable (quota stranded) + how to re-auth / route around them.
  if [ -n "$ACCOUNT_SWEEP_BRIDGE" ]; then
    { printf '\n'; printf '%s\n' "$ACCOUNT_SWEEP_BRIDGE"; } >> "$PF_NB"
  fi
  if [ "$ENGAGE_VERIFY" = 1 ]; then
    # A globally-unique engagement marker — embedded ONLY in this launch-time copy, NEVER echoed
    # to this session's own stream, so only the FIRED session's transcript can carry it. Its
    # appearance under the target account's projects dir proves the brief was ingested (P0-11).
    FIRE_MARKER="${FIRE_ENGAGE_MARKER:-HANDOFF-ENGAGE-$$-$(date +%s)-${RANDOM:-0}}"
    printf '\n<!-- handoff-fire engagement marker: %s (ignore) -->\n' "$FIRE_MARKER" >> "$PF_NB"
  fi
  PROMPT_FILE="$PF_NB"
fi

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
    # A fresh worktree bootstraps its OWN deps — PM-DETECTED, never pnpm-hardcoded. The old
    # `CI=true pnpm install --frozen-lockfile &&` broke EVERY non-Node project (Python/uv, Go,
    # Rust): `ERR_PNPM_NO_LOCKFILE` short-circuited the `&&` and the session never launched. Detect
    # the package manager by lockfile, run the matching install, then launch REGARDLESS of its exit
    # (`;` not `&&`) — a launched session self-heals its deps; an un-launched one can do nothing.
    WT_INSTALL='if [ -f pnpm-lock.yaml ]; then CI=true pnpm install --frozen-lockfile; elif [ -f bun.lockb ] || [ -f bun.lock ]; then bun install; elif [ -f package-lock.json ]; then npm ci; elif [ -f yarn.lock ]; then yarn install --frozen-lockfile; elif [ -f uv.lock ]; then { uv sync --frozen || uv sync; }; elif [ -f poetry.lock ]; then poetry install; elif [ -f Pipfile.lock ]; then pipenv sync; elif [ -f go.sum ]; then go mod download; elif [ -f Cargo.lock ]; then cargo fetch; else echo "handoff: no recognized lockfile — skipping dep install"; fi'
    CMD="cd $(printf %q "$WT") && { $WT_INSTALL ; } ; ${PREFIX}${LAUNCHER}${ARGS} \"\$(cat $QP)\""
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

# The dir the fired session lands in — pre-trusted below so it never stalls at the trust dialog.
# Recycle reuses the CURRENT pane's dir (already trusted — the running session proves it), so it
# needs no pre-trust and is excluded from the spawn path.
if   [ "$RECYCLE" = 1 ]; then LAUNCH_DIR="$PWD"
elif [ -n "$WORKTREE" ]; then LAUNCH_DIR="$WT"
elif [ -n "$CWD" ];      then LAUNCH_DIR="$CWD"
else                          LAUNCH_DIR="$REPO"
fi

# ---- spawn the surface -----------------------------------------------------------------------
# Anchor new surfaces to the FIRING session — the pane THIS script was launched from — NOT
# iTerm2's app-frontmost window. $ITERM_SESSION_ID is inherited into the Bash-tool subprocess this
# script runs in (verified), its UUID matches iTerm2's session id, and --session-id overrides the
# env-derived anchor (headless/testing).
#
# SPLIT surfaces resolve + split that anchor through the it2 PYTHON API (get_session_by_id → a
# direct hash lookup), NOT AppleScript window enumeration. Why the switch (2026-07-17, the
# operator's recurring "handoff landed in a SEPARATE window" complaint that kept getting
# per-session worked-around but never fixed on trunk): the old osascript as_split enumerated every
# window and could throw iTerm2 -1719 AFTER the split had already happened (a window/session ref
# invalidated by the split mutation). The wrapper read that as "failed" and fired a SECOND surface
# via spawn_frontmost — into the APP-FRONTMOST window, which with several windows open is some
# OTHER window: exactly the separate window the operator saw. The it2 API split is atomic — rc 0 +
# "Created new pane: <id>" on success, rc≠0 ("Session '<id>' not found") when the anchor is truly
# gone — so there is no partial-success-that-reads-as-failure class, and the fallback can FAIL LOUD
# instead of drifting to another window.
_itsid="${ITERM_SESSION_ID:-}"
FIRING_SID="${SESSION_ID:-${_itsid##*:}}"

# REAL it2 binary, NOT the $HOME/.claude/bin/it2 SHIM: the shim injects `-p Claude-Teammate` on
# every `session split` (the teammate never-prompt profile), but a handoff split wants the FIRING
# pane's OWN profile — the ⌘D "same profile" experience — which async_split_pane inherits from
# profile=None. Single source of truth for the real path = the shim's own REAL_IT2= line, so a
# Python-version bump stays a one-file edit there; if the shim is unreadable we degrade to it
# (still the correct pane — only the teammate profile differs).
IT2_SHIM="$HOME/.claude/bin/it2"
REAL_IT2="$(sed -n 's/^REAL_IT2="\(.*\)"$/\1/p' "$IT2_SHIM" 2>/dev/null | head -1)"
[ -n "$REAL_IT2" ] && [ -x "$REAL_IT2" ] || REAL_IT2="$IT2_SHIM"
[ -n "${IT2_BIN:-}" ] && REAL_IT2="$IT2_BIN"   # test seam (same convention as cc-sessions)

# PYTHON_BIN — same single-source-of-truth resolution as REAL_IT2 (the shim's own PYTHON_BIN= line,
# the interpreter with the iterm2 module). it2py() below drives the iterm2 Python API directly for the
# two things the it2 0.2.3 CLI cannot do WITHOUT stealing focus (C1): read the operator-focused session,
# and create a BACKGROUND surface then restore focus atomically. Same transport the shim uses for
# `session close -f`. Falls back to `python3` if the shim is unreadable; IT2_PYTHON_BIN is the test seam.
PYTHON_BIN="$(sed -n 's/^PYTHON_BIN="\(.*\)"$/\1/p' "$IT2_SHIM" 2>/dev/null | head -1)"
[ -n "$PYTHON_BIN" ] && [ -x "$PYTHON_BIN" ] || PYTHON_BIN="python3"
[ -n "${IT2_PYTHON_BIN:-}" ] && PYTHON_BIN="$IT2_PYTHON_BIN"

# it2py VERB [args] — iterm2 Python API driver (AppleEvent-free; the focus-safe transport). Verbs:
#   active               → print the currently-active (operator-focused) iTerm2 session id, or empty.
#   frontapp             → print the frontmost macOS application's process name (System Events), or empty.
#   bgtab FIRING         → create a BACKGROUND tab in FIRING's window, then restore the operator's PRE-
#                          CREATE focus (iTerm2 active session + frontmost app) and ASSERT it returned
#                          (self-clean + rc 5 on a genuine steal). Prints "Created new pane: <id>" rc 0;
#                          rc 1 = anchor/window gone.
#   restore SID FRONTAPP → restore SID as the active iTerm2 session + re-focus FRONTAPP (if not iTerm2),
#                          then ASSERT SID is active. rc 0 restored / rc 5 not-restored. (split path.)
# WHY order_window_front=True on the RESTORE (not on the fired surface): creating a tab/pane always
# makes it the active session (no API flag suppresses that), and only order_window_front=True reliably
# returns the operator's window+session (empirically: =False leaves focus on the new tab cross-window).
# The design's "never order_window_front=True on an autonomous fire" is about not raising the FIRED
# surface — restoring the OPERATOR's own focus is the mechanism that makes "active-session unchanged"
# hold. The frontmost-app re-focus undoes any transient iTerm2 raise for an operator in another app.
it2py() {
  "$PYTHON_BIN" - "$@" <<'PY'
import subprocess
import sys

import iterm2

rc = 0
out = []


def active_id(app):
    cw = app.current_terminal_window
    if cw is not None and cw.current_tab is not None and cw.current_tab.current_session is not None:
        return cw.current_tab.current_session.session_id
    return None


def frontmost_app():
    try:
        r = subprocess.run(
            ["osascript", "-e",
             'tell application "System Events" to name of first process whose frontmost is true'],
            capture_output=True, text=True, timeout=5)
        return r.stdout.strip()
    except Exception:  # noqa: BLE001 — focus-app read is best-effort
        return ""


def reactivate_app(name):
    # Return the operator to the app they were in before the fire (best-effort). Skip iTerm2 (the fire
    # target) and any name with a quote (can't be embedded safely — and no real app name has one).
    if not name or name == "iTerm2" or '"' in name:
        return
    try:
        subprocess.run(
            ["osascript", "-e",
             'tell application "System Events" to set frontmost of process "%s" to true' % name],
            capture_output=True, timeout=5)
    except Exception:  # noqa: BLE001 — best-effort
        pass


async def restore_focus(app, sid, frontapp):
    # Make SID the active iTerm2 session (order_window_front=True is the only reliable restore), then
    # re-focus the operator's original app. Returns True iff SID is active afterward.
    s = app.get_session_by_id(sid)
    if s is None:
        return False
    await s.async_activate(select_tab=True, order_window_front=True)
    reactivate_app(frontapp)
    return active_id(app) == sid


async def main(connection):
    global rc
    app = await iterm2.async_get_app(connection)
    verb = sys.argv[1] if len(sys.argv) > 1 else ""

    if verb == "active":
        a = active_id(app)
        out.append(a if a else "")
        return

    if verb == "frontapp":
        out.append(frontmost_app())
        return

    if verb == "restore":
        sid = sys.argv[2]
        frontapp = sys.argv[3] if len(sys.argv) > 3 else ""
        if not await restore_focus(app, sid, frontapp):
            print("Error: focus not restored to '%s'" % sid, file=sys.stderr)
            rc = 5
        return

    if verb == "bgtab":
        firing = sys.argv[2]
        s = app.get_session_by_id(firing)
        if s is None:
            print("Error: firing session '%s' not found" % firing, file=sys.stderr)
            rc = 1
            return
        window, _tab = app.get_window_and_tab_for_session(s)
        if window is None:
            print("Error: window for firing session '%s' not found" % firing, file=sys.stderr)
            rc = 1
            return
        before = active_id(app)             # capture the operator's focus BEFORE the create (atomic)
        front_before = frontmost_app()
        tab = await window.async_create_tab()
        if tab is None or tab.current_session is None:
            print("Error: create_tab returned no session", file=sys.stderr)
            rc = 1
            return
        new_sess = tab.current_session
        new_id = new_sess.session_id
        # C1: restore the operator's focus; if it will not return (their pane still exists but the
        # active session did not come back), the fire stole focus — self-clean the untyped pane and
        # fail loud. A vanished `before` pane (bs is None) is nothing-to-restore, not a steal.
        if before and app.get_session_by_id(before) is not None:
            if not await restore_focus(app, before, front_before):
                try:
                    await new_sess.async_close(force=True)
                except Exception:  # noqa: BLE001
                    pass
                print("Error: focus not restored (wanted %s) — closed pane %s" % (before, new_id),
                      file=sys.stderr)
                rc = 5
                return
        out.append("Created new pane: %s" % new_id)
        return

    print("Error: unknown it2py verb '%s'" % verb, file=sys.stderr)
    rc = 2


try:
    iterm2.run_until_complete(main)
except Exception as e:  # noqa: BLE001 — fail closed on any API/connection error
    print("iterm2 API error: %s" % e, file=sys.stderr)
    sys.exit(1)

if out:
    print("\n".join(out))
sys.exit(rc)
PY
}

# it2_bgtab FIRING — mirrors it2_split's contract (echoes the new session id | returns 1). A BACKGROUND
# tab in FIRING's window; it2py bgtab captures + restores + asserts the operator's focus atomically, so
# no split/raise of the operator's pane survives the fire (and a genuine steal self-cleans + returns 1).
it2_bgtab() {
  local out
  out="$(it2py bgtab "$1" 2>/dev/null)" || return 1
  case "$out" in
    "Created new pane: "*) printf '%s' "${out#Created new pane: }"; return 0 ;;
    *) return 1 ;;
  esac
}

# restore_focus_or_fail BEFORE FRONT NEWID LABEL — the C1 post-condition for the split path: restore
# the operator's focus (session BEFORE + frontmost app FRONT) after an autonomous split; if it cannot
# be restored, close the untyped child pane and FAIL LOUD (never silently steal / orphan). Best-effort
# skip when BEFORE is empty (focus was unreadable → nothing to assert; never a false failure).
restore_focus_or_fail() {
  local before="$1" front="$2" newid="$3" label="$4"
  [ -n "$before" ] || return 0
  it2py restore "$before" "$front" >/dev/null 2>&1 && return 0
  "$IT2_SHIM" session close -f -s "$newid" >/dev/null 2>&1 || true
  echo "!! FOCUS-STOLEN ($label): could not restore the operator's focus ($before) after the fire." >&2
  echo "   Closed the untyped pane $newid — NOTHING launched (C1: a background fire must not move focus)." >&2
  echo "   Pass --follow to intentionally land your view on the continuation, else re-fire." >&2
  return 1
}

# it2 split: split the firing pane (vertically=right / horizontally=down) inheriting ITS profile,
# and echo the new pane's session id. Returns non-zero (echoing nothing) when the anchor session is
# gone or iTerm2 errors — the caller retries-then-fails-loud, and NEVER drifts to another window.
it2_split() { # $1=firing-uuid  $2=vertically|horizontally  → echoes new session id | returns 1
  local vflag=""; [ "$2" = vertically ] && vflag="-v"
  local out; out="$("$REAL_IT2" session split -s "$1" $vflag 2>&1)" || return 1
  case "$out" in
    "Created new pane: "*) printf '%s' "${out#Created new pane: }"; return 0 ;;
    *) return 1 ;;
  esac
}

# Land the launch command into a freshly created pane. $CMD arrives RAW via `session run`
# (async_send_text + CR — the Ink-safe submit the recycle path already relies on); no AppleScript
# string-literal escaping. A fresh pane's shell needs a beat to attach its tty before it reads typed
# input, hence the settle. `session run` targets by id and does NOT move focus. The raise afterwards
# (`session focus` → async_activate(order_window_front=True)) is the OLD unconditional focus-steal —
# now gated on --follow: only a manual /handoff (operator watching) lands their view on the pane; an
# autonomous fire (FOLLOW=0) never raises (C1, the ttys018 mis-inject fix).
it2_land() { # $1=new-session-id  → 0 on typed, 1 (loud) if the pane exists but typing failed
  local id="$1" ok=0
  /bin/sleep 0.4
  for _ in 1 2; do
    if it2_type_verified "$REAL_IT2" "$id" "$CMD"; then ok=1; break; fi
    /bin/sleep 0.6
  done
  [ "$ok" = 1 ] || { echo "!! pane $id created but typing the launch command failed (2×) — run manually in it: $CMD" >&2; return 1; }
  if [ "$FOLLOW" = 1 ]; then
    "$REAL_IT2" session focus "$id" >/dev/null 2>&1 || true   # --follow: land the operator's view on the continuation
  fi
  return 0
}

# Targeted tab (opt-in --follow --tab surface): CREATE a background tab in the firing session's
# WINDOW (not the frontmost window) and echo "OK <new-session-id>" — it does NOT type. The caller
# lands the launch command via it2_land → it2_type_verified (bracketed-paste + echo-verify), the
# same ZLE-race-safe transport the split/bg-tab surfaces use, and raises the tab (--follow, via
# it2_land's session focus). Echoes "NOTFOUND" when the firing window is gone — the caller settle-
# retries then FAILS LOUD (a tab, like a split, never drifts to the app-frontmost window; only the
# deliberate --window does that). No `write text` char-stream here → no ttys018 mis-inject (the
# --tab half of item 0b878805bc27; the split/bg-tab half is e4c7e7fb41bd).
as_tab() { # $1=session-uuid  → echoes "OK <new-session-id>" | "NOTFOUND"
  osascript - "$1" <<'AS'
on run argv
  set sid to item 1 of argv
  tell application "iTerm2"
    set foundWin to missing value
    repeat with w in windows
      repeat with t in tabs of w
        repeat with s in sessions of t
          if id of s is sid then
            set foundWin to w
            exit repeat
          end if
        end repeat
        if foundWin is not missing value then exit repeat
      end repeat
      if foundWin is not missing value then exit repeat
    end repeat
    if foundWin is missing value then return "NOTFOUND"
    tell foundWin
      set newTab to (create tab with default profile)
      set newSess to current session of newTab
    end tell
    return "OK " & (id of newSess)
  end tell
end run
AS
}

# Fresh-window spawn — the ONLY surface that deliberately does NOT anchor to the firing pane
# (--window, opt-in). CREATE a brand-new iTerm2 window and echo its new session id; it does NOT
# type. The caller lands the launch command via it2_land → it2_type_verified (bracketed-paste +
# echo-verify), so there is no `write text` char-stream and no $ESC AppleScript-string escaping —
# the ttys018 mis-inject cannot reach this surface (the --window half of item 0b878805bc27). This
# is the LAST place that targets iTerm2's app-frontmost/new window; split + tab were deliberately
# removed from it (2026-07-17) so a mis-resolved anchor can only ever FAIL LOUD, never drift here.
# Zero windows → this is also the implicit surface, since there is nothing to split/tab into.
spawn_frontmost() { # → echoes the new session id on stdout | empty on failure
  # --follow raises iTerm2 (operator watching); autonomous omits `activate` so the fresh window is
  # created in the background and never pulls the operator off their current app/window (C1). The
  # raise + focus on --follow is completed by it2_land (session focus); autonomous stays background.
  if [ "$FOLLOW" = 1 ]; then
    osascript -e 'tell application "iTerm2"' \
              -e 'activate' \
              -e 'set newWin to (create window with default profile)' \
              -e 'return id of current session of newWin' \
              -e 'end tell'
  else
    osascript -e 'tell application "iTerm2"' \
              -e 'set newWin to (create window with default profile)' \
              -e 'return id of current session of newWin' \
              -e 'end tell'
  fi
}

# Dispatcher. SPLIT surfaces (the ⌘D default) go through the it2 API and, if the firing anchor
# can't be resolved, RETRY once after a settle then FAIL LOUD — they NEVER fire into another window
# (the operator's recurring complaint). --tab stays osascript-targeted to the firing window but
# ALSO fails loud (no frontmost). Only the deliberate --window uses the frontmost/fresh-window path.
# A fail-loud path returns non-zero → `set -e` aborts the script before the "→ fired" summary, so
# the calling agent sees a clean failure ("nothing launched") rather than a phantom success.
spawn() {
  # --window is SUPPOSED to open a fresh window — no firing-pane anchoring, by design. spawn_frontmost
  # CREATES the window and echoes its new session id; it2_land then lands the launch command via
  # it2_type_verified (bracketed-paste + echo-verify) and raises it on --follow. An empty id = the
  # window could not be created → FAIL LOUD (nothing launched), never a phantom success.
  if [ "$SURFACE" = "window" ]; then
    local winid
    winid="$(spawn_frontmost | tr -d '[:space:]')" || winid=""   # || guards set -e on an osascript failure
    [ -n "$winid" ] || { echo "!! could not create a fresh iTerm2 window (--window) — nothing launched." >&2; return 1; }
    it2_land "$winid" || return 1
    SPAWNED_PANE="$winid"                          # the fired pane — engagement verify + registry
    return 0
  fi
  if [ -z "$FIRING_SID" ]; then
    echo "!! no \$ITERM_SESSION_ID/--session-id to anchor to — REFUSING to fire a $SURFACE into a random window." >&2
    echo "   Re-run from inside the firing iTerm2 pane, pass --session-id <uuid>, or use --window to open a fresh window on purpose." >&2
    return 1
  fi
  case "$SURFACE" in
    bg-tab)
      # AUTONOMOUS DEFAULT — a BACKGROUND tab in the firing pane's window: never splits the operator's
      # active pane, never raises. it2_bgtab captures + restores + asserts the operator's focus
      # atomically (self-cleans + returns 1 on a genuine steal), so nothing here can move focus.
      local newid
      newid="$(it2_bgtab "$FIRING_SID")" \
        || { /bin/sleep 0.8; newid="$(it2_bgtab "$FIRING_SID")"; } \
        || { echo "!! firing window for $FIRING_SID not found in iTerm2 (settled + retried) — anchor gone; NOT firing into a random window." >&2
             echo "   Nothing was launched. Re-fire from a live pane, or pass --window for a deliberate fresh window." >&2
             return 1; }
      it2_land "$newid" || return 1
      SPAWNED_PANE="$newid"                          # the fired pane — engagement verify + registry
      ;;
    split-right|split-down)
      # C1: an explicit autonomous split still activates the child WITHIN the tab, so capture the
      # operator's focus (session + frontmost app) BEFORE the split, restore it after, and fail loud
      # if it will not return. --follow skips this: the raise is the point of a manual /handoff.
      local before="" front=""
      if [ "$FOLLOW" = 0 ]; then before="$(it2py active 2>/dev/null || true)"; front="$(it2py frontapp 2>/dev/null || true)"; fi
      local dir=vertically; [ "$SURFACE" = split-down ] && dir=horizontally
      local newid
      newid="$(it2_split "$FIRING_SID" "$dir")" \
        || { /bin/sleep 0.8; newid="$(it2_split "$FIRING_SID" "$dir")"; } \
        || { echo "!! firing pane $FIRING_SID not found in iTerm2 (settled + retried) — anchor gone; NOT firing into a random window." >&2
             echo "   Nothing was launched. Re-fire from a live pane, or pass --window for a deliberate fresh window." >&2
             return 1; }
      if [ "$FOLLOW" = 0 ]; then
        restore_focus_or_fail "$before" "$front" "$newid" "split" || return 1
      fi
      it2_land "$newid" || return 1
      SPAWNED_PANE="$newid"                          # the fired pane — engagement verify + registry
      ;;
    tab)
      # Reached only WITH --follow (autonomous --tab was normalized to bg-tab). as_tab CREATES a
      # background tab in the firing window and echoes its id; it2_land then lands the launch command
      # via it2_type_verified (bracketed-paste + echo-verify) and raises the tab (--follow).
      local out newid
      out="$(as_tab "$FIRING_SID" 2>/dev/null)" || out="ERR($?)"
      case "$out" in
        OK\ *) newid="${out#OK }" ;;
        *) /bin/sleep 0.8                            # settle + retry once, then fail loud
           out="$(as_tab "$FIRING_SID" 2>/dev/null)" || out="ERR($?)"
           case "$out" in
             OK\ *) newid="${out#OK }" ;;
             *) echo "!! firing window for $FIRING_SID not found ($out) — NOT firing a tab into a random window." >&2
                echo "   Nothing was launched. Re-fire from a live pane, or use --window for a deliberate fresh window." >&2
                return 1 ;;
           esac ;;
      esac
      it2_land "$newid" || return 1
      SPAWNED_PANE="$newid"                          # the fired pane — engagement verify + registry
      ;;
  esac
}

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
    it2_type_verified "$HOME/.claude/bin/it2" "$SID" "$CMD" \
      || { echo "!! recycle: it2 verified-type into $SID failed — run manually: $CMD" >&2; exit 1; }
    echo "→ recycled (no CC was running): typed relaunch into $SID"
    return 0
  fi
  # ORDER IS LOAD-BEARING: watcher FIRST (heartbeat-verified), /exit LAST. A typed /exit
  # INTERRUPTS the in-flight turn and exits within seconds (E2E 2026-07-03 — twice: the busy
  # turn died with no output persisted; /exit does NOT enqueue-to-turn-end the way /clear does).
  # When this script runs in its OWN pane, that interrupt kills this very Bash tool at /exit+ε
  # AND SIGKILLs its whole process group — which is why the watcher must be session-detached
  # (detach(), not nohup: 2× 2026-07-13 the nohup watcher died in that reap → 0-byte log, no
  # relaunch, stranded pane). Everything that must survive happens BEFORE the /exit keystroke,
  # and /exit is only typed once the watcher has proven itself alive (await_armed).
  WATCHER_PID="$(detach "$log" "$0" __recycle "$SID" "$tty" "$cmdfile")"
  if ! await_armed "$log"; then
    kill "$WATCHER_PID" 2>/dev/null || true
    echo "!! recycle ABORTED: watcher heartbeat never appeared ($log) — /exit NOT typed, session stays alive. Run manually: $CMD" >&2
    exit 1
  fi
  echo "→ recycle armed for $SID: watcher pid $WATCHER_PID (session-detached, heartbeat verified) relaunches $LAUNCHER once claude exits (log: $log)"
  echo "  manual fallback if no relaunch appears: $CMD"
  # Teardown marker BEFORE the first /exit — the crash watchdog must read a planned recycle, not a
  # CRASH (the /exit interrupt kills this pane mid-Bash). Guarded: never blocks the close.
  write_teardown_marker "$SID" recycle || true
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

# Split-right (⌘D) is the STANDING operator preference for handoffs. --tab/--window override it and
# should carry a reason (e.g. sliver-avoidance for many parallel fires). Advise when they don't —
# this is the guard against agents silently reverting the default to --tab session after session.
if [ "$SURFACE_EXPLICIT" = 1 ] && { [ "$SURFACE" = tab ] || [ "$SURFACE" = window ]; } && [ -z "$SURFACE_REASON" ]; then
  echo "⚠ --$SURFACE overrides the split-right (⌘D) handoff default. Prefer --split-right unless you have a reason (e.g. sliver-avoidance for many parallel fires); pass --surface-reason \"…\" to record it." >&2
fi

if [ "$DRY" = 1 ]; then
  echo "── dry run ──────────────────────────────────────"
  [ -n "$RANKED" ] && { echo "account ranking (${RANK_SRC:-unknown source}):"; printf '%s\n' "$RANKED" | while read -r a c; do echo "  $a  $c"; done; }
  echo "account:  ${CHOSEN:-auto}"
  echo "launcher: $LAUNCHER"
  if [ "$RECYCLE" = 1 ]; then
    echo "surface:  (recycle — this pane: $SID)"
    echo "chain:    arm watcher (setsid-detached, heartbeat-verified) → FOREGROUND /exit (interrupts any in-flight turn, exits in seconds — emit report/fallback BEFORE firing) → detached ps-poll ≤600s (CR nudges @60/150/300s) → it2-typed relaunch into the shell → confirm claude on tty (guarded retype, pane-visible fallback on failure)"
  else
    echo "surface:  $SURFACE"
    if [ "$FOLLOW" = 1 ]; then
      echo "follow:   YES — raises + focuses the new surface (manual /handoff, operator watching)"
    else
      echo "follow:   no — AUTONOMOUS: no raise, no split of the operator's active pane; operator focus captured + asserted unchanged, fail-loud on a steal (C1)"
    fi
    [ -n "$SURFACE_REASON" ] && echo "reason:   $SURFACE_REASON"
    case "$SURFACE" in
      bg-tab)
        if [ -n "$FIRING_SID" ]; then
          echo "anchor:   firing session $FIRING_SID — BACKGROUND tab in ITS window (no raise, no active-pane split; fail-loud if the window is gone, NEVER another window)"
        else
          echo "anchor:   (no \$ITERM_SESSION_ID/--session-id — would REFUSE to fire; pass --session-id or --window)"
        fi ;;
      split-right|split-down)
        if [ -n "$FIRING_SID" ]; then
          echo "anchor:   firing session $FIRING_SID — ${SURFACE} lands in ITS tab (it2 API ⌘D-style; fail-loud if the anchor is gone, NEVER another window)"
        else
          echo "anchor:   (no \$ITERM_SESSION_ID/--session-id — would REFUSE to fire; pass --session-id or --window)"
        fi ;;
      tab)
        if [ -n "$FIRING_SID" ]; then
          echo "anchor:   firing session $FIRING_SID — tab lands in ITS window (fail-loud if the window is gone, NEVER another window)"
        else
          echo "anchor:   (no \$ITERM_SESSION_ID/--session-id — would REFUSE to fire; pass --session-id or --window)"
        fi ;;
    esac
  fi
  if [ "$PROBE" = 1 ]; then
    pm="claude-haiku-4-5"; [ "$FABLE_EFFECTIVE" = 1 ] && pm="claude-fable-5"
    if [ "$EXPLICIT_LAUNCHER" = 1 ]; then echo "probe:    SKIPPED (explicit --launcher gives no account to probe)"
    elif [ -n "$NAMES" ]; then echo "probe:    SKIPPED in dry-run (would probe $pm walking: $(printf '%s' "$NAMES" | tr '\n' ' '))"
    else echo "probe:    SKIPPED in dry-run (would probe $pm on $CHOSEN)"; fi
  fi
  if [ "$RECYCLE" = 0 ]; then
    if [ "$ACCOUNT_SWEEP" = off ]; then echo "sweep:    account sweep OFF (HANDOFF_ACCOUNT_SWEEP=off)"
    else echo "sweep:    pre-fire claude-accounts --fresh + Phase-1 auto-heal for token-invalid; bridge-lines any stranded account into the brief (throttle ${ACCOUNT_SWEEP_THROTTLE_S}s; SKIPPED in dry-run)"; fi
  fi
  if [ -n "$WORKTREE" ]; then
    case "$WT_SETUP" in
      pool)     echo "worktree: POOL CLAIM at fire time (scripts/worktree-pool.sh claim $WORKTREE — path printed by claim; no in-pane install)" ;;
      existing) echo "worktree: $WT  (exists — reused as-is)" ;;
      *)        echo "worktree: $WT  (cold: off $BASE, created at fire time + in-pane install)" ;;
    esac
  fi
  [ -n "$NOTIFY_BACK" ] && echo "notify-back: originator $BACK_SID — fired prompt carries the cc-notify ping recipe (copy: $PROMPT_FILE)"
  if [ "$RECYCLE" = 0 ]; then
    echo "engagement: post-spawn transcript/registry-birth verify (P0-11) → re-send once on miss → FIRE FAILED (never a false '→ fired')"
    echo "registry:  provisional row if no P8 SessionStart row appears ≤${FIRE_REG_TIMEOUT:-30}s (P0-12)"
    [ -n "$AS_ROLE" ] && echo "role:      --as-role $AS_ROLE → $CC_ROLES_DIR/$AS_ROLE = <fired pane> (P0-15)"
    payload_lint_gate "$PROMPT_FILE" preview   # T-P2-5: preview the back-channel lint (dry lints the PRE-trailer payload; a --notify-back block is materialized at fire time)
  fi
  [ "$RECYCLE" = 1 ] || echo "pre-trust: $LAUNCH_DIR → $(basename "$(config_dir_for_launcher "$LAUNCHER")") (fired session skips the workspace-trust dialog)"
  echo "command:  $CMD"
elif [ "$RECYCLE" = 1 ]; then
  # P0-15: the recycled pane IS the continuation (same UUID) — keep any role naming it current,
  # and honor --as-role. refresh is a no-op when nothing named this pane.
  refresh_roles_for "$CC_ROLES_DIR" "$SID" "$SID"
  [ -n "$AS_ROLE" ] && write_role "$CC_ROLES_DIR" "$AS_ROLE" "$SID"
  recycle_fire
else
  # T-P2-5 (F3): gate the MATERIALIZED payload's back-channel before a successor fires (the W5 root).
  # RED-with-intent (cc-notify present but block malformed, or a SendMessage terminal-announce) → abort
  # LOUD (exit 4) BEFORE any side effect; a pure one-way fire passes (advisory only). Role-indirection
  # (/goal fires) passes — payload-lint accepts cc-roles/<role>.
  payload_lint_gate "$PROMPT_FILE" enforce || exit "$?"
  pre_trust "$LAUNCH_DIR" "$(config_dir_for_launcher "$LAUNCHER")"
  spawn
  # P0-11: prove the fired session ingested the brief before claiming success. A cold fire that
  # raced CC boot sits at an empty composer (INC-4) — re-send once, then FAIL LOUD.
  # per-handoff telemetry — one JSONL line per real fire so "did this handoff engage / leak / at
  # what firing-session RSS" is answerable in one grep (~/.claude/logs/handoffs.jsonl, self-bounded
  # to 500). Fully guarded: a telemetry hiccup can never affect the fire.
  emit_handoff_telemetry() { # $1 = engaged (1|0)
    local _hf_log="$HOME/.claude/logs/handoffs.jsonl" _hf_pid _hf_rss _hf_class
    # Prefer the CC session id (SESSION_ID) — watchdog pidfiles are keyed by it; FIRING_SID is a
    # PANE uuid when SESSION_ID is unset, which never matches a session-keyed pidfile.
    _hf_pid=$(cat "$HOME/.claude/watchdog/${SESSION_ID:-$FIRING_SID}.pid" 2>/dev/null || true)
    _hf_rss=$(ps -o rss= -p "${_hf_pid:-0}" 2>/dev/null | tr -d ' ' || true)
    _hf_class=$([ "${WANT_SELF_RETIRE:-0}" = 1 ] && echo self-retire-peer || echo handoff)
    mkdir -p "$HOME/.claude/logs" 2>/dev/null || true
    printf '{"ts":"%s","firing_sid":"%s","class":"%s","engaged":%s,"target_pane":"%s","account":"%s","firing_rss_kb":%s}\n' \
      "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${FIRING_SID:-?}" "$_hf_class" "${1:-0}" "${SPAWNED_PANE:-}" "${CHOSEN:-?}" "${_hf_rss:-0}" \
      >> "$_hf_log" 2>/dev/null || true
    if [ -f "$_hf_log" ] && [ "$(wc -l < "$_hf_log" 2>/dev/null || echo 0)" -gt 600 ]; then
      tail -500 "$_hf_log" > "$_hf_log.tmp" 2>/dev/null && mv "$_hf_log.tmp" "$_hf_log" 2>/dev/null || true
    fi
  }
  if [ "$ENGAGE_VERIFY" = 1 ]; then
    PROJ_DIR="$(config_dir_for_launcher "$LAUNCHER")/projects"
    if verify_engagement "$PROJ_DIR" "$FIRE_MARKER" "$REG_DIR" "$SPAWNED_PANE" "$REAL_IT2" "$(cat "$PROMPT_FILE")"; then
      emit_handoff_telemetry 1
      echo "→ engagement confirmed for the fired session (transcript/registry birth)" >&2
      # P0-12: guarantee a registry row so the reaper/board can see the fired pane.
      FIRE_NAME="$(basename "$LAUNCH_DIR")-${SPAWNED_PANE%%-*}"
      ensure_registration "$REG_DIR" "$SPAWNED_PANE" "$FIRE_NAME" "$LAUNCH_DIR" "$CMD"
      # T-P3-4: stamp the auto-reap key — ONLY for a self-retiring peer fire (see mark_fired_peer).
      # An `if` block, NOT `[ … ] && …`: a false test would return 1 and `set -e` would abort the
      # fire right before the "→ fired" summary (the same trap noted at the stranded-account line).
      if [ "$WANT_SELF_RETIRE" = 1 ]; then
        mark_fired_peer "$FIRED_DIR" "$SPAWNED_PANE" "$LAUNCH_DIR" "$FIRING_SID"
      fi
      # P0-15: publish the fired pane under its role so role-addressed pings reach it.
      if [ -n "$AS_ROLE" ] && [ -n "$SPAWNED_PANE" ]; then write_role "$CC_ROLES_DIR" "$AS_ROLE" "$SPAWNED_PANE"; fi
    else
      echo "!! FIRE FAILED — never engaged: $LAUNCHER at ${SPAWNED_PANE:-<pane?>} did not ingest the brief within the engagement window (re-sent once). The pane is live but TASK-LESS — recover with a WARM re-fire (--cwd <existing-worktree>); do NOT trust this as a working session (INC-4 / cold-worktree-fire-autosubmit-race)." >&2
      # Record the FAILED engagement (symmetry with the engaged=1 path) so "did this handoff engage"
      # is answerable in one grep. Guarded so a telemetry hiccup can never preempt the exit 1.
      emit_handoff_telemetry 0 || true
      exit 1
    fi
  fi
  DEST="${CWD:-$REPO (self-routing)}"; [ -n "$WORKTREE" ] && DEST="$WT ($WT_SETUP)"
  RSUM=""; [ -n "$SURFACE_REASON" ] && RSUM=", reason: $SURFACE_REASON"
  if [ "$FOLLOW" = 1 ]; then FSUM=", --follow (raised)"; else FSUM=", background (operator focus preserved)"; fi
  echo "→ fired: $LAUNCHER @ $DEST  (surface: $SURFACE$FSUM, account: $CHOSEN, prompt: $PROMPT_FILE$RSUM)"
  # NB: an `if` block, NOT `[ -n … ] && echo` — a trailing &&-list whose test is false returns 1,
  # which would become the script's exit status on the common (no-stranded-account) path.
  if [ -n "$ACCOUNT_SWEEP_BRIDGE" ]; then
    echo "  ⚠ pre-fire sweep found stranded account(s) — '## ACCOUNT STATE' embedded in the brief (re-auth or route around; see stderr above)"
  fi
fi