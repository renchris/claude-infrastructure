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
# The WHO-primitive ci_last_interactive_epoch lands separately in hooks/lib/cc-interactive.sh; a STUB
# is written here so these tests are landing-order-independent.
write_interactive_stub() { # <path>
  cat > "$1" <<'STUB'
#!/usr/bin/env bash
ci_last_interactive_epoch() {
  local f="${1:-}" rx ep
  [ -n "$f" ] && [ -f "$f" ] || return 1
  rx="${CC_CLASSIFY_AUTO_RX:-^<task-notification>|^<local-command-stdout>|^Stop hook feedback:|^\\[Request interrupted|^⟳|^⚑|^⚠}"
  ep="$(tail -c "${CC_CLASSIFY_INTERACTIVE_TAIL_BYTES:-2000000}" "$f" 2>/dev/null | jq -Rr --arg rx "$rx" '
      fromjson? | objects
      | select(.type=="user") | select(.isMeta != true)
      | (.message.content) as $c
      | ( if ($c|type)=="string" then $c
          elif ($c|type)=="array" and ([$c[]? | select(.type?=="tool_result")] | length)==0
          then ([$c[]? | select(.type?=="text") | .text] | join("\n"))
          else empty end ) as $t
      | select(($t|length) > 0)
      | select($t | test($rx) | not)
      | (.timestamp | strings | sub("\\.[0-9]+Z$"; "Z") | try fromdateiso8601 catch empty)
    ' 2>/dev/null | tail -1)"
  case "$ep" in ''|*[!0-9]*) return 1 ;; esac
  printf '%s' "$ep"
}
STUB
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

@test "operator-adoption belt degradation: lib ABSENT → WARN + belt skipped → teardown proceeds (exit 0)" {
  adopted_fixture
  export CC_INTERACTIVE_LIB="$BATS_TEST_TMPDIR/no-such-lib.sh"   # absent
  run "$T" U-AD --done-evidence "looks done"
  [ "$status" -eq 0 ]
  rec="$(find "$CC_TEARDOWN_RECORDS_DIR" -name '*.json' | head -1)"
  [ "$(jq -r '.decision' "$rec")" = "TEARDOWN" ]
  [[ "$output" == *"cc-interactive.sh absent"* ]]               # the degradation WARN (stderr, merged by run)
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
