# Dossier 7

## Brief
```
Measure the hook scripts: for the files directly inside /tmp/tokeff-gate/f2/tree/hooks whose names end in .sh (not subdirectories), report how many there are, their total line count, and the 3 largest by line count with their line counts. numbers: {"sh_files": N, "total_lines": N}.
```

## Returned headline
The hooks directory has 89 top-level .sh files, 28,486 lines in total (measured with find and wc -l); the three largest are validate-bash.sh (2031 lines), lead-crash-watchdog.sh (1831) and operator-readout.sh (1664).

## Returned numbers
`{"sh_files": 89, "total_lines": 28486}`

## answer.md
# Hook scripts in /tmp/tokeff-gate/f2/tree/hooks (top level only, *.sh)

- Count of .sh files (regular files, maxdepth 1): **89**
- Total line count (`wc -l`): **28486**
- 3 largest by line count:
  1. validate-bash.sh: 2031
  2. lead-crash-watchdog.sh: 1831
  3. operator-readout.sh: 1664

Method (measured): `find . -maxdepth 1 -type f -name '*.sh' | wc -l` and
`find . -maxdepth 1 -type f -name '*.sh' -print0 | xargs -0 wc -l | sort -n`.
Checks: no top-level *.sh entry is a symlink or directory (`find . -maxdepth 1 -name '*.sh' ! -type f` was empty),
and every file ends with a newline, so `wc -l` does not undercount.


## Tool calls (3) with the first 300 chars of each result
1. `Bash: {"command": "cd /tmp/tokeff-gate/f2/tree/hooks && ls -la | head -5; find . -maxdepth 1 -name '*.sh' ! -type f; echo ---; find . -maxdepth 1 -type f -name '*.sh' | wc -l; find . -maxdepth 1 -type f -name '*.sh' -print0 | xargs -0 wc -l | sort -n | tail -5; echo ---; for f in *.sh; do [ -f \"$f\" ] &&`
   → total 4368
dr-xr-xr-x@ 96 chrisren  wheel    3072 Sep 24 00:14 .
dr-xr-xr-x@ 46 chrisren  wheel    1472 Sep 24 10:27 ..
-r-xr-xr-x@  1 chrisren  wheel    7529 Sep 24 00:14 accounts-board.sh
-r-xr-xr-x@  1 chrisren  wheel   47673 Sep 24 00:14 activation-watch.sh
---
      89
    1593 ./waiting-recycl
2. `Bash: {"command": "cat > /tmp/tokeff-gate/f2/out/B07-r3/answer.md <<'EOF'\n# Hook scripts in /tmp/tokeff-gate/f2/tree/hooks (top level only, *.sh)\n\n- Count of .sh files (regular files, maxdepth 1): **89**\n- Total line count (`wc -l`): **28486**\n- 3 largest by line count:\n  1. validate-bash.sh: 2031\n`
   → (Bash completed with no output)
3. `StructuredOutput: {"answer_path": "/tmp/tokeff-gate/f2/out/B07-r3/answer.md", "headline": "The hooks directory has 89 top-level .sh files, 28,486 lines in total (measured with find and wc -l); the three largest are validate-bash.sh (2031 lines), lead-crash-watchdog.sh (1831) and operator-readout.sh (1664).", "numbers`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
