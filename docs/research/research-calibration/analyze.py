"""analyze.py - turn the A3 replay's records into per-plan calibration rows and the pooled model inputs.

Subcommands (run in order; each re-runnable):
  extract <cache> <triage_wf_dir>   triage journal -> <cache>/replay/triage/<plan>.json
  raterjobs <cache>                 OpenAI rater-1 jobs (and, once rater 1 is in, rater-3 jobs on disagreements)
  rows <cache> <review_wf_dir> <out.jsonl> <params.json>
                                    one calibration row per plan + the pooled inputs for calib_sim.py

Definitions (REPORT §3.11, §6.6), each computed, never set by hand:
  reads            non-void reviewer slots (reviewer-reads) for the plan
  material item    verifier CONFIRMED with consequence reproduced, AND >= 2 raters MATERIAL (raters 1 and 2
                   agree; on a disagreement rater 3 decides). Seeds go through the same rule.
  false alarm      a material item that the independent cross-vendor reproduction (rater 1's own verdict)
                   REFUTES. fpp = false alarms / reads. Raw rate: verifier-REFUTED items / reads.
  downgrade q      share of items matching a known at-freeze hole (or a seed), verifier-CONFIRMED, that the
                   rating rule leaves below material
  holes at freeze  N0 = known at-freeze holes (non-fix-born) + material real items matching no known hole
  invisible u      known at-freeze holes that NO reviewer detected and that history says a non-desk detector
                   found (build, probe_contact, operator, world_moved), / N0
  omit             omission share of N0
  b (fix-born)     history: fix_born / applied_fixes (post-freeze plan edits)
  forecast check   the §3.9 ratio estimator on this round's seeds (F real material found, k seeds left of s)
                   gives a point forecast and a 95% bound of desk holes left; realized = known at-freeze holes
                   no reviewer detected. Exceedance = realized > point (resp. > bound).
"""

import itertools
import json
import math
import os
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(
    0,
    os.path.join(
        HERE, "..", "upfront-research-exhaustion-2026-09-30", "evidence", "design"
    ),
)
import cert_sim as m  # noqa: E402

from prep_replay import parse_json  # noqa: E402

NON_DESK = {"build", "probe_contact", "operator", "world_moved"}
PRICE = None  # filled from cc-quota-price --json (pp per Mtok), see price()


def jl(path):
    for line in open(path):
        try:
            yield json.loads(line)
        except json.JSONDecodeError:
            continue


def extract(C, wfdir):
    labels, res = {}, {}
    for r in jl(os.path.join(wfdir, "journal.jsonl")):
        if r.get("type") == "started":
            labels[r["agentId"]] = r.get("label", "")
        elif r.get("type") == "result":
            res[r["agentId"]] = r.get("result")
    per = {}
    for aid, lab in labels.items():
        if aid not in res or res[aid] is None:
            continue
        kind, _, rest = lab.partition(":")
        plan = rest.split(":")[0]
        d = per.setdefault(
            plan,
            dict(
                plan=plan, items=None, verdicts=[], ratings2=[], score=None, audit=None
            ),
        )
        v = res[aid]
        if isinstance(v, str):
            try:
                v = parse_json(v)
            except Exception:  # noqa: BLE001
                continue
        if kind == "adjudicate":
            d["items"] = v["items"]
        elif kind == "verify":
            d["verdicts"] += v["verdicts"]
        elif kind == "rate":
            d["ratings2"] += v["ratings"]
        elif kind == "score":
            d["score"] = v
        elif kind == "audit":
            d["audit"] = v["audits"]
    os.makedirs(os.path.join(C, "replay", "triage"), exist_ok=True)
    for plan, d in per.items():
        json.dump(
            d, open(os.path.join(C, "replay", "triage", plan + ".json"), "w"), indent=1
        )
        print(
            "%-32s items=%s verdicts=%d rated=%d score=%s audit=%s"
            % (
                plan,
                len(d["items"] or []),
                len(d["verdicts"]),
                len(d["ratings2"]),
                bool(d["score"]),
                len(d["audit"] or []),
            )
        )


