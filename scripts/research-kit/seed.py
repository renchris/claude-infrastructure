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
  seed.py match  --program P --round K --plan CURRENT   (the real plan, never the seeded copy)
  seed.py prescreen --program P --caught ID… | FILE   (discard what the blind pre-screen caught)
  seed.py status --program P                       (counts, then the seed-realism line)

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
from typing import Any, Callable, Dict, List, Optional, Set, Tuple

sys.path.insert(0, str(Path(__file__).resolve().parent / "lib"))
import kit  # noqa: E402

KEY_ITEM = "cc-research-seed-vault"
OPS = ("replace", "delete-member", "drop-option", "drop-plan-item")
MIN_ANCHOR = 40
VAULT_WRITERS = ("plant", "match", "prescreen")  # the verbs that save the vault


def vault_path(slug: str) -> Path:
    return kit.sealed_dir(slug) / "vault" / "seeds.enc"


def vault_lock(slug: str) -> Any:
    """Held by main() around a verb that loads, modifies and saves the vault (no lost update)."""
    lock = kit.sealed_dir(slug, create=True) / "vault.lock"
    return kit.mkdir_lock(lock, "seed vault", "seed.py")


def load_vault(slug: str, create_key: bool = False) -> Tuple[Dict[str, Any], str]:
    key = kit.vault_key(KEY_ITEM, slug, create=create_key)
    p = vault_path(slug)
    vault = (
        json.loads(kit.decrypt(p.read_bytes(), key)) if p.exists() else {"seeds": []}
    )
    kit.test_delay("CC_RESEARCH_TEST_VAULT_DELAY")
    return vault, key


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
                1
                for s in vault["seeds"]
                if s.get("cohort") == "original" and s.get("state") != "discarded"
            )  # a seed the pre-screen discarded was never planted
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


def _is_live(s: Dict[str, Any]) -> bool:
    return s.get("state") == "live"


def apply_seeds(
    plan: str, seeds: List[Dict[str, Any]], eligible: Callable[[Dict[str, Any]], bool]
) -> Tuple[str, Dict[str, List[Tuple[int, int]]], int]:
    """The seeded text, each applied seed's edited ranges as [start, end) offsets INTO that text,
    and the skipped count. The one apply loop: cmd_apply writes its text and cmd_match reads its
    ranges, so the lines a reviewer cites in the seeded copy are the lines match computes. A seed
    is applied in vault order when `eligible` and every anchor occurs exactly once in the text so
    far; an empty replacement is a zero-width range at the deletion point."""
    spans: Dict[str, List[Tuple[int, int]]] = {}
    skipped = 0
    for s in seeds:
        if not eligible(s) or any(plan.count(q) != 1 for q in anchors(s)):
            skipped += 1
            continue
        repl = str(s.get("replacement") or "")
        mine: List[Tuple[int, int]] = []
        for i, q in enumerate(anchors(s)):
            r = repl if i == 0 else ""
            p = plan.find(q)
            if p < 0:  # an earlier anchor's edit consumed this one: str.replace's no-op
                continue
            plan = plan[:p] + r + plan[p + len(q) :]
            edit = (p, p + len(q), len(r))
            spans = {
                k: [(_moved(x, edit), _moved(y, edit)) for x, y in v]
                for k, v in spans.items()
            }
            mine = [(_moved(x, edit), _moved(y, edit)) for x, y in mine]
            mine.append((p, p + len(r)))
        spans[str(s.get("sid"))] = mine
    return plan, spans, skipped


def _moved(o: int, edit: Tuple[int, int, int]) -> int:
    """Offset o after the text [p, end) became rlen characters: an offset past the edit shifts
    with it; one inside it is clamped to the edit's new bounds."""
    p, end, rlen = edit
    if o >= end:
        return o + rlen - (end - p)
    return min(o, p + rlen) if o > p else o


def cmd_apply(a: argparse.Namespace) -> int:
    vault, _ = load_vault(a.program)
    plan, spans, skipped = apply_seeds(
        Path(a.plan).read_text(), vault["seeds"], _is_live
    )
    Path(a.out).write_text(plan)
    print(f"applied {len(spans)} seed(s); skipped {skipped}")
    return 0


