"""Read next3's quota meters only: usage endpoint (+ raw fields) and one wire call.

Imports bin/claude-accounts as a module so the token never leaves this process.
Appends one JSON line to /tmp/w2probe/meters.jsonl and prints it.
Usage: python3 meter.py <label> [--no-wire]
"""

import importlib.machinery
import importlib.util
import json
import sys
import datetime

SRC = "/Users/chrisren/Development/claude-infrastructure/bin/claude-accounts"
loader = importlib.machinery.SourceFileLoader("ca", SRC)
spec = importlib.util.spec_from_loader("ca", loader)
ca = importlib.util.module_from_spec(spec)
loader.exec_module(ca)

label = sys.argv[1] if len(sys.argv) > 1 else "read"
cfg = ca.load_cfg(need_claude_bin=False)
acct = next(a for a in cfg["accounts"] if a["name"] == "next3")
kc = acct.get("keychain_account") or cfg.get("keychain_account")
creds, state = ca.read_creds(acct["config_dir"], kc)
if not creds:
    sys.exit(f"no creds: {state}")
token = creds.get("accessToken")
status, u = ca.fetch_usage(cfg, token, retries=0)
row = {
    "label": label,
    "ts": datetime.datetime.now().astimezone().isoformat(timespec="seconds"),
    "usage_http": status,
    "usage": u,
}
if "--no-wire" not in sys.argv:
    w = ca.fetch_wire_limits(cfg, token)
    row["wire"] = w
with open("/tmp/w2probe/meters.jsonl", "a") as f:
    f.write(json.dumps(row) + "\n")
print(json.dumps(row, indent=1))
