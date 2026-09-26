"""hooks/lib/identity.py — the ONE reader of the operator's personal identity values.

WHY THIS EXISTS. This repo is public. Personal values (account e-mails, mailbox aliases, Dia profile
names, the git author address) used to be literals in tracked files; they now live in a gitignored
LOCAL OVERLAY and every consumer reads them through this module (or its bash twin, identity.sh).
The public repo carries only `identity.example.json`, with example-domain values.

RESOLUTION (one rule, shared with identity.sh):
    $CC_IDENTITY_FILE if set, else $HOME/.claude/identity.local.json
The live file is a symlink into the private, remote-less ~/Development/claude-private repo.
An absolute $HOME path — never repo-relative — so all ~90 worktrees and the live layer read the
same bytes, and a hook that runs as a COPY (githooks) resolves it too.

FAILURE DIRECTION. load_identity() returns {} on a missing or unparsable file and never raises.
Each CALLER picks the direction: a display degrades, an allow-list fails CLOSED (empty set).

MERGE, NEVER OVERRIDE. merge_accounts() fills only fields a config row LACKS. A fixture that writes
its own synthetic identity inline therefore wins over the overlay byte-for-byte, which is what keeps
the pre-overlay suites green without edits.
"""

from __future__ import annotations

import json
import os
from typing import Any

ACCOUNT_FIELDS = ("email", "mailbox", "dia_profile")


def identity_path() -> str:
    override = os.environ.get("CC_IDENTITY_FILE")
    if override:
        return override
    return os.path.join(os.path.expanduser("~"), ".claude", "identity.local.json")


def load_identity(path: str | None = None) -> dict[str, Any]:
    p = path or identity_path()
    try:
        with open(p, encoding="utf-8") as fh:
            data = json.load(fh)
    except (OSError, ValueError):
        return {}
    return data if isinstance(data, dict) else {}


def overlay_suppressed(*ssot_env_vars: str) -> bool:
    """True when a caller-specific SSOT override is set and CC_IDENTITY_FILE is not.

    A test that points a reader at a synthetic accounts file must not have the REAL overlay merged
    into it behind its back — that would make a hermetic suite machine-dependent. Same rule
    claude-accounts already applies to its log path when CLAUDE_ACCOUNTS_JSON is set."""
    if os.environ.get("CC_IDENTITY_FILE"):
        return False
    return any(os.environ.get(v) for v in ssot_env_vars)


def merge_accounts(
    cfg: dict[str, Any], ident: dict[str, Any] | None = None
) -> dict[str, Any]:
    """Fill each accounts[] row's missing email/mailbox/dia_profile (keyed by row `name`) and a
    missing top-level keychain_account from the overlay. Mutates and returns cfg."""
    if ident is None:
        ident = load_identity()
    if not ident or not isinstance(cfg, dict):
        return cfg
    per = ident.get("accounts") or {}
    for row in cfg.get("accounts") or []:
        if not isinstance(row, dict):
            continue
        vals = per.get(row.get("name")) or {}
        for field in ACCOUNT_FIELDS:
            if not row.get(field) and vals.get(field):
                row[field] = vals[field]
    if not cfg.get("keychain_account") and ident.get("keychain_account"):
        cfg["keychain_account"] = ident["keychain_account"]
    return cfg


def get(path: str, default: Any = None, ident: dict[str, Any] | None = None) -> Any:
    """Dotted lookup, e.g. get("git_identity.email")."""
    node: Any = load_identity() if ident is None else ident
    for part in path.split("."):
        if not isinstance(node, dict) or part not in node:
            return default
        node = node[part]
    return node


if (
    __name__ == "__main__"
):  # `python3 identity.py git_identity.email` — for shell callers
    import sys

    if len(sys.argv) != 2:
        print("usage: identity.py <dotted.key>", file=sys.stderr)
        sys.exit(2)
    val = get(sys.argv[1])
    if val is None:
        sys.exit(1)
    print(val if isinstance(val, str) else json.dumps(val))
