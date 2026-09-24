# Dossier 7

## Brief
```
Review /tmp/tokeff-regate/f2/review/rotate-logs.sh for bugs. List each real bug with the line, what goes wrong, and a one-line fix. Do not list style nits separately from real bugs; rank by severity. Do not run the script. numbers: {"bugs": <how many real bugs>}.
```

## Returned headline
rotate-logs.sh has 7 real bugs; the worst is that line 5 never checks whether `cd $dir` worked, so a missing or empty directory argument makes line 11 delete .gz files in the caller's directory or $HOME. Next come an off-by-one in `tail -n +$keep` that keeps only keep-1 archives, and filename splitting in `xargs rm`.

## Returned numbers
`{"bugs": 7}`

## answer.md
# rotate-logs.sh review: 7 real bugs

The worst bug is at line 5. If `cd` fails, or no directory argument is given, the script still runs line 11 in whatever directory it happens to be in and deletes `.gz` files there. Next is an off-by-one error: the script keeps one archive fewer than asked. Filenames with spaces break both the gzip loop and the delete step.

Ranked by severity:

| # | Line | What goes wrong | One-line fix |
|---|------|-----------------|--------------|
| 1 | 5 | `cd $dir` is unquoted and nothing checks whether it worked. A missing directory, a bad path, or a path with spaces makes `cd` fail and the script carries on in the caller's directory. With no argument, `cd` with nothing after it goes to `$HOME`. Either way, line 11 then deletes `.gz` files in the wrong directory. | `[ -n "$1" ] \|\| { echo "usage: $0 <dir> [keep]" >&2; exit 2; }; cd -- "$dir" \|\| exit 1` |
| 2 | 11 | Off-by-one. `tail -n +$keep` prints from line `keep` onward, so only `keep-1` archives survive. The default `keep=5` keeps 4, and `keep=1` keeps none. One archive too many is lost on every run. | `tail -n +"$((keep + 1))"` |
| 3 | 11 | `ls -t \| xargs rm -f` splits names on whitespace and treats quote characters specially. For `my app.log.gz`, `rm` receives `my` and `app.log.gz`: it can delete unrelated files with those names and it misses the real archive. A name containing `'` stops xargs with an "unterminated quote" error. | `ls -t -- *.gz \| tail -n +"$((keep+1))" \| while IFS= read -r g; do rm -f -- "$g"; done` (or `xargs -I{} rm -f -- {}` with NUL-safe input) |
| 4 | 8 | `gzip "$f"` always writes to the same `$f.gz`. On the next rotation of `app.log`, `app.log.gz` already exists. Without a terminal, gzip refuses ("already exists; not overwritten") and the log is never rotated again. In a terminal, it stops and waits for a y/n answer. Also, every log only ever has one archive, so `keep` does nothing useful. | `gzip -c -- "$f" > "$f.$(date +%Y%m%d%H%M%S).gz" && rm -f -- "$f"` |
| 5 | 7 | `find -mtime +1` matches files at least 48 hours old, not files older than 1 day. `find` rounds the age down to whole days, and `+1` means "more than 1 day", so 2 or more. Logs between 24 and 48 hours old are skipped. | `find "./$f" -mtime +0` (or `-mmin +1440`) |
| 6 | 6–7 | `for f in $(ls *.log)` splits filenames on whitespace, so `a b.log` becomes `a` and `b.log`, and neither is gzipped. After that, the unquoted `[ $(find ...) ]` becomes `[ ./a b.log ]` for such a name. That errors with "binary operator expected", counts as false, and the file is silently skipped. A name starting with `-` is read by `find` as an option. | Replace lines 6–10 with `find . -maxdepth 1 -type f -name '*.log' -mtime +0 -exec gzip -- {} +` (combine with the naming fix in #4), or `for f in *.log; do [ -e "$f" ] \|\| continue; if [ -n "$(find "./$f" -mtime +0)" ]; then …` |
| 7 | 11 | `*.gz` matches every gzip file in the directory, not just archives this script made. For example, a `backup.tar.gz` stored beside the logs gets pruned. The "newest N" limit also applies to all logs together, not to each log. | Narrow the glob to the archives the script creates: `ls -t -- *.log*.gz` (per-log: loop over base names and prune `"$base".*.gz`) |

## Also noted (not counted)
- `keep` is not checked. A value that is not a number (`abc`) or is negative makes `tail` fail, so nothing is pruned, and nothing reports it. Fix: `case $keep in ''|*[!0-9]*) echo "bad keep" >&2; exit 2;; esac`.
- If there are no `*.gz` or `*.log` files, `ls` prints "No such file or directory" to stderr. This does no harm, but cron will email it. Use `shopt -s nullglob` or the `find` form.
- Line 12 prints "rotated logs" even when `cd` or `gzip` failed. There is no `set -e` and no exit status. Minor.
- Gzipping a log that a process still has open loses that process's later writes, which go to the deleted file. The mtime check lowers the risk. The robust fix is to signal the writer or use a copytruncate step.


## Tool calls (3) with the first 300 chars of each result
1. `Bash: {"command": "cat -n /tmp/tokeff-regate/f2/review/rotate-logs.sh; ls /tmp/tokeff-regate/f2/review/ /tmp/tokeff-regate/f2/out/B06-r6/ 2>&1", "description": "Show script with line numbers and list dirs"}`
   →      1	#!/bin/bash
     2	# rotate-logs.sh <dir> [keep] — gzip every *.log in <dir> older than 1 day, keep the newest <keep> archives.
     3	dir=$1
     4	keep=${2:-5}
     5	cd $dir
     6	for f in $(ls *.log); do
     7	  if [ $(find "$f" -mtime +1) ]; then
     8	    gzip "$f"
     9	  fi
    10
2. `Bash: {"command": "cat > /tmp/tokeff-regate/f2/out/B06-r6/answer.md <<'EOF'\n# rotate-logs.sh review: 7 real bugs\n\nThe worst bug is at line 5. If `cd` fails, or no directory argument is given, the script still runs line 11 in whatever directory it happens to be in and deletes `.gz` files there. Next is `
   → (Bash completed with no output)
3. `StructuredOutput: {"answer_path": "/tmp/tokeff-regate/f2/out/B06-r6/answer.md", "headline": "rotate-logs.sh has 7 real bugs; the worst is that line 5 never checks whether `cd $dir` worked, so a missing or empty directory argument makes line 11 delete .gz files in the caller's directory or $HOME. Next come an off-by-o`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
