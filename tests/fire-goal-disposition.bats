#!/usr/bin/env bats
# fire-goal-disposition.bats — EVERY FIRE RECORDS ITS GOAL DISPOSITION, 2026-08-09.
#
# WHY THIS SUITE EXISTS, and it is not really about goals.
#
# The /goal regression cost eight days and a full investigation session, and the reason it was
# invisible is NOT that a guard was missing — `check_slash_head` worked perfectly and logged ZERO
# refusals across the whole corpus. Producers silently STOPPED EMITTING, and NOTHING COUNTS A
# NON-EMISSION. Recovering the 20.0%→3.0% adoption fact needed a hand sweep of 137 provably-fired
# sessions out of a 1,901-transcript corpus (docs/research/goal-in-handoff-2026-08-08.md §1.1).
#
# The fix for that regression then shipped in exactly the same shape: `--goal` wrote a `goal-arm`
# row when a goal WAS requested and NOTHING when it was not. Countable numerator, no denominator —
# so "what fraction of fires carry a goal?" was still a corpus sweep. These tests pin the three
# properties that close it, each keyed to a defect this repo has already paid for:
#
#   1. THE DENOMINATOR IS A MEASURED FALSE, not an absence. `goal_requested` is on every fire row as
#      a JSON boolean — including the jq-less fallback, because "the rows jq happened to write" is
#      not a population anyone would think to split on.
#   2. "COULD NOT ASK" ≠ "ASKED AND GOT NO" (memory sensor-default-off-makes-blindness-the-shipping-
#      path — one probe value standing for both fabricated 80 of 156 findings). A goal requested on a
#      fire that died before message 2 lands verdict=unreachable, naming the BRANCH at the source
#      (memory rollback-of-an-unstarted-attempt-convicts-the-subject), never a silent absence that
#      reads identically to a fire that asked for nothing.
#   3. A SUCCESSFUL RECYCLE IS VISIBLE. `ENGAGE_VERIFY` is hard-wired 0 for recycles, so the fire
#      row never ran on that path and the two recycle callers wrote only on FAILURE — measured
#      2026-08-09, 1012 ledger rows over 41h carried ZERO recycle rows of any class while --recycle
#      is the commonest succession on this box. Same non-emission, one function over.
#
# The functions are extracted VERBATIM from scripts/handoff-fire.sh and sourced, so every assertion
# is against the LITERAL emission rather than a hand-written approximation that could pass while the
# live shape drifts (memory control-must-replay-the-real-artifact).

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HF="$REPO/scripts/handoff-fire.sh"
  HOME="$BATS_TEST_TMPDIR/home"; export HOME
  mkdir -p "$HOME/.claude/logs"
  LOG="$HOME/.claude/logs/handoffs.jsonl"
  # M11 — pin the machine terms off; nothing here fires, but an ambient gate must never decide a
  # verdict on box load rather than on the tree.
  export CC_FIRE_CAPACITY_GATE=off
  export CC_FIRE_HEADROOM_GATE=off
  # Hermeticity seams (scripts/test-hermeticity-lint.sh). A fixtured $HOME does NOT redirect an
  # absolute /tmp default, nor a bare name the subject resolves off the operator's PATH — so these
  # are pinned to ABSENT paths, where the sensors that read them fail open. Nothing here fires.
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/account-sweep.json"
  export CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/no-such-claude-accounts"
  export CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/heal-"
  # The bats process runs inside a CC session that likely EXPORTS SESSION_ID, and FIRE_GOAL is the
  # subject under test — clear the slate so every "unset" case is real and every "set" case comes
  # only from its own per-call prefix.
  unset SESSION_ID FIRING_SID FIRE_GOAL WANT_SELF_RETIRE SPAWNED_PANE CHOSEN 2>/dev/null || true
  FUNCS="$BATS_TEST_TMPDIR/funcs.sh"
  {
    grep '^_iso_now() {' "$HF" || true
    sed -n '/^_under_test() {/,/^}/p'              "$HF"
    sed -n '/^emit_fire_event() {/,/^}/p'          "$HF"
    sed -n '/^_fire_gate_of() {/,/^}/p'            "$HF"
    sed -n '/^emit_fire_refusal() {/,/^}/p'        "$HF"
    sed -n '/^emit_gate_admit() {/,/^}/p'          "$HF"
    sed -n '/^emit_goal_event() {/,/^}/p'          "$HF"
    sed -n '/^goal_unreachable() {/,/^}/p'         "$HF"
    sed -n '/^emit_recycle_event() {/,/^}/p'       "$HF"
    sed -n '/^  emit_handoff_telemetry() {/,/^  }$/p' "$HF"
  } > "$FUNCS"
  bash -n "$FUNCS" || { echo "extraction from $HF is not valid bash" >&2; return 1; }
  # shellcheck disable=SC1090
  . "$FUNCS"
}

