#!/usr/bin/env python3
"""router.py — the re-ask router, the research block and the relay check (wave B1).

REPORT.md §4.1 (routing by program state), §4.2 (the tool block), §4.4 (the Stop check); §8 items 5
and 6; §10 open items 1 (deny half), 2, 3, 8 and 11-13. Path:
  docs/research/upfront-research-exhaustion-2026-09-30/REPORT.md

Three hooks call it, each through a thin bash wrapper that does the fast registry resolution with
scripts/lib/research-program.sh (wave A1's resolver, the one key every exemption shares):

  router.py classify [--program P]
      Gate row 15's contract (heldout.py `route()`): the prompt on stdin, ONE label on stdout. Point
      CC_RESEARCH_ROUTER at `<repo>/scripts/research-kit/router.py classify` to measure it.
  router.py prompt --program P --state S --by cwd|prompt     (hooks/research-precognition-nudge.sh)
      UserPromptSubmit. Classifies a genuine prompt, records the turn's label for this session and
      prints the hook's JSON. `router.py prompt --clear` forgets the session's route (no program).
      A machine-envelope FIRST prompt (no route record yet) is labeled without the classifier and
      recorded `by: envelope`: work-order on a --requires-gate marker, else a named predecessor's
      non-relayed label, else other.
  router.py tool [--program P]                               (hooks/research-block.sh)
      PreToolUse. Prints a deny, or nothing (allow).
  router.py relay-check --session SID                        (hooks/completion-assert.sh)
      Stop. The reply on stdin; prints the block reason and exits 1 when a completeness or pushback
      reply names something the relayed certificate does not carry.
  router.py status --session SID                             the session's route record, as JSON

LABELS are exactly heldout.ROUTES, plus `unavailable` for a classifier that errored, timed out or
answered outside the list (§10 item 3: that is NOT a completeness label — it denies only the
research verbs, and the next genuine prompt is classified afresh). A prompt carrying the
`--requires-gate <program>` work-order marker is labeled work-order without calling the classifier.
A machine-envelope prompt (a fired or recycled successor's brief) is never classified: it keeps the
session's last label, or, as the session's FIRST prompt, gets a deterministic `by: envelope` label
(envelope_label) so a successor is not left unlabeled, which would deny it every tool.

THE ROUTE RECORD, one per session: $CC_RESEARCH_HOME/route-state/<sid>.json
  {program, state, by, label, cert, reason, at, prompt_sha, fallbacks}
It is pre-written as `unavailable` before the classifier runs, so a hook killed at its timeout
leaves the research-verb deny in force, never a stale label from an earlier turn.

OPEN ACTIVITIES (§10 item 8), read here and written by triage or the kit (wave C):
  $CC_RESEARCH_HOME/activities.json  {"activities":[{"program","id","kind","state":"open"}]}
A Bash clause carrying `CC_RESEARCH_ACTIVITY=<open id>` that runs round.sh --delta or courier.sh,
or an Agent call whose description or prompt carries `[activity:<open id>]`, is allowed through the
research-verb deny. The registry cannot hold these: kit.registry_set keeps only its four keys.

KILL SWITCHES (operator, set in the environment Claude Code is launched with, which no tool call of
the session can change): CC_RESEARCH_BLOCK=0 turns the tool deny off; CC_RESEARCH_ROUTER=off
(hooks) turns the routing off; CC_RESEARCH_RELAY_CHECK=0 turns the Stop check off; CC_RESEARCH_WARM=0
skips the resident classifier (classifier-warm.py) and makes the cold call.

Test seams: CC_RESEARCH_HOME, CC_RESEARCH_REGISTRY, CC_RESEARCH_CLASSIFIER (a shell command given the
classifier input on stdin, printing a label), CC_RESEARCH_CLASSIFIER_TIMEOUT, CC_RESEARCH_RENDER (a
shell command printing the certificate lines), CC_MODEL_CONFIG, CC_RESEARCH_WARM_SOCK (the resident
classifier's socket; default $CC_RESEARCH_HOME/classifier-warm/sock).
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shlex
import shutil
import socket
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE / "lib"))
sys.path.insert(0, str(HERE))
import kit  # noqa: E402
from heldout import RELAYED, ROUTES  # noqa: E402

UNAVAILABLE = "unavailable"
ALLOW_ALL = ("work-order", "new-idea")  # §4.2: research runs only on a positive work label
# §10 item 1: the block is on from the freeze; §11: and stays on through both Stage 9 states
BLOCKING_STATES = ("certifying", "certified", *kit.STAGE9_STATES)
CLASSIFIER_TIMEOUT_S = 9.0  # §4.1 said 6 s; raised to 9 s by ruling 4bf73c4e55d5 (REPORT.md §9, 2026-10-04)
FALLBACK_NOTICE_AFTER = 3  # §10 item 3: consecutive fallbacks before the operator is told
PUSHBACK_LINE = (
    "A concern needs a place, a file and line or a decision or check number, and it will be "
    "checked in the next scheduled review."
)
WORK_ORDER_MARKER = re.compile(r"--requires-gate[ =]+([a-z0-9][a-z0-9-]*)")
# How an envelope names the session it continues: `predecessor session <sid>` (or `predecessor:`,
# `predecessor_sid=`), or a bare Claude Code session uuid. A candidate counts only if route-state
# holds a record for it in the same program.
PREDECESSOR = re.compile(
    r"\bpredecessor(?:[ _-]?(?:session|sid))?(?:[ _-]?id)?\s*[:=]?\s*`?([A-Za-z0-9][A-Za-z0-9_.-]{2,127})",
    re.I,
)
SESSION_UUID = re.compile(r"\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b")
# A record a machine wrote is not a genuine prompt (the completion-assert.sh kill-switch reader's
# envelope rule): it keeps the last genuine prompt's label (§4.2), and only a session's first prompt
# gets a label from it (envelope_label).
MACHINE_ENVELOPE = re.compile(
    r"^\s*(\[handoff |<teammate-message|<task-notification|<local-command-stdout>|<command-name>)"
    r"|HANDOFF-ENGAGE-[A-Za-z0-9._-]+"
)

# The route definitions, shared word for word by the classifier and the held-out raters
# (heldout-rate.py), so the sealed set's gold labels and the router answer the same question.
ROUTE_DEFINITIONS = """completeness   - asks, in any words, whether the work is complete, done, all there, good to close,
                 or what steps remain to fully done/deployed/live
