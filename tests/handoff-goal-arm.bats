#!/usr/bin/env bats
# handoff-fire.sh — THE TWO-MESSAGE GOAL PATH (--goal), 2026-08-08.
# Root cause + probe record: docs/research/goal-in-handoff-2026-08-08.md.
#
# WHY THIS SUITE EXISTS. `check_slash_head` refuses a `/goal`-headed payload, and it is RIGHT to:
# one submission cannot be both a brief and a command. The measured consequence was that fired
# sessions stopped carrying a goal at all — 20.0% of provably-fired sessions before 2026-07-31,
# 3.0% after. `--goal` is the replacement: the brief stays message 1, the goal becomes message 2,
# pasted into the pane after engagement is proven. These tests pin the three properties that make
# that safe, each of which this repo has already been burned by the absence of:
#
#   1. VALIDATED PRE-FIRE. A condition that cannot work is refused before any side effect, with a
#      distinct `payload-goal-arm-*` reason per authoring mistake (multi-line / slash / over-cap).
#   2. READ BACK, NEVER CLAIMED (memory claimed-outcome-vs-checked-outcome). The oracle is the
#      harness's OWN goal_status attachment, keyed on the condition — and case "oracle is not
#      satisfied by the echo of its own paste" is the load-bearing one: the pasted user message
#      contains the condition verbatim whether or not the command was accepted, so a grep -F oracle
#      would report success for an over-cap /goal that set nothing.
#   3. FAILS CLOSED, IN THE RIGHT DIRECTION. arm_goal can never fail the fire (message 1 has already
#      landed and been proven to engage) and can never type into a shell (the composer_owned gate
#      inside it2_paste_submit_verified). Both halves are asserted, including the never-non-zero
#      contract.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HF="$REPO/scripts/handoff-fire.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude/logs"
  # Hermeticity seams (scripts/test-hermeticity-lint.sh). Nothing here fires, but a fixtured $HOME
  # does NOT redirect an absolute /tmp default or a bare name resolved off the operator's PATH — so
  # these are pinned to ABSENT paths, where the sensors that read them fail open.
  export CC_FIRE_CAPACITY_GATE=off
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/account-sweep.json"
  export CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/no-such-claude-accounts"
  export CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/heal-"
  {
    grep '^_iso_now() {' "$HF" || true
    sed -n '/^emit_fire_event() {/,/^}/p'     "$HF"
    sed -n '/^emit_fire_refusal() {/,/^}/p'   "$HF"
    sed -n '/^_fire_gate_of() {/,/^}/p'       "$HF"
    sed -n '/^emit_goal_event() {/,/^}/p'     "$HF"
    sed -n '/^check_goal_arm() {/,/^}/p'      "$HF"
    sed -n '/^check_slash_head() {/,/^}/p'    "$HF"
    sed -n '/^goal_armed_for_pane() {/,/^}/p' "$HF"
    sed -n '/^goal_live_for_sid() {/,/^}/p'   "$HF"
    sed -n '/^inherit_recycle_goal() {/,/^}/p' "$HF"
    sed -n '/^arm_goal() {/,/^}/p'            "$HF"
  } > "$BATS_TEST_TMPDIR/units.sh"
  bash -n "$BATS_TEST_TMPDIR/units.sh" || { echo "extraction from $HF is not valid bash" >&2; return 1; }
  # shellcheck disable=SC1091
  . "$BATS_TEST_TMPDIR/units.sh"
  LOG="$HOME/.claude/logs/handoffs.jsonl"
  # The projects ROOT, plus the per-cwd project dir CC actually nests transcripts in. The first
  # version of this fixture wrote transcripts straight into the root; every test passed, and the
  # oracle then returned a FALSE NEGATIVE on the first real fired pane, because a direct
  # "$root/$sid.jsonl" lookup can never find …/projects/<project>/<sid>.jsonl. The fixture must
  # replay the real layout or it certifies the wrong thing (control-must-replay-the-real-artifact).
  PROJ_ROOT="$BATS_TEST_TMPDIR/projects"
  PDIR="$PROJ_ROOT/-Users-someone-Development-repo"; mkdir -p "$PDIR"
  # The four below are read by the functions sourced from units.sh, which shellcheck cannot follow
  # into — hence the narrow per-line disables rather than a needless `export`.
  # shellcheck disable=SC2034  # read by goal_armed_for_pane
  CC_PROJECTS_DIRS="$PROJ_ROOT"
  # shellcheck disable=SC2034  # read by check_goal_arm; reset here so a per-test prefix is the only source
  FIRE_GOAL=""
  # Fast polls — the arm_goal timeout is a wall-clock loop and this suite must not pay for it.
  # shellcheck disable=SC2034  # both read by arm_goal
  FIRE_GOAL_VERIFY_TIMEOUT=2 FIRE_GOAL_VERIFY_INTERVAL=1
}

