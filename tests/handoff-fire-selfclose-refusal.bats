#!/usr/bin/env bats
# handoff-fire.sh — the --terminal SELF-CLOSE REFUSAL, keyed on the at-retire stamp's FIELDS
# (exhaustive-drive 2026-09-08, wave W3-B1; measurement W2-B1).
#
# WHY THIS EXISTS. The ledger stamp (rank 5) annotates and may never refuse — its own comment
# deferred the refusal to "a measurement that has not been made". W2-B1 made it: 54 self-closes in
# 28 h, 44 carrying a frozen at-retire ledger, each candidate arm replayed against them.
#
#     UNLANDED>0   0 / 44   REMAINDER≠0   0 / 44   ⛔   3 / 44, and all three were RIGHT to retire
#
# So the guard is free on the arms it keeps and refuted on the one it drops.
#
# 🚨 THE CASE THAT MATTERS IS 3, AND IT IS THE ONLY ONE A PLAUSIBLE WRONG IMPLEMENTATION FAILS.
# Reading the ledger's RUNG instead of its FIELDS gives 5/44 = 11.4 % and the OPPOSITE verdict on
# the whole item. `🔧` is a compound — dirty ∨ gate-stale ∨ REMAINDER>0 ∨ FILED_MINE>0 ∨ DRAIN_SCOPE
# ∨ custody — and BOTH 🔧 retires in the measured window were raised by terms this rule never names.
# Cases 3 and 4 pin ⛔ and FILED_MINE-only 🔧 as PASSES; a rung-keyed implementation refuses both.
#
# THE UNIT CASES DRIVE hf_selfclose_ledger_refusal DIRECTLY, by sed-extraction — the technique case 3
# of handoff-fire-ledger-stamp.bats uses, for the same reason: the decision under test depends on
# four parsed fields and on nothing else, and a test that had to satisfy pane identity, teammate
# liveness and the origin class to reach one predicate would be testing those instead. Cases 1, 6 and
# 7 are the end-to-end half over a REAL git repo with a REAL unlanded commit driven through the REAL
# wrap-ledger.sh, so the fixture cannot certify itself.

setup() {
  export CC_FIRE_CAPACITY_GATE=off
  export CC_FIRE_HEADROOM_GATE=off
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HF="$REPO/scripts/handoff-fire.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_FIRED_DIR="$BATS_TEST_TMPDIR/cc-fired";       mkdir -p "$CC_FIRED_DIR"
  export CC_CUSTODY_DIR="$BATS_TEST_TMPDIR/custody";      mkdir -p "$CC_CUSTODY_DIR"
  export CC_REGISTRY_DIR="$BATS_TEST_TMPDIR/cc-registry"; mkdir -p "$CC_REGISTRY_DIR"
  export CC_MAILBOX_DIR="$BATS_TEST_TMPDIR/mailbox"
  export CC_COMMS_ALARM_DIR="$BATS_TEST_TMPDIR/comms-alarms"
  export CC_HANDOFF_ALARM_DIR="$BATS_TEST_TMPDIR/handoff-alarms"
  export CC_PROJECTS_DIRS="$BATS_TEST_TMPDIR/projects";   mkdir -p "$CC_PROJECTS_DIRS"
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/account-sweep.json"
  export CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/no-such-claude-accounts"
  export CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/heal-lock-"

  PANE="fake:REFU-0001"
  SID="99999999-8888-7777-6666-555555555555"
  MARKER="HANDOFF-ENGAGE-REFU-0001"

  # THE SUBJECT TREE: clean, level with origin/main. Identity is passed TRANSIENTLY (`git -c`) and
  # never written to a config — this repo shares one .git/config across ~100 linked worktrees, and a
  # `git -C "$EMPTY" config` is a documented no-op that re-authors commits in the CURRENT repo.
  WORK="$BATS_TEST_TMPDIR/work"; mkdir -p "$WORK"
  git init -q -b main "$WORK"
  echo landed > "$WORK/landed.txt"
  git -C "$WORK" stage landed.txt
  git -C "$WORK" -c user.email=t@example.com -c user.name=Refusal commit -qm landed
  git -C "$WORK" update-ref refs/remotes/origin/main HEAD
  git -C "$WORK" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main

  printf '{"paneUUID":"%s","cwd":"%s","firedBy":"ORIGINATOR","firedAt":"2026-09-08T18:00:00Z","selfRetire":true,"marker":"%s"}\n' \
    "$PANE" "$WORK" "$MARKER" > "$CC_FIRED_DIR/$PANE.json"
  printf '{"paneUUID":"%s","session_id":"%s","cwd":"%s"}\n' "$PANE" "$SID" "$WORK" \
    > "$CC_REGISTRY_DIR/$PANE.json"
  "$REPO/bin/cc-custody" open --cwd "$WORK" --target "$PANE" --marker "$MARKER" \
      --slug refusal-fixture --notify-back ORIGINATOR --originator-pane ORIGINATOR >/dev/null

  cd "$WORK" || return 1
}

