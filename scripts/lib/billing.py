#!/usr/bin/env python3
"""billing.py — three-key, time-aware account attribution for a Claude Code session.

Wave W2 of docs/plans/ZERO_HITL_ROTATION.md (spec: docs/research/midturn-account-move-2026-10-25/
REPORT.md §12 row W2, notes/SYNTHESIS.md §3.1 "attribution" and §3.8; the sites that will read it:
notes/I1-account-attribution-inventory.md). A session has three account keys, and today's code reads
the first one for all three:

  home(S)       the config dir the process runs under (its STORE: transcript, sessions/<pid>.json,
                the dir a --resume must use). Changes only at launch or re-home.
  billing(S,t)  the account whose bearer was on /v1/messages at time t. Limits, walls, burn and
                routing belong here. Read from the lane ledger, time-aware, because markers and
                transcripts are read after the fact.
  identity(S)   metadata.user_id.account_uuid, one of {home, billing, unknown}. Not observable on
                disk (SYNTHESIS §3.8), so this reader never asserts `billing`: after any move that
                changed billing away from home it is `unknown` until a re-home closes the mismatch.

`unknown` is a first-class value: nothing here defaults an unknown to home (invariant R5).

Kill switch CC_BILLING. Off (the default until wave W9 activates lanes) means billing == home and
identity == home, today's behavior, and the ledger is never opened. `CC_BILLING=1|on|true|yes`
turns it on, `0|off|false|no` forces it off; unset or empty defers to the switch file
`<lanes>/billing.on` (present = on). On, a session with no ledger row still bills home.

Ledger contract (written by wave W3's lr_lane/ledger.py, read only here): `<lanes>/ledger.jsonl`,
append-only, one JSON object per line:
  {t, lane, sid, pid, lstart, home, billing, prev_billing, cause, move_id, state, fp}
`t` is epoch seconds, epoch milliseconds or ISO-8601. `home`/`billing`/`prev_billing` are account
names (aliases and config dirs are folded). How each state moves billing(S,t):
  committed, proved, unproven, reverted, rehomed   billing := row.billing from row.t on
  aborted                                          billing := row.prev_billing (if present)
  prepared, anything else                          no effect
Before a session's first effective row, billing is that row's prev_billing (else home).

Paths (each overridable for tests): CC_LANES_DIR (~/.reso/lanes), CC_BILLING_LEDGER
(<lanes>/ledger.jsonl), CC_ACCOUNTS_JSON (~/.claude/accounts.json, then the repo's), CC_REGISTRY_DIR
(~/.claude/cc-registry).

CLI (also bin/cc-billing):
  billing.py --sid S [--at T] [--home ACCT|DIR] [--json | --field home|billing|identity]
  billing.py --billed-to ACCT [--at T] [--json]
  billing.py --mismatched [--at T] [--json]
  billing.py --status [--json]
Exit 0 on an answer (which may be `unknown`), 2 on usage error.
"""

import datetime
import glob
import json
import os
import sys
from typing import Any, Dict, Iterable, List, Optional, Tuple

ON_WORDS = ("1", "on", "true", "yes")
OFF_WORDS = ("0", "off", "false", "no")
UNKNOWN = "unknown"

# How a ledger state moves billing: "billing" = take row.billing, "prev" = take row.prev_billing.
STATE_EFFECT = {
    "committed": "billing",
    "proved": "billing",
    "unproven": "billing",
    "reverted": "billing",
    "rehomed": "billing",
    "aborted": "prev",
}
# States after which identity may no longer equal home (a lane carried another account's bearer).
MOVED_STATES = ("committed", "proved", "unproven", "reverted")

_HERE = os.path.dirname(os.path.realpath(__file__))


def _home_dir() -> str:
    return os.environ.get("HOME") or os.path.expanduser("~")


def lanes_dir() -> str:
    return os.environ.get("CC_LANES_DIR") or os.path.join(_home_dir(), ".reso", "lanes")


