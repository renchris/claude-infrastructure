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
  # MUST be fixtured, for the same reason as every sensor above and the same lesson a third time:
  # permission-pending joins beacons to panes through the cc-registry, and unfixtured that read is
  # the OPERATOR'S LIVE REGISTRY — the verdict would then depend on which of their sessions are up.
  export CC_REGISTRY_DIR="$D/registry"
  export CC_TEAM_ROOTS="$D/absent-teams"
  export CC_WATCHDOG_DIR="$D/watchdog"; mkdir -p "$CC_WATCHDOG_DIR"
  sg() { # <ts> <pane> <name> <model> <refusal> <recover_cmd> — append a safeguard-blocked row
    jq -nc --arg ts "$1" --arg p "$2" --arg n "$3" --arg m "$4" --arg r "$5" --arg cmd "$6" \
      '{ts:$ts,actor:"cc-reaper",kind:"safeguard-blocked",pane:$p,name:$n,account:"claude-quaternary",blocked_model:$m,refusal:$r,firedBy:"ORIG",recover_cmd:$cmd}' >> "$BOARD"; }
  # ── the account SSOT, fixtured (stale-relogin drop) ──
  # Points at a path that does NOT exist by default, deliberately: every test above has no
  # relogin-blocked row, so the tool never asks — and if that gate ever regressed, this pin makes the
  # regression read as a fail-OPEN here instead of silently shelling out to the operator's real
  # `claude-accounts` (which would put this suite's verdict at the mercy of their live login state).
  export CC_BLOCKERS_ACCOUNTS_BIN="$D/stub-claude-accounts"
  ACCT_MARK="$D/accounts-invoked"
  rb() { # <ts> <acct> <deadline> — append a relogin-blocked row, recover_cmd `cc-relogin <acct>`
    jq -nc --arg ts "$1" --arg a "$2" --arg d "$3" \
      '{ts:$ts,actor:"cc-relogin-poll",kind:"relogin-blocked",acct:$a,account:$a,deadline:$d,
        launcher:"claude",reason:"T-47h to the login deadline",recover_cmd:("cc-relogin " + $a)}' >> "$BOARD"; }
  accts() { # <json> — install a claude-accounts stub emitting $1 on stdout, exit 0
    printf '%s\n' "$1" > "$D/accts.json"
    { printf '#!/usr/bin/env bash\n'; printf 'touch %q\n' "$ACCT_MARK"; printf 'cat %q\n' "$D/accts.json"; } \
      > "$CC_BLOCKERS_ACCOUNTS_BIN"
    chmod +x "$CC_BLOCKERS_ACCOUNTS_BIN"; }
  accts_fail() { # install a stub that errors — the "SSOT unreadable" fail-open premise
    { printf '#!/usr/bin/env bash\n'; printf 'touch %q\n' "$ACCT_MARK"
      printf 'echo "claude-accounts: unavailable" >&2\nexit 1\n'; } > "$CC_BLOCKERS_ACCOUNTS_BIN"
    chmod +x "$CC_BLOCKERS_ACCOUNTS_BIN"; }
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

# ── the RUN-IN-PROGRESS cell ──────────────────────────────────────────────────────────────────────
# A stamp is written only when a run FINISHES, and a run outlives the staleness budget as a matter of
# course (measured on this host: run_s up to 10112s against ALARM_H=3h). So {stale stamp} alone does
# not distinguish "the verifier died" from "the verifier is still working", and the board used to
# resolve that ambiguity the wrong way in BOTH directions at once: it accused a live verifier of
# being inert, and — because the two alarms are mutually exclusive on stamp freshness — it suppressed
# the PERSISTENT-RED row that names the actual fault. Live on 2026-07-29: 34 stamps, 0 green ever,
# deploy halted 53 commits behind trunk, and the one row offered was "STALE, go read launchctl"
# while pid 94251 was three hours into a run. These four tests pin all four cells of
# {fresh,stale} x {running,idle}; the two above own the idle row.

hold_run_lock() { # the verifier's OWN in-progress mark: run.lock.d/pid naming a LIVE process
  mkdir -p "$CC_POSTLAND_DIR/run.lock.d"
  sleep 60 >/dev/null 2>&1 &
  local p=$!
  echo "$p" >> "$D/pids"                                  # teardown() reaps it
  printf '%s\n' "$p" > "$CC_POSTLAND_DIR/run.lock.d/pid"
}

@test "alarm verifier-inert/STALE does NOT fire while a run is IN PROGRESS" {
  mkstamp t1 red 9H                                       # stale by any budget…
  : > "$CC_LAND_LOG"                                      # …and a land newer than it: STALE's shape
  hold_run_lock                                           # …but the verifier is mid-run
  run ccb --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq '[.[] | select(.kind=="verifier-inert")] | length')" = 0 ]
}

