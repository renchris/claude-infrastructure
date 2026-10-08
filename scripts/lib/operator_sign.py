"""operator_sign.py — the operator-only signing library (REPORT.md §8 item 4).

Factored out of bin/cc-signoff, whose three protections it carries unchanged in meaning:

  ARM 1 — ANCESTRY. Walk our own parent chain with /bin/ps (absolute, so a `ps` stub earlier on
  PATH cannot fake the walk) and refuse if any ancestor's command names claude.
  ARM 2 — CONTENT PIN. A signature records the git blob sha of every artifact it covers; one
  changed byte makes the signature STALE, and a stale signature authorises nothing.
  ARM 3 — THE READER IS THE AUDITOR. A same-uid process can bypass arms 1 and 2 by writing a
  record by hand; claiming otherwise would be false. What is achievable is that a record written
  under an agent advertises itself: every record stores the ancestry chain that wrote it, and every
  reader classifies a record whose chain (or flag) shows a claude ancestor, or that carries no
  chain at all, as VOID. A void record authorises nothing, and readers print it as void by name.

Two namespaces use it. The customer mission rows (bin/cc-signoff <row-id>, bin/cc-mission render)
and the research namespace, `research:<slug>/<action>[/<target>]`, whose records are appended to
the program's sealed log `$CC_RESEARCH_HOME/<slug>/signoff.jsonl`:

  frame        pins docs/research/<slug>/frame.json            (§3.2 step 9, gate row 1)
  cert         pins the newest docs/research/<slug>/cert/CERT-v<n>.json   (§3.10 signoff)
  extra-round  the one extra round set per program              (§6.4; round.sh honours it)
  reopen       reopen certified scope, operator-caused, priced  (§5.1; gate.sh honours it)
  veto/<id>    veto an overrun or below-profile default on decision <id>  (§6.1; the sweep honours it)
  extend-decision/<id>  the one research extension on decision <id>   (§12.3; gate row 19 and the menu honour it)
  implementation  pins the newest docs/research/<slug>/built/BUILT-CERT-v<n>.json, by path and hash
               (§11, method v1.2: the implementation signoff; `gate.sh built-signed`, `close`,
               `requires` and `render` honour it). Signed only while the registry reads
               build-certified or implementation-signed.
  third-read/<set>.<stratum>  one read of a held-out stratum already read twice, as a disclosed
               cost (ruling 915d7fb98b7f item 5, wave E1l; `heldout.py evaluate` and gate row 15
               honour it, one signature per read beyond the second).

Python 3.9-safe, standard library only.
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path
from typing import Any, Dict, List, Optional

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "research-kit" / "lib"))
import kit  # noqa: E402

PS = "/bin/ps"
ACTIONS = (
    "frame",
    "cert",
    "extra-round",
    "reopen",
    "veto",
    "extend-decision",
    "implementation",
    "third-read",
)
# the actions that name a target: a decision id, or for third-read a held-out <set>.<stratum>
TARGETED = ("veto", "extend-decision", "third-read")
THIRD_READ_TARGET = re.compile(
    r"^v[0-9]+\.(regex-matched|regex-missed|pushback|other)$"
)
EVIDENCED = (
    "frame",
    "cert",
    "implementation",
)  # signatures over an artifact the operator read
VALID, VOID, STALE = "valid", "void", "stale"
# implementation_state()'s statuses, beyond the three verdicts' names
SIGNED, UNSIGNED, SUPERSEDED = "signed", "unsigned", "superseded"
IMPLEMENTATION_STATES = ("build-certified", "implementation-signed")


class Refused(Exception):
    """The signing call must not proceed. The message is printed to the operator verbatim.

    `code` is the exit status a CLI should use: 3 for an agent ancestor, 2 for any other refusal.
    """

    def __init__(self, message: str, code: int = 2) -> None:
        super().__init__(message)
        self.code = code


# ── arm 1: ancestry ─────────────────────────────────────────────────────────────────────────────


def ancestry(pid: Optional[int] = None) -> List[Dict[str, Any]]:
    """Walk pid -> ppid to init, recording each command."""
    chain: List[Dict[str, Any]] = []
    pid, depth = pid or os.getpid(), 0
    while pid and pid > 1 and depth < 24:
        try:
            out = subprocess.run(
                (PS, "-o", "ppid=,comm=", "-p", str(pid)),
                capture_output=True,
                text=True,
                timeout=5,
            )
        except (OSError, subprocess.SubprocessError):
            break
        line = out.stdout.strip()
        parts = line.split(None, 1)
        if len(parts) < 2:
            break
        chain.append({"pid": pid, "comm": parts[1], "depth": depth})
        pid, depth = int(parts[0]), depth + 1
    return chain


def claude_ancestor(chain: List[Any]) -> Optional[Dict[str, Any]]:
    """The first ancestor whose command names claude. Accepts dict entries or bare comm strings."""
    for i, c in enumerate(chain):
        comm = c.get("comm", "") if isinstance(c, dict) else str(c)
        if "claude" in comm.lower():
            return c if isinstance(c, dict) else {"comm": comm, "depth": i}
    return None


def refuse_if_agent(chain: List[Any], operator_cmd: str) -> None:
    hit = claude_ancestor(chain)
    if hit:
        raise Refused(
            f"REFUSED — this signing tool is descended from a claude process "
            f"({hit['comm']} at depth {hit.get('depth', '?')}).\n"
            "A signature is the operator's, made in his own terminal after looking at the\n"
            "artifact. An agent may prepare it and stop there.\n\n"
            f"  Operator, to sign this:  {operator_cmd}",
            code=3,
        )


# ── arm 2: content pins ─────────────────────────────────────────────────────────────────────────


def blob_sha(data: bytes) -> str:
    """git's blob id for these bytes, so a pin equals `git rev-parse <rev>:<path>` once committed."""
    return hashlib.sha1(b"blob %d\0" % len(data) + data).hexdigest()


