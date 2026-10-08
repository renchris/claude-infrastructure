# sample.py <claude-accounts path> <acct> <out.jsonl> <interval_s> <stopfile>
# Wire-header sampler: one max_tokens:1 Haiku 5.5 call per sample (~25 tokens). No email written.
import importlib.machinery, importlib.util, sys, json, time, os, subprocess
loader = importlib.machinery.SourceFileLoader("ca", sys.argv[1]); spec = importlib.util.spec_from_loader("ca", loader); ca = importlib.util.module_from_spec(spec); loader.exec_module(ca)
acct_name, out, iv, stop = sys.argv[2], sys.argv[3], float(sys.argv[4]), sys.argv[5]
cfg = ca.load_cfg(need_claude_bin=False); acct = [a for a in cfg["accounts"] if a["name"] == acct_name][0]
cdir = os.path.expanduser(acct["config_dir"])
while not os.path.exists(stop):
    creds, st = ca.read_creds(acct["config_dir"], cfg["keychain_account"])
    w = ca.fetch_wire_limits(cfg, (creds or {}).get("accessToken"))
    # foreign headless processes on this account (env visible for same-user processes)
    try:
        ps = subprocess.run(["ps", "eww", "-axo", "pid=,command="], capture_output=True, text=True, timeout=20).stdout
        n = sum(1 for l in ps.splitlines() if " -p " in l and f"CLAUDE_CONFIG_DIR={cdir} " in l and "haiku55-burn" not in l)
    except Exception: n = None
    rec = {"ts": time.time(), "iso": time.strftime("%Y-%m-%dT%H:%M:%S"), "wire": w, "foreign_p": n}
    with open(out, "a") as f: f.write(json.dumps(rec) + "\n")
    time.sleep(iv)
