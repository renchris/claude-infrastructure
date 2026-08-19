#!/usr/bin/env bats
# handoff-fire.sh — the V2 LIFECYCLE RECORD (docs/plans/SESSION_LIFECYCLE_V2.md §5).
#
# WHAT THIS PINS, and why each pin exists rather than being obvious:
#
#   1. THE METRIC HAD NO PRODUCER (V2 §2 M-2). Both timestamps the script wrote before v2
#      (handoffs.jsonl `ts`, cc-fired `firedAt`) are emitted AFTER verify_engagement returns and are
#      byte-identical for a single fire — measured on a real fire, both `2026-07-29T23:07:23Z`. So a
#      10-second fire and a 10-minute fire recorded the same instant and "fire→engaged ≤60s p95" was
#      unfalsifiable. LR_STARTED_AT is captured BEFORE spawn; _iso_delta_s turns the pair into a
#      duration.
#
#   2. NEVER FABRICATE A ZERO (R9). `firing_rss_kb` read 0 in 141 of 141 fires: an absent pidfile
#      made it `ps -p 0` ⇒ empty ⇒ `0`, so "not measured" was indistinguishable from a real 0 KB.
#      _iso_delta_s must therefore return EMPTY on unparseable input — and the POSITIVE CONTROL
#      beside that assertion is a genuine zero-second delta, which must return the string "0". A
#      test that only asserted "empty on garbage" would pass on a function that always returns empty.
#
#   3. THE RESUME FALSE-NEGATIVE IS STRUCTURAL, NOT RESUME-SPECIFIC (V2 §5.2, cc-backlog
#      93a9f880b6fe). successor_engaged passed an EMPTY marker, disabling the content path, so it
#      depended wholly on row 4's registry row carrying `.session_id` — a field the PROVISIONAL row
#      handoff-fire itself writes does not have (M-9). Any pane with a provisional row could never be
#      proven engaged. The marker path fixes both at once.
#
#   4. ADDITIVE-ONLY IS A CONTRACT, NOT A STYLE (V2 §7 A9). bin/cc-reaper keys auto-reap on this
#      file's presence + `selfRetire`. Every pre-v2 field keeps its name, type and meaning.
#
# HERMETIC: helper units are sed-extracted and sourced, the idiom of tests/handoff-selfclose.bats
# and tests/handoff-selfclose-teammate-gate.bats. No pane, no iTerm2, no network.

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
  HELPERS="$BATS_TEST_TMPDIR/helpers.sh"

  # HERMETICITY (the land gate's ratchet blocks on this, and rightly): the units under test resolve
  # default paths under $HOME — ~/.claude/cc-fired, ~/.claude/logs — so an unfixtured $HOME would
  # have this suite reading and writing the operator's LIVE state, making every result here
  # untrustworthy and every run a mutation. Fixture it before anything is sourced. Never the
  # allowlist: an allowlisted leak is a leak with paperwork.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude"

  # _iso_now is a ONE-LINE function, so the /^f() {/,/^}/ range idiom cannot match its close —
  # grep it whole. The multi-line units use the range form.
  {
    grep '^_iso_now() {' "$HF" || true
    sed -n '/^_iso_delta_s() {/,/^}/p'      "$HF"
    sed -n '/^assistant_turn_in() {/,/^}/p' "$HF"
    sed -n '/^engagement_seen() {/,/^}/p'   "$HF"
    sed -n '/^successor_engaged() {/,/^}/p' "$HF"
    sed -n '/^mark_fired_peer() {/,/^}/p'   "$HF"
  } > "$HELPERS"

  # set -u safety: the extracted units read these globals, which the real script declares at :221.
  LR_STARTED_AT="" LR_ENGAGED_AT="" LR_PROOF="" LR_TRANSCRIPT="" LR_LATENCY_S=""
  ENGAGE_PROOF="" ENGAGE_TRANSCRIPT="" FIRE_MARKER=""
  # successor_engaged reads these two: the projects-dir list it scans, and the fired-record dir it
  # takes the marker from. Both are pinned per-test below; FIRED_DIR is declared here only so the
  # extracted unit is set -u safe when a case exercises the no-record path.
  # EXPORTED, not merely assigned: both are consumed by the sed-extracted unit rather than by any
  # test body, so shellcheck reads every assignment below as dead (SC2034). FIRED_DIR is the sharper
  # case — the ${3-} case deliberately sets it and then proves it is NOT read, which is precisely
  # what makes that mutant red. Exporting states the truth (the value escapes this scope) instead of
  # silencing the check per site.
  export CC_PROJECTS_DIRS="" FIRED_DIR=""
  # shellcheck disable=SC1090
  . "$HELPERS"

  PDIR="$BATS_TEST_TMPDIR/projects/slug"; mkdir -p "$PDIR"
  REGDIR="$BATS_TEST_TMPDIR/cc-registry";  mkdir -p "$REGDIR"
  FIREDIR="$BATS_TEST_TMPDIR/cc-fired";    mkdir -p "$FIREDIR"
  PANE="7D90C1DF-7D5B-4BAD-9C3A-4370AEE64AD1"
}

