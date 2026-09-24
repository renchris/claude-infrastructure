# Dossier 2

## Brief
```
Measure the hook scripts: for the files directly inside /tmp/tokeff-gate/f2/tree/hooks whose names end in .sh (not subdirectories), report how many there are, their total line count, and the 3 largest by line count with their line counts. numbers: {"sh_files": N, "total_lines": N}.
```

## Returned headline
hooks/ holds 89 top-level .sh files totalling 28,486 lines; the largest are validate-bash.sh (2,031), lead-crash-watchdog.sh (1,831) and operator-readout.sh (1,664).

## Returned numbers
`{"sh_files": 89, "total_lines": 28486}`

## answer.md
# Hook scripts in /tmp/tokeff-gate/f2/tree/hooks (top level, *.sh only)

- Files: **89** `.sh` files directly inside `hooks/` (regular files; no symlinks; subdirectories excluded)
- Total lines: **28,486** (`wc -l`)
- 3 largest by line count:
  1. `validate-bash.sh` — 2,031
  2. `lead-crash-watchdog.sh` — 1,831
  3. `operator-readout.sh` — 1,664

Method: `find . -maxdepth 1 -name '*.sh' -type f -print0 | xargs -0 wc -l | sort -n`


## Tool calls (3) with the first 300 chars of each result
1. `Bash: {"command": "cd /tmp/tokeff-gate/f2/tree/hooks && find . -maxdepth 1 -name '*.sh' \\( -type f -o -type l \\) | wc -l; find . -maxdepth 1 -name '*.sh' -type l | wc -l; find . -maxdepth 1 -name '*.sh' -type f -print0 | xargs -0 wc -l | sort -n | tail -5; ls -la /tmp/tokeff-gate/f2/out/B07-r5/ 2>&1 | h`
   →       89
       0
    1593 ./waiting-recycle.sh
    1664 ./operator-readout.sh
    1831 ./lead-crash-watchdog.sh
    2031 ./validate-bash.sh
   28486 total
total 0
drwxr-xr-x@  2 chrisren  wheel    64 Sep 24 10:27 .
drwxr-xr-x@ 82 chrisren  wheel  2624 Sep 24 10:27 ..
2. `Bash: {"command": "cat > /tmp/tokeff-gate/f2/out/B07-r5/answer.md <<'EOF'\n# Hook scripts in /tmp/tokeff-gate/f2/tree/hooks (top level, *.sh only)\n\n- Files: **89** `.sh` files directly inside `hooks/` (regular files; no symlinks; subdirectories excluded)\n- Total lines: **28,486** (`wc -l`)\n- 3 largest`
   → # Hook scripts in /tmp/tokeff-gate/f2/tree/hooks (top level, *.sh only)

- Files: **89** `.sh` files directly inside `hooks/` (regular files; no symlinks; subdirectories excluded)
3. `StructuredOutput: {"answer_path": "/tmp/tokeff-gate/f2/out/B07-r5/answer.md", "headline": "hooks/ holds 89 top-level .sh files totalling 28,486 lines; the largest are validate-bash.sh (2,031), lead-crash-watchdog.sh (1,831) and operator-readout.sh (1,664).", "numbers": {"sh_files": 89, "total_lines": 28486}}`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
