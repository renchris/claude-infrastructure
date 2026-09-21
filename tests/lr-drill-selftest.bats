#!/usr/bin/env bats
# tests/lr-drill.sh — the five-session DoD drill's PURE surface, red-proved.
# (LIMIT_RECOVER_100P W7.)
#
# 🚨 WHAT THIS SUITE CANNOT TEST, SAID FIRST. The drill's five fault arms all need the real thing:
# a real launcher to refuse on headroom, a real detached watcher to kill, a real composer to hold a
# draft, a real turn to queue behind, a real ranker over real accounts. None of that is reachable
# from a test, and a case that pretended otherwise would pass vacuously — which the wave brief calls
# worse than no drill at all. So the arms are OPERATOR-VERIFIED and say so in the wave report, and
# what is tested here is everything that decides whether the drill is SAFE and whether its verdicts
# MEAN anything: the argv refusals, the manifest provenance, the five verdict mappers against
# recorded stage output, the results evaluator, and the two ratchets that keep live actions behind
# one door.
#
# THE SUBJECT IS A SEAM (LR_DRILL_BIN) so the wave's mutation driver can run this identical suite
# against a mutant without touching the tree. It defaults to the repo's own copy.
#
# Files this suite covers: tests/lr-drill.sh · scripts/limit-recover/lr-fleet.sh (the results.tsv
# and `parked` vocabulary the router mapper reads) · scripts/limit-recover/lr-fire-resume.sh (the
# relaunch.rc the gate mapper reads) · scripts/handoff-fire.sh (the HELD:draft verdict the draft
# mapper reads) · bin/cc-lr (the fire the drill delegates to).

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SUBJ="${LR_DRILL_BIN:-$REPO/tests/lr-drill.sh}"

  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export LR_DRILL_STATE_DIR="$BATS_TEST_TMPDIR/drill"; mkdir -p "$LR_DRILL_STATE_DIR"
  export LR_STATE_DIR="$BATS_TEST_TMPDIR/lrstate"; mkdir -p "$LR_STATE_DIR"
  export CC_REGISTRY_DIR="$BATS_TEST_TMPDIR/registry"; mkdir -p "$CC_REGISTRY_DIR"
  export CC_PROJECTS_DIRS="$BATS_TEST_TMPDIR/projects"; mkdir -p "$CC_PROJECTS_DIRS"

  # The four ambient-input classes scripts/test-hermeticity-lint.sh enforces. Pinned in setup(),
  # never per-test: a per-test pin leaves every OTHER test in the file reading the live machine.
  export CC_FIRE_CAPACITY_GATE=off
  export CC_ADMIT_GATE=off
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/account-sweep.json"
  export CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/stubbin/claude-accounts"
  export CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/heal-lock"
  unset CC_PANE_CMD_DIR CC_PANE_CMD_INTERACTIVE CC_PANE_CMD

  # BELT, not the guarantee. Every pure verb leaves DRILL_ARMED at 0 so live_do refuses on its own;
  # these stubs mean that even a mutant which deletes that refusal cannot reach a real pane from a
  # test run. Each one exits 99 and records the attempt, so a case can assert nothing was tried.
  STUBBIN="$BATS_TEST_TMPDIR/stubbin"; mkdir -p "$STUBBIN"
  local v
  for v in it2 kitty osascript launchctl claude claude2 claude3 claude4 claude-accounts; do
    { echo '#!/usr/bin/env bash'
      printf '%s\n' "printf '%s %s\\n' \"\$(basename \"\$0\")\" \"\$*\" >> \"$BATS_TEST_TMPDIR/live-attempts.log\""
      echo 'exit 99'
    } > "$STUBBIN/$v"
    chmod +x "$STUBBIN/$v"
  done
  PATH="$STUBBIN:$PATH"; export PATH
  export IT2_BIN="$STUBBIN/it2"
  export CC_LR_BIN="$STUBBIN/cc-lr-absent"

  RUN=drill-fixture
  SIDS="aaaaaaaa-1111-4000-8000-00000000000a
bbbbbbbb-2222-4000-8000-00000000000b
cccccccc-3333-4000-8000-00000000000c
dddddddd-4444-4000-8000-00000000000d
eeeeeeee-5555-4000-8000-00000000000e"
}

