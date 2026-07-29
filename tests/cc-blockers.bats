#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2329
#   Structurally false under bats, not suppressed noise: every @test body IS its own subshell, so an
#   `export` inside one is *meant* to be test-local (SC2030/SC2031), and setup()'s helpers are invoked
#   from those test subshells rather than from file scope (SC2329). Scoped to these three codes so a
#   genuine finding still surfaces. (.bats is not in the land gate's shell-file set either way —
#   is_shell_file matches *.sh/*.bash or a shell shebang, and this file's is `env bats`.)
# cc-blockers — the operator one-glance view of safeguard-blocked fired peers. Renders the reaper's
# kind=="safeguard-blocked" board rows (latest per pane); read-only; robust to the shared board's mixed
# actors and malformed lines. Hermetic: a temp board file via CC_REAPER_IDL — never the real ~/.claude.
#
# 2026-07-28: the tool gained three LAND-PIPELINE alarms that read DISK, not the board — stamp mtimes,
# land.log's mtime, and the deployed checkout's HEAD. Those sensors default to $HOME/… and the real
# checkout, so every sensor must be fixtured here or this suite reads the operator's live machine and
# its verdict flips with whatever the pipeline happens to be doing. It did exactly that when the
# alarms landed: six tests went red because a real land had just moved land.log past a stale stamp.
# The baseline below is chosen to be deterministically SILENT — a stamps dir that EXISTS (so
# never-activated cannot fire) but is EMPTY, with no land.log and no checkout (so stale, trunk-red
# and deploy-lag all lack their second sensor). Each alarm is then switched ON deliberately, one
# test at a time, below.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  C="$REPO/bin/cc-blockers"
  D="$BATS_TEST_TMPDIR"
  BOARD="$D/idl.jsonl"
  export CC_REAPER_IDL="$BOARD"
  export CC_POSTLAND_DIR="$D/postland"; mkdir -p "$CC_POSTLAND_DIR/stamps"
  export CC_LAND_LOG="$D/absent-land.log"
  export DEPLOY_REPO="$D/absent-repo"
  # ── APPROVAL-reachability sensors (cc-backlog 1e16815bac51) ──
  # Same law as the land-pipeline sensors above, and the same lesson re-learned: these default to
  # $HOME and to the LIVE PROCESS TABLE, so unfixtured they inject phantom rows into every test in
  # this file — measured, 8 went red the moment the alarms landed, on this machine's real orphaned
  # assignees and its genuinely-unwired beacon. Baseline chosen deterministically SILENT: a hook path
  # that does not exist (beacon-inert has no premise) and a team root that does not exist (ps still
  # sees this machine's real agents, but none of them can resolve a config here, so orphaned-approver
  # abstains). Each alarm is then switched ON deliberately, one test at a time, below.
  export CC_BEACON_HOOK="$D/absent-hook.sh"
  export CC_BEACON_CONFIG_DIRS="$D/cfg-void"
  export CC_BEACON_ACTIVATE_SH="$D/activate.sh"
  export CC_PERMPEND_DIR="$D/permpend"
  export CC_TEAM_ROOTS="$D/absent-teams"
  export CC_WATCHDOG_DIR="$D/watchdog"; mkdir -p "$CC_WATCHDOG_DIR"
  sg() { # <ts> <pane> <name> <model> <refusal> <recover_cmd> — append a safeguard-blocked row
    jq -nc --arg ts "$1" --arg p "$2" --arg n "$3" --arg m "$4" --arg r "$5" --arg cmd "$6" \
      '{ts:$ts,actor:"cc-reaper",kind:"safeguard-blocked",pane:$p,name:$n,account:"claude-quaternary",blocked_model:$m,refusal:$r,firedBy:"ORIG",recover_cmd:$cmd}' >> "$BOARD"; }
}

@test "absent board → clean 'none' message, exit 0" {
  run "$C"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi 'no safeguard-blocked'
}

@test "absent board --json → empty array" {
  run "$C" --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -c '.')" = '[]' ]
}