def ledger_path() -> str:
    return os.environ.get("CC_BILLING_LEDGER") or os.path.join(
        lanes_dir(), "ledger.jsonl"
    )


def switch_on() -> bool:
    """CC_BILLING env first; unset or empty defers to the switch file; default off."""
    v = (os.environ.get("CC_BILLING") or "").strip().lower()
    if v in ON_WORDS:
        return True
    if v in OFF_WORDS:
        return False
    return os.path.exists(os.path.join(lanes_dir(), "billing.on"))


def parse_t(v: Any) -> Optional[float]:
    """Epoch seconds from epoch s, epoch ms (> 1e12) or ISO-8601; None when unparseable."""
    if isinstance(v, bool) or v is None:
        return None
    if isinstance(v, (int, float)):
        f = float(v)
    elif isinstance(v, str):
        s = v.strip()
        try:
            f = float(s)
        except ValueError:
            try:
                d = datetime.datetime.fromisoformat(
                    s[:-1] + "+00:00" if s.endswith("Z") else s
                )
            except ValueError:
                return None
            if d.tzinfo is None:
                d = d.replace(tzinfo=datetime.timezone.utc)
            return d.timestamp()
    else:
        return None
    return f / 1000.0 if f > 1e12 else f


# ── accounts ─────────────────────────────────────────────────────────────────────────────────────


class Accounts:
    """Account names, their aliases and config dirs, from accounts.json (the SSOT)."""

    def __init__(self) -> None:
        self.dirs: Dict[str, str] = {}  # name -> absolute config dir
        self.alias: Dict[str, str] = {}  # any accepted spelling -> name
        home = _home_dir()
        cands = [
            os.environ.get("CC_ACCOUNTS_JSON")
            or os.path.join(home, ".claude", "accounts.json"),
            os.path.join(_HERE, "..", "..", "accounts.json"),
        ]
        rows: List[Any] = []
        for p in cands:
            try:
                with open(p, encoding="utf-8") as fh:
                    data = json.load(fh)
            except (OSError, ValueError):
                continue
            got = data.get("accounts") if isinstance(data, dict) else None
            if isinstance(got, list):
                rows = got
                break
        for a in rows:
            if not isinstance(a, dict):
                continue
            name, cfg = a.get("name"), a.get("config_dir")
            if not (isinstance(name, str) and name and isinstance(cfg, str) and cfg):
                continue
            cfg = os.path.normpath(home + cfg[1:] if cfg.startswith("~") else cfg)
            self.dirs[name] = cfg
            base = os.path.basename(cfg)
            spellings = [name, base, base.lstrip(".")]
            for k in ("launcher", "fable_name", "fable_launcher"):
                if isinstance(a.get(k), str):
                    spellings.append(a[k])
            if isinstance(a.get("aliases"), list):
                spellings += [x for x in a["aliases"] if isinstance(x, str)]
            for s in spellings:
                if s:
                    self.alias.setdefault(s, name)
        # `~/.claude` and the primary account's dir are ONE account (lr_recon invariant 24).
        prim = self.alias.get("claude")
        if prim:
            self.alias.setdefault(".claude", prim)

    def norm(self, x: Any) -> str:
        """Canonical account name for a name, alias, launcher, config dir or basename; '' if none."""
        if not isinstance(x, str) or not x.strip():
            return ""
        s = x.strip()
        if s in self.alias:
            return self.alias[s]
        if "/" in s or s.startswith("~"):
            s = os.path.basename(os.path.normpath(os.path.expanduser(s)))
            return self.alias.get(s) or self.alias.get(s.lstrip("."), "")
        return ""

    def stores(self) -> List[Tuple[str, str]]:
        """(name, config dir) per account, plus `~/.claude` for the primary account."""
        out = list(self.dirs.items())
        prim = self.alias.get(".claude")
        if prim:
            out.append((prim, os.path.join(_home_dir(), ".claude")))
        return out


