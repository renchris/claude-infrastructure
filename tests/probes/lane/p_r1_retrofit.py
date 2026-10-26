"""P-R1 — retrofit: a RUNNING interactive session is bound to a pointer lane by hot-reloading its mod, with no
restart (the rollout path, SYNTHESIS R3 / M23; P10 measured it lane→lane with copied tokens).

A throwaway TUI on a private tmux server starts on account A's store with a mod that leaves the lane alone.
While turn 1 runs (one Bash call), the module file is rewritten so its `session.start` hook — which fires on
every load AND reload — calls `$.env.set('CLAUDE_SECURESTORAGE_CONFIG_DIR', <B's real dir>)`. Mods reload at a
turn boundary, so turn 1 must stay on A; turn 2, typed after the reload, must bill B. Print mode (`-p`) never
reloads a mod (measured 2026-10-26: same module, two turns, no reload), which is why this probe needs the TUI.
The billed account is read from the mod's own session.measure records (P-S1 certifies they follow the billed
org), matched against one reference call per account.

FORM, stated rather than hidden: the session's starting store is A's store reached through the lane
variable, not through an unset variable over A's own config dir. Starting from an unset variable needs the
throwaway's CLAUDE_CONFIG_DIR to be a credentialed store: either a copied token (ruled out 2026-09-08: no
token files) or a live account dir, whose settings would run the fleet's hooks inside the throwaway and
enroll it in the census. The anchor scan certifies the remaining difference: the store dir is
`process.env.CLAUDE_SECURESTORAGE_CONFIG_DIR` read inside `uw()` on every call with the config dir as the
fallback, so a variable set later takes the same branch as the one set here (anchor lane_var_read_per_call).

PASS: turn 1 measures A, session.start re-fires after the rewrite, turn 2 reaches B within the keychain-cache
bound after the reload and never flaps back, the transcript is linear, no throwaway keychain item, no token.
"""

from __future__ import annotations

import time
from pathlib import Path

import lib

PROMPT1 = "Run the shell command `sleep 12; echo ONE` with the Bash tool, then reply with exactly: ONE"
# Turn 2 makes spaced calls: the per-session keychain read cache (30 s on 2.1.293, anchor keychain_read_cache)
# may still serve A's token right after the reload, exactly as in P-P1, so B must arrive within that bound.
PROMPT2 = (
    "Run the shell command `sleep 6; date +%s` six times, each in its own Bash tool call, one at a time, "
    "waiting for each result. Then reply with exactly: TWO"
)