# ── fixtures ───────────────────────────────────────────────────────────────────────────────────
# A manifest is built THROUGH the drill's own `--stamp` writer, never by a re-implementation of the
# format here: two writers of one format is how a check and the thing it checks drift apart
# (memory: sibling-auditors-must-share-the-state-model).
mk_manifest() { # [run] → path on stdout
  # TWO STATEMENTS, NOT ONE. `local a=$1 b="…$a…"` leaves b EMPTY: every argument of the `local`
  # builtin is word-expanded BEFORE the builtin runs, so "$a" reads the OUTER a (here, unset).
  # Measured on both /bin/bash 3.2 and bash 5.3 — and it cost this suite a false green, because
  # both calls then wrote ONE file named manifest-.tsv and the second silently replaced the first.
  local run="${1:-$RUN}" i=0 sid role arm
  local mf="$BATS_TEST_TMPDIR/manifest-$run.tsv"
  { echo '# lr-drill manifest v1'
    echo "run=$run"
    echo "account=next"
    printf '# sid\trole\tcwd\tpane\tarm\tdigest\n'
  } > "$mf"
  while IFS= read -r sid; do
    [ -n "$sid" ] || continue
    i=$((i + 1))
    case "$i" in
      1) role=shared;          arm=gate    ;;
      2) role=shared;          arm=draft   ;;
      3) role=shared,subagent; arm=queued  ;;
      4) role=worktree;        arm=watcher ;;
      5) role=worktree;        arm=router  ;;
    esac
    "$SUBJ" --stamp "$run" "$sid" "$role" "/tmp/cwd$i" "10$i" "$arm" >> "$mf"
  done <<< "$SIDS"
  printf '%s' "$mf"
}

stage() { # <name> → a fresh stage dir on stdout
  local d="$BATS_TEST_TMPDIR/stage-$1"; mkdir -p "$d"; printf '%s' "$d"
}

ev() { # <dir> <state> <detail> — one events.jsonl record in the shape lr_state_append writes
  printf '{"ts":"2026-09-21T00:00:00Z","state":"%s","stage":"x","detail":"%s"}\n' "$2" "$3" >> "$1/events.jsonl"
}

# ── the code region readers the two ratchets share ─────────────────────────────────────────────
# EXECUTABLE TEXT ONLY where the property is about behaviour (a comment cannot type into a pane),
# and the WHOLE FILE where the property is about the text itself (iron rule 7's proof in § 13 is a
# whole-file grep, and a ratchet with a comment exemption is a ratchet with a hole).
live_do_range() { # → "first last" line numbers of live_do's body
  local first last
  first="$(grep -n '^live_do() {' "$SUBJ" | head -1 | cut -d: -f1)"
  [ -n "$first" ] || return 1
  last="$(awk -v s="$first" 'NR > s && /^}$/ { print NR; exit }' "$SUBJ")"
  [ -n "$last" ] || return 1
  printf '%s %s' "$first" "$last"
}

# ══ ARGV — THE MUTUAL EXCLUSION IS A SAFETY PROPERTY ═══════════════════════════════════════════

@test "--all and --drill together are REFUSED by name, and nothing is created" {
  local mf; mf="$(mk_manifest)"
  run "$SUBJ" --all --drill "$mf"
  [ "$status" -eq 2 ]
  # THE TOKEN, not merely the rc. `--all` alone is independently refused, so a mutant that deletes
  # the mutual-exclusion clause still exits 2 — only the token separates them.
  [[ "$output" == *"REFUSED:mutually-exclusive"* ]] || false
  [ ! -e "$LR_DRILL_STATE_DIR/live.log" ]
  [ ! -e "$BATS_TEST_TMPDIR/live-attempts.log" ]
}

@test "--drill alone on a stamped manifest reaches preflight, not the mutual-exclusion refusal" {
  # THE OTHER ARM. Without this, inverting the exclusion condition (so that a bare --drill refuses)
  # is indistinguishable from the correct code: both refuse the two-flag case.
  local mf; mf="$(mk_manifest)"
  run "$SUBJ" --drill "$mf"
  [ "$status" -eq 5 ]
  [[ "$output" == *"REFUSED preflight"* ]] || false
  [[ "$output" != *"mutually-exclusive"* ]] || false
  [ ! -e "$BATS_TEST_TMPDIR/live-attempts.log" ]
}

