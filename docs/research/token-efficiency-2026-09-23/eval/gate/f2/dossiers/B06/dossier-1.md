# Dossier 1

## Brief
```
Review /tmp/tokeff-gate/f2/review/rotate-logs.sh for bugs. List each real bug with the line, what goes wrong, and a one-line fix. Do not list style nits separately from real bugs; rank by severity. Do not run the script. numbers: {"bugs": <how many real bugs>}.
```

## Returned headline
I found 7 real bugs in rotate-logs.sh by reading it; I did not run it. The worst is that `cd $dir` is unquoted and unchecked, so a missing or wrong argument makes the script delete .gz files in $HOME or the caller's directory. Next come `xargs rm` splitting names with spaces and deleting the wrong files, and an off-by-one in `tail -n +$keep` that keeps only keep-1 archives (none when keep=1). The rest: gzip refuses to overwrite an existing app.log.gz so a log stops rotating, `-mtime +1` only matches files at least 48h old, `$(ls)` and the unquoted test break names with spaces, and retention counts every *.gz in the directory.

## Returned numbers
`{"bugs": 7}`

## answer.md
# Review: /tmp/tokeff-gate/f2/review/rotate-logs.sh

I read the script but did not run it. It is 13 lines long. I found 7 real bugs, listed below from most to least severe.

| # | Line | Severity | What goes wrong | One-line fix |
|---|------|----------|-----------------|--------------|
| 1 | 3, 5 | Critical | `cd $dir` has no quotes and nothing checks whether it worked. With no argument, `cd` goes to `$HOME`. With a missing or mistyped directory, `cd` fails and the script stays in the caller's directory. With a path that has spaces, the path is split into words. In each case line 11 still runs and deletes `*.gz` files in the wrong directory. | `dir=${1:?usage: rotate-logs.sh <dir> [keep]}; cd -- "$dir" \|\| exit 1` |
| 2 | 11 | High | `ls -t *.gz \| ... \| xargs rm -f`: xargs splits its input on spaces and treats quotes and backslashes specially. An archive named `old app.log.gz` becomes `rm -f old app.log.gz`, which deletes the unrelated files `old` and `app.log.gz` and keeps the real archive. A quote in a name makes xargs abort. | `ls -t -- *.gz \| tail -n +$((keep+1)) \| while IFS= read -r g; do rm -f -- "$g"; done` |
| 3 | 11 | High | Off-by-one error. `tail -n +N` starts printing at line N, so `tail -n +$keep` deletes everything from the keep-th newest archive onward. Only `keep-1` archives remain. With `keep=1`, every archive is deleted, including the newest. | `tail -n +$((keep + 1))` |
| 4 | 8 | Medium | The archive name does not change between runs. After `app.log` is rotated to `app.log.gz`, the next `app.log` rotation fails with "app.log.gz already exists". gzip will not overwrite without a terminal. That log is never rotated again, and the failure is silent because line 12 still prints success. | `gzip -c -- "$f" > "$f.$(date +%Y%m%d%H%M%S).gz" && rm -- "$f"` |
| 5 | 7 | Medium | The age test is wrong. `find -mtime +1` counts whole 24-hour periods and needs more than 1 of them, so a file must be at least 48 hours old. Files between 24 and 48 hours old are skipped, which contradicts "older than 1 day" in the header. | `find "$f" -mtime +0` (or `-mmin +1440`) |
| 6 | 6-8 | Medium | `for f in $(ls *.log)` splits file names on spaces and expands any glob characters in them. The `[ $(find ...) ]` test on line 7 is also unquoted, so `my app.log` turns into the words `my` and `app.log`. The test then errors ("binary operator expected") or checks the wrong files, and the real log is never rotated. A name starting with `-` would be read as an option by `find` and `gzip`. | `for f in ./*.log; do [ -e "$f" ] \|\| continue; if [ -n "$(find "$f" -mtime +0)" ]; then gzip -- "$f"; fi; done` |
| 7 | 11 | Medium-Low | The retention step matches every `*.gz` in the directory, not just rotated logs. Any other archive stored there (a backup or tarball) counts toward `keep` and can be deleted. | Limit the glob to rotated logs: `ls -t -- *.log*.gz` (or `*.log.*.gz` with the timestamped names from fix 4) |

Minor points, folded into the bugs above rather than counted separately:
- `keep` is never checked. A non-numeric value makes `tail` fail, so nothing is pruned and no error is reported. Add `case $keep in ''|*[!0-9]*) exit 2;; esac`.
- Line 12 always prints "rotated logs" even when `cd`, `gzip` or `rm` failed. Once fix 1 is in, add `set -u` and check each step's exit status.

## Corrected script (for reference, not run)
```bash
#!/bin/bash
set -u
dir=${1:?usage: rotate-logs.sh <dir> [keep]}
keep=${2:-5}
case $keep in ''|*[!0-9]*) echo "keep must be a number" >&2; exit 2;; esac
cd -- "$dir" || exit 1
for f in ./*.log; do
  [ -e "$f" ] || continue
  if [ -n "$(find "$f" -mtime +0)" ]; then
    gzip -c -- "$f" > "$f.$(date +%Y%m%d%H%M%S).gz" && rm -- "$f"
  fi
done
ls -t -- ./*.log.*.gz 2>/dev/null | tail -n +$((keep + 1)) | while IFS= read -r g; do rm -f -- "$g"; done
echo "rotated logs in $dir"
```


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
2. `Bash: {"command": "ls -la /tmp/tokeff-gate/f2/review/ /tmp/tokeff-gate/f2/out/ 2>&1", "description": "List review and output directories"}`
   → /tmp/tokeff-gate/f2/out/:
total 0
drwxr-xr-x@ 82 chrisren  wheel  2624 Sep 24 10:27 .
drwxr-xr-x@  9 chrisren  wheel   288 Sep 24 10:27 ..
drwxr-xr-x@  3 chrisren  wheel    96 Sep 24 10:28 B01-r1
drwxr-xr-x@  3 chrisren  wheel    96 Sep 24 10:29 B01-r2
drwxr-xr-x@  3 chrisren  wheel    96 Sep 24 10:
3. `Bash: {"command": "cat > /tmp/tokeff-gate/f2/out/B06-r1/answer.md <<'EOF'\n# Review: /tmp/tokeff-gate/f2/review/rotate-logs.sh\n\nI read the script but did not run it. It is 13 lines long. I found 7 real bugs, listed below from most to least severe.\n\n| # | Line | Severity | What goes wrong | One-line fi`
   → ok
4. `StructuredOutput: {"answer_path": "/tmp/tokeff-gate/f2/out/B06-r1/answer.md", "headline": "I found 7 real bugs in rotate-logs.sh by reading it; I did not run it. The worst is that `cd $dir` is unquoted and unchecked, so a missing or wrong argument makes the script delete .gz files in $HOME or the caller's directory. `
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