@test "alarm trunk-red fires MID-RUN even though the newest stamp is past the budget" {
  # The regression that mattered: this is the shape the live host was in for 53 commits, and the
  # board was silent about the only thing an operator could act on.
  for n in 1 2 3 4 5; do mkstamp "r$n" red 9H; done
  : > "$CC_LAND_LOG"
  hold_run_lock
  run ccb --json
  [ "$(echo "$output" | jq -r '[.[] | select(.kind=="trunk-red")] | .[0].state')" = "PERSISTENT-RED" ]
}

@test "alarms stay MUTUALLY EXCLUSIVE in the stale+running cell (exactly one kind)" {
  for n in 1 2 3 4 5; do mkstamp "r$n" red 9H; done
  : > "$CC_LAND_LOG"
  hold_run_lock
  [ "$(kinds)" = "trunk-red " ]
}

@test "a DEAD lock holder is residue, not a run: STALE still fires" {
  # POSITIVE CONTROL for the sensor. Without this, a verifier_running() that returned true
  # unconditionally would pass every test above while permanently hiding a genuinely dead verifier —
  # the one outcome worse than the misdiagnosis being fixed here.
  mkstamp t1 red 9H
  : > "$CC_LAND_LOG"
  mkdir -p "$CC_POSTLAND_DIR/run.lock.d"
  dead_pid > "$CC_POSTLAND_DIR/run.lock.d/pid"
  run ccb --json
  [ "$(echo "$output" | jq -r '[.[] | select(.kind=="verifier-inert")] | .[0].state')" = "STALE" ]
}

# ── ALARM POLARITY (OPERATOR_SURFACE_V2 §4 M1) ────────────────────────────────────────────────────
# TWO TESTS IN THIS FILE PINNED THE DEFECT AS CORRECT and are CHANGED here, deliberately, with the
# reason recorded (map rule: "a test can encode a falsified premise — changing it is legitimate,
# hiding it is not"; and row 4's "A TEST CAN PIN A DEFECT AS CORRECT"). The old
# never-green/NEVER-CERTIFIED test asserted, in its own comment, that "a non-red verdict in the
# window ⇒ trunk-red must abstain" — which IS the suppression. Reproduced live 2026-07-29: newest
# five red/hung/red/red/red, seen=5, red=4, 4 != 5, row SUPPRESSED, 0 of 33 stamps ever green.
#
# The vocabulary is not what changed. red/cut/hung/green still mean exactly what row 1 says they
# mean. What changed is the polarity of the ALARM built on top of them: for a VERDICT ask "is it
# red?", for an ALARM ask "is it green?" — because a hung run is WORSE than a red one for "is trunk
# persistently failing", yet only the red test silences on it.
#
# never-green is NOT weakened by this; it is returned to being what its own comment always claimed
# (the backstop "emitted ONLY when no sharper row already claimed the reason"). Its remaining
# reachable window is proved below, because shipping a backstop that can no longer fire would be
# the very bug this mechanism repairs.

@test "POLARITY: the live shape (red hung red red red) FIRES as PERSISTENT-NOT-GREEN" {
  # The reproduction, verbatim. Pre-fix this window yielded NO trunk-red row at all.
  mkstamp r1 red 1M; mkstamp h1 hung 2M; mkstamp r2 red 3M; mkstamp r3 red 4M; mkstamp r4 red 5M
  : > "$CC_LAND_LOG"
  run ccb --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq '[.[] | select(.kind=="trunk-red")] | length')" = 1 ]
  [ "$(echo "$output" | jq -r '[.[] | select(.kind=="trunk-red")] | .[0].state')" = "PERSISTENT-NOT-GREEN" ]
  # …and it hands over the platter that names the ACTUAL failures — the row's whole value, and the
  # thing the never-green fallback could not give (it points at runner.log instead).
  echo "$output" | jq -r '.[0].recover_cmd' | grep -q 'failing' || false
  # one row, not two: never-green must DEFER now that a sharper row claimed the reason
  [ "$(echo "$output" | jq '[.[] | select(.kind=="never-green")] | length')" = 0 ]
}

@test "POLARITY: a cut verdict counts too — the state names the mix, never the stronger claim" {
  mkstamp c1 cut 1M; mkstamp r1 red 2M; mkstamp c2 cut 3M
  : > "$CC_LAND_LOG"
  run ccb --json
  [ "$(echo "$output" | jq -r '[.[] | select(.kind=="trunk-red")] | .[0].state')" = "PERSISTENT-NOT-GREEN" ]
  # 1 red of 3 seen ⇒ 2 nonverdicts. The DETAIL must not say "all red".
  echo "$output" | jq -r '.[0].detail' | grep -q '1 red 2 nonverdict' || false
}

