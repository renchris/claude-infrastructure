#!/usr/bin/env python3
"""collect.py <run-dir> <task-id> — metrics.json + blind dossier.md for one F1 run.

Reads <run-dir>/out/{result.json,rc,time,stderr.txt,config_dir,arm} and the session transcripts
(main + subagents) under the run's config dir. Writes <run-dir>/out/metrics.json and
<run-dir>/out/dossier.md. The dossier carries the prompt, the final message, every tool call
with a short result, the repo state and the task's outcome checks. It never carries the arm:
the run path is rewritten to /work, and any tool result that reads the memory files under
.claude/ is redacted.

Failure classes (from ERROR TEXT only, never from spend — a quota wall can arrive after a fully
billed stream): quota (rate/usage limit, overloaded), auth, timeout, other. Push outcomes are
recorded as their own fields: attempted / refused (permission denial) / succeeded.
"""

import glob, json, os, re, subprocess, sys

RUN, TASK = sys.argv[1].rstrip("/"), sys.argv[2]
H = os.path.dirname(os.path.abspath(__file__))
OUT, FX = f"{RUN}/out", f"{RUN}/fx"
ORIGIN = f"{RUN}/origin.git"
# F3 runs keep their own tasks, rubric and verifier (harness/f3/); unset, these are the F1 defaults.
rub = json.load(open(os.environ.get("GATE_RUBRICS", f"{H}/rubrics.json")))[TASK]
prompt = (
    open(os.path.join(os.environ.get("GATE_TASKS", f"{H}/tasks"), TASK, "prompt.txt"))
    .read()
    .strip()
)
VERIFY = os.environ.get("GATE_VERIFY", "")
ccd = open(f"{OUT}/config_dir").read().strip()
arm = open(f"{OUT}/arm").read().strip()
rc = int(open(f"{OUT}/rc").read().strip() or 1)
st, en = map(int, open(f"{OUT}/time").read().split())
stderr = open(f"{OUT}/stderr.txt", errors="replace").read()
try:
    res = json.load(open(f"{OUT}/result.json"))
except Exception:
    res = {}

QUOTA = re.compile(
    r"usage limit|rate[ _-]?limit|\b429\b|overloaded|\b529\b|limit reached|quota|too many requests",
    re.I,
)
AUTH = re.compile(
    r"not logged in|invalid api key|oauth|\b401\b|authentication|please run /login",
    re.I,
)
REFUSAL = re.compile(
    r"haven't granted|permission|denied|not allowed|blocked by|require[sd]? approval|auto mode",
    re.I,
)
# Blinding: a tool result is redacted only if it carries actual text of an arm's memory files
# (any line of >= 40 chars from either arm). Paths alone do not reveal the arm.
G = os.environ.get("GATE_ROOT", "/tmp/tokeff-gate")
ARM_LINES = set()
for f in glob.glob(f"{G}/arms/*/CLAUDE.md") + glob.glob(f"{G}/arms/*/rules/*.md"):
    ARM_LINES |= {
        ln.strip() for ln in open(f, errors="replace") if len(ln.strip()) >= 40
    }


def fail_class():
    txt = " ".join(
        [str(res.get("result", "")) if res.get("is_error") else "", stderr[-4000:]]
    )
    if rc == 0 and not res.get("is_error"):
        return "ok"
    if QUOTA.search(txt):
        return "quota"
    if AUTH.search(txt):
        return "auth"
    if rc == 124:
        return "timeout"
    return "other"


sid = res.get("session_id")
main = glob.glob(f"{ccd}/projects/*/{sid}.jsonl") if sid else []
subs = []
for m in main:
    subs += glob.glob(
        os.path.join(m[:-6], "subagents", "**", "*.jsonl"), recursive=True
    )


def recs(path):
    for line in open(path, errors="replace"):
        try:
            yield json.loads(line)
        except Exception:
            pass


def neutral(s):
    return s.replace(f"/private{RUN}", "/work").replace(RUN, "/work")


