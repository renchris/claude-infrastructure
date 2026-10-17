#!/usr/bin/env bats
# 52-load-2026-10-17-activate.sh — the operator's switches for the load-root-cause program (DESIGN WP-16),
# plus the two plists and the manifest row it activates.
#
# WHY THIS SUITE EXISTS: every behaviour the program ships is inert until one of these switches is
# flipped, so the script's value is in what it REFUSES: a bare run that writes nothing, a confirm that
# writes only its own file, a refusal when the evidence is absent, and one file (OP-5's promoted list)
# that no invocation may ever create. Each case reads the scratch HOME back from disk.
#
# HERMETIC: HOME is $BATS_TEST_TMPDIR/home; launchctl is a stub (CC_ACT52_LAUNCHCTL) whose "daemon"
# writes attrib-latest.json on bootstrap; the repo is a scratch copy holding the staged plist and a fake
# ms365 migration that would leave a trace if anything ran it. Nothing reads stdin.
#
# Seams for the RED proof: ACT52_SCRIPT, ACT52_MANIFEST, ACT52_ATTRIB_PLIST, ACT52_GC_PLIST.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SCRIPT="${ACT52_SCRIPT:-$REPO/docs/activation/pending-activation/52-load-2026-10-17-activate.sh}"
  MANIFEST="${ACT52_MANIFEST:-$REPO/launchd/fleet.manifest}"
  ATTRIB_PLIST="${ACT52_ATTRIB_PLIST:-$REPO/launchd/staged/com.claude.capacity-attrib.plist}"
  GC_PLIST="${ACT52_GC_PLIST:-$REPO/launchd/com.claude.worktree-gc-infra.plist}"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude/logs" "$HOME/.claude/autonomy"
  STUB="$BATS_TEST_TMPDIR/stub"; mkdir -p "$STUB"
  FAKE="$BATS_TEST_TMPDIR/repo"; mkdir -p "$FAKE/launchd/staged" "$FAKE/migrations"
  [ -f "$ATTRIB_PLIST" ] && cp "$ATTRIB_PLIST" "$FAKE/launchd/staged/"
  printf '%s\n' '#!/bin/bash' \
    '# migration-run: bash ~/Development/claude-infrastructure/migrations/0067-ms365-shared.sh --confirm ms365-shared' \
    "touch '$STUB/ms365-ran'" > "$FAKE/migrations/0067-ms365-shared.sh"
  chmod +x "$FAKE/migrations/0067-ms365-shared.sh"
  write_stub
  export CC_ACT52_LAUNCHCTL="$STUB/launchctl" CC_ACT52_REPO="$FAKE" CC_ACT52_WAIT_S=2
  AUTO="$HOME/.claude/autonomy"; LOGS="$HOME/.claude/logs"
  LA="$HOME/Library/LaunchAgents/com.claude.capacity-attrib.plist"
}

# The launchctl stub. State lives in $STUB, outside HOME, so a snapshot of HOME sees only the script's
# writes and the "daemon's" heartbeat. STUB_HB_PID overrides the pid the heartbeat names.
write_stub() {
  cat > "$STUB/launchctl" <<STUBEOF
#!/bin/bash
echo "\$*" >> "$STUB/calls"
case "\$1" in
  print)
    # A loaded job is a LIVE daemon: it rewrites its heartbeat every 5 s, which a loaded box can stretch
    # past any fixed wait, so the stub refreshes it whenever launchd is asked about the job.
    [ -f "$STUB/loaded" ] || exit 113
    # \$STUB/det, when present, is the daemon's detector-counter object (leg 3); live() writes it.
    det="\$(cat "$STUB/det" 2>/dev/null)"
    printf '{"v": 1, "pid": %s, "start": "1.000000"%s}\n' "\${STUB_HB_PID:-4242}" "\${det:+, \"detectors\": \$det}" \
      > "$HOME/.claude/logs/attrib-latest.json"
    printf '\tstate = running\n\tpid = 4242\n' ;;
  print-disabled) cat "$STUB/disabled" 2>/dev/null; exit 0 ;;
  enable) exit 0 ;;
  bootstrap) touch "$STUB/loaded" ;;
  *) exit 0 ;;
esac
STUBEOF
  chmod +x "$STUB/launchctl"
}

