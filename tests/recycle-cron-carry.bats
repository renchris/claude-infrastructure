#!/usr/bin/env bats
# recycle-cron-carry.bats — the session cron carry for self-recycle successors
# (scripts/lib/recycle-cron-carry.sh; design docs/research/selfrecycle-latency-2026-10-26/REPORT.md D3).
#
# WHAT IS LOAD-BEARING. The verdict is the set of jobs the successor will be told to re-create, so every
# case asserts the emitted job objects (or the bytes of the prompt file), never the lib's source. The
# fixture records copy the shapes measured on a real CC 2.1.29x transcript: the CronCreate tool_use in an
# assistant record, its tool_result in a later user record whose `.toolUseResult` carries the job id and the
# harness's durable verdict. A fixture that put the id only in `.input` would let a lib that never reads
# the result pass.
#
# RED-proof: new lib, no pre-fix code; each liveness rule has a case that carries the job when the rule is
# deleted (delete, durable, is_error, fired, expiry), and the order case fails on a lib that sorts by id.
#
# HERMETIC: transcripts and prompt files are built per test under $BATS_TEST_TMPDIR with jq -nc; nothing
# reads a real transcript.

setup() {
  unset CC_RECYCLE_CRON_CARRY
  T="$BATS_TEST_TMPDIR"
  TR="$T/t.jsonl"
  NOW_TS="$(jq -nr 'now | todate')"
  # shellcheck disable=SC1091  # the lib is shellchecked as its own input by the land gate
  . "$BATS_TEST_DIRNAME/../scripts/lib/recycle-cron-carry.sh"
}

# $1=tool_use id $2=cron $3=prompt $4=recurring (true|false|absent) $5=timestamp → an assistant CronCreate record
create() {
  jq -nc --arg tid "$1" --arg cron "$2" --arg p "$3" --arg rec "${4:-true}" --arg ts "${5:-$NOW_TS}" '
    {type: "assistant", timestamp: $ts, message: {role: "assistant", content: [{type: "tool_use", id: $tid,
      name: "CronCreate", input: ({cron: $cron, prompt: $p}
        + (if $rec == "absent" then {} else {recurring: ($rec == "true")} end))}]}}'
}
# $1=tool_use id $2=job id ("" ⇒ no toolUseResult) $3=durable $4=is_error → the user tool_result record
result() {
  jq -nc --arg tid "$1" --arg id "$2" --arg dur "${3:-false}" --arg err "${4:-false}" --arg ts "$NOW_TS" '
    {type: "user", timestamp: $ts, message: {role: "user", content: [{tool_use_id: $tid, type: "tool_result",
      content: ("Scheduled recurring job " + (if $id == "" then "bc2cb960" else $id end)
        + " (17,47 9-22 26 10 *). Session-only (not written to disk, dies when Claude exits)."),
      is_error: ($err == "true")}]}}
    + (if $id == "" then {} else {toolUseResult: {id: $id, humanSchedule: "x", recurring: true,
        durable: ($dur == "true")}} end)'
}
# $1=tool_use id $2=job id → an assistant CronDelete record
delete() {
  jq -nc --arg tid "$1" --arg id "$2" --arg ts "$NOW_TS" '
    {type: "assistant", timestamp: $ts, message: {role: "assistant", content: [{type: "tool_use", id: $tid,
      name: "CronDelete", input: {id: $id}}]}}'
}
# $1=tool_use id $2=is_error → a CronDelete's tool_result record
del_result() {
  jq -nc --arg tid "$1" --arg err "${2:-false}" '
    {type: "user", message: {role: "user", content: [{tool_use_id: $tid, type: "tool_result",
      content: "Cancelled job", is_error: ($err == "true")}]}}'
}
# $1=text → a plain user turn (string content)
turn() { jq -nc --arg t "$1" '{type: "user", message: {role: "user", content: $t}}'; }

@test "one live recurring job: id from toolUseResult, absent recurring reads true, input.durable ignored" {
  jq -nc --arg ts "$NOW_TS" '{type: "assistant", timestamp: $ts, message: {content: [{type: "tool_use",
    id: "toolu_1", name: "CronCreate", input: {cron: "17,47 9-22 26 10 *", prompt: "check the deploy",
    durable: true}}]}}' > "$TR"
  result toolu_1 bc2cb960 >> "$TR"
  run hf_session_crons "$TR"
  [ "$status" -eq 0 ]
  [ "$output" = "$(jq -nc --arg ts "$NOW_TS" '{id: "bc2cb960", cron: "17,47 9-22 26 10 *",
    prompt: "check the deploy", recurring: true, created_at: $ts}')" ]
}

