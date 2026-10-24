# For every candidate idle gap (candidates TSV), the timestamp of the last OPERATOR turn at or before
# prev_ts: a non-meta, non-tool_result, non-sidechain user record whose text is not a machine/peer
# wrapper. Read-only, streaming. usage: python3 -I lastop_scan.py candidates.tsv out.tsv
import bisect, csv, json, sys
from datetime import datetime

cand_path, out_path = sys.argv[1], sys.argv[2]
MACHINE = (
    "<task-notification",
    "<teammate-message",
    "Another Claude session sent a message",
    "[restore]",
    "[crash recovery]",
    "[limit-recover]",
    "<local-command",
    "Stop hook feedback",
    "[Request interrupted",
    "⟳",
    "⚑",
    "⚠",
    "⛔",
    "📬",
    "<system-reminder",
    "Caveat:",
)


def ep(s):
    try:
        return datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()
    except Exception:
        return None


C = list(csv.DictReader(open(cand_path), delimiter="\t", quoting=csv.QUOTE_NONE))
by_paths = {}
for c in C:
    by_paths.setdefault(c["paths"], []).append(c)
with open(out_path, "w") as o:
    o.write("kind\tsid\tprev_req\tprev_ts\tlast_op_ts\n")
    for ps, cs in by_paths.items():
        ops = []
        for path in ps.split("|"):
            try:
                fh = open(path, "rb")
            except OSError:
                continue
            with fh:
                for line in fh:
                    head = line[:1500]
                    if not (b'"type":"user"' in head or b'"type": "user"' in head):
                        continue
                    if b'"tool_result"' in line or b'"isMeta":true' in line:
                        continue
                    try:
                        r = json.loads(line)
                    except Exception:
                        continue
                    if r.get("isSidechain") or r.get("isMeta"):
                        continue
                    c = (r.get("message") or {}).get("content")
                    if isinstance(c, list):
                        c = " ".join(
                            b.get("text", "")
                            for b in c
                            if isinstance(b, dict) and b.get("type") == "text"
                        )
                    s = (c or "").lstrip() if isinstance(c, str) else ""
                    if not s or s.startswith(MACHINE):
                        continue
                    t = ep(r.get("timestamp", ""))
                    if t:
                        ops.append(t)
        ops.sort()
        for c in cs:
            pt = float(c["prev_ts"])
            k = bisect.bisect_right(ops, pt + 1)
            lo = ops[k - 1] if k else ""
            o.write(
                "%s\t%s\t%s\t%s\t%s\n"
                % (c["kind"], c["sid"], c["prev_req"], c["prev_ts"], lo)
            )
print("done", len(C))