files() { (cd "$HOME" && find . -type f -print | LC_ALL=C sort); }
snap() { (cd "$HOME" && find . -print | LC_ALL=C sort; find . -type f -exec cksum {} + | LC_ALL=C sort); }
new_files() { LC_ALL=C comm -13 "$1" <(files); }
iso_ago() { date -u -r $(( $(date +%s) - $1 )) +%Y-%m-%dT%H:%M:%SZ; }

seed_observe() {
  # The wake log's real shape (scripts/worktree-gc-wake.sh): one row per path, plus summary rows.
  printf '%s\n' "2026-10-10T04:15:00Z mode=observe repo=a decision=would_park path=/w/1 reason=arm-i" \
    "2026-10-11T04:15:00Z mode=observe repo=a decision=would_park path=/w/2 reason=arm-i" \
    "2026-10-11T04:15:01Z verdict=ok due=2 evaluated=2 dequeued=2 requeued=0 mode=observe" \
    "2026-10-12T04:15:00Z mode=observe repo=a decision=would_keep path=/w/3 reason=dirty" > "$LOGS/worktree-gc-wake.log"
  # The foreign log's real shape (worktree-gc-infra-run.sh post_sweep): one row per repo carrying
  # COUNTS, reasons indented under it. A quiet night's would_park=0 must add nothing.
  printf '%s\n' "2026-10-13 04:20:00  repo=b mode=observe trunk=origin/main rc=0 would_park=0 would_detach=1 would_keep=4 would_lock=0" \
    "    would park    /w/b1 [x] — arm-ii" \
    "2026-10-14 04:20:00  repo=b mode=observe trunk=origin/main rc=0 would_park=0 would_detach=0 would_keep=5 would_lock=0" \
    > "$LOGS/worktree-gc-foreign.log"
}
seed_d2() {   # <age of first row in s> — information only; the gate never reads these rows
  printf '{"det":"D2","event":"raise","mode":"record-only","ts":"%s"}\n' "$(iso_ago "$1")" > "$LOGS/capacity-detect.jsonl"
  printf '{"det":"D2","event":"clear","mode":"record-only","ts":"%s"}\n' "$(iso_ago 3600)" >> "$LOGS/capacity-detect.jsonl"
  printf '{"det":"D3","event":"raise","mode":"record-only","ts":"%s"}\n' "$(iso_ago 900000)" >> "$LOGS/capacity-detect.jsonl"
}
# D2 gate leg 1: a deployed sampler that calls the detectors, and a scratch trunk whose commit wired
# them <age in s> ago (default ~9 d). The repo is a throwaway under $BATS_TEST_TMPDIR.
wire_d2() {
  local d="@$(( $(date +%s) - ${1:-800000} )) +0000"
  mkdir -p "$HOME/.claude/scripts/lib" "$FAKE/scripts/lib"
  echo 'from capacity_detect import Detectors' > "$HOME/.claude/scripts/lib/capacity-attrib.py"
  echo '# runs capacity-detect on every tick' > "$FAKE/scripts/lib/capacity-attrib.py"
  [ -d "$FAKE/.git" ] || git -C "$FAKE" init -q
  git -C "$FAKE" add scripts/lib/capacity-attrib.py
  GIT_AUTHOR_DATE="$d" GIT_COMMITTER_DATE="$d" git -C "$FAKE" -c user.name=t -c user.email=t@t commit -qm wire
  git -C "$FAKE" update-ref refs/remotes/origin/main HEAD
}
# D2 gate leg 2a: the sampler plist installed (identical to the repo's, so a confirm leaves it) 8 d ago.
old_plist() {
  mkdir -p "$(dirname "$LA")"; cp "$FAKE/launchd/staged/com.claude.capacity-attrib.plist" "$LA"
  touch -t "$(date -r $(( $(date +%s) - 700000 )) +%Y%m%d%H%M.%S)" "$LA"
}
# D2 gate leg 2b: launchd runs pid 4242 and the heartbeat, fresh, names it.
# Leg 3: the daemon's detector counters. Default: first evaluated tick 700000 s ago (8.1 d) at 5 s,
# every tick present. live <since_age_s> <ticks> overrides either.
live() {
  local age="${1:-700000}" ticks="${2:-140000}"
  touch "$STUB/loaded"
  printf '{"live": true, "since": %s, "ticks": %s, "interval": 5.0, "err": null}' \
    "$(( $(date +%s) - age ))" "$ticks" > "$STUB/det"
  printf '{"v": 1, "pid": 4242, "detectors": %s}\n' "$(cat "$STUB/det")" > "$LOGS/attrib-latest.json"
}