# ── 1 · THE DENOMINATOR ────────────────────────────────────────────────────────────────────────
#
# The load-bearing case is the FALSE one. A fire that deliberately carried no goal is the row the
# ledger never had, and it is the entire denominator of the adoption rate.

@test "a fire with NO --goal records goal_requested:false — the row that did not exist" {
  command -v jq >/dev/null 2>&1 || skip "row shape needs jq"
  FIRING_SID="cc-sid-a" SPAWNED_PANE="pane-A" CHOSEN="next" emit_handoff_telemetry 1
  run jq -r '.goal_requested' "$LOG"
  [ "$output" = "false" ]
  # …and it is PRESENT, not merely falsy. `// false` on an absent key yields the same string, so a
  # test that only read the value would pass against a producer that emits nothing at all.
  run jq -r 'has("goal_requested")' "$LOG"
  [ "$output" = "true" ]
}

@test "a fire WITH --goal records goal_requested:true" {
  command -v jq >/dev/null 2>&1 || skip "row shape needs jq"
  FIRE_GOAL="finish the brief" FIRING_SID="cc-sid-b" SPAWNED_PANE="pane-B" CHOSEN="next2" \
    emit_handoff_telemetry 1
  run jq -r '.goal_requested' "$LOG"
  [ "$output" = "true" ]
}

@test "goal_requested is a JSON BOOLEAN, never the strings 'true'/'false'" {
  command -v jq >/dev/null 2>&1 || skip "row shape needs jq"
  FIRE_GOAL="x" emit_handoff_telemetry 1
  run jq -r '.goal_requested|type' "$LOG"
  [ "$output" = "boolean" ]
}

@test "goal_requested survives a FAILED fire (engaged=0) — a fire that asked still counted" {
  command -v jq >/dev/null 2>&1 || skip "row shape needs jq"
  FIRE_GOAL="x" SPAWNED_PANE="pane-C" emit_handoff_telemetry 0
  run jq -r '[.engaged,(.goal_requested|tostring)]|@tsv' "$LOG"
  [ "$output" = "$(printf '0\ttrue')" ]
}

@test "the jq-less FALLBACK row carries goal_requested too — the denominator has no hole" {
  # A denominator computed over "the rows jq wrote" is not a denominator, and nothing downstream
  # would think to split on it. A jq-less PATH is BUILT, not approximated by trimming: jq ships in
  # /usr/bin on this box as well as in the brew prefix, so `PATH=/usr/bin:/bin` still resolves it and
  # the "fallback" case would silently have exercised the jq path instead — a vacuous pass.
  nojq="$BATS_TEST_TMPDIR/nojq"; mkdir -p "$nojq"
  for b in bash mkdir date ps cat; do ln -sf "$(command -v "$b")" "$nojq/$b"; done
  # exit 9 is the SELF-CONTROL: if jq is still resolvable under this PATH the case aborts loudly
  # instead of passing for the wrong reason.
  run env PATH="$nojq" FIRE_GOAL="x" SPAWNED_PANE="pane-D" CHOSEN="next3" \
      bash -c ". '$FUNCS'; command -v jq >/dev/null 2>&1 && exit 9; emit_handoff_telemetry 1"
  [ "$status" -eq 0 ]
  run grep -c '"goal_requested":true' "$LOG"
  [ "$output" = "1" ]
  # …and the fallback is genuinely the path that ran: the jq row carries `started_at`, this one does not.
  run grep -c 'started_at' "$LOG"
  [ "$output" = "0" ]
}

