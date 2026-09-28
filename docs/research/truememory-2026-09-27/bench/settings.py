#!/usr/bin/env python3
"""settings.py <arm> <run-dir> <tree> <guard> <hooks-list-out> — print one #35 run's --settings JSON.

Every arm: autoMemoryDirectory (the run's frozen store copy, at a path shaped like a real
projects/<key>/memory dir, which our hooks key memory-ness on) and the f3 sandbox guard.
Arms 2 and 3 add every memory hook the arm's tree registers in settings-templates/settings.example.json,
plus bash-output-offload (registered by migration 0039, not the template), each run from the
exported tree with HOME and CLAUDE_CONFIG_DIR pointed into the run. The list is written to
<hooks-list-out> so the results can name it.
"""

import json
import os
import shlex
import sys
from typing import Any, Dict, List

KEY = "-Users-chrisren-Development-claude-infrastructure"
MEMORY_HOOKS = (
    "memory-nudge",
    "memory-index-drain",
    "backup-before-write",
    "log-bash",
    "bash-output-offload",
    "harvest-skill-end",
)
OFFLOAD = ("PostToolUse", "^Bash$", "~/.claude/hooks/bash-output-offload.sh", 10)


def is_memory_hook(cmd: str) -> bool:
    base = os.path.basename(cmd.split()[0]) if cmd.strip() else ""
    stem = base[:-3] if base.endswith(".sh") else base
    return stem in MEMORY_HOOKS or "memory" in stem or "lesson" in stem


def main(argv: List[str]) -> int:
    arm, run, tree, guard, listout = argv[1:6]
    home = os.path.join(run, "home")
    mem = os.path.join(home, ".claude", "projects", KEY, "memory")
    hooks: Dict[str, List[Dict[str, Any]]] = {
        "PreToolUse": [
            {
                "matcher": "Bash|Edit|Write|MultiEdit|NotebookEdit",
                "hooks": [
                    {
                        "type": "command",
                        "command": f"bash {shlex.quote(guard)} {shlex.quote(run)}",
                    }
                ],
            }
        ]
    }
    listed: List[str] = []
    if arm != "1":
        envp = " ".join(
            f"{k}={shlex.quote(v)}"
            for k, v in (
                ("HOME", home),
                ("CLAUDE_CONFIG_DIR", os.path.join(home, ".claude")),
                ("CC_IDL", os.path.join(home, ".claude", "autonomy", "idl.jsonl")),
                ("MEMORY_NUDGE_STATE_DIR", os.path.join(home, ".claude", "state")),
                ("MEMORY_DRAIN_STATE_DIR", os.path.join(home, ".claude", "state")),
                ("CC_BASH_OFFLOAD_DIR", os.path.join(run, "tmp", "claude-bash-output")),
            )
        )
        with open(
            os.path.join(tree, "settings-templates", "settings.example.json"),
            encoding="utf-8",
        ) as fh:
            tmpl = json.load(fh).get("hooks", {})
        entries = []
        for event, groups in tmpl.items():
            for g in groups:
                for h in g.get("hooks", []):
                    c = h.get("command", "")
                    if h.get("type") == "command" and is_memory_hook(c):
                        entries.append(
                            (event, g.get("matcher", ""), c, h.get("timeout"))
                        )
        if not any(
            os.path.basename(e[2].split()[0]) == "bash-output-offload.sh"
            for e in entries
        ):
            entries.append(OFFLOAD)
        for event, matcher, cmd, timeout in entries:
            live = cmd.replace("~/.claude/hooks/", os.path.join(tree, "hooks") + "/")
            hook: Dict[str, Any] = {"type": "command", "command": f"env {envp} {live}"}
            if timeout:
                hook["timeout"] = timeout
            group: Dict[str, Any] = {"hooks": [hook]}
            if matcher:
                group["matcher"] = matcher
            hooks.setdefault(event, []).append(group)
            listed.append(
                f"{event}\t{matcher or '-'}\t{os.path.basename(cmd.split()[0])}"
            )
    with open(listout, "w", encoding="utf-8") as fh:
        fh.write("".join(line + "\n" for line in listed))
    print(json.dumps({"autoMemoryDirectory": mem, "hooks": hooks}))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
