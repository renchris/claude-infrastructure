#!/usr/bin/env bats
# handoff-fire.sh — G5, the CLOUD DISPATCH VENUE.
#
# WHY THIS EXISTS: `cc-backlog claim --venue local|cloud` shipped fully tested and with ZERO
# PRODUCERS — nothing in the tree ever passed `--venue cloud`, because nothing could FIRE a cloud
# session in the first place: handoff-fire.sh had no `--cloud` at all, and its capacity gate asks
# only about THIS box (load per core, reclaimable RAM). Those are the wrong two questions for a
# fire that does not run here: the box terms would refuse a fire that costs the box nothing, or
# admit one whose real constraint — the ACCOUNT's rate limit — was never looked at.
#
# So the gate BRANCHES. `--cloud` substitutes per-account rate-limit headroom, read from the
# canonical router (`claude-accounts --route general`, bin/claude-accounts:2307-2328), for the two
# hardware terms. It does NOT delete them: cases 5 and 6 below are the pair that proves the branch
# is a branch and not a bypass — a LOCAL fire on a saturated box still refuses (5), and the cloud
# fire on that same saturated box admits (6), which is the whole point.
#
# THE LOAD-BEARING ASYMMETRY IS EXIT 3. `claude-accounts` exits 3 when the live limits are
# UNREADABLE and 2 when the data was fine and policy refused. A caller that treats 3 as "no
# constraint found ⇒ fire" has converted missing data into headroom — the exact defect
# bin/claude-accounts:1039-1040 already refuses to commit internally (`"no-weekly-data"  # missing
# data is NOT headroom`). Case 3 pins it: rc 3 REFUSES.
#
# DEFAULT-OFF. `--cloud` is rejected outright unless CC_FIRE_CLOUD=on. Case 1 is that refusal;
# case 7 is the control proving an unrecognised flag still dies the ordinary way, so case 1's
# refusal is caused by the opt-in and not by the parser not knowing the flag at all.
#
# RED-PROOF (recorded 2026-08-08, re-runnable): every case below was run against the pristine
# pre-change scripts/handoff-fire.sh (`git show origin/main:scripts/handoff-fire.sh`, 0 occurrences
# of `--cloud`). Cases 1-6 FAILED there — 1/2/3/4/6 because `--cloud` hit the parser's `*)` arm and
# exited 1 via usage, 5 because it never ran. Case 7 passed there and here, which is what makes it
# a control rather than a duplicate of case 1.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HF="$REPO/scripts/handoff-fire.sh"
  # HERMETICITY: handoff-fire.sh resolves the registry, mailbox, roles and projects dirs under
  # $HOME, and an ADMIT case proceeds PAST the gate into that machinery. Fixture it so no case can
  # read or mutate the operator's live ~/. Must precede any invocation below.
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  BIN="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$BIN"
  # sysctl stub — the box terms are INPUTS, not the mood of the machine running the suite. Same
  # shape as tests/handoff-fire-capacity-gate.bats setup(), reached through the CC_FIRE_SYSCTL seam
  # rather than PATH order (the gate resolves /usr/sbin/sysctl absolutely).
  cat > "$BIN/sysctl" <<'EOF'
#!/bin/bash
case "$*" in
  *hw.ncpu*)    echo "${STUB_NCPU:-10}" ;;
  *vm.loadavg*) echo "{ ${STUB_LOAD:-1.00} ${STUB_LOAD:-1.00} ${STUB_LOAD:-1.00} }" ;;
  *) exit 1 ;;
esac
EOF
  chmod +x "$BIN/sysctl"
  export CC_FIRE_SYSCTL="$BIN/sysctl"
  export CC_FIRE_HEADROOM_OVERRIDE=64      # pin the box's second term comfortably admitting
  # THE ACCOUNTS SEAM. CC_ACCOUNTS_BIN is the script's OWN pre-existing seam for this binary
  # (scripts/handoff-fire.sh:285-287 — "when a test opts in by pointing CC_ACCOUNTS_BIN at a stub"),
  # so the cloud term is stubbed through the same door the rest of the file already uses rather
  # than through a second one invented here. The stub answers ONLY `--route general`; every other
  # invocation exits 0 silently, which is why the sweep is turned off below rather than stubbed.
  cat > "$BIN/claude-accounts" <<'EOF'
