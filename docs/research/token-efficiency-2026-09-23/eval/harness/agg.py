#!/usr/bin/env python3
"""agg.py f1|f2 — aggregate the offline gate and print the pre-registered verdict.

Inputs (all under eval/gate/, committed): f1/runs.jsonl, f1/verdicts.json, f1/keys/*.json;
f2/metrics.json, f2/verdicts.json, f2/keys/*.json. Output: markdown tables on stdout and
<gate>/<flag>/summary.json.

PRE-REGISTERED DECISION RULE (written before any result was read, 2026-09-24):
  PASS          primary drops: per-task (F1) / per-brief (F2) mean list $ is lower in the treatment arm,
                Wilcoxon signed-rank two-sided p < 0.05 over the paired units, AND the meter proxy also drops;
                AND no guardrail is significantly worse (success, compliance overall, every compliance
                item: two-sided Fisher exact p < 0.05 in the harmful direction; turns, tool errors, hook
                blocks: Wilcoxon on paired unit means, p < 0.05 in the harmful direction);
                AND the 95% Newcombe CI of (treatment - control) for success and for overall compliance
                has its lower bound above -MARGIN (F1 5 pp, F2 10 pp).
  FAIL          any guardrail significantly worse, or the primary does not drop.
  INCONCLUSIVE  no significant harm, primary drops, but a CI lower bound is below -MARGIN; the n per arm
                needed to clear the margin at the observed rates is reported.
Push refusals by the auto-mode classifier are an outcome of their own: refusal rates are reported per
arm, and success/compliance are also compared on push-allowed runs only (no refused push).
"""

import json, math, os, statistics as st, sys
from collections import defaultdict
from scipy.stats import fisher_exact, wilcoxon, norm

H = os.path.dirname(os.path.abspath(__file__))
GATE = os.environ.get("GATE_DIR", os.path.join(os.path.dirname(H), "gate"))
Z = norm.ppf(0.975)


def wilson(k, n):
    if n == 0:
        return (0.0, 1.0)
    p = k / n
    d = 1 + Z * Z / n
    c = (p + Z * Z / (2 * n)) / d
    h = Z * math.sqrt(p * (1 - p) / n + Z * Z / (4 * n * n)) / d
    return (c - h, c + h)


def newcombe(k1, n1, k0, n0):
    """95% CI of p1 - p0 (Newcombe hybrid score)."""
    p1, p0 = k1 / n1, k0 / n0
    l1, u1 = wilson(k1, n1)
    l0, u0 = wilson(k0, n0)
    d = p1 - p0
    return (
        d - math.sqrt((p1 - l1) ** 2 + (u0 - p0) ** 2),
        d + math.sqrt((u1 - p1) ** 2 + (p0 - l0) ** 2),
    )


def n_needed(p1, p0, margin):
    """n per arm so the 95% CI lower bound of p1-p0 clears -margin at the observed rates."""
    d = p1 - p0
    if d <= -margin:
        return None  # observed difference already beyond the margin: no n clears it
    var = p1 * (1 - p1) + p0 * (1 - p0)
    var = max(var, 0.0025)
    return math.ceil(Z * Z * var / (margin + d) ** 2)


def fisher(k1, n1, k0, n0):
    return fisher_exact([[k1, n1 - k1], [k0, n0 - k0]], alternative="two-sided")[1]


def paired(units, key, arm_t, arm_c):
    """Paired per-unit means: returns (mean_t, mean_c, pct_change, wilcoxon p two-sided, direction)."""
    xs, ys = [], []
    for u, rows in units.items():
        t = [r[key] for r in rows if r["arm"] == arm_t and r.get(key) is not None]
        c = [r[key] for r in rows if r["arm"] == arm_c and r.get(key) is not None]
        if t and c:
            xs.append(st.mean(t))
            ys.append(st.mean(c))
    if not xs:
        return None
    diffs = [a - b for a, b in zip(xs, ys)]
    p = wilcoxon(xs, ys).pvalue if any(diffs) else 1.0
    mt, mc = st.mean(xs), st.mean(ys)
    return dict(
        t=mt, c=mc, pct=(mt - mc) / mc * 100 if mc else float("nan"), p=p, units=len(xs)
    )


def fmt_p(p):
    return "<0.001" if p < 0.001 else f"{p:.3f}"


def decide(primary, primary_meter, harms, cis, margin, flag):
    lines = []
    sig_harm = [h for h in harms if h["p"] < 0.05 and h["worse"]]
    drop = (
        primary
        and primary["pct"] < 0
        and primary["p"] < 0.05
        and primary_meter
        and primary_meter["pct"] < 0
    )
    ci_miss = [c for c in cis if c["lo"] <= -margin]
    if sig_harm or not drop:
        verdict = "FAIL"
    elif ci_miss:
        verdict = "INCONCLUSIVE"
    else:
        verdict = "PASS"
    return verdict, sig_harm, ci_miss, drop


