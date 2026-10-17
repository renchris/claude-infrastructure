"""frame_delta.py — `intake.py delta-apply`, the writer of a frame-delta cycle's rows (REPORT.md §5.4
step 1: "You add the missing rows and re-sign the frame as its next version"; RECORDS.md "Frame
deltas").

Before it, nothing sanctioned wrote a frame's ROWS: `intake.py set` writes scalars and
`known_rows_applied`, and the only other writer, a program's own generator, rewrites the records
whole. A delta file names its changes as ops, this module checks every one against the records
and gate row 1, and the apply writes them, bumps the frame's version and appends the delta, with
every row it replaced, to `frame-deltas.jsonl`. It never signs: the operator's re-sign of the new
frame is what makes the delta binding (gate.delta_signature).

The delta file (JSON):

  {"program": "<slug>", "base_version": <the frame's version now>,
   "known_rows": ["KR-n", ...],          held frame-omission rows the delta carries (required)
   "why": "<one line>",
   "frame": {"<list>": [op, ...], ...},  list one of FRAME_LISTS, or a scalar of FRAME_SCALARS
   "acceptance": [op, ...]}              rows of acceptance.json, keyed by id

  frame op       {"op": "add", "value": V}              V's id must be new to the list
                 {"op": "replace", "id": X, "value": V} X must exist; V keeps id X
  deliverable    {"op": "set", "value": "<sentence>"}   the frame's one-sentence deliverable
  locks          {"op": "add"|"replace", "id": NAME, "value": {"path", "sha256", ...}}
                                                        a hash the signed frame carries (frame.locks)
  acceptance op  {"op": "add", "row": {...}}            id new; ACCEPTANCE_REQUIRED present
                 {"op": "replace", "id": X, "fields": {...}}  merged over row X; id unchanged

An item's id: a bare-id string (`AM-18`, `DR-13a`, `E-01`) is its own id; a string opening with an id
token (`P2 the 157 build units`) has that token; any other string is its own id; an object has its
`id`, else `name`, else `what`. `am`, `dr` and `sources_required` hold bare ids, so they take adds
only: their rows' text lives in acceptance.json, decisions.jsonl and sources.jsonl.

Python 3.9-safe, standard library only.
"""

from __future__ import annotations

import copy
import dataclasses
import hashlib
import json
import re
import sys
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional, Tuple

import kit

# The frame's row lists, the only keys of frame.json a delta may touch. Every other key (rulings,
# fac_map, reask_map, reviewer pins, the contract page's hash, version, known_rows_applied) is the
# kit's or the operator's, and a delta naming one is refused.
FRAME_LISTS = (
    "am",
    "dr",
    "populations",
    "components",
    "exclusions",
    "sources_required",
)
BARE_ID_LISTS = ("am", "dr", "sources_required")
# The frame's scalars a delta may write: the deliverable sentence (a count in it can be what a held
# row corrects) and `locks`, the hashes the signed frame must carry (a locked rule's sha256). Each is
# signed with frame.json, so it changes only through a delta and the operator's re-sign.
FRAME_SCALARS = ("deliverable", "locks")
SHA256_HEX = re.compile(r"^[0-9a-f]{64}$")
DELTA_KEYS = ("program", "base_version", "known_rows", "why", "frame", "acceptance")
# gate row 1 fails a row missing any of the last three (gate_rows_a.row1); predicate is what it lints
ACCEPTANCE_REQUIRED = ("id", "predicate", "check_cmd", "threshold", "negative_branch")
# Registry states where a held frame omission exists: hold-g runs only in certification rounds, and
# the cycle runs after the certificate (§5.4). Elsewhere only an open frame-delta activity (triage's
# frame-defect bucket) lets a delta through.
DELTA_STATES = ("certifying", "certified")
# gate row 1's frame lint over a Ctx (intake.lint_fails), handed in so this module never imports intake
Lint = Callable[[Any], List[str]]
ID_TOKEN = re.compile(r"^[A-Z][A-Z0-9]*-?[0-9]+[a-z]?$")


