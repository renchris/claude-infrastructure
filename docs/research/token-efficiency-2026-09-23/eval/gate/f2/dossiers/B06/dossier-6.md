# Dossier 6

## Brief
```
Review /tmp/tokeff-gate/f2/review/rotate-logs.sh for bugs. List each real bug with the line, what goes wrong, and a one-line fix. Do not list style nits separately from real bugs; rank by severity. Do not run the script. numbers: {"bugs": <how many real bugs>}.
```

## Returned headline
rotate-logs.sh has 7 real bugs. The worst is an unquoted, unchecked `cd $dir` (line 5): if it fails, the script deletes .gz files in the wrong directory. Next come an off-by-one in `tail -n +$keep` that keeps only keep-1 archives, `xargs rm` splitting names on whitespace, a `*.gz` glob that also deletes unrelated archives, gzip refusing to overwrite an existing name.log.gz so rotation stops, `-mtime +1` meaning 48 hours rather than 1 day, and `for f in $(ls *.log)` word-splitting filenames.

## Returned numbers
`{"bugs": 7}`

## answer.md
# Review: /tmp/tokeff-gate/f2/review/rotate-logs.sh

I read the script but did not run it. Line numbers refer to the file as read. I found 7 real bugs, listed from most to least severe.

| # | Line | Severity | What goes wrong | One-line fix |
|---|------|----------|-----------------|--------------|
| 1 | 5 | Critical | `cd $dir` is not quoted and its result is not checked. If `<dir>` is missing, misspelled, unreadable or contains spaces, `cd` fails and the script keeps running in the caller's cwd. If `<dir>` is left out entirely, `cd` goes to `$HOME`. Line 11 then deletes `.gz` files in the wrong directory. | `[ -n "$1" ] \|\| { echo "usage: $0 <dir> [keep]" >&2; exit 2; }; cd -- "$dir" \|\| exit 1` |
| 2 | 11 | High (data loss) | Off-by-one in retention. `tail -n +$keep` prints from line `$keep` onward, so only the newest `keep-1` archives survive. With the default of 5, only 4 are kept and the 5th newest is deleted. | `tail -n +$((keep + 1))` |
| 3 | 11 | High (deletes wrong files) | `ls -t *.gz \| ... \| xargs rm -f` splits names on whitespace and treats quotes and backslashes specially. An archive called `my app.log.gz` becomes `rm -f my app.log.gz`, which deletes an unrelated file named `my` and misses the real one. Quote characters make xargs abort. | `ls -t -- *.log*.gz \| tail -n +$((keep+1)) \| while IFS= read -r g; do rm -f -- "$g"; done` (or NUL-delimited `find ... -print0 \| xargs -0`) |
| 4 | 11 | High (deletes wrong files) | The glob `*.gz` matches every gzip file in the directory, not just rotated logs. Unrelated archives such as `backup.tar.gz` count toward `keep` and get deleted. | Glob only what this script creates: `*.log*.gz` (or a dedicated suffix) |
| 5 | 8 | High (rotation stops) | `gzip "$f"` writes `name.log.gz` under a fixed name. On the next rotation of the same log (for example `app.log` recreated by the app), `app.log.gz` already exists. Non-interactive gzip then refuses with "already exists; not overwritten", and the log grows forever. The fixed name also means there is only ever one archive per log, so `keep` is meaningless. | `gzip -c -- "$f" > "$f.$(date +%Y%m%d%H%M%S).gz" && rm -f -- "$f"` |
| 6 | 7 | Medium | `find -mtime +1` means "more than one *whole* 24-hour period", so it only matches files at least 48 hours old. That contradicts the stated "older than 1 day": logs 24 to 48 hours old are skipped. | `find ... -mtime +0` (or `-mmin +1440`) |
| 7 | 6 (and 7) | Medium | `for f in $(ls *.log)` word-splits: `my app.log` becomes `my` and `app.log`, and both are then gzipped or tested wrongly. If a *directory* matches `*.log`, `ls` lists its contents instead of the name. On line 7 the unquoted `[ $(find ...) ]` then sees several words and fails with "binary operator expected". A name starting with `-` is parsed by `find` as an option. | `for f in ./*.log; do [ -f "$f" ] \|\| continue; if [ -n "$(find "$f" -mtime +0)" ]; then ...` (or simply `find . -maxdepth 1 -type f -name '*.log' -mtime +0 -exec gzip -- {} +` with the timestamp naming from #5) |

## Lower-severity notes (included for completeness, not counted above)
- Line 4: `keep` is not validated. A non-numeric value such as `abc` makes `tail` fail, and the pipeline then deletes nothing without any error. `keep=0` works only because of how `tail -n +0` happens to behave.
- Line 11: if there are no `.gz` files, `ls` prints an error to stderr. It is harmless because `rm -f` with no arguments does nothing.
- Line 12: the "rotated logs" message prints even when `cd`, `gzip` or `rm` failed, and the script exits 0. There is no `set -u` / `set -o pipefail` and no exit-status check. Fix: exit non-zero when a step fails.

## Minimal corrected sketch
```bash
#!/bin/bash
set -u
dir=${1:?usage: rotate-logs.sh <dir> [keep]}
keep=${2:-5}
[[ $keep =~ ^[0-9]+$ ]] || { echo "keep must be a non-negative integer" >&2; exit 2; }
cd -- "$dir" || exit 1
find . -maxdepth 1 -type f -name '*.log' -mtime +0 -print0 |
  while IFS= read -r -d '' f; do
    gzip -c -- "$f" > "$f.$(date +%Y%m%d%H%M%S).gz" && rm -f -- "$f"
  done
ls -t -- *.log.*.gz 2>/dev/null | tail -n +$((keep + 1)) |
  while IFS= read -r g; do rm -f -- "$g"; done
echo "rotated logs in $dir"
```
(Retention in the sketch is global across all logs, as in the original. For per-log retention, group by the base name.)


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
2. `Bash: {"command": "ls -la /tmp/tokeff-gate/f2/review/ /tmp/tokeff-gate/f2/out/B06-r8/ 2>&1", "description": "List review and output directories"}`
   → /tmp/tokeff-gate/f2/out/B06-r8/:
total 0
drwxr-xr-x@  2 chrisren  wheel    64 Sep 24 10:27 .
drwxr-xr-x@ 82 chrisren  wheel  2624 Sep 24 10:27 ..

/tmp/tokeff-gate/f2/review/:
total 8
dr-xr-xr-x@ 3 chrisren  wheel   96 Sep 24 10:27 .
drwxr-xr-x@ 9 chrisren  wheel  288 Sep 24 10:27 ..
-r--r--r--@ 1 c
3. `Bash: {"command": "cat > /tmp/tokeff-gate/f2/out/B06-r8/answer.md <<'EOF'\n# Review: /tmp/tokeff-gate/f2/review/rotate-logs.sh\n\nI read the script but did not run it. Line numbers refer to the file as read. I found 7 real bugs, listed from most to least severe.\n\n| # | Line | Severity | What goes wrong `
   →       36 /tmp/tokeff-gate/f2/out/B06-r8/answer.md
4. `StructuredOutput: {"answer_path": "/tmp/tokeff-gate/f2/out/B06-r8/answer.md", "headline": "rotate-logs.sh has 7 real bugs. The worst is an unquoted, unchecked `cd $dir` (line 5): if it fails, the script deletes .gz files in the wrong directory. Next come an off-by-one in `tail -n +$keep` that keeps only keep-1 archiv`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
