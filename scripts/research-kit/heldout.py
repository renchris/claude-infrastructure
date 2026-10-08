#!/usr/bin/env python3
"""heldout.py — the sealed, labeled held-out set gate row 15 measures the re-ask router on
(REPORT.md §3.10 row 15; §10 items 11, 12 and 13).

Before the router is written (wave B1), the candidate prompts are split into a TUNING set, written
in the clear for the router's builder, and a SEALED set of at least 40, encrypted at rest under a
keychain key (`cc-research-router-heldout/sealed`) so the builder does not read it by accident. Two
raters label the sealed set; gate.sh reads it at run time. Same-uid processes can still read the
keychain, so this keeps the set out of the builder's way; it does not lock it (§7).

  heldout.py [--set v1|v2|v3] seal --candidates C.jsonl --tuning-out T.jsonl [--min-sealed 40]
                                               [--exclude F.jsonl]... [--dry-run]
      C.jsonl rows: {prompt, stratum: regex-matched|regex-missed|pushback|other, source}
  heldout.py rater-sheet --out F.jsonl        the sealed prompts by id, for a rater to label
  heldout.py label --rater NAME --labels L.jsonl   L.jsonl rows: {id, label}
  heldout.py status                            counts per stratum and rater; never a prompt
  heldout.py evaluate --consent-sealed-read [--program P] [--record F.jsonl]
                                               what gate row 15 runs (router in CC_RESEARCH_ROUTER);
                                               --record keeps one row per routed item {id, set, stratum,
                                               counted, got, wall_s, load1}: no prompt and no rater label

The split is deterministic under a secret (HMAC of the prompt), so re-running `seal` cannot be used to
fish a different sealed set; a sealed set is sealed once.

SETS. v1 (`sealed.enc`) was read three times while the classifier was being configured (waves E1 and
E1b), and three of its strata are too small to judge, so wave E1c seals v2 (`sealed-v2.enc`, its own
keychain account) beside it. Each set is sealed once and no verb overwrites or deletes another set.
`seal --set v2` drops every candidate already in an earlier sealed set or in an `--exclude` file (the
earlier tuning set), so v2 holds only prompts no builder has seen. With `--set` omitted `seal` means
v1 and every other verb, and gate row 15, read the newest set that exists.
v2 was read twice (waves E1c and E1e), the second time by a configuration chosen knowing the first
read, so wave E1g seals v3 (`sealed-v3.enc`) for one read of the fast-plus-careful classifier. Its
candidates are v2's never-opened tuning file plus what the stores have gained since, and all of them
are sealed: `--fraction 1.0` leaves no tuning split. A prompt the candidates repeat is sealed once.

WAVE E1h (decision aba630ebe329). v3 read `other` at 0.76, so the classifier is chosen again on a
tuning base that looks like the sealed sets, and row 15 is then read once over a COMPOSITION of sets:

  heldout.py draw --candidates C --strata S,S --take S=N[,S=N] [--exclude F]... --out T.jsonl
      a fresh tuning sample, in the clear: no prompt of any sealed set or --exclude file, the first N
      of each stratum in the order of a keyed hash of its own (never seal's split hash, or every
      drawn prompt would sit on one side of a later split)
  heldout.py --set vN seal ... --strata S,S [--take S=N|all,...]
      a set of only the declared strata (the set stores them); --take keeps N of a stratum
  heldout.py --set vN retire --out F          a set that may carry no further verdict is written out,
      labels and all, as tuning data (F outside any repo); the sealed file is not touched and
      `evaluate` refuses the set from then on
  heldout.py instrument [--pin S=vN,...]       router-heldout/instrument.json: which set each stratum
      is scored from. With it pinned, `evaluate` without --set (gate row 15's call) scores each
      stratum from its own set and pools the item floor and the fallback share across them
  heldout.py reads [--before-ledger vN=K,...]  router-heldout/reads.jsonl, one row per stratum of a
      set per `evaluate`; the notes say how often each was read before. --before-ledger records, once
      per set, the reads made before the ledger existed

WAVE E1l (rulings a7fd5e2ee7c8, 915d7fb98b7f, 17aff7158fa6; docs/research/reask-row15-rulings-final-
2026-10-08/REPORT.md). `evaluate` decrypts nothing and logs no read unless every one of these holds,
in this order; a refusal is exit 2 with nothing written:
  - CC_RESEARCH_ROUTER is a real command: not empty, not `off` (the router's kill switch,
    hooks/research-precognition-nudge.sh), and a plain first word resolves on PATH
  - read consent: `evaluate --consent-sealed-read` (gate row 15: `gate.sh run --consent-sealed-read`,
    and only when rows 1-14 and 16-19 passed in that same run)
  - every stratum has a set pinned (`instrument --await S,S` leaves a stratum waiting for a fresh set)
  - no stratum of a set is read a third time without an operator signature per extra read,
    `cc-signoff research:<slug>/third-read/<set>.<stratum>` (`evaluate --program <slug>` finds it);
    a signed read is printed as a disclosed cost
  - RULE E1k's real-load figures above load 150 are on record and pass (`heldout.py real-load`)
  - the 1-min load reaches 40 or below within the start cap (CC_RESEARCH_ROW15_START_CAP_S, 4 h)
After the ledger row is written, every item waits for load 40 or below again, under one total cap
for the read (CC_RESEARCH_ROW15_TOTAL_CAP_S, 12 h); past it the read ends "read spent, no verdict".
Each routed row records its 1-min load (`load1`), and the notes state the bound beside RULE E1k's
figures, so the certificate carries both.

  heldout.py real-load --run N --source F --rows N --fallbacks K --held H
      records RULE E1k's verdict run (hedge-on rows above load 150, their fallbacks, rows held with
      one call silent); fewer than 40 rows is "high load not exercised" and is refused

A read takes about 73 minutes plus its load waits, so launch the gate DETACHED, never under a tool
call's timeout or the job reaper (`nohup` is not enough; scripts/lib/detach.sh):
  . scripts/lib/detach.sh; detach "$LOG" scripts/research-kit/gate.sh run --program P --consent-sealed-read
"""

