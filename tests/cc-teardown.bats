#!/usr/bin/env bats
# cc-teardown — the actuator. Its --selftest RED-proves the full flow (mock panes/pids + temp git,
# no real session); these bats add CLI-level regression that needs no mock rig.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  T="$REPO/bin/cc-teardown"
  export CC_TEARDOWN_RECORDS_DIR="$BATS_TEST_TMPDIR/rec"
  export CC_TEARDOWN_SELF_UUID="none"   # deterministic self-guard in a headless test
}

@test "selftest passes and runs all 17 checks (a zero-check suite must not 'pass')" {
  run "$T" --selftest
  [ "$status" -eq 0 ]
  n_ok="$(printf '%s' "$output" | grep -c '^  ok ')"
  [ "$n_ok" -eq 17 ]
}

@test "identity-pin: --expect-pid mismatch (pane recycled) → REFUSE (exit 2), records identity-pin (a17 S-4)" {
  # a live registry row whose pid differs from cc-reaper's classify-time pin → recycle → REFUSE, never kill.
  printf '#!/bin/bash\necho "[{\\"paneUUID\\":\\"U9\\",\\"name\\":\\"t\\",\\"pid\\":'"$$"',\\"cwd\\":\\"/tmp\\",\\"session_id\\":\\"s\\"}]"\n' > "$BATS_TEST_TMPDIR/cc-sessions"
  printf '#!/bin/bash\n[ "$1" = session ] && [ "$2" = list ] && { echo "[{\\"id\\":\\"U9\\"},{\\"id\\":\\"DESK\\"}]"; exit 0; }\nexit 0\n' > "$BATS_TEST_TMPDIR/it2"
  printf '#!/bin/bash\necho "{\\"decision\\":\\"OK\\",\\"git_state\\":\\"clean\\"}"; exit 0\n' > "$BATS_TEST_TMPDIR/gate"
  chmod +x "$BATS_TEST_TMPDIR/cc-sessions" "$BATS_TEST_TMPDIR/it2" "$BATS_TEST_TMPDIR/gate"
  CC_TEARDOWN_SESSIONS_BIN="$BATS_TEST_TMPDIR/cc-sessions" IT2_BIN="$BATS_TEST_TMPDIR/it2" \
  CC_TEARDOWN_GATE_BIN="$BATS_TEST_TMPDIR/gate" CC_TEARDOWN_SELF_UUID="none" \
  run "$T" U9 --done-evidence "x" --expect-pid 4000000
  [ "$status" -eq 2 ]
  rec="$(find "$CC_TEARDOWN_RECORDS_DIR" -name '*.json' 2>/dev/null | head -1)"
  [ -n "$rec" ]
  [ "$(jq -r '.decision' "$rec")" = "REFUSE" ]
  [ "$(jq -r '.reason_kind' "$rec")" = "identity-pin" ]
}

@test "no target → usage (exit 0), no teardown attempted" {
  run "$T"
  [ "$status" -eq 0 ]
}

@test "--self literal → REFUSE (exit 2) and writes a record (no silent refuse)" {
  run "$T" --self --done-evidence "x"
  [ "$status" -eq 2 ]
  rec="$(find "$CC_TEARDOWN_RECORDS_DIR" -name '*.json' 2>/dev/null | head -1)"
  [ -n "$rec" ]
  [ "$(jq -r '.decision' "$rec")" = "REFUSE" ]
}

@test "unknown target (empty registry) → REFUSE (exit 2)" {
  printf '#!/bin/bash\necho "[]"\n' > "$BATS_TEST_TMPDIR/cc-sessions"; chmod +x "$BATS_TEST_TMPDIR/cc-sessions"
  CC_TEARDOWN_SESSIONS_BIN="$BATS_TEST_TMPDIR/cc-sessions" run "$T" NOPE-0000 --done-evidence "x"
  [ "$status" -eq 2 ]
}

# ── operator-adoption belt (2026-07-24) — never auto-close a pane a human is conversing with ─────────
# The WHO-primitive is hooks/lib/cc-interactive.sh. Until 2026-07-29 this wrote a hand-rolled COPY of
# the predicate ("the lib lands separately"), which is fixture drift by construction: the lib grew the
# image-only-paste leg, the whole-file fallback and then the THREE-VALUED unreadable answer, while the
# copy stayed on the original two-valued body — so a test asserting the belt's fail-closed branch would
# have been green against a predicate that no longer exists. The lib is in-tree now, so the shim SOURCES
# THE REAL THING and the drift is unconstructible (memory: fixture-vs-real needs a producer).
write_interactive_stub() { # <path> — a shim onto the REAL lib, never a re-implementation
  printf '#!/usr/bin/env bash\n. "%s"\n' "$REPO/hooks/lib/cc-interactive.sh" > "$1"
}

