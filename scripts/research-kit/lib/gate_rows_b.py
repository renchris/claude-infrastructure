"""gate_rows_b.py — gate rows 9-16 of REPORT.md §3.10, plus the plan lint (§3.7 step 4).

  9 Freeze · 10 Freshness · 11 Residual (with §10 item 7's method-created classes, rendered FILED)
  12 Reconciliation (and program-packet hygiene, §10 item 4) · 13 Reviewers · 14 Rehearsal
  15 Router (the sealed held-out set, §10 items 11-13) · 16 Caps (rounds and stage time, §10 item 17)
Unknown fails: a missing record is a FAIL with its reason.
"""

from __future__ import annotations

import os
import re
import subprocess
from pathlib import Path
from typing import Any, Dict, List

import kit
from gate import FAIL, FILED, PASS, Ctx, Row
from gate_rows_a import folded, known_rows, numberless_superlative, probes, row, verdict

ALLOWED_RESIDUAL = (
    "production-traffic",
    "external-tenant-not-held",
    "elapsed-time",
    "operator-eye",
    "tooling-degraded",
)
METHOD_RESIDUAL = (
    "depth-cap",
    "stage-budget-exhausted",
    "stub-validated",
)  # §10 item 7
DAY = 86400.0


def plan_text(ctx: Ctx) -> str:
    p = ctx.frame.get("plan")
    return (
        (ctx.records / p).read_text(errors="replace")
        if p and (ctx.records / p).is_file()
        else ""
    )


def lint(ctx: Ctx) -> List[str]:
    """§3.7 step 4: no /tmp paths, no numberless superlatives, anchors resolve, cited probes exist."""
    errs: List[str] = []
    plan = plan_text(ctx)
    if not plan:
        return [f"plan file {ctx.frame.get('plan')!r} (frame.json `plan`) missing"]
    for n, ln in enumerate(plan.splitlines(), 1):
        if re.search(r"(?<![\w.])/(private/)?tmp/", ln):
            errs.append(f"plan:{n}: path under /tmp")
        if numberless_superlative(ln):
            errs.append(f"plan:{n}: numberless superlative")
    heads = {
        re.sub(r"[^a-z0-9]+", "-", m.lower()).strip("-")
        for m in re.findall(r"^#{1,6}\s+(.*)$", plan, re.M)
    }
    for t in ctx.jsonl("trace.jsonl"):
        to = str(t.get("to") or "")
        if "#" in to and to.split("#", 1)[1] not in heads:
            errs.append(f"trace anchor {to} does not resolve to a plan heading")
        m = re.search(r"§([\d.]+)", to)
        if m and not re.search(
            rf"^#{{1,6}}\s+(§)?{re.escape(m.group(1))}\b", plan, re.M
        ):
            errs.append(f"trace anchor {to} does not resolve to a plan section")
    known = set(probes(ctx))
    for pid in sorted(set(re.findall(r"\bP-[A-Za-z0-9-]+\b", plan))):
        if pid not in known:
            errs.append(f"plan cites probe {pid}, which was never run")
    return errs


def cert_rounds(ctx: Ctx, kind: str = "certification") -> List[Dict[str, Any]]:
    mats = [kit.read_json(p) for p in (ctx.records / "rounds").glob("*/matrix.json")]
    return sorted(
        [m for m in mats if m and m.get("kind", "certification") == kind],
        key=lambda m: int(m.get("seq") or 0),
    )


def blob(text: str) -> str:
    import operator_sign

    return operator_sign.blob_sha(text.encode())


# ── row 9 ───────────────────────────────────────────────────────────────────────────────────────