class Refused(kit.KitError):
    pass


def item_id(v: Any) -> Optional[str]:
    if isinstance(v, dict):
        for k in ("id", "name", "what"):
            if v.get(k):
                return str(v[k])
        return None
    if isinstance(v, str) and v.strip():
        tok = v.split(None, 1)[0]
        return tok if ID_TOKEN.match(tok) else v
    return None


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def git_blob(data: bytes) -> str:
    """git's blob id for these bytes: the form operator_sign pins a signed frame in."""
    return hashlib.sha1(b"blob %d\0" % len(data) + data).hexdigest()


def dump_like(obj: Any, original: Optional[str]) -> str:
    """obj serialised the way the file already is, so an apply's diff is its rows and not a
    re-format (truememory-2-0's acceptance.json is indent 1, unsorted, raw UTF-8); a file in no form
    tried here, or a new one, takes kit.write_json_atomic's indent 2, sorted keys."""
    if original is not None:
        old = json.loads(original)
        for indent in (2, 1, 4):
            for sort in (True, False):
                for ascii_ in (True, False):
                    form = dict(indent=indent, sort_keys=sort, ensure_ascii=ascii_)
                    if json.dumps(old, **form) + "\n" == original:
                        return json.dumps(obj, **form) + "\n"
    return json.dumps(obj, indent=2, sort_keys=True) + "\n"


def write_text_atomic(path: Path, text: str) -> None:
    import os
    import tempfile

    fd, tmp = tempfile.mkstemp(dir=str(path.parent), prefix=f".{path.name}.")
    with os.fdopen(fd, "w") as fh:
        fh.write(text)
    os.replace(tmp, path)


def load_delta(path: str) -> Tuple[Dict[str, Any], bytes]:
    p = Path(path)
    if not p.is_file():
        raise Refused(f"--file {path!r} is not a file")
    raw = p.read_bytes()
    try:
        d = json.loads(raw)
    except ValueError as e:
        raise Refused(f"--file {path}: not JSON ({e})")
    if not isinstance(d, dict):
        raise Refused(f"--file {path}: the delta is a JSON object")
    stray = sorted(set(d) - set(DELTA_KEYS))
    if stray:
        raise Refused(
            f"the delta carries {', '.join(stray)}: only {', '.join(DELTA_KEYS)} are a delta's"
        )
    return d, raw


def window(slug: str, what: str = "a frame delta applies") -> Tuple[str, Optional[str]]:
    """(registry state, open frame-delta activity id or None) inside the frame-delta window, or
    Refused. `decision annotate` shares it: an annotation is carried by the next delta's pin."""
    import activities

    state = str((kit.registry_get(slug) or {}).get("state"))
    acts = activities.open_ids(slug, "frame-delta")
    act = acts[0] if acts else None
    if state not in DELTA_STATES and not act:
        raise Refused(
            f"{slug} is {state}: {what} while the program is "
            f"{' or '.join(DELTA_STATES)} (a held frame omission's cycle, §5.4), or under an open "
            "frame-delta activity (cc-research triage, frame-defect)"
        )
    return state, act


def authorize(slug: str, known: List[str]) -> Tuple[str, Optional[str]]:
    """(registry state, open frame-delta activity id or None), or Refused."""
    state, act = window(slug)
    if not known and not act:
        raise Refused(
            "known_rows is empty: name the held frame-omission rows the delta carries (§5.4 step 1); "
            "only an open frame-delta activity applies a delta that carries none"
        )
    return state, act


def check_known_rows(slug: str, ids: List[str]) -> None:
    rows = {str(r.get("id")): r for r in kit.known_rows(slug)}
    for kid in ids:
        r = rows.get(kid) or {}
        if r.get("kind") != "frame-omission" or r.get("status", "open") != "open":
            raise Refused(f"{kid} is not an open frame-omission known row")


