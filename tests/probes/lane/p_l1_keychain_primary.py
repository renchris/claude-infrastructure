"""P-L1 — copy-lane keychain-primary swap under a `security` stall shim (REPORT §12 W0: only if P-P1 fails).

The copy form needs an access-only COPY of an account's token written into a per-session keychain item and a
0600 file. The operator ruled on 2026-09-08 that no token files are ever created, and this wave's brief
forbids copying a token. So this probe never builds that copy itself: when P-P1 passes it is moot (run.py
SKIPs it); when P-P1 fails it reports BLOCKED, naming the operator decision (be5c5e83800f option b) that
would have to authorize the copy before the probe can run.
"""

from __future__ import annotations

from pathlib import Path

import lib


def run(binary: Path, ctx: dict) -> dict:
    return lib.verdict(
        "P-L1",
        "BLOCKED",
        "copy-lane probe needs a copied token, which the 2026-09-08 ruling forbids; it can run only "
        "after decision be5c5e83800f chooses copy lanes (option b) and authorizes the copy",
    )
