# Dossier 8

## Brief
```
Review /tmp/tokeff-gate/f2/review/rotate-logs.sh for bugs. List each real bug with the line, what goes wrong, and a one-line fix. Do not list style nits separately from real bugs; rank by severity. Do not run the script. numbers: {"bugs": <how many real bugs>}.
```

## Returned headline
rotate-logs.sh has 7 real bugs. The worst is the unchecked `cd $dir` on line 5: if it fails or $1 is missing, the script runs in the wrong directory and deletes .gz files there. Next are three bugs that keep archives wrong or delete the wrong ones: an off-by-one in `tail -n +$keep` that keeps only keep-1, a `*.gz` glob that also prunes non-log archives, and a fixed archive name that makes gzip refuse the next rotation. The rest are lower severity: `-mtime +1` really means 2 or more days old, filenames with spaces or a leading dash get word-split (and xargs can rm the wrong file), and the script always prints success and exits 0.

## Returned numbers
`{"bugs": 7}`

## answer.md
# rotate-logs.sh review

7 real bugs, ranked by severity. The worst one can delete files outside the log directory.

| # | Line | What goes wrong | One-line fix |
|---|------|-----------------|--------------|
| 1 | 5 | `cd $dir` is unquoted and its result is never checked. If `$1` is missing, `cd` goes to `$HOME`. If the path doesn't exist or contains a space, `cd` fails and the script keeps running in the caller's cwd. Either way, line 11 then deletes `.gz` files in the wrong directory. | `[ -n "$1" ] && cd -- "$1" \|\| { echo "bad dir: $1" >&2; exit 1; }` |
| 2 | 11 | Off by one. `tail -n +$keep` starts printing at line `keep`, so line `keep` and everything after it are deleted. That leaves `keep-1` archives: the default keeps 4, not 5, and `keep=1` keeps none. | `tail -n +$((keep + 1))` |
| 3 | 11 | `*.gz` matches every gzip file in the directory, not just rotated logs. Unrelated archives (backups, `data.tar.gz`) get pruned too. | `ls -t -- *.log.gz` (or a dedicated archive name pattern) |
| 4 | 8 | `gzip "$f"` always writes the same `app.log.gz`. The next day, when `app.log` is old again, gzip refuses because the target exists (non-tty: "already exists; not overwritten"), so the log is never rotated again. That also means each log only ever has one archive, so `keep` never applies to it. | `gzip -c -- "$f" > "$f.$(date +%Y%m%d%H%M%S).gz" && rm -- "$f"` |
| 5 | 7 | `find -mtime +1` means "at least 2 full days old", because find rounds age down to whole 24h units and `+1` means >1. Logs 24–48h old are skipped, which contradicts "older than 1 day". | `find "$f" -mtime +0` (or `-mmin +1440`) |
| 6 | 6, 7, 11 | Filenames are word-split. `$(ls *.log)` breaks `my app.log` into `my` and `app.log`. The unquoted `[ $(find …) ]` becomes `[ ./my app.log ]` and fails with "binary operator expected". `xargs rm` splits on whitespace, so an archive named `a b.log.gz` deletes a file called `a`. A name starting with `-` is read as an option by `find`/`gzip`. | Replace lines 6–10 with `find . -maxdepth 1 -name '*.log' -mtime +0 -exec gzip -- {} +`. On line 11, prune with `while IFS= read -r g; do rm -f -- "$g"; done` instead of `xargs`. |
| 7 | 12 | The script prints "rotated logs" and exits 0 whatever happened (failed `cd`, failed `gzip`, etc.), so cron and callers never see a failure. | Add `set -euo pipefail` at the top (after fixing 1) and let a failure exit non-zero. |

Minor edge cases, not counted as separate bugs: with no `*.log`/`*.gz` present, `ls` prints "No such file" to stderr (fixed by the `find` rewrite in #6). `keep` is never validated: `keep=0` deletes every archive, and a non-numeric value makes `tail` error out.


## Tool calls (3) with the first 300 chars of each result
1. `Bash: {"command": "cat -n /tmp/tokeff-gate/f2/review/rotate-logs.sh; ls -la /tmp/tokeff-gate/f2/review/ /tmp/tokeff-gate/f2/out/B06-r3/ 2>&1", "description": "Read the script under review"}`
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
2. `Write: {"file_path": "/tmp/tokeff-gate/f2/out/B06-r3/answer.md", "content": "# rotate-logs.sh review\n\n7 real bugs, ranked by severity. The worst one can delete files outside the log directory.\n\n| # | Line | What goes wrong | One-line fix |\n|---|------|-----------------|--------------|\n| 1 | 5 | `cd $`
   → File created successfully at: /tmp/tokeff-gate/f2/out/B06-r3/answer.md (file state is current in your context — no need to Read it back)
3. `StructuredOutput: {"answer_path": "/tmp/tokeff-gate/f2/out/B06-r3/answer.md", "headline": "rotate-logs.sh has 7 real bugs. The worst is the unchecked `cd $dir` on line 5: if it fails or $1 is missing, the script runs in the wrong directory and deletes .gz files there. Next are three bugs that keep archives wrong or d`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
