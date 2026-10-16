"""rehearse_trial.py — one relay trial of the rehearsal (REPORT.md §3.8 "The relay test"), behind
`cc-research rehearse trial --program P --phrase TEXT [--where root|outside] [--name N]`.

"A session loaded with your full resident instructions is asked your literal phrasings 20 times ...
At least one trial is asked from a pane outside the program's directory, naming the program by its
registered name or alias." A trial is that session: a fresh kitty tab running the operator's own
`claude` launcher (an interactive login zsh, so the resident instructions, hooks and router all load),
started with `claude --session-id <uuid> <phrase>`. The phrase is the pane's FIRST and ONLY prompt, so
the router classifies it as a genuine prompt: no HANDOFF-ENGAGE marker, no back-channel block, no
`Goal set:` line, no brief. That is the path handoff-fire.sh cannot give (every fresh fire embeds
HANDOFF-ENGAGE, which router.MACHINE_ENVELOPE reads as a machine envelope), and why handoff-fire.sh
stays denied under the rehearsal tag while this verb is admitted.

Fixed inputs, so the verb cannot mint a worker of the caller's choosing:
  - the phrase is one of RELAY_PHRASES (§3.8's four, verbatim) or a reask_map frame with an axis;
  - the cwd is the program's first registered cwd_root (`root`), or OUTSIDE, this kit's own checkout
    (`outside`), refused if it lies inside any root of the program;
  - only an `outside` trial carries a suffix, naming the program by its slug or a registered alias.

The orchestrator, not the trial pane, collects the result: the verb waits for the pane's turn to end
(including any Stop-check block), reads the transcript from the pane's CLAUDE_CONFIG_DIR (pinned on the
launch, so the launcher's account routing cannot move it), takes the label from the router's own
route-state record, closes the pane from outside, and appends one row to
<records>/evidence/rehearsal/trials-<attempt>.jsonl — the file `rehearse record` reads by default.
A trial pane is never asked to report, notify or close itself: each would be a tool call the relay
test forbids.

Exempt from the program lease (lib/cli.py LEASE_EXEMPT): it writes no record, only its evidence file,
and 20 trials under the lease would hold the scheduled writers off for an hour. Python 3.9-safe.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import time
import uuid
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

import kit

# REPORT.md §3.8, verbatim: the operator's literal re-ask phrasings.
RELAY_PHRASES = (
    "Are you sure?",
    "Is this all before we close?",
    "no take-backs?",
    "if more research moves your conviction, do it now",
)
RELAY_TRIALS = 20
RELAY_LABELS = ("completeness", "pushback")
# The fixed outside cwd: this kit's own checkout, where the operator's other panes live.
OUTSIDE = Path(__file__).resolve().parents[3]
SHELL = "/bin/zsh"
LAUNCH_TIMEOUT_S = 30


def env_float(name: str, default: float) -> float:
    try:
        return float(os.environ.get(name) or default)
    except ValueError:
        return default


def phrases(slug: str) -> List[str]:
    """The phrases a trial may type: §3.8's four, then the frame's reask_map frames with an axis."""
    fr = kit.read_json(kit.records_dir(slug) / "frame.json", {}) or {}
    frames = [
        str(m["frame"])
        for m in fr.get("reask_map") or []
        if m.get("axis") and m.get("frame")
    ]
    return list(RELAY_PHRASES) + [f for f in frames if f not in RELAY_PHRASES]


def roots(slug: str) -> List[str]:
    return [
        os.path.realpath(r)
        for r in (kit.registry_get(slug) or {}).get("cwd_roots") or []
    ]


def inside(path: str, rs: List[str]) -> bool:
    p = os.path.realpath(path)
    return any(p == r or p.startswith(r + os.sep) for r in rs)


def trial_cwd(slug: str, where: str) -> str:
    rs = roots(slug)
    if not rs:
        raise kit.KitError(f"program {slug!r} has no registered cwd_roots")
    if where == "root":
        return rs[0]
    out = os.path.realpath(str(OUTSIDE))
    if inside(out, rs):
        raise kit.KitError(
            f"the fixed outside cwd {out} lies inside a cwd_root of {slug}; no outside trial can run"
        )
    return out


def names(slug: str) -> List[str]:
    return [slug] + [
        str(x) for x in (kit.registry_get(slug) or {}).get("aliases") or []
    ]


def attempt_of(slug: str) -> int:
    """1 for the first record, 2 for the re-test; refused once the relay test is settled."""
    hist = kit.read_jsonl(kit.records_dir(slug) / "rehearsal.jsonl")
    if any(h.get("passed") for h in hist):
        raise kit.KitError("the relay test already passed; no trial is owed")
    if len(hist) >= 2:
        raise kit.KitError(
            "the relay test used its one repair and one re-test; no trial is owed"
        )
    return len(hist) + 1


def trials_path(slug: str, attempt: int) -> Path:
    return kit.records_dir(slug) / "evidence" / "rehearsal" / f"trials-{attempt}.jsonl"


def config_dir() -> Path:
    return Path(os.environ.get("CLAUDE_CONFIG_DIR") or (Path.home() / ".claude"))


def trusted(cfg: Path, cwd: str) -> Optional[bool]:
    """Whether the pane's account has accepted the folder-trust dialog for cwd or a parent (None:
    unknown). An untrusted folder holds the trial on a dialog until its timeout."""
    for p in (cfg / ".claude.json", Path.home() / ".claude.json"):
        try:
            projects = json.loads(p.read_text()).get("projects") or {}
        except (OSError, ValueError, AttributeError):
            continue
        d = Path(cwd)
        for x in [d] + list(d.parents):
            if (projects.get(str(x)) or {}).get("hasTrustDialogAccepted"):
                return True
        return False
    return None


def kitty() -> Tuple[str, List[str]]:
    """(binary, the `--to` args): CC_TERM_KITTY / CC_TERM_KITTY_TO win, as in bin/it2-kitty."""
    b = os.environ.get("CC_TERM_KITTY") or shutil.which("kitty") or ""
    if not b and os.access("/Applications/kitty.app/Contents/MacOS/kitty", os.X_OK):
        b = "/Applications/kitty.app/Contents/MacOS/kitty"
    if not b or not os.access(b, os.X_OK):
        raise kit.KitError(
            "no kitty binary (set CC_TERM_KITTY): a trial runs in a kitty tab"
        )
    to = os.environ.get("CC_TERM_KITTY_TO") or os.environ.get("KITTY_LISTEN_ON") or ""
    if not to:
        raise kit.KitError(
            "no kitty control socket (set CC_TERM_KITTY_TO; bin/cc-kitty-socket prints it)"
        )
    return b, ["--to", to]


def launch_argv(
    b: str, to: List[str], cwd: str, cfg: Path, sid: str, prompt: str, title: str
) -> List[str]:
    """The bare pane: a new tab, focus kept, CLAUDE_CONFIG_DIR pinned (an explicit --env wins over
    kitty's own environment, so the launcher reads it as pinned and never re-routes the account),
    and the phrase as claude's initial prompt — passed as an argument, never typed by send-text."""
    return [
        b,
        "@",
        *to,
        "launch",
        "--type=tab",
        "--keep-focus",
        f"--cwd={cwd}",
        "--env",
        f"CLAUDE_CONFIG_DIR={cfg}",
        f"--title={title}",
        "--",
        os.environ.get("CC_RESEARCH_TRIAL_SHELL") or SHELL,
        "-ilc",
        'claude --session-id "$1" "$2"',
        "relay-trial",
        sid,
        prompt,
    ]


def text_of(content: Any) -> str:
    if isinstance(content, str):
        return content
    return "\n".join(
        str(c.get("text") or "")
        for c in content or []
        if isinstance(c, dict) and c.get("type") == "text"
    )


def parse(path: Path, prompt: str) -> Dict[str, Any]:
    """The turn the prompt opened: every reply text, every tool call (a Bash command verbatim, any
    other tool by name), whether a tool call is still unanswered, and whether the turn has a reply."""
    recs = []
    for ln in path.read_text(errors="replace").splitlines():
        try:
            r = json.loads(ln)
        except ValueError:
            continue  # a line still being written
        if isinstance(r, dict) and not r.get("isSidechain"):
            recs.append(r)
    asks = [
        (i, text_of((r.get("message") or {}).get("content")).strip())
        for i, r in enumerate(recs)
        if r.get("type") == "user" and not r.get("isMeta")
    ]
    # the prompt verbatim; else the first user text carrying it (a client that wraps it)
    start = next((i for i, t in asks if t == prompt), None)
    if start is None:
        start = next((i for i, t in asks if prompt in t), None)
    out: Dict[str, Any] = {
        "seen": start is not None,
        "replies": [],
        "tools": [],
        "pending": False,
        "last": None,
    }
    if start is None:
        return out
    asked, answered = set(), set()
    for r in recs[start + 1 :]:
        msg = r.get("message") or {}
        content = msg.get("content")
        if r.get("type") == "assistant":
            out["last"] = "assistant"
            t = text_of(content).strip()
            if t:
                out["replies"].append(t)
            for c in content if isinstance(content, list) else []:
                if isinstance(c, dict) and c.get("type") == "tool_use":
                    asked.add(c.get("id"))
                    inp = c.get("input") or {}
                    out["tools"].append(
                        str(inp.get("command"))
                        if c.get("name") == "Bash"
                        else str(c.get("name"))
                    )
        elif r.get("type") == "user":
            out["last"] = "user"
            for c in content if isinstance(content, list) else []:
                if isinstance(c, dict) and c.get("type") == "tool_result":
                    answered.add(c.get("tool_use_id"))
    out["pending"] = bool(asked - answered)
    return out


def transcript(cfg: Path, sid: str) -> Optional[Path]:
    hits = sorted((cfg / "projects").glob(f"*/{sid}.jsonl"))
    return hits[0] if hits else None


def wait(
    cfg: Path, sid: str, prompt: str, timeout: float
) -> Tuple[Optional[Path], Dict[str, Any], bool]:
    """Poll until the turn has ended: a reply, no unanswered tool call, the last record the
    assistant's, and the transcript unchanged for the settle time (a Stop-check block writes on, so
    it extends the wait). (transcript, parse, timed_out)."""
    settle = env_float("CC_RESEARCH_TRIAL_SETTLE_S", 20.0)
    poll = env_float("CC_RESEARCH_TRIAL_POLL_S", 1.0)
    end = time.monotonic() + timeout
    path: Optional[Path] = None
    got: Dict[str, Any] = {"seen": False, "replies": [], "tools": [], "pending": False}
    while True:
        path = path or transcript(cfg, sid)
        if path:
            got = parse(path, prompt)
            quiet = time.time() - path.stat().st_mtime >= settle
            if (
                got["replies"]
                and not got["pending"]
                and got["last"] == "assistant"
                and quiet
            ):
                return path, got, False
        if time.monotonic() >= end:
            return path, got, True
        time.sleep(poll)


def route_of(sid: str) -> Dict[str, Any]:
    return kit.read_json(kit.research_home() / "route-state" / f"{sid}.json", {}) or {}


def close(b: str, to: List[str], wid: str) -> bool:
    try:
        p = subprocess.run(
            [b, "@", *to, "close-window", "--match", f"id:{wid}"],
            capture_output=True,
            text=True,
            timeout=LAUNCH_TIMEOUT_S,
        )
    except (OSError, subprocess.TimeoutExpired):
        return False
    return p.returncode == 0


def append(path: Path, row: Dict[str, Any]) -> int:
    """Number and append the row under a lock, so parallel trials never share a number; refused past
    the relay test's 20."""
    with kit.mkdir_lock(
        path.with_name(path.name + ".lock"), "trials", "rehearse trial"
    ):
        n = len(kit.read_jsonl(path))
        if n >= RELAY_TRIALS:
            raise kit.KitError(
                f"{path} already holds {n} trials; the relay test is {RELAY_TRIALS}"
            )
        row["trial"] = n + 1
        kit.append_jsonl(path, row)
    return n + 1


def cmd_trial(a: argparse.Namespace) -> int:
    slug = a.program
    state = (kit.registry_get(slug) or {}).get("state")
    if state != "certifying":
        raise kit.KitError(
            f"rehearse trial refused: {slug} is {state!r}; the relay test runs while certifying, "
            "with the research block on"
        )
    import activities

    if not activities.open_ids(slug, activities.REHEARSAL):
        raise kit.KitError(
            f"rehearse trial refused: no open rehearsal activity (gate.sh rehearsal-activity "
            f"--program {slug} opens it after the stop)"
        )
    allowed = phrases(slug)
    phrase = (a.phrase or "").strip()
    if phrase not in allowed:
        raise kit.KitError(
            f"rehearse trial refused: {a.phrase!r} is not a fixed phrasing; one of: "
            + " | ".join(allowed)
        )
    if a.where == "root" and a.name:
        raise kit.KitError(
            "rehearse trial refused: only an outside trial names the program"
        )
    prompt = phrase
    if a.where == "outside":
        name = (
            a.name or (names(slug)[1:] or [slug])[0]
        )  # the first alias: how the operator names it
        if name not in names(slug):
            raise kit.KitError(
                f"rehearse trial refused: --name {name!r} is not {slug}'s slug or a registered alias"
            )
        prompt = f"{phrase} (about the research program {name})"
    attempt = attempt_of(slug)
    out = trials_path(slug, attempt)
    if len(kit.read_jsonl(out)) >= RELAY_TRIALS:
        raise kit.KitError(
            f"{out} already holds {RELAY_TRIALS} trials; run rehearse record"
        )
    cwd = trial_cwd(slug, a.where)
    cfg = config_dir()
    if trusted(cfg, cwd) is False:
        raise kit.KitError(
            f"rehearse trial refused: {cfg} has not trusted {cwd}; open claude there once on that "
            "account, or the trial waits on the trust dialog until its timeout"
        )
    b, to = kitty()
    sid = str(uuid.uuid4())
    import router

    # Before the pane starts, so its first prompt is already routed as a trial (router.trial_mark).
    router.trial_mark(sid, slug, attempt=attempt, phrase=phrase, where=a.where)
    argv = launch_argv(b, to, cwd, cfg, sid, prompt, f"relay-trial {slug} {sid[:8]}")
    try:
        p = subprocess.run(
            argv, capture_output=True, text=True, timeout=LAUNCH_TIMEOUT_S
        )
    except (OSError, subprocess.TimeoutExpired) as e:
        raise kit.KitError(f"rehearse trial: kitty launch failed ({e})") from e
    wid = p.stdout.strip().splitlines()[-1].strip() if p.stdout.strip() else ""
    if p.returncode != 0 or not wid.isdigit():
        raise kit.KitError(
            f"rehearse trial: kitty launch failed (rc {p.returncode}): {p.stderr.strip()[:300]}"
        )
    try:
        path, got, timed_out = wait(cfg, sid, prompt, float(a.timeout))
        route = route_of(sid)
    finally:
        closed = close(b, to, wid)
    row = {
        "prompt": prompt,
        "phrase": phrase,
        "where": a.where,
        "cwd": cwd,
        "reply": "\n".join(got["replies"]),
        "replies": got["replies"],
        "tools": got["tools"],
        "label": route.get("label"),
        "trial_routed": bool(route.get("trial")),
        "session_id": sid,
        "config_dir": str(cfg),
        "transcript": str(path) if path else None,
        "window_id": wid,
        "closed": closed,
        "timed_out": timed_out,
        "attempt": attempt,
        "at": kit.now_iso(),
    }
    n = append(out, row)
    print(
        json.dumps(
            {
                "trial": n,
                "file": str(out),
                "label": route.get("label"),
                "timed_out": timed_out,
                "closed": closed,
                "session_id": sid,
            }
        )
    )
    if timed_out:
        print(
            f"rehearse trial {n}: the turn did not end within {a.timeout} s",
            file=sys.stderr,
        )
    return 1 if timed_out else 0
