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

import contextlib
import hashlib
import json
import math
import os
import re
import socket
import tempfile
import time
from pathlib import Path
from typing import Any, Dict, Iterable, Iterator, List, Optional

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
        "quiet_probes_to_stop": 3,  # §12.1 K
        "built_hard_cap": 3,  # §11 built rounds
        "built_stage_days": 1.0,  # §11 Stage 9 agent time, soak excluded
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
        "quiet_probes_to_stop": 4,  # §12.1 K
        "built_hard_cap": 4,  # §11 built rounds
        "built_stage_days": 2.0,  # §11 Stage 9 agent time, soak excluded
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
        "quiet_probes_to_stop": 5,  # §12.1 K
        "built_hard_cap": 6,  # §11 built rounds
        "built_stage_days": 3.0,  # §11 Stage 9 agent time, soak excluded
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
    # ── method v1.2 (REPORT.md §11, §12): every figure below is an assumed input until the pilot ──
    "yield_window_factor": 2,  # §12.1: yield is measured over the last 2K counted probes
    "yield_ceiling_factor": 4.0,  # §12.1 hard ceiling: 4 x the stage budget in agent-days
    "yield_probe_ceiling": 60,  # §12.1 hard ceiling: counted probes per stage
    "decision_research_ceiling_factor": 2.0,  # §12.2: a research-tagged row gets 2 x its timebox
    "decision_extensions": 1,  # §12.3: operator-bought, per decision
    "mutants_min": 10,  # §11 row 22
    "mutants_per_row_min": 1,
    "mutation_reruns_per_survivor": 1,
    "soak_min_hours": 24,  # §11 row 24
    "soak_min_samples": 24,
    "soak_restarts": 2,
    "built_min_families": 2,  # §11 row 25
}

YIELD_STAGES = (3, 5)  # §12.1: contact, and the build-to-learn skeleton
BUILD_FINDABLE_SHARE = 0.585  # §11: share of after-signoff changes building finds; "share assumed"
AS_BUILT_KINDS = ("skeleton", "handed-cmd", "dry-run-deploy", "fault-inject")  # §11 instrument 3
AS_BUILT_ENV = {"path": "/usr/bin:/bin", "interpreter": "/bin/bash", "interpreter_major": "3.2"}
SOAK_BOUNDARIES = ("hour", "utc-midnight", "local-midnight")  # default; frame.json soak_boundaries


def method_version(frame: Dict[str, Any]) -> tuple:
    """The method version the frame was signed under, as a tuple; absent reads (1, 1)."""
    raw = str((frame or {}).get("method_version") or "1.1")
    try:
        return tuple(int(x) for x in raw.split("."))
    except ValueError:
        raise KitError(f"frame.json method_version {raw!r} is not a version") from None


def is_v12(frame: Dict[str, Any]) -> bool:
    """True when the v1.2 mechanisms (REPORT.md §11, §12) apply to this program."""
    return method_version(frame) >= (1, 2)


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

STATES = ("registered", "certifying", "certified", "build-certifying", "build-certified", "closed")
# Method v1.2 (REPORT.md §11): build-certifying is set by `gate.sh built-freeze` after the last build
# wave, build-certified by `gate.sh built-run`. ACTIVE_STATES are the ones a program is live in.
ACTIVE_STATES = STATES[:-1]
BUILD_STATES = ("build-certifying", "build-certified")
_ENTRY_KEYS = ("slug", "aliases", "cwd_roots", "state")


LOCK_WAIT_S = 5.0  # a writer waits this long for a mkdir lock, then refuses


@contextlib.contextmanager
def mkdir_lock(lock: Path, what: str, writer: str) -> Iterator[None]:
    """Hold <lock> for the block. mkdir is atomic, so exactly one process holds it at a time."""
    lock.parent.mkdir(parents=True, exist_ok=True)
    deadline = time.monotonic() + LOCK_WAIT_S
    while True:
        try:
            os.mkdir(lock)
            break
        except FileExistsError:
            if time.monotonic() >= deadline:
                raise KitError(
                    f"{what} lock {lock} held for {LOCK_WAIT_S:g} s; remove it if no "
                    f"{writer} is running"
                ) from None
            time.sleep(0.05)
    try:
        yield
    finally:
        os.rmdir(lock)


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
    with mkdir_lock(path.with_name(path.name + ".lock"), "registry", "gate.sh"):
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


