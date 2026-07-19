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
#   4. FAIL-LOUD: a delta with no reachable desk role does NOT mark the boot processed (so a re-run
#      retries — never let a wake drain to nobody, a17 S-7).
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

  # stub the resume launcher: log "<acct> <cwd> <sid> <branch>" per invocation, exit 0.
  export CC_RESUME_LAUNCH_BIN="$BATS_TEST_TMPDIR/stub-launch"
  cat > "$CC_RESUME_LAUNCH_BIN" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >> "$0.log"
SH
  chmod +x "$CC_RESUME_LAUNCH_BIN"

  # stub keepalive: log the call, exit 0 (never start the real infinite loop in a test).
  export CC_KEEPALIVE_BIN="$BATS_TEST_TMPDIR/stub-keepalive"
  cat > "$CC_KEEPALIVE_BIN" <<'SH'
#!/bin/bash
printf 'started\n' >> "$0.log"
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
}

# reg_entry <sid> <startedAt_ms> <account-config-basename> [cwd] [name]
reg_entry() {
  local sid="$1" started="$2" acct="$3" cwd="${4:-/Users/x/Development/.worktrees/wt-$1}" name="${5:-wt-$1-PANE}"
  jq -n --arg p "PANE-$sid" --arg n "$name" --arg c "$cwd" --arg a "$acct" \
        --argjson s "$started" --arg sid "$sid" \
        '{paneUUID:$p,name:$n,cwd:$c,account:$a,pid:999999,startedAt:$s,session_id:$sid}' \
        > "$CC_REGISTRY_DIR/$sid.json"
}
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
  ! grep -q 'wt-crufty-P' "$CC_NOTIFY_BIN.log"         # stale transcript → filtered out
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
  ! grep -q 'wt-live' "$CC_NOTIFY_BIN.log"                # the live session is not in the delta
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
  [ -f "$CC_KEEPALIVE_BIN.log" ]                          # keepalive started
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

# ── FAIL-LOUD: a delta with no desk role must NOT mark the boot processed ──────
@test "no desk role + a delta → fail-loud (non-zero), delivered:false, marker NOT advanced" {
  rm -f "$CC_ROLES_DIR/desk"
  reg_entry g1 1784700000000 claude-quaternary
  export CC_BOOT_RESUME_MODE=page
  run bash "$SCRIPT"
  [ "$status" -ne 0 ]
  grep -q '"delivered":false' "$CC_IDL"
  [ "$(marker)" != "1784800000" ]                         # a re-run must retry the page
}
