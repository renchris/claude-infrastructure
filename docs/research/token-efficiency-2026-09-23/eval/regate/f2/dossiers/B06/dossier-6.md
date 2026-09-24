# Dossier 6

## Brief
```
Review /tmp/tokeff-regate/f2/review/rotate-logs.sh for bugs. List each real bug with the line, what goes wrong, and a one-line fix. Do not list style nits separately from real bugs; rank by severity. Do not run the script. numbers: {"bugs": <how many real bugs>}.
```

## Returned headline
A static read of rotate-logs.sh found 6 real bugs (none run or measured): the worst is that an unchecked, unquoted `cd $dir` can gzip logs and delete archives in $HOME or the current directory; `tail -n +$keep` is off by one and keeps only keep-1 archives; xargs splits names on whitespace and can delete the wrong files; `-mtime +1` skips logs 24-48h old; the loop and test break on names with spaces or a leading dash; and gzip refuses to overwrite an existing .gz, so rotation never builds a history.

## Returned numbers
`{"bugs": 6}`

## answer.md
# rotate-logs.sh review (static read only; the script was not run)

The bugs are ranked by severity. Every finding comes from reading the 12-line script; none was measured.

1. **Line 5: `cd $dir` is unquoted and unchecked. Critical.** If `$1` is missing, `cd` with no argument goes to `$HOME`. If the directory doesn't exist or has spaces in its name, `cd` fails and the script keeps running in the current directory. Either way it then gzips `*.log` and **deletes `*.gz` archives in the wrong directory**.
   Fix: `[ -n "$dir" ] || { echo "usage: $0 <dir> [keep]" >&2; exit 1; }; cd -- "$dir" || exit 1`

2. **Line 11: `tail -n +$keep` is off by one. High.** `tail -n +N` starts printing at line N, so it keeps only `keep-1` archives. With the default of 5, only 4 are kept and one extra archive is deleted on every run. With `keep=1`, all archives are deleted.
   Fix: `tail -n +$((keep + 1))`

3. **Line 11: `ls ... | xargs rm -f` splits on whitespace. High (can delete the wrong files).** An archive named `app 2.log.gz` becomes `rm -f app 2.log.gz`, which removes unrelated files `app` and `2.log.gz` and misses the real one. Quotes and backslashes in names also break xargs.
   Fix: `ls -t -- *.gz | tail -n +$((keep+1)) | while IFS= read -r g; do rm -f -- "$g"; done`

4. **Line 7: `-mtime +1` means at least 2 days old, not "older than 1 day". Medium.** find truncates file age to whole days, and `+1` means more than 1 whole day, which is 2 or more. Logs between 24 and 48 hours old are skipped, so the documented contract is broken.
   Fix: `find ... -mtime +0` (or `-mmin +1440`)

5. **Lines 6–7: word-splitting and option injection in the loop and test. Medium.** `for f in $(ls *.log)` splits names that contain spaces into separate words, so each fragment goes to `find` and `gzip`. `[ $(find "$f" ...) ]` is unquoted, so a matching name with spaces gives `[: too many arguments`, and that file is silently not rotated. A name starting with `-` is parsed as an option or expression by `find`.
   Fix: `for f in ./*.log; do [ -e "$f" ] || continue; if [ -n "$(find "$f" -mtime +0)" ]; then gzip -- "$f"; fi; done`

6. **Line 8: gzip fails if the target name already exists. Medium.** Once `app.log.gz` exists, the next time `app.log` is old enough gzip prints "already exists; not overwritten" and leaves `app.log` uncompressed. Only one archive per log name can ever exist, so the "keep newest N" rotation never builds a history.
   Fix: `gzip -c -- "$f" > "$f.$(date +%Y%m%d%H%M%S).gz" && rm -f -- "$f"`

Lesser issues:
- `keep` is never checked to be a non-negative integer. For example, `keep=abc` makes `tail` error out, so nothing is pruned.
- If no `*.gz` files exist, `ls` prints an error.
- There is no error handling, so the line 12 success message prints even when steps fail. Fix: use `set -euo pipefail` together with the explicit checks above.


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
2. `Bash: {"command": "mkdir -p /tmp/tokeff-regate/f2/out/B06-r8 && cat > /tmp/tokeff-regate/f2/out/B06-r8/answer.md <<'EOF'\n# rotate-logs.sh review (static read only; the script was not run)\n\nThe bugs are ranked by severity. Every finding comes from reading the 12-line script; none was measured.\n\n1. **L`
   → (Bash completed with no output)
3. `StructuredOutput: {"answer_path": "/tmp/tokeff-regate/f2/out/B06-r8/answer.md", "headline": "A static read of rotate-logs.sh found 6 real bugs (none run or measured): the worst is that an unchecked, unquoted `cd $dir` can gzip logs and delete archives in $HOME or the current directory; `tail -n +$keep` is off by one `
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
