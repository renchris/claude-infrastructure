#!/usr/bin/env python3
"""Tool calls and tool errors, fleet-wide, from data/extract.sqlite (xdup=0 throughout).

Usage:  cd /tmp && nice -n 10 python3 <dir>/scripts/tool_errors.py [--chars-per-token 2.27] [--cap 10]
Writes: <dir>/measure/tool-errors.json  (every number the .md quotes)

Method (all MEASURED from the extract unless marked ESTIMATED):
- Context population: files with >= 1 xdup=0 response, split by ctx.ctx_type.
- Calls: item.kind='tool_use_input' (subkind = tool name). Results: item.kind='tool_result'.
  Results join to their call on (file, tool_use_id) for the ISSUING response seq.
- Error = tool_result.is_error=1. Classified from item.snippet (first 300 chars) by the ordered
  RULES below; anything unmatched is 'unclassified' (harness-bug candidates).
- Tokens: chars / CPT, CPT measured by scripts/tool_result_tok_ratio.py (ESTIMATED conversion).
- $ of an error (list-price weights; the fleet is subscription-billed):
    carry  = (error result tokens + failed call input tokens) held in context from the next response
             to the file's last response: one cache write at that response's TTL (1h 2x / 5m 1.25x
             input price) + a cache read on every later response (own model's cr_mult).  ESTIMATED.
    call   = failed call input tokens at the issuing model's output price.  ESTIMATED.
    recovery = full usd_total of responses after the issuing response up to and including the one
             that issues the next SUCCESSFUL call of the same tool (cap --cap responses; if the tool
             never succeeds again: 1 response). Each response is attributed to at most one error
             (the latest preceding one), so pattern totals do not double count.  ESTIMATED (an
             upper bound for errors whose output is itself informative, e.g. Bash non-zero exits).
  Every $ is also re-priced at Opus 5.5 ($4/$20, cache read 0.05x).
"""

import argparse, bisect, collections, json, os, re, sqlite3, statistics

HERE = os.path.dirname(os.path.abspath(__file__))
BASE = os.path.dirname(HERE)
DB = os.path.join(BASE, "data", "extract.sqlite")

ap = argparse.ArgumentParser()
ap.add_argument("--chars-per-token", type=float, default=2.27)
ap.add_argument("--cap", type=int, default=10)
ap.add_argument("--out", default=os.path.join(BASE, "measure", "tool-errors.json"))
a = ap.parse_args()
CPT, CAP = a.chars_per_token, a.cap

db = sqlite3.connect(f"file:{DB}?mode=ro", uri=True)

# ---------------------------------------------------------------- classification rules
VB = "validate-bash.sh"
HOOK_STEMS = [  # (regex on snippet, hook name, rule label)
    (r"^MACHINE CAPACITY", "agent-teams-enforce.sh", "capacity-admit refusal"),
    (r"^DUPLICATE WORKER", None, "duplicate-worker lease refusal"),
    (r"^git identity write with no target", VB, "git identity write"),
    (r"^CC_GIT_IDENTITY_", VB, "CC_GIT_IDENTITY_* assignment"),
    (
        r"^curl-gate: (shlex parse failed|internal error)",
        "curl-gate.py",
        "curl-gate parse/internal failure",
    ),
    (r"^curl-gate", "curl-gate.py", "curl-gate deny"),
    (r"^Dangerous command pattern blocked", VB, "dangerous pattern (rm -rf / sudo rm)"),
    (r"^git add -f blocked", VB, "git add -f"),
    (r"^Pattern kill blocked", VB, "pattern kill (pkill/pgrep -f)"),
    (r"^Empty-selector kill blocked", VB, "empty-selector kill"),
    (r"^A /goal is LIVE in this session", VB, "background park under live /goal"),
    (r"^Commit in the SHARED CHECKOUT", VB, "commit in shared checkout"),
    (r"^Ungated advance of the SHARED", VB, "ungated shared-checkout advance"),
    (r"^DDL blocked", VB, "DDL keyword (Drizzle rule)"),
    (r"^--no-verify blocked", VB, "--no-verify"),
    (r"^git commit -n blocked", VB, "git commit -n"),
    (
        r"^BLOCKED: one paragraph of this body",
        "enforce-email-formatting.py",
        "email paragraph length",
    ),
    (r"^probe-ask-from-hook", "(test probe)", "probe-ask-from-hook"),
    (r"^Worktree-UNSCOPED kill", VB, "worktree-unscoped kill of gate processes"),
    (r"^git identity write to an all-expansion target", VB, "git identity write"),
    (r"^git add --force blocked", VB, "git add -f"),
    (r"^Inert flag in a kill", VB, "inert flag in kill"),
    (r"^drizzle-kit push", VB, "drizzle-kit push"),
    (r"^BLOCKED by keychain-guard", "keychain-guard.sh", "unquoted keychain list"),
    (r"^Internal/IMDS target", "curl-gate.py", "internal/IMDS target"),
]
DUP_HOOK = {
    "Edit": "check-edit-boundary.sh",
    "Write": "check-edit-boundary.sh",
    "Bash": VB,
    "Agent": "agent-teams-enforce.sh",
}