tool_errors = hook_blocks = stop_fb = 0
calls, results = [], {}
skills, agents = [], 0
for path in main + subs:
    tag = "" if path in main else "[subagent] "
    for r in recs(path):
        msg = r.get("message") or {}
        content = msg.get("content") if isinstance(msg, dict) else None
        if (
            r.get("type") == "attachment"
            and (r.get("attachment") or {}).get("type") == "hook_blocking_error"
        ):
            hook_blocks += 1
        if r.get("type") == "user":
            if r.get("isMeta"):
                txt = (
                    content
                    if isinstance(content, str)
                    else " ".join(
                        c.get("text", "")
                        for c in (content or [])
                        if isinstance(c, dict)
                    )
                )
                if txt.lstrip().startswith("Stop hook feedback"):
                    stop_fb += 1
            if isinstance(content, list):
                for c in content:
                    if isinstance(c, dict) and c.get("type") == "tool_result":
                        body = c.get("content")
                        if isinstance(body, list):
                            body = " ".join(
                                x.get("text", "") for x in body if isinstance(x, dict)
                            )
                        results[c.get("tool_use_id")] = (
                            bool(c.get("is_error")),
                            str(body or ""),
                        )
                        if c.get("is_error"):
                            tool_errors += 1
        if r.get("type") == "assistant" and isinstance(content, list):
            for c in content:
                if isinstance(c, dict) and c.get("type") == "tool_use":
                    inp = c.get("input", {}) if isinstance(c.get("input"), dict) else {}
                    name = c.get("name")
                    s = (
                        inp.get("command")
                        if name == "Bash" and "command" in inp
                        else json.dumps(inp, ensure_ascii=False)
                    )
                    if name == "Skill":
                        skills.append(inp.get("skill"))
                    if name in ("Agent", "Task"):
                        agents += 1
                    calls.append((c.get("id"), tag, name, s or ""))

push_attempted = push_refused = push_ok = 0
lines = []
for i, (cid, tag, name, s) in enumerate(calls):
    err, body = results.get(cid, (False, ""))
    if name == "Bash" and re.search(r"\bgit\b[^|;&]*\bpush\b", s):
        push_attempted += 1
        if err and REFUSAL.search(body):
            push_refused += 1
        elif not err:
            push_ok += 1
    reads_memory = any(ln in body for ln in ARM_LINES)
    shown = (
        "[redacted: reads harness memory files]"
        if reads_memory
        else neutral(body.strip().replace("\n", " ⏎ "))[:300]
    )
    lines.append(
        f"{i + 1}. {tag}`{name}: {neutral(s)[:300]}`".replace("\n", " ⏎ ")
        + f"\n   → {'ERROR ' if err else ''}{shown}"
    )

u = res.get("usage", {}) or {}
m = dict(
    task=TASK,
    run=os.path.basename(RUN),
    arm=arm,
    account=os.path.basename(ccd),
    rc=rc,
    fail_class=fail_class(),
    cost_usd=res.get("total_cost_usd"),
    input=u.get("input_tokens"),
    cache_creation=u.get("cache_creation_input_tokens"),
    cache_read=u.get("cache_read_input_tokens"),
    output=u.get("output_tokens"),
    turns=res.get("num_turns"),
    duration_s=round((res.get("duration_ms") or 0) / 1000, 1),
    wall_s=en - st,
    is_error=res.get("is_error"),
    tool_calls=len(calls),
    tool_errors=tool_errors,
    hook_blocks=hook_blocks,
    stop_hook_feedback=stop_fb,
    push_attempted=push_attempted,
    push_refused=push_refused,
    push_ok=push_ok,
    skills=skills,
    subagents=agents,
    session_id=sid,
    transcripts=main + subs,
    leaked_tmp=sorted(os.listdir(f"{OUT}/tmp-leaked"))
    if os.path.isdir(f"{OUT}/tmp-leaked")
    else [],
)
# F3 mechanical outcomes: did the run open the situational lessons file (or any lesson body), and
# what did the code verifier say. Read from the tool calls and the fixture, never from the judge.
joined = [s for _, _, _, s in calls]
m["situational_read"] = any("agent-operating-lessons-situational" in s for s in joined)
m["lesson_body_read"] = any("docs/lessons/" in s for s in joined)
m["rules_dir_read"] = any(".claude/rules" in s for s in joined)
verify_out = ""
if VERIFY and os.path.exists(f"{OUT}/plant.sha"):
    plant = open(f"{OUT}/plant.sha").read().strip()
    try:
        vp = subprocess.run(
            ["bash", VERIFY, TASK, FX, plant],
            cwd=FX,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=600,
        )
        verify_out = vp.stdout
        m["verifier"] = {0: "pass", 1: "fail", 3: "judged"}.get(vp.returncode, "error")
    except Exception as e:
        verify_out, m["verifier"] = f"[harness error: {e}]", "error"
    m["verifier_detail"] = (verify_out.strip().splitlines() or [""])[-1][:300]
    m["new_commits"] = int(
        subprocess.run(
            ["git", "-C", FX, "rev-list", "--count", f"{plant}..HEAD"],
            capture_output=True,
            text=True,
        ).stdout.strip()
        or 0
    )
