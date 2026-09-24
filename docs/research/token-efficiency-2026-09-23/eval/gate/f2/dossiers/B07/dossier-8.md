# Dossier 8

## Brief
```
Measure the hook scripts: for the files directly inside /tmp/tokeff-gate/f2/tree/hooks whose names end in .sh (not subdirectories), report how many there are, their total line count, and the 3 largest by line count with their line counts. numbers: {"sh_files": N, "total_lines": N}.
```

## Returned headline
hooks/ holds 89 top-level .sh files totalling 28,486 lines; the largest are validate-bash.sh (2,031), lead-crash-watchdog.sh (1,831) and operator-readout.sh (1,664).

## Returned numbers
`{"sh_files": 89, "total_lines": 28486}`

## answer.md
# Hook script measurement — /tmp/tokeff-gate/f2/tree/hooks

Scope: regular files directly inside `hooks/` (maxdepth 1) whose names end in `.sh`; no symlinks present.

- **.sh files:** 89
- **Total lines:** 28,486 (`wc -l`; every file ends in a newline, so no undercount)

Top 3 by line count:

| Rank | File | Lines |
|---|---|---|
| 1 | validate-bash.sh | 2,031 |
| 2 | lead-crash-watchdog.sh | 1,831 |
| 3 | operator-readout.sh | 1,664 |

Command: `find . -maxdepth 1 -name '*.sh' -type f -print0 | xargs -0 wc -l | sort -n`


## Tool calls (4) with the first 300 chars of each result
1. `Bash: {"command": "cd /tmp/tokeff-gate/f2/tree/hooks && find . -maxdepth 1 -name '*.sh' \\( -type f -o -type l \\) | wc -l; find . -maxdepth 1 -name '*.sh' -type l | wc -l; find . -maxdepth 1 -name '*.sh' -type f -print0 | xargs -0 wc -l | sort -n | tail -4; ls -d /tmp/tokeff-gate/f2/out/B07-r1 2>&1", "de`
   →       89
       0
    1664 ./operator-readout.sh
    1831 ./lead-crash-watchdog.sh
    2031 ./validate-bash.sh
   28486 total
/tmp/tokeff-gate/f2/out/B07-r1
2. `Bash: {"command": "cd /tmp/tokeff-gate/f2/tree/hooks && n=0; for f in *.sh; do [ -f \"$f\" ] && [ -s \"$f\" ] && [ \"$(tail -c1 \"$f\" | xxd -p)\" != \"0a\" ] && n=$((n+1)); done; echo \"no-trailing-newline: $n\"", "description": "Check for files lacking trailing newline"}`
   → no-trailing-newline: 0
3. `Write: {"file_path": "/tmp/tokeff-gate/f2/out/B07-r1/answer.md", "content": "# Hook script measurement — /tmp/tokeff-gate/f2/tree/hooks\n\nScope: regular files directly inside `hooks/` (maxdepth 1) whose names end in `.sh`; no symlinks present.\n\n- **.sh files:** 89\n- **Total lines:** 28,486 (`wc -l`; ev`
   → File created successfully at: /tmp/tokeff-gate/f2/out/B07-r1/answer.md (file state is current in your context — no need to Read it back)
4. `StructuredOutput: {"answer_path": "/tmp/tokeff-gate/f2/out/B07-r1/answer.md", "headline": "hooks/ holds 89 top-level .sh files totalling 28,486 lines; the largest are validate-bash.sh (2,031), lead-crash-watchdog.sh (1,831) and operator-readout.sh (1,664).", "numbers": {"sh_files": 89, "total_lines": 28486}}`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