def add_known_rows(fr: Dict[str, Any], ids: List[str]) -> None:
    applied = list(fr.get("known_rows_applied") or [])
    for kid in ids:
        if kid not in applied:
            applied.append(kid)
    fr["known_rows_applied"] = applied


def apply_frame_ops(
    fr: Dict[str, Any], frame_ops: Any
) -> Tuple[List[Dict[str, Any]], List[str]]:
    """Apply the frame ops to fr in place: (op records with before/after, ids added to am and dr)."""
    if not isinstance(frame_ops, dict):
        raise Refused("the delta's frame is an object of row lists")
    stray = sorted(set(frame_ops) - set(FRAME_LISTS) - set(FRAME_SCALARS))
    if stray:
        raise Refused(
            f"the delta's frame names {', '.join(stray)}: a delta edits the row lists "
            f"{', '.join(FRAME_LISTS)} and the scalars {', '.join(FRAME_SCALARS)} only; rulings, "
            "maps, pins, the contract page and signatures are not a delta's"
        )
    done: List[Dict[str, Any]] = apply_scalar_ops(fr, frame_ops)
    for name in FRAME_LISTS:
        ops = frame_ops.get(name)
        if ops is None:
            continue
        if not isinstance(ops, list) or not ops:
            raise Refused(f"frame.{name}: a non-empty list of ops")
        cur = list(fr.get(name) or [])
        for n, op in enumerate(ops, 1):
            where = f"frame.{name} op {n}"
            kind = op.get("op") if isinstance(op, dict) else None
            ids = [item_id(x) for x in cur]
            if kind == "add":
                v = op.get("value")
                vid = item_id(v)
                if vid is None:
                    raise Refused(f"{where}: add needs a value with an id")
                if name in BARE_ID_LISTS and not (
                    isinstance(v, str) and ID_TOKEN.match(v)
                ):
                    raise Refused(
                        f"{where}: {name} holds bare row ids; {v!r} is not one"
                    )
                if vid in ids:
                    raise Refused(f"{where}: {vid} is already in frame.{name}")
                cur.append(v)
                done.append(dict(list=name, op="add", id=vid, before=None, after=v))
            elif kind == "replace":
                if name in BARE_ID_LISTS:
                    raise Refused(
                        f"{where}: {name} holds bare ids, so there is no text to replace; "
                        + (
                            "rewrite the row in the delta's acceptance ops"
                            if name == "am"
                            else "its record has its own writer"
                        )
                    )
                xid, v = op.get("id"), op.get("value")
                if xid not in ids:
                    raise Refused(f"{where}: {xid!r} is not in frame.{name}")
                if item_id(v) != xid:
                    raise Refused(
                        f"{where}: the new value's id is {item_id(v)!r}, not {xid!r}; a replace "
                        "rewrites a row and keeps its id"
                    )
                i = ids.index(xid)
                if cur[i] == v:
                    raise Refused(f"{where}: the new value of {xid} equals the old one")
                done.append(
                    dict(list=name, op="replace", id=xid, before=cur[i], after=v)
                )
                cur[i] = v
            else:
                raise Refused(f"{where}: op is add or replace, got {kind!r}")
        fr[name] = cur
    added = [d["id"] for d in done if d["op"] == "add" and d["list"] in ("am", "dr")]
    return done, added


