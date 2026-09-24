# Dossier 9

## Brief
```
Review /tmp/tokeff-gate/f2/review/rotate-logs.sh for bugs. List each real bug with the line, what goes wrong, and a one-line fix. Do not list style nits separately from real bugs; rank by severity. Do not run the script. numbers: {"bugs": <how many real bugs>}.
```

## Returned headline
rotate-logs.sh has 7 real bugs. The worst: an unchecked `cd $dir` (line 5) lets line 11 delete .gz files in $HOME or the current directory; `tail -n +$keep` keeps one archive too few, and with keep=1 deletes them all; `*.gz` and `xargs` delete unrelated or wrongly split files; `-mtime +1` means 2 or more days old; the `ls`/unquoted `[ ]` loop breaks on filenames with spaces; and `gzip` collides on a second rotation of the same log name.

## Returned numbers
`{"bugs": 7}`

## answer.md
# Review: /tmp/tokeff-gate/f2/review/rotate-logs.sh

I found 7 real bugs, ranked by severity. Four of them delete the wrong files or too many files. I read the script only and did not run it.

| # | Line | Severity | What goes wrong | One-line fix |
|---|------|----------|-----------------|--------------|
| 1 | 5 | Critical | `cd $dir` is unquoted and its result is never checked. If `dir` is empty (no argument), `cd` goes to `$HOME`. If the directory is missing, or the path contains a space, `cd` fails and the script keeps running in the caller's current directory. Either way, line 11 then deletes every `*.gz` file in that other directory except the newest few. | `[ -n "$1" ] && cd -- "$1" \|\| { echo "usage: $0 <dir> [keep]" >&2; exit 1; }` |
| 2 | 11 | High | Off-by-one: `tail -n +$keep` starts output at line `keep`, so only `keep-1` archives survive. With the default of 5, only 4 are kept. With `keep=1`, `tail -n +1` outputs every file, so all archives are deleted. | `tail -n +"$((keep + 1))"` |
| 3 | 11 | High | `*.gz` matches every gzip file in the directory, not just the rotated logs, so unrelated archives (such as `db-backup.sql.gz`) get pruned too. | `ls -t -- *.log.gz` |
| 4 | 11 | High | `xargs` splits its input on whitespace and treats quotes specially. An archive called `my app.log.gz` becomes two words, so `rm -f my` and `rm -f app.log.gz` run. That can delete an unrelated file named `my` while the real archive stays. | `... \| while IFS= read -r g; do rm -f -- "$g"; done` (or null-delimited `find ... -print0 \| xargs -0`) |
| 5 | 7 | Medium | `find -mtime +1` means "at least 2 full days old", because find drops fractional days before comparing. A log that is 1 to 2 days old is not rotated, which contradicts the header's "older than 1 day". | `find "$f" -mtime +0` (or `-mmin +1440`) |
| 6 | 6-7 | Medium | Filenames with spaces or glob characters break the loop. `$(ls *.log)` splits `my app.log` into `my` and `app.log`. Then `[ $(find ...) ]` is unquoted, so any output with a space becomes `[ a b ]`, which is a "binary operator expected" error, and the file is skipped. A name starting with `-` is parsed by `find` as an option. | `for f in ./*.log; do [ -f "$f" ] && [ -n "$(find "$f" -mtime +0)" ] && gzip -- "$f"; done` |
| 7 | 8 | Medium | Archive names collide. `gzip "$f"` always writes `$f.gz`. The next time a log with the same name is rotated (for example tomorrow's `app.log`), `app.log.gz` already exists. gzip then refuses, or prompts and hangs when run from a terminal. The log is never rotated, and there is never more than one archive per log name, so the "keep newest N" logic has nothing to keep. | `gzip -c -- "$f" > "$f.$(date +%Y%m%d%H%M%S).gz" && rm -f -- "$f"` |

Bugs 6 and 7 are distinct: bug 6 is word splitting in the loop and the test, bug 7 is the output file name. Rows 2 to 4 are separate defects on the same line, and each has its own independent fix.

## Not counted as bugs (minor or design notes)
- Line 12 prints "rotated logs" no matter what happened. There is no `set -e` or exit-status check, so a failed `cd` or `gzip` still ends with a success message and exit code 0. (Fixing bug 1 removes the dangerous case.)
- `keep` is not validated. A non-numeric value makes `tail` fail, and then nothing is pruned, which fails safe.
- Compressing a log that a process still holds open loses whatever it writes afterwards. The mtime filter makes this unlikely, but `copytruncate` or a reload signal is the usual safeguard.

## Suggested rewrite of the core
```bash
#!/bin/bash
set -euo pipefail
dir=${1:?usage: rotate-logs.sh <dir> [keep]}; keep=${2:-5}
cd -- "$dir"
find . -maxdepth 1 -type f -name '*.log' -mtime +0 -print0 |
  while IFS= read -r -d '' f; do gzip -c -- "$f" > "$f.$(date +%Y%m%d%H%M%S).gz" && rm -f -- "$f"; done
ls -t -- *.log.gz 2>/dev/null | tail -n +"$((keep + 1))" | while IFS= read -r g; do rm -f -- "$g"; done
echo "rotated logs in $dir"
```


## Tool calls (4) with the first 300 chars of each result
1. `Bash: {"command": "cat -n /tmp/tokeff-gate/f2/review/rotate-logs.sh; ls -la /tmp/tokeff-gate/f2/review/ /tmp/tokeff-gate/f2/out/B06-r2/ 2>&1", "description": "Read the script under review"}`
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
2. `Write: {"file_path": "/tmp/tokeff-gate/f2/out/B06-r2/answer.md", "content": "# Review: /tmp/tokeff-gate/f2/review/rotate-logs.sh\n\nI found 6 real bugs, ranked by severity. Three of them delete the wrong files or too many files. I read the script only and did not run it.\n\n| # | Line | Severity | What goe`
   → File created successfully at: /tmp/tokeff-gate/f2/out/B06-r2/answer.md (file state is current in your context — no need to Read it back)
3. `Bash: {"command": "cd /tmp/tokeff-gate/f2/out/B06-r2 && sed -i '' 's/^I found 6 real bugs, ranked by severity\\. Three of them delete/I found 7 real bugs, ranked by severity. Four of them delete/; s/^Bugs 6 and 7 are distinct\\..*$/Bugs 6 and 7 are distinct: bug 6 is word splitting in the loop and the tes`
   → # Review: /tmp/tokeff-gate/f2/review/rotate-logs.sh

I found 7 real bugs, ranked by severity. Four of them delete the wrong files or too many files. I read the script only and did not run it.

| # | Line | Severity | What goes wrong | One-line fix |
15:Bugs 6 and 7 are distinct: bug 6 is word splitt
4. `StructuredOutput: {"answer_path": "/tmp/tokeff-gate/f2/out/B06-r2/answer.md", "headline": "rotate-logs.sh has 7 real bugs. The worst: an unchecked `cd $dir` (line 5) lets line 11 delete .gz files in $HOME or the current directory; `tail -n +$keep` keeps one archive too few, and with keep=1 deletes them all; `*.gz` an`
   → Structured output provided successfully

## Writes outside the slot's OUTDIR detected by the harness
(none)
