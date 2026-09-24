# Dossier 6

## Brief
```
Measure the hook scripts: for the files directly inside /tmp/tokeff-regate/f2/tree/hooks whose names end in .sh (not subdirectories), report how many there are, their total line count, and the 3 largest by line count with their line counts. numbers: {"sh_files": N, "total_lines": N}.
```

## Returned headline
hooks/ holds 89 top-level .sh files totalling 28,486 lines; the largest are validate-bash.sh (2,031), lead-crash-watchdog.sh (1,831) and operator-readout.sh (1,664).

## Returned numbers
`{"sh_files": 89, "total_lines": 28486}`

## answer.md
# Hook scripts measurement — /tmp/tokeff-regate/f2/tree/hooks

Scope: regular files named `*.sh` directly inside `hooks/` (maxdepth 1; no subdirectories; 0 symlinks, 0 directories match).

- **.sh files:** 89
- **Total lines (`wc -l`):** 28,486

## 3 largest by line count
1. `validate-bash.sh` — 2,031 lines
2. `lead-crash-watchdog.sh` — 1,831 lines
3. `operator-readout.sh` — 1,664 lines

Method: `find . -maxdepth 1 -name '*.sh' -type f -print0 | xargs -0 wc -l | sort -n`


## Tool calls (3) with the first 300 chars of each result
1. `Bash: {"command": "cd /tmp/tokeff-regate/f2/tree/hooks && find . -maxdepth 1 -name '*.sh' \\( -type f -o -type l \\) | wc -l; find . -maxdepth 1 -name '*.sh' -type l | wc -l; find . -maxdepth 1 -name '*.sh' -type f -print0 | xargs -0 wc -l | sort -n | tail -4; find . -maxdepth 1 -name '*.sh' -type d | wc `
   →       89
       0
    1664 ./operator-readout.sh
    1831 ./lead-crash-watchdog.sh
    2031 ./validate-bash.sh
   28486 total
       0
2. `Bash: {"command": "mkdir -p /tmp/tokeff-regate/f2/out/B07-r4 && cat > /tmp/tokeff-regate/f2/out/B07-r4/answer.md <<'EOF'\n# Hook scripts measurement — /tmp/tokeff-regate/f2/tree/hooks\n\nScope: regular files named `*.sh` directly inside `hooks/` (maxdepth 1; no subdirectories; 0 symlinks, 0 directories ma`
   → (Bash completed with no output)
3. `StructuredOutput: {"answer_path": "/tmp/tokeff-regate/f2/out/B07-r4/answer.md", "headline": "hooks/ holds 89 top-level .sh files totalling 28,486 lines; the largest are validate-bash.sh (2,031), lead-crash-watchdog.sh (1,831) and operator-readout.sh (1,664).", "numbers": {"sh_files": 89, "total_lines": 28486}}`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
