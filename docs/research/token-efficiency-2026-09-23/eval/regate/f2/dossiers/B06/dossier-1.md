# Dossier 1

## Brief
```
Review /tmp/tokeff-regate/f2/review/rotate-logs.sh for bugs. List each real bug with the line, what goes wrong, and a one-line fix. Do not list style nits separately from real bugs; rank by severity. Do not run the script. numbers: {"bugs": <how many real bugs>}.
```

## Returned headline
rotate-logs.sh has 7 real bugs; I found them by reading it and did not run it. The worst is that line 5 doesn't check whether cd worked, so line 11 can delete *.gz files in $HOME or another wrong directory. Next: line 11 keeps only keep-1 archives, line 8 gzip refuses when the archive name already exists, line 11's *.gz pattern deletes unrelated archives, line 7 skips files 1 to 2 days old, and lines 6 and 11 split file names that contain spaces.

## Returned numbers
`{"bugs": 7}`

## answer.md
# rotate-logs.sh review: 7 real bugs, ranked by severity

I found these by reading the script. I did not run it.

1. **Line 5, `cd $dir`: the result isn't checked and `$dir` isn't quoted.** If the argument is missing, `cd` goes to `$HOME`. If the path is wrong, the script stays in the caller's directory. If the path has a space, the argument splits and `cd` fails. In all three cases the script keeps going and line 11 deletes `*.gz` files in the wrong directory, so data is lost.
   Fix: `[ -n "$dir" ] || { echo "usage: $0 <dir> [keep]" >&2; exit 1; }; cd -- "$dir" || exit 1`

2. **Line 11, `tail -n +$keep` is off by one.** `tail -n +N` prints from line N onward, so it deletes everything from the Nth-newest archive on. That keeps only `keep-1` archives: 4 with the default of 5, and none with `keep=1`.
   Fix: `tail -n +$((keep + 1))`

3. **Line 8, `gzip "$f"` always writes the same file name, `<name>.log.gz`.** The next time a log with that name is rotated, `app.log.gz` already exists. Without a terminal, gzip refuses with "already exists; not overwritten" and leaves the log uncompressed. So each log name can only ever have one archive, and the `keep` setting does nothing for it.
   Fix: `gzip -c -- "$f" > "$f.$(date +%Y%m%d%H%M%S).gz" && rm -f -- "$f"`

4. **Line 11, the `*.gz` pattern is too broad.** It matches every gzip file in the directory, not just rotated logs, so the retention step deletes unrelated `.gz` archives too. They also count toward `keep`.
   Fix: `ls -t -- *.log*.gz` (match only the archive names this script creates)

5. **Line 7, the age test is wrong and not quoted.**
   - `find -mtime +1` counts whole days and rounds down, so it only matches files that are at least 2 days old. Files between 1 and 2 days old are skipped, although the header says "older than 1 day".
   - The unquoted `[ $(find ...) ]` breaks with "binary operator expected" or gives the wrong answer when the file name contains spaces.
   - `find "$f"` reads a name that starts with `-` as an option.

   Fix: `if [ -n "$(find "./$f" -prune -mtime +0)" ]; then`

6. **Line 6, `for f in $(ls *.log)` splits file names.** The loop splits `ls` output on whitespace and expands wildcards in it. A log called `my app.log` becomes `my` and `app.log`, so it is never rotated, and the unrelated file `app.log` could be gzipped instead.
   Fix: `for f in *.log; do [ -e "$f" ] || continue`

7. **Line 11, `xargs rm -f` splits names on whitespace and quotes.** An archive called `my app.log.gz` is passed to `rm` as `my` and `app.log.gz`. The archive itself is never deleted, a different file with one of those names can be, and a quote in a name makes xargs fail.
   Fix: `... | tail -n +$((keep + 1)) | while IFS= read -r g; do rm -f -- "$g"; done`

**Not counted as bugs:**
- When there are no `.gz` files, line 11 only prints an `ls` error to stderr. `rm -f` with no arguments does nothing.
- `keep` is never checked to be a number. A non-numeric value only makes `tail` fail, and nothing gets deleted.


## Tool calls (5) with the first 300 chars of each result
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
2. `Bash: {"command": "ls -la /tmp/tokeff-regate/f2/review/ /tmp/tokeff-regate/f2/out/B06-r1/ 2>&1", "description": "List review directory and output directory"}`
   → Exit code 1
ls: /tmp/tokeff-regate/f2/out/B06-r1/: No such file or directory
/tmp/tokeff-regate/f2/review/:
total 8
dr-xr-xr-x@ 3 chrisren  wheel   96 Sep 24 12:36 .
drwxr-xr-x@ 9 chrisren  wheel  288 Sep 24 13:07 ..
-r--r--r--@ 1 chrisren  wheel  308 Sep 24 10:27 rotate-logs.sh
3. `Bash: {"command": "mkdir -p /tmp/tokeff-regate/f2/out/B06-r1", "description": "Create the output directory"}`
   → (Bash completed with no output)
4. `Write: {"file_path": "/tmp/tokeff-regate/f2/out/B06-r1/answer.md", "content": "# rotate-logs.sh review: 7 real bugs, ranked by severity\n\nI found these by reading the script. I did not run it.\n\n1. **Line 5, `cd $dir`: the result isn't checked and `$dir` isn't quoted.** If the argument is missing, `cd` g`
   → File created successfully at: /tmp/tokeff-regate/f2/out/B06-r1/answer.md (file state is current in your context — no need to Read it back)
5. `StructuredOutput: {"answer_path": "/tmp/tokeff-regate/f2/out/B06-r1/answer.md", "headline": "rotate-logs.sh has 7 real bugs; I found them by reading it and did not run it. The worst is that line 5 doesn't check whether cd worked, so line 11 can delete *.gz files in $HOME or another wrong directory. Next: line 11 keep`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