# The one commit that makes this fixture's tree UNLANDED — kept a helper so the three end-to-end
# cases share exactly one definition of the state they disagree about.
strand_a_commit() {
  echo stranded > "$WORK/stranded.txt"
  git -C "$WORK" stage stranded.txt
  git -C "$WORK" -c user.email=t@example.com -c user.name=Refusal commit -qm "stranded — on this machine only"
}

# The predicate, sed-extracted. Deliberately NOT in setup(): on a tree without the fix the
# extraction fails, and a setup abort would make every case red for the same uninformative reason.
# Extracting per-case lets the three END-TO-END cases (1, 6, 7) report the assertion that actually
# distinguishes the two trees — "exited 0, not 8 (REFUSED)" — which is the red-proof worth reading.
extract_predicate() {
  FN="$BATS_TEST_TMPDIR/fn.sh"
  sed -n '/^hf_selfclose_ledger_refusal() {/,/^}/p' "$HF" > "$FN"
  grep -q '^hf_selfclose_ledger_refusal() {' "$FN" \
    || { echo "hf_selfclose_ledger_refusal is not extractable from $HF — the predicate does not exist"; false; }
}

# Drive the predicate over a fields record written verbatim.
verdict() { # stdin = the fields record
  extract_predicate
  cat > "$BATS_TEST_TMPDIR/fields"
  run bash -c '. "$1"; hf_selfclose_ledger_refusal "$2"; echo "rc=$?"' _ "$FN" "$BATS_TEST_TMPDIR/fields"
}

@test "1 UNLANDED>0 — a --terminal close over commits that exist on this machine only is REFUSED" {
  # END-TO-END, through the REAL wrap-ledger over a REAL unlanded commit. RED on origin/main: before
  # this change the same invocation retired, exit 0, and the branch went with the pane.
  strand_a_commit
  run bash "$HF" self-close --terminal --session-id "$PANE" --dry-run
  [ "$status" -eq 8 ] || { echo "a --terminal close over an unlanded commit exited $status, not 8 (REFUSED): $output"; false; }
  [[ "$output" == *"self-close REFUSED"* ]] || { echo "no refusal line: $output"; false; }
  # THE MESSAGE NAMES THE STAMP IT READ — the session, and the field it decided on — so the reason is
  # auditable from the pane rather than only from this suite.
  [[ "$output" == *"$SID"* ]]        || { echo "the refusal does not name the session it read: $output"; false; }
  [[ "$output" == *"UNLANDED=1"* ]]  || { echo "the refusal does not name the UNLANDED field: $output"; false; }
  [[ "$output" == *"/ship"* ]]       || { echo "the refusal does not name the command that clears it: $output"; false; }
  # THE DEBT MUST SURVIVE A REFUSED CLOSE: discharging the originator's custody row over a close that
  # did not happen would strand the wave silently — the very loss class this refusal prevents.
  if command -v jq >/dev/null 2>&1; then
    n="$(cat "$CC_CUSTODY_DIR"/*.jsonl 2>/dev/null | jq -r 'select(.kind=="return") | .kind' | wc -l | tr -d ' ')"
    [ "$n" = 0 ] || { echo "a REFUSED close discharged the custody row anyway ($n return rows)"; false; }
  fi
}

@test "2 REMAINDER≠0 — a --terminal close with the frozen DoD unmet is REFUSED" {
  verdict <<'F'
STAMP_READ=1
RUNG=🔧
REMAINDER=2
UNLANDED=0
F
  [[ "$output" == *"rc=1"* ]] || { echo "REMAINDER=2 did not refuse: $output"; false; }
  [[ "$output" == *"REMAINDER=2"* ]] || { echo "the reason does not name the field: $output"; false; }
}

@test "3 THE POLARITY CASE — ⛔ with UNLANDED=0 REMAINDER=0 PASSES (a rung-keyed guard fails here)" {
  # W2-B1's whole refutation. ⛔ fired 3/44 and all three were legitimate: each landed its commits,
  # filed the operator's class-C packet — which IS the deliverable a fired peer's brief asks for —
  # and retired. `BLOCKED` counts packets THIS SESSION filed, so on a peer its polarity is inverted.
  # Refusing here strands a pane on a question nobody on the box can answer, because the operator is
  # away — the premise of the entire programme.
  verdict <<'F'
STAMP_READ=1
RUNG=⛔
REMAINDER=0
UNLANDED=0
F
  [[ "$output" == *"rc=0"* ]] \
    || { echo "⛔ with clean fields was REFUSED — this implementation is keyed on the RUNG, not the fields: $output"; false; }
}

