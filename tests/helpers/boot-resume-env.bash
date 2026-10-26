# shellcheck shell=bash
# shellcheck disable=SC2034,SC2016  # SCRIPT and the stubs' paths are read by the suites that load this; each stub body's $ is the stub's own shell
# The boot-resume.sh test environment, shared by tests/boot-resume.bats and tests/boot-resume-lockup.bats:
# every external seam stubbed under $BATS_TEST_TMPDIR, the boot pinned at 1784800000, and the fixture
# writers for alarm rosters, tombstones, heartbeats and registry rows. Load after helpers/cc-stub.
# cc_stub_self PATH [BODY] — cc_stub at PATH (BODY on stdin when absent), with `self=<PATH>` put after
# the #! line. Under the shim "$0" is the body's own .<D>-real path, so these stubs key their logs and
# control files (.log, .fail, .rc …) on "$self", the path the cases read and write.
cc_stub_self() {
  local p="$1" body
  if [ $# -ge 2 ]; then body="$2"; else IFS= read -r -d '' body || true; fi
  cc_stub "${p%/*}" "${p##*/}" "${body%%$'\n'*}"$'\n'"self=$(printf '%q' "$p")"$'\n'"${body#*$'\n'}"
}

boot_resume_setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SCRIPT="$REPO/scripts/boot-resume.sh"
  export CC_REGISTRY_DIR="$BATS_TEST_TMPDIR/cc-registry"
  export CC_ROLES_DIR="$BATS_TEST_TMPDIR/roles"
  export CC_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export CC_BOOT_RESUME_STATE_DIR="$BATS_TEST_TMPDIR/state"
  export CC_BOOTTIME_OVERRIDE=1784800000                 # fixed boot epoch (sec)
  mkdir -p "$CC_REGISTRY_DIR" "$CC_ROLES_DIR"
  echo "desk-pane-uuid-current" > "$CC_ROLES_DIR/desk"

  # stub cc-notify: one call-marker per invocation in .calls (the boot-delta message is MULTI-LINE,
  # so counting .log lines would over-count a single call) + the full args in .log for content greps.
  export CC_NOTIFY_BIN="$BATS_TEST_TMPDIR/stub-notify"
  cc_stub_self "$CC_NOTIFY_BIN" <<'SH'
#!/bin/bash
# A restore note (--mailbox-only, W3 P4) is not a page: it gets its own log, so the page counts and
# the page greps stay about pages.
case " $* " in *" --mailbox-only "*) printf '%s\n' "$*" >> "$self.notes"; [ -f "$self.notes-fail" ] && exit 3; exit 0 ;; esac
echo "NOTIFY_CALL" >> "$self.calls"
printf '%s\n' "$*" >> "$self.log"
SH
  # W3 P4: restore v2 reads each prompt back from the transcript for up to 90 s and falls back to
  # cc-wake. No wait in a test, and a stub in place of the real cc-wake (a file .rc sets its exit).
  export CC_RESTORE_CONFIRM_S=0 CC_RESTORE_PASTE_SETTLE_S=0
  export CC_WAKE_BIN="$BATS_TEST_TMPDIR/stub-wake"
  cc_stub_self "$CC_WAKE_BIN" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >> "$self.log"
exit "$(cat "$self.rc" 2>/dev/null || echo 1)"
SH
  unset CC_RESTORE_NUDGE
  # The verified paste has a real entry point since W3 P5 (handoff-fire.sh paste-verified). No case
  # here may reach it: the seam names a path that does not exist unless a case installs a stub.
  export CC_RESTORE_PASTE_CMD="$BATS_TEST_TMPDIR/no-paste-here"
  # This suite names the fire script only in comments; pinned so no case reads live machine load.
  export CC_FIRE_CAPACITY_GATE=off
  # The capacity-admit gate is closed too (the land's hermeticity lint): every launcher and layout
  # here is a stub, so no case may reach scripts/lib/capacity-admit.sh against the live machine.
  export CC_ADMIT_GATE=off

  # stub cc-backlog: echo a hex id + log the argv. MANDATORY, not optional — resolve_bin's ladder
  # reaches the REPO's own bin/cc-backlog from $(dirname $0)/../bin, so an unstubbed run would file
  # real rows into the operator's live ~/.claude/autonomy/backlog.jsonl from a test.
  export CC_BACKLOG_BIN="$BATS_TEST_TMPDIR/stub-backlog"
  cc_stub_self "$CC_BACKLOG_BIN" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >> "$self.log"
[ -f "$self.fail" ] && exit 1
cat "$self.out" 2>/dev/null || echo "beef1234cafe"
SH

  # stub the resume launcher: log "<acct> <cwd> <sid> <branch>" per LAUNCH, exit 0. The ownership
  # probe (--check-only) logs to .checks instead, and exits 5 for any sid listed in .held.
  export CC_RESUME_LAUNCH_BIN="$BATS_TEST_TMPDIR/stub-launch"
  cc_stub_self "$CC_RESUME_LAUNCH_BIN" <<'SH'