pushback       - doubts or challenges the answer with no location ("are you sure?", "really?",
                 "no take-backs?", "double-check that")
concern        - raises a specific problem WITH a location: a file and line, or a decision, check
                 or row number
new-idea       - proposes a new idea, feature, link or competitor to consider
research-order - orders more research or review of the certified scope
work-order     - orders build, fix or other work outside the certified research scope
other          - anything else
If two labels fit, answer the earlier one in this list."""

CLASSIFIER_BRIEF = (
    "You route one operator prompt in a research program that has a certificate.\n"
    "Answer with exactly ONE of these labels and nothing else:\n"
    + ROUTE_DEFINITIONS
    + "\n\nCERTIFICATE STATE LINES:\n{cert}\n\nPROMPT:\n{prompt}\n\nLABEL:"
)


# ── stores ──────────────────────────────────────────────────────────────────────────────────────


def route_path(sid: str) -> Path:
    safe = re.sub(r"[^A-Za-z0-9_.-]", "_", sid or "unknown")[:128]
    return kit.research_home() / "route-state" / f"{safe}.json"


def route_load(sid: str) -> Optional[Dict[str, Any]]:
    try:
        r = json.loads(route_path(sid).read_text())
        return r if isinstance(r, dict) else None
    except (OSError, ValueError):
        return None


ROUTE_HORIZON_S = 7 * 86400  # a route record outlives its session's last prompt by a week


def route_save(sid: str, rec: Dict[str, Any]) -> None:
    p = route_path(sid)
    p.parent.mkdir(parents=True, exist_ok=True)
    kit.write_json_atomic(p, rec)
    route_reap(p.parent)


def route_reap(d: Path) -> None:
    """The age reaper for route-state/ (scripts/growth-coverage.conf): one record per session would
    otherwise grow without bound. A week is far past any turn the record governs."""
    import time

    cut = time.time() - ROUTE_HORIZON_S
    try:
        for e in os.scandir(d):
            if e.name.endswith(".json") and e.stat().st_mtime < cut:
                os.unlink(e.path)
    except OSError:
        pass


def route_clear(sid: str) -> None:
    try:
        route_path(sid).unlink()
    except OSError:
        pass


def program_state(slug: str) -> Optional[str]:
    try:
        prog = kit.registry_get(slug)
    except (kit.KitError, ValueError, OSError):
        return None
    return (prog or {}).get("state")


def open_activities(slug: str) -> List[str]:
    p = kit.research_home() / "activities.json"
    try:
        data = json.loads(p.read_text())
    except (OSError, ValueError):
        return []
    acts = data.get("activities") if isinstance(data, dict) else None
    return [
        a["id"]
        for a in acts or []
        if isinstance(a, dict)
        and a.get("program") == slug
        and a.get("state") == "open"
        and isinstance(a.get("id"), str)
        and re.fullmatch(r"[A-Za-z0-9_.:-]+", a["id"])
    ]


# ── the certificate read ────────────────────────────────────────────────────────────────────────


def render_cert(slug: str) -> Tuple[str, str]:
    """(state lines, error). The same read the block whitelists (gate.sh --render)."""
    env_cmd = os.environ.get("CC_RESEARCH_RENDER")
    cmd = (
        ["/bin/bash", "-c", env_cmd]
        if env_cmd
        else [str(HERE / "gate.sh"), "--render", "--program", slug]
    )
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=5)
    except (subprocess.TimeoutExpired, OSError) as e:
        return "", f"certificate render failed: {e.__class__.__name__}"
    if p.returncode != 0 or not p.stdout.strip():
        return "", f"certificate render failed (rc {p.returncode})"
    return p.stdout.strip(), ""


# ── the classifier ──────────────────────────────────────────────────────────────────────────────


def haiku_model() -> str:
    """model-config.yaml `haiku_latest` (§4.1); `haiku` when it cannot be read."""
    for cand in (
        os.environ.get("CC_MODEL_CONFIG"),
        str(Path.home() / ".claude" / "model-config.yaml"),
        str(HERE.parent.parent / "model-config.yaml"),
    ):
        if not cand:
            continue
        try:
            for line in Path(cand).read_text().splitlines():
                m = re.match(r"\s*haiku_latest:\s*([A-Za-z0-9._-]+)", line)
                if m:
                    return m.group(1)
        except OSError:
            continue
    return "haiku"


def classifier_argv() -> Optional[List[str]]:
    env_cmd = os.environ.get("CC_RESEARCH_CLASSIFIER")
    if env_cmd:
        return ["/bin/bash", "-c", env_cmd]
    claude = shutil.which("claude")
    if not claude:
        return None
    # Headless from an empty directory with local settings only, so no resident instruction or hook
    # loads and the router cannot trigger itself (§4.1). The env guard is the belt to that brace.
    return [claude, "-p", "--model", haiku_model(), "--setting-sources", "local",
            "--tools", "", "--strict-mcp-config", "--no-session-persistence"]


def warm_sock() -> Path:
    env = os.environ.get("CC_RESEARCH_WARM_SOCK")
    return Path(env) if env else kit.research_home() / "classifier-warm" / "sock"


def warm_classify(text: str, timeout: float) -> Tuple[str, str]:
    """Ask the resident classifier (classifier-warm.py, wave E1c), which keeps classifier processes
    started ahead of the prompt. Returns ("answer", its raw reply), ("cold", why) when no process
    took the prompt (no daemon, none ready: make the cold call), or ("spent", why) when one took it
    and failed. It never yields a label of its own: the caller parses the reply as it parses a cold
    call's."""
    path = warm_sock()
    if os.environ.get("CC_RESEARCH_WARM") == "0" or not path.exists():
        return "cold", "no resident classifier"
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    try:
        s.settimeout(1.0)  # the daemon answers its socket within 1 s or it is treated as absent
        s.connect(str(path))
        s.sendall(json.dumps({"op": "ask", "text": text, "timeout": timeout}).encode() + b"\n")
    except OSError:
        s.close()
        return "cold", "the resident classifier did not take the prompt"
    try:
        s.settimeout(timeout)
        buf = b""
        while b"\n" not in buf:
            chunk = s.recv(65536)
            if not chunk:
                break
            buf += chunk
        out = json.loads(buf.split(b"\n", 1)[0])
    except (OSError, ValueError):
        return "spent", f"the resident classifier did not answer in {timeout:g} s"
    finally:
        s.close()
    if isinstance(out, dict) and out.get("ok") and isinstance(out.get("text"), str):
        return "answer", out["text"]
    if isinstance(out, dict) and out.get("cold"):
        return "cold", str(out.get("why") or "no warm process ready")
    return "spent", str((out or {}).get("why") if isinstance(out, dict) else "bad reply")


