# Dossier 2

## Brief
```
Measure the hook scripts: for the files directly inside /tmp/tokeff-gate/f2/tree/hooks whose names end in .sh (not subdirectories), report how many there are, their total line count, and the 3 largest by line count with their line counts. numbers: {"sh_files": N, "total_lines": N}.
```

## Returned headline
hooks/ holds 89 .sh files with 28,486 lines in total; the largest are validate-bash.sh (2,031 lines), lead-crash-watchdog.sh (1,831) and operator-readout.sh (1,664), all measured with find -maxdepth 1 and wc -l.

## Returned numbers
`{"sh_files": 89, "total_lines": 28486}`

## answer.md
There are 89 `.sh` files directly inside /tmp/tokeff-gate/f2/tree/hooks, with 28,486 lines in total. The three largest are:

1. validate-bash.sh: 2,031 lines
2. lead-crash-watchdog.sh: 1,831 lines
3. operator-readout.sh: 1,664 lines

These counts come from running `find . -maxdepth 1 -type f -name '*.sh'` and `wc -l`. Subdirectories are excluded. The directory contains no `.sh` symlinks.


## Tool calls (3) with the first 300 chars of each result
1. `Bash: {"command": "cd /tmp/tokeff-gate/f2/tree/hooks && find . -maxdepth 1 -type f -name '*.sh' | wc -l; find . -maxdepth 1 -type f -name '*.sh' -print0 | xargs -0 wc -l | sort -n | tail -4; ls -la /tmp/tokeff-gate/f2/out/B07-r12/ 2>&1; find . -maxdepth 1 -type l -name '*.sh'", "description": "Count hook `
   →       89
    1664 ./operator-readout.sh
    1831 ./lead-crash-watchdog.sh
    2031 ./validate-bash.sh
   28486 total
total 0
drwxr-xr-x@   2 chrisren  wheel    64 Sep 24 11:31 .
drwxr-xr-x@ 102 chrisren  wheel  3264 Sep 24 11:31 ..
2. `Bash: {"command": "cat > /tmp/tokeff-gate/f2/out/B07-r12/answer.md <<'EOF'\nThere are 89 `.sh` files directly inside /tmp/tokeff-gate/f2/tree/hooks, with 28,486 lines in total. The three largest are:\n\n1. validate-bash.sh: 2,031 lines\n2. lead-crash-watchdog.sh: 1,831 lines\n3. operator-readout.sh: 1,664`
   → There are 89 `.sh` files directly inside /tmp/tokeff-gate/f2/tree/hooks, with 28,486 lines in total. The three largest are:

1. validate-bash.sh: 2,031 lines
2. lead-crash-watchdog.sh: 1,831 lines
3. operator-readout.sh: 1,664 lines

These counts come from running `find . -maxdepth 1 -type f -name '
3. `StructuredOutput: {"answer_path": "/tmp/tokeff-gate/f2/out/B07-r12/answer.md", "headline": "hooks/ holds 89 .sh files with 28,486 lines in total; the largest are validate-bash.sh (2,031 lines), lead-crash-watchdog.sh (1,831) and operator-readout.sh (1,664), all measured with find -maxdepth 1 and wc -l.", "numbers": {`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
