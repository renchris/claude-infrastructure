# Dossier 5

## Brief
```
Review /tmp/tokeff-regate/f2/review/rotate-logs.sh for bugs. List each real bug with the line, what goes wrong, and a one-line fix. Do not list style nits separately from real bugs; rank by severity. Do not run the script. numbers: {"bugs": <how many real bugs>}.
```

## Returned headline
rotate-logs.sh has 9 real bugs. The worst is that `cd $dir` is never checked, so a missing or bad directory makes the script gzip and delete files in $HOME or wherever it was run from. Next: the prune deletes every .gz in the directory, `tail -n +$keep` keeps one archive too few, and archive names collide so each log rotates only once.

## Returned numbers
`{"bugs": 9}`

## answer.md
# rotate-logs.sh review: 9 real bugs, ranked by severity

1. **Line 5, `cd $dir`: the result is unchecked and the variable is unquoted (critical).** If `$1` is missing, `cd` with no argument goes to `$HOME`. If `cd` fails (typo, no permission, space in the path), the script keeps running in whatever directory it was in. Either way it then gzips that directory's `*.log` files and `rm`s its `*.gz` files.
   Fix: `[ -n "$1" ] || { echo "usage: $0 <dir> [keep]" >&2; exit 2; }; cd -- "$1" || exit 1`

2. **Line 11, `ls -t *.gz`: prunes every `.gz` in the directory, not just rotated logs (high).** Any unrelated archive (a backup, a download) past the newest N gets deleted.
   Fix: `ls -t -- *.log*.gz` (match only the names this script creates).

3. **Line 11, `tail -n +$keep`: off by one, keeps `keep-1` archives (high).** `tail -n +N` prints from line N onwards, so the Nth-newest archive is deleted. With the default of 5, only 4 survive. `keep=1` keeps 0.
   Fix: `tail -n +"$((keep + 1))"` (and check that `keep` is a non-negative integer first).

4. **Line 8, `gzip "$f"`: archive names collide, so a log rotates only once (high).** `app.log` becomes `app.log.gz`. The next time a new `app.log` is rotated, `app.log.gz` already exists. Non-interactive gzip refuses to overwrite, so the log is never rotated again and grows without bound. It also means there is only ever one archive per log, so "keep newest N" does nothing.
   Fix: `mv -- "$f" "$f.$(date +%Y%m%d-%H%M%S)" && gzip -- "$f".*[0-9]` (give each archive a timestamp suffix).

5. **Line 7, `find "$f" -mtime +1`: the age threshold is wrong (medium).** `find` truncates age to whole days, so `-mtime +1` means at least 2 days old, not "older than 1 day". Logs that are 1–2 days old are skipped.
   Fix: `-mtime +0`, or `-mmin +1440`.

6. **Line 7, `[ $(find ...) ]`: the command substitution is unquoted (medium).** For a filename containing spaces, find's output splits into several words. `[ a b ]` then fails with "binary operator expected" or evaluates the wrong expression, so the file is silently skipped or misjudged.
   Fix: `if [ -n "$(find "$f" -mtime +0)" ]; then`. Better still, put the whole loop in one call: `find . -maxdepth 1 -name '*.log' -mtime +0 -exec gzip -- {} +`.

7. **Line 6, `for f in $(ls *.log)`: filenames are word-split and glob-expanded (medium).** `my app.log` becomes `my` and `app.log`, neither of which exists. A name containing `*` expands again. A name starting with `-` is read as an option by `find` or `gzip`.
   Fix: `for f in ./*.log; do [ -e "$f" ] || continue; ...`

8. **Line 11, `| xargs rm -f`: xargs splits on whitespace and quotes (medium).** An archive named `old app.log.gz` becomes `rm -f old app.log.gz`, which deletes the wrong paths or none. An apostrophe in a name makes xargs abort.
   Fix: `ls -t -- *.log*.gz | tail -n +"$((keep+1))" | while IFS= read -r g; do rm -f -- "$g"; done` (or `find ... -print0 | ... | xargs -0`).

9. **Line 8: a log that is still being written loses data (medium, depends on the environment).** `gzip` unlinks the original. A process holding the log open keeps writing to the deleted inode, so every line written after rotation is lost until that process reopens the file.
   Fix: `cp -p -- "$f" "$f.$ts" && : > "$f" && gzip -- "$f.$ts"` (copy then truncate), or signal the writer to reopen its log.

Minor, not counted: line 12 prints "rotated logs" unconditionally, even when gzip or rm failed. Fix: add `set -u`, track failures, and exit non-zero.


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
2. `Bash: {"command": "mkdir -p /tmp/tokeff-regate/f2/out/B06-r7 && cat > /tmp/tokeff-regate/f2/out/B06-r7/answer.md <<'EOF'\n# rotate-logs.sh review: 9 real bugs, ranked by severity\n\n1. **Line 5, `cd $dir`: the result is unchecked and the variable is unquoted (critical).** If `$1` is missing, `cd` with no `
   → (Bash completed with no output)
3. `StructuredOutput: {"answer_path": "/tmp/tokeff-regate/f2/out/B06-r7/answer.md", "headline": "rotate-logs.sh has 9 real bugs. The worst is that `cd $dir` is never checked, so a missing or bad directory makes the script gzip and delete files in $HOME or wherever it was run from. Next: the prune deletes every .gz in the`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
