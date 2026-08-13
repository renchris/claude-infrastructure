#!/usr/bin/env python3
"""PreToolUse(Bash) model-in-the-loop permission decider.

WHAT IT IS. When a Bash call would otherwise stop the agent and wait for the
operator, route it to a model that HAS the session context and the repository
context, and let that model either approve it or hand it to the human. The
interception point, the context, and the escalate-to-human verb all already
exist -- see docs/research/model-in-the-loop-permissions-2026-08-12.md. This
file is the decision function.

IT EMITS EXACTLY TWO VERBS, EVER: `allow` and `ask`.
`deny` is deliberately unreachable. A wrong `deny` wedges the session with no
human in the loop; a wrong `ask` costs one prompt. The fail direction is `ask`
on every error path -- timeout, crash, malformed model output, budget
exhaustion, unparseable command.

MEASURED HARNESS BEHAVIOUR THIS DESIGN RESTS ON (2026-08-12, CC 2.1.220, nine
isolated arms; see the research doc's Measurement section):

  * A PreToolUse hook that exceeds its `timeout` has its verdict DISCARDED and
    the harness falls through to the normal permission flow -- byte-identical
    to the hook not being configured at all. The child process is KILLED (no
    orphan), and the timeout is SILENT: nothing on stderr, nothing in the
    transcript, no notice to the model.
      => Consequence, and it is the reason `deadline_s` exists below: falling
         through is NOT "degrade to the human". The operator runs
         defaultMode=auto, so a timeout degrades to AUTO-MODE'S CLASSIFIER.
         To actually reach the human we must EMIT `ask` before the deadline,
         so our internal deadline is strictly less than the hook timeout.

  * `timeout` is per-hook with no ceiling reached at 180s (60s and 180s both
    honoured, harness blocking the full duration). The `timeout: 5` on
    smart-bash-allowlist.sh is that hook's own choice, not a harness limit.
    A model call fits.

  * A hook emitting `ask` DOES reach the human under defaultMode=auto -- the
    auto classifier does not override it. That is what makes escalation real.

  * A hook emitting `allow` BYPASSES the permission system COMPLETELY. In the
    experiment an `allow` sailed past the allowed-working-directory write
    guard, which is a hard rule and not merely an `ask` entry. So `allow` is
    strictly more dangerous than the 732147576 commit message states, and the
    fence below is the whole safety story.

THE FENCE (the hard part). Because `allow` bypasses everything, this decider
must be STRUCTURALLY INCAPABLE of auto-approving anything the operator gated.
Three properties, in order of importance:

  1. The fence is read LIVE from the operator's settings.json on every
     invocation -- `permissions.ask` AND `permissions.deny`. Nothing is
     hardcoded here, so the operator adding a rule arms this decider against it
     with no code change. (A resident copy of a perishable fact cannot learn it
     changed.)
  2. The fence is applied to DECOMPOSED segments, not to the raw string, and
     it fences on INDIRECTION rather than enumerating spellings. Rule 4 of
     smart-bash-allowlist.sh died of a denylist that enumerated branch names;
     the lesson taken here is that anything which could RESOLVE to a gated
     command at runtime -- `eval`, command substitution, `sh -c`, `xargs`,
     piping into a shell -- is fenced without being understood.
  3. The fence runs TWICE: once before the model is consulted (so a gated
     command never even costs a token), and again on the model's `ALLOW`
     before it is emitted. The model's verdict can only ever NARROW. There is
     no code path where a model utterance widens what the fence permits.

RECURSION CONTAINMENT. The decider consults a model via a headless `claude -p`
child, whose own tool calls would fire PreToolUse -- a fork bomb with a model
inside. Two independent fences:
  * the child runs with `--setting-sources ''`, MEASURED to load no user,
    project or local settings, therefore no hooks at all; and
  * the child's environment carries CC_MITL_DECIDER=1, which this script
    checks as its very first action. If the flag semantics ever change
    upstream, the sentinel still holds.
The child is additionally given no tools it could use to act.
"""

from __future__ import annotations

import json
import os
import pathlib
import re
import shlex
import subprocess
import sys
import time