# A transcript with a content-bearing assistant turn — what assistant_turn_in requires. Attachment
# and system rows are deliberately included: they are what BIRTH looks like, and birth is not
# engagement (item ff2d6609a33e).
engaged_transcript() { # $1=path [$2=extra line]
  {
    printf '%s\n' '{"type":"system","subtype":"init"}'
    printf '%s\n' '{"type":"attachment","content":"x"}'
    printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"text","text":"working"}]}}'
    [ -n "${2:-}" ] && printf '%s\n' "$2"
  } > "$1"
  return 0
}

# BIRTH-ONLY: rows exist, no assistant turn. A fire whose prompt was rejected (the /goal >4000-char
# cap) or never submitted looks exactly like this.
birth_only_transcript() { # $1=path
  {
    printf '%s\n' '{"type":"system","subtype":"init"}'
    printf '%s\n' '{"type":"attachment","content":"x"}'
  } > "$1"
  return 0
}

# ── 1. the metric's producer ───────────────────────────────────────────────────────────────────

@test "_iso_delta_s computes the fire→engaged duration the pre-v2 script could not express" {
  run _iso_delta_s '2026-07-29T23:07:23Z' '2026-07-29T23:08:05Z'
  [ "$status" -eq 0 ]
  [ "$output" = "42" ]
}

@test "R9 POSITIVE CONTROL: a genuine zero-second delta returns \"0\", so empty can only mean UNMEASURED" {
  # Without this control, "returns empty on garbage" would also pass for a function that returns
  # empty ALWAYS — which is exactly the firing_rss_kb defect wearing the opposite mask.
  run _iso_delta_s '2026-07-29T23:07:23Z' '2026-07-29T23:07:23Z'
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]
}

