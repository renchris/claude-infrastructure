# Dossier 3

## Brief
```
Review /tmp/tokeff-regate/f2/review/rotate-logs.sh for bugs. List each real bug with the line, what goes wrong, and a one-line fix. Do not list style nits separately from real bugs; rank by severity. Do not run the script. numbers: {"bugs": <how many real bugs>}.
```

## Returned headline
rotate-logs.sh has 7 real bugs, worst first: an unchecked, unquoted `cd` that can make it delete .gz files in the wrong directory; gzip refusing to overwrite the existing .gz, so each log is only ever rotated once; the `tail -n +$keep` off-by-one that keeps only keep-1 archives; `-mtime +1` meaning 2 or more days; word-splitting on odd filenames; pruning of unrelated .gz files; and a success message printed even when steps fail.

## Returned numbers
`{"bugs": 7}`

## answer.md
# rotate-logs.sh review: 7 real bugs, most severe first

1. **Line 5, `cd $dir`: the result is never checked and `$dir` is unquoted.** If `$1` is missing, `cd` goes to `$HOME`. If the directory doesn't exist, or its path contains a space, `cd` fails and the script keeps running in whatever directory it started in. Line 11 then deletes `*.gz` files in the wrong directory, which loses data.
   Fix: `[ -n "$dir" ] || { echo "usage: $0 <dir> [keep]" >&2; exit 2; }; cd -- "$dir" || exit 1`

2. **Line 8, `gzip "$f"`: each log can be rotated only once.** The first run turns `app.log` into `app.log.gz`. On any later run, `app.log.gz` already exists, so gzip refuses to overwrite it. Under cron it prints "already exists; not overwritten" and exits 2; in a terminal it asks. After that first rotation, `app.log` is never rotated again and grows without limit. It also means the retention step never has more than one archive per log to keep.
   Fix: `gzip -c -- "$f" > "$f.$(date +%Y%m%d%H%M%S).gz" && rm -- "$f"`

3. **Line 11, `tail -n +$keep`: off by one, so only `keep-1` archives survive.** `tail -n +5` prints from line 5 onward, which means the 5th-newest archive is deleted along with everything older. With the default of 5, only 4 archives are kept.
   Fix: `tail -n +$((keep + 1))`, after checking `keep` is numeric: `case $keep in ''|*[!0-9]*) exit 2;; esac`.

4. **Line 7, `find "$f" -mtime +1`: this matches files 2 or more days old, not files older than 1 day.** find counts age in whole 24-hour periods and rounds down, so `+1` means at least 48 hours. Logs between 24 and 48 hours old are skipped.
   Fix: `find "./$f" -mmin +1440` (or `-mtime +0`).

5. **Lines 6, 7 and 11: filenames containing whitespace, or starting with `-`, are mishandled.** `$(ls *.log)` splits `my app.log` into `my` and `app.log`, so gzip and find are given files that don't exist. The unquoted `[ $(find …) ]` on line 7 also splits its output, and `[` fails with "too many arguments". A file named `-foo.log` is read by find as an option. On line 11, `xargs` splits on spaces, so it can pass `rm` the wrong names.
   Fix: `for f in ./*.log; do [ -e "$f" ] || continue; if [ -n "$(find "$f" -mmin +1440)" ]; then …`, and replace the `xargs` step with a `while IFS= read -r g; do rm -f -- "$g"; done` loop.

6. **Line 11, `ls -t *.gz`: pruning covers every `.gz` file in the directory, not just rotated logs.** Unrelated archives stored alongside the logs count toward `keep` and get deleted.
   Fix: `ls -t -- *.log*.gz` (the name pattern that fix 2 produces).

7. **Line 12: "rotated logs" is printed no matter what happened.** There is no error handling (`set -e` or `|| exit`). A failed `cd`, a refused gzip or a failed `rm` still ends with a success message and exit status 0, so cron and monitoring never see the failure.
   Fix: add `set -euo pipefail` after the shebang (with fix 1's guards, the empty-`$1` case is still reported clearly), or add `|| exit 1` on each critical step.


## Tool calls (3) with the first 300 chars of each result
1. `Bash: {"command": "cat -n /tmp/tokeff-regate/f2/review/rotate-logs.sh; ls -la /tmp/tokeff-regate/f2/review/ /tmp/tokeff-regate/f2/out/B06-r2/ 2>&1", "description": "Read the script under review"}`
   → Exit code 1
     1	#!/bin/bash
     2	# rotate-logs.sh <dir> [keep] — gzip every *.log in <dir> older than 1 day, keep the newest <keep> archives.
     3	dir=$1
     4	keep=${2:-5}
     5	cd $dir
     6	for f in $(ls *.log); do
     7	  if [ $(find "$f" -mtime +1) ]; then
     8	    gzip "$f"
     9
2. `Bash: {"command": "mkdir -p /tmp/tokeff-regate/f2/out/B06-r2 && cat > /tmp/tokeff-regate/f2/out/B06-r2/answer.md <<'EOF'\n# rotate-logs.sh review: 7 real bugs, most severe first\n\n1. **Line 5, `cd $dir`: the result is never checked and `$dir` is unquoted.** If `$1` is missing, `cd` goes to `$HOME`. If th`
   → (Bash completed with no output)
3. `StructuredOutput: {"answer_path": "/tmp/tokeff-regate/f2/out/B06-r2/answer.md", "headline": "rotate-logs.sh has 7 real bugs, worst first: an unchecked, unquoted `cd` that can make it delete .gz files in the wrong directory; gzip refusing to overwrite the existing .gz, so each log is only ever rotated once; the `tail `
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
