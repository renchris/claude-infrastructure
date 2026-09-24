#!/usr/bin/env python3
"""Price the listing attachments (skill_listing, mcp_instructions_delta, deferred_tools_delta,
agent_listing_delta) and the ToolSearch round trips, from extract.sqlite (xdup=0).

Method (ESTIMATED, list-price weights; the fleet is quota-billed):
  A token that sits in a context's prefix is paid on every later response of that context:
    - response reads the cached prefix (cache_read >= READ_FLOOR tokens) -> in_price * cr_mult
    - otherwise the prefix was (re)written this response -> in_price * (1.25*share_5m + 2.0*share_1h),
      or 1.0x when nothing was cached.
  M(file, s) = sum of that per-token price over the file's responses with seq > s.
  Item cost = tokens(item) * M(file, resp_before(item)); tokens = chars / CPT.
  Priced twice: at each response's own model and re-priced at Opus 5.5 ($4 in, cr 0.05x).
  CPT: 3.0 chars/token is Claude Code's own estimate for Opus 5.x/Fable (fn xf -> 3 bytes/token)
  and matches headless /context (30.1k-char listing ~ 10k tokens); 2.6 chars/token is the ratio
  MEASURED on memory files by /context. Both are reported.
  "Static token value" = sum over contexts of M(file, first listing) = what one extra token in
  every context's initial listing costs over the window.
Usage: python3 listings_cost.py <extract.sqlite> <out.json>
"""

import json, sqlite3, sys, collections, bisect

DB, OUT = sys.argv[1], sys.argv[2]
READ_FLOOR = 20000
CPTS = (3.0, 2.6)
KINDS = (
    "skill_listing",
    "mcp_instructions_delta",
    "deferred_tools_delta",
    "agent_listing_delta",
)
con = sqlite3.connect(DB)

resp = collections.defaultdict(list)
for (
    f,
    seq,
    inp,
    c5,
    c1,
    cr,
    pin,
    crm,
) in con.execute("""select r.file, r.seq, r.input_tokens, r.cc_5m, r.cc_1h, r.cache_read,
        coalesce(p.in_per_mtok,0), coalesce(p.cr_mult,0.1) from resp r left join price p on p.model=r.model
        where r.xdup=0 and r.has_usage=1 order by r.file, r.seq"""):
    if cr >= READ_FLOOR:
        own, o55 = pin * crm, 4.0 * 0.05
    else:
        tot = (c5 or 0) + (c1 or 0)
        mult = (1.25 * c5 + 2.0 * c1) / tot if tot else 1.0
        own, o55 = pin * mult, 4.0 * mult
    resp[f].append((seq, own / 1e6, o55 / 1e6))
# suffix sums
suf = {}
for f, rows in resp.items():
    seqs = [r[0] for r in rows]
    a = [0.0] * (len(rows) + 1)
    b = [0.0] * (len(rows) + 1)
    for i in range(len(rows) - 1, -1, -1):
        a[i] = a[i + 1] + rows[i][1]
        b[i] = b[i + 1] + rows[i][2]
    suf[f] = (seqs, a, b)


def M(f, s):
    if f not in suf:
        return 0.0, 0.0
    seqs, a, b = suf[f]
    i = bisect.bisect_right(seqs, s)
    return a[i], b[i]


