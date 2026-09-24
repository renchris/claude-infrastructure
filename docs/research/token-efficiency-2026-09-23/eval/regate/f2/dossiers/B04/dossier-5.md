# Dossier 5

## Brief
```
How big is the bats test suite in /tmp/tokeff-regate/f2/tree/tests? Count the .bats files (all depths) and the total number of @test cases across them. Name the 3 files with the most @test cases. numbers: {"bats_files": N, "test_cases": N}.
```

## Returned headline
tests/ holds 748 .bats files, all at the top level, with 15,403 real @test cases (a plain line grep finds 15,438, but 35 of those lines are fixture suites written out through heredocs or quoted strings), and the largest files are cc-reaper.bats (226), ship-land.bats (177) and deploy-live.bats (168).

## Returned numbers
`{"bats_files": 748, "test_cases": 15403, "test_cases_naive_line_grep": 15438, "top1_cc-reaper.bats": 226, "top2_ship-land.bats": 177, "top3_deploy-live.bats": 168}`

## answer.md
# Size of the bats suite in /tmp/tokeff-regate/f2/tree/tests

## Answer
- **.bats files: 748**, all at the top level of tests/ (no subdirectories hold any), none of them symlinks.
  Measured with `find . -name '*.bats' -type f | wc -l`. Every path is at depth 1 (checked with awk on the path separators).
- **@test cases: 15,403**.
  Measured with a Python shell lexer, run from stdin without writing a file. It counts lines matching `^[ \t]*@test[ \t]`
  only when the line is not inside a heredoc body or a multi-line quoted string. Quote tracking handles `$(...)` nesting.
  The lexer finished every one of the 748 files with no open quote or heredoc.
- **Top 3 files by @test count:**
  1. `cc-reaper.bats`: 226
  2. `ship-land.bats`: 177
  3. `deploy-live.bats`: 168

  (4th and 5th: `postland-verify.bats` 152, `cc-backlog.bats` 148.)

## Why 15,403 and not the naive grep figure
A plain line grep, `grep -cE '^[[:space:]]*@test[[:space:]]'` summed over all files, gives **15,438**.
A bare `grep -o '@test'` gives 15,687, because it also matches mentions in comments and strings.
35 of the 15,438 grep-matched lines are fixture text, not tests. They are inner bats suites that tests write out
through heredocs or single-quoted strings, so bats never registers them as tests of this suite. They sit in 6 files:

| file | grep lines | real tests | fixture lines |
|---|---|---|---|
| git-identity-lint.bats | 38 | 23 | 15 |
| bats-shortfall-nonverdict.bats | 20 | 14 | 6 |
| bats-shellcheck-lint.bats | 36 | 31 | 5 |
| qos-chokepoint.bats | 52 | 47 | 5 |
| lr-fire-resume-submit.bats | 35 | 33 | 2 |
| offbox-admission-lint.bats | 14 | 12 | 2 |

I spot-checked each of these files by hand with grep and sed. Examples: `fixture leaky <<'F'` followed by `@test "seeds a repo" {`
in git-identity-lint.bats; `cat > "$T/t/a.bats" <<'INNER'` in bats-shortfall-nonverdict.bats; and `mkb abort '...@test "x" {...}'`
in bats-shellcheck-lint.bats.

The top-3 ranking is the same under either method, since none of those three files holds fixture @test lines.

Cross-check: `bats --count` on cc-reaper, ship-land, deploy-live and bats-shortfall-nonverdict reported 585 (measured).
That equals 226 + 177 + 168 + 14, so bats itself excludes the heredoc fixtures, as the lexer does.
Caveat: `bats --count` creates and removes its own run temp dir under $TMPDIR, so I ran it only this one time
and did not use it for the full suite.