# Write a transcript that contains ONLY what the harness writes when a goal really is set.
_write_goal_transcript() { # $1=sid $2=condition
  jq -cn --arg c "$2" '{type:"attachment",attachment:{type:"goal_status",met:false,sentinel:true,condition:$c}}' \
    > "$PDIR/$1.jsonl"
}
cc_sid_for_pane() { printf '%s' "${STUB_SID:-}"; }

# ── 1 · PRE-FIRE VALIDATION ────────────────────────────────────────────────────────────────────

@test "no --goal is a silent no-op — the flag is opt-in and costs nothing when unset" {
  FIRE_GOAL="" run check_goal_arm
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -s "$LOG" ]
}

@test "an ordinary one-line pointer condition is admitted" {
  FIRE_GOAL='close every gate in the brief above — DoD at docs/plans/X.md' run check_goal_arm
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "a MULTI-LINE condition is refused — the CR would strand the rest in the composer" {
  command -v jq >/dev/null 2>&1 || skip "refusal rows need jq"
  FIRE_GOAL="$(printf 'do the thing\nand also this')" run check_goal_arm
  [ "$status" -eq 1 ]
  run jq -r '[.class,.refuse_reason,.gate]|@tsv' "$LOG"
  [ "$output" = "$(printf 'refused\tpayload-goal-arm-multiline\tpayload')" ]
}

@test "a condition that itself STARTS with a slash is refused — it would dispatch, not describe" {
  command -v jq >/dev/null 2>&1 || skip "refusal rows need jq"
  FIRE_GOAL='/research the design space' run check_goal_arm
  [ "$status" -eq 1 ]
  run jq -r '.refuse_reason' "$LOG"
  [ "$output" = "payload-goal-arm-slash" ]
}

@test "an OVER-CAP condition is refused pre-fire — the harness sets nothing and replies in text" {
  command -v jq >/dev/null 2>&1 || skip "refusal rows need jq"
  FIRE_GOAL="$(head -c 4001 < /dev/zero | tr '\0' 'x')" GOAL_MAX_CHARS=4000 run check_goal_arm
  [ "$status" -eq 1 ]
  run jq -r '.refuse_reason' "$LOG"
  [ "$output" = "payload-goal-arm-cap" ]
}

# The boundary is the whole content of the cap rule, so it is pinned on BOTH sides. A cap test that
# only ever asserts the refusing side passes just as well against a guard that refuses everything.
@test "cap BOUNDARY: exactly at the limit is admitted, one over is refused" {
  FIRE_GOAL="$(head -c 4000 < /dev/zero | tr '\0' 'x')" GOAL_MAX_CHARS=4000 run check_goal_arm
  [ "$status" -eq 0 ]
  FIRE_GOAL="$(head -c 4001 < /dev/zero | tr '\0' 'x')" GOAL_MAX_CHARS=4000 run check_goal_arm
  [ "$status" -eq 1 ]
}

# ── 2 · THE READ-BACK ORACLE ───────────────────────────────────────────────────────────────────

@test "goal_armed_for_pane CONFIRMS a real goal_status attachment carrying this condition" {
  command -v jq >/dev/null 2>&1 || skip "the oracle is jq-only by design"
  STUB_SID=s1 _write_goal_transcript s1 'finish the brief'
  STUB_SID=s1 run goal_armed_for_pane 900 'finish the brief'
  [ "$status" -eq 0 ]
}

@test "goal_armed_for_pane REFUSES a goal whose condition is a DIFFERENT one (a stale goal)" {
  command -v jq >/dev/null 2>&1 || skip "the oracle is jq-only by design"
  STUB_SID=s2 _write_goal_transcript s2 'some older objective'
  STUB_SID=s2 run goal_armed_for_pane 900 'finish the brief'
  [ "$status" -eq 1 ]
}

# THE LOAD-BEARING CASE. When the harness REFUSES a /goal (over-cap condition, untrusted workspace,
# restricted hooks) it still records the submitted user message — which contains the condition
# verbatim — and writes NO attachment. A substring oracle reads that as success. This asserts the
# real one does not, and it is the reason goal_armed_for_pane is jq-only rather than grep -F.
@test "goal_armed_for_pane is NOT satisfied by the echo of its own paste (a REFUSED /goal)" {
  command -v jq >/dev/null 2>&1 || skip "the oracle is jq-only by design"
  jq -cn --arg c 'finish the brief' \
    '{type:"user",message:{role:"user",content:("<command-name>/goal</command-name><command-args>" + $c + "</command-args>")}}' \
    > "$PDIR/s3.jsonl"
  jq -cn '{type:"assistant",message:{content:"Goal condition is limited to 4000 characters (got 4100)"}}' \
    >> "$PDIR/s3.jsonl"
  run grep -cF 'finish the brief' "$PDIR/s3.jsonl"   # positive control: a substring oracle WOULD pass
  [ "$output" -ge 1 ]
  STUB_SID=s3 run goal_armed_for_pane 900 'finish the brief'
  [ "$status" -eq 1 ]
}

# REGRESSION, and the reason this suite's fixture nests. The first implementation looked for
# "$CC_PROJECTS_DIRS_entry/$sid.jsonl" — the projects ROOT — and passed every test here because the
# fixture wrote there too. On the first real fired pane it returned `unverified` for a goal that was
# demonstrably set. The positive control below is the discriminator: a root-level lookup CANNOT see
# the nested file, so if anyone re-flattens the resolution this goes red.
@test "goal_armed_for_pane finds a transcript NESTED in its per-cwd project dir, not just the root" {
  command -v jq >/dev/null 2>&1 || skip "the oracle is jq-only by design"
  STUB_SID=s7 _write_goal_transcript s7 'finish the brief'
  [ -f "$PDIR/s7.jsonl" ]                        # it really is one level down…
  [ ! -f "$PROJ_ROOT/s7.jsonl" ]                 # …and NOT at the root the broken form looked in
  STUB_SID=s7 run goal_armed_for_pane 900 'finish the brief'
  [ "$status" -eq 0 ]
}

@test "goal_armed_for_pane REFUSES when the pane resolves to no session at all" {
  STUB_SID="" run goal_armed_for_pane 900 'finish the brief'
  [ "$status" -eq 1 ]
}

# ── 3 · arm_goal: THREE VERDICTS, AND IT NEVER FAILS THE FIRE ──────────────────────────────────

@test "arm_goal with no condition does nothing and says nothing" {
  it2_paste_submit_verified() { echo "PASTED" >&3; return 0; }
  run arm_goal /bin/true 900 ''
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -s "$LOG" ]
}

