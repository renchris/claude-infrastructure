#!/usr/bin/env python3
"""hook-ceiling.py — measure what a HOOK-LAYER lever can ever clear on the beacon archive.

THE INSTRUMENT IS SHIPPED, NOT JUST ITS NUMBERS. Every figure in the sibling .md decays with
the archive it was read from (the archive grows by ~40 rows/day), so the doc states the
CRITERION and names this script; re-run it rather than quoting the table.

    /usr/bin/python3 docs/research/permission-harvest-hook-ceiling-2026-09-10/hook-ceiling.py

It answers the question PERMISSION_HARVEST.md §3 left open. That plan measured the ceiling for
ALLOW RULES (13-21 prompts, 0.35-0.56%) and named STRUCTURAL — 45% of prompts, 66% of waited
time — as "authoring-habit / hook-layer levers". Nobody had measured what the hook layer can
actually reach, so "hook-layer lever" was an unpriced hope.

METHOD. For every Bash row in the archive:
  1. `permission_matcher.split_leaves` decides STRUCTURAL (the harness hard-gates the command,
     so NO allow rule of any form reaches it — this is the population the plan pointed at).
  2. `smart-bash-allowlist.decide` is run over it to get today's real verdict.
  3. The row's FULL refusal-cause set is collected, separating causes a hook could in principle
     lever (an unwhitelisted verb) from ones it never may:
       DANGER       the shared danger patterns
       FENCE        a segment behind the operator's OWN ask/deny rule — a hook allow cannot
                    revoke it (docs /permissions:442), and widening it inverts their decision
       DISPATCHER   ACE: something else chooses the real command (bash, python3, env, timeout…)
       INDIRECTION  the verb itself comes out of a substitution
       UNDECOMPOSABLE / HEREDOC_BAD / DEPTH — fail-closed, the command cannot be read
  4. The CEILING is rows carrying none of those. Greedy cover over the leverable verbs then says
     how many rows each additional per-verb policy would actually clear.

WHY CAUSE SETS AND NOT FIRST-CAUSE. `decide()` returns on its FIRST refusal, so a first-cause
histogram reports a MASK, not a distribution: 111 rows looked like single-cause "cannot
decompose" and every one of them carried other blockers underneath. Measuring the full set is
what turns "the largest single cluster" from a lever into an artifact.
"""

import collections
import glob
import importlib.util
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
ARCHIVE = os.path.expanduser("~/.claude/autonomy/permission-archive/*.jsonl")

PERMANENT = {
    "DANGER",
    "FENCE",
    "DISPATCHER",
    "INDIRECTION",
    "UNDECOMPOSABLE",
    "HEREDOC_BAD",
    "DEPTH",
}
# The three verbs an EXISTING guard already owns. Levering them is not a hook improvement, it is
# a decision to overrule a standing one: `rm` is delegated to hooks/rm-safe-allowlist.sh, `git`
# sits behind the operator's own fence entries, and `curl` is the measured property of
# hooks/curl-gate.py (1,367 of 1,368 curl "gap" rows joined to a curl-gate ask, profile §2).
GUARDED = {"rm", "git", "curl"}


