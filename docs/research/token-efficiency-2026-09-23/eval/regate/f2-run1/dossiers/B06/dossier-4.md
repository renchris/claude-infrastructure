# Dossier 4

## Brief
```
Review /tmp/tokeff-regate/f2/review/rotate-logs.sh for bugs. List each real bug with the line, what goes wrong, and a one-line fix. Do not list style nits separately from real bugs; rank by severity. Do not run the script. numbers: {"bugs": <how many real bugs>}.
```

## Returned headline
I found 6 real bugs by reading rotate-logs.sh (not running it). The worst: an unchecked, unquoted `cd` (line 5) can make line 11 delete *.gz files in the wrong directory. Next: line 11 keeps one archive too few (`tail -n +$keep` should use keep+1), and `xargs` splitting on spaces can delete the wrong files. Lower: `-mtime +1` skips logs 24-48 hours old, `$(ls)` breaks names with spaces, and gzip fails silently when the .gz already exists.

## Returned numbers
`{"bugs": 6}`

## answer.md
# rotate-logs.sh review: 6 real bugs, most severe first

I only read the script. I did not run it.

1. **Line 5, `cd $dir` (critical).** `$dir` has no quotes and nothing checks whether `cd` worked. Several things can make it fail: a missing or mistyped directory, a path with spaces, or no argument at all (then plain `cd` goes to `$HOME`). In each case the script keeps running in the wrong directory, and line 11 deletes `*.gz` files there.
   Fix: `cd -- "${dir:?usage: rotate-logs.sh <dir> [keep]}" || exit 1`

2. **Line 11, `tail -n +$keep` (high).** This is off by one. `tail -n +N` prints from line N onward, so the script keeps only the newest `keep-1` archives. With the default of 5 it keeps 4, and with `keep=1` it keeps none.
   Fix: `tail -n +"$((keep + 1))"`

3. **Line 11, `| xargs rm -f` (high).** `xargs` splits its input on spaces and quotes. An archive named `a b.gz` becomes `rm -f a b.gz`, which deletes other files called `a` and `b.gz` and leaves the real archive in place. A quote character in a name makes xargs stop with an error.
   Fix: `ls -t -- *.gz | tail -n +"$((keep+1))" | tr '\n' '\0' | xargs -0 rm -f --`. Better still, build a bash array of names and remove them with `rm -f -- "${old[@]}"`.

4. **Line 7, `find "$f" -mtime +1` (medium).** `-mtime +1` matches files at least 2 whole days old, not "older than 1 day", so logs between 24 and 48 hours old are never rotated. A name that starts with `-` is also read by `find` as an option. The `$(...)` inside `[ ]` has no quotes either, so any output with spaces breaks the test.
   Fix: `if [ -n "$(find "./$f" -prune -mtime +0)" ]; then`

5. **Line 6, `for f in $(ls *.log)` (medium).** Splitting `ls` output on spaces breaks names that contain spaces: `my app.log` becomes `my` and `app.log`, and neither gets rotated. When no `.log` file exists, `ls` prints an error, and names that start with `-` are read as `ls` options.
   Fix: `for f in ./*.log; do [ -e "$f" ] || continue`

6. **Line 8, `gzip "$f"` (low).** If `foo.log.gz` already exists (for example, `foo.log` was rotated before and then written again), gzip refuses to overwrite it when there is no terminal. That log then never rotates, and the script still prints "rotated logs" because it ignores gzip's exit status.
   Fix: `gzip -- "$f" || echo "gzip failed: $f" >&2`. Alternatively, add a date to the archive name, e.g. `gzip -c -- "$f" > "$f.$(date +%F).gz" && rm -- "$f"`.

Other notes that are not counted as bugs: nothing checks that `keep` is a number. Line 11 matches every `*.gz` in the directory, including archives this script did not create.


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
2. `Bash: {"command": "mkdir -p /tmp/tokeff-regate/f2/out/B06-r5 && cat > /tmp/tokeff-regate/f2/out/B06-r5/answer.md <<'EOF'\n# rotate-logs.sh review: 6 real bugs, most severe first\n\nI only read the script. I did not run it.\n\n1. **Line 5, `cd $dir` (critical).** `$dir` has no quotes and nothing checks whe`
   → (Bash completed with no output)
3. `StructuredOutput: {"answer_path": "/tmp/tokeff-regate/f2/out/B06-r5/answer.md", "headline": "I found 6 real bugs by reading rotate-logs.sh (not running it). The worst: an unchecked, unquoted `cd` (line 5) can make line 11 delete *.gz files in the wrong directory. Next: line 11 keeps one archive too few (`tail -n +$ke`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
