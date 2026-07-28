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
