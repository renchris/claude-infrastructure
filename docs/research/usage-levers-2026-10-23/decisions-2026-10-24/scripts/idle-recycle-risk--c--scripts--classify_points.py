# For every W4 recycle point (points TSV from sim_points.py), read the session transcript(s) and
# classify the assistant message that preceded the idle gap, plus the opener that ended the gap.
# Streaming, read-only. usage: python3 -I classify_points.py points.tsv out.tsv
import csv, json, re, sys
from datetime import datetime

pts_path, out_path = sys.argv[1], sys.argv[2]
pts = list(csv.DictReader(open(pts_path), delimiter="\t"))

def ts_epoch(s):
    try:
        return datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()
    except Exception:
        return None

# waiting-recycle.sh 5b GENUINE regex, verbatim (grep -iE; ERE -> Python re is compatible here).
GENUINE = re.compile(r"your (credential|password|api.?key|secret|token|login|cookie)|need (your|the)[^.]{0,40}(credential|password|secret|token|key|access|permission|approval)|only you (can|have|know)|(don.?t|do not|no) [a-z ]{0,20}access|which account|you.?ll need to (provide|give|share|tell|run|log ?in)|i (don.?t|do not) have (access|the |your |permission)|can you (provide|share|tell me|give me|confirm which)|which (do you|would you|of (these|the)|option|approach|one)|(would|do) you prefer|your call|up to you|how would you like|which direction|your approval|requires? (your|sudo|approval|authentication)|run (this|it|the [a-z ]{0,20}) ?yourself|sudo|interactive login|auth login|pushing to (main|origin)|push (is|remains)[^.]{0,20}your call|won.?t push|will not push|not push(ing)? (to|without)|force.?push|destructive migration|drop table|delete[^.]{0,20}production|navigation pattern|(db|database) timeout", re.I)
# A question ADDRESSED TO THE OPERATOR in the closing text (stricter than a bare "?").
ASK = re.compile(r"\b(want me to|should i|shall i|do you want|would you like|would you rather|do you prefer|which (one|option|approach|of these|would you)|ok(ay)? to (proceed|go|land|ship|merge|push|continue)|go ahead\?|proceed\?|can you|could you|are you|did you|do you|is that (ok|okay|right|what)|which do you|your call|up to you|let me know)\b", re.I)

by_sid = {}
for i, p in enumerate(pts):
    by_sid.setdefault(p["sid"], []).append(i)

res = [dict(final_text="", tool_names=[], auq_in_msg=False, auq_in_turn=False, opener_kind="", opener_text="",
            opener_ts=None, last_text_before="", found=False) for _ in pts]

