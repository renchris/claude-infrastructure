#!/bin/bash
# boot-resume-launch.sh — the TTY-coupled resume seam for boot-resume.sh (T-P16-2).
#
# boot-resume.sh runs headless from launchd and CANNOT host an interactive `claude --resume` (which
# reso-resume-one drives via `expect ... interact` and needs a real pane/tty). So the actual resume
# is delegated here: open a FRESH iTerm2 window and run reso-resume-one inside it, where the resumed
# Claude UI can live. Isolating this GUI-coupled step keeps the orchestrator (detect/decide/dedup/
# page) fully unit-testable — boot-resume.sh calls this via the CC_RESUME_LAUNCH_BIN seam.
#
#   Usage: boot-resume-launch.sh <account-alias> <cwd> <session-id> [branch]
#     account-alias: next|next2|next3|next4|fable.. (already MAPPED by boot-resume.sh)
#   --dry-run (or CC_LAUNCH_DRYRUN=1): print the reso-resume-one command + the osascript, run nothing.
#
# Env: CC_RESUME_ONE_BIN (default ~/.reso/bin/reso-resume-one) · CC_OSASCRIPT_BIN (default osascript)
#      · CC_TERM_KITTY (kitty binary) · CC_TERM_KITTY_TO (kitty control socket) · IT2_WRAPPER_NO_KITTY=1
#      (kill switch: force the iTerm2 path even inside kitty).
# Never reuses the current pane (resume-sessions off-by-one rule); always a new window. Fail-loud.
set -uo pipefail

# ---- PANE-SPAWN LOG (item 1467ea1dad4f) --------------------------------------------------------
# Runs at BOOT under launchd, always creating a NEW window — so at machine start a batch of panes
# appears with no interactive caller at all. Without a row each, that batch is indistinguishable
# from the unattributed storm §S4.1 could not explain.
for _psl in "$(dirname "$(readlink -f "$0" 2>/dev/null || printf '%s' "$0")")/lib/pane-spawn-log.sh" \
            "${CLAUDE_CONFIG_DIR:-${HOME:-}/.claude}/scripts/lib/pane-spawn-log.sh" \
            "${HOME:-}/.claude/scripts/lib/pane-spawn-log.sh"; do
  # shellcheck disable=SC1090  # runtime-resolved source; the ship gate runs shellcheck without -x
  [ -f "$_psl" ] && . "$_psl" 2>/dev/null && break
done
unset _psl

# Bound every call that reaches the iTerm2 / AppleEvent surface (machine-wide API wedge,
# 2026-07-26: a bare `it2 session list --json` returned rc 124 with zero output while blocked forks
# piled up). This runs at BOOT to drive iTerm2; unbounded, a wedged API strands the whole resume with no
# operator feedback. The existing rc-4 'osascript failed' path already reports a cut.
# timeout(1) is resolved by ABSOLUTE PATH as well as PATH — launchd jobs and hooks run with a
# minimal PATH excluding Homebrew, exactly where coreutils installs it, so a PATH-only lookup would
# leave the AUTOMATED callers unbounded while interactive shells stayed safe. No timeout(1) ⇒ run
# unbounded rather than break the call. Seams: CC_OSA_TIMEOUT_S · CC_OSA_TIMEOUT_BIN
# (set-but-EMPTY disables verbatim; `${VAR:-}` cannot tell unset from set-empty).
BRL_TIMEOUT_S="${CC_OSA_TIMEOUT_S:-20}"
if [ -n "${CC_OSA_TIMEOUT_BIN+set}" ]; then
  BRL_TIMEOUT_BIN="$CC_OSA_TIMEOUT_BIN"
else
  BRL_TIMEOUT_BIN=""
  for _c in "$(command -v timeout 2>/dev/null || true)" "$(command -v gtimeout 2>/dev/null || true)" \
            /opt/homebrew/bin/timeout /usr/local/bin/timeout \
            /opt/homebrew/bin/gtimeout /usr/local/bin/gtimeout; do
    [ -n "$_c" ] && [ -x "$_c" ] && { BRL_TIMEOUT_BIN="$_c"; break; }
  done