# ADOPTED target U-AD: a REAL operator prompt 60s ago, spawn 1h ago. Dead pid (4000000, > kern.maxproc)
# so NO real process is ever killed on the --force-adopted teardown path; it2 lists U-AD present and
# removes it on close so the effect-verify can pass. Exports the full teardown env.
adopted_fixture() {
  local D="$BATS_TEST_TMPDIR" now=1000000000 ts
  mkdir -p "$D/proj/slug" "$D/bin" "$D/rec"
  ts="$(TZ=UTC date -j -f %s "$((now-60))" +%Y-%m-%dT%H:%M:%S 2>/dev/null)"
  printf '{"type":"user","timestamp":"%s.000Z","message":{"role":"user","content":"hey do X"}}\n' "$ts" > "$D/proj/slug/sidAD.jsonl"
  printf '[{"paneUUID":"U-AD","name":"t","pid":4000000,"cwd":"/tmp","session_id":"sidAD","startedAt":%s}]\n' "$(( (now-3600)*1000 ))" > "$D/sessions.json"
  printf '#!/bin/bash\ncat "%s"\n' "$D/sessions.json" > "$D/bin/cc-sessions"
  printf '%s' '["U-AD"]' > "$D/panes.json"
  cat > "$D/bin/it2" <<'IT2'
#!/bin/bash
PF="${IT2_PANES_FILE:?}"
if [ "$1" = session ] && [ "$2" = list ]; then jq -n --slurpfile a "$PF" '($a[0] + ["DESK-0000"]) | unique | map({id: .})'; exit 0; fi
if [ "$1" = session ] && [ "$2" = close ]; then shift 2; s=""; while [ $# -gt 0 ]; do case "$1" in -s|--session) s="$2"; shift 2;; *) shift;; esac; done; [ -n "$s" ] && { jq --arg u "$s" 'map(select(. != $u))' "$PF" > "$PF.t" && mv "$PF.t" "$PF"; }; exit 0; fi
exit 0
IT2
  printf '#!/bin/bash\necho "{\\"decision\\":\\"OK\\",\\"git_state\\":\\"clean\\"}"; exit 0\n' > "$D/bin/gate"
  write_interactive_stub "$D/cc-interactive-stub.sh"
  chmod +x "$D/bin/cc-sessions" "$D/bin/it2" "$D/bin/gate"
  export CC_TEARDOWN_SESSIONS_BIN="$D/bin/cc-sessions" IT2_BIN="$D/bin/it2" CC_TEARDOWN_GATE_BIN="$D/bin/gate"
  export CC_TEARDOWN_SELF_UUID="none" CC_TEARDOWN_RECORDS_DIR="$D/rec" IT2_PANES_FILE="$D/panes.json"
  export CC_INTERACTIVE_LIB="$D/cc-interactive-stub.sh" CC_CLASSIFY_PROJECT_ROOTS="$D/proj" CC_CLASSIFY_NOW="$now"
  export CC_TEARDOWN_DIR="$D/tdmark"          # crash-watchdog marker sink (the READER's env var)
}

@test "operator-adoption belt: adopted target (real operator prompt 60s ago) → REFUSE operator-adopted (exit 2)" {
  adopted_fixture
  run "$T" U-AD --done-evidence "looks done"
  [ "$status" -eq 2 ]
  rec="$(find "$CC_TEARDOWN_RECORDS_DIR" -name '*.json' | head -1)"
  [ -n "$rec" ]
  [ "$(jq -r '.decision' "$rec")" = "REFUSE" ]
  [ "$(jq -r '.reason_kind' "$rec")" = "operator-adopted" ]
  jq -e 'index("U-AD") != null' "$IT2_PANES_FILE" >/dev/null   # the pane was NOT closed
}

@test "operator-adoption belt: --force-adopted skips ONLY the belt → teardown proceeds (exit 0)" {
  adopted_fixture
  run "$T" U-AD --done-evidence "looks done" --force-adopted
  [ "$status" -eq 0 ]
  rec="$(find "$CC_TEARDOWN_RECORDS_DIR" -name '*.json' | head -1)"
  [ "$(jq -r '.decision' "$rec")" = "TEARDOWN" ]
  jq -e 'index("U-AD") == null' "$IT2_PANES_FILE" >/dev/null   # pane actually closed (removed)
}

# ── INVERTED 2026-07-29 (SESSION_REGISTRY_V2 §4.3.5 / R3) ────────────────────────────────────────
# This test previously asserted: lib ABSENT → belt skipped → teardown PROCEEDS (exit 0), against a
# fixture carrying a REAL operator prompt. That pinned the fail-open as correct — "cannot prove the
# operator is present" treated as "proven absent" — which is the mechanism by which live operator
# conversations were closed (2026-07-24). The behavior is deliberately inverted: with no presence
# oracle available the close is REFUSED. The three arms are pinned separately so the refusal cannot
# silently become unconditional inertness.
@test "belt degradation: lib ABSENT and NO beat system → REFUSE (exit 2), never a close" {
  adopted_fixture
  export CC_INTERACTIVE_LIB="$BATS_TEST_TMPDIR/no-such-lib.sh"   # absent
  export CC_BEAT_DIR="$BATS_TEST_TMPDIR/no-such-beats"           # no beat world either
  # NOTE: the fixture pins CC_CLASSIFY_NOW=1000000000, so --decided-at must use the SAME pinned
  # clock — a real-clock timestamp reads as ~25 years in the FUTURE and trips the lease's skew arm
  # instead of the branch under test.
  run "$T" U-AD --done-evidence "looks done" --decided-at 1000000000
  [ "$status" -eq 2 ]
  rec="$(find "$CC_TEARDOWN_RECORDS_DIR" -name '*.json' | head -1)"
  [ "$(jq -r '.decision' "$rec")" = "REFUSE" ]
  [ "$(jq -r '.reason_kind' "$rec")" = "presence-unprovable" ]
  jq -e 'index("U-AD") != null' "$IT2_PANES_FILE" >/dev/null      # pane still OPEN — nothing was closed
}

@test "belt degradation: lib ABSENT but the BEAT shows a recent operator prompt → REFUSE (independent oracle)" {
  adopted_fixture
  export CC_INTERACTIVE_LIB="$BATS_TEST_TMPDIR/no-such-lib.sh"
  export CC_BEAT_DIR="$BATS_TEST_TMPDIR/beats"; mkdir -p "$CC_BEAT_DIR"
  now=1000000000   # the fixture's pinned clock (CC_CLASSIFY_NOW)
  export CC_BEAT_NOW="$now"
  printf '{"sid":"sidAD","t":%s,"who":"operator","operatorT":%s,"seq":1}\n' "$now" "$now" > "$CC_BEAT_DIR/sidAD.json"
  run "$T" U-AD --done-evidence "looks done" --decided-at "$now"
  [ "$status" -eq 2 ]
  rec="$(find "$CC_TEARDOWN_RECORDS_DIR" -name '*.json' | head -1)"
  [ "$(jq -r '.reason_kind' "$rec")" = "operator-adopted" ]
}

@test "POSITIVE CONTROL: lib ABSENT but the BEAT proves presence is OLD → proceeds (fail-closed is not inert)" {
  # Beside the two refusals above: proves the refusal is attributable to unprovable presence, not to
  # a belt that refuses everything once the lib goes missing. Without this, §4.3.5 could ship as a
  # permanent teardown outage and every test above would still be green.
  adopted_fixture
  export CC_INTERACTIVE_LIB="$BATS_TEST_TMPDIR/no-such-lib.sh"
  export CC_BEAT_DIR="$BATS_TEST_TMPDIR/beats"; mkdir -p "$CC_BEAT_DIR"
  now=1000000000   # the fixture's pinned clock (CC_CLASSIFY_NOW)
  export CC_BEAT_NOW="$now"
  # fresh beat (system IS live) but the operator high-water mark is far older than the hold
  printf '{"sid":"sidAD","t":%s,"who":"auto","operatorT":%s,"seq":9}\n' "$now" "$(( now - 99999 ))" > "$CC_BEAT_DIR/sidAD.json"
  CC_CLASSIFY_INTERACTIVE_HOLD_S=600 run "$T" U-AD --done-evidence "looks done" --decided-at "$now"
  [ "$status" -eq 0 ]
  rec="$(find "$CC_TEARDOWN_RECORDS_DIR" -name '*.json' | head -1)"
  [ "$(jq -r '.decision' "$rec")" = "TEARDOWN" ]
}

# ── THIRD STATE (2026-07-29, C-SC-1) — the lib is PRESENT but has no answer to give ───────────────
# The three arms above all concern an ABSENT lib. A distinct and much more common gap went straight
# through the belt to the close: the lib is present and working, but the target's transcript cannot be
# READ (corrupt / truncated / empty) or cannot be RESOLVED at all. ci_last_interactive_epoch answered
# those with the same empty string it used for "parsed, nobody typed", so the belt's `[ -n "$iep" ]`
# test fell through and the pane was closed — the identical absence-of-evidence-as-evidence-of-absence
# defect §4.3.5 inverted for the lib-absent arm, still live on the arm that fires far more often.
# Both now route through beat_or_refuse, the same second-oracle path, and record presence-unprovable.
set_transcript() { # <corrupt|missing|quiet> — rewrite the adopted fixture's transcript in place
  local mode="$1" f="$BATS_TEST_TMPDIR/proj/slug/sidAD.jsonl"
  case "$mode" in
    corrupt) printf 'not json at all\n\x00\x01binary garbage\n{"half":\n' > "$f" ;;
    missing) rm -f "$f" ;;
    # PARSES cleanly, holds only assistant/tool traffic — the "nobody typed" FACT, the one world that
    # is still allowed to license a close.
    quiet)   printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"done"}]},"timestamp":"2001-09-09T01:46:40.000Z"}\n' > "$f" ;;
  esac
}

