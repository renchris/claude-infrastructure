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
  profile/<name>  move a certifying program's remaining rounds to a narrower profile, between two
               certification rounds, once per program (kit.profile_switch; round.sh, estimate.py
               and gate row 16 honour it). The record carries `from` and `after_round`; frame.json,
               the signed stage budgets, the ceiling and the seeds are untouched.
  adopt/stage9  method v1.3 (REPORT.md §13.3): a program whose frame predates method 1.2 runs Stage
               9 (built-freeze, built-run, the implementation signature) without editing frame.json,
               which would void the frame signature. Rows 18 and 19 stay 1.2-only. Once per program.

DELEGATED ACCEPTANCE (REPORT.md §14, ruled 2026-10-16: "I WILL NOT look at any of the contenet for said
sign off"). The operator signs ONE standing delegation, `research:<slug|*>/delegate --because "<words>"`
(`*` covers every program), and may end it with `research:<slug|*>/revoke-delegation`; both are
operator signatures under the three arms above, appended to `$CC_RESEARCH_HOME/delegations.jsonl`.
While one is in force, an agent's `gate.sh accept` (scripts/research-kit/lib/gate_accept.py) writes an
acceptance of a DELEGABLE action to the program's `$CC_RESEARCH_HOME/<slug>/delegated.jsonl`, a log
apart from signoff.jsonl, only when that action's machine criteria (DELEGATED_CRITERIA) all hold.
`research_records` returns those acceptances beside the signatures, `_delegated` set and their
verdict computed by `acceptance_verdict`, so every reader that honours a signature honours an
acceptance exactly there, and prints it as DELEGATED_WORDS. An acceptance is VOID unless the
delegation it names is an operator signature still byte-identical to what was signed, covers the
program, and was in force at the acceptance's time (the newest of a delegation and a revoke covering
the program wins); third reads and vetoes are never delegable, so an acceptance of one is VOID.

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
from typing import Any, Dict, List, Optional, Tuple

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
    "profile",
    "adopt",
)
# the actions that name a target: a decision id, for third-read a held-out <set>.<stratum>, for
# profile the profile's name, for adopt the adopted part of a later method
TARGETED = ("veto", "extend-decision", "third-read", "profile", "adopt")
ADOPT_TARGETS = ("stage9",)  # method v1.3 (REPORT.md §13.3)
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

# ── delegated acceptance (REPORT.md §14) ──
DELEGATION_ACTIONS = ("delegate", "revoke-delegation")
DELEGATED = "delegated"  # an acceptance record's kind
DELEGATED_WORDS = "accepted by delegation (not read by the operator)"
# The actions an agent may accept under a delegation, each with the machine criteria its record must
# show, every one true, or every reader reads it VOID. gate_accept.py computes them (the names are
# the contract between the writer and the readers here).
DELEGATED_CRITERIA: Dict[str, Tuple[str, ...]] = {
    "cert": ("state", "newest-certificate", "rows-pass", "no-reopen"),
    "frame": (
        "lint",
        "newest-change-is-delta",
        "known-rows-open",
        "annotations-pinned",
    ),
    "implementation": (
        "state",
        "newest-built-certificate",
        "rows-pass",
        "freeze-snapshot",
    ),
    "extra-round": ("state", "once-per-program"),
    "profile": ("switch-terms",),
    "adopt": ("frame-predates-1.2", "once-per-program"),
    "extend-decision": (
        "decision-on-record",
        "research-can-raise-it",
        "once-per-decision",
    ),
    "reopen": ("state", "certificate", "not-reopened"),
}
DELEGABLE = tuple(DELEGATED_CRITERIA)
NOT_DELEGABLE = {
    "third-read": "a third read spends a sealed held-out stratum that can never be re-sealed "
    "(ruling 915d7fb98b7f item 5), a disclosed cost only the operator accepts",
    "veto": "a veto overrules a default the operator's own packet set; it is his voice, and the "
    "sweep counts only his signature",
    "delegate": "the delegation is the operator's own grant of authority; an agent cannot extend it",
    "revoke-delegation": "the delegation is the operator's to end",
}


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
    r"(frame|cert|extra-round|reopen|veto|extend-decision|implementation|third-read|profile|adopt)"
    r"(?:/([A-Za-z0-9._-]+))?$"
)


