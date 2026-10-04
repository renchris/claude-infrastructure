#!/usr/bin/env python3
"""heldout.py — the sealed, labeled held-out set gate row 15 measures the re-ask router on
(REPORT.md §3.10 row 15; §10 items 11, 12 and 13).

Before the router is written (wave B1), the candidate prompts are split into a TUNING set, written
in the clear for the router's builder, and a SEALED set of at least 40, encrypted at rest under a
keychain key (`cc-research-router-heldout/sealed`) so the builder does not read it by accident. Two
raters label the sealed set; gate.sh reads it at run time. Same-uid processes can still read the
keychain, so this keeps the set out of the builder's way; it does not lock it (§7).

  heldout.py seal --candidates C.jsonl --tuning-out T.jsonl [--min-sealed 40]
      C.jsonl rows: {prompt, stratum: regex-matched|regex-missed|pushback|other, source}
  heldout.py rater-sheet --out F.jsonl        the sealed prompts by id, for a rater to label
  heldout.py label --rater NAME --labels L.jsonl   L.jsonl rows: {id, label}
  heldout.py status                            counts per stratum and rater; never a prompt
  heldout.py evaluate                          what gate row 15 runs (router in CC_RESEARCH_ROUTER)

The split is deterministic under a secret (HMAC of the prompt), so re-running `seal` cannot be used to
fish a different sealed set; a sealed set is sealed once.
"""

from __future__ import annotations

import argparse
import hashlib
import hmac
import json
import subprocess
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional

sys.path.insert(0, str(Path(__file__).resolve().parent / "lib"))
import kit  # noqa: E402

KEY_ITEM = "cc-research-router-heldout"
STRATA = ("regex-matched", "regex-missed", "pushback", "other")
COMPLETENESS_STRATA = ("regex-matched", "regex-missed", "pushback")
ROUTES = (
    "completeness",
    "pushback",
    "concern",
    "new-idea",
    "research-order",
    "work-order",
    "other",
)
RELAYED = ("completeness", "pushback")  # both routes relay the certificate (§4.1)
# Assumed inputs until the calibration run measures the router (§6.6); the router time limit was 6 s
# until ruling 4bf73c4e55d5 raised it to 9 s (REPORT.md §9, 2026-10-04):
MIN_SET, MIN_RECALL, MIN_OTHER_CORRECT, MAX_FALLBACK, ROUTER_TIMEOUT_S = (
    40,
    0.95,
    0.90,
    0.10,
    9,
)


def sealed_path() -> Path:
    return kit.research_home() / "router-heldout" / "sealed.enc"


def load() -> Dict[str, Any]:
    p = sealed_path()
    if not p.exists():
        raise kit.KitError(f"no sealed held-out set at {p} (heldout.py seal)")
    return json.loads(kit.decrypt(p.read_bytes(), kit.vault_key(KEY_ITEM, "sealed")))


def save(data: Dict[str, Any], key: str) -> None:
    d = sealed_path().parent
    d.mkdir(parents=True, exist_ok=True)
    d.chmod(0o700)
    tmp = d / ".sealed.enc.tmp"
    tmp.write_bytes(kit.encrypt(json.dumps(data, sort_keys=True).encode(), key))
    tmp.chmod(0o600)
    tmp.replace(sealed_path())


def item_id(prompt: str) -> str:
    return hashlib.sha256(prompt.encode()).hexdigest()[:12]