def classify(tool, s):
    """Return (category, subclass). Order matters."""
    s = s or ""
    m = re.match(
        r"^(?:<tool_use_error>)?(PreToolUse|PostToolUse):(\S+) hook error: (.*)",
        s,
        re.S,
    )
    if m:
        rest = m.group(3)
        pm = re.match(r"\[([^\]]+)\]", rest)
        if pm:
            name = os.path.basename(pm.group(1).split()[0])
            return "hook_deny", f"{name}: " + re.sub(
                r"\d+",
                "N",
                re.sub(r"'[^']*'", "'…'", rest[pm.end() :]).strip(" :")[:60],
            )
        for rx, hook, label in HOOK_STEMS:
            if re.match(rx, rest):
                return (
                    "hook_deny",
                    f"{hook or DUP_HOOK.get(tool, 'lease hooks')}: {label}",
                )
        return "hook_deny", "unnamed: " + re.sub(r"\d+", "N", rest[:60])
    for rx, hook, label in HOOK_STEMS:
        if re.match(rx, s):
            return "hook_deny", f"{hook or DUP_HOOK.get(tool, 'lease hooks')}: {label}"
    if "denied by the Claude Code auto mode classifier" in s:
        return "auto_mode_classifier_denial", "classifier deny"
    if re.search(
        r"is temporarily unavailable \(.*?\), so auto mode cannot determine", s
    ):
        return "auto_mode_classifier_unavailable", re.sub(r"\d+", "N", s[:60])
    if (
        re.match(r"^Permission to use \S+ with command", s)
        or "was blocked by a deny rule" in s
    ):
        return "permission_denied", "deny rule / non-interactive ask"
    if (
        s.startswith("This command requires approval")
        or "The following part requires approval" in s
    ):
        return "permission_denied", "ask with no one to answer"
    if (
        s.startswith("The user doesn't want to proceed")
        or "Interrupted by user" in s
        or "[Request interrupted" in s
    ):
        return "user_interrupt", "user rejected / interrupted"
    if "No such tool available" in s:
        mm = re.search(r"No such tool available: (\S+?)\.", s)
        return "unknown_tool", (mm.group(1) if mm else "?")
    if "Blocked: sleep" in s and "followed by" in s:
        return "harness_guard", "sleep N followed by (built-in)"
    if "Subagents should return findings as text" in s:
        return "harness_guard", "subagent report-file Write blocked (built-in)"
    if "message text must not be a teammate protocol frame" in s:
        return "input_validation", "SendMessage protocol frame"
    if "File has not been read yet" in s:
        return "file_not_read", "edit/write before read"
    if "File has been modified since read" in s:
        return "file_modified_since_read", "stale read"
    if "String to replace not found" in s:
        return "old_string_not_found", "not found"
    if re.search(r"Found \d+ matches of the string to replace", s):
        return "old_string_not_unique", "not unique"
    if "Output does not match required schema" in s:
        return (
            "structured_output_schema",
            "required property missing" if "required property" in s else "other",
        )
    if (
        "InputValidationError" in s
        or "Input validation error" in s
        or "Invalid arguments" in s
    ):
        return "input_validation", re.sub(r"\d+", "N", re.sub(r"\s+", " ", s[:70]))
    if (
        s.startswith("<tool_use_error>scriptPath must be")
        or "Invalid workflow script" in s
    ):
        return "input_validation", "Workflow script path / parse"
    if re.search(r"exceeds maximum allowed (tokens|size)", s):
        return "read_too_large", "file too large for one Read"
    if (
        s.startswith("File does not exist")
        or "Path does not exist" in s
        or "EISDIR" in s
        or "is a directory" in s[:200]
    ):
        return "file_not_found", "path"
    if re.search(
        r"timed out|timeout of \d+ms exceeded|Command timed out", s[:200], re.I
    ):
        return "timeout", tool
    if re.search(
        r"Failed to acquire token|scope error|Unauthorized|\b401\b|re-?authenticat|invalid_grant",
        s[:300],
        re.I,
    ) and tool.startswith("mcp__"):
        return "mcp_auth", tool.split("__")[1]
    if re.search(
        r"Connection closed|CONNECTION_CLOSED|MCP error -32000|not connected",
        s[:300],
        re.I,
    ):
        return "mcp_connection", tool
    if tool.startswith("mcp__"):
        return "mcp_other", tool.split("__")[1] + ": " + re.sub(r"\d+", "N", s[:50])
    if s.startswith("Exit code"):
        body = s.split("\n", 1)[1] if "\n" in s else ""
        if "Traceback (most recent call last)" in body[:200]:
            return "bash_nonzero_exit", "python traceback"
        if re.search(
            r"\(eval\):\d+: (defining function based on alias|parse error|bad substitution|unmatched|.* not found)",
            body[:200],
        ):
            return "bash_nonzero_exit", "zsh (eval) parse / alias / not-found"
        if re.search(r"command not found|not found$|: not found", body[:200], re.M):
            return "bash_nonzero_exit", "command not found"
        if re.search(r"^(magick|montage|convert):", body[:40]):
            return "bash_nonzero_exit", "ImageMagick"
        if body.startswith("fatal:") or "\nfatal:" in body[:200]:
            return "bash_nonzero_exit", "git fatal"
        if "pre-commit" in body[:200]:
            return "bash_nonzero_exit", "pre-commit hook"
        if body.strip() == "":
            return "bash_nonzero_exit", "no output"
        return "bash_nonzero_exit", "other (command output)"
    if re.match(r"^(Failed to create iTerm\d? split pane|Failed to create)", s):
        return "environment", "pane spawn failed"
    if re.search(
        r"Claude Code is unable to fetch|domains are not accessible|API Error: \d+|Request failed with status code|status code \d{3}|ECONNRESET|ENOTFOUND|socket hang up",
        s[:300],
    ):
        return "web_provider_error", tool
    if tool == "Agent" and re.search(r"refused|blocked", s[:200], re.I):
        return "hook_deny", "unnamed Agent refusal: " + re.sub(r"\d+", "N", s[:60])
    # harness built-ins (strings confirmed present in the 2.1.280 binary)
    if s.startswith("Refusing to write"):
        return "harness_guard", "protected-path write refused (built-in)"
    if "isolated in the worktree" in s[:120]:
        return "harness_guard", "worktree isolation (built-in)"
    if re.search(
        r"after a cd whose target cannot be resolved|Commands that change directories and write"
        r"|The following parts requires? approval|is denied by your permission|covered by a Read deny rule",
        s[:300],
    ):
        return "permission_denied", "harness path-safety ask / deny rule"
    if re.search(
        r"No task found with ID|is not running \(status|Missing required parameter|Workflow \S+ is still running"
        r"|cannot read binary files",
        s[:200],
    ):
        return "input_validation", "stale task id / missing param / binary read"
    if "No changes to make: old_string and new_string are exactly the same" in s:
        return "old_string_not_found", "edit no-op (old == new)"
    if s.startswith("You've hit your") or "session limit" in s[:80]:
        return "web_provider_error", "quota limit"
    if re.search(
        r"ECONNREFUSED|certificate|Socket is closed|maxContentLength|response stopped arriving",
        s[:200],
    ):
        return "web_provider_error", tool
    if "needs design-system authorization" in s or "teammateMode is set to" in s:
        return "environment", "tool auth / teammate backend unavailable"
    return "unclassified", re.sub(r"\d+", "N", re.sub(r"\s+", " ", s[:70]))


