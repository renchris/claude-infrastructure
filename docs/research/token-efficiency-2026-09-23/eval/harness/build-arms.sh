#!/bin/bash
# build-arms.sh [--dry-run] — freeze both instruction arms ONCE into $GATE_ROOT/arms, so every run of
# the gate loads byte-identical files even if the live files change mid-gate.
#   full = CLAUDE.global.md (as CLAUDE.md) + rules/00-mission-board.md
#   slim = CLAUDE.global.slim.md (as CLAUDE.md) + every CLAUDE.rules.slim.<name>.md as rules/<name>.md
#          (today one: 10-session-close.md) + rules/00-mission-board.md
# Both boards are rendered in-process from cc-mission's own board_text(), same rows and date; nothing
# under ~/.claude is written. The board form follows cc-mission's compact_mode() in BOTH arms, as it
# does live for either variant (render-compact is on since F4), so the arms differ only in instruction
# text. GATE_BOARD_SPLIT=1 reproduces the 2026-09 F1 rounds: full board in full, compact in slim.
#
# Layout as of 2026-10-03 (install.sh, docs/plans/INSTRUCTION_BUDGET.md D1-D3): ~/.claude/CLAUDE.md
# holds the SELECTED variant (slim), the full text deploys to CLAUDE.full.md, which nothing loads, and
# a non-full variant's rules deploy to ~/.claude/rules/. The arms are therefore built from the SOURCE
# files in a checkout ($GATE_SRC, default the checkout holding this harness), never from ~/.claude:
# copying ~/.claude/CLAUDE.md as "full" would gate slim against itself. That also lets a candidate slim
# edit be gated on its branch before it deploys. The full arm carries no CLAUDE.rules.slim.* file (the
# full text holds the close protocol itself, and install.sh deploys variant rules only for non-full).
#
# Sync: the slim file's `derived-from CLAUDE.global.md sha256:<16>` is compared with the full text in
# the same checkout. STALE (the full text gained a rule the slim never re-derived) is printed and
# recorded in ARMS.txt; GATE_REQUIRE_SYNC=1 refuses instead. It used to refuse always, keyed on a
# `cc-instructions-variant status` line that names the DEPLOYED files, which made the gate unbuildable.
#
# --dry-run: build both arms into a temp dir, print each arm's files with byte sizes, run the leak
# checks (arm contents, and gate-excludes.py --check for every account config dir present), then
# delete the temp dir. Writes nothing under $GATE_ROOT and calls no model.
set -euo pipefail
H=$(cd "$(dirname "$0")" && pwd)
DRY=0
case "${1:-}" in
  --dry-run|--selftest) DRY=1 ;;
  '') ;;
  *) echo "usage: build-arms.sh [--dry-run]" >&2; exit 2 ;;
esac
SRC=${GATE_SRC:-$(git -C "$H" rev-parse --show-toplevel)}
CC_MISSION=${CC_MISSION:-$HOME/.claude/bin/cc-mission}
FULL_SRC="$SRC/CLAUDE.global.md"
SLIM_SRC="$SRC/CLAUDE.global.slim.md"
for f in "$FULL_SRC" "$SLIM_SRC" "$CC_MISSION"; do
  [ -f "$f" ] || { echo "build-arms: missing $f" >&2; exit 2; }
done

full_h=$(shasum -a 256 "$FULL_SRC" | cut -c1-16)
slim_from=$(sed -n 's/.*derived-from CLAUDE\.global\.md sha256:\([0-9a-f]\{16\}\).*/\1/p' "$SLIM_SRC" | awk 'NR<=1')
if [ "$slim_from" = "$full_h" ]; then
  sync="in sync (derived from $full_h)"
else
  sync="STALE (slim derived from ${slim_from:-nothing recorded}, full text is now $full_h)"
  echo "build-arms: warning: CLAUDE.global.slim.md is $sync" >&2
  [ "${GATE_REQUIRE_SYNC:-0}" = 1 ] && { echo "build-arms: GATE_REQUIRE_SYNC=1 — refusing" >&2; exit 3; }
fi

if [ "$DRY" = 1 ]; then
  ARMS=$(mktemp -d "${TMPDIR:-/tmp}/build-arms-dry.XXXXXX")
  trap 'rm -rf -- "$ARMS"' EXIT
