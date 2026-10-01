"""kit.py — the shared contract of the hand-run research kit (REPORT.md §8 item 7).

Every kit script imports this module; nothing here runs on its own. It holds four things, each
fixed by the report so that no script re-derives them:

  1. PATHS. The program's tracked records live in the deliverable repo at
     `docs/research/<slug>/` (SYNTHESIS.md:934). Sealed material (seed vault, bundles, panel
     transcripts, operator signoffs) lives outside every repo at `$CC_RESEARCH_HOME/<slug>/`,
     mode 0700 (SYNTHESIS.md:947).
  2. PROFILES AND CAPS from REPORT.md §6.1, §3.8 and §6.5. Caps live in code (§10 item 17).
  3. THE PROGRAM REGISTRY, whose shape wave A1 owns (scripts/lib/research-program.sh). gate.sh is
     its only writer, and it writes through `registry_set` here, never by hand.
  4. RECORD I/O: append-only JSONL and atomic JSON writes.

Python 3.9-safe (macOS /usr/bin/python3, which launchd resolves), standard library only.
Paths may be overridden by environment for tests; the defaults are the live stores:
  CC_RESEARCH_HOME      sealed root          (~/.claude/autonomy/research)
  CC_RESEARCH_REGISTRY  registry file        ($CC_RESEARCH_HOME/programs.json)
  CC_RESEARCH_RECORDS   one program's tracked records dir (else resolved from the registry)
"""

from __future__ import annotations

import json
import math
import os
import re
import tempfile
import time
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional

# ── 1. paths ────────────────────────────────────────────────────────────────────────────────────

SLUG_RE = re.compile(r"^[a-z0-9][a-z0-9-]{0,63}$")


class KitError(Exception):
    """A refusal the caller prints and exits 2 on. Never a crash."""


def research_home() -> Path:
    return Path(
        os.environ.get("CC_RESEARCH_HOME")
        or (Path.home() / ".claude" / "autonomy" / "research")
    )


def registry_path() -> Path:
    env = os.environ.get("CC_RESEARCH_REGISTRY")
    return Path(env) if env else research_home() / "programs.json"


def check_slug(slug: str) -> str:
    if not SLUG_RE.match(slug or ""):
        raise KitError(
            f"bad program slug {slug!r}: lowercase letters, digits and '-' only"
        )
    return slug


def sealed_dir(slug: str, create: bool = False) -> Path:
    """The program's sealed directory, outside every repo. Created 0700 on request."""
    d = research_home() / check_slug(slug)
    if create:
        d.mkdir(parents=True, exist_ok=True)
        os.chmod(d, 0o700)
    return d


def records_dir(slug: str) -> Path:
    """The program's tracked records: $CC_RESEARCH_RECORDS, else <first cwd_root>/docs/research/<slug>."""
    env = os.environ.get("CC_RESEARCH_RECORDS")
    if env:
        return Path(env)
    prog = registry_get(slug)
    if prog is None or not prog.get("cwd_roots"):
        raise KitError(
            f"program {slug!r} is not registered (run gate.sh register first)"
        )
    return Path(prog["cwd_roots"][0]) / "docs" / "research" / slug


# ── 2. profiles and caps ────────────────────────────────────────────────────────────────────────

VENDORS = ("anthropic", "frontier", "openai", "google")  # the four slot sets of §3.8
VENDOR_FAMILY = {
    "anthropic": "anthropic",
    "frontier": "anthropic",  # frontier counts as Anthropic
    "openai": "openai",
    "google": "google",
}
STRATEGIES = (
    "full-context",
    "plan-only",
    "assume-fails-in-production",
    "consumer",
    "operations-and-security",
    "frame-rows-only",
)  # §3.8, in fill order
LENSES = (
    "premise",
    "census",
    "instrument",
    "trace",
    "consistency",
    "sequencing",
    "criteria",
    "contact-declaration",
    "drift",
    "frame-omission",
    "operator-intent",
)  # §3.8 brief

# Stage budgets in agent-days (§3.2-§3.7 headings): lite = the low ends, standard = the high ends,
# full = 1.5 x standard (§6.1; lite and full are assumptions the calibration run replaces).
_STD_STAGE_DAYS = {1: 2.0, 2: 1.5, 3: 1.5, 4: 3.0, 5: 2.5, 6: 1.0}

