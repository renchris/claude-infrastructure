#!/usr/bin/env bats
# boot-resume.sh — P0-10 agent half (T-P16-2 post-login auto-resume chain + T-P16-7 boot-delta pager).
#
# Contract under test (register-criteria-FIRST, house 43de6d6 discipline):
#   1. DETECT: a "session open at last boot" = a durable cc-registry ghost whose startedAt (ms) is
#      BEFORE kern.boottime (its process died in the reboot). Post-boot live sessions are EXCLUDED.
#   2. IDEMPOTENT: the boot-epoch marker makes a second login within the SAME boot a no-op — exactly
#      one page per reboot (T-P16-7 "produces exactly one operator page on next login").
#   3. POSTURE (operator's reboot-posture call; ruling #1 = PAGE, never auto-recover, is the DEFAULT):
#      mode=page  → page the delta once, DO NOT resume ("or pages once if deferred").
#      mode=resume → invoke the resume launcher per ghost (config-basename → reso alias mapped) +
#                    start keepalive once, then page a summary.
#   4. NEVER DRAIN TO NOBODY (a17 S-7), via a LADDER — not a bare fail-loud (backlog cae796cb1bfb):
#      a delta with no reachable desk role falls back to an ADDRESSLESS durable channel (the page
#      text to <state>/undelivered-<boot>.page + a `cc-backlog needs` operator-blocked row) and marks
#      the boot only once that filing SUCCEEDS. If the fallback also fails, the original polarity
#      stands: no mark, exit 4, retry. The pre-fix branch was the right polarity over the wrong
#      channel — its loudness is launchd stderr, so "will retry" degraded to an infinite SILENT retry
#      (5 identical failed/no-desk-role records in 21 min at the 2026-08-25 reboot, delta correct
#      every time, nothing surfaced).
#   5. ABSTENTION-LOGGED: every run writes ONE {fired|abstained|failed} IDL record (B-3).