# ── 4b. concurrent writers: locked id minting (audit 2026-10-04, continuity lens item 6) ────────


def test_delay(var: str) -> None:
    """TEST-ONLY: sleep $<var> seconds, so a suite can hold a race window open deterministically."""
    s = os.environ.get(var)
    if s:
        time.sleep(float(s))


def mint_id(path: Path, prefix: str) -> str:
    """The next <prefix>-<n> for the JSONL store at <path>, unique across concurrent writers.

    The id is reserved under a mkdir lock in $CC_RESEARCH_HOME/.mint/ (outside every repo), so it
    stays unique although the caller appends its record after the lock is released. A reserved id
    whose append then fails leaves a gap, never a duplicate.
    """
    path = Path(path)
    key = hashlib.sha256(str(path.resolve()).encode()).hexdigest()[:16]
    state = research_home() / ".mint" / f"{key}.json"
    with mkdir_lock(state.with_suffix(".lock"), "id mint", "cc-research writer"):
        n = 0
        for r in read_jsonl(path):
            m = re.match(rf"^{prefix}-(\d+)$", str(r.get("id", "")))
            if m:
                n = max(n, int(m.group(1)))
        last = read_json(state, {}) or {}
        n = max(n, int((last.get("last") or {}).get(prefix, 0))) + 1
        test_delay("CC_RESEARCH_TEST_MINT_DELAY")
        last.setdefault("last", {})[prefix] = n
        last["path"] = str(path.resolve())
        write_json_atomic(state, last)
    return f"{prefix}-{n}"


# ── 4c. the program lease (audit 2026-10-04, continuity lens item 6) ────────────────────────────
# <sealed>/lease.json names the ONE owner whose writing verbs may run: {owner, pid, host, acquired,
# heartbeat}. Opt-in: with no lease file nothing is refused. Every writing verb of cc-research,
# gate.sh, round.sh and seed.py calls lease_check first; the holder's own check is its heartbeat.

LEASE_TTL_S = 1800.0  # a lease whose heartbeat is older than this is stale: anyone may write


def lease_owner() -> str:
    """CC_RESEARCH_OWNER, else the Claude session id, else pid:<parent pid>."""
    return (
        os.environ.get("CC_RESEARCH_OWNER")
        or os.environ.get("CLAUDE_CODE_SESSION_ID")
        or os.environ.get("CLAUDE_SESSION_ID")
        or f"pid:{os.getppid()}"
    )


def lease_path(slug: str) -> Path:
    return sealed_dir(slug) / "lease.json"


def lease_age(lease: Dict[str, Any]) -> float:
    try:
        return parse_iso(now_iso()) - parse_iso(str(lease["heartbeat"]))
    except (KeyError, ValueError) as e:
        raise KitError(f"lease has no readable heartbeat ({e}); remove it by hand") from e


def _lease_held(slug: str, owner: str) -> Optional[Dict[str, Any]]:
    """The lease when a DIFFERENT owner holds it fresh, else None. Call under the lease lock."""
    lease = read_json(lease_path(slug))
    if lease and lease.get("owner") != owner and lease_age(lease) < LEASE_TTL_S:
        return dict(lease)
    return None


def _lease_refusal(slug: str, lease: Dict[str, Any], owner: str) -> KitError:
    return KitError(
        f"program {slug} is leased to {lease.get('owner')} (pid {lease.get('pid')} on "
        f"{lease.get('host')}, heartbeat {lease_age(lease):.0f} s ago; stale after "
        f"{LEASE_TTL_S:.0f} s); you are {owner}. The holder releases it with "
        f"`cc-research lease release --program {slug}`"
    )


