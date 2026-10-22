#!/bin/bash
# kalloc-exec-census.sh — count every #! script exec on this Mac for N seconds (default 600).
#
# On macOS 15.8.1 each exec of a #! script by path keeps ~1.1 KiB in data.kalloc.1024 until reboot
# (docs/research/kalloc-longterm-2026-10-21/REPORT.md); this names which scripts still trigger it, and
# who runs them, so the fix can target the top rows. Read-only: it records exec events through ONE
# bounded `sudo eslogger exec` and writes only under ~/.cache/kalloc-exec-census/<stamp>/.
#
# What reaches disk, and why it is so little. eslogger prints every exec's FULL environment: the
# 2026-10-21 run stored API keys and tokens in a 26 GB world-readable file. So the stream is filtered
# before anything is written — script execs only (`"script":{`), and of each only time, script,
# caller, cwd, args[0:3] and three env keys (BATS_TEST_FILENAME, PYTEST_CURRENT_TEST,
# CLAUDE_PROJECT_DIR). No other env value is ever written. umask 077 for every file.
#
# One sudo call that bounds itself (`gtimeout -s INT`), because the old start-then-`sudo pkill` pair
# needed a second password after sudo's cache expired, failed under `|| true`, and left eslogger
# running for an hour. With no terminal (Claude Code's `!`) sudo asks through a password dialog.
#
# Usage: kalloc-exec-census.sh [SECONDS]      Safe to re-run; each run gets its own directory.
# Exit: 0 summary written · 1 no events (see eslogger.err) · 2 bad usage or a missing tool
set -uo pipefail
umask 077

DUR="${1:-600}"
case "$DUR" in ''|*[!0-9]*) echo "kalloc-exec-census: SECONDS must be a whole number, got '$DUR'" >&2; exit 2 ;; esac
[ "$DUR" -gt 0 ] || { echo "kalloc-exec-census: SECONDS must be > 0" >&2; exit 2; }

ESLOGGER="${KALLOC_CENSUS_ESLOGGER:-/usr/bin/eslogger}"
# The A/B harness of 2026-10-22 runs its own #! arms; counting them made the old summary wrong.
EXCLUDE="${KALLOC_CENSUS_EXCLUDE:-$HOME/.cache/kalloc-longterm-ab/}"
# sudo's secure_path does not hold Homebrew, so the bound and the filters are resolved here.
GTIMEOUT="$(command -v gtimeout || command -v timeout)" || { echo "kalloc-exec-census: needs gtimeout (brew install coreutils)" >&2; exit 2; }
RG="$(command -v rg)" || { echo "kalloc-exec-census: needs rg (ripgrep)" >&2; exit 2; }
JQ="$(command -v jq)" || { echo "kalloc-exec-census: needs jq" >&2; exit 2; }

OUT="$HOME/.cache/kalloc-exec-census/$(date +%Y%m%dT%H%M%S)"
mkdir -p "$OUT" || exit 2
chmod 700 "$OUT" "$HOME/.cache/kalloc-exec-census" 2>/dev/null
RAW="$OUT/exec.jsonl"

SUDO=(sudo)
if ! [ -t 0 ]; then
  ASK="$OUT/askpass.sh"
  printf '%s\n' '#!/bin/bash' \
    "/usr/bin/osascript -e 'text returned of (display dialog \"kalloc census: your Mac password, for sudo eslogger (read-only, ${DUR} s)\" default answer \"\" with hidden answer with title \"sudo\")'" > "$ASK"
  chmod 700 "$ASK"
  export SUDO_ASKPASS="$ASK"
  SUDO=(sudo -A)
fi

# Keep only the allow-listed fields. `fromjson?` skips a torn or non-JSON line instead of killing the
# pipe; the select repeats rg's test on the parsed object, so a `"script":{` inside an arg is dropped.
# shellcheck disable=SC2016  # $ex, $s, $i and $excl are jq variables, not shell ones
FILTER='fromjson? | select(.event.exec.script != null)
  | .event.exec as $ex
  | ($ex.script.path // $ex.script.executable.path // "?") as $s
  | select(($excl | length) == 0 or ($s | startswith($excl) | not))
  | {time: .time,
     script: $s,
     caller: (.process.executable.path // "?"),
     cwd: ($ex.cwd.path // null),
     args: (($ex.args // [])[0:3]),
     env: ([($ex.env // [])[] | strings
            | select(startswith("BATS_TEST_FILENAME=") or startswith("PYTEST_CURRENT_TEST=")
                     or startswith("CLAUDE_PROJECT_DIR="))
            | index("=") as $i | {(.[:$i]): .[$i + 1:]}] | add // {})}'

echo "kalloc-exec-census: recording #! exec events for ${DUR}s -> $OUT"
T0=$(date +%s)
"${SUDO[@]}" "$GTIMEOUT" -s INT "$DUR" "$ESLOGGER" exec 2> "$OUT/eslogger.err" \
  | "$RG" --line-buffered -F '"script":{' \
  | "$JQ" -c -R --unbuffered --arg excl "$EXCLUDE" "$FILTER" > "$RAW"
ps_rc=("${PIPESTATUS[@]}")
T1=$(date +%s)
WIN=$((T1 - T0))
# 124 is gtimeout's "the window ran its full length" — the expected end, not a failure.
echo "eslogger_rc=${ps_rc[0]} window_s=$WIN" >> "$OUT/eslogger.err"

N=$(wc -l < "$RAW" | tr -d ' ')
if [ "$N" -eq 0 ]; then
  echo "verdict=no-events rc=${ps_rc[0]} window_s=$WIN: no #! exec recorded. See $OUT/eslogger.err (wrong password, or the terminal app needs Full Disk Access)." >&2
  exit 1
fi

/usr/bin/python3 -I - "$RAW" "$OUT" "$WIN" "$DUR" <<'PY'
import collections, json, os, sys
raw, out, win, dur = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
scripts, pairs, cwds, tests = (collections.Counter() for _ in range(4))
n = bad = 0
for line in open(raw, errors="replace"):
    try:
        e = json.loads(line)
    except ValueError:
        bad += 1
        continue
    n += 1
    s = e.get("script") or "?"
    scripts[s] += 1
    pairs[(os.path.basename(e.get("caller") or "?"), s)] += 1
    cwds[e.get("cwd") or "?"] += 1
    env = e.get("env") or {}
    t = env.get("BATS_TEST_FILENAME") or env.get("PYTEST_CURRENT_TEST", "").split("::")[0]
    if t:
        tests[t] += 1
w = max(win, 1)
path = os.path.join(out, "summary.txt")
with open(path, "w") as f:
    f.write(f"script_execs={n} per_hour={n * 3600 // w} per_sec={n / w:.2f} window_s={win} "
            f"requested_s={dur} unparsed={bad}\n\n")
    for title, c in (("TOP #! SCRIPTS", scripts), ("TOP TEST FILES (bats/pytest env)", tests),
                     ("TOP CWDS", cwds)):
        f.write(title + "\n")
        for k, v in c.most_common(40):
            f.write(f"{v:7d}  {k}\n")
        f.write("\n")
    f.write("TOP (caller, script) PAIRS\n")
    for (par, s), v in pairs.most_common(40):
        f.write(f"{v:7d}  {par:<24} {s}\n")
print(open(path).read()[:4000])
print(f"verdict=ok script_execs={n} window_s={win} summary={path}")
PY
