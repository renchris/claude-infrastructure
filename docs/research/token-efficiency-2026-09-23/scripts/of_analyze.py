#!/usr/bin/env python3
"""of_analyze.py — price the per-line / per-item overhead in tool results, persistence-weighted.

Inputs (all under data/):
  output_formats.sqlite  tr (of_scan.py: per tool_result pattern bytes) + w (of_weights.py)
  extract.sqlite         item (resp_before, xdup), resp_priced (control totals)
  of_tokprobe.json       tokens per removed char for each pattern (count_tokens oracle)

Method:
  tokens(pattern) = bytes(pattern) x tokens_per_removed_char(pattern)        [ESTIMATED: tokenizer probe]
  $(pattern)      = sum over results of bytes x tpc x W(resp_before)          [W: of_weights.py]
Bytes are counted with xdup=0 (unique content); $ uses every result row because W already counts
only xdup=0 later responses (a copied result costs only where a continuation re-reads it).

Writes data/of_analyze.json and prints the tables used in measure/output-formats.md.
"""

import json, os, sqlite3, statistics
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
BASE = os.path.dirname(HERE)
D = os.path.join(BASE, "data")
db = sqlite3.connect(os.path.join(D, "output_formats.sqlite"))
db.execute("ATTACH ? AS x", (os.path.join(D, "extract.sqlite"),))
tp = json.load(open(os.path.join(D, "of_tokprobe.json")))

CPT = {
    "Bash": tp["bash_plain"]["chars_per_token"],
    "Read": tp["readnum_all"]["chars_per_token"],
    "json": tp["json_minify"]["chars_per_token"],
}
PLAIN_TPC = 1 / CPT["Bash"]


def cpt_for(tool):
    if tool == "Read":
        return CPT["Read"]
    if tool.startswith("mcp__"):
        return CPT["json"]
    return CPT["Bash"]


# pattern -> (sql expression for removable bytes, tokens per removed char, basis)
PAT = {
    "ansi_escapes": (
        "ansi_csi+ansi_osc+ansi_other",
        tp["ansi"]["tokens_per_removed_char"],
        "probe:ansi",
    ),
    "cr_overwritten": (
        "cr_over",
        tp["progress_cr"]["tokens_per_removed_char"],
        "probe:progress_cr",
    ),
    "progress_lines": (
        "progress",
        tp["progress_cr"]["tokens_per_removed_char"],
        "probe:progress_cr",
    ),
    "box_chars": (
        "box_chars",
        tp["box_chars_all"]["tokens_per_removed_char"],
        "probe:box_chars_all (±100 tok resolution)",
    ),
    "banner_rule_lines": (
        "banner_lines",
        tp["box_banner_lines"]["tokens_per_removed_char"],
        "probe:box_banner_lines (±100 tok resolution)",
    ),
    "abs_root_prefix": (
        "root_prefix",
        tp["paths_root"]["tokens_per_removed_char"],
        "probe:paths_root",
    ),
    "home_to_tilde": (
        "abs_home_n*14",
        tp["paths_home"]["tokens_per_removed_char"],
        "probe:paths_home",
    ),
    "json_minify": (
        "json_chars-json_mini",
        tp["json_minify"]["tokens_per_removed_char"],
        "probe:json_minify (±100 tok resolution)",
    ),
    "json_repeated_keys": (
        "json_rep_keys",
        1 / CPT["json"],
        "ESTIMATED: json base ratio; upper bound (columnar needs a header row)",
    ),
    "read_line_numbers_all": (
        "readnum",
        tp["readnum_all"]["tokens_per_removed_char"],
        "probe:readnum_all",
    ),
    "read_line_numbers_sparse10": (
        "readnum*0.9",
        tp["readnum_sparse10"]["tokens_per_removed_char"],
        "probe:readnum_sparse10 (keep every 10th)",
    ),
    "grep_repeated_path": (
        "grep_reppath",
        tp["paths_root"]["tokens_per_removed_char"],
        "ESTIMATED: path ratio",
    ),
    "table_padding_ws": (
        "pad_ws",
        tp.get("pad_ws", {}).get("tokens_per_removed_char", 0.15),
        "probe:pad_ws" if "pad_ws" in tp else "ESTIMATED 0.15 (space runs merge)",
    ),
    "shell_cwd_reset_note": ("cwd_reset", tp["cwd_reset"]["tokens_per_removed_char"], "probe:cwd_reset"),
    "auto_mode_denial_text": ("perm_denied", PLAIN_TPC, "ESTIMATED: plain ratio"),
    "warning_lines": ("warn_lines", PLAIN_TPC, "ESTIMATED: plain ratio"),
    "websearch_reminder": ("ws_reminder", PLAIN_TPC, "ESTIMATED: plain ratio"),
    "system_reminder_in_result": ("sysrem", PLAIN_TPC, "ESTIMATED: plain ratio"),
}