from __future__ import annotations

import argparse
import hashlib
import hmac
import json
import os
import re
import shutil
import subprocess
import sys
import time
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
# Wave E1l. The kill-switch values of CC_RESEARCH_ROUTER (hooks/research-precognition-nudge.sh):
KILL_SWITCH = ("off",)
# A stratum of a set is read at most twice; each read beyond that needs its own operator signature
# (ruling 915d7fb98b7f item 5):
FREE_READS = 2
# The load bound (ruling 17aff7158fa6): every item is routed at 1-min load at or below LOAD_BOUND.
# The caps bound only how long the read waits for that, never the condition, so they may be set.
LOAD_BOUND = 40.0
START_CAP_S, TOTAL_CAP_S, POLL_S = 4 * 3600, 12 * 3600, 15.0
# RULE E1k (docs/plans/RESEARCH_PROGRAM_BUILD.md, wave E1k B5): a pass is hedge-on fallback at most
# 0.03 over at least 40 hedge-on rows above load 150.
E1K_LOAD, E1K_MIN_ROWS, E1K_MAX_FALLBACK = 150, 40, 0.03


SETS = (
    "v1",
    "v2",
    "v3",
    "v4",
)  # oldest first; v1 keeps the file and keychain account it was sealed under


def check_set(name: str) -> str:
    if name not in SETS:
        raise kit.KitError(f"unknown held-out set {name!r} ({', '.join(SETS)})")
    return name


def sealed_path(name: str = "v1") -> Path:
    check_set(name)
    return (
        kit.research_home()
        / "router-heldout"
        / ("sealed.enc" if name == "v1" else f"sealed-{name}.enc")
    )


def key_account(name: str) -> str:
    return "sealed" if check_set(name) == "v1" else f"sealed-{name}"


def current_set() -> str:
    """The newest set that is sealed; v1 when none is."""
    for name in reversed(SETS):
        if sealed_path(name).exists():
            return name
    return "v1"


def heldout_dir() -> Path:
    return kit.research_home() / "router-heldout"


def ledger() -> List[Dict[str, Any]]:
    """The reads ledger's rows; a line that is not a JSON object is skipped."""
    out: List[Dict[str, Any]] = []
    try:
        lines = (heldout_dir() / "reads.jsonl").read_text().splitlines()
    except OSError:
        return out
    for line in lines:
        try:
            r = json.loads(line)
        except ValueError:
            continue
        if isinstance(r, dict):
            out.append(r)
    return out


def ledger_add(rows: List[Dict[str, Any]]) -> None:
    d = heldout_dir()
    d.mkdir(parents=True, exist_ok=True)
    p = d / "reads.jsonl"
    with open(p, "a") as fh:
        fh.write("".join(json.dumps(r, sort_keys=True) + "\n" for r in rows))
    p.chmod(0o600)


def retired(name: str) -> bool:
    return any(r.get("event") == "retire" and r.get("set") == name for r in ledger())


def set_strata(data: Dict[str, Any]) -> List[str]:
    """The strata a sealed set holds: all four unless it was sealed with --strata."""
    return [s for s in STRATA if s in (data.get("strata") or STRATA)]


def instrument() -> Optional[Dict[str, Optional[str]]]:
    """{stratum: set} when a composition is pinned, None when none is. A file that is there and
    cannot be read as one is an error: the gate must not fall back to some other set in silence.
    A stratum mapped to null waits for a fresh set (`instrument --await`, wave E1l)."""
    p = heldout_dir() / "instrument.json"
    if not p.exists():
        return None
    try:
        plan = json.loads(p.read_text())["strata"]
        ok = isinstance(plan, dict) and sorted(plan) == sorted(STRATA)
    except (OSError, ValueError, KeyError, TypeError):
        ok = False
    if not ok:
        raise kit.KitError(f"{p} does not pin one set to each of {', '.join(STRATA)}")
    return {s: None if plan[s] is None else check_set(plan[s]) for s in STRATA}


def parse_strata(spec: Optional[str]) -> List[str]:
    want = [x for x in (spec or "").split(",") if x] or list(STRATA)
    bad = [x for x in want if x not in STRATA]
    if bad:
        raise kit.KitError(f"unknown stratum {', '.join(bad)} ({', '.join(STRATA)})")
    return [s for s in STRATA if s in want]


def parse_take(spec: Optional[str], declared: List[str]) -> Dict[str, Optional[int]]:
    """{stratum: N, or None for all}; a stratum --take does not name keeps all."""
    out: Dict[str, Optional[int]] = {}
    for part in [x for x in (spec or "").split(",") if x]:
        k, _, n = part.partition("=")
        if k not in declared or not (n == "all" or n.isdigit()):
            raise kit.KitError(
                f"--take {part!r}: expected STRATUM=N|all for a declared stratum"
            )
        out[k] = None if n == "all" else int(n)
    return out


def take_order(secret: bytes, prompt: str) -> str:
    """The order prompts are taken in. Its own domain: seal's split reads byte 0 of HMAC(prompt), so
    an order by that same hash would put every taken prompt on one side of a later split."""
    return hmac.new(secret, b"take|" + prompt.encode(), hashlib.sha256).hexdigest()


def load(name: Optional[str] = None) -> Dict[str, Any]:
    name = check_set(name or current_set())
    p = sealed_path(name)
    if not p.exists():
        raise kit.KitError(f"no sealed held-out set {name} at {p} (heldout.py seal)")
    return json.loads(
        kit.decrypt(p.read_bytes(), kit.vault_key(KEY_ITEM, key_account(name)))
    )


