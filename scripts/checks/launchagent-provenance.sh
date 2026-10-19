#!/usr/bin/env bash
# launchagent-provenance.sh — page on any com.reso.* LaunchAgent no repository shipped
# (lr-wake 2026-10-18, REPORT §5 Q9, the provenance half; Wave G).
#
# WHY. At 06:35Z on 2026-10-18 a lead session (pane 344) wrote ~/.reso/limit-recover/listeners/
# drain-v2.sh and installed it as com.reso.drain-to-next3. Over the next 12 h it queued 11 move
# batches and ran 30+ next4 rotates that each ended rc=1, re-rotating healthy sessions after next4's
# reset, until the operator paused it. Nothing ever said an agent had installed a daemon. Wave D
# denies the install at the tool call (validate-bash); this check is how one that got through, or
# predates the deny, gets SEEN.
#
# SHIPPED means either:
#   (a) this repo tracks a plist with the same file name (scripts/limit-recover/com.reso.*.plist,
#       launchd/staged/…), or
#   (b) the program it runs (the first ProgramArguments path that is a file, after any interpreter)
#       lives inside a git work tree — the operator's product repos install theirs from their own
#       checkouts (reso-management-app, reso-qa-runner, sevenrooms-bridge).
# A program under ~/.reso, /tmp or any other non-checkout path is UNSHIPPED.
#
# It never loads, unloads or edits an agent. Each unshipped agent is paged ONCE per plist content
# (lr-page-once.sh; a re-install with new bytes pages again).
#
# usage: launchagent-provenance.sh [--dir <LaunchAgents dir>] [--repo <repo root>] [--no-page]
# Prints one verdict line, then `UNSHIPPED <label> program=<path>` per offender.
# exit 0 = every com.reso.* agent shipped · 1 = unshipped agent(s) · 2 = no verdict (bad usage, dir
# unreadable, no plist reader)
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
DIR="${LA_PROVENANCE_DIR:-$HOME/Library/LaunchAgents}"
PAGE=1
while [ $# -gt 0 ]; do
  case "$1" in
    --dir) DIR="${2:-}"; shift 2 ;;
    --repo) REPO="${2:-}"; shift 2 ;;
    --no-page) PAGE=0; shift ;;
    -h|--help) sed -n '2,26p' "$0"; exit 0 ;;
    *) echo "launchagent-provenance: unknown argument: $1" >&2; exit 2 ;;
  esac
done
[ -d "$DIR" ] || { echo "launchagent-provenance: verdict=no-verdict reason=no dir $DIR"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "launchagent-provenance: verdict=no-verdict reason=python3 absent"; exit 2; }

shipped_names="$(git -C "$REPO" ls-files 2>/dev/null | awk -F/ '$NF ~ /^com\.reso\..*\.plist$/ { print $NF }' | sort -u)"

program_of() { # $1=plist → the program path ProgramArguments runs (first absolute arg that is a file)
  python3 - "$1" <<'PY' 2>/dev/null
import os, plistlib, sys
try:
    with open(sys.argv[1], "rb") as fh:
        d = plistlib.load(fh)
except Exception:
    sys.exit(1)
args = d.get("ProgramArguments") or ([d["Program"]] if d.get("Program") else [])
files = [a for a in args if isinstance(a, str) and a.startswith("/") and os.path.isfile(a)]
interp = ("bash", "sh", "zsh", "node", "python", "python3", "env", "perl", "ruby", "osascript")
for a in files:
    if os.path.basename(a) not in interp or a is files[-1]:
        print(a)
        break
PY
}
in_checkout() { # $1=path → 0 when it lives inside a git work tree
  local d
  d="$(dirname "$1")"
  [ -d "$d" ] && git -C "$d" rev-parse --is-inside-work-tree >/dev/null 2>&1
}

n=0 out=""
for f in "$DIR"/com.reso.*.plist; do
  [ -f "$f" ] || continue
  name="${f##*/}"; label="${name%.plist}"
  case $'\n'"$shipped_names"$'\n' in *$'\n'"$name"$'\n'*) continue ;; esac
  prog="$(program_of "$f")"
  if [ -n "$prog" ] && in_checkout "$prog"; then continue; fi
  n=$((n + 1))
  out="${out}UNSHIPPED $label program=${prog:-unknown}"$'\n'
  if [ "$PAGE" = 1 ]; then
    sum="$(shasum -a 256 "$f" 2>/dev/null | cut -c1-12)"
    # shellcheck source=/dev/null
    ( . "$REPO/scripts/limit-recover/lr-page-once.sh" && lr_page_once "la-provenance-$label-${sum:-x}" launchagent-provenance \
        "LaunchAgent $label runs ${prog:-an unknown program}, which no repository shipped (an agent-installed daemon?). Review it; nothing was unloaded." ) >/dev/null 2>&1
  fi
done
if [ "$n" -eq 0 ]; then
  echo "launchagent-provenance: verdict=clean dir=$DIR"
  exit 0
fi
echo "launchagent-provenance: verdict=unshipped n=$n dir=$DIR"
printf '%s' "$out"
exit 1