# ── sources ──────────────────────────────────────────────────────────────────────────────────────


def read_ledger(
    path: Optional[str] = None,
) -> Tuple[Dict[str, List[Dict[str, Any]]], int]:
    """sid -> its rows in file order, each with `_t` (epoch s); and the count of skipped lines."""
    by_sid: Dict[str, List[Dict[str, Any]]] = {}
    bad = 0
    try:
        fh = open(path or ledger_path(), encoding="utf-8", errors="replace")
    except OSError:
        return by_sid, 0
    with fh:
        for line in fh:
            if not line.strip():
                continue
            try:
                row = json.loads(line)
            except ValueError:
                bad += 1
                continue
            t = parse_t(row.get("t")) if isinstance(row, dict) else None
            sid = row.get("sid") if isinstance(row, dict) else None
            if t is None or not isinstance(sid, str) or not sid:
                bad += 1
                continue
            row["_t"] = t
            by_sid.setdefault(sid, []).append(row)
    for rows in by_sid.values():
        rows.sort(key=lambda r: r["_t"])  # stable: file order breaks ties
    return by_sid, bad


def registry_rows() -> List[Dict[str, Any]]:
    d = os.environ.get("CC_REGISTRY_DIR") or os.path.join(
        _home_dir(), ".claude", "cc-registry"
    )
    out = []
    for p in glob.glob(os.path.join(d, "*.json")):
        try:
            with open(p, encoding="utf-8") as fh:
                row = json.load(fh)
        except (OSError, ValueError):
            continue
        if isinstance(row, dict):
            out.append(row)
    return out


# ── the API ──────────────────────────────────────────────────────────────────────────────────────