def save(data: Dict[str, Any], key: str, name: str) -> None:
    d = sealed_path(name).parent
    d.mkdir(parents=True, exist_ok=True)
    d.chmod(0o700)
    tmp = d / f".{sealed_path(name).name}.tmp"
    tmp.write_bytes(kit.encrypt(json.dumps(data, sort_keys=True).encode(), key))
    tmp.chmod(0o600)
    tmp.replace(sealed_path(name))


def item_id(prompt: str) -> str:
    return hashlib.sha256(prompt.encode()).hexdigest()[:12]


def seen_key(prompt: str) -> str:
    """What makes a candidate the same prompt as one already used: its first 200 characters with case
    and whitespace folded, because one prompt reads slightly differently in two stores."""
    return hashlib.sha256(" ".join(prompt.split()).lower()[:200].encode()).hexdigest()


def cmd_seal(a: argparse.Namespace) -> int:
    name = check_set(a.set or "v1")
    if sealed_path(name).exists():
        later = [s for s in SETS[SETS.index(name) + 1 :] if not sealed_path(s).exists()]
        raise kit.KitError(
            f"the held-out set {name} is already sealed; it is sealed once"
            + (f" (a new set is `--set {later[0]}`)" if later else "")
        )
    declared = parse_strata(a.strata)
    take = parse_take(a.take, declared)
    cands = read_candidates(Path(a.candidates), declared)
    used = set()
    for earlier in SETS[: SETS.index(name)]:
        if sealed_path(earlier).exists():
            used |= {seen_key(i["prompt"]) for i in load(earlier)["items"]}
    for f in a.exclude or []:
        used |= {
            seen_key(r["prompt"]) for r in kit.read_jsonl(Path(f)) if r.get("prompt")
        }
    fresh = []
    for c in cands:
        k = seen_key(c["prompt"])
        if k not in used:
            fresh.append(c)
            used.add(
                k
            )  # a prompt the candidates repeat (two stores, two files) is sealed once
    dropped = len(cands) - len(fresh)
    cands = fresh
    secret = kit.vault_key(KEY_ITEM, "split", create=not a.dry_run).encode()
    sealed, tuning = [], []
    for c in cands:
        h = hmac.new(secret, c["prompt"].encode(), hashlib.sha256).digest()
        (sealed if h[0] < int(256 * a.fraction) else tuning).append(c)
    left = (
        0  # sealed-side prompts beyond a stratum's --take: left out, and still unused
    )
    for s, n in take.items():
        if n is None:
            continue
        mine = sorted(
            (c for c in sealed if c["stratum"] == s),
            key=lambda c: take_order(secret, c["prompt"]),
        )
        over = {id(c) for c in mine[n:]}
        left += len(over)
        sealed = [c for c in sealed if id(c) not in over]
    missing = [s for s in declared if not any(c["stratum"] == s for c in sealed)]
    if len(sealed) < a.min_sealed or missing:
        raise kit.KitError(
            f"the sealed split holds {len(sealed)} prompt(s) (need {a.min_sealed})"
            + (f" and no {', '.join(missing)} stratum" if missing else "")
            + "; add candidates and seal again"
        )
    per = {s: sum(1 for c in sealed if c["stratum"] == s) for s in declared}
    beyond = f"; {left} left unsealed beyond --take" if left else ""
    if a.dry_run:
        print(
            f"would seal {len(sealed)} prompt(s) as set {name} {json.dumps(per, sort_keys=True)}; "
            f"{len(tuning)} to the tuning set; {dropped} candidate(s) dropped as already used"
            f"{beyond}; nothing written"
        )
        return 0
    key = kit.vault_key(KEY_ITEM, key_account(name), create=True)
    body: Dict[str, Any] = {"strata": declared} if declared != list(STRATA) else {}
    save(
        {
            **body,
            "set": name,
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
        name,
    )
    Path(a.tuning_out).write_text(
        "".join(json.dumps(c, sort_keys=True) + "\n" for c in tuning)
    )
    print(
        f"sealed {len(sealed)} prompt(s) as set {name} {json.dumps(per, sort_keys=True)}; "
        f"{len(tuning)} written to the tuning set"
        + (f"; {dropped} candidate(s) dropped as already used" if dropped else "")
        + beyond
    )
    return 0


def read_candidates(path: Path, declared: List[str]) -> List[Dict[str, Any]]:
    """The candidate rows of the declared strata; a row with no prompt or no known stratum is an
    error, and a row of an undeclared stratum is left out (it stays unused)."""
    cands = kit.read_jsonl(path)
    bad = [c for c in cands if c.get("stratum") not in STRATA or not c.get("prompt")]
    if bad:
        raise kit.KitError(
            f"{len(bad)} candidate(s) without a prompt or a known stratum ({', '.join(STRATA)})"
        )
    return [c for c in cands if c["stratum"] in declared]


def cmd_draw(a: argparse.Namespace) -> int:
    declared = parse_strata(a.strata)
    take = parse_take(a.take, declared)
    cands = read_candidates(Path(a.candidates), declared)
    used = set()
    for name in SETS:
        if sealed_path(name).exists():
            used |= {seen_key(i["prompt"]) for i in load(name)["items"]}
    for f in a.exclude or []:
        used |= {
            seen_key(r["prompt"]) for r in kit.read_jsonl(Path(f)) if r.get("prompt")
        }
    fresh = []
    for c in cands:
        k = seen_key(c["prompt"])
        if k not in used:
            fresh.append(c)
            used.add(k)
    secret = kit.vault_key(KEY_ITEM, "split", create=True).encode()
    drawn: List[Dict[str, Any]] = []
    per: Dict[str, int] = {}
    rest: Dict[str, int] = {}
    for s in declared:
        mine = sorted(
            (c for c in fresh if c["stratum"] == s),
            key=lambda c: take_order(secret, c["prompt"]),
        )
        n = take.get(s)
        if n is not None and len(mine) < n:
            raise kit.KitError(
                f"stratum {s}: {len(mine)} fresh candidate(s), fewer than the {n} to draw; "
                "nothing written"
            )
        got = mine if n is None else mine[:n]
        drawn += got
        per[s], rest[s] = len(got), len(mine) - len(got)
    out = Path(a.out)
    out.write_text(
        "".join(
            json.dumps(
                {
                    "prompt": c["prompt"],
                    "stratum": c["stratum"],
                    "source": c.get("source"),
                },
                sort_keys=True,
            )
            + "\n"
            for c in drawn
        )
    )
    out.chmod(0o600)
    print(
        f"drew {len(drawn)} prompt(s) {json.dumps(per, sort_keys=True)}; "
        f"{len(cands) - len(fresh)} candidate(s) dropped as already used; "
        f"fresh and not drawn {json.dumps(rest, sort_keys=True)}"
    )
    return 0


def in_a_repo(path: Path) -> bool:
    return any((d / ".git").exists() for d in path.resolve().parents)


def cmd_retire(a: argparse.Namespace) -> int:
    if not a.set:
        raise kit.KitError(
            "retire needs --set: name the set that carries no further verdict"
        )
    out = Path(a.out)
    if in_a_repo(out):
        raise kit.KitError(
            f"{out} is inside a repo; a retired set is written outside the repo"
        )
    data = load(a.set)
    out.write_text(
        "".join(
            json.dumps(
                {
                    "id": i["id"],
                    "prompt": i["prompt"],
                    "stratum": i["stratum"],
                    "source": i.get("source"),
                    "labels": i["labels"],
                },
                sort_keys=True,
            )
            + "\n"
            for i in data["items"]
        )
    )
    out.chmod(0o600)
    if not retired(a.set):
        ledger_add(
            [{"event": "retire", "set": a.set, "at": kit.now_iso(), "out": str(out)}]
        )
    print(
        f"retired set {a.set}: {len(data['items'])} prompt(s) with their labels written as tuning "
        "data; the sealed file is unchanged and evaluate refuses the set from now on"
    )
    return 0


def cmd_instrument(a: argparse.Namespace) -> int:
    p = heldout_dir() / "instrument.json"
    if a.await_:
        return cmd_instrument_await(p, a.await_)
    if not a.pin:
        plan = instrument()
        print(json.dumps(plan, sort_keys=True) if plan else "no instrument pinned")
        return 0
    plan = {}
    for part in a.pin.split(","):
        s, _, name = part.partition("=")
        if s not in STRATA:
            raise kit.KitError(f"--pin {part!r}: expected STRATUM=SET")
        plan[s] = check_set(name)
    if sorted(plan) != sorted(STRATA):
        raise kit.KitError(f"--pin must name each of {', '.join(STRATA)} once")
    for s, name in plan.items():
        if retired(name):
            raise kit.KitError(f"set {name} is retired; it carries no further verdict")
        if s not in set_strata(load(name)):
            raise kit.KitError(f"set {name} does not hold {s}")
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(
        json.dumps({"strata": plan, "pinned_at": kit.now_iso()}, sort_keys=True) + "\n"
    )
    p.chmod(0o600)
    print(f"instrument pinned: {json.dumps(plan, sort_keys=True)}")
    return 0


def cmd_instrument_await(p: Path, spec: str) -> int:
    """Unpin strata so they wait for a fresh set (wave E1l, ruling 915d7fb98b7f item 5). It opens no
    sealed set: the pinned map is edited as it stands, and `evaluate` refuses while one waits."""
    want = [x for x in spec.split(",") if x]
    bad = [x for x in want if x not in STRATA]
    if bad or not want:
        raise kit.KitError(
            f"--await {spec!r}: expected STRATUM[,STRATUM] of {', '.join(STRATA)}"
        )
    plan = instrument()
    if plan is None:
        raise kit.KitError("no instrument pinned; --await edits a pinned one")
    was = {s: plan[s] for s in want}
    plan.update({s: None for s in want})
    p.write_text(
        json.dumps({"strata": plan, "pinned_at": kit.now_iso()}, sort_keys=True) + "\n"
    )
    p.chmod(0o600)
    print(
        f"instrument: {', '.join(f'{s} (was {was[s]})' for s in want)} now await a fresh set; "
        f"pinned: {json.dumps(plan, sort_keys=True)}"
    )
    return 0


def reads_before() -> Dict[Any, int]:
    """{(set, stratum): how many times it has been read}, from the ledger."""
    n: Dict[Any, int] = {}
    for r in ledger():
        if r.get("event") == "read":
            k = (r.get("set"), r.get("stratum"))
            n[k] = n.get(k, 0) + int(r.get("times") or 1)
    return n


def cmd_reads(a: argparse.Namespace) -> int:
    if a.before_ledger:
        rows = []
        for part in a.before_ledger.split(","):
            name, _, k = part.partition("=")
            check_set(name)
            if not k.isdigit():
                raise kit.KitError(f"--before-ledger {part!r}: expected SET=COUNT")
            if any(r.get("before_ledger") and r.get("set") == name for r in ledger()):
                continue  # recorded once per set
            for s in set_strata(load(name)):
                rows.append(
                    {
                        "event": "read",
                        "set": name,
                        "stratum": s,
                        "times": int(k),
                        "before_ledger": True,
                        "at": kit.now_iso(),
                    }
                )
        ledger_add(rows)
    counts = reads_before()
    print(
        json.dumps(
            {
                "reads": {
                    f"{k[0]} {k[1]}": v for k, v in sorted(counts.items(), key=str)
                },
                "retired": sorted(s for s in SETS if retired(s)),
            },
            sort_keys=True,
        )
    )
    return 0


def cmd_rater_sheet(a: argparse.Namespace) -> int:
    data = load(a.set)
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
    name = check_set(a.set or current_set())
    data = load(name)
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
    save(data, kit.vault_key(KEY_ITEM, key_account(name)), name)
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


def router_refusal(router: Optional[str]) -> Optional[str]:
    """Why CC_RESEARCH_ROUTER is not a router `evaluate` may spend a read on, or None (wave E1l,
    ruling a7fd5e2ee7c8 guard 1). route() runs it as `/bin/bash -c`, so `off` would fall back on
    every item and still spend the read."""
    if not router or not router.strip():
        return "router not built (wave B1): CC_RESEARCH_ROUTER is unset"
    if router.strip().lower() in KILL_SWITCH:
        return (
            f"CC_RESEARCH_ROUTER is {router.strip()!r}, the router's kill switch "
            "(hooks/research-precognition-nudge.sh), not a router: every item would fall back"
        )
    first = router.split()[0]
    if re.fullmatch(r"[A-Za-z0-9_./+-]+", first) and not shutil.which(first):
        return f"CC_RESEARCH_ROUTER runs {first!r}, which is not found: every item would fall back"
    return None


def live_store() -> str:
    """The live research store of the real user, whatever HOME says (as fixture_signer.py reads it)."""
    import pwd

    return os.path.realpath(
        Path(pwd.getpwuid(os.getuid()).pw_dir) / ".claude" / "autonomy" / "research"
    )


_LOAD_FIXTURE: Dict[str, Any] = {"vals": None, "i": 0}


def load1() -> float:
    """The machine's 1-minute load. A fixture research home, never the live store, may plant a
    sequence in router-heldout/load1.fixture: one value per line, read in order, the last repeating."""
    home, live = os.path.realpath(kit.research_home()), live_store()
    f = heldout_dir() / "load1.fixture"
    if home != live and not home.startswith(live + os.sep) and f.exists():
        if _LOAD_FIXTURE["vals"] is None:
            _LOAD_FIXTURE["vals"] = [float(x) for x in f.read_text().split()] or [0.0]
        vals, i = _LOAD_FIXTURE["vals"], _LOAD_FIXTURE["i"]
        _LOAD_FIXTURE["i"] = i + 1
        return vals[min(i, len(vals) - 1)]
    return os.getloadavg()[0]


def env_seconds(var: str, default: float) -> float:
    try:
        return float(os.environ.get(var) or default)
    except ValueError:
        raise kit.KitError(f"{var} must be a number of seconds")


def wait_load(deadline: float) -> Any:
    """(True, load) once the 1-min load is at or below LOAD_BOUND; (False, last load) when the next
    poll would pass `deadline` (time.monotonic()) first."""
    poll = env_seconds("CC_RESEARCH_ROW15_POLL_S", POLL_S)
    while True:
        now = load1()
        if now <= LOAD_BOUND:
            return True, now
        if time.monotonic() + poll > deadline:
            return False, now
        time.sleep(poll)


def real_load() -> Dict[str, Any]:
    """RULE E1k's verdict run as `real-load` recorded it. The read waits for its pass (ruling
    a7fd5e2ee7c8), and the certificate states its figures beside the load bound (17aff7158fa6)."""
    p = heldout_dir() / "real-load.json"
    try:
        r = json.loads(p.read_text())
        rows, fb = int(r["rows"]), int(r["fallbacks"])
    except OSError:
        raise kit.KitError(
            "RULE E1k's real-load figures above load 150 are not on record (heldout.py real-load): "
            "the read waits for its pass, and the certificate states them beside the load bound"
        )
    except (ValueError, KeyError, TypeError):
        raise kit.KitError(f"{p} does not hold RULE E1k's figures")
    if rows < E1K_MIN_ROWS or fb / rows > E1K_MAX_FALLBACK:
        raise kit.KitError(
            f"RULE E1k run {r.get('run')} did not pass: hedge-on fallback {fb}/{rows} above load "
            f"{E1K_LOAD}, against at most {E1K_MAX_FALLBACK} over at least {E1K_MIN_ROWS} rows"
        )
    return r


def cmd_real_load(a: argparse.Namespace) -> int:
    p = heldout_dir() / "real-load.json"
    if a.rows is None:
        print(p.read_text().strip() if p.exists() else "no RULE E1k figures on record")
        return 0
    if a.run is None or a.fallbacks is None or a.held is None or not a.source:
        raise kit.KitError(
            "real-load needs --run, --source, --rows, --fallbacks and --held"
        )
    if not Path(a.source).exists():
        raise kit.KitError(
            f"--source {a.source} does not exist: name the run's own report"
        )
    if a.rows < E1K_MIN_ROWS:
        raise kit.KitError(
            f"{a.rows} hedge-on rows above load {E1K_LOAD}: high load not exercised (RULE E1k needs "
            f"{E1K_MIN_ROWS}); no verdict to record"
        )
    ok = a.fallbacks / a.rows <= E1K_MAX_FALLBACK
    rec = {
        "rule": "E1k",
        "run": a.run,
        "source": a.source,
        "load_floor": E1K_LOAD,
        "rows": a.rows,
        "fallbacks": a.fallbacks,
        "held_one_silent": a.held,
        "verdict": "PASS" if ok else "FAIL",
        "recorded_at": kit.now_iso(),
    }
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(json.dumps(rec, sort_keys=True) + "\n")
    p.chmod(0o600)
    print(
        f"RULE E1k run {a.run}: {rec['verdict']} ({a.fallbacks}/{a.rows} hedge-on fallbacks)"
    )
    return 0


def third_read_signatures(program: Optional[str]) -> Dict[str, List[Dict[str, Any]]]:
    """The program's VALID `third-read` operator signatures, by target <set>.<stratum>."""
    if not program:
        return {}
    sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "lib"))
    import operator_sign

    out: Dict[str, List[Dict[str, Any]]] = {}
    for r in operator_sign.research_records(program, "third-read"):
        if r["_verdict"] == operator_sign.VALID:
            out.setdefault(str(r.get("target")), []).append(r)
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