@test "POLARITY: an all-red window still reads PERSISTENT-RED (the state split is not a rename)" {
  for n in 1 2 3 4 5; do mkstamp "r$n" red "${n}M"; done
  : > "$CC_LAND_LOG"
  run ccb --json
  [ "$(echo "$output" | jq -r '.[0].state')" = "PERSISTENT-RED" ]
}

@test "POLARITY: one GREEN in the window silences it — the alarm's question, answered yes" {
  # The positive control for the polarity itself. If `notgreen` were miscounted (e.g. counting
  # green as not-green) every test above would still pass while the alarm fired on a HEALTHY
  # pipeline — the invented-blocker failure that is as bad as suppression.
  mkstamp r1 red 1M; mkstamp h1 hung 2M; mkstamp g green 3M; mkstamp r2 red 4M
  : > "$CC_LAND_LOG"
  run ccb --json
  [ "$(echo "$output" | jq '[.[] | select(.kind=="trunk-red")] | length')" = 0 ]
}

@test "POLARITY kill switch: CC_BLOCKERS_ALARM_POLARITY=legacy restores the suppression exactly" {
  mkstamp r1 red 1M; mkstamp h1 hung 2M; mkstamp r2 red 3M; mkstamp r3 red 4M; mkstamp r4 red 5M
  : > "$CC_LAND_LOG"
  CC_BLOCKERS_ALARM_POLARITY=legacy run ccb --json
  [ "$(echo "$output" | jq '[.[] | select(.kind=="trunk-red")] | length')" = 0 ]
  # …and with it off, the backstop takes over again — which is precisely the pre-fix board
  [ "$(echo "$output" | jq -r '[.[] | select(.kind=="never-green")] | .[0].state')" = "NEVER-CERTIFIED" ]
}

@test "POLARITY: an UNPARSEABLE stamp is a sensor failure, not a non-verdict" {
  # Direction matters in BOTH senses. Counted as not-green, one corrupt file fabricates the alarm
  # (R5 fail-open); counted as green, it silences a real one. It must be excluded from the window
  # entirely — so 4 readable reds still fire, and the corrupt file does not change the state.
  for n in 1 2 3 4; do mkstamp "r$n" red "${n}M"; done
  printf 'this is not json\n' > "$CC_POSTLAND_DIR/stamps/broken.json"
  touch -t "$(date -v-1M +%Y%m%d%H%M)" "$CC_POSTLAND_DIR/stamps/broken.json"
  : > "$CC_LAND_LOG"
  run ccb --json
  [ "$(echo "$output" | jq -r '[.[] | select(.kind=="trunk-red")] | .[0].state')" = "PERSISTENT-RED" ]
  echo "$output" | jq -r '.[0].detail' | grep -q 'newest 4 all red' || false
}

@test "POLARITY: a corrupt stamp cannot PAD the window past the n>=2 floor" {
  # The paired negative. One real verdict plus one unreadable file is n=1, not n=2.
  mkstamp solo red 1M
  printf '{"no":"verdict"}\n' > "$CC_POSTLAND_DIR/stamps/broken.json"
  touch -t "$(date -v-2M +%Y%m%d%H%M)" "$CC_POSTLAND_DIR/stamps/broken.json"
  : > "$CC_LAND_LOG"
  run ccb --json
  [ "$(echo "$output" | jq 'length')" = 0 ]
}

@test "DENOMINATOR: the DETAIL reports the LIFETIME history, not the capped window (F3)" {
  # `seen` is capped at REDRUN_N=5, and the board used to print it as if it were the whole history —
  # "5 verdicts, 0 green EVER" against a real 33. The number that sizes the problem must be real.
  for n in 1 2 3 4 5 6 7; do mkstamp "r$n" red "${n}M"; done
  : > "$CC_LAND_LOG"
  run ccb --json
  echo "$output" | jq -r '.[0].detail' | grep -q 'newest 5 all red, 0 green of 7 ever' || false
}

# ── never-green: the BACKSTOP ─────────────────────────────────────────────────────────────────────
# The state that actually halted deploy for 53 commits, and that no other alarm can express: the
# verifier works, returns verdicts, and none has EVER been green. Live shape on 2026-07-29 was
# 30 red + 2 cut + 1 hung + 0 green with `last-green` absent.
#
# Since M1 the SHARPER row (trunk-red) claims that live shape, and this is the true backstop again.
# Its remaining window: verdicts exist, none green ever, and no sharper row applies — e.g. the
# verifier is stamping fresh but NO land has arrived in 24h, so "trunk is persistently failing" is
# not yet a claim anyone can make while "nothing has ever been certified" already is.

