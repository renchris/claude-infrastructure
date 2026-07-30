#!/usr/bin/env bats
# handoff-fire.sh — PAYLOAD LEGIBILITY GATES + REFUSAL TELEMETRY
# (docs/plans/SESSION_LIFECYCLE_V2.md §5.5 and §6 F5 / F13 / M-11).
#
# All three mechanisms here exist because a real safeguard was being performed BY HAND, or not at all:
#
#   F5  — the /goal-over-cap trap. NOTE: the guard for this ALREADY EXISTED (check_slash_head,
#         handoff-fire.sh:1112) — see the METHOD CORRECTION below. What this row adds is the refusal
#         RECORD (F13), because the hard-fail exited before any telemetry and left no trace.
#
#   M-11 — scripts/pane-id-lint.sh has existed on trunk with ZERO call sites: orphaned detection, not
#         a gate. R11: a truncated pane id is strictly worse than a stale one — stale-full fails loud
#         and still mailboxes, truncated hard-fails unresolvable (a measured cc-notify exit 3) — and
#         truncation enters at AUTHORING time, which makes the payload the right chokepoint.
#
#   F13 — every pre-fire gate exits BEFORE spawn and therefore before any telemetry, so a refusal
#         wrote nothing at all. The capacity gate is live-by-default via the ~/.claude/scripts symlink
#         and refuses whenever load exceeds 2.0/core (load ranged 15-41 on 10 cores today), so the
#         fleet can stop firing while handoffs.jsonl shows only silence. "No fires logged" and "no
#         fires attempted" were the same bits.
#
# SCOPE NOTE that is load-bearing: the pane-id gate is PAYLOAD-scoped, never corpus-scoped. The live
# docs corpus carries 28 violations across 12+ files owned by other rows, so a corpus-scoped gate
# would refuse every fire on the box over somebody else's file — a fleet-wide hard stop.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HF="$REPO/scripts/handoff-fire.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude/logs"
  PF="$BATS_TEST_TMPDIR/payload.md"

  {
    grep '^_iso_now() {' "$HF" || true
    sed -n '/^emit_fire_refusal() {/,/^}/p'     "$HF"
    sed -n '/^check_slash_head() {/,/^}/p'      "$HF"
    sed -n '/^payload_pane_id_gate() {/,/^}/p'  "$HF"
  } > "$BATS_TEST_TMPDIR/units.sh"
  bash -n "$BATS_TEST_TMPDIR/units.sh" || { echo "extraction from $HF is not valid bash" >&2; return 1; }
  HF_DIR="$REPO/scripts"
  # shellcheck disable=SC1091
  . "$BATS_TEST_TMPDIR/units.sh"
  LOG="$HOME/.claude/logs/handoffs.jsonl"
}

# ── F5: the leading slash command — the guard that ALREADY EXISTED ──────────────────────────────
#
# METHOD CORRECTION, recorded rather than quietly fixed. This suite first shipped a NEW
# `payload_slash_gate`, on the strength of a measurement that `payload_lint_gate` contains no
# slash check. That measurement was true and the conclusion was wrong: `check_slash_head`
# (handoff-fire.sh:1112, called at the pre-spawn guard block) has always hard-failed the exact
# /goal-over-cap case. I greped one function and asserted a file-wide absence — the "negative
# tool-claim" trap my own standing rules name explicitly. The duplicate was removed; these tests
# pin the REAL guard instead, so a future reader cannot repeat the mistake by finding no coverage.
#
# What check_slash_head actually does, and why the asymmetry is defensible: a `/goal` head with a
# payload over the 4000-char cap is REJECTED by the harness, so it HARD-FAILS (exit 1). Any other
# slash head, or a /goal under the cap, still functions — those WARN. F13's contribution is that the
# hard-fail now also leaves a record, which it did not before.

@test "F5: the pre-existing guard hard-fails a /goal head whose payload exceeds the cap" {
  { printf '/goal ship it\n'; head -c 5000 /dev/zero | tr '\0' 'x'; } > "$PF"
  run check_slash_head "$PF"
  [ "$status" -eq 1 ]
  [[ "$output" == *"HARD-CAPS"* ]] || false
}

@test "F5: a /goal head UNDER the cap warns but is admitted — a short goal genuinely works" {
  printf '/goal fire→engaged p95 <=60s\n' > "$PF"
  run check_slash_head "$PF"
  [ "$status" -eq 0 ]
  [[ "$output" == *"starts with the slash command"* ]] || false
}