def file_pin(path: Path) -> Optional[str]:
    path = Path(path)
    return blob_sha(path.read_bytes()) if path.is_file() else None


# ── arm 3: verdicts ─────────────────────────────────────────────────────────────────────────────


def verdict(
    rec: Dict[str, Any], pins_now: Optional[Dict[str, Optional[str]]] = None
) -> str:
    """VOID if written under an agent or with no chain; STALE if a pinned artifact changed; else VALID.

    `pins_now` maps each pinned path to its current pin (None if the file is gone). Paths a
    record pins but `pins_now` omits are not re-checked; pass every one the caller can resolve.
    """
    prov = rec.get("provenance") or {}
    chain = prov.get("chain")
    if prov.get("claude_ancestor") or not chain or claude_ancestor(chain):
        return VOID
    for p, sha in (rec.get("pins") or {}).items():
        if pins_now is not None and p in pins_now and pins_now[p] != sha:
            return STALE
    return VALID


# ── the research namespace ──────────────────────────────────────────────────────────────────────

ROW_RE = re.compile(
    r"^research:([a-z0-9][a-z0-9-]{0,63})/"
    r"(frame|cert|extra-round|reopen|veto|extend-decision|implementation|third-read)"
    r"(?:/([A-Za-z0-9._-]+))?$"
)


def parse_row(row: str) -> Optional[Dict[str, Optional[str]]]:
    """'research:<slug>/<action>[/<target>]' -> {slug, action, target}; None if not that namespace."""
    m = ROW_RE.match(row or "")
    if not m:
        return None
    slug, action, target = m.group(1), m.group(2), m.group(3)
    if (action in TARGETED) != (target is not None):
        return None  # veto, extend-decision and third-read need a target; nothing else takes one
    return {"slug": slug, "action": action, "target": target}


def research_log(slug: str) -> Path:
    return kit.sealed_dir(slug) / "signoff.jsonl"