setup() {
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
  cat > "$CC_NOTIFY_BIN" <<'SH'
#!/bin/bash
echo "NOTIFY_CALL" >> "$0.calls"
printf '%s\n' "$*" >> "$0.log"
SH
  chmod +x "$CC_NOTIFY_BIN"

  # stub cc-backlog: echo a hex id + log the argv. MANDATORY, not optional — resolve_bin's ladder
  # reaches the REPO's own bin/cc-backlog from $(dirname $0)/../bin, so an unstubbed run would file
  # real rows into the operator's live ~/.claude/autonomy/backlog.jsonl from a test.
  export CC_BACKLOG_BIN="$BATS_TEST_TMPDIR/stub-backlog"
  cat > "$CC_BACKLOG_BIN" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >> "$0.log"
[ -f "$0.fail" ] && exit 1
cat "$0.out" 2>/dev/null || echo "beef1234cafe"
SH
  chmod +x "$CC_BACKLOG_BIN"

  # stub the resume launcher: log "<acct> <cwd> <sid> <branch>" per LAUNCH, exit 0. The ownership
  # probe (--check-only) logs to .checks instead, and exits 5 for any sid listed in .held.
  export CC_RESUME_LAUNCH_BIN="$BATS_TEST_TMPDIR/stub-launch"
  cat > "$CC_RESUME_LAUNCH_BIN" <<'SH'
#!/bin/bash
if [ "$1" = --check-only ]; then
  shift; printf '%s\n' "$*" >> "$0.checks"
  grep -qx "$3" "$0.held" 2>/dev/null && exit 5
  exit 0
fi
printf '%s\n' "$*" >> "$0.log"
SH
  chmod +x "$CC_RESUME_LAUNCH_BIN"

  # Every new resolution must be redirected, or a test reads the operator's real reboot roster and
  # tombstones, or drives the real kitty through the real layout. The layout is ABSENT by default,
  # which is the launcher-per-window fallback the older cases below were written against.
  export CC_BOOT_RESUME_ROSTER_DIR="$BATS_TEST_TMPDIR/autonomy"
  export CC_SHUTDOWN_TOMB_DIR="$BATS_TEST_TMPDIR/tombs"
  mkdir -p "$CC_BOOT_RESUME_ROSTER_DIR" "$CC_SHUTDOWN_TOMB_DIR"
  export CC_RESUME_LAYOUT_BIN="$BATS_TEST_TMPDIR/no-layout"
  export CC_OPEN_BIN="$BATS_TEST_TMPDIR/stub-open"
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "$0.log"\n' > "$CC_OPEN_BIN"; chmod +x "$CC_OPEN_BIN"
  export CC_BOOT_RESUME_KITTY_POLL=0
  # Step 0, the heartbeat (W3 P3a-i): a fixture HOME and a stub for every reader it has, so no case
  # reads the live registry or asks the live kitty for its tree. The stub cc-sessions prints
  # .json (default []), logs each call, and SWEEPS the fixture registry when .sweep exists — the
  # real one deletes dead rows started over 24 h ago.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_HEARTBEAT_DIR="$BATS_TEST_TMPDIR/heartbeat"
  export CC_HB_NOW=1784800000      # the tick's clock, pinned to the fixed boot: prune is age-based
  export CC_HB_SESSIONS_BIN="$BATS_TEST_TMPDIR/stub-sessions"
  cat > "$CC_HB_SESSIONS_BIN" <<'SH'
#!/bin/bash
echo call >> "$0.calls"
[ -f "$0.sweep" ] && rm -f "$CC_REGISTRY_DIR"/*.json
cat "$0.json" 2>/dev/null || echo '[]'
SH
  chmod +x "$CC_HB_SESSIONS_BIN"
  export CC_HB_KITTEN_BIN="$BATS_TEST_TMPDIR/stub-kitten"
  printf '#!/bin/bash\necho "[]"\n' > "$CC_HB_KITTEN_BIN"; chmod +x "$CC_HB_KITTEN_BIN"
  export CC_HB_PS_BIN=/usr/bin/true CC_HB_LSOF_BIN=/usr/bin/true
  export CC_KITTY_SOCKET_BIN="$BATS_TEST_TMPDIR/stub-ksock"
  printf '#!/bin/bash\necho unix:/tmp/kitty-test\n' > "$CC_KITTY_SOCKET_BIN"; chmod +x "$CC_KITTY_SOCKET_BIN"
  # classifier stub: append a verdict per row — the sid's line in .verdicts, else INTERRUPTED — and
  # log its argv. A test that wants it to fail writes .fail.
  export CC_RESUME_CLASSIFY_BIN="$BATS_TEST_TMPDIR/stub-classify"
  cat > "$CC_RESUME_CLASSIFY_BIN" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >> "$0.log"
[ -f "$0.fail" ] && exit 3
while IFS= read -r row; do
  [ -n "$row" ] || continue
  sid="$(printf '%s' "$row" | cut -f2)"
  v="$(awk -v s="$sid" '$1 == s { print $2 }' "$0.verdicts" 2>/dev/null)"
  printf '%s\t%s\n' "$row" "${v:-INTERRUPTED}"
done
SH
  chmod +x "$CC_RESUME_CLASSIFY_BIN"

  # stub lr-select (session-sprawl consolidation seam, 2026-07-21). Default = identity pass-through:
  # every --candidate becomes a winner, so the launcher-wiring tests stay about boot-resume's seam
  # rather than re-testing lr-select's policy (which owns its own 21 cases in lr-select.bats).
  # A test that wants consolidation writes the winner TSV to .winners.
  export CC_RESUME_SELECT_BIN="$BATS_TEST_TMPDIR/stub-select"
  cat > "$CC_RESUME_SELECT_BIN" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >> "$0.log"
if [ -f "$0.winners" ]; then cat "$0.winners"; exit 0; fi
while [ $# -gt 0 ]; do
  case "$1" in
    --candidate) a="${2%%:*}"; rest="${2#*:}"; s="${rest%%:*}"; c="${rest#*:}"
                 printf '%s\t%s\t%s\t\n' "$a" "$s" "$c"; shift 2 ;;
    *) shift ;;
  esac
done
SH
  chmod +x "$CC_RESUME_SELECT_BIN"

  # stub keepalive: log the call, exit 0 (never start the real infinite loop in a test).
  export CC_KEEPALIVE_BIN="$BATS_TEST_TMPDIR/stub-keepalive"
  cat > "$CC_KEEPALIVE_BIN" <<'SH'
#!/bin/bash
printf 'started\n' >> "$0.log"
printf '%s\n' "${CC_KEEPALIVE_MARKERS-<unset>}" >> "$0.markers"
SH
  chmod +x "$CC_KEEPALIVE_BIN"

  # stub launchctl: report two loaded com.claude jobs (one up, one down) deterministically.
  export CC_LAUNCHCTL_BIN="$BATS_TEST_TMPDIR/stub-launchctl"
  cat > "$CC_LAUNCHCTL_BIN" <<'SH'
#!/bin/bash
# mimic `launchctl list`: PID<TAB>Status<TAB>Label
printf '%s\t%s\t%s\n' 4321 0 com.claude.dispatcher
printf '%s\t%s\t%s\n' - 0 com.claude.discovery
SH
  chmod +x "$CC_LAUNCHCTL_BIN"

  # stub transcript_mtime: default = "recent" (just before the fixed test boottime) so a registry
  # ghost passes the recency filter; a per-sid override file marks a session as OLD cruft.
  export MTIME_STUB_DIR="$BATS_TEST_TMPDIR/mtimes"; mkdir -p "$MTIME_STUB_DIR"
  export CC_TRANSCRIPT_MTIME_BIN="$BATS_TEST_TMPDIR/stub-mtime"
  cat > "$CC_TRANSCRIPT_MTIME_BIN" <<'SH'
#!/bin/bash
# args: <account> <sid> <cwd>
if [ -f "$MTIME_STUB_DIR/$2" ]; then cat "$MTIME_STUB_DIR/$2"; else echo 1784799900; fi
SH
  chmod +x "$CC_TRANSCRIPT_MTIME_BIN"

  # Restore v2 (W3 P3a-ii): the start gate reads load through sysctl, so a stub answers it — the
  # first lines of .loads in turn, then the last one; load 0.50 on 8 cores by default — or a case
  # would wait on the box's real load. The recycle log and teardown markers are fixtures too.
  export CC_SYSCTL_BIN="$BATS_TEST_TMPDIR/stub-sysctl"
  cat > "$CC_SYSCTL_BIN" <<'SH'
#!/bin/bash
case "$*" in
  *vm.loadavg*) n=$(cat "$0.n" 2>/dev/null || echo 0); echo $((n + 1)) > "$0.n"
                l="$(sed -n "$((n + 1))p" "$0.loads" 2>/dev/null)"; [ -n "$l" ] || l="$(tail -n 1 "$0.loads" 2>/dev/null)"
                echo "{ ${l:-0.50} 0.40 0.30 }" ;;
  *hw.ncpu*) echo 8 ;;
  *) exit 1 ;;
esac
SH
  chmod +x "$CC_SYSCTL_BIN"
  export CC_RESTORE_GATE_POLL_S=0
  export CC_HANDOFF_LOG="$BATS_TEST_TMPDIR/handoffs.jsonl" CC_TEARDOWN_DIR="$BATS_TEST_TMPDIR/teardown"
}

# reg_entry <sid> <startedAt_ms> <account-config-basename> [cwd] [name]
reg_entry() {
  local sid="$1" started="$2" acct="$3" cwd="${4:-/Users/x/Development/.worktrees/wt-$1}" name="${5:-wt-$1-PANE}"
  jq -n --arg p "PANE-$sid" --arg n "$name" --arg c "$cwd" --arg a "$acct" \
        --argjson s "$started" --arg sid "$sid" \
        '{paneUUID:$p,name:$n,cwd:$c,account:$a,pid:999999,startedAt:$s,session_id:$sid}' \
        > "$CC_REGISTRY_DIR/$sid.json"
}
# The keepalive is DETACHED into its own session (launchd reaps the job's group on exit), so its
# log lands asynchronously — wait for it rather than racing it.
keepalive_log() { local i=0; while [ ! -s "$CC_KEEPALIVE_BIN.markers" ] && [ "$i" -lt 30 ]; do sleep 0.1; i=$((i + 1)); done; cat "$CC_KEEPALIVE_BIN.markers" 2>/dev/null; }
notify_count() { [ -f "$CC_NOTIFY_BIN.calls" ] && wc -l < "$CC_NOTIFY_BIN.calls" | tr -d ' ' || echo 0; }
launch_count() { [ -f "$CC_RESUME_LAUNCH_BIN.log" ] && wc -l < "$CC_RESUME_LAUNCH_BIN.log" | tr -d ' ' || echo 0; }
marker() { cat "$CC_BOOT_RESUME_STATE_DIR/last-boot-epoch" 2>/dev/null || echo ""; }

@test "--help exits 0" {
  run bash "$SCRIPT" --help
  [ "$status" -eq 0 ]
}

# ── REGRESSION: parse the sec field, never the usec field, out of real sysctl output ──
# `sysctl -n kern.boottime` → `{ sec = 1783830779, usec = 963957 } <date>`. A greedy `.*sec = `
# captures usec (963957 → epoch 1970) → every session looks post-boot → NO ghost ever detected.
@test "boottime parses the sec field (not usec) from real sysctl format" {
  unset CC_BOOTTIME_OVERRIDE
  export CC_SYSCTL_BIN="$BATS_TEST_TMPDIR/stub-sysctl"
  cat > "$CC_SYSCTL_BIN" <<'SH'
#!/bin/bash
echo "{ sec = 1783830779, usec = 963957 } Sat Jul 11 21:32:59 2026"
SH
  chmod +x "$CC_SYSCTL_BIN"
  run bash "$SCRIPT" --print-boottime
  [ "$status" -eq 0 ]
  [ "$output" = "1783830779" ]        # the sec field — NOT 963957 (usec)
}

# ── cruft filter: a ghost whose transcript is STALE (crashed long ago, never deregistered) is NOT
#    reported as open-at-boot, even though its startedAt predates the boot (the 81-cruft defect) ──
@test "an old-transcript ghost is excluded as cruft; a recent one is kept" {
  reg_entry fresh 1784700000000 claude-quaternary /Users/x/wt-fresh wt-fresh-P
  reg_entry crufty 1784600000000 claude-secondary /Users/x/wt-crufty wt-crufty-P
  echo 1000000000 > "$MTIME_STUB_DIR/crufty"          # 2001 → far older than boot-24h → cruft
  export CC_BOOT_RESUME_MODE=page
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(notify_count)" -eq 1 ]
  grep -q 'wt-fresh-P'  "$CC_NOTIFY_BIN.log"           # recent transcript → reported
  ! grep -q 'wt-crufty-P' "$CC_NOTIFY_BIN.log" || false # stale transcript → filtered out
  grep -q '"n_open":1' "$CC_IDL"                       # exactly the fresh one
}

# ── idempotency: this boot already processed → abstain, no page ────────────────
@test "boot-epoch already processed → abstain, zero notifies" {
  mkdir -p "$CC_BOOT_RESUME_STATE_DIR"; echo "1784800000" > "$CC_BOOT_RESUME_STATE_DIR/last-boot-epoch"
  reg_entry aaa 1784700000000 claude-quaternary          # a ghost, but this boot is already handled
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(notify_count)" -eq 0 ]
  grep -q '"disposition":"abstained"' "$CC_IDL"
  grep -q 'already-processed' "$CC_IDL"
}

# ── reboot but nothing was open → no page, marker advanced ─────────────────────
@test "reboot, no sessions open at last boot → abstain, marker written, zero notifies" {
  reg_entry live 1784900000000 claude-next               # startedAt AFTER boot → live, not a ghost
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(notify_count)" -eq 0 ]
  grep -q '"disposition":"abstained"' "$CC_IDL"
  [ "$(marker)" = "1784800000" ]
}

# ── T-P16-7: reboot + ghosts, default page-mode → exactly ONE delta page ───────
@test "page-mode: two ghosts (+one live) → one page listing 2, launcher NOT called, marker set" {
  reg_entry g1 1784700000000 claude-quaternary /Users/x/Development/.worktrees/wt-alpha wt-alpha-P
  reg_entry g2 1784600000000 claude-secondary /Users/x/Development/reso-management-app wt-reso-P
  reg_entry live 1784900000000 claude-next               # post-boot live → must be excluded
  export CC_BOOT_RESUME_MODE=page
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(notify_count)" -eq 1 ]
  [ "$(launch_count)" -eq 0 ]                             # page-mode never resumes
  grep -qi 'boot' "$CC_NOTIFY_BIN.log"                    # it is a boot-delta page
  grep -q 'wt-alpha-P' "$CC_NOTIFY_BIN.log"
  grep -q 'wt-reso-P' "$CC_NOTIFY_BIN.log"
  ! grep -q 'wt-live' "$CC_NOTIFY_BIN.log" || false       # the live session is not in the delta
  grep -q '"disposition":"fired"' "$CC_IDL"
  grep -q '"mode":"page"' "$CC_IDL"
  grep -q '"n_open":2' "$CC_IDL"
  grep -q '"resumed":0' "$CC_IDL"
  [ "$(marker)" = "1784800000" ]
}

# ── idempotency across two logins in one boot: exactly one page total ──────────
@test "second run within the same boot → already-processed, still exactly ONE page" {
  reg_entry g1 1784700000000 claude-quaternary
  export CC_BOOT_RESUME_MODE=page
  run bash "$SCRIPT"; [ "$status" -eq 0 ]; [ "$(notify_count)" -eq 1 ]
  run bash "$SCRIPT"; [ "$status" -eq 0 ]
  [ "$(notify_count)" -eq 1 ]                             # NOT 2
  grep -q 'already-processed' "$CC_IDL"
}

# ── the 2026-10-02 incident: a clock step moved kern.boottime by ONE second, the exact-match marker
#    read it as a new boot, and a two-day-old roster was replayed into 15 panes. ──
@test "boottime jitters by 1 s with no uuid marker → same boot, abstain, zero notifies" {
  mkdir -p "$CC_BOOT_RESUME_STATE_DIR"; echo "1784800001" > "$CC_BOOT_RESUME_STATE_DIR/last-boot-epoch"
  reg_entry aaa 1784700000000 claude-quaternary
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(notify_count)" -eq 0 ]
  grep -q 'already-processed' "$CC_IDL"
}

@test "same boot uuid, boottime jittered → abstain; uuid decides even outside the epoch tolerance" {
  export CC_BOOTUUID_OVERRIDE=AAAA-1111
  mkdir -p "$CC_BOOT_RESUME_STATE_DIR"
  echo "1784790000" > "$CC_BOOT_RESUME_STATE_DIR/last-boot-epoch"   # 10 000 s off: epoch alone says NEW
  echo "AAAA-1111"  > "$CC_BOOT_RESUME_STATE_DIR/last-boot-uuid"
  reg_entry aaa 1784700000000 claude-quaternary
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(notify_count)" -eq 0 ]
  grep -q 'already-processed' "$CC_IDL"
}

@test "different boot uuid, epoch within tolerance → a NEW boot, one page, both markers advanced" {
  export CC_BOOTUUID_OVERRIDE=BBBB-2222 CC_BOOT_RESUME_MODE=page
  mkdir -p "$CC_BOOT_RESUME_STATE_DIR"
  echo "1784800001" > "$CC_BOOT_RESUME_STATE_DIR/last-boot-epoch"
  echo "AAAA-1111"  > "$CC_BOOT_RESUME_STATE_DIR/last-boot-uuid"
  reg_entry g1 1784700000000 claude-quaternary
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(notify_count)" -eq 1 ]
  [ "$(marker)" = "1784800000" ]
  [ "$(cat "$CC_BOOT_RESUME_STATE_DIR/last-boot-uuid")" = "BBBB-2222" ]
}

@test "pre-uuid marker for this boot → abstain and backfill the uuid marker" {
  export CC_BOOTUUID_OVERRIDE=CCCC-3333
  mkdir -p "$CC_BOOT_RESUME_STATE_DIR"; echo "1784800000" > "$CC_BOOT_RESUME_STATE_DIR/last-boot-epoch"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(cat "$CC_BOOT_RESUME_STATE_DIR/last-boot-uuid")" = "CCCC-3333" ]
}

# ── T-P16-2: resume-mode → launcher per ghost with MAPPED account alias + keepalive ──
@test "resume-mode: launcher called per ghost with config→reso alias mapped; keepalive started once; summary paged" {
  reg_entry g1 1784700000000 claude-quaternary /Users/x/wt-a aaa
  reg_entry g2 1784600000000 claude-secondary  /Users/x/wt-b bbb
  reg_entry g3 1784500000000 claude            /Users/x/wt-c ccc
  reg_entry g4 1784550000000 claude-tertiary   /Users/x/wt-d ddd
  export CC_BOOT_RESUME_MODE=resume
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(launch_count)" -eq 4 ]
  grep -q '^next4 ' "$CC_RESUME_LAUNCH_BIN.log"           # claude-quaternary → next4
  grep -q '^next2 ' "$CC_RESUME_LAUNCH_BIN.log"           # claude-secondary  → next2
  grep -q '^next '  "$CC_RESUME_LAUNCH_BIN.log"           # claude (mirror)   → next
  grep -q '^next3 ' "$CC_RESUME_LAUNCH_BIN.log"           # claude-tertiary   → next3
  [ -n "$(keepalive_log)" ]                               # keepalive started (all four INTERRUPTED)
  [ "$(wc -l < "$CC_KEEPALIVE_BIN.log" | tr -d ' ')" -eq 1 ]  # exactly once
  [ "$(notify_count)" -eq 1 ]                             # summary page still sent
  grep -q '"mode":"resume"' "$CC_IDL"
  grep -q '"resumed":4' "$CC_IDL"
}

# ── the launcher receives the session's real cwd + sid (so reso-resume-one can act) ──
@test "resume-mode: launcher args carry cwd and sid" {
  reg_entry sidX 1784700000000 claude-quaternary /Users/x/Development/.worktrees/wt-zeta wt-zeta-P
  export CC_BOOT_RESUME_MODE=resume
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -q '/Users/x/Development/.worktrees/wt-zeta' "$CC_RESUME_LAUNCH_BIN.log"
  grep -q 'sidX' "$CC_RESUME_LAUNCH_BIN.log"
}

# ── session-sprawl consolidation (2026-07-21): fire WINNERS, not ghosts ───────
@test "resume-mode: ghosts are routed through lr-select with the MAPPED account alias" {
  reg_entry g1 1784700000000 claude-quaternary /Users/x/wt-a aaa
  reg_entry g2 1784600000000 claude            /Users/x/wt-b bbb
  export CC_BOOT_RESUME_MODE=resume
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -q -- '--candidate next4:g1:/Users/x/wt-a' "$CC_RESUME_SELECT_BIN.log"
  grep -q -- '--candidate next:g2:/Users/x/wt-b'  "$CC_RESUME_SELECT_BIN.log"
  grep -q -- '--max-per-worktree 1' "$CC_RESUME_SELECT_BIN.log"   # the consolidation default
  grep -q -- '--max-total 4'        "$CC_RESUME_SELECT_BIN.log"
}

@test "resume-mode: N ghosts in one worktree fire only the selected winner (incident shape)" {
  # 4 ghosts, ONE worktree — the 2026-07-21 shape. lr-select returns a single winner.
  for g in g1 g2 g3 g4; do reg_entry "$g" 1784700000000 claude-quaternary /Users/x/wt-shared "$g"; done
  printf 'next4\tg3\t/Users/x/wt-shared\t\n' > "$CC_RESUME_SELECT_BIN.winners"
  export CC_BOOT_RESUME_MODE=resume
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(launch_count)" -eq 1 ]                               # NOT 4
  grep -q 'g3' "$CC_RESUME_LAUNCH_BIN.log"
  grep -q '"n_open":4' "$CC_IDL"                            # all four still DETECTED…
  grep -q '"resumed":1' "$CC_IDL"                           # …only one FIRED
}

@test "consolidation is surfaced in the page, never silent" {
  for g in g1 g2 g3 g4; do reg_entry "$g" 1784700000000 claude-quaternary /Users/x/wt-shared "$g"; done
  printf 'next4\tg3\t/Users/x/wt-shared\t\n' > "$CC_RESUME_SELECT_BIN.winners"
  export CC_BOOT_RESUME_MODE=resume
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -qF 'consolidated: 4 ghost(s) → 1 fired' "$CC_NOTIFY_BIN.log"
  grep -qF 'LISTED, not lost' "$CC_NOTIFY_BIN.log"
}

@test "a missing selector refuses to resume — never falls back to firing every ghost" {
  # The fallback that "works" is the incident itself. Fail loud, launch nothing, do NOT mark the
  # boot processed (same discipline as a missing launcher).
  reg_entry g1 1784700000000 claude-quaternary /Users/x/wt-a aaa
  reg_entry g2 1784600000000 claude-quaternary /Users/x/wt-a bbb
  export CC_BOOT_RESUME_MODE=resume
  export CC_RESUME_SELECT_BIN="$BATS_TEST_TMPDIR/does-not-exist"
  run bash "$SCRIPT"
  [ "$status" -eq 3 ]
  [ ! -f "$CC_RESUME_LAUNCH_BIN.log" ]                      # nothing launched
  grep -q 'no-resume-selector' "$CC_IDL"
  [ "$(marker)" != "1784800000" ]                           # boot NOT marked → a re-run retries
}

# ── NEVER DRAIN TO NOBODY: the no-role LADDER (backlog cae796cb1bfb) ───────────
# Rung 1 — the addressless fallback lands, so the retry is BOUNDED at one surfaced item.
# Pre-fix this case exited 4 with delivered:false and an un-advanced marker, i.e. it retried
# every ~5 min forever into launchd stderr; the assertions below invert exactly that.
@test "no desk role + a delta → filed via cc-backlog needs, delivered:true, marker ADVANCED" {
  rm -f "$CC_ROLES_DIR/desk"
  reg_entry g1 1784700000000 claude-quaternary
  export CC_BOOT_RESUME_MODE=page
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -q '"delivered":true' "$CC_IDL"
  grep -q '"channel":"backlog-needs"' "$CC_IDL"
  grep -q '"backlog_id":"beef1234cafe"' "$CC_IDL"
  grep -q '"reason":"no-desk-role"' "$CC_IDL"
  [ "$(marker)" = "1784800000" ]                          # bounded: a re-run must NOT re-page
  grep -q -- '--project claude-infrastructure' "$CC_BACKLOG_BIN.log"
  grep -q 'needs ' "$CC_BACKLOG_BIN.log"
  # classed AND receipted (row 12b4209cb7fc): the step text changes per boot, so each re-file rewrites a
  # live row's needs, and the class gate demands a receipt for that — the page file the row points at.
  grep -q -- '--class needs-human --receipt .*/undelivered-[0-9]*\.page' "$CC_BACKLOG_BIN.log"
}