def load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def main():
    sys.path.insert(0, os.path.join(REPO, "hooks", "lib"))
    import permission_matcher as pm

    sba = load(os.path.join(REPO, "hooks", "lib", "smart-bash-allowlist.py"), "sba")
    # PRECONDITION, asserted not hoped: the core resolves its sibling rm hook relative to its own
    # __file__, and a copy that cannot reach it refuses every `rm` segment — which would silently
    # inflate the leverable set. (memory: subject reads its own path.)
    if not os.path.exists(sba._RM_HOOK):
        sys.stderr.write(
            "hook-ceiling: sibling rm hook unreachable — arm is not in shape\n"
        )
        return 2
    fence, fence_ok = sba.load_fence()
    if not fence_ok:
        sys.stderr.write("hook-ceiling: fence unreadable — refusing to report\n")
        return 2

    rows, files = [], sorted(glob.glob(ARCHIVE))
    for path in files:
        with open(path, errors="replace") as fh:
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                try:
                    rec = json.loads(line)
                except ValueError:
                    continue
                cmd = (rec.get("tool_input") or {}).get("command")
                if cmd:
                    rows.append(cmd)

    def classify(cmd, depth=0):
        """(permanent_blockers, leverable_verbs) — the FULL set, never the first cause."""
        perm, lev = set(), set()
        if sba.danger(cmd):
            return {"DANGER"}, lev
        body, ok = sba.strip_heredocs(cmd)
        if not ok:
            return {"HEREDOC_BAD"}, lev
        if depth >= sba.MAX_SUBST_DEPTH:
            return {"DEPTH"}, lev
        inner, body, ok = sba.extract_substitutions(body)
        if not ok:
            return {"UNDECOMPOSABLE"}, lev
        for sub in inner:
            p2, l2 = classify(sub, depth + 1)
            perm |= p2
            lev |= l2
        segs, ok = sba.split_segments(body)
        if not ok:
            perm.add("UNDECOMPOSABLE")
            return perm, lev
        norm = [s for s in (sba.normalize(r) for r in segs) if s]
        for seg in norm:
            if sba.crosses_fence(seg, fence):
                perm.add("FENCE")
                continue
            if sba.allowed_segment(seg, sole=(len(norm) == 1)) is not None:
                continue
            v = sba.verb(seg)
            if v is None:
                perm.add("INDIRECTION")
            elif v == sba.SUBST_PLACEHOLDER or v.startswith(sba.SUBST_PLACEHOLDER):
                perm.add("INDIRECTION")
            elif v in sba.DISPATCHERS:
                perm.add("DISPATCHER")
            else:
                lev.add(v)
        return perm, lev

    struct = 0
    verdict = collections.Counter()
    first_cause = collections.Counter()
    cause_sizes = collections.Counter()
    permc = collections.Counter()
    ceiling = []
    for cmd in rows:
        if pm.split_leaves(cmd).kind != "structural":
            continue
        struct += 1
        decision, why = sba.decide(cmd, _fence=fence)
        verdict["allow" if decision == "allow" else "defer"] += 1
        first_cause[(why or "?").split(":")[0].strip()] += 1
        perm, lev = classify(cmd)
        cause_sizes[len(perm | lev)] += 1
        for x in perm:
            permc[x] += 1
        if not (perm & PERMANENT):
            ceiling.append(frozenset(lev))

    print("archive files: %d   Bash rows with a command: %d" % (len(files), len(rows)))
    print("STRUCTURAL rows (no allow rule of any form reaches these): %d" % struct)
    print("today's hook verdict on them: %s" % dict(verdict))
    print(
        "\nFIRST refusal cause (a MASK — see the module docstring, do not read as a distribution):"
    )
    for k, n in first_cause.most_common(8):
        print("  %5d  %s" % (n, k))
    print("\ndistinct refusal causes PER ROW (full set):")
    for k in sorted(cause_sizes):
        print("  %2d cause(s): %5d rows" % (k, cause_sizes[k]))
    print("\npermanent blockers, rows touched (a row may carry several):")
    for k, n in permc.most_common():
        print("  %5d  %s" % (n, k))

    n = len(ceiling)
    print(
        "\nHOOK-LAYER CEILING — rows with NO danger, NO operator fence, NO ACE dispatcher,"
        "\nno verb-from-substitution, and decomposable: %d (%.1f%% of structural)"
        % (n, 100.0 * n / max(struct, 1))
    )
    print(
        "  of those, already allowed today (0 leverable verbs): %d"
        % sum(1 for s in ceiling if not s)
    )

    def cover(sets, label, rounds=10):
        print("\ngreedy cover — %s (n=%d):" % (label, len(sets)))
        rem, total = list(sets), len(sets)
        for _ in range(rounds):
            cnt = collections.Counter()
            for s in rem:
                for v in s:
                    cnt[v] += 1
            if not cnt:
                break
            best = cnt.most_common(1)[0][0]
            rem = [s - {best} for s in rem]
            rem = [s for s in rem if s]
            print(
                "  +%-12s rows fully cleared: %d / %d" % (best, total - len(rem), total)
            )

    cover(ceiling, "the whole ceiling")
    safe = [s for s in ceiling if not (s & GUARDED)]
    print(
        "\nceiling rows needing NONE of %s (i.e. not overruling an existing guard):"
        "\n  %d rows = %.1f%% of structural"
        % (sorted(GUARDED), len(safe), 100.0 * len(safe) / max(struct, 1))
    )
    cover(safe, "the subset no existing guard owns", rounds=8)
    return 0


if __name__ == "__main__":
    sys.exit(main())