#!/bin/bash
case "$*" in
  *"--route general"*)
    if [ "${STUB_ROUTE_RC:-0}" != 0 ]; then
      echo "none"
      echo "claude-accounts: no routable account for general: stub" >&2
      exit "${STUB_ROUTE_RC}"
    fi
    echo "${STUB_ROUTE_ACCT:-next3}"
    exit 0 ;;
esac
exit 0
EOF
  chmod +x "$BIN/claude-accounts"
  export CC_ACCOUNTS_BIN="$BIN/claude-accounts"
  export HANDOFF_ACCOUNT_SWEEP=off   # the stranded-account sweep is not under test here
  export PATH="$BIN:$PATH"
  PAYLOAD="$BATS_TEST_TMPDIR/p.txt"
  echo "TASK — cloud venue gate fixture payload." > "$PAYLOAD"
}

# fire() — the real script, always --dry-run so an ADMIT never actually launches anything.
# $1 = ncpu, $2 = load; the rest are passed through.
fire() { run env STUB_NCPU="$1" STUB_LOAD="$2" bash "$HF" --prompt-file "$PAYLOAD" --dry-run "${@:3}"; }

@test "1 --cloud is DEFAULT-OFF — refused when CC_FIRE_CLOUD is unset" {
  # The opt-in, not the parser: the flag is RECOGNISED (case 7 is the control for that) and
  # refused on policy. An off-box fire spends an ACCOUNT's rate limit, which is a different
  # resource from the one every other fire spends, so it does not ship live by default.
  fire 10 1.00 --cloud
  [ "$status" -eq 2 ]
  [[ "$output" == *"CC_FIRE_CLOUD"* ]]
  [[ "$output" == *"--cloud"* ]]
}

@test "2 cloud branch ADMITS when the account router reports headroom" {
  # `-ne 9` and `-ne 2`, not `-eq 0`, and for the reason the sibling suite's case 2 gives: a
  # --dry-run that clears the gate proceeds into the rest of the script, which has its own exit
  # paths under a fixtured $HOME. The GATE's verdict is what is under test, so the assertion is
  # "neither refusal fired, and the admit line was printed" — asserting 0 would silently couple
  # this case to machinery it is not about.
  STUB_ROUTE_RC=0 STUB_ROUTE_ACCT=next3 CC_FIRE_CLOUD=on fire 10 1.00 --cloud
  [ "$status" -ne 9 ]   # not a gate refusal
  [ "$status" -ne 2 ]   # not the opt-in refusal
  [[ "$output" == *"cloud capacity gate: ADMIT"* ]]
  [[ "$output" == *"next3"* ]]
}

@test "3 cloud branch REFUSES on claude-accounts exit 3 — missing data is NEVER headroom" {
  # THE case. rc 3 means the live limits could not be READ. A gate that admits on it has silently
  # converted "we do not know" into "there is room" — and the resulting fire is the one that finds
  # out. Mirrors bin/claude-accounts:1039-1040, which refuses to score a row with no weekly data.
  STUB_ROUTE_RC=3 CC_FIRE_CLOUD=on fire 10 1.00 --cloud
  [ "$status" -eq 9 ]
  [[ "$output" == *"REFUSING"* ]]
  [[ "$output" == *"Missing data is NEVER headroom"* ]]
}

@test "4 cloud branch REFUSES on claude-accounts exit 2 — no account routable by policy" {
  # Distinct from case 3 and must stay distinct: rc 2 is a healthy instrument reporting an
  # exhausted fleet, rc 3 is a blind one. Same refusal, different reason text, because the two
  # have different cures (wait for a reset vs fix the prober).
  STUB_ROUTE_RC=2 CC_FIRE_CLOUD=on fire 10 1.00 --cloud
  [ "$status" -eq 9 ]
  [[ "$output" == *"REFUSING"* ]]
  [[ "$output" == *"POLICY"* ]]
}