@test "a bare run reports every step and writes nothing" {
  seed_observe; seed_d2 900000
  snap > "$BATS_TEST_TMPDIR/before"
  run bash "$SCRIPT" </dev/null
  [ "$status" -eq 0 ]
  snap > "$BATS_TEST_TMPDIR/after"
  diff "$BATS_TEST_TMPDIR/before" "$BATS_TEST_TMPDIR/after"
  [[ "$output" == *"report only — nothing written"* ]]
  [[ "$output" == *"would_park 2"* ]]
  [ ! -e "$STUB/loaded" ]
  if grep -q bootstrap "$STUB/calls" 2>/dev/null; then echo "a bare run bootstrapped"; return 1; fi
}

@test "--confirm capacity-attrib installs, bootstraps and verifies, writing only the plist (and the daemon its heartbeat)" {
  files > "$BATS_TEST_TMPDIR/before"
  run bash "$SCRIPT" --confirm capacity-attrib </dev/null
  [ "$status" -eq 0 ]
  [[ "$output" == *"VERIFIED: running, pid 4242"* ]]
  [[ "$output" == *"staged -> run"* ]]
  cmp -s "$FAKE/launchd/staged/com.claude.capacity-attrib.plist" "$LA"
  [ "$(new_files "$BATS_TEST_TMPDIR/before")" = "$(printf '%s\n' ./.claude/logs/attrib-latest.json ./Library/LaunchAgents/com.claude.capacity-attrib.plist)" ]
}

@test "--confirm capacity-attrib clears a domain-level disabled bit before bootstrapping" {
  printf '\t"com.claude.capacity-attrib" => disabled\n' > "$STUB/disabled"
  run bash "$SCRIPT" --confirm capacity-attrib </dev/null
  [ "$status" -eq 0 ]
  grep -q '^enable gui/[0-9]*/com.claude.capacity-attrib$' "$STUB/calls"
  [ "$(grep -n '^enable' "$STUB/calls" | cut -d: -f1)" -lt "$(grep -n '^bootstrap' "$STUB/calls" | cut -d: -f1)" ]
}

@test "--confirm capacity-attrib fails closed when the heartbeat names another pid" {
  STUB_HB_PID=999 run bash "$SCRIPT" --confirm capacity-attrib </dev/null
  [ "$status" -eq 1 ]
  [[ "$output" == *"names pid '999', launchd runs 4242"* ]]
  [[ "$output" != *"staged -> run"* ]]
}

@test "--confirm worktree-gc-events is refused with no observe log, and writes no mode file" {
  files > "$BATS_TEST_TMPDIR/before"
  run bash "$SCRIPT" --confirm worktree-gc-events </dev/null
  [ "$status" -eq 1 ]
  [[ "$output" == *"neither observe log has a row"* ]]
  [ -z "$(new_files "$BATS_TEST_TMPDIR/before")" ]
}

@test "--confirm worktree-gc-events prints the evidence, then writes only the mode file, reading 'act'" {
  seed_observe
  files > "$BATS_TEST_TMPDIR/before"
  run bash "$SCRIPT" --confirm worktree-gc-events </dev/null
  [ "$status" -eq 0 ]
  [[ "$output" == *"worktree-gc-wake.log: 3 row(s) · would_park 2 · would_detach 0 · would_lock 0 · would_keep 1"* ]]
  [[ "$output" == *"first row 2026-10-10 · last row 2026-10-12"* ]]
  # summed, not row-counted: two rows that both say would_park=0 are zero parks
  [[ "$output" == *"worktree-gc-foreign.log: 2 row(s) · would_park 0 · would_detach 1 · would_lock 0 · would_keep 9"* ]]
  [[ "$output" == *"first row 2026-10-13 · last row 2026-10-14"* ]]
  [ "$(new_files "$BATS_TEST_TMPDIR/before")" = ./.claude/autonomy/worktree-gc-events.mode ]
  [ "$(cat "$AUTO/worktree-gc-events.mode")" = act ]
}

@test "--confirm capacity-alarm-load-rung is refused while the deployed sampler does not call the detectors, whatever D2's rows say" {
  seed_d2 900000; old_plist; live
  mkdir -p "$HOME/.claude/scripts/lib"; echo 'def daemon(): pass' > "$HOME/.claude/scripts/lib/capacity-attrib.py"
  run bash "$SCRIPT" --confirm capacity-alarm-load-rung </dev/null
  [ "$status" -eq 1 ]
  [[ "$output" == *"D2 is not running live; capacity-attrib does not call the detectors"* ]]
  [[ "$output" == *"D2 rows (information only): 2, 1 raise(s)"* ]]
  [ ! -e "$AUTO/capacity-alarm-load-rung.mode" ]
}

