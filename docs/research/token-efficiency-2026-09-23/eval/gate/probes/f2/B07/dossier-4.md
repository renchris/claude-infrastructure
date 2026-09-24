# Dossier 4

## Brief
```
Measure the hook scripts: for the files directly inside /tmp/tokeff-gate/f2/tree/hooks whose names end in .sh (not subdirectories), report how many there are, their total line count, and the 3 largest by line count with their line counts. numbers: {"sh_files": N, "total_lines": N}.
```

## Returned headline
The hooks folder holds 89 .sh files at its top level, with 28,486 lines in total (measured with find and wc -l). The three largest are validate-bash.sh (2,031 lines), lead-crash-watchdog.sh (1,831) and operator-readout.sh (1,664).

## Returned numbers
`{"sh_files": 89, "total_lines": 28486}`

## answer.md
# Hook scripts in /tmp/tokeff-gate/f2/tree/hooks (top level, *.sh only)

- Number of .sh files: **89** (measured: `find . -maxdepth 1 -type f -name '*.sh' | wc -l`; no symlinked or hidden .sh files)
- Total line count: **28,486** (measured: `wc -l` over those files; every file ends with a newline, so wc -l does not undercount)

## 3 largest by line count (measured: `wc -l | sort -rn`)
1. validate-bash.sh: 2,031 lines
2. lead-crash-watchdog.sh: 1,831 lines
3. operator-readout.sh: 1,664 lines

(4th, for context: waiting-recycle.sh, 1,593 lines)


## Tool calls (5) with the first 300 chars of each result
1. `Bash: {"command": "cd /tmp/tokeff-gate/f2/tree/hooks && find . -maxdepth 1 -type f -name '*.sh' | wc -l; find . -maxdepth 1 -type f -name '*.sh' -print0 | xargs -0 wc -l | sort -rn | head -5; ls -la /tmp/tokeff-gate/f2/out/B07-r2/ 2>&1; find . -maxdepth 1 -name '*.sh' ! -type f", "description": "Count hoo`
   →       89
   28486 total
    2031 ./validate-bash.sh
    1831 ./lead-crash-watchdog.sh
    1664 ./operator-readout.sh
    1593 ./waiting-recycle.sh
total 0
drwxr-xr-x@  2 chrisren  wheel    64 Sep 24 10:27 .
drwxr-xr-x@ 82 chrisren  wheel  2624 Sep 24 10:27 ..
2. `Bash: {"command": "cd /tmp/tokeff-gate/f2/tree/hooks && for f in *.sh .*.sh; do [ -f \"$f\" ] && [ -s \"$f\" ] && [ \"$(tail -c1 \"$f\" | xxd -p)\" != \"0a\" ] && echo \"no-trailing-nl: $f\"; done 2>/dev/null; ls -d .*.sh 2>/dev/null; echo done", "description": "Check for files lacking trailing newline or`
   → Exit code 1
3. `Bash: {"command": "cd /tmp/tokeff-gate/f2/tree/hooks; for f in *.sh; do if [ -s \"$f\" ] && [ \"$(tail -c1 \"$f\" | xxd -p)\" != \"0a\" ]; then echo \"no-trailing-nl: $f\"; fi; done; ls -A | grep -c '^\\..*\\.sh$'; echo done", "description": "Check trailing newlines and hidden .sh files"}`
   → 0
done
4. `Bash: {"command": "cat > /tmp/tokeff-gate/f2/out/B07-r2/answer.md <<'EOF'\n# Hook scripts in /tmp/tokeff-gate/f2/tree/hooks (top level, *.sh only)\n\n- Number of .sh files: **89** (measured: `find . -maxdepth 1 -type f -name '*.sh' | wc -l`; no symlinked or hidden .sh files)\n- Total line count: **28,486*`
   → (Bash completed with no output)
5. `StructuredOutput: {"answer_path": "/tmp/tokeff-gate/f2/out/B07-r2/answer.md", "headline": "The hooks folder holds 89 .sh files at its top level, with 28,486 lines in total (measured with find and wc -l). The three largest are validate-bash.sh (2,031 lines), lead-crash-watchdog.sh (1,831) and operator-readout.sh (1,66`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
