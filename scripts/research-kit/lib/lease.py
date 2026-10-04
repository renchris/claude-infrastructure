"""lease.py — `cc-research lease acquire|release|show --program P`, the program lease (audit
2026-10-04, continuity lens item 6; the lease itself is kit.lease_*).

  acquire  take or renew the lease as this owner (CC_RESEARCH_OWNER, else the Claude session id, else
           pid:<ppid>); exit 2 while another owner holds it with a fresh heartbeat
  release  drop it; exit 2 while another owner holds it fresh
  show     print the lease with its age and whether it is stale, or "no lease"

While a fresh lease is held, every OTHER owner's writing verb refuses (exit 2, naming the holder).
"""

from __future__ import annotations

import argparse
import json
from typing import Any

import kit


def cmd_lease(a: argparse.Namespace) -> int:
    slug = kit.check_slug(a.program)
    if a.action == "acquire":
        lease = kit.lease_acquire(slug)
        print(
            f"lease on {slug} held by {lease['owner']} (stale after {kit.LEASE_TTL_S:.0f} s idle)"
        )
    elif a.action == "release":
        print(
            f"lease on {slug} released"
            if kit.lease_release(slug)
            else f"no lease on {slug}"
        )
    else:
        lease = kit.read_json(kit.lease_path(slug))
        if not lease:
            print(f"no lease on {slug}")
            return 0
        age = kit.lease_age(lease)
        lease.update(age_s=round(age), stale=age >= kit.LEASE_TTL_S)
        print(json.dumps(lease, indent=2, sort_keys=True))
    return 0


def add_verbs(sub: Any) -> None:
    p = sub.add_parser("lease", help="one owner at a time writes a program's records")
    p.add_argument("action", choices=("acquire", "release", "show"))
    p.add_argument("--program", required=True)
    p.set_defaults(fn=cmd_lease)
