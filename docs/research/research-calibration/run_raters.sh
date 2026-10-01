#!/usr/bin/env bash
# run_raters.sh - the OpenAI rater pass of the A3 replay, after the lane's usage window resets.
# Rater 1 (OpenAI) rates and re-reproduces every verifier-confirmed item; rater 3 (a fresh OpenAI process,
# the §3.8 two-vendor rule) rates only the items where raters 1 and 2 disagree on MATERIAL.
# usage: run_raters.sh <cache_dir> [HHMM to wait for]
set -euo pipefail
C="$1"
HERE="$(cd "$(dirname "$0")" && pwd)"
if [ -n "${2:-}" ]; then
  while [ "$(date +%H%M)" -lt "$2" ]; do sleep 60; done
fi
cd "$HERE"
python3 analyze.py raterjobs "$C" r1
python3 courier.py "$C/replay/r1-jobs.json" "$C/replay/rater1" 6
python3 analyze.py raterjobs "$C" r3
if [ -s "$C/replay/r3-jobs.json" ] && [ "$(python3 -c "import json;print(len(json.load(open('$C/replay/r3-jobs.json'))))")" -gt 0 ]; then
  python3 courier.py "$C/replay/r3-jobs.json" "$C/replay/rater3" 6
fi
echo "verdict=raters-done"