@test "verdict=set — pasted AND read back from the session's own transcript" {
  command -v jq >/dev/null 2>&1 || skip "verdict rows need jq"
  STUB_SID=s4 _write_goal_transcript s4 'finish the brief'
  it2_paste_submit_verified() { return 0; }
  STUB_SID=s4 run arm_goal /bin/true 900 'finish the brief'
  [ "$status" -eq 0 ]
  [[ "$output" == *"goal-arm verdict=set"* ]] || false
  run jq -r '[.class,.verdict]|@tsv' "$LOG"
  [ "$output" = "$(printf 'goal-arm\tset')" ]
}

@test "verdict=abstained — the paste refused (pane not provably a live CC composer)" {
  command -v jq >/dev/null 2>&1 || skip "verdict rows need jq"
  it2_paste_submit_verified() { return 1; }
  STUB_SID=s5 run arm_goal /bin/true 900 'finish the brief'
  [ "$status" -eq 0 ]                              # ← never fails the fire
  [[ "$output" == *"goal-arm verdict=abstained"* ]] || false
  [[ "$output" == *"HAS its brief and is working"* ]] || false
  run jq -r '.verdict' "$LOG"
  [ "$output" = "abstained" ]
}

@test "verdict=unverified — submitted, but NO goal_status ever appeared (never called 'armed')" {
  command -v jq >/dev/null 2>&1 || skip "verdict rows need jq"
  : > "$PDIR/s6.jsonl"
  it2_paste_submit_verified() { return 0; }
  STUB_SID=s6 run arm_goal /bin/true 900 'finish the brief'
  [ "$status" -eq 0 ]
  [[ "$output" == *"goal-arm verdict=unverified"* ]] || false
  [[ "$output" != *"verdict=set"* ]] || false
  run jq -r '.verdict' "$LOG"
  [ "$output" = "unverified" ]
}