def apply_scalar_ops(
    fr: Dict[str, Any], frame_ops: Dict[str, Any]
) -> List[Dict[str, Any]]:
    """The deliverable and locks ops, applied to fr in place: their op records with before/after."""
    done: List[Dict[str, Any]] = []
    for name in FRAME_SCALARS:
        ops = frame_ops.get(name)
        if ops is None:
            continue
        if not isinstance(ops, list) or not ops:
            raise Refused(f"frame.{name}: a non-empty list of ops")
        for n, op in enumerate(ops, 1):
            where = f"frame.{name} op {n}"
            kind = op.get("op") if isinstance(op, dict) else None
            v = op.get("value") if isinstance(op, dict) else None
            if name == "deliverable":
                if kind != "set":
                    raise Refused(
                        f"{where}: the deliverable takes op set, got {kind!r}"
                    )
                if not isinstance(v, str) or not v.strip():
                    raise Refused(f"{where}: the deliverable is a non-empty sentence")
                if fr.get(name) == v:
                    raise Refused(f"{where}: the new deliverable equals the old one")
                done.append(
                    dict(list=name, op="set", id=name, before=fr.get(name), after=v)
                )
                fr[name] = v
                continue
            locks = dict(fr.get("locks") or {})
            xid = op.get("id") if isinstance(op, dict) else None
            if not isinstance(xid, str) or not xid.strip():
                raise Refused(f"{where}: a lock op names its lock by id")
            if not isinstance(v, dict) or not str(v.get("path") or "").strip():
                raise Refused(f"{where}: a lock is an object with a path and a sha256")
            if not SHA256_HEX.match(str(v.get("sha256") or "")):
                raise Refused(
                    f"{where}: {xid}'s sha256 is not 64 lowercase hex digits; a lock carries the hash"
                )
            if kind == "add":
                if xid in locks:
                    raise Refused(f"{where}: {xid} is already in frame.locks")
            elif kind == "replace":
                if xid not in locks:
                    raise Refused(f"{where}: {xid!r} is not in frame.locks")
                if locks[xid] == v:
                    raise Refused(f"{where}: the new value of {xid} equals the old one")
            else:
                raise Refused(f"{where}: op is add or replace, got {kind!r}")
            done.append(
                dict(list=name, op=kind, id=xid, before=locks.get(xid), after=v)
            )
            locks[xid] = v
            fr["locks"] = locks
    return done


def annotations(decisions: List[Dict[str, Any]]) -> List[str]:
    """Every `decision annotate` event's id (DA-n), in file order."""
    return [str(e["annotation"]) for e in decisions if e.get("annotation")]


def pinned_annotations(fr: Dict[str, Any]) -> List[str]:
    return [a for p in fr.get("frame_deltas") or [] for a in p.get("annotations") or []]


def decisions_pin(rec: Path, fr: Dict[str, Any]) -> Dict[str, Any]:
    """The new frame's pin on decisions.jsonl: the sha256 of its bytes now, how many there are, and
    the annotation events no earlier delta pinned. The frame signature pins frame.json alone, so this
    is what puts a decision's annotated text under the operator's re-sign (RECORDS.md "Decision
    annotations"); the byte count lets gate row 1 re-hash the prefix as the log grows."""
    path = rec / "decisions.jsonl"
    data = path.read_bytes() if path.is_file() else b""
    old = set(pinned_annotations(fr))
    return {
        "decisions_sha256": sha256(data),
        "decisions_bytes": len(data),
        "annotations": [a for a in annotations(kit.read_jsonl(path)) if a not in old],
    }


def pin_fails(rec: Path, fr: Dict[str, Any]) -> List[str]:
    """Gate row 1's decisions-pin lint: an annotation event no delta pinned (its text shows in the
    frame's render but is under no re-sign), and a pinned prefix of decisions.jsonl that no longer
    hashes as pinned (an append-only log rewritten under the frame)."""
    path = rec / "decisions.jsonl"
    data = path.read_bytes() if path.is_file() else b""
    fails: List[str] = []
    for p in fr.get("frame_deltas") or []:
        if "decisions_sha256" not in p:
            continue
        n = int(p.get("decisions_bytes") or 0)
        if len(data) < n or sha256(data[:n]) != p["decisions_sha256"]:
            fails.append(
                f"decisions.jsonl no longer holds the {n} bytes {p.get('id')} pinned: the log was "
                "rewritten under the frame, and an append-only record is never rewritten"
            )
    pinned = set(pinned_annotations(fr))
    loose = [a for a in annotations(kit.read_jsonl(path)) if a not in pinned]
    if loose:
        fails.append(
            f"decision annotation(s) {', '.join(loose)} carried by no frame delta: apply a delta "
            "(intake.py delta-apply) so the operator's frame re-sign covers their text"
        )
    return fails


