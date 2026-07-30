#!/bin/bash
# TeammateIdle hook — graceful auto-shutdown with work preservation.
# Fires (LEAD-side) when a teammate goes idle after finishing its turn.
#
# Design — checkpoint-first, defer-until-quiesced, then close the EXACT pane:
#   1. CHECKPOINT FIRST via teammate-checkpoint.sh (synthetic TeammateIdle
#      payload). Preserves tracked + untracked work to refs/checkpoints/<m>/<ts>
#      and refs/wip/<m>/LAST. Uses git plumbing — bypasses pre-commit hooks.
#   2. FALLBACK to /tmp/<team>-<member>-<ts>.patch if the checkpoint fails
#      for any reason (corrupt repo, permission issue). Hook still exits 0.
#   3. DEFER on dirty tree — if git status shows uncommitted work, skip the
#      reap this cycle. TeammateIdle fires 3-4× per teammate; we wait until
#      the teammate actually quiesces (this IS the final-idle gate). Max
#      defers: 3 (backstop). After that, reap but checkpoint first.
#   4. COOPERATIVE MARKER — if <worktree>/.teammate-busy exists, defer
#      unconditionally. Teammate writes it before multi-turn work.
#   5. CLOSE THE EXACT PANE, then remove the worktree. The pane id is read
#      from the team config.json member field `tmuxPaneId` (an iTerm2 session
#      UUID under the it2 backend, or a tmux %N id), looked up across ALL
#      team roots — CC writes $CLAUDE_CONFIG_DIR/teams/<team>/, so a team led
#      from a *2 launcher (claude-next2 / claude-fable2 → ~/.claude-secondary)
#      lives ONLY under ~/.claude-secondary/teams (memory:
#      teammate-shutdown-secondary-config-dir-2026-06-09) — and closed with
#      `it2 session close -f -s <id>` — which the ~/.claude/bin/it2 shim
#      reroutes to a python iterm2 close with force=True (it2 0.2.3 never
#      propagates -f to the API, and iTerm2's non-forced close prompts on
#      running-job panes REGARDLESS of the never-prompt profile; memory:
#      it2-session-close-force-modal-2026-06-09) — or `tmux kill-pane -t <id>`.
#
# WHY NOT `kill -TERM $PPID` (the retired mechanism): a TeammateIdle hook runs
# on the LEAD as  lead-claude → /bin/sh -c → bash, so $PPID is the /bin/sh shim,
# already dead by the time the backgrounded kill fired — the signal then hit a
# PID-RECYCLED process (intermittently the lead or an unrelated shell). That is
# exactly the observed "closes too early / inconsistent" regression. Targeting
# the recorded pane id is deterministic and hits only the teammate's pane.
#
# Uses JSON {"continue": false} with exit 0 to stop the teammate's turn.
#
# Kill switch: export TEAMMATE_SHUTDOWN_DISABLED=1
# Tuning:      export TEAMMATE_MAX_DEFERS=<N>   (default 3)
#              export CC_CLASSIFY_INTERACTIVE_HOLD_S=<sec>  (default 21600) — operator-adoption hold window
#              export CC_CLASSIFY_INTERACTIVE_HOLD_DISABLE=1 — disable the operator-adoption hold
#              export TEAMMATE_CLOSE_GRACE_S=<sec>          (default 3) — grace before the detached pane close

set -uo pipefail

if [[ "${TEAMMATE_SHUTDOWN_DISABLED:-0}" == "1" ]]; then
  exit 0
fi

readonly MAX_DEFERS="${TEAMMATE_MAX_DEFERS:-3}"
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"   # declare/assign split: SC2155
readonly HOOK_DIR
readonly LOG_DIR="$HOME/.claude/logs"
readonly WATCHDOG_DIR="$HOME/.claude/watchdog"

# ── operator-adoption hold config (2026-07-24; mirrors cc-classify 4.7 env family) ───────────────
# The WHO-primitive ci_last_interactive_epoch lives in hooks/lib/cc-interactive.sh, which LANDS
# SEPARATELY — sourced IF PRESENT, else one WARN + skip (graceful degradation for a partial deploy).
readonly INTERACTIVE_HOLD_S="${CC_CLASSIFY_INTERACTIVE_HOLD_S:-21600}"   # a real operator prompt within this ⇒ ADOPTED pane
readonly FIRE_PROMPT_SLACK_S="${CC_CLASSIFY_FIRE_PROMPT_SLACK_S:-300}"   # a prompt within spawn+this = the spawn brief, not adoption
readonly INTERACTIVE_LIB="${CC_INTERACTIVE_LIB:-$HOOK_DIR/lib/cc-interactive.sh}"
readonly PROJECT_ROOTS="${CC_CLASSIFY_PROJECT_ROOTS:-$HOME/.claude/projects $HOME/.claude-secondary/projects $HOME/.claude-tertiary/projects $HOME/.claude-quaternary/projects}"
readonly CC_NOTIFY_BIN="${CC_NOTIFY_BIN:-$HOME/.claude/bin/cc-notify}"
readonly CLOSE_GRACE_S="${TEAMMATE_CLOSE_GRACE_S:-3}"

