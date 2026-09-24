# Dossier 7

## Brief
```
Review /tmp/tokeff-regate/f2/review/rotate-logs.sh for bugs. List each real bug with the line, what goes wrong, and a one-line fix. Do not list style nits separately from real bugs; rank by severity. Do not run the script. numbers: {"bugs": <how many real bugs>}.
```

## Returned headline
rotate-logs.sh has 6 real bugs. The worst: with no argument, or a directory that does not exist, it deletes *.gz files in $HOME or the caller's directory. Also: retention keeps one archive too few, a log can only be rotated once, -mtime +1 means 2 or more days, filenames with spaces break, and it deletes unrelated .gz files.

## Returned numbers
`{"bugs": 6}`

## answer.md
# rotate-logs.sh review — 6 real bugs, ranked by severity

1. **Lines 3, 5: no argument check and an unchecked `cd` send the delete to the wrong directory (critical).**
   Run with no argument, `cd $dir` becomes a bare `cd`, which goes to `$HOME`. Give it a path that does not exist and the `cd` fails, but the script keeps running in the caller's cwd. Either way, line 11 then deletes every `*.gz` in that directory except the newest few. The unquoted `$dir` also breaks on paths with spaces. Line 12 then reports success anyway.
   Fix: `[ -n "$1" ] || { echo "usage: $0 <dir> [keep]" >&2; exit 2; }; cd -- "$dir" || exit 1`

2. **Line 11: off-by-one in retention (high).**
   `tail -n +$keep` starts output at line `keep`, so it deletes from the keep-th newest archive onward. Only `keep-1` archives survive: the default keeps 4, and `keep=1` keeps none.
   Fix: `tail -n +$((keep + 1))`, after checking that `keep` is a non-negative integer.

3. **Line 8: rotating the same log a second time fails (high).**
   `gzip "$f"` writes `$f.gz`. The next time `app.log` is due, `app.log.gz` already exists. Without a terminal, gzip refuses ("already exists; not overwritten") and exits non-zero. With a terminal, it stops at a prompt. So each log name is rotated once and never again, and the "keep the newest N archives" logic can never apply to more than one archive per log.
   Fix: `gzip -c -- "$f" > "$f.$(date +%Y%m%d%H%M%S).gz" && rm -- "$f"`

4. **Line 7: `-mtime +1` means at least 2 days old, not "older than 1 day" (medium).**
   find rounds age down to whole 24-hour periods, so `+1` only matches files 48 hours old or more. A log that is 30 hours old is skipped.
   Fix: `find "$f" -mtime +0` (or `-mmin +1440`), and quote the test: `[ -n "$(find ...)" ]`.

5. **Lines 6, 7, 11: filenames containing whitespace or glob characters break (medium).**
   - Line 6: `for f in $(ls *.log)` splits `my app.log` into `my` and `app.log`, so those files are never rotated.
   - Line 7: the unquoted `[ $(...) ]` errors on multi-word output.
   - Line 11: `xargs rm -f` splits on whitespace too, so it can delete the wrong file or miss the right one.

   Fix: `for f in *.log; do [ -e "$f" ] || continue; ...`, and delete with `ls -t -- *.gz | tail -n +$((keep+1)) | while IFS= read -r g; do rm -f -- "$g"; done`. A cleaner option for both is `find -print0 | xargs -0`.

6. **Line 11: retention deletes every `*.gz` in the directory, not just rotated logs (medium-low).**
   Any unrelated `.gz` in the log directory (a backup, a download) counts against `keep` and gets deleted.
   Fix: match only the archives this script creates, e.g. `ls -t -- *.log*.gz`.

Not counted separately: line 12 always prints success and the script exits 0 even when gzip or rm failed. The `|| exit` in fix #1, plus checking gzip's exit status, covers it.


## Tool calls (3) with the first 300 chars of each result
1. `Bash: {"command": "cat -n /tmp/tokeff-regate/f2/review/rotate-logs.sh; ls /tmp/tokeff-regate/f2/review/", "description": "Show the script under review with line numbers"}`
   →      1	#!/bin/bash
     2	# rotate-logs.sh <dir> [keep] — gzip every *.log in <dir> older than 1 day, keep the newest <keep> archives.
     3	dir=$1
     4	keep=${2:-5}
     5	cd $dir
     6	for f in $(ls *.log); do
     7	  if [ $(find "$f" -mtime +1) ]; then
     8	    gzip "$f"
     9	  fi
    10
2. `Bash: {"command": "mkdir -p /tmp/tokeff-regate/f2/out/B06-r6 && cat > /tmp/tokeff-regate/f2/out/B06-r6/answer.md <<'EOF'\n# rotate-logs.sh review — 6 real bugs, ranked by severity\n\n1. **Lines 3, 5: no argument check and an unchecked `cd` send the delete to the wrong directory (critical).**\n   Run with `
   → (Bash completed with no output)
3. `StructuredOutput: {"answer_path": "/tmp/tokeff-regate/f2/out/B06-r6/answer.md", "headline": "rotate-logs.sh has 6 real bugs. The worst: with no argument, or a directory that does not exist, it deletes *.gz files in $HOME or the caller's directory. Also: retention keeps one archive too few, a log can only be rotated o`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
