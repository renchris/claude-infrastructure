#!/usr/bin/env bats
# cc-lid — clamshell-sleep toggle.
#
# THE CONTROL THAT MATTERS is `applied but the setting did not move` (below). cc-lid's
# verdict must come from a SECOND read of pmset, never from the exit code of the write it
# just issued — memory claimed-outcome-vs-checked-outcome. A liar-pmset that accepts the
# write and reports the old value must produce exit 4, not a cheerful success line.
#
# The second is `pmset unreadable ⇒ exit 3`, not `off`. Treating an unreadable instrument as
# "sleep is enabled" would render the ▶ block over a machine that is already awake, and — the
# expensive direction — would let `cc-lid off` claim it restored sleep it never read.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LID="$REPO/bin/cc-lid"
  D="$BATS_TEST_TMPDIR"
  echo 0 > "$D/state"

  # pmset stub: `-g` renders the SleepDisabled line; `-a disablesleep N` writes state.
  cat > "$D/pmset" <<'EOF'
#!/bin/bash
if [ "${1:-}" = "-g" ] && [ $# -eq 1 ]; then
  echo " SleepDisabled		$(cat "$STATE")"
  echo " sleep                1"
  exit 0
fi
if [ "${1:-}" = "-a" ] && [ "${2:-}" = "disablesleep" ]; then
  [ -n "${PMSET_LIES:-}" ] || echo "$3" > "$STATE"
  exit 0
fi
exit 1
EOF
  chmod +x "$D/pmset"
  export STATE="$D/state"

  # sudo stubs. CANNOT: `-n true` fails, as under a password prompt (and as under
  # hooks/validate-bash.sh, which denies sudo to an agent outright).
  printf '#!/bin/bash\nexit 1\n' > "$D/sudo-cannot"; chmod +x "$D/sudo-cannot"
  cat > "$D/sudo-can" <<'EOF'
#!/bin/bash
[ "${1:-}" = "-n" ] && exit 0
exec "$@"
EOF
  chmod +x "$D/sudo-can"

  export CC_LID_PMSET="$D/pmset" CC_LID_SUDO="$D/sudo-cannot"
}

@test "status reads the live setting, both ways" {
  run "$LID"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ENABLED (normal)"* ]] || false
  [[ "$output" == *"caffeinate does NOT cover this"* ]] || false
  echo 1 > "$D/state"
  run "$LID"
  [ "$status" -eq 0 ]
  [[ "$output" == *"DISABLED"* ]] || false
  [[ "$output" == *"persists across reboot"* ]]
}

@test "toggle from off renders the operator block for bit 1 and exits 10" {
  run "$LID" toggle
  [ "$status" -eq 10 ]
  [[ "$output" == *"▶ Run this:"* ]] || false
  [[ "$output" == *'`sudo pmset -a disablesleep 1`'* ]] || false
  # It must not have moved the setting behind the block it just printed.
  [ "$(cat "$D/state")" = 0 ]
}

@test "toggle from on renders bit 0" {
  echo 1 > "$D/state"
  run "$LID" toggle
  [ "$status" -eq 10 ]
  [[ "$output" == *'`sudo pmset -a disablesleep 0`'* ]]
}

@test "already in the requested state is exit 0 with no command block" {
  run "$LID" off
  [ "$status" -eq 0 ]
  [[ "$output" != *"▶ Run this:"* ]]
}

@test "with passwordless sudo it applies and verifies by re-reading" {
  CC_LID_SUDO="$D/sudo-can" run "$LID" on
  [ "$status" -eq 0 ]
  [ "$(cat "$D/state")" = 1 ]
  [[ "$output" == *"SleepDisabled=1"* ]] || false
  [[ "$output" != *"▶ Run this:"* ]]
}

@test "CONTROL: a write that does not move the setting fails closed (exit 4)" {
  PMSET_LIES=1 CC_LID_SUDO="$D/sudo-can" run "$LID" on
  [ "$status" -eq 4 ]
  [[ "$output" == *"still reads"* ]] || false
  [[ "$output" != *"now DISABLED"* ]]
}

@test "CONTROL: an unreadable pmset is 'unknown', never 'off'" {
  printf '#!/bin/bash\nexit 1\n' > "$D/pmset"
  run "$LID" on
  [ "$status" -eq 3 ]
  [[ "$output" == *"refusing to guess"* ]]
}

@test "--machine emits one parseable line carrying the resolved command" {
  run "$LID" on --machine
  [ "$status" -eq 10 ]
  [[ "$output" == "state=off want=on verdict=needs-sudo cmd=sudo pmset -a disablesleep 1" ]] || false
  run "$LID" off --machine
  [ "$status" -eq 0 ]
  [[ "$output" == *"verdict=satisfied"* ]]
}

@test "an unknown argument is a usage error, not a silent status" {
  run "$LID" enable-please
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown argument"* ]]
}