def _lease_lock(slug: str) -> Any:
    return mkdir_lock(sealed_dir(slug, create=True) / "lease.lock", "lease", "lease writer")


def lease_check(slug: str, owner: Optional[str] = None) -> None:
    """Refuse a writing verb while another owner holds a fresh lease. No lease file: no-op."""
    if not lease_path(slug).exists():
        return
    owner = owner or lease_owner()
    with _lease_lock(slug):
        held = _lease_held(slug, owner)
        if held:
            raise _lease_refusal(slug, held, owner)
        lease = read_json(lease_path(slug))
        if lease and lease.get("owner") == owner:
            lease["heartbeat"] = now_iso()
            write_json_atomic(lease_path(slug), lease)


def lease_acquire(slug: str, owner: Optional[str] = None) -> Dict[str, Any]:
    """Take (or renew) the lease; refused while another owner holds it fresh."""
    owner = owner or lease_owner()
    with _lease_lock(slug):
        held = _lease_held(slug, owner)
        if held:
            raise _lease_refusal(slug, held, owner)
        old = read_json(lease_path(slug)) or {}
        now = now_iso()
        lease = {
            "owner": owner,
            "pid": os.getppid(),
            "host": socket.gethostname(),
            "acquired": old.get("acquired") if old.get("owner") == owner else now,
            "heartbeat": now,
        }
        write_json_atomic(lease_path(slug), lease)
        return lease


def lease_release(slug: str, owner: Optional[str] = None) -> bool:
    """Drop the lease; refused while another owner holds it fresh. False: there was none."""
    owner = owner or lease_owner()
    if not lease_path(slug).exists():
        return False
    with _lease_lock(slug):
        held = _lease_held(slug, owner)
        if held:
            raise _lease_refusal(slug, held, owner)
        lease_path(slug).unlink()
        return True


# ── 5. evidence levels (§3.4) and the conviction rule (§3.5) ────────────────────────────────────
# Levels are COMPUTED from how a claim was checked, never typed by hand.
#   E0 recall · E1 secondary text · E2 primary read · E3 live read (with expiry)
#   E4 measurement (>= 5 samples with a load control) · E5 execution in the target env · E6 operator's own look

REQUIRED_LEVEL = {"code": 2, "document": 2, "live-state": 3, "behavior": 4, "target-env": 5,
                  "operator": 6}
_PROBE_LEVEL = {"read": 2, "read-through": 2, "live-read": 3, "measure": 4, "spike": 5,
                "skeleton": 5, "model-check": 5, "fault-inject": 5, "dry-run-deploy": 5,
                "handed-cmd": 5, "reproduce": 5, "operator-view": 6}


def probe_level(probe: Dict[str, Any]) -> int:
    """The evidence level one probe earns. 0 when it failed, or a fallible probe never showed it
    could fail (no negative control ran and no reason is recorded; §3.4)."""
    if probe.get("exit") != 0:
        return 0
    nc = probe.get("negative_control") or {}
    if not nc.get("ran") and not nc.get("reason_if_not_run"):
        return 0
    if nc.get("ran") and not nc.get("reported_refutation"):
        return 0                      # it ran against known-bad input and still passed: cannot fail
    lvl = _PROBE_LEVEL.get(probe.get("kind", ""), 0)
    if lvl == 4 and (int(probe.get("n") or 0) < 5 or not probe.get("load_control")):
        return 1                      # a measurement without 5 samples and a load control is anecdote
    return lvl


def premise_level(premise: Dict[str, Any], probes: Dict[str, Dict[str, Any]],
                  now: Optional[float] = None) -> int:
    """Achieved level: the best of its own origin tier and its probes; live reads past ttl_h lapse."""
    now = time.time() if now is None else now
    origin = str((premise.get("origin") or {}).get("tier", "E0"))
    best = int(origin[1:]) if origin[:1] == "E" and origin[1:].isdigit() else 0
    best = min(best, 1)               # recall and secondary text never close a load-bearing claim
    ttl = premise.get("ttl_h")
    for pid in premise.get("probes") or []:
        pr = probes.get(pid)
        if not pr:
            continue
        lvl = probe_level(pr)
        if lvl == 3 and ttl is not None and pr.get("at"):
            if now - parse_iso(pr["at"]) > float(ttl) * 3600:
                lvl = 0
        best = max(best, lvl)
    return best


