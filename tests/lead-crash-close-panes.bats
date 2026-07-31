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
  # Seam so the RED proof stays reproducible: point LCW_UNDER_TEST at the pre-fix watchdog
  # (git show origin/main:hooks/lead-crash-watchdog.sh) and (xiii)-(xvi) must FAIL.
  WD="${LCW_UNDER_TEST:-$REPO/hooks/lead-crash-watchdog.sh}"

  # Fixture $HOME — without it this suite would resolve the operator's REAL ~/.claude/bin/cc-teardown
  # and could close live panes.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude/bin"

  # ── DE-AMBIENT: pin every lever the subject reads, in SETUP, never per-test ──────────────────────
  # Rule-1 shape (scripts/test-hermeticity-lint.sh): a per-test pin leaves every OTHER test in the
  # file reading the operator's shell, which is the flake it exists to kill.
  #
  # These are not hypothetical seams. `~/.zshrc` sources `~/.claude/autonomy/watchdog.env`, which
  # carries `export LCW_ORPHAN_CLOSE=1` (armed 2026-07-29T20:35). EVERY shell that sources the
  # profile — bats included — therefore handed this suite an ARMED actuator, so the two DEFAULT-OFF
  # tests stopped testing the default and started testing this box: (iv) and (v) go red 4/4,
  # foreground and background band alike. Exactly the $HOME / CC_FIRE_CAPACITY_GATE class the
  # hermeticity ratchet already covers, on a lever it did not yet know about.
  unset LCW_ORPHAN_CLOSE                # DEFAULT-OFF must mean the DEFAULT, never this box's arming
  unset LEAD_CRASH_WATCHDOG_DISABLED    # ambient =1 exits(0) before any leg runs — green by no-op
  # The subject's OWN bounds (hooks/lead-crash-watchdog.sh lcw_bounded). Pinned for the same reason:
  # an ambient budget would silently outlast this suite's outer bound below and put the two back in
  # the wrong order. Every one stays BELOW $BOUND_S so the subject's graceful cut wins when it can.
  export LCW_TEARDOWN_TIMEOUT_S=20 LCW_HARVEST_SCAN_TIMEOUT_S=20 LCW_REPORT_READ_TIMEOUT_S=20
  # Account roots — hoisted out of (ix-b) for rule 1's reason verbatim. member_transcript's
  # strategy-2 fallback greps EVERY account's project corpus (6k+ transcripts on this box); unpinned,
  # any test that reaches harvest walks the operator's real corpus instead of this fixture.
  export CC_ACCOUNT_BASES="$BATS_TEST_TMPDIR/acct"; mkdir -p "$CC_ACCOUNT_BASES/projects"

  TEAM="$BATS_TEST_TMPDIR/teams/session-dead"
  mkdir -p "$TEAM/HARVEST"
  STATUS="$TEAM/HARVEST/status.tsv"
  PLAN="$TEAM/HARVEST/close-plan.tsv"

  # Spy cc-teardown: records every invocation, and its exit code is steerable per-test.
  # TD_SAY lets a test give the spy the REAL cc-teardown's *output* too, not just its rc. That
  # matters: rc 2 alone cannot distinguish "a safety gate declined" from "the actuator could not
  # even SEE the target", and a spy that only ever returned 0 is precisely why this leg's 100%
  # abstain stayed invisible through landing (memory: fixture-shape-parity-with-real-producer).
  TD="$BATS_TEST_TMPDIR/cc-teardown-spy"
  TD_LOG="$BATS_TEST_TMPDIR/teardown-calls.log"; : > "$TD_LOG"
  TD_RC="$BATS_TEST_TMPDIR/teardown.rc"; echo 0 > "$TD_RC"
  TD_SAY="$BATS_TEST_TMPDIR/teardown.say"; : > "$TD_SAY"
  cat > "$TD" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$TD_LOG"