# MUTATION CONTROL. Every assertion above passes vacuously if it cannot fail — so delete the field
# from the real emitter, at exactly one anchor, and prove the suite's own predicate goes red
# (memory per-site-mutation-attributes-coverage: a malformed mutant reddens everything and reads as
# maximal coverage, so the mutant is syntax-checked and the anchor is matched exactly once).
@test "CONTROL: strip goal_requested from the emitter and the denominator assertion FAILS" {
  command -v jq >/dev/null 2>&1 || skip "control needs jq"
  MUT="$BATS_TEST_TMPDIR/mutant.sh"
  run grep -c '^         + {goal_requested:  \$gr}$' "$FUNCS"
  [ "$output" = "1" ]                                  # the anchor exists exactly once
  grep -v '^         + {goal_requested:  \$gr}$' "$FUNCS" > "$MUT"
  bash -n "$MUT"                                       # a broken mutant proves nothing
  run env FIRE_GOAL="x" bash -c ". '$MUT'; emit_handoff_telemetry 1; jq -r 'has(\"goal_requested\")' '$LOG'"
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]                              # ← the live assertion's inverse
}

# ── 2 · "COULD NOT ASK" IS NOT "ASKED AND GOT NO" ──────────────────────────────────────────────

@test "goal_unreachable is a NO-OP when no goal was requested — it cannot become a nudge" {
  # The anti-alarm property, asserted rather than promised. A row (or a warning) on every goal-less
  # fire would fire on ~97% of fires measured — the same zero bits as an alarm that never fires
  # (memory alarm-polarity-and-attention-budget).
  run goal_unreachable never-engaged
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -s "$LOG" ]
}

@test "a requested goal on a fire that never reached message 2 → verdict=unreachable, branch named" {
  command -v jq >/dev/null 2>&1 || skip "verdict rows need jq"
  FIRE_GOAL="finish the brief" run goal_unreachable pane-wedged
  [ "$status" -eq 0 ]
  run jq -r '[.class,.gate,.verdict]|@tsv' "$LOG"
  [ "$output" = "$(printf 'goal-arm\tgoal\tunreachable')" ]
  # WHY, recorded at the SOURCE — the branch's own name — not left to be inferred from an absence.
  run jq -r '.detail' "$LOG"
  [[ "$output" == *"pane-wedged"* ]] || false
}

@test "unreachable is DISTINGUISHABLE from abstained — the two silences never collapse" {
  command -v jq >/dev/null 2>&1 || skip "verdict rows need jq"
  FIRE_GOAL="x" goal_unreachable never-engaged
  emit_goal_event abstained "arming paste refused/abstained for pane P"
  run jq -rs 'map(.verdict)|join(",")' "$LOG"
  [ "$output" = "unreachable,abstained" ]
  # A consumer counting "we asked and it did not take" must see exactly ONE — the abstained row.
  # Folding unreachable into it would convict the arming path for a failure that happened upstream.
  run jq -rs '[.[]|select(.verdict=="abstained")]|length' "$LOG"
  [ "$output" = "1" ]
}

@test "an unreachable row carries NO 'engaged' key — it is not evidence about engagement" {
  command -v jq >/dev/null 2>&1 || skip "row shape needs jq"
  FIRE_GOAL="x" goal_unreachable recycle-dead
  run jq -r 'has("engaged")' "$LOG"
  [ "$output" = "false" ]
}

# ── 3 · A SUCCESSFUL RECYCLE LEAVES A ROW ──────────────────────────────────────────────────────

@test "emit_recycle_engaged writes class recycle-engaged with engaged:TRUE" {
  command -v jq >/dev/null 2>&1 || skip "row shape needs jq"
  FIRING_SID="cc-sid-r" CHOSEN="next4" emit_recycle_event recycle-engaged 1 "pane-R" "recycled in place"
  run jq -r '[.class,(.engaged|tostring),.target_pane,.gate]|@tsv' "$LOG"
  [ "$output" = "$(printf 'recycle-engaged\ttrue\tpane-R\trecycle')" ]
}

@test "the recycle row does NOT borrow emit_fire_event's engaged:false (a fabricated outcome)" {
  command -v jq >/dev/null 2>&1 || skip "row shape needs jq"
  emit_recycle_event recycle-engaged 1 "pane-R" "recycled in place"
  emit_recycle_event recycle-dead 0 "pane-R" "no assistant turn"
  # `engaged` is the numerator of the V2 M-1 rate. An ENGAGEMENT-CONFIRMED recycle filed as
  # engaged:false would deflate it by one row per successful recycle — the commonest succession.
  run jq -rs 'map(.engaged|tostring)|join(",")' "$LOG"
  [ "$output" = "true,false" ]
}

