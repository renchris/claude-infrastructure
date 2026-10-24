# For each shadow row, find the transcript and the opener records inside (idle_start, turn_start].
import glob, json, os, sys
from datetime import datetime
def ts(s):
    try: return datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()
    except Exception: return None
rows = [json.loads(l) for l in open(sys.argv[1])]
for r in rows:
    cfg = r["config_dir"]
    hits = glob.glob(os.path.join(cfg, "projects", "*", r["sid"] + ".jsonl"))
    op = []
    for h in hits[:1]:
        with open(h, "rb") as fh:
            for line in fh:
                if b'"type":"user"' not in line[:1500] or b'"tool_result"' in line:
                    continue
                try: d = json.loads(line)
                except Exception: continue
                if d.get("isSidechain") or d.get("isMeta"): continue
                t = ts(d.get("timestamp", ""))
                if t is None or not (r["idle_start"] < t <= r["turn_start"] + 1): continue
                c = d.get("message", {}).get("content")
                if isinstance(c, list):
                    c = " ".join(b.get("text", "") for b in c if isinstance(b, dict) and b.get("type") == "text")
                c = c if isinstance(c, str) else ""
                if c.startswith("<task-notification>"):
                    i = c.find("<summary>"); j = c.find("</summary>")
                    op.append("NOTICE:" + (c[i + 9:j] if i >= 0 else c[:80]).replace("\n", " ")[:110] + (" [cc-await-ping]" if "cc-await-ping" in c else ""))
                else:
                    op.append("PROMPT:" + c[:60].replace("\n", " "))
    print("%s busy=%s would=%s gap=%dm | %s" % (r["sid"][:8], r["busy_notice"], r["would_advise"], r["gap_s"] // 60, " || ".join(op)[:300]))
