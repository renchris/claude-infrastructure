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
# RED-PROOF (MEASURED 2026-08-08, re-runnable). Replayed against the pristine pre-change
# scripts/handoff-fire.sh — `git show origin/main:scripts/handoff-fire.sh`, 0 occurrences of
# `--cloud` — in a scratch tree, this file copied in unchanged:
#
#   RED there, green here : 1 2 3 4 6 8   (1/2/3/4/6 die at the parser's `*)` arm, exit 1 via
#                                          usage; 8's extractor finds no cloud-branch markers)
#   green on BOTH trees   : 5 7           — which is precisely what makes them controls
#
# ONE TRAP for whoever re-runs this: the scratch tree must also carry
# `scripts/lib/capacity-admit.sh`. Without it the gate takes its ABSENT-LIBRARY branch and
# fail-OPENS, so control case 5 goes red for a reason that has nothing to do with the change —
# a harness artifact that reads exactly like a real refutation.

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
  # …and turning the sweep OFF is not the same as pinning WHERE it would have written. Both of
  # these default to an ABSOLUTE /tmp path, which no amount of $HOME fixturing redirects, so an
  # unpinned run reaches the operator's real files. Absent paths are the right value — these
  # sensors fail open on one.
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/account-sweep.json"
  export CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/heal-"
  # THE BOX GATE IS OFF BY DEFAULT HERE, AND EVERY CASE THAT IS ABOUT IT TURNS IT BACK ON.
  # A suite exercising handoff-fire on a shared box otherwise goes red-by-LOAD rather than by its
  # subject: this machine lives well above the 2.0/core ceiling, so the verdict would be a function
  # of what else happens to be running. Off is the safe default for cases that merely need a fire
  # to proceed; `gate_on` is how a case that genuinely tests the gate opts in — against the STUBBED
  # sysctl, so the load it sees is an input rather than the mood of the machine.
  export CC_FIRE_CAPACITY_GATE=off
  export PATH="$BIN:$PATH"
  PAYLOAD="$BATS_TEST_TMPDIR/p.txt"
  echo "TASK — cloud venue gate fixture payload." > "$PAYLOAD"
}

# Opt back into the capacity gate for the cases that ARE the gate. Paired with the sysctl stub, so
# STUB_LOAD/STUB_NCPU are what the gate reads — never /usr/sbin/sysctl's live answer.
# Wave E (task #170) defaulted the LOAD term OFF — load1 does not move with an added resident
# session, so the saturated-load fixture case 5 uses is no longer a refusal unless the term is asked
# for. Pinning it here keeps case 5 asserting what it was written to assert (the cloud branch is a
# BRANCH, not a weakening of the box-local gate) rather than silently becoming a test of a term that
# no longer runs. The segment and active terms are pinned to comfortably-admitting values for the
# same reason the headroom override exists: otherwise this suite becomes a function of the
# compressor state and live session count of whichever box happens to run it.
gate_on() {
  export CC_FIRE_CAPACITY_GATE=on
  export CC_FIRE_LOAD_TERM=on
  export CC_FIRE_SEGMENT_OVERRIDE=0
  export CC_FIRE_ACTIVE_OVERRIDE=0
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
  [[ "$output" == *"CC_FIRE_CLOUD"* ]] || false
  [[ "$output" == *"--cloud"* ]]
}

@test "2 cloud branch ADMITS when the account router reports headroom" {
  gate_on
  # `-ne 9` and `-ne 2`, not `-eq 0`, and for the reason the sibling suite's case 2 gives: a
  # --dry-run that clears the gate proceeds into the rest of the script, which has its own exit
  # paths under a fixtured $HOME. The GATE's verdict is what is under test, so the assertion is
  # "neither refusal fired, and the admit line was printed" — asserting 0 would silently couple
  # this case to machinery it is not about.
  STUB_ROUTE_RC=0 STUB_ROUTE_ACCT=next3 CC_FIRE_CLOUD=on fire 10 1.00 --cloud
  [ "$status" -ne 9 ]   # not a gate refusal
  [ "$status" -ne 2 ]   # not the opt-in refusal
  [[ "$output" == *"cloud capacity gate: ADMIT"* ]] || false
  [[ "$output" == *"next3"* ]]
}

