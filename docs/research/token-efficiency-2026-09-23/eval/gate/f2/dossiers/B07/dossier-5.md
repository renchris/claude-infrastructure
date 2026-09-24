# Dossier 5

## Brief
```
Measure the hook scripts: for the files directly inside /tmp/tokeff-gate/f2/tree/hooks whose names end in .sh (not subdirectories), report how many there are, their total line count, and the 3 largest by line count with their line counts. numbers: {"sh_files": N, "total_lines": N}.
```

## Returned headline
The hooks directory has 89 .sh files directly inside it, totalling 28486 lines (measured with find -maxdepth 1 and wc -l). The three largest are validate-bash.sh (2031 lines), lead-crash-watchdog.sh (1831) and operator-readout.sh (1664).

## Returned numbers
`{"sh_files": 89, "total_lines": 28486}`

## answer.md
# Hook scripts measurement: /tmp/tokeff-gate/f2/tree/hooks

Scope: regular files named `*.sh` directly inside the hooks directory, not recursing into subdirectories (`find . -maxdepth 1 -type f -name '*.sh'`).

- Number of .sh files: **89** (measured: `find ... | wc -l`)
- Total line count: **28486** (measured: `wc -l` over the 89 files; every file ends with a newline and there are no hidden `.sh` files, so `wc -l` gives the true line count)

Three largest by line count (measured: `wc -l | sort -n`):
1. validate-bash.sh: 2031 lines
2. lead-crash-watchdog.sh: 1831 lines
3. operator-readout.sh: 1664 lines

(The next largest is waiting-recycle.sh at 1593 lines.)


## Tool calls (4) with the first 300 chars of each result
1. `Bash: {"command": "cd /tmp/tokeff-gate/f2/tree/hooks && find . -maxdepth 1 -type f -name '*.sh' | wc -l; find . -maxdepth 1 -name '*.sh' ! -type f | head; find . -maxdepth 1 -type f -name '*.sh' -print0 | xargs -0 wc -l | sort -n | tail -5; ls -ld /tmp/tokeff-gate/f2/out/B07-r7 2>&1", "description": "Coun`
   →       89
    1593 ./waiting-recycle.sh
    1664 ./operator-readout.sh
    1831 ./lead-crash-watchdog.sh
    2031 ./validate-bash.sh
   28486 total
drwxr-xr-x@ 2 chrisren  wheel  64 Sep 24 10:27 /tmp/tokeff-gate/f2/out/B07-r7
2. `Bash: {"command": "cd /tmp/tokeff-gate/f2/tree/hooks && for f in *.sh; do [ -f \"$f\" ] && [ -s \"$f\" ] && [ \"$(tail -c1 \"$f\" | xxd -p)\" != \"0a\" ] && echo \"no-trailing-nl: $f\"; done; ls -A | grep -c '^\\..*\\.sh$'", "description": "Check for missing trailing newlines and hidden .sh files"}`
   → 0
3. `Bash: {"command": "cat > /tmp/tokeff-gate/f2/out/B07-r7/answer.md <<'EOF'\n# Hook scripts measurement: /tmp/tokeff-gate/f2/tree/hooks\n\nScope: regular files named `*.sh` directly inside the hooks directory, not recursing into subdirectories (`find . -maxdepth 1 -type f -name '*.sh'`).\n\n- Number of .sh `
   → (Bash completed with no output)
4. `StructuredOutput: {"answer_path": "/tmp/tokeff-gate/f2/out/B07-r7/answer.md", "headline": "The hooks directory has 89 .sh files directly inside it, totalling 28486 lines (measured with find -maxdepth 1 and wc -l). The three largest are validate-bash.sh (2031 lines), lead-crash-watchdog.sh (1831) and operator-readout.`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
