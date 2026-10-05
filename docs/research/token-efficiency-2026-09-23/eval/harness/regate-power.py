#!/usr/bin/env python3
"""regate-power.py — how many runs per arm a TRUE TIE needs to clear F1's -5 pp success margin.

Uses agg.py's own newcombe() and margin rule (a CI lower bound <= -MARGIN is a miss), unchanged.
For a true success rate p in both arms and n runs per arm, the probability that the 95% Newcombe
lower bound of (slim - full) lands above -5 pp is summed exactly over Binomial(n, p) x Binomial(n, p).
Success is the binding guardrail: overall compliance pools ~4-6 items per run, so its n is 4-6x larger.

    python3 -B regate-power.py            the table and the perfect-tie bounds
No model calls; reads nothing but agg.py.
"""

import os, sys

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from agg import newcombe  # noqa: E402
from scipy.stats import binom  # noqa: E402

MARGIN = 0.05
RATES = (0.85, 0.90, 0.95, 0.98)
NS = (50, 100, 150, 200, 250, 300, 320, 350, 400)


def p_clear(p, n):
    pk = [binom.pmf(k, n, p) for k in range(n + 1)]
    live = [k for k in range(n + 1) if pk[k] >= 1e-9]
    return sum(
        pk[a] * pk[b] for a in live for b in live if newcombe(a, n, b, n)[0] > -MARGIN
    )


def main():
    print("perfect tie (n/n vs n/n), success CI lower bound:")
    for n in (50, 100, 150, 200, 300):
        print(f"  n={n:<4} {newcombe(n, n, n, n)[0] * 100:+.2f} pp")
    print(
        "\nP(true tie clears -5 pp) by runs per arm (rows) and true success rate (columns)"
    )
    print("n/arm  " + "  ".join(f"p={p:.2f}" for p in RATES))
    for n in NS:
        print(f"{n:<6} " + "  ".join(f"{p_clear(p, n):6.2f}" for p in RATES))


if __name__ == "__main__":
    main()