@test "3 cloud branch REFUSES on claude-accounts exit 3 — missing data is NEVER headroom" {
  gate_on
  # THE case. rc 3 means the live limits could not be READ. A gate that admits on it has silently
  # converted "we do not know" into "there is room" — and the resulting fire is the one that finds
  # out. Mirrors bin/claude-accounts:1039-1040, which refuses to score a row with no weekly data.
  STUB_ROUTE_RC=3 CC_FIRE_CLOUD=on fire 10 1.00 --cloud
  [ "$status" -eq 9 ]
  [[ "$output" == *"REFUSING"* ]] || false
  [[ "$output" == *"Missing data is NEVER headroom"* ]]
}

@test "4 cloud branch REFUSES on claude-accounts exit 2 — no account routable by policy" {
  gate_on
  # Distinct from case 3 and must stay distinct: rc 2 is a healthy instrument reporting an
  # exhausted fleet, rc 3 is a blind one. Same refusal, different reason text, because the two
  # have different cures (wait for a reset vs fix the prober).
  STUB_ROUTE_RC=2 CC_FIRE_CLOUD=on fire 10 1.00 --cloud
  [ "$status" -eq 9 ]
  [[ "$output" == *"REFUSING"* ]] || false
  [[ "$output" == *"POLICY"* ]]
}

@test "5 CONTROL — the box-local gate still refuses a LOCAL fire on a saturated box" {
  gate_on
  # Proof the change is a BRANCH, not a weakening. 10 cores at load 30 = 3.0/core, over the 2.0
  # default ceiling. Without this case, case 6 would be indistinguishable from "the capacity gate
  # was accidentally disabled for everyone".
  fire 10 30.00
  [ "$status" -eq 9 ]
  [[ "$output" == *"capacity gate: REFUSING"* ]]
}

@test "6 the cloud fire ADMITS on that same saturated box — it does not run here" {
  gate_on
  # The reason the branch exists at all: identical box state to case 5, opposite verdict, because
  # a cloud fire consumes none of this box's cores or RAM. The gate that binds it is the account's.
  STUB_ROUTE_RC=0 STUB_ROUTE_ACCT=next2 CC_FIRE_CLOUD=on fire 10 30.00 --cloud
  [ "$status" -ne 9 ]
  [[ "$output" == *"cloud capacity gate: ADMIT"* ]] || false
  [[ "$output" == *"next2"* ]] || false
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
  gate_on
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

# ══ 9-16 · THE CREATE ITSELF (CLOUD_OBSERVABILITY.md §10.4) ═════════════════════════════════════
#
# Cases 1-8 above are entirely about the GATE — which questions admit an off-box fire. They passed,
# and shipped, over a fire path that could not fire: §10.4's census found handoff-fire.sh parsing
# `--cloud`, gating it default-off and pricing it against account headroom, then never invoking a
# create, never calling `cc-cloud declare` and never touching the claude binary. G5 was graded ✅ on
# the parts that were built. These cases are the part that was not — and they are written so that
# the same mistake cannot repeat: every one of them asserts on an EFFECT (a create attempted, a
# declaration written, an exit code), never on the presence of a flag or a string in the source.
#
# THE TWO SEAMS. `CC_CLOUD_CREATE_BIN` is the claude binary the library invokes; `CC_CLOUD_BIN` is
# the cc-cloud used to declare, honored SET-including-EMPTY (`${VAR+set}`) exactly as
# bin/cc-spawn-verify and bin/cc-notify honor it, so a case can genuinely turn the declaration off.

# An account map the fixture actually owns. Without it cfg_dir resolves against the operator's real
# accounts.json, and a cloud case would either read live paths or refuse for a reason unrelated to
# its subject.
cloud_acct() {
  mkdir -p "$HOME/.claude-next3"
  cat > "$BATS_TEST_TMPDIR/acctmap.sh" <<'EOF'
cc_acct_dir_for_name() {
  CC_ACCT_IS_FABLE=0; CC_ACCT_DIR=""
  case "$1" in next3|claude3) CC_ACCT_DIR="$HOME/.claude-next3" ;; *) return 1 ;; esac
}
cc_acct_launcher_for_name() { case "$1" in next3) echo claude3 ;; *) return 1 ;; esac; }
cc_acct_name_for_dir_basename() { case "$1" in .claude-next3) echo next3 ;; *) return 1 ;; esac; }
EOF
  export CC_ACCOUNT_MAP="$BATS_TEST_TMPDIR/acctmap.sh"
  export CC_FIRE_CLOUD=on CC_FIRE_CLOUD_GATE=off
}

