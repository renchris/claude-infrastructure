#!/bin/bash
# P1 — RC-10 probe: does the vendor's cleanupSessionTeams (2000 ms race, D §4) close
# ALL FOUR member panes when a lead exits gracefully?
#
# SAFETY: this script only ever touches windows/processes it created itself. Every
# census is a SET DIFFERENCE against a pre-launch snapshot; nothing outside that delta
# is read, matched, signalled or closed. There is no kill, no `it2 session close`, no
# `kitty @ close-window` anywhere in this file. The lead is ended by typing `/exit`
# into the lead's OWN composer — the vendor's graceful-exit path, which is the subject.
#
# Fleet closer neutralised via its OWN documented kill switch TEAMMATE_SHUTDOWN_DISABLED=1
# (hooks/teammate-auto-shutdown.sh:80) so the probe measures the VENDOR and not the fleet
# actuator. No fleet code is modified.
#
# Usage: ./run-p1.sh <run-label>
set -uo pipefail

RUN="${1:?usage: run-p1.sh <run-label> | --census}"
case "$RUN" in --census) ;; -*) echo "run-p1.sh: unknown option '$RUN' (expected a run label or --census)" >&2; exit 2 ;; esac
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# The scratch lives OUTSIDE the repo and is PUBLISHED into captures/ only when the run ends.
# Writing it in-tree makes the worktree dirty for the whole run, and scripts/ship-land.sh
# fail-closes on a dirty tree — so an in-flight measurement blocked every land. Evidence is
# committed; run state is not.
CAP="${PROBE_SCRATCH:-/tmp/claude-501/teammate-probe}/$RUN"
PUB="$HERE/captures/p1-$RUN"
rm -rf "$CAP"; mkdir -p "$CAP"
publish() {  # never publish an empty scratch (e.g. the --census self-test path)
  [ -n "$(ls -A "$CAP" 2>/dev/null)" ] || return 0
  mkdir -p "$PUB" && cp -R "$CAP"/. "$PUB"/ 2>/dev/null; echo "published -> $PUB"; }
trap publish EXIT
# The scratch project's own settings. `settings.local.json` is gitignored repo-wide and
# force-adding a gitignored path is forbidden, so the fixture ships the .example and installs it
# here — that keeps the probe re-runnable from a clean clone without an `add -f`.
if [[ ! -f "$HERE/.claude/settings.local.json" && -f "$HERE/.claude/settings.local.json.example" ]]; then
  cp "$HERE/.claude/settings.local.json.example" "$HERE/.claude/settings.local.json"
fi
CLAUDE_BIN="${PROBE_CLAUDE_BIN:-$HOME/.claude-260/node_modules/.bin/claude}"
KL="${KITTY_LISTEN_ON:?KITTY_LISTEN_ON must be set}"
IDLE_TIMEOUT_S="${PROBE_IDLE_TIMEOUT_S:-600}"
SETTLE_S="${PROBE_SETTLE_S:-30}"

ts() { date -u +%Y-%m-%dT%H:%M:%SZ; }
log() { echo "[$(ts)] $*" | tee -a "$CAP/run.log"; }

box() {  # $1 = label ; the addendum's load control
  { echo "== BOX $1 @ $(ts) =="
    uptime
    top -l 2 -n 0 | /usr/bin/grep '^CPU usage' | tail -1
  } | tee -a "$CAP/box-$1.txt"
}