PROFILES: Dict[str, Dict[str, Any]] = {
    "lite": {
        "per_slot_set": 2,
        "quiet_to_stop": 2,
        "hard_cap": 6,
        "seeds_original": 40,
        "design_holes": 10,
        "frame_expansion_level_days": 0.5,
        "frame_delta_days": 2,
        "stage_days": {1: 0.5, 2: 0.5, 3: 0.75, 4: 1.0, 5: 1.0, 6: 0.5},
    },
    "standard": {
        "per_slot_set": 4,
        "quiet_to_stop": 3,
        "hard_cap": 10,
        "seeds_original": 60,
        "design_holes": 20,
        "frame_expansion_level_days": 1.0,
        "frame_delta_days": 3,
        "stage_days": dict(_STD_STAGE_DAYS),
    },
    "full": {
        "per_slot_set": 6,
        "quiet_to_stop": 3,
        "hard_cap": 14,
        "seeds_original": 100,
        "design_holes": 40,
        "frame_expansion_level_days": 1.0,
        "frame_delta_days": 3,
        "stage_days": {k: v * 1.5 for k, v in _STD_STAGE_DAYS.items()},
    },
}

CAPS = {
    "overrun_factor": 1.5,  # §6.5 stage overrun: one class-B "proceed" packet at 1.5 x budget
    "overrun_default_hours": 24,
    "slot_reruns": 2,  # dead or voided reviewer slot in a live lane
    "frame_critique_rounds": 2,  # exactly 2 (§3.2 step 6, §6.5)
    "frame_critique_reviewers": 6,  # per round, across >= 3 vendors
    "frame_critique_min_vendors": 3,
    "extra_round_sets": 1,  # operator-only, once per program (§6.4)
    "reversible_runs": 2,  # decision research runs on a reversible row
    "refutation_reopens": 2,  # each decision reopened by refutation at most twice
    "dead_lane_default_hours": 48,  # class-B "continue on two vendors"
    "class_b_default_hours": 48,  # §3.5 rulings table
    "agent_change_requests": 2,  # §5.3 step 6
    "seed_lines_per_seed": 25,  # at most 1 original seed per 25 plan lines (§3.9)
    "escape_seeds": 20,
    "rp90_slack_rounds": 4,  # R_max = min(round-1 forecast p90 + 4, hard cap)
}


def profile(name: str) -> Dict[str, Any]:
    if name not in PROFILES:
        raise KitError(f"unknown profile {name!r}: one of {', '.join(PROFILES)}")
    p = dict(PROFILES[name])
    p["name"] = name
    p["strategies"] = list(STRATEGIES[: p["per_slot_set"]])
    p["reviewers_per_round"] = p["per_slot_set"] * len(VENDORS)
    p["stage_budget_days"] = sum(p["stage_days"].values())
    return p


def r_max(
    profile_name: str, round1_p90: Optional[float], extra_round_granted: bool = False
) -> int:
    """The round cap (§3.8): min(round-1 forecast p90 + 4, hard cap), +1 only for a signed extra set.

    With no round-1 forecast yet the hard cap applies. The extra round set is the operator's one
    purchase per program (§6.4); the caller proves it with a VALID operator signoff record.
    """
    cap = profile(profile_name)["hard_cap"]
    if round1_p90 is not None:
        cap = min(cap, int(math.ceil(round1_p90)) + CAPS["rp90_slack_rounds"])
    return cap + (1 if extra_round_granted else 0)


def max_original_seeds(profile_name: str, plan_lines: int) -> int:
    return min(
        profile(profile_name)["seeds_original"],
        plan_lines // CAPS["seed_lines_per_seed"],
    )


# ── 3. the program registry (contract owned by wave A1; gate.sh is its only writer) ────────────

STATES = ("registered", "certifying", "certified", "closed")
_ENTRY_KEYS = ("slug", "aliases", "cwd_roots", "state")


def registry_load() -> Dict[str, Any]:
    p = registry_path()
    if not p.exists():
        return {"programs": []}
    data = json.loads(p.read_text())
    if not isinstance(data, dict) or not isinstance(data.get("programs"), list):
        raise KitError(f"registry {p} does not match the contract (no programs array)")
    return data


