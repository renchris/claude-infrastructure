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
# SCOPE NOTE that is load-bearing: the pane-id gate is PAYLOAD-scoped, never corpus-scoped. A
# corpus-scoped gate would refuse every fire on the box over somebody else's file — a fleet-wide hard
# stop. Re-measured 2026-08-21 (recycle #121): the figure this note used to carry, "28 violations
# across 12+ files", is now 134 flagged lines across 17 directories — the argument is monotone in
# that count, so the rot strengthens the scoping rather than dating it. Payload-scope is also
# non-punitive in fact, not just in principle: all 20 surviving real fire payloads on this box PASS.
#
# M-11 PREVIEW (recycle #121): the gate takes a MODE. `--dry-run` previews it, so a dry run predicts
# the refusal instead of going quiet about it; preview reports on stdout and returns 0.

setup() {
  # M11 (MACHINE_CAPACITY_V2 §11.3) — a test's environment is PINNED, not ambient. handoff-fire.sh's
  # capacity_gate reads the box's live loadavg AND (M10) its memory headroom, exiting 9 when either is
  # past its bar, so an unpinned suite goes RED purely because the box is busy — the corpus deciding a
  # verdict on machine state instead of on the tree. Both terms are pinned off here (they are the two
  # TERMS of one exit 9, handoff-fire.sh:4487); tests/handoff-fire-capacity-gate.bats is the ONE place
  # the gate runs ON, against synthetic inputs.
  export CC_FIRE_CAPACITY_GATE=off
  export CC_FIRE_HEADROOM_GATE=off
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HF="$REPO/scripts/handoff-fire.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude/logs"
  PF="$BATS_TEST_TMPDIR/payload.md"

  {
    grep '^_iso_now() {' "$HF" || true
    sed -n '/^emit_fire_event() {/,/^}/p'       "$HF"
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

@test "F5 (universalized, c89b9c7b1526): a /goal head UNDER the cap is REFUSED too" {
  printf '/goal fire→engaged p95 <=60s\n' > "$PF"
  run check_slash_head "$PF"
  [ "$status" -eq 1 ]
  [[ "$output" == *"STARTS with the slash command"* ]] || false
}

# The asymmetry this item removed: `check_slash_head` refused ONLY an over-cap /goal, and let every
# other slash head warn-and-fire. The harness makes no such distinction — it parses the whole
# submission as whatever command heads it — so a /research- or /ship-headed brief died the same way.
@test "F5 (universalized): a NON-/goal slash head is REFUSED — the audit's [S2] shape" {
  printf '/ship the branch\n\nthen report back\n' > "$PF"
  run check_slash_head "$PF"
  [ "$status" -eq 1 ]
  [[ "$output" == *"STARTS with the slash command '/ship'"* ]] || false
}

# The two refusals must stay TELEMETRICALLY DISTINCT: one is a length problem with a length fix, the
# other a parse problem with a structural fix. A single collapsed token would make handoffs.jsonl
# unable to say which authoring mistake stalled a fire.
@test "F5 + F13: the non-/goal refusal records its OWN reason, not payload-goal-cap" {
  printf '/wrap it up\n' > "$PF"
  run check_slash_head "$PF"
  [ "$status" -eq 1 ]
  [ -s "$LOG" ]
  run jq -r '[.class,.refuse_reason]|@tsv' "$LOG"
  [ "$output" = "$(printf 'refused\tpayload-slash-head')" ]
}

# The escape hatch is the ONLY way past a now-universal rule, so it is a contract, not a convenience.
@test "F5 (universalized): FIRE_ALLOW_SLASH_HEAD=1 admits a non-/goal slash head" {
  printf '/research the design space\n' > "$PF"
  FIRE_ALLOW_SLASH_HEAD=1 run check_slash_head "$PF"
  [ "$status" -eq 0 ]
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

# ── M-11 preview: --dry-run must PREDICT the refusal, not go quiet about it (recycle #121) ──────
#
# The mismatch these pin: handoff-fire has three fire paths and the pane-id gate was on ONE. The
# dry-run branch previewed payload_lint_gate and nothing else, so `--dry-run` printed a clean readout
# for a payload the real fire exits 3 on. A preview whose silence does not mean "would fire" is worse
# than no preview, because it is consulted precisely to avoid the abort.

@test "M-11 preview: a payload that WOULD be refused is reported, and the preview does not abort" {
  printf 'ping the orchestrator pane 99261468 when done\n' > "$PF"
  run payload_pane_id_gate "$PF" preview
  # returns 0 — a preview reports, it never becomes the failure it is previewing
  [ "$status" -eq 0 ]
  [[ "$output" == *"WOULD REFUSE"* ]] || false
  # it must name the OFFENDING TOKEN, not merely that something is wrong: the operator's next action
  # is to edit that token out of the payload, and a verdict with no locus cannot be acted on.
  [[ "$output" == *"99261468"* ]] || false
}

@test "M-11 preview: preview and enforce agree on the SAME payload — the verdicts cannot diverge" {
  # The discriminator this suite exists for: preview is only worth having if it answers the same
  # question the fire asks. Both arms are run over both a REFUSED and an ADMITTED payload, so a
  # preview hard-wired to either verdict fails one of the two pairs.
  printf 'pane 99261468\n' > "$PF"
  run payload_pane_id_gate "$PF"; local enforce_bad="$status"
  run payload_pane_id_gate "$PF" preview; local preview_bad="$output"
  [ "$enforce_bad" -eq 3 ]
  [[ "$preview_bad" == *"WOULD REFUSE"* ]] || false

  printf 'fired by 71B42B48-1331-4F60-8DA3-6849F2682CA2 (historical fact)\n' > "$PF"
  run payload_pane_id_gate "$PF"; local enforce_ok="$status"
  run payload_pane_id_gate "$PF" preview; local preview_ok="$output"
  [ "$enforce_ok" -eq 0 ]
  # the CONTROL that can fail: on an admitted payload the preview must be SILENT about refusing
  [[ "$preview_ok" != *"WOULD REFUSE"* ]] || false
}

@test "M-11 preview: an unrecognised mode is treated as ENFORCE, so a typo fails CLOSED" {
  # mode is a bare string; the default and every non-'preview' value must reach the abort path.
  # A gate that silently downgraded to advisory on a misspelled mode would be the F13 shape again.
  printf 'pane 99261468\n' > "$PF"
  run payload_pane_id_gate "$PF" preveiw
  [ "$status" -eq 3 ]
  run payload_pane_id_gate "$PF" ""
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

@test "F12/F13 VOCABULARY: an unverified RECYCLE is not filed as a refusal" {
  # `class` is what consumers count. A successful-but-unverified recycle logged as "refused" would
  # inflate the refusal metric with non-refusals and make a genuine fire outage unreadable — the
  # campaign's own CUT/HUNG-is-not-RED leak, one layer down.
  emit_fire_event recycle-unverified process-alive "relaunched pane P; engagement NOT verified"
  emit_fire_refusal capacity "load over ceiling"
  run jq -rs 'map(.class)|join(",")' "$LOG"
  [ "$output" = "recycle-unverified,refused" ]
  # a consumer counting refusals must see exactly ONE
  run jq -rs 'map(select(.class=="refused"))|length' "$LOG"
  [ "$output" = "1" ]
}