# ------------------------------------------------------------------ F1
def f1like(flag):
    """F1, and F3/F4, which run the F1 harness shape (headless runs, blind dossiers, per-task keys).
    F3 and F4 are instruction-content changes like F1, so they take F1's 5 pp margin. In F3, success
    is the judge's verdict AND a code verifier that did not FAIL (the verifier is shown to the judge)."""
    title, T, C = {
        "f1": ("F1 slim instructions", "slim", "full"),
        "f3": ("F3 rules split (situational lessons excluded)", "exclude", "control"),
        "f4": ("F4 compact mission board", "compactboard", "full"),
        "f1sys": ("F1 rank 2: memory in the system prompt", "sys", "full"),
    }[flag]
    runs = [json.loads(l) for l in open(f"{GATE}/{flag}/runs.jsonl")]
    verdicts = json.load(open(f"{GATE}/{flag}/verdicts.json"))
    keyed = {}
    for g in verdicts:
        keys = json.load(open(f"{GATE}/{flag}/keys/{g['id']}.json"))["dossiers"]
        for v in g["verdicts"]:
            k = keys[v["dossier"]]
            keyed[(g["id"], k["rep"])] = v
    rows = []
    for r in runs:
        v = keyed.get((r["task"], r["rep"]))
        if r["fail_class"] != "ok" or v is None:
            continue
        r = dict(
            r,
            success=v["success"] and r.get("verifier") != "fail",
            judge_success=v["success"],
            quality=v["quality"],
            items=v["items"],
            harmful=v["harmful"],
            meter=(r["input"] or 0) + (r["cache_creation"] or 0) + (r["output"] or 0),
            push_blocked=r["push_refused"] > 0,
        )
        rows.append(r)
    text, summary = report(title, rows, T, C, "task", 0.05)
    if flag == "f3":  # mechanical outcomes, reported beside the rule (not inputs to it)
        A = {a: [r for r in rows if r["arm"] == a] for a in (T, C)}
        ex = ["\n### Mechanical outcomes (code, not judge; not inputs to the rule)\n"]
        ex.append(f"| | {T} | {C} |\n|---|---|---|")
        for key, label in (
            ("situational_read", "Opened the situational lessons file"),
            ("lesson_body_read", "Opened a docs/lessons body"),
            ("rules_dir_read", "Touched .claude/rules at all"),
        ):
            ex.append(
                f"| {label} | {sum(bool(r.get(key)) for r in A[T])}/{len(A[T])} | {sum(bool(r.get(key)) for r in A[C])}/{len(A[C])} |"
            )
        for lab, pred in (
            (
                "Verifier PASS (code-checked tasks)",
                lambda r: r.get("verifier") == "pass",
            ),
            ("Judge success (all tasks)", lambda r: r["judge_success"]),
        ):
            den = lambda a: [
                r
                for r in A[a]
                if lab.startswith("Judge") or r.get("verifier") in ("pass", "fail")
            ]
            ex.append(
                f"| {lab} | {sum(pred(r) for r in den(T))}/{len(den(T))} | {sum(pred(r) for r in den(C))}/{len(den(C))} |"
            )
        ex.append(
            f"\n| task | situational opened {T} / {C} | verifier PASS {T} / {C} |\n|---|---|---|"
        )
        for t in sorted({r["task"] for r in rows}):
            g = lambda a, k: [r for r in A[a] if r["task"] == t]
            sr = lambda a: (
                f"{sum(bool(r.get('situational_read')) for r in g(a, 0))}/{len(g(a, 0))}"
            )
            vp = lambda a: (
                f"{sum(r.get('verifier') == 'pass' for r in g(a, 0))}/{len(g(a, 0))}"
            )
            ex.append(f"| {t} | {sr(T)} / {sr(C)} | {vp(T)} / {vp(C)} |")
        text += "\n" + "\n".join(ex)
    return rows, (text, summary)


def f1():
    return f1like("f1")


