#!/usr/bin/env python3
"""Finish the 2026-10-01 kitty-restart resume from inside the new kitty.

Runs boot-resume rounds (private state dir, the saved 32-session roster) with the capacity ceiling
raised to the fleet's normal operating band, fullscreens every new OS window with kitty's own
toggle_fullscreen action (the AX title match fails once Claude retitles the pane), then sends each
resumed session the one-time recovery prompt. Log: /tmp/inboot-2026-10-01/finish.log
"""

import importlib.util, json, os, re, sys, time

spec = importlib.util.spec_from_file_location("krr", "/tmp/kitty-restart-resume.py")
krr = importlib.util.module_from_spec(spec)
spec.loader.exec_module(krr)

D, STATE = krr.D, krr.STATE
NEW = int(sys.argv[1]) if len(sys.argv) > 1 else 48854
SOCK = "unix:/tmp/kitty-%d" % NEW
SELF_SID = "09c26b2b-dd82-4cf2-b884-395d02cbddf1"
CEIL = os.environ.get("FINISH_MAX_LOAD_PER_CORE", "6")


def kls():
    rc, out, _ = krr.sh([krr.KITTEN, "@", "--to", SOCK, "ls"], timeout=15)
    try:
        return json.loads(out) if rc == 0 else []
    except ValueError:
        return []


def os_windows():
    """{os_window_id: [window ids]}"""
    return {o["id"]: [w["id"] for t in o["tabs"] for w in t["windows"]] for o in kls()}


sids = [s for s in open(os.path.join(D, "roster-sids.txt")).read().split() if s]
seen_os = set(os_windows())
marker = os.path.join(STATE, "last-boot-epoch")
for rnd in range(1, 13):
    live = {
        r.get("session_id") for r in (krr.roster() or []) if r.get("kitty_pid") == NEW
    }
    missing = [s for s in sids if s not in live]
    krr.log(
        "round %d: %d of %d back, %d missing"
        % (rnd, len(sids) - len(missing), len(sids), len(missing))
    )
    if not missing:
        break
    l1 = os.getloadavg()[0]
    krr.log("round %d: load %.1f" % (rnd, l1))
    if os.path.exists(marker):
        os.remove(marker)
    env = krr.clean_env(
        {
            "CC_BOOTTIME_OVERRIDE": str(int(time.time())),
            "CC_BOOT_RESUME_MODE": "resume",
            "CC_BOOT_RESUME_STATE_DIR": STATE,
            "CC_BOOT_RESUME_ROSTER_DIR": D,
            "CC_TERM_KITTY_TO": SOCK,
            "CC_ADMIT_MAX_LOAD_PER_CORE": CEIL,
        }
    )
    rc, out, err = krr.sh(["/bin/bash", krr.BOOT_RESUME], timeout=1800, env=env)
    try:
        v = [
            l for l in open(os.path.join(STATE, "last-layout.out")) if "verdict=" in l
        ][-1].strip()
    except (OSError, IndexError):
        v = "no layout verdict"
    krr.log("round %d: boot-resume rc=%d · %s" % (rnd, rc, v))
    time.sleep(20)
    now = os_windows()
    for oid, wids in now.items():
        if oid not in seen_os and wids:
            r2, _, _ = krr.sh(
                [
                    krr.KITTEN,
                    "@",
                    "--to",
                    SOCK,
                    "action",
                    "--match",
                    "id:%d" % wids[0],
                    "toggle_fullscreen",
                ],
                timeout=10,
            )
            krr.log("fullscreen os-window %d (window %d): rc=%d" % (oid, wids[0], r2))
            time.sleep(3)
    seen_os |= set(now)
    time.sleep(60)

time.sleep(60)
rows = {
    r.get("session_id"): r for r in (krr.roster() or []) if r.get("kitty_pid") == NEW
}
missing = [s for s in sids if s not in rows]
with open(os.path.join(D, "missing.txt"), "w") as fh:
    fh.write("\n".join(missing) + ("\n" if missing else ""))
prompt = krr.PROMPT.format(hm="13:29")
sent = 0
for sid in sids:
    r = rows.get(sid)
    if not r or sid == SELF_SID or not str(r.get("paneUUID", "")).isdigit():
        continue
    rc, _, _ = krr.sh(
        [
            krr.KITTEN,
            "@",
            "--to",
            SOCK,
            "send-text",
            "--match",
            "id:%s" % r["paneUUID"],
            prompt + "\r",
        ],
        timeout=15,
    )
    sent += rc == 0
    krr.log("recovery prompt -> pane %s (%s): rc=%d" % (r["paneUUID"], sid[:8], rc))
krr.log(
    "DONE: %d of %d back, %d prompted, missing listed in %s/missing.txt"
    % (len(sids) - len(missing), len(sids), sent, D)
)