@test "renders a safeguard-blocked row: slug, account, model, refusal, recover command" {
  sg "2026-07-25T09:05:00Z" "725A269A" "wt-pool-2-725A269A" "Fable 5" "safeguards flagged this message" "cc-recover-safeguard 725A269A"
  run "$C"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'wt-pool-2-725A269A'
  echo "$output" | grep -q 'Fable 5'
  echo "$output" | grep -q 'safeguards flagged this message'
  echo "$output" | grep -q 'cc-recover-safeguard 725A269A'
}

@test "dedup: multiple rows for one pane → only the LATEST is shown" {
  sg "2026-07-25T09:05:00Z" "PANE1" "peer-1" "Fable 5" "older refusal" "cc-recover-safeguard PANE1"
  sg "2026-07-25T09:10:00Z" "PANE1" "peer-1" "Fable 5" "NEWER refusal" "cc-recover-safeguard PANE1"
  run "$C" --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq 'length')" = 1 ]
  [ "$(echo "$output" | jq -r '.[0].refusal')" = "NEWER refusal" ]
}

@test "ignores non-safeguard board rows (surface-page / selfcheck)" {
  printf '%s\n' '{"ts":"2026-07-25T09:00:00Z","actor":"cc-reaper","kind":"surface-page","cause":"crashed","name":"x","pane":"P0"}' >> "$BOARD"
  printf '%s\n' '{"ts":"2026-07-25T09:01:00Z","actor":"cc-reaper","kind":"selfcheck-page","live":3,"enumerated":2,"delta":1}' >> "$BOARD"
  run "$C" --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -c '.')" = '[]' ]      # no safeguard rows → empty
  run "$C"
  echo "$output" | grep -qi 'no safeguard-blocked sessions surfaced'
}

@test "robust to a malformed (non-JSON) line in the shared board" {
  printf '%s\n' 'THIS IS NOT JSON at all' >> "$BOARD"
  sg "2026-07-25T09:05:00Z" "PANE2" "peer-2" "Fable 5" "refused" "cc-recover-safeguard PANE2"
  run "$C" --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq 'length')" = 1 ]         # the good row survives; the junk line is skipped
  [ "$(echo "$output" | jq -r '.[0].pane')" = "PANE2" ]
}

@test "two distinct blocked panes → two rows, newest first" {
  sg "2026-07-25T09:05:00Z" "PANE-A" "peer-a" "Fable 5" "ra" "cc-recover-safeguard PANE-A"
  sg "2026-07-25T09:20:00Z" "PANE-B" "peer-b" "Fable 5" "rb" "cc-recover-safeguard PANE-B"
  run "$C" --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq 'length')" = 2 ]
  [ "$(echo "$output" | jq -r '.[0].pane')" = "PANE-B" ]   # newest first
}

@test "unknown arg → exit 2" {
  run "$C" --bogus
  [ "$status" -eq 2 ]
}

# ── LAND-PIPELINE alarms (LAND_PIPELINE_V2 §4.4) ─────────────────────────────────────────────────
# Invoked through /bin/bash EXPLICITLY, not the shebang's PATH bash. The production readers are
# macOS bash 3.2, whose command-substitution parser mis-reads a `case` pattern's `)` as the closing
# paren — a class of bug that `bash -n` and shellcheck both pass and that a homebrew bash 5 on PATH
# would hide. One shipped in this very file and surfaced as a FALSE alarm; these run 3.2 on purpose.
# Every `[[ ]]` carries `|| false`: a non-final `[[ ]]` is errexit-EXEMPT under bats, i.e. dead.
ccb() { /bin/bash "$C" "$@"; }
mkstamp() { # <name> <verdict> <age, signed relative — never a literal date>
  printf '{"tree":"%s","commit":"c%s","verdict":"%s","failing":["tests/x.bats"]}\n' "$1" "$1" "$2" \
    > "$CC_POSTLAND_DIR/stamps/$1.json"
  touch -t "$(date -v-"$3" +%Y%m%d%H%M)" "$CC_POSTLAND_DIR/stamps/$1.json"
}
kinds() { ccb --json | jq -r '.[].kind' | sort | tr '\n' ' '; }

