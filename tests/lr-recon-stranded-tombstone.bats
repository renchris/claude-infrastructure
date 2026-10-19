#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2016  # each @test is its own subshell; per-test exports are the intent
# A tombstoned session whose successor never started is STRANDED, and its remedy is exit + resume
# in the SAME pane (lr-wake 2026-10-18, h defect 5; Wave G).
#
# 3e929a81 at 03:03Z: the next4→next3 transplant wrote …3e929a81.HANDOFF.json and renamed the next4
# transcript .jsonl.handed-off; the next3 copy stayed byte-identical (4,040,651 bytes, mtime 02:56)
# and the old next4 process sat in pane 23 behind the handed-off guard for ~10 h. The remedy that
# worked by hand: /exit (no background work, so no modal), then lr-fire-resume.sh next3 <cwd> <sid>.
# WHAT IS PINNED:
#   · the census names it (census.stranded_tombstone) and the pass pages it once with its command;
#     a young tombstone, a successor that wrote, or a live copy on the target is not stranded;
#   · lr-unstrand.sh REFUSES with nothing typed on background work (rc 6) or a non-empty composer
#     (rc 6), and when the successor ran (rc 3);
#   · with neither, it types /exit, waits for the old process to end, then types the resume line
#     into the SAME pane's shell; --dry-run types nothing.
# [RED] cases fail on the tree before the fix.
#
# Hermetic: stores, registry, `ps` snapshot, cc-tui and lr-fire-resume are fixtures; the "old
# process" is a sleep under a bash parent. Nothing here reaches a live pane.

setup() {
  command -v jq >/dev/null || skip "jq required"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd -P)"
  UNSTRAND="$REPO/scripts/limit-recover/lr-unstrand.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  # lr-unstrand sources lr-lib/lr-upgrade, which reach capacity-admit: pin it, never the live box
  export CC_FIRE_CAPACITY_GATE=off CC_ADMIT_GATE=off
  export LR_STATE_DIR="$HOME/.reso/limit-recover"; mkdir -p "$LR_STATE_DIR"
  export CC_REGISTRY_DIR="$BATS_TEST_TMPDIR/reg"; mkdir -p "$CC_REGISTRY_DIR"
  export LRU_PS_SNAPSHOT="$BATS_TEST_TMPDIR/ps.txt"
  export LR_PAGE_ONCE_BIN="$BATS_TEST_TMPDIR/absent-pager"
  export LR_UNSTRAND_SHELL_SETTLE_S=0 LR_UNSTRAND_EXIT_WAIT_S=10 LR_STRANDED_QUIET_S=600
  SID="3e929a81-0000-4000-8000-000000000001"; PANE=23
  SRC="$HOME/.claude-quaternary"; DST="$HOME/.claude-tertiary"
  mkdir -p "$SRC/projects/-x" "$DST/projects/-x" "$BATS_TEST_TMPDIR/cwd"
  export LR_UNSTRAND_CFG_DIRS="$SRC"$'\n'"$DST"
  # the stores: a byte copy on the target, older than the tombstone written 20 minutes ago
  local body ts
  body='{"type":"assistant","isApiErrorMessage":true,"error":"rate_limit"}'
  printf '%s\n' "$body" > "$DST/projects/-x/$SID.jsonl"
  printf '%s\n' "$body" > "$SRC/projects/-x/$SID.jsonl.handed-off"
  touch -t "$(date -v-27M +%Y%m%d%H%M.%S 2>/dev/null || date -d '-27 min' +%Y%m%d%H%M.%S)" "$DST/projects/-x/$SID.jsonl"
  ts="$(date -u -v-20M +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '-20 min' +%Y-%m-%dT%H:%M:%SZ)"
  printf '{"handed_off_to":"%s","target_transcript":"%s","ts":"%s","confirm_len":%d}\n' \
    "$DST" "$DST/projects/-x/$SID.jsonl" "$ts" "$(wc -c < "$DST/projects/-x/$SID.jsonl" | tr -d ' ')" \
    > "$SRC/projects/-x/$SID.HANDOFF.json"
  # the old process: a sleep whose parent is a shell, registered on the source in pane 23
  bash -c 'sleep 900 3>&- & echo $! > "$1"; wait' _ "$BATS_TEST_TMPDIR/old.pid" 3>&- &
  PARENT=$!
  for _ in 1 2 3 4 5 6 7 8 9 10; do [ -s "$BATS_TEST_TMPDIR/old.pid" ] && break; sleep 0.2; done
  OLD="$(cat "$BATS_TEST_TMPDIR/old.pid")"
  printf '{"paneUUID":"%s","pid":%d,"session_id":"%s","account":"claude-quaternary","cwd":"%s"}\n' \
    "$PANE" "$OLD" "$SID" "$BATS_TEST_TMPDIR/cwd" > "$CC_REGISTRY_DIR/$PANE.json"
  printf '%d %d Tue Sep 22 06:47:13 2026 /opt/cc/claude --resume %s\n' "$OLD" "$PARENT" "$SID" > "$LRU_PS_SNAPSHOT"
  # a stub cc-tui: the box is the file composer-23; /exit ends the old process
  TUI="$BATS_TEST_TMPDIR/tui.sh"; export LR_UNSTRAND_TUI_LIB="$TUI"
  printf '' > "$BATS_TEST_TMPDIR/composer-$PANE"
  cat > "$TUI" <<EOF