@test "--all alone is refused and never widens to the census" {
  run "$SUBJ" --all
  [ "$status" -eq 2 ]
  [[ "$output" == *"REFUSED:all-unimplemented"* ]] || false
}

# ══ MANIFEST PROVENANCE — the path from this file to a keystroke in a REAL session ═════════════

@test "a stamped manifest this drill wrote is accepted, five rows" {
  local mf; mf="$(mk_manifest)"
  run "$SUBJ" --check-manifest "$mf"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c .)" -eq 5 ]
}

@test "a sid the drill did not stamp is REFUSED BY NAME" {
  local mf; mf="$(mk_manifest)"
  # The operator's real session, pasted in place of a seeded one. Its row keeps a valid-looking
  # digest column; what it cannot have is a stamp.
  sed -i.bak 's/^aaaaaaaa-1111-4000-8000-00000000000a/99999999-9999-4000-8000-999999999999/' "$mf"
  run "$SUBJ" --check-manifest "$mf"
  [ "$status" -eq 2 ]
  [[ "$output" == *"99999999"* ]] || false
  [[ "$output" == *"no seed stamp"* ]] || false
}

@test "a row whose digest does not match its stamp is REFUSED" {
  local mf; mf="$(mk_manifest)"
  sed -i.bak '5s/\(.*\)\t[0-9a-f]*$/\1\tdeadbeefdeadbeef/' "$mf"
  run "$SUBJ" --check-manifest "$mf"
  [ "$status" -eq 2 ]
  [[ "$output" == *"digest"* ]] || false
}

@test "a stamp belonging to another run is REFUSED" {
  local mf; mf="$(mk_manifest)"
  mk_manifest other >/dev/null
  # Same sid, stamped under a different run, and the manifest header still says drill-fixture.
  rm -f "$LR_DRILL_STATE_DIR/seeded/$RUN/aaaaaaaa-1111-4000-8000-00000000000a"
  cp "$LR_DRILL_STATE_DIR/seeded/other/aaaaaaaa-1111-4000-8000-00000000000a" \
     "$LR_DRILL_STATE_DIR/seeded/$RUN/aaaaaaaa-1111-4000-8000-00000000000a"
  run "$SUBJ" --check-manifest "$mf"
  [ "$status" -eq 2 ]
  [[ "$output" == *"another run"* ]] || false
}

@test "a file that merely contains the magic somewhere is REFUSED" {
  local mf; mf="$(mk_manifest)" other="$BATS_TEST_TMPDIR/pasted.tsv"
  { echo "notes someone kept"; cat "$mf"; } > "$other"
  run "$SUBJ" --check-manifest "$other"
  [ "$status" -eq 2 ]
  [[ "$output" == *"manifest magic"* ]] || false
}

@test "four stamped sessions are REFUSED — the drill is five, and a short drill claims more than it did" {
  local mf; mf="$(mk_manifest)"
  grep -v '^eeeeeeee' "$mf" > "$mf.short"
  mv "$mf.short" "$mf"
  run "$SUBJ" --check-manifest "$mf"
  [ "$status" -eq 2 ]
  [[ "$output" == *"the drill is 5 sessions"* ]] || false
}

@test "too few worktree sessions is REFUSED — and the clause is reached, not shadowed" {
  # The role is changed to one the counters do not recognise rather than to `shared`, so the
  # SHARED count stays at its correct 3 and the worktree clause is the one that fires. Flipping a
  # worktree to shared reds the earlier clause and would have proved nothing about this one.
  local mf; mf="$(mk_manifest)"
  sed -i.bak '$s/\tworktree\t/\tspare\t/' "$mf"
  run "$SUBJ" --check-manifest "$mf"
  [ "$status" -eq 2 ]
  [[ "$output" == *"in worktrees, the drill wants 2"* ]] || false
}

@test "too few shared-checkout sessions is REFUSED" {
  local mf; mf="$(mk_manifest)"
  sed -i.bak '5s/\tshared\t/\tspare\t/' "$mf"
  run "$SUBJ" --check-manifest "$mf"
  [ "$status" -eq 2 ]
  [[ "$output" == *"in the shared checkout, the drill wants 3"* ]] || false
}