@row(9, "Freeze")
def row9(ctx: Ctx) -> Row:
    fails = [f"lint: {e}" for e in lint(ctx)]
    fz = ctx.json("freeze.json")
    if not fz or not fz.get("snapshot_sha"):
        return verdict(9, "Freeze", fails + ["not frozen (gate.sh freeze)"], [], [])
    if fz.get("plan_blob") and blob(plan_text(ctx)) != fz["plan_blob"]:
        fails.append("the plan changed after the freeze")
    full = [
        m
        for m in cert_rounds(ctx)
        if m.get("counted") and not m.get("verification_only")
    ]
    if not full:
        fails.append("no counted full certification round")
    elif full[-1].get("snapshot_sha") != fz["snapshot_sha"]:
        fails.append(
            f"the certified snapshot {fz['snapshot_sha'][:12]} is not the one the last full round "
            f"examined ({str(full[-1].get('snapshot_sha'))[:12]})"
        )
    vonly = {str(m["round"]) for m in cert_rounds(ctx) if m.get("verification_only")}
    named = {str(r.get("hole")) for r in known_rows(ctx)}
    for h in folded(ctx, "holes.jsonl").values():
        late = h.get("source") == "rehearsal" or str(h.get("round")) in vonly
        if (
            late
            and (h.get("materiality") or {}).get("level") == "MATERIAL"
            and h["id"] not in named
        ):
            fails.append(
                f"{h['id']}: a cap-round or rehearsal find that is not a named known row"
            )
    return verdict(9, "Freeze", fails, [], [])


# ── row 10 ──────────────────────────────────────────────────────────────────────────────────────


@row(10, "Freshness")
def row10(ctx: Ctx) -> Row:
    fails: List[str] = []
    now = kit.parse_iso(kit.now_iso())
    pr = probes(ctx)
    for p in folded(ctx, "premises.jsonl").values():
        if not p.get("recheck_cmd"):
            continue
        ats = [
            kit.parse_iso(x["at"])
            for x in pr.values()
            if p["id"] in (x.get("closes") or []) and x.get("at")
        ]
        if not ats or now - max(ats) > DAY:
            fails.append(f"{p['id']}: no re-check within 24 h of the gate")
    end = ctx.frame.get("build_window_end")
    for c in ctx.frame.get("credentials") or []:
        renew = pr.get(str(c.get("renewer_probe")))
        if renew and renew.get("exit") == 0:
            continue
        if not end or not c.get("expires"):
            fails.append(
                f"credential {c.get('name')}: no expiry or no build window to check it against"
            )
        elif kit.parse_iso(c["expires"]) < kit.parse_iso(end) + 7 * DAY:
            fails.append(
                f"credential {c.get('name')}: expires {c['expires']}, before the build window + 7 days"
            )
    return verdict(10, "Freshness", fails, [], [])


# ── row 11 ──────────────────────────────────────────────────────────────────────────────────────


@row(11, "Residual")
def row11(ctx: Ctx) -> Row:
    fails: List[str] = []
    filed: List[str] = []
    pr = probes(ctx)
    capped = 0
    for r in folded(ctx, "residual.jsonl").values():
        why, rid = r.get("why_unreachable"), r.get("id")
        if why in METHOD_RESIDUAL:
            capped += 1
            miss = [k for k in ("owner_wave", "due", "closing_probe") if not r.get(k)]
            if miss:
                fails.append(f"{rid}: {why} residual missing {', '.join(miss)}")
            else:
                filed.append(f"{rid}: {why}, owner {r['owner_wave']}, due {r['due']}")
            continue
        if why not in ALLOWED_RESIDUAL:
            fails.append(f"{rid}: {why!r} is not an allowed reason")
            continue
        if why == "tooling-degraded" and not r.get("operator_step"):
            fails.append(f"{rid}: tooling-degraded without an operator-step id")
        miss = [
            k
            for k in ("verify_cmd", "owner", "due", "backlog_id", "falsifier")
            if not r.get(k)
        ]
        if miss:
            fails.append(f"{rid}: missing {', '.join(miss)}")
        if r.get("closest_probe") not in pr:
            fails.append(
                f"{rid}: closest probe {r.get('closest_probe')!r} was never run"
            )
    return verdict(
        11,
        "Residual",
        fails,
        filed,
        [f"{capped} method-created (capped) residual row(s)"],
    )


# ── row 12 ──────────────────────────────────────────────────────────────────────────────────────