# The page text itself must survive somewhere addressless — the backlog row is one line and POINTS
# at it. A row naming a file that was never written is a pointer to nothing.
@test "no desk role → the full delta text is written to <state>/undelivered-<boot>.page" {
  rm -f "$CC_ROLES_DIR/desk"
  reg_entry g1 1784700000000 claude-quaternary
  export CC_BOOT_RESUME_MODE=page
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ -s "$CC_BOOT_RESUME_STATE_DIR/undelivered-1784800000.page" ]
  grep -q 'boot-delta' "$CC_BOOT_RESUME_STATE_DIR/undelivered-1784800000.page"
  grep -qF "$CC_BOOT_RESUME_STATE_DIR/undelivered-1784800000.page" "$CC_BACKLOG_BIN.log"
}

# Rung 2 — the fallback ALSO fails ⇒ a17 S-7 is back in force. This is the case the pre-fix branch
# handled for every input; it must still hold for THIS one, or the fix trades a silent retry for a
# silent drop, which is strictly worse.
@test "no desk role AND cc-backlog fails → fail-loud rc 4, delivered:false, marker NOT advanced" {
  rm -f "$CC_ROLES_DIR/desk"
  touch "$CC_BACKLOG_BIN.fail"
  reg_entry g1 1784700000000 claude-quaternary
  export CC_BOOT_RESUME_MODE=page
  run bash "$SCRIPT"
  [ "$status" -eq 4 ]
  grep -q '"delivered":false' "$CC_IDL"
  grep -q '"fallback":"backlog-unavailable"' "$CC_IDL"
  [ "$(marker)" != "1784800000" ]                         # unbounded retry is CORRECT here
}