@test "alarm never-green/NEVER-CERTIFIED: verdicts exist, none has ever been green" {
  # CHANGED 2026-07-29 by row 10's rebuild, deliberately (see the POLARITY header above). The old
  # fixture asserted trunk-red ABSTAINS on a non-verdict in the window — the suppression itself.
  # Same claim, moved to a window where never-green is genuinely the sharpest row: fresh stamps, but
  # the newest land is >24h old, so lands_24h is 0 and trunk-red has no premise.
  mkstamp r1 red 1M; mkstamp r2 red 2M; mkstamp h1 hung 3M; mkstamp r3 red 4M
  : > "$CC_LAND_LOG"; touch -t "$(date -v-30H +%Y%m%d%H%M)" "$CC_LAND_LOG"
  run ccb --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '[.[] | select(.kind=="never-green")] | .[0].state')" = "NEVER-CERTIFIED" ]
  [ "$(echo "$output" | jq '[.[] | select(.kind=="trunk-red")] | length')" = 0 ]
  # POSITIVE CONTROL on the row's own denominator: 4 readable verdicts, and it says 4.
  echo "$output" | jq -r '[.[] | select(.kind=="never-green")] | .[0].detail' | grep -q '0 green in 4 EVER' || false
}

@test "never-green carries the DEPLOY EXPOSURE — how many commits are inert, not just why (F4)" {
  # "deploy has no cursor" is the cause; the count of landed commits sitting un-deployed behind it
  # is what sizes the exposure, and it was nowhere on the board. Upstream wired locally so @{u}
  # resolves without a network.
  git init -q -b main "$D/dr"
  git -C "$D/dr" config user.email t@t; git -C "$D/dr" config user.name t
  git -C "$D/dr" commit -q --allow-empty -m a; behind="$(git -C "$D/dr" rev-parse HEAD)"
  git -C "$D/dr" commit -q --allow-empty -m b
  git -C "$D/dr" branch up
  git -C "$D/dr" reset -q --hard "$behind"
  git -C "$D/dr" config branch.main.remote .
  git -C "$D/dr" config branch.main.merge refs/heads/up
  [ "$(git -C "$D/dr" rev-list --count 'HEAD..@{u}')" = 1 ]      # harness self-check
  export DEPLOY_REPO="$D/dr"
  mkstamp r1 red 1M; mkstamp h1 hung 2M
  : > "$CC_LAND_LOG"; touch -t "$(date -v-30H +%Y%m%d%H%M)" "$CC_LAND_LOG"
  run ccb --json
  echo "$output" | jq -r '[.[] | select(.kind=="never-green")] | .[0].detail' | grep -q 'live layer 1 behind' || false
}

@test "never-green degrades honestly when the deploy lag is UNREADABLE (no upstream)" {
  # The paired fail-open: no @{u} ⇒ no number invented, and the row still ships with its cause.
  mkstamp r1 red 1M; mkstamp h1 hung 2M
  : > "$CC_LAND_LOG"; touch -t "$(date -v-30H +%Y%m%d%H%M)" "$CC_LAND_LOG"
  run ccb --json
  echo "$output" | jq -r '[.[] | select(.kind=="never-green")] | .[0].detail' | grep -q 'deploy has no cursor' || false
}

@test "alarm never-green is SILENCED by a single green stamp ever having existed" {
  mkstamp r1 red 1M; mkstamp h1 hung 2M; mkstamp g green 30H     # green is OLD — outside 24h
  : > "$CC_LAND_LOG"
  run ccb --json
  [ "$(echo "$output" | jq '[.[] | select(.kind=="never-green")] | length')" = 0 ]
}

@test "alarm never-green is SILENCED by an existing last-green cursor" {
  # The cursor is what deploy actually reads, so its presence means deploy is not cursorless even if
  # the stamp that produced it has since been pruned.
  mkstamp r1 red 1M; mkstamp h1 hung 2M
  : > "$CC_LAND_LOG"
  printf 'deadbeef\n' > "$CC_POSTLAND_DIR/last-green"
  run ccb --json
  [ "$(echo "$output" | jq '[.[] | select(.kind=="never-green")] | length')" = 0 ]
}

@test "alarm never-green DEFERS to a sharper row — never two rows for one fault" {
  for n in 1 2 3 4 5; do mkstamp "r$n" red "${n}M"; done          # all-red ⇒ trunk-red owns it
  : > "$CC_LAND_LOG"
  [ "$(kinds)" = "trunk-red " ]
}

