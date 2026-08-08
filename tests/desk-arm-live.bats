#!/usr/bin/env bats
# desk-arm-live.sh — go-live actuator for waiting-recycle Stage 2: arms the monitoring desk's cwd
# --live under EVERY config root it may run under, so a config-dir migration or a state-dir wipe
# cannot silently strand the arm (the CFG-stranding root cause: an arm keyed by shasum("$CFG|$cwd")
# under $CFG/state is invisible to a desk running under a different $CFG).
#
# Coverage: multi-config LIVE arm (arm+live+brief per root, correct key), SHADOW omits the live
# file, --dry-run is inert, brief/ cwd validation exits 2, the loop-breaker cooldown survives a
# re-arm (landmine), and the default cwd resolves from the installed-hook symlink source.

setup() {
  # Fixture $HOME (rule 1) + the one non-$HOME seam the subject reaches (rule 5: waiting-recycle.sh
  # reads CC_TELEMETRY_DIR, default the ABSOLUTE /tmp/cc-telemetry, which a fixtured $HOME does not
  # redirect by one character). Both measured before being added: 8/8 with HOME pointed at an empty
  # dir. They are here so this suite can leave the host-suites partition and be judged by the tree.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_TELEMETRY_DIR="$BATS_TEST_TMPDIR/tel"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HELPER="$REPO/scripts/desk-arm-live.sh"
  export CC_ARM_WR="$REPO/hooks/waiting-recycle.sh"
  CFGA="$BATS_TEST_TMPDIR/cfgA"; CFGB="$BATS_TEST_TMPDIR/cfgB"
  export CC_ARM_CFGS="$CFGA $CFGB"
  DESK="$BATS_TEST_TMPDIR/desk"; mkdir -p "$DESK"
  BRIEF="$BATS_TEST_TMPDIR/brief.md"; printf 'You are the desk. Re-derive from disk.\n' > "$BRIEF"
  export CC_ARM_BRIEF="$BRIEF"
  # HERMETIC coordination root — pins WHICH KEY the delegated CLI writes under (2026-07-26).
  # `waiting-recycle.sh arm` resolves every sentinel through sentinel_for(), which keys on the desk
  # ROLE instead of the cwd when the ARMING process itself holds that role (57c4594d). It decides
  # that by comparing $CC_WR_COORD_DIR/cc-roles/desk against this process's own pane uuid. Left
  # unset those default to the REAL ~/.claude/cc-roles/desk and the REAL $ITERM_SESSION_ID — so the
  # suite's verdict depended on WHICH PANE RAN IT: green from any ordinary pane, RED from the desk's
  # own pane (where the landing gate normally runs), writing arm-<role-key> while asserting
  # arm-<cwd-key>. Both inputs are pinned here so the cwd-keyed contract below is deterministic; the
  # role-keyed branch is covered explicitly by its own test rather than inherited from the machine.
  export CC_WR_COORD_DIR="$BATS_TEST_TMPDIR/coord"; mkdir -p "$CC_WR_COORD_DIR/cc-roles"
  export CC_WR_UUID="ARM-UUID-NOT-THE-DESK"
}

# shasum key the desk's own hook invocation will look up for (cfg, cwd).
key_for() { printf '%s|%s' "$1" "$2" | shasum | cut -c1-16; }
# …and the ROLE-keyed key it looks up instead when the arming process holds the desk role.
rolekey_for() { printf '%s|role:%s' "$1" "${2:-desk}" | shasum | cut -c1-16; }

@test "live: arms arm+live+brief under EVERY config root with the (cfg,cwd) key" {
  run "$HELPER" --cwd "$DESK"
  [ "$status" -eq 0 ]
  for cfg in "$CFGA" "$CFGB"; do
    k="$(key_for "$cfg" "$DESK")"; d="$cfg/state/waiting-recycle"
    [ -f "$d/arm-$k" ]
    [ -f "$d/live-$k" ]                                   # LIVE ⇒ exec enabled
    [ -s "$d/brief-$k" ]                                  # brief seeded (FM-D: no task-less fire)
    diff -q "$d/brief-$k" "$BRIEF"
  done
}

