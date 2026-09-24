# Dossier 7

## Brief
```
How big is the bats test suite in /tmp/tokeff-gate/f2/tree/tests? Count the .bats files (all depths) and the total number of @test cases across them. Name the 3 files with the most @test cases. numbers: {"bats_files": N, "test_cases": N}.
```

## Returned headline
tests/ holds 748 .bats files, all at the top level, with 15,438 @test cases between them; cc-reaper.bats has the most (226), then ship-land.bats (177) and deploy-live.bats (168).

## Returned numbers
`{"bats_files": 748, "test_cases": 15438}`

## answer.md
# Bats suite size — /tmp/tokeff-gate/f2/tree/tests

- **.bats files (all depths): 748** — all sit directly in `tests/` (no subdirectories hold any; 0 are symlinks).
- **@test cases: 15,438** — lines matching `^@test ` across those 748 files.
- **Top 3 files by @test count:**
  1. `cc-reaper.bats` — 226
  2. `ship-land.bats` — 177
  3. `deploy-live.bats` — 168
  (next: `postland-verify.bats` 152, `cc-backlog.bats` 148)

## Method
`find tests -name '*.bats' -type f | wc -l` and `grep -cE '^@test[[:space:]]'` per file, summed.
A loose `grep -c '@test'` gives 15,680; the extra 242 are non-declarations (comments, `grep -c '^@test'`
strings, and `printf`/`echo` lines that generate fixture suites, e.g. in `test-hermeticity-lint.bats`
and `test-afunix-path-lint.bats`). No indented `@test` declarations exist, so the anchored count is the
declaration count. `bats --count` was not run (read-only brief).


## Tool calls (4) with the first 300 chars of each result
1. `Bash: {"command": "cd /tmp/tokeff-gate/f2/tree/tests && find . -name '*.bats' -type f | wc -l; find . -name '*.bats' -type l | wc -l; find . -name '*.bats' -type f -print0 | xargs -0 grep -cE '^[[:space:]]*@test[[:space:]]' | awk -F: '{s+=$NF} END{print s}'; find . -name '*.bats' -type f -print0 | xargs -`
   →      748
       0
15438
./cc-reaper.bats:226
./ship-land.bats:177
./deploy-live.bats:168
./postland-verify.bats:152
./cc-backlog.bats:148
15680
2. `Bash: {"command": "cd /tmp/tokeff-gate/f2/tree/tests && find . -name '*.bats' -type f -print0 | xargs -0 grep -nE '@test' | grep -vE ':[0-9]+:[[:space:]]*@test[[:space:]]' | head -8; echo; find . -name '*.bats' -type f -print0 | xargs -0 grep -nE '^[[:space:]]+@test' | wc -l; find . -name '*.bats' -type f`
   → ./stop-failure-marker.bats:937:  declared="$(grep -c '^@test' "$BATS_TEST_FILENAME")"
./test-afunix-path-lint.bats:43:  printf '#!/usr/bin/env bats\n%s\n@test "x" { true; }\n' "$2" > "$FIX/$1/zz-fixture.bats"
./test-afunix-path-lint.bats:129:  printf '#!/usr/bin/env bats\n# AF_UNIX %s( an absolute p
3. `Bash: {"command": "mkdir -p /tmp/tokeff-gate/f2/out/B04-r6 && cat > /tmp/tokeff-gate/f2/out/B04-r6/answer.md <<'EOF'\n# Bats suite size — /tmp/tokeff-gate/f2/tree/tests\n\n- **.bats files (all depths): 748** — all sit directly in `tests/` (no subdirectories hold any; 0 are symlinks).\n- **@test cases: 15,`
   → (Bash completed with no output)
4. `StructuredOutput: {"answer_path": "/tmp/tokeff-gate/f2/out/B04-r6/answer.md", "headline": "tests/ holds 748 .bats files, all at the top level, with 15,438 @test cases between them; cc-reaper.bats has the most (226), then ship-land.bats (177) and deploy-live.bats (168).", "numbers": {"bats_files": 748, "test_cases": 1`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