# Team-state roots. CC writes $CLAUDE_CONFIG_DIR/teams/<team>/config.json with
# each member's tmuxPaneId — including on the 2.1.183 IMPLICIT-team model (teams
# named `session-<id>`; verified 2026-06-28). The *2/*3/*4 launchers each run a
# DIFFERENT, REAL config dir (claude-next2 → ~/.claude-secondary, next3 →
# ~/.claude-tertiary, next4 → ~/.claude-quaternary, …), so a team led from any of
# them records its pane ids ONLY under THAT dir's teams/. Scan the CURRENT
# session's config dir first, then EVERY ~/.claude*/teams root.
#
# The old hardcoded three {secondary, tertiary, .claude} silently dropped panes
# for teams led from an unlisted dir — e.g. ~/.claude-quaternary (the vihard
# session), the exact source of the original "no pane id resolved → pane stays
# open on 2.1.183" report. (The earlier RCA "implicit-team writes no config" was
# wrong: the config existed, just under an unscanned root.) Order is a tie-break
# only — the resolver below prefers whichever root recorded a non-empty
# tmuxPaneId, so extra/duplicate roots (e.g. the ~/.claude-next → ~/.claude
# symlink) are harmless.
_team_roots=()
[[ -n "${CLAUDE_CONFIG_DIR:-}" && -d "${CLAUDE_CONFIG_DIR}/teams" ]] && _team_roots+=("${CLAUDE_CONFIG_DIR}/teams")
shopt -s nullglob
_team_roots+=("$HOME"/.claude*/teams)
shopt -u nullglob
[[ ${#_team_roots[@]} -eq 0 ]] && _team_roots+=("$HOME/.claude/teams")
readonly TEAM_ROOTS=("${_team_roots[@]}")
unset _team_roots

mkdir -p "$LOG_DIR" "$WATCHDOG_DIR" 2>/dev/null || true
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_DIR/teammate-lifecycle.log" 2>/dev/null || true
}

# --- Pane-close primitives ------------------------------------------------------
# Resolve the it2 CLI. Calling the SHIM (~/.claude/bin/it2, first in PATH) here
# is REQUIRED, not incidental: it rewrites `session split` (injects the
# Claude-Teammate no-prompt profile) AND `session close -f -s <id>` (reroutes
# to a python iterm2 force=True close). The real CLI's `close -f` does NOT
# propagate force to the API and pops iTerm2's running-job confirmation modal
# on every live teammate pane (memory: it2-session-close-force-modal-2026-06-09).
_it2_bin() { command -v it2 2>/dev/null || echo "$HOME/.claude/bin/it2"; }

# Bound every fork that reaches the iTerm2 API (machine-wide wedge, 2026-07-26). The shim
# self-bounds its own CLI forks at 30s, but this hook must return inside its 5s hook budget and
# close_pane is called PER TEAMMATE, so 30s each is already too slow; _pane_from_tty forks python
# directly and is not covered by the shim at all. timeout(1) is resolved by ABSOLUTE PATH too —
# hooks run with a minimal PATH excluding Homebrew, where coreutils installs it. No timeout(1)
# ⇒ run unbounded rather than break teardown. Seam: TAS_IT2_TIMEOUT_S · TAS_IT2_TIMEOUT_BIN
# (set-but-EMPTY disables verbatim; `${VAR:-}` cannot tell unset from set-empty).
TAS_TIMEOUT_S="${TAS_IT2_TIMEOUT_S:-8}"
if [[ -n "${TAS_IT2_TIMEOUT_BIN+set}" ]]; then
  TAS_TIMEOUT_BIN="$TAS_IT2_TIMEOUT_BIN"
else
  TAS_TIMEOUT_BIN=""
  for _c in "$(command -v timeout 2>/dev/null || true)" "$(command -v gtimeout 2>/dev/null || true)" \
            /opt/homebrew/bin/timeout /usr/local/bin/timeout \
            /opt/homebrew/bin/gtimeout /usr/local/bin/gtimeout; do
    [[ -n "$_c" && -x "$_c" ]] && { TAS_TIMEOUT_BIN="$_c"; break; }
  done
fi
tas_bounded() {
  if [[ -z "$TAS_TIMEOUT_BIN" || ! -x "$TAS_TIMEOUT_BIN" ]]; then "$@"; return $?; fi
  "$TAS_TIMEOUT_BIN" -k 3 "$TAS_TIMEOUT_S" "$@"
}

# Close one teammate pane by its recorded id. Idempotent: closing an
# already-gone pane fails with "not found" (the caller logs it as such).
# iTerm2 session UUIDs are never recycled, so a stale id can only no-op — it
# can never hit the wrong pane. Stderr is captured into CLOSE_ERR so the
# caller can tell "already gone" from a real failure (RPC error, timeout).
CLOSE_ERR=""
close_pane() {
  local pane="$1"
  [[ -n "$pane" ]] || return 1
  if [[ "$pane" =~ ^%[0-9]+$ ]]; then
    CLOSE_ERR=$(tmux kill-pane -t "$pane" 2>&1 >/dev/null)   # tmux backend: synchronous, no prompt
  else
    CLOSE_ERR=$(tas_bounded "$(_it2_bin)" session close -f -s "$pane" 2>&1 >/dev/null)  # shim → python force=True
  fi
}

# ── teardown marker (MARKER CONTRACT v1; reader = hooks/lead-crash-watchdog.sh classify_death) ─────
# Closing a teammate's pane kills a LIVE CC session, and lead-crash-watchdog is a SessionStart hook
# with NO matcher — it arms on EVERY session, teammates included. Without deterministic evidence the
# teammate's own watchdog runs the classify ladder, finds no close-record (C10-pending), no jetsam and
# no self-close prose (this teammate never chose to close — we closed it), and lands on CRASH. So every
# idle-teammate shutdown logged a false crash. handoff-fire got this marker on 2026-07-23 (self-close)
# and cc-teardown on 2026-07-25 (delegated close); the TeammateIdle closer is the same class.
#
# Dual-keyed exactly like the other two writers: the reader checks <sid>.json directly, else resolves
# pane→sid through the session registry — a torn-down teammate's registry row can be overwritten, so
# both keys are written and key_kind records each file's own key. `mode=teammate-idle` is the
# discriminator. SESSION_ID defaults to the literal "unknown" (see the hook-input parse), which must
# NEVER become a marker filename — an "unknown.json" marker would mask a genuine crash of whatever
# session the reader next asks about. FULLY GUARDED: a marker write can never fail or delay a close.
# Writers never delete markers; the reader GCs them.
write_teardown_marker() { # $1=pane-uuid  $2=sid ("" / "unknown" ⇒ pane-key only)  $3=mode
  local _tm_pane="${1:-}" _tm_sid="${2:-}" _tm_mode="${3:-teammate-idle}" _tm_dir _tm_ts
  _tm_dir="${CC_TEARDOWN_DIR:-$HOME/.claude/watchdog/teardown}"
  [[ "$_tm_sid" == "unknown" ]] && _tm_sid=""
  [[ -n "$_tm_sid" || -n "$_tm_pane" ]] || return 0
  mkdir -p "$_tm_dir" 2>/dev/null || true
  _tm_ts="$(date -u +%FT%TZ)"
  if [[ -n "$_tm_sid" ]]; then
    printf '{"key_kind":"sid","pane":"%s","sid":"%s","mode":"%s","ts":"%s"}\n' \
      "$_tm_pane" "$_tm_sid" "$_tm_mode" "$_tm_ts" > "$_tm_dir/$_tm_sid.json" 2>/dev/null || true
  fi
  if [[ -n "$_tm_pane" ]]; then
    printf '{"key_kind":"pane","pane":"%s","sid":"%s","mode":"%s","ts":"%s"}\n' \
      "$_tm_pane" "$_tm_sid" "$_tm_mode" "$_tm_ts" > "$_tm_dir/$_tm_pane.json" 2>/dev/null || true
  fi
  return 0
}

# Close + log one pane (shared by the config-resolved AND implicit-team paths).
close_and_log() {
  local pane="$1" who="$2"
  # Drop the marker HERE — close_and_log is reached only from the detached close block, i.e. only
  # once every gate (busy-marker, dirty-defer, reap-guard, worktree-resolve, operator-adoption) has
  # already passed and the close is inevitable. A marker written at any earlier decision point would
  # mask a genuine crash of a teammate we then chose to KEEP for the reader's whole freshness window.
  write_teardown_marker "$pane" "${SESSION_ID:-}" teammate-idle
  close_pane "$pane"
  local rc=$?
  local err="${CLOSE_ERR//$'\n'/ ; }"
  if (( rc == 0 )); then
    log "  ✓ closed pane $pane ($who)"
  elif [[ "$err" == *"not found"* || "$err" == *"find pane"* ]]; then
    log "  ~ pane $pane ($who) already gone (${err:-not found})"
  else
    log "  ✗ pane close FAILED (rc=$rc) for $pane ($who): ${err:-<no stderr>}"
  fi
}

# --- Implicit-team (CC 2.1.178+) pane resolution — DEFENSE IN DEPTH -------------
# PRIMARY resolution is still the config.json/tmuxPaneId loop below — which now
# works on the 2.1.183 implicit-team model too, because TEAM_ROOTS scans every
# ~/.claude*/teams root (the missing-root bug, fixed above). This block is the
# BACKSTOP for the residual cases where the config loop still yields PANEID="":
# a config-WRITE RACE (a teammate that idles before CC has written its pane id),
# or a future config dir that doesn't match ~/.claude*. It is independent of the
# config bookkeeping entirely.
#
# The lever: on the implicit-team model the TeammateIdle hook runs as a
# descendant of the IDLE TEAMMATE'S OWN claude.exe, so $PPID is
# `claude.exe --agent-id <member>@session-<id> ...` (verified empirically — the
# "PPID-forensic" log line below). We resolve THAT process's iTerm2 pane id and
# close it the same way. Two methods, both validated 2026-06-28 against a live
# pane (lead pane 28EBFC93… ↔ ITERM_SESSION_ID env AND tty ttys031):
#   A) ITERM_SESSION_ID from the process env (`ps eww`) — instant; used in-body.
#   B) controlling tty → iTerm2 session whose `tty` var matches — used in the
#      unbounded detached close (it does an iTerm2 API round-trip).
# SAFETY (load-bearing): only ever resolve from a process whose command contains
# `--agent-id <THIS teammate>@`. Never the lead (no --agent-id), never another
# teammate. No match → empty → old behavior (leave for CC session-end cleanup).
# A forced close must never be able to hit the wrong pane.
readonly PANE_PYTHON_BIN="/Library/Frameworks/Python.framework/Versions/3.11/bin/python3.11"

# Walk up from $PPID (bounded) to the claude.exe whose --agent-id matches this
# teammate (any MEMBER_CANDIDATES form). Echoes the pid; empty on no match.
_find_teammate_pid() {
  local pid="$PPID" depth=0 cmd m
  while [[ -n "$pid" && "$pid" =~ ^[0-9]+$ && "$pid" -gt 1 && $depth -lt 6 ]]; do
    cmd=$(ps -p "$pid" -o command= 2>/dev/null)
    if [[ "$cmd" == *"claude.exe"* ]]; then
      for m in "${MEMBER_CANDIDATES[@]}"; do
        if [[ -n "$m" && "$cmd" == *"--agent-id ${m}@"* ]]; then
          printf '%s\n' "$pid"; return 0
        fi
      done
    fi
    pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
    depth=$((depth + 1))
  done
  return 1
}

# iTerm2 session UUID from a pid via its ITERM_SESSION_ID env var
# (shape `<window><tab><pane>:<UUID>`). Echoes UUID; empty on failure.
_pane_from_env() {
  local pid="$1" line sid
  [[ -n "$pid" ]] || return 1
  line=$(ps eww -p "$pid" 2>/dev/null | tr ' ' '\n' | grep -m1 '^ITERM_SESSION_ID=')
  sid="${line##*:}"
  [[ "$sid" =~ ^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$ ]] \
    && printf '%s\n' "$sid"
}

# iTerm2 session UUID from a pid via its controlling tty (API enumeration).
# Echoes UUID; empty on failure.
#
# The inner `asyncio.wait_for(_find(), timeout=3)` bounds only the RPC — it cannot fire if the API
# CONNECT before it never completes, which is exactly what a wedged iTerm2 does (the same gap the
# it2 shim documents for its own force-close interception). So the "bounded 3s" this comment used
# to claim was FALSE in the one failure mode it was written for, and a false bound is worse than
# none: callers trusted it and skipped their own cap. The outer process bound below is what makes
# the claim true.
_pane_from_tty() {
  local pid="$1" tty
  [[ -n "$pid" ]] || return 1
  [[ -x "$PANE_PYTHON_BIN" ]] || return 1
  tty=$(ps -o tty= -p "$pid" 2>/dev/null | tr -d ' ')
  [[ -n "$tty" && "$tty" != "??" ]] || return 1
  tas_bounded "$PANE_PYTHON_BIN" - "/dev/$tty" <<'PY' 2>/dev/null
import asyncio, sys
try:
    import iterm2
except Exception:
    sys.exit(0)
want = sys.argv[1]
async def main(connection):
    async def _find():
        app = await iterm2.async_get_app(connection)
        for w in app.terminal_windows:
            for t in w.tabs:
                for s in t.all_sessions:
                    if str(await s.async_get_variable("tty")) == want:
                        return s.session_id
        return None
    try:
        sid = await asyncio.wait_for(_find(), timeout=3)
    except asyncio.TimeoutError:
        sid = None
    if sid:
        print(sid)
try:
    iterm2.run_until_complete(main)
except Exception:
    pass
PY
}

# ── operator-adoption helpers (2026-07-24) ──────────────────────────────────────────────────────
# Transcript .jsonl for a session id — first match across the account project roots (mirror cc-classify).
_find_transcript() {
  local sid="${1:-}" r f
  [[ -n "$sid" ]] || return 1
  for r in $PROJECT_ROOTS; do
    [[ -d "$r" ]] || continue
    f="$(find "$r" -maxdepth 2 -name "$sid.jsonl" 2>/dev/null | head -1)"
    [[ -n "$f" ]] && { printf '%s' "$f"; return 0; }
  done
  return 1
}

# Spawn epoch (seconds) for a session id from the registry startedAt (epoch-ms); empty on miss.
_spawn_epoch() {
  local sid="${1:-}" ms
  [[ -n "$sid" ]] || return 1
  ms="$(cc-sessions --json 2>/dev/null | jq -r --arg s "$sid" \
        '.[] | select((.session_id // .sessionId)==$s) | .startedAt // empty' 2>/dev/null | head -1)"
  [[ "$ms" =~ ^[0-9]+$ ]] || return 1
  printf '%s' "$(( ms / 1000 ))"
}

# D7 send-damping (best-effort: absent lib ⇒ undamped, i.e. today's behaviour, never a lost page).
# Same resolve order + fail-open posture as bin/cc-reaper's.
for _c in "$HOOK_DIR/lib/page-damp.sh" "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/hooks/lib/page-damp.sh" \
          "$HOME/.claude/hooks/lib/page-damp.sh"; do
  # shellcheck disable=SC1090,SC1091
  [[ -f "$_c" ]] && { . "$_c" 2>/dev/null || true; break; }
done

# Best-effort desk page (never fatal).
_page_desk() { "$CC_NOTIFY_BIN" --role desk "$1" >/dev/null 2>&1 || true; }

# Damped desk page: <fingerprint> <message>. The fingerprint is the page's STATE — never a clock or a
# counter, which would change every sweep and silently disable damping while looking wired.
_page_desk_damped() {
  local fp="$1" msg="$2"
  if command -v damp_should_send >/dev/null 2>&1; then
    damp_should_send "role:desk" "$fp" || { log "  ~ page suppressed (damped) [$fp]"; return 0; }
  fi
  _page_desk "$msg"
}

# ── LIVENESS: is a tool RUNNING right now? (2026-07-29) ──────────────────────────────────────────
# TeammateIdle fires on turn-boundary silence, but a teammate in the middle of a long Bash/build/test
# call is SILENT AND WORKING: its transcript's last record is an assistant tool_use timestamped at
# call START, so idleness crosses the threshold mid-call and a live worker reads as finished. Observed
# on this hook 2026-07-29 — a teammate actively writing tests (stale=0m) was SURFACEd as confirm-close.
# In a real transcript a FINISHED turn ends with an assistant TEXT block or a `user` tool_result,
# never a bare trailing tool_use, so this fires only on a genuine mid-call state.
# Mirrors bin/cc-classify's tool_in_flight() (a18 L-13) — same predicate, deliberately re-stated here
# rather than sourced: cc-classify is an executable with no library guard, so sourcing it would run
# its main. Keep the two in step; tests/teammate-auto-shutdown.bats pins this copy's semantics.
_tool_in_flight() {  # <session-id> → 0 if a tool call is outstanding
  local sid="${1:-}" f last_rec tu_id
  [[ -n "$sid" && "$sid" != "unknown" ]] || return 1
  f="$(_find_transcript "$sid")" || return 1
  [[ -s "$f" ]] || return 1
  last_rec="$(tail -n 1 "$f" 2>/dev/null)"
  [[ -n "$last_rec" ]] || return 1
  printf '%s' "$last_rec" \
    | jq -e '.type=="assistant" and ((.message.content // []) | map(select(.type=="tool_use")) | length > 0)' \
      >/dev/null 2>&1 || return 1
  tu_id="$(printf '%s' "$last_rec" \
    | jq -r '(.message.content // []) | map(select(.type=="tool_use")) | last | .id // empty' 2>/dev/null)"
  if [[ -n "$tu_id" ]]; then
    # a matching tool_result anywhere ⇒ the tool returned ⇒ not in flight
    jq -rc 'select(.type=="user") | (.message.content // []) | if type=="array" then .[] else empty end
            | select(.type=="tool_result") | .tool_use_id // empty' "$f" 2>/dev/null \
      | grep -qxF "$tu_id" && return 1
  fi
  return 0
}

INPUT=$(cat)
TEAMMATE_NAME=$(echo "$INPUT" | jq -r '.teammate_name // "unknown"' 2>/dev/null)
TEAM_NAME=$(echo "$INPUT" | jq -r '.team_name // "unknown"' 2>/dev/null)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null)

# Resolve the worktree. Conventions + edge cases:
#   /tmp/wt-<team>-<member>        newer
#   /tmp/worktree-<team>-<member>  legacy
#   /tmp/worktree-<member>         single-segment
# AND: the team slug in the worktree path may differ from team_name (e.g.,
# plan branches named 'feat/ui-sh-v2' while team_name is 'ui-sh-100p-v2'),
# AND: the member name may be auto-incremented (quality-keeper → quality-keeper-2).
#
# Strategy: try exact matches first, then fall back to a glob-based search.
WORKTREE=""

# ── WORKTREE_OWNED — may we DESTROY this worktree? (2026-07-29) ───────────────────────────────────
# Two different questions share the one $WORKTREE variable, and conflating them is a data-loss bug:
#   (a) "which tree do I GATE on?"    — busy-marker, dirty-defer, reap-guard effect-read, checkpoint.
#   (b) "which tree may I REMOVE?"    — the `git worktree remove --force` at the end of the close.
# For a DEDICATED per-member worktree both answers are the same tree. For a SHARED one they are not:
# on the 2.1.183 implicit-team model every member's config.json `cwd` is the LEAD's spawn cwd, shared
# verbatim by the whole team (verified: team session-a8e72ae5 — lead + 3 members all recorded
# ~/Development/.worktrees/gu-session-lifecycle). Resolving (b) to that tree would make the reap of
# ONE pool teammate `--force`-remove the LEAD's worktree and every sibling's uncommitted work.
# So: resolution legs that prove per-MEMBER ownership set OWNED=true; the shared-cwd leg leaves it
# false, which still buys every gate in (a) — strictly more safety than today's unresolved-and-blind
# path — while the removal below stays refused. Gate on a shared tree, never destroy one.
WORKTREE_OWNED=false

# Build candidate member names: full, and with trailing "-N" stripped.
MEMBER_CANDIDATES=("$TEAMMATE_NAME")
if [[ "$TEAMMATE_NAME" =~ ^(.+)-[0-9]+$ ]]; then
  MEMBER_CANDIDATES+=("${BASH_REMATCH[1]}")
fi

# (#16) Resolve member→worktree from the team MANIFEST first — the legacy
# /tmp globs below cannot match branch-named worktrees like
# ~/Development/.worktrees/wt-journal-gate, so a Track-R teammate would be
# reaped with WORKTREE="" → no checkpoint → lost work (re-gate N1).
PAYLOAD_CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || echo '')
PAYLOAD_CWD="${PAYLOAD_CWD#/private}"

