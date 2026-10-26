"""P-L4 — re-home identity: a session relaunched under its billing account's config dir sends that account's
identity on its FIRST call (SYNTHESIS §3.8, M29; certifies per CC version that a re-home closes the
bearer≠metadata mismatch P6 measured after every zero-restart move).

1. A throwaway `-p` session on account A's store (pointer) is told a code word; its transcript is the source.
2. Cold transplant: the transcript is copied into a FRESH config dir standing in for B's dir — seeded with B's
   own `oauthAccount` record from B's .claude.json (an identity record: uuids, names; never a token), which is
   what B's real dir already holds — and the session is resumed there with the lane pointing at B's store.
3. The resumed run goes through the observer proxy (with the first-party override, P2), which records each
   /v1/messages request's `metadata.user_id` account uuid and the response org.

PASS: call 1 of the resumed run already carries B's account uuid and bills B's org; every call does; the
answer recalls the code word (the conversation survived the transplant); the resumed transcript keeps the
session id and stays linear; the stand-in dir's identity is B's; no token anywhere.
"""

from __future__ import annotations

import json
from pathlib import Path

import lib

WORD = "PELICAN-42"


def run(binary: Path, ctx: dict) -> dict:
    a, adir, b, bdir = lib.pick_pair()
    ida, idb = lib.identity_of(adir), lib.identity_of(bdir)
    if not idb.get("account") or ida.get("account") == idb.get("account"):
        return lib.verdict(
            "P-L4", "INCONCLUSIVE", "accounts lack distinct recorded identities"
        )
    base = lib.scratch("pl4")
    src = lib.fresh_cfg(base, "cfg-src")
    r1 = lib.spawn_session(
        binary,
        src,
        f"Remember this code word for later: {WORD}. Reply with exactly: OK",
        lane=str(adir),
        mod=None,
        outdir=base,
        tag="pl4-src",
        timeout_s=240,
    )
    sid = r1.session_id
    if not sid or not (r1.result or {}).get("result"):
        lib.scrub_tokens([base])
        return lib.verdict(
            "P-L4", "FAIL", "source session produced no transcript", rc=r1.rc
        )

    dst = lib.fresh_cfg(base, "cfg-rehome")
    oa = json.loads((bdir / ".claude.json").read_text()).get("oauthAccount") or {}
    (dst / ".claude.json").write_text(json.dumps({"oauthAccount": oa}))
    moved = lib.copy_transcript(src, dst, sid)
    before_lines = len(moved.read_text().splitlines()) if moved else 0

    proxy = lib.ObserverProxy()
    try:
        r2 = lib.spawn_session(
            binary,
            dst,
            "What was the code word I gave you? Reply with the code word only.",
            lane=str(bdir),
            mod=None,
            outdir=base,
            tag="pl4-rehome",
            timeout_s=240,
            extra_args=["--resume", sid],
            extra_env={
                "ANTHROPIC_BASE_URL": f"http://127.0.0.1:{proxy.port}",
                "_CLAUDE_CODE_ASSUME_FIRST_PARTY_BASE_URL": "1",
            },
        )
    finally:
        proxy.close()
    hits = lib.scrub_tokens([base])
    msgs = [
        x
        for x in proxy.rows
        if x["path"].startswith("/v1/messages") and x.get("status") == 200
    ]
    acct_of = {ida["account"]: a, idb["account"]: b}
    org_of = {ida["org"]: a, idb["org"]: b}
    calls = [
        {
            "identity": acct_of.get(x.get("account_uuid"), x.get("account_uuid")),
            "billed": org_of.get(x.get("org")),
        }
        for x in msgs
    ]
    answer = str((r2.result or {}).get("result", ""))
    after = len(moved.read_text().splitlines()) if moved else 0
    others = [f.name for f in dst.glob("projects/*/*.jsonl") if f.stem != sid]
    tx = lib.transcript_check(dst, sid)
    checks = {
        "source_billed_A": any(
            x.org == ida["org"] and x.status == 200 for x in r1.resps
        ),
        "call1_identity_B": bool(calls) and calls[0]["identity"] == b,
        "call1_billed_B": bool(calls) and calls[0]["billed"] == b,
        "every_call_identity_and_billing_B": bool(calls)
        and all(c["identity"] == b and c["billed"] == b for c in calls),
        "conversation_survived": WORD in answer,
        "same_session_continued": after > before_lines and not others,
        "transcript_linear": tx.get("ok", False),
        "rehome_dir_identity_B": lib.identity_of(dst).get("account") == idb["account"],
        "no_token_in_artifacts": not hits,
    }
    ok = all(checks.values())
    return lib.verdict(
        "P-L4",
        "PASS" if ok else "FAIL",
        (
            f"re-home under {b}'s identity: call 1 identity={calls[0]['identity'] if calls else None} "
            f"billed={calls[0]['billed'] if calls else None}, {len(calls)} call(s), answer recalls the word: "
            f"{WORD in answer}"
        )
        + (
            ""
            if ok
            else "; failed: " + ", ".join(k for k, v in checks.items() if not v)
        ),
        checks=checks,
        calls=calls,
        transcript=tx,
        new_transcripts=others,
        artifacts=str(base),
        token_hits=hits,
        rc=[r1.rc, r2.rc],
    )
