#!/usr/bin/env bats
# scripts/kalloc-exec-census.sh (REPORT §3 Phase 0, docs/research/kalloc-longterm-2026-10-21/REPORT.md):
# the census must never write an env value beyond its three allow-listed keys. The 2026-10-21 run
# stored every exec's full environment (API keys, tokens) in a 26 GB world-readable file.
#
# RED-proof: feed the same fixture through the old tool's own filter (it popped `env` but kept every
# other field verbatim, and before that wrote eslogger's raw stream) and the secret is on disk.
#
# Hermetic: $HOME is a fixture; sudo is a PATH stub that runs its argv without privilege, and
# eslogger is a stub that prints a fixed stream.

SECRET="sk-ant-TESTSECRET-0123456789"

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME" "$BATS_TEST_TMPDIR/bin"
  # sudo stub: drop its own options, run the rest unprivileged.
  # shellcheck disable=SC2016  # the stub's own $1/$@, not ours
  printf '#!/bin/bash\nwhile [ "${1#-}" != "$1" ]; do shift; done\nexec "$@"\n' > "$BATS_TEST_TMPDIR/bin/sudo"
  chmod +x "$BATS_TEST_TMPDIR/bin/sudo"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  STREAM="$BATS_TEST_TMPDIR/stream.jsonl"
  ev() { # <script-or-null> <caller> — one eslogger exec event carrying secrets in env and elsewhere
    jq -nc --arg s "$1" --arg c "$2" --arg sec "$SECRET" --arg h "$HOME" '{
      time: "2026-10-22T07:00:00.000Z", mach_time: 1, event_type: 9, seq_num: 1,
      process: {executable: {path: $c}, ppid: 1, audit_token: {pid: 7}, signing_id: $sec},
      event: {exec: {
        script: (if $s == "null" then null else {path: $s, stat: {st_size: 1}} end),
        target: {executable: {path: "/bin/bash"}, signing_id: $sec},
        cwd: {path: ($h + "/proj")},
        args: ["/bin/bash", $s, "--token", $sec, "more"],
        env: ["ANTHROPIC_API_KEY=" + $sec, "GH_TOKEN=" + $sec, "PATH=/usr/bin",
              "BATS_TEST_FILENAME=/r/tests/x.bats", "CLAUDE_PROJECT_DIR=/r",
              "MULTI=a\nb=" + $sec],
        env_count: 6}}}'
  }
  {
    ev "$HOME/bin/leaf.sh" /bin/bash
    ev "$HOME/bin/leaf.sh" /bin/bash
    ev "null" /bin/zsh                                     # a Mach-O exec: not a script
    ev "$HOME/.cache/kalloc-longterm-ab/leaf.sh" /bin/bash # the A/B harness: excluded
    printf '{"torn": "line with "script":{ in it\n'        # not JSON: skipped, never fatal
  } > "$STREAM"
  printf '#!/bin/bash\ncat %q\n' "$STREAM" > "$BATS_TEST_TMPDIR/eslogger"
  chmod +x "$BATS_TEST_TMPDIR/eslogger"
  export KALLOC_CENSUS_ESLOGGER="$BATS_TEST_TMPDIR/eslogger"
}

@test "no env value except the three allow-listed keys reaches disk" {
  run /bin/bash "$REPO/scripts/kalloc-exec-census.sh" 5 < /dev/null
  [ "$status" -eq 0 ]
  [[ "$output" == *"verdict=ok script_execs=2 "* ]] || false
  out="$(ls -d "$HOME/.cache/kalloc-exec-census/"*/)"
  # The secret appears in env, args[3], signing_id and a multi-line env value: none may be written.
  run grep -rlF "$SECRET" "$out"
  [ "$status" -eq 1 ]
  run grep -rlE 'ANTHROPIC_API_KEY|GH_TOKEN|MULTI|PATH=' "$out"
  [ "$status" -eq 1 ]
  [ "$(wc -l < "$out/exec.jsonl" | tr -d ' ')" -eq 2 ]
  run jq -c 'keys' "$out/exec.jsonl"
  [ "${lines[0]}" = '["args","caller","cwd","env","script","time"]' ]
  run jq -c '.env' "$out/exec.jsonl"
  [ "${lines[0]}" = '{"BATS_TEST_FILENAME":"/r/tests/x.bats","CLAUDE_PROJECT_DIR":"/r"}' ]
  run jq -c '.args' "$out/exec.jsonl"
  [ "${lines[0]}" = "[\"/bin/bash\",\"$HOME/bin/leaf.sh\",\"--token\"]" ]
}

