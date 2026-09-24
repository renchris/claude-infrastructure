# Dossier 6

## Brief
```
Review /tmp/tokeff-gate/f2/review/rotate-logs.sh for bugs. List each real bug with the line, what goes wrong, and a one-line fix. Do not list style nits separately from real bugs; rank by severity. Do not run the script. numbers: {"bugs": <how many real bugs>}.
```

## Returned headline
rotate-logs.sh has 7 real bugs. The worst is the unquoted, unchecked `cd $dir` on line 5, which lets line 11's `rm` delete .gz files in the wrong directory. Line 11 also keeps one archive too few, matches every *.gz rather than just log archives, and mis-splits names in xargs. The rest are `ls` word-splitting (line 6), `-mtime +1` meaning 2+ days (line 7), and gzip refusing to overwrite an existing .gz (line 8).

## Returned numbers
`{"bugs": 7}`

## answer.md
# rotate-logs.sh review: 7 real bugs, ranked by severity

I reviewed it by reading only. I did not run the script.

1. **Line 5, `cd $dir`: critical.** The path is unquoted and nothing checks whether `cd` worked.
   - If `$1` is missing, `cd` goes to `$HOME`.
   - If the path doesn't exist or contains a space, `cd` fails and the script stays in the caller's directory.
   - Either way, line 11 then runs `rm -f` on `.gz` files in the wrong directory.
   - Fix: `[ -n "$1" ] || { echo "usage: $0 <dir> [keep]" >&2; exit 2; }; cd -- "$dir" || exit 1`

2. **Line 11, `tail -n +$keep`: high (off-by-one).** `tail -n +K` starts printing at line K, so only `keep-1` archives survive. With the default of 5, only 4 are kept. With `keep=1`, none are kept.
   - Fix: `tail -n +$((keep + 1))`

3. **Line 11, `ls -t *.gz`: high.** The pattern matches every `.gz` file in the directory, not just rotated logs. Unrelated archives such as backups or tarballs get deleted.
   - Fix: `ls -t -- *.log.gz`

4. **Line 11, `| xargs rm -f`: medium-high.** `xargs` splits on whitespace and treats quotes as special.
   - An archive named `my app.log.gz` becomes `rm -f my app.log.gz`. That deletes an unrelated file called `my` if one exists, and leaves the real archive alone.
   - A name containing an apostrophe makes `xargs` abort.
   - Fix: `... | while IFS= read -r g; do rm -f -- "$g"; done`, or use NUL-separated output from `find -print0 | xargs -0`.

5. **Line 6, `for f in $(ls *.log)`: medium.** The output of `ls` is word-split, so a log named `app 1.log` becomes the two words `app` and `1.log`, and neither gets rotated.
   - If a directory matches `*.log`, `ls` lists that directory's contents instead, and the loop then works on the wrong names.
   - Fix: `for f in ./*.log; do [ -f "$f" ] || continue; ...`

6. **Line 7, `-mtime +1`: medium.** The header says "older than 1 day", but `find -mtime +1` only matches files at least 2 full days old, because `find` rounds age down to whole days. Logs aged 1 to 2 days are never rotated.
   - The unquoted `[ $(find ...) ]` adds a second problem: a matched name with spaces turns into several words, and `[` errors with "too many arguments" or "binary operator expected".
   - Fix: `if [ -n "$(find "$f" -prune -mtime +0)" ]; then`, or use `-mmin +1440`.

7. **Line 8, `gzip "$f"`: medium-low.** If `$f.gz` already exists from an earlier rotation, non-interactive `gzip` refuses to overwrite it. The log is never rotated again, and the failure is silent because the script ignores the exit code.
   - Fix: `gzip -c -- "$f" > "$f.$(date +%Y%m%d%H%M%S).gz" && rm -f -- "$f"` (the timestamp gives each archive a unique name).

Not counted: there's no `set -u` or `set -e`, and the final `echo` reports success whether or not anything worked. Both are style issues; the real harm is already covered by bugs 1 and 7.


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
2. `Bash: {"command": "mkdir -p /tmp/tokeff-gate/f2/out/B06-r6 && cat > /tmp/tokeff-gate/f2/out/B06-r6/answer.md <<'EOF'\n# rotate-logs.sh review: 7 real bugs, ranked by severity\n\nI reviewed it by reading only. I did not run the script.\n\n1. **Line 5, `cd $dir`: critical.** The path is unquoted and nothing`
   → (Bash completed with no output)
3. `StructuredOutput: {"answer_path": "/tmp/tokeff-gate/f2/out/B06-r6/answer.md", "headline": "rotate-logs.sh has 7 real bugs. The worst is the unquoted, unchecked `cd $dir` on line 5, which lets line 11's `rm` delete .gz files in the wrong directory. Line 11 also keeps one archive too few, matches every *.gz rather than`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