# ------------------------------------------------------------------ F2
def f2():
    m = json.load(open(f"{GATE}/f2/metrics.json"))
    verdicts = json.load(open(f"{GATE}/f2/verdicts.json"))
    keyed = {}
    for g in verdicts:
        keys = json.load(open(f"{GATE}/f2/keys/{g['id']}.json"))["dossiers"]
        for v in g["verdicts"]:
            keyed[(g["id"], keys[v["dossier"]]["rep"])] = v
    rows = []
    for s in m:
        v = keyed.get((s["brief"], s["rep"]))
        if v is None:
            continue
        arm = "lean" if s["agent_type"] == "workflow-lean" else "default"
        ok = v["success"] if s["verifier"] == "judged" else (s["verifier"] == "pass")
        rows.append(
            dict(
                s,
                arm=arm,
                task=s["brief"],
                success=ok,
                judge_success=v["success"],
                quality=v["quality"],
                items=v["items"],
                harmful=v["harmful"],
                meter=s["meter_proxy"],
                turns=s["responses"],
                hook_blocks=0,
                push_blocked=False,
                total_tokens=s["input"]
                + s["cache_creation"]
                + s["cache_read"]
                + s["output"],
            )
        )
    return rows, report(
        "F2 workflow-lean", rows, "lean", "default", "task", 0.10, f2_extra=True
    )


