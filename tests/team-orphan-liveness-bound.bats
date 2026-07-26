#!/usr/bin/env bats
# team-orphan-reaper.sh — POSITIVE liveness oracle + BOUNDED abstain (leg c of 95281da714f0).
#
# The defect: "no watchdog pid file" is UNKNOWN, and UNKNOWN did nothing except log and page —
# every sweep, forever. Measured on disk 2026-07-26: 77 identical "unknown-liveness
# session-85cf3b06" pages plus 11 for session-69dfb701, each re-emitting "if the team is truly
# dead, clean up <dir>". A correct abstention that never terminates is a permanent operator step.
#
# The fix has three parts, and this suite pins each:
#   POSITIVE   ask whether anyone is actually WORKING (a live process's cwd at/below a member
#              worktree), not merely whether a RECORD of the lead exists. Keyed on cwd OCCUPANCY,
#              never argv: the launcher carries the worktree path and then exits.
#   THREE-STATE a probe that cannot run is UNRESOLVED — a non-verdict. It abstains and NEVER
#              archives at any age; folding it into "unoccupied" would archive every team on a
#              machine without lsof.
#   BOUNDED    past the ceiling the abstain RESOLVES instead of sitting forever, and the page is
#              damped to at most once per episode.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  REAPER="$REPO/scripts/team-orphan-reaper.sh"

  # Fixture $HOME — the state dir defaults under it, and without this the suite would write the
  # operator's real ~/.claude/autonomy/ and page their real desk.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export TEAM_REAPER_TEAMS_DIR="$BATS_TEST_TMPDIR/teams"
  export TEAM_REAPER_WATCHDOG_DIR="$BATS_TEST_TMPDIR/watchdog"
  export TEAM_REAPER_LOG_FILE="$BATS_TEST_TMPDIR/reaper.log"
  export TEAM_REAPER_STATE_DIR="$BATS_TEST_TMPDIR/state"
  TEAMS="$TEAM_REAPER_TEAMS_DIR"; LOG="$TEAM_REAPER_LOG_FILE"; STATE="$TEAM_REAPER_STATE_DIR"
  mkdir -p "$TEAMS" "$TEAM_REAPER_WATCHDOG_DIR" "$STATE"

  # The member worktree the oracle probes.
  WT="$BATS_TEST_TMPDIR/wt-live"; mkdir -p "$WT"

  SHIM="$BATS_TEST_TMPDIR/bin"; mkdir -p "$SHIM"
  SESS_JSON="$BATS_TEST_TMPDIR/sessions.json"; echo '[]' > "$SESS_JSON"
  NOTIFY_LOG="$BATS_TEST_TMPDIR/notify.log"; : > "$NOTIFY_LOG"
  cat > "$SHIM/cc-sessions" <<EOF
#!/usr/bin/env bash
cat "$SESS_JSON" 2>/dev/null || echo '[]'
EOF
  cat > "$SHIM/cc-notify" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$NOTIFY_LOG"
exit 0
EOF
  chmod +x "$SHIM/cc-sessions" "$SHIM/cc-notify"
  export PATH="$SHIM:$PATH"

  # Fake lsof emitting the -F pn form. Steerable: LSOF_OUT holds exactly what it prints.
  LSOF="$BATS_TEST_TMPDIR/lsof-spy"
  LSOF_OUT="$BATS_TEST_TMPDIR/lsof.out"; : > "$LSOF_OUT"
  cat > "$LSOF" <<EOF
#!/usr/bin/env bash
cat "$LSOF_OUT" 2>/dev/null
exit 0
EOF
  chmod +x "$LSOF"
  export TEAM_REAPER_LSOF_BIN="$LSOF"
}

mk_team() { mkdir -p "$TEAMS/$1"; printf '%s' "$2" > "$TEAMS/$1/config.json"; }
archived() { ls -d "$TEAMS/_archive/$1-"* >/dev/null 2>&1; }
# backdate the UNKNOWN clock so the bound is already exceeded
age_out() { echo $(( $(date +%s) - 99999 )) > "$STATE/$1.unknown-since"; }

@test "(i) POSITIVE: a live process whose CWD is in a member worktree keeps the team ALIVE" {
  mk_team t-occ "{\"leadSessionId\":\"sid-o\",\"members\":[{\"name\":\"w1\",\"cwd\":\"$WT\"}]}"
  printf 'p4242\nn%s\n' "$WT" > "$LSOF_OUT"
  age_out t-occ                                    # even PAST the bound, occupancy wins
  run bash "$REAPER"
  [ "$status" -eq 0 ] || false
  [ -d "$TEAMS/t-occ" ] || false
  ! archived t-occ || false
  grep -q "OCCUPIED" "$LOG" || false
}

