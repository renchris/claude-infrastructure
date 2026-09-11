#!/usr/bin/env bats
# propose-goal-flag-watch.sh — the standing watch behind cc-backlog `2a65b9bf722d`.
#
# WHY THIS SUITE EXISTS. The subject is a FALSIFIER: its whole job is to stay quiet for months and
# then, once, say "the flag flipped". A falsifier that can never fire is indistinguishable from one
# that is merely still waiting, and that is precisely the state the row was already in —
# `docs/research/propose-goal-flag-recheck-2026-09-10.md` §5 records that "without [the true-flag
# arms] a probe that always returns `false` looks identical to a correct one, and this row would be
# waiting on a falsifier that cannot fire". So the load-bearing cases here are the ones where the
# expected verdict is RETRACT, not the ones where it is "keep waiting".
#
# THE THREE STATES THE SUBJECT MUST KEEP APART, because the stored one-liner keeps only two:
#   flag true on a fresh cache          → rc 0   RETRACT
#   flag off on a fresh cache           → rc 1   keep waiting
#   nothing fresh / nothing readable    → rc 2   NON-VERDICT — "nobody asked", not "off"
# Measured 2026-09-11 on a cloud VM, the stored probe answers the third case by printing the word
# `false` and exiting 2 (its desk-shaped glob matches no file there, jq fails to open the literal
# path). A consumer reading the printed word, or reading only `rc != 0`, cannot tell that from a
# genuine negative — which is the defect. G1-G3 pin the separation; M3 proves they can see it lost.
#
# RED-PROOF. Every load-bearing assertion is proved by MUTATION: a copy of the real subject is
# deranged at the exact line the assertion depends on, and the test asserts the verdict inverts. Each
# mutant is checked to have applied EXACTLY ONCE (a mutant anchored on a string that is absent, or on
# one that is not unique, silently applies to nothing and the green that follows proves nothing) and
# to still parse (`bash -n`), so a mutation that no-ops or breaks the file cannot pass for a control.
#
# NOT A RED-PROOF, and marked as such: the whole-selftest case (G0) and the still-off cases are
# EQUIVALENCE guards — they would pass against several wrong implementations, and they earn their
# place only because the mutants below show which assertions actually discriminate.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SUBJ="$REPO/scripts/propose-goal-flag-watch.sh"
  [ -f "$SUBJ" ] || { echo "missing $SUBJ"; return 1; }
  T="$BATS_TEST_TMPDIR"
  NOW=1789000000
  FRESH=$(( (NOW - 3600) * 1000 ))
  STALE=$(( (NOW - 30 * 86400) * 1000 ))

  printf '{"cachedGrowthBookFeaturesAt":%d,"cachedGrowthBookFeatures":{"tengu_propose_goal":true}}\n'  "$FRESH" > "$T/fresh_true.json"
  printf '{"cachedGrowthBookFeaturesAt":%d,"cachedGrowthBookFeatures":{"tengu_propose_goal":false}}\n' "$FRESH" > "$T/fresh_false.json"
  printf '{"cachedGrowthBookFeaturesAt":%d,"cachedGrowthBookFeatures":{"tengu_other":1}}\n'            "$FRESH" > "$T/fresh_absent.json"
  printf '{"cachedGrowthBookFeaturesAt":%d,"cachedGrowthBookFeatures":{"tengu_propose_goal":true}}\n'  "$STALE" > "$T/stale_true.json"

  printf 'function xyz(){return I("tengu_propose_goal",!1)}\ntengu_other\nProposeGoal\n' > "$T/bin_off"
  printf 'function q9(){return I("tengu_propose_goal",!0)}\ntengu_other\nProposeGoal\n'  > "$T/bin_on"
  printf 'tengu_other\nProposeGoal used here\n'                                          > "$T/bin_minified"
  printf 'tengu_other\nnothing of interest\n'                                            > "$T/bin_removed"
  printf 'nothing of interest at all\n'                                                  > "$T/bin_wrongsubject"
}