@test "R9: unparseable or absent timestamps yield EMPTY, never a fabricated 0" {
  run _iso_delta_s 'not-a-date' '2026-07-29T23:08:05Z'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  run _iso_delta_s '' ''
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ── 2. the engagement oracle names itself (R12) ────────────────────────────────────────────────

@test "engagement_seen sets ENGAGE_PROOF=marker on the content path" {
  engaged_transcript "$PDIR/abc.jsonl" '{"type":"user","message":{"content":"HANDOFF-ENGAGE-1-2-3"}}'
  ENGAGE_PROOF="" ENGAGE_TRANSCRIPT=""
  engagement_seen "$PDIR" 'HANDOFF-ENGAGE-1-2-3' "$REGDIR" "$PANE"
  [ "$ENGAGE_PROOF" = "marker" ]
  [ "$ENGAGE_TRANSCRIPT" = "$PDIR/abc.jsonl" ]
}

@test "engagement_seen sets ENGAGE_PROOF=registry:<sid> on the registry path" {
  engaged_transcript "$PDIR/sid-9999.jsonl"
  printf '{"paneUUID":"%s","session_id":"sid-9999"}\n' "$PANE" > "$REGDIR/$PANE.json"
  ENGAGE_PROOF="" ENGAGE_TRANSCRIPT=""
  engagement_seen "$PDIR" '' "$REGDIR" "$PANE"
  [ "$ENGAGE_PROOF" = "registry:sid-9999" ]
}

@test "BIRTH IS NOT ENGAGEMENT: a born-but-never-run transcript proves nothing, and the PROOF stays empty" {
  birth_only_transcript "$PDIR/born.jsonl"
  printf '%s\n' '{"type":"user","message":{"content":"HANDOFF-ENGAGE-9-9-9"}}' >> "$PDIR/born.jsonl"
  ENGAGE_PROOF="set-before-call"
  run engagement_seen "$PDIR" 'HANDOFF-ENGAGE-9-9-9' "$REGDIR" "$PANE"
  [ "$status" -eq 1 ]
  # POSITIVE CONTROL for this absence: the SAME marker in a transcript that DOES have an assistant
  # turn must succeed — otherwise the failure above could be a broken fixture, not a real refusal.
  engaged_transcript "$PDIR/ran.jsonl" '{"type":"user","message":{"content":"HANDOFF-ENGAGE-9-9-9"}}'
  ENGAGE_PROOF=""
  engagement_seen "$PDIR" 'HANDOFF-ENGAGE-9-9-9' "$REGDIR" "$PANE"
  [ "$ENGAGE_PROOF" = "marker" ]
}

@test "F2 ROOT CAUSE: the marker proves engagement when the registry row carries NO session_id" {
  # This is the resume false-negative (cc-backlog 93a9f880b6fe) reduced to its structural core, and
  # it is NOT resume-specific: ensure_registration's own PROVISIONAL row has no session_id field at
  # all (M-9), so before v2 ANY pane with a provisional row was unprovable and self-close aborted on
  # a successor that was in fact working.
  printf '{"paneUUID":"%s","name":"n","cwd":"/tmp","cmd":"c","provisional":true}\n' "$PANE" \
    > "$REGDIR/$PANE.json"
  # A resume writes into the ORIGINAL sid's transcript — no new file is ever created — but that
  # transcript now CONTAINS the marker, because the resumed session ingested the marked prompt.
  engaged_transcript "$PDIR/original-sid.jsonl" '{"type":"user","message":{"content":"MARK-RESUMED"}}'

  # registry path alone (what pre-v2 successor_engaged had): must FAIL on a sid-less row.
  run engagement_seen "$PDIR" '' "$REGDIR" "$PANE"
  [ "$status" -eq 1 ]
  # marker path: must SUCCEED on the very same fixture. The fix is a better oracle row 2 OWNS,
  # never a weakened gate (V2 §8 rejects failing open).
  ENGAGE_PROOF=""
  engagement_seen "$PDIR" 'MARK-RESUMED' "$REGDIR" "$PANE"
  [ "$ENGAGE_PROOF" = "marker" ]
}

# ── 2b. …AND THE GATE ACTUALLY USES IT (cc-backlog 93a9f880b6fe) ───────────────────────────────
# The three cases above prove the ORACLE. They passed for a day while the only consumer that needed
# them, successor_engaged, still handed engagement_seen an empty marker — so the better answer was
# unreachable from the gate, and self-close kept aborting on a working successor. These pin the
# CONSUMER: one case that could not pass before the wiring, and two that keep it from widening.

# The resume fixture, verbatim from the oracle case above: a PROVISIONAL registry row with no
# session_id (so path b cannot answer) and the marker sitting in the transcript the resumed session
# actually grew. Only the marker path can prove this pane engaged.
resumed_successor_fixture() { # $1=marker-in-transcript
  printf '{"paneUUID":"%s","name":"n","cwd":"/tmp","cmd":"c","provisional":true}\n' "$PANE" \
    > "$REGDIR/$PANE.json"
  engaged_transcript "$PDIR/original-sid.jsonl" \
    "$(printf '{"type":"user","message":{"content":"%s"}}' "$1")"
  CC_PROJECTS_DIRS="$PDIR"
}

@test "successor_engaged proves a RESUMED successor via the marker its own fire recorded" {
  resumed_successor_fixture 'MARK-RESUMED'
  FIRE_MARKER='MARK-RESUMED' mark_fired_peer "$FIREDIR" "$PANE" '/tmp/wt' 'FIRING-SID-1'
  [ "$(jq -r '.marker' "$FIREDIR/$PANE.json")" = 'MARK-RESUMED' ]
  # pre-wiring this returned 1 — "process-alive but NEVER ENGAGED" — and self-close aborted (exit 3)
  run successor_engaged "$REGDIR" "$PANE" "$FIREDIR"
  [ "$status" -eq 0 ]
}

@test "successor_engaged: an explicitly EMPTY fired-dir reads no marker, even with a record on disk" {
  # The record EXISTS and would prove engagement — but the caller said "no fired-dir", and the unit
  # must honour that rather than substituting its live default. This is the ${3-} vs ${3:-} choice
  # made falsifiable: a colon-default silently promotes "the caller passed empty" into "the caller
  # said nothing", which is how a harness ends up certifying a path it never exercised.
  resumed_successor_fixture 'MARK-RESUMED'
  FIRE_MARKER='MARK-RESUMED' mark_fired_peer "$FIREDIR" "$PANE" '/tmp/wt' 'FIRING-SID-1'
  FIRED_DIR="$FIREDIR"
  run successor_engaged "$REGDIR" "$PANE" ""
  [ "$status" -eq 1 ]
}

@test "successor_engaged: a recorded marker ABSENT from the transcript never fabricates engagement" {
  # The gate must still fail closed. A record whose marker no transcript carries is the cold-fire
  # case the whole check exists for — the successor booted, and never ingested the brief.
  resumed_successor_fixture 'MARK-SOMETHING-ELSE'
  FIRE_MARKER='MARK-RESUMED' mark_fired_peer "$FIREDIR" "$PANE" '/tmp/wt' 'FIRING-SID-1'
  run successor_engaged "$REGDIR" "$PANE" "$FIREDIR"
  [ "$status" -eq 1 ]
}

# ── 3. the record ──────────────────────────────────────────────────────────────────────────────

@test "mark_fired_peer writes schema 2 with the lifecycle fields the fire knew and used to discard" {
  LR_STARTED_AT='2026-07-29T23:07:23Z' LR_ENGAGED_AT='2026-07-29T23:08:05Z'
  LR_PROOF='marker' LR_TRANSCRIPT="$PDIR/abc.jsonl" FIRE_MARKER='HANDOFF-ENGAGE-1-2-3'
  mark_fired_peer "$FIREDIR" "$PANE" '/tmp/wt' 'FIRING-SID-1'
  [ -s "$FIREDIR/$PANE.json" ]
  run jq -r '[.schema,.originClass,.originator,.firedStartedAt,.engagedAt,.engageLatencyS,.engageProof,.marker]|@tsv' \
    "$FIREDIR/$PANE.json"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf '2\tfired-peer\tFIRING-SID-1\t2026-07-29T23:07:23Z\t2026-07-29T23:08:05Z\t42\tmarker\tHANDOFF-ENGAGE-1-2-3')" ]
}

