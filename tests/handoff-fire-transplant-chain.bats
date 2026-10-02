#!/usr/bin/env bats
# handoff-fire.sh hf_transplant_evidence — THE CHAIN TIP (LIMIT_RECOVER_FLEET_V2 W5, lead decision 90%).
#
# A TARGET-LIMITED or TARGET-AUTH hop moves an already-moved session again, so A→B→C leaves one
# tombstone in A and one in B. The pane is a husk over the CHAIN TIP — the tombstone whose
# destination store holds no tombstone for the sid. Zero tips, several tips, a cycle and a missing
# destination store still refuse with the "disambiguate by hand" message.
#
# Harness: the two functions extracted from the real script; fixture config dirs under
# $BATS_TEST_TMPDIR; no pane, no registry, nothing typed.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd -P)"
  HF="$REPO/scripts/handoff-fire.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_FIRE_CAPACITY_GATE=off
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/sweep.json"
  export CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/absent-accounts"
  export CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/heal-"
  eval "$(sed -n '/^hf_ts_chain_tip() {/,/^}/p; /^hf_transplant_evidence() {/,/^}/p' "$HF")"
  command -v hf_ts_chain_tip >/dev/null && command -v hf_transplant_evidence >/dev/null
  T="$BATS_TEST_TMPDIR"
  SID="aaaaaaaa-1111-2222-3333-444444444444"
  LOCK="$T/lock"; : > "$LOCK"
  for c in a b c d; do mkdir -p "$T/cfg-$c/projects/-p"; done
}

# tomb <from> <to> — a tombstone in cfg-<from> handing the session to cfg-<to>
tomb() {
  printf '{"handed_off_to":"%s","lock":"%s"}\n' "$T/cfg-$2" "$LOCK" > "$T/cfg-$1/projects/-p/$SID.HANDOFF.json"
}
roots() { echo "$T/cfg-a/projects $T/cfg-b/projects $T/cfg-c/projects $T/cfg-d/projects"; }
evidence() { hf_transplant_evidence "$SID" "$(roots)" --recycle "" 2>"$T/err"; }

@test "one tombstone: today's single-hop evidence, unchanged" {
  tomb a b
  evidence
  [ "$HF_TS_TOMBSTONE" = "$T/cfg-a/projects/-p/$SID.HANDOFF.json" ]
  [ "$HF_TS_TO" = "$T/cfg-b" ]
  [ "$HF_TS_CFG" = "$T/cfg-a" ]
}

@test "2-hop A→B→C resolves to the tip (B's tombstone): source B, destination C" {
  tomb a b; tomb b c
  evidence
  [ "$HF_TS_TOMBSTONE" = "$T/cfg-b/projects/-p/$SID.HANDOFF.json" ] || { cat "$T/err"; false; }
  [ "$HF_TS_TO" = "$T/cfg-c" ]
  [ "$HF_TS_CFG" = "$T/cfg-b" ]
  grep -q "the chain tip is" "$T/err"
}

@test "2-hop A→B→C where B is a mirror config dir (B/projects is a symlink to M/projects) resolves to the tip" {
  # 2026-10-02, pane 30: next2→next→next4. ~/.claude-next/projects → ~/.claude/projects, the hop
  # named .claude-next, and the onward tombstone was enumerated under .claude/projects first.
  mkdir -p "$T/cfg-m/projects/-p"; rm -rf "$T/cfg-b/projects"; ln -s "$T/cfg-m/projects" "$T/cfg-b/projects"
  tomb a b
  printf '{"handed_off_to":"%s","lock":"%s"}\n' "$T/cfg-c" "$LOCK" > "$T/cfg-m/projects/-p/$SID.HANDOFF.json"
  hf_transplant_evidence "$SID" "$T/cfg-m/projects $(roots)" --recycle "" 2>"$T/err" || { cat "$T/err"; false; }
  [ "$HF_TS_TOMBSTONE" = "$T/cfg-m/projects/-p/$SID.HANDOFF.json" ] || { cat "$T/err"; false; }
  [ "$HF_TS_TO" = "$T/cfg-c" ]
}

@test "3-hop A→B→C→D resolves to the tip (C's tombstone), whatever order the roots list them" {
  tomb a b; tomb b c; tomb c d
  evidence
  [ "$HF_TS_TOMBSTONE" = "$T/cfg-c/projects/-p/$SID.HANDOFF.json" ] || { cat "$T/err"; false; }
  [ "$HF_TS_TO" = "$T/cfg-d" ]
  hf_transplant_evidence "$SID" "$T/cfg-d/projects $T/cfg-c/projects $T/cfg-b/projects $T/cfg-a/projects" --recycle "" 2>/dev/null
  [ "$HF_TS_TOMBSTONE" = "$T/cfg-c/projects/-p/$SID.HANDOFF.json" ]
}

@test "a fork (A→C and B→D, two tips) refuses and says disambiguate by hand" {
  tomb a c; tomb b d
  run hf_transplant_evidence "$SID" "$(roots)" --recycle ""
  [ "$status" -eq 2 ]
  [[ "$output" == *"2 chain tips (a fork)"*"disambiguate by hand"* ]] || { echo "$output"; false; }
}

@test "two tombstones into one store (A→C and B→C) refuse as a fork" {
  tomb a c; tomb b c
  run hf_transplant_evidence "$SID" "$(roots)" --recycle ""
  [ "$status" -eq 2 ]
  [[ "$output" == *"(a fork)"*"disambiguate by hand"* ]] || { echo "$output"; false; }
}

@test "a cycle (A→B→A) has no tip and refuses" {
  tomb a b; tomb b a
  run hf_transplant_evidence "$SID" "$(roots)" --recycle ""
  [ "$status" -eq 2 ]
  [[ "$output" == *"(a cycle)"*"disambiguate by hand"* ]] || { echo "$output"; false; }
}

@test "a cycle beside a chain (A↔B plus C→D) refuses: the walk from the tip misses two tombstones" {
  tomb a b; tomb b a; tomb c d
  run hf_transplant_evidence "$SID" "$(roots)" --recycle ""
  [ "$status" -eq 2 ]
  [[ "$output" == *"reaches 1 of 3 tombstones (a cycle)"* ]] || { echo "$output"; false; }
}

@test "a missing destination store refuses" {
  tomb a b; tomb b c
  printf '{"handed_off_to":"%s","lock":"%s"}\n' "$T/cfg-gone" "$LOCK" > "$T/cfg-b/projects/-p/$SID.HANDOFF.json"
  run hf_transplant_evidence "$SID" "$(roots)" --recycle ""
  [ "$status" -eq 2 ]
  [[ "$output" == *"destination store $T/cfg-gone/projects is missing"*"disambiguate by hand"* ]] || { echo "$output"; false; }
}

@test "the tip still needs its split-brain lock" {
  tomb a b; tomb b c
  rm "$LOCK"
  run hf_transplant_evidence "$SID" "$(roots)" --recycle ""
  [ "$status" -eq 2 ]
  [[ "$output" == *"split-brain lock is gone"* ]] || { echo "$output"; false; }
}