@test "no in-flight subagent among the five is REFUSED" {
  local mf; mf="$(mk_manifest)"
  sed -i.bak 's/\tshared,subagent\t/\tshared\t/' "$mf"
  run "$SUBJ" --check-manifest "$mf"
  [ "$status" -eq 2 ]
  [[ "$output" == *"in-flight subagent"* ]] || false
}

@test "a duplicated arm is REFUSED" {
  local mf; mf="$(mk_manifest)"
  sed -i.bak 's/\tworktree\t\/tmp\/cwd5\t105\trouter\t/\tworktree\t\/tmp\/cwd5\t105\tgate\t/' "$mf"
  run "$SUBJ" --check-manifest "$mf"
  [ "$status" -eq 2 ]
  [[ "$output" == *"twice"* ]] || false
}

# ══ THE VERDICT MAPPERS, against recorded stage output ═════════════════════════════════════════

@test "arm (a) gate: rc 9 plus a headroom reason maps to FAILED:gate:headroom" {
  local d; d="$(stage gate)"
  echo 9 > "$d/relaunch.rc"; echo 1200 > "$d/gate.elapsed_ms"
  # THE REASON TEXT AS THE TREE ACTUALLY WRITES IT — it names the numbers and never the term
  # (scripts/lib/capacity-admit.sh passes the term name only to the IDL row). A fixture that
  # helpfully spelled `headroom` into this string would test a reason text nothing produces.
  ev "$d" FAILED "rc=9 — gate: capacity-admit: REFUSING resume — reclaimable 0.01GB < floor 4096GB (refusal 1 of 3; once the budget is spent the next evaluation ADMITS and pages)"
  run "$SUBJ" --verdict gate "$d"
  [ "$status" -eq 0 ]
  [ "$output" = "FAILED:gate:headroom" ]
}

@test "arm (a) gate: the term comes from the IDL row when one was collected" {
  # The authoritative source. When the drill captured capacity-admit's own `term` field, that is
  # what names the arm — the detail shape is only the fallback.
  local d; d="$(stage gate-idl)"
  echo 9 > "$d/relaunch.rc"; echo 800 > "$d/gate.elapsed_ms"
  echo segments > "$d/admit.term"
  ev "$d" FAILED "rc=9 — gate: capacity-admit: REFUSING resume — reclaimable 0.01GB < floor 4096GB"
  run "$SUBJ" --verdict gate "$d"
  [ "$status" -eq 0 ]
  [ "$output" = "FAILED:gate:segments" ]
}

@test "arm (a) gate: a reason naming no recognisable term is UNMEASURED, not headroom-by-default" {
  local d; d="$(stage gate-noterm)"
  echo 9 > "$d/relaunch.rc"; echo 800 > "$d/gate.elapsed_ms"
  ev "$d" FAILED "rc=9 — gate: something nobody has seen before"
  run "$SUBJ" --verdict gate "$d"
  [ "$status" -eq 4 ]
  [[ "$output" == *no-term-in-reason* ]] || false
}

@test "arm (a) gate: a refusal slower than 3s FAILS rather than passing on the term alone" {
  local d; d="$(stage gate-slow)"
  echo 9 > "$d/relaunch.rc"; echo 4500 > "$d/gate.elapsed_ms"
  ev "$d" FAILED "rc=9 — gate: capacity-admit: REFUSING resume — reclaimable 0.01GB < floor 4096GB"
  run "$SUBJ" --verdict gate "$d"
  [ "$status" -eq 1 ]
  [[ "$output" == *":slow:4500ms" ]] || false
}

@test "arm (a) gate: a DIFFERENT rc is not laundered into this arm" {
  local d; d="$(stage gate-rc)"
  echo 3 > "$d/relaunch.rc"; echo 900 > "$d/gate.elapsed_ms"
  ev "$d" FAILED "rc=3 — capacity-admit: REFUSING resume — reclaimable 0.01GB < floor 4096GB"
  run "$SUBJ" --verdict gate "$d"
  [ "$status" -eq 1 ]
  [ "$output" = "FAILED:gate:wrong-rc:3" ]
}

@test "arm (a) gate: no relaunch.rc is UNMEASURED, never a pass" {
  local d; d="$(stage gate-none)"
  run "$SUBJ" --verdict gate "$d"
  [ "$status" -eq 4 ]
  [[ "$output" == UNMEASURED:* ]] || false
}

