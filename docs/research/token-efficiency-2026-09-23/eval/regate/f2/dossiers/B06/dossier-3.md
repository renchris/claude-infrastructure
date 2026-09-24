# Dossier 3

## Brief
```
Review /tmp/tokeff-regate/f2/review/rotate-logs.sh for bugs. List each real bug with the line, what goes wrong, and a one-line fix. Do not list style nits separately from real bugs; rank by severity. Do not run the script. numbers: {"bugs": <how many real bugs>}.
```

## Returned headline
rotate-logs.sh has 7 real bugs. The worst is the unchecked, unquoted `cd $dir`: a missing or empty argument makes the script gzip logs and delete .gz files in the wrong directory (HOME or the caller's cwd). The rest are `xargs rm` splitting names on whitespace, an off-by-one in `tail` that keeps one archive too few, `-mtime +1` meaning 48 h rather than 1 day, `$(ls)` and the unquoted test breaking on odd filenames, gzip refusing to overwrite an existing archive so later rotations never happen, and a success message printed even when steps fail.

## Returned numbers
`{"bugs": 7}`

## answer.md
# rotate-logs.sh review: 7 real bugs, ranked by severity

The script was read but not run. Line numbers refer to `/tmp/tokeff-regate/f2/review/rotate-logs.sh`.

| # | Line | Severity | What goes wrong | One-line fix |
|---|------|----------|-----------------|--------------|
| 1 | 5 | Critical | `cd $dir` is unquoted and its result is never checked. With no argument, `cd` goes to `$HOME`. With a missing directory, `cd` fails and the script stays in the caller's cwd. With a path containing spaces, the path splits and `cd` fails. In each case the script carries on and gzips `*.log` in the WRONG directory, and line 11 `rm -f`s that directory's `*.gz` files. | `[ -n "$1" ] \|\| { echo "usage: $0 <dir> [keep]" >&2; exit 2; }; cd -- "$dir" \|\| exit 1` |
| 2 | 11 | High | `xargs rm -f` splits its input on whitespace and treats quotes and backslashes specially. An archive named `app old.log.gz` becomes `rm -f app old.log.gz`, which deletes an unrelated file called `app` (if present) and misses the real archive. A name containing a quote makes xargs abort. | `ls -t -- *.gz \| tail -n +"$((keep+1))" \| while IFS= read -r g; do rm -f -- "$g"; done` |
| 3 | 11 | High | Off-by-one: `tail -n +$keep` starts printing at line `keep`, so only `keep-1` archives survive. The default of 5 keeps 4, and `keep=1` keeps none. This deletes one more archive than the spec allows. | `tail -n +"$((keep+1))"` |
| 4 | 7 | Medium | `find -mtime +1` matches files whose age, rounded down to whole days, is greater than 1. That means at least 48 h old, not "older than 1 day" as the header says. A log between 24 h and 48 h old is skipped, so every log is rotated a day late. | `find "$f" -prune -mtime +0` (or `-mmin +1440`) |
| 5 | 6-7 | Medium | `for f in $(ls *.log)` splits filenames on whitespace and glob-expands them again. `my app.log` becomes `my` and `app.log`, and each piece is then gzipped or errors. The unquoted `[ $(find ...) ]` breaks too: two or more words give `[: too many arguments` or `binary operator expected`. A name starting with `-` is parsed as an option by `ls`, `find` and `gzip`. A directory named `x.log` makes `find` descend into it and then `gzip` a directory. | `for f in ./*.log; do [ -f "$f" ] \|\| continue; if [ -n "$(find "$f" -prune -mtime +0)" ]; then gzip -- "$f"; fi; done` |
| 6 | 8 | Medium | Archive-name collision: once `app.log.gz` exists, the next rotation of a recreated `app.log` finds `gzip` refusing to overwrite. On a tty it prompts; under cron it prints "already exists; not overwritten" and skips. So each log is rotated once and never again, and `keep` never has more than one archive per log to prune. | `gzip -c -- "$f" > "$f.$(date +%Y%m%d%H%M%S).gz" && rm -f -- "$f"` |
| 7 | 12 | Low | The script always prints "rotated logs" and exits 0, even when `cd`, `gzip` or `rm` failed, so cron or monitoring cannot see a failed rotation. | Track failures (`rc=1` on each failed `gzip`/`rm`) and `exit "$rc"`; print success only when `rc=0` |

Related points that are harmless on their own. The fixes above already cover them.
- When no `*.log` or `*.gz` files exist, the literal glob goes to `ls`, which prints "No such file or directory" to stderr but deletes nothing. The `./*.log` + `[ -f ]` guard removes the noise, and so does `shopt -s nullglob`.
- `keep` is never validated. A non-numeric value makes `$((keep+1))` error out, or makes `tail` fail, which deletes nothing. Add `case $keep in ''|*[!0-9]*) exit 2;; esac`.
- Retention counts every `*.gz` in the directory, so unrelated `.gz` files that happen to live there count against `keep` and can be deleted. Scope the glob to `*.log.*.gz` once fix 6 names the archives.


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
2. `Bash: {"command": "mkdir -p /tmp/tokeff-regate/f2/out/B06-r2 && cat > /tmp/tokeff-regate/f2/out/B06-r2/answer.md <<'EOF'\n# rotate-logs.sh review: 7 real bugs, ranked by severity\n\nThe script was read but not run. Line numbers refer to `/tmp/tokeff-regate/f2/review/rotate-logs.sh`.\n\n| # | Line | Severi`
   → (Bash completed with no output)
3. `StructuredOutput: {"answer_path": "/tmp/tokeff-regate/f2/out/B06-r2/answer.md", "headline": "rotate-logs.sh has 7 real bugs. The worst is the unchecked, unquoted `cd $dir`: a missing or empty argument makes the script gzip logs and delete .gz files in the wrong directory (HOME or the caller's cwd). The rest are `xarg`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
