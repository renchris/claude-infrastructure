#!/usr/bin/env python3
"""regate-bisect-arms.py — build the 2026-09-24 re-gate's F1 bisect arms under $GATE_ROOT/arms
(default /tmp/tokeff-gate, where the gate's frozen full/slim/slimclose arms live; see GATE.md § R2).

  scdod / scdone / sce0  slimclose with ONE slim paraphrase replaced by the full file's exact wording
                         ("Freeze the DoD" / "Done this turn" / the E0 row)
  scall                  all three replacements
  slimscp                slim with the full file's whole Session Close Protocol section
  fullmd                 the full CLAUDE.md with slim's rules files
  sctarget               the fix that shipped in CLAUDE.global.slim.md: slimclose minus slim's own
                         "✅ additionally requires" paraphrase, plus the close-question paragraph
Then: probe.sh <arm> T10-status-plan <first-rep> <last-rep> <config-dir> (reps above the gate's 1-15)."""

import os, shutil

A = os.path.join(os.environ.get("GATE_ROOT", "/tmp/tokeff-gate"), "arms")
full_txt = open(f"{A}/full/CLAUDE.md").read()
full = full_txt.splitlines(keepends=True)
slim = open(f"{A}/slim/CLAUDE.md").read().splitlines(keepends=True)
base = open(f"{A}/slimclose/CLAUDE.md").read()


def arm(name, text, src="slimclose"):
    d = f"{A}/{name}"
    shutil.rmtree(d, ignore_errors=True)
    shutil.copytree(f"{A}/{src}", d)
    open(f"{d}/CLAUDE.md", "w").write(text)
    print(f"{name}: {len(text)} chars")


def full_block(prefix):
    i = next(k for k, l in enumerate(full) if l.startswith(prefix))
    j = i + 1
    while j < len(full) and full[j].strip() and not full[j].startswith("|"):
        j += 1
    return "".join(full[i:j])


def slim_para(text, prefix):
    i = text.index(prefix)
    return text[i : text.index("\n", i) + 1]


e0_row = next(l for l in full if l.startswith("| _E0_ read-only"))
swaps = {
    "dod": (
        slim_para(base, "Freeze the DoD at intake:"),
        full_block("**Freeze the DoD at intake.**"),
    ),
    "done": (
        slim_para(base, "Done this turn, stated without hedging"),
        full_block('**"Done this turn" — assert with zero hedge IFF:**'),
    ),
    "e0": (
        slim_para(base, "- E0, read-only turn:"),
        "- E0, read-only turn (no tracked writes): "
        + e0_row.split("| — |", 1)[1].rsplit("|", 1)[0].strip()
        + "\n",
    ),
}
for name, keys in {
    "scdod": ["dod"],
    "scdone": ["done"],
    "sce0": ["e0"],
    "scall": ["dod", "done", "e0"],
}.items():
    t = base
    for k in keys:
        old, new = swaps[k]
        assert t.count(old) == 1, (name, k)
        t = t.replace(old, new)
    arm(name, t)


def section(lines, title):
    i = next(k for k, l in enumerate(lines) if l.startswith(f"## {title}"))
    j = next(k for k in range(i + 1, len(lines)) if lines[k].startswith("## "))
    return i, j


fi, fj = section(full, "Session Close Protocol")
si, sj = section(slim, "Session Close Protocol")
arm("slimscp", "".join(slim[:si] + full[fi:fj] + slim[sj:]), src="slim")
arm("fullmd", full_txt, src="slim")

t = base
i = t.index("✅ additionally requires:")
t = t[:i] + t[t.index("\n\n", i) + 2 :]
target = (
    'A close question ("are we done?", "good to close?", "100% complete?") asks about the task, not about '
    "what this session wrote. Before answering, find the scope (the `Scope (frozen):` line and the open items "
    'in the plan) and diff the repo against it. "This session changed nothing" is never grounds for ✅: an '
    "open plan item is open work, so drive it or answer `Good to close: no` and name it. No findable scope is "
    "an unknown, not a ✅.\n\n"
)
assert t.count("### The readout\n") == 1
arm("sctarget", t.replace("### The readout\n", target + "### The readout\n"))