def classify(prompt: str, cert: str) -> Tuple[Optional[str], str]:
    """(label, reason). label None = unavailable: an error, a timeout, an unknown or mixed label."""
    m = WORK_ORDER_MARKER.search(prompt)
    if m:
        return "work-order", f"--requires-gate {m.group(1)} marker"
    try:
        timeout = float(
            os.environ.get("CC_RESEARCH_CLASSIFIER_TIMEOUT") or CLASSIFIER_TIMEOUT_S
        )
    except ValueError:
        timeout = CLASSIFIER_TIMEOUT_S
    text = CLASSIFIER_BRIEF.format(cert=cert or "(none rendered)", prompt=prompt)
    # The resident classifier first, inside the same limit; the cold call gets what is left of it.
    t0 = time.time()
    state, reply = warm_classify(text, timeout)
    if state == "answer":
        labels = reply.replace(",", " ").split()
        if len(labels) != 1 or labels[0] not in ROUTES:
            return None, f"classifier answered {' '.join(labels)[:60]!r}, not one route label"
        return labels[0], "classifier (resident)"
    if state == "spent":
        return None, reply
    timeout -= time.time() - t0
    if timeout <= 0:
        return None, "classifier timed out before the cold call"
    argv = classifier_argv()
    if argv is None:
        return None, "no classifier: `claude` is not on PATH"
    empty = tempfile.mkdtemp(prefix="cc-research-router-")
    try:
        p = subprocess.run(
            argv,
            input=text,
            capture_output=True,
            text=True,
            timeout=timeout,
            cwd=empty,
            env=dict(os.environ, CC_RESEARCH_ROUTER_INNER="1"),
        )
    except subprocess.TimeoutExpired:
        return None, f"classifier timed out at {timeout:g} s"
    except OSError as e:
        return None, f"classifier did not start: {e.__class__.__name__}"
    finally:
        shutil.rmtree(empty, ignore_errors=True)
    labels = p.stdout.replace(",", " ").split()
    if p.returncode != 0:
        return None, f"classifier exited {p.returncode}"
    if len(labels) != 1 or labels[0] not in ROUTES:
        return None, f"classifier answered {' '.join(labels)[:60]!r}, not one route label"
    return labels[0], "classifier"