# A non-id on stdout is NOT a filing. cc-backlog can print a project warning (rc 0) and file nothing;
# accepting any exit-0 output as an id is how a fallback claims a delivery it never made.
@test "cc-backlog exits 0 but prints no id → treated as NOT filed (rc 4, marker NOT advanced)" {
  rm -f "$CC_ROLES_DIR/desk"
  printf 'cc-backlog: warning — unknown project\n' > "$CC_BACKLOG_BIN.out"
  reg_entry g1 1784700000000 claude-quaternary
  export CC_BOOT_RESUME_MODE=page
  run bash "$SCRIPT"
  [ "$status" -eq 4 ]
  grep -q '"fallback":"backlog-unavailable"' "$CC_IDL"
  [ "$(marker)" != "1784800000" ]
}

# The two causes reaching this branch are DIFFERENT and the record must separate them — a
# "no-desk-role" record over an unresolvable cc-notify sends the next reader at the wrong store.
@test "role present but cc-notify unresolvable → reason no-notify-bin, still filed durably" {
  export CC_NOTIFY_BIN="$BATS_TEST_TMPDIR/does-not-exist"
  reg_entry g1 1784700000000 claude-quaternary
  export CC_BOOT_RESUME_MODE=page
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -q '"reason":"no-notify-bin"' "$CC_IDL"
  grep -q '"delivered":true' "$CC_IDL"
  [ "$(marker)" = "1784800000" ]
}

# ── a worktree path containing a space must survive the candidate handoff ──────
@test "a cwd with spaces reaches lr-select as ONE candidate, not two argv entries" {
  reg_entry gs 1784700000000 claude-quaternary "/Users/x/My Dev Worktree" gs-name
  export CC_BOOT_RESUME_MODE=resume
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -qF -- '--candidate next4:gs:/Users/x/My Dev Worktree' "$CC_RESUME_SELECT_BIN.log"
  grep -qF 'My Dev Worktree' "$CC_RESUME_LAUNCH_BIN.log"
}

# ══ SOURCES: roster → shutdown tombstones → registry ghosts (2026-09-30) ══════════════════════════
# The 15:24 scripted reboot: 20 sessions live, 11 registry ghosts from earlier crashes, overlap 0 —
# a graceful shutdown runs every SessionEnd hook, which deleted the rows this script looked for.
# RED-proof: against the pre-change script the first case lists the stale ghost and neither roster
# session, and the tombstone cases see no tombstones at all.
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
stub_layout() { # <summary line>; a file .rc3=N makes the first N calls exit 3 (no live kitty)
  export CC_RESUME_LAYOUT_BIN="$BATS_TEST_TMPDIR/stub-layout"
  cat > "$CC_RESUME_LAYOUT_BIN" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >> "$0.log"; cat >> "$0.rows"
printf '%s\n' "${CC_ADMIT_LOAD_TERM:-on}" >> "$0.loadterm"
n=$(cat "$0.n" 2>/dev/null || echo 0); echo $((n + 1)) > "$0.n"
[ -f "$0.rc3" ] && [ "$n" -lt "$(cat "$0.rc3")" ] && exit 3
cat "$0.sum"
SH
  chmod +x "$CC_RESUME_LAYOUT_BIN"
  printf '%s\n' "$1" > "$CC_RESUME_LAYOUT_BIN.sum"
}
SUM_OK2='cc-resume-layout: verdict=ok launched=2 shed=0 failed=0 windows=1 fullscreen_ok=1 fullscreen_failed=0'