FIX = {  # category -> (fix, spec category)
}

# ---------------------------------------------------------------- load
ctx = {f: t for f, t in db.execute("SELECT file, ctx_type FROM ctx")}
resp = collections.defaultdict(
    list
)  # file -> [(seq, usd, usd55, in_price, cr_mult, out_price, ttl1h, model)]
for f, seq, usd, usd55, inp, crm, outp, c5, c1, model in db.execute(
    "SELECT file, seq, usd_total, usd_total_at_opus55, in_per_mtok, cr_mult, out_per_mtok, cc_5m, cc_1h, model "
    "FROM resp_priced WHERE xdup=0 ORDER BY file, seq"
):
    resp[f].append(
        (
            seq,
            usd or 0.0,
            usd55 or 0.0,
            inp or 0.0,
            crm or 0.1,
            outp or 0.0,
            (c1 or 0) > (c5 or 0),
            model,
        )
    )
pop = collections.Counter(ctx[f] for f in resp)  # contexts with >=1 xdup=0 response

seqs = {f: [r[0] for r in v] for f, v in resp.items()}
# suffix sums of per-token cache-read price (own model / opus55) over responses with seq > s
suf_cr = {}
for f, v in resp.items():
    acc, acc55, out = 0.0, 0.0, [None] * (len(v) + 1)
    out[len(v)] = (0.0, 0.0)
    for i in range(len(v) - 1, -1, -1):
        acc += v[i][3] * v[i][4] / 1e6
        acc55 += 4 * 0.05 / 1e6
        out[i] = (acc, acc55)
    suf_cr[f] = out