ctype = dict(con.execute("select file, ctx_type from ctx"))
atype = dict(con.execute("select file, agent_type from ctx"))
pslug = dict(con.execute("select file, project_slug from ctx"))
proj_is_reso = lambda f: "reso" if "reso" in (pslug.get(f) or "") else "other"
by_agent = collections.defaultdict(lambda: collections.defaultdict(float))
out = dict(method=__doc__.split("Usage:")[0].strip(), read_floor=READ_FLOOR)
agg = collections.defaultdict(lambda: collections.defaultdict(float))
first_listing = {}
for (
    f,
    sub,
    rb,
    ch,
    det,
) in con.execute(f"""select file, subkind, resp_before, chars, detail from item
        where kind='attachment' and xdup=0 and visible=1 and subkind in {KINDS}"""):
    own, o55 = M(f, rb)
    k = (sub, ctype.get(f))
    a = agg[k]
    a["n"] += 1
    a["chars"] += ch
    for cpt in CPTS:
        a[f"usd_own@{cpt}"] += ch / cpt * own
        a[f"usd_o55@{cpt}"] += ch / cpt * o55
    if sub == "skill_listing":
        b = by_agent[(ctype.get(f), atype.get(f) or "-", proj_is_reso(f))]
        b["n"] += 1
        b["chars"] += ch
        b["usd_own@3.0"] += ch / 3.0 * own
        b["usd_o55@3.0"] += ch / 3.0 * o55
    if sub == "skill_listing" and "initial=True" in (det or ""):
        if f not in first_listing:
            first_listing[f] = (rb, own, o55)
out["by_kind_ctx"] = [
    dict(kind=k[0], ctx_type=k[1], **{x: round(y, 2) for x, y in v.items()})
    for k, v in sorted(agg.items())
]
tot = collections.defaultdict(float)
for k, v in agg.items():
    for x, y in v.items():
        tot[(k[0], x)] += y
out["by_kind"] = {}
for (kind, x), y in tot.items():
    out["by_kind"].setdefault(kind, {})[x] = round(y, 2)
# value of one static token present in every context's initial skill listing position
sv = collections.defaultdict(lambda: [0, 0.0, 0.0])
for f, (rb, own, o55) in first_listing.items():
    s = sv[ctype.get(f)]
    s[0] += 1
    s[1] += own
    s[2] += o55
out["static_token_value"] = {
    k: dict(
        contexts=v[0],
        usd_per_1k_tokens_own=round(v[1] * 1000, 4),
        usd_per_1k_tokens_o55=round(v[2] * 1000, 4),
    )
    for k, v in sv.items()
}
allv = [sum(v[i] for v in sv.values()) for i in range(3)]
out["static_token_value"]["all"] = dict(
    contexts=allv[0],
    usd_per_1k_tokens_own=round(allv[1] * 1000, 4),
    usd_per_1k_tokens_o55=round(allv[2] * 1000, 4),
)

# ToolSearch-only responses = the round-trip a deferred tool costs
ts = con.execute("""select ctx_type, count(*), sum(usd_total), sum(usd_total_at_opus55), avg(cache_read)
        from resp_priced where xdup=0 and tool_use_names='ToolSearch' group by 1""").fetchall()
out["toolsearch_only_responses"] = [
    dict(
        ctx_type=a,
        n=b,
        usd_own=round(c, 2),
        usd_o55=round(d, 2),
        avg_cache_read=round(e),
    )
    for a, b, c, d, e in ts
]
out["toolsearch_any_responses"] = (
    con.execute("""select count(*), sum(usd_total), sum(usd_total_at_opus55) from resp_priced
        where xdup=0 and (','||tool_use_names||',') like '%,ToolSearch,%'""").fetchone()
)
out["fleet_total"] = con.execute(
    "select sum(usd_total), sum(usd_total_at_opus55) from resp_priced where xdup=0"
).fetchone()
out["skill_listing_by_ctx_agent_project"] = [
    dict(ctx_type=k[0], agent_type=k[1], project=k[2], **{x: round(y, 2) for x, y in v.items()})
    for k, v in sorted(by_agent.items(), key=lambda kv: -kv[1]["usd_own@3.0"])
]
json.dump(out, open(OUT, "w"), indent=1)
print(
    json.dumps(
        {
            k: out[k]
            for k in (
                "by_kind",
                "static_token_value",
                "toolsearch_only_responses",
                "toolsearch_any_responses",
                "fleet_total",
            )
        },
        indent=1,
    )
)
