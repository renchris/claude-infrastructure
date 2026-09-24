# Dossier 7

## Brief
```
Review /tmp/tokeff-gate/f2/review/rotate-logs.sh for bugs. List each real bug with the line, what goes wrong, and a one-line fix. Do not list style nits separately from real bugs; rank by severity. Do not run the script. numbers: {"bugs": <how many real bugs>}.
```

## Returned headline
rotate-logs.sh has 8 real bugs; the worst is that it never checks the cd on line 5 (or that a directory was given at all), so line 11 can delete .gz files in $HOME or the caller's directory. Also: line 11 deletes unrelated .gz files, keeps one archive too few and breaks on names with spaces in xargs; gzip fails for good once a .gz of the same name exists; ls and find mishandle filenames; and -mtime +1 means 2 days, not 1.

## Returned numbers
`{"bugs": 8}`

## answer.md
# Review: /tmp/tokeff-gate/f2/review/rotate-logs.sh

**8 real bugs.** The worst one: the script never checks that the `cd` succeeded, and it deletes every `*.gz` in whatever directory it ends up in. Ranked by severity:

| # | Line | What goes wrong | One-line fix |
|---|------|-----------------|--------------|
| 1 | 5 | `cd $dir` is unquoted, and nothing checks whether it worked. With no argument, `cd` goes to `$HOME`. If the directory doesn't exist or its name contains spaces, `cd` fails and the script keeps going in the caller's cwd. Either way, line 11 then deletes `.gz` files in the wrong directory, and line 12 still prints success. | `[ -n "$1" ] || { echo "usage: $0 <dir> [keep]" >&2; exit 2; }; cd -- "$dir" \|\| exit 1` |
| 2 | 11 | `ls -t *.gz` matches every gzip file in the directory, not only rotated logs. Unrelated files such as `backup.tar.gz` or `data.csv.gz` are counted toward the limit and deleted. | `ls -t -- *.log.gz` (match only what line 8 produces) |
| 3 | 11 | Off-by-one: `tail -n +$keep` starts at line `keep`, so it deletes the `keep`-th newest archive too. The script keeps `keep-1` archives (4 by default, not 5). | `tail -n +$((keep + 1))` |
| 4 | 11 | `xargs rm -f` splits names on whitespace and treats quotes and backslashes specially. `old app.log.gz` becomes `rm old app.log.gz`, which can delete the wrong files. A name containing a quote makes xargs abort. | `ls -t -- *.log.gz \| tail -n +$((keep+1)) \| tr '\n' '\0' \| xargs -0 rm -f --` (or loop over a bash array) |
| 5 | 8 | The archive name is fixed at `$f.gz`. Once `app.log.gz` exists, every later rotation of a recreated `app.log` fails with `already exists; not overwritten`, so the log is never rotated again and grows without limit. `gzip -f` would avoid the error but overwrite the previous archive, which also loses data. | `gzip -c -- "$f" > "$f.$(date +%Y%m%d%H%M%S).gz" && rm -- "$f"` |
| 6 | 6 | `for f in $(ls *.log)` word-splits the output of `ls`. A file named `my app.log` becomes two bogus names, `my` and `app.log`, so it is never rotated (and `find`/`gzip` error on the pieces). Parsing `ls` also breaks on glob characters in names. | `for f in *.log; do [ -e "$f" ] \|\| continue` |
| 7 | 7 | `[ $(find "$f" -mtime +1) ]` leaves the command output unquoted, so a path with spaces produces `[ a b ]` and the error "binary operator expected", which the `if` reads as false. A name starting with `-` or `(` is parsed by `find` as an expression, not a path. | `if [ -n "$(find "./$f" -prune -mtime +0)" ]; then` |
| 8 | 7 | Wrong age threshold. `find` rounds age down to whole 24-hour periods, so `-mtime +1` matches only files at least 2 full days old, not "older than 1 day" as the header says. Logs that are 24–48 hours old are skipped. | Use `-mtime +0` (older than 24 h) |

## Suggested rewrite (for reference; not run)

```bash
#!/bin/bash
set -u
dir=${1:?usage: rotate-logs.sh <dir> [keep]}
keep=${2:-5}
[[ $keep =~ ^[0-9]+$ ]] || { echo "keep must be a non-negative integer" >&2; exit 2; }
cd -- "$dir" || exit 1
shopt -s nullglob
while IFS= read -r -d '' f; do
  gzip -c -- "$f" > "$f.$(date +%Y%m%d%H%M%S).gz" && rm -- "$f"
done < <(find . -maxdepth 1 -type f -name '*.log' -mtime +0 -print0)
archives=( $(ls -t -- *.log.*.gz 2>/dev/null) )   # names from our own scheme contain no spaces
(( ${#archives[@]} > keep )) && rm -f -- "${archives[@]:keep}"
echo "rotated logs in $dir"
```

Not counted as a bug: gzipping a file that another process still holds open loses whatever that process writes afterwards, because it keeps writing to the deleted inode. The 1-day age filter makes this unlikely. A full fix needs `copytruncate` or a signal to the writer, which this script's design doesn't cover.


## Tool calls (3) with the first 300 chars of each result
1. `Bash: {"command": "cat -n /tmp/tokeff-gate/f2/review/rotate-logs.sh; ls -la /tmp/tokeff-gate/f2/review/ /tmp/tokeff-gate/f2/out/B06-r7/ 2>&1", "description": "Read the script under review and list output dir"}`
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
2. `Write: {"file_path": "/tmp/tokeff-gate/f2/out/B06-r7/answer.md", "content": "# Review: /tmp/tokeff-gate/f2/review/rotate-logs.sh\n\n**8 real bugs.** The worst one: the script never checks that the `cd` succeeded, and it deletes every `*.gz` in whatever directory it ends up in. Ranked by severity:\n\n| # | `
   → File created successfully at: /tmp/tokeff-gate/f2/out/B06-r7/answer.md (file state is current in your context — no need to Read it back)
3. `StructuredOutput: {"answer_path": "/tmp/tokeff-gate/f2/out/B06-r7/answer.md", "headline": "rotate-logs.sh has 8 real bugs; the worst is that it never checks the cd on line 5 (or that a directory was given at all), so line 11 can delete .gz files in $HOME or the caller's directory. Also: line 11 deletes unrelated .gz `
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
