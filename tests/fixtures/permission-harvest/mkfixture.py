#!/usr/bin/env python3
"""Materialise the permission-harvest fixture HOME from the templates beside this file.

WHY THIS EXISTS. Every input the harvester reads is dated, and two of them rot by CALENDAR: the
archive window is `now - N days` and the oracle-dark arm compares `.archive-alive`'s mtime against
a 3-day bound. A fixture with literal timestamps is green only inside its subject's TTL (memory:
fixture-literal-date-expires-against-a-ttl), so nothing here carries a date — the templates carry
`days`-back offsets and this generator resolves them at run time. Paths are substituted the same
way: `@@HOME@@` in a settings template becomes the test's own $HOME, so no fixture ever names the
operator's real tree.

WHY A GENERATOR AND NOT A PRINTF STUB. The transcript fixture's rejection text contains an
apostrophe. Built inside a single-quoted printf stub it makes the generated script unparseable, the
stub exits non-zero, and a fail-open consumer then reports the HEALTHY state — a broken fixture
wearing a logic defect's clothes (memory: fixture-stub-cannot-carry-an-apostrophe). Templates are
JSON files read with json.load; nothing is quoted through a shell.

Usage:  mkfixture.py <dest_home> [--scenario base|covered|decayed|dark|empty]

It writes `<dest_home>/fixture-manifest.json` naming every derived path and id, so a bats suite
reads the manifest instead of recomputing a single date.
"""

from __future__ import annotations

import gzip
import json
import os
import shutil
import subprocess
import sys
import time

FIXDIR = os.path.dirname(os.path.realpath(__file__))

# The five forks the apply path must write or silently apply to one account. `~/.claude*` is the
# discovery glob, so these names are what discover_settings() has to find under a fixture HOME.
FLEET_DIRS = (
    ".claude",
    ".claude-secondary",
    ".claude-next",
    ".claude-next2",
    ".claude-next3",
)

DAY = 86400


def _load(name):
    with open(os.path.join(FIXDIR, name), encoding="utf-8") as fh:
        return json.load(fh)


def _write_json(path, obj):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(obj, fh, indent=2, ensure_ascii=False)
        fh.write("\n")


def _subst(obj, home):
    """@@HOME@@ → the fixture HOME, recursively. Keeps templates free of absolute paths."""
    if isinstance(obj, str):
        return obj.replace("@@HOME@@", home)
    if isinstance(obj, list):
        return [_subst(x, home) for x in obj]
    if isinstance(obj, dict):
        return dict((k, _subst(v, home)) for k, v in obj.items())
    return obj


def _slug(path):
    """The transcript project-dir name the harness derives from a cwd."""
    return path.replace("/", "-")


def _projects(home):
    return {
        # A: a git checkout whose .claude/settings.local.json is gitignored — the ONLY shape the
        # apply path will write project-local, and the consolidation cluster's home.
        "A": os.path.join(home, "Development", "proj-a"),
        # B: no .claude at all — the fleet rules are the whole ruleset in force.
        "B": os.path.join(home, "Development", "proj-b"),
        # C: never created. 40.9% of real rows have a cwd that no longer exists, so their local
        # rules are UNRECOVERABLE and they are excluded from MIN_EVIDENCE counting.
        "C": os.path.join(home, "Development", "proj-c-gone"),
    }


# Seconds between two rows of the same day. It MUST exceed the hook-attribution join window
# (±15 s), and by a margin: with every row of a day sharing one timestamp, the curl-gate join
# matched every row in that session on that day — a deny_hit row was attributed to curl-gate and
# the deny_hit bucket read 0. A fixture that collapses time makes a correctly-bounded join look
# unbounded, and the arm it breaks is not the one under test.
ROW_STRIDE_S = 61


def _archive_rows(rows, projects, now, shift_days):
    """Template rows → archive JSONL records, grouped by (month, sid) as the beacon writes them.

    Returns (grouped, ts_index) where ts_index maps (sid, command) → the row's ts, so the hook
    decision logs can be written at a real offset from the row they attribute rather than from the
    day the row happens to fall in.
    """
    out = {}
    ts_index = {}
    for i, r in enumerate(rows):
        if "sid" not in r:
            continue  # a `note` entry: the template documents itself in place
        ts = now - (r["days"] + shift_days) * DAY + i * ROW_STRIDE_S
        if "cmd" in r:
            ts_index[(r["sid"], r["cmd"])] = ts
        cwd = projects[r["proj"]]
        rec = {
            "session_id": r["sid"],
            "ts": ts,
            "resolved_ts": ts + r.get("waited", 1),
            "waited_s": r.get("waited", 1),
            "resolved_by": r["by"],
            "cleared_tool": "Bash" if r["by"] == "PostToolUse" else "",
            "cleared_tool_use_id": "",
            "tool_use_id": "",  # "" in 0 of 3,641 real rows — the id branch never fires
            "tool_name": "Bash",
            "cwd": cwd,
        }
        # A grant is PROVEN by the signature pair, never inferred from the tool NAME: an equal pair
        # is an approval, an unequal one is a collateral clear, absence is `unknown`.
        if r.get("approved"):
            sig = "sig%04dsig%04d" % (i, i)
            rec["tool_sig"] = sig
            rec["cleared_tool_sig"] = sig
        if "summary" in r:
            rec["tool_input_truncated"] = True
            rec["tool_input_summary"] = r["summary"]
        else:
            rec["tool_input"] = {"command": r["cmd"]}
        month = time.strftime("%Y-%m", time.gmtime(ts))
        out.setdefault((month, r["sid"]), []).append(rec)
    return out, ts_index