@test "id falls back to the tool_result text when toolUseResult is absent" {
  { create toolu_1 "*/5 * * * *" "poll"; result toolu_1 ""; } > "$TR"
  run hf_session_crons "$TR"
  [ "$status" -eq 0 ]
  [ "$(jq -r .id <<<"$output")" = bc2cb960 ]
}

@test "create then delete leaves no job; a failed delete leaves it live" {
  { create toolu_1 "*/5 * * * *" "poll"; result toolu_1 aaaaaa01
    delete toolu_2 aaaaaa01; del_result toolu_2
    create toolu_3 "*/7 * * * *" "kept"; result toolu_3 bbbbbb02
    delete toolu_4 bbbbbb02; del_result toolu_4 true; } > "$TR"
  run hf_session_crons "$TR"
  [ "$status" -eq 0 ]
  [ "$(jq -sc '[.[].id]' <<<"$output")" = '["bbbbbb02"]' ]
}

@test "a durable:true result is not carried (it survives the exit by itself)" {
  { create toolu_1 "*/5 * * * *" "poll"; result toolu_1 aaaaaa01 true; } > "$TR"
  run hf_session_crons "$TR"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "an is_error create result is not carried" {
  { create toolu_1 "*/5 * * * *" "poll"; result toolu_1 aaaaaa01 false true; } > "$TR"
  run hf_session_crons "$TR"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "a one-shot whose prompt came back as a later user turn has fired and is not carried" {
  p="remind me to check the land at 15:30 — exactly this text"
  { create toolu_1 "30 15 26 10 *" "$p" false; result toolu_1 aaaaaa01; turn "$p"; } > "$TR"
  run hf_session_crons "$TR"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "a one-shot not yet fired is carried, even when an EARLIER turn held the same text" {
  p="remind me to check the land at 15:30"
  { turn "$p"; create toolu_1 "30 15 26 10 *" "$p" false; result toolu_1 aaaaaa01; turn "unrelated"; } > "$TR"
  run hf_session_crons "$TR"
  [ "$status" -eq 0 ]
  [ "$(jq -c '[.id, .recurring]' <<<"$output")" = '["aaaaaa01",false]' ]
}

@test "a recurring job created over 7 days ago has expired; one 6 days old is carried" {
  old="$(jq -nr 'now - 8 * 86400 | todate')" six="$(jq -nr 'now - 6 * 86400 | todate')"
  { create toolu_1 "*/5 * * * *" "old" true "$old"; result toolu_1 aaaaaa01
    create toolu_2 "*/5 * * * *" "young" true "$six"; result toolu_2 bbbbbb02; } > "$TR"
  run hf_session_crons "$TR"
  [ "$status" -eq 0 ]
  [ "$(jq -sc '[.[].prompt]' <<<"$output")" = '["young"]' ]
}

@test "two jobs come out in creation order, not id order" {
  { create toolu_1 "1 * * * *" "first"; result toolu_1 ffffff01
    create toolu_2 "2 * * * *" "second"; result toolu_2 aaaaaa02; } > "$TR"
  run hf_session_crons "$TR"
  [ "$status" -eq 0 ]
  [ "$(jq -sc '[.[].id]' <<<"$output")" = '["ffffff01","aaaaaa02"]' ]
}

@test "missing transcript and a transcript with no cron lines both give no jobs, rc 0" {
  run hf_session_crons "$T/absent.jsonl"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  turn "hello" > "$TR"
  run hf_session_crons "$TR"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "block: marker, header, one ~~~json fence per job, a prompt with a backtick and quote round-trips" {
  # shellcheck disable=SC2016  # the backticks are the fixture: literal text that must survive the round trip
  p='run `cc-wrap` and say "done"'
  { create toolu_1 "1 * * * *" "$p"; result toolu_1 aaaaaa01
    create toolu_2 "2 * * * *" "plain"; result toolu_2 bbbbbb02; } > "$TR"
  run hf_cron_carry_block "$TR"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = '<!-- recycle-cron-carry v1 -->' ]
  [ "${lines[1]}" = '## Session scheduled tasks to re-create' ]
  [ "$(grep -c -x -F '~~~json' <<<"$output")" -eq 2 ]
  [ "$(grep -c -x -F '~~~' <<<"$output")" -eq 2 ]
  [ "$(grep -c -F '```' <<<"$output")" -eq 0 ]
  first="$(grep -A1 -x -F '~~~json' <<<"$output" | sed -n 2p)"
  [ "$(jq -r .prompt <<<"$first")" = "$p" ]
  [ "$(jq -c 'keys' <<<"$first")" = '["cron","prompt","recurring"]' ]
}

@test "block: rc 1 and no output when nothing is live" {
  turn "hello" > "$TR"
  run hf_cron_carry_block "$TR"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "append: rc 0 adds the block after one blank line and keeps mode 0600; a second append is rc 2 and changes nothing" {
  { create toolu_1 "1 * * * *" "poll"; result toolu_1 aaaaaa01; } > "$TR"
  pf="$T/prompt.txt"; printf 'brief line\n' > "$pf"; chmod 600 "$pf"
  run hf_cron_carry_append "$TR" "$pf"
  [ "$status" -eq 0 ]
  [ "$output" = "→ cron-carry: 1 job(s) appended to $pf" ]
  [ "$(sed -n 1,3p "$pf")" = "$(printf 'brief line\n\n<!-- recycle-cron-carry v1 -->')" ]
  [ "$(stat -f %Lp "$pf" 2>/dev/null || stat -c %a "$pf")" = 600 ]
  cp "$pf" "$T/after-first"
  run hf_cron_carry_append "$TR" "$pf"
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  cmp -s "$pf" "$T/after-first"
}

@test "append: a prompt file without a trailing newline still gets one blank line before the block" {
  { create toolu_1 "1 * * * *" "poll"; result toolu_1 aaaaaa01; } > "$TR"
  pf="$T/prompt.txt"; printf 'no newline' > "$pf"
  run hf_cron_carry_append "$TR" "$pf"
  [ "$status" -eq 0 ]
  [ "$(sed -n 1,3p "$pf")" = "$(printf 'no newline\n\n<!-- recycle-cron-carry v1 -->')" ]
}

@test "append: rc 1 and the file untouched when there is nothing to carry" {
  turn "hello" > "$TR"
  pf="$T/prompt.txt"; printf 'brief\n' > "$pf"; cp "$pf" "$T/orig"
  run hf_cron_carry_append "$TR" "$pf"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
  cmp -s "$pf" "$T/orig"
}

@test "append: rc 3 for a missing prompt file and for an unwritable one, which stays byte-identical" {
  { create toolu_1 "1 * * * *" "poll"; result toolu_1 aaaaaa01; } > "$TR"
  run hf_cron_carry_append "$TR" "$T/absent.txt"
  [ "$status" -eq 3 ]
  [ ! -e "$T/absent.txt" ]
  pf="$T/ro.txt"; printf 'brief\n' > "$pf"; cp "$pf" "$T/orig"; chmod 400 "$pf"
  run hf_cron_carry_append "$TR" "$pf"
  [ "$status" -eq 3 ]
  cmp -s "$pf" "$T/orig"
}

@test "append: CC_RECYCLE_CRON_CARRY=off is rc 1 and writes nothing" {
  { create toolu_1 "1 * * * *" "poll"; result toolu_1 aaaaaa01; } > "$TR"
  pf="$T/prompt.txt"; printf 'brief\n' > "$pf"; cp "$pf" "$T/orig"
  CC_RECYCLE_CRON_CARRY=off run hf_cron_carry_append "$TR" "$pf"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
  cmp -s "$pf" "$T/orig"
}

# $1=transcript → runs hf_session_crons, output to $T/out, its CPU seconds (user+sys, children included) on stdout
cpu_secs() {
  local TIMEFORMAT='%U %S'
  { time hf_session_crons "$1" > "$T/out"; } 2> "$T/time"
  awk '{ print $1 + $2 }' "$T/time"
}

@test "a 50 MB transcript costs under 2 s of CPU, with no cron line and with one live job at its end" {
  if [ "${CC_SKIP_SLOW:-}" = 1 ]; then skip "CC_SKIP_SLOW=1"; fi
  # CPU, not wall: at load 60-130 a 0.06 s-user run measured 1.6 s wall and a 0.27 s one 11.7 s, so a
  # wall bound here convicts the scheduler. The lib's own cost is what a slow parse would raise.
  turn "$(printf 'filler %.0s' $(seq 1 120))" > "$T/chunk"
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16; do cat "$T/chunk" "$T/chunk" > "$T/c2"; mv "$T/c2" "$T/chunk"; done
  # 2^16 lines of ~0.9 KB is ~57 MB.
  mv "$T/chunk" "$TR"
  [ "$(wc -c < "$TR")" -ge 50000000 ]
  cpu="$(cpu_secs "$TR")"
  [ ! -s "$T/out" ]
  awk -v c="$cpu" 'BEGIN { exit !(c < 2) }'
  { create toolu_1 "1 * * * *" "poll"; result toolu_1 aaaaaa01; } >> "$TR"
  cpu="$(cpu_secs "$TR")"
  [ "$(jq -r .id "$T/out")" = aaaaaa01 ]
  awk -v c="$cpu" 'BEGIN { exit !(c < 2) }'
}