# Primary: the team manifest, located via the SHARED git-common-dir (resolves
# to the same main repo root from a teammate worktree OR the lead root — the
# untracked .claude/team-briefs/ lives only in that root).
resolve_from_manifest() {
  local seed="$1" common root manifest count i name wt m
  [[ -n "$seed" && -e "$seed" ]] || return 1
  command -v yq >/dev/null 2>&1 || return 1
  common=$(git -C "$seed" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || return 1
  root="${common%/.git}"
  manifest="$root/.claude/team-briefs/$TEAM_NAME/manifest.yaml"
  [[ -f "$manifest" ]] || return 1
  count=$(yq eval '.members | length' "$manifest" 2>/dev/null) || return 1
  [[ "$count" =~ ^[0-9]+$ ]] || return 1
  for (( i=0; i<count; i++ )); do
    name=$(yq eval ".members[$i].name" "$manifest" 2>/dev/null)
    for m in "${MEMBER_CANDIDATES[@]}"; do
      if [[ "$name" == "$m" ]]; then
        wt=$(yq eval ".members[$i].worktree" "$manifest" 2>/dev/null)
        wt="${wt/#\~/$HOME}"
        if [[ -n "$wt" && -d "$wt" ]]; then printf '%s\n' "$wt"; return 0; fi
      fi
    done
  done
  return 1
}
if MANIFEST_WT=$(resolve_from_manifest "$PAYLOAD_CWD"); then
  WORKTREE="$MANIFEST_WT"          # manifest declares a per-member worktree ⇒ dedicated
  WORKTREE_OWNED=true
fi

# ── Team config.json — the ONE file that always exists for an implicit team (2026-07-29) ─────────
# Read once here and reused by both new legs below. CC writes $CLAUDE_CONFIG_DIR/teams/<team>/
# config.json for every team INCLUDING the 2.1.183 implicit ones (`session-<id>`), recording each
# member's `cwd` — and the close block at the bottom of this hook already opens exactly this file
# for tmuxPaneId. The worktree answer was sitting in a file we already read and never looked at.
# Prefer the root that actually lists this member; a stale same-named team dir must not shadow it.
TEAM_CONFIG=""
for _root in "${TEAM_ROOTS[@]}"; do
  _cand_cfg="$_root/$TEAM_NAME/config.json"
  [[ -f "$_cand_cfg" ]] || continue
  [[ -z "$TEAM_CONFIG" ]] && TEAM_CONFIG="$_cand_cfg"        # first existing = weakest fallback
  for m in "${MEMBER_CANDIDATES[@]}"; do
    if jq -e --arg m "$m" '.members[]? | select(.name==$m)' "$_cand_cfg" >/dev/null 2>&1; then
      TEAM_CONFIG="$_cand_cfg"; break 2
    fi
  done
done

# ── LEG: the member's OWN worktree, by name, from git itself (2026-07-29) ────────────────────────
# WHY this leg exists: every pre-existing leg is structurally dead for an implicit team. The manifest
# above needs .claude/team-briefs/<team>/manifest.yaml (no such file exists anywhere on this machine);
# the TSV below is written only by create-team.sh (present for 4 named teams from June, none of the
# `session-*` ones); the /tmp globs cannot match ~/Development/.worktrees/<name>, which is where the
# native `claude -w` / Agent worktrees actually live. Net effect measured 2026-07-29: WORKTREE was
# unresolved for 100% of implicit-team teammates — 81 SURFACE pages, and reap-guard's decision-record
# dir was EMPTY, i.e. the whole birth-grace/effect-read/adoption gate had never once executed.
# git is the authority on where a worktree is, so ask git: the fleet convention is one worktree per
# member named for that member (gu5-verdict → ~/Development/.worktrees/gu5-verdict, all in
# `git worktree list`). A basename match is per-MEMBER evidence ⇒ dedicated ⇒ removable.
resolve_by_worktree_name() {
  local seed="$1" line wt base m
  [[ -n "$seed" && -d "$seed" ]] || return 1
  while IFS= read -r line; do
    wt="${line#worktree }"
    [[ "$wt" != "$line" ]] || continue          # only `worktree <path>` records
    # ONE normal form. git reports the path as recorded at `worktree add`, which on macOS is the
    # /private-prefixed realpath for anything under /var or /tmp, while every other leg here yields
    # the unprefixed form (PAYLOAD_CWD and the config cwd are both `#/private`-stripped). Two spellings
    # of one directory would then reach the log line, the checkpoint payload, the patch header and the
    # teardown marker. Strip only when the result still resolves — an unconditional strip would break a
    # path that genuinely lives under /private with no /-rooted twin.
    [[ "$wt" == /private/* && -d "${wt#/private}" ]] && wt="${wt#/private}"
    base="${wt##*/}"
    for m in "${MEMBER_CANDIDATES[@]}"; do
      if [[ "$base" == "$m" && -d "$wt" ]]; then printf '%s\n' "$wt"; return 0; fi
    done
  done < <(git -C "$seed" worktree list --porcelain 2>/dev/null)
  return 1
}
if [[ -z "$WORKTREE" ]]; then
  # The seed only has to be SOME live path inside the right repo — `git worktree list` then reports
  # every worktree of that repo, including the member's. Try each candidate until one is a live dir:
  # a DEAD seed silently disables this whole leg. Live case that proved it (team session-8891c11f,
  # 2026-07-29): the recorded cwd for all 7 members is ~/Development/.worktrees/gu-autonomy-dispatch,
  # which no longer exists — yet gu5-verdict/-decide/-cadence each still own a worktree of their own
  # name. Seeding from only the first recorded cwd left every one of them unresolved.
  _named_seeds=()
  [[ -n "$PAYLOAD_CWD" ]] && _named_seeds+=("$PAYLOAD_CWD")
  if [[ -n "$TEAM_CONFIG" ]]; then
    while IFS= read -r _c; do
      [[ -n "$_c" ]] && _named_seeds+=("${_c#/private}")
    done < <(jq -r '[.members[]?.cwd // empty] | map(select(.!="")) | unique | .[]' "$TEAM_CONFIG" 2>/dev/null)
  fi
  for _seed in "${_named_seeds[@]:-}"; do
    [[ -n "$_seed" && -d "$_seed" ]] || continue
    if NAMED_WT=$(resolve_by_worktree_name "$_seed"); then
      WORKTREE="$NAMED_WT"
      WORKTREE_OWNED=true
      break
    fi
  done
fi

# Fallback: a global TSV (<member>\t<worktree>) persisted by create-team.sh —
# keyed only by team, so it needs no project path from the payload. Scan every
# team root: create-team.sh writes under ~/.claude/teams, but a secondary-led
# team's state may exist only under ~/.claude-secondary/teams.
if [[ -z "$WORKTREE" ]]; then
  for _root in "${TEAM_ROOTS[@]}"; do
    TSV="$_root/$TEAM_NAME/worktrees.tsv"
    [[ -f "$TSV" ]] || continue
    for m in "${MEMBER_CANDIDATES[@]}"; do
      cand=$(awk -F'\t' -v want="$m" '$1==want{print $2; exit}' "$TSV" 2>/dev/null || echo '')
      cand="${cand/#\~/$HOME}"
      if [[ -n "$cand" && -d "$cand" ]]; then WORKTREE="$cand"; WORKTREE_OWNED=true; break 2; fi
    done
  done
fi

# Legacy /tmp exact-match attempt (only if manifest/TSV didn't resolve)
if [[ -z "$WORKTREE" ]]; then
  for m in "${MEMBER_CANDIDATES[@]}"; do
    for candidate in \
      "/tmp/wt-${TEAM_NAME}-${m}" \
      "/tmp/worktree-${TEAM_NAME}-${m}" \
      "/tmp/worktree-${m}"; do
      if [[ -d "$candidate" ]]; then
        WORKTREE="$candidate"        # per-member path ⇒ dedicated
        WORKTREE_OWNED=true
        break 2
      fi
    done
  done
fi

# Glob fallback: match any /tmp/wt-*-<member> or /tmp/worktree-*-<member>.
# This catches the case where the team slug in the path != team_name
# (e.g., /tmp/wt-ui-sh-v2-quality-keeper vs team_name=ui-sh-100p-v2).
if [[ -z "$WORKTREE" ]]; then
  shopt -s nullglob
  for m in "${MEMBER_CANDIDATES[@]}"; do
    for candidate in /tmp/wt-*-"${m}" /tmp/worktree-*-"${m}"; do
      if [[ -d "$candidate" ]]; then
        WORKTREE="$candidate"        # per-member path ⇒ dedicated
        WORKTREE_OWNED=true
        break 2
      fi
    done
  done
  shopt -u nullglob
fi

# ── LAST LEG: the team config's recorded cwd — GATE-ONLY, never removable (2026-07-29) ───────────
# Deliberately last: every leg above is per-MEMBER evidence, this one is not. On the implicit-team
# model `.members[].cwd` is the cwd the member was SPAWNED in, which is the lead's — team
# session-8891c11f records ~/Development/.worktrees/gu-autonomy-dispatch for all 7 members even
# though gu5-verdict/-decide/-cadence each own a worktree of their own name (the name leg above
# catches those first, which is exactly why it runs first). Two consequences, both handled:
#   • It is often SHARED ⇒ OWNED stays false ⇒ the removal at the bottom refuses it. Marking it
#     owned would `--force`-remove the lead's tree on the first pool teammate reaped.
#   • It can be STALE — the recorded dir may already be gone (that same team's cwd no longer
#     exists). A non-directory is not a resolution; fall through to the fail-closed defer instead.
# What it DOES buy: for genuinely-shared pool teammates this is the real tree they work in, so the
# busy-marker, dirty-tree and reap-guard effect-read gates finally run on something true.
if [[ -z "$WORKTREE" && -n "$TEAM_CONFIG" ]]; then
  for m in "${MEMBER_CANDIDATES[@]}"; do
    cfg_cwd=$(jq -r --arg m "$m" '.members[]? | select(.name==$m) | .cwd // empty' "$TEAM_CONFIG" 2>/dev/null | head -1)
    cfg_cwd="${cfg_cwd#/private}"
    [[ -n "$cfg_cwd" && -d "$cfg_cwd" ]] || continue
    WORKTREE="$cfg_cwd"
    # Dedicated ONLY if this member is the sole occupant of that cwd; any sibling (the lead counts)
    # sharing it ⇒ shared ⇒ gate-only. jq counts members recording the same path.
    _occupants=$(jq -r --arg c "$cfg_cwd" '[.members[]? | select((.cwd // "") == $c)] | length' "$TEAM_CONFIG" 2>/dev/null)
    if [[ "$_occupants" == "1" ]]; then
      WORKTREE_OWNED=true
    else
      log "  ↳ $TEAMMATE_NAME: worktree $WORKTREE is SHARED by ${_occupants:-?} members — gating on it, removal refused"
    fi
    break
  done
fi

# Rule 4 — cooperative busy marker
if [[ -n "$WORKTREE" && -f "$WORKTREE/.teammate-busy" ]]; then
  log "defer $TEAMMATE_NAME (team=$TEAM_NAME): .teammate-busy marker present"
  # Do NOT emit {"continue": false}; let the teammate keep working.
  exit 0
fi

# Rule 3 — defer on dirty tree, bounded by MAX_DEFERS
DEFER_COUNTER="$WATCHDOG_DIR/defer-$SESSION_ID-$TEAMMATE_NAME.count"
DEFER_COUNT=0
[[ -f "$DEFER_COUNTER" ]] && DEFER_COUNT=$(cat "$DEFER_COUNTER" 2>/dev/null || echo 0)

TREE_DIRTY=false
if [[ -n "$WORKTREE" ]]; then
  if git -C "$WORKTREE" status --porcelain 2>/dev/null | grep -q .; then
    TREE_DIRTY=true
  fi
fi

if $TREE_DIRTY && (( DEFER_COUNT < MAX_DEFERS )); then
  DEFER_COUNT=$((DEFER_COUNT + 1))
  echo "$DEFER_COUNT" > "$DEFER_COUNTER"
  log "defer $TEAMMATE_NAME ($DEFER_COUNT/$MAX_DEFERS): dirty tree"
  # Snapshot what's there so we don't lose work if they never quiesce.
  "$HOOK_DIR/teammate-checkpoint.sh" <<<"{\"hook_event_name\":\"TeammateIdle\",\"session_id\":\"$SESSION_ID\",\"cwd\":\"$WORKTREE\",\"team_name\":\"$TEAM_NAME\",\"teammate_name\":\"$TEAMMATE_NAME\"}" \
    2>/dev/null || true
  # Do NOT emit {"continue": false}; let the teammate keep working.
  exit 0
fi

# ── TOOL-IN-FLIGHT hold (2026-07-29) — a running tool is positive evidence of LIFE ───────────────
# Sits BEFORE reap-guard and is deliberately independent of $WORKTREE: it reads the teammate's own
# transcript, so it holds for the teammates no worktree leg can resolve (a member with no `cwd`
# recorded, or a team with no config.json at all) as well as for the resolved ones.
# It is also the safety companion to the resolution fix above. Until 2026-07-29 an implicit-team
# teammate never got past the unresolved-worktree defer, so it was never closeable at all; now that
# those worktrees DO resolve, such a teammate reaches the close for the first time — and a live one
# mid-tool_use with a clean tree and products since spawn is precisely what reap-guard would wave
# through. Neither tree-state nor turn-silence can see a running tool; only the transcript can.
# UNBOUNDED by design (not charged to MAX_DEFERS): a tool that is still running is a fact, not a
# stall, and it clears itself the moment the tool_result lands.
if _tool_in_flight "$SESSION_ID"; then
  log "defer $TEAMMATE_NAME (team=$TEAM_NAME): tool in flight — teammate is live, not idle"
  # Do NOT emit {"continue": false}; the teammate is mid-call.
  exit 0
fi

# ── reap-safety birth-grace + effect-read + operator-adoption gate (P0-13 reap-guard R-a/R-b + R-d) ──
# The LAST gate before reap: a just-born teammate (within grace), a clean tree with NO work products
# since spawn (indistinguishable from finished by tree-state alone), OR a pane the OPERATOR adopted
# (typed into after its spawn brief — the 2026-07-24 reaper incident class, which this hook otherwise
# reaps who-blind) — DEFER, do not shut down. --session-id lets reap-guard read WHO drove the last turn.
REAP_GUARD="${CC_REAP_GUARD_BIN:-$HOME/.claude/scripts/reap-guard.sh}"
if [[ -n "$WORKTREE" && -x "$REAP_GUARD" ]]; then
  # spawn-time = registry startedAt (epoch-MILLISECONDS) / 1000; unresolvable → now → DEFER (fail-safe)
  _started_ms="$(cc-sessions --json 2>/dev/null \
     | jq -r --arg s "$SESSION_ID" '.[] | select((.session_id // .sessionId)==$s) | .startedAt // empty' 2>/dev/null | head -1)"
  if [[ "$_started_ms" =~ ^[0-9]+$ ]]; then _spawn_s=$(( _started_ms / 1000 )); else _spawn_s="$(date +%s)"; fi
  if ! "$REAP_GUARD" decide --worktree "$WORKTREE" --member "$TEAMMATE_NAME" --spawn-time "$_spawn_s" --session-id "$SESSION_ID" >/dev/null 2>&1; then
    log "defer $TEAMMATE_NAME (team=$TEAM_NAME): reap-guard DEFER (birth-grace / no-products / operator-adopted)"
    # Do NOT emit {"continue": false}; let the just-born teammate keep working.
    exit 0
  fi
fi

# ── FAIL-CLOSED on unresolved WORKTREE (2026-07-24) ──────────────────────────────────────────────
# Every safety gate above (busy-marker, dirty-defer, reap-guard) AND the checkpoint below is
# conditioned on -n "$WORKTREE". When worktree resolution misses (a branch-named path we could not
# map, or a config-write race), ALL of them silently no-op and the close below would proceed with
# ZERO gates evaluated and NO checkpoint — the ungated-close defect. Fail closed: DEFER on the SAME
# counter (same MAX_DEFERS), and after the last defer SURFACE (loud log + best-effort desk page)
# rather than ever closing ungated. A close with zero gates evaluated must be impossible.
if [[ -z "$WORKTREE" ]]; then
  if (( DEFER_COUNT < MAX_DEFERS )); then
    DEFER_COUNT=$((DEFER_COUNT + 1))
    echo "$DEFER_COUNT" > "$DEFER_COUNTER"
    log "defer $TEAMMATE_NAME ($DEFER_COUNT/$MAX_DEFERS): WORKTREE unresolved — no safety gate could run, refusing ungated close"
    # Do NOT emit {"continue": false}; leave the teammate's turn untouched.
    exit 0
  fi
  log "⚑ SURFACE $TEAMMATE_NAME (team=$TEAM_NAME): WORKTREE unresolved after $MAX_DEFERS defers — refusing ungated close, paging desk (session=$SESSION_ID)"
  # DAMPED (2026-07-29): this leg re-fires on EVERY subsequent TeammateIdle for the same teammate —
  # measured 81 pages, one teammate paging 6 times in 3 minutes. A close-order channel that repeats
  # itself trains the operator to ignore it, so the page is keyed on its STATE (team+member+cause)
  # and re-asserts on the page-damp TTL (~2/hour) instead of every sweep. The LOG line above stays
  # undamped — the forensic record must remain complete even when the page is suppressed.
  _page_desk_damped "WORKTREE-UNRESOLVED:$TEAM_NAME:$TEAMMATE_NAME" \
    "teammate-auto-shutdown SURFACE: cannot resolve worktree for $TEAMMATE_NAME (team $TEAM_NAME, session $SESSION_ID) after $MAX_DEFERS defers — pane NOT closed (would be ungated). Confirm-close manually."
  exit 0
fi

# Clear defer counter — we're proceeding to reap
rm -f "$DEFER_COUNTER" 2>/dev/null || true

log "Auto-shutdown idle teammate: $TEAMMATE_NAME (team: $TEAM_NAME)"

# Rule 1 + 2 — CHECKPOINT FIRST, then fallback patch if checkpoint failed.
# This must happen BEFORE git worktree remove.
CHECKPOINT_OK=false
if [[ -n "$WORKTREE" ]]; then
  if "$HOOK_DIR/teammate-checkpoint.sh" <<<"{\"hook_event_name\":\"TeammateIdle\",\"session_id\":\"$SESSION_ID\",\"cwd\":\"$WORKTREE\",\"team_name\":\"$TEAM_NAME\",\"teammate_name\":\"$TEAMMATE_NAME\"}" 2>/dev/null; then
    CHECKPOINT_OK=true
    log "  ✓ final checkpoint written for $WORKTREE"
  else
    log "  ✗ checkpoint failed for $WORKTREE — writing fallback patch"
  fi

  # Regardless of checkpoint success, also emit a patch if tree is dirty
  # (belt-and-suspenders — the teammate always has a recoverable trace)
  if git -C "$WORKTREE" status --porcelain 2>/dev/null | grep -q .; then
    PATCH="/tmp/${TEAM_NAME}-${TEAMMATE_NAME}-$(date -u +%Y%m%dT%H%M%SZ).patch"
    {
      echo "# Auto-patch from teammate-auto-shutdown.sh"
      echo "# Team: $TEAM_NAME  Member: $TEAMMATE_NAME"
      echo "# Worktree: $WORKTREE"
      echo "# Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
      echo "# Checkpoint status: $($CHECKPOINT_OK && echo 'written' || echo 'failed — rely on this patch')"
      echo "# --- status ---"
      git -C "$WORKTREE" status --porcelain 2>/dev/null || true
      echo "# --- diff HEAD (tracked changes only) ---"
      git -C "$WORKTREE" diff HEAD 2>/dev/null || true
    } > "$PATCH" 2>/dev/null
    log "  ✓ fallback patch: $PATCH"
  fi
fi

# Rule 5 — close the teammate's pane, then remove its worktree.
# Resolve the pane id + canonical member name from the team config.json across
# TEAM_ROOTS — a secondary-led team's config lives ONLY under
# ~/.claude-secondary/teams (the tier0 lingering-pane bug, 2026-06-09). The
# member name may be auto-incremented, so match against MEMBER_CANDIDATES.
# Prefer the root whose config recorded a non-empty tmuxPaneId: a stale
# same-named team dir in the other root must never shadow the live one.
PANEID=""
MEMBER_NAME="$TEAMMATE_NAME"
for _root in "${TEAM_ROOTS[@]}"; do
  CONFIG="$_root/$TEAM_NAME/config.json"
  [[ -f "$CONFIG" ]] || continue
  RESOLVED=$(jq -r --args \
    '.members[]? | select(.name as $n | $ARGS.positional | index($n)) | "\(.name)\t\(.tmuxPaneId // "")"' \
    "${MEMBER_CANDIDATES[@]}" < "$CONFIG" 2>/dev/null | head -1)
  if [[ -n "$RESOLVED" && "$RESOLVED" == *$'\t'* ]]; then
    MEMBER_NAME="${RESOLVED%%$'\t'*}"
    PANEID="${RESOLVED#*$'\t'}"
    [[ -z "$MEMBER_NAME" ]] && MEMBER_NAME="$TEAMMATE_NAME"
    [[ -n "$PANEID" ]] && break
  fi
done

# Implicit-team (CC 2.1.178+) fallback — env-method, instant: if the config
# lookup found no pane id, resolve from the idle teammate's OWN claude.exe
# ($PPID on this model). Safety-gated to a process whose --agent-id matches this
# teammate (see helpers). The slower tty-method runs later in the unbounded
# detached close, so we keep this in-body path instant (5s hook budget).
TEAMMATE_PID=""
if [[ -z "$PANEID" ]]; then
  TEAMMATE_PID=$(_find_teammate_pid || true)
  if [[ -n "$TEAMMATE_PID" ]]; then
    PANEID=$(_pane_from_env "$TEAMMATE_PID" || true)
    [[ -n "$PANEID" ]] \
      && log "  ↳ implicit-team: pane $PANEID for $MEMBER_NAME via env (teammate pid $TEAMMATE_PID)"
  fi
fi

# ── OPERATOR-ADOPTION hold (2026-07-24; mirrors cc-classify 4.7 / hooks/lib/cc-interactive.sh) ────
# BELT+SUSPENDERS (2026-07-25): a SECOND, independent belt COMPLEMENTING scripts/reap-guard.sh guard
# R-d (fc633b5) — same predicate family (a real operator prompt after the spawn brief, within the
# hold ⇒ hold), but lib-based here (ci_last_interactive_epoch, distinct envs CC_CLASSIFY_INTERACTIVE_
# HOLD_S/_DISABLE) vs R-d's context-econ ce_last_interactive_age via the reap-guard --session-id
# wiring. Classify-hold + reaper-belt precedent — two guards, not one; reap-guard.sh is single-owned.
# A teammate pane a human OPERATOR has typed real prompts into is ADOPTED — never force-close it on
# TeammateIdle. Between prompts an adopted pane is indistinguishable from a finished teammate by
# tree-state alone (idle + clean), so the ONE signal we trust is WHO drove the last turn:
# ci_last_interactive_epoch returns the epoch of the last REAL operator-typed prompt. Newer than
# spawn+SLACK (the spawn brief arrives as a user prompt and must NOT count as adoption) AND within
# the hold window ⇒ adopted → surface (page), never close. The WHO-primitive lives in
# hooks/lib/cc-interactive.sh (lands separately) — absent ⇒ one WARN + skip (graceful degradation).
# THIRD STATE (2026-07-29, C-SC-1): the primitive now distinguishes "the transcript parsed and nobody
# typed" (rc 1 — a FACT that may license the close) from "we could not READ the answer" (rc 2,
# "unreadable" — corrupt/truncated/empty/no-jq). rc 2 HOLDS + pages, exactly like adoption: absence of
# evidence is not evidence of absence on an actuator that force-closes a pane.
# Kill switch: CC_CLASSIFY_INTERACTIVE_HOLD_DISABLE=1.
_hold_on=1
[[ "${CC_CLASSIFY_INTERACTIVE_HOLD_DISABLE:-0}" == "1" ]] && _hold_on=0
{ [[ "$INTERACTIVE_HOLD_S" =~ ^[0-9]+$ ]] && (( INTERACTIVE_HOLD_S > 0 )); } || _hold_on=0
if (( _hold_on )); then
  if [[ -f "$INTERACTIVE_LIB" ]]; then
    # shellcheck source=/dev/null
    . "$INTERACTIVE_LIB" 2>/dev/null || true
  fi
  if ! type -t ci_last_interactive_epoch >/dev/null 2>&1; then
    log "  WARN: cc-interactive.sh absent ($INTERACTIVE_LIB) — skipping operator-adoption check (degraded)"
  else
    _adopt_tj="$(_find_transcript "$SESSION_ID" || true)"
    if [[ -z "$_adopt_tj" && -n "$PANEID" ]]; then
      _alt_sid="$(cc-sessions --json 2>/dev/null | jq -r --arg p "$PANEID" \
                  '.[] | select(.paneUUID==$p) | (.session_id // .sessionId) // empty' 2>/dev/null | head -1)"
      [[ -n "$_alt_sid" ]] && _adopt_tj="$(_find_transcript "$_alt_sid" || true)"
    fi
    if [[ -n "$_adopt_tj" ]]; then
      _irc=0
      _iep="$(ci_last_interactive_epoch "$_adopt_tj" 2>/dev/null)" || _irc=$?
      if (( _irc == 2 )); then
        # THREE-VALUED contract (hooks/lib/cc-interactive.sh, 2026-07-29 C-SC-1 close): "unreadable" —
        # corrupt / truncated / binary / empty / no jq. NOT "nobody typed". Before the split this
        # returned the same empty answer as a parsed-but-quiet transcript and fell through to the
        # pane CLOSE below, so an unreadable transcript licensed exactly the force-close this belt
        # exists to prevent. reap-guard R-d fails closed the same way — but only for teammates that
        # HAVE a worktree (the reap-guard call above is gated on $WORKTREE), so for a worktree-less
        # teammate this belt is the ONLY who-gate and must not fall open.
        log "  ⚑ who-oracle UNREADABLE for $_adopt_tj (corrupt/truncated/empty, or no jq) — 'cannot read' is not 'nobody typed'; NOT closing pane [$PANEID] ($MEMBER_NAME); paging desk"
        # Damped for the same reason as the SURFACE page: both re-fire on EVERY subsequent
        # TeammateIdle. Neither had ever fired before 2026-07-29 — not because they are rare, but
        # because the unresolved-worktree defer above short-circuited every implicit-team teammate
        # before it could reach them. The resolution fix makes this belt reachable for the first
        # time, so it gets the damping up front rather than after it becomes the next 81-page log.
        _page_desk_damped "ADOPTION-UNREADABLE:$TEAM_NAME:$MEMBER_NAME" \
          "teammate-auto-shutdown HELD: pane $PANEID ($MEMBER_NAME, team $TEAM_NAME) — the operator-presence oracle could not READ its transcript ($_adopt_tj), so adoption is unprovable; left open, confirm-close manually."
        exit 0
      fi
      if [[ "$_iep" =~ ^[0-9]+$ ]]; then
        _now="${CC_CLASSIFY_NOW:-$(date +%s)}"
        _spawn_s="$(_spawn_epoch "$SESSION_ID" || echo 0)"; [[ "$_spawn_s" =~ ^[0-9]+$ ]] || _spawn_s=0
        _iage=$(( _now - _iep )); (( _iage < 0 )) && _iage=0
        if (( _iage < INTERACTIVE_HOLD_S )) && (( _iep > _spawn_s + FIRE_PROMPT_SLACK_S )); then
          log "  ⚑ operator-adopted: real prompt ${_iage}s ago (< hold ${INTERACTIVE_HOLD_S}s, past spawn+${FIRE_PROMPT_SLACK_S}s) — NOT closing pane [$PANEID] ($MEMBER_NAME); paging desk"
          # Damped on (team, member, cause) — see the note on the unreadable-oracle page above.
          _page_desk_damped "ADOPTION-HELD:$TEAM_NAME:$MEMBER_NAME" \
            "teammate-auto-shutdown HELD: pane $PANEID ($MEMBER_NAME, team $TEAM_NAME) is operator-adopted — real prompt ${_iage}s ago; left open, confirm-close manually."
          # Do NOT emit {"continue": false}; leave the operator's turn untouched.
          exit 0
        fi
      fi
    fi
  fi
fi

# PPID-forensic (logs only; no kill). On the classic 2.1.114 LEAD-side model
# $PPID was the dead/recycled /bin/sh shim (the retired `kill -TERM $PPID` bug);
# on the 2.1.183 implicit-team model $PPID is the idle teammate's own claude.exe
# (`--agent-id <member>@session-<id>`) — which is exactly what the implicit-team
# resolver above keys off. Grep teammate-lifecycle.log for "PPID-forensic".
log "  PPID-forensic: \$PPID=$PPID cmd=[$(ps -p "$PPID" -o command= 2>/dev/null | tr -d '\n' || echo 'dead/recycled')] pane=[$PANEID] member=$MEMBER_NAME"

# Stop the teammate's current turn — JSON on stdout with exit 0.
echo '{"continue": false, "stopReason": "Idle teammate auto-shutdown (work preserved in refs/wip/LAST + /tmp/*.patch; pane closed via it2/tmux)"}'

# Detached close so the hook itself returns within its 5s timeout. Ordering:
#   brief grace for CC to flush the {"continue":false} response → close the EXACT
#   pane → remove the worktree. Work is already checkpointed above, so removing
#   the worktree here cannot lose work.
(
  sleep "$CLOSE_GRACE_S"
  if [[ -n "$PANEID" ]]; then
    close_and_log "$PANEID" "$MEMBER_NAME"
  else
    # Implicit-team tty-method fallback (unbounded here — no 5s hook limit), in
    # case the in-body env-method missed (e.g. ITERM_SESSION_ID absent). Still
    # safety-gated via _find_teammate_pid's --agent-id match.
    [[ -z "$TEAMMATE_PID" ]] && TEAMMATE_PID=$(_find_teammate_pid || true)
    LATE_PANE=$(_pane_from_tty "$TEAMMATE_PID" || true)
    if [[ -n "$LATE_PANE" ]]; then
      log "  ↳ implicit-team: pane $LATE_PANE for $MEMBER_NAME via tty (teammate pid $TEAMMATE_PID)"
      close_and_log "$LATE_PANE" "$MEMBER_NAME"
    else
      log "  ! no pane id resolved for $MEMBER_NAME — left for CC session-end cleanup"
    fi
  fi
  # `--force` DISCARDS uncommitted work, so this must fire only on a tree this member provably OWNS.
  # WORKTREE_OWNED is false when the path came from the shared team-config cwd (2026-07-29): on the
  # implicit-team model that is the LEAD's worktree, recorded identically for every member, so an
  # unguarded remove would destroy the lead's tree and every sibling's uncommitted work the first
  # time any one pool teammate went idle. Gate on a shared tree; never destroy one.
  if [[ -n "$WORKTREE" ]] && $WORKTREE_OWNED; then
    MAIN_REPO=$(git -C "$WORKTREE" rev-parse --git-common-dir 2>/dev/null | sed 's|/\.git$||')
    if [[ -n "$MAIN_REPO" && -d "$MAIN_REPO" ]]; then
      git -C "$MAIN_REPO" worktree remove "$WORKTREE" --force 2>/dev/null \
        && log "  ✓ worktree removed: $WORKTREE"
    fi
  elif [[ -n "$WORKTREE" ]]; then
    log "  ~ worktree kept (shared, not owned by $MEMBER_NAME): $WORKTREE"
  fi
) >/dev/null 2>&1 &

exit 0