@test "roster: the sessions live at a scripted reboot are the delta, not the stale registry ghosts" {
  reg_entry gstale 1784700000000 claude-quaternary /Users/x/wt-stale STALE-GHOST
  roster 2026-09-30 1784799900 "[$(rrow r1 claude-quaternary /Users/x/wt-a ROSTER-ONE),$(rrow r2 claude-next /Users/x/wt-b ROSTER-TWO)]"
  export CC_BOOT_RESUME_MODE=page
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -q 'ROSTER-ONE' "$CC_NOTIFY_BIN.log"
  grep -q 'ROSTER-TWO' "$CC_NOTIFY_BIN.log"
  ! grep -q 'STALE-GHOST' "$CC_NOTIFY_BIN.log" || false
  grep -q 'source: roster reboot-2026-09-30' "$CC_NOTIFY_BIN.log"
  grep -q '"source":"roster"' "$CC_IDL"
  grep -q '"n_open":2' "$CC_IDL"
}

@test "roster: one from before the previous boot, or after this boot, is not this reboot's roster" {
  mkdir -p "$CC_BOOT_RESUME_STATE_DIR"; echo 1784790000 > "$CC_BOOT_RESUME_STATE_DIR/last-boot-epoch"
  roster old  1784780000 "[$(rrow o1 claude-next /Users/x/wt-o OLD-ROSTER)]"
  roster late 1784800100 "[$(rrow l1 claude-next /Users/x/wt-l LATE-ROSTER)]"
  reg_entry g1 1784795000000 claude-quaternary /Users/x/wt-g GHOST-ONE
  export CC_BOOT_RESUME_MODE=page
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  ! grep -q 'OLD-ROSTER\|LATE-ROSTER' "$CC_NOTIFY_BIN.log" || false
  grep -q 'GHOST-ONE' "$CC_NOTIFY_BIN.log"
  grep -q '"source":"registry"' "$CC_IDL"
}

@test "roster: of two in the window, the newest wins" {
  roster a 1784799000 "[$(rrow x1 claude-next /Users/x/wt-x EARLIER)]"
  roster b 1784799900 "[$(rrow y1 claude-next /Users/x/wt-y LATER)]"
  export CC_BOOT_RESUME_MODE=page
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -q 'LATER' "$CC_NOTIFY_BIN.log"
  ! grep -q 'EARLIER' "$CC_NOTIFY_BIN.log" || false
}

@test "roster: an in-window roster listing nobody is an answer — no page, ghosts NOT reported" {
  roster empty 1784799900 '[]'
  reg_entry g1 1784700000000 claude-quaternary
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(notify_count)" -eq 0 ]
  grep -q 'no-open-sessions' "$CC_IDL"
  grep -q '"source":"roster"' "$CC_IDL"
}

@test "tombstones: only the LAST burst before the boot is the shutdown; a pane closed earlier is not" {
  tomb closed 1784790000
  tomb t1 1784799800
  tomb t2 1784799803
  export CC_BOOT_RESUME_MODE=page
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -q 'T-t1' "$CC_NOTIFY_BIN.log"
  grep -q 'T-t2' "$CC_NOTIFY_BIN.log"
  ! grep -q 'T-closed' "$CC_NOTIFY_BIN.log" || false
  grep -q '"source":"tombstones"' "$CC_IDL"
}

@test "tombstones: kern.willshutdown evidence outranks the burst rule" {
  tomb flagged 1784795000 true
  tomb unflagged 1784799900 false
  export CC_BOOT_RESUME_MODE=page
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -q 'T-flagged' "$CC_NOTIFY_BIN.log"
  ! grep -q 'T-unflagged' "$CC_NOTIFY_BIN.log" || false
}

@test "tombstones: one older than the window falls through to the registry ghosts" {
  tomb ancient 1784700000
  reg_entry g1 1784795000000 claude-quaternary /Users/x/wt-g GHOST-ONE
  export CC_BOOT_RESUME_MODE=page
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  ! grep -q 'T-ancient' "$CC_NOTIFY_BIN.log" || false
  grep -q 'GHOST-ONE' "$CC_NOTIFY_BIN.log"
}

# ══ RESUME through --desktops, nudging only what the shutdown INTERRUPTED ═══════════════════════
@test "resume: roster rows skip consolidation — two live sessions in one checkout both open via --desktops" {
  roster r 1784799900 "[$(rrow r1 claude-quaternary /Users/x/shared ONE),$(rrow r2 claude-next /Users/x/shared TWO)]"
  stub_layout "$SUM_OK2"
  export CC_BOOT_RESUME_MODE=resume
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ ! -f "$CC_RESUME_SELECT_BIN.log" ]                               # no lr-select for a roster
  grep -qx -- '--desktops' "$CC_RESUME_LAYOUT_BIN.log"
  grep -q "^next4	r1	/Users/x/shared	" "$CC_RESUME_LAYOUT_BIN.rows"
  grep -q "^next	r2	/Users/x/shared	" "$CC_RESUME_LAYOUT_BIN.rows"
  [ "$(wc -l < "$CC_RESUME_LAUNCH_BIN.checks" | tr -d ' ')" -eq 2 ]   # both ownership-checked
  [ ! -f "$CC_RESUME_LAUNCH_BIN.log" ]                               # no per-session window
  grep -q -- '--boot-epoch 1784799900' "$CC_RESUME_CLASSIFY_BIN.log" # anchored on the SHUTDOWN
  grep -q '"resumed":2' "$CC_IDL"
  grep -q '"opener":"desktops"' "$CC_IDL"
  grep -q '"fullscreen_ok":1' "$CC_IDL"
}

@test "resume: only INTERRUPTED cwds reach the keepalive; an AT-REST session in the same cwd vetoes it" {
  roster r 1784799900 "[$(rrow a claude-next /x/a A),$(rrow b claude-next /x/b B),$(rrow c1 claude-next /x/c C1),$(rrow c2 claude-next /x/c C2)]"
  printf 'b AT-REST\nc2 AT-REST\n' > "$CC_RESUME_CLASSIFY_BIN.verdicts"
  stub_layout 'cc-resume-layout: verdict=ok launched=4 shed=0 failed=0 windows=1 fullscreen_ok=1 fullscreen_failed=0'
  export CC_BOOT_RESUME_MODE=resume
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(keepalive_log)" = "/x/a" ]
  grep -q '"interrupted":2' "$CC_IDL"
  grep -q '"at_rest":2' "$CC_IDL"
  grep -q '2 were cut off mid-turn' "$CC_NOTIFY_BIN.log"
}

@test "resume: nothing INTERRUPTED, or a failed classifier ⇒ no keepalive at all" {
  roster r 1784799900 "[$(rrow a claude-next /x/a A),$(rrow b claude-next /x/b B)]"
  touch "$CC_RESUME_CLASSIFY_BIN.fail"
  stub_layout "$SUM_OK2"
  export CC_BOOT_RESUME_MODE=resume
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  sleep 0.5
  [ ! -f "$CC_KEEPALIVE_BIN.log" ]
  grep -q '"interrupted":0' "$CC_IDL"
  grep -q '"resumed":2' "$CC_IDL"                                     # still restored
}

@test "resume: a session the ownership check holds (rc 5) is never handed to the layout" {
  roster r 1784799900 "[$(rrow a claude-next /x/a A),$(rrow b claude-next /x/b B)]"
  echo b > "$CC_RESUME_LAUNCH_BIN.held"
  stub_layout 'cc-resume-layout: verdict=ok launched=1 shed=0 failed=0 windows=1 fullscreen_ok=1 fullscreen_failed=0'
  export CC_BOOT_RESUME_MODE=resume
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -q '	a	' "$CC_RESUME_LAYOUT_BIN.rows"
  ! grep -q '	b	' "$CC_RESUME_LAYOUT_BIN.rows" || false
  grep -q '"resume_held":1' "$CC_IDL"
}

@test "resume: no live kitty at login ⇒ opens kitty ONCE, waits, then lays out" {
  roster r 1784799900 "[$(rrow a claude-next /x/a A),$(rrow b claude-next /x/b B)]"
  stub_layout "$SUM_OK2"
  echo 2 > "$CC_RESUME_LAYOUT_BIN.rc3"
  export CC_BOOT_RESUME_MODE=resume
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(cat "$CC_OPEN_BIN.log")" = "-a /Applications/kitty.app" ]   # by path, and never -n
  [ "$(cat "$CC_RESUME_LAYOUT_BIN.n")" -eq 3 ]
  grep -q '"opener":"desktops"' "$CC_IDL"
}

