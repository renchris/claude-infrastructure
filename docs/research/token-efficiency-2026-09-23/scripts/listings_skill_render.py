#!/usr/bin/env python3
"""Per-skill presence in the rendered skill_listing attachments (what the model actually saw).

For every INITIAL skill_listing attachment (xdup=0, per extract.sqlite item rows) this re-reads the
transcript line, parses rendered[].content, and classifies each "- <name>[: <desc>]" entry as
described / name-only. Aggregates by ctx_type and by version. Also records the header length
(text before the first entry) and the max-entry-length so the budget can be reconstructed.

Usage: nice -n 10 python3 listings_skill_render.py <extract.sqlite> <out.json>
Only prints aggregates; never dumps transcript content.
"""

import json, re, sqlite3, sys, collections
from multiprocessing import Pool

DB, OUT = sys.argv[1], sys.argv[2]
ENTRY = re.compile(r"^- (\S+?)(?:: (.*))?$")  # names may contain ':' (plugin:skill)


def work(args):
    path, seqs = args
    seqs = set(seqs)
    res = []
    n = -1
    try:
        with open(path, "rb") as f:
            # item_seq in the extract counts in-window items; recount cheaply by re-deriving is
            # expensive, so instead match every skill_listing attachment whose initial flag is set
            # and whose timestamp is in-window; seqs is used only as an expected count.
            for line in f:
                if b'"skill_listing"' not in line:
                    continue
                try:
                    r = json.loads(line)
                except Exception:
                    continue
                if r.get("type") != "attachment":
                    continue
                a = r.get("attachment") or {}
                if a.get("type") != "skill_listing":
                    continue
                if (r.get("timestamp") or "") < "2026-09-09T00:00:00Z":
                    continue
                if not a.get("isInitial", True) is True:
                    continue
                txt = "".join(
                    (x or {}).get("content", "") for x in (r.get("rendered") or [])
                )
                if not txt:
                    continue
                lines = txt.split("\n")
                first = next(
                    (i for i, l in enumerate(lines) if l.startswith("- ")), len(lines)
                )
                header = "\n".join(lines[:first])
                described, nameonly = [], []
                for l in lines[first:]:
                    m = ENTRY.match(l)
                    if not m:
                        continue
                    (described if m.group(2) else nameonly).append(m.group(1).strip())
                res.append(
                    dict(
                        version=r.get("version"),
                        uuid=r.get("uuid"),
                        chars=len(txt),
                        header_chars=len(header),
                        described=described,
                        nameonly=nameonly,
                        entries_chars=len("\n".join(lines[first:])),
                    )
                )
    except Exception as e:
        return path, [], str(e)
    return path, res, None


def main():
    con = sqlite3.connect(DB)
    rows = con.execute("""select i.file, c.ctx_type, group_concat(i.item_seq), group_concat(i.uid, '|')
        from item i join ctx c on c.file=i.file
        where i.kind='attachment' and i.subkind='skill_listing' and i.xdup=0
          and i.detail like '%initial=True%' group by i.file""").fetchall()
    ctype = {r[0]: r[1] for r in rows}
    keep_uids = {r[0]: set(u.split("#")[0] for u in r[3].split("|")) for r in rows}
    with Pool(4) as p:
        out = p.map(work, [(r[0], []) for r in rows], chunksize=8)
    agg = collections.defaultdict(lambda: collections.Counter())
    nlist = collections.Counter()
    sizes = collections.defaultdict(list)
    examples = {}
    errs = 0
    for path, res, err in out:
        if err:
            errs += 1
        ct = ctype[path]
        for x in res:
            if x["uuid"] not in keep_uids[path]:
                continue
            key = ct
            nlist[key] += 1
            sizes[key].append(
                (
                    x["chars"],
                    x["header_chars"],
                    x["entries_chars"],
                    len(x["described"]),
                    len(x["nameonly"]),
                )
            )
            for s in x["described"]:
                agg[key][(s, "d")] += 1
            for s in x["nameonly"]:
                agg[key][(s, "n")] += 1
            examples.setdefault(
                (key, x["chars"] // 1000),
                dict(
                    file=path,
                    described=x["described"],
                    nameonly=x["nameonly"],
                    header_chars=x["header_chars"],
                    version=x["version"],
                ),
            )
    skills = sorted({k[0] for c in agg.values() for k in c})
    table = {}
    for s in skills:
        table[s] = {
            ct: dict(
                described=agg[ct][(s, "d")],
                nameonly=agg[ct][(s, "n")],
                listings=nlist[ct],
            )
            for ct in nlist
        }
    size_summary = {}
    for ct, v in sizes.items():
        v.sort()
        size_summary[ct] = dict(
            n=len(v),
            median_chars=v[len(v) // 2][0],
            p90_chars=v[int(len(v) * 0.9)][0],
            max_chars=v[-1][0],
            median_header=v[len(v) // 2][1],
            median_described=sorted(x[3] for x in v)[len(v) // 2],
            median_nameonly=sorted(x[4] for x in v)[len(v) // 2],
        )
    json.dump(
        dict(
            listings=nlist,
            per_skill=table,
            sizes=size_summary,
            read_errors=errs,
            examples={f"{k[0]}|{k[1]}k": v for k, v in examples.items()},
        ),
        open(OUT, "w"),
        indent=1,
    )
    print("listings", dict(nlist), "errors", errs)
    for ct, s in size_summary.items():
        print(ct, s)


if __name__ == "__main__":
    main()