@test "verdict=abstained when there is no pane to paste into at all" {
  it2_paste_submit_verified() { echo "SHOULD NOT PASTE" >&2; return 0; }
  run arm_goal /bin/true '' 'finish the brief'
  [ "$status" -eq 0 ]
  [[ "$output" == *"verdict=abstained"* ]] || false
  [[ "$output" != *"SHOULD NOT PASTE"* ]]
}

# ── 4 · THE LEDGER ROW MUST NOT POLLUTE THE ENGAGEMENT METRIC ──────────────────────────────────
#
# emit_fire_event writes `engaged:false` on every non-admit row, and `engaged` is the numerator of
# the V2 M-1 engagement rate. A goal-arm row is written only AFTER engagement was proven, so it says
# nothing about engagement; borrowing that schema would deflate the metric by one row per armed
# goal. R9: an unmeasured field reads ABSENT, never false.
@test "a goal-arm row carries NO 'engaged' key — it is not evidence about engagement" {
  command -v jq >/dev/null 2>&1 || skip "row shape needs jq"
  run emit_goal_event set 'pane 900'
  [ "$status" -eq 0 ]
  run jq -r 'has("engaged")' "$LOG"
  [ "$output" = "false" ]
  run jq -r '[.class,.gate,.verdict]|@tsv' "$LOG"
  [ "$output" = "$(printf 'goal-arm\tgoal\tset')" ]
  # …and it is still distinguishable from a REFUSAL, which the same log carries.
  run jq -rs '[.[]|select(.class=="refused")]|length' "$LOG"
  [ "$output" = "0" ]
}

# ── 5 · THE PAYLOAD GATE IS UNTOUCHED (constraint 1) ───────────────────────────────────────────
#
# The whole point of --goal is that it works ALONGSIDE check_slash_head, not by relaxing it. If a
# later change ever "simplifies" this by admitting a /goal head, this goes red.
@test "check_slash_head still refuses a /goal-headed payload — --goal did NOT weaken it" {
  printf '/goal ship it\n\nand here is the brief\n' > "$BATS_TEST_TMPDIR/p.md"
  run check_slash_head "$BATS_TEST_TMPDIR/p.md"
  [ "$status" -eq 1 ]
  printf 'TASK — ship it.\n\nSTEP 3: /goal is armed separately.\n' > "$BATS_TEST_TMPDIR/q.md"
  run check_slash_head "$BATS_TEST_TMPDIR/q.md"
  [ "$status" -eq 0 ]
}

# ── 5 · RECYCLE GOAL INHERITANCE (2026-08-10) ────────────────────────────────────────────────────
# A goal is session-scoped and dies with the /exit a recycle types (§3.4 of the research doc), and
# the wave recipe now REQUIRES a goal on every fired session — so a --recycle with no --goal
# inherits the predecessor's LIVE condition. These pin the oracle (goal_live_for_sid) and every
# branch of the decision (inherit_recycle_goal).