@test "alarm never-green DEFERS to verifier-inert/STALE (a dead verifier is the sharper fault)" {
  mkstamp r1 red 9H; mkstamp h1 hung 10H
  : > "$CC_LAND_LOG"
  [ "$(kinds)" = "verifier-inert " ]
}

@test "alarm never-green has NO premise in a void (no land.log, no deploy repo)" {
  # The phantom-row law: a fixtured $HOME has no greens either. Absence is only an alarm where a
  # pipeline was supposed to certify.
  mkstamp r1 red 1M; mkstamp h1 hung 2M
  rm -f "$CC_LAND_LOG"; export DEPLOY_REPO="$D/absent-repo"
  run ccb --json
  [ "$(echo "$output" | jq 'length')" = 0 ]
}

@test "alarm never-green stays quiet on a single verdict (the n>=2 floor)" {
  mkstamp solo hung 1M
  : > "$CC_LAND_LOG"
  run ccb --json
  [ "$(echo "$output" | jq 'length')" = 0 ]
}

@test "alarm never-green renders in the LAND-PIPELINE table, not only in --json" {
  # A kind missing from LAND_SEL rides the JSON array and VANISHES from the operator's table.
  # CHANGED 2026-07-29 (row 10, §4 M1): fixture moved to never-green's own window — a >24h-old land —
  # because the old one is now correctly claimed by trunk-red. The CLAIM under test is unchanged.
  mkstamp r1 red 1M; mkstamp h1 hung 2M
  : > "$CC_LAND_LOG"; touch -t "$(date -v-30H +%Y%m%d%H%M)" "$CC_LAND_LOG"
  run ccb
  [ "$(echo "$output" | grep -c '^LAND-PIPELINE')" = 1 ]
  echo "$output" | grep -q 'never-green' || false
}

@test "trunk-red PERSISTENT-NOT-GREEN renders in the LAND-PIPELINE table too (new state, same SEL)" {
  # LAND_SEL filters on .kind, so a new STATE cannot fall out of the table — asserted, not assumed,
  # because the mirror bug (a new kind missing from the selector) has bitten this file before.
  mkstamp r1 red 1M; mkstamp h1 hung 2M; mkstamp r2 red 3M
  : > "$CC_LAND_LOG"
  run ccb
  [ "$(echo "$output" | grep -c '^LAND-PIPELINE')" = 1 ]
  echo "$output" | grep -q 'PERSISTENT-NOT-G' || false
}

@test "an unparseable lock pid reads as NOT running (the sensor never guesses alive)" {
  mkstamp t1 red 9H
  : > "$CC_LAND_LOG"
  mkdir -p "$CC_POSTLAND_DIR/run.lock.d"
  printf 'not-a-pid\n' > "$CC_POSTLAND_DIR/run.lock.d/pid"
  run ccb --json
  [ "$(echo "$output" | jq -r '[.[] | select(.kind=="verifier-inert")] | .[0].state')" = "STALE" ]
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
  while read -r p; do [ -n "$p" ] && kill "$p" 2>/dev/null || true; done < "$D/pids"
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

# ══════════════════════════════════════════════════════════════════════════════════════════════════
# M8 · the ALL-CLEAR line must distinguish "nothing to report" from "nothing could be read"
# (OPERATOR_SURFACE_V2 §4 M8 — the frozen DoD's second clause at its last remaining site)
#
# Every sensor family here fails OPEN by design, so a ZERO-ROW board means EITHER "healthy" OR "every
# sensor broken". That is the incident quoted at the top of bin/cc-blockers verbatim: it said "no
# safeguard-blocked sessions surfaced" while a teammate was demonstrably blocked. beacon-inert closed
# that one case; the aggregate line still could not tell the two apart.
# ══════════════════════════════════════════════════════════════════════════════════════════════════

@test "M8: the all-clear line NAMES an unreadable sensor, so silence is not mistaken for evidence" {
  : > "$BOARD"                                        # board readable, nothing on it
  export CC_BLOCKERS_FLEET_BIN="$D/no-such-fleet"     # producer unreadable
  run ccb
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'no safeguard-blocked' || false
  echo "$output" | grep -q 'fleet:x' || false
  echo "$output" | grep -qE 'sensors [0-4]/5 readable' || false
}

@test "M8 POSITIVE CONTROL: with every sensor readable it says 5/5 — the count can reach full" {
  # Without this the roster could be hardwired to under-report and every test above would pass while
  # the line permanently implied a broken board. A count that cannot reach its maximum is not a count.
  : > "$BOARD"
  fleet="$D/fleet-stub"; printf '#!/bin/bash\nexit 0\n' > "$fleet"; chmod +x "$fleet"
  export CC_BLOCKERS_FLEET_BIN="$fleet"
  run ccb
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'sensors 5/5 readable' || false
  ! echo "$output" | grep -q ':x' || false
}

@test "M8: it does NOT editorialize — no alarm language on a fresh host with sensors missing" {
  # The mirror of the defect this whole rebuild is about. The first cut appended "NOT a clean bill of
  # health" on any `x`, which on a fresh host (no board file, cc-fleet not installed) is NORMAL — so
  # it would have cried wolf on every clean install. A count makes the fact available without the
  # board asserting an alarm it cannot justify.
  export CC_BLOCKERS_FLEET_BIN="$D/no-such-fleet"
  run ccb
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -qi 'clean bill of health' || false
  ! echo "$output" | grep -qi 'degraded\|ALARM' || false
}

@test "M8: the roster is printed ONLY on the all-clear path — rows are their own message" {
  for n in 1 2 3 4 5; do mkstamp "r$n" red "${n}M"; done
  : > "$CC_LAND_LOG"
  run ccb
  echo "$output" | grep -q 'trunk-red' || false
  ! echo "$output" | grep -q 'sensors .*readable' || false
}

@test "M8: --json is unchanged by the roster (a machine consumer sees no prose)" {
  : > "$BOARD"
  run ccb --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -c '.')" = '[]' ]
}

