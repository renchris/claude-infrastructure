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
@test "unknown-liveness: a team with NO watchdog pid file abstains (bounded), NOT archived" {
  mk_team t-nopid '{"leadSessionId":"sid-nopid","members":[{"name":"team-lead","cwd":"/somewhere"}]}'
  # (deliberately no pid file ⇒ UNKNOWN, the common in-place-/handoff shape)
  run bash "$REAPER"
  [ "$status" -eq 0 ]
  [ -d "$TEAMS/t-nopid" ]                                                    # still live on disk
  # COMPOSED resolution: this session's contract change, kept under 575a55ea's `|| false`
  # dead-assertion discipline (a non-final `!` is errexit-EXEMPT and therefore cannot fail).
  ! archived t-nopid || false                                               # never moved to _archive
  grep -q "unknown-liveness t-nopid" "$LOG"                                 # still surfaced in the log
  grep -q "abstaining" "$LOG"                                               # and explicitly bounded
  # CONTRACT CHANGE: the operator is NOT paged on a fresh UNKNOWN. The old behaviour paged every
  # sweep forever (measured: 77 identical pages for one team, 11 for another), which is the
  # permanent manual step this bounded-abstain replaces. A page now happens at most ONCE, and only
  # for an UNRESOLVED probe past its ceiling — see the leg-(c) suite.
  ! grep -q "t-nopid" "$NOTIFY_LOG" || false
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

# ── OFF-BOX ABSTAIN (CLOUD_OBSERVABILITY.md §5.2, liar #3 — the destructive one) ─────────────────
# Every oracle in this file is local: `kill -0` on a watchdog pid, `lsof -d cwd`, and a cc-sessions
# registry written by local hooks. A lead in an Anthropic-managed VM answers NO to all three BY
# CONSTRUCTION, and the ladder then archives — on a 600s launchd timer, so an unattended cloud fleet
# would be destroyed within ten minutes of being fired, by our own safety mechanism.
#
# The branch that matters is UNKNOWN, not DEAD: an off-box lead has NO watchdog pid file, so it
# never reaches the dead-pid arm — it enters UNKNOWN, and UNKNOWN archives too past the ceiling.
# A guard placed on the DEAD arm alone would have been correct-looking and completely ineffective.

use_cc_cloud() {
  export CC_CLOUD_BIN="$REPO/bin/cc-cloud"
  export CC_CLOUD_STATE="$BATS_TEST_TMPDIR/cloud"
  mkdir -p "$CC_CLOUD_STATE"
}
declare_cloud() { printf 'id=%s\nbranch=b\n' "$1" > "$CC_CLOUD_STATE/$1.decl"; }

# THE ONE THAT WOULD HAVE DESTROYED THE FLEET. No pid file (UNKNOWN), nothing occupying a worktree,
# no live session, and the UNKNOWN clock already past its ceiling ⇒ the pre-wiring subject archives.
@test "offbox: an UNKNOWN off-box lead past UNKNOWN_MAX_S is NOT archived" {
  use_cc_cloud
  declare_cloud session_01FLEET
  export TEAM_REAPER_UNKNOWN_MAX_S=0            # the ceiling is already breached — archive is due
  mk_team t-cloud '{"leadSessionId":"session_01FLEET","members":[{"name":"team-lead","cwd":"/nowhere"}]}'
  run bash "$REAPER"
  [ "$status" -eq 0 ]
  ! archived t-cloud || false
  [ -d "$TEAMS/t-cloud" ]
  grep -q "DECLARED OFF-BOX" "$LOG"
}

# THE POSITIVE CONTROL FOR THAT TEST. Identical fixture, undeclared id: the subject MUST still
# archive. Without this the test above passes for a subject that simply stopped archiving.
@test "offbox control: the SAME fixture with an UNDECLARED lead IS archived" {
  use_cc_cloud
  export TEAM_REAPER_UNKNOWN_MAX_S=0
  mk_team t-local '{"leadSessionId":"session_01UNDECLARED","members":[{"name":"team-lead","cwd":"/nowhere"}]}'
  run bash "$REAPER"
  [ "$status" -eq 0 ]
  archived t-local
}

@test "offbox: a DEAD-pid off-box lead is NOT archived either" {
  use_cc_cloud
  declare_cloud session_01DEADPID
  mk_team t-cd '{"leadSessionId":"session_01DEADPID","members":[{"name":"team-lead","cwd":"/x"}]}'
  mk_pid_dead session_01DEADPID              # a stale local pid file must not override the declaration
  run bash "$REAPER"
  [ "$status" -eq 0 ]
  ! archived t-cd || false
}

@test "offbox: a RETIRED declaration resumes the ordinary ladder — retire is terminal" {
  use_cc_cloud
  declare_cloud session_01RETIRED
  printf 'retired_at=1\n' > "$CC_CLOUD_STATE/session_01RETIRED.retired"
  mk_team t-ret '{"leadSessionId":"session_01RETIRED","members":[{"name":"team-lead","cwd":"/x"}]}'
  mk_pid_dead session_01RETIRED
  run bash "$REAPER"
  [ "$status" -eq 0 ]
  archived t-ret
}

@test "offbox: an off-box team is not counted as live, and does not page the operator" {
  use_cc_cloud
  declare_cloud session_01QUIET
  export TEAM_REAPER_UNKNOWN_MAX_S=0 TEAM_REAPER_UNRESOLVED_MAX_S=0
  mk_team t-q '{"leadSessionId":"session_01QUIET","members":[{"name":"team-lead","cwd":"/nowhere"}]}'
  run bash "$REAPER"
  [ "$status" -eq 0 ]
  # An abstention is not a page: the operator debt this file already fought (77 identical pages for
  # one session) must not come back through the cloud door.
  [ ! -s "$NOTIFY_LOG" ] || false
  grep -q "0 live" "$LOG" || false
  # …and it must be an ABSTENTION, not a quiet archive. Without this line the pre-wiring subject
  # also passes (it archives silently, which is likewise 0-live and page-free) and the test
  # discriminates nothing.
  ! archived t-q || false
  grep -q "keep t-q" "$LOG" || false
}

@test "offbox: no cc-cloud on the box degrades to the old ladder, never to a crash" {
  export CC_CLOUD_BIN=""                       # set-to-EMPTY must genuinely disable the lookup
  export TEAM_REAPER_UNKNOWN_MAX_S=0
  mk_team t-nocloud '{"leadSessionId":"session_01WOULDBE","members":[{"name":"team-lead","cwd":"/nowhere"}]}'
  run bash "$REAPER"
  [ "$status" -eq 0 ]
  archived t-nocloud
}