@test "(ii) PREFIX not equality — a worker that cd'd into a SUBDIRECTORY is still working" {
  mk_team t-sub "{\"leadSessionId\":\"sid-s\",\"members\":[{\"name\":\"w1\",\"cwd\":\"$WT\"}]}"
  printf 'p4242\nn%s/src/deep\n' "$WT" > "$LSOF_OUT"
  age_out t-sub
  run bash "$REAPER"
  [ -d "$TEAMS/t-sub" ] || false
  grep -q "OCCUPIED" "$LOG" || false
}

@test "(iii) PHYSICAL path — lsof resolves symlinks, so a symlinked worktree must still match" {
  # This is the failure mode that is blind while looking like it works: lsof reports the PHYSICAL
  # cwd, so matching only the logical path finds nothing under any symlinked parent.
  real="$BATS_TEST_TMPDIR/real-wt"; mkdir -p "$real"
  link="$BATS_TEST_TMPDIR/link-wt"; ln -s "$real" "$link"
  mk_team t-sym "{\"leadSessionId\":\"sid-y\",\"members\":[{\"name\":\"w1\",\"cwd\":\"$link\"}]}"
  printf 'p4242\nn%s\n' "$(cd "$real" && pwd -P)" > "$LSOF_OUT"   # lsof reports the PHYSICAL path
  age_out t-sym
  run bash "$REAPER"
  [ -d "$TEAMS/t-sym" ] || false
  ! archived t-sym || false
  grep -q "OCCUPIED" "$LOG" || false
}

@test "(iv) a SIBLING worktree must NOT count as occupancy (no loose prefix match)" {
  sib="${WT}-sibling"; mkdir -p "$sib"
  mk_team t-sib "{\"leadSessionId\":\"sid-b\",\"members\":[{\"name\":\"w1\",\"cwd\":\"$WT\"}]}"
  printf 'p4242\nn%s\n' "$sib" > "$LSOF_OUT"       # occupancy is in the SIBLING, not our worktree
  age_out t-sib
  run bash "$REAPER"
  archived t-sib || false                          # ⇒ resolves, because our worktree is empty
}

@test "(iv-b) a SHARED main checkout is NOT occupancy evidence — 45 procs there mean nothing" {
  # The measured false-ALIVE: session-85cf3b06's only member cwd is the shared checkout
  # (~/Development/claude-infrastructure), where 45 live processes legitimately sat. Counting them
  # would pin a dead team forever and re-create the stall this leg removes. `.git` is a DIRECTORY
  # in a main checkout and a FILE in a linked worktree, so the test needs no path list.
  shared="$BATS_TEST_TMPDIR/shared-checkout"; mkdir -p "$shared/.git"      # .git DIR ⇒ main checkout
  mk_team t-shared "{\"leadSessionId\":\"sid-sh\",\"members\":[{\"name\":\"team-lead\",\"cwd\":\"$shared\"}]}"
  printf 'p4242\nn%s\np4243\nn%s\n' "$shared" "$shared" > "$LSOF_OUT"      # busy shared checkout
  age_out t-shared
  run bash "$REAPER"
  [ "$status" -eq 0 ] || false
  grep -q "skipping shared checkout" "$LOG" || false
  archived t-shared || false                       # resolves, instead of a false ALIVE forever
}

@test "(iv-c) a DEDICATED linked worktree IS occupancy evidence (the positive control)" {
  # Same fixture shape as (iv-b) but `.git` is a FILE ⇒ linked worktree ⇒ occupancy counts.
  # Without this control, (iv-b) would also pass if the probe were simply broken everywhere.
  ded="$BATS_TEST_TMPDIR/wt-dedicated"; mkdir -p "$ded"; echo "gitdir: /somewhere/.git/worktrees/x" > "$ded/.git"
  mk_team t-ded "{\"leadSessionId\":\"sid-dd\",\"members\":[{\"name\":\"w1\",\"cwd\":\"$ded\"}]}"
  printf 'p4242\nn%s\n' "$ded" > "$LSOF_OUT"
  age_out t-ded
  run bash "$REAPER"
  [ -d "$TEAMS/t-ded" ] || false
  ! archived t-ded || false
  grep -q "OCCUPIED" "$LOG" || false
}

@test "(v) THREE-STATE: an UNRESOLVED probe (no lsof) NEVER archives, at any age" {
  mk_team t-unres "{\"leadSessionId\":\"sid-u\",\"members\":[{\"name\":\"w1\",\"cwd\":\"$WT\"}]}"
  age_out t-unres                                  # far past every ceiling
  TEAM_REAPER_LSOF_BIN= run bash "$REAPER"         # set-but-EMPTY ⇒ probe genuinely disabled
  [ "$status" -eq 0 ] || false
  [ -d "$TEAMS/t-unres" ] || false
  ! archived t-unres || false
  grep -q "UNRESOLVED" "$LOG" || false
}