@test "alarms: the fixtured baseline is SILENT (no alarm may fire on an idle, healthy fixture)" {
  run ccb --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq 'length')" = 0 ]
}

@test "alarm NEVER-ACTIVATED stays SILENT in a void (no land.log, no deploy repo)" {
  # THE EVIDENCE GATE (found by v2's own bootstrap land): keyed on stamps-absence alone this
  # alarm fired inside every fixtured-$HOME suite (4 phantom-row failures in
  # tests/cc-relogin-status.bats) and would fire on any machine that never had the infra.
  # Its positive control is the NEVER-ACTIVATED test below — same void plus one land.log.
  export CC_POSTLAND_DIR="$D/never"
  run ccb --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq 'length')" = 0 ]
}

@test "alarm verifier-inert/NEVER-ACTIVATED: no stamps dir has ever existed" {
  export CC_POSTLAND_DIR="$D/never"                       # nothing was ever created here
  : > "$CC_LAND_LOG"    # EVIDENCE GATE: a landing pipeline exists here (a land.log) — without
                        # any evidence a stamps-dir void is a fixture/fresh machine, not an alarm
  run ccb --json
  [ "$(echo "$output" | jq 'length')" = 1 ]
  [ "$(echo "$output" | jq -r '.[0].kind')" = "verifier-inert" ]
  [ "$(echo "$output" | jq -r '.[0].state')" = "NEVER-ACTIVATED" ]
  [[ "$(echo "$output" | jq -r '.[0].recover_cmd')" == *"14-land-pipeline-v2-activate.sh"* ]] || false
}

@test "alarm verifier-inert/STALE: stamping stopped while land.log kept moving" {
  mkstamp t1 red 9H
  : > "$CC_LAND_LOG"                                      # a land, newer than the newest stamp
  run ccb --json
  [ "$(echo "$output" | jq 'length')" = 1 ]
  [ "$(echo "$output" | jq -r '.[0].state')" = "STALE" ]
}

@test "alarm verifier-inert/STALE does NOT fire on an idle box (stale stamp, no newer land)" {
  mkstamp t1 red 9H
  : > "$CC_LAND_LOG"; touch -t "$(date -v-11H +%Y%m%d%H%M)" "$CC_LAND_LOG"   # land OLDER than stamp
  run ccb --json
  [ "$(echo "$output" | jq 'length')" = 0 ]
}

@test "alarm trunk-red/PERSISTENT-RED: fresh stamps, newest N all red, no green in 24h, lands" {
  for n in 1 2 3 4 5; do mkstamp "r$n" red "${n}M"; done
  : > "$CC_LAND_LOG"
  run ccb --json
  [ "$(echo "$output" | jq 'length')" = 1 ]
  [ "$(echo "$output" | jq -r '.[0].kind')" = "trunk-red" ]
  [ "$(echo "$output" | jq -r '.[0].state')" = "PERSISTENT-RED" ]
}

@test "alarm trunk-red: a single red verdict is an ordinary red land, not a persistent state" {
  mkstamp solo red 2M
  : > "$CC_LAND_LOG"
  run ccb --json
  [ "$(echo "$output" | jq 'length')" = 0 ]               # the n>=2 floor
}

@test "alarm trunk-red: one GREEN inside 24h silences it even with reds on top" {
  for n in 1 2 3 4; do mkstamp "r$n" red "${n}M"; done
  mkstamp g green 5M
  : > "$CC_LAND_LOG"
  run ccb --json
  [ "$(echo "$output" | jq 'length')" = 0 ]
}