fi
brl_bounded() {
  if [ -z "$BRL_TIMEOUT_BIN" ] || [ ! -x "$BRL_TIMEOUT_BIN" ]; then "$@"; return $?; fi
  "$BRL_TIMEOUT_BIN" -k 3 "$BRL_TIMEOUT_S" "$@"
}


DRYRUN="${CC_LAUNCH_DRYRUN:-0}"
case "${1:-}" in
  -h|--help) sed -n '2,/^set -uo/p' "$0" | sed 's/^# \{0,1\}//; /^set -uo/d'; exit 0 ;;
  --dry-run) DRYRUN=1; shift ;;
esac

acct="${1:-}"; cwd="${2:-}"; sid="${3:-}"; branch="${4:-}"
if [ -z "$acct" ] || [ -z "$sid" ]; then
  echo "boot-resume-launch: usage: <account-alias> <cwd> <session-id> [branch]" >&2
  exit 2
fi

RESUME_ONE="${CC_RESUME_ONE_BIN:-$HOME/.reso/bin/reso-resume-one}"
OSASCRIPT="${CC_OSASCRIPT_BIN:-osascript}"
# Resolve the kitty binary ABSOLUTELY. Hooks and launchd jobs run with a minimal PATH that excludes
# Homebrew, so a bare `kitty` does not exist for exactly the AUTOMATED callers this file serves —
# green where a human tests it, dead where it runs. That is what left a teammate pane open for 3h09m
# with its 653 MB claude.exe resident on 2026-08-01 (full account: bin/cc-kitty-bin header).
# Falling back to the previous spelling keeps a partial deploy degraded rather than broken.
CC_KITTY_BIN="${CC_TERM_KITTY:-kitty}"
# Candidate order matters: the SYMLINK-RESOLVED sibling first. ~/.claude/scripts/*.sh are symlinks
# into this checkout, so `dirname "$0"/../bin` alone points at ~/.claude/bin — which only holds
# cc-kitty-bin AFTER install.sh runs. Resolving the link first finds the repo's own bin/ and makes
# the fix live the moment the file does, instead of waiting on a deploy it cannot trigger.
# ${HOME:-} DELIBERATELY: bash expands the ENTIRE for-list before the loop body runs, so a bare
# $HOME under `set -u` aborts this whole script on the third candidate even when the FIRST one
# resolves. With :- it degrades to a nonexistent path `[ -x ]` rejects. See bin/kitty-split-launch.sh.
_CC_KS="$(readlink -f "$0" 2>/dev/null || printf '%s' "$0")"
for _CC_KB in "$(dirname "$_CC_KS")/../bin/cc-kitty-bin" "$(dirname "$0")/../bin/cc-kitty-bin" "${HOME:-}/.claude/bin/cc-kitty-bin"; do
  [ -x "$_CC_KB" ] || continue
  _CC_KR="$("$_CC_KB" 2>/dev/null)" && [ -n "$_CC_KR" ] && { CC_KITTY_BIN="$_CC_KR"; break; }
done
# NOTE the ${CC_KITTY_BIN:-…} fallback at every call site below. These functions are EXTRACTED
# INDIVIDUALLY with sed by tests/*.bats ("NOTHING HERE EXECUTES scripts/handoff-fire.sh"), so a
# function that depends on a top-level variable is unset in every extracted-function test — measured
# 2026-08-01, it turned `it2py bgtab` red. Each call site therefore re-states the pre-resolution
# spelling as its own default: production gets the absolute path from the block above, an extracted
# function degrades to exactly the behaviour it had before this change.

KITTY="${CC_KITTY_BIN:-${CC_TERM_KITTY:-kitty}}"

