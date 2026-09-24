# Dossier 4

## Brief
```
How big is the bats test suite in /tmp/tokeff-regate/f2/tree/tests? Count the .bats files (all depths) and the total number of @test cases across them. Name the 3 files with the most @test cases. numbers: {"bats_files": N, "test_cases": N}.
```

## Returned headline
The suite in /tmp/tokeff-regate/f2/tree/tests has 748 .bats files (all directly in tests/) and 15,403 real @test cases: grep finds 15,438 @test lines, and 35 of them are fixture text inside heredocs or strings. The largest files are cc-reaper.bats (226), ship-land.bats (177) and deploy-live.bats (168).

## Returned numbers
`{"bats_files": 748, "test_cases": 15403, "raw_at_test_lines_including_fixtures": 15438, "fixture_at_test_lines_excluded": 35, "cc-reaper.bats": 226, "ship-land.bats": 177, "deploy-live.bats": 168}`

## answer.md
# Size of the bats suite in /tmp/tokeff-regate/f2/tree/tests

**748 .bats files and 15,403 real @test cases.** The files with the most tests are cc-reaper.bats (226), ship-land.bats (177) and deploy-live.bats (168).

## Counts
| Metric | Value | How it was found |
|---|---|---|
| .bats files, any depth | **748** | measured: `find . -name '*.bats' -type f \| wc -l`. All 748 sit directly in tests/, none in subdirectories, and there are no symlinked .bats files. |
| Lines matching `^[[:space:]]*@test[[:space:]]` | 15,438 | measured: `grep -c` over all .bats files, then summed. None of these lines are indented; they all start at column 0. |
| Fixture @test lines inside heredocs or multi-line strings | 35 | measured and then checked by eye: see below |
| **Real @test cases** | **15,403** | 15,438 minus 35 |

The 35 fixture lines are test text that a real test writes out to a scratch .bats file. bats never runs them as tests of this suite:
- git-identity-lint.bats: 15 (`fixture ... <<'F'` heredocs)
- bats-shortfall-nonverdict.bats: 6 (`<<'INNER'` heredocs)
- bats-shellcheck-lint.bats: 5 (multi-line `mkb '...'` strings)
- qos-chokepoint.bats: 5 (`cat > slow.bats <<'EOF'`)
- lr-fire-resume-submit.bats: 2 (`<<'INNER'`)
- offbox-admission-lint.bats: 2 (`<<'EOF'`)

How they were found: I ran two awk passes, one that looks at the line before each `@test` and one that tracks nesting depth and heredocs. I then read each candidate in context with sed. Neither pass is a full shell parser, so 15,403 is a close static count, not a number from bats itself. I did not run `bats --count` because it would need scratch files and would run code at the top level of each file.

## Top 3 files by @test count
Measured with a per-file `grep -c`, sorted. None of these files contain fixture lines.
1. cc-reaper.bats: 226
2. ship-land.bats: 177
3. deploy-live.bats: 168

Next are postland-verify.bats (152) and cc-backlog.bats (148).


## Tool calls (17) with the first 300 chars of each result
1. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree/tests && find . -name '*.bats' -type f | wc -l; find . -name '*.bats' -type f -exec grep -cE '^[[:space:]]*@test[[:space:]]' {} + | awk -F: '{s+=$2} END{print s}'; find . -name '*.bats' -type f -exec grep -cE '^[[:space:]]*@test[[:space:]]' {} + | sort -t: `
   → Exit code 1
     748
15438
./cc-reaper.bats:226
./ship-land.bats:177
./deploy-live.bats:168
./postland-verify.bats:152
./cc-backlog.bats:148
       0
ls: /tmp/tokeff-regate/f2/out/B04-r5: No such file or directory
2. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree/tests && find . -name '*.bats' -type f -exec grep -h '@test' {} + | grep -vcE '^[[:space:]]*@test[[:space:]]'; find . -name '*.bats' -type f -exec grep -h '@test' {} + | grep -vE '^[[:space:]]*@test[[:space:]]' | head -5; find . -name '*.bats' -type f -exec`
   → 242
  declared="$(grep -c '^@test' "$BATS_TEST_FILENAME")"
  printf '#!/usr/bin/env bats\n%s\n@test "x" { true; }\n' "$2" > "$FIX/$1/zz-fixture.bats"
  printf '#!/usr/bin/env bats\n# AF_UNIX %s( an absolute path ) is the 104-byte defect — see e1d43f93da19\nsetup() { true; }\n@test "x" { true; }\n' "
3. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree/tests && grep -lE '<<-?[[:space:]]*.?[A-Z_]+' $(grep -lE '^@test' *.bats) | xargs awk 'FNR==1{h=0} /<<-?[[:space:]]*['\"'\"'\"]?[A-Z_]+/{match($0,/<<-?[[:space:]]*['\"'\"'\"]?[A-Z_]+/); t=substr($0,RSTART,RLENGTH); gsub(/[<\\-'\"'\"'\" ]/,\"\",t); h=1; next`
   → bats-kill-guard-lint.bats: @test "GREEN: a kill inside a REAL heredoc body is data — a stub script is not bats commands" {
bats-kill-guard-lint.bats: @test "GREEN: a kill inside a suite's own multi-line fixture string is described, not run" {
bats-kill-guard-lint.bats: @test "RED: a nested command s
4. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree/tests && for f in *.bats; do awk -v F=\"$f\" '\n{ if (h) { line=$0; if (strip) sub(/^\\t+/,\"\",line); if (line==term) {h=0; next}; if ($0 ~ /^@test[[:space:]]/) print F\": \"$0; next } }\n/<<-?[[:space:]]*[\"'\"'\"']?[A-Za-z_]+[\"'\"'\"']?/ && $0 !~ /<<</ `
   → bats-assert-liveness.bats: @test "a QUOTED-delimiter heredoc body is never analyzed either (<<'EOF' is the common form)" {
bats-assert-liveness.bats: @test "a <<-'EOF' (tab-stripped, quoted) body is skipped, and its indented terminator closes it" {
bats-assert-liveness.bats: @test "a <<EOF inside a 
5. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree/tests && grep -hE '^@test' *.bats | grep -vE '\\{[[:space:]]*$' | head; grep -hE '^@test' *.bats | grep -vcE '^@test \"[^\"]*\"[[:space:]]*\\{[[:space:]]*$'", "description": "Check shape of column-0 @test lines"}`
   → @test "a1" { true; }
@test "a3" { true; }
@test "a4" { true; }
@test "b1" { true; }
@test "b2" { true; }
24
6. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree/tests && grep -nE '^@test' *.bats | grep -vE ':@test \"[^\"]*\"[[:space:]]*\\{[[:space:]]*$'; ", "description": "List atypical @test lines with context"}`
   → bats-shortfall-nonverdict.bats:47:@test "a1" { true; }
bats-shortfall-nonverdict.bats:53:@test "a3" { true; }
bats-shortfall-nonverdict.bats:54:@test "a4" { true; }
bats-shortfall-nonverdict.bats:57:@test "b1" { true; }
bats-shortfall-nonverdict.bats:58:@test "b2" { true; }
cc-backlog-condition-grou
7. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree/tests && sed -n 38,62p bats-shortfall-nonverdict.bats", "description": "Inspect fixture tests in shortfall file"}`
   → # ── the generator ────────────────────────────────────────────────────────────────────────────────
# Writes $T/tap. Six planned tests across two files; test 2 deletes $BATS_RUN_TMPDIR, which is what
# a tmp reaper does to a long run. THE GUARD IS NOT DECORATION: bats exports BATS_RUN_TMPDIR, and an
8. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree/tests && for f in *.bats; do awk -v F=\"$f\" '\nh { line=$0; if (strip) sub(/^\\t+/,\"\",line); if (line==term) {h=0; next}; if ($0 ~ /^@test[[:space:]]/) print F\":\"FNR\": \"$0; next }\n$0 !~ /^[[:space:]]*(@test|#)/ && $0 !~ /<<</ && match($0,/<<-?[[:spa`
   → bats-shortfall-nonverdict.bats:47: @test "a1" { true; }
bats-shortfall-nonverdict.bats:48: @test "a2 reclaims the run dir" {
bats-shortfall-nonverdict.bats:53: @test "a3" { true; }
bats-shortfall-nonverdict.bats:54: @test "a4" { true; }
bats-shortfall-nonverdict.bats:57: @test "b1" { true; }
bats-sh
9. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree/tests && sed -n 55,92p git-identity-lint.bats; echo ----; sed -n 498,515p lr-fire-resume-submit.bats; echo ----; sed -n 28,46p offbox-admission-lint.bats; echo ----; sed -n 50,62p qos-chokepoint.bats; sed -n 1000,1008p qos-chokepoint.bats", "description": "`
   →   printf '%s' "$output" | grep -q '36/36' || { echo "selftest count changed — update this assertion deliberately: $output"; false; }
}

# ── THE POSITIVE CONTROL. If the lint were a no-op these two tests are the ones that fail. ────────

@test "2: POSITIVE CONTROL — a leaky fixture makes the lint ex
10. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree/tests && for f in completion-assert.bats pkill-scope.bats qos-rewrite.bats session-busy.bats smart-bash-allowlist-compound.bats validate-bash-ff-gate.bats worker-claim-gate-coverage.bats git-identity-write-guard.bats; do awk -v F=\"$f\" '\nh { line=$0; if (`
   → completion-assert.bats: opener@737: `cat <<EOF > /tmp/report.txt`')" "$w" "a2-d5-hd" term=[EOF]
pkill-scope.bats: opener@91:     echo 'cat <<TABLE' term=[TABLE]
qos-rewrite.bats: opener@135:   run run_hook "cat > /tmp/x.sh <<XEOF term=[XEOF]
session-busy.bats: opener@50:   { echo '#!/bin/bash'; echo
11. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree/tests && awk 'FNR==1{prev=\"\"} /^@test[[:space:]]/ { if (prev !~ /^[[:space:]]*$/ && prev !~ /^}[[:space:]]*$/ && prev !~ /^[[:space:]]*#/) print FILENAME\":\"FNR\": prev=[\"prev\"]\" } {prev=$0}' *.bats", "description": "Find @test lines with unusual prec`
   → bats-shellcheck-lint.bats:221: prev=[  mkb abort '# shellcheck + prose that opens with the tool name]
bats-shellcheck-lint.bats:225: prev=[  mkb plain '# ShellCheck + the same prose, reworded]
bats-shellcheck-lint.bats:239: prev=[  mkb abort '# shellcheck + prose that opens with the tool name]
bats-
12. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree/tests && sed -n 218,242p bats-shellcheck-lint.bats; echo ...; sed -n 280,287p bats-shellcheck-lint.bats; echo ...; sed -n 366,373p bats-shellcheck-lint.bats; echo; sed -n 480,497p lr-fire-resume-submit.bats", "description": "Inspect multi-line string fixtur`
   → @test "an UNANALYZABLE file hides a REAL defect — the positive control for the abort" {
  need_sc
  mkb abort '# shellcheck + prose that opens with the tool name
@test "x" {
  foo= bar
}'
  mkb plain '# ShellCheck + the same prose, reworded
@test "x" {
  foo= bar
}'
  # Identical bodies. The only di
13. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree/tests && cat > /dev/null; awk '\nFNR==1 { depth=0; h=0 }\nh { l=$0; if (strip) sub(/^\\t+/,\"\",l); if (l==term) h=0; else if ($0 ~ /^@test[[:space:]]/) print \"EXCL-HD \" FILENAME\":\"FNR; next }\n/^@test[[:space:]]/ { if (depth==0) { real[FILENAME]++; tot`
   → EXCL-NEST bats-shellcheck-lint.bats:221
EXCL-NEST bats-shellcheck-lint.bats:225
EXCL-NEST bats-shellcheck-lint.bats:239
EXCL-NEST bats-shellcheck-lint.bats:283
EXCL-NEST bats-shellcheck-lint.bats:369
EXCL-HD bats-shortfall-nonverdict.bats:47
EXCL-HD bats-shortfall-nonverdict.bats:48
EXCL-HD bats-sho
14. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree/tests && sed -n 1585,1600p postland-verify.bats; echo ....; sed -n 1052,1066p waiting-recycle.bats", "description": "Inspect nested exclusions"}`
   →   # ~160KB a run against ~43 lands/day: unbounded, this is the one piece of state that grows with
  # trunk VELOCITY rather than with tree count.
  b="$(stub_bats bound "printf '1..3\nok 1 a\n'; exit 137")"
  CC_POSTLAND_TAP_KEEP=1 CC_POSTLAND_BATS="$b" run bash "$SUT" --run-if-needed
  [ "$(taps_n)
15. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree/tests && awk '\nfunction inquote(s,   i,c,sq,dq){ sq=0; dq=0; for(i=1;i<=length(s);i++){c=substr(s,i,1); if(c==\"'\"'\"'\" && !dq) sq=!sq; else if(c==\"\\\"\" && !sq) dq=!dq}; return sq||dq }\nFNR==1 { depth=0; h=0; fn=0 }\nh { l=$0; if (strip) sub(/^\\t+/,`
   → EXCL-NEST bats-shellcheck-lint.bats:221
EXCL-NEST bats-shellcheck-lint.bats:239
EXCL-NEST bats-shellcheck-lint.bats:283
EXCL-NEST bats-shellcheck-lint.bats:369
EXCL-HD bats-shortfall-nonverdict.bats:47
EXCL-HD bats-shortfall-nonverdict.bats:48
EXCL-HD bats-shortfall-nonverdict.bats:53
EXCL-HD bats-s
16. `Bash: {"command": "mkdir -p /tmp/tokeff-regate/f2/out/B04-r5 && cat > /tmp/tokeff-regate/f2/out/B04-r5/answer.md <<'EOF'\n# Size of the bats suite in /tmp/tokeff-regate/f2/tree/tests\n\n**748 .bats files and 15,403 real @test cases.** The files with the most tests are cc-reaper.bats (226), ship-land.bats `
   → (Bash completed with no output)
17. `StructuredOutput: {"answer_path": "/tmp/tokeff-regate/f2/out/B04-r5/answer.md", "headline": "The suite in /tmp/tokeff-regate/f2/tree/tests has 748 .bats files (all directly in tests/) and 15,403 real @test cases: grep finds 15,438 @test lines, and 35 of them are fixture text inside heredocs or strings. The largest fi`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