cat "$TD_SAY" 2>/dev/null
exit "\$(cat "$TD_RC" 2>/dev/null || echo 0)"
EOF
  chmod +x "$TD"
  export LCW_TEARDOWN_BIN="$TD"

  # ── the OUTER BOUND. Resolved with the subject's own ladder (hooks/lead-crash-watchdog.sh:28-36)
  # so the two agree about what "no timeout(1)" means on a given box.
  BOUND_S="${LCW_TEST_BOUND_S:-60}"
  TB=""
  for _c in "$(command -v timeout 2>/dev/null || true)" "$(command -v gtimeout 2>/dev/null || true)" \
            /opt/homebrew/bin/timeout /usr/local/bin/timeout \
            /opt/homebrew/bin/gtimeout /usr/local/bin/gtimeout; do
    [ -n "$_c" ] && [ -x "$_c" ] && { TB="$_c"; break; }
  done
  # REFUSE rather than degrade. The subject's lcw_bounded falls back to an UNBOUNDED call when no
  # timeout(1) resolves — a defensible choice for a crash handler that must not lose the call, and
  # the wrong one here: running this suite unbounded is precisely what stalled the corpus. A skip is
  # legible in the TAP; a silent unbounded run is the failure wearing a green hat.
  [ -n "$TB" ] || skip "no timeout(1)/gtimeout(1) — refusing to run the subject UNBOUNDED (see run_wd)"
}

# run_wd <args…> — invoke the subject BOUNDED, exactly as a bare `run bash "$WD" …` otherwise would.
#
# WHY THE CALLER BOUNDS, when the subject already bounds itself: `lcw_bounded` wraps the watchdog's
# own external calls (cc-teardown → AppleEvents into iTerm2, the harvest greps, the transcript
# reader), but it DEGRADES to running them unbounded whenever no timeout(1) resolves — and it did
# not exist at all on 2026-07-29, when this file wedged the whole post-land corpus: 900s of ZERO TAP
# progress at 1565/2215, the run cut at 10800s, the stall attributed here at test (i), this file's
# first (`~/.claude/autonomy/postland/runner.log`; lcw_bounded landed later, in 70d7afe9). A bound
# the subject can degrade away is not this suite's guarantee. This one is.
#
# THE COST OF NOT HAVING IT is the whole point: an unbounded wedge emits no TAP line at all, so it
# takes the 649 later tests with it and leaves a verdict nobody can read. rc 124 fails ONE test, by
# name, with the cause on stdout. The subject's every entrypoint exits 0, so 124 is unambiguously
# the bound and never the subject's own verdict.
#
# GROUP-KILL, deliberately — `timeout` WITHOUT `--foreground`. It puts itself and the subject in a
# NEW process group and signals that GROUP, so a wedged GRANDCHILD is reaped with its parent. This
# was settled by measurement against a subject that logs and then wedges, because the intuitive
# choice is the wrong one: `--foreground` signals only the direct child, the grandchild survives
# holding an fd it inherited from bats, and bats then HANGS after emitting the failure — measured at
# the full outer bound, 30s/30s and 6/6 runs, i.e. `--foreground` reproduces the very corpus stall
# this helper exists to prevent (memory: fixture-lifetime-is-an-orphan-leak-bound). Group-kill exits
# clean in 3s with the TAP result intact. Group-kill does NOT endanger bats: the new process group is
# timeout's own, not the harness's.
# The capture goes to a FILE rather than through bats' `run` pipe, and `3>&-` closes bats' TAP fd, so
# nothing the subject spawns can hold the harness open even if the reap ever misses one.
# `</dev/null` closes the last half: the hook's main path parses its JSON with `INPUT=$(cat)`, so any
# future entrypoint falling through the argv dispatch would block on stdin forever rather than fail.
# status/output/lines are set exactly as bats' own `run` sets them (stderr merged, same as default).
run_wd() {
  local of="$BATS_TEST_TMPDIR/wd-run.out" rc=0 l
  : > "$of"
  "$TB" -k 3 "$BOUND_S" bash "$WD" "$@" >"$of" 2>&1 </dev/null 3>&- || rc=$?
  status="$rc"
  output="$(cat "$of")"
  lines=(); while IFS= read -r l; do lines+=("$l"); done < "$of"
  [ "$status" -ne 124 ] || {
    echo "BOUND FIRED: the watchdog exceeded ${BOUND_S}s and was cut — a seam WEDGED (not a slow box)."
    echo "  Do not raise LCW_TEST_BOUND_S to clear this; find the un-stubbed external call."
    # The subject's OWN last words, which is the diagnostic 2026-07-29 did not have: a stall that
    # emits no TAP line leaves nothing to read, and the wedge was never attributed to a single call.
    # `run` keeps whatever was written before the cut, so the last line names the leg it died in.
    local n="${#lines[@]}" start=0
    if [ "$n" -eq 0 ]; then
      echo "  --- the subject produced NO output before the cut: it wedged before its first log line ---"
    else
      # NOT `${lines[@]: -5}`. A negative array offset whose magnitude EXCEEDS the array length
      # expands to NOTHING in bash — so the usual "last 5" idiom printed a blank line for every
      # run with fewer than 5 lines, i.e. it was silently emptiest exactly when the subject died
      # early and the diagnostic mattered most. Caught only by checking the rendered output against
      # a subject that really did log before wedging (99 bytes captured, 2 lines, nothing printed).
      [ "$n" -gt 5 ] && start=$((n - 5))
      echo "  --- last output before the cut (names the leg) ---"
      printf '  %s\n' "${lines[@]:$start}"
    fi
    false
  }
}

row() { printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$5" >> "$STATUS"; }
calls() { wc -l < "$TD_LOG" | tr -d ' '; }

@test "(i) HARVEST-FIRST: no status.tsv ⇒ REFUSE, and cc-teardown is never invoked" {
  rm -f "$STATUS"
  run_wd --close-panes "$TEAM" sid-1
  [ "$status" -eq 0 ] || false
  [[ "$output" == *"REFUSE"* ]] || false
  [[ "$output" == *"harvest never ran"* ]] || false
  [ "$(calls)" -eq 0 ] || false
}

@test "(ii) a NO-TRANSCRIPT member is NEVER closed — its pane is the last copy of its report" {
  row "w-lost" "PANE-LOST" "NO-TRANSCRIPT" 0 ""
  LCW_ORPHAN_CLOSE=1 run_wd --close-panes "$TEAM" sid-1
  [ "$status" -eq 0 ] || false
  [[ "$output" == *"SKIP w-lost"* ]] || false
  [ "$(calls)" -eq 0 ] || false
  grep -q "SKIP-UNHARVESTED" "$PLAN" || false
}

@test "(iii) ARMED: a harvested member's pane is closed through cc-teardown with done-evidence" {
  row "w-ok" "PANE-OK" "HARVESTED" 4242 "/tmp/t.jsonl"
  LCW_ORPHAN_CLOSE=1 run_wd --close-panes "$TEAM" sid-1
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
  run_wd --close-panes "$TEAM" sid-1
  [ "$status" -eq 0 ] || false
  [ "$(calls)" -eq 0 ] || false
}

@test "(v) UNARMED IS NOT SILENT: the orphaned pane is still counted, logged and planned" {
  row "w-ok" "PANE-OK" "HARVESTED" 4242 "/tmp/t.jsonl"
  run_wd --close-panes "$TEAM" sid-1
  [[ "$output" == *"WOULD-CLOSE w-ok pane=PANE-OK"* ]] || false
  [[ "$output" == *"1 orphaned pane(s) left RUNNING"* ]] || false
  [[ "$output" == *"LCW_ORPHAN_CLOSE=1"* ]] || false      # names its own arming lever
  grep -q "WOULD-CLOSE(unarmed)" "$PLAN" || false
}

@test "(vi) cc-teardown DEFER (rc 10) is trusted — reported, not retried, not forced" {
  row "w-dirty" "PANE-D" "HARVESTED" 100 "/tmp/t.jsonl"
  echo 10 > "$TD_RC"
  LCW_ORPHAN_CLOSE=1 run_wd --close-panes "$TEAM" sid-1
  [ "$status" -eq 0 ] || false
  [ "$(calls)" -eq 1 ] || false                            # exactly once: no blind retry
  [[ "$output" == *"DEFER"* ]] || false
  [[ "$output" == *"work-unsafe"* ]] || false
  [[ "$output" == *"1 defer"* ]] || false
}

@test "(vii) cc-teardown FAIL LOUD (rc 5) is surfaced as a survivor, never a false success" {
  row "w-surv" "PANE-S" "HARVESTED" 100 "/tmp/t.jsonl"
  echo 5 > "$TD_RC"
  LCW_ORPHAN_CLOSE=1 run_wd --close-panes "$TEAM" sid-1
  [[ "$output" == *"FAIL LOUD"* ]] || false
  [[ "$output" == *"pane SURVIVED"* ]] || false
  [[ "$output" == *"0 torn down"* ]] || false              # must NOT be counted as reaped
}

@test "(viii) cc-teardown REFUSE (rc 2) is trusted and counted separately from a failure" {
  row "w-ref" "PANE-R" "HARVESTED" 100 "/tmp/t.jsonl"
  echo 2 > "$TD_RC"
  LCW_ORPHAN_CLOSE=1 run_wd --close-panes "$TEAM" sid-1
  [[ "$output" == *"REFUSE"* ]] || false
  [[ "$output" == *"1 refuse"* ]] || false
}

@test "(ix) the lead's own 'leader' sentinel and pane-less members are skipped, never torn down" {
  row "team-lead" "leader" "HARVESTED" 10 "/tmp/t.jsonl"
  row "w-inproc"  "-"      "HARVESTED" 10 "/tmp/t.jsonl"   # '-' = the writer's absent-pane placeholder
  LCW_ORPHAN_CLOSE=1 run_wd --close-panes "$TEAM" sid-1
  [ "$(calls)" -eq 0 ] || false
  [[ "$output" == *"no pane / in-process"* ]] || false
}

@test "(ix-b) the PRODUCER never emits an empty TSV field — `read` would shift the columns left" {
  # Fixture-shape parity: assert what harvest_team_reports LITERALLY writes, not a hand-made row.
  # An in-process member has no pane; an empty column there would be coalesced away by
  # `IFS=$'\t' read`, so the reader would take state="HARVESTED" as the PANE and tear down a
  # nonexistent target. The contract is a '-' placeholder, and this pins it at the source.
  # CC_ACCOUNT_BASES is pinned in setup() — per-test would leave the other tests on the real corpus.
  T2="$BATS_TEST_TMPDIR/teams/session-prod"; mkdir -p "$T2"
  cat > "$T2/config.json" <<'EOF'
{"teamName":"session-prod","members":[
  {"name":"team-lead","tmuxPaneId":"leader","cwd":"/nowhere"},
  {"name":"w-inproc","cwd":"/nowhere"}
]}
EOF
  run_wd --harvest-team "$T2" sid-p
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
  LCW_ORPHAN_CLOSE=1 run_wd --close-panes "$TEAM" sid-1
  [ "$(calls)" -eq 1 ] || false
}

@test "(xi) a mixed team closes only the harvested panes and leaves the unharvested one alive" {
  row "w-a" "PANE-A" "HARVESTED"     10 "/tmp/a.jsonl"
  row "w-b" "PANE-B" "NO-TRANSCRIPT"  0 ""
  row "w-c" "PANE-C" "EMPTY"          0 "/tmp/c.jsonl"
  LCW_ORPHAN_CLOSE=1 run_wd --close-panes "$TEAM" sid-1
  [ "$(calls)" -eq 2 ] || false
  grep -q "PANE-A" "$TD_LOG" || false
  grep -q "PANE-C" "$TD_LOG" || false
  ! grep -q "PANE-B" "$TD_LOG" || false
}

@test "(xii) cc-teardown unavailable ⇒ abstain and say so, never fall back to raw it2/osascript" {
  row "w-ok" "PANE-OK" "HARVESTED" 10 "/tmp/t.jsonl"
  # The empty value is the ENTIRE POINT of this test and must not be "fixed": the subject
  # distinguishes UNSET (resolve an actuator, up to the operator's real ~/.claude/bin/cc-teardown)
  # from SET-BUT-EMPTY (honored verbatim ⇒ actuator disabled). `LCW_TEARDOWN_BIN=''` would read the
  # same to the subject but hides the intent; the bare form is what a caller disabling the actuator
  # actually writes, so it is the form worth pinning.
  # shellcheck disable=SC1007
  LCW_TEARDOWN_BIN= LCW_ORPHAN_CLOSE=1 run_wd --close-panes "$TEAM" sid-1
  [ "$status" -eq 0 ] || false
  [[ "$output" == *"cc-teardown-unavailable"* ]] || false
  ! [[ "$output" == *"osascript"* ]] || false
}

# ── the INERTNESS signal (2026-07-29) ──────────────────────────────────────────────────────────────
# An assignee pane has NO session-registry row — 134 of 134 measured across every team dir on this
# machine — and cc-teardown resolved ONLY via that registry. So every real call came back
# REFUSE unknown-target, which test (viii) above pins as a *trusted* outcome. Net effect: this leg
# was built, tested, landed, and structurally incapable of closing a single pane, while reporting a
# clean run. These tests pin the two halves of the fix: pass the identity that makes resolution
# possible, and never let a blind actuator be mistaken for a safety verdict.

@test "(xiii) the assignee IDENTITY is passed — --assignee-of <dead lead> and its own sid" {
  row "w-ok" "PANE-OK" "HARVESTED" 4242 "/acct/projects/p/sess-abc123.jsonl"
  LCW_ORPHAN_CLOSE=1 run_wd --close-panes "$TEAM" sid-1
  [ "$(calls)" -eq 1 ] || false
  # without --assignee-of, cc-teardown can only ever answer unknown-target for an assignee pane
  grep -q -- "--assignee-of sid-1" "$TD_LOG" || false
  # the assignee's OWN sid keeps the operator-adoption belt ARMED; absent it, find_transcript ""
  # returns nothing and that whole safety gate silently no-ops (bypassed, not passed)
  grep -q -- "--assignee-sid sess-abc123" "$TD_LOG" || false
}

@test "(xiv) a member with no transcript path yields NO empty --assignee-sid flag" {
  # EMPTY state = the transcript was read and held no report, so it IS closable, but tpath may be
  # '-'. An empty flag value would shift cc-teardown's own argv parse.
  row "w-empty" "PANE-E" "EMPTY" 0 "-"
  LCW_ORPHAN_CLOSE=1 run_wd --close-panes "$TEAM" sid-1
  [ "$(calls)" -eq 1 ] || false
  ! grep -q -- "--assignee-sid *$" "$TD_LOG" || false
  grep -q -- "--assignee-of sid-1" "$TD_LOG" || false
}

@test "(xv) UNRESOLVED is NOT the trusted refuse bucket — a blind actuator reports BLIND" {
  row "w-ok" "PANE-OK" "HARVESTED" 4242 "/tmp/t.jsonl"
  echo 2 > "$TD_RC"
  # the REAL outcome, verbatim from cc-teardown's refuse path — verdict token line THEN the prose,
  # which is the shape record() + say() actually produce (memory: fixture-shape-parity).
  printf '%s\n%s\n' \
    "cc-teardown: verdict=REFUSE reason_kind=unknown-target exit=2 target=PANE-OK pane=- pid=-" \
    "cc-teardown: REFUSE reason_kind=unknown-target — unknown target 'PANE-OK' (exit 2)" > "$TD_SAY"
  LCW_ORPHAN_CLOSE=1 run_wd --close-panes "$TEAM" sid-1
  [ "$status" -eq 0 ] || false
  [[ "$output" == *"UNRESOLVED"* ]] || false
  [[ "$output" == *"close BLIND"* ]] || false
  [[ "$output" == *"STILL RUNNING"* ]] || false
  [[ "$output" == *"wiring failure, not a verdict"* ]] || false
  # and it must NOT be laundered into the refuse tally that reads as a clean run
  [[ "$output" == *"0 refuse"* ]] || false
  [[ "$output" == *"1 UNRESOLVED"* ]] || false
}

@test "(xvi) assignee-unproven is UNRESOLVED too — cannot prove identity ≠ gate declined" {
  row "w-ok" "PANE-OK" "HARVESTED" 4242 "/tmp/t.jsonl"
  echo 2 > "$TD_RC"
  printf '%s\n%s\n' \
    "cc-teardown: verdict=REFUSE reason_kind=assignee-unproven exit=2 target=PANE-OK pane=- pid=-" \
    "cc-teardown: REFUSE reason_kind=assignee-unproven — cannot prove pane hosts an assignee (exit 2)" > "$TD_SAY"
  LCW_ORPHAN_CLOSE=1 run_wd --close-panes "$TEAM" sid-1
  [[ "$output" == *"1 UNRESOLVED"* ]] || false
  [[ "$output" == *"close BLIND"* ]] || false
}

# ── the false-success class reaches THIS caller too (backlog 99f87bf7a6f7) ─────────────────────────
# LCW_ORPHAN_CLOSE=1 made this leg cc-teardown's first autonomous caller, and to an autonomous caller
# a false `exit 0` is indistinguishable from a real reap — the orphan survives forever while the log
# says TORN DOWN. cc-teardown now refuses instead of inventing a success; these pin that each new
# refusal reaches the LOUD bucket rather than the trusted one.

@test "(xvi-b) target-not-a-pane-uuid is UNRESOLVED — the actuator was handed an unanswerable key" {
  row "w-ok" "PANE-OK" "HARVESTED" 4242 "/tmp/t.jsonl"
  echo 2 > "$TD_RC"
  printf '%s\n%s\n' \
    "cc-teardown: verdict=REFUSE reason_kind=target-not-a-pane-uuid exit=2 target=gu2-seams pane=- pid=-" \
    "cc-teardown: REFUSE reason_kind=target-not-a-pane-uuid — 'gu2-seams' is not a pane UUID (exit 2)" > "$TD_SAY"
  LCW_ORPHAN_CLOSE=1 run_wd --close-panes "$TEAM" sid-1
  [[ "$output" == *"1 UNRESOLVED"* ]] || false
  [[ "$output" == *"target-not-a-pane-uuid"* ]] || false
  [[ "$output" == *"0 refuse"* ]] || false
}

@test "(xvi-c) absence-contradicted reports STILL OCCUPIED — a positive finding, not a blind spot" {
  row "w-ok" "PANE-OK" "HARVESTED" 4242 "/tmp/t.jsonl"
  echo 2 > "$TD_RC"
  printf '%s\n%s\n' \
    "cc-teardown: verdict=REFUSE reason_kind=absence-contradicted exit=2 target=PANE-OK pane=- pid=-" \
    "cc-teardown: REFUSE reason_kind=absence-contradicted — it2 omits pane 'PANE-OK' but pid(s) [44938] are still live in it; NOT gone (exit 2)" > "$TD_SAY"
  LCW_ORPHAN_CLOSE=1 run_wd --close-panes "$TEAM" sid-1
  [[ "$output" == *"STILL OCCUPIED"* ]] || false
  [[ "$output" == *"44938"* ]] || false
  # the outcome is the same as blind — still running, no gate judged it — so it must stay LOUD
  [[ "$output" == *"1 UNRESOLVED"* ]] || false
  [[ "$output" == *"0 refuse"* ]] || false
}

@test "(xvi-d) PRE-TOKEN SKEW: an older cc-teardown emitting only prose still lands in UNRESOLVED" {
  # `command -v cc-teardown` can resolve a copy this repo does not control. A token-only parse would
  # silently demote that skew into the trusted refuse bucket — quieter, and quiet is exactly wrong
  # for a wiring failure. This is the control that the fallback arm is not dead code.
  row "w-ok" "PANE-OK" "HARVESTED" 4242 "/tmp/t.jsonl"
  echo 2 > "$TD_RC"
  echo "cc-teardown: REFUSE reason_kind=assignee-unproven — cannot prove pane hosts an assignee (exit 2)" > "$TD_SAY"
  LCW_ORPHAN_CLOSE=1 run_wd --close-panes "$TEAM" sid-1
  [[ "$output" == *"1 UNRESOLVED"* ]] || false
  [[ "$output" == *"0 refuse"* ]] || false
}

@test "(xvii) a GENUINE policy refusal stays a trusted refuse — the split must cut both ways" {
  row "w-ok" "PANE-OK" "HARVESTED" 4242 "/tmp/t.jsonl"
  echo 2 > "$TD_RC"
  echo "cc-teardown: REFUSE — operator-adopted pane: real prompt 12s ago (exit 2)." > "$TD_SAY"
  LCW_ORPHAN_CLOSE=1 run_wd --close-panes "$TEAM" sid-1
  [[ "$output" == *"1 refuse"* ]] || false
  [[ "$output" == *"0 UNRESOLVED"* ]] || false
  ! [[ "$output" == *"close BLIND"* ]] || false
}