def apply_acceptance_ops(acc: Dict[str, Any], acc_ops: Any) -> List[Dict[str, Any]]:
    if not isinstance(acc_ops, list) or not acc_ops:
        raise Refused("the delta's acceptance is a non-empty list of ops")
    rows = acc.setdefault("rows", [])
    done: List[Dict[str, Any]] = []
    for n, op in enumerate(acc_ops, 1):
        where = f"acceptance op {n}"
        kind = op.get("op") if isinstance(op, dict) else None
        ids = [r.get("id") for r in rows]
        if kind == "add":
            row = op.get("row")
            if not isinstance(row, dict):
                raise Refused(f"{where}: add needs a row object")
            miss = [k for k in ACCEPTANCE_REQUIRED if not row.get(k)]
            if miss:
                raise Refused(f"{where}: the row lacks {', '.join(miss)}")
            if not ID_TOKEN.match(str(row["id"])):
                raise Refused(f"{where}: {row['id']!r} is not a row id")
            if row["id"] in ids:
                raise Refused(f"{where}: {row['id']} is already in acceptance.json")
            rows.append(row)
            done.append(
                dict(list="acceptance", op="add", id=row["id"], before=None, after=row)
            )
        elif kind == "replace":
            xid, fields = op.get("id"), op.get("fields")
            if xid not in ids:
                raise Refused(f"{where}: {xid!r} is not in acceptance.json")
            if not isinstance(fields, dict) or not fields:
                raise Refused(f"{where}: replace needs a non-empty fields object")
            if "id" in fields:
                raise Refused(f"{where}: a replace keeps the row's id")
            i = ids.index(xid)
            new = dict(rows[i], **fields)
            if new == rows[i]:
                raise Refused(f"{where}: the fields change nothing in {xid}")
            done.append(
                dict(list="acceptance", op="replace", id=xid, before=rows[i], after=new)
            )
            rows[i] = new
        else:
            raise Refused(f"{where}: op is add or replace, got {kind!r}")
    return done


def lint_new(
    slug: str, frame: Dict[str, Any], acc: Optional[Dict[str, Any]], lint: Lint
) -> List[str]:
    """Gate row 1's frame lint (`lint`, intake.lint_fails) failures the proposed records have and
    the records on disk do not: the delta may not make the frame worse than it found it."""
    from gate import Ctx, make_ctx

    @dataclasses.dataclass
    class Proposed(Ctx):
        overlay: Dict[str, Any] = dataclasses.field(default_factory=dict)

        def json(self, rel: str, default: Any = None) -> Any:
            if rel in self.overlay:
                return copy.deepcopy(self.overlay[rel])
            return super().json(rel, default)

    now = make_ctx(slug)
    overlay: Dict[str, Any] = {"frame.json": frame}
    if acc is not None:
        overlay["acceptance.json"] = acc
    before = set(lint(now))
    after = lint(
        Proposed(
            slug=now.slug, records=now.records, sealed=now.sealed, overlay=overlay
        ),
    )
    return [e for e in after if e not in before]


