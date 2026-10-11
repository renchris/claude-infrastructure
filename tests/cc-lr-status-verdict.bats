#!/usr/bin/env bats
# bin/cc-lr status — the terminal verdict from EVERY store, and one registry walk (lr-reliability
# 2026-10-10 REPORT D5 + D8, wave A items A3 + A5).
#
# D5: lr-handoff never writes its terminal state, so 151 of 224 bundles ended non-terminal and
# 58d3640a read `admitted` for an hour after it FAILED; a sid the rail never ran (a parked or retired
# request, a session the reconciler closed) had no bundle and no status at all. D8: status --all
# walked the registry once per dead sid's bundle — 206 walks, 200 s.
#
# HERMETIC: HOME, LR_STATE_DIR, LR_RECON_ROOT, LR_CONFIG_DIRS and the registry live in
# BATS_TEST_TMPDIR. status reads only; nothing here starts a recovery or types anywhere.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LR="$REPO/bin/cc-lr"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export LR_STATE_DIR="$BATS_TEST_TMPDIR/state"; mkdir -p "$LR_STATE_DIR"
  export LR_RECON_ROOT="$LR_STATE_DIR/recon"; mkdir -p "$LR_RECON_ROOT/sessions"
  export LR_CONFIG_DIRS="$HOME/.claude-next"
  SID="aaaaaaaa-1111-4000-8000-000000000001"
  SID2="bbbbbbbb-2222-4000-8000-000000000002"
  SID3="cccccccc-3333-4000-8000-000000000003"
  STUBBIN="$BATS_TEST_TMPDIR/stubbin"; mkdir -p "$STUBBIN"
  PATH="$STUBBIN:$PATH"; export PATH
  unset CLAUDE_CODE_SESSION_ID CC_PANE_ID ITERM_SESSION_ID KITTY_WINDOW_ID
}

bundle() { # <sid> <stamp> <state>… — one events.jsonl, one line per state given
  local sid="$1" stamp="$2" d s; shift 2
  d="$LR_STATE_DIR/$sid/bundle-$stamp"; mkdir -p "$d"
  : > "$d/events.jsonl"
  for s in "$@"; do
    printf '{"ts":"2026-10-11T03:20:00Z","run":"%s","state":"%s","stage":"st","detail":"detail-of-%s"}\n' \
      "$d" "$s" "$s" >> "$d/events.jsonl"
  done
  printf '%s' "$d"
}
fleet_verdict() { # <sid> <run stamp> <verdict line> [epoch]
  local d="$LR_STATE_DIR/fleet/one-$2-${1:0:8}"
  mkdir -p "$d"; printf '%s\n' "$3" > "$d/verdict.txt"
  [ -z "${4:-}" ] || touch -t "$(date -u -r "$4" +%Y%m%d%H%M.%S)" "$d/verdict.txt"
}
recon_record() { # <sid> <outcome|""> <epoch> [phase/substate when open]
  if [ -n "$2" ]; then
    printf '{"sid":"%s","record_id":"recon:c:%s:1","cohort_id":"next-7d-1","cwd":"%s","terminal":{"outcome":"%s","proof":"proof-of-%s","at":%s},"close":{"via":"IN-PLACE","at":%s}}\n' \
      "$1" "${1:0:8}" "$BATS_TEST_TMPDIR/wt" "$2" "$2" "$3" "$3" > "$LR_RECON_ROOT/sessions/$1.json"
  else
    printf '{"sid":"%s","record_id":"recon:c:%s:1","cohort_id":"next-7d-1","cwd":"%s","phase":"PRE-MOVE","substate":"WAIT_RESET","terminal":null}\n' \
      "$1" "${1:0:8}" "$BATS_TEST_TMPDIR/wt" > "$LR_RECON_ROOT/sessions/$1.json"
  fi
}
reg_live() { # a live registry row for $1, owned by this test's own shell
  mkdir -p "$HOME/.claude/cc-registry"
  printf '{"session_id":"%s","pid":%s,"paneUUID":"pane-%s","account":"next","cwd":"%s"}\n' \
    "$1" "$$" "${1:0:8}" "$BATS_TEST_TMPDIR/wt" > "$HOME/.claude/cc-registry/$1.json"
}
reg_dead() { # a registry row whose pid is certainly gone
  mkdir -p "$HOME/.claude/cc-registry"
  printf '{"session_id":"%s","pid":999999,"paneUUID":"pane-%s"}\n' "$1" "${1:0:8}" > "$HOME/.claude/cc-registry/$1.json"
}
transcript() { # <sid> <json line>… — the session's transcript under the fixtured config dir
  local d="$HOME/.claude-next/projects/$(printf '%s' "$BATS_TEST_TMPDIR/wt" | sed 's/[^A-Za-z0-9]/-/g')" sid="$1" l
  mkdir -p "$d"; : > "$d/$sid.jsonl"
  shift; for l in "$@"; do printf '%s\n' "$l" >> "$d/$sid.jsonl"; done
}

