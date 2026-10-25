#!/usr/bin/env python3
"""policy.py — the D1 policies cc-lever-eval `run` replays through sim.py (plan § W7+ §2 D1).

  candidate         one rule, (k, n_min) from params: the hillclimbed lever (tunable: k, n_min)
  current_practice  the stated practice fully applied: 350k after 15 min, or 250k after 60 min
  never             no recycle: the null, which must net exactly 0

READS are the two read-weight ends (pp per Mtok); a round is decided on the WORSE end.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
import sim  # noqa: E402

READS = (("low", sim.READS["low"]), ("high", sim.READS["high"]))
TUNABLE = dict(
    k=200_000, n_min=15
)  # the approved lever: 200k after 15 idle min (decision 43da49891e75)
DEFAULT = ("candidate", "current_practice", "never")
N_MIN_FLOOR = 15  # boundary-handoff CONV_S=900 holds 15 min after an interactive turn: never cut a live exchange


def rules(pol, params):
    p = dict(TUNABLE, **(params or {}))
    if pol == "candidate":
        return [(int(p["k"]), float(p["n_min"]))]
    if pol == "current_practice":
        return [(350_000, 15), (250_000, 60)]
    if pol == "never":
        return []
    raise ValueError("unknown D1 policy %r (known: %s)" % (pol, ", ".join(DEFAULT)))


def run(cases, pol, r, wk=1.0, params=None, per_case=None, detail=None):
    """→ {"all": {net, recycles, terminal, sessions}}, net in pp x wk."""
    base, new, nrec, term, per_sess, _parts = sim.simulate(
        cases, rules(pol, params), r, per_case=per_case, detail=detail
    )
    if per_case is not None:
        for k in per_case:
            per_case[k] *= wk
    net = (sum(base.values()) - sum(new.values())) * wk
    return {
        "all": dict(
            net=net,
            recycles=sum(nrec.values()),
            terminal=sum(term.values()),
            sessions=len(per_sess),
            recycled=sum(1 for n in per_sess if n),
        )
    }


def line(label, res):
    a = res["all"]
    return (
        "%-28s net %+8.3f pp/wk · recycles %d (+%d terminal) over %d sessions (%d recycled)"
        % (label, a["net"], a["recycles"], a["terminal"], a["sessions"], a["recycled"])
    )