for sid, idxs in by_sid.items():
    want = {}
    for i in idxs:
        want.setdefault(pts[i]["prev_req"], []).append(i)
    paths = pts[idxs[0]]["paths"].split("|")
    # per point: openers seen in (prev_ts, next_ts]; last assistant text strictly before the opener
    for path in paths:
        try:
            fh = open(path, "rb")
        except OSError:
            continue
        last_text = ""          # last non-empty assistant text seen so far in file order
        turn_auq = False         # an AskUserQuestion since the last opener
        with fh:
            for line in fh:
                head = line[:1500]
                is_user = b'"type":"user"' in head or b'"type": "user"' in head
                if is_user:
                    if b'"tool_result"' in line:
                        continue
                    try:
                        r = json.loads(line)
                    except Exception:
                        continue
                    if r.get("isSidechain") or r.get("isMeta"):
                        continue
                    t = ts_epoch(r.get("timestamp", ""))
                    c = (r.get("message") or {}).get("content")
                    if isinstance(c, list):
                        c = " ".join(b.get("text", "") for b in c if isinstance(b, dict) and b.get("type") == "text")
                    c = c if isinstance(c, str) else ""
                    if t is not None:
                        for i in idxs:
                            p = pts[i]
                            if p["kind"] != "mid" or res[i]["opener_ts"] is not None:
                                continue
                            if float(p["prev_ts"]) < t <= float(p["next_ts"]) + 1:
                                res[i]["opener_ts"] = t
                                res[i]["opener_text"] = c[:400]
                    turn_auq = False
                    continue
                if b'"assistant"' not in head:
                    continue
                try:
                    r = json.loads(line)
                except Exception:
                    continue
                if r.get("type") != "assistant" or r.get("isSidechain"):
                    continue
                m = r.get("message") or {}
                key_ids = {r.get("requestId"), m.get("id"), r.get("uuid")}
                texts, names = [], []
                for b in m.get("content") or []:
                    if not isinstance(b, dict):
                        continue
                    if b.get("type") == "text" and b.get("text", "").strip():
                        texts.append(b["text"])
                    elif b.get("type") == "tool_use":
                        names.append(b.get("name", ""))
                if "AskUserQuestion" in names:
                    turn_auq = True
                hit = [i for k in key_ids if k in want for i in want[k]]
                for i in hit:
                    res[i]["found"] = True
                    if texts:
                        res[i]["final_text"] = (res[i]["final_text"] + "\n" + "\n".join(texts)).strip()
                    res[i]["tool_names"] += names
                    res[i]["auq_in_msg"] = res[i]["auq_in_msg"] or ("AskUserQuestion" in names)
                    res[i]["auq_in_turn"] = res[i]["auq_in_turn"] or turn_auq
                    res[i]["last_text_before"] = "\n".join(texts) if texts else last_text
                if texts:
                    last_text = "\n".join(texts)

def classify_opener(t):
    s = t.lstrip()
    if not s:
        return "empty"
    if s.startswith("<task-notification>"):
        return "rewake" if "<summary>" in s[:60] else "job-notice"
    if s.startswith("<teammate-message"):
        return "teammate"
    if s.startswith("<local-command") or s.startswith("<command-name>"):
        return "slash-command"
    if s.startswith("Stop hook feedback") or s[:1] in "⟳⚑⚠⛔📬":
        return "hook"
    if s.startswith("[Request interrupted"):
        return "interrupt"
    if s.startswith("<"):
        return "other-tag"
    return "typed"

with open(out_path, "w") as o:
    cols = ["kind", "sid", "acct", "prev_ts", "next_ts", "gap_s", "ctx", "found", "q300", "q_last_line", "ask_rx",
            "genuine_head4000", "genuine_full", "auq_in_msg", "auq_in_turn", "opener_kind", "opener_len",
            "tail300", "opener"]
    o.write("\t".join(cols) + "\n")
    for p, r in zip(pts, res):
        txt = r["final_text"] or r["last_text_before"]
        tail = txt[-300:]
        lines = [l.strip() for l in txt.strip().splitlines() if l.strip()]
        last_line = re.sub(r"[*_`)\]\s]+$", "", lines[-1]) if lines else ""
        ok = r["opener_kind"] or (classify_opener(r["opener_text"]) if p["kind"] == "mid" else "")
        row = [p["kind"], p["sid"], p["acct"], p["prev_ts"], p["next_ts"], p["gap_s"], p["ctx"], int(r["found"]),
               int("?" in tail), int(last_line.endswith("?")), int(bool(ASK.search(tail)) and "?" in tail),
               int(bool(GENUINE.search(txt[:4000]))), int(bool(GENUINE.search(txt))),
               int(r["auq_in_msg"]), int(r["auq_in_turn"]), ok, len(r["opener_text"]),
               tail.replace("\t", " ").replace("\n", " \\n "), r["opener_text"][:200].replace("\t", " ").replace("\n", " \\n ")]
        o.write("\t".join(str(x) for x in row) + "\n")
with open(out_path + ".text.jsonl", "w") as o2:
    for p, r in zip(pts, res):
        o2.write(json.dumps({"kind": p["kind"], "sid": p["sid"], "prev_ts": p["prev_ts"], "gap_s": p["gap_s"],
                             "final_text": (r["final_text"] or r["last_text_before"])[-1500:],
                             "opener": r["opener_text"][:400], "tools": r["tool_names"]}) + "\n")
print("wrote", out_path, len(pts))
