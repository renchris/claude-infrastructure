"""A9: how much per-turn hook context is a REPEAT the model already holds (read-only).

Usage: python3 -I a9-ups-repeat.py <file-list> <since-iso>

Walks each main transcript in order. For every model-facing hook text (UserPromptSubmit / PostToolUse /
PreToolUse hook_additional_context elements, and Stop hook_blocking_error reasons) it assigns a
category by prefix signature and a normalised body (digits stripped, so a changed pid/count/time does
not count as new information). A text is a REPEAT when the same (category, normalised body) was
already injected in this transcript since the last compact boundary (/compact or auto-compact
rewrites the context, so a re-injection after it is not a repeat). Also splits UserPromptSubmit
injections by whether the prompt that triggered them was a machine prompt ('<'-prefixed:
task-notification etc.) or a human/other prompt.
"""

import json
import re
import sys
from collections import defaultdict

flist, since = sys.argv[1], sys.argv[2]

CATS = [
    ("wake:goal-inert-crumb", re.compile(r"YOUR /goal WAS SKIPPED")),
    ("wake:parked-watcher", re.compile(r"A parked watcher is holding")),
    (
        "wake:goal-live-no-arm",
        re.compile(r"No inbox wake path armed\.\s*\(a /goal is LIVE"),
    ),
    ("wake:no-watcher", re.compile(r"No inbox wake path armed")),
    ("peer-mail", re.compile(r"peer mail")),
    ("memory-budget", re.compile(r"MEMORY INDEX BUDGET")),
    ("research-program", re.compile(r"^RESEARCH PROGRAM")),
    ("handoff-intent", re.compile(r"^HANDOFF-INTENT")),
    ("research-precog", re.compile(r"^RESEARCH-INTENT")),
    ("cache-expired", re.compile(r"^PROMPT CACHE")),
    ("episodic-cue", re.compile(r"^EPISODIC CUE")),
    ("relay-verbatim", re.compile(r"RELAY|VERBATIM", re.I)),
    ("lesson-pointer", re.compile(r"recalled lesson pointers")),
    ("plan-agent-teams", re.compile(r"Agent Team|agent-teams|Phase 0", re.I)),
    ("backup-before-write", re.compile(r"[Bb]ackup|WRITE-BOUNDARY|boundary", re.I)),
]


def cat_of(event, text):
    for name, rx in CATS:
        if rx.search(text):
            return event + "/" + name
    return event + "/other:" + text[:40].replace("\n", " ")


def norm(text):
    return re.sub(r"\d+", "#", text)


tot = defaultdict(lambda: [0, 0, 0, 0])  # cat -> [n, chars, repeat_n, repeat_chars]
ups_by_prompt = defaultdict(lambda: [0, 0])  # machine|human -> [n, chars]
cat_kind = defaultdict(lambda: [0, 0])  # (category, prompt kind) -> [n, chars]
files = 0
for path in open(flist):
    path = path.strip()
    try:
        fh = open(path, errors="replace")
    except OSError:
        continue
    files += 1
    seen = set()
    last_prompt_kind = "human"
    with fh:
        for ln in fh:
            if not (
                '"hook_' in ln
                or '"compact_boundary"' in ln
                or '"type":"user"' in ln
                or '"queued_command"' in ln
            ):
                continue
            try:
                r = json.loads(ln)
            except ValueError:
                continue
            qa = r.get("attachment") if isinstance(r.get("attachment"), dict) else {}
            if qa.get("type") == "queued_command":
                # a prompt delivered from the queue (task-notification, peer wake, typed-ahead):
                # classify by its text when present, else call it queued
                p = qa.get("prompt")
                p = p if isinstance(p, str) else json.dumps(p)[:200]
                last_prompt_kind = (
                    "machine"
                    if p.lstrip().startswith("<") or "task-notification" in p[:200]
                    else "queued-other"
                )
                continue
            if (r.get("timestamp") or "") < since:
                # still track compaction state; skip counting
                pass
            if r.get("type") == "system" and r.get("subtype") == "compact_boundary":
                seen = set()
                continue
            if r.get("type") == "user" and not r.get("isMeta"):
                c = (r.get("message") or {}).get("content")
                if isinstance(c, str):
                    last_prompt_kind = (
                        "machine"
                        if c.lstrip().startswith("<")
                        or c.startswith("Another Claude session sent")
                        else "human"
                    )
                continue
            a = r.get("attachment")
            if not isinstance(a, dict):
                continue
            t = a.get("type")
            ev = a.get("hookEvent") or "?"
            texts = []
            if t == "hook_additional_context" and ev in (
                "UserPromptSubmit",
                "PostToolUse",
                "PreToolUse",
            ):
                c = a.get("content")
                texts = c if isinstance(c, list) else [c or ""]
            elif t == "hook_blocking_error" and ev == "Stop":
                be = a.get("blockingError") or {}
                cmd = (be.get("command") or "?").rsplit("/", 1)[-1]
                texts = [("[%s] " % cmd) + (be.get("blockingError") or "")]
            else:
                continue
            counted = (r.get("timestamp") or "") >= since
            for x in texts:
                if not x:
                    continue
                if ev == "Stop":
                    k = "Stop/" + x.split("]", 1)[0].strip("[")
                else:
                    k = cat_of(ev, x)
                key = (k, norm(x))
                rep = key in seen
                seen.add(key)
                if not counted:
                    continue
                s = tot[k]
                s[0] += 1
                s[1] += len(x)
                if rep:
                    s[2] += 1
                    s[3] += len(x)
                if ev == "UserPromptSubmit":
                    ups_by_prompt[last_prompt_kind][0] += 1
                    ups_by_prompt[last_prompt_kind][1] += len(x)
                    ck = cat_kind[(k, last_prompt_kind)]
                    ck[0] += 1
                    ck[1] += len(x)

print(f"files={files} since={since}")
print("category\tn\tchars\trepeat_n\trepeat_chars\trepeat_share")
for k, (n, c, rn, rc) in sorted(tot.items(), key=lambda x: -x[1][1]):
    print(f"{k}\t{n}\t{c}\t{rn}\t{rc}\t{(rc / c if c else 0):.2f}")
print()
print(
    "UserPromptSubmit injections by triggering prompt kind (n, chars):",
    dict(ups_by_prompt),
)
print("UserPromptSubmit category x prompt kind (n, chars):")
for (k, kind), (n, c) in sorted(cat_kind.items(), key=lambda x: -x[1][1]):
    print(f"  {k}\t{kind}\t{n}\t{c}")
