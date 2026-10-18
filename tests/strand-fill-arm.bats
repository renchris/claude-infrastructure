#!/usr/bin/env bats
# strand-fill-arm.sh — start fill work on an account falling behind its weekly pace (weekly-strand
# post-mortem docs/research/weekly-strand-next-2026-10-18/REPORT.md §4 item 1).
#
# The load-bearing property is the NEGATIVE one, as in drain-revival-arm.bats: the fire binary runs
# in exactly one case (mode on, pace behind, no alarm hold, under KMAX, admitted, no live cooldown,
# a prompt file, a claimed stamp). Every case that could fire asserts whether the stub was called.
#
# RED-proof: the replay case is the acceptance test. With the pace rule's `behind` arm removed (every
# account reads on-pace) it finds no fire for next before Oct 17 and goes red; with r raised to 4.0
# its first fire moves past Oct 16. The fixture is an hourly slice (2026-10-13T00Z..10-17T00Z) of
# ~/.claude/logs/account-utilization.jsonl: weekly_pct and weekly_reset_h as logged, k from the
# native census, burn_wk_flat_ph = the 24h weekly-pct delta / hours within one weekly window.
# HOME is fixtured; claude-accounts, the fire path and the alarm log are stubs or fixtures.

setup() {
  export HOME="${BATS_TEST_TMPDIR}/home"; mkdir -p "$HOME"
  SUBJECT="${BATS_TEST_DIRNAME}/../scripts/strand-fill-arm.sh"
  FIXTURE="${BATS_TEST_DIRNAME}/fixtures/strand-fill/week-2026-10-18.jsonl"
  export CC_STRAND_FILL_STATE_DIR="${BATS_TEST_TMPDIR}/state"
  export CC_STRAND_FILL_ALARM_LOG="${BATS_TEST_TMPDIR}/capacity-alarm.jsonl"
  export CC_STRAND_FILL_KMAX=24 CC_STRAND_FILL_INTERVAL_S=0
  export CC_STRAND_FILL_NOW=1792200000
  SNAP="${BATS_TEST_TMPDIR}/snap.json"; CALLS="${BATS_TEST_TMPDIR}/accounts.calls"
  export CC_STRAND_FILL_ACCOUNTS_BIN="${BATS_TEST_TMPDIR}/accounts-stub"
  printf '#!/bin/bash\necho "$*" >> "%s"\ncat "%s"\n' "$CALLS" "$SNAP" > "$CC_STRAND_FILL_ACCOUNTS_BIN"
  FIRE_LOG="${BATS_TEST_TMPDIR}/fire.log"
  export CC_STRAND_FILL_FIRE_BIN="${BATS_TEST_TMPDIR}/fire-stub.sh"
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "%s"\nexit 0\n' "$FIRE_LOG" > "$CC_STRAND_FILL_FIRE_BIN"
  chmod +x "$CC_STRAND_FILL_ACCOUNTS_BIN" "$CC_STRAND_FILL_FIRE_BIN"
  # Admission: the real library, every term but `active` off, the census pinned, its records local.
  export CC_ADMIT_STATE_DIR="${BATS_TEST_TMPDIR}/admit" CC_ADMIT_IDL="${BATS_TEST_TMPDIR}/admit.jsonl"
  export CC_ADMIT_NOTIFY_BIN=/usr/bin/true CC_ADMIT_BUDGET=99
  export CC_ADMIT_HEADROOM_TERM=off CC_ADMIT_SEGMENT_TERM=off CC_SP_ACTIVE_OVERRIDE=0
  # The reserve terms read the LIVE box (a ps tree census, vm_stat) and refused intermittently at
  # ~42 live sessions; the operator slot under test is the arm's own ceiling 7, not the reserve.
  export CC_ADMIT_RESERVE_TERM=off
  unset CC_STRAND_FILL CC_STRAND_FILL_PROMPT_FILE CC_STRAND_FILL_RATE_PPH CC_ADMIT_GATE
}