# ── UserPromptSubmit ────────────────────────────────────────────────────────────────────────────


def genuine(prompt: str) -> bool:
    return bool(prompt.strip()) and not MACHINE_ENVELOPE.search(prompt)


def envelope_label(prompt: str, slug: str, sid: str) -> Tuple[str, str]:
    """(label, reason) for a machine-envelope FIRST prompt, without the classifier: the work-order
    marker, else the label of a predecessor session the envelope names, else `other`. A relayed
    label is not inherited: it governs one re-ask turn, and the successor's brief is not one."""
    m = WORK_ORDER_MARKER.search(prompt)
    if m:
        return "work-order", f"machine envelope with the --requires-gate {m.group(1)} marker"
    cands = [c.group(1).rstrip("._-") for c in PREDECESSOR.finditer(prompt)]
    for cand in cands + SESSION_UUID.findall(prompt):
        prev = route_load(cand) if cand != sid else None
        lab = (prev or {}).get("label")
        if prev and prev.get("program") == slug and lab in ROUTES and lab not in RELAYED:
            return str(lab), f"machine envelope inheriting predecessor session {cand}"
    return "other", "machine envelope naming no routed predecessor session"


def context_for(slug: str, state: str, label: str, cert: str, reason: str) -> str:
    head = f"RESEARCH PROGRAM {slug} ({state}) — this prompt is routed as"
    lines = cert or "(the certificate read failed; say so in one line and add nothing)"
    if label in RELAYED:
        extra = f'\nThen this one fixed line, verbatim: "{PUSHBACK_LINE}"' if label == "pushback" else ""
        return (
            f"{head} {'PUSHBACK' if label == 'pushback' else 'a COMPLETENESS question'} "
            "(REPORT.md §4.1). Relay the certificate state lines below VERBATIM, plus at most 3 lines "
            "explaining them. Name no item, location or row the lines do not carry, whether you open "
            "yes or no; a 'no' must cite a triaged escape, a scheduled freshness flip or a change the "
            "operator accepted. Every tool except `scripts/research-kit/gate.sh --render --program "
            f"{slug}` is blocked this turn.{extra}\n--- certificate state lines ---\n{lines}\n---"
        )
    if label == UNAVAILABLE:
        return (
            f"{head} UNKNOWN: the re-ask classifier was unavailable ({reason}). Research verbs "
            "(Agent, Workflow, handoff-fire.sh, the vendor CLIs, round.sh, courier.sh) are blocked this "
            "turn; other tools are not. If the prompt asks whether the work is complete, relay these "
            f"lines verbatim and add nothing:\n--- certificate state lines ---\n{lines}\n---"
        )
    if label == "concern":
        return (
            f"{head} a CONCERN with a location. It is checked in the next scheduled triage batch and "
            "reaches the certificate only if triage confirms a material escape (§4.4). File it; do not "
            "research it. Research verbs are blocked this turn."
        )
    if label == "new-idea":
        return (
            f"{head} a NEW IDEA. Park it for the next version with a price (§5.1); it enters this "
            "version only if the operator marks it 'blocks this version' after seeing the price. Any "
            "research on it runs as a separate task whose results park."
        )
    if label == "research-order":
        if state == "certifying":
            return (
                f"{head} a RESEARCH ORDER while certification runs. The kit's own rounds (round.sh, "
                "courier.sh) are allowed; Agent, Workflow, handoff-fire.sh and bare vendor CLIs are "
                "blocked this turn."
            )
        return (
            f"{head} an ORDER TO RESEARCH THE CERTIFIED SCOPE. No research on certified scope this "
            "turn. Answer from the certificate's line for the row in question; the options (a separate "
            "task whose results park, the one extra round set, or a reopen the operator signs in their "
            "own terminal) are the operator's to choose, not yours to offer or run."
        )
    if label == "other":
        return f"{head} other: normal handling, but research verbs stay blocked this turn (§4.2)."
    return ""  # work-order: normal handling, nothing to say