@test "third state: transcript CORRUPT (lib present, no answer) and no beat → REFUSE, pane stays open" {
  adopted_fixture
  set_transcript corrupt
  export CC_BEAT_DIR="$BATS_TEST_TMPDIR/no-such-beats"
  run "$T" U-AD --done-evidence "looks done" --decided-at 1000000000
  [ "$status" -eq 2 ]
  rec="$(find "$CC_TEARDOWN_RECORDS_DIR" -name '*.json' | head -1)"
  [ "$(jq -r '.decision' "$rec")" = "REFUSE" ]
  [ "$(jq -r '.reason_kind' "$rec")" = "presence-unprovable" ]
  jq -e 'index("U-AD") != null' "$IT2_PANES_FILE" >/dev/null
}

# The BOUNDARY of the fix, pinned so it cannot drift in either direction. An UNRESOLVABLE transcript
# is NOT treated as unreadable: no <sid>.jsonl is the ordinary state of a synthetic sid and of any
# session whose transcript a handoff renamed to <sid>.jsonl.handed-off, so refusing on it would refuse
# a large legitimate population whenever the beat world is also down. Routing it through
# beat_or_refuse was tried and RED-proved wrong — it turned 7 of the 17 --selftest checks into REFUSE
# (a fleet-wide teardown outage). Only a transcript that EXISTS and cannot be READ is unprovable.
@test "boundary: transcript UNRESOLVABLE is NOT unreadable → belt skipped, teardown proceeds" {
  adopted_fixture
  set_transcript missing
  export CC_BEAT_DIR="$BATS_TEST_TMPDIR/no-such-beats"
  run "$T" U-AD --done-evidence "looks done" --decided-at 1000000000
  [ "$status" -eq 0 ]
  rec="$(find "$CC_TEARDOWN_RECORDS_DIR" -name '*.json' | head -1)"
  [ "$(jq -r '.decision' "$rec")" = "TEARDOWN" ]
}

