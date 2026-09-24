# Dossier 8

## Brief
```
Review /tmp/tokeff-regate/f2/review/rotate-logs.sh for bugs. List each real bug with the line, what goes wrong, and a one-line fix. Do not list style nits separately from real bugs; rank by severity. Do not run the script. numbers: {"bugs": <how many real bugs>}.
```

## Returned headline
rotate-logs.sh has 7 real bugs, most severe first: (1) line 5's unchecked, unquoted `cd` means line 11 deletes .gz files in the wrong directory; (2) gzip hits an existing archive name, so a log is never rotated again; (3) `tail -n +$keep` keeps one archive too few; (4) the `*.gz` glob prunes unrelated archives; (5) `-mtime +1` waits 2 days, not 1; (6) `ls` and word-splitting break on spaces and leading dashes; (7) it reports success and exits 0 even when a step failed.

## Returned numbers
`{"bugs": 7}`

## answer.md
# rotate-logs.sh review: 7 real bugs

I read the script and did not run it. The bugs are listed most severe first.

| # | Line | What goes wrong | One-line fix |
|---|------|-----------------|--------------|
| 1 | 5 | `cd $dir` is unquoted and never checked. If `$1` is missing, `cd` goes to `$HOME`. If the path does not exist or contains a space, `cd` fails and the script keeps running in the caller's directory. Either way, line 11 then deletes `*.gz` files in the **wrong directory**. | `[ -n "$1" ] \|\| { echo "usage: $0 <dir> [keep]" >&2; exit 2; }; cd -- "$dir" \|\| exit 1` |
| 2 | 8 | Archive names are never unique. Once `app.log` has been rotated to `app.log.gz`, the next rotation of the recreated `app.log` finds that `.gz` already there. With no tty, gzip refuses ("already exists; not overwritten"). The log is **never rotated again** and grows without limit. It also means there can never be more than one archive per log, so the "keep N archives" retention has nothing to act on. | `gzip -c -- "$f" > "$f.$(date +%Y%m%d-%H%M%S).gz" && rm -- "$f"` |
| 3 | 11 | Off by one. `tail -n +$keep` starts printing at line `keep`, so lines 1..keep-1 survive. `keep=5` keeps only **4** archives. | `tail -n +$((keep + 1))` |
| 4 | 11 | `*.gz` matches every gzip file in the directory, not only archives this script made. Unrelated `.gz` files (backups, dumps) get pruned. | Glob only rotated logs: `ls -t -- *.log.*.gz` (or `*.log.gz` with the current naming) |
| 5 | 7 | `find -mtime +1` means "at least **2** full days old", because find rounds down to whole 24h periods. A log that is 1.5 days old is skipped, which contradicts the header's "older than 1 day". | `find ... -mtime +0` (or `-mmin +1440`) |
| 6 | 6, 7, 11 | Filenames go through `ls` and word splitting. `for f in $(ls *.log)` breaks `my app.log` into `my` and `app.log`. `[ $(find ...) ]` is unquoted, so a path with a space gives `[ a b ]`, which errors with "binary operator expected" and skips the file. A name starting with `-` is parsed as an option by `find`. `ls \| xargs rm` splits on spaces too, so the wrong paths get removed or are missed. | `for f in ./*.log; do [ -f "$f" ] \|\| continue; if [ -n "$(find "$f" -prune -mtime +0)" ]; then ...` and prune with `find . -maxdepth 1 -name '*.gz' -print0`, sorted, fed to `xargs -0 rm -f --` (or a `while read -r` loop) |
| 7 | 12 | It always prints "rotated logs" and exits 0, even when `cd`, `gzip` or `rm` failed, so cron and monitoring never see a failure. | Track failures (`rc=1` on each failed step), print the message only on success, and `exit "$rc"` |

## Lower-severity notes (not counted)
- **`keep` is not validated (line 4).** A non-numeric `keep` makes `tail` error out, so nothing is pruned and nothing reports it. Fix: `case $keep in ''|*[!0-9]*) echo "bad keep" >&2; exit 2;; esac`.
- **Data loss from a live writer.** gzip unlinks the original, so a process that still has the log open keeps writing to a deleted inode. The mtime gate makes this unlikely, but it is not guaranteed. The usual fixes are copy-and-truncate or signalling the writer to reopen.
- **Unexpected match on a directory.** If a directory's name ends in `.log`, `ls *.log` lists its contents instead of the directory itself.


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
2. `Write: {"file_path": "/tmp/tokeff-regate/f2/out/B06-r3/answer.md", "content": "# rotate-logs.sh review: 7 real bugs\n\nI read the script and did not run it. The bugs are listed most severe first.\n\n| # | Line | What goes wrong | One-line fix |\n|---|------|-----------------|--------------|\n| 1 | 5 | `cd `
   → File created successfully at: /tmp/tokeff-regate/f2/out/B06-r3/answer.md (file state is current in your context — no need to Read it back)
3. `StructuredOutput: {"answer_path": "/tmp/tokeff-regate/f2/out/B06-r3/answer.md", "headline": "rotate-logs.sh has 7 real bugs, most severe first: (1) line 5's unchecked, unquoted `cd` means line 11 deletes .gz files in the wrong directory; (2) gzip hits an existing archive name, so a log is never rotated again; (3) `ta`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