else
  # Build beside $G/arms and move it into place only after the leak checks pass, so a refused build
  # leaves no arms/ for run.sh to run (it checks only that CLAUDE.md exists). The old arms go first:
  # a failed rebuild must not leave the previous build looking current.
  G=${GATE_ROOT:-/tmp/tokeff-gate}
  mkdir -p "$G"
  rm -rf -- "$G/arms"
  ARMS=$(mktemp -d "$G/arms.build.XXXXXX")
  trap 'rm -rf -- "$ARMS"' EXIT
fi
mkdir -p "$ARMS/full/rules" "$ARMS/slim/rules"
cp "$FULL_SRC" "$ARMS/full/CLAUDE.md"
cp "$SLIM_SRC" "$ARMS/slim/CLAUDE.md"
slim_rules=""
for r in "$SRC"/CLAUDE.rules.slim.*.md; do
  [ -f "$r" ] || continue
  name=${r##*/CLAUDE.rules.slim.}
  cp "$r" "$ARMS/slim/rules/$name"
  slim_rules="$slim_rules $name"
done
python3 - "$CC_MISSION" "$ARMS" "${GATE_BOARD_SPLIT:-0}" <<'PY'
import importlib.machinery, importlib.util, sys, time
src, arms, split = sys.argv[1], sys.argv[2], sys.argv[3] == "1"
sys.dont_write_bytecode = True
loader = importlib.machinery.SourceFileLoader("ccm", src)
spec = importlib.util.spec_from_loader("ccm", loader)
m = importlib.util.module_from_spec(spec); loader.exec_module(m)
now = time.time()
rows = [m.evaluate(r, now) for r in m.load_rows()]
stale = m.rank([r for r in rows if m.is_stale(r)])
live = [r for r in rows if r.get("state") in m.OPERATOR_STATES]
stamp = time.strftime("%Y-%m-%d", time.localtime(now))
for arm, compact in (("full", False), ("slim", True)) if split else (("full", m.compact_mode()), ("slim", m.compact_mode())):
    open(f"{arms}/{arm}/rules/00-mission-board.md", "w").write(m.board_text(rows, stale, live, stamp, compact))
PY

# Leak checks: each arm holds exactly its own files.
bad=0
cmp -s "$FULL_SRC" "$ARMS/full/CLAUDE.md" || { echo "LEAK: full/CLAUDE.md is not CLAUDE.global.md" >&2; bad=1; }
cmp -s "$SLIM_SRC" "$ARMS/slim/CLAUDE.md" || { echo "LEAK: slim/CLAUDE.md is not CLAUDE.global.slim.md" >&2; bad=1; }
[ -n "$slim_rules" ] || { echo "LEAK: no CLAUDE.rules.slim.*.md in $SRC — the slim arm would lack its close rules" >&2; bad=1; }
for name in $slim_rules; do
  [ ! -e "$ARMS/full/rules/$name" ] || { echo "LEAK: slim rule $name is in the full arm" >&2; bad=1; }
done

{
  printf 'source: %s @ %s\n' "$SRC" "$(git -C "$SRC" rev-parse --short HEAD 2>/dev/null || echo '?')"
  printf 'slim sync: %s\n' "$sync"
  for arm in full slim; do
    printf '%s arm:\n' "$arm"
    ( cd "$ARMS/$arm" && find . -type f | sort | while IFS= read -r f; do
        printf '  %8s  %s\n' "$(wc -c < "$f" | tr -d ' ')" "${f#./}"
      done )
    printf '  %8s  total\n' "$(cat "$ARMS/$arm/CLAUDE.md" "$ARMS/$arm"/rules/*.md | wc -c | tr -d ' ')"
  done
} | tee "$ARMS/ARMS.txt"

if [ "$DRY" = 1 ]; then
  echo "memory excludes (run.sh --settings), per account config dir present:"
  for d in "$HOME/.claude-next" "$HOME/.claude-secondary" "$HOME/.claude-tertiary" "$HOME/.claude-quaternary"; do
    [ -d "$d" ] || continue
    echo " $d"
    python3 -B "$H/gate-excludes.py" --check "$d" || bad=1
  done
  [ "$bad" = 0 ] && echo "build-arms --dry-run: OK (temp arms removed; nothing written under \$GATE_ROOT)"
  exit "$bad"
fi
[ "$bad" = 0 ] || exit 4
( cd "$ARMS" && find . -type f | sort | grep -v MANIFEST | xargs shasum -a 256 ) | tee "$ARMS/MANIFEST.sha256"
chmod 755 "$ARMS"
mv -- "$ARMS" "$G/arms"
trap - EXIT
