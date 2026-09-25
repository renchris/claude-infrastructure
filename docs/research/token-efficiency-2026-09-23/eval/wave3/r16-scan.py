#!/usr/bin/env python3
"""r16-scan.py — replay of rank 16 (`bashOutputMaxChars: 16000`) over real transcripts.

Streams every transcript (main + subagent + workflow agent) under ~/.claude*/projects, window
2026-09-09T00:00Z .. 2026-09-23T23:02Z (14.96 days, the pass's window), and measures:
  1. persisted Bash results (>30k today, `<persisted-output>` marker): did the model read the saved
     file within the next 3 responses of that context (Read/Grep on the path, or any Bash naming it)?
     Also: re-run of the same command, and the rate within 10 responses / the rest of the segment.
  2. the 16k-30k band of inline Bash results: n, chars, command kind, later requests re-reading it
     (split cache-read vs rewrite by comparing each later response's cache_read to the prompt size
     of the first response that carried the result), and what hooks/bash-output-offload.sh (0039)
     would do to each (exempt read / offloaded / left inline because <=110 lines).
  3. the $ model (see the doc): saving = removed tokens x (writes + later reads), cost = recovery
     probability x (re-read tokens x same weight + one extra full-context turn).
Dedupe: responses by message.id, results by tool_use_id, first file in mtime order wins; a result
copied into a resumed file still accrues that file's new responses. A compact_boundary ends a segment.
Read-only. Usage: nice -n 10 python3 r16-scan.py [--workers 4] [--limit N]  -> r16-scan.raw.json + r16-scan.json beside it
(--analyze-only re-derives r16-scan.json from the raw file).
"""

import glob, json, os, re, sys, argparse
from multiprocessing import Pool

T0, T1 = "2026-09-09T00:00:00", "2026-09-23T23:02:00"
DAYS = 14.96
PRICE_IN, PRICE_OUT, CPT = (
    5.0,
    25.0,
    2.5,
)  # $/MTok Opus 5.5 list (per brief), chars/token
CR, CW5, CW1 = 0.1, 1.25, 2.0
LO, HI = 16000, 30000
NEAR = 60000  # persisted results this small are the stratum closest to the 16-30k band
EXTRA_TURN_OUT_TOK = 150  # output tokens of one recovery response (assumed)
# hooks/bash-output-offload.sh, verbatim
READ = re.compile(
    r"(^|[\s;&|(`$])(cat|sed|head|tail|awk|less|more|nl|bat|jq|grep|egrep|rg|diff)(\s|$)"
    r"|git\s+(-C\s+\S+\s+)?(show|diff|log|blame)\b"
)
FAIL = re.compile(
    r"\b(not ok|FAIL(ED|URE)?|ERROR|Error|error:|Traceback|Exception|panic|fatal|WARN(ING)?|warning:|assert)",
    re.I,
)
BUILD = re.compile(
    r"\b(bats|pytest|jest|vitest|playwright|npm|pnpm|yarn|npx|make|cargo|go\s+(test|build)|tsc|eslint|ruff|mypy|shellcheck|cc-bats|ship|gradle|xcodebuild)\b"
)
SAVED = re.compile(r"Full output saved to: (\S+)")


CDPRE = re.compile(
    r"^\s*((cd|pushd)\s+\S+\s*(&&|;)\s*|[A-Za-z_][A-Za-z0-9_]*=\S*\s+|(nice\s+-n\s*\d+|timeout\s+\S+|time)\s+)+"
)
FILE_READ = re.compile(r"^(cat|sed|head|tail|awk|less|more|nl|bat|jq|grep|egrep|rg|diff)\b")
GIT_READ = re.compile(r"^git\s+(-C\s+\S+\s+)?(--no-pager\s+)?(show|diff|log|blame)\b")


PATHTOK = re.compile(r"""(?:https?://[^\s'"|;&)]+|[\w.~/+-]*/[\w.+-]+\.[A-Za-z0-9]{1,8}|[\w+-]{3,}\.(?:md|sh|py|ts|tsx|js|json|jsonl|yaml|yml|toml|txt|log|html|css|bats|sql|plist|conf|csv|swift|rs|go))""")


