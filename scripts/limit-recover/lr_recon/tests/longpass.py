"""LongPass: a wall clock a test owns, for driving ONE reconciler pass that runs for minutes (B7 §8.4).

Patched over ``time.time`` for the duration of a pass, it lets slow stubs (a placer at its 120 s
bound, a probe at its 30 s bound) advance the wall while the pass's ``now`` stays the census
instant, which is the regime permanent 15-40/core load puts every pass in. Not a test module (no
``test_`` prefix): the load harness (B1) can import it too.
"""

from typing import List


class LongPass:
    """A callable wall clock; ``advance(s)`` moves it, ``marks`` records readings a stub asked for."""

    def __init__(self, t0: float) -> None:
        self.t = float(t0)
        self.marks: List[float] = []

    def __call__(self) -> float:
        return self.t

    def advance(self, s: float) -> float:
        self.t += float(s)
        return self.t

    def mark(self) -> float:
        self.marks.append(self.t)
        return self.t
