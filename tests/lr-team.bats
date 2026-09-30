#!/usr/bin/env bats
# lr-team.sh — the one live-member test (FLEET_V2 W6, D4.1), and its parity with the Python copy
# lr_recon/census.py is_member_argv over the shared 8-row fixture.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  REPO="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  TEAM="$REPO/scripts/limit-recover/lr-team.sh"
  FIX="$REPO/tests/fixtures/lr-team/members.tsv"
  SID="aaaaaaaa-0000-4000-8000-000000000001"
}

bash_verdict() { # $1=snapshot line → 1 member / 0 not
  # shellcheck disable=SC1090
  (source "$TEAM" && lr_team_members "$SID" "$1")
}

py_verdict() { # $1=snapshot line → 1 member / 0 not
  PYTHONPATH="$REPO/scripts/limit-recover" python3 - "$SID" "$1" <<'EOF'
import sys
from lr_recon import census as C
sid, line = sys.argv[1], sys.argv[2]
pid, stat, args = line.split(" ", 2)
print(1 if not stat.startswith("Z") and C.is_member_argv(args, sid) else 0)
EOF
}

@test "every fixture row: the bash test gives the expected verdict" {
  while IFS=$'\t' read -r want name line; do
    got="$(bash_verdict "$line")"
    [ "$got" = "$want" ] || {
      echo "bash: $name want $want got $got"
      return 1
    }
  done <"$FIX"
}

@test "every fixture row: the Python copy agrees with the bash test" {
  while IFS=$'\t' read -r want name line; do
    b="$(bash_verdict "$line")"
    p="$(py_verdict "$line")"
    [ "$b" = "$p" ] || {
      echo "parity: $name bash=$b python=$p"
      return 1
    }
    [ "$p" = "$want" ]
  done <"$FIX"
}

@test "the whole snapshot counts both members (real and named team)" {
  snap="$(cut -f3 "$FIX")"
  run bash -c "source '$TEAM'; lr_team_members '$SID' \"\$1\"" _ "$snap"
  [ "$output" = "2" ]
  run bash -c "source '$TEAM'; lr_has_live_teammate '$SID' \"\$1\"" _ "$snap"
  [ "$status" -eq 0 ]
  run bash -c "source '$TEAM'; lr_has_live_teammate bbbbbbbb-0000-4000-8000-000000000009 \"\$1\"" _ "$snap"
  [ "$status" -ne 0 ]
}

@test "a sid prefix is not the sid: adjacency needs the full token" {
  run bash -c "source '$TEAM'; lr_team_members aaaaaaaa \"\$1\"" _ "$(cut -f3 "$FIX")"
  [ "$output" = "0" ]
}

@test "the command form reads the snapshot seam" {
  cut -f3 "$FIX" >"$BATS_TEST_TMPDIR/snap"
  LR_TEAM_PS_SNAPSHOT="$BATS_TEST_TMPDIR/snap" run bash "$TEAM" count "$SID"
  [ "$output" = "2" ]
  LR_TEAM_PS_SNAPSHOT="$BATS_TEST_TMPDIR/snap" run bash "$TEAM" has "$SID"
  [ "$status" -eq 0 ]
  LR_TEAM_PS_SNAPSHOT="$BATS_TEST_TMPDIR/snap" run bash "$TEAM" has ""
  [ "$status" -ne 0 ]
  run bash "$TEAM"
  [ "$status" -eq 2 ]
}

@test "a raw-newline argv continuation is not a process line" {
  # the continuation's second field is prose, not a ps stat code
  snap="$(printf '%s\n%s' "419 S claude -p 'line one" "420 then claude.exe --parent-session-id $SID now'")"
  run bash -c "source '$TEAM'; lr_team_members '$SID' \"\$1\"" _ "$snap"
  [ "$output" = "0" ]
}

@test "runs under /bin/bash 3.2" {
  [ -x /bin/bash ] || skip "no /bin/bash"
  cut -f3 "$FIX" >"$BATS_TEST_TMPDIR/snap"
  LR_TEAM_PS_SNAPSHOT="$BATS_TEST_TMPDIR/snap" run /bin/bash "$TEAM" count "$SID"
  [ "$output" = "2" ]
}