# A stub claude that emits a canned create/refusal. Real ANSI, because the normaliser is in the path.
cloud_claude() { # $1 = payload written to stdout, $2 = exit code
  # It also records its own argv when CLOUD_CREATE_LOG is set, which is how case 17 reads the
  # PAYLOAD as an effect (the thing actually handed to the create) rather than as a string in the
  # source. Unset for every pre-existing case, so their behaviour is byte-identical.
  printf '#!/bin/bash\nif [ -n "${CLOUD_CREATE_LOG:-}" ]; then printf "%%s\\n" "$@" >> "$CLOUD_CREATE_LOG"; fi\nprintf %%s "$CLOUD_STUB_OUT"\nexit %s\n' "${2:-0}" > "$BIN/claude-cloud"
  chmod +x "$BIN/claude-cloud"
  export CLOUD_STUB_OUT="$1" CC_CLOUD_CREATE_BIN="$BIN/claude-cloud"
}

# A stub cc-cloud that RECORDS the declaration argv, so case 13 asserts the declare happened with
# the right fields rather than that the script contains the word "declare".
cloud_ccloud() {
  # ⚠️ THE VERBS ARE SPLIT, and that split is load-bearing. `cc-cloud` is now called TWICE per fire
  # — `preflight` before the create (B2) and `declare` after it — and a stub that answered both
  # from one rc and one log would have collapsed the two states under test: CLOUD_DECL_RC=1 (case
  # 15's FAILED DECLARE) would have refused at the preflight instead, and every preflight would
  # have written into the log three cases assert is EMPTY. One seam per verb keeps each case
  # measuring what it names (memory: harness-default-collapses-the-states-under-test).
  #
  # ⚠️ AND THE SEAMS ARE `STUB_`-PREFIXED FOR A MEASURED REASON, not for tidiness. They were first
  # written as CLOUD_PF_RC/CLOUD_PF_LOG — the same names the subject uses for its OWN locals. Bash
  # keeps the export attribute on assignment, so the subject's `CLOUD_PF_RC=0` REWROTE the exported
  # value before invoking this stub: case 18 fired a rc=1 preflight, the stub read 0, the fire sailed
  # into the create and the case failed asserting the exit code. A stub seam must not collide with a
  # variable name inside the thing it is stubbing.
  cat > "$BIN/cc-cloud" <<'EOF'
#!/bin/bash
if [ "${1:-}" = preflight ]; then
  if [ -n "${STUB_PF_LOG:-}" ]; then echo "$@" >> "$STUB_PF_LOG"; fi
  exit "${STUB_PF_RC:-0}"
fi
echo "$@" >> "$CLOUD_DECL_LOG"
exit "${CLOUD_DECL_RC:-0}"
EOF
  chmod +x "$BIN/cc-cloud"
  export CLOUD_DECL_LOG="$BATS_TEST_TMPDIR/decl.log" CC_CLOUD_BIN="$BIN/cc-cloud"
}

cfire() { run env "$@" bash "$HF" --prompt-file "$PAYLOAD" --cloud --account next3; }

@test "9 --dry-run prints the create PLAN and issues no create at all" {
  cloud_acct
  cloud_claude "Created cloud session: should never run" 0
  run env bash "$HF" --prompt-file "$PAYLOAD" --cloud --account next3 --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"DRY RUN: cloud fire"* ]] || false
  [[ "$output" == *"next3"* ]] || false
  [[ "$output" == *"claude/fire-"* ]] || false          # the branch is assigned even on a dry run…
  [ ! -f "$BATS_TEST_TMPDIR/decl.log" ]                  # …and nothing was declared
}

@test "10 the create library being ABSENT is a REFUSAL, not an ungated fire" {
  # Deliberately the OPPOSITE default from the capacity library, whose absent branch fails OPEN
  # because it sits on the universal spawn chokepoint. This branch is reached only by a fire that
  # asked for the off-box venue, so its blast radius is one fire — and firing without the library
  # means firing without the pty allocator, i.e. spending an attempt the CLI refuses outright.
  cloud_acct
  cfire CC_FIRE_CLOUD_LIB="$BATS_TEST_TMPDIR/no-such-lib.sh"
  [ "$status" -eq 10 ]
  [[ "$output" == *"cloud-create.sh is unreachable"* ]] || false
}