DELEGATION_ROW_RE = re.compile(
    r"^research:([a-z0-9][a-z0-9-]{0,63}|\*)/(delegate|revoke-delegation)$"
)


def parse_row(row: str) -> Optional[Dict[str, Optional[str]]]:
    """'research:<slug>/<action>[/<target>]' -> {slug, action, target}; None if not that namespace.
    The delegation rows alone take `*` (every program) for the slug, and no target."""
    m = DELEGATION_ROW_RE.match(row or "")
    if m:
        return {"slug": m.group(1), "action": m.group(2), "target": None}
    m = ROW_RE.match(row or "")
    if not m:
        return None
    slug, action, target = m.group(1), m.group(2), m.group(3)
    if (action in TARGETED) != (target is not None):
        return None  # the TARGETED actions need a target; nothing else takes one
    if action == "adopt" and target not in ADOPT_TARGETS:
        return None  # only a named, built part of a later method is adoptable
    return {"slug": slug, "action": action, "target": target}


def profile_switch_terms(slug: str, target: Optional[str]) -> Dict[str, Any]:
    """What a profile-switch signature records ({"from", "after_round"}), or Refused.

    A switch is signed while the program is certifying, between two certification rounds (the
    newest one closed, the next not started), once per program, and only to a narrower profile whose
    hard cap still leaves a round to run."""
    if target not in kit.PROFILES:
        raise Refused(
            f"REFUSED — {target!r} is not a profile: one of {', '.join(kit.PROFILES)}."
        )
    state = (kit.registry_get(slug) or {}).get("state")
    if state != "certifying":
        raise Refused(
            f"REFUSED — {slug} is {state or 'not registered'}, not certifying: a profile switch "
            "moves the certification rounds still to run."
        )
    rec = kit.records_dir(slug)
    cur = (kit.read_json(rec / "frame.json") or {}).get("profile")
    if cur not in kit.PROFILES:
        raise Refused(
            f"REFUSED — {rec / 'frame.json'} names no profile to switch from."
        )
    if any(r["_verdict"] == VALID for r in research_records(slug, "profile")):
        raise Refused("REFUSED — the one profile switch per program is already signed.")
    cap = kit.PROFILES[target]["hard_cap"]
    if cap >= kit.PROFILES[cur]["hard_cap"]:
        raise Refused(
            f"REFUSED — {target} is not narrower than {cur}: a switch only narrows review; wider "
            "review is an extra round set or a reopen."
        )
    mats = [kit.read_json(p) for p in (rec / "rounds").glob("*/matrix.json")]
    mats = sorted(
        [m for m in mats if m and m.get("kind", "certification") == "certification"],
        key=lambda m: int(m.get("seq") or 0),
    )
    if not mats or not mats[-1].get("closed"):
        raise Refused(
            "REFUSED — a profile switch is signed between rounds, after a certification round "
            "has closed (round.sh close)."
        )
    if (rec / "rounds" / str(len(mats) + 1)).exists():
        raise Refused(
            f"REFUSED — round {len(mats) + 1} has already started on {cur}; sign the switch after "
            "it closes."
        )
    counted = sum(1 for m in mats if m.get("counted"))
    if counted < 1 or counted >= cap:
        raise Refused(
            f"REFUSED — {counted} counted round(s) so far against {target}'s hard cap of {cap}: "
            "the switch needs a counted round behind it and a round still to run."
        )
    return {"from": cur, "after_round": counted}


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
            " or research:<slug|*>/<delegate|revoke-delegation>"
        )
    slug, action, target = parsed["slug"], parsed["action"], parsed["target"]
    if action in DELEGATION_ACTIONS:
        return sign_delegation(row, str(slug), str(action), because)
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
        action
        in (
            "extra-round",
            "reopen",
            "veto",
            "extend-decision",
            "third-read",
            "profile",
            "adopt",
        )
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
        r["_verdict"] == VALID for r in research_records(slug, "extra-round")
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
            r["_verdict"] == VALID
            for r in research_records(slug, "extend-decision", target)
        ):
            raise Refused(
                f"REFUSED — the one research extension per decision (REPORT.md §12.3) is "
                f"already bought for {target}."
            )
    if action == "adopt":
        fr = kit.read_json(kit.records_dir(slug) / "frame.json") or {}
        if not fr:
            raise Refused(f"REFUSED — {slug} has no frame.json to adopt {target} for.")
        if kit.is_v12(fr):
            raise Refused(
                f"REFUSED — {slug}'s frame is method {fr.get('method_version')}: {target} already "
                "applies, so there is nothing to adopt."
            )
        if any(r["_verdict"] == VALID for r in research_records(slug, "adopt", target)):
            raise Refused(f"REFUSED — {target} is already adopted for {slug}.")
    terms = profile_switch_terms(slug, target) if action == "profile" else {}
    now = time.time()
    rec = {
        **terms,
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


# ── delegated acceptance (REPORT.md §14) ─────────────────────────────────────────────────────────


def delegations_log() -> Path:
    """Every delegation and revoke, for every program: one log, since `*` names no program."""
    return kit.research_home() / "delegations.jsonl"


def acceptance_log(slug: str) -> Path:
    """The program's delegated acceptances, apart from the operator's signoff.jsonl."""
    return kit.sealed_dir(slug) / "delegated.jsonl"


def record_sha(rec: Dict[str, Any]) -> str:
    """sha256 of a delegation record as signed: canonical JSON without its own id and hash."""
    body = {
        k: v
        for k, v in rec.items()
        if k not in ("id", "sha256") and not k.startswith("_")
    }
    return hashlib.sha256(json.dumps(body, sort_keys=True).encode()).hexdigest()


def covers(scope: Any, slug: str) -> bool:
    return scope == "*" or scope == slug


def delegation_records() -> List[Dict[str, Any]]:
    """Every delegation and revoke, each with `_verdict`: VOID when written under an agent or with no
    chain (arm 3), or when its bytes no longer hash to the sha256 it was signed with."""
    out = []
    for rec in kit.read_jsonl(delegations_log()):
        v = verdict(rec)
        if v == VALID and (
            rec.get("action") not in DELEGATION_ACTIONS
            or rec.get("sha256") != record_sha(rec)
        ):
            v = VOID
        rec["_verdict"] = v
        out.append(rec)
    return out


def in_force(
    d: Dict[str, Any], slug: str, at: float, recs: List[Dict[str, Any]]
) -> bool:
    """Was delegation `d` in force for `slug` at time `at`? A VALID delegate record covering the
    program, given at or before `at`, with no VALID revoke covering the program between the two:
    the newest of a delegation and a revoke wins."""
    if (
        d.get("_verdict") != VALID
        or d.get("action") != "delegate"
        or not covers(d.get("program"), slug)
    ):
        return False
    given = float(d.get("at") or 0)
    if given > at:
        return False
    return not any(
        r.get("_verdict") == VALID
        and r.get("action") == "revoke-delegation"
        and covers(r.get("program"), slug)
        and given < float(r.get("at") or 0) <= at
        for r in recs
    )


def delegation_for(slug: str, at: Optional[float] = None) -> Optional[Dict[str, Any]]:
    """The newest delegation in force for `slug` at `at` (now by default), or None."""
    recs = delegation_records()
    when = time.time() if at is None else at
    live = [d for d in recs if in_force(d, slug, when, recs)]
    return max(live, key=lambda d: float(d.get("at") or 0)) if live else None


def acceptance_verdict(
    slug: str, rec: Dict[str, Any], dels: List[Dict[str, Any]]
) -> Tuple[str, str]:
    """(VALID|VOID|STALE, why) for one delegated acceptance. VOID unless it is a delegated record of
    a delegable action for this program, its delegation is on record, VALID and in force at its time,
    and it shows every criterion its action requires, each true; STALE if a pinned artifact changed."""
    action = str(rec.get("action"))
    if rec.get("kind") != DELEGATED or rec.get("program") != slug:
        return VOID, "not a delegated acceptance of this program"
    if action not in DELEGABLE:
        return (
            VOID,
            f"{action} is never delegable: {NOT_DELEGABLE.get(action, 'unknown action')}",
        )
    ref = (rec.get("delegation") or {}).get("sha256")
    d = next((x for x in dels if ref and x.get("sha256") == ref), None)
    if d is None:
        return VOID, "it names no delegation on record"
    if d["_verdict"] != VALID:
        return (
            VOID,
            f"its delegation {d.get('id')} is void (agent-written, or edited after signing)",
        )
    if not in_force(d, slug, float(rec.get("at") or 0), dels):
        return VOID, (
            f"its delegation {d.get('id')} was not in force for {slug} at {rec.get('at_iso')} "
            "(revoked before it, or given after it)"
        )
    shown = {
        str(c.get("name")): c.get("ok")
        for c in rec.get("criteria") or []
        if isinstance(c, dict)
    }
    unmet = [n for n in DELEGATED_CRITERIA[action] if shown.get(n) is not True]
    if unmet:
        return VOID, f"its record does not show criteria {', '.join(unmet)} holding"
    if action in EVIDENCED and not rec.get("pins"):
        return VOID, "it pins no artifact"
    now = current_pins(slug, rec)
    if any(now.get(p) != sha for p, sha in (rec.get("pins") or {}).items()):
        return STALE, "a pinned artifact changed after it"
    return VALID, ""


def research_records(
    slug: str, action: Optional[str] = None, target: Optional[str] = None
) -> List[Dict[str, Any]]:
    """Every record in the program's log (optionally filtered), each with `_verdict` set, then every
    delegated acceptance (`_delegated` True, `_why` naming why one is not VALID)."""
    out = []
    for rec in kit.read_jsonl(research_log(slug)):
        if action and rec.get("action") != action:
            continue
        if target is not None and rec.get("target") != target:
            continue
        rec["_verdict"] = verdict(rec, current_pins(slug, rec))
        out.append(rec)
    dels: Optional[List[Dict[str, Any]]] = None
    for rec in kit.read_jsonl(acceptance_log(slug)):
        if action and rec.get("action") != action:
            continue
        if target is not None and rec.get("target") != target:
            continue
        if dels is None:
            dels = delegation_records()
        rec["_verdict"], rec["_why"] = acceptance_verdict(slug, rec, dels)
        rec["_delegated"] = True
        out.append(rec)
    return out


def signed_words(rec: Dict[str, Any]) -> str:
    """How a reader names a VALID record: the operator's signature, or a delegated acceptance."""
    when = rec.get("at_iso") or "at an unrecorded time"
    if rec.get("_delegated"):
        return f"{DELEGATED_WORDS} {when}"
    return f"signed by the operator {when}"


def sign_delegation(
    row: str, scope: str, action: str, because: Optional[str]
) -> Dict[str, Any]:
    """Append one delegation or revoke, an operator signature (arms 1 and 3), to delegations_log()."""
    chain = ancestry()
    refuse_if_agent(
        chain,
        f"cc-signoff {row} " + ('--because "<words>"' if action == "delegate" else ""),
    )
    if action == "delegate" and not (because or "").strip():
        raise Refused(
            'REFUSED — delegate needs --because "<words>": every acceptance made under it quotes them.'
        )
    if scope != "*" and kit.registry_get(scope) is None:
        raise Refused(
            f"REFUSED — {scope} is not a registered program; research:*/{action} covers every "
            "program, or register it first (a delegation for a misspelt slug would cover nothing)."
        )
    if action == "revoke-delegation" and not any(
        covers(d.get("program"), scope) or scope == "*"
        for d in delegation_records()
        if d["_verdict"] == VALID and d.get("action") == "delegate"
    ):
        raise Refused(
            f"REFUSED — no delegation on record covers {scope}: nothing to revoke."
        )
    now = time.time()
    rec: Dict[str, Any] = {
        "row": row,
        "program": scope,
        "action": action,
        "target": None,
        "at": now,
        "at_iso": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(now)),
        "because": because,
        "pins": {},
        "provenance": {
            "claude_ancestor": False,
            "chain": [c["comm"] if isinstance(c, dict) else str(c) for c in chain],
        },
    }
    rec["sha256"] = record_sha(rec)
    rec["id"] = rec["sha256"][:12]
    log = delegations_log()
    log.parent.mkdir(parents=True, exist_ok=True)
    with log.open("a") as fh:
        fh.write(json.dumps(rec, sort_keys=True) + "\n")
    return rec


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
        return signed_words(rec)
    if st["status"] == VOID and rec.get("_delegated"):
        return f"delegated acceptance VOID ({rec.get('_why')}): not signed"
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