def cmd_prompt(a: argparse.Namespace) -> int:
    try:
        data = json.loads(sys.stdin.read() or "{}")
    except ValueError:
        return 0
    sid = str(data.get("session_id") or "unknown")
    prompt = data.get("prompt") or data.get("user_prompt") or ""
    if not isinstance(prompt, str) or not prompt.strip():
        return 0
    if not genuine(prompt):
        return envelope_prompt(a, sid, prompt)
    if a.clear or not a.program or a.state not in BLOCKING_STATES:
        route_clear(sid)
        return 0
    prev = route_load(sid) or {}
    base = {
        "program": a.program,
        "state": a.state,
        "by": a.by,
        "at": kit.now_iso(),
        "prompt_sha": hashlib.sha256(prompt.encode()).hexdigest()[:12],
    }
    # Pre-written, so a hook killed at its registered timeout leaves `unavailable` (§10 item 3).
    route_save(sid, dict(base, label=UNAVAILABLE, cert="", reason="router did not finish",
                         fallbacks=int(prev.get("fallbacks") or 0) + 1))
    cert, err = render_cert(a.program)
    label, reason = classify(prompt, cert)
    fallbacks = 0 if label else int(prev.get("fallbacks") or 0) + 1
    label = label or UNAVAILABLE
    route_save(sid, dict(base, label=label, cert=cert, reason=err or reason, fallbacks=fallbacks))
    out: Dict[str, Any] = {}
    ctx = context_for(a.program, a.state, label, cert, reason)
    if ctx:
        out["hookSpecificOutput"] = {"hookEventName": "UserPromptSubmit", "additionalContext": ctx}
    if fallbacks >= FALLBACK_NOTICE_AFTER:
        out["systemMessage"] = (
            f"research-program router: classifier unavailable for {fallbacks} prompts in a row "
            f"({reason}); only the research-verb deny is in force. Kill switch: launch with "
            "CC_RESEARCH_ROUTER=off."
        )
    if out:
        print(json.dumps(out))
    return 0


def envelope_prompt(a: argparse.Namespace, sid: str, prompt: str) -> int:
    """A machine-envelope prompt. With a route record the last genuine label stands (§4.2); as the
    session's first prompt in a blocking program it gets envelope_label's label, recorded `by:
    envelope`, so cmd_tool does not read the session as unlabeled (completeness)."""
    if a.clear or not a.program or a.state not in BLOCKING_STATES or route_load(sid):
        return 0
    label, reason = envelope_label(prompt, a.program, sid)
    route_save(sid, {
        "program": a.program,
        "state": a.state,
        "by": "envelope",
        "at": kit.now_iso(),
        "prompt_sha": hashlib.sha256(prompt.encode()).hexdigest()[:12],
        "label": label,
        "cert": "",
        "reason": reason,
        "fallbacks": 0,
    })
    ctx = context_for(a.program, a.state, label, "", reason)
    if ctx:
        print(json.dumps({"hookSpecificOutput": {"hookEventName": "UserPromptSubmit",
                                                 "additionalContext": ctx}}))
    return 0


# ── PreToolUse ──────────────────────────────────────────────────────────────────────────────────

# Every separator the shell has, newline and command substitution included (a clause splitter is a
# claim about every separator — docs/lessons/a-clause-splitter-is-a-claim-about-every-separator-the-
# shell-has.md).
SEPARATORS = re.compile(r"\$\(|[;&|\n()`{}]")
WRAPPERS = {"bash", "sh", "zsh", "env", "exec", "nohup", "time", "command", "sudo", "xargs",
            "python", "python3", "nice", "caffeinate"}
