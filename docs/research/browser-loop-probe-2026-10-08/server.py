#!/usr/bin/env python3
"""Serve the fixed form task and record every "Save lead" POST.

The record is written by the server, not read back from the page, so a run is scored on what the
form actually submitted whatever the driving loop did to the tab afterwards.

Usage: python3 -I server.py <port> <out.jsonl>
"""

import http.server
import json
import pathlib
import sys
import time

ROOT = pathlib.Path(__file__).resolve().parent / "fixture"


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *a, **kw):
        super().__init__(*a, directory=str(ROOT), **kw)

    def do_POST(self):
        if self.path != "/save":
            self.send_error(404)
            return
        body = self.rfile.read(int(self.headers.get("Content-Length") or 0))
        try:
            lead = json.loads(body)
        except ValueError:
            self.send_error(400)
            return
        lead["_ts"] = time.time()
        with open(OUT, "a", encoding="utf-8") as fh:
            fh.write(json.dumps(lead) + "\n")
        self.send_response(204)
        self.end_headers()

    def log_message(self, *a):
        pass


if __name__ == "__main__":
    port, OUT = int(sys.argv[1]), sys.argv[2]
    http.server.ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()