@test "4 a 🔧 raised only by FILED_MINE PASSES — the rung is a compound the rule never named" {
  # The second half of case 3, and the other measured 🔧 shape. Both 🔧 retires in the window were
  # raised by FILED_MINE=1 (DIRTY=0 AHEAD=0) or by the drain-scope arm; neither had REMAINDER>0.
  verdict <<'F'
STAMP_READ=1
RUNG=🔧
REMAINDER=0
UNLANDED=0
F
  [[ "$output" == *"rc=0"* ]] \
    || { echo "a FILED_MINE-only 🔧 was REFUSED — keyed on the rung, not on the fields: $output"; false; }
}

@test "5 an ABSENT or UNREAD stamp PASSES — a refusal on a non-answer strands the pane" {
  # 10 of the 54 measured retires carried no frozen ledger at all, so this is the common path.
  # Three shapes, one verdict: no file, a file the stamp wrote on an UNREAD path, and junk fields.
  extract_predicate
  run bash -c '. "$1"; hf_selfclose_ledger_refusal "$2"; echo "rc=$?"' _ "$FN" "$BATS_TEST_TMPDIR/nosuchfile"
  [[ "$output" == *"rc=0"* ]] || { echo "an ABSENT fields file refused: $output"; false; }
  verdict <<'F'
STAMP_READ=0
RUNG=
REMAINDER=
UNLANDED=
F
  [[ "$output" == *"rc=0"* ]] || { echo "STAMP_READ=0 (nobody looked) refused: $output"; false; }
  verdict <<'F'
STAMP_READ=1
RUNG=?
REMAINDER=?
UNLANDED=?
F
  [[ "$output" == *"rc=0"* ]] || { echo "non-numeric fields refused — only a POSITIVE disproof may: $output"; false; }
}

@test "6 the end-to-end UNREAD path still retires — an unresolvable sid never refuses a close" {
  # Case 5's end-to-end half, and the guard on the seam the refusal was bolted to: removing the
  # registry row is exactly the state a provisional row is in (measured 10 of 19 live rows), and the
  # close must reach the same exit it reaches over a clean ledger. The tree is UNLANDED here, so a
  # refusal that keyed on git rather than on the STAMP would fire and this case would go red.
  strand_a_commit
  rm -f "$CC_REGISTRY_DIR/$PANE.json"
  run bash "$HF" self-close --terminal --session-id "$PANE" --dry-run
  [ "$status" -eq 0 ] || { echo "an unstampable close was REFUSED ($status) — a non-answer must never refuse: $output"; false; }
  [[ "$output" == *"LEDGER AT RETIREMENT: UNREAD"* ]] || { echo "no UNREAD stamp on the unresolvable path: $output"; false; }
}

@test "7 --allow-unlanded is the deliberate-park escape — the same close then retires" {
  strand_a_commit
  run bash "$HF" self-close --terminal --session-id "$PANE" --dry-run
  [ "$status" -eq 8 ] || { echo "positive control failed: the unlanded close did not refuse ($status)"; false; }
  run bash "$HF" self-close --terminal --session-id "$PANE" --allow-unlanded --dry-run
  [ "$status" -eq 0 ] || { echo "--allow-unlanded did not clear the refusal ($status): $output"; false; }
  # An unretireable pane is a worse failure than an unannotated one, so the escape must exist; but it
  # must not silence the stamp, or a deliberate park becomes indistinguishable from a clean close.
  [[ "$output" == *"LEDGER AT RETIREMENT"* ]] || { echo "the escape silenced the stamp: $output"; false; }
}

@test "8 --recycle and --successor carry the work forward — neither can inherit this refusal" {
  # A recycle relaunches THE SAME PANE into a fresh context and hands the successor the stamp in its
  # brief; a --successor close hands the branch to a live pane. On both, an unlanded commit is
  # INHERITED, not stranded. The structural proof is the stronger one: the predicate is a pure
  # function of four fields, there is exactly one call site, and it is gated on --terminal.
  run bash -c "awk '/^hf_selfclose_ledger_refusal\\(\\) \\{/,/^\\}/' '$HF' | grep -c 'SC_TERMINAL\\|RECYCLE\\|SC_SUCCESSOR' || true"
  [ "$output" = 0 ] || { echo "the predicate reads a mode flag — it must be a pure function of the fields"; false; }
  n="$(grep -c 'hf_selfclose_ledger_refusal "\$SC_STAMP_FIELDS"' "$HF")"
  [ "$n" = 1 ] || { echo "expected exactly one refusal call site, found $n"; false; }
  grep -q 'SC_TERMINAL" = 1 \] && \[ -z "\$SC_SUCCESSOR" \]' "$HF" \
    || { echo "the refusal is not gated on --terminal-with-no-successor — a succession could inherit it"; false; }
  # And the recycle brief's own stamp section carries no exit of any kind.
  run bash -c "awk '/## STATE YOU ARE INHERITING/{f=1} f{print} f&&/^  fi\$/{exit}' '$HF' | grep -c 'exit ' || true"
  [ "$output" = 0 ] || { echo "the recycle brief's stamp section can exit — it must stay annotate-only"; false; }
}
