"""P-P1 — pointer lane on a real account store, moved mid-turn, with the expiry guard (REPORT §4.2).

Decides operator decision be5c5e83800f (pointer lane vs copied token). One throwaway session is launched
with its lane variable pointing at account A's REAL config dir and a throwaway mod whose `turn.step` hook
re-reads a route file before every model request (the P11 mechanism). After the first response, and only
if the guard allows it, the harness rewrites the ROUTE FILE to account B's real dir. Nothing else changes:
no credential is written by the probe, and no token exists anywhere but the accounts' own keychain items.

PASS needs every one of:
  billing   calls before the flip bill A; a call after it bills B within ADOPTION_BOUND_S (+ one request);
            once B, never A again; the turn completes (is_error false)
  linear    one transcript, no branch, every tool_use answered, no interrupted turn
  guard     both tokens had >= 30 min of life at start; the guard (6 min / refresh lock) allowed the flip
  keychain  no keychain item and no .credentials.json created for the throwaway; no .credentials.json
            created in A or B; any change to A's or B's item is an ordinary refresh (expiry advanced, the
            new fingerprints belong to no other account) and the two accounts never share a refresh token
  identity  A's and B's own .claude.json identity unchanged
  tokens    no token-shaped string in any artifact
"""

from __future__ import annotations

import json
from pathlib import Path

import lib

PROMPT = (
    "Run the shell command `sleep 6; date +%s` eight times. Use a separate Bash tool call for each run, "
    "one at a time, waiting for each result before starting the next. Then reply with the word DONE "
    "followed by the eight numbers."
)