win_ids() { kitten @ --to "$KL" ls 2>/dev/null | python3 -c '
import json,sys
d=json.load(sys.stdin)
print("\n".join(str(w["id"]) for o in d for t in o["tabs"] for w in t["windows"]))' | sort; }

# Every claude agent process on the box, as "pid<TAB>full argv". We never match on a
# bare name (memory: pgrep-f-matches-agent-briefs); ownership is decided by set
# difference plus the three-flag conjunction --agent-id/--agent-name/--team-name.
# The pattern travels in the ENVIRONMENT, never in argv: a concurrent `ps` prints the
# matcher's own command line, so a grep for its own pattern matches itself and answers YES
# for anything asked (docs/lessons/census-matches-itself.md). Observed live in this probe's
# first P2 census, which matched two of this session's own Bash-tool shells.
# ...and the assignment must sit on AWK, not on ps: `VAR=x cmd` binds VAR to that command
# only, so awk would read it EMPTY and index($0,"") is 1 for every line — an empty selector
# is a universal selector (docs/lessons/empty-selector-is-a-universal-selector.md). Caught
# here by a control that expected 0 rows and printed 1302.
# A bare `--agent-id` match is worthless on this box: measured 2026-09-19, 5 rows matched and
# ALL FIVE were false — one was this census's own shell, four were full SESSIONS whose argv
# carries a brief that MENTIONS the flag (memory: pgrep-f-matches-agent-briefs). A member is
# the binary `claude.exe` carrying all three membership flags, and nothing else.
agent_procs() {
  # A member is a process whose argv[0] IS the claude.exe binary and which carries all three
  # membership flags. Matching the whole line is not enough on this box: measured 2026-09-19,
  # a whole-line match returned 5 rows and all 5 were false — this census's own shell, and
  # sibling SESSIONS whose argv carries a brief that merely MENTIONS the flags (memory:
  # pgrep-f-matches-agent-briefs; docs/lessons/census-matches-itself.md). argv[0] cannot be
  # spoofed by prose, so the anchor is $2, and the patterns travel in the ENVIRONMENT.
  ps -eo pid= -o command= \
    | P_ID='--agent-id ' P_NM='--agent-name ' P_TM='--team-name session-' \
      awk '$2 ~ /claude\.exe$/ && index($0,ENVIRON["P_ID"]) \
           && index($0,ENVIRON["P_NM"]) && index($0,ENVIRON["P_TM"])'
}

if [[ "$RUN" == "--census" ]]; then
  # Self-test: the matcher must not match itself. Every pattern is in the ENVIRONMENT and
  # this file is read from disk, so no command line anywhere carries one.
  echo "live members now:"; agent_procs | cut -c1-120; echo "count=$(agent_procs | wc -l | tr -d ' ')"; exit 0
fi

log "=== P1 run '$RUN' — binary $CLAUDE_BIN ==="
"$CLAUDE_BIN" --version > "$CAP/claude-version.txt" 2>&1; log "binary version: $(cat "$CAP/claude-version.txt")"

# ── PREFLIGHT ────────────────────────────────────────────────────────────────────────────────
# Two independent reasons this probe must not run on a busy box, and they happen to coincide:
#  (a) RC-10's subject is a 2 000 ms wall-clock race, so a loaded box makes the vendor miss it for
#      reasons that are nothing to do with the vendor — a FALSE "probe FAILED", and failure is the
#      direction that licenses a fleet-side change. A cure or a defect is verified only under the
#      load that produced it.
#  (b) the fleet's own admission gate (hooks/agent-teams-enforce.sh -> cc_capacity_admit) refuses a
#      spawn when too many sessions are MID-TURN (ceiling 8). Run 1 was refused 3/3 on exactly this.
# We WAIT rather than override: CC_ADMIT_GATE=off would defeat a protective gate to measure a race.
# CORRECTED 2026-09-19 after 77 minutes of one-minute samples proved this bar unreachable.
# It was 3, reasoned as "a lead plus four members must stay under the ceiling of 8". That is
# NOT the gate's condition. cc_capacity_admit refuses when `active + 1 > 8`, so it ADMITS at
# active <= 7 — and it counts sessions MID-TURN, which probe members stop being seconds after
# they spawn. Measured over the same 77 samples: active<=3 and active<=4 were met 0/77 (0.0%),
# while the gate's own active<=7 held 64/77 (83.1%). The preflight was stricter than the gate
# it existed to satisfy, so it blocked the probe on a self-imposed bar and not on the box —
# the "blocker isn't the standard" failure: when two tools judge one population, adopt the
# standard of the one that actually adjudicates. 6 keeps one slot of margin for the spawn
# burst, during which the four members are briefly mid-turn themselves.
PRE_MAX_ACTIVE="${PROBE_MAX_ACTIVE:-6}"
PRE_MIN_IDLE="${PROBE_MIN_IDLE_PCT:-40}"    # the addendum's bar
PRE_WAIT_S="${PROBE_PREFLIGHT_WAIT_S:-2400}"

cpu_idle() { top -l 2 -n 0 | /usr/bin/grep '^CPU usage' | tail -1 | sed -E 's/.*, ([0-9.]+)% idle.*/\1/'; }
sp_active() { bash -c '. "$HOME/.claude/scripts/lib/spawn-presence.sh" 2>/dev/null && cc_sp_active 2>/dev/null' ; }

log "--- preflight: need active <= $PRE_MAX_ACTIVE AND idle >= ${PRE_MIN_IDLE}% (wait <= ${PRE_WAIT_S}s) ---"
pf_deadline=$(( $(date +%s) + PRE_WAIT_S )); pf_ok=0
while [[ $(date +%s) -lt $pf_deadline ]]; do
  a=$(sp_active); i=$(cpu_idle)
  a=${a:-99}; i=${i:-0}
  log "  preflight: cc_sp_active=$a cpu_idle=$i%"
  if awk -v a="$a" -v i="$i" -v ma="$PRE_MAX_ACTIVE" -v mi="$PRE_MIN_IDLE" \
       'BEGIN{exit !(a<=ma && i>=mi)}'; then pf_ok=1; break; fi
  sleep 60
done
if [[ $pf_ok -ne 1 ]]; then
  log "PREFLIGHT NOT MET within ${PRE_WAIT_S}s — NOT running. A survivors>0 here would license nothing."
  echo "preflight=NOT-MET active=$(sp_active) idle=$(cpu_idle)" > "$CAP/RESULT.txt"
  exit 3
fi
log "preflight MET: cc_sp_active=$(sp_active) cpu_idle=$(cpu_idle)%"

box before

log "--- census BEFORE launch ---"
win_ids > "$CAP/windows.before"
agent_procs > "$CAP/agents.before"
log "windows before: $(wc -l < "$CAP/windows.before" | tr -d ' ')  agent procs before: $(wc -l < "$CAP/agents.before" | tr -d ' ')"

# ---- launch the lead in a NEW kitty OS window that this script creates ----
BRIEF="$HERE/lead-brief-p1.txt"
WRAP="$CAP/lead-wrapper.sh"
cat > "$WRAP" <<EOF
#!/bin/bash
cd "$HERE" || exit 9
# Claude Code gates its iTerm2 pane backend on ITERM_SESSION_ID (~/.zshrc:678-696); the ~/.claude/bin/it2
# shim then translates each backend call into 'kitty @'. A non-interactive shell never reads .zshrc, so
# without this the lead cannot create a named teammate AT ALL. This is the fleet's own synthesis,
# reproduced verbatim — it is NOT a teammateMode change (that is forbidden for this wave).
if [ -n "${KITTY_WINDOW_ID:-}" ] && [ -x "$HOME/.claude/bin/cc-in-kitty" ] && "$HOME/.claude/bin/cc-in-kitty"; then
  export ITERM_SESSION_ID="w0t0p0:$KITTY_WINDOW_ID"
fi
echo \$\$ > "$CAP/lead.shpid"
"$CLAUDE_BIN" --permission-mode auto --model claude-opus-5 "\$(cat '$BRIEF')"
echo "EXIT=\$? at \$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$CAP/lead.exit"
EOF
chmod +x "$WRAP"

LEAD_WIN=$(kitten @ --to "$KL" launch --type=os-window --cwd "$HERE" \
  --env TEAMMATE_SHUTDOWN_DISABLED=1 --env CC_PROBE_P1="$RUN" \
  --env CLAUDE_CONFIG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}" \
  --env PATH="$HOME/.claude/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  --window-title "P1-PROBE-LEAD-$RUN" -- "$WRAP")
