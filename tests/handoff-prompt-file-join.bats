#!/usr/bin/env bats
# handoff-prompt-file-join.bats — EVERY FIRE ROW NAMES THE BRIEF IT WAS MADE FROM, 2026-08-18.
#
# WHY THIS SUITE EXISTS. BACKLOG_DRAIN_24_7 §2.1 (recycle #19) DECLINED to build the "a brief was
# written but never fired" detector, and recorded why: *"its detector needs to answer 'was a fire
# ever made FROM this brief', and no row in handoffs.jsonl records a prompt-file path, so the
# linking primitive does not exist. Building the sweep without it would have shipped a heuristic
# alarm over an attention budget."* That is the decline this suite's subject repays — the ledger
# recorded the surface, the account, the RSS, the engagement latency and the goal disposition of
# every fire, and never once recorded which file the fire was fired FROM.
#
# Four properties, each keyed to a way the naive one-line version would have been wrong:
#
#   1. THE AUTHOR'S PATH, NEVER THE TRAILER'S COPY. The prompt trailer (handoff-fire.sh:7263)
#      copies the payload to a `mktemp` and reassigns PROMPT_FILE to it on every non-dry fire AND
#      every non-dry recycle. So a field that recorded a bare PROMPT_FILE would read
#      `…/handoff-prompt-nb-XXXXXX` on essentially every production row — a path no brief is ever
#      written to and no detector can join on. The field would have existed and answered nothing.
#   2. A REFUSED FIRE CARRIES IT TOO. `written and never attempted` and `written, attempted,
#      refused by a gate` are different facts. If only the success row carried the path, the
#      detector would alarm loudest on the briefs that DID try — an alarm over an attention budget
#      (memory alarm-polarity-and-attention-budget), which is the exact outcome the decline avoided.
#   3. THE RECYCLE ROW CARRIES IT, ACROSS A PROCESS BOUNDARY. `--recycle` is the commonest
#      succession on this box and never reaches emit_handoff_telemetry (ENGAGE_VERIFY is hard-wired
#      0 for recycles), and its row is written by a DETACHED `__recycle` re-exec where
#      PROMPT_FILE/PROMPT_FILE_ORIG are unset by construction. A join covering only the peer-fire
#      row would be blind to exactly the `fire-drain-recycle<N>.txt` chain of §4.1 — the drain
#      program's own briefs.
#   4. UNMEASURED READS null, NOT "" (R9). The pre-parse gates refuse before PROMPT_FILE exists at
#      all; `null` says "this refusal is not about any brief" instead of inventing an empty string
#      that joins against nothing and counts as a value.
#
# RED-PROOF (recorded 2026-08-18, per case, against the pristine pre-change scripts/handoff-fire.sh
# recovered with `git show origin/main:scripts/handoff-fire.sh` — 9,341 lines, 0 occurrences of
# `prompt_file`): ALL NINE not-ok. Every case reddens for the same underlying reason, that no
# emitter wrote the key at all.
#
# CASE 9 IS THE ONE TO READ HONESTLY, and the correction is recorded rather than laundered. It is
# labelled a CONTROL and the first draft of this header claimed it was "green in both directions by
# design". The red-proof refuted that: it fails pre-change on `KeyError: 'prompt_file'`, because it
# reads the key before it can judge the escaping. That does NOT make it a proof of the feature —
# the property it actually guards (a `"` or `\` in a path cannot corrupt the jq-less line) is
# UNPROVABLE against the pristine tree, for the plainest possible reason: there is no field there
# to corrupt, so the subject of the assertion does not yet exist. It is the inverse of the trap
# BACKLOG_DRAIN_24_7 §2.1 (recycle #18) paid for — *"ask of every green pre-fix case whether its
# subject even exists yet"* — and the answer here is no, which is why its red says nothing about
# the escaping either way. It stays because that escaping is hand-rolled and the blast radius of
# getting it wrong is the whole file, not one key; it is a regression guard, not evidence.
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
  # An EMPTY PATH dir, for the two fallback cases. Reaching the jq-less branch the way production
  # does means making jq unresolvable, and every other external the emitter touches on that path
  # (mkdir, cat, ps, date) is already `|| true`-guarded or has a builtin answer — which is the
  # property those cases incidentally confirm.
  mkdir -p "$BATS_TEST_TMPDIR/emptybin"
  # M11 — pin the machine terms off; nothing here fires, but an ambient gate must never decide a
  # verdict on box load rather than on the tree.
  export CC_FIRE_CAPACITY_GATE=off
  export CC_FIRE_HEADROOM_GATE=off
  # Hermeticity seams (scripts/test-hermeticity-lint.sh): pinned to ABSENT paths, where the sensors
  # that read them fail open. Nothing here fires.
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/account-sweep.json"
  export CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/no-such-claude-accounts"
  export CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/heal-"
  # The bats process runs inside a CC session that likely EXPORTS SESSION_ID, and the two PROMPT_FILE
  # globals are the subject under test — clear the slate so every "unset" case is real and every
  # "set" case comes only from its own per-call prefix.
  unset SESSION_ID FIRING_SID FIRE_GOAL WANT_SELF_RETIRE SPAWNED_PANE CHOSEN \
        PROMPT_FILE PROMPT_FILE_ORIG RCY_PROMPT_FILE RCY_OLD_SID 2>/dev/null || true
  FUNCS="$BATS_TEST_TMPDIR/funcs.sh"
  {
    grep '^_iso_now() {' "$HF" || true
    sed -n '/^_under_test() {/,/^}/p'              "$HF"
    sed -n '/^emit_fire_event() {/,/^}/p'          "$HF"
    sed -n '/^_fire_gate_of() {/,/^}/p'            "$HF"
    sed -n '/^emit_fire_refusal() {/,/^}/p'        "$HF"
    sed -n '/^emit_recycle_event() {/,/^}/p'       "$HF"
    sed -n '/^  emit_handoff_telemetry() {/,/^  }$/p' "$HF"
  } > "$FUNCS"
  bash -n "$FUNCS" || { echo "extraction from $HF is not valid bash" >&2; return 1; }
  # shellcheck disable=SC1090
  . "$FUNCS"
}

