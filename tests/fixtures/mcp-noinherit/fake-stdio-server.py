#!/usr/bin/env python3
"""Fake stdio MCP server — logs every invocation, so a spawn can be COUNTED.

Used by the W3 no-inherit work (backlog eece54939e7f) as both the live probe subject
and the bats fixture's positive control. It answers `initialize`, `tools/list`, `ping`
and `tools/call` well enough that Claude Code completes its startup handshake — a server
that hangs would stall every session by MCP_TIMEOUT (30 s) and make the probe measure
the timeout instead of the spawn.

usage: fake-stdio-server.py <logfile> [tag]

Each line appended to <logfile> is NDJSON:
  {"t": iso, "ev": "START"|"RECV", "tag": …, "pid": …, "ppid": …, "cwd": …, "method": …}

The START line is what a spawn test counts: one line per server PROCESS, so a session
that never started the server leaves the file absent/empty, and a session that started it
twice is visible as two lines. Nothing here is Claude-Code specific — any MCP client that
launches this binary is recorded.
"""

import json
import os
import sys
import datetime


def main() -> int:
    log_path = sys.argv[1] if len(sys.argv) > 1 else os.environ.get("FAKE_MCP_LOG", "")
    tag = sys.argv[2] if len(sys.argv) > 2 else os.environ.get("FAKE_MCP_TAG", "probe")

    def parent_cmd() -> str:
        # A START line that names only a ppid cannot be attributed once that parent exits — and the
        # parents here are short-lived by nature (`claude mcp list` health-checks a server and dies).
        # Reading the parent's argv AT START is what makes each line self-attributing, so a count can
        # be split between "the session under test" and "some other CLI that happened to run".
        try:
            import subprocess

            return subprocess.run(
                ["ps", "-o", "command=", "-p", str(os.getppid())],
                capture_output=True,
                text=True,
                timeout=5,
            ).stdout.strip()[:400]
        except Exception:
            return ""

    def rec(ev: str, **kw: object) -> None:
        if not log_path:
            return
        row = {
            "t": datetime.datetime.now().isoformat(timespec="microseconds"),
            "ev": ev,
            "tag": tag,
            "pid": os.getpid(),
            "ppid": os.getppid(),
            "cwd": os.getcwd(),
        }
        if ev == "START":
            row["pcmd"] = parent_cmd()
        row.update(kw)
        with open(log_path, "a", encoding="utf-8") as fh:
            fh.write(json.dumps(row) + "\n")
            fh.flush()

    rec("START", argv=sys.argv[1:])

    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            msg = json.loads(line)
        except json.JSONDecodeError:
            continue
        method = msg.get("method")
        mid = msg.get("id")
        rec("RECV", method=method, id=mid)
        if mid is None:  # a notification takes no reply
            continue
        if method == "initialize":
            result: object = {
                "protocolVersion": (msg.get("params") or {}).get(
                    "protocolVersion", "2025-06-18"
                ),
                "capabilities": {"tools": {}},
                "serverInfo": {"name": "fake-noinherit-probe", "version": "1.0.0"},
            }
        elif method == "tools/list":
            result = {
                "tools": [
                    {
                        "name": "probe_ping",
                        "description": "returns PROBE-PONG",
                        "inputSchema": {"type": "object", "properties": {}},
                    }
                ]
            }
        elif method == "tools/call":
            result = {"content": [{"type": "text", "text": "PROBE-PONG"}]}
        elif method == "ping":
            result = {}
        else:
            sys.stdout.write(
                json.dumps(
                    {
                        "jsonrpc": "2.0",
                        "id": mid,
                        "error": {"code": -32601, "message": "no"},
                    }
                )
                + "\n"
            )
            sys.stdout.flush()
            continue
        sys.stdout.write(
            json.dumps({"jsonrpc": "2.0", "id": mid, "result": result}) + "\n"
        )
        sys.stdout.flush()

    rec("STDIN_EOF")
    return 0


if __name__ == "__main__":
    sys.exit(main())