# agy / antigravity: the Antigravity CLI, the Google reviewer lane since the gemini CLI was retired
# for individual accounts (scripts/research-kit/lib/courier.py header).
VENDOR = {"codex", "gemini", "agy", "antigravity"}
KIT_ROUND = {"round.sh", "courier.sh"}
CC_RESEARCH_BUYING = {"reopen", "extra-round", "round", "frame-critique", "rehearse"}
ASSIGN = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")


def split_clauses(cmd: str) -> List[str]:
    """Split on every shell separator OUTSIDE quotes. Inside double quotes `$(` and a backtick still
    run a command, so they split there too; text inside single quotes never runs."""
    out: List[str] = []
    cur: List[str] = []
    q: Optional[str] = None
    i = 0
    while i < len(cmd):
        ch = cmd[i]
        if q == "'":
            cur.append(ch)
            q = None if ch == "'" else q
        elif ch == "\\" and i + 1 < len(cmd):
            cur.append(cmd[i : i + 2])
            i += 1
        elif cmd.startswith("$(", i) or ch == "`":
            out.append("".join(cur))
            cur = []
            i += 1 if ch == "$" else 0
        elif q == '"':
            cur.append(ch)
            q = None if ch == '"' else q
        elif ch in "'\"":
            cur.append(ch)
            q = ch
        elif ch in ";&|\n(){}":
            out.append("".join(cur))
            cur = []
        else:
            cur.append(ch)
        i += 1
    out.append("".join(cur))
    return out


def clauses(cmd: str) -> List[List[str]]:
    out = []
    for raw in split_clauses(cmd):
        try:
            toks = shlex.split(raw, comments=True)
        except ValueError:
            toks = raw.split()
        if toks:
            out.append(toks)
    return out


def head(toks: List[str]) -> Tuple[Dict[str, str], List[str]]:
    """(env assignments, argv of the real command): assignments, wrappers, their options and a
    `timeout` duration are stripped, so `env X=1 timeout 5 codex …` reads as codex."""
    env: Dict[str, str] = {}
    i = 0
    while i < len(toks):
        t = toks[i]
        b = os.path.basename(t)
        if ASSIGN.match(t):
            k, _, v = t.partition("=")
            env[k] = v
        elif b == "timeout":
            i += 1
            while i < len(toks) and toks[i].startswith("-"):
                i += 1  # its options; the duration is skipped by the outer i += 1
        elif b in WRAPPERS or t.startswith("-"):
            pass
        else:
            return env, toks[i:]
        i += 1
    return env, []


def research_clause(toks: List[str], slug: str, acts: List[str], certifying: bool,
                    label: str) -> Optional[str]:
    """The research verb a clause runs, or None. Activity-tagged and allowed kit calls are None."""
    env, argv = head(toks)
    if not argv:
        return None
    if any(c.isspace() for c in argv[0]):  # `bash -c "codex …"`: the script is one token
        for sub in clauses(argv[0]):
            hit = research_clause(sub, slug, acts, certifying, label)
            if hit:
                return hit
        return None
    base = os.path.basename(argv[0])
    rest = argv[1:]
    if base == "handoff-fire.sh":
        return "handoff-fire.sh"
    if base in VENDOR:
        return base
    if base == "claude" and any(t in ("-p", "--print") or t.startswith("--print=") for t in rest):
        return "claude -p"
    if base == "cc-research" and rest and rest[0] in CC_RESEARCH_BUYING:
        return f"cc-research {rest[0]}"
    if base in KIT_ROUND:
        act = env.get("CC_RESEARCH_ACTIVITY")
        if act and act in acts and (base == "courier.sh" or "--delta" in rest
                                    or "delta" in rest):
            return None  # a contract-listed activity (§10 item 8)
        if certifying and label == "research-order":
            return None  # certification is the kit's own scheduled stage
        return base
    return None


def cert_read(cmd: str, slug: str) -> bool:
    """The ONE whitelisted tool of a completeness or pushback turn: a bare certificate read."""
    s = cmd.strip()
    if SEPARATORS.search(s) or re.search(r"[<>]", s):
        return False
    s_slug = re.escape(slug)
    return bool(
        re.fullmatch(rf"(\S*/)?gate\.sh\s+(--render|render)\s+--program\s+{s_slug}", s)
        or re.fullmatch(rf"(\S*/)?cc-research\s+verdict(\s+--program)?\s+{s_slug}", s)
    )


def deny(reason: str) -> int:
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse",
                                             "permissionDecision": "deny",
                                             "permissionDecisionReason": reason}}))
    return 0