@test "11 a cloud fire REFUSES when no owning account resolves — sessions are account-scoped" {
  # §10.2: the same id returns {ok:true} from the owning account and "Session not found" from any
  # other, so an unrouted create would be declared under a name that is not its owner and every
  # later send would read as a DEAD session. --launcher bypasses account selection entirely.
  cloud_acct
  run env CC_FIRE_CLOUD=on CC_FIRE_CLOUD_GATE=off bash "$HF" --prompt-file "$PAYLOAD" --cloud \
      --launcher claude-nope
  [ "$status" -eq 10 ]
  [[ "$output" == *"account"* ]] || false
  [[ "$output" == *"Session not found"* ]] || false     # names the symptom it is preventing
}

@test "12 a refused create is NAMED by its class, and the four stay distinct" {
  # "…or refuses with a named reason" is half of §10.4's frozen DoD. The classes have four
  # different cures, so one merged 'cloud fire failed' would make them unanswerable after the fact.
  cloud_acct; cloud_ccloud
  cloud_claude "$(printf 'Error:\x1b[8GBundle\x1b[15Gupload\x1b[22Gfailed: Socket is closed after 3 attempts')" 1
  cfire CC_CLOUD_CREATE_ATTEMPTS=2 CC_CLOUD_CREATE_BACKOFF_S=0
  [ "$status" -eq 10 ]
  [[ "$output" == *"REFUSED — refused-bundle"* ]] || false
  [ ! -f "$CLOUD_DECL_LOG" ]                             # nothing declared for a session that is not there
}

@test "13 a successful create is DECLARED IMMEDIATELY, with id, branch AND owning account" {
  # §8.1: the id does not exist until after the fire, so create-then-declare is the only possible
  # order — which makes the window between them the one interval where a real cloud session exists
  # that nothing on this box can see, with a 600s orphan reaper running. Nothing goes between them.
  cloud_acct; cloud_ccloud
  cloud_claude "$(printf 'Created cloud session: t\x1b[8GView: https://claude.ai/code/session_01TESTTESTTESTTESTTESTT?from=cli')" 0
  cfire
  [ "$status" -eq 0 ]
  [ -s "$CLOUD_DECL_LOG" ]
  grep -q -- "--id session_01TESTTESTTESTTESTTESTT" "$CLOUD_DECL_LOG"
  grep -q -- "--account next3" "$CLOUD_DECL_LOG"
  grep -q -- "--branch claude/fire-" "$CLOUD_DECL_LOG"
  [[ "$output" == *"session_01TESTTESTTESTTESTTESTT"* ]] || false
}

@test "14 created-unidentified gets its OWN exit — a live session nobody can name" {
  # The loudest state this script reaches. It is neither `created` (there is no id to declare) nor
  # a refusal (a session IS running and spending quota), and folding it into either loses the one
  # fact the operator needs: something is live and no local instrument can see it.
  cloud_acct; cloud_ccloud
  cloud_claude "Created cloud session: a banner carrying no id whatsoever" 0
  cfire
  [ "$status" -eq 11 ]
  [[ "$output" == *"CANNOT BE NAMED"* ]] || false
  [[ "$output" == *"cc-cloud declare"* ]] || false       # hands over the exact recovery command
  [ ! -f "$CLOUD_DECL_LOG" ]
}

@test "15 a created-but-UNDECLARED session exits 11 too — created is not the success condition" {
  # The declaration is what makes the session observable, so a create whose declare failed is not a
  # successful fire. Exit 0 there would report a healthy off-box session that the three abstaining
  # oracles cannot even recognise as off-box — cc-cloud is-offbox answers from the declaration.
  cloud_acct; cloud_ccloud
  cloud_claude "$(printf 'Created cloud session: t\x1b[8GView: https://claude.ai/code/session_01TESTTESTTESTTESTTESTT?from=cli')" 0
  cfire CLOUD_DECL_RC=1
  [ "$status" -eq 11 ]
  [[ "$output" == *"declaration FAILED"* ]] || false
  [[ "$output" == *"session_01TESTTESTTESTTESTTESTT"* ]] || false
}