@row(12, "Reconciliation")
def row12(ctx: Ctx) -> Row:
    import gate_sweep

    fails: List[str] = []
    items: List[str] = []
    for ln in plan_text(ctx).splitlines():
        if re.search(r"\bTODO\b|\bTBD\b|^\s*- \[ \]", ln):
            items.append(f"plan:{ln.strip()}")
    items += [f"residual:{k}" for k in folded(ctx, "residual.jsonl")]
    items += [
        f"decision:{k}"
        for k, d in folded(ctx, "decisions.jsonl").items()
        if d.get("status") == "open"
    ]
    repo = ctx.frame.get("deliverable_repo")
    if repo and Path(repo).is_dir():
        p = subprocess.run(
            ["git", "-C", repo, "status", "--porcelain"], capture_output=True, text=True
        )
        if p.returncode != 0:
            fails.append(f"git status failed in {repo}")
        items += [f"dirty:{ln[3:]}" for ln in p.stdout.splitlines() if ln.strip()]
    rec = folded(ctx, "reconcile.jsonl")
    for it in items:
        r = rec.get(it)
        d = (r or {}).get("disposition")
        if d not in ("done", "not-required", "filed", "frame-row"):
            fails.append(f"unmapped: {it}")
        elif (
            d == "not-required"
            and not r.get("reason")
            or d in ("filed", "frame-row")
            and not r.get("ref")
        ):
            fails.append(
                f"{it}: {d} without its {'reason' if d == 'not-required' else 'ref'}"
            )
    fails += gate_sweep.packet_problems(ctx)
    return verdict(
        12, "Reconciliation", fails, [], [f"{len(items)} item(s) reconciled"]
    )


# ── row 13 ──────────────────────────────────────────────────────────────────────────────────────


@row(13, "Reviewers")
def row13(ctx: Ctx) -> Row:
    fails: List[str] = []
    fr = ctx.frame
    pf = kit.read_json(ctx.sealed / "preflight.json")
    if not pf:
        return Row(
            13,
            "Reviewers",
            FAIL,
            ["the vendor preflight never ran (courier.sh preflight)"],
        )
    first = min(str(v.get("at")) for v in pf.values())
    if not fr.get("contract_page_at") or first >= str(fr["contract_page_at"]):
        fails.append("the vendor preflight did not run before the contract page")
    two = fr.get("degraded") == "two vendors"
    pins = fr.get("reviewer_pins") or {}
    counted = [m for m in cert_rounds(ctx) if m.get("counted")]
    if not counted:
        fails.append("no counted certification round")
    for m in counted:
        rid = str(m["round"])
        if any(s == "dead" for s in (m.get("lanes") or {}).values()):
            fails.append(f"round {rid}: counted with a dead vendor lane")
        fams = {
            kit.VENDOR_FAMILY.get(s.get("vendor"), "?") for s in m.get("slots") or []
        }
        if not (len(fams) >= 3 or (two and len(fams) == 2 and fams != {"anthropic"})):
            fails.append(f"round {rid}: {len(fams)} vendor families")
        for s in m.get("slots") or []:
            if s.get("status") != "complete":
                fails.append(f"round {rid}: slot {s.get('pid')} {s.get('status')}")
            if int(s.get("reruns") or 0) > kit.CAPS["slot_reruns"]:
                fails.append(
                    f"round {rid}: slot {s.get('pid')} re-run {s.get('reruns')} times"
                )
            pj = (
                kit.read_json(
                    ctx.records / "rounds" / rid / "panels" / f"{s.get('pid')}.json"
                )
                or {}
            )
            lenses = {x.get("lens") for x in pj.get("lenses") or []}
            if not set(kit.LENSES) <= lenses:
                fails.append(
                    f"round {rid}: {s.get('pid')} attested {len(lenses)}/{len(kit.LENSES)} lenses"
                )
            want = pins.get(str(s.get("vendor")))
            if not want or pj.get("responding_model") != want:
                fails.append(
                    f"round {rid}: {s.get('pid')} answered as {pj.get('responding_model')}, pinned {want}"
                )
            if (pj.get("integrity") or {}).get("hits"):
                fails.append(f"round {rid}: {s.get('pid')} integrity hit")
    notes = ["degraded: two vendors"] if two else []
    return verdict(13, "Reviewers", sorted(set(fails)), [], notes)


# ── row 14 ──────────────────────────────────────────────────────────────────────────────────────


