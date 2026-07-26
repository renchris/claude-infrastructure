#!/usr/bin/env bats
# team-orphan-reaper.sh — archive-safety gate. A team is ARCHIVED only on POSITIVE evidence of death;
# absence of a watchdog pid file is UNKNOWN (surfaced, never archived), and a dead LEAD pid is
# cross-checked against the live-session registry before archiving (a /handoff or crash-respawn
# successor drives the team from a member worktree/name).
#
# Coverage (the script had ZERO prior coverage):
#   (i)   no watchdog pid file            → UNKNOWN: surfaced (log + operator page), NOT archived
#   (ii)  dead lead pid + live co-cwd     → KEEP (successor drives from inside a member worktree)
#   (v)   dead lead pid + live name-match → KEEP (successor registered under a member/lead name)
#   (iii) dead lead pid + no live match   → ARCHIVED as before (regression guard)
#   (iv)  _archive dir + malformed config → skipped safely, no error, nothing archived
#   plus: an ALIVE lead is never touched; cc-sessions unreadable degrades to archive (never stranded)

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  REAPER="$REPO/scripts/team-orphan-reaper.sh"

  # Fully hermetic: env seams point every real path at a fixture; HOME is fixtured belt-and-suspenders.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export TEAM_REAPER_TEAMS_DIR="$BATS_TEST_TMPDIR/teams"
  export TEAM_REAPER_WATCHDOG_DIR="$BATS_TEST_TMPDIR/watchdog"
  export TEAM_REAPER_LOG_FILE="$BATS_TEST_TMPDIR/reaper.log"
  TEAMS="$TEAM_REAPER_TEAMS_DIR"; WD="$TEAM_REAPER_WATCHDOG_DIR"; LOG="$TEAM_REAPER_LOG_FILE"
  mkdir -p "$TEAMS" "$WD"

  # PATH shims for the helper CLIs (the reaper resolves cc-sessions / cc-notify PATH-first).
  SHIM="$BATS_TEST_TMPDIR/bin"; mkdir -p "$SHIM"
  SESS_JSON="$BATS_TEST_TMPDIR/sessions.json"; echo '[]' > "$SESS_JSON"   # default: no live sessions
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
}

# ── fixtures ──────────────────────────────────────────────────────────────────────────────────────
mk_team()      { local d="$TEAMS/$1"; mkdir -p "$d"; printf '%s' "$2" > "$d/config.json"; }  # $1=name $2=config-json
mk_pid_dead()  { printf '%s\n' 999999 > "$WD/$1.pid"; }   # pid file present, pid dead (> macOS max pid)
mk_pid_alive() { printf '%s\n' "$$"   > "$WD/$1.pid"; }   # pid file present, pid alive (this test process)
archived()     { ls -d "$TEAMS/_archive/$1-"* >/dev/null 2>&1; }  # 0 iff an archive entry exists

# ── (i) UNKNOWN-liveness: no watchdog pid file ──────────────────────────────────────────────────────
@test "unknown-liveness: a team with NO watchdog pid file is surfaced, NOT archived" {
  mk_team t-nopid '{"leadSessionId":"sid-nopid","members":[{"name":"team-lead","cwd":"/somewhere"}]}'
  # (deliberately no pid file ⇒ UNKNOWN, the common in-place-/handoff shape)
  run bash "$REAPER"
  [ "$status" -eq 0 ]
  [ -d "$TEAMS/t-nopid" ]                                                    # still live on disk
  ! archived t-nopid || false                                               # never moved to _archive
  grep -q "unknown-liveness t-nopid (no watchdog pid file) — surfacing" "$LOG"
  grep -q "t-nopid" "$NOTIFY_LOG"                                           # operator was paged
}

@test "unknown-liveness: an EMPTY watchdog pid file is also UNKNOWN (not dead)" {
  mk_team t-empty '{"leadSessionId":"sid-empty","members":[{"name":"team-lead","cwd":"/x"}]}'
  : > "$WD/sid-empty.pid"                                                    # present but empty ⇒ no pid to test
  run bash "$REAPER"
  [ "$status" -eq 0 ]
  ! archived t-empty || false
  grep -q "unknown-liveness t-empty" "$LOG"
}