@test "arm (b) watcher: stale on the next tick with no keystroke in the window" {
  local d; d="$(stage w)"
  echo 1000 > "$d/watcher.armed_at"; echo 2000 > "$d/watcher.killed_at"
  echo "STALE:boot" > "$d/reaper.state"
  printf '2500\ttyped after the watcher died\n' > "$d/keystrokes.log"
  run "$SUBJ" --verdict watcher "$d"
  [ "$status" -eq 0 ]
  [ "$output" = "STALE:watcher" ]
}

@test "arm (b) watcher: a keystroke WHILE the fixture watcher was alive convicts, whatever the reaper said" {
  local d; d="$(stage w2)"
  echo 1000 > "$d/watcher.armed_at"; echo 2000 > "$d/watcher.killed_at"
  echo "STALE:boot" > "$d/reaper.state"
  printf '1500\ttyped while it lived\n' > "$d/keystrokes.log"
  run "$SUBJ" --verdict watcher "$d"
  [ "$status" -eq 1 ]
  [[ "$output" == "FAILED:watcher:typed-while-alive:1" ]] || false
}

@test "arm (b) watcher: a reaper that never went STALE FAILS" {
  local d; d="$(stage w3)"
  echo 1000 > "$d/watcher.armed_at"; echo 2000 > "$d/watcher.killed_at"
  echo "RECOVERED" > "$d/reaper.state"
  run "$SUBJ" --verdict watcher "$d"
  [ "$status" -eq 1 ]
  [[ "$output" == FAILED:watcher:not-stale:* ]] || false
}

@test "arm (c) draft: HELD:draft with an EMPTY movement probe passes" {
  local d; d="$(stage dr)"
  echo 'HELD:draft' > "$d/precheck.verdict"; : > "$d/moved.txt"
  run "$SUBJ" --verdict draft "$d"
  [ "$status" -eq 0 ]
  [ "$output" = "HELD:draft" ]
}

@test "arm (c) draft: HELD:draft with a lock left behind FAILS — the arm is 'nothing moved', not 'it said HELD'" {
  local d; d="$(stage dr2)"
  echo 'HELD:draft' > "$d/precheck.verdict"
  printf 'lock\t/x/y.lock\n' > "$d/moved.txt"
  run "$SUBJ" --verdict draft "$d"
  [ "$status" -eq 1 ]
  [ "$output" = "FAILED:draft:moved:1" ]
}

@test "arm (c) draft: an UNPROBED movement set is UNMEASURED, not empty" {
  # The emptiness gate cannot tell "nothing moved" from "nobody looked", and the two demand
  # opposite actions (docs/lessons/empty-vs-no-surface.md).
  local d; d="$(stage dr3)"
  echo 'HELD:draft' > "$d/precheck.verdict"
  run "$SUBJ" --verdict draft "$d"
  [ "$status" -eq 4 ]
  [[ "$output" == *nothing-probed* ]] || false
}

@test "arm (d) queued: queued then engaged passes" {
  local d; d="$(stage q)"
  ev "$d" queued "enqueued behind a running turn"
  echo 1 > "$d/engaged.verdict"
  run "$SUBJ" --verdict queued "$d"
  [ "$status" -eq 0 ]
  [ "$output" = "queued->engaged" ]
}

@test "arm (d) queued: FAILED:submit anywhere in the log is the failure this arm exists to catch" {
  local d; d="$(stage q2)"
  ev "$d" queued "enqueued"
  ev "$d" FAILED:submit "no record of the prompt within 40s"
  echo 1 > "$d/engaged.verdict"
  run "$SUBJ" --verdict queued "$d"
  [ "$status" -eq 1 ]
  [ "$output" = "FAILED:submit" ]
}

@test "arm (d) queued: queued but never engaged FAILS" {
  local d; d="$(stage q3)"
  ev "$d" queued "enqueued"
  echo 0 > "$d/engaged.verdict"
  run "$SUBJ" --verdict queued "$d"
  [ "$status" -eq 1 ]
  [ "$output" = "FAILED:queued:never-engaged" ]
}