@test "shadow: --shadow arms arm+brief but NOT the live file" {
  run "$HELPER" --cwd "$DESK" --shadow
  [ "$status" -eq 0 ]
  k="$(key_for "$CFGA" "$DESK")"; d="$CFGA/state/waiting-recycle"
  [ -f "$d/arm-$k" ]
  [ -s "$d/brief-$k" ]
  [ ! -f "$d/live-$k" ]
}

@test "dry-run: changes nothing on disk" {
  run "$HELPER" --cwd "$DESK" --dry-run
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "dry-run"
  [ ! -d "$CFGA/state" ]
  [ ! -d "$CFGB/state" ]
}

@test "validate: missing/empty brief → exit 2, no arm" {
  export CC_ARM_BRIEF="$BATS_TEST_TMPDIR/nope.md"
  run "$HELPER" --cwd "$DESK"
  [ "$status" -eq 2 ]
  [ ! -d "$CFGA/state" ]
}

@test "validate: non-existent --cwd → exit 2" {
  run "$HELPER" --cwd "$BATS_TEST_TMPDIR/does-not-exist"
  [ "$status" -eq 2 ]
}

@test "landmine: a re-arm does NOT clear the loop-breaker cooldown of an already-armed cwd" {
  export CC_ARM_CFGS="$CFGA"                              # single root keeps the assertion crisp
  run "$HELPER" --cwd "$DESK"; [ "$status" -eq 0 ]
  k="$(key_for "$CFGA" "$DESK")"; d="$CFGA/state/waiting-recycle"
  echo 1234567890 > "$d/cooldown-$k"                      # stand in for a fire's loop-breaker stamp
  run "$HELPER" --cwd "$DESK"; [ "$status" -eq 0 ]        # re-arm (successor-safe path)
  [ -f "$d/cooldown-$k" ]                                 # cooldown survived → loop-breaker intact
  [ "$(cat "$d/cooldown-$k")" = 1234567890 ]
}

@test "resolve: default cwd is the repo the installed hook symlinks from" {
  mkdir -p "$BATS_TEST_TMPDIR/main/hooks" "$BATS_TEST_TMPDIR/install/hooks"
  cp "$CC_ARM_WR" "$BATS_TEST_TMPDIR/main/hooks/waiting-recycle.sh"
  ln -s "$BATS_TEST_TMPDIR/main/hooks/waiting-recycle.sh" "$BATS_TEST_TMPDIR/install/hooks/waiting-recycle.sh"
  export CC_ARM_HOOK="$BATS_TEST_TMPDIR/install/hooks/waiting-recycle.sh"
  run "$HELPER"                                           # no --cwd → resolve from the symlink
  [ "$status" -eq 0 ]
  k="$(key_for "$CFGA" "$BATS_TEST_TMPDIR/main")"         # expect cwd == the symlink source root
  [ -f "$CFGA/state/waiting-recycle/arm-$k" ]
}

# POSITIVE CONTROL for the isolation added in setup(): proves the pinned (cc-roles, uuid) inputs are
# load-bearing rather than a convenient default. Un-pin them and this branch is what the machine
# silently supplied to every test above — arming FROM the desk's own pane. Both branches are now
# asserted, so neither the isolation nor the role-keying (57c4594d) can be dropped unnoticed.
@test "role: an arming session that HOLDS the desk role gets the ROLE-keyed sentinel, not the cwd one" {
  export CC_ARM_CFGS="$CFGA"                              # single root keeps the assertion crisp
  printf '%s\n' "$CC_WR_UUID" > "$CC_WR_COORD_DIR/cc-roles/desk"   # THIS process now holds the role
  run "$HELPER" --cwd "$DESK"
  [ "$status" -eq 0 ]
  rk="$(rolekey_for "$CFGA")"; ck="$(key_for "$CFGA" "$DESK")"
  d="$CFGA/state/waiting-recycle"
  [ "$rk" != "$ck" ]                                      # the two keys really are distinct
  [ -f "$d/arm-$rk" ]                                     # role-keyed ⇒ survives a desk cwd change
  [ -f "$d/live-$rk" ]
  [ -s "$d/brief-$rk" ]
  [ ! -f "$d/arm-$ck" ]                                   # …and the legacy cwd key is NOT written
}