#!/bin/bash
if [ "$1" = --check-only ]; then
  shift; printf '%s\n' "$*" >> "$self.checks"
  grep -qx "$3" "$self.held" 2>/dev/null && { echo "boot-resume-launch: $3 already has 1 live holder(s) - stub" >&2; exit 5; }
  grep -qx "$3" "$self.member" 2>/dev/null && { echo "boot-resume-launch: NOT LAUNCHING $3 - an Agent Teams member (stub)" >&2; exit 7; }
  exit 0
fi
printf '%s\n' "$*" >> "$self.log"
grep -qx "$3" "$self.indet" 2>/dev/null && exit 6   # an indeterminate kitty launch (review item 2)
grep -qx "$3" "$self.held" 2>/dev/null && exit 5
grep -qx "$3" "$self.member-at-launch" 2>/dev/null && exit 7   # passed --check-only, refused at launch
exit 0
SH

  # Every new resolution must be redirected, or a test reads the operator's real reboot roster and
  # tombstones, or drives the real kitty through the real layout. The layout is ABSENT by default,
  # which is the launcher-per-window fallback the older cases below were written against.
  export CC_BOOT_RESUME_ROSTER_DIR="$BATS_TEST_TMPDIR/autonomy"
  export CC_SHUTDOWN_TOMB_DIR="$BATS_TEST_TMPDIR/tombs"
  mkdir -p "$CC_BOOT_RESUME_ROSTER_DIR" "$CC_SHUTDOWN_TOMB_DIR"
  export CC_RESUME_LAYOUT_BIN="$BATS_TEST_TMPDIR/no-layout"
  export CC_OPEN_BIN="$BATS_TEST_TMPDIR/stub-open"
  cc_stub_self "$CC_OPEN_BIN" "$(printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "$self.log"\n')"
  export CC_BOOT_RESUME_KITTY_POLL=0
  # Step 0, the heartbeat (W3 P3a-i): a fixture HOME and a stub for every reader it has, so no case
  # reads the live registry or asks the live kitty for its tree. The stub cc-sessions prints
  # .json (default []), logs each call, and SWEEPS the fixture registry when .sweep exists — the
  # real one deletes dead rows started over 24 h ago.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_HEARTBEAT_DIR="$BATS_TEST_TMPDIR/heartbeat"
  export CC_HB_NOW=1784800000      # the tick's clock, pinned to the fixed boot: prune is age-based
  export CC_HB_SESSIONS_BIN="$BATS_TEST_TMPDIR/stub-sessions"
  cc_stub_self "$CC_HB_SESSIONS_BIN" <<'SH'