def src_tokens(cmd):
    """File paths / URLs a command names (redirect targets and /dev/* excluded)."""
    out = set()
    for m in PATHTOK.finditer(cmd or ""):
        t = m.group(0).rstrip(".,:")
        pre = (cmd[max(0, m.start() - 2):m.start()] or "").strip()
        if t.startswith("/dev/") or pre.endswith(">") or len(t) < 6:
            continue
        out.add(t)
    return out


def core(cmd):
    return CDPRE.sub("", cmd or "").strip()


def kind_of(cmd):
    """Leading program of the command: the brief's split (deliberate read vs the rest)."""
    c = core(cmd)
    if FILE_READ.match(c):
        return "file_read"
    if GIT_READ.match(c):
        return "git_read"
    if BUILD.search(c.split("|")[0]):
        return "build_test"
    return "other"


def hook_len(cmd, stdout, stderr, total):
    """Length of the tool_result after 0039; None when the hook leaves it alone."""
    if READ.search(cmd) or len(stdout) <= 8000:
        return None
    lines = stdout.split("\n")
    if len(lines) <= 110:
        return None
    mid = lines[40:-60]
    hits = [l[:300] for l in mid if FAIL.search(l)]
    shown = hits[:30]
    body = (
        sum(len(l[:300]) + 1 for l in lines[:40] + lines[-60:])
        + 330
        + sum(len(l) + 8 for l in shown)
    )
    new_err = len(stderr) if len(stderr) <= 8000 else 2060
    return total - len(stdout) - len(stderr) + body + new_err


def kb_size(head):
    m = re.search(r"Output too large \(([\d.]+)(KB|MB)\)", head)
    return int(float(m.group(1)) * (1024 if m.group(2) == "KB" else 1048576)) if m else 0


def text_of(c):
    if isinstance(c, str):
        return c
    if isinstance(c, list):
        return "".join(
            x.get("text", "")
            if x.get("type") == "text"
            else ("" if x.get("type") == "image" else json.dumps(x))
            for x in c
            if isinstance(x, dict)
        )
    return ""