RATER = """# Rater brief (OpenAI). Read only this directory; do not edit anything.

`plan/` is a frozen plan. `ITEMS.json` lists findings a verifier confirmed against it. You do not know who
raised them, how many reviewers did, or how anyone else rated them.

For EACH item:
1. `reproduce`: check the claim yourself against `plan/` (and `research/` if present). CONFIRMED if the text
   shows it true as stated; REFUTED if the quoted text is absent, the claim is false, or the plan handles it
   elsewhere (search the whole plan before agreeing with an omission).
2. `rating` under this rubric:
{rubric}

Return JSON only: {{"ratings": [{{"iid": "...", "reproduce": "CONFIRMED|REFUTED", "rating":
"MATERIAL|REFINEMENT|COSMETIC|GENERIC", "clause": "a-g or -", "reason": "one line"}}]}}
"""


def blind(it):
    return {
        k: it[k]
        for k in (
            "iid",
            "title",
            "claim",
            "consequence",
            "location",
            "quote",
            "clause",
            "omission",
        )
    }


def raterjobs(C, stage="r1"):
    rubric = json.load(open(os.path.join(C, "replay", "rubric.json")))["rubric"]
    jobs = []
    for fn in sorted(os.listdir(os.path.join(C, "replay", "triage"))):
        d = json.load(open(os.path.join(C, "replay", "triage", fn)))
        plan = d["plan"]
        conf = {v["iid"] for v in d["verdicts"] if v["verdict"] == "CONFIRMED"}
        items = [blind(it) for it in d["items"] or [] if it["iid"] in conf]
        if stage == "r3":
            r1 = load_r(C, "rater1", plan)
            r2 = {r["iid"]: r["rating"] for r in d["ratings2"]}
            items = [
                it
                for it in items
                if (r1.get(it["iid"], {}).get("rating") == "MATERIAL")
                != (r2.get(it["iid"]) == "MATERIAL")
            ]
        if not items:
            continue
        wd = os.path.join(C, "replay", stage + "work", plan)
        shutil.rmtree(wd, ignore_errors=True)
        shutil.copytree(
            os.path.join(C, "bundles", plan, "full", "plan"), os.path.join(wd, "plan")
        )
        json.dump(items, open(os.path.join(wd, "ITEMS.json"), "w"), indent=1)
        jobs.append(dict(id=plan, cwd=wd, prompt=RATER.format(rubric=rubric)))
    out = os.path.join(C, "replay", stage + "-jobs.json")
    json.dump(jobs, open(out, "w"))
    print(
        "%s jobs %d, items %d"
        % (
            stage,
            len(jobs),
            sum(
                len(json.load(open(os.path.join(j["cwd"], "ITEMS.json")))) for j in jobs
            ),
        )
    )


def load_r(C, stage, plan):
    p = os.path.join(C, "replay", stage, plan + ".last")
    if not os.path.exists(p):
        return {}
    try:
        return {r["iid"]: r for r in parse_json(open(p).read())["ratings"]}
    except Exception:  # noqa: BLE001
        return {}


def ratio(F, k_left, s):
    """the §3.9 ratio estimator (cert_sim.ratio_est): point and 95% upper bound of holes left"""
    return m.ratio_est(F, k_left, s)


def phi(a, b):
    n11 = sum(1 for x, y in zip(a, b) if x and y)
    n10 = sum(1 for x, y in zip(a, b) if x and not y)
    n01 = sum(1 for x, y in zip(a, b) if y and not x)
    n00 = sum(1 for x, y in zip(a, b) if not x and not y)
    den = math.sqrt((n11 + n10) * (n01 + n00) * (n11 + n01) * (n10 + n00))
    return (n11 * n00 - n10 * n01) / den if den else None


def slot_usage(wfdir):
    """deduped token components per review slot, from the review workflow's agent transcripts"""
    labels = {}
    for r in jl(os.path.join(wfdir, "journal.jsonl")):
        if r.get("type") == "started" and str(r.get("label", "")).startswith("review:"):
            labels[r["agentId"]] = r["label"][len("review:") :]
    out = {}
    for aid, sid in labels.items():
        last = {}
        p = os.path.join(wfdir, "agent-%s.jsonl" % aid)
        if not os.path.exists(p):
            continue
        for r in jl(p):
            msg = r.get("message") or {}
            if msg.get("role") == "assistant" and msg.get("id") and msg.get("usage"):
                last[msg["id"]] = msg[
                    "usage"
                ]  # the LAST record of a message carries its final output count
        comp = dict(input=0, cache_creation=0, cache_read=0, output=0)
        for u in last.values():
            comp["input"] += u.get("input_tokens") or 0
            comp["cache_creation"] += u.get("cache_creation_input_tokens") or 0
            comp["cache_read"] += u.get("cache_read_input_tokens") or 0
            comp["output"] += u.get("output_tokens") or 0
        out[sid] = comp
    return out