@test "--confirm capacity-alarm-load-rung is refused when the deployed file calls the detectors but trunk has no wiring commit" {
  old_plist; live
  mkdir -p "$HOME/.claude/scripts/lib"; echo 'from capacity_detect import Detectors' > "$HOME/.claude/scripts/lib/capacity-attrib.py"
  run bash "$SCRIPT" --confirm capacity-alarm-load-rung </dev/null
  [ "$status" -eq 1 ]
  [[ "$output" == *"D2 is not running live; capacity-attrib does not call the detectors"* ]]
}

@test "--confirm capacity-alarm-load-rung: the 7 d clock starts at the LATER of the install and the wiring commit" {
  wire_d2 86400; old_plist; live
  run bash "$SCRIPT" --confirm capacity-alarm-load-rung </dev/null
  [ "$status" -eq 1 ]; [[ "$output" == *"D2 has run live for 1 d"*"7 d are required"* ]]
  [ ! -e "$AUTO/capacity-alarm-load-rung.mode" ]
}

@test "--confirm capacity-alarm-load-rung is refused when the sampler was installed under 7 d ago, or is not live" {
  wire_d2; live
  mkdir -p "$(dirname "$LA")"; cp "$FAKE/launchd/staged/com.claude.capacity-attrib.plist" "$LA"
  run bash "$SCRIPT" --confirm capacity-alarm-load-rung </dev/null
  [ "$status" -eq 1 ]; [[ "$output" == *"D2 has run live for 0 d"* ]]
  old_plist; rm "$STUB/loaded"
  run bash "$SCRIPT" --confirm capacity-alarm-load-rung </dev/null
  [ "$status" -eq 1 ]; [[ "$output" == *"sampler is not live now"* ]]
  [ ! -e "$AUTO/capacity-alarm-load-rung.mode" ]
}

@test "--confirm capacity-alarm-load-rung is refused when the detectors did not run continuously, however old the install" {
  wire_d2; old_plist
  live 700000 70000            # 8.1 d since the first evaluated tick, but ticks cover only 50% of it
  run bash "$SCRIPT" --confirm capacity-alarm-load-rung </dev/null
  [ "$status" -eq 1 ]
  [[ "$output" == *"have not run continuously for 7 d"* ]]
  [ ! -e "$AUTO/capacity-alarm-load-rung.mode" ]
  live 300000 60000            # every tick present, but only 3.5 d of them
  run bash "$SCRIPT" --confirm capacity-alarm-load-rung </dev/null
  [ "$status" -eq 1 ]
  [ ! -e "$AUTO/capacity-alarm-load-rung.mode" ]
  : > "$STUB/det"                                                   # a pre-wiring daemon: no counters
  printf '{"v": 1, "pid": 4242}\n' > "$LOGS/attrib-latest.json"
  run bash "$SCRIPT" --confirm capacity-alarm-load-rung </dev/null
  [ "$status" -eq 1 ]
  [[ "$output" == *"no counters"* ]]
  [ ! -e "$AUTO/capacity-alarm-load-rung.mode" ]
}

@test "--confirm capacity-alarm-load-rung with both legs holding writes only its mode file, with no D2 rows at all" {
  wire_d2; old_plist; live
  files > "$BATS_TEST_TMPDIR/before"
  run bash "$SCRIPT" --confirm capacity-alarm-load-rung </dev/null
  [ "$status" -eq 0 ]
  [ "$(new_files "$BATS_TEST_TMPDIR/before")" = ./.claude/autonomy/capacity-alarm-load-rung.mode ]
  [ "$(cat "$AUTO/capacity-alarm-load-rung.mode")" = record-only ]
}

@test "--archive-floor-gb refuses anything but a whole positive number, before writing anything" {
  seed_observe
  for bad in abc 0 07 -5 1.5 ''; do
    snap > "$BATS_TEST_TMPDIR/before"
    run bash "$SCRIPT" --confirm worktree-gc-events --archive-floor-gb "$bad" </dev/null
    [ "$status" -eq 2 ] || { echo "accepted '$bad'"; return 1; }
    snap | diff "$BATS_TEST_TMPDIR/before" -
  done
  run bash "$SCRIPT" --archive-floor-gb 50 </dev/null
  [ "$status" -eq 0 ]
  [ "$(cat "$AUTO/worktree-gc-archive-floor.gb")" = 50 ]
  [ ! -e "$AUTO/worktree-gc-events.mode" ]
}