@test "arm (d) queued: an unreadable engagement verdict is UNMEASURED, not 'not engaged'" {
  local d; d="$(stage q4)"
  ev "$d" queued "enqueued"
  echo "?" > "$d/engaged.verdict"
  run "$SUBJ" --verdict queued "$d"
  [ "$status" -eq 4 ]
}

@test "arm (e) router: parked with the router's own reasons and nothing moved" {
  local d; d="$(stage r)"
  echo 'parked' > "$d/fleet.mech"
  echo 'no routable target' > "$d/fleet.note"
  echo 'next: recovery-weekly-thin; next2: recovery-5h-thin' > "$d/rank.stderr"
  : > "$d/moved.txt"
  run "$SUBJ" --verdict router "$d"
  [ "$status" -eq 0 ]
  [ "$output" = "PARKED:no-target" ]
}

@test "arm (e) router: a park with NO reasons FAILS — a park nobody can act on is not the target state" {
  local d; d="$(stage r2)"
  echo 'parked' > "$d/fleet.mech"
  echo 'no routable target' > "$d/fleet.note"
  : > "$d/rank.stderr"
  : > "$d/moved.txt"
  run "$SUBJ" --verdict router "$d"
  [ "$status" -eq 4 ]
  [[ "$output" == *no-router-reasons* ]] || false
}

@test "arm (e) router: a transplant that happened anyway FAILS" {
  local d; d="$(stage r3)"
  echo 'parked' > "$d/fleet.mech"
  echo 'no routable target' > "$d/fleet.note"
  echo 'next: recovery-weekly-thin' > "$d/rank.stderr"
  printf 'lock\t/x/y.lock\n' > "$d/moved.txt"
  run "$SUBJ" --verdict router "$d"
  [ "$status" -eq 1 ]
  [ "$output" = "FAILED:router:transplanted-anyway" ]
}

@test "an unknown arm is a usage error, not a verdict" {
  local d; d="$(stage u)"
  run "$SUBJ" --verdict banana "$d"
  [ "$status" -eq 3 ]
}

# ══ THE EVALUATOR ══════════════════════════════════════════════════════════════════════════════

mk_results() { # <verdict-for-every-row> → path
  local v="$1" n m
  local f="$BATS_TEST_TMPDIR/results-$v.tsv"
  : > "$f"
  while IFS=$'\t' read -r n m _; do
    printf '%s\t%s\t%s\tfixture\n' "$n" "$m" "$v" >> "$f"
  done < <("$SUBJ" --rows)
  printf '%s' "$f"
}

@test "--assert: twelve PASS rows is the only green" {
  local f; f="$(mk_results PASS)"
  run "$SUBJ" --assert "$f"
  [ "$status" -eq 0 ]
}

@test "--assert: one FAIL row is rc 1 and the row is named" {
  local f; f="$(mk_results PASS)"
  sed -i.bak '3s/PASS/FAIL/' "$f"
  run "$SUBJ" --assert "$f"
  [ "$status" -eq 1 ]
  [[ "$output" == *"row 3"* ]] || false
}

@test "--assert: UNMEASURED is a THIRD state — it is not folded into the pass" {
  local f; f="$(mk_results PASS)"
  sed -i.bak '7s/PASS/UNMEASURED/' "$f"
  run "$SUBJ" --assert "$f"
  [ "$status" -eq 4 ]
  [[ "$output" == *"UNMEASURED"* ]] || false
}

@test "--assert: a MISSING row cannot be a green — absence is not a pass" {
  local f; f="$(mk_results PASS)"
  grep -v '^9	' "$f" > "$f.x"
  mv "$f.x" "$f"
  run "$SUBJ" --assert "$f"
  [ "$status" -eq 3 ]
  [[ "$output" == *"MISSING"* ]] || false
}

@test "--assert: a duplicated row is rc 3, never counted twice into a green" {
  local f dup
  f="$(mk_results PASS)"
  # READ, THEN WRITE — never `head -1 "$f" >> "$f"`, which reads and appends to one file in one
  # pipeline and is undefined the moment the file outgrows a buffer.
  dup="$(head -1 "$f")"
  printf '%s\n' "$dup" >> "$f"
  run "$SUBJ" --assert "$f"
  [ "$status" -eq 3 ]
  [[ "$output" == *"twice"* ]] || false
}

