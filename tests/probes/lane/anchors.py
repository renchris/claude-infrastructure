"""Binary-parametric anchors for the lane design: each is found by a REGEX over the binary's embedded source,
never by a byte offset or a minified name, so a new release (the ruled >= 2.1.301 upgrade) re-certifies by
re-running the same scan. A missing anchor means the mechanism moved: the probes must be re-derived before a
lane is armed on that binary (R14). Values the design depends on (the keychain read-cache interval, which
bounds pointer-lane adoption) are extracted and recorded, not assumed.
"""

from __future__ import annotations

import mmap
import re
from pathlib import Path

ANCHORS: dict[str, tuple[bytes, str]] = {
    # uw(): the lane variable is read inside a function on every call, falling back to the config dir
    "lane_var_read_per_call": (
        rb'="-credentials";function [\w$]+\(\)\{let ([\w$]+)=process\.env\.CLAUDE_SECURESTORAGE_CONFIG_DIR;'
        rb"if\(\1!==void 0\)return",
        "credential store dir = CLAUDE_SECURESTORAGE_CONFIG_DIR, read per call (uw)",
    ),
    "refresh_lock_file": (
        rb'"\.oauth_refresh\.lock"',
        "per-store refresh lock the pointer lane shares",
    ),
    "keychain_read_cache": (
        rb"[\w$]+=(\d+);class [\w$]+\{cache=\{data:null,cachedAt:0\}",
        "per-session keychain read cache (bounds pointer adoption)",
    ),
    "thread_404_replay": (
        rb'status===404\)return [\w$]+\.includes\("thread_not_found"\)',
        "first call on a new org: thread_not_found is replayed, not fatal",
    ),
    "mod_env_set_op": (
        rb'"env\.get","env\.set"\]',
        "hooks-module op env.set (the binding actuator)",
    ),
    "mod_turn_step_event": (
        rb'"turn\.start","turn\.step","turn\.complete"',
        "per-request hook turn.step",
    ),
    "mod_session_measure_event": (
        rb'"session\.measure"',
        "session.measure (the utilization sensor)",
    ),
    "oauth_401_keychain_recovery": (
        rb"tengu_oauth_401_recovered_from_keychain",
        "401 re-reads the store",
    ),
    "org_header": (rb"anthropic-organization-id", "billing observer header"),
}


def scan(binary: Path) -> dict:
    with open(Path(binary).resolve(), "rb") as f:
        m = mmap.mmap(f.fileno(), 0, access=mmap.ACCESS_READ)
        found: dict[str, dict] = {}
        for name, (pat, what) in ANCHORS.items():
            hit = re.search(pat, m)
            row = {"found": bool(hit), "what": what}
            if hit and name == "keychain_read_cache":
                row["value_ms"] = int(hit.group(1))
            found[name] = row
        m.close()
    missing = [k for k, v in found.items() if not v["found"]]
    cache = found["keychain_read_cache"].get("value_ms")
    ok = not missing
    summary = (
        f"{len(found) - len(missing)}/{len(found)} anchors found"
        + (f"; keychain read cache {cache} ms" if cache else "")
        + (f"; MISSING {', '.join(missing)}" if missing else "")
    )
    return {"ok": ok, "summary": summary, "anchors": found, "keychain_cache_ms": cache}


if __name__ == "__main__":
    import json
    import sys

    print(json.dumps(scan(Path(sys.argv[1])), indent=2))
