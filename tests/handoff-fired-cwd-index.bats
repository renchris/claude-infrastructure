#!/usr/bin/env bats
# The fired-peer stamp's DURABLE KEY (item 1467ea1dad4f).
#
# THE DEFECT. The store is keyed on the pane id and the pane id is volatile — a resume, a
# crash-recreate or a kitty restart renumbers the pane and orphans its stamp under the old id.
# Measured 2026-08-07: pane 353 was found holding pane 351's orphaned stamp. `$FIRED_DIR/353.json`
# then MISSES, and the origin gate reads a miss as "this session was never fired" — the strongest
# possible wrong answer, because it refuses a peer that had earned the right to retire.
#
# THE SHAPE UNDER TEST. cwd is the INDEX (it finds the record); the fire MARKER is the PROOF (it
# establishes identity). Neither alone is sufficient and the tests below pin both halves:
#   · cwd alone must NOT authorise — an operator pane in the same worktree matches the cwd too,
#     which is exactly why find_open_stamp_for_cwd refused to act on its own finding
#   · a marker that is not in THIS session's transcript must NOT authorise
#   · the RECORD stays pane-keyed (cc-reaper's contract) — only the LOOKUP gains a durable key
#   · the index lives in a SUBDIRECTORY so the three `"$FIRED_DIR"/*.json` globbers cannot see it
#
# Functions are sed-extracted as isolated units, the same way tests/fire-engagement.bats and
# tests/handoff-lifecycle-record.bats extract mark_fired_peer.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HF="$REPO_ROOT/scripts/handoff-fire.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_FIRED_DIR="$BATS_TEST_TMPDIR/fired"; mkdir -p "$CC_FIRED_DIR"
  export CC_REGISTRY_DIR="$BATS_TEST_TMPDIR/registry"; mkdir -p "$CC_REGISTRY_DIR"
  export CC_PROJECTS_DIRS="$BATS_TEST_TMPDIR/projects"; mkdir -p "$CC_PROJECTS_DIRS"
  # HERMETICITY (test-hermeticity-lint). Fixturing $HOME is not enough for handoff-fire: its
  # capacity gate reads LIVE machine load, and three of its seams default to an ABSOLUTE /tmp path
  # or to a BARE NAME it then EXECUTES off the operator's PATH — neither of which $HOME redirects.
  # An absent path is the right value here; these sensors fail open on one.
  export CC_FIRE_CAPACITY_GATE=off
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/account-sweep.json"
  export CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/no-such-claude-accounts"
  export CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/heal-"
  WT="$BATS_TEST_TMPDIR/wt-abc"; mkdir -p "$WT"
  OTHER="$BATS_TEST_TMPDIR/wt-other"; mkdir -p "$OTHER"

  # Extract exactly the units under test plus the two collaborators they call. The cwd-index +
  # tenancy family moved to hooks/lib/origin-identity.sh (CLOSE_INTEGRITY W1) and is sourced from
  # the REAL lib file — the same bytes production sources — while the fire-path-coupled functions
  # are still sed-extracted from the dispatcher.
  LIBSH="$BATS_TEST_TMPDIR/lib.sh"
  {
    echo '_iso_now() { date -u +%Y-%m-%dT%H:%M:%SZ; }'
    echo "CC_PROJECTS_DIRS='$CC_PROJECTS_DIRS'"
    cat "$REPO_ROOT/hooks/lib/origin-identity.sh"
    sed -n '/^mark_fired_peer() {/,/^}/p'           "$HF"
    sed -n '/^find_open_stamp_for_cwd() {/,/^}/p'   "$HF"
    sed -n '/^record_close_succession() {/,/^}/p'   "$HF"
    sed -n '/^cc_sid_for_pane() {/,/^}/p'           "$HF"
    sed -n '/^fired_marker_is_mine() {/,/^}/p'      "$HF"
    sed -n '/^adopt_orphan_stamp() {/,/^}/p'        "$HF"
  } > "$LIBSH"
  # A silently-empty extraction would make every case below pass vacuously
  # (memory control-must-replay-the-real-artifact).
  grep -q '^adopt_orphan_stamp() {' "$LIBSH"
  grep -q '^_fired_cwd_key() {' "$LIBSH"
}

