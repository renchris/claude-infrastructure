#!/usr/bin/env python3
"""Cost of every static-prefix source over the extract window (list-price weights; fleet is quota-billed).

Inputs: data/sp_composition.jsonl (sp_composition.py) + data/extract.sqlite (resp, price).
Population: contexts whose first response (seq=0) is in-window, xdup=0, not <synthetic>.

Token conversion (ESTIMATED from chars with per-source chars/token ratios MEASURED by headless
/context, see measure/static-prefix-raw/: context_*.txt rows and calib_counts.txt).

Two costings per source S in context c (tok = tokens(S) in c):
  A  'spec'     : tok*p_in*(w + r*(n_resp-1)), w = 2.0 if the first response wrote 1h cache else 1.25,
                  r = cache-read multiplier, p_in = first response's model input price.
  B  'observed' : per response i, the static span sits at [T0, T0+Stot] (T0 = system+tools, Stot = all
                  static blocks of c). read_frac_i = clamp((cache_read_i - T0)/Stot, 0, 1); the rest is
                  (re)written at response i's own TTL mix (1.25x 5m / 2x 1h) or, with no cache write,
                  billed as uncached input (1x). Priced at response i's model. Catches re-writes after TTL
                  expiry and first requests that hit a warm prefix (resume / fork).
Both are also re-priced at Opus 5.5 ($4 in, read 0.05x).
System prompt + tools (T0) is costed with B only: read when cache_read_i >= T0, else written.
Output: prints tables, writes measure/static-prefix.json (numbers only)."""

import json, os, sqlite3, statistics, re, sys
from collections import defaultdict

BASE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
DB = os.path.join(BASE, "data", "extract.sqlite")
COMP = os.path.join(BASE, "data", "sp_composition.jsonl")
OUTJ = os.path.join(BASE, "measure", "static-prefix-cost.json")

# chars per token, MEASURED (headless /context on the same files / rendered blocks)
R_FILE = {
    "global CLAUDE.md": 2.606,
    "mission board (~/.claude/rules/00-mission-board.md)": 2.52,
    "global rules essay (~/.claude/rules/agent-operating-lessons.md)": 2.61,
    "project CLAUDE.md [infra]": 2.60,
    "project CLAUDE.md [reso]": 2.43,
    "project rules agent-operating-lessons.md [infra]": 2.655,
    "project rules agent-operating-lessons.md [reso]": 2.53,
    "project rules bottle-generation-ledger.md [reso]": 2.376,
    "project rules agent-teams.md [reso]": 2.45,
    "MEMORY.md [infra]": 2.40,
    "MEMORY.md [reso]": 2.53,
}
R_DEFAULT_FILE = 2.5
R_BLOCK = {
    "skill_listing": 2.69,
    "agent_listing_delta": 2.70,
    "deferred_tools_delta": 2.0,
    "mcp_instructions_delta": 2.87,
    "hook_additional_context:SessionStart": 2.26,
    "hook_additional_context:UserPromptSubmit": 2.3,
    "session_context": 2.6,
}
R_SMALL = 2.4
SMALL = {
    "environment",
    "model",
    "auto_mode",
    "date",
    "remote_session_change",
    "total_tokens_reminder",
    "workflow_keyword_request",
    "hook_success:SessionStart",
    "ultra_effort_enter",
    "plan_mode",
}
INVISIBLE = {
    "hook_system_message",
    "prompt_snapshot",
    "hook_cancelled",
    "command_permissions",
    "goal_status",
    "auto_mode_exit",
    "hook_non_blocking_error",
    "structured_output",
    "deferred_tools_record",
}


def repo_of(instr, slug):
    for f in instr:
        m = re.search(r"/projects/([^/]+)/memory/MEMORY\.md$", f["path"] or "")
        if m:
            s = m.group(1)
            if "claude-infrastructure" in s:
                return "infra"
            if "reso-management-app" in s:
                return "reso"
            return "other"
    if "claude-infrastructure" in slug:
        return "infra"
    if "reso-management-app" in slug:
        return "reso"
    return "other"


def classify_file(p, repo):
    p = p or ""
    if re.search(r"/\.claude[^/]*/CLAUDE\.md$", p) and "/Development/" not in p:
        return "global CLAUDE.md"
    if p.endswith("/.claude/rules/00-mission-board.md") and "/Development/" not in p:
        return "mission board (~/.claude/rules/00-mission-board.md)"
    if (
        p.endswith("/.claude/rules/agent-operating-lessons.md")
        and "/Development/" not in p
    ):
        return "global rules essay (~/.claude/rules/agent-operating-lessons.md)"
    if "/Development/" not in p and "/.claude/rules/" in p:
        return "global rules other"
    if p.endswith("/memory/MEMORY.md"):
        return f"MEMORY.md [{repo}]"
    if "/.claude/rules/" in p:
        return f"project rules {os.path.basename(p)} [{repo}]"
    if p.endswith("CLAUDE.md") or p.endswith("CLAUDE.local.md"):
        return f"project CLAUDE.md [{repo}]"
    return "other memory file"