pref_usd = {}
for f, v in resp.items():
    p, p55, a1, a2 = [0.0], [0.0], 0.0, 0.0
    for r in v:
        a1 += r[1]
        a2 += r[2]
        p.append(a1)
        p55.append(a2)
    pref_usd[f] = (p, p55)

calls = {}  # (file, tuid) -> (tool, issuing seq, input chars)
calls_by_file_tool = collections.defaultdict(list)
call_count = collections.Counter()  # (ctx_type, tool) -> calls
ctx_tool = collections.defaultdict(set)  # (ctx_type, tool) -> files
for f, rb, tool, ch, tuid in db.execute(
    "SELECT file, resp_before, subkind, chars, tool_use_id FROM item WHERE kind='tool_use_input' AND xdup=0"
):
    if f not in resp:
        continue
    calls[(f, tuid)] = (tool, rb, ch or 0)
    t = ctx[f]
    call_count[(t, tool)] += 1
    ctx_tool[(t, tool)].add(f)

results = []
for f, rb, tool, ch, err, sn, tuid, det in db.execute(
    "SELECT file, resp_before, subkind, chars, is_error, snippet, tool_use_id, detail FROM item "
    "WHERE kind='tool_result' AND xdup=0"
):
    if f not in resp:
        continue
    c = calls.get((f, tuid))
    iseq = c[1] if c else rb
    cin = c[2] if c else 0
    results.append((f, iseq, tool, ch or 0, err or 0, sn, cin, det))
    calls_by_file_tool[(f, tool)].append((iseq, err or 0))
for k in calls_by_file_tool:
    calls_by_file_tool[k].sort()

# ---------------------------------------------------------------- per-tool usage table
res_count = collections.Counter()
err_count = collections.Counter()
err_chars = collections.Counter()
all_chars = collections.Counter()
for f, iseq, tool, ch, err, sn, cin, det in results:
    t = ctx[f]
    res_count[(t, tool)] += 1
    all_chars[(t, tool)] += ch
    if err:
        err_count[(t, tool)] += 1
        err_chars[(t, tool)] += ch
tools = sorted(
    {k[1] for k in call_count} | {k[1] for k in res_count},
    key=lambda x: -sum(call_count[(t, x)] for t in pop),
)
per_tool = []
for tool in tools:
    row = {"tool": tool, "by_ctx_type": {}}
    tc = te = tr = tec = 0
    for t in ("main", "subagent", "workflow_agent"):
        n_ctx = len(ctx_tool[(t, tool)])
        c = call_count[(t, tool)]
        r = res_count[(t, tool)]
        e = err_count[(t, tool)]
        row["by_ctx_type"][t] = {
            "contexts_calling": n_ctx,
            "contexts_total": pop[t],
            "share_contexts_calling": round(n_ctx / pop[t], 4) if pop[t] else None,
            "calls": c,
            "calls_per_calling_ctx": round(c / n_ctx, 2) if n_ctx else None,
            "calls_per_ctx_all": round(c / pop[t], 3) if pop[t] else None,
            "results": r,
            "errors": e,
            "error_rate": round(e / r, 4) if r else None,
            "error_result_tokens_est": round(err_chars[(t, tool)] / CPT),
        }
        tc += c
        te += e
        tr += r
        tec += err_chars[(t, tool)]
    row.update(
        calls=tc,
        results=tr,
        errors=te,
        error_rate=round(te / tr, 4) if tr else None,
        error_result_tokens_est=round(tec / CPT),
        result_tokens_est=round(sum(all_chars[(t, tool)] for t in pop) / CPT),
    )
    per_tool.append(row)

