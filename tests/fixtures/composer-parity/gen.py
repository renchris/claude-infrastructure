"""Regenerate the synthetic screens of this directory: `python3 -I gen.py` (writes beside itself).

Claude Code 2.1.293 screen states for tests/composer-parser-parity.bats, from the reader sweep
(docs/research/recycle-failures-kitty-2026-10-10/slot-reader-sweep.md section 3). The escape styles
are copied from a live pane capture taken for that sweep: border colour 136, box row "❯" plus
U+00A0, slash text 177:185:249, menu rows grey 153, the highlighted menu row bold (SGR 22;1).
Each state is written as NAME.txt (plain) and NAME.ansi, 62 rows tall, at 38 and 57 columns.
"""
import os
import textwrap

OUT = os.path.dirname(os.path.abspath(__file__))
E = "\x1b"
R = E + "[m"
def border(w): return (R + E + "[38:2:136:136:136m" + "─" * w, "─" * w)
def box(text, w, slash=False, faint=False):
    # first row "❯\xa0text", continuation rows "  text"
    avail = w - 2
    if not text:
        return [(R + "❯\xa0", "❯\xa0")]
    parts = textwrap.wrap(text, avail) or [text]
    rows = []
    for i, p in enumerate(parts):
        lead = "❯\xa0" if i == 0 else "  "
        if faint:  ink = E + "[2m" + p + E + "[22m"
        elif slash and i == 0: ink = E + "[38:2:177:185:249m" + p
        else: ink = p
        rows.append((R + lead + ink, lead + p))
    return rows
def footer(w, pane="134", sid="6defb493"):
    a = f"  (1) #{pane} {sid} 47% · wt-pool-7 (1c99e4c04)  cc-13"
    b = "  ⏵⏵ auto mode on · 1 shell · ← for agents"
    cut = lambda s: s if len(s) <= w else s[: w - 1] + "…"
    return [(R + E + "[38:2:153:153:153m" + cut(a), cut(a)), (R + E + "[38:2:255:193:7m" + cut(b), cut(b))]
def menu(w, typed="/exit", hi=0):
    items = [("/exit", "Exit the CLI"), ("/context", "Visualize current context usage as a colored grid"),
             ("/usage-credits", "Configure usage credits or request them from your admin")]
    if typed == "/e":
        items = [("/exit", "Exit the CLI"), ("/export", "Export the current conversation to a file or clipboard"),
                 ("/effort", "Set effort level for model usage")]
    col = 18 if w < 45 else 24
    rows = []
    for k, (cmd, desc) in enumerate(items):
        first = True
        for d in textwrap.wrap(desc, max(8, w - col - 2)):
            if first:
                head = ("  ❯ " if k == hi else "    ") + cmd
                head = head.ljust(col)
                line = head + d
                ansi = (R + "  " + E + "[38:2:177:185:249m❯ /" + E + "[22;1m" + cmd[1:] + E + "[22m" + " " * (col - 4 - len(cmd)) + d) if k == hi \
                       else (R + "  " + E + "[38:2:153:153:153m  " + cmd.ljust(col - 4) + d)
                first = False
            else:
                line = " " * col + d
                ansi = R + " " * col + E + "[38:2:153:153:153m" + d
            rows.append((ansi, line))
    return rows
def transcript(w, n=10):
    t = ("⏺ The inbox watcher was woken by the two recycle-held messages I already reported, so nothing new "
         "came in; I've turned it back on. It's still running five evidence slots and three skeptic slots.")
    rows = [(R + "  " + l, "  " + l) for l in textwrap.wrap(t, w - 2)]
    return [(R, "")] * max(0, n - len(rows)) + rows + [(R, "")]
def spinner(w):
    s = "✻ Sautéing… (12s · ↓ 1.2k tokens · esc to interrupt)"
    s = s if len(s) <= w else s[: w - 1] + "…"
    return [(R + E + "[38:2:215:119:87m" + s, s), (R, "")]
def dialog(w):
    rows = ["  Background work is running", "  The following will stop when you exit:", "",
            "  shell · sleep 1800", "", "  ❯ 1. Exit and stop tasks", "    2. Move to background and exit",
            "    3. Stay", "", "  Enter to confirm · Esc to cancel", ""]
    out = []
    for r in rows:
        for p in (textwrap.wrap(r, w, subsequent_indent="    ") if r.strip() else [""]):
            out.append((R + p, p))
    return out
def write(name, rows, height=62):
    rows = [(R, "")] * max(0, height - len(rows)) + rows
    with open(f"{OUT}/{name}.ansi", "w") as f: f.write("\n".join(a for a, _ in rows) + "\n")
    with open(f"{OUT}/{name}.txt", "w") as f: f.write("\n".join(p for _, p in rows) + "\n")
DRAFT = "fix the build then ping me"
for w in (38, 57):
    B = border(w)
    write(f"empty-{w}c", transcript(w) + [B] + box("", w) + [B] + footer(w))
    write(f"draft-{w}c", transcript(w) + [B] + box(DRAFT, w) + [B] + footer(w))
    write(f"exit-nomenu-{w}c", transcript(w) + [B] + box("/exit", w, slash=True) + [B] + footer(w))
    write(f"exit-menu-own-{w}c", transcript(w) + menu(w) + [B] + box("/exit", w, slash=True) + [B] + footer(w))
    # the box holds the prefix /e while the highlight is /exit: a CR would submit /exit, not /e
    write(f"e-prefix-menu-{w}c", transcript(w) + menu(w, "/e") + [B] + box("/e", w, slash=True) + [B] + footer(w))
    write(f"midturn-exit-menu-own-{w}c", transcript(w) + spinner(w) + menu(w) + [B] + box("/exit", w, slash=True) + [B] + footer(w))
    # the box holds /exit while the highlight sits on /export: a CR would submit /export
    write(f"exit-menu-foreign-{w}c", transcript(w) + menu(w, "/e", hi=1) + [B] + box("/exit", w, slash=True) + [B] + footer(w))
    write(f"bgdialog-above-empty-{w}c", transcript(w) + dialog(w) + [B] + box("", w) + [B] + footer(w))
    write(f"bgdialog-below-{w}c", transcript(w) + [B] + box("/exit", w, slash=True) + [B] + dialog(w))
    # hypothetical: a dialog whose highlighted option starts with a slash, over an EMPTY box
    dl = [(R + "  Add a working directory", "  Add a working directory"), (R, ""),
          (R + "  ❯ /Users/me/src", "  ❯ /Users/me/src"),
          (R + "    /tmp", "    /tmp"), (R, ""),
          (R + "  Enter to confirm · Esc to cancel", "  Enter to confirm · Esc to cancel"), (R, "")]
    write(f"pathdialog-above-empty-{w}c", transcript(w) + dl + [B] + box("", w) + [B] + footer(w))