def _span(s: str) -> Optional[Tuple[str, int, int]]:
    m = re.match(r"^(.+?):(\d+)-(\d+)$", s or "")
    return (Path(m.group(1)).name, int(m.group(2)), int(m.group(3))) if m else None


def locus_ranges(lines: Any) -> List[Tuple[int, int]]:
    """A hole locus's `lines` as ranges. Reviewers cite several places in one hole
    ("103; 1266; 1396-1431"), so each `;`- or `,`-separated part is its own N or N-M."""
    out = []
    for part in re.split(r"[;,]", str(lines or "")):
        m = re.match(r"^\s*(\d+)\s*(?:[-–]\s*(\d+))?\s*$", part)
        if m:
            lo, hi = int(m.group(1)), int(m.group(2) or m.group(1))
            out.append((min(lo, hi), max(lo, hi)))
    return out


# A seeded span is computed, not authored, so it is exact for the copy the reviewers read; the slack
# absorbs a reviewer citing the heading or the sentence beside the planted text, and plan edits made
# between `apply` and `match` that move it a line or two. It widens only a hole whose claim must
# also restate the defect (same_defect), never a class-only hole.
SEEDED_SPAN_SLACK = 3
# A quote that repeats this many characters of a seed's replacement, characters that occur nowhere
# in the real plan, was read off the planted text, whatever the hole's claim says.
QUOTE_MATCH_MIN = 25


def _norm(text: Any) -> str:
    if isinstance(text, list):
        text = " ".join(str(t) for t in text)
    return " ".join(str(text or "").split())


def _windows(text: str) -> Set[str]:
    return {
        text[i : i + QUOTE_MATCH_MIN] for i in range(len(text) - QUOTE_MATCH_MIN + 1)
    }


def _line_of(text: str, offset: int) -> int:
    return text.count("\n", 0, offset) + 1


def live_at(s: Dict[str, Any], rnd: int) -> bool:
    """The seed was live when round rnd's seeded copy was applied: live now, or caught or orphaned
    by round rnd's own match or a later one (a re-close re-runs match on a closed round)."""
    if s.get("state") == "live":
        return True
    r = s.get("state_round")
    return s.get("state") in ("caught", "orphaned") and r is not None and int(r) >= rnd


class SeededCopy:
    """Where each seed sits in the copy the reviewers read. Reviewers cite the SEEDED copy's line
    numbers and quote its text; a seed's author-written detect_span uses the real plan's numbering,
    which every deletion or replacement above it shifts. So the spans are recomputed by re-running
    the apply loop on the real plan, and the detect_span is kept only as a secondary span."""

    def __init__(
        self, plan: str, plan_name: str, seeds: List[Dict[str, Any]], rnd: int
    ):
        text, offs, _ = apply_seeds(plan, seeds, lambda s: live_at(s, rnd))
        self.plan_name = plan_name
        self.lines = {
            sid: [(_line_of(text, x), _line_of(text, max(x, y - 1))) for x, y in v]
            for sid, v in offs.items()
        }
        self.plan_windows = _windows(_norm(plan))
        self._seed_only: Dict[str, Set[str]] = {}

    def seed_only(self, seed: Dict[str, Any]) -> Set[str]:
        """The replacement's windows that do not occur in the real plan: a replacement usually keeps
        most of its anchor's words, and a quote of those is a quote of the real plan."""
        sid = str(seed.get("sid"))
        if sid not in self._seed_only:
            rep = _norm(seed.get("replacement"))
            self._seed_only[sid] = _windows(rep) - self.plan_windows
        return self._seed_only[sid]


def overlaps(
    hole: Dict[str, Any], seed: Dict[str, Any], copy: SeededCopy, slack: int
) -> bool:
    """Any of the hole's line ranges meets the seed's span in the seeded copy (widened by slack)
    or its author-written detect_span. Reviewers name the plan's own basename while an author may
    have written the brief's example `PLAN.md`, so either is the plan."""
    loc = hole.get("locus") or {}
    sp = _span(str(seed.get("detect_span")))
    if Path(str(loc.get("path") or "")).name not in {copy.plan_name, sp and sp[0]}:
        return False
    spans = [
        (lo - slack, hi + slack) for lo, hi in copy.lines.get(str(seed.get("sid")), [])
    ]
    if sp:
        spans.append((sp[1], sp[2]))
    return any(
        lo <= shi and slo <= hi
        for lo, hi in locus_ranges(loc.get("lines"))
        for slo, shi in spans
    )