## Tool calls (19) with the first 300 chars of each result
1. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree/tests && find . -name '*.bats' -type f | wc -l; find . -name '*.bats' -type f -exec grep -cE '^[[:space:]]*@test[[:space:]]' {} + | awk -F: '{s+=$2} END{print s}'; find . -name '*.bats' -type f -exec grep -cE '^[[:space:]]*@test[[:space:]]' {} + | sort -t: `
   →      748
15438
./cc-reaper.bats:226
./ship-land.bats:177
./deploy-live.bats:168
./postland-verify.bats:152
./cc-backlog.bats:148
       0
   15687
drwxr-xr-x@ 2 chrisren  wheel  64 Sep 24 13:39 /tmp/tokeff-regate/f2/out/B04-r1
2. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree/tests && grep -rnE '@test' --include='*.bats' . | grep -vE ':[0-9]+:[[:space:]]*@test[[:space:]]' | head -8; echo ---; grep -rnE '^[[:space:]]+@test' --include='*.bats' . | wc -l; find . -name '*.bats' -type f | awk -F/ '{print NF-1}' | sort | uniq -c", "de`
   → stop-failure-marker.bats:937:  declared="$(grep -c '^@test' "$BATS_TEST_FILENAME")"
test-afunix-path-lint.bats:43:  printf '#!/usr/bin/env bats\n%s\n@test "x" { true; }\n' "$2" > "$FIX/$1/zz-fixture.bats"
test-afunix-path-lint.bats:129:  printf '#!/usr/bin/env bats\n# AF_UNIX %s( an absolute path ) 
3. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree/tests && grep -rnE '^@test' --include='*.bats' . | grep -vE '\\{[[:space:]]*$' | head; grep -rnE '^@test' --include='*.bats' . | grep -vE '\\{[[:space:]]*$' | wc -l; grep -rlE \"<<-?[[:space:]]*'?\\\"?[A-Z_]+\" --include='*.bats' . | xargs grep -nE -A0 '^@t`
   → bats-shortfall-nonverdict.bats:47:@test "a1" { true; }
bats-shortfall-nonverdict.bats:53:@test "a3" { true; }
bats-shortfall-nonverdict.bats:54:@test "a4" { true; }
bats-shortfall-nonverdict.bats:57:@test "b1" { true; }
bats-shortfall-nonverdict.bats:58:@test "b2" { true; }
       5
bats-shortfall-n
4. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree/tests && sed -n 38,62p bats-shortfall-nonverdict.bats; which bats && bats --count bats-shortfall-nonverdict.bats cc-reaper.bats ship-land.bats deploy-live.bats", "description": "View fixture context and bats count"}`
   → # ── the generator ────────────────────────────────────────────────────────────────────────────────
# Writes $T/tap. Six planned tests across two files; test 2 deletes $BATS_RUN_TMPDIR, which is what
# a tmp reaper does to a long run. THE GUARD IS NOT DECORATION: bats exports BATS_RUN_TMPDIR, and an
5. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree/tests && for f in $(find . -name '*.bats' -type f); do awk -v F=\"$f\" '\nBEGIN{n=0;term=\"\"}\n{ if(term!=\"\"){ l=$0; sub(/^[\\t]+/,\"\",l); if(l==term) term=\"\"; next }\n  if($0 ~ /^[ \\t]*@test[ \\t]/) n++\n  if(match($0,/<<-?[ \\t]*[\"\\x27]?[A-Za-z_]`
   → 226 ./cc-reaper.bats
226 ./cc-reaper.bats
168 ./deploy-live.bats
168 ./deploy-live.bats
152 ./postland-verify.bats
TOTAL 29576 1496
6. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree/tests && for f in $(find . -name '*.bats' -type f); do awk -v F=\"$f\" '\nBEGIN{n=0;term=\"\"}\n{ if(term!=\"\"){ l=$0; sub(/^[\\t]+/,\"\",l); if(l==term) term=\"\"; next }\n  if($0 ~ /^[ \\t]*@test[ \\t]/) n++\n  if(match($0,/<<-?[ \\t]*[\"\\x27]?[A-Za-z_]`
   → 226 ./cc-reaper.bats
168 ./deploy-live.bats
152 ./postland-verify.bats
143 ./compressor-sentinel.bats
133 ./wrap-ledger.bats
TOTAL 14788 748
177
7. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree/tests && grep -nE '<<' ship-land.bats | head -20", "description": "Find heredoc markers in ship-land.bats"}`
   → 625:  cat > hooks/lib/session-index-helpers.sh <<'EOF'