db.execute(
    """CREATE TEMP TABLE tj AS SELECT t.*, i.xdup AS xdup, w.w_own AS w_own, w.w_o55 AS w_o55, w.n_later AS n_later
       FROM tr t JOIN x.item i ON i.file=t.file AND i.tool_use_id=t.tool_use_id AND i.kind='tool_result'
       JOIN w ON w.file=i.file AND w.s=i.resp_before"""
)
out = {"cpt": CPT, "tokprobe": tp}

# ---- control: all visible items priced with W vs the fleet's cache $ ----
tot_cache = db.execute(
    "SELECT SUM(usd_cw5m+usd_cw1h+usd_cache_read), SUM(usd_total), SUM(usd_total_at_opus55), SUM((cc_5m*1.25+cc_1h*2+cache_read*0.05)*4/1e6) FROM x.resp_priced WHERE xdup=0"
).fetchone()
items = db.execute(
    """SELECT SUM(i.chars*w.w_own), SUM(i.chars*w.w_o55) FROM x.item i JOIN w ON w.file=i.file AND w.s=i.resp_before WHERE i.visible=1"""
).fetchone()
out["control"] = {
    "fleet_cache_usd_own": tot_cache[0],
    "fleet_total_usd_own": tot_cache[1],
    "fleet_total_usd_o55": tot_cache[2],
    "fleet_cache_usd_o55": tot_cache[3],
    "items_weighted_usd_own_at_plain_ratio": items[0] / CPT["Bash"],
    "items_weighted_usd_o55_at_plain_ratio": items[1] / CPT["Bash"],
}
print("CONTROL", out["control"])

# ---- tool results by tool ----
rows = db.execute(
    """SELECT tool, SUM(xdup=0), SUM(CASE WHEN xdup=0 THEN chars END), SUM(chars*w_own), SUM(chars*w_o55) FROM tj GROUP BY 1 ORDER BY 4 DESC"""
).fetchall()
bytool = []
for tool, n, ch, wo, w5 in rows:
    c = cpt_for(tool)
    bytool.append(
        {
            "tool": tool,
            "n": n,
            "chars": ch or 0,
            "tokens_est": (ch or 0) / c,
            "usd_own": wo / c,
            "usd_o55": w5 / c,
        }
    )
out["by_tool"] = bytool
tr_own = sum(r["usd_own"] for r in bytool)
tr_o55 = sum(r["usd_o55"] for r in bytool)
out["tool_results_usd_own"] = tr_own
out["tool_results_usd_o55"] = tr_o55
print(
    "TOOL RESULTS $own %.0f  $o55 %.0f  (%.1f%% / %.1f%% of fleet)"
    % (tr_own, tr_o55, 100 * tr_own / tot_cache[1], 100 * tr_o55 / tot_cache[2])
)
for r in bytool[:12]:
    print(
        "  %-40s n=%6d chars=%11d tok=%10.0f $own=%8.0f $o55=%8.0f"
        % (
            r["tool"][:40],
            r["n"],
            r["chars"],
            r["tokens_est"],
            r["usd_own"],
            r["usd_o55"],
        )
    )

