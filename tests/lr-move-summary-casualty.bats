#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2016  # each @test is its own subshell; per-test exports are the intent; stub bodies expand in the stub
# THE HIDDEN CASUALTY (move-lane-double-submit, 2026-10-17). Batch 20261017T073813Z-next2-next-26358
# drove 6 sessions. Its watch bound passed at 08:04:43 with 9f6593c5's worker still running; the
# summary and its one mail at 08:06:37 read "done: NOTMOVED=5", and at 08:07:08 that worker wrote
# STRANDED to a batch nobody summarized again. `cc-lr move --status` showed it; the mail never did.
# The record (paths scrubbed) is tests/fixtures/move-lane-2026-10-17/batch, its own summary.json
# included as the defect's evidence.
#
# Pinned: a member with no verdict at the close is counted (RUNNING) and keeps the batch `running`;
# STRANDED leads the summary and the mail, by rank and by name; a late verdict rewrites the summary
# and mails a casualty or the settled batch, and the settle mail goes out once. The library runs
# under /bin/bash, as launchd starts the batch (bash 3.2 ends a `$( )` at a bare case pattern's `)`).
#
# RED-proof: 1, 2, 3, 6 and 7 fail on the pre-fix tree (no lr_move_summary; the runner ranks
# NOTMOVED before STRANDED; the worker rewrites nothing). Mutants, one per site, each red on its case:
# drop the RUNNING rows (1) · drop the `running` status (1) · drop the rank awk (3, 5) · drop the lead
# (2, 3) · drop the casualty arm of lr_move_summary_late (8) · drop its summary.settled claim (4) ·
# drop the worker's lr_move_summary_late call (6) · drop the batch's close recheck (7).