HOME = pathlib.Path(os.environ.get("HOME", "/"))
SETTINGS = HOME / ".claude/settings.json"
STATE_DIR = pathlib.Path(
    os.environ.get("MITL_STATE_DIR", str(HOME / ".claude/autonomy/mitl-decider"))
)
CLAUDE_BIN = os.environ.get(
    "MITL_CLAUDE_BIN", "/Users/chrisren/.claude-220/node_modules/.bin/claude"
)
MODEL = os.environ.get("MITL_MODEL", "claude-haiku-4-5-20251001")

# Internal deadline. MUST stay strictly below the hook `timeout` in
# settings.json, because a hook that overruns is silently discarded and its
# verdict never reaches the harness. Wire the hook at 60 and leave headroom.
DEADLINE_S = float(os.environ.get("MITL_DEADLINE_S", "38"))

# Budget. Fail direction on exhaustion is `ask`, never `allow`.
PER_SESSION_MAX = int(os.environ.get("MITL_PER_SESSION_MAX", "40"))
PER_DAY_MAX = int(os.environ.get("MITL_PER_DAY_MAX", "400"))

# Anything that can resolve to a different command at runtime. Fenced without
# being understood -- the decomposition below cannot see through these, so
# claiming to have checked them would be a lie.
INDIRECTION = re.compile(
    r"""(?x)
      \$\(            # command substitution
    | `               # backtick substitution
    | (?:^|[\s;&|])eval(?:\s|$)
    | (?:^|[\s;&|])exec(?:\s|$)
    | (?:^|[\s;&|])(?:sh|bash|zsh|dash)\s+-c
    | (?:^|[\s;&|])xargs(?:\s|$)
    | (?:^|[\s;&|])(?:source|\.)\s
    | \|\s*(?:sh|bash|zsh)(?:\s|$)
    | base64\s+(?:-d|--decode)
    """
)


# --------------------------------------------------------------------------
# fence
# --------------------------------------------------------------------------
def gated_patterns() -> tuple[list[str], list[str], bool]:
    """Read the operator's gates LIVE. Never cache, never hardcode.

    Returns (ask_patterns, deny_patterns, readable). `readable` False means we
    could not determine what is gated -- which is not a licence to approve, so
    the caller escalates. (An earlier draft signalled this with a sentinel
    PATTERN, which could never match any segment and therefore approved
    everything; the suite's unreadable-settings case caught it.)
    """
    try:
        perms = json.loads(SETTINGS.read_text()).get("permissions", {})
    except (OSError, ValueError):
        return ([], [], False)

    def prefixes(rules: object) -> list[str]:
        out = []
        for rule in rules if isinstance(rules, list) else []:
            m = re.match(r"^Bash\((.*?)(?::\*)?\)$", str(rule))
            if m and m.group(1):
                out.append(m.group(1).strip())
        return out

    return prefixes(perms.get("ask")), prefixes(perms.get("deny")), True


def segments(cmd: str) -> list[str]:
    """Split a compound command into independently-executed segments.

    The measured top blockers are compound commands (head = cd / export / set),
    so matching the raw string would miss the gated command sitting in segment
    four. This is a splitter, not a shell parser -- which is exactly why
    INDIRECTION is fenced separately rather than resolved.
    """
    parts = re.split(r"\|\||&&|;|\||\n|&", cmd)
    return [p.strip() for p in parts if p.strip()]


def normalise(seg: str) -> str:
    """Strip leading assignments and env wrappers so the head is the real verb."""
    s = seg.strip()
    s = re.sub(r"^\(\s*", "", s)
    s = re.sub(r"^(?:[A-Za-z_][A-Za-z0-9_]*=(?:\"[^\"]*\"|'[^']*'|\S*)\s+)*", "", s)
    s = re.sub(r"^env\s+(?:-\S+\s+)*(?:[A-Za-z_][A-Za-z0-9_]*=\S*\s+)*", "", s)
    s = re.sub(r"^(?:command|builtin|nohup|time)\s+", "", s)
    s = re.sub(r"^timeout\s+\S+\s+", "", s)
    return s.strip()