def plan(slug: str, path: str, lint: Lint) -> Dict[str, Any]:
    """Every check, nothing written: the new frame and acceptance text, the delta record, warnings."""
    d, raw = load_delta(path)
    rec = kit.records_dir(slug)
    fr_path, acc_path = rec / "frame.json", rec / "acceptance.json"
    if not fr_path.is_file():
        raise Refused(f"no frame.json for {slug}")
    fr_text = fr_path.read_text()
    fr = json.loads(fr_text)
    if d.get("program") != slug:
        raise Refused(f"the delta is for {d.get('program')!r}, not {slug}")
    if d.get("base_version") != fr.get("version"):
        raise Refused(
            f"the delta was drafted against frame v{d.get('base_version')}; the frame is "
            f"v{fr.get('version')}: re-draft it against the frame as it stands"
        )
    known = d.get("known_rows")
    if not isinstance(known, list) or not all(isinstance(k, str) for k in known):
        raise Refused(
            "the delta needs known_rows, a list of known-row ids (may be [] only "
            "under an open frame-delta activity)"
        )
    if not str(d.get("why") or "").strip():
        raise Refused("the delta needs a one-line why")
    dpin = decisions_pin(rec, fr)
    if (
        d.get("frame") is None
        and d.get("acceptance") is None
        and not dpin["annotations"]
    ):
        raise Refused(
            "the delta has no ops: give frame, acceptance or both (a delta with neither only pins "
            "pending decision annotations, and there are none)"
        )
    state, act = authorize(slug, known)
    check_known_rows(slug, known)

    new = copy.deepcopy(fr)
    ops, added = (
        apply_frame_ops(new, d["frame"]) if d.get("frame") is not None else ([], [])
    )
    acc_text = acc_path.read_text() if acc_path.is_file() else None
    acc_new: Optional[Dict[str, Any]] = None
    if d.get("acceptance") is not None:
        acc_new = json.loads(acc_text) if acc_text else {"rows": []}
        ops += apply_acceptance_ops(acc_new, d["acceptance"])
    acc_rows = {
        r.get("id")
        for r in (
            (acc_new if acc_new is not None else kit.read_json(acc_path, {})) or {}
        ).get("rows")
        or []
    }
    decisions = kit.fold(kit.read_jsonl(rec / "decisions.jsonl"))
    for o in ops:
        if o["op"] != "add":
            continue
        if o["list"] == "am" and o["id"] not in acc_rows:
            raise Refused(
                f"frame.am adds {o['id']}, which acceptance.json does not hold: add its row in the "
                "delta's acceptance ops"
            )
        if o["list"] == "dr" and o["id"] not in decisions:
            raise Refused(
                f"frame.dr adds {o['id']}, which decisions.jsonl does not hold; a decision is "
                "recorded by its own verbs (cc-research decision), never by a delta"
            )
        if o["list"] == "acceptance" and "am" in new and o["id"] not in new["am"]:
            raise Refused(
                f"acceptance adds {o['id']} but frame.am does not name it, so the frame signature "
                "would not cover it: add it to frame.am in the same delta"
            )
    warnings: List[str] = []
    sources = kit.fold(kit.read_jsonl(rec / "sources.jsonl"))
    for o in ops:
        if (
            o["list"] == "populations"
            and not (rec / "census" / f"{o['after']}.json").is_file()
        ):
            warnings.append(
                f"census/{o['after']}.json does not exist: gate row 2 fails until the delta's "
                "census runs (§5.4 step 2)"
            )
        if o["list"] == "sources_required" and o["id"] not in sources:
            warnings.append(
                f"sources.jsonl holds no {o['id']} yet (gate row 3 reads it)"
            )

    new["version"] = int(fr.get("version") or 0) + 1
    add_known_rows(new, known)
    fd_id = f"FD-{len(kit.read_jsonl(rec / 'frame-deltas.jsonl')) + 1}"
    acc_out = dump_like(acc_new, acc_text) if acc_new is not None else None
    # The frame signature pins frame.json alone, so the new frame carries the delta's hash and the
    # rewritten acceptance.json's: the operator's re-sign then pins the row text as well.
    new.setdefault("frame_deltas", []).append(
        {
            "id": fd_id,
            "version": new["version"],
            "sha256": sha256(raw),
            "acceptance_sha256": sha256(acc_out.encode()) if acc_out else None,
            **dpin,
        }
    )
    fails = lint_new(slug, new, acc_new, lint)
    if fails:
        raise Refused(
            "the delta leaves gate row 1 failing where it passed: " + "; ".join(fails)
        )
    lists = sorted({o["list"] for o in ops})
    frame_text = dump_like(new, fr_text)
    record = {
        "id": fd_id,
        "program": slug,
        "file": str(Path(path).resolve()),
        "sha256": sha256(raw),
        # the frame.json this apply writes: while it still hashes to this, the delta is the frame's
        # newest change (gate.sh accept --action frame, REPORT.md §14)
        "frame_sha256": sha256(frame_text.encode()),
        # the frame it applied ON, as a git blob id (the pin a frame signature records), so an
        # acceptance can require that base to be the frame last signed or accepted
        "base_frame_blob": git_blob(fr_path.read_bytes()),
        # acceptance.json as this apply leaves it: the rows the frame's checks run
        "acceptance_after_sha256": (
            sha256(acc_out.encode())
            if acc_out is not None
            else (sha256(acc_text.encode()) if acc_text is not None else None)
        ),
        "base_version": fr.get("version"),
        "version": new["version"],
        "known_rows": known,
        "why": d["why"],
        "registry_state": state,
        "activity": act,
        "ops": ops,
        "rows_before": {n: _ids(fr, acc_text, n) for n in lists},
        "rows_after": {n: _ids(new, acc_out, n) for n in lists},
        **dpin,
        "delta": d,
        "by": kit.lease_owner(),
        "at": kit.now_iso(),
    }
    return {
        "record": record,
        "frame_text": frame_text,
        "frame_old": fr_text,
        "acc_text": acc_out,
        "acc_old": acc_text,
        "warnings": warnings,
    }


