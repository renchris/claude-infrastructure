# Dossier 1

## Brief
```
Review /tmp/tokeff-regate/f2/review/rotate-logs.sh for bugs. List each real bug with the line, what goes wrong, and a one-line fix. Do not list style nits separately from real bugs; rank by severity. Do not run the script. numbers: {"bugs": <how many real bugs>}.
```

## Returned headline
I found 8 real bugs in rotate-logs.sh (by reading the code, not running it). The worst are on line 5, where a missing or failed cd goes unchecked and line 11 then deletes .gz files in the wrong directory, and on line 11, where tail -n +$keep keeps only keep-1 archives, xargs splits filenames on spaces, and the *.gz glob also catches unrelated archives. The rest are a gzip name clash that stops repeat rotation, -mtime +1 meaning 2 days, and unsafe word splitting on lines 6-7.

## Returned numbers
`{"bugs": 8}`

## answer.md
# rotate-logs.sh review

I read the script and did not run it. I found 8 real bugs, counted by reading the code. They are ranked by severity, worst first.

1. **Line 5, `cd $dir`: a failed or empty `cd` goes unchecked (possible data loss).** With no argument, `cd` goes to `$HOME`. If the path does not exist, the script stays in the caller's cwd. A path with spaces is word-split. In each case the script carries on, and line 11 deletes `*.gz` files in the wrong directory.
   Fix: `[ -n "$1" ] || { echo "usage: $0 dir [keep]" >&2; exit 2; }; cd -- "$dir" || exit 1`

2. **Line 11, `tail -n +$keep`: off by one, so one archive too many is deleted.** `tail -n +N` starts printing at line N, so only the newest `keep-1` archives survive. With keep=5, the 5th newest is deleted. With keep=1, every archive is deleted.
   Fix: `tail -n +$((keep + 1))`

3. **Line 11, `| xargs rm -f`: filenames are split on whitespace and quotes.** An archive named `my app.log.gz` becomes `rm -f my app.log.gz`, so it can delete an unrelated file called `my` and leave the real archive in place. A name with quotes can make xargs fail. Parsing `ls` output has the same weakness.
   Fix: `ls -t -- *.log.gz | tail -n +$((keep+1)) | tr '\n' '\0' | xargs -0 rm -f --`. Better still, drop `ls` parsing and use a `find -print0` with a sort by mtime.

4. **Line 11, `*.gz`: the glob is too broad.** It counts and deletes every `.gz` in the directory, not only the rotated logs. Unrelated archives such as backups or tarballs are pruned, and they also use up the `keep` slots.
   Fix: `ls -t -- *.log.gz`

5. **Line 8, `gzip "$f"`: a name collision blocks the next rotation.** After `app.log` is rotated once, `app.log.gz` exists. The next time `app.log` is old enough, gzip refuses without a tty ("already exists; not overwritten"), so the log is never compressed again. Adding `-f` instead would overwrite, and lose, the older archive.
   Fix: `gzip -c -- "$f" > "$f.$(date +%Y%m%d%H%M%S).gz" && rm -- "$f"`. The line 11 glob then becomes `*.log.*.gz`.

6. **Line 7, `-mtime +1`: this means "older than 2 days", not 1.** find rounds age down to whole 24h periods, and `+1` means more than 1 full period, so at least 48h. Files between 24h and 48h old are skipped, which contradicts the header comment.
   Fix: `find "$f" -prune -mtime +0` (or `-mmin +1440`)

7. **Line 6, `for f in $(ls *.log)`: word splitting and an empty-glob failure.** `my app.log` becomes two words, `my` and `app.log`, and neither exists. With no `.log` files, `ls` prints an error. A file whose name starts with `-` is read as an `ls` option.
   Fix: `shopt -s nullglob; for f in ./*.log; do`

8. **Line 7, `[ $(find ...) ]`: the command substitution is unquoted.** A matched filename with spaces expands to several words, so you get `[: too many arguments` and that file is never gzipped. A name that looks like a test operator can also be misread.
   Fix: `if [ -n "$(find "$f" -prune -mtime +0)" ]; then`. Or replace lines 6-10 with `find . -maxdepth 1 -name '*.log' -type f -mtime +0 -exec gzip -- {} +`, which still needs the collision fix from bug 5.

Low-severity items folded in (not counted): `keep` is not validated, so a non-numeric value makes `tail` error out and nothing is pruned. Line 12 prints "rotated" even when steps failed, because nothing checks errors (`set -euo pipefail` is missing).


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
2. `Bash: {"command": "mkdir -p /tmp/tokeff-regate/f2/out/B06-r1 && cat > /tmp/tokeff-regate/f2/out/B06-r1/answer.md <<'EOF'\n# rotate-logs.sh review\n\nI read the script and did not run it. I found 8 real bugs, counted by reading the code. They are ranked by severity, worst first.\n\n1. **Line 5, `cd $dir`: `
   → (Bash completed with no output)
3. `StructuredOutput: {"answer_path": "/tmp/tokeff-regate/f2/out/B06-r1/answer.md", "headline": "I found 8 real bugs in rotate-logs.sh (by reading the code, not running it). The worst are on line 5, where a missing or failed cd goes unchecked and line 11 then deletes .gz files in the wrong directory, and on line 11, wher`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