# ── terminal dispatch (2026-07-31) ────────────────────────────────────────────────────────────────
# This file's whole job is "open a window with a tty and run the resume in it". That intent is
# terminal-shaped, and until now it could only be spelled in iTerm2: `open -a iTerm` + AppleScript.
# Inside kitty that spelling is not merely inert, it is ACTIVE HARM — it would RESURRECT iTerm2
# behind an operator whose fleet deliberately left it, and then resume the session into a window in
# the wrong terminal. Under kitty the equivalent intent is `kitty @ launch --type=os-window`.
# The predicate MIRRORS bin/it2-wrapper:75 exactly, kill switch included, so this file cannot
# disagree with handoff-fire.sh / cc-pane about which terminal this is (a resume fired into one
# terminal while the fleet lives in the other is a silent strand, not a visible failure).
#
# THE FAILURE TAXONOMY IS THE SAME ON BOTH SIDES — callers key on these codes, so kitty reuses them
# rather than minting new ones: exit 3 = the driver is unavailable (osascript missing / kitty
# missing), exit 4 = the driver ran and FAILED to open the window. exit 2 (usage) and exit 3
# (reso-resume-one not executable) are terminal-independent and unchanged.
#
# No --keep-focus: the iTerm2 arm `activate`s deliberately (a boot resume is a window the operator
# is meant to SEE and type into), so the kitty arm must not silently become a background pop-up.
IN_KITTY=0
if [ -n "${KITTY_WINDOW_ID:-}" ] && [ -z "${IT2_WRAPPER_NO_KITTY:-}" ]; then IN_KITTY=1; fi
# An explicit socket is explicit intent (bin/it2-kitty:197) — honor it even with no kitty env.
if [ "$IN_KITTY" = 0 ] && [ -n "${CC_TERM_KITTY_TO:-}" ] && [ -z "${IT2_WRAPPER_NO_KITTY:-}" ]; then IN_KITTY=1; fi
# DAEMON-CONTEXT DISPATCH (2026-08-07). Env inheritance is a SAMPLING detector: a launchd job
# carries no KITTY_WINDOW_ID even while the whole fleet lives in kitty, so every autonomous
# resume fell through to the iTerm2 arm — which then `open -a iTerm`ed a terminal the operator
# had left (observed 03:51:18 this morning: iTerm2 resurrected + 6 sessions fired into it while
# kitty held 153 panes). bin/cc-kitty-socket is a LIVE detector — it verifies a running kitty
# against its control socket — and feeding its answer through CC_TERM_KITTY_TO is it2-kitty's
# documented explicit-intent channel. Env still wins when present (a genuine iTerm2 pane keeps
# its arm; IT2_WRAPPER_NO_KITTY still forces it); the resolver decides only the ABSENT case.
if [ "$IN_KITTY" = 0 ] && [ -z "${KITTY_WINDOW_ID:-}" ] && [ -z "${IT2_WRAPPER_NO_KITTY:-}" ]; then
  _brl_sock=""
  for _brl_ksb in "$(dirname "$_CC_KS")/../bin/cc-kitty-socket" \
                  "$(dirname "$0")/../bin/cc-kitty-socket" \
                  "${CLAUDE_CONFIG_DIR:-${HOME:-}/.claude}/bin/cc-kitty-socket" \
                  "${HOME:-}/.claude/bin/cc-kitty-socket"; do
    [ -x "$_brl_ksb" ] && { _brl_sock="$(brl_bounded "$_brl_ksb" 2>/dev/null)" || _brl_sock=""; break; }
  done
  if [ -n "$_brl_sock" ]; then CC_TERM_KITTY_TO="$_brl_sock"; export CC_TERM_KITTY_TO; IN_KITTY=1; fi
fi

brl_kitty() { # bounded `kitty @ …` — socket seam kept out of the call sites
  if [ -n "${CC_TERM_KITTY_TO:-}" ]; then brl_bounded "$KITTY" @ --to "$CC_TERM_KITTY_TO" "$@"
  else brl_bounded "$KITTY" @ "$@"; fi
}

# shell-quote a single argument (wrap in single quotes, escaping embedded single quotes) so a cwd
# with spaces survives the osascript `write text` shell.
shq() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }

