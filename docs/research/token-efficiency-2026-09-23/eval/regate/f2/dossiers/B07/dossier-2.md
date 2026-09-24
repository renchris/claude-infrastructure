# Dossier 2

## Brief
```
Measure the hook scripts: for the files directly inside /tmp/tokeff-regate/f2/tree/hooks whose names end in .sh (not subdirectories), report how many there are, their total line count, and the 3 largest by line count with their line counts. numbers: {"sh_files": N, "total_lines": N}.
```

## Returned headline
The top level of hooks/ holds 89 .sh files with 28,486 lines in total; the three largest are validate-bash.sh at 2,031 lines, lead-crash-watchdog.sh at 1,831 and operator-readout.sh at 1,664.

## Returned numbers
`{"sh_files": 89, "total_lines": 28486}`

## answer.md
# Hook scripts: measurements

The top level of `/tmp/tokeff-regate/f2/tree/hooks` holds **89 `.sh` files with 28,486 lines between them**. Subdirectories (`lib/`, `tests/`) were left out.

The three largest, by line count:

| Rank | File | Lines |
|---|---|---|
| 1 | validate-bash.sh | 2,031 |
| 2 | lead-crash-watchdog.sh | 1,831 |
| 3 | operator-readout.sh | 1,664 |

How this was measured:
- Files were listed with `find hooks -maxdepth 1 -name '*.sh' -type f` and counted with `wc -l`.
- None of the matching entries is a symlink.
- Every file ends with a newline, so `wc -l` gives the true line count for each one.


## Tool calls (4) with the first 300 chars of each result
1. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree/hooks && find . -maxdepth 1 -name '*.sh' \\( -type f -o -type l \\) | wc -l; find . -maxdepth 1 -name '*.sh' -type l | wc -l; find . -maxdepth 1 -name '*.sh' -type f -print0 | xargs -0 wc -l | sort -n | tail -4; ls -d */ 2>/dev/null | head", "description": `
   →       89
       0
    1664 ./operator-readout.sh
    1831 ./lead-crash-watchdog.sh
    2031 ./validate-bash.sh
   28486 total
lib/
tests/
2. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree/hooks && n=0; for f in *.sh; do [ -f \"$f\" ] && [ -s \"$f\" ] && [ \"$(tail -c1 \"$f\" | od -An -c | tr -d ' ')\" != '\\n' ] && { n=$((n+1)); echo \"$f\"; }; done; echo \"no-trailing-newline=$n\"", "description": "Check for files lacking trailing newline"}`
   → no-trailing-newline=0
3. `Bash: {"command": "mkdir -p /tmp/tokeff-regate/f2/out/B07-r5 && cat > /tmp/tokeff-regate/f2/out/B07-r5/answer.md <<'EOF'\n# Hook scripts: measurements\n\nThe top level of `/tmp/tokeff-regate/f2/tree/hooks` holds **89 `.sh` files with 28,486 lines between them**. Subdirectories (`lib/`, `tests/`) were left`
   → (Bash completed with no output)
4. `StructuredOutput: {"answer_path": "/tmp/tokeff-regate/f2/out/B07-r5/answer.md", "headline": "The top level of hooks/ holds 89 .sh files with 28,486 lines in total; the three largest are validate-bash.sh at 2,031 lines, lead-crash-watchdog.sh at 1,831 and operator-readout.sh at 1,664.", "numbers": {"sh_files": 89, "to`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
