# Dossier 4

## Brief
```
Review /tmp/tokeff-gate/f2/review/rotate-logs.sh for bugs. List each real bug with the line, what goes wrong, and a one-line fix. Do not list style nits separately from real bugs; rank by severity. Do not run the script. numbers: {"bugs": <how many real bugs>}.
```

## Returned headline
I found 7 real bugs in rotate-logs.sh (read only, not run), worst first: (1) the unquoted, unchecked `cd $dir` (line 5) also runs with no argument, so line 11 deletes .gz files in $HOME or the caller's directory; (2) `tail -n +$keep` keeps one archive fewer than asked; (3) `*.gz` deletes unrelated gzip files; (4) `xargs` splits names on spaces and can remove the wrong file; (5) the `ls`/unquoted-test loop breaks on names with spaces or a leading dash; (6) a fixed `.log.gz` name collides on the next rotation, so the log never rotates again; (7) `-mtime +1` waits about 48h, not 1 day.

## Returned numbers
`{"bugs": 7}`

## answer.md
# Review: /tmp/tokeff-gate/f2/review/rotate-logs.sh

I read the script but did not run it. The bugs are ranked by severity, most severe first. Count: **7 real bugs**.

| # | Line | Severity | What goes wrong | One-line fix |
|---|------|----------|-----------------|--------------|
| 1 | 3, 5 | Critical | `cd $dir` is unquoted and nothing checks whether it worked. If `$1` is missing, `cd` goes to `$HOME`. If the directory does not exist, or its name contains spaces, `cd` fails and the script keeps running in the caller's cwd. Either way, line 11 then deletes `*.gz` files in the wrong directory. | `[ -n "$1" ] \|\| { echo "usage: $0 <dir> [keep]" >&2; exit 2; }; cd -- "$dir" \|\| exit 1` |
| 2 | 11 | High | Off-by-one error: `tail -n +N` starts printing at line N, so `tail -n +$keep` keeps only `keep-1` archives (4 with the default of 5). With `keep=1` it deletes every archive. | `tail -n +$((keep + 1))` |
| 3 | 11 | High | `*.gz` matches every gzip file in the directory, not just rotated logs. The script deletes any unrelated `.gz` file (backups, dumps) that is not among the newest `keep`. | Restrict the glob to rotated logs: `ls -t -- *.log*.gz` (it must match the naming used by the fix for bug 6) |
| 4 | 11 | High | `xargs` splits its input on whitespace and treats quotes specially. The archive `my app.log.gz` becomes `rm -f my app.log.gz`, which misses the real file and can delete an unrelated file named `my` or `app.log.gz`. Newlines in names break it the same way. | `ls -t -- *.log*.gz \| tail -n +$((keep+1)) \| while IFS= read -r g; do rm -f -- "$g"; done` (or a NUL-safe `find ... -print0 \| xargs -0`) |
| 5 | 6-7 | Medium | Three problems in the loop. (a) `for f in $(ls *.log)` word-splits names that contain spaces, so `gzip` gets fragments that don't exist. (b) `[ $(find ...) ]` is unquoted, so a match whose name has spaces gives `[: too many arguments`/`binary operator expected` and the file is skipped. (c) A name that starts with `-` is read as an option by `find` and `gzip`. When no `*.log` file exists, `ls` also prints an error. | `for f in ./*.log; do [ -e "$f" ] \|\| continue; if [ -n "$(find "$f" -mtime +0)" ]; then gzip -- "$f"; fi; done` |
| 6 | 8 | Medium | The archive name is fixed as `<name>.log.gz`. On the next run the recreated `app.log` collides with the existing `app.log.gz`. Without a TTY, gzip refuses to overwrite, so the log is never rotated again and keeps growing. | Use a timestamped name: `gzip -c -- "$f" > "$f.$(date +%Y%m%d%H%M%S).gz" && rm -- "$f"` |
| 7 | 7 | Medium | `-mtime +1` means "at least 2 whole 24h periods old": find truncates the file's age to whole days, then requires more than 1. A file that is 25 to 47 hours old is not rotated, although the header promises "older than 1 day". | `find "$f" -mtime +0` (or `-mmin +1440`) |

## Lower-priority note (not counted)
- Line 8: if a process still has a log open, gzipping and unlinking it loses whatever the process writes afterwards. The one-day mtime check makes this unlikely, but it is not guaranteed. For daemons that keep files open, use copytruncate (`gzip -c ... && : > "$f"`) or signal the writer.

## Suggested corrected core
```bash
dir=${1:?usage: rotate-logs.sh <dir> [keep]}; keep=${2:-5}
cd -- "$dir" || exit 1
find . -maxdepth 1 -type f -name '*.log' -mtime +0 -exec sh -c \
  'for f; do gzip -c -- "$f" > "$f.$(date +%Y%m%d%H%M%S).gz" && rm -- "$f"; done' _ {} +
ls -t -- *.log.*.gz 2>/dev/null | tail -n +$((keep + 1)) | while IFS= read -r g; do rm -f -- "$g"; done
```


## Tool calls (4) with the first 300 chars of each result
1. `Read: {"file_path": "/tmp/tokeff-gate/f2/review/rotate-logs.sh"}`
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
2. `Bash: {"command": "ls -la /tmp/tokeff-gate/f2/review/ /tmp/tokeff-gate/f2/out/ 2>&1 | head -50", "description": "List review and output directories"}`
   → /tmp/tokeff-gate/f2/out/:
total 0
drwxr-xr-x@ 82 chrisren  wheel  2624 Sep 24 10:27 .
drwxr-xr-x@  9 chrisren  wheel   288 Sep 24 10:27 ..
drwxr-xr-x@  3 chrisren  wheel    96 Sep 24 10:28 B01-r1
drwxr-xr-x@  3 chrisren  wheel    96 Sep 24 10:29 B01-r2
drwxr-xr-x@  3 chrisren  wheel    96 Sep 24 10:
3. `Write: {"file_path": "/tmp/tokeff-gate/f2/out/B06-r4/answer.md", "content": "# Review: /tmp/tokeff-gate/f2/review/rotate-logs.sh\n\nI read the script but did not run it. The bugs are ranked by severity, most severe first. Count: **7 real bugs**.\n\n| # | Line | Severity | What goes wrong | One-line fix |\n`
   → File created successfully at: /tmp/tokeff-gate/f2/out/B06-r4/answer.md (file state is current in your context — no need to Read it back)
4. `StructuredOutput: {"answer_path": "/tmp/tokeff-gate/f2/out/B06-r4/answer.md", "headline": "I found 7 real bugs in rotate-logs.sh (read only, not run), worst first: (1) the unquoted, unchecked `cd $dir` (line 5) also runs with no argument, so line 11 deletes .gz files in $HOME or the caller's directory; (2) `tail -n +`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