@test "files are owner-only, the A/B harness is excluded, and the window is the real one" {
  run /bin/bash "$REPO/scripts/kalloc-exec-census.sh" 5 < /dev/null
  [ "$status" -eq 0 ]
  out="$(ls -d "$HOME/.cache/kalloc-exec-census/"*/)"
  for f in "$out" "$out"exec.jsonl "$out"summary.txt "$out"eslogger.err; do
    m="$(stat -f %Lp "$f")"
    [ "$m" = 700 ] || [ "$m" = 600 ] || { echo "$f is $m"; false; }
  done
  run grep -c kalloc-longterm-ab "$out/exec.jsonl"
  [ "$output" = 0 ]
  # The stub ends at once, so the window is ~0 s, not the requested 5: per_hour uses the real one.
  run head -1 "$out/summary.txt"
  # 0-1 s idle; at load ~450/core (2026-10-22) the stub's startup alone took longer, so any real
  # window under the requested 5 s proves the point.
  [[ "$output" =~ window_s=[0-4]\ requested_s=5 ]] || false
  run grep -F "$HOME/bin/leaf.sh" "$out/summary.txt"
  [[ "${lines[0]}" == *"      2  "* ]] || false
  grep -qF '/r/tests/x.bats' "$out/summary.txt"
}

@test "an empty stream is a no-events verdict, not a summary" {
  printf '#!/bin/bash\nexit 1\n' > "$BATS_TEST_TMPDIR/eslogger"
  run /bin/bash "$REPO/scripts/kalloc-exec-census.sh" 5 < /dev/null
  [ "$status" -eq 1 ]
  [[ "$output" == *"verdict=no-events rc=1 "* ]]
}

@test "a non-numeric window is refused before sudo runs" {
  run /bin/bash "$REPO/scripts/kalloc-exec-census.sh" 10m < /dev/null
  [ "$status" -eq 2 ]
  [ ! -d "$HOME/.cache/kalloc-exec-census" ]
}

# Plan KALLOC_TRIGGER_ELIMINATION W5: rank the sources, draft lint rows only for paths NEWLY above N.
# The stub ends at once, so the real window is 0-4 s even under load and a rate is count x 600 / w
# (w >= 1): N=1000 puts 20 execs above it (>= 3000) and 1 below it (<= 600) at any of those windows.
@test "ranks every script by rate and drafts lint rows only for paths newly above N" {
  {
    for _ in $(seq 20); do ev "$HOME/bin/hot.sh" /bin/zsh; done
    for _ in $(seq 15); do ev "$HOME/bin/known.sh" /bin/bash; done
    ev "$HOME/bin/cold.sh" /bin/bash
  } > "$STREAM"
  prev="$HOME/.cache/kalloc-exec-census/20000101T000000"
  mkdir -p "$prev"
  printf 'rank\tscript\texecs\tper_10min\tshare_pct\tclass\ttop_caller\n1\t%s\t9\t4000.0\t100.0\ttest\tbash\n' \
    "$HOME/bin/known.sh" > "$prev/ranking.tsv"
  before="$(cksum < "$prev/ranking.tsv")"
  export KALLOC_CENSUS_LINT_N=1000
  run /bin/bash "$REPO/scripts/kalloc-exec-census.sh" 5 < /dev/null
  [ "$status" -eq 0 ] || false
  [[ "$output" == *"verdict=ok script_execs=36 "*"new_above_n=1 "* ]] || false
  for out in "$HOME/.cache/kalloc-exec-census/"*/; do [ "$out" = "$prev/" ] || break; done
  run cut -f1-3,6,7 "$out/ranking.tsv"
  [ "${lines[1]}" = "1	$HOME/bin/hot.sh	20	test	zsh" ] || false
  [ "${lines[2]}" = "2	$HOME/bin/known.sh	15	test	bash" ] || false
  [ "${lines[3]}" = "3	$HOME/bin/cold.sh	1	test	bash" ] || false
  run grep -c '^DRAFT' "$out/lint-drafts.txt"
  [ "$output" = 1 ] || false
  run grep '^DRAFT' "$out/lint-drafts.txt"
  [[ "$output" == "DRAFT	$HOME/bin/hot.sh	"*"/10min	class=test	caller=zsh	fix: "* ]] || false
  grep -qF "NEW ABOVE 1000 PER 10 MIN: 1" "$out/summary.txt"
  # Drafts only: the previous census is untouched and nothing new sits beside the two run dirs.
  [ "$(cksum < "$prev/ranking.tsv")" = "$before" ] || false
  [ "$(find "$HOME/.cache/kalloc-exec-census" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')" = 2 ]
}

@test "with no previous census every path above N is drafted, and the header says so" {
  run /bin/bash "$REPO/scripts/kalloc-exec-census.sh" 5 < /dev/null
  [ "$status" -eq 0 ] || false
  out="$(ls -d "$HOME/.cache/kalloc-exec-census/"*/)"
  grep -q 'no previous census had (first census here)' "$out/lint-drafts.txt"
  run grep -c "^DRAFT	$HOME/bin/leaf.sh	" "$out/lint-drafts.txt"
  [ "$output" = 1 ]
}

@test "RED-proof: the old tool's filter writes the secret" {
  # kalloc-exec-census.sh.txt:27-37 — it dropped env but kept args and every other field.
  run /usr/bin/python3 -I -c '
import json, sys
for l in open(sys.argv[1]):
    try: j = json.loads(l)
    except ValueError: continue
    ex = (j.get("event") or {}).get("exec") or {}
    ex.pop("env", None); ex.pop("env_count", None)
    print(json.dumps(j))' "$STREAM"
  [[ "$output" == *"$SECRET"* ]] || false
}
