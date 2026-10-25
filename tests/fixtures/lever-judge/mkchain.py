#!/usr/bin/python3 -I
"""One treated D1 recycle, built for tests/lever-judge-chain.bats: predecessor P idles 900 s at a
200k context, its due-time wake and handoff turns run, successor S (same lineage, resolved from the
lineage file) orients, the operator returns 3000 s later with one re-ask and one new request.
Token counts are the ones the bats file prices by hand. Also writes 24 D1-return anchors carrying
[[gold:...]] labels for the claude stub, and a flag file with D1 live at 100%.

usage: mkchain.py <dir> <T0 epoch>
"""

import json
import os
import sys

D, T0 = sys.argv[1], int(sys.argv[2])
P = "aaaaaaaa-1111-4000-8000-00000000000a"
S = "bbbbbbbb-2222-4000-8000-00000000000b"
home = os.path.join(D, "home")


def iso(t):
    import time

    return time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime(t))


def w(path, rows):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "a") as fh:
        for r in rows:
            fh.write(json.dumps(r, separators=(",", ":")) + "\n")


for r in (".claude", ".claude-secondary", ".claude-tertiary", ".claude-quaternary"):
    os.makedirs(os.path.join(home, r, "projects"), exist_ok=True)
os.makedirs(os.path.join(home, ".claude-next"), exist_ok=True)
os.symlink(
    os.path.join(home, ".claude", "projects"),
    os.path.join(home, ".claude-next", "projects"),
)


def asst(sid, t, n, wr, cr, out, content=None):
    return {
        "type": "assistant",
        "timestamp": iso(t),
        "sessionId": sid,
        "message": {
            "id": "msg_%s_%d" % (sid[:4], n),
            "model": "claude-opus-5-5",
            "stop_reason": "end_turn",
            "usage": {
                "input_tokens": 0,
                "cache_creation_input_tokens": wr,
                "cache_read_input_tokens": cr,
                "output_tokens": out,
                "cache_creation": {
                    "ephemeral_5m_input_tokens": 0,
                    "ephemeral_1h_input_tokens": wr,
                },
            },
            "content": content or [{"type": "text", "text": "ok"}],
        },
    }


def user(sid, t, content):
    return {
        "type": "user",
        "timestamp": iso(t),
        "sessionId": sid,
        "message": {"role": "user", "content": content},
    }


proj = os.path.join(home, ".claude", "projects", "-Users-x-proj")
w(
    os.path.join(proj, P + ".jsonl"),
    [
        user(P, T0 + 990, "start the refactor"),
        asst(
            P,
            T0 + 1000,
            1,
            2000,
            198000,
            500,
            [
                {
                    "type": "tool_use",
                    "id": "tu_p1",
                    "name": "Read",
                    "input": {"file_path": "/x/a.py"},
                },
                {
                    "type": "tool_use",
                    "id": "tu_p2",
                    "name": "Edit",
                    "input": {"file_path": "/x/b.py"},
                },
            ],
        ),
        asst(P, T0 + 1901, 2, 100, 200000, 200),  # the due-time wake
        asst(P, T0 + 1950, 3, 1500, 200100, 1500),  # the handoff turn
    ],
)
w(
    os.path.join(proj, S + ".jsonl"),
    [
        user(S, T0 + 1995, "Continue from the bridge: HANDOFF-ENGAGE"),
        asst(
            S,
            T0 + 2000,
            1,
            60000,
            0,
            1000,
            [
                {
                    "type": "tool_use",
                    "id": "tu_s1",
                    "name": "Read",
                    "input": {"file_path": "/x/a.py"},
                },
                {
                    "type": "tool_use",
                    "id": "tu_s2",
                    "name": "Read",
                    "input": {"file_path": "/x/c.py"},
                },
            ],
        ),
        user(
            S,
            T0 + 2010,
            [
                {"type": "tool_result", "tool_use_id": "tu_s1", "content": "a" * 4000},
                {
                    "type": "tool_result",
                    "tool_use_id": "tu_s2",
                    "content": [{"type": "text", "text": "c" * 8000}],
                },
            ],
        ),
        asst(S, T0 + 2030, 2, 5000, 60000, 800),
        user(
            S,
            T0 + 5020,
            "No, I already told you: run it against staging, not prod. [[gold:R=Y]]",
        ),
        asst(S, T0 + 5030, 3, 1000, 65000, 400),
        user(S, T0 + 5050, "thanks, now update the docs"),
        asst(S, T0 + 5060, 4, 2000, 66000, 600),
    ],
)
state, logs = os.path.join(D, "state"), os.path.join(D, "logs")
os.makedirs(state, exist_ok=True)
lev = {
    L: {
        "stage": "S0",
        "pct": 0,
        "holdback": 0,
        "mode": "shadow",
        "salt": "fx-" + L,
        "split_salt": "sp-" + L,
        "params_id": "p0",
        "candidate": None,
        "trip": None,
        "thresholds_sha": None,
    }
    for L in ("D1", "D2", "D3", "D4")
}
lev["D1"].update(stage="S2", pct=100, mode="live", stage_started_at=iso(T0))
json.dump(
    {"v": 1, "rev": 1, "levers": lev}, open(os.path.join(state, "flags.json"), "w")
)
arm = {
    "arm": "treat",
    "u": 0.5,
    "flag_src": "file",
    "split": "train",
    "pct_eff": 100,
    "stage": "S2",
}
w(
    os.path.join(logs, "lever-arms.jsonl"),
    [
        {
            "v": 1,
            "kind": "session",
            "ts": iso(T0 + 980),
            "sid": P,
            "lineage": P,
            "lineage_src": "self",
            "acct": ".claude-next",
            "pane": "w1",
            "flag_src": "file",
            "arms": {"D1": arm, "D2": dict(arm, arm="ctrl")},
        },
        {
            "v": 1,
            "kind": "session",
            "ts": iso(T0 + 1990),
            "sid": S,
            "lineage": P,
            "lineage_src": "lineage-file",
            "acct": ".claude-next",
            "pane": "w1",
            "flag_src": "file",
            "arms": {"D1": arm, "D2": dict(arm, arm="ctrl")},
        },
    ],
)
w(
    os.path.join(logs, "idle-recycle-shadow.jsonl"),
    [
        {
            "ts": iso(T0 + 1900),
            "sid": P,
            "config_dir": "/x/.claude-next",
            "v": "ok",
            "turn_start": iso(T0 + 1900),
            "would_advise": True,
            "would_advise_k2": True,
            "ctx_at_idle": 200000,
            "gap_s": 900,
        }
    ],
)
an = []
for i in range(24):
    h, a = ("Y" if i < 8 else "N"), ("Y" if i < 4 else "N")
    an.append(
        {
            "id": "d1r-%02d" % i,
            "labels": {"H": h, "A": a},
            "sections": {
                "predecessor_final_msg": "Status of task %d is on disk." % i,
                "operator_prompt": "prompt %d [[gold:H=%s,A=%s]]" % (i, h, a),
            },
        }
    )
w(os.path.join(D, "hc", "judge", "anchors", "d1_return.jsonl"), an)
print(json.dumps({"P": P, "S": S}))