@test "resume: kitty never comes up ⇒ falls back to one launcher window per session" {
  roster r 1784799900 "[$(rrow a claude-next /x/a A),$(rrow b claude-next /x/b B)]"
  stub_layout "$SUM_OK2"
  echo 99 > "$CC_RESUME_LAYOUT_BIN.rc3"
  export CC_BOOT_RESUME_MODE=resume CC_BOOT_RESUME_KITTY_TRIES=2
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(launch_count)" -eq 2 ]
  grep -q '"opener":"windows"' "$CC_IDL"
  grep -q '"resumed":2' "$CC_IDL"
}

@test "resume: a window that did not go fullscreen is named in the page" {
  roster r 1784799900 "[$(rrow a claude-next /x/a A),$(rrow b claude-next /x/b B)]"
  stub_layout 'cc-resume-layout: verdict=degraded launched=2 shed=0 failed=0 windows=1 fullscreen_ok=0 fullscreen_failed=1'
  export CC_BOOT_RESUME_MODE=resume
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -q 'did not go fullscreen' "$CC_NOTIFY_BIN.log"
  grep -q '"fullscreen_failed":1' "$CC_IDL"
}

# ══ STEP 0 HEARTBEAT, ROSTER CHOICE AND EVENT MODE (W3 P3a-i, 2026-10-04) ═════════════════════════
# A hard power-off leaves no tombstone and the registry fallback caps at 4 sessions, so the newest
# heartbeat (one 300 s tick old at most) competes with the alarm roster by start epoch. Event mode is
# a restore inside the running boot: it must never touch the boot markers, or the next reboot reads
# as already handled. Event cases run under /bin/bash 3.2, the interpreter launchd uses.
hbeat() { # <uuid> <kitty-pid> <start> <roster-json> [hb.session.tsv line]
  local d="$CC_HEARTBEAT_DIR/$1/$2"
  mkdir -p "$d"; printf '%s' "$4" > "$d/hb.roster.json"; echo "$3" > "$d/hb.start"
  [ -z "${5:-}" ] || printf '%s\n' "$5" > "$d/hb.session.tsv"
}
dead_pid() { sleep 0 & local p=$!; wait "$p"; echo "$p"; }
markers_sum() { shasum "$CC_BOOT_RESUME_STATE_DIR/last-boot-epoch" "$CC_BOOT_RESUME_STATE_DIR/last-boot-uuid" 2>&1; }

@test "reboot: a heartbeat one tick old outranks an alarm roster taken earlier; sessions started after the tick join it" {
  roster alarm 1784790000 "[$(rrow a1 claude-next /x/a ALARM-ONE)]"
  hbeat UUID-PREV 4001 1784799900 "[$(rrow h1 claude-next /x/h1 HB-ONE),$(rrow h2 claude-tertiary /x/h2 HB-TWO)]"
  reg_entry late 1784799950000 claude-next /x/late LATE-REG
  reg_entry early 1784799000000 claude-next /x/early EARLY-REG
  export CC_BOOT_RESUME_MODE=page
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -q 'HB-ONE' "$CC_NOTIFY_BIN.log"
  grep -q 'HB-TWO' "$CC_NOTIFY_BIN.log"
  grep -q 'LATE-REG' "$CC_NOTIFY_BIN.log"
  ! grep -q 'ALARM-ONE\|EARLY-REG' "$CC_NOTIFY_BIN.log" || false
  grep -q 'source: heartbeat UUID-PREV/4001 at .* + 1 started after it' "$CC_NOTIFY_BIN.log"
  grep -q '"source":"heartbeat"' "$CC_IDL"
  grep -q '"n_open":3' "$CC_IDL"
}

@test "reboot: an alarm roster newer than every heartbeat still wins" {
  hbeat UUID-PREV 4001 1784799000 "[$(rrow h1 claude-next /x/h1 HB-ONE)]"
  roster alarm 1784799900 "[$(rrow a1 claude-next /x/a ALARM-ONE)]"
  export CC_BOOT_RESUME_MODE=page
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -q 'ALARM-ONE' "$CC_NOTIFY_BIN.log"
  ! grep -q 'HB-ONE' "$CC_NOTIFY_BIN.log" || false
  grep -q '"source":"roster"' "$CC_IDL"
}

@test "the .start pair: a two-line .start (kalloc appended) is read by its first field, and a start equal to the boot counts" {
  printf '%s' "[$(rrow r1 claude-next /x/r LEGACY-ONE)]" > "$CC_BOOT_RESUME_ROSTER_DIR/reboot-legacy.roster.json"
  printf '1784800000\n1784800000 kalloc1024_gb=6.00\n' > "$CC_BOOT_RESUME_ROSTER_DIR/reboot-legacy.start"
  export CC_BOOT_RESUME_MODE=page
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -q 'LEGACY-ONE' "$CC_NOTIFY_BIN.log"
  grep -q '"source":"roster"' "$CC_IDL"
}

@test "reboot: a heartbeat taken after this boot is not the roster of the boot before it" {
  hbeat UUID-NOW 4002 1784800100 "[$(rrow n1 claude-next /x/n NOW-ONE)]"
  reg_entry g1 1784795000000 claude-quaternary /x/g GHOST-ONE
  export CC_BOOT_RESUME_MODE=page
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  ! grep -q 'NOW-ONE' "$CC_NOTIFY_BIN.log" || false
  grep -q 'GHOST-ONE' "$CC_NOTIFY_BIN.log"
}

@test "step 0: an already-handled tick still takes the heartbeat; a new boot takes it only after reading the registry" {
  mkdir -p "$CC_BOOT_RESUME_STATE_DIR"; echo 1784800000 > "$CC_BOOT_RESUME_STATE_DIR/last-boot-epoch"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$CC_HB_SESSIONS_BIN.calls" | tr -d ' ')" -eq 1 ]
  rm -f "$CC_BOOT_RESUME_STATE_DIR/last-boot-epoch" "$CC_HB_SESSIONS_BIN.calls" "$CC_IDL"
  reg_entry g1 1784700000000 claude-quaternary /x/g OLD-GHOST
  touch "$CC_HB_SESSIONS_BIN.sweep"                                   # the real lister reaps these
  export CC_BOOT_RESUME_MODE=page
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -q 'OLD-GHOST' "$CC_NOTIFY_BIN.log"                             # read BEFORE the sweep ran
  [ "$(wc -l < "$CC_HB_SESSIONS_BIN.calls" | tr -d ' ')" -eq 1 ]
}

@test "event: bypasses same_boot even when the overridden uuid equals the marker, and never writes either boot marker" {
  mkdir -p "$CC_BOOT_RESUME_STATE_DIR"
  echo 1784800000 > "$CC_BOOT_RESUME_STATE_DIR/last-boot-epoch"; echo UUID-1 > "$CC_BOOT_RESUME_STATE_DIR/last-boot-uuid"
  export CC_BOOTUUID_OVERRIDE=UUID-1
  kp="$(dead_pid)"
  hbeat UUID-1 "$kp" 1784804900 "[$(rrow e1 claude-next /x/e1 EV-ONE),$(rrow e2 claude-next /x/e2 EV-TWO)]"
  before="$(markers_sum)"
  stub_layout "$SUM_OK2"
  run /bin/bash "$SCRIPT" --event 1784805000 --kind restart
  [ "$status" -eq 0 ]
  [ "$(markers_sum)" = "$before" ]
  [ -f "$CC_BOOT_RESUME_STATE_DIR/events/1784805000.done" ]
  grep -q "^next	e1	/x/e1	" "$CC_RESUME_LAYOUT_BIN.rows"
  grep -q '"event":1784805000,"kind":"restart"' "$CC_IDL"
  grep -q '"resumed":2' "$CC_IDL"
  grep -q 'kitty restart at' "$CC_NOTIFY_BIN.log"
  run /bin/bash "$SCRIPT" --event 1784805000 --kind restart          # the same event again
  [ "$status" -eq 0 ]
  [ "$(cat "$CC_RESUME_LAYOUT_BIN.n")" -eq 1 ]
  tail -1 "$CC_IDL" | grep -q 'already-processed'
  [ "$(markers_sum)" = "$before" ]
}