# One account behind pace (the Oct 16 16Z shape of next: 35%, reset 36h, 0.25 pp/h) beside one far off.
behind() { # [k] [reset_h] [weekly_pct]
  jq -nc --argjson k "${1:-3}" --argjson h "${2:-36}" --argjson p "${3:-35}" '{rows:[
    {acct:"next", auth:"ok", weekly_pct:$p, weekly_reset_h:$h, burn_wk_flat_ph:0.25, k:$k},
    {acct:"next3", auth:"ok", weekly_pct:2, weekly_reset_h:150, burn_wk_flat_ph:0.08, k:2}]}' > "$SNAP"
}
line() { printf '%s\n' "$output" | jq -c --arg a "$1" 'select(.acct == $a)'; }
decision() { line "${1:-next}" | jq -r '.decision'; }
fires() { [ -f "$FIRE_LOG" ] && wc -l < "$FIRE_LOG" | tr -d ' ' || echo 0; }
alarm() { # <verdict> <age_s>
  printf '{"ts":"%s","verdict":"%s"}\n' "$(date -u -r $(( CC_STRAND_FILL_NOW - $2 )) +%Y-%m-%dT%H:%M:%SZ)" "$1" \
    > "$CC_STRAND_FILL_ALARM_LOG"
}

@test "replay of the week ending 2026-10-18: the arm would fire for next by Oct 16 at the latest" {
  [ -s "$FIXTURE" ]
  local ts first=""
  while IFS= read -r snap; do
    ts="$(jq -r '.ts' <<<"$snap")"
    jq -c '{rows: [.rows[] | . + {auth: "ok"}]}' <<<"$snap" > "$SNAP"
    rm -rf "$CC_STRAND_FILL_STATE_DIR"
    run bash "$SUBJECT" --tick
    [ "$status" -eq 0 ]
    if [ "$(decision next)" = would-fire ]; then first="$ts"; break; fi
  done < "$FIXTURE"
  echo "first would-fire for next: ${first:-none}"
  [ -n "$first" ]
  [[ "$first" < "2026-10-17T00:00:00Z" ]] || false
  line next | jq -e '.cmd | test("--account next")' >/dev/null
  [ "$(fires)" = 0 ]                                    # would-fire launches nothing
}

@test "default mode is would-fire: a behind account is decided and logged, nothing launched" {
  behind
  run bash "$SUBJECT" --tick
  [ "$status" -eq 0 ]
  [ "$(decision)" = would-fire ]
  line next | jq -e '.mode == "would-fire" and .pace == "behind" and .need_pph > 1.8' >/dev/null
  [ "$(decision next3)" = outside-horizon ]             # a line for EVERY account, not only the fire
  [ "$(fires)" = 0 ]
}

@test "on: launches once, pinned to the account, with the fill brief; a second tick is cooldown-held" {
  behind
  printf 'fill work\n' > "${BATS_TEST_TMPDIR}/brief.txt"
  export CC_STRAND_FILL=on CC_STRAND_FILL_PROMPT_FILE="${BATS_TEST_TMPDIR}/brief.txt"
  run bash "$SUBJECT" --tick
  [ "$(decision)" = fired ]
  [ "$(fires)" = 1 ]
  grep -q -- "--prompt-file ${BATS_TEST_TMPDIR}/brief.txt --account next" "$FIRE_LOG"
  CC_STRAND_FILL_NOW=$(( CC_STRAND_FILL_NOW + 600 )) run bash "$SUBJECT" --tick
  [ "$(decision)" = cooldown-held ]
  [ "$(fires)" = 1 ]
}

@test "on with no fill brief fails closed: no-work, nothing launched, no stamp claimed" {
  behind
  CC_STRAND_FILL=on run bash "$SUBJECT" --tick
  [ "$(decision)" = no-work ]
  [ "$(fires)" = 0 ]
  [ ! -e "$CC_STRAND_FILL_STATE_DIR/fire-next.stamp" ]
}

@test "off reads nothing; an unknown mode fails closed as bad-mode" {
  behind
  CC_STRAND_FILL=off run bash "$SUBJECT" --tick
  [ "$(printf '%s' "$output" | jq -r '.decision')" = off ]
  [ ! -e "$CALLS" ]
  CC_STRAND_FILL=yes run bash "$SUBJECT" --tick
  [ "$(printf '%s' "$output" | jq -r '.decision')" = bad-mode ]
  [ "$(fires)" = 0 ]
}