# per model error rate for top tools
model_of = {}
for f, v in resp.items():
    for r in v:
        model_of[(f, r[0])] = r[7]
by_model = collections.defaultdict(lambda: [0, 0])
for f, iseq, tool, ch, err, sn, cin, det in results:
    m = model_of.get((f, iseq), "?")
    by_model[(tool, m)][0] += 1
    by_model[(tool, m)][1] += err

# ---------------------------------------------------------------- errors: classify + cost
errs = []
for f, iseq, tool, ch, err, sn, cin, det in results:
    if not err:
        continue
    cat, sub = classify(tool, sn)
    errs.append(
        dict(
            f=f, iseq=iseq, tool=tool, ch=ch, cin=cin, cat=cat, sub=sub, det=det, sn=sn
        )
    )

# carry + call cost
for e in errs:
    f, s = e["f"], e["iseq"]
    sq = seqs[f]
    i = bisect.bisect_right(sq, s)  # index of first response after issuing one
    tok = (e["ch"] + e["cin"]) / CPT
    ctok = e["cin"] / CPT
    if i < len(sq):
        r = resp[f][i]
        wmult = 2.0 if r[6] else 1.25
        write = tok * r[3] * wmult / 1e6
        write55 = tok * 4 * wmult / 1e6
        cr, cr55 = suf_cr[f][i + 1]  # reads on responses after the one that writes it
        carry, carry55 = write + tok * cr, write55 + tok * cr55
        e["later_resp"] = len(sq) - i
    else:
        carry = carry55 = 0.0
        e["later_resp"] = 0
    j = bisect.bisect_left(sq, s)
    outp = resp[f][j][5] if j < len(sq) and sq[j] == s else 25.0
    e["usd_carry"], e["usd_carry55"] = carry, carry55
    e["usd_call"], e["usd_call55"] = ctok * outp / 1e6, ctok * 20 / 1e6
    e["tok"] = e["ch"] / CPT
    # recovery window: responses (s, next success seq], cap CAP; never-again => 1 response
    lst = calls_by_file_tool[(f, e["tool"])]
    nxt = None
    k = bisect.bisect_right(lst, (s, 99))
    for q, er in lst[k:]:
        if q > s and not er:
            nxt = q
            break
    lo = i
    if nxt is None:
        hi = min(i + 1, len(sq))
        e["recovered"] = False
    else:
        hi = min(bisect.bisect_right(sq, nxt), i + CAP)
        e["recovered"] = True
    e["win"] = (lo, hi)

# attribute each recovery response to the latest error whose window covers it
owner = {}
for idx, e in sorted(enumerate(errs), key=lambda x: (x[1]["f"], x[1]["iseq"])):
    lo, hi = e["win"]
    for p in range(lo, hi):
        owner[(e["f"], p)] = idx
rec = collections.defaultdict(lambda: [0.0, 0.0, 0])
for (f, p), idx in owner.items():
    r = resp[f][p]
    rec[idx][0] += r[1]
    rec[idx][1] += r[2]
    rec[idx][2] += 1
for idx, e in enumerate(errs):
    e["usd_rec"], e["usd_rec55"], e["n_rec"] = rec[idx]
    # lower bound: only the first response after the error, if it was attributed to this error
    lo = e["win"][0]
    fr = owner.get((e["f"], lo)) == idx and lo < len(seqs[e["f"]])
    e["usd_rec_lb"] = resp[e["f"]][lo][1] if fr else 0.0
    e["usd_rec_lb55"] = resp[e["f"]][lo][2] if fr else 0.0


