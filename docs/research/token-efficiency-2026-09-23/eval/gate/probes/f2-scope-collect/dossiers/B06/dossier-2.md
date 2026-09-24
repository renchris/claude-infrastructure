# Dossier 2

## Brief
```
Review /tmp/tokeff-gate/f2/review/rotate-logs.sh for bugs. List each real bug with the line, what goes wrong, and a one-line fix. Do not list style nits separately from real bugs; rank by severity. Do not run the script. numbers: {"bugs": <how many real bugs>}.
```

## Returned headline
rotate-logs.sh has 6 real bugs. The worst is that `cd $dir` on line 5 is unchecked, so the rm on line 11 can delete .gz files in the wrong directory. The others: an off-by-one in `tail -n +$keep` keeps one archive too few, gzip skips any log whose .gz name already exists, word splitting in the loop and `[ $(find) ]` test, xargs breaking on whitespace in names, and a `-mtime +1` test that only matches files 48 or more hours old.

## Returned numbers
`{"bugs": 6}`

## answer.md
Bugs in /tmp/tokeff-gate/f2/review/rotate-logs.sh, most severe first:

1. **Line 5, `cd $dir`: the `cd` is unquoted and never checked.** If `$dir` is missing, mistyped or contains spaces, `cd` fails and the script keeps going in the caller's current directory. If no argument is given, `cd` goes to `$HOME`. Either way, line 11 then deletes `*.gz` files in the wrong directory. Fix: `cd -- "$dir" || exit 1`.
2. **Line 11, `tail -n +$keep`: off by one.** `tail -n +N` starts output at line N, so it keeps only `keep-1` archives. With the default of 5, it keeps 4. Fix: `tail -n +$((keep + 1))`.
3. **Line 8, `gzip "$f"`: archive-name collision.** After the first run, `app.log` becomes `app.log.gz`. On the next run, gzip finds `app.log.gz` already there and skips the file without a prompt ("already exists; not overwritten"). So a log with a fixed name is never rotated again and keeps growing. Adding `-f` would instead overwrite the old archive. Fix: `gzip -c -- "$f" > "$f.$(date +%Y%m%d%H%M%S).gz" && rm -- "$f"`.
4. **Lines 6–7, `for f in $(ls *.log)` and unquoted `[ $(find "$f" ...) ]`: word splitting.** A name with spaces is split into pieces that don't exist, so gzip fails or the file is skipped. Once `find` prints such a name, `[ ... ]` gets several words and errors with "binary operator expected". A name starting with `-` is read by `find` as an option. Fix: `for f in ./*.log; do [ -e "$f" ] || continue; if [ -n "$(find "$f" -mtime +0)" ]; then`.
5. **Line 11, `ls -t *.gz | ... | xargs rm -f`: whitespace in names.** `xargs` splits on spaces and quotes. An archive name with a space makes `rm` target the wrong paths or none at all, and a stray quote aborts `xargs`. Fix: `ls -t -- *.gz | tail -n +$((keep + 1)) | tr '\n' '\0' | xargs -0 rm -f --`.
6. **Line 7, `-mtime +1`: wrong age threshold.** `find` rounds age down to whole days, and `+1` means "more than 1", so only files at least 48 hours old match, not files older than one day as the header says. Fix: use `-mtime +0`, or `-mmin +1440`.


## Tool calls (3) with the first 300 chars of each result
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
2. `Bash: {"command": "mkdir -p /tmp/tokeff-gate/f2/out/B06-r9 && cat > /tmp/tokeff-gate/f2/out/B06-r9/answer.md <<'EOF'\nBugs in /tmp/tokeff-gate/f2/review/rotate-logs.sh, most severe first:\n\n1. **Line 5, `cd $dir`: the `cd` is unquoted and never checked.** If `$dir` is missing, mistyped or contains spaces`
   → (Bash completed with no output)
3. `StructuredOutput: {"answer_path": "/tmp/tokeff-gate/f2/out/B06-r9/answer.md", "headline": "rotate-logs.sh has 6 real bugs. The worst is that `cd $dir` on line 5 is unchecked, so the rm on line 11 can delete .gz files in the wrong directory. The others: an off-by-one in `tail -n +$keep` keeps one archive too few, gzip`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