@test "a fresh ALARM holds the fire unless the reset is under 12h; a stale ALARM is not believed" {
  behind
  alarm ALARM 60
  CC_STRAND_FILL=on CC_STRAND_FILL_PROMPT_FILE="$FIXTURE" run bash "$SUBJECT" --tick
  [ "$(decision)" = alarm-held ]
  [ "$(fires)" = 0 ]
  behind 3 10 80                                        # 10h left, 20pp short, feasible: alarm yields
  run bash "$SUBJECT" --tick
  [ "$(decision)" = would-fire ]
  behind
  alarm ALARM 1200                                      # 20 min old: stale, ignored
  rm -rf "$CC_STRAND_FILL_STATE_DIR"
  run bash "$SUBJECT" --tick
  [ "$(decision)" = would-fire ]
}

@test "KMAX and admission hold the fire: k at KMAX, and active + 1 over 8 minus the operator slot" {
  behind 24
  CC_STRAND_FILL=on CC_STRAND_FILL_PROMPT_FILE="$FIXTURE" run bash "$SUBJECT" --tick
  [ "$(decision)" = kmax-held ]
  behind
  CC_SP_ACTIVE_OVERRIDE=7 CC_STRAND_FILL=on CC_STRAND_FILL_PROMPT_FILE="$FIXTURE" run bash "$SUBJECT" --tick
  [ "$(decision)" = admit-refused ]
  [ "$(fires)" = 0 ]
  grep -q '"caller":"strand-fill"' "$CC_ADMIT_IDL"
  CC_SP_ACTIVE_OVERRIDE=6 run bash "$SUBJECT" --tick     # 6 + 1 = 7: the last non-reserve slot
  [ "$(decision)" = would-fire ]
}

@test "pace verdicts: on-pace once projected to finish, pace-unknown without a rate, 96h horizon in a reset cluster" {
  jq -nc '{rows:[
    {acct:"finishing", weekly_pct:80, weekly_reset_h:30, burn_wk_flat_ph:0.9, k:1},
    {acct:"blind", weekly_pct:10, weekly_reset_h:400, k:1},
    {acct:"norate", weekly_pct:10, weekly_reset_h:30, k:1},
    {acct:"far", weekly_pct:10, weekly_reset_h:84, burn_wk_flat_ph:0.1, k:1},
    {acct:"peer", weekly_pct:95, weekly_reset_h:70, burn_wk_flat_ph:0.1, k:1}]}' > "$SNAP"
  run bash "$SUBJECT" --tick
  [ "$(decision finishing)" = on-pace ]
  [ "$(decision blind)" = outside-horizon ]
  [ "$(decision norate)" = pace-unknown ]
  [ "$(decision far)" = would-fire ]                    # 84h > 72h, but peer resets within 24h
  line far | jq -e '.horizon_h == 96' >/dev/null
  jq -c '.rows |= map(select(.acct != "peer"))' "$SNAP" > "$SNAP.t" && mv "$SNAP.t" "$SNAP"
  rm -rf "$CC_STRAND_FILL_STATE_DIR"
  run bash "$SUBJECT" --tick
  [ "$(decision far)" = outside-horizon ]
}

@test "cadence: inside the interval one interval-held line, no read; no rows is a no-data line" {
  behind
  export CC_STRAND_FILL_INTERVAL_S=1800
  run bash "$SUBJECT" --tick
  [ "$(decision)" = would-fire ]
  : > "$CALLS"
  CC_STRAND_FILL_NOW=$(( CC_STRAND_FILL_NOW + 300 )) run bash "$SUBJECT" --tick
  [ "$(printf '%s' "$output" | jq -r '.decision')" = interval-held ]
  [ ! -s "$CALLS" ]
  echo '{"rows":[]}' > "$SNAP"
  CC_STRAND_FILL_NOW=$(( CC_STRAND_FILL_NOW + 3600 )) run bash "$SUBJECT" --tick
  [ "$(printf '%s' "$output" | jq -r '.decision')" = no-data ]
}
