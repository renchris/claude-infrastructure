#!/usr/bin/env python3
"""Grade sims.jsonl against the four criteria, plus a syntax check. Read-only except its own output.
 (a) foreground: no run_in_background
 (b) each call under 270 s: tool timeout <= 270000 and any inner `timeout N` <= 270
 (c) the wait still happens: for loop plans the original exit condition survives verbatim in the
     re-issued call (after undoing the '\\'' escaping) and a timeout is visible (echo rc=$?) or the
     loop keeps its own progress print; for `lower` plans the work is unchanged
 (d) no run_in_background (same test as (a); kept separate because the brief lists it)
 syntax: `bash -n` over the outer command, and over the inner `bash -c` script when there is one.
Usage: python3 -I grade.py <sample.json> <sims.jsonl> <workdir>"""

import json, os, re, shlex, subprocess, sys

S = {r["id"]: r for r in json.load(open(sys.argv[1]))}
W = sys.argv[3]
TO_RX = re.compile(r"(?:^|[;&|\s(])g?timeout\s+(?:-\S+\s+)*([0-9]+)([sm]?)\s")
COND = re.compile(r"(until|while)\s+(.*?);\s*do\b", re.S)


def syntax(cmd, tag):
    p = os.path.join(W, "syn_%s.sh" % tag)
    open(p, "w").write(cmd + "\n")
    r = subprocess.run(["/bin/bash", "-n", p], capture_output=True, text=True)
    return r.returncode == 0, r.stderr.strip()[:200]


rows = []
for l in open(sys.argv[2]):
    s = json.loads(l)
    c = s["call"]["command"]
    to = s["call"]["timeout"]
    orig = S[s["id"]]["cmd"]
    a = not s["call"].get("run_in_background")
    inner = [
        int(m.group(1)) * (60 if m.group(2) == "m" else 1) for m in TO_RX.finditer(c)
    ]
    b = to <= 270000 and all(
        x <= 270 for x in inner[:1]
    )  # the outermost bound is the first one
    ok_outer, err_outer = syntax(c, "%02d_outer" % s["n"])
    ok_inner, err_inner = True, ""
    m = re.match(r"\s*timeout\s+\d+\s+bash\s+-c\s+", c)
    if m:
        try:
            toks = shlex.split(c[m.end() :], posix=True)
            ok_inner, err_inner = syntax(toks[0], "%02d_inner" % s["n"])
        except ValueError as e:
            ok_inner, err_inner = False, str(e)
    # (c)
    if s["plan"] in ("lower",):
        cc = c == orig
        why_c = "work unchanged; if it outlasts 270 s the harness moves it to the background and notifies"
    else:
        oc = COND.search(orig)
        cond = oc.group(2).strip() if oc else None
        body = c.replace("'\\''", "'")
        same = cond is not None and cond in body
        if s["plan"].startswith("seq="):
            same = "break" in c and re.sub(r"\$\(seq 1 [0-9]+\)", "", c) == re.sub(
                r"\$\(seq 1 [0-9]+\)", "", orig
            )
        visible = "rc=$?" in c or "echo" in c
        cc = same and visible
        why_c = ("exit condition kept verbatim" if same else "CONDITION CHANGED") + (
            "; timeout visible" if visible else "; timeout NOT visible"
        )
    rows.append(
        {
            "n": s["n"],
            "plan": s["plan"],
            "a_fg": a,
            "b_under_270": b,
            "c_wait_kept": cc,
            "d_no_bg": a,
            "syntax_outer": ok_outer,
            "syntax_inner": ok_inner,
            "err": (err_outer or err_inner)[:160],
            "why_c": why_c,
            "orig_runtime_s": round(S[s["id"]]["rt"] or 0),
            "orig_rebuilt": S[s["id"]]["reb"],
        }
    )
allp = 0
for r in rows:
    p = (
        r["a_fg"]
        and r["b_under_270"]
        and r["c_wait_kept"]
        and r["d_no_bg"]
        and r["syntax_outer"]
        and r["syntax_inner"]
    )
    allp += p
    print(
        "%02d %-15s a=%d b=%d c=%d d=%d syn=%d/%d pass=%d | %s %s"
        % (
            r["n"],
            r["plan"],
            r["a_fg"],
            r["b_under_270"],
            r["c_wait_kept"],
            r["d_no_bg"],
            r["syntax_outer"],
            r["syntax_inner"],
            p,
            r["why_c"],
            r["err"],
        )
    )
print("all four criteria + syntax: %d/%d" % (allp, len(rows)))
json.dump(rows, open(os.path.join(W, "grades.json"), "w"), indent=1)