def quotes_seed(hole: Dict[str, Any], seed: Dict[str, Any], copy: SeededCopy) -> bool:
    """The hole quotes text that exists only in this seed's replacement."""
    quote = _norm((hole.get("locus") or {}).get("quote"))
    return bool(_windows(quote) & copy.seed_only(seed))


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


def same_defect(hole: Dict[str, Any], seed: Dict[str, Any], copy: SeededCopy) -> bool:
    """The hole reports this seed's defect: no disagreeing class, and either a quote of the seed's
    planted text, or the same span plus, when the hole carries a claim, one that restates the
    defect statement. A hole with neither a claim nor a class proves nothing about identity, so it
    never matches on its span alone. An omission seed has no planted text, so only the span and
    claim tests can catch it."""
    hc, sc = hole.get("taxonomy_class"), seed.get("class")
    if hc and sc and hc != sc:
        return False
    if quotes_seed(hole, seed, copy):
        return True
    claim = _tokens(str(hole.get("claim") or ""))
    # The slack is for a loose citation whose claim then proves identity; a hole with only a class
    # has nothing else to tell neighbouring seeds apart, so it must hit the exact span.
    if not overlaps(hole, seed, copy, SEEDED_SPAN_SLACK if claim else 0):
        return False
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
        if st == "discarded":  # caught by the pre-screen: never planted, in no count
            continue
        if st == "orphaned":
            c["orphaned"] += 1
            continue
        c["s_eff"] += 1
        c["caught" if st == "caught" else "k_left"] += 1
    return {k: v for k, v in out.items() if any(v.values())}


def cmd_match(a: argparse.Namespace) -> int:
    plan = Path(a.plan).read_text()
    vault, key = load_vault(a.program)
    holes_path = kit.records_dir(a.program) / "holes.jsonl"
    holes = kit.fold(kit.read_jsonl(holes_path)).values()
    # Certification rounds are numbered; a hole from a frame-critique or integration round ("fc1",
    # "stage6-W2") predates the seeds, so it can never catch one and is skipped, not parsed.
    material = [
        h
        for h in holes
        if (h.get("materiality") or {}).get("level") == "MATERIAL"
        and str(h.get("round") or "0").isdigit()
        and int(h.get("round") or 0) <= a.round
    ]
    # The seeded copy has lost every replace anchor and every omitted member, so passing it as
    # --plan would orphan the seeds wholesale. A real fix rewrites a few anchors, not most of them.
    live = [s for s in vault["seeds"] if s.get("state") == "live"]
    gone = [s for s in live if any(plan.count(q) == 0 for q in anchors(s))]
    if live and len(gone) * 2 > len(live):
        raise kit.KitError(
            f"{len(gone)} of {len(live)} live seeds have no anchor in --plan: --plan looks like "
            "the seeded copy; pass the real plan"
        )
    copy = SeededCopy(plan, Path(a.plan).name, vault["seeds"], a.round)
    for s in live:
        if s in gone:
            s.update(
                {"state": "orphaned", "state_round": a.round}
            )  # a fix rewrote its anchor
        elif any(same_defect(h, s, copy) for h in material):
            s.update({"state": "caught", "state_round": a.round})
    # Tag every hole that restates a seed still in the plan (caught now or earlier), so round close
    # reads it as a seed catch rather than a real finding. Append-only: the fold keeps the newest.
    in_plan = [s for s in vault["seeds"] if s.get("state") in ("live", "caught")]
    for h in material:
        if h.get("seed_match"):
            continue
        sid = next((s["sid"] for s in in_plan if same_defect(h, s, copy)), None)
        if sid:
            kit.append_jsonl(holes_path, {"id": h["id"], "seed_match": sid})
    save_vault(a.program, vault, key)
    print(json.dumps(counts(vault), sort_keys=True))
    return 0