# ── 1 · THE AUTHOR'S PATH WINS ────────────────────────────────────────────────────────────────
#
# The load-bearing case in the whole suite. In production PROMPT_FILE_ORIG is set on essentially
# every real fire, so if precedence ran the other way the field would be a mktemp path fleet-wide
# and the detector it exists for would join zero rows while looking perfectly healthy.

@test "the fire row records the AUTHOR's brief, not the trailer's mktemp copy" {
  command -v jq >/dev/null 2>&1 || skip "row shape needs jq"
  PROMPT_FILE_ORIG="/tmp/fire-drain-recycle20.txt" \
  PROMPT_FILE="/tmp/handoff-prompt-nb-Ab3xQ1" \
  FIRING_SID="cc-sid-a" SPAWNED_PANE="pane-A" CHOSEN="next" emit_handoff_telemetry 1
  run jq -r '.prompt_file' "$LOG"
  [ "$output" = "/tmp/fire-drain-recycle20.txt" ]
}

@test "with no trailer copy the fire row records PROMPT_FILE itself" {
  command -v jq >/dev/null 2>&1 || skip "row shape needs jq"
  # --dry-run and the pre-trailer branches never make a copy, so ORIG is legitimately unset there
  # and the bare PROMPT_FILE *is* the author's path.
  PROMPT_FILE="/tmp/fire-probe.txt" \
  FIRING_SID="cc-sid-b" SPAWNED_PANE="pane-B" CHOSEN="next2" emit_handoff_telemetry 1
  run jq -r '.prompt_file' "$LOG"
  [ "$output" = "/tmp/fire-probe.txt" ]
}

# ── 2 · UNMEASURED READS null, AND IS PRESENT ─────────────────────────────────────────────────

@test "a row with no brief in scope emits prompt_file:null — present, not absent, not empty" {
  command -v jq >/dev/null 2>&1 || skip "row shape needs jq"
  FIRING_SID="cc-sid-c" SPAWNED_PANE="pane-C" CHOSEN="next3" emit_handoff_telemetry 0
  run jq -r '.prompt_file' "$LOG"
  [ "$output" = "null" ]
  # …and the KEY is present. `.prompt_file` on an absent key prints "null" too, so a case that only
  # read the value would pass against a producer that emits nothing at all — the exact non-emission
  # this whole family of fields exists to make countable.
  run jq -r 'has("prompt_file")' "$LOG"
  [ "$output" = "true" ]
  # null, never "". An empty string is a VALUE: it joins against nothing and counts as one.
  run jq -r '.prompt_file == ""' "$LOG"
  [ "$output" = "false" ]
}

# ── 3 · A REFUSED FIRE IS NOT A NEVER-FIRED BRIEF ─────────────────────────────────────────────

@test "a gate REFUSAL carries the brief — attempted-and-refused is distinguishable from never-fired" {
  command -v jq >/dev/null 2>&1 || skip "row shape needs jq"
  PROMPT_FILE_ORIG="/tmp/fire-refused.txt" PROMPT_FILE="/tmp/handoff-prompt-nb-ZZ" \
    emit_fire_refusal capacity "load 4.10/core over bar"
  run jq -r '.prompt_file' "$LOG"
  [ "$output" = "/tmp/fire-refused.txt" ]
  # The refusal's own identity is untouched by the added key.
  run jq -r '.verdict + " " + .gate' "$LOG"
  [ "$output" = "refuse capacity" ]
}