rc=$?
if [[ $rc -ne 0 || -z "$LEAD_WIN" ]]; then log "FATAL: launch failed rc=$rc"; exit 1; fi
echo "$LEAD_WIN" > "$CAP/lead.winid"
log "lead kitty window id = $LEAD_WIN (MINE — created by this script)"

# ---- wait for all four idle notifications, read off the LEAD's own pane ----
log "--- waiting for 4 idle notifications (timeout ${IDLE_TIMEOUT_S}s) ---"
deadline=$(( $(date +%s) + IDLE_TIMEOUT_S ))
seen=0
while [[ $(date +%s) -lt $deadline ]]; do
  kitten @ --to "$KL" get-text --match "id:$LEAD_WIN" --extent all > "$CAP/lead-pane.live" 2>/dev/null
  seen=$(/usr/bin/grep -oE 'Teammate @?(probeA|probeB|probeC|probeD)' "$CAP/lead-pane.live" 2>/dev/null \
         | sed -E 's/.*(probe[ABCD])/\1/' | sort -u | wc -l | tr -d ' ')
  # The marker is IN the brief, so the pane ALWAYS shows it once (the prompt echo). The lead
  # PRINTING it is the SECOND occurrence. Run 1 of this probe fired /exit 10 s in because this
  # test read >=1 — a detector that matched its own instruction text.
  allfour=$(/usr/bin/grep -c 'P1-ALL-FOUR-IDLE' "$CAP/lead-pane.live" 2>/dev/null || echo 0)
  members=$(agent_procs | /usr/bin/grep -c 'agent-id probe' || true)
  if [[ "${allfour:-0}" -ge 2 && "${members:-0}" -ge 4 ]]; then
    log "lead PRINTED the marker (occurrence 2) and $members members are live"; break; fi
  log "  ...waiting: marker occurrences=${allfour:-0} (1 = prompt echo only), live members=${members:-0}"
  sleep 10
