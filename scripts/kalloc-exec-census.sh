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
# Output: summary.txt, ranking.tsv (every script ranked by execs per 10 min) and lint-drafts.txt
# (draft rows for paths newly above KALLOC_CENSUS_LINT_N=50 per 10 min; see RANKED SOURCES below).
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

# RANKED SOURCES and DRAFT LINT ROWS (plan KALLOC_TRIGGER_ELIMINATION W5, REPORT §3 Phase 5). Every
# script is ranked with its rate per 10 minutes, its class and its top caller (ranking.tsv), and
# each path above LINT_N per 10 min that the previous census in this directory did not already
# have above LINT_N gets a DRAFT lint row in lint-drafts.txt. Drafts only: nothing outside $OUT is
# written. LINT_N = 50: the 0.30 GiB/day target is ~1,990 execs per 10 min at 1.1 KiB each, so one
# source at 50 spends ~2.5% of it (~0.0074 GiB/day). On REPORT §7's census it flags exactly the
# production paths W1 fixed (cc-kqwait 282, cc-settings-parity 124 per 10 min) and none of the
# 31-41 tail (claude-accounts, cc-backlog, cc-in-kitty) that W4's call-site pass covers.
LINT_N="${KALLOC_CENSUS_LINT_N:-50}"
case "$LINT_N" in ''|*[!0-9]*) LINT_N=50 ;; esac
PREV=""
for d in "$HOME/.cache/kalloc-exec-census/"*/; do
  d="${d%/}"
  [ "$d" = "$OUT" ] && continue
  [ -f "$d/ranking.tsv" ] && PREV="$d/ranking.tsv"   # the glob is sorted, so the newest wins
done

/usr/bin/python3 -I - "$RAW" "$OUT" "$WIN" "$DUR" "$LINT_N" "$PREV" "$HOME" <<'PY'
import collections, json, os, sys
raw, out, win, dur = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
lint_n, prev, home = int(sys.argv[5]), sys.argv[6], sys.argv[7]
scripts, pairs, cwds, tests = (collections.Counter() for _ in range(4))
tested = collections.Counter()
callers = collections.defaultdict(collections.Counter)
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
    callers[s][os.path.basename(e.get("caller") or "?")] += 1
    cwds[e.get("cwd") or "?"] += 1
    env = e.get("env") or {}
    t = env.get("BATS_TEST_FILENAME") or env.get("PYTEST_CURRENT_TEST", "").split("::")[0]
    if t:
        tests[t] += 1
        tested[s] += 1
w = max(win, 1)


def klass(s):
    """test harness / our tools / package managers / other — the owner a lint row would go to."""
    if tested[s] * 2 >= scripts[s]:
        return "test"
    if "/.claude/" in s or "/claude-infrastructure/" in s or "/.worktrees/" in s:
        return "ours"
    if s.startswith(("/opt/homebrew/", "/usr/local/")) or "/node_modules/" in s:
        return "package"
    if s.startswith(home + "/"):
        return "home"
    return "other"


def fix(s, k, caller):
    if k == "test":
        return "route the harness's by-name stub through the cc-shim trampoline (W3), or exec it as <interp> <path>"
    if k == "package":
        return "call the package's real interpreter or Mach-O entry instead of its #! wrapper (upstream ask if ours cannot)"
    return f"at the {caller} call sites: exec it as <interp> {s}, never by path (exec-form lint, W4)"


rate = {s: c * 600 / w for s, c in scripts.items()}
above_before = set()
if prev:
    try:
        for row in open(prev, errors="replace"):
            f = row.rstrip("\n").split("\t")
            if len(f) >= 4 and f[0] != "rank" and float(f[3]) > lint_n:
                above_before.add(f[1])
    except (OSError, ValueError):
        above_before = set()
with open(os.path.join(out, "ranking.tsv"), "w") as f:
    f.write("rank\tscript\texecs\tper_10min\tshare_pct\tclass\ttop_caller\n")
    for i, (s, c) in enumerate(scripts.most_common(), 1):
        top = callers[s].most_common(1)[0][0]
        f.write(f"{i}\t{s}\t{c}\t{rate[s]:.1f}\t{100 * c / max(n, 1):.1f}\t{klass(s)}\t{top}\n")
drafts = [(s, c) for s, c in scripts.most_common() if rate[s] > lint_n and s not in above_before]
with open(os.path.join(out, "lint-drafts.txt"), "w") as f:
    f.write(f"# DRAFT lint rows — paths above {lint_n} #! execs per 10 min that "
            f"{'the previous census (' + prev + ') did not have above it' if prev else 'no previous census had (first census here)'}.\n"
            "# Drafts only: review, then add the real lint or call-site fix by hand.\n")
    for s, c in drafts:
        k, top = klass(s), callers[s].most_common(1)[0][0]
        f.write(f"DRAFT\t{s}\t{rate[s]:.1f}/10min\tclass={k}\tcaller={top}\tfix: {fix(s, k, top)}\n")
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
    f.write(f"\nRANKED SOURCES (per 10 min; full list in ranking.tsv)\n")
    for s, c in scripts.most_common(20):
        f.write(f"{rate[s]:9.1f}  {klass(s):<7} {s}\n")
    f.write(f"\nNEW ABOVE {lint_n} PER 10 MIN: {len(drafts)} — draft lint rows in lint-drafts.txt\n")
    for s, c in drafts:
        f.write(f"{rate[s]:9.1f}  {s}\n")
print(open(path).read()[:4000])
print(f"verdict=ok script_execs={n} window_s={win} new_above_n={len(drafts)} summary={path}")
PY