@row(14, "Rehearsal")
def row14(ctx: Ctx) -> Row:
    rh = ctx.json("rehearsal.json")
    if not rh:
        return Row(14, "Rehearsal", FAIL, ["no rehearsal record"])
    fails: List[str] = []
    typed = set(rh.get("frames_typed") or [])
    for m in ctx.frame.get("reask_map") or []:
        if m.get("axis") and m.get("frame") not in typed:
            fails.append(
                f"historical frame {m.get('frame')!r} never typed in rehearsal"
            )
    relay = rh.get("relay") or {}
    if relay.get("unstable"):
        return verdict(14, "Rehearsal", fails, [], ["relay unstable"])
    if int(relay.get("trials") or 0) < 20 or not relay.get("passed"):
        fails.append(
            f"relay test: {relay.get('trials', 0)} trials, passed={relay.get('passed')}, "
            "and 'relay unstable' not recorded"
        )
    return verdict(14, "Rehearsal", fails, [], [])


# ── row 15 ──────────────────────────────────────────────────────────────────────────────────────


@row(15, "Router")
def row15(ctx: Ctx) -> Row:
    import heldout

    try:
        res = heldout.evaluate(os.environ.get("CC_RESEARCH_ROUTER"))
    except kit.KitError as e:
        return Row(15, "Router", FAIL, [str(e)])
    return Row(
        15, "Router", PASS if not res["fails"] else FAIL, res["fails"] + res["notes"]
    )


# ── row 16 ──────────────────────────────────────────────────────────────────────────────────────


@row(16, "Caps")
def row16(ctx: Ctx) -> Row:
    import operator_sign

    fails: List[str] = []
    filed: List[str] = []
    fr = ctx.frame
    prof = kit.profile(fr.get("profile") or "")
    certs = cert_rounds(ctx)
    extras = [
        r
        for r in operator_sign.research_records(ctx.slug, "extra-round")
        if r["_verdict"] == "valid"
    ]
    if len(extras) > kit.CAPS["extra_round_sets"]:
        fails.append(
            f"{len(extras)} extra round sets signed; the cap is {kit.CAPS['extra_round_sets']} per program"
        )
    p90 = (certs[0].get("forecast") or {}).get("p90") if certs else None
    rmax = kit.r_max(prof["name"], p90, bool(extras))
    if len(certs) > rmax:
        fails.append(f"{len(certs)} certification rounds ran; R_max is {rmax}")
    fc = cert_rounds(ctx, "frame-critique")
    if len(fc) != kit.CAPS["frame_critique_rounds"]:
        fails.append(
            f"{len(fc)} frame-critique rounds; exactly {kit.CAPS['frame_critique_rounds']} are required"
        )
    per: Dict[str, int] = {}
    for m in cert_rounds(ctx, "delta"):
        per[str(m.get("escape"))] = per.get(str(m.get("escape")), 0) + 1
    fails += [
        f"escape {e}: {n} delta rounds; the cap is 2" for e, n in per.items() if n > 2
    ]
    agent_crs = [
        c for c in folded(ctx, "changes.jsonl").values() if c.get("origin") == "agent"
    ]
    if len(agent_crs) > kit.CAPS["agent_change_requests"]:
        fails.append(
            f"{len(agent_crs)} agent-originated change requests; the cap is {kit.CAPS['agent_change_requests']}"
        )
    budget = ctx.json("budget.json") or {}
    now = kit.parse_iso(kit.now_iso())
    for st, v in sorted((budget.get("stages") or {}).items()):
        if not v.get("started"):
            continue
        days = (
            (kit.parse_iso(v["ended"]) if v.get("ended") else now)
            - kit.parse_iso(v["started"])
        ) / DAY
        cap = prof["stage_days"].get(int(st), 0) * kit.CAPS["overrun_factor"]
        if days > cap:
            pkt = (budget.get("overrun_packets") or {}).get(str(st))
            if pkt:
                filed.append(
                    f"stage {st}: {days:.1f} d against a {cap:.2f} d cap; overrun packet {pkt} (default proceed)"
                )
            else:
                fails.append(
                    f"stage {st}: {days:.1f} d against a {cap:.2f} d cap and no overrun packet"
                )
    return verdict(16, "Caps", fails, filed, [f"rounds {len(certs)} of R_max {rmax}"])


ROWS = [row9, row10, row11, row12, row13, row14, row15, row16]