def evaluate(
    router: Optional[str],
    name: Optional[str] = None,
    record: Optional[Path] = None,
    consent: bool = False,
    program: Optional[str] = None,
) -> Dict[str, List[str]]:
    """Gate row 15. A fallback (error, timeout, unknown or mixed label) is a miss in every stratum:
    the as-built router records it as `unavailable`, which relays nothing (router.py, §10 item 3), so
    it never counts as a correct relay. Fallbacks are also counted against MAX_FALLBACK.

    With no set named, a pinned instrument decides which set each stratum is scored from (wave E1h);
    the item floor and the fallback share are pooled over everything routed.

    Wave E1l: every refusal below comes before any set is decrypted or the reads ledger is written
    (the order is in this module's docstring)."""
    refusal = router_refusal(router)
    if refusal:
        raise kit.KitError(refusal)
    if not consent:
        raise kit.KitError(
            "no read consent: a sealed read is spent only on purpose (heldout.py evaluate "
            "--consent-sealed-read; gate.sh run --consent-sealed-read); nothing decrypted, no read logged"
        )
    pinned = None if name else instrument()
    if pinned:
        waiting = [s for s in STRATA if pinned[s] is None]
        if waiting:
            raise kit.KitError(
                f"stratum {', '.join(waiting)}: no set pinned, it awaits a fresh set (heldout.py "
                "instrument --await; ruling 915d7fb98b7f); no read logged"
            )
        plan: Dict[str, str] = {s: str(pinned[s]) for s in STRATA}
    else:
        name = check_set(name or current_set())
        plan = {s: name for s in STRATA}
    for n in sorted(set(plan.values())):
        if retired(n):
            raise kit.KitError(
                f"set {n} is retired to tuning data (heldout.py retire); it carries no further verdict"
            )
    # A stratum of a set is read at most FREE_READS times; each read beyond needs its own operator
    # signature, and is said in the notes as a disclosed cost (ruling 915d7fb98b7f item 5).
    sigs = third_read_signatures(program)
    before = reads_before()
    over, disclosed = [], []
    for s in STRATA:
        k, signed = before.get((plan[s], s), 0), sigs.get(f"{plan[s]}.{s}", [])
        if k >= FREE_READS + len(signed):
            over.append(f"{s} of {plan[s]} (read {k} times, {len(signed)} signed)")
        elif k >= FREE_READS:
            last = max(signed, key=lambda r: r.get("at", 0))
            disclosed.append(
                f"stratum {s} of set {plan[s]}: read {k + 1}, beyond the second, a disclosed cost "
                f"under operator signature {last.get('at_iso')} ({last.get('because')})"
            )
    if over:
        raise kit.KitError(
            "a read beyond the second is refused without a signed override: "
            + "; ".join(over)
            + " (cc-signoff research:<slug>/third-read/<set>.<stratum>, then evaluate --program "
            "<slug>); no read logged"
        )
    companion = real_load()
    t0 = time.monotonic()
    cap = env_seconds("CC_RESEARCH_ROW15_START_CAP_S", START_CAP_S)
    ok, now = wait_load(t0 + cap)
    if not ok:
        raise kit.KitError(
            f"1-min load stayed above {LOAD_BOUND:g} for the start cap ({cap:g} s; last {now:.1f}): "
            "nothing decrypted, no read logged (ruling 17aff7158fa6)"
        )
    datas: Dict[str, Dict[str, Any]] = {n: load(n) for n in sorted(set(plan.values()))}
    # (set, item) for every item of a stratum in the set that stratum is scored from
    pool = [
        (n, i)
        for n in sorted(datas, key=SETS.index)
        for i in datas[n]["items"]
        if plan.get(i["stratum"]) == n and i["stratum"] in set_strata(datas[n])
    ]
    valid = [
        (n, i)
        for n, i in pool
        if len(i["labels"]) >= 2 and len(set(i["labels"].values())) == 1
    ]
    fails: List[str] = []
    notes = [
        (
            "held-out instrument, each stratum from its own set: "
            + " · ".join(f"{s} from {plan[s]}" for s in STRATA)
            + f"; {len(pool)} sealed item(s)"
        )
        if pinned
        else f"held-out set {name}: {len(pool)} sealed item(s)",
        f"{len(pool) - len(valid)} item(s) excluded for rater disagreement or a missing label",
    ]
    if len(valid) < MIN_SET:
        return {
            "fails": [
                f"{len(valid)} agreed sealed item(s); at least {MIN_SET} are required"
            ],
            "notes": notes,
        }
    # The reads ledger: what was read before, said in the notes; then this read, written before the
    # first call so a read that is cut short still counts.
    held = sorted(
        {(n, i["stratum"]) for n, i in pool}, key=lambda k: (STRATA.index(k[1]), k[0])
    )
    before = reads_before()
    notes += [
        f"stratum {s} of set {n}: read {before.get((n, s), 0)} time(s) before"
        for n, s in held
    ] + disclosed
    ledger_add(
        [
            {
                "event": "read",
                "set": n,
                "stratum": s,
                "at": kit.now_iso(),
                "instrument": bool(pinned),
            }
            for n, s in held
        ]
    )
    hits: Dict[str, List[int]] = {s: [0, 0] for s in STRATA}
    exact = [0, 0]  # `other`'s exact-label rate: shown only since wave E1i
    fell: Dict[str, int] = {
        s: 0 for s in STRATA
    }  # fallbacks among the items a stratum counts
    false_relay: Dict[str, List[int]] = {s: [0, 0] for s in STRATA}
    store: Dict[str, List[int]] = {"history": [0, 0], "transcript": [0, 0]}
    fallbacks = 0
    rows: List[Dict[str, Any]] = []
    # The load bound, per item, under one total cap for the read; past it nothing more is routed and
    # the read ends with no verdict (it is already in the ledger).
    logged = len(notes)  # the notes a spent read keeps: none of the scoring below is a verdict
    total_cap = env_seconds("CC_RESEARCH_ROW15_TOTAL_CAP_S", TOTAL_CAP_S)
    deadline = time.monotonic() + total_cap
    spent: List[float] = []

    def routed(n: str, i: Dict[str, Any], counted: bool) -> Optional[str]:
        if spent:
            return None
        ok, load_now = wait_load(deadline)
        if not ok:
            spent.append(load_now)
            return None
        t0 = time.time()
        got = route(router, i["prompt"])
        rows.append(
            {
                "id": i["id"],
                "set": n,
                "stratum": i["stratum"],
                "counted": counted,
                "got": got,
                "wall_s": round(time.time() - t0, 2),
                "load1": round(load_now, 2),
            }
        )
        return got

    for n, i in valid:
        got = routed(n, i, True)
        if got is None:
            fallbacks += 1  # None is neither RELAYED nor any gold label: a miss below
        gold = next(iter(i["labels"].values()))
        if gold not in RELAYED:
            fr = false_relay[i["stratum"]]
            fr[0] += 1 if got in RELAYED else 0
            fr[1] += 1
        h = hits[i["stratum"]]
        h[1] += 1
        if i["stratum"] in COMPLETENESS_STRATA and gold in RELAYED:
            h[0] += 1 if got in RELAYED else 0
        elif i["stratum"] == "other":
            # Wave E1i (decision 1f3b8f2d01b7, REPORT gate row 15): right when the router relays exactly
            # when the agreed label relays; a fallback relays nothing but is still a miss.
            right = got is not None and (got in RELAYED) == (gold in RELAYED)
            h[0] += 1 if right else 0
            exact[0] += 1 if got == gold else 0
            exact[1] += 1
            st = store[
                "history"
                if str(i.get("source") or "").startswith("history:")
                else "transcript"
            ]
            st[0] += 1 if right else 0
            st[1] += 1
        else:
            h[1] -= (
                1  # a completeness-stratum prompt whose agreed label is not a re-ask
            )
            continue
        fell[i["stratum"]] += 1 if got is None else 0
    for s in STRATA:
        ok, n_items = hits[s]
        need = MIN_OTHER_CORRECT if s == "other" else MIN_RECALL
        if n_items == 0:
            fails.append(f"stratum {s}: no agreed item to measure")
        elif ok / n_items < need:
            fails.append(
                f"stratum {s}: {'relay-decision rate' if s == 'other' else 'recall'} {ok}/{n_items} = "
                f"{ok / n_items:.2f}, below {need}"
            )
        else:
            notes.append(
                f"stratum {s}: {ok}/{n_items}"
                + (" (relay decision)" if s == "other" else "")
            )
    if exact[1]:
        notes.append(
            f"other, exact label (shown only, never a failure): {exact[0]}/{exact[1]}"
        )
    rate = fallbacks / len(valid)
    notes.append(
        f"{fallbacks} of {len(valid)} routed item(s) fell back (share {rate:.2f}); "
        "each is scored a miss in its stratum"
    )
    notes.append(
        "fallbacks among counted items, which tells a slow classifier from a wrong one: "
        + " · ".join(f"{s} {fell[s]} of {hits[s][1]}" for s in STRATA)
    )
    if rate > MAX_FALLBACK:
        fails.append(
            f"fallback rate {rate:.2f} (error or timeout at {ROUTER_TIMEOUT_S} s), above {MAX_FALLBACK}"
        )
    # Shown only, never a failure (wave E1h): what a wrong relay costs is a blocked turn, so the
    # notes say how often an agreed non-relay prompt was relayed, and how `other` reads in each store.
    shown = [s for s in ("other",) + COMPLETENESS_STRATA if false_relay[s][1]]
    if shown:
        notes.append(
            "relayed although both raters gave a non-relay label: "
            + " · ".join(f"{s} {false_relay[s][0]}/{false_relay[s][1]}" for s in shown)
        )
    if store["history"][1] or store["transcript"][1]:
        notes.append(
            "other by store, relay decision right / items: "
            + " · ".join(f"{k} {v[0]}/{v[1]}" for k, v in store.items())
        )
    # Not counted, shown only: a completeness-stratum prompt both raters would relay, under two
    # different relay labels. Row 15 leaves it out as a disagreement; this line says what that costs.
    split = [
        (n, i)
        for n, i in pool
        if i["stratum"] in COMPLETENESS_STRATA
        and len(i["labels"]) >= 2
        and len(set(i["labels"].values())) > 1
        and all(lab in RELAYED for lab in i["labels"].values())
    ]
    if split:
        seen: Dict[str, List[int]] = {s: [0, 0, 0] for s in COMPLETENESS_STRATA}
        for n, i in split:
            got = routed(n, i, False)
            c = seen[i["stratum"]]
            c[0] += 1 if got in RELAYED else 0
            c[1] += 1
            c[2] += 1 if got is None else 0
        notes.append(
            "not counted in any line above (the raters chose two different relay labels), relayed / "
            "items / fell back: "
            + " · ".join(f"{s} {c[0]}/{c[1]}/{c[2]}" for s, c in seen.items())
        )
    if spent:
        del notes[logged:]
        fails = [
            f"read spent, no verdict: 1-min load stayed above {LOAD_BOUND:g} past the read's total "
            f"cap ({total_cap:g} s; last {spent[0]:.1f}) after {len(rows)} routed item(s); the reads "
            "ledger holds this read"
        ]
    else:
        notes.append(
            f"load bound (ruling 17aff7158fa6), a stated condition of row 15: every routed item "
            f"started at 1-min load <= {LOAD_BOUND:g} (highest "
            f"{max((r['load1'] for r in rows), default=0.0):.1f}); real-load companion, RULE E1k run "
            f"{companion.get('run')} above load {E1K_LOAD}: hedge-on fallback "
            f"{companion['fallbacks']}/{companion['rows']}, rows held with one call silent "
            f"{companion.get('held_one_silent')} ({companion.get('source')})"
        )
    if record:
        record.write_text("".join(json.dumps(r, sort_keys=True) + "\n" for r in rows))
        record.chmod(0o600)
    notes.append(
        f"thresholds are assumed inputs until calibration (§6.6): set ≥ {MIN_SET}, recall ≥ {MIN_RECALL}, "
        f"other (relay decision) ≥ {MIN_OTHER_CORRECT}, fallback ≤ {MAX_FALLBACK}"
    )
    return {"fails": fails, "notes": notes}