def premise_at_level(premise: Dict[str, Any], probes: Dict[str, Dict[str, Any]],
                     now: Optional[float] = None) -> bool:
    need = REQUIRED_LEVEL.get(premise.get("truth_lives_in", ""), 99)
    return premise.get("verdict") == "holds" and premise_level(premise, probes, now) >= need


def conviction(decision: Dict[str, Any], premises: Dict[str, Dict[str, Any]],
               probes: Dict[str, Dict[str, Any]], now: Optional[float] = None) -> Optional[int]:
    """The §3.5 rule, from the decision's stored tally. None = no load-bearing factual premise, so a
    taste or value call the operator rules.

      90 only when every load-bearing premise of the chosen option is at its required level AND the
      'what would flip it' probe ran and came back negative; otherwise
      floor(89 x at-level / all). A flip probe not run caps at 89 (the formula already does).
    """
    tally = decision.get("tally") or {}
    ids = list(tally.get("premises") or decision.get("premises") or [])
    if not ids:
        return None
    ok = sum(1 for i in ids if i in premises and premise_at_level(premises[i], probes, now))
    flip = tally.get("flip_probe")
    flip_negative = bool(flip) and tally.get("flip_result") == "negative" and \
        probe_level(probes.get(flip, {})) > 0
    if ok == len(ids) and flip_negative:
        return 90
    return (89 * ok) // len(ids)


# ── 6. sealed-at-rest encryption (seed vault §3.9; sealed router held-out set, §10 item 13) ─────
# Same-uid processes can still read the keychain, so this is detection-grade isolation, never
# prevention (§3.8, §7). /usr/bin/openssl (LibreSSL) is used because launchd resolves it.

OPENSSL = "/usr/bin/openssl"
_ENC = ("enc", "-aes-256-cbc", "-pbkdf2", "-iter", "200000", "-salt", "-a")


def vault_key(item: str, account: str, create: bool = False) -> str:
    """The key for keychain item <item>/<account>; env CC_RESEARCH_VAULT_KEY overrides (tests)."""
    import secrets
    import subprocess
    env = os.environ.get("CC_RESEARCH_VAULT_KEY")
    if env:
        return env
    out = subprocess.run(("/usr/bin/security", "find-generic-password", "-s", item, "-a", account,
                          "-w"), capture_output=True, text=True)
    if out.returncode == 0 and out.stdout.strip():
        return out.stdout.strip()
    if not create:
        raise KitError(f"no keychain item {item}/{account}; nothing sealed under it can be read")
    key = secrets.token_hex(32)
    add = subprocess.run(("/usr/bin/security", "add-generic-password", "-s", item, "-a", account,
                          "-w", key), capture_output=True, text=True)
    if add.returncode != 0:
        raise KitError(f"cannot create keychain item {item}/{account}: {add.stderr.strip()}")
    return key


def encrypt(plaintext: bytes, key: str) -> bytes:
    import subprocess
    out = subprocess.run((OPENSSL,) + _ENC + ("-pass", "env:CC_KIT_K"), input=plaintext,
                         capture_output=True, env=dict(os.environ, CC_KIT_K=key))
    if out.returncode != 0:
        raise KitError(f"encrypt failed: {out.stderr.decode(errors='replace').strip()}")
    return out.stdout


def decrypt(ciphertext: bytes, key: str) -> bytes:
    import subprocess
    out = subprocess.run((OPENSSL,) + _ENC + ("-d", "-pass", "env:CC_KIT_K"), input=ciphertext,
                         capture_output=True, env=dict(os.environ, CC_KIT_K=key))
    if out.returncode != 0:
        raise KitError("decrypt failed: wrong key or corrupted vault")
    return out.stdout
