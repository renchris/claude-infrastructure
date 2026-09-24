#!/usr/bin/env python3
"""Fit chars->tokens ratios from prefix deltas and test whether prior-turn thinking stays in context.

Reads measure/growth_work/pairs.npz (scripts/growth_pairs.py). Writes measure/growth_work/fit.json.

Model A (thinking test, pairs where response s recorded its final output):
    D = b_out*out(s) + sum_c a_c*chars_c + sum_k o_k*count_k + e
  If the whole assistant message incl. thinking is re-sent, b_out ~ 1 and the assistant-side char
  coefficients (atext, tui) ~ 0. If thinking is stripped, b_out ~ 0 and atext/tui carry ~1/ratio.
Model B (ratios): D - out(s) = sum over user-side classes a_c*chars_c + per-item overheads.
Model C (assistant-side ratios): out(s) = a_text*atext + a_tui*tui + overhead*n_tui, on responses
  WITHOUT thinking (so output = visible text + tool calls only).
Robust: OLS, drop |resid| > 6*MAD, refit. Fits on the stratified SAMPLE and on ALL pairs.
"""

import numpy as np, json, os

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
W = os.path.join(ROOT, "measure", "growth_work")
d = dict(np.load(os.path.join(W, "pairs.npz")))
d["att"] = d["att_ttr"] + d["att_other"]
USER = [
    "tr_read",
    "tr_bash",
    "tr_web",
    "tr_mcp",
    "tr_other",
    "att",  # att_ttr + att_other: the ~86-char total_tokens_reminder rides nearly every group, collinear with n_att
    "prompt",
    "meta",
]
CNT = ["n_tr", "n_att", "n_up"]


def robust(X, y, names):
    b = np.linalg.lstsq(X, y, rcond=None)[0]
    for _ in range(2):
        r = y - X @ b
        mad = np.median(np.abs(r - np.median(r))) + 1e-9
        keep = np.abs(r) < 6 * 1.4826 * mad
        b = np.linalg.lstsq(X[keep], y[keep], rcond=None)[0]
    r = y[keep] - X[keep] @ b
    # standard errors (homoskedastic, on kept rows)
    s2 = (r @ r) / max(1, keep.sum() - X.shape[1])
    try:
        se = np.sqrt(np.diag(s2 * np.linalg.inv(X[keep].T @ X[keep])))
    except np.linalg.LinAlgError:
        se = np.full(X.shape[1], np.nan)
    pred_tot = (X @ b).sum()
    obs_tot = y.sum()
    return {
        "n": int(len(y)),
        "kept": int(keep.sum()),
        "coef": {n: [float(v), float(e)] for n, v, e in zip(names, b, se)},
        "sum_pred_over_obs_all_rows": float(pred_tot / obs_tot) if obs_tot else None,
    }


def fit_all(mask, tag):
    res = {}
    m = mask & (d["out_final"] == 1) & (d["D"] >= 0)
    names = ["out", "atext", "tui"] + USER + CNT  # n_tui dropped: collinear with n_tr
    X = np.column_stack([d[n] for n in names]).astype(float)
    res["A_thinking_test_all"] = robust(X[m], d["D"][m].astype(float), names)
    for lab, mm in (
        (
            "A_thinking_test_think1_prompt_boundary",
            m & (d["think"] == 1) & (d["has_prompt"] == 1),
        ),
        (
            "A_thinking_test_think1_tool_loop",
            m & (d["think"] == 1) & (d["has_prompt"] == 0),
        ),
        ("A_thinking_test_think0", m & (d["think"] == 0)),
    ):
        if mm.sum() > 200:
            res[lab] = robust(X[mm], d["D"][mm].astype(float), names)
    namesB = USER + CNT
    XB = np.column_stack([d[n] for n in namesB]).astype(float)
    yB = (d["D"] - d["out"]).astype(float)
    res["B_user_side"] = robust(XB[m], yB[m], namesB)
    mc = mask & (d["out_final"] == 1) & (d["think"] == 0) & (d["out"] > 0)
    namesC = ["atext", "tui", "n_tui"]
    XC = np.column_stack([d[n] for n in namesC] + [np.ones(len(d["D"]))]).astype(float)
    res["C_assistant_side_no_thinking"] = robust(
        XC[mc], d["out"][mc].astype(float), namesC + ["const"]
    )
    return res


out = {"n_pairs_total": int(len(d["D"])), "neg_delta_pairs": int((d["D"] < 0).sum())}
for tag, mask in (
    ("sample", d["sample"] == 1),
    ("all", np.ones(len(d["D"]), bool)),
    ("all_main", d["ctx"] == 0),
    ("all_agents", d["ctx"] > 0),
):
    out[tag] = fit_all(mask, tag)
json.dump(out, open(os.path.join(W, "fit.json"), "w"), indent=1)


def show(r):
    return {k: (round(v[0], 4), round(v[1], 4)) for k, v in r["coef"].items()}


for tag in ("sample", "all", "all_main", "all_agents"):
    print("==", tag)
    for k, v in out[tag].items():
        print(
            " ",
            k,
            "n=%d kept=%d pred/obs=%.3f"
            % (v["n"], v["kept"], v["sum_pred_over_obs_all_rows"] or 0),
        )
        print("    ", show(v))