@test "A9 cc-reaper contract: EVERY pre-v2 field survives unchanged (additive-only)" {
  LR_STARTED_AT='2026-07-29T23:07:23Z'
  mark_fired_peer "$FIREDIR" "$PANE" '/tmp/wt' 'FIRING-SID-1'
  run jq -r '[.paneUUID,.cwd,.firedBy,.selfRetire,(.firedAt|type)]|@tsv' "$FIREDIR/$PANE.json"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf '%s\t/tmp/wt\tFIRING-SID-1\ttrue\tstring' "$PANE")" ]
}

@test "R9 in the record: unmeasured lifecycle fields are PRESENT and null, never absent and never fabricated" {
  # No LR_* set at all — the pre-engagement / kill-switched-collaborator case.
  mark_fired_peer "$FIREDIR" "$PANE" '/tmp/wt' 'FIRING-SID-1'
  # `has()` is load-bearing, not belt-and-braces: `jq '.missing|type'` ALSO returns "null", so a
  # type-only assertion passes vacuously against a tree where the field does not exist at all. The
  # RED-proof against the pristine tree caught exactly that — this test passed on pre-v2 code. An
  # ABSENT field and a null one are different claims: absent means "this writer knows nothing about
  # the concept", null means "measured, and there was nothing to measure" (R9).
  run jq -r '[(has("firedStartedAt")),(has("engagedAt")),(has("engageLatencyS")),(has("engageProof"))]|@tsv' \
    "$FIREDIR/$PANE.json"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'true\ttrue\ttrue\ttrue')" ]
  run jq -r '[(.firedStartedAt|type),(.engagedAt|type),(.engageLatencyS|type),(.engageProof|type)]|@tsv' \
    "$FIREDIR/$PANE.json"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'null\tnull\tnull\tnull')" ]
}

@test "A11 kill switch: CC_LIFECYCLE_RECORD=0 restores EXACTLY the pre-v2 five-field stamp" {
  LR_STARTED_AT='2026-07-29T23:07:23Z' LR_PROOF='marker'
  CC_LIFECYCLE_RECORD=0 mark_fired_peer "$FIREDIR" "$PANE" '/tmp/wt' 'FIRING-SID-1'
  run jq -r 'keys|join(",")' "$FIREDIR/$PANE.json"
  [ "$status" -eq 0 ]
  [ "$output" = "cwd,firedAt,firedBy,paneUUID,selfRetire" ]
  # POSITIVE CONTROL: the switch is what makes the difference, not a broken writer — the same call
  # with the switch ON must produce the schema-2 record.
  rm -f "$FIREDIR/$PANE.json"
  mark_fired_peer "$FIREDIR" "$PANE" '/tmp/wt' 'FIRING-SID-1'
  run jq -r '.schema' "$FIREDIR/$PANE.json"
  [ "$output" = "2" ]
}

@test "the UUID guard still refuses a path fragment (pre-v2 safety, unchanged)" {
  run mark_fired_peer "$FIREDIR" '../../etc/passwd' '/tmp/wt' 'FIRING-SID-1'
  [ "$status" -eq 0 ]
  [ ! -e "$FIREDIR/../../etc/passwd" ]
  # POSITIVE CONTROL: a well-formed uuid on the same call path DOES write.
  mark_fired_peer "$FIREDIR" "$PANE" '/tmp/wt' 'FIRING-SID-1'
  [ -s "$FIREDIR/$PANE.json" ]
}
