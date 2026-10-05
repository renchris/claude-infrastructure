#!/usr/bin/env python3
"""gate-excludes.py <config-dir> — the --settings JSON run.sh passes, keeping the machine's own memory out of a run.

    gate-excludes.py <config-dir>                         print {"claudeMdExcludes": [...]} for run.sh
    gate-excludes.py --check <config-dir> [settings.json]  exit 1 naming any memory file on disk the
                                                           list misses (default: the list printed above)

A gate run must load only its arm's files (copied into the fixture as project memory). The account's
user memory (<config-dir>/CLAUDE.md and <config-dir>/rules/*.md) and ~/.claude's (CLAUDE.md, rules/*.md)
are excluded. The list used to be four hard-coded paths, so when install.sh began deploying the slim
variant's close rules as ~/.claude/rules/10-session-close.md (2026-10-03) that 31 KB file loaded into
BOTH arms. The list is now built from what is on disk at run time, as written and as its realpath, plus
the historical names, so a rules file added later is excluded without an edit here. rules/ is read
recursively, as the loader reads it.

--check does NOT reuse live_files(): it walks the same dirs with os.walk (symlinks followed, dot-files
included) and requires each .md file it finds to be in the list both as written and as its realpath.
A check built on the list's own enumeration could never fail. Pass a settings JSON to check a list
other than the computed one, e.g. the value run.sh actually passed.
"""

import glob, json, os, sys

HISTORICAL = (
    "00-mission-board.md",
    "agent-operating-lessons.md",
    "10-session-close.md",
)


def live_files(ccd):
    home = os.path.expanduser("~/.claude")
    out = []
    for d in (ccd, home):
        out.append(os.path.join(d, "CLAUDE.md"))
        out.extend(
            sorted(glob.glob(os.path.join(d, "rules", "**", "*.md"), recursive=True))
        )
    return [p for p in out if os.path.exists(p)]


def on_disk(ccd):
    """Independent enumeration for --check: every memory file the loader could read."""
    home = os.path.expanduser("~/.claude")
    out = []
    for d in (ccd, home):
        out.append(os.path.join(d, "CLAUDE.md"))
        for root, _dirs, files in os.walk(os.path.join(d, "rules"), followlinks=True):
            out.extend(
                os.path.join(root, f) for f in sorted(files) if f.endswith(".md")
            )
    return sorted({p for p in out if os.path.isfile(p)})


def excludes(ccd):
    home = os.path.expanduser("~/.claude")
    paths = [os.path.join(ccd, "CLAUDE.md"), os.path.join(home, "CLAUDE.md")]
    paths += [os.path.join(d, "rules", n) for d in (ccd, home) for n in HISTORICAL]
    for p in live_files(ccd):
        paths += [p, os.path.realpath(p)]
    seen, out = set(), []
    for p in paths:
        if p not in seen:
            seen.add(p)
            out.append(p)
    return out


def main(argv):
    check = argv[:1] == ["--check"]
    args = argv[1:] if check else argv
    if not (len(args) == 1 or (check and len(args) == 2)) or not os.path.isdir(args[0]):
        print(
            "usage: gate-excludes.py [--check] <config-dir> [settings.json]",
            file=sys.stderr,
        )
        return 2
    ccd = args[0].rstrip("/")
    if not check:
        print(json.dumps({"claudeMdExcludes": excludes(ccd)}))
        return 0
    ex = (
        json.load(open(args[1]))["claudeMdExcludes"]
        if len(args) == 2
        else excludes(ccd)
    )
    covered = set(ex)
    files = on_disk(ccd)
    ok = lambda p: p in covered and os.path.realpath(p) in covered
    missed = [p for p in files if not ok(p)]
    for p in files:
        print(f"  {'excluded' if ok(p) else 'LEAKS   '} {p}")
    if missed:
        print(
            f"gate-excludes: {len(missed)} live memory file(s) would load into every arm",
            file=sys.stderr,
        )
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