def _ids(fr: Dict[str, Any], acc_text: Optional[str], name: str) -> List[Optional[str]]:
    if name == "deliverable":
        return [fr.get(name)]
    if name == "locks":
        return sorted(fr.get(name) or {})
    if name == "acceptance":
        return [
            r.get("id")
            for r in (json.loads(acc_text) if acc_text else {}).get("rows") or []
        ]
    return [item_id(x) for x in fr.get(name) or []]


def apply(slug: str, path: str, dry_run: bool, lint: Lint) -> int:
    import difflib

    if not dry_run:
        kit.lease_check(slug)
    p = plan(slug, path, lint)
    rec = kit.records_dir(slug)
    r = p["record"]
    if dry_run:
        for name, old, new in (
            ("frame.json", p["frame_old"], p["frame_text"]),
            ("acceptance.json", p["acc_old"], p["acc_text"]),
        ):
            if new is None:
                continue
            print(
                "".join(
                    difflib.unified_diff(
                        (old or "").splitlines(True),
                        new.splitlines(True),
                        f"a/{name}",
                        f"b/{name}",
                    )
                ),
                end="",
            )
    else:
        if p["acc_text"] is not None:
            write_text_atomic(rec / "acceptance.json", p["acc_text"])
        write_text_atomic(rec / "frame.json", p["frame_text"])
        kit.append_jsonl(rec / "frame-deltas.jsonl", r)
        kit.append_jsonl(
            rec / "intake.jsonl",
            dict(
                event="delta-apply",
                id=r["id"],
                version=r["version"],
                sha256=r["sha256"],
            ),
        )
    for w in p["warnings"]:
        print(f"WARNING {w}", file=sys.stderr)
    counts = ", ".join(
        [f"{o['op']} {o['list']} {o['id']}" for o in r["ops"]]
        + [f"pin {a}" for a in r["annotations"]]
    )
    print(
        f"{'DRY RUN, nothing written: ' if dry_run else ''}{r['id']} frame "
        f"v{r['base_version']} -> v{r['version']} ({counts}); known_rows_applied += "
        f"{', '.join(r['known_rows']) or 'none'}. The frame signature is "
        f"{'about to go' if dry_run else 'now'} STALE: the operator re-signs it "
        f"(cc-signoff research:{slug}/frame), or under a standing delegation an agent accepts it "
        f"(gate.sh accept --program {slug} --action frame), and only that spares and closes the rows"
    )
    return 0