def main(argv: Optional[List[str]] = None) -> int:
    ap = argparse.ArgumentParser(prog="heldout.py")
    ap.add_argument(
        "--set",
        choices=SETS,
        help="which sealed set; omitted: seal means v1, every other verb the newest sealed set",
    )
    sub = ap.add_subparsers(dest="verb", required=True)
    p = sub.add_parser("seal")
    p.add_argument("--candidates", required=True)
    p.add_argument("--tuning-out", required=True)
    p.add_argument("--min-sealed", type=int, default=MIN_SET)
    p.add_argument("--fraction", type=float, default=0.5)
    p.add_argument(
        "--exclude",
        action="append",
        help="a JSONL of {prompt} rows already used (an earlier tuning set); never sealed again",
    )
    p.add_argument(
        "--dry-run",
        action="store_true",
        help="print the per-stratum counts the split would seal (never a prompt) and write nothing",
    )
    p.add_argument(
        "--strata", help="seal only these strata (comma-separated); the set stores them"
    )
    p.add_argument(
        "--take", help="STRATUM=N|all,...: keep N of a stratum's sealed side"
    )
    p = sub.add_parser("draw")
    p.add_argument("--candidates", required=True)
    p.add_argument("--strata", required=True)
    p.add_argument(
        "--take", help="STRATUM=N|all,...; a stratum it does not name is drawn whole"
    )
    p.add_argument("--exclude", action="append")
    p.add_argument("--out", required=True)
    p = sub.add_parser("retire")
    p.add_argument("--out", required=True)
    p = sub.add_parser("instrument")
    p.add_argument(
        "--await",
        dest="await_",
        help="STRATUM[,STRATUM]: unpin these so they wait for a fresh set; opens no sealed set",
    )
    p.add_argument(
        "--pin", help="STRATUM=SET for each of the four strata, comma-separated"
    )
    p = sub.add_parser("reads")
    p.add_argument(
        "--before-ledger", help="SET=COUNT,...: reads made before the ledger existed"
    )
    p = sub.add_parser("rater-sheet")
    p.add_argument("--out", required=True)
    p = sub.add_parser("label")
    p.add_argument("--rater", required=True)
    p.add_argument("--labels", required=True)
    sub.add_parser("status")
    p = sub.add_parser("real-load")
    p.add_argument("--run", type=int)
    p.add_argument("--source", help="the run's own report")
    p.add_argument("--rows", type=int, help="hedge-on rows above load 150")
    p.add_argument("--fallbacks", type=int, help="hedge-on fallbacks among them")
    p.add_argument("--held", type=int, help="hedge-on rows held with one call silent")
    p = sub.add_parser("evaluate")
    p.add_argument(
        "--consent-sealed-read",
        action="store_true",
        help="spend a read of the sealed set(s); without it evaluate decrypts and logs nothing",
    )
    p.add_argument("--program", help="the program whose third-read signatures count")
    p.add_argument(
        "--record",
        help="write one row per routed item {id, set, stratum, counted, got, wall_s, load1} to this file",
    )
    a = ap.parse_args(argv)
    try:
        if a.verb == "seal":
            return cmd_seal(a)
        if a.verb == "draw":
            return cmd_draw(a)
        if a.verb == "retire":
            return cmd_retire(a)
        if a.verb == "real-load":
            return cmd_real_load(a)
        if a.verb == "instrument":
            return cmd_instrument(a)
        if a.verb == "reads":
            return cmd_reads(a)
        if a.verb == "rater-sheet":
            return cmd_rater_sheet(a)
        if a.verb == "label":
            return cmd_label(a)
        if a.verb == "status":
            name = check_set(a.set or current_set())
            print(json.dumps(counts(load(name)), sort_keys=True))
            print(f"heldout.py: set {name}", file=sys.stderr)
            return 0
        res = evaluate(
            os.environ.get("CC_RESEARCH_ROUTER"),
            a.set,
            Path(a.record) if a.record else None,
            consent=a.consent_sealed_read,
            program=a.program,
        )
        print("\n".join(res["fails"] + res["notes"]))
        return 1 if res["fails"] else 0
    except kit.KitError as e:
        print(f"heldout.py: {e}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