def run(binary: Path, ctx: dict) -> dict:
    a, adir, b, bdir = lib.pick_pair()
    ida, idb = lib.identity_of(adir), lib.identity_of(bdir)
    if not ida.get("org") or not idb.get("org") or ida["org"] == idb["org"]:
        return lib.verdict(
            "P-P1", "INCONCLUSIVE", "accounts lack distinct recorded orgs", a=ida, b=idb
        )
    ka0, kb0 = lib.kc_state(adir), lib.kc_state(bdir)
    for name, k in ((a, ka0), (b, kb0)):
        if not k.get("present") or (k.get("life_s") or 0) < lib.PRECOND_LIFE_S:
            return lib.verdict(
                "P-P1",
                "INCONCLUSIVE",
                f"precondition: {name}'s token needs >= {lib.PRECOND_LIFE_S} s of life",
                life_a=ka0.get("life_s"),
                life_b=kb0.get("life_s"),
            )
    creds0 = lib.credential_files([adir, bdir])

    base = lib.scratch("pp1")
    cfg = lib.fresh_cfg(base)
    route, modlog = base / "route", base / "modlog"
    route.write_text(str(adir))
    mod = lib.write_mod(base, route, modlog)
    flip = {"t": None, "guard": None}

    def on_line(t, ln, r):
        if flip["t"] is None and flip["guard"] is None and lib._RESP_START.match(ln):
            ok, why = lib.guard_allows_repoint(adir, lib.kc_state(adir))
            flip["guard"] = why
            if ok:
                route.write_text(str(bdir))
                flip["t"] = lib.now()
                lib.log(f"P-P1 route flipped {a} → {b} ({why})")
            else:
                lib.log(f"P-P1 guard refused the flip: {why}")

    lib.log(f"P-P1 throwaway in {base}: lane={adir} then {bdir}")
    r = lib.spawn_session(
        binary,
        cfg,
        PROMPT,
        lane=str(adir),
        mod=mod,
        outdir=base,
        tag="pp1",
        on_line=on_line,
    )
    ka1, kb1 = lib.kc_state(adir), lib.kc_state(bdir)
    hits = lib.scrub_tokens([base])

    org_of = {ida["org"]: a, idb["org"]: b}
    rows = [
        {
            "dt_from_flip": (round(x.t - flip["t"], 2) if flip["t"] else None),
            "status": x.status,
            "acct": org_of.get(x.org, x.org and x.org[:8]),
            "util7d": x.util7d,
        }
        for x in r.resps
    ]
    before = [x for x in rows if x["dt_from_flip"] is None or x["dt_from_flip"] <= 0]
    after = [x for x in rows if x["dt_from_flip"] is not None and x["dt_from_flip"] > 0]
    first_b = next((x for x in after if x["acct"] == b and x["status"] == 200), None)
    after_first_b = after[after.index(first_b) :] if first_b else []
    statuses = [x["status"] for x in rows]
    res = r.result or {}

    steps = [x for x in lib.read_modlog(modlog) if x.get("kind") == "step"]
    steps_seen_b = [
        s for s in steps if flip["t"] and s.get("t", 0) / 1000.0 > flip["t"]
    ]
    ctx["pp1"] = {
        "run": r,
        "a": a,
        "b": b,
        "ida": ida,
        "idb": idb,
        "flip_t": flip["t"],
        "base": str(base),
        "modlog": modlog,
    }

    checks = {
        "billing_before_A": bool(before)
        and all(x["acct"] == a for x in before if x["status"] == 200),
        "flipped": flip["t"] is not None,
        "adopted_B": first_b is not None,
        "adoption_within_bound": bool(first_b)
        and first_b["dt_from_flip"] <= lib.ADOPTION_BOUND_S + 15,
        "no_flap_after_B": all(
            x["acct"] == b for x in after_first_b if x["status"] == 200
        ),
        "turn_completed": (not res.get("is_error"))
        and "DONE" in str(res.get("result", "")),
        "no_401": 401 not in statuses,
        "mod_routed_B": bool(steps_seen_b)
        and all(s.get("seen") == str(bdir) for s in steps_seen_b),
        "no_throwaway_keychain_item": lib.kc_mdat(cfg) is None,
        "no_credentials_file_created": lib.credential_files([adir, bdir]) == creds0
        and not (cfg / ".credentials.json").exists(),
        "identity_unchanged": lib.identity_of(adir) == ida
        and lib.identity_of(bdir) == idb,
        "accounts_keep_distinct_grants": ka1.get("refresh_fp") != kb1.get("refresh_fp"),
        "no_token_in_artifacts": not hits,
    }
    for name, k0, k1, other in ((a, ka0, ka1, kb0), (b, kb0, kb1, ka0)):
        changed = (k0.get("access_fp"), k0.get("refresh_fp")) != (
            k1.get("access_fp"),
            k1.get("refresh_fp"),
        )
        ordinary = (not changed) or (
            k1.get("expires_at", 0) > k0.get("expires_at", 0)
            and k1.get("refresh_fp") not in (other.get("refresh_fp"),)
            and k1.get("access_fp") not in (other.get("access_fp"),)
        )
        checks[f"keychain_{name}_only_ordinary_writes"] = ordinary
    tx = lib.transcript_check(cfg, r.session_id)
    checks["transcript_linear"] = tx.get("ok", False)

    ok = all(checks.values())
    return lib.verdict(
        "P-P1",
        "PASS" if ok else "FAIL",
        (
            f"pointer lane moved {a}→{b} mid-turn: first {b}-billed response {first_b['dt_from_flip']} s after the "
            f"route flip"
            if first_b
            else f"no {b}-billed response after the flip"
        )
        + (
            ""
            if ok
            else "; failed: " + ", ".join(k for k, v in checks.items() if not v)
        ),
        checks=checks,
        calls=rows,
        guard=flip["guard"],
        transcript=tx,
        num_turns=res.get("num_turns"),
        rc=r.rc,
        wall_s=round(r.ended - r.started, 1),
        steps=len(steps),
        steps_after_flip=len(steps_seen_b),
        keychain={
            a: {
                "before_life_s": ka0.get("life_s"),
                "mdat": [ka0.get("mdat"), ka1.get("mdat")],
                "changed": ka0.get("access_fp") != ka1.get("access_fp"),
            },
            b: {
                "before_life_s": kb0.get("life_s"),
                "mdat": [kb0.get("mdat"), kb1.get("mdat")],
                "changed": kb0.get("access_fp") != kb1.get("access_fp"),
            },
        },
        orgs={a: ida["org"][:8], b: idb["org"][:8]},
        artifacts=str(base),
        token_hits=hits,
        cost_usd=res.get("total_cost_usd"),
    )