def cmd_tool(a: argparse.Namespace) -> int:
    try:
        data = json.loads(sys.stdin.read() or "{}")
    except ValueError:
        return 0
    sid = str(data.get("session_id") or "unknown")
    tool = str(data.get("tool_name") or "")
    tin = data.get("tool_input") if isinstance(data.get("tool_input"), dict) else {}
    route = route_load(sid)
    slug = (route or {}).get("program") or a.program
    if not slug:
        return 0
    state = program_state(slug)
    if state not in BLOCKING_STATES:
        return 0
    label = (route or {}).get("label") if (route or {}).get("program") == slug else None
    unlabeled = label is None
    if unlabeled:
        label = "completeness"  # §4.2: a genuine prompt the router left no label for
    if label in ALLOW_ALL:
        return 0
    cmd = str(tin.get("command") or "") if tool == "Bash" else ""
    where = f"research program {slug} is {state}"
    if label in RELAYED:
        if tool == "Bash" and cert_read(cmd, slug):
            return 0
        why = (
            "no genuine prompt has been routed in this session since the program became " + state
            if unlabeled else f"this turn's prompt is routed as {label}"
        )
        return deny(
            f"research block (REPORT.md §4.2): {where} and {why}, so every tool is blocked except "
            f"the certificate read `scripts/research-kit/gate.sh --render --program {slug}`. "
            "Relay its state lines verbatim, plus at most 3 lines; add no item. Operator kill switch: "
            "launch with CC_RESEARCH_BLOCK=0."
        )
    acts = open_activities(slug)
    hit: Optional[str] = None
    if tool in ("Agent", "Task", "Workflow"):
        tag = " ".join(str(tin.get(k) or "") for k in ("description", "prompt", "name"))
        if not any(f"[activity:{x}]" in tag for x in acts):
            hit = tool
    elif tool == "Bash":
        for toks in clauses(cmd):
            hit = research_clause(toks, slug, acts, state == "certifying", label)
            if hit:
                break
    if not hit:
        return 0
    if label == UNAVAILABLE:
        why = "the re-ask classifier was unavailable for this turn's prompt (§10 item 3); the next genuine prompt is classified afresh"
    else:
        why = f"this turn's prompt is routed as {label}, not as a work order or a new idea"
    return deny(
        f"research block (REPORT.md §4.2): {where} and {why}, so `{hit}` (a research verb) is "
        "blocked. Research on certified scope runs only on a prompt positively labeled a work order "
        "or a new idea, after an operator-signed reopen, or as an open contract-listed activity "
        "tagged CC_RESEARCH_ACTIVITY=<id> / [activity:<id>]. Operator kill switch: launch with "
        "CC_RESEARCH_BLOCK=0."
    )


# ── Stop: the relay check (§4.4) ────────────────────────────────────────────────────────────────

# The census's own "names an item" pattern (evidence/adversary/llm/ask_turns.py ITEM), so the check
# and the measurement that motivated it agree on what an added item looks like.
ITEM = re.compile(
    r"\b(one|two|three|a few|several) (more|remaining|small|other|last) "
    r"(thing|item|gap|hole|check|step|caveat)s?\b|worth (noting|flagging)|one caveat|\bexcept\b|"
    r"still open|not yet (run|verified|measured|built|live)|follow-on: (?!none)",
    re.I,
)
OPENS_NO = re.compile(
    r"^\W*(no\b|not yet|not quite|actually|almost|close,? but|nearly|🔧|⛔|📦|good to close:\s*no)",
    re.I,
)
# Its yes-side twin: together they say a reply opens with a verdict, which is what puts an
# `unavailable` turn's reply under the check (a fallback is not a licence to add items).
OPENS_YES = re.compile(
    r"^\W*(yes\b|yep\b|done\b|complete\b|completed\b|all done|finished\b|✅|good to close:\s*yes)",
    re.I,
)
EVENT = re.compile(r"escape|freshness|accepted", re.I)
TOKENS = (
    re.compile(r"[\w./~-]+\.\w{1,6}:\d+(?:-\d+)?"),  # file:line
    re.compile(r"[\w~.-]*/[\w./-]*\.\w{1,6}\b"),  # a path with an extension
    re.compile(r"\b[\w-]+\.(?:sh|py|md|json|jsonl|ts|js|yaml|yml|toml|bats|go|rs|txt|plist)\b"),
    re.compile(r"\b(?:row|decision|check|item|premise|source|population|step)\s?#?\d+\b", re.I),
    re.compile(r"\b[DR]\d+\b"),
    re.compile(r"#\d+\b"),
    re.compile(r"\b(?=[0-9a-f]*[0-9])(?=[0-9a-f]*[a-f])[0-9a-f]{12}\b"),  # a backlog or packet id
    re.compile(r"`([^`\n]+)`"),  # anything code-styled
)
MAX_EXTRA_LINES = 3


