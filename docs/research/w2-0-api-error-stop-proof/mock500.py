# T9 arm C — a REACHABLE Anthropic endpoint that returns 500 on /v1/messages.
# Reachability is the point: arm B refused the TCP connection, which the client may classify
# earlier and differently than a real api_error from a server that answered. This narrows the
# one variable that arm B could not control.
import sys, json
from http.server import BaseHTTPRequestHandler, HTTPServer
LOG = sys.argv[2] if len(sys.argv) > 2 else "/dev/null"
class H(BaseHTTPRequestHandler):
    def _log(self, s):
        with open(LOG, "a") as f: f.write(s + "\n")
    def do_POST(self):
        n = int(self.headers.get("content-length", 0) or 0)
        self.rfile.read(n)
        self._log("HIT POST " + self.path)
        body = json.dumps({"type":"error","error":{"type":"api_error","message":"T9 probe: synthetic 500"}}).encode()
        self.send_response(500)
        self.send_header("content-type","application/json")
        self.send_header("content-length",str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def do_GET(self):
        self._log("HIT GET " + self.path)
        self.send_response(500); self.send_header("content-length","0"); self.end_headers()
    def log_message(self, *a): pass
HTTPServer(("127.0.0.1", int(sys.argv[1])), H).serve_forever()