@test "the recycle row carries goal_requested, so recycles join the same denominator" {
  command -v jq >/dev/null 2>&1 || skip "row shape needs jq"
  FIRE_GOAL="finish the brief" emit_recycle_event recycle-engaged 1 "pane-R" "recycled in place"
  run jq -r '.goal_requested' "$LOG"
  [ "$output" = "true" ]
}

# ── 4 · THE PUBLISHED QUERY ACTUALLY RUNS ──────────────────────────────────────────────────────
#
# The whole claim of this change is "one ledger query with a real denominator, no corpus sweep".
# A claim like that is prose until something executes it, and this repo has shipped a spec-named
# mechanism that existed only in prose before (memory spec-named-mechanism-may-be-prose-only). This
# is the query from the emit_handoff_telemetry header comment, run over a synthetic mixed ledger
# that also carries the row classes a naive grep would wrongly sweep in.

@test "the adoption-rate query returns a real numerator AND denominator over a mixed ledger" {
  command -v jq >/dev/null 2>&1 || skip "the query needs jq"
  FIRE_GOAL="x" SPAWNED_PANE="p1" emit_handoff_telemetry 1                 # fire, with a goal
  SPAWNED_PANE="p2" emit_handoff_telemetry 1                               # fire, no goal
  SPAWNED_PANE="p3" emit_handoff_telemetry 1                               # fire, no goal
  FIRE_GOAL="x" emit_recycle_event recycle-engaged 1 "p4" "recycled"       # recycle, with a goal
  emit_fire_event admitted measured "load 1.2/core" admit capacity         # NOT a fire outcome
  emit_fire_refusal capacity "load over ceiling"                           # NOT a fire outcome
  FIRE_GOAL="x" goal_unreachable never-engaged                             # NOT a fire outcome
  run jq -rs '[.[]|select(.class=="handoff" or .class=="self-retire-peer" or .class=="recycle-engaged")]
              | group_by(.goal_requested) | map({(.[0].goal_requested|tostring): length}) | add | tojson' "$LOG"
  [ "$output" = '{"false":2,"true":2}' ]
}

# ── 5 · TASK 3 · THE DENOMINATOR IS 45% TEST ROWS, AND NOTHING MARKED THEM ─────────────────────
#
# Suites that do not export HOME write into the operator's LIVE ledger. Measured 2026-08-09:
# 107/237 refusals carry a /Users/chrisren/.claude/bin/cc-bats fingerprint, 0 of 109 payload-gate refusals came from a real fire,
# and 453/633 admits carry basis:"gate-off" — a basis only CC_FIRE_CAPACITY_GATE=off produces,
# which 88 test files set and no production caller does. The published admit-ratio query therefore
# reads 84.4% against 58.9% over production rows alone: a 25.5-point error in the exact metric the
# admit side was added to make provable (MACHINE_CAPACITY_V2 §9.5, retracted twice).

@test "under_test is TRUE on every row a /Users/chrisren/.claude/bin/cc-bats run writes — the contamination becomes countable" {
  command -v jq >/dev/null 2>&1 || skip "row shape needs jq"
  emit_fire_refusal capacity "load over ceiling"
  emit_gate_admit capacity measured "load 1.2/core"
  emit_goal_event set "pane P"
  emit_recycle_event recycle-engaged 1 "pane-R" "recycled"
  emit_handoff_telemetry 1
  # BATS_TEST_TMPDIR is exported by the harness running this very case, so this is the real signal.
  run jq -rs 'map(.under_test)|unique|@csv' "$LOG"
  [ "$output" = "true" ]
  run jq -rs 'length' "$LOG"
  [ "$output" = "5" ]                                  # …and every emitter is covered, not just one
}

@test "under_test is FALSE with no /Users/chrisren/.claude/bin/cc-bats variables present — it measures the env, not intent" {
  command -v jq >/dev/null 2>&1 || skip "row shape needs jq"
  run env -u BATS_TEST_TMPDIR -u BATS_VERSION -u BATS_TEST_FILENAME HOME="$HOME" \
      bash -c ". '$FUNCS'; emit_fire_refusal capacity 'load over ceiling'"
  [ "$status" -eq 0 ]
  run jq -r '.under_test' "$LOG"
  [ "$output" = "false" ]
}