def pp(comp, price):
    return sum(comp[k] / 1e6 * price[k] for k in ("input", "cache_creation", "output"))


def rows(C, review_wf, out_path, params_path):
    price = json.load(open(os.path.join(C, "replay", "price.json")))
    slots = {
        s["slot"]: s for s in json.load(open(os.path.join(C, "replay", "slots.json")))
    }
    usage = slot_usage(review_wf)
    pooled = dict(
        reads=0,
        fa=0,
        refuted=0,
        items=0,
        q_num=0,
        q_den=0,
        qs_num=0,
        qs_den=0,
        N0=0,
        inv=0,
        omit=0,
        fb=0,
        fixes=0,
        pt_ex=0,
        b95_ex=0,
        n=0,
        seeds=0,
        seeds_caught=0,
        known=0,
        known_hit=0,
        desk_missed=0,
        audit=[],
        phis={"same-model": [], "cross-strategy": [], "cross-vendor": []},
        recall={},
        pp_slot={"anthropic": [], "openai_tokens": []},
    )
    out_rows = []
    for fn in sorted(os.listdir(os.path.join(C, "replay", "triage"))):
        d = json.load(open(os.path.join(C, "replay", "triage", fn)))
        plan = d["plan"]
        hist = json.load(open(os.path.join(C, "history", plan + ".json")))
        seeds = json.load(open(os.path.join(C, "seeds", plan + ".json")))
        r1, r3 = load_r(C, "rater1", plan), load_r(C, "rater3", plan)
        r2 = {r["iid"]: r for r in d["ratings2"]}
        ver = {v["iid"]: v for v in d["verdicts"]}
        items = d["items"] or []
        sc = d["score"] or {"item_matches": [], "holes": [], "seeds": []}
        match = {x["iid"]: x for x in sc["item_matches"]}
        live = [s for s in slots.values() if s["plan"] == plan and not s["void"]]
        reads = len(live)
        vendors = sorted({s["vendor"] for s in live})

        def material(iid):
            v = ver.get(iid)
            if not v or v["verdict"] != "CONFIRMED" or not v["consequence_reproduced"]:
                return False
            a = r1.get(iid, {}).get("rating") == "MATERIAL"
            b = r2.get(iid, {}).get("rating") == "MATERIAL"
            if a == b:
                return a
            if iid in r3:
                return r3[iid].get("rating") == "MATERIAL"
            return None  # undecided until rater 3 runs

        mat = {it["iid"]: material(it["iid"]) for it in items}
        undecided = sum(1 for v in mat.values() if v is None)
        refuted = sum(
            1 for it in items if ver.get(it["iid"], {}).get("verdict") == "REFUTED"
        )
        fa = [
            i
            for i, v in mat.items()
            if v and r1.get(i, {}).get("reproduce") == "REFUTED"
        ]
        real_mat = [i for i, v in mat.items() if v and i not in fa]
        kind = {i: (match.get(i, {}).get("match") or "none") for i in mat}
        new_real = [i for i in real_mat if kind[i] == "none"]
        # downgrade: confirmed items that match ground truth (known hole / seed) but end below material
        gt = [
            i
            for i in mat
            if kind[i] in ("hole", "seed")
            and ver.get(i, {}).get("verdict") == "CONFIRMED"
        ]
        q_num = sum(1 for i in gt if mat[i] is False and kind[i] == "hole")
        q_den = sum(1 for i in gt if mat[i] is not None and kind[i] == "hole")
        qs_num = sum(1 for i in gt if mat[i] is False and kind[i] == "seed")
        qs_den = sum(1 for i in gt if mat[i] is not None and kind[i] == "seed")
        atf = [h for h in hist["holes"] if not h.get("fix_born")]
        n_atf = int(hist["counts"].get("holes_at_freeze") or len(atf))
        listed = {h["id"]: h for h in atf}
        hdet = {h["hole_id"]: h for h in sc["holes"]}
        detected = [hid for hid in listed if hdet.get(hid, {}).get("detected_by_iids")]
        missed = [hid for hid in listed if hid not in detected]
        inv = [hid for hid in missed if listed[hid].get("found_by") in NON_DESK]
        desk_missed = [
            hid for hid in missed if listed[hid].get("found_by") not in NON_DESK
        ]
        scale = n_atf / max(
            1, len(listed)
        )  # history lists at most 40 holes; scale listed shares to the count
        N0 = n_atf + len(new_real)
        omit_n = sum(1 for h in atf if h.get("omission")) * scale + sum(
            1 for it in items if it["iid"] in new_real and it.get("omission")
        )
        seed_hit = {s["seed_id"]: s["detected_by_iids"] for s in sc["seeds"]}
        caught = [
            sid for sid, iids in seed_hit.items() if any(mat.get(i) for i in iids)
        ]
        F = len(real_mat) - sum(1 for i in real_mat if kind[i] == "seed")
        k_left = len(seeds) - len(caught)
        pt, up = ratio(F, k_left, len(seeds))
        realized = len(missed) * scale
        # per-slot detection over the target set (known holes detected by anyone + seeds + new real items)
        member = {
            it["iid"]: {f.split("#")[0].split("__")[1] for f in it["members"]}
            for it in items
        }
        targets = [i for i in mat if mat[i] or kind[i] in ("hole", "seed")]
        cols = sorted({s["slot"].split("__")[1] for s in live})
        vec = {c: [c in member.get(i, ()) for i in targets] for c in cols}
        for a, b in itertools.combinations(cols, 2):
            f = phi(vec[a], vec[b])
            if f is None:
                continue
            fa_, sa = a.split("_")
            fb_, sb = b.split("_")
            same_vendor = (fa_ in "AD") == (fb_ in "AD")
            key = (
                "same-model"
                if same_vendor and sa == sb
                else "cross-strategy"
                if same_vendor
                else "cross-vendor"
            )
            pooled["phis"][key].append(f)
        for c in cols:
            refs = {match[i]["ref"] for i in targets if kind[i] == "hole" and c in member.get(i, ())}
            rec = pooled["recall"].setdefault(c, [0, 0])
            rec[0] += len(refs & set(listed))
            rec[1] += len(listed)
        for s in live:
            if s["vendor"] == "anthropic" and s["slot"].split("__", 1)[0] == plan:
                comp = usage.get(s["slot"])
                if comp:
                    pooled["pp_slot"]["anthropic"].append(pp(comp, price))
            elif s["vendor"] == "openai" and s.get("tokens"):
                pooled["pp_slot"]["openai_tokens"].append(s["tokens"])
        aud = d.get("audit") or []
        pooled["audit"] += aud
        b = (hist["counts"].get("fix_born") or 0) / max(
            1, hist["counts"].get("applied_fixes") or 0
        )
        row = dict(
            plan=plan,
            repo=os.path.basename(hist["repo"]),
            freeze_sha=hist["freeze_sha"],
            vendors=vendors,
            reads=reads,
            raw_findings=sum(s["n"] for s in live),
            items=len(items),
            refuted=refuted,
            material=len(real_mat) + len(fa),
            undecided=undecided,
            false_alarms=len(fa),
            fpp=round(len(fa) / reads, 4) if reads else None,
            raw_refuted_per_read=round(refuted / reads, 3) if reads else None,
            new_real_material=len(new_real),
            known_at_freeze=n_atf,
            known_listed=len(listed),
            known_detected=len(detected),
            known_missed_desk=len(desk_missed),
            known_missed_nondesk=len(inv),
            holes_at_freeze=round(N0, 1),
            invisible_share=round(len(inv) * scale / N0, 3) if N0 else None,
            omission_share=round(omit_n / N0, 3) if N0 else None,
            downgrade_known=[q_num, q_den],
            downgrade_seeds=[qs_num, qs_den],
            seeds=len(seeds),
            seeds_caught_material=len(caught),
            fixborn=hist["counts"].get("fix_born"),
            applied_fixes=hist["counts"].get("applied_fixes"),
            fixborn_rate=round(b, 3),
            forecast_point=round(pt, 2),
            forecast_95=(round(up, 2) if up != float("inf") else None),
            realized_missed=round(realized, 1),
            point_exceeded=realized > pt,
            bound_exceeded=(realized > up) if up != float("inf") else False,
            audit_sample=len(aud),
            audit_real_material_present=sum(
                1 for a in aud if a["real"] and a["material"] and a["present_at_freeze"]
            ),
            front_end_days=hist.get("front_end_days"),
            size=hist.get("size"),
        )
        out_rows.append(row)
        for k, v in (
            ("reads", reads),
            ("fa", len(fa)),
            ("refuted", refuted),
            ("items", len(items)),
            ("q_num", q_num),
            ("q_den", q_den),
            ("qs_num", qs_num),
            ("qs_den", qs_den),
            ("N0", N0),
            ("inv", len(inv) * scale),
            ("omit", omit_n),
            ("fb", hist["counts"].get("fix_born") or 0),
            ("fixes", hist["counts"].get("applied_fixes") or 0),
            ("pt_ex", int(realized > pt)),
            ("b95_ex", int(row["bound_exceeded"])),
            ("n", 1),
            ("seeds", len(seeds)),
            ("seeds_caught", len(caught)),
            ("known", len(listed)),
            ("known_hit", len(detected)),
            ("desk_missed", len(desk_missed) * scale),
        ):
            pooled[k] += v
    with open(out_path, "w") as fh:
        for r in out_rows:
            fh.write(json.dumps(r) + "\n")
    P = pooled
    fpp = P["fa"] / P["reads"]
    q = P["q_num"] / P["q_den"] if P["q_den"] else None
    u = P["inv"] / P["N0"]
    omit = P["omit"] / P["N0"]
    nontm2 = [r for r in out_rows if r["plan"] != "tm2"]
    b_pool = sum(r["fixborn"] or 0 for r in nontm2) / max(
        1, sum(r["applied_fixes"] or 0 for r in nontm2)
    )
    aud = P["audit"]
    summary = dict(
        n_plans=P["n"],
        reads=P["reads"],
        fpp=round(fpp, 4),
        raw_refuted_per_read=round(P["refuted"] / P["reads"], 3),
        q=round(q, 3) if q is not None else None,
        q_counts=[P["q_num"], P["q_den"]],
        q_seeds=[P["qs_num"], P["qs_den"]],
        u=round(u, 3),
        omit=round(omit, 3),
        b_pooled_ex_tm2=round(b_pool, 3),
        b_tm2=next((r["fixborn_rate"] for r in out_rows if r["plan"] == "tm2"), None),
        N0_median=sorted(r["holes_at_freeze"] for r in out_rows)[len(out_rows) // 2],
        N0_list=sorted(r["holes_at_freeze"] for r in out_rows),
        seed_recall=round(P["seeds_caught"] / P["seeds"], 3),
        known_recall=round(P["known_hit"] / P["known"], 3),
        point_exceeded=[P["pt_ex"], P["n"]],
        bound_exceeded=[P["b95_ex"], P["n"]],
        phi={
            k: (round(sum(v) / len(v), 3) if v else None, len(v))
            for k, v in P["phis"].items()
        },
        recall_by_slot={
            k: round(a / b, 3) for k, (a, b) in sorted(P["recall"].items())
        },
        audit=dict(
            n=len(aud),
            real=sum(a["real"] for a in aud),
            material=sum(a["material"] for a in aud),
            present=sum(a["present_at_freeze"] for a in aud),
            all3=sum(
                1 for a in aud if a["real"] and a["material"] and a["present_at_freeze"]
            ),
            found_by_ok=sum(a["found_by_ok"] for a in aud),
            evidence_ok=sum(a["evidence_ok"] for a in aud),
        ),
        pp_per_anthropic_read=round(
            sum(P["pp_slot"]["anthropic"]) / max(1, len(P["pp_slot"]["anthropic"])), 3
        ),
        openai_tokens_per_read=int(
            sum(P["pp_slot"]["openai_tokens"])
            / max(1, len(P["pp_slot"]["openai_tokens"]))
        ),
    )
    json.dump(summary, open(params_path, "w"), indent=1)
    print(json.dumps(summary, indent=1))


if __name__ == "__main__":
    cmd = sys.argv[1]
    if cmd == "extract":
        extract(sys.argv[2], sys.argv[3])
    elif cmd == "raterjobs":
        raterjobs(sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else "r1")
    elif cmd == "rows":
        rows(*sys.argv[2:6])
