# Dossier 4

## Brief
```
Review /tmp/tokeff-regate/f2/review/rotate-logs.sh for bugs. List each real bug with the line, what goes wrong, and a one-line fix. Do not list style nits separately from real bugs; rank by severity. Do not run the script. numbers: {"bugs": <how many real bugs>}.
```

## Returned headline
I found 6 real bugs in rotate-logs.sh, worst first (read only, not run): an unchecked, unquoted cd (line 5) that can gzip and delete files in the wrong directory; an off-by-one in tail (line 11) that keeps only keep-1 archives; xargs splitting filenames on whitespace (line 11), which can delete unrelated files; -mtime +1 (line 7) meaning at least 2 days, not 1; word splitting on filenames in the loop and test (lines 6-7); and gzip failing when the .gz already exists (line 8).

## Returned numbers
`{"bugs": 6}`

## answer.md
# Review: /tmp/tokeff-regate/f2/review/rotate-logs.sh

Method: I read the 12-line script. I did not run it. Behaviour below comes from bash, find, tail, xargs and gzip semantics.

Real bugs, most severe first:

1. **Line 5, `cd $dir`: a failed cd is not checked, and `$dir` is unquoted.** If the directory is missing, has no permission, or contains a space, `cd` fails and the script keeps going in whatever directory it was started from. If no argument is given, `cd` goes to `$HOME`. Either way, line 8 gzips that directory's `*.log` files and line 11 deletes its `*.gz` files. Line 12 still prints "rotated logs in ...".
   Fix: `cd -- "${dir:?usage: rotate-logs.sh <dir> [keep]}" || exit 1`

2. **Line 11, `tail -n +$keep`: off by one, so it keeps `keep-1` archives.** `tail -n +N` starts output at line N. With keep=5 it prints lines 5 and later, so the 5th-newest archive is deleted and only 4 remain. With keep=1, `tail -n +1` prints every line and all archives are deleted.
   Fix: `tail -n +"$((keep + 1))"`

3. **Line 11, `| xargs rm -f`: filenames are split on whitespace and quotes.** An archive named `app 1.gz` becomes `rm -f app 1.gz`, which deletes unrelated files called `app` and `1.gz`. That archive also never gets rotated out. A quote character in a name makes xargs abort.
   Fix: `ls -t -- *.gz | tail -n +"$((keep+1))" | tr '\n' '\0' | xargs -0 rm -f --`. Better, avoid parsing `ls` and use `find . -maxdepth 1 -name '*.gz' -print0` sorted by mtime.

4. **Line 7, `find "$f" -mtime +1`: the age test is wrong.** `-mtime +1` matches files whose age, rounded down to whole days, is greater than 1. That means at least 2 full days old. The header says "older than 1 day", so a log that is 30 hours old is not rotated.
   Fix: `find "./$f" -mtime +0` (or `-mmin +1440`)

5. **Lines 6-7, `for f in $(ls *.log)` and the unquoted `[ $(find ...) ]`: word splitting and globbing on filenames.** A log named `my app.log` becomes two loop items, `my` and `app.log`. find and gzip then fail on names that don't exist, and the real file is never rotated. If a name is split into several words inside `[ ... ]`, you get "too many arguments" or a wrong test result. A name starting with `-` is read as an option by find.
   Fix: `for f in ./*.log; do [ -e "$f" ] || continue; if [ -n "$(find "$f" -mtime +0)" ]; then gzip -- "$f"; fi; done`

6. **Line 8, `gzip "$f"`: fails when `$f.gz` already exists.** This happens when a log with the same name was rotated earlier and then recreated. gzip refuses to overwrite: it prompts on a terminal, or prints "already exists; not overwritten" under cron. The log stays uncompressed and keeps growing. Nothing checks for the error.
   Fix: compress to a unique name, e.g. `gzip -c -- "$f" > "$f.$(date +%Y%m%d%H%M%S).gz" && rm -- "$f"`. Or at least check: `gzip -- "$f" || echo "gzip failed: $f" >&2`

Total real bugs: 6 (1-3 high, 4-5 medium, 6 low).


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
2. `Bash: {"command": "ls -la /tmp/tokeff-regate/f2/review/ /tmp/tokeff-regate/f2/out/B06-r5/ 2>&1", "description": "List review and output directories"}`
   → /tmp/tokeff-regate/f2/out/B06-r5/:
total 0
drwxr-xr-x@  2 chrisren  wheel    64 Sep 24 13:39 .
drwxr-xr-x@ 82 chrisren  wheel  2624 Sep 24 13:39 ..

/tmp/tokeff-regate/f2/review/:
total 8
dr-xr-xr-x@  3 chrisren  wheel   96 Sep 24 12:36 .
drwxr-xr-x@ 10 chrisren  wheel  320 Sep 24 13:39 ..
-r--r--r-
3. `Write: {"file_path": "/tmp/tokeff-regate/f2/out/B06-r5/answer.md", "content": "# Review: /tmp/tokeff-regate/f2/review/rotate-logs.sh\n\nMethod: I read the 12-line script. I did not run it. Behaviour below comes from bash, find, tail, xargs and gzip semantics.\n\nReal bugs, most severe first:\n\n1. **Line 5`
   → File created successfully at: /tmp/tokeff-regate/f2/out/B06-r5/answer.md (file state is current in your context — no need to Read it back)
4. `StructuredOutput: {"answer_path": "/tmp/tokeff-regate/f2/out/B06-r5/answer.md", "headline": "I found 6 real bugs in rotate-logs.sh, worst first (read only, not run): an unchecked, unquoted cd (line 5) that can gzip and delete files in the wrong directory; an off-by-one in tail (line 11) that keeps only keep-1 archive`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