def cmd_seal(a: argparse.Namespace) -> int:
    if sealed_path().exists():
        raise kit.KitError("the held-out set is already sealed; it is sealed once")
    cands = kit.read_jsonl(Path(a.candidates))
    bad = [c for c in cands if c.get("stratum") not in STRATA or not c.get("prompt")]
    if bad:
        raise kit.KitError(
            f"{len(bad)} candidate(s) without a prompt or a known stratum ({', '.join(STRATA)})"
        )
    secret = kit.vault_key(KEY_ITEM, "split", create=True).encode()
    sealed, tuning = [], []
    for c in cands:
        h = hmac.new(secret, c["prompt"].encode(), hashlib.sha256).digest()
        (sealed if h[0] < int(256 * a.fraction) else tuning).append(c)
    missing = [s for s in STRATA if not any(c["stratum"] == s for c in sealed)]
    if len(sealed) < a.min_sealed or missing:
        raise kit.KitError(
            f"the sealed split holds {len(sealed)} prompt(s) (need {a.min_sealed})"
            + (f" and no {', '.join(missing)} stratum" if missing else "")
            + "; add candidates and seal again"
        )
    key = kit.vault_key(KEY_ITEM, "sealed", create=True)
    save(
        {
            "items": [
                {
                    "id": item_id(c["prompt"]),
                    "prompt": c["prompt"],
                    "stratum": c["stratum"],
                    "source": c.get("source"),
                    "labels": {},
                }
                for c in sealed
            ],
            "sealed_at": kit.now_iso(),
        },
        key,
    )
    Path(a.tuning_out).write_text(
        "".join(json.dumps(c, sort_keys=True) + "\n" for c in tuning)
    )
    print(f"sealed {len(sealed)} prompt(s); {len(tuning)} written to the tuning set")
    return 0


def cmd_rater_sheet(a: argparse.Namespace) -> int:
    data = load()
    Path(a.out).write_text(
        "".join(
            json.dumps({"id": i["id"], "prompt": i["prompt"]}) + "\n"
            for i in data["items"]
        )
    )
    print(
        f"wrote {len(data['items'])} prompt(s) for labeling; labels go back through heldout.py label"
    )
    return 0


def cmd_label(a: argparse.Namespace) -> int:
    data = load()
    by_id = {i["id"]: i for i in data["items"]}
    n = 0
    for r in kit.read_jsonl(Path(a.labels)):
        if r.get("label") not in ROUTES:
            raise kit.KitError(
                f"label {r.get('label')!r} is not a route ({', '.join(ROUTES)})"
            )
        if r.get("id") not in by_id:
            raise kit.KitError(f"unknown item id {r.get('id')!r}")
        by_id[r["id"]]["labels"][a.rater] = r["label"]
        n += 1
    save(data, kit.vault_key(KEY_ITEM, "sealed"))
    print(f"{a.rater}: {n} label(s) recorded")
    return 0


def counts(data: Dict[str, Any]) -> Dict[str, Any]:
    out: Dict[str, Any] = {}
    for i in data["items"]:
        c = out.setdefault(i["stratum"], {"items": 0, "agreed": 0, "raters": {}})
        c["items"] += 1
        labs = list(i["labels"].values())
        c["agreed"] += 1 if len(labs) >= 2 and len(set(labs)) == 1 else 0
        for r in i["labels"]:
            c["raters"][r] = c["raters"].get(r, 0) + 1
    return out


def route(router: str, prompt: str) -> Optional[str]:
    """The router's single label, or None for an error, timeout, unknown or mixed label."""
    try:
        p = subprocess.run(
            ["/bin/bash", "-c", router],
            input=prompt,
            capture_output=True,
            text=True,
            timeout=ROUTER_TIMEOUT_S,
        )
    except subprocess.TimeoutExpired:
        return None
    labels = p.stdout.replace(",", " ").split()
    if p.returncode != 0 or len(labels) != 1 or labels[0] not in ROUTES:
        return None
    return labels[0]


