#!/usr/bin/env python3
"""p_kit.py — every origin/main commit since 2026-09-28 touching scripts/research-kit, classified.

Classes (one per commit, judged from subject + diff; the reason is in the CSV):
  G-plan  generic capability built from the method spec, before or independent of TM2 hitting it
  G-trig  generic capability any program could need, built because TM2 hit the situation
  T       TM2-only: exists for this program's particular state
  D       fixing the kit's own defect (a bug or gap in kit code/contract the kit already shipped,
          incl. reverts and environment breakage of a shipped lane)
  O       not kit work: a repo-wide commit that merely touched a kit file
TM2 is the only program the kit has ever registered (~/.claude/autonomy/research/programs.json),
so every class was paid for by this program.

Usage (from the repo root):
  python3 docs/research/tm2-cost-vs-outcome-2026-10-16/scripts/p_kit.py
Writes data/p_kit_commits.csv and data/p_kit.json; prints the summary.
"""

import collections, csv, json, os, subprocess
from datetime import datetime, timezone

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(os.path.dirname(HERE), "data")
REPO = os.path.abspath(os.path.join(HERE, "..", "..", "..", ".."))

C = {
    # 10-01: waves A-C, the kit built from the method spec
    "86369a8be": ("G-plan", "kit contract, gate dispatcher, registry"),
    "6c412fac1": ("G-plan", "records contract"),
    "d9f279903": ("D", "gate passed rows no module provided"),
    "5568521dd": ("G-plan", "refactor during build-out"),
    "c7ecde16a": ("D", "dispatcher import / reopen bug"),
    "a7a827b4f": ("G-plan", "sealed-at-rest encryption"),
    "c70bdb50f": ("G-plan", "probe runner, doctor"),
    "3f5d99b3e": ("G-plan", "seeds + vault"),
    "23f3f324a": ("G-plan", "courier"),
    "b9cdb53c9": ("G-plan", "round runner + estimator"),
    "92cf72197": ("G-plan", "16-row gate, freeze, certificate"),
    "6adde7e46": ("G-plan", "research index"),
    "19ddcc365": ("G-plan", "router, research block, relay check"),
    "0fb32f503": ("G-plan", "skill, intake, briefs, rubric"),
    "89937d701": ("G-plan", "handoff-fire --requires-gate"),
    "d9b6df940": ("G-plan", "cc-research verb table"),
    "6756b475b": ("G-plan", "scheduled jobs"),
    "a6c2155b7": ("G-plan", "launchd runner"),
    "97e1fea96": ("G-plan", "certification verbs"),
    "686836cb9": ("G-plan", "round/frame-critique/rehearsal workflows"),
    "dd4fe7050": ("G-plan", "records contract doc"),
    "9ff555f83": ("G-plan", "state verbs"),
    "168a4207f": ("G-plan", "record verbs, triage"),
    "1a6f19e58": ("G-plan", "probe/doctor verbs"),
    "baa05b780": ("G-plan", "reference-class timing"),
    "d55b04fa9": ("D", "Google lane broken (gemini retired) -> Antigravity"),
    "30e07d8c5": ("D", "Google lane cannot read bundle"),
    "82d87ac10": ("D", "bundle paths tripped integrity check"),
    # 10-03/04
    "cbe90eb63": ("O", "instruction-variant budget fix, repo-wide"),
    "9989d3a78": ("O", "headless helper settings, repo-wide"),
    "3cb00ec08": ("D", "relay check skipped a verdict-first reply"),
    "8b531dd34": ("D", "heldout scored router fallback wrong"),
    "da9da7a18": ("D", "machine-envelope prompt mislabeled"),
    "a2f39ff84": ("D", "doc for the route-label fix"),
    "bc17af96d": ("D", "check-round skipped non-voided incomplete slots"),
    "fb345896a": ("D", "lane counted live with incomplete slots"),
    "c18ccd4bd": ("D", "invisible bound wrong; re-measured"),
    "dc51b2368": ("D", "shadow stratum drew from wrong count"),
    "d1048d356": ("D", "forecast ignored false-material share"),
    "d69121e0a": ("G-plan", "calibration sharpness/rank skill"),
    "da5eea40e": ("D", "seed catches counted as real findings"),
    "0d8dfbd12": ("G-plan", "seed pre-screen, realism statistic"),
    "9d011c6f0": ("G-plan", "records doc for the above"),
    "fa06657b8": ("D", "certificate rendered stale records"),
    "65b3713cf": ("D", "row 17 accepted a dishonest stop"),
    "2fae4d7b5": ("D", "close counted a round with incomplete slots"),
    "20b8d9cbc": ("D", "interrupted round wedged"),
    "3bbefd668": ("D", "R_max unbounded; stale preflight accepted"),
    "e0f390797": ("D", "sweep missed a program with an open packet"),
    "eb7653f57": ("D", "id minting / vault writes raced"),
    "4a511e3fb": ("G-trig", "program lease after concurrent writers"),
    "7e67e96a2": ("D", "partial slot not re-run"),
    "3b4a9f0d7": ("G-trig", "records doc: resume, cap, lease"),
    "b2b09e273": ("G-trig", "program spanning several roots"),
    "0d5ad49c0": ("D", "import lost in a merge"),
    "f0742dec5": ("D", "re-register dropped aliases"),
    "eb367c280": ("G-plan", "router re-ask classifier, row 15 limit"),
    "1e78179b6": ("G-plan", "router classifier slimming (E1b)"),
    "0e2c97516": ("D", "revert of E1b (read worse)"),
    "da9c13320": ("G-plan", "pin reviewer effort per vendor"),
    "d4045400a": ("G-plan", "estimate.py measured inputs (v1.2)"),
    "e44627831": ("G-plan", "intake profile warning, v1.2 stamp"),
    "835da4f84": ("G-plan", "held-out set v2"),
    "6ab93d373": ("G-plan", "method v1.2 spec skeleton"),
    "b74d33b95": ("G-plan", "yield stop for stages 3 and 5"),
    "b428d019f": ("G-plan", "Stage 9 built-artifact certificate"),
    "8f9f8d3d6": ("G-plan", "built gate rows 20-25"),
    "940d2925c": ("G-plan", "Stage 9 registry states"),
    "655459ce9": ("G-plan", "contract-page v1.2 ceiling"),
    "36f811d89": ("G-plan", "Stage 9 soak scheduler"),
    "aa5bb7a65": ("D", "ceiling omitted v1.2 parts"),
    "7b2f50ce3": ("D", "render placeholder bug"),
    # 10-05..10-08: router hardening
    "adc7e2d6c": ("G-plan", "warm router classifier"),
    "1d8feb56c": ("G-plan", "implementation signature"),
    "10349a46e": ("D", "logged-out warm classifier cost every call"),
    "2e2d17cb5": ("G-plan", "fast-plus-careful classifier (E1g)"),
    "067278db0": ("G-plan", "held-out set v3"),
    "a3c4b556f": ("G-plan", "held-out tooling (E1h)"),
    "e0f9bb418": ("G-plan", "router relay notice etc."),
    "c6b110492": ("G-plan", "count overridden relays"),
    "07a2a8029": ("G-plan", "tuning rater tolerance"),
    "d68323586": ("G-plan", "E1i pre-registration"),
    "79887ba4c": ("G-plan", "router fast call model (E1i)"),
    "70f881599": ("D", "router stall invisible (trace row)"),
    "5d28a9507": ("D", "router workers hung on keychain"),
    "471f7dcd2": ("D", "router cold-start latency hedge"),
    "44b261af4": ("G-trig", "overrun packet verb (TM2 stage 4 overran)"),
    "20405baa4": ("D", "row 15 read guards / load bound"),
    "a5d6bd21f": ("D", "pin router careful call after drift"),
    "80712ea08": ("D", "version-pin ratchet blocked ruled pin"),
    "0901322a6": ("D", "stall row skipped by late wakeup"),
    "48e6a35d0": ("T", "census re-pin after TM2's replan merge"),
    "ac402dd96": ("D", "frame lacked keys gate rows 8-9 read"),
    # 10-10..10-13: certification under way
    "16b6b441f": ("D", "seed match crashed on round 'fc1'"),
    "0ed9589d0": ("D", "research block refused the program's own round"),
    "13614c2bf": ("D", "file-packet accepted malformed class-B packet"),
    "0816f9cb4": ("D", "freshness read env crash as refutation"),
    "46d4d64a2": ("D", "certificate miscounted triaged drift flip"),
    "7dab6ce0d": ("D", "no-verdict re-check hid the missing tool"),
    "544fa4aa7": ("D", "certifying program blocked self-close"),
    "55444343d": ("D", "seed match read the wrong copy"),
    "4d11ed938": ("G-trig", "settle a round before plan edits"),
    "d318ec014": ("D", "router mislabeled out-of-root pane"),
    "b6e453ee1": ("D", "router label inheritance too wide"),
    "9b2a729d6": ("D", "router read any brief as a work order"),
    "cf9a55fcd": ("D", "test for the router fix"),
    "91d21b830": ("D", "activity could not run settling verbs"),
    "0b0a1cf64": ("D", "freshness skipped carried premises; row 4 key"),
    "0d3b70bca": ("D", "timed-out probe left children running"),
    "4c7010dae": ("D", "round-2 safety: bundle leaked history; re-finds counted"),
    "9fdde4e2d": ("G-trig", "operator reopen/re-rule of a decision"),
    "23ac3a5de": (
        "G-trig",
        "front-end return, profile switch, re-rendered contract page",
    ),
    "b55d29ecf": ("D", "census repin one method per call"),
    "5c10d15f4": ("D", "activity could not run new settling verbs"),
    "4fc7688d9": ("D", "row 9 certified the wrong snapshot"),
    "26e83e2ba": ("D", "cap round could not settle / name finds"),
    "9000cec6f": ("D", "row 13 read an overwritten preflight"),
    "3b4ab4fdf": ("D", "row 8 /tmp scan hit vendor quotes"),
    "2cb602f17": ("G-trig", "premise revise --probe"),
    "5e11243a7": ("G-trig", "decision carry revise / reopen"),
    "d1adcfd24": ("G-plan", "rehearsal finds as known rows"),
    # 10-15..10-16: rehearsal and gate rows
    "af46ca131": ("D", "answered sweep-converted decision stayed blocked"),
    "a860db7c2": ("G-trig", "decision affirm; sweep supersedes"),
    "e29c3fdb4": ("G-trig", "agent-run rehearsal (operator could not run it)"),
    "0b8636a2a": ("D", "rehearsal briefs cited wrong plan path"),
    "1b5258733": ("D", "rehearsal trials misrouted while certifying"),
    "921b85267": ("D", "relay named an unrunnable read; Stop arms contradicted"),
    "15adbe4b0": ("G-trig", "practice relay trial"),
    "56f1c3a07": ("D", "agy reads escaped bundle; rater cap stranded level"),
    "14c951fd7": ("D", "relay instruction missed Stop-check phrases"),
    "80e89ab38": ("D", "relay context suggested next steps"),
    "bcc23e97c": ("D", "row 8 /tmp scan hit relay trial text"),
    "70d46e643": ("T", "row 4 files TM2's build-only premises not-yet-true"),
    "40158a730": ("T", "re-file supersedes a same-morning not-yet-true filing"),
}


