# Dossier 1

## Brief
```
Review /tmp/tokeff-gate/f2/review/rotate-logs.sh for bugs. List each real bug with the line, what goes wrong, and a one-line fix. Do not list style nits separately from real bugs; rank by severity. Do not run the script. numbers: {"bugs": <how many real bugs>}.
```

## Returned headline
rotate-logs.sh has 6 real bugs: the worst is that nothing checks `cd $dir` (line 5), so line 11 can delete .gz files in the wrong directory. Line 11 also keeps only keep-1 archives, splits names on whitespace before `rm` and deletes every .gz rather than only log archives; `-mtime +1` (line 7) means 2 days, and the ls loop and unquoted test (lines 6-7) break on unusual file names.

## Returned numbers
`{"bugs": 6}`

## answer.md
Bugs in /tmp/tokeff-gate/f2/review/rotate-logs.sh, most severe first:

1. **Line 5, `cd $dir`**: nothing checks that `cd` worked, and `$dir` is unquoted. If the directory is missing, the path has spaces, or `$1` is not given (bare `cd` goes to `$HOME`), the script keeps going in the wrong directory and line 11 deletes `.gz` files there. Fix: `[ -n "$1" ] || exit 1; cd -- "$dir" || exit 1`.
2. **Line 11, off-by-one retention**: `tail -n +$keep` starts printing at line `keep`, so only `keep-1` archives survive (keep=5 leaves 4, and keep=1 deletes all of them). Fix: `tail -n +$((keep + 1))`.
3. **Line 11, `ls | xargs rm` splits names on whitespace**: an archive named `a b.log.gz` becomes `rm a b.log.gz`, which deletes other files called `a` and `b.log.gz` and misses the real one. Fix: `ls -t -- *.log.gz | tail -n +$((keep + 1)) | tr '\n' '\0' | xargs -0 rm -f --`.
4. **Line 11, `*.gz` is too broad**: it counts and deletes every `.gz` in the directory, not just the log archives this script makes. Fix: use `*.log.gz` instead of `*.gz`.
5. **Line 7, `-mtime +1` means 2 days or more, not "older than 1 day"**: find rounds age down to whole days, so `+1` only matches files at least 48h old. Fix: `find "$f" -mmin +1440` (or `-mtime +0`).
6. **Lines 6-7, the loop and test break on unusual file names**: `$(ls *.log)` word-splits names with spaces. The unquoted `[ $(find ...) ]` then gets several words and fails with "binary operator expected". A name starting with `-` is read by `find` as an option. Fix: `for f in ./*.log; do [ -e "$f" ] || continue; if [ -n "$(find "$f" -mmin +1440)" ]; then gzip -- "$f"; fi; done`.


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
2. `Bash: {"command": "mkdir -p /tmp/tokeff-gate/f2/out/B06-r10 && cat > /tmp/tokeff-gate/f2/out/B06-r10/answer.md <<'EOF'\nBugs in /tmp/tokeff-gate/f2/review/rotate-logs.sh, most severe first:\n\n1. **Line 5, `cd $dir`**: nothing checks that `cd` worked, and `$dir` is unquoted. If the directory is missing, t`
   → (Bash completed with no output)
3. `StructuredOutput: {"answer_path": "/tmp/tokeff-gate/f2/out/B06-r10/answer.md", "headline": "rotate-logs.sh has 6 real bugs: the worst is that nothing checks `cd $dir` (line 5), so line 11 can delete .gz files in the wrong directory. Line 11 also keeps only keep-1 archives, splits names on whitespace before `rm` and d`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