def pin_targets(slug: str, action: str) -> Dict[str, Path]:
    """Which artifacts a research action pins, keyed by records-relative path."""
    rec = kit.records_dir(slug)
    if action == "frame":
        return {"frame.json": rec / "frame.json"}
    if action == "cert":
        certs = sorted(
            (rec / "cert").glob("CERT-v*.json"),
            key=lambda p: int(re.sub(r"\D", "", p.stem) or 0),
        )
        return {f"cert/{certs[-1].name}": certs[-1]} if certs else {}
    if action == "implementation":
        newest = newest_built_cert(slug)
        return {f"built/{newest.name}": newest} if newest else {}
    return {}


def newest_built_cert(slug: str) -> Optional[Path]:
    """The newest built certificate (REPORT.md §11) of the program, or None."""
    certs = sorted(
        (kit.records_dir(slug) / "built").glob("BUILT-CERT-v*.json"),
        key=lambda p: int(re.sub(r"\D", "", p.stem) or 0),
    )
    return certs[-1] if certs else None


def current_pins(slug: str, rec: Dict[str, Any]) -> Dict[str, Optional[str]]:
    base = kit.records_dir(slug)
    return {p: file_pin(base / p) for p in (rec.get("pins") or {})}


def sign_research(
    row: str,
    evidence: Optional[str] = None,
    because: Optional[str] = None,
    chain: Optional[List[Dict[str, Any]]] = None,
) -> Dict[str, Any]:
    """Append one operator signature to the program's sealed log. Raises Refused on any refusal."""
    parsed = parse_row(row)
    if parsed is None:
        raise Refused(
            f"REFUSED — {row!r} is not research:<slug>/<{'|'.join(ACTIONS)}>[/<decision-id>]"
        )
    slug, action, target = parsed["slug"], parsed["action"], parsed["target"]
    chain = ancestry()
    refuse_if_agent(
        chain,
        f"cc-signoff {row} "
        + (
            "--evidence <what you read>" if action in EVIDENCED else '--because "<why>"'
        ),
    )
    if action in EVIDENCED and not evidence:
        raise Refused(
            "REFUSED — --evidence is required: the path or URL you actually read.\n"
            "A signature with no referent is a claim about nothing."
        )
    if action == "third-read" and not THIRD_READ_TARGET.match(target or ""):
        raise Refused(
            f"REFUSED — {target!r} is not a held-out <set>.<stratum> (e.g. v3.regex-missed): a "
            "third read is signed for one stratum of one set."
        )
    if (
        action in ("extra-round", "reopen", "veto", "extend-decision", "third-read")
        and not because
    ):
        raise Refused(
            f'REFUSED — {action} needs --because "<why>"; it is logged as operator-caused and priced.'
        )
    if action == "implementation":
        state = (kit.registry_get(slug) or {}).get("state")
        if state not in IMPLEMENTATION_STATES:
            raise Refused(
                f"REFUSED — {slug} is {state or 'not registered'}, not build-certified: the built "
                "gate\nhas not certified the artifact this signature would accept "
                "(gate.sh built-run)."
            )
        if newest_built_cert(slug) is None:
            raise Refused(
                f"REFUSED — no built certificate exists under {kit.records_dir(slug) / 'built'} "
                "to pin."
            )
    pins: Dict[str, str] = {}
    for rel, path in pin_targets(slug, action).items():
        pin = file_pin(path)
        if pin is None:
            raise Refused(
                f"REFUSED — cannot pin {path}: it does not exist. Signing an unpinnable\n"
                "artifact would be a signature over nothing."
            )
        pins[rel] = pin
    if action in EVIDENCED and not pins:
        raise Refused(
            f"REFUSED — no {action} artifact exists under {kit.records_dir(slug)} to pin."
        )
    if action == "extra-round" and any(
        verdict(r) == VALID for r in research_records(slug, "extra-round")
    ):
        raise Refused(
            "REFUSED — the one extra round set per program (REPORT.md §6.4) is already bought."
        )
    if action == "extend-decision":
        known = kit.fold(kit.read_jsonl(kit.records_dir(slug) / "decisions.jsonl"))
        if target not in known:
            raise Refused(
                f"REFUSED — {target} is not a decision of {slug}: an extension is bought for "
                "one decision on record."
            )
        if any(
            verdict(r) == VALID
            for r in research_records(slug, "extend-decision", target)
        ):
            raise Refused(
                f"REFUSED — the one research extension per decision (REPORT.md §12.3) is "
                f"already bought for {target}."
            )
    now = time.time()
    rec = {
        "row": row,
        "program": slug,
        "action": action,
        "target": target,
        "at": now,
        "at_iso": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(now)),
        "evidence": evidence,
        "because": because,
        "pins": pins,
        "provenance": {
            "claude_ancestor": False,
            "chain": [c["comm"] if isinstance(c, dict) else str(c) for c in chain],
        },
    }
    log = research_log(slug)
    kit.sealed_dir(slug, create=True)
    with log.open("a") as fh:
        fh.write(json.dumps(rec, sort_keys=True) + "\n")
    return rec