done
cp "$CAP/lead-pane.live" "$CAP/lead-pane.at-idle.txt" 2>/dev/null

# ---- census AFTER spawn: pin exactly what is mine ----
win_ids > "$CAP/windows.spawned"
agent_procs > "$CAP/agents.spawned"
comm -13 "$CAP/windows.before" "$CAP/windows.spawned" > "$CAP/windows.mine"
# my agent procs = argv names one of my four probe members AND carries all three flags
: > "$CAP/agents.mine"
while IFS= read -r line; do
  pid=${line%% *}
  if [[ "$line" == *"--agent-id probe"* && "$line" == *"--agent-name probe"* && "$line" == *"--team-name session-"* ]]; then
    echo "$line" >> "$CAP/agents.mine"
  fi
done < "$CAP/agents.spawned"
MINE_WINS=$(wc -l < "$CAP/windows.mine" | tr -d ' ')
MINE_PROCS=$(wc -l < "$CAP/agents.mine" | tr -d ' ')
TEAM=$(/usr/bin/grep -oE -- '--team-name session-[a-z0-9]+' "$CAP/agents.mine" | head -1 | awk '{print $2}')
log "PRECONDITION: idle notifications observed = $seen/4 ; lead printed ALL-FOUR = ${allfour:-0}"
log "MINE at spawn: kitty windows = $MINE_WINS (ids: $(tr '\n' ' ' < "$CAP/windows.mine")) ; agent procs = $MINE_PROCS ; team = ${TEAM:-UNKNOWN}"
{ echo "seen_idle=$seen"; echo "all_four_marker=${allfour:-0}"; echo "mine_windows=$MINE_WINS";
  echo "mine_procs=$MINE_PROCS"; echo "team=${TEAM:-UNKNOWN}"; } > "$CAP/precondition.txt"

# ---- the graceful lead exit: /exit typed into the lead's OWN composer ----
log "--- sending /exit to MY lead window $LEAD_WIN at $(ts) ---"
date -u +%Y-%m-%dT%H:%M:%SZ > "$CAP/exit-sent.at"
# A bare LF inserts a newline in the composer; only a CARRIAGE RETURN submits it. Run 1 left
# `/exit` sitting unsent for minutes and the measurement window was meaningless.
kitten @ --to "$KL" send-text --match "id:$LEAD_WIN" '/exit'
printf '\r' | kitten @ --to "$KL" send-text --match "id:$LEAD_WIN" --stdin
sleep 2
kitten @ --to "$KL" get-text --match "id:$LEAD_WIN" --extent all > "$CAP/lead-pane.after-exit.txt" 2>/dev/null

# ---- +30 s settle, then count survivors FROM MY PINNED SET ONLY ----
log "--- settling ${SETTLE_S}s ---"
sleep "$SETTLE_S"
date -u +%Y-%m-%dT%H:%M:%SZ > "$CAP/measured.at"
win_ids > "$CAP/windows.plus30"
agent_procs > "$CAP/agents.plus30"

SURV_WINS=$(comm -12 "$CAP/windows.mine" "$CAP/windows.plus30" | tee "$CAP/windows.survivors" | wc -l | tr -d ' ')
: > "$CAP/agents.survivors"
while IFS= read -r line; do
  pid=${line%% *}
  if /usr/bin/grep -qE "^ *$pid " "$CAP/agents.plus30"; then echo "$line" >> "$CAP/agents.survivors"; fi
done < "$CAP/agents.mine"
SURV_PROCS=$(wc -l < "$CAP/agents.survivors" | tr -d ' ')

box after

{ echo "run=$RUN"; echo "measured_at=$(cat "$CAP/measured.at")";
  echo "idle_observed=$seen/4"; echo "spawned_windows=$MINE_WINS"; echo "spawned_procs=$MINE_PROCS";
  echo "survivor_windows=$SURV_WINS"; echo "survivor_procs=$SURV_PROCS"; } > "$CAP/RESULT.txt"
log "RESULT: survivors at +${SETTLE_S}s — kitty windows=$SURV_WINS  agent procs=$SURV_PROCS"
cat "$CAP/RESULT.txt"