@test "a refusal raised BEFORE the payload is parsed reads null, not a stale or invented path" {
  command -v jq >/dev/null 2>&1 || skip "row shape needs jq"
  # The pre-parse gates (handoff-fire.sh:6245 and earlier) refuse while both globals are still
  # unset. `null` is the honest answer: this refusal is not about any brief.
  emit_fire_refusal cloud-quota "no account had headroom"
  run jq -r '.prompt_file' "$LOG"
  [ "$output" = "null" ]
  run jq -r 'has("prompt_file")' "$LOG"
  [ "$output" = "true" ]
}

# ── 4 · THE RECYCLE ROW, ACROSS THE PROCESS BOUNDARY ──────────────────────────────────────────

@test "a recycle row carries the brief handed to the detached watcher as RCY_PROMPT_FILE" {
  command -v jq >/dev/null 2>&1 || skip "row shape needs jq"
  # This is the __recycle re-exec's world: neither PROMPT_FILE nor PROMPT_FILE_ORIG is assigned
  # there (its argv is `__recycle SID tty cmdfile …`), so the ONLY way the author's brief reaches
  # this row is the positional slot the foreground passes. Without it the drain chain's own
  # recycles — the commonest fire class on the box — would all read null.
  RCY_PROMPT_FILE="/tmp/fire-drain-recycle21.txt" RCY_OLD_SID="cc-sid-prev" \
    emit_recycle_event recycle-engaged 1 "pane-R" "relaunch typed"
  run jq -r '.prompt_file' "$LOG"
  [ "$output" = "/tmp/fire-drain-recycle21.txt" ]
  run jq -r '.class + " " + (.engaged|tostring)' "$LOG"
  [ "$output" = "recycle-engaged true" ]
}

@test "in the FOREGROUND a recycle row still prefers the author's path over RCY_PROMPT_FILE" {
  command -v jq >/dev/null 2>&1 || skip "row shape needs jq"
  # emit_recycle_event runs in two processes. The precedence must not invert when both worlds'
  # variables happen to be visible at once — the author's path is the answer in either.
  PROMPT_FILE_ORIG="/tmp/fire-author.txt" PROMPT_FILE="/tmp/handoff-prompt-nb-QQ" \
  RCY_PROMPT_FILE="/tmp/fire-stale-watcher-arg.txt" \
    emit_recycle_event recycle-dead 0 "pane-S" "no turn in window"
  run jq -r '.prompt_file' "$LOG"
  [ "$output" = "/tmp/fire-author.txt" ]
}

# ── 5 · THE jq-LESS FALLBACK ──────────────────────────────────────────────────────────────────

@test "the jq-less fallback line carries prompt_file too — and is still valid JSON" {
  command -v python3 >/dev/null 2>&1 || skip "fallback shape check needs python3"
  # Force the fallback the way production reaches it: jq unresolvable on PATH. "The rows jq
  # happened to write" is not a population anyone would think to split on, and a join key with a
  # jq-shaped hole in it silently under-reports fires.
  PATH="$BATS_TEST_TMPDIR/emptybin" \
  PROMPT_FILE_ORIG="/tmp/fire-nojq.txt" \
  FIRING_SID="cc-sid-d" SPAWNED_PANE="pane-D" CHOSEN="next4" emit_handoff_telemetry 1
  run cat "$LOG"
  [[ "$output" == *'"prompt_file":"/tmp/fire-nojq.txt"'* ]] || false
  run python3 -c "import json,sys; json.loads(open(sys.argv[1]).read().strip())" "$LOG"
  [ "$status" -eq 0 ]
}

# ── 6 · CONTROL — the escaping, not the field ─────────────────────────────────────────────────

@test "CONTROL: a path holding a quote and a backslash cannot break the fallback's JSON" {
  command -v python3 >/dev/null 2>&1 || skip "fallback shape check needs python3"
  # Green in BOTH directions by construction — pre-change there was no field to corrupt — so this
  # is a guard on the hand-rolled escaping, never a proof of the feature. It earns its place
  # because this is the one field on that path whose value is not controlled by us: an unescaped
  # `"` there does not lose one key, it makes the reader that hits it drop or die on the WHOLE file.
  PATH="$BATS_TEST_TMPDIR/emptybin" \
  PROMPT_FILE_ORIG='/tmp/fire-"odd"\name.txt' \
  FIRING_SID="cc-sid-e" SPAWNED_PANE="pane-E" CHOSEN="next" emit_handoff_telemetry 1
  run python3 -c "import json,sys; print(json.loads(open(sys.argv[1]).read().strip())['prompt_file'])" "$LOG"
  [ "$status" -eq 0 ]
  [ "$output" = '/tmp/fire-"odd"\name.txt' ]
}