# ── (ii) cross-check: live session cwd INSIDE a member worktree ⇒ KEEP ───────────────────────────────
@test "cross-check: dead lead pid but a live session cwd inside a member worktree ⇒ KEEP" {
  local wt="$BATS_TEST_TMPDIR/wt-alpha"; mkdir -p "$wt/nested"
  mk_team t-live "$(jq -nc --arg wt "$wt" '{leadSessionId:"sid-dl",members:[{name:"team-lead",cwd:$wt}]}')"
  mk_pid_dead sid-dl
  jq -nc --arg c "$wt/nested" '[{paneUUID:"u1",name:"Successor-Desk",cwd:$c,pid:1}]' > "$SESS_JSON"
  run bash "$REAPER"
  [ "$status" -eq 0 ]
  ! archived t-live || false                                                # positive life evidence ⇒ kept
  [ -d "$TEAMS/t-live" ]
  grep -q "keep t-live:" "$LOG"
}

# ── (v) cross-check: live session NAME matches a member/lead name ⇒ KEEP ─────────────────────────────
@test "cross-check: dead lead pid but a live session NAME matches a member ⇒ KEEP" {
  mk_team t-name '{"leadSessionId":"sid-dn","members":[{"name":"worker-1","cwd":"/a"},{"name":"team-lead","cwd":"/b"}]}'
  mk_pid_dead sid-dn
  jq -nc '[{paneUUID:"u2","name":"worker-1",cwd:"/unrelated/path",pid:1}]' > "$SESS_JSON"
  run bash "$REAPER"
  [ "$status" -eq 0 ]
  ! archived t-name || false
  grep -q "keep t-name:" "$LOG"
}

# ── (iii) regression: genuinely dead ⇒ archived exactly as before ────────────────────────────────────
@test "regression: dead lead pid + no live registry match ⇒ archived (as before)" {
  mk_team t-dead '{"leadSessionId":"sid-dead","members":[{"name":"team-lead","cwd":"/gone/wt"}]}'
  mk_pid_dead sid-dead
  echo '[]' > "$SESS_JSON"                                                   # no live sessions
  run bash "$REAPER"
  [ "$status" -eq 0 ]
  archived t-dead                                                           # moved to _archive
  [ ! -d "$TEAMS/t-dead" ]                                                   # gone from live teams
  grep -q "archived orphan team: t-dead" "$LOG"
  # watchdog pid file for the archived lead is cleaned up (unchanged behaviour)
  [ ! -f "$WD/sid-dead.pid" ]
}

# ── (iv) safety: _archive dir + malformed config are skipped without error ───────────────────────────
@test "safety: the _archive dir and a malformed config.json are skipped, nothing archived" {
  mkdir -p "$TEAMS/_archive/old-123"
  echo '{"leadSessionId":"whatever"}' > "$TEAMS/_archive/old-123/config.json"
  mk_team t-bad 'this is { not: valid json'                                  # unparseable config
  # (no pid file — but the empty-leadSessionId guard short-circuits before liveness is ever consulted)
  run bash "$REAPER"
  [ "$status" -eq 0 ]
  [ -d "$TEAMS/_archive/old-123" ]                                          # _archive left untouched
  [ -d "$TEAMS/t-bad" ]                                                     # malformed team not archived
  ! archived t-bad || false
  grep -q "skip t-bad: no leadSessionId" "$LOG"
}

# ── alive-branch preserved: a live lead is never touched ─────────────────────────────────────────────
@test "alive lead: a team whose lead pid is alive is never archived" {
  mk_team t-alive '{"leadSessionId":"sid-al","members":[{"name":"team-lead","cwd":"/x"}]}'
  mk_pid_alive sid-al
  run bash "$REAPER"
  [ "$status" -eq 0 ]
  ! archived t-alive || false
  [ -d "$TEAMS/t-alive" ]
}

# ── degradation: cc-sessions unreadable ⇒ the pid-death verdict still archives (never stranded) ──────
@test "degradation: cc-sessions unreadable ⇒ a dead team is still archived (fallback)" {
  export CC_SESSIONS_BIN="$BATS_TEST_TMPDIR/no-such-cc-sessions"            # nonexistent ⇒ cross-check yields nothing
  mk_team t-fb '{"leadSessionId":"sid-fb","members":[{"name":"team-lead","cwd":"/x"}]}'
  mk_pid_dead sid-fb
  run bash "$REAPER"
  [ "$status" -eq 0 ]
  archived t-fb
}
