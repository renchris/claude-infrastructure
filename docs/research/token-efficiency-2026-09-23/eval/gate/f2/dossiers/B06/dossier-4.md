# Dossier 4

## Brief
```
Review /tmp/tokeff-gate/f2/review/rotate-logs.sh for bugs. List each real bug with the line, what goes wrong, and a one-line fix. Do not list style nits separately from real bugs; rank by severity. Do not run the script. numbers: {"bugs": <how many real bugs>}.
```

## Returned headline
rotate-logs.sh has 9 real bugs, found by reading the script without running it. The worst is on line 5: the cd is unchecked, so a missing or bad directory makes it gzip and delete files in the wrong place. Next come the keep off-by-one and the over-broad *.gz delete on line 11, and on line 8 gzip refuses once the .gz exists, so a stable-named log never rotates again.

## Returned numbers
`{"bugs": 9}`

## answer.md
# Review: /tmp/tokeff-gate/f2/review/rotate-logs.sh

I read the script but did not run it. The whole file is 12 lines. I found 9 real bugs. They are ranked below by severity, most severe first.

| # | Line | Severity | What goes wrong | One-line fix |
|---|------|----------|-----------------|--------------|
| 1 | 5 | Critical | `cd $dir` has no quotes and no error check. If `$1` is missing, `cd` goes to `$HOME`. If the directory doesn't exist or its path has spaces, `cd` fails and the script carries on in the current directory. Either way it gzips the wrong `*.log` files and runs `rm` on the wrong `*.gz` files. | `[ -n "$1" ] \|\| { echo "usage: $0 <dir> [keep]" >&2; exit 2; }; cd -- "$dir" \|\| exit 1` |
| 2 | 11 | High | Off-by-one. `tail -n +$keep` starts printing at line `$keep`, so only `keep-1` archives survive. The default of 5 keeps 4. | `tail -n +$((keep + 1))` |
| 3 | 11 | High | `*.gz` matches every gzip file in the directory, including ones this script didn't create (backups, tarballs), and deletes them. | `ls -t -- *.log.gz` (or use a dedicated archive name pattern) |
| 4 | 8 | High | `gzip "$f"` fails with "already exists" when `$f.gz` exists. For a log with a stable name like `app.log`, the first rotation creates `app.log.gz`, and every later run fails, so that log is never rotated again. It also means you only ever have one archive per log, so the `keep` logic can't work as described. | `gzip -c -- "$f" > "$f.$(date +%Y%m%d%H%M%S).gz" && rm -- "$f"` |
| 5 | 7 | Medium | `find -mtime +1` means "more than 1 full 24-hour period", so in practice files must be at least 48 h old. The header says "older than 1 day", so files between 24 h and 48 h old are skipped. | `find "$f" -prune -mtime +0` (or `-mmin +1440`) |
| 6 | 7 | Medium | `[ $(find ...) ]` has no quotes. If the name contains spaces, `find` prints several words, `[` fails with "binary operator expected", and the file is skipped. If the name starts with `-`, `find` reads it as an expression or option. | `if [ -n "$(find ./"$f" -prune -mtime +0)" ]; then` |
| 7 | 6 | Medium | `for f in $(ls *.log)` splits file names on whitespace and expands glob characters in them, so names with spaces become separate, non-existent files. | `for f in *.log; do [ -e "$f" ] \|\| continue` |
| 8 | 11 | Medium | `xargs` splits input on whitespace and quote characters. Archive names with spaces or quotes cause `rm` to get the wrong names, or `xargs` stops on an unmatched quote. | `ls -t -- *.log.gz \| tail -n +$((keep+1)) \| tr '\n' '\0' \| xargs -0 rm -f --` |
| 9 | 4 / 11 | Low | `keep` is never validated. `keep=0` gives `tail -n +0`, which prints every line, so every archive is deleted. A non-numeric value makes `tail` fail, so nothing is pruned, and the script still reports success. | `case $keep in ''\|*[!0-9]*) echo "keep must be a number" >&2; exit 2;; esac` |

## Other points (not counted as bugs)
- Line 12 prints "rotated logs" no matter what failed before it. Add `set -u` plus explicit checks, or exit with a non-zero status when something fails.
- When no files match, `ls *.log` and `ls -t *.gz` print "No such file" to stderr. After fixes 7 and 8 this goes away, or you can add `shopt -s nullglob`.
- A simpler overall rewrite would be `find . -maxdepth 1 -name '*.log' -mmin +1440 -exec ...`, which avoids problems 5 to 7 together.


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
2. `Bash: {"command": "ls -la /tmp/tokeff-gate/f2/review/ /tmp/tokeff-gate/f2/out/B06-r5/ 2>&1", "description": "List review and output directories"}`
   → /tmp/tokeff-gate/f2/out/B06-r5/:
total 0
drwxr-xr-x@  2 chrisren  wheel    64 Sep 24 10:27 .
drwxr-xr-x@ 82 chrisren  wheel  2624 Sep 24 10:27 ..

/tmp/tokeff-gate/f2/review/:
total 8
dr-xr-xr-x@ 3 chrisren  wheel   96 Sep 24 10:27 .
drwxr-xr-x@ 9 chrisren  wheel  288 Sep 24 10:27 ..
-r--r--r--@ 1 c
3. `Write: {"file_path": "/tmp/tokeff-gate/f2/out/B06-r5/answer.md", "content": "# Review: /tmp/tokeff-gate/f2/review/rotate-logs.sh\n\nI read the script but did not run it. The whole file is 12 lines. I found 9 real bugs. They are ranked below by severity, most severe first.\n\n| # | Line | Severity | What go`
   → File created successfully at: /tmp/tokeff-gate/f2/out/B06-r5/answer.md (file state is current in your context — no need to Read it back)
4. `StructuredOutput: {"answer_path": "/tmp/tokeff-gate/f2/out/B06-r5/answer.md", "headline": "rotate-logs.sh has 9 real bugs, found by reading the script without running it. The worst is on line 5: the cd is unchecked, so a missing or bad directory makes it gzip and delete files in the wrong place. Next come the keep of`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
