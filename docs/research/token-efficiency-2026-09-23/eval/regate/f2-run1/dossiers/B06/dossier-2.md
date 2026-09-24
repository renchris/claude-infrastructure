# Dossier 2

## Brief
```
Review /tmp/tokeff-regate/f2/review/rotate-logs.sh for bugs. List each real bug with the line, what goes wrong, and a one-line fix. Do not list style nits separately from real bugs; rank by severity. Do not run the script. numbers: {"bugs": <how many real bugs>}.
```

## Returned headline
By reading rotate-logs.sh without running it, I found 7 real bugs. The worst is on line 5: the script doesn't check that `cd $dir` worked and doesn't quote it, so line 11 can delete *.gz files in the wrong directory. Next come an off-by-one in `tail -n +$keep` that keeps one archive too few, an over-broad *.gz glob, xargs breaking on whitespace, looping over parsed `ls` output, `-mtime +1` meaning 2 or more days, and an unquoted `[ $(find ...) ]` test.

## Returned numbers
`{"bugs": 7}`

## answer.md
# Review: /tmp/tokeff-regate/f2/review/rotate-logs.sh

I read the script but did not run it. The findings below come from reading the code. There are 7 real bugs, ranked by severity.

1. **Line 5, `cd $dir`: the script does not check that `cd` worked and does not quote `$dir` (can lose data).** If `<dir>` is missing, misspelled or unreadable, `cd` fails and the script carries on in the caller's current directory. If the argument is omitted, `cd` goes to `$HOME`. Either way, line 11 then deletes `*.gz` files in the wrong directory. A path with spaces also breaks, because `$dir` is unquoted.
   Fix: `[ -n "$dir" ] || { echo "usage: $0 <dir> [keep]" >&2; exit 2; }; cd -- "$dir" || exit 1`

2. **Line 11, `tail -n +$keep`: keeps one archive too few.** `tail -n +N` starts printing at line N, so the newest `keep-1` files survive and everything from the `keep`-th newest onward is deleted. With the default of 5, only 4 archives are kept. With `keep=1`, all of them are deleted.
   Fix: `tail -n +"$((keep + 1))"`

3. **Line 11, `*.gz`: the glob is too broad.** It picks up every `.gz` file in the directory, such as `backup.tar.gz` or unrelated archives, not just the rotated logs. Those files get counted toward `keep` and deleted.
   Fix: `ls -t -- *.log.gz`

4. **Line 11, `| xargs rm -f`: breaks on filenames with whitespace or quotes.** `xargs` splits on blanks and interprets quotes. `my app.log.gz` becomes `my` and `app.log.gz`, so the wrong file is removed or the real one is left behind. A quote character makes `xargs` abort.
   Fix: `ls -t -- *.log.gz | tail -n +"$((keep+1))" | while IFS= read -r g; do rm -f -- "$g"; done` (or use `find ... -print0 | xargs -0`)

5. **Line 6, `for f in $(ls *.log)`: parses `ls` output.** Filenames with spaces are split into pieces, so those logs are never rotated. Names containing glob characters get expanded again. When no `*.log` files exist, `ls` prints an error, and names starting with `-` are read as options.
   Fix: `for f in ./*.log; do [ -e "$f" ] || continue`

6. **Line 7, `-mtime +1`: the age test does not match the header.** `find -mtime +1` matches files at least 2 full days old, not "older than 1 day". A log that is 1.5 days old is not rotated.
   Fix: `find "$f" -prune -mtime +0` (or `-mmin +1440`)

7. **Line 7, `[ $(find "$f" -mtime +1) ]`: the substitution is unquoted.** If the path has spaces, or looks like a test operator (`!`, `-n`, `=`), `[` gets several words and fails with "too many arguments" or "binary operator expected", or evaluates the wrong expression. The file is then silently skipped or wrongly gzipped. Once bug 5 is fixed, this is where names with spaces fail.
   Fix: `if [ -n "$(find "$f" -prune -mtime +0)" ]; then` (or replace lines 6-10 with `find . -maxdepth 1 -name '*.log' -type f -mtime +0 -exec gzip -- {} +`)

Not counted separately:
- Line 12 prints success even when `cd`, `gzip` or `rm` failed. Setting `set -u` and checking `gzip`'s exit status would surface these failures.
- `keep` is never checked to be a non-negative integer. A non-numeric value makes `tail` fail, so nothing is pruned.


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
2. `Bash: {"command": "ls -la /tmp/tokeff-regate/f2/review/ /tmp/tokeff-regate/f2/out/B06-r4/ 2>&1", "description": "List review dir and output dir"}`
   → Exit code 1
ls: /tmp/tokeff-regate/f2/out/B06-r4/: No such file or directory
/tmp/tokeff-regate/f2/review/:
total 8
dr-xr-xr-x@ 3 chrisren  wheel   96 Sep 24 12:36 .
drwxr-xr-x@ 9 chrisren  wheel  288 Sep 24 13:07 ..
-r--r--r--@ 1 chrisren  wheel  308 Sep 24 10:27 rotate-logs.sh
3. `Bash: {"command": "mkdir -p /tmp/tokeff-regate/f2/out/B06-r4 && cat > /tmp/tokeff-regate/f2/out/B06-r4/answer.md <<'EOF'\n# Review: /tmp/tokeff-regate/f2/review/rotate-logs.sh\n\nI read the script but did not run it. The findings below come from reading the code. There are 7 real bugs, ranked by severity.`
   → (Bash completed with no output)
4. `StructuredOutput: {"answer_path": "/tmp/tokeff-regate/f2/out/B06-r4/answer.md", "headline": "By reading rotate-logs.sh without running it, I found 7 real bugs. The worst is on line 5: the script doesn't check that `cd $dir` worked and doesn't quote it, so line 11 can delete *.gz files in the wrong directory. Next com`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
