#!/usr/bin/env python3
"""T9 arm-1 mock Anthropic endpoint — the isolation that makes this probe hermetic.

Serves /v1/messages in two modes so the CONTROL and the TEST differ in exactly one variable:
  MODE=ok    → a valid streaming (SSE) assistant turn, so the turn ends NORMALLY
  MODE=error → HTTP 400 with an api_error body, so the turn ends on an API ERROR

Why this exists at all: the probe needs a config dir holding ONLY the hook under test, or the
fleet's ~50 live hooks force turns of their own and a synthesized wake is unreadable in the stream.
A throwaway CLAUDE_CONFIG_DIR has no credentials — but ANTHROPIC_API_KEY=<anything> plus this
endpoint means no credential and no quota are needed at all. Measured 2026-09-17: a throwaway dir
that answered "Not logged in · Please run /login" against the real API reaches the API layer
normally once a dummy key is set.
"""
import json, sys
from http.server import BaseHTTPRequestHandler, HTTPServer

PORT = int(sys.argv[1]); MODE = sys.argv[2]; LOG = sys.argv[3]

SSE = [
    ("message_start", {"type":"message_start","message":{"id":"msg_t9","type":"message",
        "role":"assistant","model":"claude-haiku-4-5-20251001","content":[],
        "stop_reason":None,"stop_sequence":None,
        "usage":{"input_tokens":10,"output_tokens":1}}}),
    ("content_block_start", {"type":"content_block_start","index":0,
        "content_block":{"type":"text","text":""}}),
    ("content_block_delta", {"type":"content_block_delta","index":0,
        "delta":{"type":"text_delta","text":"OK"}}),
    ("content_block_stop", {"type":"content_block_stop","index":0}),
    ("message_delta", {"type":"message_delta",
        "delta":{"stop_reason":"end_turn","stop_sequence":None},"usage":{"output_tokens":1}}),
    ("message_stop", {"type":"message_stop"}),
]

class H(BaseHTTPRequestHandler):
    def _log(self, s):
        with open(LOG, "a") as f: f.write(s + "\n")
    def do_POST(self):
        n = int(self.headers.get("content-length", 0) or 0)
        self.rfile.read(n)
        self._log(f"HIT POST {self.path} mode={MODE}")
        if MODE == "ok":
            self.send_response(200)
            self.send_header("content-type", "text/event-stream")
            self.end_headers()
            for ev, payload in SSE:
                self.wfile.write(f"event: {ev}\ndata: {json.dumps(payload)}\n\n".encode())
                self.wfile.flush()
        else:
            body = json.dumps({"type":"error","error":{
                "type":"api_error","message":"T9 arm-1 probe: synthetic api_error"}}).encode()
            self.send_response(400)
            self.send_header("content-type","application/json")
            self.send_header("content-length",str(len(body)))
            self.end_headers()
            self.wfile.write(body)
    def do_GET(self):
        self._log(f"HIT GET {self.path}")
        self.send_response(404); self.send_header("content-length","0"); self.end_headers()
    def log_message(self, *a): pass

HTTPServer(("127.0.0.1", PORT), H).serve_forever()