@test "16 CONTROL — a cloud fire spawns NO local surface (the venue is the whole point)" {
  # The pane machinery below the branch is all box-local: a composer to type into, an engagement to
  # verify, a pane uuid to register. A cloud fire that fell through to it would be firing locally
  # while reporting off-box. Asserted by effect: the it2 backend is never reached.
  cloud_acct; cloud_ccloud
  cloud_claude "$(printf 'Created cloud session: t\x1b[8GView: https://claude.ai/code/session_01TESTTESTTESTTESTTESTT?from=cli')" 0
  cat > "$BIN/it2" <<'EOF'
#!/bin/bash
echo "it2 $*" >> "$CLOUD_IT2_LOG"
EOF
  chmod +x "$BIN/it2"
  cfire CLOUD_IT2_LOG="$BATS_TEST_TMPDIR/it2.log"
  [ "$status" -eq 0 ]
  [ ! -f "$BATS_TEST_TMPDIR/it2.log" ]
}

# ── B1 + B2 — the two halves of backlog 7c6ff16259a0 ────────────────────────────────────────────
# Both defects lived ONLY on this leg, and the reason is worth stating once: the sibling API create
# (scripts/cloud-create-api.py) names the branch in the create body's `outcomes.git_info.branches`,
# so there the push target is authorised AT CREATE and neither fix is needed. cc_cloud_create's
# signature is `cfg cwd prompt` — no branch parameter at all — so on this leg the payload is the
# only place the branch can be established, and nothing had ever established it.
#
# RED-PROOF (re-runnable): replay this file against `git show <pre-fix sha>:scripts/handoff-fire.sh`
# in a scratch tree. 17 and 18 go RED there — 17 because the payload only ever said
# `git push origin HEAD:<branch>` with no branch to push, 18 because no preflight was called at all,
# so the fire proceeded to the create and exited on the create's own outcome instead of on 12.
# 19 is green on BOTH trees BY DESIGN and is not a weaker case for it: it is the non-discrimination
# control proving the new gate is a GATE and not a blanket refusal of the venue.

@test "17 the payload CREATES the assigned branch before pushing it — not a push to a name nothing holds" {
  cloud_acct; cloud_ccloud
  cloud_claude "Created cloud session: t" 0
  cfire CLOUD_CREATE_LOG="$BATS_TEST_TMPDIR/create.log"
  [ -s "$BATS_TEST_TMPDIR/create.log" ]
  local sw push
  sw="$(grep -n 'git switch -c claude/fire-' "$BATS_TEST_TMPDIR/create.log" | head -1 | cut -d: -f1)"
  push="$(grep -n 'git push -u origin HEAD' "$BATS_TEST_TMPDIR/create.log" | head -1 | cut -d: -f1)"
  [ -n "$sw" ] || { echo "the payload never creates the branch it tells the VM to push"; false; }
  [ -n "$push" ] || { echo "the payload never instructs the push"; false; }
  [ "$sw" -lt "$push" ] || { echo "switch -c must PRECEDE the push (sw=$sw push=$push)"; false; }
  # The pre-fix spelling pushed HEAD straight at an invented ref name. It must be gone, or the
  # branch would be created and then bypassed by the very next line.
  ! grep -q 'HEAD:claude/fire-' "$BATS_TEST_TMPDIR/create.log"
}

@test "18 a fire whose preflight REFUSES never reaches the create — the quota is not spent" {
  cloud_acct; cloud_ccloud
  cloud_claude "Created cloud session: this create must never be reached" 0
  cfire STUB_PF_RC=1 STUB_PF_LOG="$BATS_TEST_TMPDIR/pf.log" \
        CLOUD_CREATE_LOG="$BATS_TEST_TMPDIR/create.log"
  [ "$status" -eq 12 ]
  [[ "$output" == *"REFUSED by preflight"* ]] || false
  [ ! -f "$BATS_TEST_TMPDIR/create.log" ]                # the account's rate limit was NOT spent
  [ ! -f "$CLOUD_DECL_LOG" ]                             # and nothing was declared
  # Called for the REPO the VM would clone, not for some default — the whole point of the probe.
  [ -s "$BATS_TEST_TMPDIR/pf.log" ]
  grep -q -- '--repo' "$BATS_TEST_TMPDIR/pf.log"
}

@test "19 CONTROL — a PASSING preflight changes nothing, and the override still fires" {
  # Green on both trees by design (case 18 is the discriminating half). It exists so that a future
  # widening of the gate into "refuse the venue" cannot pass: both a clean probe and an explicit
  # opt-out must still produce an ordinary, declared cloud fire.
  cloud_acct; cloud_ccloud
  cloud_claude "$(printf 'Created cloud session: t\x1b[8GView: https://claude.ai/code/session_01TESTTESTTESTTESTTESTT?from=cli')" 0
  cfire STUB_PF_RC=0
  [ "$status" -eq 0 ]
  [ -s "$CLOUD_DECL_LOG" ]
  rm -f "$CLOUD_DECL_LOG"
  cfire CC_FIRE_CLOUD_PREFLIGHT=off STUB_PF_RC=1 STUB_PF_LOG="$BATS_TEST_TMPDIR/pf-off.log"
  [ "$status" -eq 0 ]
  [ -s "$CLOUD_DECL_LOG" ]
  [ ! -f "$BATS_TEST_TMPDIR/pf-off.log" ]                # the override SKIPS the probe, not just its verdict
}