# Runs a subject (real or mutant) with a fixtured population and no binary arm.
run_f() {
  local subj="$1"; shift
  PGW_NOW="$NOW" PGW_CONFIG_PATHS="$1" PGW_CLAUDE_BIN='' bash "$subj" --falsify
}

# Derange a copy of the subject. Asserts the anchor occurs EXACTLY once before editing, and that the
# result still parses — the two ways a mutant silently proves nothing.
#
# The replacement is LITERAL, done in python rather than with awk's `sub()` or sed: every anchor here
# is shell source full of `[`, `$`, `(`, `|` and `//`, and a regex engine reads those as operators.
# The first draft of this helper used `sub()` and three of four mutants either compiled to a
# different pattern or failed to match — one of them still passing `cmp` because the mangled pattern
# happened to change some other byte. That is the "applied to NOTHING" failure wearing a green coat.
mutate() {
  local name="$1" anchor="$2" replacement="$3" out="$T/mut_$1.sh"
  ANCHOR="$anchor" REPL="$replacement" OUT="$out" SUBJ="$SUBJ" python3 - <<'PY' || return 1
import os, sys
src = open(os.environ["SUBJ"]).read()
a, r = os.environ["ANCHOR"], os.environ["REPL"]
n = src.count(a)
if n != 1:
    sys.exit(f"anchor occurs {n}x in the subject, want exactly 1")
open(os.environ["OUT"], "w").write(src.replace(a, r))
PY
  cmp -s "$SUBJ" "$out" && { echo "mutant $name applied to NOTHING"; return 1; }
  bash -n "$out" || { echo "mutant $name does not parse"; return 1; }
  printf '%s\n' "$out"
}

# ── G0 · the subject's own fixture table ──────────────────────────────────────────────────────────
@test "G0 --selftest is green (18 arms: §5's cache table + §4's binary table)" {
  run bash "$SUBJ" --selftest
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"0 failed"* ]] || false
  [[ "$output" == *"18 ok"* ]] || false
}

# ── G1-G3 · the three states, which is the whole point ────────────────────────────────────────────
@test "G1 fresh cache with the flag TRUE retracts the row (rc 0)" {
  run run_f "$SUBJ" "$T/fresh_true.json"
  [ "$status" -eq 0 ] || false
}

@test "G2 fresh cache with the flag off keeps the row open (rc 1)" {
  run run_f "$SUBJ" "$T/fresh_false.json"
  [ "$status" -eq 1 ] || false
  run run_f "$SUBJ" "$T/fresh_absent.json"
  [ "$status" -eq 1 ] || false
}

@test "G3 nothing fresh, and nothing readable, are NON-VERDICTS (rc 2) — not negatives" {
  run run_f "$SUBJ" "$T/stale_true.json"
  [ "$status" -eq 2 ] || false                     # stale-only: the flag may well be on
  run run_f "$SUBJ" "$T/nonexistent.json"
  [ "$status" -eq 2 ] || false                     # the cloud-VM shape the stored glob hits
  printf 'not json\n' > "$T/broken.json"
  run run_f "$SUBJ" "$T/broken.json"
  [ "$status" -eq 2 ] || false
}

@test "G4 a fresh observation beats a stale one, in both directions" {
  run run_f "$SUBJ" "$T/stale_true.json"$'\n'"$T/fresh_absent.json"
  [ "$status" -eq 1 ] || false                     # the newer observation wins → off
  run run_f "$SUBJ" "$T/stale_true.json"$'\n'"$T/fresh_true.json"
  [ "$status" -eq 0 ] || false                     # a fresh true still retracts
}

