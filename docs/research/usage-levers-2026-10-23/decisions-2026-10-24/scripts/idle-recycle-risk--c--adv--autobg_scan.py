# Jobs W4's scan.py does not see: a FOREGROUND Bash call that the harness moved to the background
# (at its timeout, or by the user), identified by toolUseResult.backgroundTaskId on its tool_result,
# whose tool_use had no run_in_background. Interval = launch (assistant record ts) -> earliest record
# carrying its tool-use-id inside a <task-notification> (None if never). Read-only, streaming.
# usage: python3 -I autobg_scan.py candidates.tsv out.tsv
import csv, json, re, sys
from datetime import datetime

cand_path, out_path = sys.argv[1], sys.argv[2]


def ep(s):
    try:
        return datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()
    except Exception:
        return None


paths = {}
for r in csv.DictReader(open(cand_path), delimiter="\t", quoting=csv.QUOTE_NONE):
    for p in r["paths"].split("|"):
        paths[p] = r["sid"]
TUID = re.compile(rb"<tool-use-id>(toolu_[A-Za-z0-9]+)</tool-use-id>")
TS = re.compile(rb'"timestamp":\s*"([^"]+)"')
n_files = 0
with open(out_path, "w") as o:
    o.write("sid\ttu\tkind\tjs\tje\tdesc\n")
    for path, sid in sorted(paths.items()):
        try:
            fh = open(path, "rb")
        except OSError:
            continue
        n_files += 1
        launch = {}  # tu -> (ts, rib, cmd, desc)
        bg = {}  # tu -> kind
        notice = {}
        with fh:
            for line in fh:
                if b"<task-notification>" in line:
                    m = TS.search(line)
                    t = ep(m.group(1).decode()) if m else None
                    for tu in TUID.findall(line):
                        tu = tu.decode()
                        if t and (tu not in notice or t < notice[tu]):
                            notice[tu] = t
                if b'"tool_use"' in line and b'"Bash"' in line:
                    try:
                        r = json.loads(line)
                    except Exception:
                        continue
                    if r.get("type") != "assistant" or r.get("isSidechain"):
                        continue
                    t = ep(r.get("timestamp", ""))
                    for b in (r.get("message") or {}).get("content") or []:
                        if (
                            isinstance(b, dict)
                            and b.get("type") == "tool_use"
                            and b.get("name") == "Bash"
                        ):
                            bi = b.get("input") or {}
                            launch[b.get("id")] = (
                                t,
                                bool(bi.get("run_in_background")),
                                str(bi.get("command", "")),
                                str(bi.get("description", ""))[:80],
                            )
                if b'"backgroundTaskId"' in line:
                    try:
                        r = json.loads(line)
                    except Exception:
                        continue
                    if r.get("isSidechain"):
                        continue
                    tr = r.get("toolUseResult")
                    if not (isinstance(tr, dict) and tr.get("backgroundTaskId")):
                        continue
                    for b in (r.get("message") or {}).get("content") or []:
                        if isinstance(b, dict) and b.get("type") == "tool_result":
                            bg[b.get("tool_use_id")] = (
                                "timeout" if tr.get("timedOutAfterMs") else "moved"
                            )
        for tu, kind in bg.items():
            if tu not in launch:
                continue
            t, rib, cmd, desc = launch[tu]
            if rib or "cc-await-ping" in cmd or t is None:
                continue
            je = notice.get(tu)
            o.write(
                "%s\t%s\t%s\t%.3f\t%s\t%s\n"
                % (
                    sid,
                    tu,
                    kind,
                    t,
                    "%.3f" % je if je else "",
                    desc.replace("\t", " ").replace("\n", " "),
                )
            )
print("files", n_files)
