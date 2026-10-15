"""kitty_pane_actions — the one writer of ~/.claude/logs/kitty-pane-actions.jsonl.

WHY IT EXISTS. The 2026-10-15 crash (docs/research/kitty-crash-2026-10-15/README.md) was attributed
at 75% and no better because the right-click menu's "Move to <window>" deliberately wrote nothing,
and kitty-confirm-close wrote nothing either. Every pane-menu choice, confirm-close action and
fullscreen-guard verdict now leaves a row here. The INTENT row is written and fsynced BEFORE the
destructive call, so a kitty that segfaults inside that call still leaves its attribution on disk.

Imported by bin/kitty-pane-menu, bin/kitty-confirm-close and bin/kitty-fullscreen-guard through
the checkout's own lib/ (they resolve it from realpath(__file__)), so the schema has one owner.

Row fields (absent ones are omitted, never invented): ts, tool, phase (intent|result|verdict),
choice, wid, os_window_id, platform_window_id, panes, state, verdict, rc, detail, pid.

Best-effort by contract: a menu pick or a close must never fail on its own bookkeeping, so every
error here is swallowed. Path: $CC_KITTY_PANE_ACTIONS_LOG, else $HOME/.claude/logs/... — HOME and
not CLAUDE_CONFIG_DIR, because the four account config dirs would otherwise split one machine's
pane history across four files.
"""

from __future__ import annotations

import json
import os
import time


def log_path() -> str:
    return os.environ.get("CC_KITTY_PANE_ACTIONS_LOG") or os.path.join(
        os.path.expanduser("~"), ".claude", "logs", "kitty-pane-actions.jsonl"
    )


def log_row(tool: str, phase: str, **fields: object) -> None:
    row: dict[str, object] = {
        "ts": time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime())
        + ".%03dZ" % (int(time.time() * 1000) % 1000),
        "tool": tool,
        "phase": phase,
        "pid": os.getpid(),
    }
    row.update({k: v for k, v in fields.items() if v is not None})
    path = log_path()
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        fd = os.open(path, os.O_WRONLY | os.O_APPEND | os.O_CREAT, 0o600)
        try:
            os.write(
                fd,
                (json.dumps(row, separators=(",", ":"), default=str) + "\n").encode(),
            )
            os.fsync(fd)
        finally:
            os.close(fd)
    except (OSError, TypeError, ValueError):
        pass