@test "alarms verifier-inert and trunk-red are MUTUALLY EXCLUSIVE — stale side" {
  # All-red AND land-newer-than-stamp both hold; freshness is what decides. Stale ⇒ STALE only:
  # a dead verifier and a red trunk have opposite fixes, so emitting both would tell the operator
  # to do two contradictory things at once.
  for n in 1 2 3 4 5; do mkstamp "r$n" red 9H; done
  : > "$CC_LAND_LOG"
  [ "$(kinds)" = "verifier-inert " ]
}

@test "alarms verifier-inert and trunk-red are MUTUALLY EXCLUSIVE — fresh side" {
  for n in 1 2 3 4 5; do mkstamp "r$n" red "${n}M"; done   # same shape, stamps now FRESH
  : > "$CC_LAND_LOG"
  [ "$(kinds)" = "trunk-red " ]
}

@test "alarm deploy-lag: a green commit ahead of the deployed HEAD past the budget" {
  git init -q "$D/repo"
  git -C "$D/repo" config user.email t@t; git -C "$D/repo" config user.name t
  printf 'a\n' > "$D/repo/a"; git -C "$D/repo" add a; git -C "$D/repo" commit -qm a
  behind="$(git -C "$D/repo" rev-parse HEAD)"
  printf 'b\n' > "$D/repo/b"; git -C "$D/repo" add b; git -C "$D/repo" commit -qm b
  ahead="$(git -C "$D/repo" rev-parse HEAD)"
  git -C "$D/repo" reset -q --hard "$behind"              # deployed HEAD sits behind the green
  export DEPLOY_REPO="$D/repo"
  printf '{"tree":"x","commit":"%s","verdict":"green"}\n' "$ahead" > "$CC_POSTLAND_DIR/stamps/x.json"
  touch -t "$(date -v-4H +%Y%m%d%H%M)" "$CC_POSTLAND_DIR/stamps/x.json"
  run ccb --json
  [ "$(echo "$output" | jq -r '[.[]|select(.kind=="deploy-lag")]|length')" = 1 ]
  [ "$(echo "$output" | jq -r '[.[]|select(.kind=="deploy-lag")][0].state')" = "LAGGING" ]
  # a green stamp BEHIND the deployed HEAD is history, not lag
  git -C "$D/repo" reset -q --hard "$ahead"
  run ccb --json
  [ "$(echo "$output" | jq -r '[.[]|select(.kind=="deploy-lag")]|length')" = 0 ]
}

@test "alarms fail OPEN: an unreadable/absent sensor yields NO row, never an invented blocker" {
  for n in 1 2 3 4 5; do mkstamp "r$n" red "${n}M"; done   # would be trunk-red…
  export CC_LAND_LOG="$D/nope.log"                         # …but the land sensor is absent
  export DEPLOY_REPO="$D/not-a-checkout"                   # and there is no git to read
  run ccb --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq 'length')" = 0 ]
}

@test "alarms ride in the SAME --json array as board rows (a JSON consumer sees both)" {
  sg "2026-07-25T09:05:00Z" "PANE9" "peer-9" "Fable 5" "refused" "cc-recover-safeguard PANE9"
  export CC_POSTLAND_DIR="$D/never"
  : > "$CC_LAND_LOG"    # evidence gate (see the NEVER-ACTIVATED test)
  run ccb --json
  [ "$(echo "$output" | jq 'length')" = 2 ]
  [ "$(echo "$output" | jq -r '[.[].kind]|sort|join(",")')" = "safeguard-blocked,verifier-inert" ]
}

# ══════════════════════════════════════════════════════════════════════════════════════════════════
# APPROVAL-REACHABILITY alarms (cc-backlog 1e16815bac51)
#
# THE INCIDENT these pin: a lead process died, its five assignees survived, and @gu5-decide parked on
# "Waiting for team lead approval" — an approval routed to a process that cannot answer, with no
# fallback to the operator and no prompt ever rendered. Meanwhile the one mechanism built to see it
# (hooks/cc-permission-beacon.sh) was registered in ZERO settings.json, so `cc-blockers` reported
# all-clear. Both halves are pinned here: the live stuck process, and the blind observer.
#
# These tests spawn REAL processes rather than stubbing ps, because the predicate under test IS a
# process-table fact (relative process AGE) and a stub would let it pass while the real comparison
# was wrong. `sh -c 'sleep N' --agent-id <id>` reproduces an assignee's argv shape faithfully: the
# trailing words land in the shell's own argv exactly as the harness's --agent-id does.
# ══════════════════════════════════════════════════════════════════════════════════════════════════