#!/bin/bash
echo call >> "$self.calls"
[ -f "$self.sweep" ] && rm -f "$CC_REGISTRY_DIR"/*.json
cat "$self.json" 2>/dev/null || echo '[]'
SH
  export CC_HB_KITTEN_BIN="$BATS_TEST_TMPDIR/stub-kitten"
  cc_stub "$BATS_TEST_TMPDIR" stub-kitten "$(printf '#!/bin/bash\necho "[]"\n')"
  export CC_HB_PS_BIN="$BATS_TEST_DIRNAME/fixtures/hb-kitty-ps" CC_HB_LSOF_BIN=/usr/bin/true
  export CC_KITTY_SOCKET_BIN="$BATS_TEST_TMPDIR/stub-ksock"
  cc_stub "$BATS_TEST_TMPDIR" stub-ksock "$(printf '#!/bin/bash\necho unix:/tmp/kitty-test\n')"
  # The classifier stub is each suite's own (its text matters to boot-resume.bats; see there).
  export CC_RESUME_CLASSIFY_BIN="$BATS_TEST_TMPDIR/stub-classify"

  # stub lr-select (session-sprawl consolidation seam, 2026-07-21). Default = identity pass-through:
  # every --candidate becomes a winner, so the launcher-wiring tests stay about boot-resume's seam
  # rather than re-testing lr-select's policy (which owns its own 21 cases in lr-select.bats).
  # A test that wants consolidation writes the winner TSV to .winners.
  export CC_RESUME_SELECT_BIN="$BATS_TEST_TMPDIR/stub-select"
  cc_stub_self "$CC_RESUME_SELECT_BIN" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >> "$self.log"
if [ -f "$self.winners" ]; then cat "$self.winners"; exit 0; fi
while [ $# -gt 0 ]; do
  case "$1" in
    --candidate) a="${2%%:*}"; rest="${2#*:}"; s="${rest%%:*}"; c="${rest#*:}"
                 printf '%s\t%s\t%s\t\n' "$a" "$s" "$c"; shift 2 ;;
    *) shift ;;
  esac
done
SH

  # stub keepalive: log the call, exit 0 (never start the real infinite loop in a test).
  export CC_KEEPALIVE_BIN="$BATS_TEST_TMPDIR/stub-keepalive"
  cc_stub_self "$CC_KEEPALIVE_BIN" <<'SH'
#!/bin/bash
printf 'started\n' >> "$self.log"
printf '%s\n' "${CC_KEEPALIVE_MARKERS-<unset>}" >> "$self.markers"
SH

  # stub launchctl: report two loaded com.claude jobs (one up, one down) deterministically.
  export CC_LAUNCHCTL_BIN="$BATS_TEST_TMPDIR/stub-launchctl"
  cc_stub "$BATS_TEST_TMPDIR" stub-launchctl - <<'SH'
#!/bin/bash
# mimic `launchctl list`: PID<TAB>Status<TAB>Label
printf '%s\t%s\t%s\n' 4321 0 com.claude.dispatcher
printf '%s\t%s\t%s\n' - 0 com.claude.discovery
SH

  # stub transcript_mtime: default = "recent" (just before the fixed test boottime) so a registry
  # ghost passes the recency filter; a per-sid override file marks a session as OLD cruft.
  export MTIME_STUB_DIR="$BATS_TEST_TMPDIR/mtimes"; mkdir -p "$MTIME_STUB_DIR"
  export CC_TRANSCRIPT_MTIME_BIN="$BATS_TEST_TMPDIR/stub-mtime"
  cc_stub "$BATS_TEST_TMPDIR" stub-mtime - <<'SH'
#!/bin/bash
# args: <account> <sid> <cwd>
if [ -f "$MTIME_STUB_DIR/$2" ]; then cat "$MTIME_STUB_DIR/$2"; else echo 1784799900; fi
SH

  # Restore v2 (W3 P3a-ii): the start gate reads load through sysctl, so a stub answers it — the
  # first lines of .loads in turn, then the last one; load 0.50 on 8 cores by default — or a case
  # would wait on the box's real load. The recycle log and teardown markers are fixtures too.
  export CC_SYSCTL_BIN="$BATS_TEST_TMPDIR/stub-sysctl"
  cc_stub_self "$CC_SYSCTL_BIN" <<'SH'
#!/bin/bash
case "$*" in
  *vm.loadavg*) n=$(cat "$self.n" 2>/dev/null || echo 0); echo $((n + 1)) > "$self.n"
                l="$(sed -n "$((n + 1))p" "$self.loads" 2>/dev/null)"; [ -n "$l" ] || l="$(tail -n 1 "$self.loads" 2>/dev/null)"
                echo "{ ${l:-0.50} 0.40 0.30 }" ;;
  *hw.ncpu*) echo 8 ;;
  *) exit 1 ;;
esac
SH
  export CC_HANDOFF_LOG="$BATS_TEST_TMPDIR/handoffs.jsonl" CC_TEARDOWN_DIR="$BATS_TEST_TMPDIR/teardown"
  # 2026-10-21 (reboot-resume R3, R8): the mail carry works on a fixture mailbox through the real
  # library, and cc-restore-rebind is a stub that logs its argv (the real one claims live roles).
  export CC_MAILBOX_DIR="$BATS_TEST_TMPDIR/mailbox"
  export CC_RESTORE_REBIND_BIN="$BATS_TEST_TMPDIR/stub-rebind"
  cc_stub_self "$CC_RESTORE_REBIND_BIN" "$(printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "$self.log"\necho "cc-restore-rebind: verdict=NOOP"\n')"
}

reg_entry() {
  local sid="$1" started="$2" acct="$3" cwd="${4:-/Users/x/Development/.worktrees/wt-$1}" name="${5:-wt-$1-PANE}"
  jq -n --arg p "PANE-$sid" --arg n "$name" --arg c "$cwd" --arg a "$acct" \
        --argjson s "$started" --arg sid "$sid" \
        '{paneUUID:$p,name:$n,cwd:$c,account:$a,pid:999999,startedAt:$s,session_id:$sid}' \
        > "$CC_REGISTRY_DIR/$sid.json"
}
roster() { # <tag> <start-epoch> <json>
  printf '%s' "$3" > "$CC_BOOT_RESUME_ROSTER_DIR/reboot-$1.roster.json"
  echo "$2" > "$CC_BOOT_RESUME_ROSTER_DIR/reboot-$1.start"
}
rrow() { # <sid> <config-acct> <cwd> <name>
  printf '{"session_id":"%s","account":"%s","cwd":"%s","name":"%s","pid":1,"startedAt":1}' "$1" "$2" "$3" "$4"
}
tomb() { # <sid> <endedAt> [hostShutdown] [cwd]
  jq -n --arg s "$1" --argjson t "$2" --argjson h "${3:-false}" --arg c "${4:-/Users/x/wt-$1}" \
    '{session_id:$s,account:"claude-next",cwd:$c,name:("T-"+$s),endedAt:$t,endReason:"other",hostShutdown:$h}' \
    > "$CC_SHUTDOWN_TOMB_DIR/$1.json"
}
hbeat() { # <uuid> <kitty-pid> <start> <roster-json> [hb.session.tsv line]
  local d="$CC_HEARTBEAT_DIR/$1/$2"
  mkdir -p "$d"; printf '%s' "$4" > "$d/hb.roster.json"; echo "$3" > "$d/hb.start"
  [ -z "${5:-}" ] || printf '%s\n' "$5" > "$d/hb.session.tsv"
}
