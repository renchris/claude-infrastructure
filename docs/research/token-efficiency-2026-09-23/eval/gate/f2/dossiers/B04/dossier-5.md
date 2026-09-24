# Dossier 5

## Brief
```
How big is the bats test suite in /tmp/tokeff-gate/f2/tree/tests? Count the .bats files (all depths) and the total number of @test cases across them. Name the 3 files with the most @test cases. numbers: {"bats_files": N, "test_cases": N}.
```

## Returned headline
The tests directory holds 748 .bats files with 15438 @test cases in total (counted with find and grep). The three largest are cc-reaper.bats (226), ship-land.bats (177) and deploy-live.bats (168).

## Returned numbers
`{"bats_files": 748, "test_cases": 15438}`

## answer.md
# B04: bats suite size in /tmp/tokeff-gate/f2/tree/tests

- .bats files (all depths): **748**. Measured with `find . -name '*.bats' | wc -l`. All 748 sit directly in tests/, with none in subdirectories. `find -L` gives the same count and there are no symlinks.
- @test cases in total: **15438**. Measured by counting lines that match `^[[:space:]]*@test[[:space:]]` across all .bats files. Every match starts at column 0.
  - A plain `grep '@test'` finds 15680 lines. The 242 extra lines are not test cases. They are `@test` inside strings, printf/echo fixture generators and comments, for example in test-hermeticity-lint.bats, test-afunix-path-lint.bats and stop-failure-marker.bats.

## Top 3 files by @test count
1. cc-reaper.bats: 226
2. ship-land.bats: 177
3. deploy-live.bats: 168

The next two are postland-verify.bats (152) and cc-backlog.bats (148), so there is no tie for third place.


## Tool calls (4) with the first 300 chars of each result
1. `Bash: {"command": "cd /tmp/tokeff-gate/f2/tree/tests && find . -name '*.bats' | wc -l; find . -name '*.bats' -print0 | xargs -0 grep -cE '^[[:space:]]*@test[[:space:]]' | sort -t: -k2 -nr | head -5; find . -name '*.bats' -print0 | xargs -0 grep -hE '^[[:space:]]*@test[[:space:]]' | wc -l; find . -name '*.`
   →      748
./cc-reaper.bats:226
./ship-land.bats:177
./deploy-live.bats:168
./postland-verify.bats:152
./cc-backlog.bats:148
   15438
   15680
2. `Bash: {"command": "cd /tmp/tokeff-gate/f2/tree/tests && find . -name '*.bats' -print0 | xargs -0 grep -nE '^[[:space:]]+@test' | head; echo ---; find . -name '*.bats' -print0 | xargs -0 grep -n '@test' | grep -vE ':[0-9]+:[[:space:]]*@test[[:space:]]' | head -8; echo; find . -name '*.bats' -print0 | xargs`
   → ---
./stop-failure-marker.bats:937:  declared="$(grep -c '^@test' "$BATS_TEST_FILENAME")"
./test-afunix-path-lint.bats:43:  printf '#!/usr/bin/env bats\n%s\n@test "x" { true; }\n' "$2" > "$FIX/$1/zz-fixture.bats"
./test-afunix-path-lint.bats:129:  printf '#!/usr/bin/env bats\n# AF_UNIX %s( an absolu
3. `Bash: {"command": "cat > /tmp/tokeff-gate/f2/out/B04-r1/answer.md <<'EOF'\n# B04: bats suite size in /tmp/tokeff-gate/f2/tree/tests\n\n- .bats files (all depths): **748**. Measured with `find . -name '*.bats' | wc -l`. All 748 sit directly in tests/, with none in subdirectories. `find -L` gives the same c`
   → (Bash completed with no output)
4. `StructuredOutput: {"answer_path": "/tmp/tokeff-gate/f2/out/B04-r1/answer.md", "headline": "The tests directory holds 748 .bats files with 15438 @test cases in total (counted with find and grep). The three largest are cc-reaper.bats (226), ship-land.bats (177) and deploy-live.bats (168).", "numbers": {"bats_files": 74`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