json.dump(m, open(f"{OUT}/metrics.json", "w"), indent=1)


def sh(cmd):
    env = dict(
        os.environ, FX=FX, ORIGIN=ORIGIN, RUN=RUN, PATH=os.environ.get("PATH", "")
    )
    try:
        p = subprocess.run(
            ["bash", "-c", cmd],
            cwd=FX,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=60,
            env=env,
        )
        return neutral(p.stdout.rstrip()) + f"\n[exit {p.returncode}]"
    except Exception as e:
        return f"[harness error: {e}]"


# Diff base: the initial commit (F1 fixtures), or the planted commit for F3, whose clone carries the
# repo's whole history (a root-commit diff would be the entire repository).
BASE = (
    open(f"{OUT}/plant.sha").read().strip()
    if os.path.exists(f"{OUT}/plant.sha")
    else "$(git rev-list --max-parents=0 HEAD 2>/dev/null | tail -1)"
)
D = [
    f"# Dossier\n",
    "## Prompt\n",
    "```\n" + prompt + "\n```\n",
    "## Final assistant message (verbatim)\n",
    "```\n" + neutral(str(res.get("result"))) + "\n```\n",
    f"## Tool calls in order ({len(calls)}), each with the first 300 chars of its result\n",
    "\n".join(lines) + "\n",
    f"Stop-hook feedback turns: {stop_fb}. Hook blocking errors: {hook_blocks}.\n",
    "## Repo state after the run\n",
]
for c in [
    "git status --short --branch",
    "git log --oneline --all --graph -8",
    "git branch -a -v",
    "git ls-remote origin 2>/dev/null || echo '(no origin)'",
    f"git diff {BASE} --stat -- . ':!.claude' 2>/dev/null",
    "git ls-files --others --exclude-standard | grep -v '^.claude' || echo '(no untracked files)'",
]:
    D.append(f"### `{c}`\n```\n{sh(c)}\n```\n")
if os.path.exists(f"{FX}/.git"):
    D.append(
        "### Diff of tracked files vs the base commit\n```diff\n"
        + sh(
            f"git diff {BASE} -- . ':!.claude' | head -200"
        )
        + "\n```\n"
    )
D.append("## Outcome checks (run by the harness after the session)\n")
if verify_out:
    D.append(f"### Harness verifier (code)\n```\n{neutral(verify_out.rstrip())}\n```\n")
for c in rub["checks"]:
    D.append(f"### `{neutral(c)[:160]}`\n```\n{sh(c)}\n```\n")
open(f"{OUT}/dossier.md", "w").write("\n".join(D))
print(
    json.dumps(
        {
            k: m[k]
            for k in (
                "task",
                "run",
                "arm",
                "account",
                "fail_class",
                "cost_usd",
                "turns",
                "tool_errors",
                "hook_blocks",
                "push_attempted",
                "push_refused",
            )
        }
    )
)