843:  cat > "$ORIGIN/hooks/post-update" <<EOF
895:  cat > "$ORIGIN/hooks/post-update" <<EOF
955:  cat > "$SHIMDIR/bats" <<EOF
1022:    printf 'cat <<SELEOF\n%s\nSELEOF\n' "$2"
1024:    printf 'cat <<SELEOF\n%s\nSELEOF\n' "$1"
1530:  cat > "$SHIM
8. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree/tests && for f in $(find . -name '*.bats' -type f); do awk -v F=\"$f\" '\nBEGIN{n=0;term=\"\"}\n{ if(term!=\"\"){ l=$0; sub(/^[\\t]+/,\"\",l); if(l==term) term=\"\"; next }\n  if($0 ~ /^[ \\t]*@test[ \\t]/) n++\n  x=$0\n  if(x ~ /^[ \\t]*#/) next\n  gsub(/<`
   → 226 ./cc-reaper.bats 
177 ./ship-land.bats 
168 ./deploy-live.bats 
152 ./postland-verify.bats 
148 ./cc-backlog.bats 
TOTAL 15204 748
8
9. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree/tests && grep UNTERM /tmp/tokeff-regate/f2/out/B04-r1/counts.txt; while read n f rest; do g=$(grep -cE '^[[:space:]]*@test[[:space:]]' \"$f\"); [ \"$g\" != \"$n\" ] && echo \"$f grep=$g heredoc-aware=$n $rest\"; done < /tmp/tokeff-regate/f2/out/B04-r1/count`
   → Exit code 1
16 ./lr-fire-resume-submit.bats UNTERMINATED:LRSCREENSH1d
8 ./qos-rewrite.bats UNTERMINATED:XEOF
29 ./git-identity-write-guard.bats UNTERMINATED:EOF
6 ./lr-lib.bats UNTERMINATED:PY
49 ./completion-assert.bats UNTERMINATED:EOF
9 ./smart-bash-allowlist-compound.bats UNTERMINATED:EOF
27 ./v
10. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree/tests && for f in git-identity-lint offbox-admission-lint qos-chokepoint; do echo \"== $f\"; grep -nE '^[[:space:]]*@test|<<' $f.bats | head -60; done", "description": "Inspect heredoc and @test lines"}`
   → == git-identity-lint
41:@test "1: the lint's own --selftest passes (36/36, both directions)" {
60:@test "2: POSITIVE CONTROL — a leaky fixture makes the lint exit non-zero AND names the file" {
61:  root="$(fixture leaky <<'F'
62:@test "seeds a repo" {
73:@test "3: POSITIVE CONTROL's pair — the same
11. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree/tests && for p in \"lr-fire-resume-submit LRSCREENSH1d\" \"qos-rewrite XEOF\" \"lr-lib PY\" \"completion-assert EOF\" \"smart-bash-allowlist-compound EOF\" \"worker-claim-gate-coverage PY\" \"validate-bash-ff-gate EOF\" \"git-identity-write-guard EOF\"; do `
   → == lr-fire-resume-submit LRSCREENSH1d
ugrep: warning: lr-fire-resume-submit LRSCREENSH1d.bats: No such file or directory
== qos-rewrite XEOF
ugrep: warning: qos-rewrite XEOF.bats: No such file or directory
== lr-lib PY
ugrep: warning: lr-lib PY.bats: No such file or directory
== completion-assert EO
12. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree/tests && bash -c 'for p in \"lr-fire-resume-submit LRSCREENSH1d\" \"qos-rewrite XEOF\" \"lr-lib PY\" \"completion-assert EOF\" \"smart-bash-allowlist-compound EOF\" \"worker-claim-gate-coverage PY\" \"validate-bash-ff-gate EOF\" \"git-identity-write-guard E`
   → == lr-fire-resume-submit