class Attribution:
    """One reader over one snapshot of the ledger, registry and accounts (load once, ask many)."""

    def __init__(self, ledger: Optional[str] = None, on: Optional[bool] = None) -> None:
        self.on = switch_on() if on is None else on
        self.accounts = Accounts()
        self.ledger_file = ledger or ledger_path()
        self.ledger_present = self.on and os.path.exists(self.ledger_file)
        self.rows, self.bad = (
            read_ledger(self.ledger_file) if self.ledger_present else ({}, 0)
        )
        self._registry: Optional[List[Dict[str, Any]]] = None

    def registry(self) -> List[Dict[str, Any]]:
        if self._registry is None:
            self._registry = registry_rows()
        return self._registry

    def home_of(self, sid: str, home: Optional[str] = None) -> Tuple[str, str]:
        """(account, source): the caller's own word, the live registry row, then the store holding
        the transcript (newest if several), then (switch on) the ledger's last `home`."""
        n = self.accounts.norm(home)
        if n:
            return n, "arg"
        best: Optional[Tuple[float, str]] = None
        for r in self.registry():
            if r.get("session_id") == sid:
                a = self.accounts.norm(r.get("account"))
                at = (
                    r.get("startedAt")
                    if isinstance(r.get("startedAt"), (int, float))
                    else 0
                )
                if a and (best is None or at > best[0]):
                    best = (float(at), a)
        if best:
            return best[1], "registry"
        hits = []
        for name, cfg in self.accounts.stores():
            for p in glob.glob(os.path.join(cfg, "projects", "*", sid + ".jsonl")):
                try:
                    hits.append((os.path.getmtime(p), name))
                except OSError:
                    pass
        if hits:
            return max(hits)[1], "transcript"
        for r in reversed(self.rows.get(sid, [])):
            a = self.accounts.norm(r.get("home"))
            if a:
                return a, "ledger"
        return UNKNOWN, ""

    def _acct(self, v: Any) -> str:
        return self.accounts.norm(v) or UNKNOWN

    def attribute(
        self, sid: str, at: Optional[float] = None, home: Optional[str] = None
    ) -> Dict[str, Any]:
        """All three keys for sid at time `at` (epoch s; None = now)."""
        h, hsrc = self.home_of(sid, home)
        out: Dict[str, Any] = {
            "sid": sid,
            "at": at,
            "home": h,
            "home_source": hsrc,
            "billing": h,
            "billing_source": "off",
            # An unknown home names no account, so identity cannot be "home" either (R5).
            "identity": UNKNOWN if h == UNKNOWN else "home",
            "identity_acct": None if h == UNKNOWN else h,
            "state": None,
            "move_id": None,
            "since": None,
            "switch": "on" if self.on else "off",
        }
        if not self.on:
            return out
        if not self.ledger_present:
            out["billing_source"] = "no-ledger"
            return out
        rows = [r for r in self.rows.get(sid, []) if at is None or r["_t"] <= at]
        eff = [r for r in rows if r.get("state") in STATE_EFFECT]
        if not eff:
            first = next(
                (r for r in self.rows.get(sid, []) if r.get("state") in STATE_EFFECT),
                None,
            )
            if first is not None and first.get("prev_billing") is not None:
                out["billing"] = self._acct(first.get("prev_billing"))
                out["billing_source"] = "ledger-pre"
            else:
                out["billing_source"] = "no-row"
        else:
            last = eff[-1]
            # An abort that names no previous billing says nothing: the row before it decides. A
            # moving row that names no billing is `unknown` (R5), never the row before it.
            val: Any = h
            for r in reversed(eff):
                if STATE_EFFECT[r["state"]] == "billing":
                    val = self._acct(r.get("billing"))
                    break
                if r.get("prev_billing") is not None:
                    val = self._acct(r.get("prev_billing"))
                    break
            out["billing"] = val
            out.update(
                billing_source="ledger",
                state=last["state"],
                move_id=last.get("move_id"),
                since=last["_t"],
            )
        # identity: home until a move put another account's bearer on the wire; a re-home closes it.
        tail = rows
        for i in range(len(rows) - 1, -1, -1):
            if rows[i].get("state") == "rehomed":
                tail = rows[i + 1 :]
                break
        moved = any(
            r.get("state") in MOVED_STATES and self._acct(r.get("billing")) != h
            for r in tail
        )
        if moved or out["billing"] == UNKNOWN:
            out["identity"], out["identity_acct"] = UNKNOWN, None
        return out

    def billing_of(
        self, sid: str, at: Optional[float] = None, home: Optional[str] = None
    ) -> str:
        return self.attribute(sid, at, home)["billing"]

    def identity_of(
        self, sid: str, at: Optional[float] = None, home: Optional[str] = None
    ) -> str:
        return self.attribute(sid, at, home)["identity"]

    def census(self, sids: Optional[Iterable[str]] = None) -> List[str]:
        if sids is not None:
            return sorted(set(sids))
        reg = [r.get("session_id") for r in self.registry()]
        return sorted(set(self.rows) | {s for s in reg if isinstance(s, str) and s})

    def sessions_billed_to(
        self,
        acct: str,
        at: Optional[float] = None,
        sids: Optional[Iterable[str]] = None,
    ) -> List[str]:
        """Sessions whose billing at `at` is acct, over `sids` (default: ledger ∪ registry sids)."""
        want = self.accounts.norm(acct) or acct
        return [s for s in self.census(sids) if self.billing_of(s, at) == want]

    def mismatched(self, at: Optional[float] = None) -> List[Dict[str, Any]]:
        """Ledger sessions whose billing at `at` is a known account other than their home."""
        out = []
        for s in sorted(self.rows):
            a = self.attribute(s, at)
            if a["billing"] not in (UNKNOWN, a["home"]):
                out.append(a)
        return out


# Module-level conveniences: each builds a fresh snapshot.
def billing_of(sid: str, at: Optional[float] = None, home: Optional[str] = None) -> str:
    return Attribution().billing_of(sid, at, home)


def home_of(sid: str, home: Optional[str] = None) -> str:
    return Attribution().home_of(sid, home)[0]