cc_tui_valid_id() { case "\${1:-}" in ''|*[!0-9]*) return 1 ;; *) return 0 ;; esac; }
cc_tui_composer() { tr -d '[:space:]' < "$BATS_TEST_TMPDIR/composer-\$1"; }
cc_tui_screen() { printf 'some output\n'; }
cc_tui_submit() { printf 'submit %s %s\n' "\$1" "\$(cat "\$2")" >> "$BATS_TEST_TMPDIR/keys.log"; kill $OLD; return 5; }
cc_tui_type_keys() { printf 'type %s %s\n' "\$1" "\$(cat "\$2")" >> "$BATS_TEST_TMPDIR/keys.log"; }
cc_tui_cr() { printf 'cr %s\n' "\$1" >> "$BATS_TEST_TMPDIR/keys.log"; }
EOF
}
teardown() { kill "${OLD:-0}" "${PARENT:-0}" 2>/dev/null || true; }
py() { (cd "$REPO/scripts/limit-recover" && python3 -m unittest "lr_recon.tests.test_wave_g.StrandedTombstone.$1" 2>&1); }

@test "1 [RED] census: a quiet tombstone with its old process in a pane is STRANDED, with its remedy" {
  run py test_a_quiet_tombstone_with_its_old_process_in_a_pane_is_stranded
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  run py test_controls_a_young_a_grown_or_a_live_successor_is_not_stranded
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "2 [RED] reconciler: the stranded session is recorded and paged once" {
  run py test_the_pass_records_and_pages_it_once
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "3 [RED] lr-unstrand: background work is REFUSED (rc 6) with nothing typed" {
  printf '%d %d Tue Sep 22 06:47:13 2026 /bin/zsh -c source ~/.claude/shell-snapshots/snap.sh && sleep 1800\n' 99999 "$OLD" >> "$LRU_PS_SNAPSHOT"
  run bash "$UNSTRAND" --sid "$SID"
  [ "$status" -eq 6 ] || { echo "$output"; false; }
  [[ "$output" == *"background work"* ]] || { echo "$output"; false; }
  [ ! -e "$BATS_TEST_TMPDIR/keys.log" ]
  kill -0 "$OLD"
}

@test "4 [RED] lr-unstrand: a non-empty composer is REFUSED (rc 6) with nothing typed" {
  printf '/exit\n' > "$BATS_TEST_TMPDIR/composer-$PANE"
  run bash "$UNSTRAND" --sid "$SID"
  [ "$status" -eq 6 ] || { echo "$output"; false; }
  [ ! -e "$BATS_TEST_TMPDIR/keys.log" ]
}

@test "5 [RED] lr-unstrand: a successor that wrote is not stranded (rc 3)" {
  printf '{"type":"user"}\n' >> "$DST/projects/-x/$SID.jsonl"
  run bash "$UNSTRAND" --sid "$SID"
  [ "$status" -eq 3 ] || { echo "$output"; false; }
  [ ! -e "$BATS_TEST_TMPDIR/keys.log" ]
}

@test "6 [RED] lr-unstrand --dry-run prints the same-pane plan and types nothing" {
  run bash "$UNSTRAND" --sid "$SID" --dry-run
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"PLAN pane $PANE pid $OLD: /exit, then in the same pane: bash "*"lr-fire-resume.sh $DST "*" $SID"* ]] || { echo "$output"; false; }
  [ ! -e "$BATS_TEST_TMPDIR/keys.log" ]
}

@test "7 [RED] lr-unstrand: /exit, the old process ends, then the resume line in the SAME pane" {
  run bash "$UNSTRAND" --sid "$SID"
  [ "$status" -eq 0 ] || { echo "$output"; cat "$BATS_TEST_TMPDIR/keys.log" 2>/dev/null; false; }
  [[ "$output" == *"RESUMED pane $PANE"* ]] || { echo "$output"; false; }
  run cat "$BATS_TEST_TMPDIR/keys.log"
  [ "${lines[0]}" = "submit $PANE /exit" ] || { echo "$output"; false; }
  [[ "${lines[1]}" == "type $PANE bash "*"lr-fire-resume.sh $DST $BATS_TEST_TMPDIR/cwd $SID" ]] || { echo "$output"; false; }
  [ "${lines[2]}" = "cr $PANE" ] || { echo "$output"; false; }
  [ "${#lines[@]}" -eq 3 ]
  # the run claim is released
  [ ! -e "$LR_STATE_DIR/runs/by-sid/$SID.active" ]
}
