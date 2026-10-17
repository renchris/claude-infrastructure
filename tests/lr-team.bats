#!/usr/bin/env bats
# lr-team.sh — the one live-member test (FLEET_V2 W6, D4.1), and its parity with the Python copy
# lr_recon/census.py is_member_argv over the shared 8-row fixture.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  # The agent-id fixture names lr-fire-resume.sh (a capacity-admit caller) in a ps line, which puts
  # this suite in the hermeticity lint's rule-7 scope; nothing here runs the gate, so pin it shut.
  export CC_ADMIT_GATE=off
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

# ── lr_agent_id_holders (teammate resurrection 2026-10-16, REPORT.md § 4.2 step 2) ───────────────
@test "lr_agent_id_holders: counts only live claude/claude.exe argv[0] carrying the adjacent --agent-id" {
  id="web-next16@session-3cbb68e5"
  snap="$(printf '%s\n' \
    "101 S /Users/x/.claude-293/node_modules/@anthropic-ai/claude-code/bin/claude.exe --agent-id $id --agent-name web-next16" \
    "102 S claude --resume s1 --agent-id $id" \
    "103 Z claude.exe --agent-id $id" \
    "104 S /bin/bash /x/scripts/limit-recover/lr-fire-resume.sh --extra-args --agent-id $id" \
    "105 S expect -c spawn claude --agent-id $id" \
    "106 S /x/bin/cc-close-attrib claude --agent-id $id" \
    "107 S claude --agent-id other@session-3cbb68e5" \
    "108 S claude --agent-id")"
  run bash -c "source '$TEAM'; lr_agent_id_holders '$id' \"\$1\"" _ "$snap"
  [ "$output" = "2" ]
  run bash -c "source '$TEAM'; lr_agent_id_holders '$id' \"\$1\" '101 999'" _ "$snap"
  [ "$output" = "1" ]
  run bash -c "source '$TEAM'; lr_agent_id_holders '' \"\$1\"" _ "$snap"
  [ "$output" = "0" ]
}

@test "lr_agent_id_holders: the live census is not matched by itself (the id rides in ENVIRON)" {
  id="probe-$$@session-nobody"
  run /bin/bash -c "source '$TEAM'; lr_agent_id_holders '$id'"
  [ "$status" -eq 0 ]; [ "$output" = "0" ]
}