@test "under_test is a BOOLEAN on every class, so one predicate splits the whole ledger" {
  command -v jq >/dev/null 2>&1 || skip "row shape needs jq"
  emit_gate_admit capacity measured "load 1.2/core"
  emit_recycle_event recycle-dead 0 "pane-R" "no assistant turn"
  emit_handoff_telemetry 1
  run jq -rs 'map(.under_test|type)|unique|@csv' "$LOG"
  [ "$output" = "\"boolean\"" ]
}

@test "the production-only admit ratio is computable — the query the retractions needed" {
  command -v jq >/dev/null 2>&1 || skip "the query needs jq"
  # Two production rows (no /Users/chrisren/.claude/bin/cc-bats vars) and two test rows, all four in one ledger. Without the field
  # the ratio reads 50%; with it, production reads 100% admit and the test rows fall out.
  env -u BATS_TEST_TMPDIR -u BATS_VERSION -u BATS_TEST_FILENAME HOME="$HOME" \
      bash -c ". '$FUNCS'; emit_gate_admit capacity measured 'load 1.2/core'; emit_gate_admit capacity measured 'load 1.3/core'"
  emit_fire_refusal capacity "load over ceiling"
  emit_fire_refusal capacity "load over ceiling"
  run jq -rs '[.[]|select(.gate=="capacity")]|group_by(.verdict)|map({(.[0].verdict):length})|add|tojson' "$LOG"
  [ "$output" = '{"admit":2,"refuse":2}' ]
  run jq -rs '[.[]|select(.gate=="capacity" and (.under_test|not))]|group_by(.verdict)|map({(.[0].verdict):length})|add|tojson' "$LOG"
  [ "$output" = '{"admit":2}' ]
}

# ── 6 · TASK 3 · A RECYCLE THAT COULD NOT BE VERIFIED IS NOT A RECYCLE THAT FAILED ─────────────

@test "recycle-unverified carries NO engaged key — 'could not ask', never a measured negative" {
  command -v jq >/dev/null 2>&1 || skip "row shape needs jq"
  # This branch is reached BECAUSE nothing was handed over to verify against. emit_fire_event, its
  # previous emitter, hard-codes engaged:false — a measured negative for a question never asked,
  # landing in the numerator of the V2 M-1 engagement rate.
  emit_recycle_event recycle-unverified "" "pane-R" "no marker/baseline handed to the watcher"
  run jq -r 'has("engaged")' "$LOG"
  [ "$output" = "false" ]
  run jq -r '.class' "$LOG"
  [ "$output" = "recycle-unverified" ]
}

@test "the three recycle verdicts are engaged true / false / ABSENT — a real tri-state" {
  command -v jq >/dev/null 2>&1 || skip "row shape needs jq"
  emit_recycle_event recycle-engaged   1  "pane-R" "a real assistant turn"
  emit_recycle_event recycle-dead      0  "pane-R" "no assistant turn in window"
  emit_recycle_event recycle-unverified "" "pane-R" "nothing to verify against"
  run jq -rs 'map([.class,(if has("engaged") then (.engaged|tostring) else "ABSENT" end)]|join(":"))|join(" ")' "$LOG"
  [ "$output" = "recycle-engaged:true recycle-dead:false recycle-unverified:ABSENT" ]
}

@test "prev_sid makes a recycle joinable — firing_sid is null by construction in the watcher" {
  command -v jq >/dev/null 2>&1 || skip "row shape needs jq"
  # The __recycle re-exec never reaches the FIRING_SID assignment, so firing_sid:null is not a bug
  # to fix here — the identity of a recycle is (pane, predecessor→successor), and $6 carries it.
  RCY_OLD_SID="sid-before" emit_recycle_event recycle-engaged 1 "pane-R" "recycled"
  run jq -r '[.prev_sid,.target_pane,(.firing_sid|tostring)]|@tsv' "$LOG"
  [ "$output" = "$(printf 'sid-before\tpane-R\tnull')" ]
}

@test "prev_sid is NULL, not empty-string, when the watcher was handed no baseline" {
  command -v jq >/dev/null 2>&1 || skip "row shape needs jq"
  emit_recycle_event recycle-unverified "" "pane-R" "nothing to verify against"
  run jq -r '.prev_sid|type' "$LOG"
  [ "$output" = "null" ]
}

