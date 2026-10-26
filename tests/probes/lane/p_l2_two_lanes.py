"""P-L2 — two pointer lanes on one account, and that account's own refresh: count the 401s (SYNTHESIS FM70;
recorded, not gating — AC14).

Two throwaway sessions run concurrently, both pointed at the same account's real store, each making a
string of spaced calls. With pointer lanes there is no copy to go stale: a refresh by any session of that
account (native, or one of these two under the account's own `.oauth_refresh.lock`) rewrites the one store
both read, and a 401 re-reads it. Expected: 0 failed turns, and at most the client's own transparent
retries.

To span a refresh, set LANE_PL2_MAX_WAIT_S: the probe then waits until the account whose token expires
soonest is ~6 min from expiry (if that is within the wait budget) and runs across the expiry. Without it,
the run records whether a refresh happened to fall inside the window. Either way the refresh, if any, is
the account's ordinary one; the probe writes no credential.
"""

from __future__ import annotations

import os
import threading
import time
from pathlib import Path

import lib

PROMPT = (
    "Run the shell command `sleep 8; date +%s` {n} times, each in its own Bash tool call, one at a time, "
    "waiting for each result. Then reply with the word DONE."
)


def run(binary: Path, ctx: dict) -> dict:
    dirs = lib.account_dirs()
    max_wait = float(os.environ.get("LANE_PL2_MAX_WAIT_S", "0"))
    states = {
        n: lib.kc_state(d)
        for n, d in dirs.items()
        if not (d / ".credentials.json").exists()
    }
    live = {n: s for n, s in states.items() if s.get("present") and s.get("life_s")}
    if not live:
        return lib.verdict("P-L2", "INCONCLUSIVE", "no account with a readable store")
    acct = (
        min(live, key=lambda n: live[n]["life_s"])
        if max_wait
        else os.environ.get("LANE_PL2_ACCOUNT", "next2")
    )
    adir = dirs[acct]
    k0 = lib.kc_state(adir)
    spanning = False
    n_calls = 5
    if max_wait and 0 < k0["life_s"] - 360 <= max_wait:
        lib.log(
            f"P-L2 waiting {int(k0['life_s'] - 360)} s for {acct}'s token to near expiry"
        )
        time.sleep(max(0.0, k0["life_s"] - 360))
        spanning, n_calls = True, 50  # ~9-10 min of calls straddling the expiry
    elif k0["life_s"] < lib.GUARD_EXPIRY_S:
        spanning = True
    base = lib.scratch("pl2")
    runs: dict[str, lib.Run] = {}

    def one(tag: str) -> None:
        cfg = lib.fresh_cfg(base, f"cfg-{tag}")
        runs[tag] = lib.spawn_session(
            binary,
            cfg,
            PROMPT.format(n=n_calls),
            lane=str(adir),
            mod=None,
            outdir=base,
            tag=tag,
            timeout_s=1500 if spanning else 420,
        )

    ts = [threading.Thread(target=one, args=(t,)) for t in ("lane1", "lane2")]
    for t in ts:
        t.start()
        time.sleep(2)
    for t in ts:
        t.join()
    k1 = lib.kc_state(adir)
    hits = lib.scrub_tokens([base])
    refreshed = k1.get("access_fp") != k0.get("access_fp")
    per = {}
    for tag, r in runs.items():
        st = [x.status for x in r.resps]
        res = r.result or {}
        per[tag] = {
            "calls": len(st),
            "s401": st.count(401),
            "non200": [s for s in st if s != 200],
            "is_error": res.get("is_error"),
            "done": "DONE" in str(res.get("result", "")),
        }
    failed = [t for t, p in per.items() if p["is_error"] or not p["done"]]
    checks = {
        "no_failed_turn": not failed,
        "no_401": all(p["s401"] == 0 for p in per.values()),
        "no_token_in_artifacts": not hits,
        "accounts_distinct_after": len(
            {lib.kc_state(d).get("refresh_fp") for d in dirs.values()} - {None}
        )
        == len([d for d in dirs.values() if lib.kc_state(d).get("present")]),
    }
    ok = (
        checks["no_failed_turn"]
        and checks["no_token_in_artifacts"]
        and checks["accounts_distinct_after"]
    )
    return lib.verdict(
        "P-L2",
        "PASS" if ok else "FAIL",
        f"two pointer lanes on {acct}: 401s {[p['s401'] for p in per.values()]}, failed turns "
        f"{len(failed)}, refresh inside the window: {refreshed}"
        + (
            ""
            if ok
            else "; failed: " + ", ".join(k for k, v in checks.items() if not v)
        ),
        checks=checks,
        per_lane=per,
        account=acct,
        refresh_observed=refreshed,
        spanning=spanning,
        life_before_s=k0.get("life_s"),
        mdat=[k0.get("mdat"), k1.get("mdat")],
        artifacts=str(base),
        token_hits=hits,
    )