# ── PERMISSION-PENDING: the READING half of the beacon ───────────────────────────────────────────
# WHY THESE EXIST: `beacon-inert` only ever asked "is the beacon WIRED", answering with the presence
# of CC_PERMPEND_DIR — which was the ONLY consumption of that path in the whole tool. So the board
# proved its sensor worked and never read what the sensor recorded. Measured 2026-07-31: three live
# beacons, one EIGHTEEN HOURS old, while cc-blockers rendered LAND-PIPELINE and FLEET and not one
# word about a blocked approval. That is the file's own opening incident, re-run with the wiring
# half fixed and the reading half still missing.
pend() { # <sid> <age_seconds> <command> [cwd]
  mkdir -p "$CC_PERMPEND_DIR"
  jq -nc --arg c "$3" --arg w "${4:-/w/wt-abc}" --argjson ts "$(( $(date +%s) - $2 ))" \
    '{ts:$ts,tool_name:"Bash",tool_input:{command:$c},cwd:$w}' > "$CC_PERMPEND_DIR/$1.json"
}
reg() { # <paneUUID> <session_id>
  mkdir -p "$CC_REGISTRY_DIR"
  jq -nc --arg p "$1" --arg s "$2" '{paneUUID:$p,session_id:$s,cwd:"/w",name:"n",account:"a",pid:1}' \
    > "$CC_REGISTRY_DIR/$1.json"
}

@test "a pending beacon is RENDERED — the board no longer stays silent on a blocked approval" {
  pend sess-block 64800 'git push --force origin main'
  run "$C"
  [ "$status" -eq 0 ]
  [[ "$output" == *"permission-pend"* ]] || false
  [[ "$output" == *"git push --force origin main"* ]] || false
  [[ "$output" == *"BLOCKED-18h"* ]] || false      # age is visible, not buried in --json
}

@test "RED CONTROL: with no beacon the board says nothing about a pending permission" {
  mkdir -p "$CC_PERMPEND_DIR"          # dir exists (wired) but empty — the trustworthy all-clear
  run "$C"
  [[ "$output" != *"permission-pend"* ]] || false
}

# The remaining permission-pending assertions share ONE fixture and ONE invocation each. cc-blockers
# runs every sensor on every call (launchctl, ps, jq over the fleet manifest), so a test-per-assertion
# shape cost ~14s and pushed this already-~92s suite past the land gate's smoke budget. Grouping is
# the economy; no assertion was dropped to get it.
@test "addressing: age, pane resolution, unresolved fallback, and the session_id join key" {
  pend sess-old   64800 'x'                                    # 18h
  pend sess-new   120   'y'                                    # 2m
  pend sess-p     60    'rm -rf /tmp/x'
  pend sess-ghost 60    'dd if=/dev/zero'
  reg 706DA5A2-A877-464D-831F-7CD448E364AD sess-p
  reg AAAA1111-0000-0000-0000-000000000000 some-other-session  # matches no beacon
  run "$C" --json
  [ "$status" -eq 0 ]

  # An 18-hour block must not read like a 1-minute one.
  [ "$(echo "$output" | jq -r '.[]|select(.subject=="sess-old").state')" = "BLOCKED-18h" ]
  [ "$(echo "$output" | jq -r '.[]|select(.subject=="sess-new").state')" = "BLOCKED-2m" ]

  # A resolvable session hands over ONE command that focuses its actual pane. The join keys on
  # session_id, NOT on the registry's paneUUID filename — the two identifiers are different, and
  # keying on the filename would silently never match.
  [ "$(echo "$output" | jq -r '.[]|select(.subject=="sess-p").recover_cmd')" \
    = "it2 session focus 706DA5A2-A877-464D-831F-7CD448E364AD" ]

  # An UNRESOLVABLE session is still listed — dropping it rebuilds the silence this row breaks.
  [ "$(echo "$output" | jq -r '[.[]|select(.subject=="sess-ghost")]|length')" = 1 ]
  [[ "$(echo "$output" | jq -r '.[]|select(.subject=="sess-ghost").recover_cmd')" == "jq . "* ]] || false
}