def _write_archive(archdir, grouped, heartbeat_age_s):
    os.makedirs(archdir, exist_ok=True)
    for (month, sid), recs in sorted(grouped.items()):
        path = os.path.join(archdir, "%s.%s.10000.jsonl" % (month, sid))
        with open(path, "a", encoding="utf-8") as fh:
            for rec in recs:
                fh.write(json.dumps(rec, ensure_ascii=False) + "\n")
    beat = os.path.join(archdir, ".archive-alive")
    with open(beat, "w", encoding="utf-8") as fh:
        fh.write("")
    if heartbeat_age_s:
        stamp = time.time() - heartbeat_age_s
        os.utime(beat, (stamp, stamp))


def _write_corpus(logdir, spec, now):
    """Anchored RECORDS, .gz rotation included. 82% of the real log's LINES are continuations."""
    os.makedirs(logdir, exist_ok=True)

    def render(records):
        buf = []
        for rec in records:
            ts = time.strftime(
                "%Y-%m-%dT%H:%M:%SZ", time.gmtime(now - rec["days"] * DAY)
            )
            buf.append("[%s] [%s] %s" % (ts, rec["sid"], rec["lines"][0]))
            buf.extend(rec["lines"][1:])
        return "\n".join(buf) + "\n"

    with open(os.path.join(logdir, "bash-commands.log"), "w", encoding="utf-8") as fh:
        fh.write(render(spec["live"]))
    with gzip.open(os.path.join(logdir, "bash-commands.log.1.gz"), "wb") as gz:
        gz.write(render(spec["rotated"]).encode("utf-8"))


def _write_curl_audit(home, spec, ts_index):
    """One curl-gate ask per named archive row, `offset_s` after THAT ROW's own timestamp.

    Keyed on the row's command, not on its day: a day-keyed offset attributes the ask to whatever
    else that session did that day, which is a fixture bug that reads as an over-wide join.
    """
    path = os.path.join(home, ".reso", "curl-audit.jsonl")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as fh:
        for r in spec["rows"]:
            key = (r["sid"], r["match_cmd"])
            if key not in ts_index:
                # Two absences, told apart by the archive's OWN verbs: a scenario with no curl rows
                # at all (`covered`, `empty`) has nothing to attribute and writes nothing — raising
                # there fails every arm that builds it, in setup, for a reason no assertion names.
                # A scenario that HAS curl rows but not this one is a typo in the template, raised.
                verb = r["match_cmd"].split()[0]
                if any(cmd.split()[:1] == [verb] for _sid, cmd in ts_index):
                    raise RuntimeError(
                        "curl-audit row names no archive row: %r" % (key,)
                    )
                continue
            ts = ts_index[key] + r["offset_s"]
            fh.write(
                json.dumps(
                    {
                        "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(ts)),
                        "decision": r["decision"],
                        "reason": r["reason"],
                        "cmd_redacted": r["cmd_redacted"],
                        "host": r["host"],
                        "method": r["method"],
                        "session_id": r["sid"],
                        "tool_use_id": "",
                        "cwd": "",
                    }
                )
                + "\n"
            )


def _write_transcript(home, spec, projects):
    slug = _slug(projects["B"])
    path = os.path.join(home, ".claude", "projects", slug, "%s.jsonl" % spec["sid"])
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as fh:
        for line in spec["lines"]:
            fh.write(json.dumps(line, ensure_ascii=False) + "\n")
    return path


def _git_bin():
    """Absolute first, PATH second — an unattended fixture must not depend on the caller's PATH."""
    for cand in ("/usr/bin/git", "/opt/homebrew/bin/git", "/usr/local/bin/git"):
        if os.path.isfile(cand) and os.access(cand, os.X_OK):
            return cand
    found = shutil.which("git")
    if not found:
        raise RuntimeError("git not found — project A cannot be built")
    return found