# ══ 20-22 · THE BOOT CONTRACT (CLOUD_OBSERVABILITY.md §4.1) ═════════════════════════════════════
#
# §4.1 is what makes the declared branch worth watching: absence of the ref means "never booted"
# ONLY because the brief required a first-act push. It was prose and nothing else until 2026-08-27
# — this file's own case 17 pinned that the payload creates and pushes the branch, and the payload
# said to do it *before you finish*, i.e. at the END of the session. So the observable the verdict
# reads was produced, if at all, hours after the 15-minute budget that convicts its absence.
# Measured consequence on the live board 2026-08-19: 65 of 84 non-retired declarations read
# NOT-STARTED against a mature-window push rate of 80%.
#
# Written as EFFECTS, like 9-19: the payload actually handed to the create, and the argv actually
# handed to `cc-cloud declare`. Never the presence of a string in the source.

@test "20 the payload's FIRST ACT is the branch publish, and it PRECEDES the brief" {
  cloud_acct; cloud_ccloud
  cloud_claude "Created cloud session: t" 0
  cfire CLOUD_CREATE_LOG="$BATS_TEST_TMPDIR/create.log"
  [ -s "$BATS_TEST_TMPDIR/create.log" ]
  local first task
  first="$(grep -n 'FIRST ACT' "$BATS_TEST_TMPDIR/create.log" | head -1 | cut -d: -f1)"
  task="$(grep -n 'cloud venue gate fixture payload' "$BATS_TEST_TMPDIR/create.log" | head -1 | cut -d: -f1)"
  [ -n "$first" ] || { echo "the payload carries no first-act clause — §4.1 is prose again"; false; }
  [ -n "$task" ] || { echo "the payload lost the brief itself"; false; }
  # ORDER IS THE WHOLE CLAIM. A clause that says "before you read anything else" cannot arrive
  # after the task it precedes: a model reading top-down acts on what it met first.
  [ "$first" -lt "$task" ] || { echo "the contract must PRECEDE the brief (first=$first task=$task)"; false; }
}

@test "21 the declaration STATES the contract was delivered — the fire is the only thing that knows" {
  cloud_acct; cloud_ccloud
  cloud_claude "$(printf 'Created cloud session: t\x1b[8GView: https://claude.ai/code/session_01TESTTESTTESTTESTTESTT?from=cli')" 0
  cfire
  [ "$status" -eq 0 ]
  grep -q -- "--boot-contract first-push" "$CLOUD_DECL_LOG"
}

@test "22 an ABSENT contract library DEGRADES the fire, and the declaration does not claim one" {
  # Deliberately NOT the create library's fail-closed treatment (case 10). This library is a NEW
  # file, and a file a landed diff ADDS is ABSENT on the live layer — not stale — until
  # deploy-live.sh converges, so a refusal here would break every cloud fire for that whole window.
  # The cost of degrading is exactly one thing, and it is the safe direction: the declaration omits
  # the flag, so cc-cloud ABSTAINS on absence instead of convicting.
  cloud_acct; cloud_ccloud
  cloud_claude "$(printf 'Created cloud session: t\x1b[8GView: https://claude.ai/code/session_01TESTTESTTESTTESTTESTT?from=cli')" 0
  cfire CC_FIRE_BOOT_CONTRACT_LIB= CLOUD_CREATE_LOG="$BATS_TEST_TMPDIR/create.log"
  [ "$status" -eq 0 ]                                    # it still fires
  [ -s "$CLOUD_DECL_LOG" ]                               # and is still declared
  ! grep -q -- "--boot-contract" "$CLOUD_DECL_LOG"        # but claims nothing it did not deliver
  ! grep -q 'FIRST ACT' "$BATS_TEST_TMPDIR/create.log"
  [[ "$output" == *"NO BOOT CONTRACT"* ]] || false        # and says so where a human will see it
}