@test "event --plan-only prints every row and launches nothing: no probe, classifier, layout, open, page or marker" {
  export CC_BOOTUUID_OVERRIDE=UUID-1
  kp="$(dead_pid)"
  hbeat UUID-1 "$kp" 1784804900 "[$(rrow p1 claude-tertiary /x/p1 PLAN-ONE),$(rrow p2 claude-next /x/p2 PLAN-TWO)]" \
    "p1	claude-tertiary	m	e	auto	feat-p1	1"
  stub_layout "$SUM_OK2"
  run /bin/bash "$SCRIPT" --event 1784805000 --kind restart --plan-only
  [ "$status" -eq 0 ]
  [[ "$output" == *"row	next3	p1	/x/p1	feat-p1	PLAN-ONE"* ]] || [[ "$output" == *"	p1	/x/p1	feat-p1	PLAN-ONE"* ]] || false
  [[ "$output" == *"	p2	/x/p2	-	PLAN-TWO"* ]] || false
  [[ "$output" == *"verdict=planned rows=2 retired=0 launches=0"* ]] || false
  [ ! -f "$CC_RESUME_LAUNCH_BIN.checks" ] && [ ! -f "$CC_RESUME_LAUNCH_BIN.log" ] || false
  [ ! -f "$CC_RESUME_LAYOUT_BIN.log" ] && [ ! -f "$CC_RESUME_CLASSIFY_BIN.log" ] && [ ! -f "$CC_OPEN_BIN.log" ] || false
  [ "$(notify_count)" -eq 0 ]
  [ -z "$(ls "$CC_BOOT_RESUME_STATE_DIR/events" 2>/dev/null)" ]
  [ ! -f "$CC_BOOT_RESUME_STATE_DIR/last-boot-epoch" ]
  grep -q '"reason":"plan-only"' "$CC_IDL"
}

@test "event --kind crash restores the dead kitty's fleet over a live kitty's newer heartbeat; --kitty-pid names one" {
  export CC_BOOTUUID_OVERRIDE=UUID-1
  kp="$(dead_pid)"
  hbeat UUID-1 "$kp" 1784804000 "[$(rrow d1 claude-next /x/d1 DEAD-ONE)]"
  hbeat UUID-1 "$$" 1784804900 "[$(rrow l1 claude-next /x/l1 LIVE-ONE)]"
  run /bin/bash "$SCRIPT" --event 1784805000 --kind crash --plan-only
  [ "$status" -eq 0 ]
  [[ "$output" == *"DEAD-ONE"* ]] && [[ "$output" != *"LIVE-ONE"* ]] || false
  run /bin/bash "$SCRIPT" --event 1784805000 --kind crash --kitty-pid "$$" --plan-only
  [ "$status" -eq 0 ]
  [[ "$output" == *"LIVE-ONE"* ]] && [[ "$output" != *"DEAD-ONE"* ]]
}

@test "event with no heartbeat fails loud (rc 3) and never falls back to the registry or the alarm roster" {
  reg_entry g1 1784795000000 claude-quaternary /x/g GHOST-ONE
  roster alarm 1784799900 "[$(rrow a1 claude-next /x/a ALARM-ONE)]"
  run /bin/bash "$SCRIPT" --event 1784805000 --kind crash
  [ "$status" -eq 3 ]
  grep -q '"reason":"no-heartbeat"' "$CC_IDL"
  [ "$(notify_count)" -eq 0 ]
}

@test "bad event arguments exit 2 and touch nothing" {
  run bash "$SCRIPT" --event abc --kind restart;      [ "$status" -eq 2 ]
  run bash "$SCRIPT" --event 1784805000 --kind reboot; [ "$status" -eq 2 ]
  run bash "$SCRIPT" --plan-only;                       [ "$status" -eq 2 ]
  run bash "$SCRIPT" --bogus;                           [ "$status" -eq 2 ]
  [ ! -f "$CC_IDL" ]
}

# ══ RESTORE V2: CONTRACT COLUMNS 6-11, LEDGER, HEADROOM, CAPACITY (W3 P3a-ii, 2026-10-04) ═════════════
# Everything here runs behind --event or <state>/restore-v2. A roster says where a session WAS; the
# newest transcript says where it went since, so the account, model, effort and permission mode come
# from it, with the heartbeat's reading as the fallback. A later round of the same event never
# launches a sid twice, and the event is done only at shed=0 or after its deadline.
txn() { # <config-dir> <sid> <mtime YYYYMMDDhhmm> <jsonl lines...>
  local d="$HOME/.$1/projects/-x-$2" f; f="$d/$2.jsonl"; mkdir -p "$d"; shift 3
  : > "$f"; for l in "$@"; do printf '%s\n' "$l" >> "$f"; done
}
txn_at() { touch -t "$3" "$HOME/.$1/projects/-x-$2/$2.jsonl"; }
ASST='{"type":"assistant","timestamp":"2026-10-04T10:00:00Z","effort":"high","gitBranch":"feat-tx","message":{"model":"claude-opus-5-5","content":[]}}'
SYNTH='{"type":"assistant","timestamp":"2026-10-04T10:01:00Z","message":{"model":"<synthetic>","content":[]}}'
PMODE='{"type":"permission-mode","permissionMode":"plan"}'
row_of() { awk -F'\t' -v s="$2" '$2 == s' "$1"; }   # <rows file> <sid>
SUM_MAP1='cc-resume-layout: map sid=e1 wid=51 oswin=1
cc-resume-layout: verdict=ok launched=1 shed=1 failed=0 windows=1 fullscreen_ok=1 fullscreen_failed=0'
SUM_OK1='cc-resume-layout: map sid=e2 wid=52 oswin=1
cc-resume-layout: verdict=ok launched=1 shed=0 failed=0 windows=1 fullscreen_ok=1 fullscreen_failed=0'
v2_fleet() { # a dead kitty's heartbeat of e1 (claude-next) and e2 (claude-tertiary)
  export CC_BOOTUUID_OVERRIDE=UUID-1
  KP="$(dead_pid)"
  hbeat UUID-1 "$KP" 1784804900 "[$(rrow e1 claude-next /x/e1 EV-ONE),$(rrow e2 claude-tertiary /x/e2 EV-TWO)]" \
    "e2	claude-tertiary	claude-sonnet-5-5	medium	default	feat-e2	1"
}

@test "v2 event: 11 columns; the account is the newest transcript's; model, effort, mode from its last real records; empty cells padded" {
  v2_fleet
  unset CC_TRANSCRIPT_MTIME_BIN                                # the real mtime reader, over fixture HOME
  txn claude-next e1 202610040900 "$ASST"; txn_at claude-next e1 202610040900
  txn claude-tertiary e1 202610041000 "$ASST" "$SYNTH" "$PMODE"; txn_at claude-tertiary e1 202610041000
  stub_layout "$SUM_OK2"
  run /bin/bash "$SCRIPT" --event 1784805000 --kind crash
  [ "$status" -eq 0 ]
  r1="$(row_of "$CC_RESUME_LAYOUT_BIN.rows" e1)"; r2="$(row_of "$CC_RESUME_LAYOUT_BIN.rows" e2)"
  [ "$(printf '%s\n' "$r1" | awk -F'\t' '{ print NF }')" -eq 11 ]
  [ "$(printf '%s\n' "$r2" | awk -F'\t' '{ print NF }')" -eq 11 ]
  # e1 moved to tertiary (next3) after the roster was taken; the synthetic record does not count.
  [ "$(printf '%s\n' "$r1" | awk -F'\t' '{ print $1, $4, $6, $7, $11 }')" = "next3 feat-tx claude-opus-5-5 high plan" ]
  # e2 has no transcript: the heartbeat's reading stands, branch included.
  [ "$(printf '%s\n' "$r2" | awk -F'\t' '{ print $1, $4, $6, $7, $11 }')" = "next3 feat-e2 claude-sonnet-5-5 medium default" ]
  [ "$(printf '%s\n' "$r1" | cut -f10)" = $'\037' ]            # prompt_file is P4's: padded, never empty
  grep -qx -- '--desktops --restore' "$CC_RESUME_LAYOUT_BIN.log"
  grep -qx off "$CC_RESUME_LAYOUT_BIN.loadterm"                # restore capacity mode: no per-launch load term
}

