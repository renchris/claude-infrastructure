#!/bin/bash
# build-f4-arms.sh — freeze the two F4 arms into $GATE_ROOT/arms, plus a tasks dir and a rubric file.
#   full          = the gate's full arm: CLAUDE.md + agent-operating-lessons.md + the FULL board
#   compactboard  = the same, with the board rendered compact (cc-mission's own board_text(), compact on)
# Both boards are rendered in one process from the same rows and the same date stamp, so the arms
# differ in the board's rendering only. CLAUDE.md and the lessons file come from $F4_BASE_ARM (the
# round-3 frozen full arm) when it exists, else from the live files. Nothing under ~/.claude is written.
# Also writes $GATE_ROOT/tasks (symlinks: harness/tasks/T* + f4/tasks/T21) and $GATE_ROOT/rubrics.json.
set -euo pipefail
H=$(cd "$(dirname "$0")/.." && pwd)
G=${GATE_ROOT:-/tmp/tokeff-f4}
CC_MISSION=${CC_MISSION:-$HOME/.claude/bin/cc-mission}
BASE=${F4_BASE_ARM:-/tmp/tokeff-r3f1/arms/full}
rm -rf "$G/arms" "$G/tasks"; mkdir -p "$G/arms/full/rules" "$G/arms/compactboard/rules" "$G/tasks"
if [ -f "$BASE/CLAUDE.md" ] && [ -f "$BASE/rules/agent-operating-lessons.md" ]; then
  src_md="$BASE/CLAUDE.md"; src_les="$BASE/rules/agent-operating-lessons.md"
else
  src_md="$HOME/.claude/CLAUDE.md"; src_les="$HOME/.claude/rules/agent-operating-lessons.md"
fi
echo "base files: $src_md $src_les"
for a in full compactboard; do
  cp "$src_md" "$G/arms/$a/CLAUDE.md"; cp "$src_les" "$G/arms/$a/rules/"
done
python3 - "$CC_MISSION" "$G/arms" <<'PY'
import importlib.machinery, importlib.util, sys, time
src, arms = sys.argv[1], sys.argv[2]
loader = importlib.machinery.SourceFileLoader("ccm", src)
spec = importlib.util.spec_from_loader("ccm", loader)
m = importlib.util.module_from_spec(spec); loader.exec_module(m)
now = time.time()
rows = [m.evaluate(r, now) for r in m.load_rows()]
stale = m.rank([r for r in rows if m.is_stale(r)])
live = [r for r in rows if r.get("state") in m.OPERATOR_STATES]
stamp = time.strftime("%Y-%m-%d", time.localtime(now))
for arm, compact in (("full", False), ("compactboard", True)):
    open(f"{arms}/{arm}/rules/00-mission-board.md", "w").write(m.board_text(rows, stale, live, stamp, compact))
PY
for t in "$H"/tasks/T*/ "$H"/f4/tasks/T*/; do ln -s "${t%/}" "$G/tasks/$(basename "$t")"; done
python3 - "$H/rubrics.json" "$H/f4/rubrics-t21.json" "$G/rubrics.json" <<'PY'
import json, sys
r = json.load(open(sys.argv[1])); r.update(json.load(open(sys.argv[2])))
json.dump(r, open(sys.argv[3], "w"), indent=1)
PY
( cd "$G/arms" && find . -type f | sort | grep -v MANIFEST | xargs shasum -a 256 ) | tee "$G/arms/MANIFEST.sha256"
wc -c "$G"/arms/*/CLAUDE.md "$G"/arms/*/rules/*.md