# ══ D5 (a): the run's own verdict.txt outranks a non-terminal bundle ══════════════════════════════
@test "a run that ends 'admitted' takes the FAILED in its lr-fleet --one verdict.txt" {
  bundle "$SID" 20261011T032034Z probed admitted >/dev/null
  fleet_verdict "$SID" 20261011T031606Z "lr-fleet --one aaaaaaaa: verdict=FAILED rc=1 pane=113 — lr-handoff rc=1; see stderr"
  run bash "$LR" status "${SID:0:8}"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  local row; row="$(printf '%s\n' "$output" | grep 'bundle-20261011T032034Z')"
  [[ "$row" == *" FAILED "* ]] || { echo "$output"; false; }
  [[ "$row" == *"rail verdict: lr-handoff rc=1"* ]] || { echo "$output"; false; }
  [[ "$row" != *admitted* ]] || { echo "$output"; false; }
  [[ "$output" == *"VERDICT  aaaaaaaa  FAILED  "* ]] || { echo "$output"; false; }
}

@test "a verdict.txt from a run that started AFTER the bundle does not rewrite that bundle's row" {
  bundle "$SID" 20261011T032034Z probed admitted >/dev/null
  fleet_verdict "$SID" 20261011T050000Z "lr-fleet --one aaaaaaaa: verdict=FAILED rc=1 — a later attempt"
  run bash "$LR" status "${SID:0:8}"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$(printf '%s\n' "$output" | grep 'bundle-20261011T032034Z')" == *admitted* ]] || { echo "$output"; false; }
}

# ══ D5 (b): the reconciler's record, and the newest terminal wins ════════════════════════════════
@test "a sid with NO run is answered from the reconciler's terminal record, rc 0" {
  recon_record "$SID" CLOSED 1791693391
  run bash "$LR" status "${SID:0:8}"
  [ "$status" -eq 0 ] || { echo "rc $status: $output"; false; }
  [[ "$output" == *"VERDICT  aaaaaaaa  CLOSED:IN-PLACE  2026-10-11T04:36:31Z  reconciler record recon:c:aaaaaaaa:1"* ]] || { echo "$output"; false; }
  [[ "$output" == *"proof-of-CLOSED"* ]] || { echo "$output"; false; }
}

@test "the NEWEST terminal wins: a reconciler close after the rail's FAILED, and the reverse" {
  bundle "$SID" 20261011T032034Z probed admitted >/dev/null
  fleet_verdict "$SID" 20261011T031606Z "lr-fleet --one aaaaaaaa: verdict=FAILED rc=1 — rsync raced" 1791689000
  recon_record "$SID" CLOSED 1791693391
  run bash "$LR" status "${SID:0:8}"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$(printf '%s\n' "$output" | grep '^VERDICT')" == *"CLOSED:IN-PLACE"* ]] || { echo "$output"; false; }
  [[ "$output" == *"also: FAILED"* ]] || { echo "$output"; false; }
  recon_record "$SID" CLOSED 1791680000
  run bash "$LR" status "${SID:0:8}"
  [[ "$(printf '%s\n' "$output" | grep '^VERDICT')" == *" FAILED "* ]] || { echo "$output"; false; }
}