def report(title, rows, T, C, unit, margin, f2_extra=False):
    out, units = [], defaultdict(list)
    for r in rows:
        units[r[unit]].append(r)
    A = {a: [r for r in rows if r["arm"] == a] for a in (T, C)}
    n = {a: len(A[a]) for a in A}
    succ = {a: sum(r["success"] for r in A[a]) for a in A}
    comp = {
        a: (sum(sum(r["items"]) for r in A[a]), sum(len(r["items"]) for r in A[a]))
        for a in A
    }
    out.append(f"## {title}\n")
    out.append(f"| | {T} | {C} | Δ | test |\n|---|---|---|---|---|")
    ps = fisher(succ[T], n[T], succ[C], n[C])
    ci_s = newcombe(succ[T], n[T], succ[C], n[C])
    out.append(
        f"| Success | {succ[T]}/{n[T]} ({succ[T] / n[T]:.1%}) | {succ[C]}/{n[C]} ({succ[C] / n[C]:.1%}) | "
        f"{(succ[T] / n[T] - succ[C] / n[C]) * 100:+.1f} pp, 95% CI [{ci_s[0] * 100:+.1f}, {ci_s[1] * 100:+.1f}] | Fisher p={fmt_p(ps)} |"
    )
    pc = fisher(comp[T][0], comp[T][1], comp[C][0], comp[C][1])
    ci_c = newcombe(comp[T][0], comp[T][1], comp[C][0], comp[C][1])
    out.append(
        f"| Compliance, all items | {comp[T][0]}/{comp[T][1]} ({comp[T][0] / comp[T][1]:.1%}) | {comp[C][0]}/{comp[C][1]} ({comp[C][0] / comp[C][1]:.1%}) | "
        f"{(comp[T][0] / comp[T][1] - comp[C][0] / comp[C][1]) * 100:+.1f} pp, 95% CI [{ci_c[0] * 100:+.1f}, {ci_c[1] * 100:+.1f}] | Fisher p={fmt_p(pc)} |"
    )
    qt, qc = [r["quality"] for r in A[T]], [r["quality"] for r in A[C]]
    out.append(
        f"| Quality (1–5), mean | {st.mean(qt):.2f} | {st.mean(qc):.2f} | {st.mean(qt) - st.mean(qc):+.2f} | |"
    )
    harms, metrics = [], {}
    for key, label in (
        ("cost_usd", "Cost per run, list $"),
        ("meter", "Meter proxy (input + cache_creation + output)"),
        ("cache_creation", "cache_creation"),
        ("cache_read", "cache_read"),
        ("output", "output"),
        ("turns", "Turns (responses)" if f2_extra else "Turns"),
        ("tool_errors", "Tool errors per run"),
        ("hook_blocks", "Hook blocks per run"),
    ) + (
        (("first_prefix", "First-request prefix"), ("total_tokens", "Total tokens"))
        if f2_extra
        else ()
    ):
        pr = paired(units, key, T, C)
        if pr is None:
            continue
        metrics[key] = pr
        fmtv = (
            (lambda x: f"${x:.3f}")
            if key == "cost_usd"
            else (lambda x: f"{x:,.1f}" if x < 100 else f"{x:,.0f}")
        )
        out.append(
            f"| {label} | {fmtv(pr['t'])} | {fmtv(pr['c'])} | {pr['pct']:+.1f}% | Wilcoxon p={fmt_p(pr['p'])} over {pr['units']} {unit}s |"
        )
        if key in ("turns", "tool_errors", "hook_blocks"):
            harms.append(dict(name=label, p=pr["p"], worse=pr["t"] > pr["c"]))
    harms.append(dict(name="Success", p=ps, worse=succ[T] / n[T] < succ[C] / n[C]))
    harms.append(
        dict(
            name="Compliance, all items",
            p=pc,
            worse=comp[T][0] / comp[T][1] < comp[C][0] / comp[C][1],
        )
    )
    # push refusals as their own outcome
    if not f2_extra:
        pa = {a: sum(r["push_attempted"] for r in A[a]) for a in A}
        pr_ = {a: sum(r["push_refused"] for r in A[a]) for a in A}
        rb = {a: sum(r["push_blocked"] for r in A[a]) for a in A}
        out.append(
            f"| Push attempts / refused by auto mode | {pa[T]} / {pr_[T]} | {pa[C]} / {pr_[C]} | | |"
        )
        out.append(
            f"| Runs with ≥1 push refusal | {rb[T]}/{n[T]} ({rb[T] / n[T]:.1%}) | {rb[C]}/{n[C]} ({rb[C] / n[C]:.1%}) | | Fisher p={fmt_p(fisher(rb[T], n[T], rb[C], n[C]))} |"
        )
        B = {a: [r for r in A[a] if not r["push_blocked"]] for a in A}
        bs = {a: sum(r["success"] for r in B[a]) for a in A}
        bc = {
            a: (sum(sum(r["items"]) for r in B[a]), sum(len(r["items"]) for r in B[a]))
            for a in A
        }
        out.append(
            f"| Success, push-allowed runs only | {bs[T]}/{len(B[T])} | {bs[C]}/{len(B[C])} | | Fisher p={fmt_p(fisher(bs[T], len(B[T]), bs[C], len(B[C])))} |"
        )
        out.append(
            f"| Compliance, push-allowed runs only | {bc[T][0]}/{bc[T][1]} | {bc[C][0]}/{bc[C][1]} | | Fisher p={fmt_p(fisher(bc[T][0], bc[T][1], bc[C][0], bc[C][1]))} |"
        )
    else:
        so = {a: sum(r["so_first_try_valid"] for r in A[a]) for a in A}
        ver = {a: [r for r in A[a] if r["verifier"] != "judged"] for a in A}
        vp = {a: sum(r["verifier"] == "pass" for r in ver[a]) for a in A}
        ow = {a: sum(bool(r["outside_writes"]) for r in A[a]) for a in A}
        js = {a: sum(r["judge_success"] for r in A[a]) for a in A}
        out.append(
            f"| StructuredOutput first-try valid | {so[T]}/{n[T]} | {so[C]}/{n[C]} | | Fisher p={fmt_p(fisher(so[T], n[T], so[C], n[C]))} |"
        )
        out.append(
            f"| Verifier pass (code-checked briefs) | {vp[T]}/{len(ver[T])} | {vp[C]}/{len(ver[C])} | | Fisher p={fmt_p(fisher(vp[T], len(ver[T]), vp[C], len(ver[C])))} |"
        )
        out.append(
            f"| Judge success (all briefs) | {js[T]}/{n[T]} | {js[C]}/{n[C]} | | Fisher p={fmt_p(fisher(js[T], n[T], js[C], n[C]))} |"
        )
        out.append(
            f"| Slots with a write outside OUTDIR (harness regex) | {ow[T]} | {ow[C]} | | |"
        )
        harms.append(
            dict(
                name="StructuredOutput first-try valid",
                p=fisher(so[T], n[T], so[C], n[C]),
                worse=so[T] < so[C],
            )
        )
        harms.append(
            dict(
                name="Verifier pass",
                p=fisher(vp[T], len(ver[T]), vp[C], len(ver[C])),
                worse=vp[T] / max(len(ver[T]), 1) < vp[C] / max(len(ver[C]), 1),
            )
        )
    harmful = {
        a: sum(
            1
            for r in A[a]
            if (r["harmful"] or "none").strip().lower() not in ("none", "none.", "")
        )
        for a in A
    }
    out.append(
        f"| Runs the judge flagged with a harmful action | {harmful[T]} | {harmful[C]} | | |"
    )
    # per-item compliance
    out.append(
        f"\n### Compliance per item ({T} / {C}, runs passing; two-sided Fisher exact)\n"
    )
    out.append(f"| {unit} | item | {T} | {C} | p |\n|---|---|---|---|---|")
    item_rows = []
    for u in sorted(units):
        rs = units[u]
        k = max(len(r["items"]) for r in rs)
        for i in range(k):
            t = [r["items"][i] for r in rs if r["arm"] == T and i < len(r["items"])]
            c = [r["items"][i] for r in rs if r["arm"] == C and i < len(r["items"])]
            p = fisher(sum(t), len(t), sum(c), len(c))
            worse = sum(t) / max(len(t), 1) < sum(c) / max(len(c), 1)
            item_rows.append((u, i + 1, sum(t), len(t), sum(c), len(c), p, worse))
            harms.append(dict(name=f"{u} item {i + 1}", p=p, worse=worse))
            mark = " **←**" if p < 0.05 else ""
            out.append(
                f"| {u} | {i + 1} | {sum(t)}/{len(t)} | {sum(c)}/{len(c)} | {fmt_p(p)}{mark} |"
            )
    posthoc = []
    if f2_extra:
        # POST-HOC (not in the pre-registered rule): F2's four items are the same for every brief, so
        # they can be pooled across briefs. Reported for information; it does not enter decide().
        out.append(
            f"\n### Post-hoc: compliance per item pooled across {unit}s ({T} / {C})\n"
        )
        out.append(f"| item | {T} | {C} | p |\n|---|---|---|---|")
        k = max(len(r["items"]) for r in rows)
        for i in range(k):
            t = [r["items"][i] for r in A[T] if i < len(r["items"])]
            c = [r["items"][i] for r in A[C] if i < len(r["items"])]
            p = fisher(sum(t), len(t), sum(c), len(c))
            posthoc.append(
                dict(item=i + 1, t=sum(t), nt=len(t), c=sum(c), nc=len(c), p=p)
            )
            out.append(
                f"| {i + 1} | {sum(t)}/{len(t)} | {sum(c)}/{len(c)} | {fmt_p(p)} |"
            )
    # per-unit cost
    out.append(f"\n### Per {unit} (arm means)\n")
    out.append(
        f"| {unit} | $ {T} | $ {C} | Δ $ | turns {T} / {C} | success {T} / {C} | quality {T} / {C} |\n|---|---|---|---|---|---|---|"
    )
    for u in sorted(units):
        rs = units[u]
        g = lambda a, k: [r[k] for r in rs if r["arm"] == a]
        ct, cc = st.mean(g(T, "cost_usd")), st.mean(g(C, "cost_usd"))
        out.append(
            f"| {u} | {ct:.3f} | {cc:.3f} | {(ct - cc) / cc * 100:+.1f}% | {st.mean(g(T, 'turns')):.1f} / {st.mean(g(C, 'turns')):.1f} | "
            f"{sum(g(T, 'success'))}/{len(g(T, 'success'))} / {sum(g(C, 'success'))}/{len(g(C, 'success'))} | "
            f"{st.mean(g(T, 'quality')):.1f} / {st.mean(g(C, 'quality')):.1f} |"
        )
    cis = [
        dict(name="Success", lo=ci_s[0], p1=succ[T] / n[T], p0=succ[C] / n[C]),
        dict(
            name="Compliance",
            lo=ci_c[0],
            p1=comp[T][0] / comp[T][1],
            p0=comp[C][0] / comp[C][1],
        ),
    ]
    verdict, sig_harm, ci_miss, drop = decide(
        metrics.get("cost_usd"), metrics.get("meter"), harms, cis, margin, title
    )
    need = {c["name"]: n_needed(c["p1"], c["p0"], margin) for c in ci_miss}
    summary = dict(
        title=title,
        verdict=verdict,
        n=n,
        margin_pp=margin * 100,
        primary=metrics.get("cost_usd"),
        meter=metrics.get("meter"),
        significant_harms=sig_harm,
        ci_misses=ci_miss,
        n_needed_per_arm=need,
        success=(succ, n),
        compliance=comp,
        ci_success=ci_s,
        ci_compliance=ci_c,
        items_tested=len(item_rows),
    )
    out.insert(
        0,
        f"**Verdict: {verdict}** — primary drop significant: {drop}; significant harms: "
        f"{[h['name'] for h in sig_harm] or 'none'}; CI lower bounds: success {ci_s[0] * 100:+.1f} pp, "
        f"compliance {ci_c[0] * 100:+.1f} pp vs margin -{margin * 100:.0f} pp"
        + (f"; n per arm needed: {need}" if need else "")
        + "\n",
    )
    return "\n".join(out), summary


if __name__ == "__main__":
    which = sys.argv[1]
    rows, (text, summary) = f2() if which == "f2" else f1like(which)
    os.makedirs(f"{GATE}/{which}", exist_ok=True)
    json.dump(summary, open(f"{GATE}/{which}/summary.json", "w"), indent=1, default=str)
    open(f"{GATE}/{which}/report.md", "w").write(
        f"# {summary['title']} — full gate tables\n\nGenerated by `harness/agg.py {which}`; "
        "the decision rule is in that file's docstring.\n\n" + text + "\n"
    )
    print(text)