@test "--assert: an unknown verdict word is rc 3, never a silent skip" {
  local f; f="$(mk_results PASS)"
  sed -i.bak '2s/PASS/probably-fine/' "$f"
  run "$SUBJ" --assert "$f"
  [ "$status" -eq 3 ]
}

@test "--rows is exactly the twelve assertions of PLAN_DRAFT section 13" {
  run "$SUBJ" --rows
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c .)" -eq 12 ]
}

# ══ THE TWO RATCHETS ═══════════════════════════════════════════════════════════════════════════

@test "RATCHET iron rule 7: the drill contains no source-control write verb, anywhere in the file" {
  run grep -cE 'git +(commit|push|merge|reset|checkout)' "$SUBJ"
  [ "$status" -ne 0 ] || [ "$output" = "0" ]
}

@test "RATCHET: no real-pane verb is reachable outside live_do" {
  local range first last offenders
  range="$(live_do_range)"
  first="${range%% *}"; last="${range##* }"
  [ -n "$first" ]
  [ -n "$last" ]
  [ "$last" -gt "$first" ]
  # WHOLE-FILE, WITH NO COMMENT PARSER. The first draft filtered comments out and a trailing
  # `# … kill -9 …` on a function's own header line walked straight through it — a comment
  # stripper is a parser, and a parser inside a safety ratchet is one more thing that can be
  # wrong in the permissive direction. So the property is the stricter and simpler one: these
  # tokens appear NOWHERE in the file except inside live_do, comments included. The drill's
  # prose says SIGKILL and "types into panes" instead, which costs nothing.
  offenders="$(grep -nE '(^|[^A-Za-z0-9_])(it2|osascript|launchctl|kitty @)|kill -9' "$SUBJ" \
               | awk -F: -v a="$first" -v b="$last" '$1 < a || $1 > b { print }' || true)"
  [ -z "$offenders" ] || { echo "reachable outside live_do:"; echo "$offenders"; false; }
}

@test "RATCHET: live_do's FIRST executable statement is the armed check" {
  local range first last body
  range="$(live_do_range)"
  first="${range%% *}"; last="${range##* }"
  body="$(sed -n "$((first + 1)),$((last - 1))p" "$SUBJ" \
          | grep -v '^[[:space:]]*#' | grep -v '^[[:space:]]*$' | head -1)"
  [[ "$body" == *DRILL_ARMED* ]] || false
}

@test "live_do REFUSES while unarmed — the behavioural half of the ratchet above" {
  # The ratchets prove the guard is PRESENT and FIRST. This proves it REFUSES, by calling the door
  # directly with the script sourced as a library. `LR_DRILL_NO_MAIN` is not a seam the drill has,
  # so the argv block is neutralised the way a library-less script must be: with no arguments, the
  # trailing `case` falls to `usage; exit 3` — which is why the source runs in a SUBSHELL and the
  # function is re-read from it there. Every recipe must come back 90 and touch nothing.
  local r out
  for r in pane-open pane-type pane-draft pane-read fire-recover proc-kill daemon-kick; do
    out="$(bash -c 'set -uo pipefail
                    eval "$(sed -n "/^live_do() {/,/^}$/p" "$1")"
                    DRILL_ARMED=0; DRILL_STATE="$2"
                    d_say() { printf "%s\n" "$*" >&2; }
                    live_do "$3" x y; echo "rc=$?"' _ "$SUBJ" "$LR_DRILL_STATE_DIR" "$r" 2>/dev/null)"
    [ "$out" = "rc=90" ] || { echo "recipe $r returned '$out', not the unarmed refusal"; false; }
  done
  # …and nothing was recorded or attempted: live_do appends to its log BEFORE acting, so an empty
  # log is evidence the refusal came first rather than after the fact.
  [ ! -e "$LR_DRILL_STATE_DIR/live.log" ]
  [ ! -e "$BATS_TEST_TMPDIR/live-attempts.log" ]
}

@test "no pure verb ever opens the live log" {
  "$SUBJ" --rows >/dev/null
  "$SUBJ" --check-manifest "$(mk_manifest)" >/dev/null
  "$SUBJ" --verdict gate "$(stage none)" >/dev/null 2>&1 || true
  [ ! -e "$LR_DRILL_STATE_DIR/live.log" ]
  [ ! -e "$BATS_TEST_TMPDIR/live-attempts.log" ]
}