teardown() {
  [ -f "$D/pids" ] || return 0
  while read -r p; do [ -n "$p" ] && kill "$p" 2>/dev/null; done < "$D/pids"
  return 0
}

spawn_agent() { # <agentId> → pid of a live process whose argv carries --agent-id <agentId>
  # `; :` IS LOAD-BEARING — do not "simplify" it away. With a single simple command, sh EXECs it
  # instead of forking, so the process becomes a bare `sleep 60` and the --agent-id words vanish from
  # argv entirely. The fixture then spawns nothing the detector can see and every positive test fails
  # while the detector is fine. Caught exactly that way; the compound command defeats the exec.
  # >/dev/null IS ALSO LOAD-BEARING: this helper is called as `lead=$(spawn_agent ...)`, and a
  # background job that inherits the command substitution's stdout holds that pipe OPEN — `$( )`
  # then blocks for the full 60s instead of returning the pid. Redirecting releases it immediately.
  /bin/sh -c 'sleep 60; :' --agent-id "$1" >/dev/null 2>&1 &
  local p=$!
  echo "$p" >> "$D/pids"
  printf '%s' "$p"
}

team_cfg() { # <team> <leadSessionId> — the only field the alarm reads from team state
  mkdir -p "$CC_TEAM_ROOTS/$1"
  jq -nc --arg s "$2" '{leadSessionId:$s}' > "$CC_TEAM_ROOTS/$1/config.json"
}

dead_pid() { # a pid that is provably NOT running (spawned, reaped, then waited on)
  /bin/sh -c 'exit 0' & local p=$!; wait "$p" 2>/dev/null; printf '%s' "$p"
}

orphan_rows() { echo "$output" | jq '[.[] | select(.kind=="orphaned-approver")]'; }
beacon_rows() { echo "$output" | jq '[.[] | select(.kind=="beacon-inert")]'; }

# ── orphaned-approver ────────────────────────────────────────────────────────────────────────────

@test "orphaned-approver LEAD-DEAD: a live assignee whose lead process is gone" {
  spawn_agent "gu5-decide@session-T1" >/dev/null
  spawn_agent "gu5-cadence@session-T1" >/dev/null
  team_cfg session-T1 lead-sid-1
  dead_pid > "$CC_WATCHDOG_DIR/lead-sid-1.pid"
  run ccb --json
  [ "$status" -eq 0 ]
  [ "$(orphan_rows | jq 'length')" = 1 ]
  [ "$(orphan_rows | jq -r '.[0].state')" = "LEAD-DEAD" ]
  [ "$(orphan_rows | jq -r '.[0].orphans | split(",") | sort | join(",")')" = "gu5-cadence,gu5-decide" ]
  [ "$(orphan_rows | jq -r '.[0].lead_session')" = "lead-sid-1" ]
}

@test "orphaned-approver LEAD-DEAD also when the lead pidfile never existed at all" {
  spawn_agent "a1@session-T2" >/dev/null
  team_cfg session-T2 lead-sid-2          # no $CC_WATCHDOG_DIR/lead-sid-2.pid written
  run ccb --json
  [ "$(orphan_rows | jq 'length')" = 1 ]
  [ "$(orphan_rows | jq -r '.[0].state')" = "LEAD-DEAD" ]
}

