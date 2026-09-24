#!/usr/bin/env python3
"""of_threshold_sim.py — what would a lower Bash inline cap (settings.bashOutputMaxChars) remove?

For a cap T, every Bash result longer than T would be replaced by Claude Code's <persisted-output>
message (2,000-char preview + ~260 chars of wrapper/path, per the 2.1.280 binary: Pye=2000, dce()).
GROSS saving = sum over such results of (chars - 2260) x W(resp_before) / chars_per_token.
It is an UPPER BOUND: it ignores the follow-up Read/grep/sed turns an agent spends to recover what
the preview dropped (each costs at least one extra response, and the re-read content persists too).
'Deliberate reads' (sed/cat/head/tail/awk/nl — the agent asked for those bytes) are split out,
because capping them mostly forces a re-read.

Also reports Bash $ by ctx_type (main / subagent / workflow_agent).
Writes data/of_threshold_sim.json.
"""

import json, os, sqlite3

HERE = os.path.dirname(os.path.abspath(__file__))
D = os.path.join(os.path.dirname(HERE), "data")
db = sqlite3.connect(os.path.join(D, "output_formats.sqlite"))
db.execute("ATTACH ? AS x", (os.path.join(D, "extract.sqlite"),))
tp = json.load(open(os.path.join(D, "of_tokprobe.json")))
cpt = tp["bash_plain"]["chars_per_token"]
PREVIEW = 2260
READS = ("sed", "cat", "head", "tail", "awk", "nl", "git show")
db.execute(
    """CREATE TEMP TABLE tj AS SELECT t.program, t.chars, i.xdup, w.w_own, w.w_o55, w.n_later, c.ctx_type
       FROM tr t JOIN x.item i ON i.file=t.file AND i.tool_use_id=t.tool_use_id AND i.kind='tool_result'
       JOIN w ON w.file=i.file AND w.s=i.resp_before JOIN x.ctx c ON c.file=t.file WHERE t.tool='Bash'"""
)
out = {"by_ctx": [], "caps": []}
for ct, n, ch, wo, w5, nl in db.execute(
    "SELECT ctx_type, SUM(xdup=0), SUM(CASE WHEN xdup=0 THEN chars END), SUM(chars*w_own), SUM(chars*w_o55), AVG(n_later) FROM tj GROUP BY 1"
):
    out["by_ctx"].append(
        {
            "ctx_type": ct,
            "n": n,
            "chars": ch,
            "usd_own": wo / cpt,
            "usd_o55": w5 / cpt,
            "mean_later_reads": nl,
        }
    )
    print(
        "%-15s n=%7d chars=%11d $own=%7.0f $o55=%7.0f later_reads=%.0f"
        % (ct, n, ch, wo / cpt, w5 / cpt, nl)
    )
ph = ",".join("?" * len(READS))
for T in (8000, 12000, 16000, 20000):
    for label, cond, args in (
        ("all", "1", ()),
        ("deliberate_reads", f"program IN ({ph})", READS),
        ("other", f"program NOT IN ({ph})", READS),
    ):
        n, wo, w5 = db.execute(
            f"SELECT SUM(xdup=0), SUM((chars-{PREVIEW})*w_own), SUM((chars-{PREVIEW})*w_o55) FROM tj WHERE chars>? AND {cond}",
            (T,) + args,
        ).fetchone()
        r = {
            "cap": T,
            "subset": label,
            "n": n or 0,
            "gross_usd_own": (wo or 0) / cpt,
            "gross_usd_o55": (w5 or 0) / cpt,
        }
        out["caps"].append(r)
        print(
            "cap=%6d %-17s n=%6d gross $own=%6.0f $o55=%6.0f"
            % (T, label, r["n"], r["gross_usd_own"], r["gross_usd_o55"])
        )
json.dump(out, open(os.path.join(D, "of_threshold_sim.json"), "w"), indent=1)
