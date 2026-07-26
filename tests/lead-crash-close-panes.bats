#!/usr/bin/env bats
# lead-crash-watchdog.sh — ORPHANED-PANE CLOSE (leg b). After the reports are off disk, each orphaned
# assignee's pane is closed through bin/cc-teardown — never raw it2/osascript, because only
# cc-teardown re-observes both legs and calls a surviving pane FAIL LOUD instead of a false success.
#
# Observed cost of not doing this (2026-07-26, team session-a3f68174): 8 assignees alive holding
# 3.4GB after their lead died, panes never closed.
#
# The two rules this suite exists to pin:
#   HARVEST-FIRST   no status.tsv ⇒ REFUSE outright; a NO-TRANSCRIPT member is never closed, because
#                   its pane is the last place its report could still be found.
#   DEFAULT-OFF     cc-teardown's header bars raw hook wiring (C10), so the close is armed only by
#                   LCW_ORPHAN_CLOSE=1 — but UNARMED IS NOT SILENT: the plan is still computed,
#                   logged and written, so orphaned panes stay visible and countable.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  WD="$REPO/hooks/lead-crash-watchdog.sh"

  # Fixture $HOME — without it this suite would resolve the operator's REAL ~/.claude/bin/cc-teardown
  # and could close live panes.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude/bin"

  TEAM="$BATS_TEST_TMPDIR/teams/session-dead"
  mkdir -p "$TEAM/HARVEST"
  STATUS="$TEAM/HARVEST/status.tsv"
  PLAN="$TEAM/HARVEST/close-plan.tsv"

  # Spy cc-teardown: records every invocation, and its exit code is steerable per-test.
  TD="$BATS_TEST_TMPDIR/cc-teardown-spy"
  TD_LOG="$BATS_TEST_TMPDIR/teardown-calls.log"; : > "$TD_LOG"
  TD_RC="$BATS_TEST_TMPDIR/teardown.rc"; echo 0 > "$TD_RC"
  cat > "$TD" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$TD_LOG"
exit "\$(cat "$TD_RC" 2>/dev/null || echo 0)"
EOF
  chmod +x "$TD"
  export LCW_TEARDOWN_BIN="$TD"
}

row() { printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$5" >> "$STATUS"; }
calls() { wc -l < "$TD_LOG" | tr -d ' '; }

@test "(i) HARVEST-FIRST: no status.tsv ⇒ REFUSE, and cc-teardown is never invoked" {
  rm -f "$STATUS"
  run bash "$WD" --close-panes "$TEAM" sid-1
  [ "$status" -eq 0 ] || false
  [[ "$output" == *"REFUSE"* ]] || false
  [[ "$output" == *"harvest never ran"* ]] || false
  [ "$(calls)" -eq 0 ] || false
}

@test "(ii) a NO-TRANSCRIPT member is NEVER closed — its pane is the last copy of its report" {
  row "w-lost" "PANE-LOST" "NO-TRANSCRIPT" 0 ""
  LCW_ORPHAN_CLOSE=1 run bash "$WD" --close-panes "$TEAM" sid-1
  [ "$status" -eq 0 ] || false
  [[ "$output" == *"SKIP w-lost"* ]] || false
  [ "$(calls)" -eq 0 ] || false
  grep -q "SKIP-UNHARVESTED" "$PLAN" || false
}

@test "(iii) ARMED: a harvested member's pane is closed through cc-teardown with done-evidence" {
  row "w-ok" "PANE-OK" "HARVESTED" 4242 "/tmp/t.jsonl"
  LCW_ORPHAN_CLOSE=1 run bash "$WD" --close-panes "$TEAM" sid-1
  [ "$status" -eq 0 ] || false
  [ "$(calls)" -eq 1 ] || false
  grep -q -- "PANE-OK" "$TD_LOG" || false
  grep -q -- "--done-evidence" "$TD_LOG" || false
  # the evidence must be POSITIVE and derived — it names the death evidence AND the harvest
  grep -q "DEAD (positive evidence" "$TD_LOG" || false
  grep -q "HARVESTED to" "$TD_LOG" || false
  [[ "$output" == *"TORN DOWN + effect-verified"* ]] || false
}

@test "(iv) DEFAULT-OFF: unarmed runs invoke cc-teardown ZERO times" {
  row "w-ok" "PANE-OK" "HARVESTED" 4242 "/tmp/t.jsonl"
  run bash "$WD" --close-panes "$TEAM" sid-1
  [ "$status" -eq 0 ] || false
  [ "$(calls)" -eq 0 ] || false
}

@test "(v) UNARMED IS NOT SILENT: the orphaned pane is still counted, logged and planned" {
  row "w-ok" "PANE-OK" "HARVESTED" 4242 "/tmp/t.jsonl"
  run bash "$WD" --close-panes "$TEAM" sid-1
  [[ "$output" == *"WOULD-CLOSE w-ok pane=PANE-OK"* ]] || false
  [[ "$output" == *"1 orphaned pane(s) left RUNNING"* ]] || false
  [[ "$output" == *"LCW_ORPHAN_CLOSE=1"* ]] || false      # names its own arming lever
  grep -q "WOULD-CLOSE(unarmed)" "$PLAN" || false
}

@test "(vi) cc-teardown DEFER (rc 10) is trusted — reported, not retried, not forced" {
  row "w-dirty" "PANE-D" "HARVESTED" 100 "/tmp/t.jsonl"
  echo 10 > "$TD_RC"
  LCW_ORPHAN_CLOSE=1 run bash "$WD" --close-panes "$TEAM" sid-1
  [ "$status" -eq 0 ] || false
  [ "$(calls)" -eq 1 ] || false                            # exactly once: no blind retry
  [[ "$output" == *"DEFER"* ]] || false
  [[ "$output" == *"work-unsafe"* ]] || false
  [[ "$output" == *"1 defer"* ]] || false
}

@test "(vii) cc-teardown FAIL LOUD (rc 5) is surfaced as a survivor, never a false success" {
  row "w-surv" "PANE-S" "HARVESTED" 100 "/tmp/t.jsonl"
  echo 5 > "$TD_RC"
  LCW_ORPHAN_CLOSE=1 run bash "$WD" --close-panes "$TEAM" sid-1
  [[ "$output" == *"FAIL LOUD"* ]] || false
  [[ "$output" == *"pane SURVIVED"* ]] || false
  [[ "$output" == *"0 torn down"* ]] || false              # must NOT be counted as reaped
}

@test "(viii) cc-teardown REFUSE (rc 2) is trusted and counted separately from a failure" {
  row "w-ref" "PANE-R" "HARVESTED" 100 "/tmp/t.jsonl"
  echo 2 > "$TD_RC"
  LCW_ORPHAN_CLOSE=1 run bash "$WD" --close-panes "$TEAM" sid-1
  [[ "$output" == *"REFUSE"* ]] || false
  [[ "$output" == *"1 refuse"* ]] || false
}

@test "(ix) the lead's own 'leader' sentinel and pane-less members are skipped, never torn down" {
  row "team-lead" "leader" "HARVESTED" 10 "/tmp/t.jsonl"
  row "w-inproc"  "-"      "HARVESTED" 10 "/tmp/t.jsonl"   # '-' = the writer's absent-pane placeholder
  LCW_ORPHAN_CLOSE=1 run bash "$WD" --close-panes "$TEAM" sid-1
  [ "$(calls)" -eq 0 ] || false
  [[ "$output" == *"no pane / in-process"* ]] || false
}

@test "(ix-b) the PRODUCER never emits an empty TSV field — `read` would shift the columns left" {
  # Fixture-shape parity: assert what harvest_team_reports LITERALLY writes, not a hand-made row.
  # An in-process member has no pane; an empty column there would be coalesced away by
  # `IFS=$'\t' read`, so the reader would take state="HARVESTED" as the PANE and tear down a
  # nonexistent target. The contract is a '-' placeholder, and this pins it at the source.
  export CC_ACCOUNT_BASES="$BATS_TEST_TMPDIR/acct"; mkdir -p "$BATS_TEST_TMPDIR/acct/projects"
  T2="$BATS_TEST_TMPDIR/teams/session-prod"; mkdir -p "$T2"
  cat > "$T2/config.json" <<'EOF'
{"teamName":"session-prod","members":[
  {"name":"team-lead","tmuxPaneId":"leader","cwd":"/nowhere"},
  {"name":"w-inproc","cwd":"/nowhere"}
]}
EOF
  run bash "$WD" --harvest-team "$T2" sid-p
  [ "$status" -eq 0 ] || false
  # the pane-less member's row must carry 5 tab-separated fields, none empty
  line=$(grep '^w-inproc' "$T2/HARVEST/status.tsv")
  [ "$(printf '%s' "$line" | awk -F'\t' '{print NF}')" -eq 5 ] || false
  [ "$(printf '%s' "$line" | awk -F'\t' '{print $2}')" = "-" ] || false
  [ "$(printf '%s' "$line" | awk -F'\t' '{print $3}')" = "NO-TRANSCRIPT" ] || false
}

@test "(x) an EMPTY harvest still permits close — the transcript was read and held no report" {
  # EMPTY is a PROVEN outcome (assignee died before its first turn), unlike NO-TRANSCRIPT.
  row "w-empty" "PANE-E" "EMPTY" 0 "/tmp/t.jsonl"
  LCW_ORPHAN_CLOSE=1 run bash "$WD" --close-panes "$TEAM" sid-1
  [ "$(calls)" -eq 1 ] || false
}

@test "(xi) a mixed team closes only the harvested panes and leaves the unharvested one alive" {
  row "w-a" "PANE-A" "HARVESTED"     10 "/tmp/a.jsonl"
  row "w-b" "PANE-B" "NO-TRANSCRIPT"  0 ""
  row "w-c" "PANE-C" "EMPTY"          0 "/tmp/c.jsonl"
  LCW_ORPHAN_CLOSE=1 run bash "$WD" --close-panes "$TEAM" sid-1
  [ "$(calls)" -eq 2 ] || false
  grep -q "PANE-A" "$TD_LOG" || false
  grep -q "PANE-C" "$TD_LOG" || false
  grep -q "PANE-B" "$TD_LOG" && false
  true
}

@test "(xii) cc-teardown unavailable ⇒ abstain and say so, never fall back to raw it2/osascript" {
  row "w-ok" "PANE-OK" "HARVESTED" 10 "/tmp/t.jsonl"
  LCW_TEARDOWN_BIN= LCW_ORPHAN_CLOSE=1 run bash "$WD" --close-panes "$TEAM" sid-1
  [ "$status" -eq 0 ] || false
  [[ "$output" == *"cc-teardown-unavailable"* ]] || false
  [[ "$output" == *"osascript"* ]] && false
  true
}