# ── 7 · TASK 3 · THE TRIM DESTROYED DATA AND SAID NOTHING ──────────────────────────────────────
#
# The only data-destroying operation in the file, and the only one with no record. The budget is
# class-blind, so one heavy /Users/chrisren/.claude/bin/cc-bats day (456 admits on 2026-08-08) silently evicts a day of production
# fire history — which is exactly the "13 samples in one high-variance window" failure the bound was
# doubled to fix, re-created by test rows.

@test "a trim leaves a class:trim row naming what it dropped, per class" {
  command -v jq >/dev/null 2>&1 || skip "the trim row needs jq"
  # 1205 synthetic rows of two classes, so the drop is 205 and its per-class split is known exactly.
  for i in $(seq 1 1100); do printf '{"ts":"2026-08-09T00:00:%02dZ","class":"admitted"}\n' "$((i % 60))"; done > "$LOG"
  for i in $(seq 1 104); do printf '{"ts":"2026-08-09T01:00:%02dZ","class":"refused"}\n' "$((i % 60))"; done >> "$LOG"
  [ "$(wc -l < "$LOG" | tr -d ' ')" = "1204" ]
  SPAWNED_PANE="pane-T" emit_handoff_telemetry 1       # 1205 → over the 1200 bound → trims
  run jq -rs '[.[]|select(.class=="trim")]|length' "$LOG"
  [ "$output" = "1" ]
  run jq -rs '[.[]|select(.class=="trim")][0]|[.kept,(.dropped.admitted)]|@tsv' "$LOG"
  [ "$output" = "$(printf '1000\t205')" ]
}

@test "the trim row is written AFTER the trim, so it survives the trim it describes" {
  command -v jq >/dev/null 2>&1 || skip "the trim row needs jq"
  for i in $(seq 1 1204); do printf '{"ts":"2026-08-09T00:00:%02dZ","class":"admitted"}\n' "$((i % 60))"; done > "$LOG"
  SPAWNED_PANE="pane-T" emit_handoff_telemetry 1
  run tail -1 "$LOG"
  [[ "$output" == *'"class":"trim"'* ]] || false
  # 1000 kept + the trim row itself. A trim row written before the mv would not be here at all.
  run bash -c "wc -l < '$LOG' | tr -d ' '"
  [ "$output" = "1001" ]
}

@test "window_starts_at names the oldest SURVIVING row — the coverage a rate must be quoted with" {
  command -v jq >/dev/null 2>&1 || skip "the trim row needs jq"
  for i in $(seq 1 1204); do printf '{"ts":"2026-08-09T00:%02d:00Z","class":"admitted"}\n' "$((i % 60))"; done > "$LOG"
  SPAWNED_PANE="pane-T" emit_handoff_telemetry 1
  run jq -rs '[.[]|select(.class=="trim")][0].window_starts_at' "$LOG"
  [ -n "$output" ]
  # It is the FIRST surviving row's ts, not the trimmed file's old head.
  run bash -c "head -1 '$LOG' | jq -r .ts"
  first="$output"
  run jq -rs '[.[]|select(.class=="trim")][0].window_starts_at' "$LOG"
  [ "$output" = "$first" ]
}

@test "NO trim row when the ledger is under the bound — this cannot become a per-fire row" {
  command -v jq >/dev/null 2>&1 || skip "the trim row needs jq"
  SPAWNED_PANE="pane-T" emit_handoff_telemetry 1
  run jq -rs '[.[]|select(.class=="trim")]|length' "$LOG"
  [ "$output" = "0" ]
}

@test "CONTROL: BSD head refuses a negative count — the GNU spelling would have shipped broken" {
  # `head -n -1000` reads correct and is what a GNU-shaped fix would use. On this platform it is an
  # error, so the drop-census would have been empty on every trim, forever, silently
  # (memory prescribed-remedy-worse-than-the-bug: run the prescription in the context that executes it).
  run bash -c "printf 'a\nb\nc\n' | head -n -1"
  [ "$status" -ne 0 ]
  [[ "$output" == *"illegal line count"* ]] || false
  # …and the shipped emitter uses the portable spelling instead.
  run grep -c 'head -n "\$_hf_ndrop"' "$FUNCS"
  [ "$output" = "1" ]
}
