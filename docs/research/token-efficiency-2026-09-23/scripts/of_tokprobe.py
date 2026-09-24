#!/usr/bin/env python3
"""of_tokprobe.py — measure tokens-per-character for each overhead pattern with the real tokenizer.

Oracle: headless `claude -p "/context"` reports each memory file's token count via the free
count_tokens API (no model turn). We write a probe text as the project CLAUDE.md of a scratch dir
under /tmp/ofprobe (content never enters the repo), wrapped in a ```text fence so '@' imports are
not evaluated, and read back the 'Project | .../CLAUDE.md | N' row. A fence-only baseline file is
measured and subtracted. Resolution is 0.1k tokens, so each probe is ~30-40k chars.

For each pattern the probe measures the ORIGINAL sample and the CLEANED sample (pattern removed or
rewritten); delta tokens / delta chars is the token cost of one removed character, and
tokens/chars of the original is the base ratio for that output class.

Samples come from of_scan.py (/tmp/ofprobe/samples/*.json, random tool_results from 600 files).
Output: data/of_tokprobe.json
"""

import json, os, re, subprocess, random, sys

HERE = os.path.dirname(os.path.abspath(__file__))
BASE = os.path.dirname(HERE)
SAMP = "/tmp/ofprobe/samples"
WORK = "/tmp/ofprobe/tok"
CLAUDE = "/Users/chrisren/.claude-280/node_modules/.bin/claude"
sys.path.insert(0, HERE)
import of_scan as S  # noqa: E402

CAP = 36000
random.seed(11)


def load(k):
    with open(os.path.join(SAMP, k + ".json")) as fh:
        return json.load(fh)


def pack(texts, cap=CAP):
    out, n = [], 0
    for t in texts:
        t = t.replace("```", "'''")
        if n + len(t) > cap:
            break
        out.append(t)
        n += len(t) + 1
    return out


ROW = re.compile(
    r"\|\s*Project\s*\|\s*\S*ofprobe/tok/[^|]*CLAUDE\.md\s*\|\s*([\d.]+)(k?)\s*\|"
)


def count(name, text):
    d = os.path.join(WORK, name)
    os.makedirs(d, exist_ok=True)
    body = "```text\n" + text + "\n```\n"
    with open(os.path.join(d, "CLAUDE.md"), "w") as fh:
        fh.write(body)
    if not os.path.isdir(os.path.join(d, ".git")):
        subprocess.run(["git", "init", "-q"], cwd=d)
    p = subprocess.run(
        [CLAUDE, "-p", "/context"], cwd=d, capture_output=True, text=True, timeout=180
    )
    m = ROW.search(p.stdout)
    if not m:
        return None, len(body)
    v = float(m.group(1)) * (1000 if m.group(2) else 1)
    return v, len(body)


def main():
    res = {}
    base, _ = count("baseline", "x")
    res["baseline_tokens"] = base
    probes = {}
    # 1. plain Bash output (general ratio)
    bp = pack(random.sample(load("bash_plain"), 400))
    probes["bash_plain"] = ("\n".join(bp), None)
    # 2. absolute path prefixes
    pp = pack(load("paths"))
    o = "\n".join(pp)
    probes["paths_root"] = (o, S.ROOT.sub("", o))
    probes["paths_home"] = (o, o.replace("/Users/chrisren/", "~/"))
    # 3. box-drawing / banners
    bx = pack(load("box"))
    o = "\n".join(bx)
    nb = "\n".join(
        l
        for l in o.split("\n")
        if not (len(l) >= 10 and S.RULE_LINE.match(l) and len(l.strip()) >= 10)
    )
    probes["box_banner_lines"] = (o, nb)
    probes["box_chars_all"] = (o, S.BOX.sub("", o))
    # 4. JSON pretty vs minified
    js = pack(load("json"))
    mins = []
    for t in js:
        try:
            mins.append(
                json.dumps(json.loads(t), separators=(",", ":"), ensure_ascii=False)
            )
        except Exception:
            mins.append(t)
    probes["json_minify"] = ("\n".join(js), "\n".join(mins))
    # 5. Read line-number prefixes
    rd = pack(load("readnum"))
    o = "\n".join(rd)
    probes["readnum_all"] = (o, S.READNUM.sub("", o))

    def sparse(m, _c=[0]):
        _c[0] += 1
        n = int(m.group(1).strip())
        return m.group(0) if n % 10 == 0 else ""

    probes["readnum_sparse10"] = (o, S.READNUM.sub(sparse, o))
    # 6. ANSI
    an = pack(load("ansi"))
    o = "\n".join(an)
    probes["ansi"] = (o, S.OSC.sub("", S.CSI.sub("", o)))
    # 7. progress / CR
    pr = pack(load("progress"))
    o = "\n".join(pr)

    def uncr(t):
        return "\n".join(
            (l[l.rfind("\r") + 1 :] if "\r" in l else l) for l in t.split("\n")
        )

    probes["progress_cr"] = (o, uncr(o))
    for k, (orig, clean) in probes.items():
        to, lo = count(k + "_o", orig)
        r = {
            "orig_chars": len(orig),
            "orig_tokens": (to - base) if to is not None else None,
        }
        if r["orig_tokens"]:
            r["chars_per_token"] = round(len(orig) / r["orig_tokens"], 3)
        if clean is not None:
            tc, lc = count(k + "_c", clean)
            r["clean_chars"] = len(clean)
            r["clean_tokens"] = (tc - base) if tc is not None else None
            dc = len(orig) - len(clean)
            if (
                r["orig_tokens"] is not None
                and r["clean_tokens"] is not None
                and dc > 0
            ):
                dt = r["orig_tokens"] - r["clean_tokens"]
                r["removed_chars"] = dc
                r["removed_tokens"] = dt
                r["tokens_per_removed_char"] = round(dt / dc, 4)
                r["token_share_removed"] = round(dt / r["orig_tokens"], 4)
        res[k] = r
        print(k, r, flush=True)
    with open(os.path.join(BASE, "data", "of_tokprobe.json"), "w") as fh:
        json.dump(res, fh, indent=1)


if __name__ == "__main__":
    main()