# ---- patterns ----
pats = []
for name, (expr, tpc, basis) in PAT.items():
    b, n, wo, w5 = db.execute(
        f"SELECT SUM(CASE WHEN xdup=0 THEN {expr} END), SUM(CASE WHEN xdup=0 AND ({expr})>0 THEN 1 END), SUM(({expr})*w_own), SUM(({expr})*w_o55) FROM tj"
    ).fetchone()
    b = b or 0
    pats.append(
        {
            "pattern": name,
            "bytes": b,
            "results_affected": n or 0,
            "tokens_per_char": round(tpc, 4),
            "tokens_est": b * tpc,
            "usd_own": (wo or 0) * tpc,
            "usd_o55": (w5 or 0) * tpc,
            "basis": basis,
            "expr": expr,
        }
    )
pats.sort(key=lambda r: -r["usd_own"])
out["patterns"] = pats
print("PATTERNS")
for p in pats:
    print(
        "  %-28s bytes=%10d n=%6d tok=%9.0f $own=%7.0f $o55=%7.0f  [%s]"
        % (
            p["pattern"],
            p["bytes"],
            p["results_affected"],
            p["tokens_est"],
            p["usd_own"],
            p["usd_o55"],
            p["basis"],
        )
    )

# ---- Bash programs ----
REPO = "/Users/chrisren/Development/claude-infrastructure"
ours = set()
for sub in ("bin", "scripts", "hooks", "scripts/lib", "hooks/lib"):
    try:
        ours.update(os.listdir(os.path.join(REPO, sub)))
    except OSError:
        pass
ours.update({"cc-bats"})
prog = defaultdict(
    lambda: {
        "n": 0,
        "chars": [],
        "usd_own": 0.0,
        "usd_o55": 0.0,
        "ansi_n": 0,
        "ansi_b": 0,
        "box": 0,
        "banner": 0,
        "warn": 0,
        "pad": 0,
        "root": 0,
        "persisted": 0,
        "err": 0,
        "cwd": 0,
        "n_later": [],
    }
)
c = CPT["Bash"]
for (
    p,
    xd,
    ch,
    wo,
    w5,
    ab,
    ansi_n,
    box,
    ban,
    warn,
    pad,
    root,
    pers,
    err,
    cwd,
    nl,
) in db.execute(
    """SELECT program, xdup, chars, w_own, w_o55, ansi_csi+ansi_osc+ansi_other, ansi_csi_n, box_chars, banner_lines, warn_lines,
              pad_ws, root_prefix, persisted, is_error, cwd_reset, n_later FROM tj WHERE tool='Bash'"""
):
    d = prog[p]
    d["usd_own"] += ch * wo / c
    d["usd_o55"] += ch * w5 / c
    if xd:
        continue
    d["n"] += 1
    d["chars"].append(ch)
    d["n_later"].append(nl)
    if ab:
        d["ansi_n"] += 1
        d["ansi_b"] += ab
    d["box"] += box
    d["banner"] += ban
    d["warn"] += warn
    d["pad"] += pad
    d["root"] += root
    d["persisted"] += pers
    d["err"] += err
    d["cwd"] += cwd


def pct(a, q):
    if not a:
        return 0
    a = sorted(a)
    return a[min(len(a) - 1, int(q * len(a)))]


plist = []
for p, d in prog.items():
    if not d["n"]:
        continue
    plist.append(
        {
            "program": p,
            "ours": p in ours,
            "n": d["n"],
            "chars_total": sum(d["chars"]),
            "p50": pct(d["chars"], 0.5),
            "p90": pct(d["chars"], 0.9),
            "p99": pct(d["chars"], 0.99),
            "max": max(d["chars"]),
            "mean_later_reads": round(statistics.mean(d["n_later"]), 1),
            "usd_own": d["usd_own"],
            "usd_o55": d["usd_o55"],
            "ansi_results": d["ansi_n"],
            "ansi_bytes": d["ansi_b"],
            "box_chars": d["box"],
            "banner_bytes": d["banner"],
            "warn_bytes": d["warn"],
            "pad_ws_bytes": d["pad"],
            "root_prefix_bytes": d["root"],
            "persisted": d["persisted"],
            "err_rate": round(d["err"] / d["n"], 3),
            "cwd_reset_bytes": d["cwd"],
        }
    )