# ── G5 · the printed row, which is where the value conflation would show ──────────────────────────
@test "G5 key-present-and-false renders as false, never as ABSENT" {
  # jq's `//` treats a literal `false` as null, so the obvious spelling reports a key that is present
  # and off as if the account had never been in the experiment. Both read rc 1, so only the RENDERED
  # row can tell them apart — which is why this assertion is on the text and not on the status.
  run env PGW_NOW="$NOW" PGW_CONFIG_PATHS="$T/fresh_false.json" PGW_CLAUDE_BIN='' bash "$SUBJ" --report
  [[ "$output" == *"tengu_propose_goal=false"* ]] || { echo "$output"; false; }
  run env PGW_NOW="$NOW" PGW_CONFIG_PATHS="$T/fresh_absent.json" PGW_CLAUDE_BIN='' bash "$SUBJ" --report
  [[ "$output" == *"tengu_propose_goal=ABSENT"* ]] || { echo "$output"; false; }
}

@test "G6 every cache is named in the report, so one blind member cannot hide behind the others" {
  run env PGW_NOW="$NOW" PGW_CONFIG_PATHS="$T/fresh_absent.json"$'\n'"$T/stale_true.json" \
      PGW_CLAUDE_BIN='' bash "$SUBJ" --report
  [[ "$output" == *"fresh_absent.json"* ]] || false
  [[ "$output" == *"stale_true.json"* ]] || false
  [[ "$output" == *"STALE"* ]] || false
}

# ── G7 · the binary arm, keyed on the ARGUMENT because the symbol moves every release ─────────────
@test "G7 the gate is read by its argument, not its symbol (mct → cgt → syt, three releases)" {
  run env PGW_CLAUDE_BIN="$T/bin_off" bash "$SUBJ" --binary
  [ "$status" -eq 1 ] || false
  run env PGW_CLAUDE_BIN="$T/bin_on" bash "$SUBJ" --binary
  [ "$status" -eq 0 ] || false
  # the fixtures carry DIFFERENT minified symbols on purpose: a reader keyed on `cgt` sees neither
  run env PGW_CLAUDE_BIN="$T/bin_off" bash "$SUBJ" --report
  [[ "$output" == *'function xyz(){return I("tengu_propose_goal",!1)}'* ]] || false
}

@test "G8 a gate that does not match is only a removal when the feature is really gone" {
  run env PGW_CLAUDE_BIN="$T/bin_minified" bash "$SUBJ" --binary
  [ "$status" -eq 0 ] || false                     # present but minified past the pattern → look
  run env PGW_CLAUDE_BIN="$T/bin_removed" bash "$SUBJ" --binary
  [ "$status" -eq 3 ] || false                     # absent from a verified subject → removed
  run env PGW_CLAUDE_BIN="$T/bin_wrongsubject" bash "$SUBJ" --binary
  [ "$status" -eq 2 ] || false                     # tripwire fails → wrong subject, not a removal
  run env PGW_CLAUDE_BIN='' bash "$SUBJ" --binary
  [ "$status" -eq 2 ] || false                     # set-but-empty disables the arm verbatim
}

# ── M1-M4 · the mutants. Each derangement must invert a verdict above. ────────────────────────────
@test "M1 deleting the freshness filter turns a stale cache into a live reading" {
  local m; m="$(mutate freshness \
      '[ "$ts_ms" -gt 0 ] && [ "$age" -lt "$PGW_MAXAGE_S" ]; then' \
      'true; then')" || { echo "$m"; false; }
  run run_f "$m" "$T/stale_true.json"
  [ "$status" -eq 0 ] || { echo "mutant did not invert G3's stale-only arm (got $status, want 0)"; false; }
  run run_f "$SUBJ" "$T/stale_true.json"
  [ "$status" -eq 2 ] || false                     # control: the real subject still abstains
}

@test "M2 deleting the tripwire mints a false 'feature removed' from the wrong subject" {
  local m; m="$(mutate tripwire \
      '[ "$PGW_TRIPWIRE" -gt 0 ] || return 2' \
      ':')" || { echo "$m"; false; }
  run env PGW_CLAUDE_BIN="$T/bin_wrongsubject" bash "$m" --binary
  [ "$status" -eq 3 ] || { echo "mutant did not invert G8's tripwire arm (got $status, want 3)"; false; }
  run env PGW_CLAUDE_BIN="$T/bin_wrongsubject" bash "$SUBJ" --binary
  [ "$status" -eq 2 ] || false
}

