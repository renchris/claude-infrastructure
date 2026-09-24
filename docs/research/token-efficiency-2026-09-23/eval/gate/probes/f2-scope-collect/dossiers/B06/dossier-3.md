# Dossier 3

## Brief
```
Review /tmp/tokeff-gate/f2/review/rotate-logs.sh for bugs. List each real bug with the line, what goes wrong, and a one-line fix. Do not list style nits separately from real bugs; rank by severity. Do not run the script. numbers: {"bugs": <how many real bugs>}.
```

## Returned headline
rotate-logs.sh has 6 real bugs: the worst is an unchecked `cd` that can gzip logs and delete archives in the wrong directory, then an off-by-one in `tail -n +$keep` that keeps one archive too few, then unsafe whitespace handling in `xargs rm`, `-mtime +1` meaning at least 2 days old, word-splitting of filenames in the loop and test, and gzip failing when an earlier archive of the same name exists.

## Returned numbers
`{"bugs": 6}`

## answer.md
Bugs in /tmp/tokeff-gate/f2/review/rotate-logs.sh, most severe first:

1. **Line 5, `cd $dir`**: nothing checks whether it worked, and `$dir` is unquoted. A missing directory, an empty argument (`cd` with no argument goes to `$HOME`) or a path with spaces leaves the script in the wrong directory. It then gzips logs there, and line 11 deletes `*.gz` files there. Fix: `cd -- "${1:?usage: rotate-logs.sh <dir> [keep]}" || exit 1`.
2. **Line 11, `tail -n +$keep`**: off by one. `tail -n +N` starts printing at line N, so only `keep-1` archives survive. With `keep=1` or `keep=0`, every archive is deleted. Fix: `tail -n +$((keep + 1))`.
3. **Line 11, `ls -t *.gz | ... | xargs rm -f`**: `xargs` splits names on whitespace and quotes. `old log.gz` becomes `rm -f old log.gz`, which can delete an unrelated file called `old` and leaves the archive in place. A quote in a name makes `xargs` abort. Fix: `ls -t -- *.gz | tail -n +$((keep + 1)) | while IFS= read -r g; do rm -f -- "$g"; done`.
4. **Line 7, `find "$f" -mtime +1`**: `-mtime +1` matches files at least 2 whole days old, not files older than 1 day as the header says. Logs that are 24 to 48 hours old never get rotated. Fix: `find "$f" -mmin +1440`.
5. **Lines 6-7, `for f in $(ls *.log)` and `[ $(find ...) ]`**: filenames are split on whitespace, so a log with a space in its name becomes two bogus names and is never rotated. Also, the unquoted `$(find)` inside `[ ]` gives "too many arguments" or a wrong result. Fix: `for f in *.log; do [ -e "$f" ] || continue; if [ -n "$(find "$f" -mmin +1440)" ]; then`.
6. **Line 8, `gzip "$f"`**: the archive name is always `<name>.log.gz`, so the second rotation of the same log hits the existing archive. From cron, gzip refuses and the log is never rotated. On a terminal, it prompts. Fix: `gzip -c -- "$f" > "$f.$(date +%Y%m%d%H%M%S).gz" && rm -- "$f"`.


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
2. `Bash: {"command": "ls -la /tmp/tokeff-gate/f2/out/B06-r12/ 2>&1; ls -la /tmp/tokeff-gate/f2/review/", "description": "Check output dir and review dir contents"}`
   → total 0
drwxr-xr-x@   2 chrisren  wheel    64 Sep 24 11:31 .
drwxr-xr-x@ 102 chrisren  wheel  3264 Sep 24 11:31 ..
total 8
dr-xr-xr-x@  3 chrisren  wheel   96 Sep 24 10:27 .
drwxr-xr-x@ 10 chrisren  wheel  320 Sep 24 10:31 ..
-r--r--r--@  1 chrisren  wheel  308 Sep 24 10:27 rotate-logs.sh
3. `Bash: {"command": "cat > /tmp/tokeff-gate/f2/out/B06-r12/answer.md <<'EOF'\nBugs in /tmp/tokeff-gate/f2/review/rotate-logs.sh, most severe first:\n\n1. **Line 5, `cd $dir`**: nothing checks whether it worked, and `$dir` is unquoted. A missing directory, an empty argument (`cd` with no argument goes to `$H`
   → (Bash completed with no output)
4. `StructuredOutput: {"answer_path": "/tmp/tokeff-gate/f2/out/B06-r12/answer.md", "headline": "rotate-logs.sh has 6 real bugs: the worst is an unchecked `cd` that can gzip logs and delete archives in the wrong directory, then an off-by-one in `tail -n +$keep` that keeps one archive too few, then unsafe whitespace handli`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