CMD="$(shq "$RESUME_ONE") $(shq "$acct") $(shq "$cwd") $(shq "$sid")"
[ -n "$branch" ] && CMD="$CMD $(shq "$branch")"

if [ "$IN_KITTY" = 1 ]; then
  # ARGV, not a typed command line. `kitty @ launch … -- prog args…` execs the program directly, so
  # nothing here is re-parsed by a shell — the spacey-cwd quoting the AppleScript arm needs shq for
  # cannot bite, and there is no `write text` race between window creation and the shell's prompt.
  # $cwd is passed to reso-resume-one ALWAYS (even empty, matching the AppleScript arm's shq ''),
  # but only becomes --cwd when it is a real directory: kitty refuses to launch on a bad --cwd, and
  # a resume that could have run in $HOME must not die over the working directory.
  KARGS=(launch --type=os-window)
  { [ -n "$cwd" ] && [ -d "$cwd" ]; } && KARGS+=(--cwd "$cwd")
  KARGS+=(-- "$RESUME_ONE" "$acct" "$cwd" "$sid")
  [ -n "$branch" ] && KARGS+=("$branch")
else
  # osascript escaping: the command runs inside an AppleScript double-quoted string → escape " and \.
  osa_cmd="$(printf '%s' "$CMD" | sed 's/\\/\\\\/g; s/"/\\"/g')"
  read -r -d '' OSA <<OSA_EOF || true
tell application id "com.googlecode.iterm2"
  activate
  set w to (create window with default profile)
  tell current session of w
    write text "$osa_cmd"
  end tell
end tell
OSA_EOF
fi

if [ "$DRYRUN" = "1" ]; then
  printf 'CMD: %s\n' "$CMD"
  if [ "$IN_KITTY" = 1 ]; then printf 'KITTY: %s @ %s\n' "$KITTY" "$(printf '%q ' "${KARGS[@]}")"
  else printf '%s\n' "$OSA"; fi
  exit 0
fi

if [ ! -x "$RESUME_ONE" ]; then
  echo "boot-resume-launch: reso-resume-one not executable at $RESUME_ONE" >&2
  exit 3
fi

# ── MACHINE-CAPACITY ADMISSION — the reso-resume-one seam (MACHINE_CAPACITY_V2 §12.1/§12.4). ───
# §12.1's bypass table lists `~/.reso/bin/reso-resume-one` as an ungated spawn path. That file is
# NOT IN ANY GIT REPOSITORY — `git -C ~/.reso rev-parse` fails, it is an untracked 2026-07-05 file
# on disk — so it cannot be gated in its own body by anything this repo can land or verify. Its
# every in-repo invocation goes through THIS line, so this is where the term can bind and stay
# landed. Direct hand-invocations of `reso-resume-one` remain uncovered by construction; that
# residue is stated in §12.1 rather than papered over here.
#
# PLACEMENT. After the `--dry-run` return above (a dry run prints a command and spawns nothing —
# gating it would refuse an inspection) and after the RESUME_ONE executability check (a resume with
# a missing binary must fail on THAT, with that message, not on a load reading). Before every
# terminal arm below, so kitty and osascript are covered by one evaluation rather than two.
#
# BOUNDED, and here that is the load-bearing property, not a nicety. §12.2 proved an unbounded
# loadavg gate refuses every recovery path on a healthy box and can never recover — refusing spawns
# does not lower the number it reads (iTerm2 + WindowServer + XProtect are ~2.4 UNSHEDDABLE cores).
# A reboot-recovery path is exactly where a permanent refusal is least acceptable: it would convert
# "the box crashed" into "the box never comes back". So after CC_ADMIT_BUDGET consecutive refusals
# the gate admits and pages rather than standing.
#
# EXIT 9 IS ITS OWN CODE, distinct from 2 (usage), 3 (missing dep) and 4 (terminal launch failed).
# boot-resume.sh reads it as `shed` and reports it separately from `failed` — same count, opposite
# operator action: a failure needs fixing, a shed needs the box to settle.
#
# ABSENT LIBRARY IS LOUD (§12.2's rule for capacity_gate, verbatim: inertness must be LOUD rather
# than a silent admit) and deliberately NOT fatal: refusing to recover a reboot because a telemetry
# library is missing would be the gate causing the outage it exists to prevent.
_BRL_CA=""
for _brl_d in "$(dirname "$_CC_KS")/lib/capacity-admit.sh" \
              "$(dirname "$0")/lib/capacity-admit.sh" \
              "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/scripts/lib/capacity-admit.sh" \
              "${HOME:-}/.claude/scripts/lib/capacity-admit.sh"; do
  [ -f "$_brl_d" ] && { _BRL_CA="$_brl_d"; break; }