# ---------------------------------------------------------------- aggregate
def agg(key):
    g = collections.OrderedDict()
    for e in errs:
        k = key(e)
        d = g.setdefault(
            k,
            dict(
                count=0,
                files=set(),
                tokens=0.0,
                usd_err=0.0,
                usd_err55=0.0,
                usd_rec=0.0,
                usd_rec55=0.0,
                usd_rec_lb=0.0,
                usd_rec_lb55=0.0,
                n_rec=0,
                recovered=0,
                ctx=collections.Counter(),
                tools=collections.Counter(),
                example=None,
                details=collections.Counter(),
            ),
        )
        d["count"] += 1
        d["files"].add(e["f"])
        d["tokens"] += e["tok"]
        d["usd_err"] += e["usd_carry"] + e["usd_call"]
        d["usd_err55"] += e["usd_carry55"] + e["usd_call55"]
        d["usd_rec"] += e["usd_rec"]
        d["usd_rec55"] += e["usd_rec55"]
        d["n_rec"] += e["n_rec"]
        d["usd_rec_lb"] += e["usd_rec_lb"]
        d["usd_rec_lb55"] += e["usd_rec_lb55"]
        d["recovered"] += e["recovered"]
        d["ctx"][ctx[e["f"]]] += 1
        d["tools"][e["tool"]] += 1
        d["details"][(e["det"] or "")[:40]] += 1
        if d["example"] is None:
            d["example"] = re.sub(r"/Users/chrisren", "~", (e["sn"] or "")[:160])
    out = []
    for k, d in g.items():
        out.append(
            dict(
                key=k,
                count=d["count"],
                contexts=len(d["files"]),
                tokens_est=round(d["tokens"]),
                usd_error_result=round(d["usd_err"], 2),
                usd_error_result_at_opus55=round(d["usd_err55"], 2),
                usd_recovery=round(d["usd_rec"], 2),
                usd_recovery_at_opus55=round(d["usd_rec55"], 2),
                usd_recovery_lower_bound=round(d["usd_rec_lb"], 2),
                usd_recovery_lower_bound_at_opus55=round(d["usd_rec_lb55"], 2),
                recovery_responses=d["n_rec"],
                recovered_share=round(d["recovered"] / d["count"], 3),
                usd_total=round(d["usd_err"] + d["usd_rec"], 2),
                usd_total_at_opus55=round(d["usd_err55"] + d["usd_rec55"], 2),
                by_ctx_type=dict(d["ctx"]),
                by_tool=dict(d["tools"].most_common(5)),
                top_details=[x for x, _ in d["details"].most_common(3)],
                example=d["example"],
            )
        )
    out.sort(key=lambda x: -x["usd_total"])
    return out


by_cat = agg(lambda e: e["cat"])
by_pat = agg(lambda e: f"{e['cat']} | {e['sub']}")
unclassified = [x for x in by_pat if x["key"].startswith("unclassified")]

tot_results = sum(res_count.values())
tot_err = len(errs)
fleet = db.execute(
    "SELECT SUM(usd_total), SUM(usd_total_at_opus55) FROM resp_priced WHERE xdup=0"
).fetchone()
out = dict(
    meta=dict(
        db=DB,
        chars_per_token=CPT,
        recovery_cap=CAP,
        contexts=dict(pop),
        results=tot_results,
        errors=tot_err,
        error_rate=round(tot_err / tot_results, 4),
        error_result_tokens_est=round(sum(e["tok"] for e in errs)),
        all_result_tokens_est=round(sum(r[3] for r in results) / CPT),
        usd_fleet=round(fleet[0], 2),
        usd_fleet_at_opus55=round(fleet[1], 2),
        usd_errors_total=round(sum(x["usd_total"] for x in by_cat), 2),
        usd_errors_total_at_opus55=round(
            sum(x["usd_total_at_opus55"] for x in by_cat), 2
        ),
        usd_errors_lower_bound=round(
            sum(x["usd_error_result"] + x["usd_recovery_lower_bound"] for x in by_cat),
            2,
        ),
        usd_errors_lower_bound_at_opus55=round(
            sum(
                x["usd_error_result_at_opus55"]
                + x["usd_recovery_lower_bound_at_opus55"]
                for x in by_cat
            ),
            2,
        ),
    ),
    per_tool=per_tool,
    per_tool_model=[
        dict(
            tool=t, model=m, results=v[0], errors=v[1], error_rate=round(v[1] / v[0], 4)
        )
        for (t, m), v in sorted(by_model.items(), key=lambda x: -x[1][1])
        if v[1] >= 3
    ],
    by_category=by_cat,
    by_pattern=by_pat,
    unclassified=unclassified,
)
# ---------------------------------------------------------------- extra: Bash non-zero exits
bx = collections.Counter()
bx_usd = collections.Counter()
for e in errs:
    if e["cat"] != "bash_nonzero_exit":
        continue
    mm = re.match(r"Exit code (\d+)", e["sn"] or "")
    code = mm.group(1) if mm else "?"
    cmd = (e["det"] or "").strip()
    cmd = re.sub(r"^(cd \S+ (&&|;) ?|[A-Z_][A-Z0-9_]*=\S+ ?)+", "", cmd)
    word = os.path.basename(cmd.split()[0]) if cmd.split() else "?"
    k = f"exit {code} | {word}"
    bx[k] += 1
    bx_usd[k] += e["usd_carry"] + e["usd_call"] + e["usd_rec"]
