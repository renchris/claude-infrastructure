#!/usr/bin/env python3
"""backlog-operator-relink — one-shot: key master-operator-gated by CLASS (BACKLOG_MASTER W0
ledger-admission.5).

Until 2026-09-30 every `block` joined the operator batch, so the group held agent work, dated parks
and value calls alike (pile-census 2026-09-04: ~70% misrouted). The linker now keys on the class
(bin/cc-backlog operator_act_class); this re-sorts the rows that joined before it did:

  * class needs-human / needs-credential ............ stay
  * unclassed, audit actor operator|decision ........ stay, and are CLASSED by a same-text re-block
                                                      carrying the audit verdict as the receipt
  * anything else (agent work, not-yet-true, ...) ... leave the group (`link --clear --force`);
                                                      status is untouched — nothing is unblocked

Claimed rows are skipped. Dry-run by default; --apply writes through cc-backlog, never the JSONL.

usage: backlog-operator-relink.py --verdicts <verdicts.jsonl> [--apply] [--cc-backlog BIN]
"""

from __future__ import annotations

import argparse
import collections
import json
import re
import subprocess
import sys

GROUP = "master-operator-gated"
OPERATOR_CLASSES = ("needs-human", "needs-credential")
CLASSES = ("needs-credential", "needs-human", "not-yet-true", "no-capacity")
CRED = re.compile(
    r"\b(credential|log ?in|sign[ -]?in|token|api key|secret|password|oauth|/login)\b",
    re.I,
)


def needs_class(text: str) -> str:
    for c in CLASSES:
        if text == c or text.startswith(c + ":"):
            return c
    if re.match(r"On or after \d{4}-\d{2}-\d{2}", text):
        return "not-yet-true"
    return ""


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--verdicts", required=True)
    ap.add_argument("--apply", action="store_true")
    ap.add_argument("--cc-backlog", default="cc-backlog")
    a = ap.parse_args()

    verdicts: dict[str, dict] = {}
    with open(a.verdicts, encoding="utf-8") as fh:
        for line in fh:
            try:
                r = json.loads(line)
            except ValueError:
                continue
            verdicts[r.get("id", "")] = r

    items = json.loads(
        subprocess.run(
            [a.cc_backlog, "list", "--all", "--json"],
            check=True,
            capture_output=True,
            text=True,
        ).stdout
    )
    members = [
        i
        for i in items
        if i.get("condition") == GROUP and i.get("status") in ("open", "blocked")
    ]

    def cls(i: dict) -> str:
        return i.get("blockClass") or needs_class(i.get("needs") or "")

    before = collections.Counter(cls(i) or "(none)" for i in members)
    plan: list[tuple[str, str, list[str]]] = []
    for i in members:
        iid, c = i["id"], cls(i)
        if c in OPERATOR_CLASSES:
            continue
        v = verdicts.get(iid, {})
        actor = v.get("actor", "")
        if not c and actor in ("operator", "decision") and i.get("status") == "blocked":
            nc = (
                "needs-credential"
                if CRED.search(i.get("needs") or "")
                else "needs-human"
            )
            conv = str(min(int(v.get("confidence") or 70), 90))
            plan.append(
                (
                    iid,
                    "classify:" + nc,
                    [
                        "block",
                        iid,
                        "--needs",
                        i.get("needs") or "",
                        "--class",
                        nc,
                        "--conviction",
                        conv,
                        "--receipt",
                        a.verdicts,
                    ],
                )
            )
        else:
            plan.append(
                (
                    iid,
                    "leave-group (class=%s actor=%s)" % (c or "none", actor or "none"),
                    ["link", iid, "--clear", "--force"],
                )
            )

    print("members before: %d  by class: %s" % (len(members), dict(before)))
    fails = 0
    for iid, what, args in plan:
        print("%s %s %s" % ("APPLY" if a.apply else "WOULD", iid, what))
        if a.apply:
            p = subprocess.run([a.cc_backlog] + args, capture_output=True, text=True)
            if p.returncode not in (0, 4):
                fails += 1
                print(
                    "  FAILED rc=%d %s" % (p.returncode, p.stderr.strip()[:200]),
                    file=sys.stderr,
                )
    if a.apply:
        items = json.loads(
            subprocess.run(
                [a.cc_backlog, "list", "--all", "--json"],
                check=True,
                capture_output=True,
                text=True,
            ).stdout
        )
        after = [
            i
            for i in items
            if i.get("condition") == GROUP and i.get("status") in ("open", "blocked")
        ]
        bad = [i["id"] for i in after if cls(i) in ("", "not-yet-true")]
        print(
            "members after: %d  by class: %s"
            % (len(after), dict(collections.Counter(cls(i) or "(none)" for i in after)))
        )
        print(
            "members whose class is not-yet-true or empty: %d %s"
            % (len(bad), " ".join(bad))
        )
        return 1 if (fails or bad) else 0
    return 0


if __name__ == "__main__":
    sys.exit(main())