plist.sort(key=lambda r: -r["usd_own"])
out["programs_top60"] = plist[:60]
out["programs_ours"] = [r for r in plist if r["ours"]][:40]
out["bash_usd_own"] = sum(r["usd_own"] for r in plist)
out["bash_usd_o55"] = sum(r["usd_o55"] for r in plist)
print("PROGRAMS (top 30 by $own)")
for r in plist[:30]:
    print(
        "  %-26s %s n=%6d chars=%10d p50=%6d p90=%6d p99=%6d max=%6d reads=%6.1f $own=%7.0f $o55=%6.0f ansi=%d box=%d ban=%d warn=%d pad=%d pers=%d"
        % (
            r["program"][:26],
            "*" if r["ours"] else " ",
            r["n"],
            r["chars_total"],
            r["p50"],
            r["p90"],
            r["p99"],
            r["max"],
            r["mean_later_reads"],
            r["usd_own"],
            r["usd_o55"],
            r["ansi_results"],
            r["box_chars"],
            r["banner_bytes"],
            r["warn_bytes"],
            r["pad_ws_bytes"],
            r["persisted"],
        )
    )
print("OURS (top 25)")
for r in out["programs_ours"][:25]:
    print(
        "  %-26s n=%6d chars=%10d p50=%6d p90=%6d max=%6d $own=%6.0f $o55=%6.0f ansi=%d/%d box=%d ban=%d warn=%d pad=%d root=%d"
        % (
            r["program"][:26],
            r["n"],
            r["chars_total"],
            r["p50"],
            r["p90"],
            r["max"],
            r["usd_own"],
            r["usd_o55"],
            r["ansi_results"],
            r["ansi_bytes"],
            r["box_chars"],
            r["banner_bytes"],
            r["warn_bytes"],
            r["pad_ws_bytes"],
            r["root_prefix_bytes"],
        )
    )

# ---- size distribution of Bash results, and persistence ----
sz = [r[0] for r in db.execute("SELECT chars FROM tj WHERE tool='Bash' AND xdup=0")]
buckets = [
    (0, 1000),
    (1000, 4000),
    (4000, 10000),
    (10000, 20000),
    (20000, 30001),
    (30001, 10**9),
]
dist = []
for lo, hi in buckets:
    q = db.execute(
        "SELECT COUNT(*), SUM(chars), SUM(chars*w_own), SUM(chars*w_o55) FROM tj WHERE tool='Bash' AND chars>=? AND chars<?",
        (lo, hi),
    ).fetchone()
    qx = db.execute(
        "SELECT COUNT(*), SUM(chars) FROM tj WHERE tool='Bash' AND xdup=0 AND chars>=? AND chars<?",
        (lo, hi),
    ).fetchone()
    dist.append(
        {
            "lo": lo,
            "hi": hi,
            "n": qx[0],
            "chars": qx[1] or 0,
            "usd_own": (q[2] or 0) / c,
            "usd_o55": (q[3] or 0) / c,
        }
    )
out["bash_size_dist"] = dist
print("BASH SIZE DIST")
for d in dist:
    print(
        "  [%6d,%9d) n=%7d chars=%11d $own=%7.0f $o55=%7.0f"
        % (d["lo"], d["hi"], d["n"], d["chars"], d["usd_own"], d["usd_o55"])
    )
out["bash_n"] = len(sz)
out["bash_p50_p90_p99_max"] = [pct(sz, 0.5), pct(sz, 0.9), pct(sz, 0.99), max(sz)]
print("bash sizes p50/p90/p99/max", out["bash_p50_p90_p99_max"])

json.dump(out, open(os.path.join(D, "of_analyze.json"), "w"), indent=1, default=float)