# ══ D5 (c): a request's fate when no run exists ══════════════════════════════════════════════════
@test "a cc-lr request the poller parked as unknown mode reads REQUEST-PARKED, not 'no runs'" {
  mkdir -p "$LR_STATE_DIR/results"
  printf '{"sid":"%s","mode":"recover","requested_by":"cc-lr","pane":"113"}\n' "$SID" \
    > "$LR_STATE_DIR/results/$SID.cc-lr.unknown-mode.json"
  run bash "$LR" status "${SID:0:8}"
  [ "$status" -eq 0 ] || { echo "rc $status: $output"; false; }
  [[ "$output" == *"VERDICT  aaaaaaaa  REQUEST-PARKED:unknown-mode"* ]] || { echo "$output"; false; }
  [[ "$output" == *"mode recover from cc-lr"* ]] || { echo "$output"; false; }
}

@test "a request the poller retired reads REQUEST-RETIRED with its reason; a queued one reads QUEUED" {
  mkdir -p "$LR_STATE_DIR/results" "$LR_STATE_DIR/requests"
  printf '{"sid":"%s","verdict":"retired","ts":"2026-10-11T03:58:42Z","reason":"transplanted to /x"}\n' "$SID" \
    > "$LR_STATE_DIR/results/$SID.json"
  printf '{"sid":"%s","at":1791690000,"requested_by":"cc-lr","mode":"recover"}\n' "$SID2" \
    > "$LR_STATE_DIR/requests/$SID2.cc-lr.json"
  run bash "$LR" status "${SID:0:8}"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"VERDICT  aaaaaaaa  REQUEST-RETIRED  2026-10-11T03:58:42Z  poller request lane: transplanted to /x"* ]] || { echo "$output"; false; }
  run bash "$LR" status "${SID2:0:8}"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"PENDING  bbbbbbbb  QUEUED since 2026-10-11T03:40:00Z"* ]] || { echo "$output"; false; }
}

@test "CONTROL — a ref nothing anywhere knows is still rc 1" {
  recon_record "$SID" CLOSED 1791693391
  run bash "$LR" status ffffffff
  [ "$status" -eq 1 ] || { echo "$output"; false; }
}

# ══ D5 (d): the session's CURRENT class ══════════════════════════════════════════════════════════
@test "a live session working again after a FAILED reads RESOLVED-OUTSIDE-RAIL (working since <ts>)" {
  bundle "$SID" 20261011T032034Z probed admitted >/dev/null
  fleet_verdict "$SID" 20261011T031606Z "lr-fleet --one aaaaaaaa: verdict=FAILED rc=1 — rsync raced"
  mkdir -p "$LR_STATE_DIR/results"
  printf '{"sid":"%s","verdict":"dispatched","cwd":"%s"}\n' "$SID" "$BATS_TEST_TMPDIR/wt" > "$LR_STATE_DIR/results/$SID.json"
  reg_live "$SID"
  transcript "$SID" \
    '{"type":"assistant","timestamp":"2026-10-11T03:06:18Z","isApiErrorMessage":true,"error":"rate_limit","message":{"content":[{"type":"text","text":"You'"'"'ve hit your weekly limit"}]}}' \
    '{"type":"assistant","timestamp":"2026-10-11T04:19:16Z","message":{"content":[{"type":"text","text":"Resuming."}]}}' \
    '{"type":"assistant","timestamp":"2026-10-11T05:17:06Z","message":{"content":[{"type":"text","text":"Done."}]}}'
  run bash "$LR" status "${SID:0:8}"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"VERDICT  aaaaaaaa  RESOLVED-OUTSIDE-RAIL (working since 2026-10-11T04:19:16Z) — last rail word: FAILED"* ]] || { echo "$output"; false; }
  [[ "$output" == *"now: working (last turn 2026-10-11T05:17:06Z)"* ]] || { echo "$output"; false; }
}

