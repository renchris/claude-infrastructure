#!/usr/bin/env bash
# root_capture.sh — the ROOT half of the data.kalloc.1024 attribution (backlog a417ab59e8f5).
#
#   sudo bash root_capture.sh [--secs 300] [--sysdiagnose]
#
# What the no-root work established (kalloc-ratchet-2026-10.md): the zone's changes move 1:1 with
# the kernel `cred` zone, so the ratchet is driven by credential churn. What it could not see is
# WHICH processes create those credentials: a 1 s `ps` poll misses short-lived execs. Endpoint
# Security sees every exec, and needs root. This runs `eslogger exec` for --secs while sampling the
# zones every 20 s, and writes rows in sandbox_churn.py's format, so attribute.py ranks process
# names against Δdata.kalloc.1024 directly:
#     python3 attribute.py <outdir>/windows.jsonl
# --sysdiagnose also takes a sysdiagnose (for the Apple Feedback report) while the zone is high.
#
# Why it is staged at the alarm reboot: the reboot erases the zone, and the ratchet's per-boot
# history is what makes a high-zone sysdiagnose worth attaching. eslogger needs Full Disk Access
# for the app that launched it (kitty); without it eslogger exits NOT_PERMITTED and this script
# says so and still writes the zprint snapshot.
set -uo pipefail
SECS=300; SYSDIAG=0
while [ $# -gt 0 ]; do
  case "$1" in
    --secs) SECS="${2:?}"; shift 2 ;;
    --sysdiagnose) SYSDIAG=1; shift ;;
    *) echo "usage: sudo bash $0 [--secs N] [--sysdiagnose]" >&2; exit 2 ;;
  esac
done
[ "$(id -u)" = 0 ] || { echo "root_capture: run under sudo (eslogger needs root)" >&2; exit 2; }
USER_HOME="$(dscl . -read "/Users/${SUDO_USER:-$USER}" NFSHomeDirectory 2>/dev/null | awk '{print $2}')"
OUT="${USER_HOME:-/var/root}/.claude/logs/kalloc-root-capture-$(date +%Y%m%dT%H%M%S)"
mkdir -p "$OUT"
HERE="$(cd "$(dirname "$0")" && pwd -P)"

/usr/bin/zprint -L > "$OUT/zprint-start.txt" 2>&1
echo "root_capture: zprint snapshot → $OUT/zprint-start.txt"

# eslogger emits one JSON object per line; keep only what attribution needs.
/usr/bin/eslogger exec > "$OUT/exec.raw.jsonl" 2> "$OUT/eslogger.err" &
ES=$!
/usr/bin/python3 - "$OUT" "$SECS" <<'PY' &
import json, subprocess, sys, time
out, secs = sys.argv[1], int(sys.argv[2])
def zones():
    z = {}
    for line in subprocess.run(["/usr/bin/zprint", "-L"], capture_output=True, text=True).stdout.splitlines():
        f = line.split()
        if len(f) >= 7 and f[1].isdigit() and f[6].isdigit():
            z[f[0]] = int(f[6])
    return z
with open(out + "/zones.jsonl", "w") as fh:
    end = time.time() + secs
    while time.time() < end:
        z = zones()
        fh.write(json.dumps({"t": time.time(), "k": z.get("data.kalloc.1024"), "cred": z.get("cred")}) + "\n")
        fh.flush()
        time.sleep(20)
PY
ZS=$!
sleep "$SECS"
kill "$ES" 2>/dev/null; wait "$ZS" 2>/dev/null; wait "$ES" 2>/dev/null
if grep -qi 'not.permitted\|NOT_PERMITTED\|Full Disk' "$OUT/eslogger.err"; then
  echo "root_capture: eslogger was REFUSED (grant Full Disk Access to the terminal app, then re-run):"
  head -3 "$OUT/eslogger.err"
else
  /usr/bin/python3 - "$OUT" <<'PY'
import bisect, collections, json, os, sys
out = sys.argv[1]
zs = [json.loads(l) for l in open(out + "/zones.jsonl")]
edges = [z["t"] for z in zs]
wins = [collections.Counter() for _ in zs]
n = 0
for line in open(out + "/exec.raw.jsonl", errors="replace"):
    try:
        e = json.loads(line)
        t = e["time"]
        # eslogger time is ISO-8601 with NANOseconds; python 3.9's fromisoformat takes at most 6 digits
        import re
        from datetime import datetime
        ts = datetime.fromisoformat(re.sub(r"(\.\d{6})\d+", r"\1", t).replace("Z", "+00:00")).timestamp()
        tgt = e["event"]["exec"]["target"]
        name = os.path.basename(tgt["executable"]["path"])
        tag = "setuid:" if tgt.get("audit_token", {}).get("euid") != tgt.get("audit_token", {}).get("ruid") else ""
    except Exception:
        continue
    i = bisect.bisect_right(edges, ts)
    if 0 < i < len(zs):
        wins[i][tag + name] += 1
        n += 1
with open(out + "/windows.jsonl", "w") as fh:
    for i in range(1, len(zs)):
        fh.write(json.dumps({"t": zs[i]["t"], "d_kalloc1024": zs[i]["k"] - zs[i-1]["k"],
                             "d_cred": zs[i]["cred"] - zs[i-1]["cred"],
                             "births_by_comm": dict(wins[i].most_common(60))}) + "\n")
print(f"root_capture: {n} execs joined into {len(zs)-1} windows → {out}/windows.jsonl")
PY
  rm -f "$OUT/exec.raw.jsonl"          # large; the joined windows keep what attribution needs
  echo "root_capture: rank it with  python3 $HERE/attribute.py $OUT/windows.jsonl --min-births 30"
fi
if [ "$SYSDIAG" = 1 ]; then
  echo "root_capture: taking a sysdiagnose (several minutes)…"
  /usr/bin/sysdiagnose -u -f "$OUT" >/dev/null 2>&1 && echo "root_capture: sysdiagnose → $OUT"
fi
chown -R "${SUDO_USER:-root}" "$OUT" 2>/dev/null
echo "verdict=captured dir=$OUT"
