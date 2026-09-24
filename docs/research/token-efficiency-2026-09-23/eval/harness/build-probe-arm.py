#!/usr/bin/env python3
"""build-probe-arm.py <name> <anchor-in-full> <anchor-in-slim> — build a probe arm = the frozen slim arm
with ONE block copied verbatim from the frozen full arm, inserted after the slim line that starts with
<anchor-in-slim>. The block is the full-arm line starting with <anchor-in-full> plus its indented
continuation lines. Writes $GATE_ROOT/arms/<name>/ (run build-arms.sh first).

The 2026-09-24 probe was:
  build-probe-arm.py slimclose "- **✅ is a safe-to-close assertion, not a vibe.**" "- Close certificate:"
Then: probe.sh slimclose T10-status-plan 11 15 <config-dir>  (and T08-close-dirty), judged mixed with
the gate's own dossiers by probe-judge.py. Use the same recipe to bisect the rest of the slim diff.
"""

import os, shutil, sys

name, anchor_full, anchor_slim = sys.argv[1:4]
A = os.path.join(os.environ.get("GATE_ROOT", "/tmp/tokeff-gate"), "arms")
full = open(f"{A}/full/CLAUDE.md").read().splitlines(keepends=True)
start = next(i for i, l in enumerate(full) if l.startswith(anchor_full))
end = start + 1
while end < len(full) and full[end].startswith("  "):
    end += 1
slim = open(f"{A}/slim/CLAUDE.md").read().splitlines(keepends=True)
at = next(i for i, l in enumerate(slim) if l.startswith(anchor_slim)) + 1
d = f"{A}/{name}"
shutil.rmtree(d, ignore_errors=True)
shutil.copytree(f"{A}/slim", d)
open(f"{d}/CLAUDE.md", "w").write("".join(slim[:at] + full[start:end] + slim[at:]))
print(
    f"{name}: inserted full lines {start + 1}-{end} ({end - start} lines) after slim line {at}"
)