_write_terminal_goal_transcript() { # $1=sid — armed then ACHIEVED: nothing live to inherit
  { jq -cn '{type:"attachment",attachment:{type:"goal_status",met:false,sentinel:true,condition:"old"}}'
    jq -cn '{type:"attachment",attachment:{type:"goal_status",met:true,condition:"old",iterations:2}}'
  } > "$PDIR/$1.jsonl"
}

@test "goal_live_for_sid reads a LIVE condition from the NESTED per-cwd transcript" {
  _write_goal_transcript "sid-live-1" "land wave 5 — proven by ship-land verdict"
  run goal_live_for_sid "sid-live-1"
  [ "$status" -eq 0 ]
  [ "$output" = "land wave 5 — proven by ship-land verdict" ]
}

@test "goal_live_for_sid returns NOTHING for a terminal goal (met — last record wins)" {
  _write_terminal_goal_transcript "sid-done-1"
  run goal_live_for_sid "sid-done-1"
  [ "$status" -eq 1 ]
}

@test "goal_live_for_sid is not fooled by PROSE about goals (no attachment ⇒ no goal)" {
  printf '{"type":"assistant","message":{"content":[{"type":"text","text":"a goal_status with met false is the arm marker"}]}}\n' > "$PDIR/sid-prose-1.jsonl"
  run goal_live_for_sid "sid-prose-1"
  [ "$status" -eq 1 ]
}

@test "inherit: empty FIRE_GOAL + live predecessor goal ⇒ inherited verbatim" {
  _write_goal_transcript "sid-inh-1" "finish the audit — proven by the gate summary"
  FIRE_GOAL=""
  inherit_recycle_goal "sid-inh-1"
  [ "$FIRE_GOAL" = "finish the audit — proven by the gate summary" ]
}

@test "inherit: an EXPLICIT --goal always wins over the predecessor's" {
  _write_goal_transcript "sid-inh-2" "the old contract"
  FIRE_GOAL="the operator's new contract"
  inherit_recycle_goal "sid-inh-2"
  [ "$FIRE_GOAL" = "the operator's new contract" ]
}

@test "inherit: CC_RECYCLE_GOAL_INHERIT=0 opts out entirely" {
  _write_goal_transcript "sid-inh-3" "should never be read"
  FIRE_GOAL=""
  CC_RECYCLE_GOAL_INHERIT=0 inherit_recycle_goal "sid-inh-3"
  [ -z "$FIRE_GOAL" ]
}

@test "inherit: a TERMINAL predecessor goal inherits nothing" {
  _write_terminal_goal_transcript "sid-inh-4"
  FIRE_GOAL=""
  inherit_recycle_goal "sid-inh-4"
  [ -z "$FIRE_GOAL" ]
}

@test "inherit: a condition the paste path cannot carry is REFUSED, loudly, never armed corrupt" {
  # A multi-line condition would submit at its first CR, stranding the rest in the composer —
  # check_goal_arm refuses it pre-fire, and inheritance must land in the same refusal.
  # Built with jq: the value must carry a REAL newline behind a single valid JSONL line — a raw
  # printf '\n' would break the line and make the transcript unreadable instead (a different test).
  jq -cn '{type:"attachment",attachment:{type:"goal_status",met:false,sentinel:true,condition:"line one\nline two"}}' \
    > "$PDIR/sid-inh-5.jsonl"
  FIRE_GOAL=""
  run inherit_recycle_goal "sid-inh-5"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'NOT inherited' || false
  # and the mutation direction: FIRE_GOAL must be EMPTY afterwards in the calling shell too
  inherit_recycle_goal "sid-inh-5"
  [ -z "$FIRE_GOAL" ]
}

@test "inherit: never fails the recycle (unknown sid ⇒ rc 0, FIRE_GOAL untouched)" {
  FIRE_GOAL=""
  run inherit_recycle_goal "sid-that-never-existed"
  [ "$status" -eq 0 ]
}