@test "v2 --plan-only prints 11 columns per row with group and slot from the heartbeat's kitty tree" {
  v2_fleet
  d="$CC_HEARTBEAT_DIR/UUID-1/$KP"
  jq '[.[] | .paneUUID = (if .session_id == "e1" then "30" else "31" end)]' "$d/hb.roster.json" > "$d/r" && mv "$d/r" "$d/hb.roster.json"
  echo '[{"id":7,"tabs":[{"id":1,"windows":[{"id":31},{"id":99},{"id":30}]}]}]' > "$d/hb.kitty-ls.json"
  run /bin/bash "$SCRIPT" --event 1784805000 --kind crash --plan-only
  [ "$status" -eq 0 ]
  rows="$(printf '%s\n' "$output" | grep '^row	')"
  [ "$(printf '%s\n' "$rows" | grep -c .)" -eq 2 ]
  [ "$(printf '%s\n' "$rows" | awk -F'\t' 'NF != 12' | grep -c .)" -eq 0 ]   # "row" + 11 contract columns
  [ "$(printf '%s\n' "$rows" | awk -F'\t' '$3 == "e2" { print $9, $10 }')" = "k${KP}w7 1" ]
  [ "$(printf '%s\n' "$rows" | awk -F'\t' '$3 == "e1" { print $9, $10, $7 }')" = "k${KP}w7 2 -" ]
  [[ "$output" == *"verdict=planned rows=2 retired=0 exhausted=0 no_model=1 launches=0"* ]] || false
  [ -z "$(ls "$CC_BOOT_RESUME_STATE_DIR/events" 2>/dev/null)" ]
}

@test "v2 ledger: a later round never relaunches a sid; map lines are kept; done only once nothing is shed" {
  v2_fleet
  export CC_RESTORE_NOW=1784805060                             # inside the event's deadline
  stub_layout "$SUM_MAP1"
  run /bin/bash "$SCRIPT" --event 1784805000 --kind crash
  [ "$status" -eq 0 ]
  ev="$CC_BOOT_RESUME_STATE_DIR/events/1784805000"
  [ "$(cat "$ev/launched")" = e1 ]
  grep -qx 'cc-resume-layout: map sid=e1 wid=51 oswin=1' "$CC_BOOT_RESUME_STATE_DIR/last-layout.map"
  grep -qx 'cc-resume-layout: map sid=e1 wid=51 oswin=1' "$ev/map"
  [ ! -f "$CC_BOOT_RESUME_STATE_DIR/events/1784805000.done" ]   # one row was shed
  [ "$(notify_count)" -eq 1 ]
  grep -q 'this restore runs again for them' "$CC_NOTIFY_BIN.log"
  printf '%s\n' "$SUM_OK1" > "$CC_RESUME_LAYOUT_BIN.sum"
  run /bin/bash "$SCRIPT" --event 1784805000 --kind crash        # round 2
  [ "$status" -eq 0 ]
  [ "$(grep -c '	e1	' "$CC_RESUME_LAYOUT_BIN.rows")" -eq 1 ]   # e1 went to the layout once, ever
  [ "$(grep -c '	e2	' "$CC_RESUME_LAYOUT_BIN.rows")" -eq 2 ]
  [ -f "$CC_BOOT_RESUME_STATE_DIR/events/1784805000.done" ]
  [ "$(notify_count)" -eq 1 ]                                  # one page per event, not per round
  tail -n 1 "$CC_IDL" | grep -q '"ledger_skipped":1'
  tail -n 1 "$CC_IDL" | grep -q '"channel":"already-paged"'
  [ "$(sort "$ev/launched" | tr '\n' ' ')" = "e1 e2 " ]
}

@test "v2: past the event's deadline a shed row no longer holds the event open" {
  v2_fleet
  export CC_RESTORE_NOW=$((1784805000 + 1801))
  stub_layout "$SUM_MAP1"
  run /bin/bash "$SCRIPT" --event 1784805000 --kind crash
  [ "$status" -eq 0 ]
  [ -f "$CC_BOOT_RESUME_STATE_DIR/events/1784805000.done" ]
}

@test "v2 start gate: waits while load per core is over the gate, logging each reading; at its deadline it goes ahead" {
  v2_fleet
  printf '64.0\n64.0\n2.0\n' > "$CC_SYSCTL_BIN.loads"            # 8/core, 8/core, then 0.25/core
  stub_layout "$SUM_OK2"
  run /bin/bash "$SCRIPT" --event 1784805000 --kind crash
  [ "$status" -eq 0 ]
  log="$CC_BOOT_RESUME_STATE_DIR/events/1784805000/load.log"
  [ "$(grep -c 'gate=6' "$log")" -eq 3 ]
  tail -n 1 "$log" | grep -q 'per_core=0.25'
  grep -q '"gate":"open"' "$CC_IDL"
  rm -rf "$CC_BOOT_RESUME_STATE_DIR" "$CC_RESUME_LAYOUT_BIN".* "$CC_SYSCTL_BIN.n" "$CC_IDL" "$CC_NOTIFY_BIN".*
  printf '64.0\n' > "$CC_SYSCTL_BIN.loads"; stub_layout "$SUM_OK2"
  CC_RESTORE_GATE_MAX_S=0 run /bin/bash "$SCRIPT" --event 1784805000 --kind crash
  [ "$status" -eq 0 ]
  grep -q '"gate":"deadline"' "$CC_IDL"
  [ "$(cat "$CC_RESUME_LAYOUT_BIN.n")" -eq 1 ]                  # restored anyway
  grep -q 'stayed over 6 for the whole wait' "$CC_NOTIFY_BIN.log"
}

@test "v2 headroom: a row on an account at its weekly limit is restored, listed, and never reaches the keepalive" {
  v2_fleet
  export CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/stub-accounts"
  cat > "$CC_ACCOUNTS_BIN" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >> "$0.log"
echo '{"rows":[{"acct":"next","weekly_pct":100},{"acct":"next3","weekly_pct":20}]}'
SH
  chmod +x "$CC_ACCOUNTS_BIN"
  stub_layout "$SUM_OK2"
  run /bin/bash "$SCRIPT" --event 1784805000 --kind crash
  [ "$status" -eq 0 ]
  grep -qx -- '--json --max-wait 0' "$CC_ACCOUNTS_BIN.log"       # cache-only, read once
  [ "$(grep -c . "$CC_ACCOUNTS_BIN.log")" -eq 1 ]
  row_of "$CC_RESUME_LAYOUT_BIN.rows" e1 | grep -q .           # still restored
  [ "$(cat "$CC_BOOT_RESUME_STATE_DIR/events/1784805000/exhausted")" = e1 ]
  [ "$(keepalive_log)" = /x/e2 ]                               # both INTERRUPTED; only e2 is nudged
  grep -q '1 sit on account(s) at their weekly limit (next)' "$CC_NOTIFY_BIN.log"
}

@test "a reboot without the restore-v2 flag keeps 5 columns and no --restore; with the flag it is v2" {
  roster alarm 1784799900 "[$(rrow a1 claude-next /x/a ALARM-ONE)]"
  export CC_BOOT_RESUME_MODE=resume
  stub_layout "$SUM_OK2"
  run /bin/bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(awk -F'\t' '{ print NF }' "$CC_RESUME_LAYOUT_BIN.rows")" -eq 5 ]
  grep -qx -- '--desktops' "$CC_RESUME_LAYOUT_BIN.log"
  grep -qx on "$CC_RESUME_LAYOUT_BIN.loadterm"
  [ ! -e "$CC_BOOT_RESUME_STATE_DIR/events" ]
  rm -rf "$CC_BOOT_RESUME_STATE_DIR" "$CC_RESUME_LAYOUT_BIN".*; stub_layout "$SUM_OK2"
  mkdir -p "$CC_BOOT_RESUME_STATE_DIR"; touch "$CC_BOOT_RESUME_STATE_DIR/restore-v2"
  run /bin/bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(awk -F'\t' '{ print NF }' "$CC_RESUME_LAYOUT_BIN.rows")" -eq 11 ]
  grep -qx -- '--desktops --restore' "$CC_RESUME_LAYOUT_BIN.log"
  [ -f "$CC_BOOT_RESUME_STATE_DIR/events/boot-1784800000/load.log" ]
  [ "$(marker)" = 1784800000 ]
}
