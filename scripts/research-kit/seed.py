#!/usr/bin/env python3
"""seed.py — planted defects and their encrypted vault (REPORT.md §3.9, §8 item 7).

A seed is a patch anchored on a verbatim quote (≥ 40 characters, occurring exactly once in the
plan), with a defect statement and a detection span. Seeds measure how much the reviewers catch,
so the lead must never see them: the vault is encrypted at rest under a keychain key
(`cc-research-seed-vault/<slug>`), and no verb prints an anchor, a replacement or a defect
statement — only counts. Same-uid processes can still read the keychain, so this is detection-grade
isolation, not prevention (§3.8, §7).

  seed.py plant  --program P --plan F --seeds S.jsonl [--profile lite|standard|full]
  seed.py apply  --program P --plan F --out SEEDED
  seed.py match  --program P --round K --plan CURRENT
  seed.py status --program P

Seed record (S.jsonl, written by a seed author from a vendor other than the lead's):
  {sid, cohort: original|shadow-r<k>|escape, class, op: replace|delete-member|drop-option|drop-plan-item,
   anchor_quote | anchors: [..], replacement, defect_statement, detect_span: "FILE:a-b"}
Omission operators (every op except replace) are required in an original set: the most
decision-changing class of hole is an omission (§3.9).
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional, Set, Tuple

sys.path.insert(0, str(Path(__file__).resolve().parent / "lib"))
import kit  # noqa: E402

KEY_ITEM = "cc-research-seed-vault"
OPS = ("replace", "delete-member", "drop-option", "drop-plan-item")
MIN_ANCHOR = 40


def vault_path(slug: str) -> Path:
    return kit.sealed_dir(slug) / "vault" / "seeds.enc"


def load_vault(slug: str, create_key: bool = False) -> Tuple[Dict[str, Any], str]:
    key = kit.vault_key(KEY_ITEM, slug, create=create_key)
    p = vault_path(slug)
    if not p.exists():
        return {"seeds": []}, key
    return json.loads(kit.decrypt(p.read_bytes(), key)), key


def save_vault(slug: str, vault: Dict[str, Any], key: str) -> None:
    d = kit.sealed_dir(slug, create=True) / "vault"
    d.mkdir(exist_ok=True)
    d.chmod(0o700)
    tmp = d / ".seeds.enc.tmp"
    tmp.write_bytes(kit.encrypt(json.dumps(vault, sort_keys=True).encode(), key))
    tmp.chmod(0o600)
    tmp.replace(vault_path(slug))


def anchors(seed: Dict[str, Any]) -> List[str]:
    a = seed.get("anchors")
    if a:
        return [str(x) for x in a]
    return [str(seed.get("anchor_quote") or "")]


def validate(seed: Dict[str, Any], plan: str) -> Optional[str]:
    """The reason this seed cannot be planted, or None."""
    sid = seed.get("sid") or "?"
    if seed.get("op") not in OPS:
        return f"{sid}: op must be one of {', '.join(OPS)}"
    if seed.get("op") == "replace" and len(anchors(seed)) != 1:
        return f"{sid}: a replace seed has exactly one anchor"
    for q in anchors(seed):
        if len(q) < MIN_ANCHOR:
            return f"{sid}: anchor shorter than {MIN_ANCHOR} characters"
        n = plan.count(q)
        if n != 1:
            return f"{sid}: anchor occurs {n} times in the plan; it must occur exactly once"
    for f in ("defect_statement", "detect_span", "class", "cohort"):
        if not seed.get(f):
            return f"{sid}: missing {f}"
    if not re.match(r"^[^:]+:\d+-\d+$", str(seed["detect_span"])):
        return f"{sid}: detect_span must read FILE:a-b"
    return None


def cmd_plant(a: argparse.Namespace) -> int:
    plan = Path(a.plan).read_text()
    new = kit.read_jsonl(Path(a.seeds))
    vault, key = load_vault(a.program, create_key=True)
    have = {s["sid"] for s in vault["seeds"]}
    errs = [e for e in (validate(s, plan) for s in new) if e]
    errs += [
        f"{s.get('sid')}: sid already in the vault" for s in new if s.get("sid") in have
    ]
    originals = [s for s in new if s.get("cohort") == "original"]
    if originals and not any(s.get("op") != "replace" for s in originals):
        errs.append(
            "no omission operator in the original set: omission seeds are required (§3.9)"
        )
    profile = a.profile or (
        kit.read_json(kit.records_dir(a.program) / "frame.json", {}) or {}
    ).get("profile")
    if originals:
        if not profile:
            errs.append("no profile: pass --profile or set it in frame.json")
        else:
            cap = kit.max_original_seeds(profile, len(plan.splitlines()))
            total = len(originals) + sum(
                1 for s in vault["seeds"] if s.get("cohort") == "original"
            )
            if total > cap:
                errs.append(
                    f"{total} original seeds exceed the cap {cap} for {profile} at "
                    f"{len(plan.splitlines())} plan lines (1 per {kit.CAPS['seed_lines_per_seed']})"
                )
    if errs:
        for e in errs:
            print(f"refused: {e}", file=sys.stderr)
        return 2
    for s in new:
        s.update({"state": "live", "state_round": None, "planted_at": kit.now_iso()})
        vault["seeds"].append(s)
    save_vault(a.program, vault, key)
    print(f"planted {len(new)} seed(s); vault holds {len(vault['seeds'])}")
    return 0


def cmd_apply(a: argparse.Namespace) -> int:
    plan = Path(a.plan).read_text()
    vault, _ = load_vault(a.program)
    applied = skipped = 0
    for s in vault["seeds"]:
        if s.get("state") != "live" or any(plan.count(q) != 1 for q in anchors(s)):
            skipped += 1
            continue
        repl = str(s.get("replacement") or "")
        for i, q in enumerate(anchors(s)):
            plan = plan.replace(q, repl if i == 0 else "", 1)
        applied += 1
    Path(a.out).write_text(plan)
    print(f"applied {applied} seed(s); skipped {skipped}")
    return 0


def _span(s: str) -> Optional[Tuple[str, int, int]]:
    m = re.match(r"^(.+?):(\d+)-(\d+)$", s or "")
    return (Path(m.group(1)).name, int(m.group(2)), int(m.group(3))) if m else None


def overlaps(hole: Dict[str, Any], seed: Dict[str, Any]) -> bool:
    loc = hole.get("locus") or {}
    sp = _span(str(seed.get("detect_span")))
    m = re.match(r"^(\d+)(?:-(\d+))?$", str(loc.get("lines") or ""))
    if not sp or not m or Path(str(loc.get("path") or "")).name != sp[0]:
        return False
    lo, hi = int(m.group(1)), int(m.group(2) or m.group(1))
    return lo <= sp[2] and sp[1] <= hi


# A hole is a seed's catch only when it names the seed's defect, not merely its lines: the share of
# the shorter text's content tokens that the hole's claim and the seed's defect statement share.
DEFECT_MATCH_MIN = 0.5
_STOP = frozenset(
    "the and for that this with from are was were has have not but its into than then".split()
)


def _tokens(text: str) -> Set[str]:
    return {
        t
        for t in re.findall(r"[a-z0-9]+", text.lower())
        if len(t) > 2 and t not in _STOP
    }


def same_defect(hole: Dict[str, Any], seed: Dict[str, Any]) -> bool:
    """The hole reports this seed's defect: same span, no disagreeing class, and, when the hole
    carries a claim, one that restates the defect statement. A hole with neither a claim nor a
    class proves nothing about identity, so it never matches."""
    if not overlaps(hole, seed):
        return False
    hc, sc = hole.get("taxonomy_class"), seed.get("class")
    if hc and sc and hc != sc:
        return False
    claim = _tokens(str(hole.get("claim") or ""))
    if claim:
        stmt = _tokens(str(seed.get("defect_statement") or ""))
        if not stmt:
            return False
        return len(claim & stmt) / min(len(claim), len(stmt)) >= DEFECT_MATCH_MIN
    return bool(hc and sc)


def counts(vault: Dict[str, Any]) -> Dict[str, Dict[str, int]]:
    out: Dict[str, Dict[str, int]] = {}
    for s in vault["seeds"]:
        c = out.setdefault(
            str(s.get("cohort")), {"s_eff": 0, "caught": 0, "k_left": 0, "orphaned": 0}
        )
        st = s.get("state")
        if st == "orphaned":
            c["orphaned"] += 1
            continue
        c["s_eff"] += 1
        c["caught" if st == "caught" else "k_left"] += 1
    return out


def cmd_match(a: argparse.Namespace) -> int:
    plan = Path(a.plan).read_text()
    vault, key = load_vault(a.program)
    holes_path = kit.records_dir(a.program) / "holes.jsonl"
    holes = kit.fold(kit.read_jsonl(holes_path)).values()
    material = [
        h
        for h in holes
        if (h.get("materiality") or {}).get("level") == "MATERIAL"
        and int(h.get("round") or 0) <= a.round
    ]
    for s in vault["seeds"]:
        if s.get("state") != "live":
            continue
        if any(plan.count(q) == 0 for q in anchors(s)):
            s.update(
                {"state": "orphaned", "state_round": a.round}
            )  # a fix rewrote its anchor
        elif any(same_defect(h, s) for h in material):
            s.update({"state": "caught", "state_round": a.round})
    # Tag every hole that restates a seed still in the plan (caught now or earlier), so round close
    # reads it as a seed catch rather than a real finding. Append-only: the fold keeps the newest.
    in_plan = [s for s in vault["seeds"] if s.get("state") in ("live", "caught")]
    for h in material:
        if h.get("seed_match"):
            continue
        sid = next((s["sid"] for s in in_plan if same_defect(h, s)), None)
        if sid:
            kit.append_jsonl(holes_path, {"id": h["id"], "seed_match": sid})
    save_vault(a.program, vault, key)
    print(json.dumps(counts(vault), sort_keys=True))
    return 0


def cmd_status(a: argparse.Namespace) -> int:
    vault, _ = load_vault(a.program)
    print(json.dumps(counts(vault), sort_keys=True))
    return 0


def main(argv: Optional[List[str]] = None) -> int:
    ap = argparse.ArgumentParser(prog="seed.py")
    sub = ap.add_subparsers(dest="verb", required=True)
    p = sub.add_parser("plant")
    p.add_argument("--program", required=True)
    p.add_argument("--plan", required=True)
    p.add_argument("--seeds", required=True)
    p.add_argument("--profile", choices=sorted(kit.PROFILES))
    p.set_defaults(fn=cmd_plant)
    p = sub.add_parser("apply")
    p.add_argument("--program", required=True)
    p.add_argument("--plan", required=True)
    p.add_argument("--out", required=True)
    p.set_defaults(fn=cmd_apply)
    p = sub.add_parser("match")
    p.add_argument("--program", required=True)
    p.add_argument("--round", type=int, required=True)
    p.add_argument("--plan", required=True)
    p.set_defaults(fn=cmd_match)
    p = sub.add_parser("status")
    p.add_argument("--program", required=True)
    p.set_defaults(fn=cmd_status)
    a = ap.parse_args(argv)
    try:
        kit.check_slug(a.program)
        return int(a.fn(a))
    except kit.KitError as e:
        print(f"seed.py: {e}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