@test "POSITIVE CONTROL: transcript PARSES with no operator turn → proceeds (the FACT still licenses a close)" {
  # The counterpart to the two refusals above, and the reason the three-valued split exists at all. If
  # "no operator turn" were folded into "unreadable", this teardown would refuse too and cc-teardown
  # would be a permanent outage for every ordinary finished worker — with both tests above still green.
  adopted_fixture
  set_transcript quiet
  export CC_BEAT_DIR="$BATS_TEST_TMPDIR/no-such-beats"
  run "$T" U-AD --done-evidence "looks done" --decided-at 1000000000
  [ "$status" -eq 0 ]
  rec="$(find "$CC_TEARDOWN_RECORDS_DIR" -name '*.json' | head -1)"
  [ "$(jq -r '.decision' "$rec")" = "TEARDOWN" ]
  jq -e 'index("U-AD") == null' "$IT2_PANES_FILE" >/dev/null
}

@test "third state: transcript CORRUPT but the BEAT proves presence is OLD → proceeds (second oracle not inert)" {
  adopted_fixture
  set_transcript corrupt
  export CC_BEAT_DIR="$BATS_TEST_TMPDIR/beats"; mkdir -p "$CC_BEAT_DIR"
  now=1000000000
  export CC_BEAT_NOW="$now"
  printf '{"sid":"sidAD","t":%s,"who":"auto","operatorT":%s,"seq":9}\n' "$now" "$(( now - 99999 ))" > "$CC_BEAT_DIR/sidAD.json"
  CC_CLASSIFY_INTERACTIVE_HOLD_S=600 run "$T" U-AD --done-evidence "looks done" --decided-at "$now"
  [ "$status" -eq 0 ]
  rec="$(find "$CC_TEARDOWN_RECORDS_DIR" -name '*.json' | head -1)"
  [ "$(jq -r '.decision' "$rec")" = "TEARDOWN" ]
}