def cmd_prescreen(a: argparse.Namespace) -> int:
    """Discard the seeds a blind pre-screen reviewer caught, so the planted ones resemble the
    harder holes that survive research (§3.9). Takes the reviewer's result; never runs it."""
    ids: List[str] = []
    for c in a.caught:
        p = Path(c)
        ids += p.read_text().split() if p.is_file() else [c]
    vault, key = load_vault(a.program)
    by_sid = {s["sid"]: s for s in vault["seeds"]}
    errs = [f"{i}: not in the vault" for i in ids if i not in by_sid]
    errs += [
        f"{i}: state {by_sid[i].get('state')}; only a live seed can be discarded"
        for i in ids
        if i in by_sid and by_sid[i].get("state") not in ("live", "discarded")
    ]
    if not ids:
        errs.append("no seed ids given")
    if errs:
        for e in errs:
            print(f"refused: {e}", file=sys.stderr)
        return 2
    for i in ids:
        by_sid[i].update({"state": "discarded", "state_round": None})
    save_vault(a.program, vault, key)
    live = sum(1 for s in vault["seeds"] if s.get("state") == "live")
    print(f"discarded {len(set(ids))} seed(s); {live} live")
    return 0


# Holes the blind rounds found, and holes that surfaced only after them (desk misses).
REVIEW_SOURCES = ("panel", "delta")
MISSED_SOURCES = ("build", "operator")
# Seeds caught more readily than real holes by this factor are flagged as too easy: the
# calibration pool measured 0.547 seed catch against 0.488 real desk detection, about 1.12x.
SEED_EASIER_RATIO = 1.1


def realism(vault: Dict[str, Any], holes: List[Dict[str, Any]]) -> str:
    """Seed realism: seeds caught and rated material over seeds planted, beside the real-hole
    detection rate. Escape seeds are never a denominator (§3.9), and neither is a seed the
    pre-screen discarded or a fix orphaned."""
    planted = [
        s
        for s in vault["seeds"]
        if s.get("cohort") != "escape"
        and s.get("state") not in ("discarded", "orphaned")
    ]
    discarded = sum(1 for s in vault["seeds"] if s.get("state") == "discarded")
    if not planted:
        return f"realism: no seeds planted; {discarded} discarded by the pre-screen"
    caught = sum(1 for s in planted if s.get("state") == "caught")
    seed_rate = caught / len(planted)
    out = (
        f"realism {caught}/{len(planted)} = {seed_rate:.2f} (seeds caught and rated material / "
        f"seeds planted; {discarded} discarded by the pre-screen)"
    )
    real = [
        h
        for h in holes
        if (h.get("verification") or {}).get("status") == "CONFIRMED"
        and (h.get("materiality") or {}).get("level") == "MATERIAL"
        and not h.get("seed_match")
    ]
    found = sum(1 for h in real if h.get("source") in REVIEW_SOURCES)
    missed = sum(1 for h in real if h.get("source") in MISSED_SOURCES)
    if not missed:  # a detection rate needs the holes the rounds missed
        return out + "; real detection: no post-review holes recorded yet"
    real_rate = found / (found + missed)
    out += f"; real detection {found}/{found + missed} = {real_rate:.2f}"
    if seed_rate > real_rate * SEED_EASIER_RATIO:
        out += f"; FLAG: seeds easier than real holes (> {SEED_EASIER_RATIO}x)"
    return out


def cmd_status(a: argparse.Namespace) -> int:
    vault, _ = load_vault(a.program)
    print(json.dumps(counts(vault), sort_keys=True))
    try:
        holes = list(
            kit.fold(
                kit.read_jsonl(kit.records_dir(a.program) / "holes.jsonl")
            ).values()
        )
    except kit.KitError:  # an unregistered program has no records to hold a hole
        holes = []
    print(realism(vault, holes))
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
    p = sub.add_parser("prescreen")
    p.add_argument("--program", required=True)
    p.add_argument(
        "--caught", nargs="+", required=True, help="seed ids, or a file of them"
    )
    p.set_defaults(fn=cmd_prescreen)
    p = sub.add_parser("status")
    p.add_argument("--program", required=True)
    p.set_defaults(fn=cmd_status)
    a = ap.parse_args(argv)
    try:
        kit.check_slug(a.program)
        if a.verb not in VAULT_WRITERS:
            return int(a.fn(a))
        kit.lease_check(a.program)
        with vault_lock(a.program):
            return int(a.fn(a))
    except kit.KitError as e:
        print(f"seed.py: {e}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