setup() {
  command -v jq >/dev/null || skip "jq required"
  [ -x /bin/bash ] || skip "/bin/bash absent"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_ADMIT_GATE=off CC_FIRE_CAPACITY_GATE=off
  # shellcheck source=/dev/null
  . "$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)/helpers/lr-move-fixture.sh"
  mvf_setup
  FX="$REPO/tests/fixtures/move-lane-2026-10-17/batch"
  export CC_NOTIFY_BIN="$STUBS/cc-notify" NOTIFY_LOG="$BATS_TEST_TMPDIR/notify.log"
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "$NOTIFY_LOG"\n' > "$CC_NOTIFY_BIN"; chmod +x "$CC_NOTIFY_BIN"
  : > "$NOTIFY_LOG"
  RB="20261017T073813Z-next2-next-26358"; RD="$LR_STATE_DIR/move/$RB"; mkdir -p "$RD"
  cp "$FX"/*.json "$FX/workers.tsv" "$RD/"
  rm -f "$RD/summary.json"                       # the record's summary is the defect; each case makes its own
  STR="9f6593c5-fa6d-45eb-babd-5f3be41cd18f"
}
teardown() { mvf_teardown; }

# lib <fn> <args...> — one call into lr-move-lib.sh under /bin/bash; `close` = summary + its mail.
lib() {
  run /bin/bash -c '. "$0"; case "$1" in (close) shift; lr_move_summary "$@" && lr_move_summary_mail ;; (*) "$@" ;; esac' \
    "$LRD/lr-move-lib.sh" "$@"
}
sj() { jq -r "$1" "$RD/summary.json"; }
mails() { grep -c . "$NOTIFY_LOG" || true; }

@test "1 [RED] replay the 08:06:37 close: the member still running is counted, and the batch is not 'done'" {
  # The record: 6 members, the summary counted 5 and called the batch done.
  [ "$(jq -r .verdicts "$FX/summary.json")" = "NOTMOVED=5" ] && [ "$(jq -r .status "$FX/summary.json")" = "done" ] || false
  [ "$(jq '[.rows[] | select(.act == "move")] | length' "$FX/plan.json")" = 6 ]
  mv "$RD/$STR.json" "$BATS_TEST_TMPDIR/late.json"        # its verdict landed at 08:07:08, after the close
  lib close "$RD" "$RB" "done" "" ok 1792222693
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(sj .verdicts)" = "RUNNING=1 NOTMOVED=5" ] || { cat "$RD/summary.json"; false; }
  [ "$(sj .status)" = running ]
  [ "$(sj '.running | join(",")')" = 9f6593c5 ]
  grep -q "^21 cc-lr move $RB (next2 -> next) running: RUNNING=1 NOTMOVED=5;" "$NOTIFY_LOG" || { cat "$NOTIFY_LOG"; false; }
  grep -q "1 member(s) had no verdict yet (9f6593c5)" "$NOTIFY_LOG"
}

@test "2 [RED] replay the 08:07:08 late STRANDED verdict: the summary is rewritten and a mail leads with it" {
  mv "$RD/$STR.json" "$BATS_TEST_TMPDIR/late.json"
  lib close "$RD" "$RB" "done" "" ok 1792222693
  mv "$BATS_TEST_TMPDIR/late.json" "$RD/$STR.json"
  lib lr_move_summary_late "$RD" "$RB"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(sj .status)" = "done" ]
  [ "$(sj .verdicts)" = "STRANDED=1 NOTMOVED=5" ] || { cat "$RD/summary.json"; false; }
  [ "$(sj '.stranded | join(",")')" = 9f6593c5 ] && [ "$(sj '.running | length')" = 0 ] || false
  [ "$(sj .lead)" = "STRANDED 9f6593c5: no live process holds the session (resume debt: open)" ] || { cat "$RD/summary.json"; false; }
  [ "$(mails)" = 2 ] || { cat "$NOTIFY_LOG"; false; }
  sed -n 2p "$NOTIFY_LOG" | grep -q "^21 cc-lr move $RB (next2 -> next) done: STRANDED 9f6593c5: no live process holds the session (resume debt: open) — STRANDED=1 NOTMOVED=5;" \
    || { cat "$NOTIFY_LOG"; false; }
  grep -q "Late verdict: 9f6593c5 STRANDED." "$NOTIFY_LOG"
}

@test "3 [RED] the runner over the whole record under /bin/bash: the summary and the one mail lead with STRANDED" {
  export CC_ACCOUNTS_BIN="$STUBS/claude-accounts" LR_MOVE_GUARD_CHECK=off
  printf '#!/bin/bash\nprintf "next 0.9\\nnext3 0.4\\n"\n' > "$CC_ACCOUNTS_BIN"; chmod +x "$CC_ACCOUNTS_BIN"
  # Every driven row already holds its result, so nothing is claimed or actuated: admit, close, roll-up.
  run /bin/bash "$LRD/lr-move-batch.sh" "$RB"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" != *"syntax error"* ]] || { echo "$output"; false; }
  # RED before the fix: "NOTMOVED=5 STRANDED=1", alphabetical, and nothing named.
  [ "$(sj .verdicts)" = "STRANDED=1 NOTMOVED=5" ] || { cat "$RD/summary.json"; false; }
  [ "$(sj .status)" = "done" ]
  [ "$(mails)" = 1 ] || { cat "$NOTIFY_LOG"; false; }
  grep -q "^21 cc-lr move $RB (next2 -> next) done: STRANDED 9f6593c5: no live process holds the session (resume debt: open) — STRANDED=1 NOTMOVED=5;" "$NOTIFY_LOG" \
    || { cat "$NOTIFY_LOG"; false; }
  [ -d "$RD/summary.settled" ]
}

@test "4 late MOVED verdicts mail nothing until the batch settles, and the settle mail goes out once" {
  mv "$RD/$STR.json" "$BATS_TEST_TMPDIR/late.json"
  mv "$RD/1bf14662-1933-4928-a6a9-8316254979c9.json" "$BATS_TEST_TMPDIR/late2.json"
  lib close "$RD" "$RB" "done" "" ok 1792222693
  [ "$(sj .verdicts)" = "RUNNING=2 NOTMOVED=4" ] || { cat "$RD/summary.json"; false; }
  # The first lands MOVED: rewritten (RUNNING=1), no mail.
  jq '.verdict = "MOVED" | .reason = "pane 7 runs the session on the target, one copy"' "$BATS_TEST_TMPDIR/late.json" > "$RD/$STR.json"
  lib lr_move_summary_late "$RD" "$RB"
  [ "$(sj .verdicts)" = "RUNNING=1 MOVED=1 NOTMOVED=4" ] || { cat "$RD/summary.json"; false; }
  [ "$(mails)" = 1 ] || { cat "$NOTIFY_LOG"; false; }
  # The last lands: settled, one mail. Two last workers: the second read the summary from BEFORE the
  # first rewrote it (restored here), so only the summary.settled claim stops a second settle mail.
  cp "$RD/summary.json" "$BATS_TEST_TMPDIR/pre-settle.json"
  mv "$BATS_TEST_TMPDIR/late2.json" "$RD/1bf14662-1933-4928-a6a9-8316254979c9.json"
  lib lr_move_summary_late "$RD" "$RB"
  cp "$BATS_TEST_TMPDIR/pre-settle.json" "$RD/summary.json"
  lib lr_move_summary_late "$RD" "$RB"
  [ "$(sj .status)" = "done" ] && [ "$(sj .verdicts)" = "MOVED=1 NOTMOVED=5" ] || false
  [ "$(mails)" = 2 ] || { cat "$NOTIFY_LOG"; false; }
  sed -n 2p "$NOTIFY_LOG" | grep -q "done: MOVED=1 NOTMOVED=5;" || { cat "$NOTIFY_LOG"; false; }
}

@test "8 a late STRANDED verdict mails at once, while another member is still running" {
  mv "$RD/$STR.json" "$BATS_TEST_TMPDIR/late.json"
  mv "$RD/1bf14662-1933-4928-a6a9-8316254979c9.json" "$BATS_TEST_TMPDIR/late2.json"
  lib close "$RD" "$RB" "done" "" ok 1792222693
  mv "$BATS_TEST_TMPDIR/late.json" "$RD/$STR.json"
  lib lr_move_summary_late "$RD" "$RB"
  [ "$(sj .status)" = running ] || { cat "$RD/summary.json"; false; }
  [ "$(sj .verdicts)" = "STRANDED=1 RUNNING=1 NOTMOVED=4" ] || { cat "$RD/summary.json"; false; }
  # Not the settle mail (1bf14662 is still running): the casualty's own.
  [ "$(mails)" = 2 ] || { cat "$NOTIFY_LOG"; false; }
  sed -n 2p "$NOTIFY_LOG" | grep -q "running: STRANDED 9f6593c5: no live process holds the session (resume debt: open) — STRANDED=1 RUNNING=1 NOTMOVED=4;" \
    || { cat "$NOTIFY_LOG"; false; }
}

@test "5 the rank: STRANDED, FAILED, RUNNING, then the rest by name" {
  jq '.verdict = "FAILED" | .reason = "guard-blocks: x"' "$RD/1bf14662-1933-4928-a6a9-8316254979c9.json" > "$RD/t" && mv "$RD/t" "$RD/1bf14662-1933-4928-a6a9-8316254979c9.json"
  jq '.verdict = "MOVED"' "$RD/30c3a88d-b42c-47ab-9d00-e7b893b4f174.json" > "$RD/t" && mv "$RD/t" "$RD/30c3a88d-b42c-47ab-9d00-e7b893b4f174.json"
  rm -f "$RD/76033be2-562f-49ab-9f00-958e7a4e9407.json"
  lib close "$RD" "$RB" "done" "" ok 1792222693
  [ "$(sj .verdicts)" = "STRANDED=1 FAILED=1 RUNNING=1 MOVED=1 NOTMOVED=2" ] || { cat "$RD/summary.json"; false; }
}

@test "6 [RED] the worker whose verdict lands after the close rewrites the batch summary itself" {
  W="eeee0001-0000-4000-8000-000000000001"
  # A seventh driven row the plan names without a pane: its worker finishes NOTMOVED at once.
  jq --arg w "$W" '.rows += [{sid:$w, act:"move", disposition:"move"}]' "$FX/plan.json" > "$RD/plan.json"
  lib close "$RD" "$RB" "done" "" ok 1792222693
  [ "$(sj '.running | join(",")')" = eeee0001 ] || { cat "$RD/summary.json"; false; }
  run /bin/bash "$LRD/lr-move-worker.sh" "$RB" "$W"
  [ -f "$RD/$W.json" ] || { echo "$output"; false; }
  [ "$(jq -r .verdict "$RD/$W.json")" = NOTMOVED ]
  # RED before the fix: still `running`, RUNNING=1.
  [ "$(sj .status)" = "done" ] || { cat "$RD/summary.json"; echo "$output"; false; }
  [ "$(sj .verdicts)" = "STRANDED=1 NOTMOVED=6" ]
  [ "$(mails)" = 2 ] || { cat "$NOTIFY_LOG"; false; }
}

@test "7 [RED] a verdict that lands between the close's scan and its summary is not left 'running'" {
  mv "$RD/$STR.json" "$BATS_TEST_TMPDIR/late.json"
  # The batch's own summary(), extracted, with a jq that drops the late verdict in as summary.json is
  # being written: the worker found no summary to rewrite, so only the close can count it.
  real_jq="$(command -v jq)"
  mkdir -p "$BATS_TEST_TMPDIR/shim"
  printf '#!/bin/bash\ncase " $* " in (*" --arg run "*) [ -e "%s" ] || cp "%s" "%s" ;; esac\nexec "%s" "$@"\n' \
    "$RD/$STR.json" "$BATS_TEST_TMPDIR/late.json" "$RD/$STR.json" "$real_jq" > "$BATS_TEST_TMPDIR/shim/jq"
  chmod +x "$BATS_TEST_TMPDIR/shim/jq"
  sed -n '/^summary() {/,/^}/p' "$LRD/lr-move-batch.sh" > "$BATS_TEST_TMPDIR/summary.sh"
  run env PATH="$BATS_TEST_TMPDIR/shim:$PATH" BDIR="$RD" BATCH="$RB" AUTH_AFTER=ok T0=1792222693 /bin/bash -c \
    'say() { printf "%s\n" "$*"; }; . "$0"; . "$1"; summary done ""' "$LRD/lr-move-lib.sh" "$BATS_TEST_TMPDIR/summary.sh"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ -e "$RD/$STR.json" ]
  [ "$(sj .status)" = "done" ] || { cat "$RD/summary.json"; echo "$output"; false; }
  [ "$(sj .verdicts)" = "STRANDED=1 NOTMOVED=5" ]
  [ "$(mails)" = 2 ] || { cat "$NOTIFY_LOG"; false; }
}
