"""A9: repeat share of model-facing hook text, attributed to the producing command (read-only).

Usage: python3 -I a9-repeat-by-cmd.py <file-list> <since-iso>

Uses hook_success records (which carry `command` and the hook's raw stdout) for PreToolUse /
PostToolUse; parses hookSpecificOutput.additionalContext. A text is a REPEAT when the same
(command, digits-normalised text) already appeared in this transcript since the last compact
boundary. UserPromptSubmit hooks are not covered here: CC records no hook_success for them in this
corpus (their text only appears in the event-level hook_additional_context), see a9-ups-repeat.py.
"""

import json
import re
import sys
from collections import defaultdict

flist, since = sys.argv[1], sys.argv[2]
tot = defaultdict(lambda: [0, 0, 0, 0])
for path in open(flist):
    path = path.strip()
    try:
        fh = open(path, errors="replace")
    except OSError:
        continue
    seen = set()
    with fh:
        for ln in fh:
            if '"compact_boundary"' in ln:
                try:
                    if json.loads(ln).get("subtype") == "compact_boundary":
                        seen = set()
                except ValueError:
                    pass
                continue
            if '"hook_success"' not in ln or "additionalContext" not in ln:
                continue
            try:
                r = json.loads(ln)
            except ValueError:
                continue
            a = r.get("attachment") or {}
            ev = a.get("hookEvent")
            if ev not in ("PreToolUse", "PostToolUse"):
                continue
            try:
                j = json.loads((a.get("stdout") or "").strip())
                ac = (j.get("hookSpecificOutput") or {}).get("additionalContext") or ""
            except (ValueError, AttributeError):
                continue
            if not ac:
                continue
            cmd = (a.get("command") or "?").rsplit("/", 1)[-1]
            # key on the first 60 normalised chars + length bucket: the rule text, not the file name
            body = re.sub(r"\d+", "#", re.sub(r"'[^']*'", "'F'", ac))
            key = (ev, cmd, body)
            rep = key in seen
            seen.add(key)
            if (r.get("timestamp") or "") < since:
                continue
            s = tot[(ev, cmd)]
            s[0] += 1
            s[1] += len(ac)
            if rep:
                s[2] += 1
                s[3] += len(ac)
print("event\tcommand\tn\tchars\trepeat_n\trepeat_chars\trepeat_share")
for (ev, cmd), (n, c, rn, rc) in sorted(tot.items(), key=lambda x: -x[1][1]):
    print(f"{ev}\t{cmd}\t{n}\t{c}\t{rn}\t{rc}\t{rc / c:.2f}")