@test "(vi) an UNRESOLVED probe past its ceiling pages the operator exactly ONCE" {
  mk_team t-page "{\"leadSessionId\":\"sid-p\",\"members\":[{\"name\":\"w1\",\"cwd\":\"$WT\"}]}"
  age_out t-page
  TEAM_REAPER_LSOF_BIN= run bash "$REAPER"
  TEAM_REAPER_LSOF_BIN= run bash "$REAPER"
  TEAM_REAPER_LSOF_BIN= run bash "$REAPER"
  [ "$(grep -c 't-page' "$NOTIFY_LOG")" -eq 1 ] || false     # 3 sweeps, ONE page — the 77-page fix
}

@test "(vii) BOUNDED: unoccupied + no live session + past the ceiling RESOLVES (archives)" {
  mk_team t-res "{\"leadSessionId\":\"sid-r\",\"members\":[{\"name\":\"w1\",\"cwd\":\"$WT\"}]}"
  : > "$LSOF_OUT"                                  # probe ANSWERS: nobody is there
  age_out t-res
  run bash "$REAPER"
  [ "$status" -eq 0 ] || false
  archived t-res || false                          # no longer stalls forever
  grep -q "resolving" "$LOG" || false
}

@test "(viii) WITHIN the ceiling it still abstains — the watchdog may not have written its pidfile" {
  mk_team t-young "{\"leadSessionId\":\"sid-g\",\"members\":[{\"name\":\"w1\",\"cwd\":\"$WT\"}]}"
  : > "$LSOF_OUT"
  run bash "$REAPER"                               # fresh clock ⇒ age 0
  [ -d "$TEAMS/t-young" ] || false
  ! archived t-young || false
  grep -q "abstaining" "$LOG" || false
}

@test "(ix) a live REGISTRY session still keeps an unoccupied team (successor by name)" {
  mk_team t-reg "{\"leadSessionId\":\"sid-g2\",\"members\":[{\"name\":\"w-named\",\"cwd\":\"$WT\"}]}"
  : > "$LSOF_OUT"                                  # unoccupied …
  echo '[{"name":"w-named","cwd":"/elsewhere"}]' > "$SESS_JSON"   # … but the registry knows it
  age_out t-reg
  run bash "$REAPER"
  [ -d "$TEAMS/t-reg" ] || false
  ! archived t-reg || false
}

@test "(x) the UNKNOWN clock is per-team — one team's age must not resolve another" {
  mk_team t-old "{\"leadSessionId\":\"sid-1\",\"members\":[{\"name\":\"w1\",\"cwd\":\"$WT\"}]}"
  mk_team t-new "{\"leadSessionId\":\"sid-2\",\"members\":[{\"name\":\"w2\",\"cwd\":\"$WT\"}]}"
  : > "$LSOF_OUT"
  age_out t-old                                    # only t-old is past the bound
  run bash "$REAPER"
  archived t-old || false
  [ -d "$TEAMS/t-new" ] || false                   # t-new keeps its own, fresh clock
  ! archived t-new || false
}

@test "(xi) going ALIVE clears the UNKNOWN clock, so a later UNKNOWN starts a fresh episode" {
  mk_team t-clr "{\"leadSessionId\":\"sid-c\",\"members\":[{\"name\":\"w1\",\"cwd\":\"$WT\"}]}"
  age_out t-clr
  printf '%s\n' "$$" > "$TEAM_REAPER_WATCHDOG_DIR/sid-c.pid"    # lead pid ALIVE this sweep
  run bash "$REAPER"
  [ ! -f "$STATE/t-clr.unknown-since" ] || false                # clock cleared
  [ -d "$TEAMS/t-clr" ] || false
}

@test "(xii) DEAD lead pid + OCCUPIED worktree ⇒ KEEP (assignees still working)" {
  # A dead LEAD is not a dead TEAM. This can only ever prevent an archive, never cause one.
  mk_team t-dead "{\"leadSessionId\":\"sid-d\",\"members\":[{\"name\":\"w1\",\"cwd\":\"$WT\"}]}"
  printf '%s\n' 999999 > "$TEAM_REAPER_WATCHDOG_DIR/sid-d.pid"  # present + dead ⇒ DEAD verdict
  printf 'p4242\nn%s\n' "$WT" > "$LSOF_OUT"                     # but someone is still working
  run bash "$REAPER"
  [ -d "$TEAMS/t-dead" ] || false
  ! archived t-dead || false
  grep -q "assignees still working" "$LOG" || false
}