@test "M3 collapsing the NON-VERDICT into 'off' reproduces the stored probe's defect" {
  # This mutant IS the incumbent: rc 2 folded into rc 1 is exactly what a consumer sees today when
  # it reads `rc != 0` as "keep waiting" without asking whether anything was read at all.
  local m; m="$(mutate nonverdict \
      '[ "$PGW_N_FRESH" -gt 0 ] && return 1' \
      '[ "$PGW_N_FRESH" -ge 0 ] && return 1')" || { echo "$m"; false; }
  run run_f "$m" "$T/nonexistent.json"
  [ "$status" -eq 1 ] || { echo "mutant did not invert G3's empty-population arm (got $status, want 1)"; false; }
  run run_f "$m" "$T/fresh_true.json"
  [ "$status" -eq 0 ] || false                     # the mutant still fires on a true flag …
  run run_f "$SUBJ" "$T/nonexistent.json"
  [ "$status" -eq 2 ] || false                     # … which is why only the rc-2 case attributes it
}

@test "M4 reading the flag with jq's // reports present-and-false as ABSENT" {
  local m; m="$(mutate slashslash \
      'elif (.cachedGrowthBookFeatures | has("tengu_propose_goal")) then (.cachedGrowthBookFeatures.tengu_propose_goal | tostring)' \
      'elif ((.cachedGrowthBookFeatures.tengu_propose_goal // null) != null) then (.cachedGrowthBookFeatures.tengu_propose_goal | tostring)')" \
      || { echo "$m"; false; }
  run env PGW_NOW="$NOW" PGW_CONFIG_PATHS="$T/fresh_false.json" PGW_CLAUDE_BIN='' bash "$m" --report
  [[ "$output" == *"tengu_propose_goal=ABSENT"* ]] || { echo "mutant did not invert G5 -- $output"; false; }
  run env PGW_NOW="$NOW" PGW_CONFIG_PATHS="$T/fresh_false.json" PGW_CLAUDE_BIN='' bash "$SUBJ" --report
  [[ "$output" == *"tengu_propose_goal=false"* ]] || false
}

# ── G9 · the contract the row's consumers actually read ───────────────────────────────────────────
@test "G9 --report never exits 0 unless an arm is signalling" {
  run env PGW_NOW="$NOW" PGW_CONFIG_PATHS="$T/fresh_absent.json" PGW_CLAUDE_BIN="$T/bin_off" bash "$SUBJ" --report
  [ "$status" -eq 1 ] || false
  run env PGW_NOW="$NOW" PGW_CONFIG_PATHS="$T/fresh_true.json" PGW_CLAUDE_BIN="$T/bin_off" bash "$SUBJ" --report
  [ "$status" -eq 0 ] || false
  run env PGW_NOW="$NOW" PGW_CONFIG_PATHS="$T/fresh_absent.json" PGW_CLAUDE_BIN="$T/bin_on" bash "$SUBJ" --report
  [ "$status" -eq 0 ] || false                     # a binary signal alone is enough to look
  run env PGW_NOW="$NOW" PGW_CONFIG_PATHS="$T/stale_true.json" PGW_CLAUDE_BIN="$T/bin_off" bash "$SUBJ" --report
  [ "$status" -eq 2 ] || false                     # an instrument that could not answer outranks "off"
}

@test "G10 the subject writes nothing outside its own scratch dir" {
  local before after
  before="$(cd "$REPO" && git status --porcelain | sort)"
  run env PGW_NOW="$NOW" PGW_CONFIG_PATHS="$T/fresh_absent.json" PGW_CLAUDE_BIN="$T/bin_off" bash "$SUBJ" --report
  [ "$status" -eq 1 ] || false
  run bash "$SUBJ" --selftest
  [ "$status" -eq 0 ] || false
  after="$(cd "$REPO" && git status --porcelain | sort)"
  [ "$before" = "$after" ] || { echo "subject dirtied the tree"; false; }
}