@test "5 CONTROL — the box-local gate still refuses a LOCAL fire on a saturated box" {
  # Proof the change is a BRANCH, not a weakening. 10 cores at load 30 = 3.0/core, over the 2.0
  # default ceiling. Without this case, case 6 would be indistinguishable from "the capacity gate
  # was accidentally disabled for everyone".
  fire 10 30.00
  [ "$status" -eq 9 ]
  [[ "$output" == *"capacity gate: REFUSING"* ]]
}

@test "6 the cloud fire ADMITS on that same saturated box — it does not run here" {
  # The reason the branch exists at all: identical box state to case 5, opposite verdict, because
  # a cloud fire consumes none of this box's cores or RAM. The gate that binds it is the account's.
  STUB_ROUTE_RC=0 STUB_ROUTE_ACCT=next2 CC_FIRE_CLOUD=on fire 10 30.00 --cloud
  [ "$status" -ne 9 ]
  [[ "$output" == *"cloud capacity gate: ADMIT"* ]]
  [[ "$output" == *"next2"* ]]
  # …and the box terms were not merely cleared, they were never asked: the load verdict line the
  # sibling gate always prints is ABSENT. Without this the case would also pass if the branch had
  # run both gates and the box happened to admit.
  [[ "$output" != *"capacity gate: ADMIT — load"* ]]
}

@test "7 CONTROL — an unknown flag still dies at the parser (case 1 is the opt-in, not ignorance)" {
  fire 10 1.00 --clouds
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown arg"* ]]
}

@test "8 the cloud branch records every admit — no silent return, reason mapped to a gate" {
  # The two standing properties tests/handoff-fire-capacity-gate.bats case 31 asserts over the
  # whole of capacity_gate(), restated here so this file fails on its OWN branch rather than only
  # via the sibling: (a) each `return 0` the cloud branch owns is preceded by an emit_gate_admit,
  # so a term added later with a bare `return 0` cannot re-open the hole; (b) every cloud refusal
  # reason maps in _fire_gate_of and so cannot fall into the fail-visible `*)` arm.
  local body mapped n=0 prev line
  body="$(awk '/^  # ---- G5: CLOUD VENUE BRANCH/{p=1} p{print} p&&/^  # ---- end G5 cloud branch/{exit}' "$HF")"
  [ -n "$body" ] || { echo "cloud branch markers not found — the extractor, not the gate, is broken"; false; }
  # Normalise exactly as the sibling case 31 does, and for the same two reasons: comments are
  # stripped because this branch's own prose contains the string `return 0`, and line-continuations
  # are JOINED because an emit split across `\` sits two PHYSICAL lines above its return — an
  # adjacency test on raw lines would call a correctly-recorded admit unrecorded.
  body="$(printf '%s\n' "$body" | sed 's/^[[:space:]]*//' | grep -v '^#' \
            | sed -e :a -e '/\\$/N; s/\\\n//; ta')"
  prev=""
  while IFS= read -r line; do
    case "$line" in
      *"return 0"*)
        n=$((n + 1))
        printf '%s\n%s\n' "$prev" "$line" | grep -q 'emit_gate_admit' \
          || { echo "UNRECORDED ADMIT in the cloud branch: $line"; false; } ;;
    esac
    prev="$line"
  done <<< "$body"
  [ "$n" -ge 2 ] || { echo "expected >=2 admitting returns in the cloud branch, found $n"; false; }
  mapped="$(awk '/^_fire_gate_of\(\)/{p=1} p{print} p&&/^\}$/{exit}' "$HF")"
  printf '%s' "$mapped" | grep -q 'cloud-\*' \
    || { echo "cloud-* refusal reasons are unmapped in _fire_gate_of"; false; }
}
