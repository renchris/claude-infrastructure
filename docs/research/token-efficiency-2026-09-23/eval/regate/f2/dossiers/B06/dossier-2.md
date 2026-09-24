# Dossier 2

## Brief
```
Review /tmp/tokeff-regate/f2/review/rotate-logs.sh for bugs. List each real bug with the line, what goes wrong, and a one-line fix. Do not list style nits separately from real bugs; rank by severity. Do not run the script. numbers: {"bugs": <how many real bugs>}.
```

## Returned headline
rotate-logs.sh has 6 real bugs, worst first: an unchecked, unquoted `cd $dir` (line 5) can gzip and delete files in the wrong directory; `tail -n +$keep` (line 11) keeps one archive too few; `ls | xargs rm` (line 11) can delete the wrong files when names contain spaces; word splitting on lines 6-7 means logs with spaces are never rotated; `-mtime +1` (line 7) actually means at least 2 days old; and `gzip` (line 8) refuses to overwrite an existing `.gz`, so a fixed-name log rotates only once.

## Returned numbers
`{"bugs": 6}`

## answer.md
# Review: /tmp/tokeff-regate/f2/review/rotate-logs.sh

I read the script but did not run it, as the brief asked. I found 6 real bugs, ranked from most to least severe.

1. **Line 5: `cd $dir` is unquoted and never checked (data loss).** If `$1` is missing, `cd` goes to `$HOME`. If the path doesn't exist or contains a space, `cd` fails and the script carries on in the current directory. Either way, lines 6-11 then gzip and delete `*.log` and `*.gz` files in the wrong directory.
   Fix: `[ -n "$dir" ] || { echo "usage: $0 <dir> [keep]" >&2; exit 2; }; cd -- "$dir" || exit 1`

2. **Line 11: `tail -n +$keep` keeps one archive too few.** `tail -n +K` starts output at line K, so only the newest `keep-1` archives survive. With the default of 5, only 4 are kept. With `keep=1` (or `0`), every archive is deleted.
   Fix: `ls -t -- *.gz | tail -n +$((keep + 1)) | xargs rm -f` (the bug 3 fix also applies to this line)

3. **Line 11: `ls | xargs rm` splits names on whitespace and quotes (wrong files deleted).** An archive called `old app.log.gz` becomes `rm -f old app.log.gz`, which deletes unrelated files named `old` and `app.log.gz` and leaves the real archive in place. A quote character in a name makes xargs abort.
   Fix: `ls -t -- *.gz | tail -n +$((keep+1)) | while IFS= read -r g; do rm -f -- "$g"; done` (or use `find -print0` with `xargs -0`)

4. **Lines 6-7: word splitting in `$(ls *.log)` and in the unquoted `[ $(find ...) ]`.** A log called `my app.log` is split into `my` and `app.log`. Neither exists, so the log is never rotated. Even with correct names, the unquoted `[ $(find ...) ]` breaks when find prints a name with spaces: `[` gets several words and errors out ("binary operator expected"), so the test is treated as false. A name starting with `-` is read by `find` as an option.
   Fix: `for f in ./*.log; do [ -e "$f" ] || continue; if [ -n "$(find "$f" -prune -mtime +0)" ]; then gzip -- "$f"; fi; done`

5. **Line 7: `-mtime +1` means "at least 2 days old", not "older than 1 day".** find rounds file age down to whole days, so `+1` only matches files 48 hours old or more. A log that is 30 hours old is left alone, which contradicts the header comment.
   Fix: `find "$f" -mmin +1440` (or `-mtime +0`)

6. **Line 8: `gzip "$f"` fails when `$f.gz` already exists.** A log with a fixed name (for example `app.log`) rotates once and becomes `app.log.gz`. On the next run, gzip refuses to overwrite it (and prompts if run on a terminal), so the log is never rotated again and keeps growing. Using `-f` instead would overwrite and lose the previous archive.
   Fix: `gzip -c -- "$f" > "$f.$(date +%Y%m%d%H%M%S).gz" && rm -f -- "$f"`

Lower-impact points that belong with the bugs above:
- There is no `set -e` or error check, so line 12 prints "rotated logs" even after a failed `cd`, `gzip` or `rm`.
- `keep` is never checked to be a number. A non-numeric value makes `tail` fail, so nothing is pruned, and the script still reports success.
- When nothing matches the globs, `ls` prints error messages. The loop and `rm -f` then do nothing, so this causes noise, not damage.


## Tool calls (4) with the first 300 chars of each result
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
2. `Bash: {"command": "ls -la /tmp/tokeff-regate/f2/review/ /tmp/tokeff-regate/f2/out/B06-r4/ 2>&1", "description": "List review and output directories"}`
   → /tmp/tokeff-regate/f2/out/B06-r4/:
total 0
drwxr-xr-x@  2 chrisren  wheel    64 Sep 24 13:39 .
drwxr-xr-x@ 82 chrisren  wheel  2624 Sep 24 13:39 ..

/tmp/tokeff-regate/f2/review/:
total 8
dr-xr-xr-x@  3 chrisren  wheel   96 Sep 24 12:36 .
drwxr-xr-x@ 10 chrisren  wheel  320 Sep 24 13:39 ..
-r--r--r-
3. `Bash: {"command": "cat > /tmp/tokeff-regate/f2/out/B06-r4/answer.md <<'EOF'\n# Review: /tmp/tokeff-regate/f2/review/rotate-logs.sh\n\nI read the script but did not run it, as the brief asked. I found 6 real bugs, ranked from most to least severe.\n\n1. **Line 5: `cd $dir` is unquoted and never checked (da`
   → (Bash completed with no output)
4. `StructuredOutput: {"answer_path": "/tmp/tokeff-regate/f2/out/B06-r4/answer.md", "headline": "rotate-logs.sh has 6 real bugs, worst first: an unchecked, unquoted `cd $dir` (line 5) can gzip and delete files in the wrong directory; `tail -n +$keep` (line 11) keeps one archive too few; `ls | xargs rm` (line 11) can dele`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