def scan(path):
    resp, ridx = [], {}  # resp: [msg_id, in_window, prompt, ttl_mult, seg, version]
    tu = {}  # tool_use_id -> (r, name, key)
    tu_by_r = {}  # r -> [tool_use_id]
    res_chars = {}  # tool_use_id -> result chars
    items, seg, ver = [], 0, ""
    try:
        fh = open(path, errors="replace")
    except OSError:
        return path, None
    with fh:
        for line in fh:
            try:
                d = json.loads(line)
            except ValueError:
                continue
            t = d.get("type")
            if t == "system" and d.get("subtype") == "compact_boundary":
                seg += 1
                continue
            m = d.get("message") if isinstance(d.get("message"), dict) else {}
            ts = d.get("timestamp") or ""
            if t == "assistant":
                mid = m.get("id") or d.get("requestId") or ("nomid:%s" % len(resp))
                ver = d.get("version") or ver
                if mid not in ridx:
                    u = m.get("usage") or {}
                    cc = u.get("cache_creation") or {}
                    c5, c1 = (
                        cc.get("ephemeral_5m_input_tokens") or 0,
                        cc.get("ephemeral_1h_input_tokens") or 0,
                    )
                    prompt = (
                        (u.get("input_tokens") or 0)
                        + (u.get("cache_creation_input_tokens") or 0)
                        + (u.get("cache_read_input_tokens") or 0)
                    )
                    ridx[mid] = len(resp)
                    resp.append(
                        [
                            mid,
                            T0 <= ts < T1 and prompt > 0,
                            prompt,
                            u.get("cache_read_input_tokens") or 0,
                            CW1 if c1 > c5 else CW5,
                            seg,
                            ver,
                        ]
                    )
                r = ridx[mid]
                for b in m.get("content") or []:
                    if isinstance(b, dict) and b.get("type") == "tool_use":
                        inp = b.get("input") or {}
                        n = b.get("name")
                        key = (
                            inp.get("command")
                            if n == "Bash"
                            else (
                                inp.get("file_path")
                                or inp.get("path")
                                or inp.get("pattern")
                                or ""
                            )
                        )
                        tu[b.get("id")] = (r, n, key if isinstance(key, str) else "")
                        tu_by_r.setdefault(r, []).append(b.get("id"))
            elif t == "user" and isinstance(m.get("content"), list):
                tur = (
                    d.get("toolUseResult")
                    if isinstance(d.get("toolUseResult"), dict)
                    else {}
                )
                for b in m["content"]:
                    if not (isinstance(b, dict) and b.get("type") == "tool_result"):
                        continue
                    tid = b.get("tool_use_id")
                    txt = text_of(b.get("content"))
                    res_chars[tid] = len(txt)
                    u = tu.get(tid)
                    if not u or u[1] != "Bash" or not (T0 <= ts < T1):
                        continue
                    pers = txt.startswith("<persisted-output>")
                    if not pers and len(txt) <= LO:
                        continue
                    so, se = tur.get("stdout") or "", tur.get("stderr") or ""
                    if not (so or se):
                        so = txt  # no structured copy: treat the visible text as stdout
                    sm = SAVED.search(txt[:600]) if pers else None
                    items.append(
                        {
                            "tid": tid,
                            "r": len(resp) - 1,
                            "seg": seg,
                            "chars": len(txt),
                            "cmd": u[2],
                            "pers": pers,
                            "ppath": sm.group(1) if sm else "",
                            "psize": tur.get("persistedOutputSize") or kb_size(txt[:200]),
                            "ver": ver,
                            "hook": None if pers else hook_len(u[2], so, se, len(txt)),
                            "ok_split": bool(so or se)
                            and abs(len(so) + len(se) - len(txt)) < 64,
                        }
                    )
    # recovery detection (local to the file). "saved": the persisted file is read (Read/Grep/Glob on
    # its path, or a Bash naming it). "src": a later read-type call names a file/URL the ORIGINAL
    # command named (re-reading the source instead of the saved copy); measured for inline results
    # too, so the inline band gives the baseline rate of source re-touches that happen anyway.
    for it in items:
        base = os.path.basename(it["ppath"]) if it["ppath"] else None
        pre = core(it["cmd"])
        toks = src_tokens(it["cmd"])
        rr = {3: [0, 0, 0], 10: [0, 0, 0], 999999: [0, 0, 0]}  # horizon -> [saved, rerun, src]
        rchars3 = schars3 = 0
        for k in range(it["r"] + 1, len(resp)):
            if resp[k][5] != it["seg"]:
                break
            dist = k - it["r"]
            for tid in tu_by_r.get(k, ()):
                _, n, key = tu[tid]
                rd = n in ("Read", "Bash", "Grep", "Glob", "WebFetch")
                hit = bool(base) and rd and base in key
                rer = n == "Bash" and len(pre) >= 12 and core(key).startswith(pre) and not hit
                src = rd and not hit and any(t in key for t in toks)
                for h in rr:
                    if dist <= h:
                        rr[h][0] |= hit
                        rr[h][1] |= rer
                        rr[h][2] |= src
                if dist <= 3:
                    rchars3 += res_chars.get(tid, 0) if hit else 0
                    schars3 += res_chars.get(tid, 0) if (src or rer) else 0
        it["rr"] = {str(h): v for h, v in rr.items()}
        it["rchars3"] = rchars3
        it["schars3"] = schars3
    return path, {"resp": resp, "items": items}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--workers", type=int, default=4)
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--analyze-only", action="store_true")
    a = ap.parse_args()
    if a.analyze_only:
        return analyze()
    home = os.path.expanduser("~")
    seen, files = set(), []
    for root in ("", "-next", "-secondary", "-tertiary", "-quaternary"):
        for f in glob.glob(f"{home}/.claude{root}/projects/**/*.jsonl", recursive=True):
            rp = os.path.realpath(f)
            if rp in seen or os.path.basename(rp) == "journal.jsonl":
                continue
            seen.add(rp)
            try:
                mt = os.path.getmtime(rp)
            except OSError:
                continue
            if mt >= 1788912000:  # 2026-09-09T00:00Z
                files.append((mt, rp))
    files = [f for _, f in sorted(files)]
    if a.limit:
        files = files[: a.limit]
    print(f"files={len(files)}", file=sys.stderr)
    seen_msg, seen_tid, acc = set(), {}, {}
    out_items, task_turns, n_resp = [], {}, 0
    with Pool(a.workers) as pool:
        for i, (path, res) in enumerate(pool.imap(scan, files, chunksize=4)):
            if i % 500 == 0:
                print(f"  {i}/{len(files)}", file=sys.stderr)
            if not res:
                continue
            rel = path.split("/projects/", 1)[1]
            parts = rel.split("/")
            task = parts[1][:-6] if len(parts) == 2 else parts[1]
            ctx = (
                "main"
                if len(parts) == 2
                else ("workflow_agent" if "/workflows/" in rel else "subagent")
            )
            resp = res["resp"]
            counted = []
            for rrow in resp:
                c = rrow[1] and rrow[0] not in seen_msg
                if rrow[1]:
                    seen_msg.add(rrow[0])
                counted.append(c)
                if c:
                    n_resp += 1
                    task_turns[task] = task_turns.get(task, 0) + 1
            for it in res["items"]:
                r, sg = it["r"], it["seg"]
                nxt = r + 1 if r + 1 < len(resp) and resp[r + 1][5] == sg else None
                p1 = resp[nxt][2] if nxt is not None else 0
                w = nreads = ncr = 0.0
                if nxt is not None:
                    for k in range(nxt, len(resp)):
                        if resp[k][5] != sg:
                            break
                        if not counted[k]:
                            continue
                        nreads += 1
                        if resp[k][3] >= p1 and k != nxt:
                            w += CR
                            ncr += 1
                        else:
                            w += resp[k][4]
                key = it["tid"]
                if (
                    key in seen_tid
                ):  # copy in a resumed file: add its new later requests
                    o = acc[key]
                    o["w"] += w
                    o["nlater"] += nreads
                    o["ncr"] += ncr
                    continue
                seen_tid[key] = 1
                it.update(
                    w=w,
                    nlater=nreads,
                    ncr=ncr,
                    p1=p1,
                    ctx=ctx,
                    task=task,
                    kind=kind_of(it["cmd"] or ""),
                    exempt=bool(READ.search(it["cmd"] or "")),
                )
                acc[key] = it
                out_items.append(it)
    for it in out_items:
        it["cmd"] = (it["cmd"] or "")[:160]
    json.dump(
        {
            "window": [T0, T1],
            "n_files": len(files),
            "n_resp": n_resp,
            "n_tasks": len(task_turns),
            "task_turns": task_turns,
            "items": out_items,
        },
        open(
            os.path.join(
                os.path.dirname(os.path.abspath(__file__)), "r16-scan.raw.json"
            ),
            "w",
        ),
    )
    print(
        f"resp={n_resp} tasks={len(task_turns)} items={len(out_items)}", file=sys.stderr
    )
    analyze()