def research_records(
    slug: str, action: Optional[str] = None, target: Optional[str] = None
) -> List[Dict[str, Any]]:
    """Every record in the program's log (optionally filtered), each with `_verdict` set."""
    out = []
    for rec in kit.read_jsonl(research_log(slug)):
        if action and rec.get("action") != action:
            continue
        if target is not None and rec.get("target") != target:
            continue
        rec["_verdict"] = verdict(rec, current_pins(slug, rec))
        out.append(rec)
    return out


def latest_valid(
    slug: str, action: str, target: Optional[str] = None
) -> Optional[Dict[str, Any]]:
    """The newest VALID record for this action/target, or None. Void and stale records never count."""
    valid = [
        r for r in research_records(slug, action, target) if r["_verdict"] == VALID
    ]
    return max(valid, key=lambda r: r.get("at", 0)) if valid else None


def implementation_state(slug: str) -> Dict[str, Any]:
    """Is the newest built certificate signed? {"status", "cert", "record"} (REPORT.md §11).

    signed      a VALID record pins the newest built certificate, unchanged since
    unsigned    no implementation record at all (or no built certificate)
    void        the newest record was written under an agent, or carries no chain
    stale       the newest record's pinned certificate changed after it was signed
    superseded  the newest record is sound but pins an older built certificate
    Only `signed` authorises anything; the other four are reasons, printed by name.
    """
    newest = newest_built_cert(slug)
    name = newest.stem if newest else None
    recs = research_records(slug, "implementation")
    if newest is not None:
        key = f"built/{newest.name}"
        hits = [
            r for r in recs if r["_verdict"] == VALID and key in (r.get("pins") or {})
        ]
        if hits:
            return {
                "status": SIGNED,
                "cert": name,
                "record": max(hits, key=lambda r: r.get("at", 0)),
            }
    if not recs:
        return {"status": UNSIGNED, "cert": name, "record": None}
    last = max(recs, key=lambda r: r.get("at", 0))
    status = last["_verdict"] if last["_verdict"] in (VOID, STALE) else SUPERSEDED
    return {"status": status, "cert": name, "record": last}


def implementation_words(slug: str, state: Optional[Dict[str, Any]] = None) -> str:
    """One clause for a reader: the signature state of the newest built certificate, by name."""
    st = state or implementation_state(slug)
    rec = st["record"] or {}
    if st["status"] == SIGNED:
        return f"signed by the operator {rec.get('at_iso') or 'at an unrecorded time'}"
    if st["status"] == VOID:
        return "signature VOID (agent-written): not signed"
    if st["status"] == STALE:
        return "signature STALE (the built certificate changed after it): not signed"
    if st["status"] == SUPERSEDED:
        old = (
            ", ".join(Path(p).stem for p in sorted(rec.get("pins") or {}))
            or "no certificate"
        )
        return f"not signed (the signature on file covers {old})"
    return "not signed"
