#!/usr/bin/env bash
# shellcheck disable=SC2009  # file-wide: `ps -o comm= -t <tty>` is a controlling-TTY process lookup
#   that pgrep cannot express (pgrep matches by name/args, not by tty). Correct + intentional here.
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
#   --split-right       DEFAULT + the STANDING operator preference for handoffs. ⌘D-split the FIRING
#                       pane — THIS session's own pane, located via $ITERM_SESSION_ID — new pane to
#                       the RIGHT, SAME TAB, SAME PROFILE, IN THE OPERATOR'S WINDOW. Resolved + split
#                       via the it2 python API (get_session_by_id, atomic); if the anchor is gone it
#                       RETRIES once after a settle then FAILS LOUD — it NEVER fires into another
#                       window (the "separate window" complaint this default exists to kill).
#   --split-down        Split the firing pane, new pane below (⌘⇧D). Same it2 path + fail-loud.
#   --tab               OPT-IN (pair with --surface-reason). Background tab in the FIRING pane's
#                       window (not the current view). Overrides the split-right default; also
#                       fails loud rather than drifting to another window.
#   --window            OPT-IN (pair with --surface-reason). Fresh iTerm2 window — the ONLY surface
#                       that deliberately does NOT anchor to the firing pane.
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

PROMPT_FILE="" ACCOUNT="auto" LAUNCHER="" MODEL="" EFFORT="" CWD="" WORKTREE=""
REPO="$DEFAULT_REPO" WTROOT="$HOME/Development/.worktrees" BASE="origin/main"
SURFACE="split-right" SURFACE_EXPLICIT=0 SURFACE_REASON="" PROBE=0 DRY=0 IN_PLACE=0 EXTRA="" RECYCLE=0 SESSION_ID=""
NOTIFY_BACK="" SELF_RETIRE=1 AS_ROLE=""
SPAWNED_PANE="" ENGAGE_VERIFY=0 FIRE_MARKER=""

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
engagement_seen() { # $1=projects-dir $2=marker $3=registry-dir $4=fired-pane → 0 engaged / 1 not
  local pdir="$1" marker="$2" regdir="$3" pane="$4" hit rsid
  # (a) transcript-birth: a JSONL under the target account's projects dir carrying the marker.
  if [ -n "$marker" ] && [ -d "$pdir" ]; then
    hit="$(find "$pdir" -name '*.jsonl' -type f -exec grep -lF -- "$marker" {} + 2>/dev/null | head -1)"
    [ -n "$hit" ] && return 0
  fi
  # (b) a cc-registry row for the fired pane bearing a (non-null) session_id — CC registered.
  if [ -n "$pane" ] && [ -n "$regdir" ] && [ -f "$regdir/$pane.json" ] && command -v jq >/dev/null 2>&1; then
    rsid="$(jq -r '.session_id // empty' "$regdir/$pane.json" 2>/dev/null)"
    [ -n "$rsid" ] && return 0
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
    "$it2" session run -s "$pane" "$resend" >/dev/null 2>&1 || true
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
    if "$IT2" session run -s "$RSID" "$(cat "$CMDFILE")" >/dev/null 2>&1; then ok=1; break; fi
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
    "$IT2" session run -s "$RSID" "$(cat "$CMDFILE")" >/dev/null 2>&1 || true
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
    if [ -n "$(git status --porcelain 2>/dev/null | head -1)" ]; then
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
      echo "chain:     arm watcher → FOREGROUND /exit (interrupts any in-flight turn, exits in seconds) → detached ps-poll ≤180s (CR nudge @60s) → it2 force-close pane"
    fi
    exit 0
  fi
  # P0-15: the pane is about to close — repoint every role still naming it to the (verified-alive)
  # successor, so a role-addressed ping lands on the continuation, never on the dead pane (SO-1).
  # A --terminal close has no successor → refresh_roles_for no-ops (nothing continues).
  refresh_roles_for "$CC_ROLES_DIR" "$SC_SID" "$SC_SUCCESSOR"
  # Succession announce — INTO the survivor, BEFORE the close chain starts. The report emitted
  # in the closing pane dies with the pane (observed 23:03 2026-07-13); the successor's
  # transcript + mailbox are where the operator/its model will actually look. Composer inject
  # is visible and queues safely into a busy session; failure degrades loudly but does NOT
  # abort the close (mailbox record + post-close focus still carry the succession).
  if [ -n "$SC_SUCCESSOR" ] && [ "$SC_NO_NOTIFY" = 0 ]; then
    if [ -x "$HOME/.claude/bin/cc-notify" ]; then
      if "$HOME/.claude/bin/cc-notify" "$SC_SUCCESSOR" "HANDOFF-SUCCESSION: predecessor pane $SC_SID is self-closing now ($(date '+%H:%M:%S')) — you are the active continuation of its work; the operator's view will be focused here. Close log: $SC_LOG" >/dev/null 2>&1; then
        echo "→ succession announced into $SC_SUCCESSOR (composer + mailbox)"
      else
        echo "⚠ cc-notify to successor did not verify (strand/closed?) — mailbox record + post-close focus still carry the succession" >&2
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
    # shellcheck disable=SC2016  # $HOME (and \r/\n) below are LITERAL guidance for the fired reader, not shell expansions
    {
      printf '\n'
      printf '## BACK-CHANNEL — ping the originator (%s)\n' "$BACK_SID"
      printf '%s\n' 'On completion, at a decision gate, or on a blocker, ping the session that fired this handoff:'
      printf '  cc-notify %s "HANDOFF-PING %s: <one-line status>"\n' "$BACK_SID" "$NB_SLUG"
      printf '%s\n' '(cc-notify is on PATH at $HOME/.claude/bin/cc-notify — it types the line into the'
      printf '%s\n' "originator's composer via the it2 transport (\\r submit, not \\n) AND records"
      printf '%s%s.md as the durable fallback,\n' '$HOME/.claude/mailbox/' "$BACK_SID"
      printf '%s\n' 'so the ping survives a closed/recycled pane. If the originator armed cc-await-ping,'
      printf '%s\n' 'the mailbox write alone wakes it; the composer injection is the interrupt path.)'
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

# ESC is for the FRONTMOST/WINDOW path only — that path embeds the command inside an AppleScript
# string literal via -e "…write text \"$ESC\"", so backslashes then double-quotes must be escaped
# (load-bearing order). The it2 split path and as_tab pass $CMD RAW (session run / osascript argv),
# which reaches the pane verbatim with no string-literal parsing — no escaping needed.
ESC="$(printf '%s' "$CMD" | sed 's/\\/\\\\/g; s/"/\\"/g')"

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

# Land the launch command into a freshly split pane + focus it. $CMD arrives RAW via `session run`
# (async_send_text + CR — the Ink-safe submit the recycle path already relies on); no AppleScript
# string-literal escaping. A fresh split's shell needs a beat to attach its tty before it reads
# typed input, hence the settle. Focus lands the operator's view ON the continuation (best-effort).
it2_land() { # $1=new-session-id  → 0 on typed, 1 (loud) if the pane exists but typing failed
  local id="$1" ok=0
  /bin/sleep 0.4
  for _ in 1 2; do
    if "$REAL_IT2" session run -s "$id" "$CMD" >/dev/null 2>&1; then ok=1; break; fi
    /bin/sleep 0.6
  done
  [ "$ok" = 1 ] || { echo "!! split pane $id created but typing the launch command failed (2×) — run manually in it: $CMD" >&2; return 1; }
  "$REAL_IT2" session focus "$id" >/dev/null 2>&1 || true   # land the operator's view on the continuation (best-effort)
  return 0
}

# Targeted tab (opt-in --tab surface): create a background tab in the firing session's WINDOW (not
# the frontmost window), type the raw command into it, raise that window. Echoes "OK <id>" on
# success / "NOTFOUND" when the window is gone — the caller settle-retries then FAILS LOUD (a tab,
# like a split, never drifts to the app-frontmost window; only the deliberate --window does that).
as_tab() { # $1=session-uuid  $2=raw-command-text
  osascript - "$1" "$2" <<'AS'
on run argv
  set sid to item 1 of argv
  set theText to item 2 of argv
  tell application "iTerm2"
    activate
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
    tell newSess to write text theText
    tell foundWin to select
    return "OK " & (id of newSess)
  end tell
end run
AS
}

# Fresh-window spawn — the ONLY surface that deliberately does NOT anchor to the firing pane
# (--window, opt-in). Creates a brand-new iTerm2 window and types the command into it. This is the
# LAST place that targets iTerm2's app-frontmost/new window; split + tab were deliberately removed
# from it (2026-07-17) so a mis-resolved anchor can only ever FAIL LOUD, never drift here. Uses
# $ESC (the command embedded inside the AppleScript string literal). Zero windows → this is also
# the implicit surface, since there is nothing to split/tab into.
spawn_frontmost() {
  osascript -e 'tell application "iTerm2"' \
            -e 'activate' \
            -e 'set newWin to (create window with default profile)' \
            -e "tell current session of newWin to write text \"$ESC\"" \
            -e 'end tell' >/dev/null
}

# Dispatcher. SPLIT surfaces (the ⌘D default) go through the it2 API and, if the firing anchor
# can't be resolved, RETRY once after a settle then FAIL LOUD — they NEVER fire into another window
# (the operator's recurring complaint). --tab stays osascript-targeted to the firing window but
# ALSO fails loud (no frontmost). Only the deliberate --window uses the frontmost/fresh-window path.
# A fail-loud path returns non-zero → `set -e` aborts the script before the "→ fired" summary, so
# the calling agent sees a clean failure ("nothing launched") rather than a phantom success.
spawn() {
  # --window is SUPPOSED to open a fresh window — no firing-pane anchoring, by design.
  if [ "$SURFACE" = "window" ]; then spawn_frontmost; return; fi
  if [ -z "$FIRING_SID" ]; then
    echo "!! no \$ITERM_SESSION_ID/--session-id to anchor to — REFUSING to fire a $SURFACE into a random window." >&2
    echo "   Re-run from inside the firing iTerm2 pane, pass --session-id <uuid>, or use --window to open a fresh window on purpose." >&2
    return 1
  fi
  case "$SURFACE" in
    split-right|split-down)
      local dir=vertically; [ "$SURFACE" = split-down ] && dir=horizontally
      local newid
      newid="$(it2_split "$FIRING_SID" "$dir")" \
        || { /bin/sleep 0.8; newid="$(it2_split "$FIRING_SID" "$dir")"; } \
        || { echo "!! firing pane $FIRING_SID not found in iTerm2 (settled + retried) — anchor gone; NOT firing into a random window." >&2
             echo "   Nothing was launched. Re-fire from a live pane, or pass --window for a deliberate fresh window." >&2
             return 1; }
      it2_land "$newid" || return 1
      SPAWNED_PANE="$newid"                          # the fired pane — engagement verify + registry
      ;;
    tab)
      local out
      out="$(as_tab "$FIRING_SID" "$CMD" 2>/dev/null)" || out="ERR($?)"
      case "$out" in OK\ *) SPAWNED_PANE="${out#OK }"; return 0 ;; esac
      /bin/sleep 0.8                                # settle + retry once, then fail loud
      out="$(as_tab "$FIRING_SID" "$CMD" 2>/dev/null)" || out="ERR($?)"
      case "$out" in
        OK\ *) SPAWNED_PANE="${out#OK }" ;;
        *) echo "!! firing window for $FIRING_SID not found ($out) — NOT firing a tab into a random window." >&2
           echo "   Nothing was launched. Re-fire from a live pane, or use --window for a deliberate fresh window." >&2
           return 1 ;;
      esac
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
    "$HOME/.claude/bin/it2" session run -s "$SID" "$CMD" \
      || { echo "!! recycle: it2 write into $SID failed — run manually: $CMD" >&2; exit 1; }
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
    [ -n "$SURFACE_REASON" ] && echo "reason:   $SURFACE_REASON"
    case "$SURFACE" in
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
  pre_trust "$LAUNCH_DIR" "$(config_dir_for_launcher "$LAUNCHER")"
  spawn
  # P0-11: prove the fired session ingested the brief before claiming success. A cold fire that
  # raced CC boot sits at an empty composer (INC-4) — re-send once, then FAIL LOUD.
  if [ "$ENGAGE_VERIFY" = 1 ]; then
    PROJ_DIR="$(config_dir_for_launcher "$LAUNCHER")/projects"
    if verify_engagement "$PROJ_DIR" "$FIRE_MARKER" "$REG_DIR" "$SPAWNED_PANE" "$REAL_IT2" "$(cat "$PROMPT_FILE")"; then
      echo "→ engagement confirmed for the fired session (transcript/registry birth)" >&2
      # P0-12: guarantee a registry row so the reaper/board can see the fired pane.
      FIRE_NAME="$(basename "$LAUNCH_DIR")-${SPAWNED_PANE%%-*}"
      ensure_registration "$REG_DIR" "$SPAWNED_PANE" "$FIRE_NAME" "$LAUNCH_DIR" "$CMD"
      # P0-15: publish the fired pane under its role so role-addressed pings reach it.
      if [ -n "$AS_ROLE" ] && [ -n "$SPAWNED_PANE" ]; then write_role "$CC_ROLES_DIR" "$AS_ROLE" "$SPAWNED_PANE"; fi
    else
      echo "!! FIRE FAILED — never engaged: $LAUNCHER at ${SPAWNED_PANE:-<pane?>} did not ingest the brief within the engagement window (re-sent once). The pane is live but TASK-LESS — recover with a WARM re-fire (--cwd <existing-worktree>); do NOT trust this as a working session (INC-4 / cold-worktree-fire-autosubmit-race)." >&2
      exit 1
    fi
  fi
  DEST="${CWD:-$REPO (self-routing)}"; [ -n "$WORKTREE" ] && DEST="$WT ($WT_SETUP)"
  RSUM=""; [ -n "$SURFACE_REASON" ] && RSUM=", reason: $SURFACE_REASON"
  echo "→ fired: $LAUNCHER @ $DEST  (surface: $SURFACE, account: $CHOSEN, prompt: $PROMPT_FILE$RSUM)"
fi