@test "an unknown --confirm target is refused before anything is written" {
  snap > "$BATS_TEST_TMPDIR/before"
  run bash "$SCRIPT" --confirm worktree-gc-repos-promoted </dev/null
  [ "$status" -eq 2 ]
  snap | diff "$BATS_TEST_TMPDIR/before" -
}

@test "no invocation creates the OP-5 promoted file or runs the ms365 migration; all three switches mark .done" {
  seed_observe; seed_d2 700000; wire_d2; old_plist
  # the daemon this run bootstraps reports 8.1 d of continuous detector ticks (leg 3)
  printf '{"live": true, "since": %s, "ticks": 140000, "interval": 5.0, "err": null}' \
    "$(( $(date +%s) - 700000 ))" > "$STUB/det"
  for args in "" "--confirm capacity-attrib" "--confirm worktree-gc-events" "--archive-floor-gb 40" \
              "--confirm capacity-attrib --confirm worktree-gc-events --confirm capacity-alarm-load-rung --archive-floor-gb 40"; do
    # shellcheck disable=SC2086
    run bash "$SCRIPT" $args </dev/null
    [ "$status" -eq 0 ] || { echo "args '$args' → $status: $output"; return 1; }
    [ ! -e "$AUTO/worktree-gc-repos.promoted" ]
    [ ! -e "$STUB/ms365-ran" ]
  done
  [[ "$output" == *"OP-5"* ]]
  [[ "$output" == *"0067-ms365-shared.sh --confirm ms365-shared"* ]]
  [ -f "$AUTO/pending-activation/52-load-2026-10-17-activate.sh.done" ]
}

@test "both plists lint" {
  /usr/bin/plutil -lint "$ATTRIB_PLIST"
  /usr/bin/plutil -lint "$GC_PLIST"
}

@test "capacity-attrib plist: KeepAlive daemon in the Standard band, no demotion keys" {
  x() { /usr/bin/plutil -extract "$1" raw -o - "$ATTRIB_PLIST"; }
  [ "$(x Label)" = com.claude.capacity-attrib ]
  [ "$(x KeepAlive)" = true ]; [ "$(x RunAtLoad)" = true ]
  [ "$(x ProcessType)" = Standard ]
  if x Nice >/dev/null 2>&1 || x LowPriorityIO >/dev/null 2>&1; then echo "a demotion key is set"; return 1; fi
  [[ "$(x ProgramArguments.2)" == *'capacity-attrib.py" --daemon --interval 5'* ]]
}

@test "worktree-gc-infra plist: 04:15 calendar kept, WatchPaths on the wake file, StartInterval 600, --auto" {
  x() { /usr/bin/plutil -extract "$1" raw -o - "$GC_PLIST"; }
  [ "$(x StartCalendarInterval.Hour)" = 4 ]; [ "$(x StartCalendarInterval.Minute)" = 15 ]
  [ "$(x WatchPaths.0)" = /Users/chrisren/.claude/state/worktree-gc.wake ]
  [ "$(x StartInterval)" = 600 ]
  [ "$(x ProgramArguments.2 | grep -o 'worktree-gc-infra-run.sh" --auto' | wc -l | tr -d ' ')" = 2 ]
}

@test "the capacity-attrib manifest row parses, matches the plist Label and names this script" {
  row="$(grep -E '^com\.claude\.capacity-attrib[[:space:]]*\|' "$MANIFEST")"
  [ "$(printf '%s\n' "$row" | wc -l | tr -d ' ')" = 1 ]
  nf="$(printf '%s' "$row" | awk -F'|' '{print NF}')"
  [ "$nf" -ge 6 ] && [ "$nf" -le 7 ]
  f() { printf '%s' "$row" | cut -d'|' -f"$1" | tr -d '[:space:]'; }
  [ "$(f 1)" = "$(/usr/bin/plutil -extract Label raw -o - "$ATTRIB_PLIST")" ]
  [ "$(f 2)" = staged ]
  [ "$(f 6)" = 52-load-2026-10-17-activate.sh ]
  [ -x "$REPO/docs/activation/pending-activation/$(f 6)" ]
}