== qos-rewrite
135:  run run_hook "cat > /tmp/x.sh <<XEOF
137:XEOF"
== lr-lib
69:  a="$(sed -n '/^lr_engaged_after() {/,/^}/p' "$LIB" | sed -n "/<<'PY'/,/^PY$/p")"
70:  b="$(sed -n '/^resume_engaged() {/,/^}/p' "$HF" | sed -n "/<<'PY'/,/^PY$/p")"
== completion-assert
727:  #
13. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree/tests && python3 - <<'PYEOF'\nimport os,re,glob\nfiles=sorted(os.path.relpath(os.path.join(d,f)) for d,_,fs in os.walk('.') for f in fs if f.endswith('.bats'))\ntestre=re.compile(r'^[ \\t]*@test[ \\t]')\nhdre=re.compile(r'<<(-?)[ \\t]*(?:\\'([^\\']+)\\'|\"(`
   → files 748 total 15132 grep_total 15438
(226, 'cc-reaper.bats', 226, '')
(177, 'ship-land.bats', 177, '')
(168, 'deploy-live.bats', 168, '')
(152, 'postland-verify.bats', 152, '')
(148, 'cc-backlog.bats', 148, '')
DIFF (112, 'operator-readout.bats', 114, '')
DIFF (94, 'cc-classify.bats', 102, '')
DIF
14. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree/tests && python3 - <<'PYEOF'\nimport re\nhdre=re.compile(r'<<(-?)[ \\t]*(?:\\'([^\\']+)\\'|\"([^\"]+)\"|\\\\?([A-Za-z_][A-Za-z_0-9]*))')\nfor f in ['cloud-refusal-route.bats','dispatch-assert.bats','terminal-bench.bats','custody-deathwatch.bats','handoff-fi`
   → cloud-refusal-route.bats open quote ' from line 781
      grep -q '_cloudret_deployed" != 1' "$sweep"
dispatch-assert.bats open quote ' from line 331
      [ "$(printf '%s' "$output" | grep -c -- '--source \\"sid-')" -eq 0 ]
terminal-bench.bats open quote ' from line 495
      grep -q '"layout":"bro
15. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree/tests && python3 - <<'PYEOF'\nimport os,re\nfiles=sorted(os.path.relpath(os.path.join(d,f)) for d,_,fs in os.walk('.') for f in fs if f.endswith('.bats'))\ntestre=re.compile(r'^[ \\t]*@test[ \\t]')\nhdre=re.compile(r'<<(-?)[ \\t]*(?:\\'([^\\']+)\\'|\"([^\"]`
   → files 748 lexer_total 15403 grep_total 15438
226 226 cc-reaper.bats
177 177 ship-land.bats
168 168 deploy-live.bats
152 152 postland-verify.bats
148 148 cc-backlog.bats
DIFF bats-shellcheck-lint.bats lexer 31 grep 36 
DIFF bats-shortfall-nonverdict.bats lexer 14 grep 20 
DIFF git-identity-lint.bats 
16. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree/tests && grep -nE '^[[:space:]]*@test|<<' bats-shellcheck-lint.bats | head -50; echo ====; grep -nE '<<|^[[:space:]]*@test' lr-fire-resume-submit.bats | grep -B2 -A2 -E '<<' | head -30", "description": "Verify remaining differing files"}`
   → Exit code 1
37:@test "--selftest passes: the lint discriminates in both directions" {
45:@test "a finding on a line in the own-set BLOCKS" {
56:@test "the SAME finding on a line NOT in the own-set is advisory, never blocking" {
68:@test "a SET-BUT-EMPTY own-set means 'I wrote no line' — nothing bloc
17. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree/tests && sed -n 216,228p bats-shellcheck-lint.bats; sed -n 280,286p bats-shellcheck-lint.bats; echo ----; grep -nE '<<' lr-fire-resume-submit.bats | head; ", "description": "Check fixture context in two files"}`
   → # cannot protect it: a defect added at line 500 would be invisible. It is a NON-VERDICT wearing a
# clean file's clothes.
@test "an UNANALYZABLE file hides a REAL defect — the positive control for the abort" {
  need_sc
  mkb abort '# shellcheck + prose that opens with the tool name
@test "x" {
  fo
18. `Bash: {"command": "rm /tmp/tokeff-regate/f2/out/B04-r1/counts.txt; cat > /tmp/tokeff-regate/f2/out/B04-r1/answer.md <<'EOF'\n# Size of the bats suite in /tmp/tokeff-regate/f2/tree/tests\n\n## Answer\n- **.bats files: 748**, all at the top level of tests/ (no subdirectories hold any), none of them symlinks`
   → (Bash completed with no output)
19. `StructuredOutput: {"answer_path": "/tmp/tokeff-regate/f2/out/B04-r1/answer.md", "headline": "tests/ holds 748 .bats files, all at the top level, with 15,403 real @test cases (a plain line grep finds 15,438, but 35 of those lines are fixture suites written out through heredocs or quoted strings), and the largest files`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