def identity_of(
    sid: str, at: Optional[float] = None, home: Optional[str] = None
) -> str:
    return Attribution().identity_of(sid, at, home)


def sessions_billed_to(acct: str, at: Optional[float] = None) -> List[str]:
    return Attribution().sessions_billed_to(acct, at)


def mismatched(at: Optional[float] = None) -> List[Dict[str, Any]]:
    return Attribution().mismatched(at)


# ── CLI ──────────────────────────────────────────────────────────────────────────────────────────

USAGE = """usage: cc-billing --sid S [--at T] [--home ACCT|DIR] [--json | --field home|billing|identity]
       cc-billing --billed-to ACCT [--at T] [--json]
       cc-billing --mismatched [--at T] [--json]
       cc-billing --status [--json]
T is epoch seconds, epoch ms or ISO-8601. Switch: CC_BILLING (default off = billing is home)."""


def _usage(msg: str) -> int:
    sys.stderr.write("cc-billing: %s\n%s\n" % (msg, USAGE))
    return 2


def main(argv: List[str]) -> int:
    opts: Dict[str, Any] = {}
    flags = ("--json", "--mismatched", "--status")
    valued = ("--sid", "--at", "--home", "--field", "--billed-to")
    i = 0
    while i < len(argv):
        a = argv[i]
        if a in ("-h", "--help"):
            sys.stdout.write(USAGE + "\n")
            return 0
        if a in flags:
            opts[a] = True
        elif a in valued:
            if i + 1 >= len(argv):
                return _usage("%s needs a value" % a)
            opts[a] = argv[i + 1]
            i += 1
        else:
            return _usage("unknown argument: %s" % a)
        i += 1
    modes = [
        m for m in ("--sid", "--billed-to", "--mismatched", "--status") if m in opts
    ]
    if len(modes) != 1:
        return _usage("give exactly one of --sid, --billed-to, --mismatched, --status")
    at = None
    if "--at" in opts:
        at = parse_t(opts["--at"])
        if at is None:
            return _usage("unparseable --at: %s" % opts["--at"])
    field = opts.get("--field")
    if field is not None and (
        field not in ("home", "billing", "identity") or modes[0] != "--sid"
    ):
        return _usage("--field takes home|billing|identity, with --sid only")
    as_json = bool(opts.get("--json"))
    A = Attribution()
    if modes[0] == "--sid":
        sid = opts["--sid"]
        if not sid:
            return _usage("--sid is empty")
        r = A.attribute(sid, at, opts.get("--home"))
        if field:
            print(r[field])
        elif as_json:
            print(json.dumps(r, sort_keys=True))
        else:
            print(
                "%s home=%s billing=%s identity=%s source=%s switch=%s"
                % (
                    sid,
                    r["home"],
                    r["billing"],
                    r["identity"],
                    r["billing_source"],
                    r["switch"],
                )
            )
    elif modes[0] == "--billed-to":
        if not A.accounts.norm(opts["--billed-to"]):
            return _usage("unknown account: %s" % opts["--billed-to"])
        sids = A.sessions_billed_to(opts["--billed-to"], at)
        print(json.dumps(sids) if as_json else "\n".join(sids))
    elif modes[0] == "--mismatched":
        rows = A.mismatched(at)
        if as_json:
            print(json.dumps(rows, sort_keys=True))
        else:
            for r in rows:
                print(
                    "%s home=%s billing=%s since=%s"
                    % (r["sid"], r["home"], r["billing"], r["since"])
                )
    else:
        st = {
            "switch": "on" if A.on else "off",
            "ledger": A.ledger_file,
            "ledger_present": A.ledger_present,
            "sessions": len(A.rows),
            "bad_rows": A.bad,
            "accounts": sorted(A.accounts.dirs),
        }
        if as_json:
            print(json.dumps(st, sort_keys=True))
        else:
            print(" ".join("%s=%s" % (k, st[k]) for k in sorted(st)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
