#!/usr/bin/env python3
"""Minimal stdio JSON-RPC client for the ms-365-mcp-server binary.

WHY THIS EXISTS: the ms365 tools are an MCP server, so they are reachable only
from an agent whose MCP connection is UP. That connection dies (measured
2026-09-19: `ms365 (CONNECTION_CLOSED)` for a whole session) and takes every
mail capability with it. The server is a plain stdio JSON-RPC binary using its
OWN cached token, so driving it directly is independent of Claude Code's
connection state — and scriptable, which an MCP tool call is not.
"""
import json, os, queue, subprocess, threading, time

DEFAULT_BIN = os.path.expanduser(
    "~/Library/Application Support/fnm/aliases/default/bin/ms-365-mcp-server")
DEFAULT_NODE = os.path.expanduser(
    "~/Library/Application Support/fnm/aliases/default/bin/node")


class MS365:
    def __init__(self, timeout=120, binary=None, node=None):
        self.timeout = timeout
        binary = binary or os.environ.get("MS365_BIN", DEFAULT_BIN)
        node = node or os.environ.get("MS365_NODE", DEFAULT_NODE)
        if not os.path.exists(binary):
            raise FileNotFoundError(f"ms-365-mcp-server not found: {binary}")
        if not os.path.exists(node):
            raise FileNotFoundError(f"node not found: {node}")
        self.p = subprocess.Popen(
            [node, binary], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL, text=True, bufsize=1)
        self.q = queue.Queue()
        self._id = 0
        threading.Thread(target=self._reader, daemon=True).start()
        self._rpc("initialize", {
            "protocolVersion": "2025-06-18", "capabilities": {},
            "clientInfo": {"name": "cc-mail-images", "version": "1"}})
        self._send({"jsonrpc": "2.0", "method": "notifications/initialized", "params": {}})

    def _reader(self):
        try:
            for line in self.p.stdout:
                line = line.strip()
                if not line:
                    continue
                try:
                    self.q.put(json.loads(line))
                except Exception:
                    pass
        except Exception:
            pass

    def _send(self, obj):
        self.p.stdin.write(json.dumps(obj) + "\n")
        self.p.stdin.flush()

    def _rpc(self, method, params):
        self._id += 1
        rid = self._id
        self._send({"jsonrpc": "2.0", "id": rid, "method": method, "params": params})
        deadline = time.time() + self.timeout
        stash = []
        while time.time() < deadline:
            try:
                r = self.q.get(timeout=1)
            except queue.Empty:
                continue
            if r.get("id") == rid:
                for x in stash:
                    self.q.put(x)
                return r
            stash.append(r)
        raise TimeoutError(f"{method} timed out after {self.timeout}s")

    def call(self, tool, args=None):
        """Call a tool. Returns parsed JSON when the payload is JSON, else {'_raw': text}."""
        r = self._rpc("tools/call", {"name": tool, "arguments": args or {}})
        if "error" in r:
            raise RuntimeError(f"{tool}: {r['error']}")
        result = r.get("result", {})
        if result.get("isError"):
            raise RuntimeError(f"{tool} returned isError: {result}")
        texts = [c.get("text", "") for c in result.get("content", [])
                 if c.get("type") == "text"]
        blob = "\n".join(texts)
        try:
            return json.loads(blob)
        except Exception:
            return {"_raw": blob}

    def close(self):
        try:
            self.p.stdin.close()
        except Exception:
            pass
        try:
            self.p.kill()
        except Exception:
            pass

    def __enter__(self):
        return self

    def __exit__(self, *a):
        self.close()