def fence(cmd: str) -> str | None:
    """Return a reason to escalate, or None if the command clears the fence.

    None means ONLY "no operator gate is implicated". It is not an approval --
    the model still has to approve, and the model can only narrow.
    """
    if not cmd.strip():
        return "empty command"
    if INDIRECTION.search(cmd):
        return "command contains indirection (substitution/eval/shell -c/xargs) that could resolve to a gated command"

    ask_pats, deny_pats, readable = gated_patterns()
    if not readable:
        return "operator settings.json unreadable -- cannot tell what is gated"
    for seg in segments(cmd):
        s = normalise(seg)
        if not s:
            continue
        try:
            shlex.split(s)
        except ValueError:
            return f"segment could not be tokenised: {s[:60]!r}"
        for pat in deny_pats:
            if s == pat or s.startswith(pat + " ") or s.startswith(pat):
                return f"segment matches operator deny rule {pat!r}"
        for pat in ask_pats:
            if s == pat or s.startswith(pat + " ") or s.startswith(pat):
                return f"segment matches operator ask rule {pat!r}"
    return None


def already_allowed(cmd: str) -> bool:
    """True when the operator's own allow list already covers every segment.

    These calls never prompt, so spending a model call on them is pure cost.
    """
    try:
        perms = json.loads(SETTINGS.read_text()).get("permissions", {})
    except (OSError, ValueError):
        return False
    pats = []
    for rule in perms.get("allow", []) or []:
        m = re.match(r"^Bash\((.*?)(?::\*)?\)$", str(rule))
        if m and m.group(1):
            pats.append(m.group(1).strip())
    if not pats:
        return False
    segs = [normalise(s) for s in segments(cmd)]
    segs = [s for s in segs if s]
    if not segs:
        return False
    return all(any(s == p or s.startswith(p) for p in pats) for s in segs)


# --------------------------------------------------------------------------
# budget
# --------------------------------------------------------------------------
def spend(session_id: str) -> str | None:
    """Consume one unit of budget. Returns a reason string when exhausted."""
    try:
        STATE_DIR.mkdir(parents=True, exist_ok=True)
        day = time.strftime("%Y-%m-%d")
        for path, cap, label in (
            (STATE_DIR / f"day-{day}.count", PER_DAY_MAX, "daily"),
            (
                STATE_DIR / f"session-{session_id or 'unknown'}.count",
                PER_SESSION_MAX,
                "session",
            ),
        ):
            try:
                n = int(path.read_text().strip() or "0")
            except (OSError, ValueError):
                n = 0
            if n >= cap:
                return f"{label} decider budget exhausted ({n}/{cap})"
            path.write_text(str(n + 1))
    except OSError as exc:
        return f"budget state unwritable ({exc.__class__.__name__})"
    return None


# --------------------------------------------------------------------------
# context packet
# --------------------------------------------------------------------------
def repo_context(cwd: str, budget_s: float) -> str:
    if not os.path.isdir(cwd):
        return "cwd does not exist"
    out = []
    for label, argv in (
        ("branch", ["git", "rev-parse", "--abbrev-ref", "HEAD"]),
        ("status", ["git", "status", "--porcelain=v1", "--untracked-files=no"]),
    ):
        try:
            cp = subprocess.run(
                argv,
                cwd=cwd,
                capture_output=True,
                text=True,
                timeout=max(1.0, budget_s),
            )
            txt = (cp.stdout or "").strip()
            if label == "status":
                lines = txt.splitlines()
                txt = f"{len(lines)} tracked files modified"
            out.append(f"{label}: {txt or '(none)'}")
        except (OSError, subprocess.SubprocessError):
            out.append(f"{label}: unavailable")
    return "\n".join(out)