done
if [ -n "$_BRL_CA" ]; then
  # shellcheck disable=SC1090  # runtime-resolved source; the ship gate runs shellcheck without -x
  . "$_BRL_CA" 2>/dev/null || _BRL_CA=""
fi
if [ -n "$_BRL_CA" ]; then
  if ! cc_capacity_admit boot-resume-launch "resume ${sid} on ${acct}"; then
    echo "boot-resume-launch: $(cc_capacity_admit_reason)" >&2
    echo "  Session $sid is DEFERRED, not lost — re-run /resume-sessions once the box settles." >&2
    exit 9
  fi
  echo "boot-resume-launch: $(cc_capacity_admit_reason)" >&2
else
  echo "boot-resume-launch: capacity-admit: ABSENT (scripts/lib/capacity-admit.sh unreachable) — launching UNGATED" >&2
fi

if [ "$IN_KITTY" = 1 ]; then
  command -v "$KITTY" >/dev/null 2>&1 || { echo "boot-resume-launch: kitty unavailable" >&2; exit 3; }
  # No `open -a kitty` counterpart on purpose: we are RUNNING inside kitty (that is the predicate),
  # so the app is up by construction, and the control socket — not the app — is the thing that can
  # be missing. If it is, the launch fails and rc 4 reports the cut exactly as osascript's does.
  brl_kitty "${KARGS[@]}" >/dev/null 2>&1 || { echo "boot-resume-launch: kitty launch failed for $sid" >&2; exit 4; }
  command -v cc_log_pane_spawn >/dev/null 2>&1 && cc_log_pane_spawn os-window kitty "" "${cwd:-$PWD}" "boot-resume-launch resume sid:${sid:-}"
  exit 0
fi

command -v "${OSASCRIPT%% *}" >/dev/null 2>&1 || { echo "boot-resume-launch: osascript unavailable" >&2; exit 3; }

# NEVER `open -a iTerm` (removed 2026-08-07 — it was this file's line for "post-login it may not
# be running yet"). LAUNCHING the app is exactly how autonomous resumes resurrected iTerm2 behind
# a kitty-fleet operator: the daemon context has no kitty env, fell to this arm, and `open -a`
# brought the abandoned terminal back with sessions in it. This arm now REQUIRES iTerm2 to be
# already running — the `is running` probe is the one iTerm2 reference that never launches it
# (same guard as handoff-fire.sh:931). Not running ⇒ rc 3 (driver unavailable), the taxonomy
# callers already map to their deferred/queue fallbacks; with the kitty socket resolver above,
# reaching this line with iTerm2 down means NO drivable terminal exists at all.
_brl_it2_up="$(brl_bounded "$OSASCRIPT" -e 'if application id "com.googlecode.iterm2" is running then return "UP"' 2>/dev/null || true)"
if [ "$_brl_it2_up" != "UP" ]; then
  echo "boot-resume-launch: iTerm2 not running and no kitty socket — refusing to launch a terminal for $sid" >&2
  exit 3
fi
printf '%s' "$OSA" | brl_bounded "$OSASCRIPT" - >/dev/null 2>&1 || { echo "boot-resume-launch: osascript failed for $sid" >&2; exit 4; }
command -v cc_log_pane_spawn >/dev/null 2>&1 && cc_log_pane_spawn window iterm2 "" "${cwd:-$PWD}" "boot-resume-launch resume sid:${sid:-}"
exit 0