@test "orphaned-approver LEAD-RESTARTED: lead pid ALIVE but assignees OLDER than it" {
  # THE REGRESSION THIS EXISTS FOR. The motivating incident had a LIVE lead pid (the pane had already
  # been resumed), so "is the lead alive" answers YES and false-negatives the whole thing. A resume
  # restores the session, never the team channel: the assignees are bound to the process that died.
  spawn_agent "gu5-decide@session-T3" >/dev/null   # assignee first...
  sleep 3                                          # ...so it is measurably OLDER than the "lead"
  local lead; lead=$(spawn_agent "team-lead@session-T3")
  echo "$lead" > "$CC_WATCHDOG_DIR/lead-sid-3.pid"
  team_cfg session-T3 lead-sid-3
  export CC_ORPHAN_GRACE_S=0                       # grace absorbs ps's 1s granularity, not the 3s gap
  run ccb --json
  [ "$(orphan_rows | jq 'length')" = 1 ]
  [ "$(orphan_rows | jq -r '.[0].state')" = "LEAD-RESTARTED" ]
  [ "$(orphan_rows | jq -r '.[0].orphans')" = "gu5-decide" ]
}

@test "orphaned-approver is SILENT on a healthy team (assignee spawned BY a live lead is younger)" {
  local lead; lead=$(spawn_agent "team-lead@session-T4")   # lead first, as a real lead does
  sleep 2
  spawn_agent "worker@session-T4" >/dev/null               # then its assignee
  echo "$lead" > "$CC_WATCHDOG_DIR/lead-sid-4.pid"
  team_cfg session-T4 lead-sid-4
  export CC_ORPHAN_GRACE_S=0
  run ccb --json
  [ "$(orphan_rows | jq 'length')" = 0 ]
}

@test "orphaned-approver EXISTENCE EVIDENCE: a dead lead with NO live assignee raises nothing" {
  team_cfg session-T5 lead-sid-5
  dead_pid > "$CC_WATCHDOG_DIR/lead-sid-5.pid"
  run ccb --json                              # team state exists, lead is dead, but nobody is waiting
  [ "$(orphan_rows | jq 'length')" = 0 ]
}

@test "orphaned-approver abstains when a live agent has no resolvable team config" {
  spawn_agent "stray@session-T6" >/dev/null   # live, but $CC_TEAM_ROOTS/session-T6 does not exist
  run ccb --json
  [ "$(orphan_rows | jq 'length')" = 0 ]
}

@test "orphaned-approver never counts the lead's own sentinel as an orphan" {
  spawn_agent "team-lead@session-T7" >/dev/null    # the ONLY live agent for this team
  team_cfg session-T7 lead-sid-7
  dead_pid > "$CC_WATCHDOG_DIR/lead-sid-7.pid"
  run ccb --json
  [ "$(orphan_rows | jq 'length')" = 0 ]
}

@test "orphaned-approver matches the team suffix EXACTLY (no prefix bleed between teams)" {
  spawn_agent "w1@session-T8X" >/dev/null     # session-T8X must not satisfy team session-T8
  team_cfg session-T8 lead-sid-8
  dead_pid > "$CC_WATCHDOG_DIR/lead-sid-8.pid"
  run ccb --json
  [ "$(orphan_rows | jq 'length')" = 0 ]
}

@test "orphaned-approver hands over a runnable INVENTORY command naming the team" {
  spawn_agent "a@session-T9" >/dev/null
  team_cfg session-T9 lead-sid-9
  dead_pid > "$CC_WATCHDOG_DIR/lead-sid-9.pid"
  run ccb --json
  echo "$(orphan_rows | jq -r '.[0].recover_cmd')" | grep -q '@session-T9'
  # and the table renders it verbatim — a paraphrased command is not a silver platter
  run ccb
  echo "$output" | grep -q 'APPROVAL'
  echo "$output" | grep -q "ps -axo pid=,tty=,command="
}

# ── beacon-inert ─────────────────────────────────────────────────────────────────────────────────