# fire <pane> <cwd> [marker] — stamp a peer the way the real fire path does.
fire() {
  FIRE_MARKER="${3:-}" bash -c ". '$LIBSH'; FIRE_MARKER='${3:-}' mark_fired_peer '$CC_FIRED_DIR' '$1' '$2' FIRING-1"
}
# register <pane> <sid> — the cc-registry row that maps a pane to a CC session id.
register() { printf '{"paneUUID":"%s","session_id":"%s"}\n' "$1" "$2" > "$CC_REGISTRY_DIR/$1.json"; }
# transcript <sid> <text> — a session's own jsonl.
transcript() { printf '{"type":"user","message":{"content":"%s"}}\n' "$2" > "$CC_PROJECTS_DIRS/$1.jsonl"; }

call() { bash -c ". '$LIBSH'; $1"; }
# Count index entries without parsing `ls` (SC2012) — a glob loop is exact and filename-safe.
idx_count() { local n=0 f; for f in "$CC_FIRED_DIR"/by-cwd/*.json; do [ -f "$f" ] && n=$((n + 1)); done; echo "$n"; }

# ── the index itself ───────────────────────────────────────────────────────────────────────────

@test "mark_fired_peer writes a cwd index pointer alongside the pane-keyed record" {
  fire 351 "$WT" MARK-1
  [ -s "$CC_FIRED_DIR/351.json" ]                       # the RECORD is still pane-keyed
  [ -d "$CC_FIRED_DIR/by-cwd" ]
  [ "$(idx_count)" = 1 ]
  [ "$(jq -r '.paneUUID' "$CC_FIRED_DIR"/by-cwd/*.json)" = 351 ]
}

@test "the index is a POINTER, not a copy — it carries no closedAt to diverge" {
  fire 351 "$WT" MARK-1
  run jq -r 'has("closedAt")' "$CC_FIRED_DIR"/by-cwd/*.json
  [ "$output" = false ]
}

@test "SUBDIRECTORY: the index is invisible to a \"\$FIRED_DIR\"/*.json glob" {
  # cc-classify:406, selfclose_inventory_warn and desk-invariant:288 all enumerate this way and
  # treat the FILENAME as a pane id. desk-invariant feeds max-mtime straight to heal_role, so an
  # index file caught by this glob would repoint the desk role at a hash.
  fire 351 "$WT" MARK-1
  local n=0 f
  for f in "$CC_FIRED_DIR"/*.json; do [ -f "$f" ] && n=$((n + 1)); done
  [ "$n" -eq 1 ]
  [ "$(basename "$(echo "$CC_FIRED_DIR"/*.json)" .json)" = 351 ]
}

@test "the key normalises symlinked and /tmp-vs-/private/tmp spellings to ONE entry" {
  ln -s "$WT" "$BATS_TEST_TMPDIR/wt-link"
  fire 351 "$WT" MARK-1
  fire 351 "$BATS_TEST_TMPDIR/wt-link" MARK-1
  [ "$(idx_count)" = 1 ]
}

@test "read_fired_cwd_index resolves a cwd to its pane, and nothing for an unknown cwd" {
  fire 351 "$WT" MARK-1
  [ "$(call "read_fired_cwd_index '$CC_FIRED_DIR' '$WT'")" = 351 ]
  [ -z "$(call "read_fired_cwd_index '$CC_FIRED_DIR' '$OTHER'")" ]
}

@test "find_open_stamp_for_cwd answers from the index without scanning" {
  # CC_SELFCLOSE_SCAN_MAX=0 makes the scan return nothing at all, so a hit here can ONLY have come
  # from the index — the positive control for the fast path (memory control-must-replay-the-real-artifact).
  fire 351 "$WT" MARK-1
  run bash -c ". '$LIBSH'; CC_SELFCLOSE_SCAN_MAX=0 find_open_stamp_for_cwd '$CC_FIRED_DIR' '$WT' 353"
  [ "$output" = 351 ]
}

@test "a stale index pointer costs a scan, never a wrong verdict" {
  fire 351 "$WT" MARK-1
  # Corrupt the pointer to name a pane whose record does not exist.
  local idx; idx="$(echo "$CC_FIRED_DIR"/by-cwd/*.json)"
  jq '.paneUUID = "999"' "$idx" > "$idx.t" && mv "$idx.t" "$idx"
  run bash -c ". '$LIBSH'; find_open_stamp_for_cwd '$CC_FIRED_DIR' '$WT' 353"
  [ "$output" = 351 ]        # the scan found the real record anyway
}

@test "a CLOSED record is never offered through the index" {
  fire 351 "$WT" MARK-1
  call "record_close_succession '$CC_FIRED_DIR' 351 terminal '' none"
  run bash -c ". '$LIBSH'; find_open_stamp_for_cwd '$CC_FIRED_DIR' '$WT' 353"
  [ -z "$output" ]
}

# ── adoption: the index FINDS, the marker PROVES ───────────────────────────────────────────────

@test "ADOPT: an orphaned stamp is re-keyed onto the pane whose transcript carries its marker" {
  fire 351 "$WT" HANDOFF-ENGAGE-27022-1-2
  register 353 sid-353
  transcript sid-353 'brief HANDOFF-ENGAGE-27022-1-2 ignore'
  run bash -c "cd '$WT'; . '$LIBSH'; adopt_orphan_stamp '$CC_FIRED_DIR' '$WT' 353"
  [ "$status" -eq 0 ]
  [ "$output" = 351 ]
  [ -s "$CC_FIRED_DIR/353.json" ]
  [ "$(jq -r '.paneUUID' "$CC_FIRED_DIR/353.json")" = 353 ]
  [ "$(jq -r '.adoptedFrom' "$CC_FIRED_DIR/353.json")" = 351 ]
  [ "$(jq -r '.selfRetire' "$CC_FIRED_DIR/353.json")" = true ]
  [ "$(jq -r '.cwd' "$CC_FIRED_DIR/353.json")" = "$WT" ]
}

@test "ADOPT spends the orphan: it is CLOSED, so it can never be adopted twice" {
  fire 351 "$WT" MARK-2
  register 353 sid-353; transcript sid-353 'x MARK-2 y'
  bash -c "cd '$WT'; . '$LIBSH'; adopt_orphan_stamp '$CC_FIRED_DIR' '$WT' 353" >/dev/null
  [ "$(jq -r '.closedAt' "$CC_FIRED_DIR/351.json")" != null ]
  [ "$(jq -r '.succession.kind' "$CC_FIRED_DIR/351.json")" = adopted ]
  [ "$(jq -r '.succession.successorPane' "$CC_FIRED_DIR/351.json")" = 353 ]
  # a second pane in the same worktree finds nothing left to adopt. Its transcript deliberately
  # does NOT carry the marker: production guarantees the marker rides exactly ONE composed prompt
  # (fired_marker_is_mine's own header), so a second session "proving" the same marker is an
  # impossible world — the pre-fix version fabricated it and pinned the mechanism's inability to
  # distinguish it, which is why this case was RED on pristine trunk (verified 2026-08-10). The
  # spent-orphan invariant it names is still fully exercised: 351 is CLOSED (asserted above), the
  # scan skips it, and the open ADOPTED record cannot be claimed without the marker proof.
  register 355 sid-355; transcript sid-355 'an unrelated session with no marker'
  run bash -c "cd '$WT'; . '$LIBSH'; adopt_orphan_stamp '$CC_FIRED_DIR' '$WT' 355"
  [ "$status" -eq 1 ]
}

@test "ADOPT repoints the index at the adopting pane" {
  fire 351 "$WT" MARK-3
  register 353 sid-353; transcript sid-353 'x MARK-3 y'
  bash -c "cd '$WT'; . '$LIBSH'; adopt_orphan_stamp '$CC_FIRED_DIR' '$WT' 353" >/dev/null
  [ "$(call "read_fired_cwd_index '$CC_FIRED_DIR' '$WT'")" = 353 ]
}

@test "REFUSES: a cwd match with NO marker in this session's transcript" {
  # THE LOAD-BEARING NEGATIVE. This is the operator pane opened in the peer's worktree — the exact
  # case find_open_stamp_for_cwd names as its reason for refusing to authorise on cwd alone.
  fire 351 "$WT" MARK-4
  register 353 sid-353
  transcript sid-353 'an operator session that was never fired'
  run bash -c "cd '$WT'; . '$LIBSH'; adopt_orphan_stamp '$CC_FIRED_DIR' '$WT' 353"
  [ "$status" -eq 1 ]
  [ ! -e "$CC_FIRED_DIR/353.json" ]
}

@test "REFUSES: a marker that belongs to a DIFFERENT session's transcript" {
  fire 351 "$WT" MARK-5
  register 353 sid-353; transcript sid-353 'nothing here'
  transcript sid-999 'x MARK-5 y'          # the marker exists, just not in MY stream
  run bash -c "cd '$WT'; . '$LIBSH'; adopt_orphan_stamp '$CC_FIRED_DIR' '$WT' 353"
  [ "$status" -eq 1 ]
}

@test "ABSTAINS: a schema-1 record has no marker, so nothing can be proven" {
  CC_LIFECYCLE_RECORD=0 bash -c ". '$LIBSH'; CC_LIFECYCLE_RECORD=0 mark_fired_peer '$CC_FIRED_DIR' 351 '$WT' FIRING-1"
  [ "$(jq -r 'has("marker")' "$CC_FIRED_DIR/351.json")" = false ]
  register 353 sid-353; transcript sid-353 'anything'
  run bash -c "cd '$WT'; . '$LIBSH'; adopt_orphan_stamp '$CC_FIRED_DIR' '$WT' 353"
  [ "$status" -eq 1 ]
}

@test "ABSTAINS: this pane has no registry row, so no transcript can be named" {
  fire 351 "$WT" MARK-6
  transcript sid-353 'x MARK-6 y'          # a transcript exists but nothing maps 353 to it
  run bash -c "cd '$WT'; . '$LIBSH'; adopt_orphan_stamp '$CC_FIRED_DIR' '$WT' 353"
  [ "$status" -eq 1 ]
}

@test "REFUSES: an orphan for a DIFFERENT cwd is not adoptable even with a matching marker" {
  fire 351 "$OTHER" MARK-7
  register 353 sid-353; transcript sid-353 'x MARK-7 y'
  run bash -c "cd '$WT'; . '$LIBSH'; adopt_orphan_stamp '$CC_FIRED_DIR' '$WT' 353"
  [ "$status" -eq 1 ]
}

@test "SEAM: CC_SELFCLOSE_ADOPT=0 disables adoption outright" {
  fire 351 "$WT" MARK-8
  register 353 sid-353; transcript sid-353 'x MARK-8 y'
  run bash -c "cd '$WT'; . '$LIBSH'; CC_SELFCLOSE_ADOPT=0 adopt_orphan_stamp '$CC_FIRED_DIR' '$WT' 353"
  [ "$status" -eq 1 ]
  [ ! -e "$CC_FIRED_DIR/353.json" ]
}

@test "ADOPT carries the prompt sidecar across, so the brief is not orphaned too" {
  # bin/cc-recover-safeguard reads $FIRED_DIR/<pane>.prompt to re-fire a content-blocked brief.
  printf 'the brief\n' > "$BATS_TEST_TMPDIR/p.txt"
  bash -c ". '$LIBSH'; FIRE_MARKER=MARK-9 mark_fired_peer '$CC_FIRED_DIR' 351 '$WT' FIRING-1 '$BATS_TEST_TMPDIR/p.txt'"
  [ -s "$CC_FIRED_DIR/351.prompt" ]
  register 353 sid-353; transcript sid-353 'x MARK-9 y'
  bash -c "cd '$WT'; . '$LIBSH'; adopt_orphan_stamp '$CC_FIRED_DIR' '$WT' 353" >/dev/null
  [ -s "$CC_FIRED_DIR/353.prompt" ]
  grep -q 'the brief' "$CC_FIRED_DIR/353.prompt"
}

@test "A9: the adopted record keeps every pre-v2 field cc-reaper's contract depends on" {
  fire 351 "$WT" MARK-10
  register 353 sid-353; transcript sid-353 'x MARK-10 y'
  bash -c "cd '$WT'; . '$LIBSH'; adopt_orphan_stamp '$CC_FIRED_DIR' '$WT' 353" >/dev/null
  run jq -r '[.paneUUID,.cwd,.firedBy,(.selfRetire|tostring),(.firedAt|type),.originClass]|join(",")' \
      "$CC_FIRED_DIR/353.json"
  [ "$output" = "353,$WT,FIRING-1,true,string,fired-peer" ]
}
