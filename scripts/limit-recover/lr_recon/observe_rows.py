"""Registry, session-row, resume-argv and background-work readers for the census (§C3.4-5, §C3.7).

Split out of observe.py so each stays under 400 LOC. Everything here is a pure function of the one
``ps`` read plus the JSON rows on disk: nothing re-runs ps, and a row that fails to parse is skipped
by SHAPE rather than raising, because a peer-token file or a half-written row sits beside the real
ones in the same directory (§C3.5).
"""

from __future__ import annotations

import glob
import json
import os
import re
from typing import Any, Callable, Dict, Iterable, List, Optional, Set, Tuple

from lr_recon import types as T

# The five config dirs a claude can run under; `.claude` and `.claude-next` are ONE account (inv. 24).
CFG_DIRS = (
    ".claude",
    ".claude-next",
    ".claude-secondary",
    ".claude-tertiary",
    ".claude-quaternary",
)
CLAUDE_BINS = ("claude", "claude.exe")
SHELLS = ("zsh", "bash", "fish", "sh")
_SID_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{3,}$")
_UUID_RE = re.compile(
    r"[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}"
)
_HOST_RE = re.compile(r'"pid"\s*:\s*(\d+)')

GlobFn = Callable[[str], List[str]]


def argv0(args: str) -> str:
    """Basename of argv[0], login-dash stripped (`-zsh` is a zsh)."""
    head = args.split(None, 1)[0] if args.strip() else ""
    return os.path.basename(head).lstrip("-")


def is_claude(args: str) -> bool:
    """A claude CLI: the `claude` wrapper, its `claude.exe` leaf, or node running a claude cli.js."""
    b = argv0(args)
    if b in CLAUDE_BINS:
        return True
    return b.startswith("node") and any(
        "claude" in t and t.endswith("cli.js") for t in args.split()[1:]
    )


def load_json(path: str) -> Optional[Any]:
    """One JSON file, or None on any read/parse failure (a torn row is skipped, never raised)."""
    try:
        with open(path, "r", encoding="utf-8") as fh:
            return json.load(fh)
    except (OSError, ValueError):
        return None


def live(pid: Any, procs: Dict[int, T.ProcRow]) -> Optional[T.ProcRow]:
    """The ps row for ``pid`` when it is an int, present and not a zombie (§10 #12)."""
    if not isinstance(pid, int) or isinstance(pid, bool):
        return None
    row = procs.get(pid)
    return row if row is not None and not row.zombie else None


# ── accounts (invariant 24) ──────────────────────────────────────────────────────────────────────


def acct_cfg_map(home: str) -> Dict[str, str]:
    """Account name → absolute config dir, from ``~/.claude/accounts.json`` (`{} ` if unreadable)."""
    data = load_json(os.path.join(home, ".claude", "accounts.json"))
    out: Dict[str, str] = {}
    rows = data.get("accounts") if isinstance(data, dict) else None
    for a in rows if isinstance(rows, list) else []:
        if not isinstance(a, dict):
            continue
        name, cfg = a.get("name"), a.get("config_dir")
        if isinstance(name, str) and isinstance(cfg, str) and name and cfg:
            if cfg.startswith("~"):
                cfg = home + cfg[1:]
            out[name] = os.path.normpath(cfg)
    return out


def acct_of_cfg(cfg: str, amap: Dict[str, str]) -> str:
    """The folded account name for a config dir: `.claude` resolves as `.claude-next` (inv. 24)."""
    if not cfg:
        return ""
    norm = os.path.normpath(cfg)
    if os.path.basename(norm) == ".claude":
        norm = os.path.join(os.path.dirname(norm), ".claude-next")
    for name, d in amap.items():
        if d == norm:
            return name
    return ""


def registry_cfg(account: str, home: str, amap: Dict[str, str]) -> str:
    """A registry ``account`` (`claude-secondary`, a dir basename sans dot, or an account name)."""
    if not account:
        return ""
    if account in amap:
        return amap[account]
    base = account if account.startswith(".") else "." + account
    return os.path.join(home, base) if base in CFG_DIRS else ""


# ── rows ─────────────────────────────────────────────────────────────────────────────────────────


def read_registry(reg_dir: str, glob_fn: GlobFn = glob.glob) -> List[Dict[str, Any]]:
    """Registry rows that are dicts carrying a session_id; the row's own lstart is ignored (local TZ)."""
    rows = []
    for f in sorted(glob_fn(os.path.join(reg_dir, "*.json"))):
        d = load_json(f)
        if (
            isinstance(d, dict)
            and isinstance(d.get("session_id"), str)
            and d["session_id"]
        ):
            rows.append(d)
    return rows


def read_session_rows(
    home: str, procs: Dict[int, T.ProcRow], glob_fn: GlobFn = glob.glob
) -> List[Tuple[str, Dict[str, Any]]]:
    """(cfg, row) for each `<cfg>/sessions/*.json` dict with a sessionId and a LIVE int pid (§C3.5)."""
    out = []
    for name in CFG_DIRS:
        cfg = os.path.join(home, name)
        for f in sorted(glob_fn(os.path.join(cfg, "sessions", "*.json"))):
            d = load_json(f)
            if not isinstance(d, dict) or not isinstance(d.get("sessionId"), str):
                continue
            if d["sessionId"] and live(d.get("pid"), procs) is not None:
                out.append((cfg, d))
    return out


def is_iterm(row: Dict[str, Any]) -> bool:
    """An iTerm2 surface: its paneUUID carries a UUID (kitty rows carry a window id)."""
    return (
        bool(_UUID_RE.search(str(row.get("paneUUID") or "")))
        or "iterm" in str(row.get("surface") or "").lower()
    )