wire_cfg() { # <dir> <wired:0|1> — a settings.json that does or does not register the beacon
  mkdir -p "$1"
  if [ "$2" = 1 ]; then
    jq -nc '{hooks:{PermissionRequest:[{matcher:"",hooks:[{type:"command",command:"~/.claude/hooks/cc-permission-beacon.sh write"}]}]}}' > "$1/settings.json"
  else
    jq -nc '{hooks:{PostToolUse:[{matcher:"",hooks:[{type:"command",command:"~/.claude/hooks/other.sh"}]}]}}' > "$1/settings.json"
  fi
}

@test "beacon-inert NOT-WIRED: the hook is deployed but registered in no settings.json" {
  : > "$CC_BEACON_HOOK"                       # deployed ⇒ the premise holds
  wire_cfg "$D/cfg-void" 0
  run ccb --json
  [ "$status" -eq 0 ]
  [ "$(beacon_rows | jq 'length')" = 1 ]
  [ "$(beacon_rows | jq -r '.[0].state')" = "NOT-WIRED" ]
  [ "$(beacon_rows | jq -r '.[0].recover_cmd')" = "CONFIRM=1 bash $CC_BEACON_ACTIVATE_SH" ]
}

@test "beacon-inert NOT-WIRED is TERMINAL — it never also emits NEVER-FIRED" {
  : > "$CC_BEACON_HOOK"
  wire_cfg "$D/cfg-void" 0                    # unwired AND no beacon dir: both conditions true
  run ccb --json
  [ "$(beacon_rows | jq 'length')" = 1 ]      # exactly one row, not two
}

@test "beacon-inert NEVER-FIRED: wired, yet the beacon dir has never existed" {
  : > "$CC_BEACON_HOOK"
  wire_cfg "$D/cfg-void" 1
  run ccb --json
  [ "$(beacon_rows | jq 'length')" = 1 ]
  [ "$(beacon_rows | jq -r '.[0].state')" = "NEVER-FIRED" ]
}

@test "beacon-inert SILENT once the heartbeat dir exists — the positive control that closes the gap" {
  # The whole point: an EMPTY beacon dir must read as 'nothing pending', NOT as 'never ran'. Before
  # the heartbeat, absence was the only observation available and the two were indistinguishable.
  : > "$CC_BEACON_HOOK"
  wire_cfg "$D/cfg-void" 1
  mkdir -p "$CC_PERMPEND_DIR"                 # dir exists, EMPTY — no pending prompt
  run ccb --json
  [ "$(beacon_rows | jq 'length')" = 0 ]
}

@test "beacon-inert has NO premise where the hook is not deployed (a host that never had it)" {
  wire_cfg "$D/cfg-void" 0                    # settings exist, but $CC_BEACON_HOOK does not
  run ccb --json
  [ "$(beacon_rows | jq 'length')" = 0 ]
}

@test "beacon-inert has NO premise in a settings-less void (the phantom-row law)" {
  : > "$CC_BEACON_HOOK"                       # hook deployed, but no settings.json anywhere
  run ccb --json
  [ "$(beacon_rows | jq 'length')" = 0 ]
}

@test "beacon-inert is wired-if-ANY dir registers it (one armed account is armed)" {
  : > "$CC_BEACON_HOOK"
  wire_cfg "$D/c1" 0; wire_cfg "$D/c2" 1
  export CC_BEACON_CONFIG_DIRS="$D/c1 $D/c2"
  mkdir -p "$CC_PERMPEND_DIR"
  run ccb --json
  [ "$(beacon_rows | jq 'length')" = 0 ]
}

@test "both APPROVAL kinds ride the same --json array and render under one heading" {
  : > "$CC_BEACON_HOOK"; wire_cfg "$D/cfg-void" 0
  spawn_agent "a@session-TA" >/dev/null
  team_cfg session-TA lead-sid-a
  dead_pid > "$CC_WATCHDOG_DIR/lead-sid-a.pid"
  run ccb --json
  [ "$(echo "$output" | jq -r '[.[].kind]|sort|unique|join(",")')" = "beacon-inert,orphaned-approver" ]
  run ccb
  [ "$(echo "$output" | grep -c '^APPROVAL')" = 1 ]
}