def registry_get(slug: str) -> Optional[Dict[str, Any]]:
    for prog in registry_load()["programs"]:
        if prog.get("slug") == slug:
            return prog
    return None


def registry_set(
    slug: str,
    state: str,
    aliases: Optional[List[str]] = None,
    cwd_roots: Optional[List[str]] = None,
) -> Dict[str, Any]:
    """Create or update ONE program entry, atomically, under a mkdir lock. Other entries untouched.

    Writes exactly the contract's four keys. cwd_roots must be absolute (the resolver ignores
    relative roots). Only gate.sh may call this.
    """
    check_slug(slug)
    if state not in STATES:
        raise KitError(f"bad registry state {state!r}: one of {', '.join(STATES)}")
    for r in cwd_roots or []:
        if not os.path.isabs(r):
            raise KitError(f"cwd_root {r!r} is not absolute")
    path = registry_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    lock = path.with_name(path.name + ".lock")
    for _ in range(100):
        try:
            os.mkdir(lock)
            break
        except FileExistsError:
            time.sleep(0.05)
    else:
        raise KitError(
            f"registry lock {lock} held for 5 s; remove it if no gate.sh is running"
        )
    try:
        data = registry_load()
        entry = next((p for p in data["programs"] if p.get("slug") == slug), None)
        if entry is None:
            if cwd_roots is None:
                raise KitError(
                    f"program {slug!r} is not registered; register needs --root"
                )
            entry = {"slug": slug, "aliases": [], "cwd_roots": [], "state": state}
            data["programs"].append(entry)
        if aliases is not None:
            entry["aliases"] = list(aliases)
        if cwd_roots is not None:
            entry["cwd_roots"] = [os.path.realpath(r) for r in cwd_roots]
        entry["state"] = state
        for k in list(entry):
            if k not in _ENTRY_KEYS:
                del entry[k]
        write_json_atomic(path, data)
        return dict(entry)
    finally:
        os.rmdir(lock)


# ── 4. record I/O ───────────────────────────────────────────────────────────────────────────────


def now_iso() -> str:
    return os.environ.get("CC_NOW") or time.strftime(
        "%Y-%m-%dT%H:%M:%SZ", time.gmtime()
    )


def parse_iso(s: str) -> float:
    """ISO-8601 UTC ('...Z') to epoch seconds."""
    import calendar

    return float(calendar.timegm(time.strptime(s, "%Y-%m-%dT%H:%M:%SZ")))


def write_json_atomic(path: Path, obj: Any) -> None:
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=str(path.parent), prefix=f".{path.name}.")
    with os.fdopen(fd, "w") as fh:
        json.dump(obj, fh, indent=2, sort_keys=True)
        fh.write("\n")
    os.replace(tmp, path)


def read_json(path: Path, default: Any = None) -> Any:
    path = Path(path)
    if not path.exists():
        return default
    return json.loads(path.read_text())


def append_jsonl(path: Path, rec: Dict[str, Any]) -> None:
    """Append one record. Stores are append-only event logs; state is the fold (SYNTHESIS.md:934)."""
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    rec.setdefault("ts", now_iso())
    with path.open("a") as fh:
        fh.write(json.dumps(rec, sort_keys=True) + "\n")


def read_jsonl(path: Path) -> List[Dict[str, Any]]:
    """Every record, in order. A malformed line is a KitError naming its line, never skipped."""
    path = Path(path)
    if not path.exists():
        return []
    out = []
    for n, line in enumerate(path.read_text().splitlines(), 1):
        if not line.strip():
            continue
        try:
            out.append(json.loads(line))
        except ValueError as e:
            raise KitError(f"{path}:{n}: not JSON ({e})") from e
    return out


def fold(
    records: Iterable[Dict[str, Any]], key: str = "id"
) -> Dict[str, Dict[str, Any]]:
    """Last-writer-wins per id, merging fields, so a later event updates an earlier one."""
    state: Dict[str, Dict[str, Any]] = {}
    for r in records:
        k = r.get(key)
        if k is None:
            continue
        state.setdefault(k, {}).update(r)
    return state