def ep(s):
    return datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()


WEEKS = [
    ("Wk1", ep("2026-09-28T05:00:00Z")),
    ("Wk2", ep("2026-10-05T05:00:00Z")),
    ("Wk3", ep("2026-10-12T05:00:00Z")),
]


def week(t):
    w = "pre"
    for n, a in WEEKS:
        if t >= a:
            w = n
    return w


def git(*a):
    return subprocess.run(
        ["git", "-C", REPO, *a], capture_output=True, text=True
    ).stdout


def main():
    lines = (
        git(
            "log",
            "origin/main",
            "--since=2026-09-28",
            "--format=%h|%cI|%s",
            "--",
            "scripts/research-kit",
        )
        .strip()
        .split("\n")
    )
    rows, missing = [], []
    for ln in lines:
        sha, ci, subj = ln.split("|", 2)
        k = sha[:9]
        cls, why = C.get(k, ("?", "unclassified"))
        if cls == "?":
            missing.append(k)
        ns = git("show", "--numstat", "--format=", sha)
        add = dele = files = 0
        for r in ns.strip().split("\n"):
            p = r.split("\t")
            if len(p) == 3 and p[0].isdigit():
                add += int(p[0])
                dele += int(p[1])
                files += 1
        rows.append(
            {
                "sha": k,
                "committed": ci,
                "week": week(ep(ci)),
                "class": cls,
                "added": add,
                "deleted": dele,
                "files": files,
                "fixup": subj.startswith("fixup!"),
                "subject": subj,
                "reason": why,
            }
        )
    all_main = int(
        git("rev-list", "--count", "--since=2026-09-28", "origin/main").strip()
    )
    os.makedirs(DATA, exist_ok=True)
    with open(os.path.join(DATA, "p_kit_commits.csv"), "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=list(rows[0].keys()))
        w.writeheader()
        w.writerows(rows)
    by = collections.defaultdict(lambda: {"commits": 0, "added": 0, "deleted": 0})
    byw = collections.defaultdict(collections.Counter)
    for r in rows:
        b = by[r["class"]]
        b["commits"] += 1
        b["added"] += r["added"]
        b["deleted"] += r["deleted"]
        byw[r["week"]][r["class"]] += 1
    out = {
        "kit_commits": len(rows),
        "origin_main_commits_since_0928": all_main,
        "kit_share_of_trunk": round(len(rows) / all_main, 4),
        "by_class": dict(by),
        "by_week": {k: dict(v) for k, v in sorted(byw.items())},
        "unclassified": missing,
    }
    with open(os.path.join(DATA, "p_kit.json"), "w") as fh:
        json.dump(out, fh, indent=1, sort_keys=True)
    print(json.dumps(out, indent=1, sort_keys=True))


if __name__ == "__main__":
    main()
