#!/bin/bash
# Does each account's dedicated login browser get the Authorize page, or get bounced to a re-login?
# SAFE: opens an authorize URL with DUMMY PKCE values and never clicks anything. No `claude auth
# login` runs and no code is exchanged, so no credential or keychain item is touched.
# Answers "can this account's login browser still reach the Authorize page?" for each account.
# A fresh sign-in passes and ages out over time (measured 2026-09-22), so re-run it to find when.
set -u
python3 - next next2 next3 next4 <<'EOF'
import importlib.machinery, importlib.util, json, os, sys, time, urllib.parse
CA = os.path.expanduser("~/.claude/bin/cc-relogin")
ccr = importlib.util.module_from_spec(importlib.util.spec_from_loader(
    "ccr", importlib.machinery.SourceFileLoader("ccr", CA)))
importlib.machinery.SourceFileLoader("ccr", CA).exec_module(ccr)
q = urllib.parse.urlencode({
    "code": "true", "client_id": "9d1c250a-e61b-44d9-88ed-5944d1962f5e",
    "response_type": "code",
    "redirect_uri": "https://platform.claude.com/oauth/code/callback",
    "scope": "org:create_api_key user:profile user:inference user:sessions:claude_code user:mcp_servers user:file_upload",
    "code_challenge": "PROBEonlyPROBEonlyPROBEonlyPROBEonlyPROBEon",
    "code_challenge_method": "S256", "state": "probe-never-exchanged"})
JS = """(async()=>{
  let who='?'; try{const r=await fetch('https://claude.ai/api/account',{credentials:'include'});
    who=r.status===200?(await r.json()).email_address:('none (http '+r.status+')');}catch(e){who='err'}
  const auth=[...document.querySelectorAll('button,[role=button]')]
    .some(b=>/^(authorize|allow|approve)/i.test((b.innerText||'').trim()));
  return JSON.stringify({reauth:/reauth=1/.test(location.search)||location.pathname.startsWith('/login'),
                         authorize:auth, session:who, where:location.host+location.pathname,
                         title:document.title,
                         text:(document.body?document.body.innerText:'').replace(/\\s+/g,' ').slice(0,140)});})()"""
for acct in sys.argv[1:]:
    rc, out = ccr.authbrowser(acct, "--start", "--json")
    if rc != 0:
        print(f"{acct:6}  browser failed to start (rc={rc})"); continue
    try:
        cdp = ccr.CDP(json.loads(out)["ws_url"])
        tid = cdp.send("Target.createTarget", {"url": f"https://claude.com/cai/oauth/authorize?{q}"})["targetId"]
        s = cdp.send("Target.attachToTarget", {"targetId": tid, "flatten": True})["sessionId"]
        # Poll until the page SETTLES on one of the two answers (max 30s): a single look after a
        # fixed sleep read a still-rendering page as UNCLEAR on a loaded box.
        deadline, r = time.monotonic() + 30, {}
        while time.monotonic() < deadline:
            time.sleep(2)
            try:
                r = json.loads((cdp.send("Runtime.evaluate", {"expression": JS, "returnByValue": True,
                                "awaitPromise": True}, s).get("result") or {}).get("value") or "{}")
            except (ValueError, TypeError):
                continue
            if r.get("authorize") or r.get("reauth"):
                break
        verdict = ("AUTHORIZE PAGE — unattended relogin can work" if r.get("authorize") else
                   "BOUNCED to re-login" if r.get("reauth") else "UNCLEAR after 30s")
        print(f"{acct:6}  {verdict:46}  signed in as: {r.get('session')}")
        if verdict.startswith("UNCLEAR"):
            print(f"        page: {r.get('where')}  title: {r.get('title')!r}\n        text: {r.get('text')}")
    finally:
        ccr.authbrowser(acct, "--stop")
EOF