@test "CONTROL — a live session whose last turn is still the limit error keeps the rail's FAILED" {
  fleet_verdict "$SID" 20261011T031606Z "lr-fleet --one aaaaaaaa: verdict=FAILED rc=1 — rsync raced"
  mkdir -p "$LR_STATE_DIR/results"
  printf '{"sid":"%s","verdict":"dispatched","cwd":"%s"}\n' "$SID" "$BATS_TEST_TMPDIR/wt" > "$LR_STATE_DIR/results/$SID.json"
  reg_live "$SID"
  transcript "$SID" \
    '{"type":"assistant","timestamp":"2026-10-11T03:06:18Z","isApiErrorMessage":true,"error":"rate_limit","message":{"content":[{"type":"text","text":"You'"'"'ve hit your weekly limit"}]}}'
  run bash "$LR" status "${SID:0:8}"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"VERDICT  aaaaaaaa  FAILED  "* ]] || { echo "$output"; false; }
  [[ "$output" == *"now: limited"* ]] || { echo "$output"; false; }
  [[ "$output" != *RESOLVED-OUTSIDE-RAIL* ]] || { echo "$output"; false; }
}

# ══ B1-5 skeptic: never offer repair for a sid the reconciler holds ══════════════════════════════
@test "a FAILED run of a LIVE sid the reconciler holds is never offered cc-lr repair" {
  local b; b="$(bundle "$SID" 20261011T032034Z probed "FAILED:submit")"
  recon_record "$SID" "" 0
  reg_live "$SID"
  run bash "$LR" status --all
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" != *"cc-lr repair"* ]] || { echo "$output"; false; }
  [[ "$output" == *"the reconciler holds it (PRE-MOVE/WAIT_RESET); no repair: cc-lr status --cohort next-7d-1"* ]] || { echo "$output"; false; }
}

@test "CONTROL — the same FAILED run with no reconciler record still offers cc-lr repair" {
  local b; b="$(bundle "$SID" 20261011T032034Z probed "FAILED:submit")"
  reg_live "$SID"
  run bash "$LR" status --all
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"→ cc-lr repair $b"* ]] || { echo "$output"; false; }
}

# ══ D8: one registry walk for the whole of status --all ══════════════════════════════════════════
jq_counter() { # wraps jq; logs each call whose argv names the registry
  local real; real="$(PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin command -v jq)"
  { echo '#!/usr/bin/env bash'
    echo "case \"\$*\" in *cc-registry*) echo x >> \"$BATS_TEST_TMPDIR/regwalk.calls\" ;; esac"
    echo "exec \"$real\" \"\$@\""
  } > "$STUBBIN/jq"
  chmod +x "$STUBBIN/jq"
}
three_dead_one_live() {
  bundle "$SID" 20261011T010000Z probed "FAILED:submit" >/dev/null
  bundle "$SID2" 20261011T020000Z probed "FAILED:relaunch" >/dev/null
  bundle "$SID3" 20261011T030000Z probed "FAILED:submit" >/dev/null
  reg_live "$SID"; reg_dead "$SID2"; reg_dead "$SID3"
}

@test "status --all walks the registry ONCE for N sids, not once per sid per file" {
  three_dead_one_live
  jq_counter
  run bash "$LR" status --all
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(wc -l < "$BATS_TEST_TMPDIR/regwalk.calls" | tr -d ' ')" -eq 1 ] || { cat "$BATS_TEST_TMPDIR/regwalk.calls"; false; }
}

@test "the bulk live set renders exactly what the per-sid walk renders (a malformed row forces that walk)" {
  three_dead_one_live
  run bash "$LR" status --all
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  local bulk; bulk="$(printf '%s\n' "$output" | awk '{ $3 = "" } 1')"
  [[ "$output" == *"source session is gone"* ]] || { echo "$output"; false; }
  [[ "$output" == *"cc-lr repair $LR_STATE_DIR/$SID/bundle-20261011T010000Z"* ]] || { echo "$output"; false; }
  printf '{not json' > "$HOME/.claude/cc-registry/zz-broken.json"
  jq_counter
  run bash "$LR" status --all
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(wc -l < "$BATS_TEST_TMPDIR/regwalk.calls" | tr -d ' ')" -gt 1 ]   # the fallback really ran
  [ "$(printf '%s\n' "$output" | awk '{ $3 = "" } 1')" = "$bulk" ] || { echo "bulk:"; echo "$bulk"; echo "walk:"; echo "$output"; false; }
}