def norm(s: str) -> str:
    return re.sub(r"\s+", " ", s).strip().lower()


def relay_violations(reply: str, cert: str, label: str) -> List[str]:
    c = norm(cert) + " " + norm(PUSHBACK_LINE if label == "pushback" else "")
    out: List[str] = []
    unknown: List[str] = []
    for rx in TOKENS:
        for m in rx.finditer(reply):
            tok = m.group(1) if rx.groups else m.group(0)
            if norm(tok) and norm(tok) not in c and tok not in unknown:
                unknown.append(tok)
    if unknown:
        out.append("it names " + ", ".join(f"'{t}'" for t in unknown[:6])
                   + " which the certificate lines do not carry")
    for m in ITEM.finditer(reply):
        if norm(m.group(0)) not in c:
            out.append(f"'{m.group(0)}' introduces an item beyond the certificate")
            break
    first = next((ln for ln in reply.splitlines() if ln.strip()), "")
    if OPENS_NO.search(first) and not EVENT.search(reply):
        out.append("it opens 'no' without citing a triaged escape, a scheduled freshness flip or a "
                   "change the operator accepted (§4.4)")
    extra = 0
    for ln in reply.splitlines():
        s = norm(re.sub(r"^[\s>*\-•]+|```\w*", "", ln))
        if s and s not in c:
            extra += 1
    if extra > MAX_EXTRA_LINES:
        out.append(f"it adds {extra} lines beyond the certificate (at most {MAX_EXTRA_LINES})")
    return out


def cmd_relay_check(a: argparse.Namespace) -> int:
    route = route_load(a.session)
    label = (route or {}).get("label")
    if not route or (label not in RELAYED and label != UNAVAILABLE):
        return 0
    slug = route.get("program") or ""
    if program_state(slug) not in BLOCKING_STATES:
        return 0
    reply = sys.stdin.read()
    cert = route.get("cert") or ""
    routed = str(label)
    if label == UNAVAILABLE:
        # The classifier fell back, so the prompt may have been a re-ask: a reply that opens with a
        # verdict is checked as a completeness relay; any other reply is ordinary work.
        first = next((ln for ln in reply.splitlines() if ln.strip()), "")
        if not (OPENS_NO.search(first) or OPENS_YES.search(first)):
            return 0
        cert = cert or render_cert(slug)[0]
        routed = "unavailable (the re-ask classifier fell back; the reply opens with a verdict)"
    v = relay_violations(reply, cert, str(label))
    if not v:
        return 0
    print(
        f"Research relay check (REPORT.md §4.4): this turn's prompt was routed as {routed} "
        f"in research program {slug} ({route.get('state')}), and your reply adds to the certificate: "
        + "; ".join(v)
        + ". Re-answer with the certificate state lines verbatim (gate.sh --render --program "
        f"{slug}) plus at most {MAX_EXTRA_LINES} lines explaining them, naming nothing they do not "
        "carry. Only a triaged escape, a scheduled freshness flip or an accepted change moves the "
        "answer, and none happens inside a re-ask turn."
    )
    return 1


def main(argv: Optional[List[str]] = None) -> int:
    ap = argparse.ArgumentParser(prog="router.py")
    sub = ap.add_subparsers(dest="verb", required=True)
    p = sub.add_parser("classify")
    p.add_argument("--program")
    p = sub.add_parser("prompt")
    p.add_argument("--program", default="")
    p.add_argument("--state", default="")
    p.add_argument("--by", default="cwd", choices=("cwd", "prompt"))
    p.add_argument("--clear", action="store_true")
    p = sub.add_parser("tool")
    p.add_argument("--program", default="")
    p = sub.add_parser("relay-check")
    p.add_argument("--session", required=True)
    p = sub.add_parser("status")
    p.add_argument("--session", required=True)
    a = ap.parse_args(argv)
    if a.verb == "classify":
        cert = render_cert(a.program)[0] if a.program else ""
        label, _ = classify(sys.stdin.read(), cert)
        if not label:
            return 1  # heldout.route() counts a non-zero exit as a fallback
        print(label)
        return 0
    if a.verb == "prompt":
        return cmd_prompt(a)
    if a.verb == "tool":
        return cmd_tool(a)
    if a.verb == "relay-check":
        return cmd_relay_check(a)
    print(json.dumps(route_load(a.session) or {}, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