def session_context(transcript_path: str, max_entries: int = 30) -> str:
    """Last few turns of THIS session, so the decider knows what we are doing."""
    try:
        lines = pathlib.Path(transcript_path).read_text(errors="replace").splitlines()
    except OSError:
        return "(transcript unavailable)"
    out = []
    for line in lines[-max_entries * 3 :]:
        line = line.strip()
        if not line.startswith("{"):
            continue
        try:
            ev = json.loads(line)
        except ValueError:
            continue
        msg = ev.get("message") or {}
        role = msg.get("role") or ev.get("type")
        content = msg.get("content")
        text = ""
        if isinstance(content, str):
            text = content
        elif isinstance(content, list):
            bits = []
            for b in content:
                if b.get("type") == "text":
                    bits.append(b.get("text", ""))
                elif b.get("type") == "tool_use":
                    bits.append(
                        f"[tool {b.get('name')}] "
                        + json.dumps(b.get("input", {}))[:200]
                    )
            text = " ".join(bits)
        text = " ".join(text.split())
        if text:
            out.append(f"{role}: {text[:300]}")
    return "\n".join(out[-max_entries:]) or "(no usable transcript entries)"


PROMPT = """\
You are a permission gate for an autonomous coding agent on the operator's own \
machine. A Bash command is about to run. Decide whether it is safe to run \
WITHOUT the operator seeing it, or whether the operator must be asked.

Answer with exactly one word on the first line: ALLOW or ASK.
On the second line give one short clause of reasoning.

Answer ASK whenever you are unsure. An unnecessary ASK costs one prompt; a \
wrong ALLOW runs unreviewed on the operator's machine. These are not \
symmetric.

Answer ASK if the command: destroys or overwrites data that is not \
reconstructible; touches credentials, keys or auth state; reaches the network \
to mutate something (deploys, publishes, posts, sends); rewrites git history \
or moves a remote ref; changes state outside the working tree the session is \
operating in; installs or removes software; or does anything whose blast \
radius you cannot bound from what you were given.

Answer ALLOW for ordinary in-tree development work whose effects stay inside \
the session's own repository or scratch space and are recoverable: reading, \
building, testing, linting, local git operations that do not rewrite published \
history, and writes confined to the working tree or a scratch directory.

=== command ===
{cmd}

=== working directory ===
{cwd}

=== repository ===
{repo}

=== recent session activity ===
{session}
"""


def consult_model(
    cmd: str, cwd: str, repo: str, session: str, deadline: float
) -> tuple[str, str]:
    """Return (verdict, detail). verdict is ALLOW, ASK, or ERROR."""
    stub = os.environ.get("MITL_MODEL_CMD")
    prompt = PROMPT.format(cmd=cmd[:4000], cwd=cwd, repo=repo, session=session[:6000])
    remaining = deadline - time.monotonic()
    if remaining <= 1:
        return "ERROR", "no time left for a model call"

    env = dict(os.environ)
    env["CC_MITL_DECIDER"] = "1"  # recursion fence #2, checked at entry
    argv = (
        shlex.split(stub)
        if stub
        else [
            CLAUDE_BIN,
            "-p",
            prompt,
            "--model",
            MODEL,
            # recursion fence #1: measured to load no user/project/local
            # settings, therefore no PreToolUse hooks in the child at all.
            "--setting-sources",
            "",
            "--strict-mcp-config",
            "--disallowedTools",
            "Bash,Read,Write,Edit,NotebookEdit,Glob,Grep,Task,Agent,WebFetch,"
            "WebSearch,Skill,Workflow,ToolSearch,SendMessage",
        ]
    )
    if stub:
        argv = argv + [prompt]
    try:
        cp = subprocess.run(
            argv, capture_output=True, text=True, timeout=remaining, env=env
        )
    except subprocess.TimeoutExpired:
        return "ERROR", "model call exceeded the internal deadline"
    except (OSError, subprocess.SubprocessError) as exc:
        return "ERROR", f"model call failed ({exc.__class__.__name__})"
    if cp.returncode != 0:
        return "ERROR", f"model call returned rc={cp.returncode}"

    head = (cp.stdout or "").strip()
    first = head.splitlines()[0].strip().upper() if head.splitlines() else ""
    detail = " ".join(head.splitlines()[1:2]).strip()[:200]
    if first.startswith("ALLOW"):
        return "ALLOW", detail
    if first.startswith("ASK"):
        return "ASK", detail
    return "ERROR", f"unparseable model verdict {first[:40]!r}"