# ── teardown markers (2026-07-25) — a DELEGATED close must not read as a CRASH ────────────────────
# cc-teardown kills the target and closes its pane; to the target's OWN lead-crash-watchdog that death
# looked exactly like a real CC crash (handoff-fire got its marker on 2026-07-23, the delegated close
# never did). These drive the REAL binary end-to-end and then the REAL reader, so the assertion is the
# live cross-file contract — not a hand-written fixture that could pass while either side drifts.

@test "marker: TEARDOWN writes the dual-keyed contract-v1 marker for the TARGET (sid + pane)" {
  adopted_fixture
  run "$T" U-AD --done-evidence "looks done" --force-adopted
  [ "$status" -eq 0 ]
  [ -f "$CC_TEARDOWN_DIR/sidAD.json" ]                       # keyed by the TARGET's session id
  [ -f "$CC_TEARDOWN_DIR/U-AD.json" ]                        # …and by its pane uuid
  run cat "$CC_TEARDOWN_DIR/sidAD.json"
  [[ "$output" == *'"key_kind":"sid"'* ]] || false
  [[ "$output" == *'"sid":"sidAD"'* ]] || false
  [[ "$output" == *'"pane":"U-AD"'* ]] || false
  [[ "$output" == *'"mode":"teardown"'* ]] || false          # the discriminator vs handoff-fire's modes
  run cat "$CC_TEARDOWN_DIR/U-AD.json"
  [[ "$output" == *'"key_kind":"pane"'* ]] || false
  run python3 -c "import json,sys; json.loads(open(sys.argv[1]).read().strip())" "$CC_TEARDOWN_DIR/sidAD.json"
  [ "$status" -eq 0 ]
}

@test "marker: REFUSE (operator-adopted) writes NO marker — a LIVE pane is never masked" {
  # The placement invariant: markers go in only once a close is inevitable. A pre-gate write would
  # mask a genuine crash of the still-live target for the reader's whole 30-min freshness window.
  adopted_fixture
  run "$T" U-AD --done-evidence "looks done"
  [ "$status" -eq 2 ]
  [ ! -e "$CC_TEARDOWN_DIR" ] || [ -z "$(ls -A "$CC_TEARDOWN_DIR" 2>/dev/null)" ]
}

@test "marker contract: the REAL watchdog classifies a cc-teardown close as RECYCLE/deliberate-teardown" {
  adopted_fixture
  W="$REPO/hooks/lead-crash-watchdog.sh"
  D="$BATS_TEST_TMPDIR"
  mkdir -p "$D/wdbase/projects/slug" "$D/reg" "$D/nojetsam"
  cp "$D/proj/slug/sidAD.jsonl" "$D/wdbase/projects/slug/sidAD.jsonl"   # the reader needs a transcript
  run "$T" U-AD --done-evidence "looks done" --force-adopted
  [ "$status" -eq 0 ]
  # sid-keyed hit (the direct path)
  CC_ACCOUNT_BASES="$D/wdbase" CC_REGISTRY_DIR="$D/reg" CC_JETSAM_DIRS="$D/nojetsam" \
    run "$W" --classify sidAD
  [ "$status" -eq 0 ]
  [[ "$output" == RECYCLE* ]] || false
  [[ "$output" == *deliberate-teardown* ]] || false
  # pane-keyed alias (what remains when cc-sessions carried no session_id): drop the sid marker and
  # give the registry the pane→sid row the reader reverse-looks-up.
  rm -f "$CC_TEARDOWN_DIR/sidAD.json"
  printf '{\n  "session_id": "sidAD"\n}\n' > "$D/reg/U-AD.json"
  CC_ACCOUNT_BASES="$D/wdbase" CC_REGISTRY_DIR="$D/reg" CC_JETSAM_DIRS="$D/nojetsam" \
    run "$W" --classify sidAD
  [[ "$output" == RECYCLE* ]] || false
  [[ "$output" == *deliberate-teardown* ]]
}