def _git_project(path, home):
    """Project A: a real checkout whose settings.local.json is gitignored.

    `git check-ignore` is the gate the apply path uses, and it needs a repo — not a commit. HOME
    and GIT_CONFIG_NOSYSTEM keep the fixture independent of the operator's git config. A failure
    here is RAISED, never swallowed: a silently non-repo project A would make the project-local
    apply arm refuse for a reason no assertion in either suite names.
    """
    os.makedirs(path, exist_ok=True)
    env = dict(os.environ)
    env["HOME"] = home
    env["GIT_CONFIG_NOSYSTEM"] = "1"
    subprocess.run(
        [_git_bin(), "init", "-q", path],
        check=True,
        env=env,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    with open(os.path.join(path, ".gitignore"), "w", encoding="utf-8") as fh:
        fh.write(".claude/settings.local.json\n")
    os.makedirs(os.path.join(path, "scripts"), exist_ok=True)
    with open(os.path.join(path, "scripts", "zzlocal.sh"), "w", encoding="utf-8") as fh:
        fh.write("#!/bin/bash\nexit 0\n")


def build(home, scenario):
    now = int(time.time())
    projects = _projects(home)
    os.makedirs(home, exist_ok=True)

    fleet_tmpl = (
        "settings-fleet-covered.json"
        if scenario == "covered"
        else "settings-fleet.json"
    )
    fleet = _subst(_load(fleet_tmpl), home)
    fleet_paths = []
    for d in FLEET_DIRS:
        p = os.path.join(home, d, "settings.json")
        _write_json(p, fleet)
        fleet_paths.append(p)

    _git_project(projects["A"], home)
    os.makedirs(projects["B"], exist_ok=True)
    proj_a_tmpl = (
        "settings-proj-a-covered.json"
        if scenario == "covered"
        else "settings-proj-a.json"
    )
    proj_a_local = os.path.join(projects["A"], ".claude", "settings.local.json")
    _write_json(proj_a_local, _subst(_load(proj_a_tmpl), home))

    rows = _load(
        "archive-rows-covered.json" if scenario == "covered" else "archive-rows.json"
    )
    if scenario == "decayed":
        # Evidence DECAY, not tampering: every `gh pr view` row is removed, so the rule a stale
        # proposal still names fails MIN_EVIDENCE on the fresh run and is a NAMED DROP at exit 0 —
        # the case that must stay distinguishable from a gate failure (exit 4).
        rows = [r for r in rows if "gh pr view" not in r.get("cmd", "")]

    archdir = os.path.join(home, ".claude", "autonomy", "permission-archive")
    shift = 60 if scenario == "dark" else 0
    grouped, ts_index = _archive_rows(rows, projects, now, shift)
    if scenario != "empty":
        heartbeat_age = 4 * DAY if scenario == "dark" else 0
        _write_archive(archdir, grouped, heartbeat_age)

    logdir = os.path.join(home, ".claude", "logs")
    corpus = _load("corpus-records.json")
    _write_corpus(logdir, corpus, now)
    _write_curl_audit(home, _load("curl-audit.json"), ts_index)
    transcript = _write_transcript(home, _load("transcript-denied.json"), projects)

    real = [r for r in rows if "sid" in r]
    manifest = {
        "scenario": scenario,
        "home": home,
        "archive_dir": archdir,
        "fleet_settings": fleet_paths,
        "proj_a": projects["A"],
        "proj_a_local": proj_a_local,
        "proj_b": projects["B"],
        "proj_c_missing": projects["C"],
        "corpus_log": os.path.join(logdir, "bash-commands.log"),
        "corpus_gz": os.path.join(logdir, "bash-commands.log.1.gz"),
        "corpus_records": len(corpus["live"]) + len(corpus["rotated"]),
        "curl_audit": os.path.join(home, ".reso", "curl-audit.jsonl"),
        "transcript": transcript,
        "archive_rows": len(real) if scenario != "empty" else 0,
        "sessions": sorted(set(r["sid"] for r in real)) if scenario != "empty" else [],
    }
    _write_json(os.path.join(home, "fixture-manifest.json"), manifest)
    return manifest


def main(argv):
    if len(argv) < 2:
        sys.stderr.write(__doc__)
        return 2
    home = os.path.abspath(argv[1])
    scenario = "base"
    if "--scenario" in argv:
        scenario = argv[argv.index("--scenario") + 1]
    if scenario not in ("base", "covered", "decayed", "dark", "empty"):
        sys.stderr.write("unknown scenario: %s\n" % scenario)
        return 2
    # Re-runnable inside one test (a scenario switch rebuilds the tree), and keyed on OUR OWN
    # manifest rather than on the directory's name: a path-shaped guard would either refuse the
    # caller's chosen dir or authorise an rmtree over a tree this generator never wrote.
    if os.path.isfile(os.path.join(home, "fixture-manifest.json")):
        shutil.rmtree(home)
    build(home, scenario)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