def run(binary: Path, ctx: dict) -> dict:
    a, adir, b, bdir = lib.pick_pair()
    ka0, kb0 = lib.kc_state(adir), lib.kc_state(bdir)
    ok_guard, why = lib.guard_allows_repoint(adir, ka0)
    if not ok_guard or (kb0.get("life_s") or 0) < lib.PRECOND_LIFE_S:
        return lib.verdict(
            "P-R1",
            "INCONCLUSIVE",
            f"guard/precondition: {why}; {b} life {kb0.get('life_s')} s",
        )
    refs = {
        a: lib.account_ref(binary, adir, ctx),
        b: lib.account_ref(binary, bdir, ctx),
    }
    if not all(refs.values()) or refs[a].get("reset7d") == refs[b].get("reset7d"):
        return lib.verdict(
            "P-R1",
            "INCONCLUSIVE",
            "reference readings missing or indistinguishable",
            refs=refs,
        )

    base = lib.scratch("pr1")
    cfg = lib.fresh_cfg(base)
    lib.seed_tui_config(cfg, base)
    route, modlog = base / "route-unused", base / "modlog"
    mod = lib.write_mod(base, route, modlog)
    lib.log(f"P-R1 throwaway TUI in {base}: starts on {adir}")
    tui = lib.Tui(base, binary, cfg, str(adir), mod)
    marks: dict = {}
    try:
        if not lib.wait_for(lambda: "❯" in tui.screen() or ">" in tui.screen(), 120):
            return lib.verdict(
                "P-R1",
                "FAIL",
                "TUI never reached its prompt",
                screen=tui.screen()[-1500:],
            )
        time.sleep(3)
        tui.type_prompt(PROMPT1)
        # rewrite once turn 1's first request is out (its step record), so the reload must wait for the turn end
        lib.wait_for(
            lambda: any(x["kind"] == "step" for x in lib.read_modlog(modlog)), 120
        )
        lib.write_mod_module(mod, route, modlog, on_start_lane=str(bdir))
        marks["rewrite_t"] = lib.now()
        lib.log(f"P-R1 module rewritten mid-turn to bind {b} at session.start")
        got_start = lib.wait_for(
            lambda: any(x["kind"] == "start" for x in lib.read_modlog(modlog)), 180
        )
        marks["start_seen_t"] = lib.now() if got_start else None
        turn1_end = lib.wait_for(
            lambda: any(
                '"text":"ONE"' in f.read_text() for f in cfg.glob("projects/*/*.jsonl")
            ),
            120,
        )
        time.sleep(4)
        marks["turn2_t"] = lib.now()
        tui.type_prompt(PROMPT2)
        lib.wait_for(
            lambda: any(
                '"text":"TWO"' in f.read_text() for f in cfg.glob("projects/*/*.jsonl")
            ),
            240,
        )
        time.sleep(4)
    finally:
        tui.close()
    hits = lib.scrub_tokens([base])
    recs = lib.read_modlog(modlog)
    measures = [
        (round(m["host_mtime"] - marks["rewrite_t"], 2), lib.measure_account(m, refs))
        for m in recs
        if m["kind"] == "measure"
    ]
    t1 = [acct for dt, acct in measures if dt + marks["rewrite_t"] < marks["turn2_t"]]
    t2 = [acct for dt, acct in measures if dt + marks["rewrite_t"] >= marks["turn2_t"]]
    starts = [
        round(s["host_mtime"] - marks["rewrite_t"], 2)
        for s in recs
        if s["kind"] == "start"
    ]
    tx = lib.transcript_check(cfg, None)
    reload_dt = next((s for s in starts if s >= 0), None)
    first_b = next((dt for dt, acct in measures if acct == b), None)
    adoption_s = (
        round(first_b - reload_dt, 2)
        if first_b is not None and reload_dt is not None
        else None
    )
    after_b = [acct for dt, acct in measures if first_b is not None and dt >= first_b]
    checks = {
        "turn1_billed_A": bool(t1) and set(t1) == {a},
        "module_reloaded_after_rewrite": reload_dt is not None,
        "turn1_ended": bool(turn1_end),
        "turn2_ends_on_B": bool(t2) and t2[-1] == b,
        "adoption_within_bound": adoption_s is not None
        and adoption_s <= lib.ADOPTION_BOUND_S + 20,
        "no_flap_after_B": all(x == b for x in after_b),
        "transcript_linear": tx.get("ok", False),
        "no_throwaway_keychain_item": lib.kc_mdat(cfg) is None,
        "no_token_in_artifacts": not hits,
    }
    ok = all(checks.values())
    return lib.verdict(
        "P-R1",
        "PASS" if ok else "FAIL",
        (
            f"retrofit by mod reload in a running TUI: turn 1 measured {t1}, turn 2 measured {t2}, "
            f"session.start re-fired {starts} s after the mid-turn rewrite, B adopted {adoption_s} s after the reload"
        )
        + (
            ""
            if ok
            else "; failed: " + ", ".join(k for k, v in checks.items() if not v)
        ),
        checks=checks,
        form="pointer(A)→pointer(B) via session.start on reload, interactive",
        measures=measures,
        starts=starts,
        refs={
            k: {"org": (v.get("org") or "")[:8], "reset7d": v.get("reset7d")}
            for k, v in refs.items()
        },
        transcript=tx,
        artifacts=str(base),
        token_hits=hits,
    )