@test "robustness: malformed beacon, the heartbeat dotfile, quoting, and no silent cap" {
  mkdir -p "$CC_PERMPEND_DIR"
  printf 'not json {{{' > "$CC_PERMPEND_DIR/sess-bad.json"     # unreadable ⇒ a row, never a traceback
  : > "$CC_PERMPEND_DIR/.beacon-alive"                         # must never read as a pending prompt
  pend sess-q 60 "$(printf 'git commit -m "a\nb" && echo \x27x\x27')"
  for i in 1 2 3 4 5 6 7; do pend "sess-$i" $((i * 60)) "cmd-$i"; done
  run "$C" --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e . >/dev/null                          # quoting cannot break the JSON
  [ "$(echo "$output" | jq -r '[.[]|select(.subject=="sess-bad")]|length')" = 1 ]
  [ "$(echo "$output" | jq -r '[.[]|select(.kind=="permission-pending")]|length')" = 9 ]
  [ "$(echo "$output" | jq -r '[.[]|select(.subject==".beacon-alive")]|length')" = 0 ]
}

# ── the STALE-RELOGIN drop (2026-08-01) ──────────────────────────────────────────────────────────
# A relogin-blocked row LATCHES: cc-relogin-poll skips healthy accounts before its escalate block
# (bin/cc-relogin-poll:183), so no retraction row is reachable by construction once the operator
# re-logs in. Measured live: a row raised 2026-07-31 for deadline 2026-08-02 was still rendered after
# the account's real deadline moved to 2026-08-28, and the exact command the board printed answered
# `cc-relogin next: REFUSED (2) — no re-auth needed — healthy`. The drop rule is TIMESTAMPS ONLY —
# never a second copy of cc-relogin's need_relogin() — and it fails OPEN on every uncertainty, which
# is what the four fail-open cases below pin. Case 2 is the positive control: without it a filter
# that muted EVERY relogin row would pass case 1 just as well.
#
# EVERY stamp below is seeded RELATIVE to now. An absolute future date silently changes meaning as
# the clock passes it, and the suite would go red on a calendar boundary with no code change (the
# 2026-07-27 fleet-wide gate outage; the wall-clock ratchet blocks the land over exactly this, and
# caught this file on its first land attempt). The drop rule compares the two stamps to EACH OTHER
# and never to now, so only their ORDER is load-bearing: later-than-deadline ⇒ dropped, equal or
# earlier ⇒ kept. Seeding relative keeps that order fixed forever.
#   ts_at   — the board's shape (…:49Z)              ts_acct — claude-accounts' shape (…:10.065000+00:00)
# SIGNED offset is required: bare `date -v 12H` SETS the hour to 12 instead of adding 12h.
ts_at()   { date -u -v"$1" +%Y-%m-%dT%H:%M:%SZ; }
ts_acct() { date -u -v"$1" +%Y-%m-%dT%H:%M:%S.065000+00:00; }

@test "STALE: a relogin row the account's live deadline has moved PAST is dropped" {
  sg "$(ts_at -24H)" "PANE9" "peer-9" "Fable 5" "safeguards flagged this" "cc-recover-safeguard PANE9"
  rb "$(ts_at -12H)" "next" "$(ts_at +47H)"
  accts "{\"rows\":[{\"acct\":\"next\",\"auth\":\"ok\",\"login_expires_h\":654.35,\"login_expires_at\":\"$(ts_acct +654H)\",\"state\":null}]}"
  run "$C" --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq '[.[]|select(.kind=="relogin-blocked")]|length')" = 0 ]
  [ "$(echo "$output" | jq '[.[]|select(.kind=="safeguard-blocked")]|length')" = 1 ]
}