@test "F5 POSITIVE CONTROL: the shape the campaign actually uses (plain prose first) is silent" {
  printf 'YOUR TASK — a ground-up rebuild of ONE subsystem.\n\nScope (frozen): ...\n\nSTEP 1: /goal ...\n' > "$PF"
  run check_slash_head "$PF"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "F5 + F13: the /goal hard-fail now leaves a REFUSAL RECORD (it left none before)" {
  { printf '/goal ship it\n'; head -c 5000 /dev/zero | tr '\0' 'x'; } > "$PF"
  run check_slash_head "$PF"
  [ "$status" -eq 1 ]
  [ -s "$LOG" ]
  run jq -r '[.class,.refuse_reason]|@tsv' "$LOG"
  [ "$output" = "$(printf 'refused\tpayload-goal-cap')" ]
}

# ── M-11: truncated pane ids in the payload ─────────────────────────────────────────────────────

@test "M-11: a payload carrying a truncated pane id is REFUSED (the lint finally has a call site)" {
  printf 'ping the orchestrator pane 99261468 when done\n' > "$PF"
  run payload_pane_id_gate "$PF"
  [ "$status" -eq 3 ]
  [[ "$output" == *"TRUNCATED pane id"* ]] || false
  [[ "$output" == *"ROLE token"* ]] || false
}

@test "M-11: the all-digit real prefix is caught — the forbidden hex-letter shortcut would miss it" {
  # 99261468 is a REAL pane-uuid prefix and is all digits; it is the exact truncation that caused the
  # cc-notify exit-3 hard-fail. Requiring a hex letter for precision would false-negative it, which is
  # why tests/pane-id-lint.bats pins it and why this gate must inherit that behaviour rather than
  # reimplement a looser regex.
  printf 'pane 99261468\n' > "$PF"
  run payload_pane_id_gate "$PF"
  [ "$status" -eq 3 ]
}

@test "M-11 POSITIVE CONTROL: a FULL uuid is the sanctioned historical form and is ADMITTED" {
  printf 'fired by 71B42B48-1331-4F60-8DA3-6849F2682CA2 (historical fact)\n' > "$PF"
  run payload_pane_id_gate "$PF"
  [ "$status" -eq 0 ]
}

@test "M-11: a benign 8-digit date is not mistaken for a pane id" {
  printf 'rotated on 20260729 and again later\n' > "$PF"
  run payload_pane_id_gate "$PF"
  [ "$status" -eq 0 ]
}

@test "M-11 A11 kill switch: CC_PANE_ID_GATE=0 admits, and the switch is what does it" {
  printf 'pane 99261468\n' > "$PF"
  CC_PANE_ID_GATE=0 run payload_pane_id_gate "$PF"
  [ "$status" -eq 0 ]
  run payload_pane_id_gate "$PF"
  [ "$status" -eq 3 ]
}

@test "M-11: an unresolvable lint degrades to ADMIT rather than blocking every fire on the box" {
  printf 'pane 99261468\n' > "$PF"
  # ALL THREE resolver paths must be blanked, not just the script-relative one. A first version of
  # this test only overrode HF_DIR and still refused — because CLAUDE_CONFIG_DIR resolved the lint out
  # of ~/.claude-next/scripts, which on the eval track is a REAL directory of copies rather than
  # symlinks. That is worth knowing: the second path is live, so a lint fix landed in the checkout is
  # NOT automatically the one an eval-track session runs.
  HF_DIR="$BATS_TEST_TMPDIR/nowhere" CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/nowhere" \
    run payload_pane_id_gate "$PF"
  [ "$status" -eq 0 ]
  # POSITIVE CONTROL: with the real resolver the same payload IS refused, so the admit above is the
  # degradation path and not a broken gate.
  run payload_pane_id_gate "$PF"
  [ "$status" -eq 3 ]
}

# ── F13: a refused fire leaves a record ─────────────────────────────────────────────────────────

@test "F13: emit_fire_refusal writes a parseable class=refused line" {
  FIRING_SID="abc-123" CHOSEN="next" emit_fire_refusal capacity "load/core over ceiling 2.0"
  [ -s "$LOG" ]
  run jq -r '[.class,.refuse_reason,.firing_sid,.account,(.engaged|tostring)]|@tsv' "$LOG"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'refused\tcapacity\tabc-123\tnext\tfalse')" ]
}

@test "F13 R9: an unknown firing session is null, never the ambiguous \"?\" string" {
  FIRING_SID="" CHOSEN="" emit_fire_refusal capacity ""
  run jq -r '[(.firing_sid|type),(.account|type),(.detail|type)]|@tsv' "$LOG"
  [ "$output" = "$(printf 'null\tnull\tnull')" ]
}

@test "F13: a load-blocked fleet is DISTINGUISHABLE from a quiet one (the whole point)" {
  # Before this, both states produced an identical empty tail. Now the reason is on the record, so
  # "why did the fleet stop firing" is answerable from the log alone.
  emit_fire_refusal capacity "load/core over ceiling 2.0"
  emit_fire_refusal payload-slash-command "first line is a slash command"
  run jq -rs 'map(select(.class=="refused")|.refuse_reason)|join(",")' "$LOG"
  [ "$output" = "capacity,payload-slash-command" ]
  # and a quiet fleet writes nothing at all — absence still means absence
  : > "$LOG"
  run jq -rs 'length' "$LOG"
  [ "$output" = "0" ]
}

@test "F13 kill switch + never-fatal: CC_FIRE_REFUSAL_LOG=0 is silent and always returns 0" {
  CC_FIRE_REFUSAL_LOG=0 emit_fire_refusal capacity "x"
  [ ! -s "$LOG" ]
  # POSITIVE CONTROL: with logging ON the same call DOES write.
  emit_fire_refusal capacity "x"
  [ -s "$LOG" ]
}

@test "F13: telemetry can never change a refusal's exit code (an unwritable log is survivable)" {
  # The gates call this on their way out; if it could fail it would corrupt the refusal's own status.
  rm -rf "$HOME/.claude/logs"
  printf 'not-a-dir\n' > "$HOME/.claude/logs"
  run emit_fire_refusal capacity "x"
  [ "$status" -eq 0 ]
}
