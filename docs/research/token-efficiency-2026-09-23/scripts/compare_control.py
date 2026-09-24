#!/usr/bin/env python3
"""Self-check (b): compare extract.sqlite totals to the census of record,
`cc-quota-price --census --json --since <day>`, per token class.

cc-quota-price keeps the FIRST record's usage per message.id, so its output equals our
`output_first`; the input-side classes are identical on every record of a message.
Writes data/control_cc_quota_price_census.json and prints the comparison table."""

import json, os, sqlite3, subprocess, sys

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
D = os.path.join(HERE, "data")
CQP = os.path.expanduser("~/Development/claude-infrastructure/bin/cc-quota-price")
db = sqlite3.connect(os.path.join(D, "extract.sqlite"))
since = db.execute("select v from meta where k='since'").fetchone()[0]
built = db.execute("select v from meta where k='built_at'").fetchone()[0]
out = subprocess.run(
    ["nice", "-n", "10", CQP, "--census", "--json", "--since", since[:10]],
    capture_output=True,
    text=True,
)
if out.returncode != 0:
    sys.exit("cc-quota-price rc=%d: %s" % (out.returncode, out.stderr[:500]))
c = json.loads(out.stdout)
json.dump(c, open(os.path.join(D, "control_cc_quota_price_census.json"), "w"), indent=1)
t = c["tokens"]
r = db.execute(
    "select count(*), sum(input_tokens), sum(cc_total), sum(cache_read), sum(output_first), "
    "sum(output_tokens), sum(output_est) from resp where xdup=0"
).fetchone()
print(
    f"extract built_at={built}; control window --since {since[:10]} (UTC midnight = same start)"
)
print(
    f"control meta: {json.dumps({k: v for k, v in c['census'].items() if k not in ('models', 'roots')})}"
)
rows = [
    ("responses (deduped)", r[0], c["census"]["deduped"]),
    ("input", r[1], t["input"]),
    ("cache_creation", r[2], t["cache_creation"]),
    ("cache_read", r[3], t["cache_read"]),
    ("output, first record (control's method)", r[4], t["output"]),
    ("output, final record (extract output_tokens)", r[5], t["output"]),
    ("output_est, final + imputed (ESTIMATED)", r[6], t["output"]),
]
print(f"{'class':46s} {'extract':>16s} {'control':>16s} {'delta%':>9s}")
for n, a, b in rows:
    print(f"{n:46s} {a:>16,} {b:>16,} {100 * (a - b) / b:+9.3f}")
em = dict(
    db.execute("select model, count(*) from resp where xdup=0 group by 1").fetchall()
)
cm = c["census"]["models"]
print(
    "per-model response count delta (extract - control):",
    {
        m: em.get(m, 0) - cm.get(m, 0)
        for m in sorted(set(em) | set(cm))
        if em.get(m, 0) != cm.get(m, 0)
    },
)