def analyze():
    """Leg 1-4 numbers from r16-scan.raw.json -> r16-scan.json (+ printed summary)."""
    import statistics as st

    here = os.path.dirname(os.path.abspath(__file__))
    d = json.load(open(os.path.join(here, "r16-scan.raw.json")))
    it = d["items"]
    C = PRICE_IN / 1e6
    P = [i for i in it if i["pers"]]
    B = [i for i in it if not i["pers"] and LO < i["chars"] <= HI]
    prev = st.mean(i["chars"] for i in P)
    grp = lambda i: "deliberate" if i["kind"] in ("file_read", "git_read") else "rest"
    mean = lambda xs: st.mean(xs) if xs else 0.0
    anyr = lambda i, h: bool(i["rr"][h][0] or i["rr"][h][1] or i["rr"][h][2])
    out = {"n_resp": d["n_resp"], "n_tasks": d["n_tasks"], "preview_chars": prev,
           "n_over30k_not_persisted": sum(1 for i in it if not i["pers"] and i["chars"] > HI)}
    l1 = {}
    for g in ("all", "deliberate", "rest", "near_all", "near_deliberate", "near_rest"):
        gg = g.replace("near_", "")
        S = [i for i in P if (gg == "all" or grp(i) == gg) and (not g.startswith("near") or i["psize"] <= NEAR)]
        Bg = [i for i in B if gg == "all" or grp(i) == gg]
        R = [i for i in S if i["rr"]["3"][0]]
        A = [i for i in S if anyr(i, "3")]
        base = mean([bool(i["rr"]["3"][1] or i["rr"]["3"][2]) for i in Bg])
        l1[g] = {"n": len(S), "file_chars_mean": mean([i["psize"] for i in S]),
                 "saved3": mean([i["rr"]["3"][0] for i in S]),
                 "saved10": mean([i["rr"]["10"][0] for i in S]),
                 "saved_any": mean([i["rr"]["999999"][0] for i in S]),
                 "saved_chars_mean": mean([i["rchars3"] for i in R]),
                 "any3": mean([anyr(i, "3") for i in S]),
                 "any10": mean([anyr(i, "10") for i in S]),
                 "any_chars_mean": mean([i["rchars3"] + i["schars3"] for i in A]),
                 "any_frac_of_file": mean([min(1, (i["rchars3"] + i["schars3"]) / max(i["psize"], 1)) for i in A]),
                 "band_inline_baseline3": base,
                 "excess3": max(0.0, mean([anyr(i, "3") for i in S]) - base)}
    out["leg1"] = l1
    l2 = {}
    for k in ("all", "file_read", "git_read", "build_test", "other"):
        S = [i for i in B if k == "all" or i["kind"] == k]
        l2[k] = {"n": len(S), "chars": sum(i["chars"] for i in S),
                 "later_reqs_mean": mean([i["nlater"] for i in S]),
                 "cache_reads_mean": mean([i["ncr"] for i in S]),
                 "weight_mean": mean([i["w"] for i in S]),
                 "hook_exempt": sum(i["exempt"] for i in S),
                 "hook_offloaded_below_cap": sum(1 for i in S if i["hook"] is not None and i["hook"] <= LO)}
    out["leg2"] = l2
    out["leg2_ctx"] = {c: sum(1 for i in B if i["ctx"] == c) for c in ("main", "subagent", "workflow_agent")}

    def model(rate_key, full_reread, with_hook, near=False):
        sav = cost = turns = 0.0
        n, per_task = 0, {}
        for i in B:
            ch = i["chars"]
            if with_hook and i["hook"] is not None:
                if i["hook"] <= LO:
                    continue  # 0039 already offloaded it below the cap
                ch = i["hook"]
            n += 1
            s = max(0.0, ch - prev) / CPT * i["w"] * C
            g = l1[("near_" if near else "") + grp(i)]
            r = g[rate_key]
            frac = 1.0 if full_reread else g["any_frac_of_file"]
            c = r * (ch * frac / CPT * i["w"] * C + i["p1"] * CR * C + EXTRA_TURN_OUT_TOK * PRICE_OUT / 1e6)
            sav, cost, turns = sav + s, cost + c, turns + r
            per_task[i["task"]] = per_task.get(i["task"], 0) + r
        tt = d["task_turns"]
        ratios = [per_task[t] / tt[t] for t in per_task if tt.get(t)]
        return {"n": n, "saving": sav, "cost": cost, "net": sav - cost, "extra_turns": turns,
                "extra_turns_pct_of_all_turns": 100 * turns / d["n_resp"],
                "extra_turns_per_task": turns / d["n_tasks"],
                "pct_turns_mean_over_tasks": 100 * sum(ratios) / d["n_tasks"],
                "pct_turns_max_task": 100 * max(ratios) if ratios else 0,
                "tasks_over_1pct": sum(1 for x in ratios if x > 0.01),
                "band_rate": turns / n if n else 0}
    out["leg3"] = {}
    for wh in (False, True):
        for rk in ("saved3", "excess3", "any3"):
            for full in (False, True):
                key = "%s|%s|%s" % ("with0039" if wh else "no0039", rk, "full" if full else "frac")
                out["leg3"][key] = model(rk, full, wh)
                out["leg3"]["near|" + key] = model(rk, full, wh, near=True)
    json.dump(out, open(os.path.join(here, "r16-scan.json"), "w"), indent=1)
    print(json.dumps({k: v for k, v in out.items() if k != "leg3"}, indent=1))
    for k, v in out["leg3"].items():
        print("%-28s n=%4d save=%6.0f cost=%6.0f net=%6.0f turns=%5.0f %%turns=%.3f %%task_mean=%.3f max=%.1f >1%%=%d rate=%.3f"
              % (k, v["n"], v["saving"], v["cost"], v["net"], v["extra_turns"], v["extra_turns_pct_of_all_turns"],
                 v["pct_turns_mean_over_tasks"], v["pct_turns_max_task"], v["tasks_over_1pct"], v["band_rate"]))

if __name__ == "__main__":
    main()
