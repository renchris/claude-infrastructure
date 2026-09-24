# Dossier 4

## Brief
```
Review /tmp/tokeff-gate/f2/review/rotate-logs.sh for bugs. List each real bug with the line, what goes wrong, and a one-line fix. Do not list style nits separately from real bugs; rank by severity. Do not run the script. numbers: {"bugs": <how many real bugs>}.
```

## Returned headline
rotate-logs.sh has 7 real bugs; the worst is that nothing checks whether `cd $dir` (unquoted) worked, so a missing directory or argument makes it gzip and delete files in the current directory or $HOME. Next: the `tail -n +$keep` off-by-one keeps only keep-1 archives, `*.gz` deletes unrelated archives, xargs and `$(ls)` split filenames on spaces, `-mtime +1` really means 2 or more days, and gzip fails when an archive with the same name already exists.

## Returned numbers
`{"bugs": 7}`

## answer.md
# rotate-logs.sh: bugs, most severe first

1. **Line 5, `cd $dir`**: nothing checks whether the `cd` worked, and `$dir` is unquoted. If the directory is missing, the script keeps going in the current directory. If no argument is given, bare `cd` goes to `$HOME`. Either way, lines 6-11 then gzip and delete files in the wrong directory. A path with spaces also breaks the `cd`. Fix: `cd -- "${1:?usage: rotate-logs.sh <dir> [keep]}" || exit 1`.
2. **Line 11, `tail -n +$keep`**: off by one. `tail -n +N` starts printing at line N, so only `keep-1` archives survive. With the default of 5, the script keeps 4. Fix: `tail -n +$((keep + 1))`.
3. **Line 11, `ls -t *.gz`**: the glob matches every `.gz` file in the directory, not only rotated logs. Unrelated archives get counted and deleted. Fix: use `*.log.gz` instead of `*.gz`.
4. **Line 11, `| xargs rm -f`**: xargs splits on whitespace and treats quotes specially. For an archive named `my app.log.gz`, it runs `rm -f my app.log.gz`, which can delete an unrelated file named `my` and leaves the real archive in place. Fix: `ls -t -- *.log.gz | tail -n +$((keep + 1)) | tr '\n' '\0' | xargs -0 rm -f --`.
5. **Lines 6-7, `for f in $(ls *.log)` / `[ $(find "$f" ...) ]`**: filenames get word-split, and the command substitution in the test is unquoted. `my app.log` becomes two words, `my` and `app.log`. The real file is never rotated, and a stray old file named `my` would be gzipped. If only line 6 is fixed, line 7 then fails with `[: too many arguments`. Fix: replace lines 6-10 with `find . -maxdepth 1 -type f -name '*.log' -mtime +0 -exec gzip -- {} +`.
6. **Line 7, `-mtime +1`**: find rounds file age down to whole days, so `+1` only matches files at least 2 days old. Files between 1 and 2 days old are skipped, which does not match "older than 1 day". Fix: use `-mtime +0`, or `-mmin +1440`.
7. **Line 8, `gzip "$f"`**: log names are usually reused. Once `app.log.gz` exists, the next rotation of `app.log` fails with "already exists; not overwritten" when there is no terminal, so that log never rotates again. On a terminal, gzip stops to ask. Fix: `gzip -c -- "$f" > "${f%.log}.$(date +%Y%m%d%H%M%S).log.gz" && rm -- "$f"`. These names still match the `*.log.gz` glob from fix 3.


## Tool calls (5) with the first 300 chars of each result
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
2. `Bash: {"command": "ls -la /tmp/tokeff-gate/f2/out/B06-r11/ /tmp/tokeff-gate/f2/review/ 2>&1", "description": "List output and review directories"}`
   → /tmp/tokeff-gate/f2/out/B06-r11/:
total 0
drwxr-xr-x@   2 chrisren  wheel    64 Sep 24 11:31 .
drwxr-xr-x@ 102 chrisren  wheel  3264 Sep 24 11:31 ..

/tmp/tokeff-gate/f2/review/:
total 8
dr-xr-xr-x@  3 chrisren  wheel   96 Sep 24 10:27 .
drwxr-xr-x@ 10 chrisren  wheel  320 Sep 24 10:31 ..
-r--r--r--
3. `Bash: {"command": "cat > /tmp/tokeff-gate/f2/out/B06-r11/answer.md <<'EOF'\n# rotate-logs.sh: bugs, most severe first\n\n1. **Line 5, `cd $dir`**: nothing checks whether the `cd` worked, and `$dir` is unquoted. If the directory is missing, the script keeps going in the current directory. If no argument is`
   →        9
4. `Bash: {"command": "cd /tmp/tokeff-gate/f2/out/B06-r11 && python3 - <<'EOF'\np='answer.md'\ns=open(p).read()\nold='Fix: `gzip -c -- \"$f\" > \"$f.$(date +%Y%m%d%H%M%S).gz\" && rm -- \"$f\"`. Line 11 still matches these names with `*.log.gz` if the glob becomes `*.log*.gz`.'\nnew='Fix: `gzip -c -- \"$f\" > `
   → 6. **Line 7, `-mtime +1`**: find rounds file age down to whole days, so `+1` only matches files at least 2 days old. Files between 1 and 2 days old are skipped, which does not match "older than 1 day". Fix: use `-mtime +0`, or `-mmin +1440`.
7. **Line 8, `gzip "$f"`**: log names are usually reused. 
5. `StructuredOutput: {"answer_path": "/tmp/tokeff-gate/f2/out/B06-r11/answer.md", "headline": "rotate-logs.sh has 7 real bugs; the worst is that nothing checks whether `cd $dir` (unquoted) worked, so a missing directory or argument makes it gzip and delete files in the current directory or $HOME. Next: the `tail -n +$ke`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