@test "STALE: the RELOGIN-BLOCKED table does not render, and the safeguard table is untouched" {
  sg "$(ts_at -24H)" "PANE9" "peer-9" "Fable 5" "safeguards flagged this" "cc-recover-safeguard PANE9"
  rb "$(ts_at -12H)" "next" "$(ts_at +47H)"
  accts "{\"rows\":[{\"acct\":\"next\",\"auth\":\"ok\",\"login_expires_at\":\"$(ts_acct +654H)\"}]}"
  run "$C"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | grep -c 'RELOGIN-BLOCKED')" -eq 0 ]
  [ "$(echo "$output" | grep -c 'cc-relogin next')" -eq 0 ]
  echo "$output" | grep -q 'peer-9'
  echo "$output" | grep -q 'cc-recover-safeguard PANE9'
}

@test "POSITIVE CONTROL: rows the account has NOT outlived are KEPT — not a blanket mute" {
  # $dl is computed ONCE and reused: the equal-stamps case is the load-bearing boundary (>=, not >),
  # and two separate `date` calls could land a second apart and silently make it the > case instead.
  local dl; dl="$(ts_at +47H)"
  rb "$(ts_at -12H)" "next"  "$dl"   # live == deadline  ⇒ not moved
  rb "$(ts_at -12H)" "next2" "$dl"   # live  < deadline  ⇒ still due, sooner
  accts "{\"rows\":[{\"acct\":\"next\",\"auth\":\"token-invalid\",\"login_expires_at\":\"${dl%Z}.000000+00:00\"},
                  {\"acct\":\"next2\",\"auth\":\"ok\",\"login_expires_at\":\"$(ts_acct +6H)\"}]}"
  run "$C" --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq '[.[]|select(.kind=="relogin-blocked")]|length')" = 2 ]
}

@test "POSITIVE CONTROL: a kept row still renders its table and its EXACT recover command" {
  local dl; dl="$(ts_at +47H)"
  rb "$(ts_at -12H)" "next" "$dl"
  accts "{\"rows\":[{\"acct\":\"next\",\"auth\":\"token-invalid\",\"login_expires_at\":\"${dl%Z}.000000+00:00\"}]}"
  run "$C"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'RELOGIN-BLOCKED'
  echo "$output" | grep -q 'cc-relogin next'
}

@test "FAIL-OPEN: claude-accounts ABSENT ⇒ the row is KEPT" {
  rb "$(ts_at -12H)" "next" "$(ts_at +47H)"     # no stub installed ⇒ the bin is missing
  run "$C" --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq '[.[]|select(.kind=="relogin-blocked")]|length')" = 1 ]
  [ ! -e "$ACCT_MARK" ]
}

@test "FAIL-OPEN: claude-accounts ERRORS ⇒ the row is KEPT" {
  rb "$(ts_at -12H)" "next" "$(ts_at +47H)"
  accts_fail
  run "$C" --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq '[.[]|select(.kind=="relogin-blocked")]|length')" = 1 ]
  [ -e "$ACCT_MARK" ]
}

@test "FAIL-OPEN: unparseable account JSON ⇒ the row is KEPT" {
  rb "$(ts_at -12H)" "next" "$(ts_at +47H)"
  accts 'not json {{{'
  run "$C" --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq '[.[]|select(.kind=="relogin-blocked")]|length')" = 1 ]
}

@test "FAIL-OPEN: no login_expires_at, an unknown account, and an unparseable stamp ⇒ all KEPT" {
  rb "$(ts_at -12H)" "next"  "$(ts_at +47H)"    # row present, field absent
  rb "$(ts_at -12H)" "next2" "$(ts_at +47H)"    # no row for this account at all
  rb "$(ts_at -12H)" "next3" "not-a-timestamp"  # the ROW's own stamp will not parse
  accts "{\"rows\":[{\"acct\":\"next\",\"auth\":\"ok\",\"login_expires_h\":654.35},
                  {\"acct\":\"next3\",\"auth\":\"ok\",\"login_expires_at\":\"$(ts_acct +654H)\"}]}"
  run "$C" --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq '[.[]|select(.kind=="relogin-blocked")]|length')" = 3 ]
}

@test "with NO relogin row the account SSOT is never consulted (the suite cannot read the live one)" {
  sg "2026-07-25T09:05:00Z" "PANE1" "peer-1" "Fable 5" "refusal" "cc-recover-safeguard PANE1"
  accts "{\"rows\":[{\"acct\":\"next\",\"auth\":\"ok\",\"login_expires_at\":\"$(ts_acct +654H)\"}]}"
  run "$C" --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq 'length')" = 1 ]
  [ ! -e "$ACCT_MARK" ]
}
