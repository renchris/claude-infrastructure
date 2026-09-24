#!/bin/bash
# build-arms.sh — freeze both instruction arms ONCE into $GATE_ROOT/arms, so every run of
# the gate loads byte-identical files even if the live files change mid-gate.
#   full = ~/.claude/CLAUDE.md + ~/.claude/rules/{00-mission-board,agent-operating-lessons}.md
#   slim = ~/.claude/CLAUDE.slim.md + the COMPACT mission board (rendered in-process from
#          cc-mission's own board_text(), same rows and date as the full board; nothing under
#          ~/.claude is written)
# Refuses unless `cc-instructions-variant status` reports the slim file in sync.
set -euo pipefail
G=${GATE_ROOT:-/tmp/tokeff-gate}
CC_MISSION=${CC_MISSION:-$HOME/.claude/bin/cc-mission}
cc-instructions-variant status | grep -q 'CLAUDE.slim.md: in sync' \
  || { echo "build-arms: CLAUDE.slim.md is not in sync with CLAUDE.md — refusing" >&2; exit 3; }
rm -rf "$G/arms"; mkdir -p "$G/arms/full/rules" "$G/arms/slim/rules"
cp "$HOME/.claude/CLAUDE.md" "$G/arms/full/CLAUDE.md"
cp "$HOME/.claude/rules/agent-operating-lessons.md" "$G/arms/full/rules/"
cp "$HOME/.claude/CLAUDE.slim.md" "$G/arms/slim/CLAUDE.md"
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
for arm, compact in (("full", False), ("slim", True)):
    open(f"{arms}/{arm}/rules/00-mission-board.md", "w").write(m.board_text(rows, stale, live, stamp, compact))
PY
( cd "$G/arms" && find . -type f | sort | grep -v MANIFEST | xargs shasum -a 256 ) | tee "$G/arms/MANIFEST.sha256"
wc -c "$G"/arms/*/CLAUDE.md "$G"/arms/*/rules/*.md
