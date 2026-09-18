#!/usr/bin/env python3
"""test-union-batch-schema.py — red-proof for union-batch.py's request/response shapes.

Runs OFFLINE: urlopen is replaced, so nothing is sent and no key is needed.

WHY IT EXISTS. `union-alpha` is reachable on three routes with TWO different APIs —
OpenRouter and Cloudflare speak OpenAI chat-completions, while OpenCode Zen (the only route
that calls the model FREE in its own words) speaks the ANTHROPIC MESSAGES schema. The two
differ in ways that fail SILENTLY rather than loudly:

  · `system` is a top-level field in Messages and a message ROLE in OpenAI. Send it as a role
    to Messages and it is not an error — the instruction is simply ignored.
  · A Messages reply is a LIST OF CONTENT BLOCKS. Concatenating every block folds a thinking
    or tool block into the answer, which reads as the model rambling rather than as a bug.

Both produce plausible output, so only an assertion catches them.  Run: python3 <this file>
"""
import importlib.util, json, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("ub", HERE / "union-batch.py")
ub = importlib.util.module_from_spec(spec); spec.loader.exec_module(ub)

fails = 0
def ck(cond, name):
    global fails
    print(("  PASS " if cond else "  FAIL ") + name)
    if not cond: fails += 1

sent = {}
class FakeResp:
    def __init__(self, payload): self._p = json.dumps(payload).encode()
    def read(self): return self._p
    def __enter__(self): return self
    def __exit__(self, *a): return False

def fake_urlopen(req, timeout=None, context=None):
    sent["url"] = req.full_url
    sent["headers"] = {k.lower(): v for k, v in req.headers.items()}
    sent["body"] = json.loads(req.data.decode())
    return FakeResp(sent["_reply"])

ub.urllib.request.urlopen = fake_urlopen

print("=== ANTHROPIC schema (OpenCode Zen) ===")
sent["_reply"] = {"content": [{"type": "thinking", "text": "SHOULD NOT APPEAR"},
                              {"type": "text", "text": "READY"}],
                  "stop_reason": "end_turn", "usage": {"input_tokens": 5, "output_tokens": 1}}
r = ub.call_once("KEY", "union-alpha", "hi", "be terse", 32, 30,
                 ub.ZEN_ENDPOINT, schema="anthropic", auth="bearer")
ck(sent["url"] == ub.ZEN_ENDPOINT, "posts to the zen /v1/messages endpoint")
ck("system" in sent["body"], "`system` is a TOP-LEVEL field (Messages API)")
ck(all(m["role"] != "system" for m in sent["body"]["messages"]), "no system ROLE in messages")
ck("stream" not in sent["body"], "no OpenAI-only `stream` key leaks into the anthropic body")
ck(r["text"] == "READY", f"text from content BLOCKS only (got {r['text']!r})")
ck("SHOULD NOT APPEAR" not in r["text"], "a non-text block is NOT folded into the answer")
ck(r["finish_reason"] == "end_turn", "stop_reason mapped to finish_reason")

print("\n=== x-api-key auth style ===")
ub.call_once("KEY", "m", "hi", None, 8, 30, ub.ZEN_ENDPOINT, "anthropic", "x-api-key")
ck(sent["headers"].get("x-api-key") == "KEY", "x-api-key header set")
ck("authorization" not in sent["headers"], "no Authorization header when x-api-key is chosen")
ck(sent["headers"].get("anthropic-version") is not None, "anthropic-version sent")

print("\n=== OPENAI schema unchanged (regression) ===")
sent["_reply"] = {"choices": [{"message": {"content": "OK"}, "finish_reason": "stop"}],
                  "model": "x", "usage": {}}
r2 = ub.call_once("KEY", "m", "hi", "sys", 16, 30, ub.ENDPOINT, "openai", "bearer")
ck(any(m["role"] == "system" for m in sent["body"]["messages"]), "system stays a ROLE for openai")
ck(sent["body"].get("stream") is False, "openai body still carries stream:false")
ck(r2["text"] == "OK", "openai text still parsed from choices[].message")
ck(sent["headers"].get("authorization") == "Bearer KEY", "bearer header for openai")

print(f"\nSUITE: {'PASS' if not fails else str(fails) + ' FAILURE(S)'}")
sys.exit(1 if fails else 0)