def main():
    c = sqlite3.connect(f"file:{DB}?mode=ro", uri=True)
    price = {m: (pi, cr) for m, pi, po, cr, src in c.execute("select * from price")}
    fleet_own, fleet_55 = c.execute(
        "select sum(usd_total), sum(usd_total_at_opus55) from resp_priced where xdup=0"
    ).fetchone()
    resp = defaultdict(list)
    for f, seq, model, inp, c5, c1, cr in c.execute(
        "select file, seq, model, input_tokens, cc_5m, cc_1h, cache_read from resp where xdup=0 order by file, seq"
    ):
        resp[f].append((seq, model, inp, c5, c1, cr))
    meta = {
        f: (ct, slug, ver)
        for f, ct, slug, ver in c.execute(
            "select file, ctx_type, project_slug, versions from ctx"
        )
    }
    # T0 per (ctx_type, version) = median first-response cache_read within the system+tools band (5k..30k)
    band = defaultdict(list)
    for f, rs in resp.items():
        if rs and rs[0][0] == 0 and 5000 < rs[0][5] < 30000:
            ct, slug, ver = meta[f]
            band[(ct, ver.split(",")[0])].append(rs[0][5])
            band[(ct, "*")].append(rs[0][5])
    T0med = {k: statistics.median(v) for k, v in band.items() if len(v) >= 5}

    src = defaultdict(
        lambda: {
            "ctx": 0,
            "tok": [],
            "A": 0.0,
            "A55": 0.0,
            "B": 0.0,
            "B55": 0.0,
            "Bct": defaultdict(float),
            "Aw": 0.0,
            "Aw55": 0.0,
            "B55ct": defaultdict(float),
            "by_ct": defaultdict(int),
            "by_repo": defaultdict(int),
        }
    )
    n_ctx = defaultdict(int)
    rewrites = defaultdict(lambda: [0, 0])
    per_ctx_static = defaultdict(list)
    for ln in open(COMP):
        rec = json.loads(ln)
        f = rec["file"]
        if f not in resp or "blocks" not in rec:
            continue
        rs = resp[f]
        if rs[0][0] != 0:
            continue
        ct, slug, ver = meta[f]
        n_ctx[ct] += 1
        repo = repo_of(rec["instr"], slug)
        toks = defaultdict(float)
        fsum = 0
        for fi in rec["instr"]:
            k = classify_file(fi["path"], repo)
            toks[k] += fi["chars"] / R_FILE.get(k, R_DEFAULT_FILE)
            fsum += fi["chars"]
        seen_instr = False
        for b in rec["blocks"]:
            t = b["t"]
            if t in ("user_prompt", "user_meta") or t.split(":")[0] in INVISIBLE:
                continue
            if t == "instructions":
                if not seen_instr and b["chars"] > fsum:
                    toks["memory-block wrapper text"] += (
                        b["chars"] - fsum
                    ) / R_DEFAULT_FILE
                seen_instr = True
                continue
            if t == "hook_success:SessionStart" and not b["vis"]:
                continue
            if t in R_BLOCK:
                toks[
                    {
                        "skill_listing": "skill listing",
                        "agent_listing_delta": "agent listing",
                        "deferred_tools_delta": "deferred tool names",
                        "mcp_instructions_delta": "MCP server instructions",
                        "hook_additional_context:SessionStart": "SessionStart hook context",
                        "hook_additional_context:UserPromptSubmit": "UserPromptSubmit hook context (1st prompt)",
                        "session_context": "session_context (gitStatus, userEmail)",
                    }[t]
                ] += b["chars"] / R_BLOCK[t]
            elif t in SMALL:
                toks["small setup attachments (env, model, auto_mode, date, ...)"] += (
                    b["chars"] / R_SMALL
                )
            else:
                toks["other pre-first-response attachments: " + t] += (
                    b["chars"] / R_SMALL
                )
        Stot = sum(toks.values())
        v0 = ver.split(",")[0]
        T0 = T0med.get((ct, v0), T0med[(ct, "*")])
        first = rs[0]
        _, m0, i0, c50, c10, cr0 = first
        p0, r0 = price.get(m0, (0, 0.1))
        w0 = 2.0 if c10 > 0 else 1.25
        n = len(rs)
        # per-response factors for B (same for every static source in c)
        fB = 0.0
        fB55 = 0.0
        sysB = 0.0
        sysB55 = 0.0
        for seq, m, inp, c5, c1, cr in rs:
            pi, rm = price.get(m, (0, 0.1))
            cc = c5 + c1
            wm = (c5 * 1.25 + c1 * 2.0) / cc if cc > 0 else 1.0
            rf = min(1.0, max(0.0, (cr - T0) / Stot)) if Stot > 0 else 1.0
            if seq > 0:
                rewrites[ct][0] += 1
                if rf < 0.5:
                    rewrites[ct][1] += 1
            fB += pi * (rf * rm + (1 - rf) * wm)
            fB55 += 4 * (rf * 0.05 + (1 - rf) * wm)
            sr = 1.0 if cr >= T0 else 0.0
            sysB += T0 * pi * (sr * rm + (1 - sr) * wm) / 1e6
            sysB55 += T0 * 4 * (sr * 0.05 + (1 - sr) * wm) / 1e6
        s = src["system prompt + tool schemas (T0)"]
        s["ctx"] += 1
        s["tok"].append(T0)
        s["B"] += sysB
        s["B55"] += sysB55
        s["Bct"][ct] += sysB
        s["B55ct"][ct] += sysB55
        s["by_ct"][ct] += 1
        s["by_repo"][repo] += 1
        per_ctx_static[ct].append(Stot)
        for k, tk in toks.items():
            if tk <= 0:
                continue
            s = src[k]
            s["ctx"] += 1
            s["tok"].append(tk)
            s["by_ct"][ct] += 1
            s["by_repo"][repo] += 1
            s["A"] += tk * p0 * (w0 + r0 * (n - 1)) / 1e6
            s["A55"] += tk * 4 * (w0 + 0.05 * (n - 1)) / 1e6
            s["Aw"] += tk * p0 * w0 / 1e6
            s["Aw55"] += tk * 4 * w0 / 1e6
            s["B"] += tk * fB / 1e6
            s["B55"] += tk * fB55 / 1e6
            s["Bct"][ct] += tk * fB / 1e6
            s["B55ct"][ct] += tk * fB55 / 1e6
    rows = []
    for k, s in src.items():
        rows.append(
            {
                "source": k,
                "contexts": s["ctx"],
                "tokens_median": round(statistics.median(s["tok"])),
                "tokens_total_per_ctx_sum": round(sum(s["tok"])),
                "by_ctx_type": dict(s["by_ct"]),
                "by_repo": dict(s["by_repo"]),
                "usd_spec_own": round(s["A"], 2),
                "usd_spec_opus55": round(s["A55"], 2),
                "usd_observed_own": round(s["B"], 2),
                "usd_observed_opus55": round(s["B55"], 2),
                "share_fleet_observed_own": round(s["B"] / fleet_own, 4),
                "share_fleet_observed_opus55": round(s["B55"] / fleet_55, 4),
                "usd_spec_first_write_own": round(s["Aw"], 2),
                "usd_spec_first_write_opus55": round(s["Aw55"], 2),
                "usd_observed_own_by_ctx_type": {k2: round(v, 2) for k2, v in s["Bct"].items()},
                "usd_observed_opus55_by_ctx_type": {k2: round(v, 2) for k2, v in s["B55ct"].items()},
            }
        )
    rows.sort(key=lambda r: -r["usd_observed_own"])
    print(
        f"fleet $ own={fleet_own:.0f} opus55={fleet_55:.0f}; contexts={dict(n_ctx)}; T0={ {k: v for k, v in T0med.items()} }"
    )
    print(
        f"{'source':62s} {'ctx':>5s} {'medtok':>7s} {'A own':>8s} {'B own':>8s} {'B 5.5':>8s} {'share':>6s}  by_ct"
    )
    tot = defaultdict(float)
    for r in rows:
        for x in (
            "usd_spec_own",
            "usd_spec_opus55",
            "usd_observed_own",
            "usd_observed_opus55",
        ):
            if not r["source"].startswith("system prompt"):
                tot[x] += r[x]
        print(
            f"{r['source'][:62]:62s} {r['contexts']:5d} {r['tokens_median']:7d} {r['usd_spec_own']:8.0f} {r['usd_observed_own']:8.0f} "
            f"{r['usd_observed_opus55']:8.0f} {100 * r['share_fleet_observed_own']:5.1f}%  {dict(r['by_ctx_type'])}"
        )
    print(
        "static attachments total (excl system+tools):",
        {k: round(v) for k, v in tot.items()},
        "share own",
        round(tot["usd_observed_own"] / fleet_own, 4),
        "share 5.5",
        round(tot["usd_observed_opus55"] / fleet_55, 4),
    )
    rw = {
        ct: {
            "later_responses": a,
            "static_mostly_rewritten": b,
            "rate": round(b / a, 4) if a else None,
        }
        for ct, (a, b) in rewrites.items()
    }
    print(
        "prefix re-write rate (later responses whose static span was >50% written):", rw
    )
    st = {
        ct: {
            "median_tokens": round(statistics.median(v)),
            "p90": round(statistics.quantiles(v, n=10)[8]),
        }
        for ct, v in per_ctx_static.items()
    }
    print("static attachment tokens per context:", st)
    json.dump(
        {
            "fleet_usd_own": fleet_own,
            "fleet_usd_opus55": fleet_55,
            "contexts": n_ctx,
            "T0_median": {f"{a}|{b}": v for (a, b), v in T0med.items()},
            "rows": rows,
            "static_total": tot,
            "rewrites": rw,
            "static_tokens_per_ctx": st,
        },
        open(OUTJ, "w"),
        indent=1,
    )


if __name__ == "__main__":
    main()
