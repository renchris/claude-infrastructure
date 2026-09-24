# Dossier 8

## Brief
```
Review /tmp/tokeff-regate/f2/review/rotate-logs.sh for bugs. List each real bug with the line, what goes wrong, and a one-line fix. Do not list style nits separately from real bugs; rank by severity. Do not run the script. numbers: {"bugs": <how many real bugs>}.
```

## Returned headline
rotate-logs.sh has 8 real bugs. The worst is the unchecked `cd $dir` (line 5): if it fails, line 11 deletes .gz files in the wrong directory (e.g. $HOME). Line 11 also deletes every *.gz, not just rotated logs, and keeps one archive fewer than asked. The others: a second rotation of the same log fails because the .gz name already exists, `-mtime +1` means 2 days rather than 1, filenames are split on spaces in both the loop and xargs, and keep is never checked while failures still exit 0.

## Returned numbers
`{"bugs": 8}`

## answer.md
# rotate-logs.sh review: 8 real bugs, most severe first

1. **Line 5: `cd $dir` is unquoted, has no failure check, and `$1` is never required.** Suppose `$1` is empty, the directory is missing, or the path has a space. The `cd` then fails, or a bare `cd` goes to `$HOME`. The script carries on in the wrong directory, and line 11 runs `rm -f` on that directory's `*.gz` files.
   Fix: `[ -n "$1" ] || { echo "usage: $0 <dir> [keep]" >&2; exit 2; }; cd -- "$dir" || exit 1`

2. **Line 11: the glob `*.gz` matches every gzip file in the directory, not just rotated logs.** Files such as `backup.tar.gz` or `data.csv.gz` get counted in the retention set and deleted.
   Fix: use `ls -t -- *.log.gz` (or whatever archive name pattern the script writes).

3. **Line 11: `tail -n +$keep` keeps one archive too few.** `tail -n +N` starts printing at line N, so only the first N-1 (newest) archives survive. The default `keep=5` keeps 4.
   Fix: `tail -n +"$((keep + 1))"`

4. **Line 8: rotating the same log a second time fails.** The first rotation turns `app.log` into `app.log.gz`. The app then recreates `app.log`, and the next run's `gzip app.log` finds `app.log.gz` already there. Without a terminal (e.g. under cron), gzip refuses and skips the file. With a terminal it stops to ask. Either way the log is not rotated from then on.
   Fix: `gzip -c -- "$f" > "$f.$(date +%Y%m%d%H%M%S).gz" && rm -- "$f"` (and match `*.log.*.gz` on line 11).

5. **Line 7: `-mtime +1` means "at least 2 whole days old", not "older than 1 day".** `find` rounds the age down to whole 24h periods and `+1` means more than 1. Logs aged between 24h and 48h are skipped.
   Fix: use `-mtime +0`, or `-mmin +1440`.

6. **Lines 6-7: word splitting on filenames.** `for f in $(ls *.log)` splits `my app.log` into `my` and `app.log`. The unquoted `[ $(find …) ]` then gets several words and fails with "too many arguments", which evaluates as false. A name starting with `-` is read as a `find` option. Such files are never rotated, or the wrong names are processed.
   Fix: `for f in ./*.log; do [ -e "$f" ] || continue; if [ -n "$(find "$f" -prune -mtime +0)" ]; then …`

7. **Line 11: `xargs rm -f` splits on whitespace and quotes.** An archive named `my app.log.gz` becomes `rm -f my app.log.gz`, which can delete an unrelated file named `my` or `app.log.gz`. A name containing a quote makes xargs abort.
   Fix: `ls -t -- *.log.gz | tail -n +"$((keep+1))" | while IFS= read -r g; do rm -f -- "$g"; done`

8. **Line 4: `keep` is never validated.** A non-numeric value makes `tail` error out, so retention silently never happens. The script still prints "rotated" on line 12 and exits 0 whatever failed, so cron never sees an error.
   Fix: `case $keep in ''|*[!0-9]*) echo "keep must be an integer" >&2; exit 2;; esac`, and add `set -o pipefail` plus a checked exit status before the final echo.

Note (not counted): gzipping a log the application still has open loses anything it writes afterwards. The writes go to the unlinked file. This is a design limit: fixing it needs `copytruncate` or a reopen signal to the app.


## Tool calls (3) with the first 300 chars of each result
1. `Read: {"file_path": "/tmp/tokeff-regate/f2/review/rotate-logs.sh"}`
   → 1	#!/bin/bash
2	# rotate-logs.sh <dir> [keep] — gzip every *.log in <dir> older than 1 day, keep the newest <keep> archives.
3	dir=$1
4	keep=${2:-5}
5	cd $dir
6	for f in $(ls *.log); do
7	  if [ $(find "$f" -mtime +1) ]; then
8	    gzip "$f"
9	  fi
10	done
11	ls -t *.gz | tail -n +$keep | xargs rm -
2. `Bash: {"command": "mkdir -p /tmp/tokeff-regate/f2/out/B06-r3 && cat > /tmp/tokeff-regate/f2/out/B06-r3/answer.md <<'EOF'\n# rotate-logs.sh review: 8 real bugs, most severe first\n\n1. **Line 5: `cd $dir` is unquoted, has no failure check, and `$1` is never required.** Suppose `$1` is empty, the directory `
   → (Bash completed with no output)
3. `StructuredOutput: {"answer_path": "/tmp/tokeff-regate/f2/out/B06-r3/answer.md", "headline": "rotate-logs.sh has 8 real bugs. The worst is the unchecked `cd $dir` (line 5): if it fails, line 11 deletes .gz files in the wrong directory (e.g. $HOME). Line 11 also deletes every *.gz, not just rotated logs, and keeps one `
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
