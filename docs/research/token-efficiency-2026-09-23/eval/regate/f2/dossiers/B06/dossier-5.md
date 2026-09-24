# Dossier 5

## Brief
```
Review /tmp/tokeff-regate/f2/review/rotate-logs.sh for bugs. List each real bug with the line, what goes wrong, and a one-line fix. Do not list style nits separately from real bugs; rank by severity. Do not run the script. numbers: {"bugs": <how many real bugs>}.
```

## Returned headline
rotate-logs.sh has 7 real bugs. The worst is that `cd $dir` is never checked, so a missing or bad argument makes line 11 delete .gz files in $HOME or the caller's directory. After that: gzip collides with its own previous archive, so each log rotates only once; `tail -n +$keep` keeps one archive too few; xargs splits names on whitespace and can delete the wrong files; `$(ls *.log)` mangles file names; `-mtime +1` means at least 48 hours, not one day; and the unquoted `[ $(find ...) ]` test fails on names with spaces.

## Returned numbers
`{"bugs": 7}`

## answer.md
# rotate-logs.sh review — 7 real bugs, ranked by severity

Reviewed by reading only; the script was not run.

1. **Line 5, `cd $dir`: critical, can delete files in the wrong directory.** Nothing checks the `cd` and `$dir` is unquoted. If no argument is passed, bare `cd` goes to `$HOME`. If the directory is missing, or its name has spaces, the `cd` fails and the script keeps going in the caller's cwd. Either way, line 11 then deletes `*.gz` files in a directory nobody pointed it at.
   Fix: `[ -n "$1" ] || { echo "usage: $0 <dir> [keep]" >&2; exit 2; }; cd -- "$dir" || exit 1`

2. **Line 8, `gzip "$f"`: high, a log is rotated only once.** The archive name is always `<name>.log.gz`. The second time `app.log` is rotated, `app.log.gz` already exists. With no tty, gzip refuses to overwrite it and skips the file, so `app.log` grows without limit. The keep-N logic also has nothing to keep, because each log only ever gets one archive.
   Fix: `gzip -c -- "$f" > "$f.$(date +%Y%m%d%H%M%S).gz" && rm -f -- "$f"`

3. **Line 11, `tail -n +$keep`: high, keeps one archive too few.** `tail -n +N` starts printing at line N, so only the first N-1 names are spared. With the default of 5, only 4 archives are kept. With `keep=1`, none are kept.
   Fix: `tail -n +$((keep + 1))`

4. **Line 11, `... | xargs rm -f`: high, can delete the wrong files.** xargs splits its input on whitespace and quotes. An archive called `my app.log.gz` becomes `rm -f my app.log.gz`, which deletes an unrelated file named `my` and misses the real archive. A quote character in a name makes xargs abort.
   Fix: `ls -t -- *.gz | tail -n +$((keep+1)) | while IFS= read -r g; do rm -f -- "$g"; done` (or `tr '\n' '\0' | xargs -0 rm -f --`)

5. **Line 6, `for f in $(ls *.log)`: medium, file names are mangled.** Parsing `ls` output splits names on whitespace, so `my app.log` becomes two items, `my` and `app.log`, and neither exists. A name starting with `-` is read by `ls` as an option. When there are no `.log` files, the literal `*.log` goes through the loop and produces errors.
   Fix: `for f in ./*.log; do [ -f "$f" ] || continue; ...`

6. **Line 7, `-mtime +1`: medium, the age test is off by a day.** `find -mtime +1` matches files whose age, rounded down to whole days, is more than 1. That means at least 48 hours, not "older than 1 day" as the header says. Logs between 24 and 48 hours old are never rotated.
   Fix: use `-mtime +0` (or `-mmin +1440`).

7. **Line 7, `if [ $(find "$f" ...) ]`: medium, the test fails on some names.** The command substitution is unquoted. After bug 5 is fixed, a name with spaces produces `[ my app.log ]`. That is a `test` syntax error (exit 2), which reads as false, so the file is never rotated. A name starting with `-` is also read by `find` as a primary.
   Fix: `if [ -n "$(find "./$f" -prune -mtime +0)" ]; then` (or `find . -maxdepth 1 -name '*.log' -mtime +0 -exec gzip {} +`)

## Minor, not counted
- Nothing checks that `keep` is a number. A non-numeric value makes `tail` fail, so nothing is pruned.
- With no `*.gz` files, `ls` prints an error to stderr.
- Line 12 prints "rotated" even when earlier steps failed. `set -euo pipefail` would make failures visible.


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
2. `Bash: {"command": "mkdir -p /tmp/tokeff-regate/f2/out/B06-r7 && cat > /tmp/tokeff-regate/f2/out/B06-r7/answer.md <<'EOF'\n# rotate-logs.sh review — 7 real bugs, ranked by severity\n\nReviewed by reading only; the script was not run.\n\n1. **Line 5, `cd $dir`: critical, can delete files in the wrong direct`
   → (Bash completed with no output)
3. `StructuredOutput: {"answer_path": "/tmp/tokeff-regate/f2/out/B06-r7/answer.md", "headline": "rotate-logs.sh has 7 real bugs. The worst is that `cd $dir` is never checked, so a missing or bad argument makes line 11 delete .gz files in $HOME or the caller's directory. After that: gzip collides with its own previous arc`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