# ── process tree ─────────────────────────────────────────────────────────────────────────────────


def children_map(procs: Dict[int, T.ProcRow]) -> Dict[int, List[int]]:
    kids: Dict[int, List[int]] = {}
    for r in procs.values():
        if not r.zombie:
            kids.setdefault(r.ppid, []).append(r.pid)
    return kids


def ancestors(pid: int, procs: Dict[int, T.ProcRow], limit: int = 64) -> Iterable[int]:
    """Strict ancestors of ``pid`` up to launchd; cycle- and depth-bounded."""
    seen: Set[int] = {pid}
    p = pid
    for _ in range(limit):
        row = procs.get(p)
        if row is None or row.ppid in seen or row.ppid <= 0:
            return
        p = row.ppid
        seen.add(p)
        yield p


def descendants(pid: int, kids: Dict[int, List[int]], limit: int = 512) -> List[int]:
    out: List[int] = []
    stack = list(kids.get(pid, []))
    while stack and len(out) < limit:
        c = stack.pop()
        if c in out:
            continue
        out.append(c)
        stack.extend(kids.get(c, []))
    return out


def resume_sid(args: str) -> str:
    """The sid after `--resume` (or `--resume=`), or ""."""
    toks = args.split()
    for i, t in enumerate(toks):
        cand = ""
        if t == "--resume" and i + 1 < len(toks):
            cand = toks[i + 1]
        elif t.startswith("--resume="):
            cand = t[len("--resume=") :]
        if cand and _SID_RE.match(cand):
            return cand
    return ""


def resume_leaves(procs: Dict[int, T.ProcRow]) -> Dict[str, List[int]]:
    """sid → live pids carrying `--resume <sid>`, minus any wrapper whose descendant carries it too."""
    by_sid: Dict[str, List[int]] = {}
    for r in procs.values():
        if r.zombie:
            continue
        sid = resume_sid(r.args)
        if sid:
            by_sid.setdefault(sid, []).append(r.pid)
    out: Dict[str, List[int]] = {}
    for sid, pids in by_sid.items():
        wrappers: Set[int] = set()
        for p in pids:
            wrappers.update(a for a in ancestors(p, procs) if a in pids)
        out[sid] = sorted(p for p in pids if p not in wrappers)
    return out


# ── background work (§C3.7; port of lr-upgrade.sh lru_bg_kind / lru_bg_host_pid) ─────────────────


def bg_host_pid(pid: int, procs: Dict[int, T.ProcRow]) -> int:
    """The claude that spawned a bg session's daemon: `daemon run … --spawned-by {"pid":N}` ≤4 up."""
    for i, a in enumerate(ancestors(pid, procs)):
        if i >= 4:
            break
        args = procs[a].args
        if " daemon run " in args and "--spawned-by" in args:
            m = _HOST_RE.search(args.split("--spawned-by", 1)[1])
            return int(m.group(1)) if m else 0
    return 0


def bg_work_for(
    claude_pids: Iterable[int],
    procs: Dict[int, T.ProcRow],
    kids: Dict[int, List[int]],
    bg_rows: List[Tuple[int, T.ProcRow]],
) -> List[T.BgWork]:
    """Raw background-work findings for one session; the at-rest gate is the caller's.

    A harness background shell is a DIRECT child zsh/bash whose args carry `shell-snapshots`; a
    hook's `bash` child has none, and the naive any-shell-child rule adds 4/20 false positives (W0).
    """
    out: List[T.BgWork] = []
    cps = set(claude_pids)
    for c in sorted(cps):
        for j in sorted(kids.get(c, [])):
            r = procs[j]
            if argv0(r.args) not in ("zsh", "bash") or "shell-snapshots" not in r.args:
                continue
            desc = descendants(j, kids)
            watcher = "cc-await-ping" in r.args and all(
                "cc-await-ping" in procs[k].args
                for k in kids.get(j, [])
                if argv0(procs[k].args) != "tail"
            )
            ship = "ship-land" in r.args or any(
                "ship-land" in procs[d].args for d in desc
            )
            out.append(T.BgWork("shell", j, r.lstart, r.args, watcher, ship))
    for host, row in bg_rows:
        if host in cps:
            out.append(T.BgWork("bg-row", row.pid, row.lstart, row.args))
    return out


# ── C3.2, C3.5: pane binding and the holder set ───────────────────────────────────────────────


def bind(
    pid: int, procs: Dict[int, T.ProcRow], roots: Dict[int, Tuple[int, int]]
) -> Optional[Tuple[int, int]]:
    """(kitty_pid, window_id) by walking the ppid chain to a window root — never by tty (§C3.2)."""
    if pid in roots:
        return roots[pid]
    for a in ancestors(pid, procs):
        if a in roots:
            return roots[a]
    return None


def holders_for(
    sources: List[Tuple[str, str, int, str]],
    procs: Dict[int, T.ProcRow],
    roots: Dict[int, Tuple[int, int]],
) -> List[T.HolderObs]:
    """H(sid): distinct live (pid, lstart); a later source only fills an unknown cfg (§C3.5)."""
    held: Dict[Tuple[int, str], T.HolderObs] = {}
    for src, cfg, pid, kind in sources:
        row = live(pid, procs)
        if row is None:
            continue
        key = (row.pid, row.lstart)
        if key in held:
            held[key].cfg = held[key].cfg or cfg
            continue
        held[key] = T.HolderObs(
            row.pid,
            row.lstart,
            cfg,
            src,
            kind,
            kind == "bg",
            bind(row.pid, procs, roots),
        )
    return list(held.values())