def evaluate(router: Optional[str]) -> Dict[str, List[str]]:
    """Gate row 15. A fallback (error, timeout, unknown or mixed label) is a miss in every stratum:
    the as-built router records it as `unavailable`, which relays nothing (router.py, §10 item 3), so
    it never counts as a correct relay. Fallbacks are also counted against MAX_FALLBACK."""
    if not router:
        raise kit.KitError("router not built (wave B1): CC_RESEARCH_ROUTER is unset")
    data = load()
    valid = [
        i
        for i in data["items"]
        if len(i["labels"]) >= 2 and len(set(i["labels"].values())) == 1
    ]
    fails: List[str] = []
    notes = [
        f"{len(data['items']) - len(valid)} item(s) excluded for rater disagreement or a missing label"
    ]
    if len(valid) < MIN_SET:
        return {
            "fails": [
                f"{len(valid)} agreed sealed item(s); at least {MIN_SET} are required"
            ],
            "notes": notes,
        }
    hits: Dict[str, List[int]] = {s: [0, 0] for s in STRATA}
    fallbacks = 0
    for i in valid:
        got = route(router, i["prompt"])
        if got is None:
            fallbacks += 1  # None is neither RELAYED nor any gold label: a miss below
        gold = next(iter(i["labels"].values()))
        h = hits[i["stratum"]]
        h[1] += 1
        if i["stratum"] in COMPLETENESS_STRATA and gold in RELAYED:
            h[0] += 1 if got in RELAYED else 0
        elif i["stratum"] == "other":
            h[0] += 1 if got == gold else 0
        else:
            h[1] -= (
                1  # a completeness-stratum prompt whose agreed label is not a re-ask
            )
    for s in STRATA:
        ok, n = hits[s]
        need = MIN_OTHER_CORRECT if s == "other" else MIN_RECALL
        if n == 0:
            fails.append(f"stratum {s}: no agreed item to measure")
        elif ok / n < need:
            fails.append(
                f"stratum {s}: {'correct-label rate' if s == 'other' else 'recall'} {ok}/{n} = "
                f"{ok / n:.2f}, below {need}"
            )
        else:
            notes.append(f"stratum {s}: {ok}/{n}")
    rate = fallbacks / len(valid)
    notes.append(
        f"{fallbacks} of {len(valid)} routed item(s) fell back (share {rate:.2f}); "
        "each is scored a miss in its stratum"
    )
    if rate > MAX_FALLBACK:
        fails.append(
            f"fallback rate {rate:.2f} (error or timeout at {ROUTER_TIMEOUT_S} s), above {MAX_FALLBACK}"
        )
    notes.append(
        f"thresholds are assumed inputs until calibration (§6.6): set ≥ {MIN_SET}, recall ≥ {MIN_RECALL}, "
        f"other ≥ {MIN_OTHER_CORRECT}, fallback ≤ {MAX_FALLBACK}"
    )
    return {"fails": fails, "notes": notes}


def main(argv: Optional[List[str]] = None) -> int:
    ap = argparse.ArgumentParser(prog="heldout.py")
    sub = ap.add_subparsers(dest="verb", required=True)
    p = sub.add_parser("seal")
    p.add_argument("--candidates", required=True)
    p.add_argument("--tuning-out", required=True)
    p.add_argument("--min-sealed", type=int, default=MIN_SET)
    p.add_argument("--fraction", type=float, default=0.5)
    p = sub.add_parser("rater-sheet")
    p.add_argument("--out", required=True)
    p = sub.add_parser("label")
    p.add_argument("--rater", required=True)
    p.add_argument("--labels", required=True)
    sub.add_parser("status")
    sub.add_parser("evaluate")
    a = ap.parse_args(argv)
    try:
        if a.verb == "seal":
            return cmd_seal(a)
        if a.verb == "rater-sheet":
            return cmd_rater_sheet(a)
        if a.verb == "label":
            return cmd_label(a)
        if a.verb == "status":
            print(json.dumps(counts(load()), sort_keys=True))
            return 0
        import os

        res = evaluate(os.environ.get("CC_RESEARCH_ROUTER"))
        print("\n".join(res["fails"] + res["notes"]))
        return 1 if res["fails"] else 0
    except kit.KitError as e:
        print(f"heldout.py: {e}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