out["bash_exit_breakdown"] = [
    dict(key=k, count=v, usd_total=round(bx_usd[k], 2)) for k, v in bx.most_common(40)
]
out["bash_exit_by_code"] = dict(
    collections.Counter(k.split(" | ")[0] for k in bx.elements()).most_common(15)
)

# ---------------------------------------------------------------- extra: file_not_read provenance
# Was the file previously read via Bash (cat/sed/head/grep ... <basename>) or via Read in the same context?
bash_det = collections.defaultdict(list)
read_paths = collections.defaultdict(list)
for f, rb, tool, det in db.execute(
    "SELECT file, resp_before, subkind, detail FROM item WHERE kind='tool_use_input' AND xdup=0 AND subkind IN ('Bash','Read')"
):
    (bash_det if tool == "Bash" else read_paths)[f].append((rb, det or ""))
fnr = collections.Counter()
for e in errs:
    if e["cat"] != "file_not_read":
        continue
    path = e["det"] or ""
    base = os.path.basename(path)
    prior_bash = any(
        rb < e["iseq"] and base and base in d for rb, d in bash_det[e["f"]]
    )
    prior_read = any(rb < e["iseq"] and d == path for rb, d in read_paths[e["f"]])
    fnr[
        ("prior Bash mention" if prior_bash else "no prior Bash mention")
        + (" + prior Read" if prior_read else "")
    ] += 1
    fnr["new file (Write)" if e["tool"] == "Write" else "Edit"] += 1
out["file_not_read_provenance"] = dict(fnr)

# ---------------------------------------------------------------- extra: retries per context for top hook patterns
rep = collections.Counter((e["f"], e["cat"], e["sub"]) for e in errs)
mx = collections.defaultdict(list)
for (f, c, s_), n in rep.items():
    mx[f"{c} | {s_}"].append(n)
out["repeat_per_context"] = {
    k: dict(
        contexts=len(v),
        max=max(v),
        mean=round(sum(v) / len(v), 2),
        ctx_ge3=sum(1 for x in v if x >= 3),
    )
    for k, v in mx.items()
    if sum(v) >= 20
}

os.makedirs(os.path.dirname(a.out), exist_ok=True)
json.dump(out, open(a.out, "w"), indent=1, default=list)
m = out["meta"]
print(json.dumps(m, indent=1))
print("\nBY CATEGORY")
for x in by_cat:
    print(
        f"{x['key']:34s} n={x['count']:5d} ctx={x['contexts']:5d} tok={x['tokens_est']:8d} err$={x['usd_error_result']:8.2f} "
        f"rec$={x['usd_recovery']:8.2f} (lb {x['usd_recovery_lower_bound']:7.2f}) tot$={x['usd_total']:8.2f} @55={x['usd_total_at_opus55']:8.2f} rec%={x['recovered_share']}"
    )
print("\nTOP 30 PATTERNS")
for x in by_pat[:30]:
    print(
        f"{x['count']:5d} ctx={x['contexts']:4d} tot$={x['usd_total']:8.2f} err$={x['usd_error_result']:7.2f} rec$={x['usd_recovery']:8.2f} lb={x['usd_recovery_lower_bound']:7.2f} nrec={x['recovery_responses']:5d} {x['key'][:90]} {x['by_ctx_type']}"
    )
print("\nUNCLASSIFIED", sum(x["count"] for x in unclassified))
for x in unclassified[:25]:
    print(f"{x['count']:4d} {x['by_tool']} {x['key'][:100]}")
