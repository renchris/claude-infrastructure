# Dossier 6

## Brief
```
Review /tmp/tokeff-regate/f2/review/rotate-logs.sh for bugs. List each real bug with the line, what goes wrong, and a one-line fix. Do not list style nits separately from real bugs; rank by severity. Do not run the script. numbers: {"bugs": <how many real bugs>}.
```

## Returned headline
rotate-logs.sh has 7 real bugs; the worst are an unchecked cd that can rotate and delete files in the wrong directory, an off-by-one in tail that deletes one archive too many, and xargs splitting filenames so rm can delete the wrong files.

## Returned numbers
`{"bugs": 7}`

## answer.md
# Review: /tmp/tokeff-regate/f2/review/rotate-logs.sh

I read the script and did not run it. It has 7 real bugs, listed from most to least severe.

1. **Line 5, `cd $dir`: nothing checks whether the `cd` worked, and `$dir` is unquoted. Critical.**
   If `<dir>` is missing, misspelled or unreadable, the `cd` fails and the script keeps going in the directory it was started from. It then gzips that directory's `*.log` files and deletes its `*.gz` files. If no argument is given at all, `cd` with no argument goes to `$HOME` and rotates the logs there. A path containing spaces gets split into several words. At the end, line 12 still prints "rotated logs" either way.
   Fix: `[ -n "$1" ] || { echo "usage: $0 <dir> [keep]" >&2; exit 2; }; cd -- "$dir" || exit 1`

2. **Line 11, `tail -n +$keep`: off by one, so it deletes one archive too many. High (data loss).**
   `tail -n +N` starts printing at line N, so it skips only N-1 lines. With the default `keep=5`, only the newest 4 archives survive. With `keep=1` or `keep=0`, every archive is deleted.
   Fix: `tail -n +$((keep + 1))`

3. **Line 11, `ls -t *.gz | ... | xargs rm -f`: filenames are split on spaces, quotes and backslashes. High (can delete the wrong files).**
   `xargs` splits its input on whitespace and treats quotes and backslashes specially. An archive named `old app.log.gz` therefore becomes `rm -f old app.log.gz`. That deletes unrelated files named `old` and `app.log.gz`, and leaves the real archive in place. A name containing a quote makes `xargs` abort.
   Fix: `ls -t -- *.log.gz 2>/dev/null | tail -n +$((keep + 1)) | while IFS= read -r g; do rm -f -- "$g"; done`

4. **Line 7, `find "$f" -mtime +1`: the age cutoff is wrong. Medium.**
   `find` rounds file age down to whole days, so `-mtime +1` means "at least 2 days old", not "older than 1 day". Logs between 24 and 48 hours old are never rotated.
   Fix: `find "./$f" -maxdepth 0 -mmin +1440` (or `-mtime +0`)

5. **Lines 6-7, `for f in $(ls *.log)` and the unquoted `[ $(...) ]`: filenames get split, and an empty match is mishandled. Medium.**
   Splitting the `ls` output breaks `my app.log` into `my` and `app.log`, so the real file is never rotated. When nothing matches, `ls` prints an error. The `[ $(find ...) ]` test is unquoted, so any output of more than one word causes a `[` syntax error. A name starting with `-` is read by `find` as an option.
   Fix: `for f in ./*.log; do [ -e "$f" ] || continue; if [ -n "$(find "$f" -maxdepth 0 -mmin +1440)" ]; then gzip -- "$f"; fi; done`

6. **Line 8, `gzip "$f"`: the archive name is the same every time, so the second rotation collides. Medium.**
   `app.log` always becomes `app.log.gz`. On the next run, `app.log.gz` already exists. `gzip` then either stops to ask whether to overwrite (on a terminal) or skips the file with a warning (e.g. under cron). The log is never rotated again. This also means only one archive per log ever exists, so the "keep N" logic in bug 2 has nothing to count.
   Fix: `ts=$(date +%Y%m%d%H%M%S); mv -- "$f" "$f.$ts" && gzip -- "$f.$ts"`

7. **Line 11, `*.gz`: the pruning deletes every `.gz` file in the directory, not just the rotated logs. Low-medium.**
   Any other gzip file in `<dir>`, such as database dumps or tarballs, counts toward `keep` and can be deleted.
   Fix: match only rotated logs: `ls -t -- *.log*.gz`


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
2. `Bash: {"command": "ls -la /tmp/tokeff-regate/f2/review/ /tmp/tokeff-regate/f2/out/B06-r8/ 2>&1", "description": "List review dir and output dir"}`
   → Exit code 1
ls: /tmp/tokeff-regate/f2/out/B06-r8/: No such file or directory
/tmp/tokeff-regate/f2/review/:
total 8
dr-xr-xr-x@ 3 chrisren  wheel   96 Sep 24 12:36 .
drwxr-xr-x@ 9 chrisren  wheel  288 Sep 24 13:07 ..
-r--r--r--@ 1 chrisren  wheel  308 Sep 24 10:27 rotate-logs.sh
3. `Bash: {"command": "mkdir -p /tmp/tokeff-regate/f2/out/B06-r8 && cat > /tmp/tokeff-regate/f2/out/B06-r8/answer.md <<'EOF'\n# Review: /tmp/tokeff-regate/f2/review/rotate-logs.sh\n\nI read the script and did not run it. It has 7 real bugs, listed from most to least severe.\n\n1. **Line 5, `cd $dir`: nothing `
   → (Bash completed with no output)
4. `StructuredOutput: {"answer_path": "/tmp/tokeff-regate/f2/out/B06-r8/answer.md", "headline": "rotate-logs.sh has 7 real bugs; the worst are an unchecked cd that can rotate and delete files in the wrong directory, an off-by-one in tail that deletes one archive too many, and xargs splitting filenames so rm can delete th`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