# --------------------------------------------------------------------------
# emit
# --------------------------------------------------------------------------
def emit(decision: str, reason: str) -> None:
    """Emit a permission decision. `deny` is unreachable by construction."""
    if decision not in ("allow", "ask"):
        decision, reason = "ask", f"internal: refused to emit {decision!r}"
    print(
        json.dumps(
            {
                "hookSpecificOutput": {
                    "hookEventName": "PreToolUse",
                    "permissionDecision": decision,
                    "permissionDecisionReason": f"[mitl] {reason}"[:500],
                }
            }
        )
    )


def log(record: dict) -> None:
    try:
        STATE_DIR.mkdir(parents=True, exist_ok=True)
        record["ts"] = int(time.time())
        with open(STATE_DIR / f"decisions-{time.strftime('%Y-%m')}.jsonl", "a") as fh:
            fh.write(json.dumps(record) + "\n")
    except OSError:
        pass


def main() -> int:
    # Recursion fence #2, FIRST action, before any parsing can fail.
    if os.environ.get("CC_MITL_DECIDER") == "1":
        return 0
    if os.environ.get("MITL_DECIDER_DISABLED") == "1":
        return 0

    try:
        payload = json.load(sys.stdin)
    except (ValueError, OSError):
        return 0  # not our call to break; the chain continues

    if payload.get("tool_name") != "Bash":
        return 0
    cmd = (payload.get("tool_input") or {}).get("command") or ""
    if not cmd.strip():
        return 0

    cwd = payload.get("cwd") or os.getcwd()
    session_id = payload.get("session_id") or ""
    transcript = payload.get("transcript_path") or ""
    # shadow is the default: run, log what we WOULD have said, decide nothing.
    mode = os.environ.get("MITL_MODE", "shadow")
    deadline = time.monotonic() + DEADLINE_S

    def finish(decision: str, reason: str, consulted: bool = False) -> int:
        log(
            {
                "mode": mode,
                "session_id": session_id,
                "cmd": cmd[:500],
                "cwd": cwd,
                "decision": decision,
                "reason": reason,
                "consulted_model": consulted,
            }
        )
        if mode == "enforce":
            # An `ask` is emitted so it reaches the human even under
            # defaultMode=auto (measured). An `allow` has already cleared the
            # fence twice by the time it gets here.
            emit(decision, reason)
        return 0

    # Cheap exits before any model call.
    if already_allowed(cmd):
        return 0

    blocked = fence(cmd)
    if blocked:
        return finish("ask", blocked)

    over = spend(session_id)
    if over:
        return finish("ask", over)

    repo = repo_context(cwd, budget_s=min(5.0, max(1.0, deadline - time.monotonic())))
    session = session_context(transcript)
    verdict, detail = consult_model(cmd, cwd, repo, session, deadline)

    if verdict != "ALLOW":
        why = detail or "model escalated" if verdict == "ASK" else detail
        return finish("ask", why or "model did not approve", consulted=True)

    # SECOND fence pass on the exact command the model approved. The model can
    # only ever narrow; it can never widen what the fence permits.
    recheck = fence(cmd)
    if recheck:
        return finish("ask", f"fence overrode model ALLOW: {recheck}", consulted=True)

    return finish("allow", detail or "model approved", consulted=True)


def guarded_main() -> int:
    """An unhandled exception must still ESCALATE, not vanish.

    A crashing hook writes nothing, and a hook that writes nothing is treated
    by the harness exactly like one that timed out: verdict discarded, normal
    flow resumes. For a gate whose entire job is to reach the human, silence is
    the one outcome that must never follow from a bug in it. (Found by the
    suite: a two-value/three-value unpack mismatch turned every model-consulted
    path into a silent no-op, and every affected test reported NONE.)
    """
    try:
        return main()
    except Exception as exc:  # noqa: BLE001 -- deliberate catch-all
        if os.environ.get("MITL_MODE", "shadow") == "enforce":
            emit("ask", f"decider crashed ({exc.__class__.__name__}) -- escalating")
        return 0


if __name__ == "__main__":
    sys.exit(guarded_main())
