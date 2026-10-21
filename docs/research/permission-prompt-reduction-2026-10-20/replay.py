#!/usr/bin/env python3
"""replay.py — replay the last N days of real prompts through a hook tree and a settings set.

Read-only. Two populations, kept apart because they are different oracles:

  ARCHIVE  every Claude Code permission dialog the beacon recorded
           (~/.claude/autonomy/permission-archive), bucketed by cc-permission-harvest's own
           `analyse` so this instrument and the weekly harvester can never disagree on a bucket.
  HOOKASK  every PreToolUse hook `ask` (cc-hook-asks --json), including the ones raised in
           workflow slots and subagents that the archive does not see.

For each row it asks the question the operator cares about — "would this prompt still appear?" —
against a TREE (the hooks/ dir to run) and an ASK set (the fleet `ask` rules to apply), and prints
the share that would now be auto-allowed.

  usage: replay.py [--tree DIR] [--ask-drop RULE ...] [--days 14] [--hookasks PATH] [--rows-out PATH]

A row counts as CLEARED only when every arm that raised it is gone:
  * an `ask`-rule hit is cleared only if that rule is in --ask-drop;
  * a hook ask (validate-bash / curl-gate) is cleared only if the TREE's hook no longer asks;
  * a structural or rule-gap dialog is cleared only if the TREE's smart-bash-allowlist emits
    `allow` (a hook allow short-circuits the classifier and the prompt, never a deny/ask rule).
Everything else is reported as still asking, with its reason. The hooks are run with HOME pointed
at a scratch dir holding a copy of the fleet settings, so nothing here writes a live log.
"""

import argparse
import collections
import glob
import importlib.machinery
import importlib.util
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.realpath(__file__))
REPO = os.path.realpath(os.path.join(HERE, "..", "..", ".."))


def load_harvest(repo):
    path = os.path.join(repo, "bin", "cc-permission-harvest")
    loader = importlib.machinery.SourceFileLoader("cc_permission_harvest", path)
    spec = importlib.util.spec_from_loader("cc_permission_harvest", loader)
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)
    return mod


def scratch_home(ask_drop):
    """A HOME with the five fleet settings files copied in, minus the dropped ask rules."""
    home = tempfile.mkdtemp(prefix="ppr-replay-home.")
    for d in (
        ".claude",
        ".claude-next",
        ".claude-secondary",
        ".claude-tertiary",
        ".claude-quaternary",
    ):
        src = os.path.expanduser("~/%s/settings.json" % d)
        if not os.path.isfile(src):
            continue
        os.makedirs(os.path.join(home, d), exist_ok=True)
        with open(src) as f:
            s = json.load(f)
        perms = s.get("permissions") or {}
        perms["ask"] = [r for r in perms.get("ask") or [] if r not in ask_drop]
        with open(os.path.join(home, d, "settings.json"), "w") as f:
            json.dump(s, f)
    os.makedirs(os.path.join(home, ".claude", "logs"), exist_ok=True)
    return home


def run_hook(argv, cmd, cwd, home, sid="replay", agent_id=None):
    body = {
        "session_id": sid,
        "tool_name": "Bash",
        "hook_event_name": "PreToolUse",
        "tool_input": {"command": cmd},
        "cwd": cwd or "/tmp",
    }
    if agent_id:
        body["agent_id"] = (
            agent_id  # validate-bash denies, rather than asks, inside a subagent
        )
    payload = json.dumps(body)
    env = {
        "HOME": home,
        # The hooks' OWN interpreter resolution: curl-gate.py needs python >= 3.10, and a reduced
        # PATH that put /usr/bin/python3 (3.9) first made it crash silently, which read as "cleared".
        "PATH": os.environ.get("PATH", "/usr/bin:/bin"),
        "CLAUDE_CONFIG_DIR": os.path.join(home, ".claude"),
        "CC_REPLAY": "1",
    }
    run_cwd = cwd if cwd and os.path.isdir(cwd) else "/tmp"
    try:
        p = subprocess.run(
            argv,
            input=payload,
            capture_output=True,
            text=True,
            timeout=30,
            env=env,
            cwd=run_cwd,
        )
    except subprocess.TimeoutExpired:
        return "timeout", ""
    if p.returncode == 2:
        return "deny", (p.stderr or "")[:200]
    out = (p.stdout or "").strip()
    if not out:
        return "none", ""
    # validate-bash prints its decision as MULTI-LINE JSON; the other hooks print one line. Parse
    # the whole stream first — reading only the last line read every validate-bash ask as "none".
    try:
        d = json.loads(out)
    except ValueError:
        try:
            d = json.loads(out.splitlines()[-1])
        except ValueError:
            return "none", out[:200]
    h = d.get("hookSpecificOutput") or {}
    return (h.get("permissionDecision") or "none"), (
        h.get("permissionDecisionReason") or ""
    )[:200]


def hooks_for(tree):
    return {
        "smart": ["/bin/bash", os.path.join(tree, "smart-bash-allowlist.sh")],
        "validate": ["/bin/bash", os.path.join(tree, "validate-bash.sh")],
        "curl": ["/bin/bash", os.path.join(tree, "curl-gate-scope.sh")],
        "push": ["/bin/bash", os.path.join(tree, "ship-rail-push-allow.sh")],
    }


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--tree", default=os.path.join(REPO, "hooks"))
    ap.add_argument("--ask-drop", nargs="*", default=[])
    ap.add_argument("--days", type=float, default=14)
    ap.add_argument("--hookasks", default=None)
    ap.add_argument("--rows-out", default=None)
    a = ap.parse_args(argv)

    hv = load_harvest(REPO)
    pm = hv.pm
    ns = argparse.Namespace(
        out=None, hook_logs=None, transcripts=[], settings=None, mode=None
    )
    seams = hv.Seams(ns)
    seams.transcripts = []
    settings = hv.discover(seams, None)
    fleet_paths = [p for p, s in settings if s == "fleet"]
    local_paths = [p for p, s in settings if s != "fleet"]
    mode, _src = hv._fleet_mode(fleet_paths)
    fleet_rs = pm.load_rulesets(fleet_paths, mode=mode)
    local_union = pm.load_rulesets(local_paths, mode=mode) if local_paths else None
    _ra, rows_window, _f, _age, _bad, _w = hv.read_oracle(seams, a.days)
    hook_idx, _present = hv.load_hook_logs(seams.hook_logs)
    ctx = hv.Ctx()
    an = hv.analyse(
        rows_window, fleet_rs, local_union, seams, mode, hook_idx, {}, ctx, []
    )

    home = scratch_home(set(a.ask_drop))
    H = hooks_for(a.tree)
    out_rows = []
    tally = collections.Counter()
    still = collections.Counter()
    try:
        for info in an["infos"]:
            cmd, cwd, b = info["cmd"], info["cwd"], info["bucket"]
            rs, st = hv.rules_for(ctx, fleet_rs, local_union, cwd, seams, mode)
            # A project's local rules bind only rows whose cwd is still that project; a reaped cwd
            # is judged on the fleet rules alone (the harvest's union is its own conservative read).
            if st != "recovered":
                rs = fleet_rs
            blockers = []
            for leaf in info["leaves"]:
                o, rule = pm.leaf_verdict(leaf, rs)
                if o in ("ask", "deny") and rule is not None:
                    raw = rule.raw if hasattr(rule, "raw") else str(rule)
                    if o == "deny" or raw not in a.ask_drop:
                        blockers.append("%s-rule:%s" % (o, raw))
            if b == "truncated" or not cmd:
                blockers.append("truncated")
            else:
                v, vr = run_hook(H["validate"], cmd, cwd, home)
                c, cr = (
                    run_hook(H["curl"], cmd, cwd, home)
                    if "curl" in cmd
                    else ("none", "")
                )
                s_, _sr = run_hook(H["smart"], cmd, cwd, home)
                p_, _pr = (
                    run_hook(H["push"], cmd, cwd, home)
                    if "push" in cmd
                    else ("none", "")
                )
                if v in ("ask", "deny"):
                    blockers.append("validate-bash:" + vr[:70])
                if c in ("ask", "deny"):
                    blockers.append("curl-gate:" + cr[:70])
                hook_allow = "allow" in (s_, p_, c)
                rule_clean = (
                    not info["structural"]
                    and not info["uncovered"]
                    and b not in ("hook_or_classifier",)
                )
                if not hook_allow and not rule_clean:
                    blockers.append("no-hook-allow")
            cleared = not blockers
            tally["cleared" if cleared else "asks"] += 1
            tally["w_cleared" if cleared else "w_asks"] += info["waited"]
            for k in dict.fromkeys(
                x.split(":")[0] + (":" + x.split(":", 1)[1][:45] if ":" in x else "")
                for x in blockers
            ):
                still[k] += 1
            out_rows.append(
                {
                    "ts": info["ts"],
                    "sid": info["sid"],
                    "bucket": b,
                    "cls": info["cls"],
                    "cleared": cleared,
                    "blockers": blockers,
                    "waited": info["waited"],
                    "cwd": cwd,
                    "cmd": cmd,
                }
            )
        hk = replay_hookasks(a.hookasks, H, home) if a.hookasks else None
    finally:
        shutil.rmtree(home, ignore_errors=True)
    n = tally["cleared"] + tally["asks"]
    print(
        "ARCHIVE replay — %d Bash dialog(s), %d day(s), tree=%s, ask-drop=%s"
        % (n, a.days, a.tree, a.ask_drop or "none")
    )
    print(
        "  cleared %d (%.1f%%)  still ask %d   waited cleared %.1f h / %.1f h"
        % (
            tally["cleared"],
            100.0 * tally["cleared"] / max(n, 1),
            tally["asks"],
            tally["w_cleared"] / 3600,
            (tally["w_cleared"] + tally["w_asks"]) / 3600,
        )
    )
    print("  rows still asking, by blocker (a row can carry several):")
    for k, v in still.most_common(30):
        print("  %5d  %s" % (v, k))
    if a.rows_out:
        with open(a.rows_out, "w") as f:
            for r in out_rows:
                f.write(json.dumps(r) + "\n")
    if hk:
        t, by, w = hk
        print(
            "HOOKASK replay — %d hook ask(s) (cc-hook-asks), cleared %d (%.1f%%), "
            "waited cleared %.1f h / %.1f h, cwd recovered for %d"
            % (
                t["n"],
                t["cleared"],
                100.0 * t["cleared"] / max(t["n"], 1),
                w[True] / 3600,
                (w[True] + w[False]) / 3600,
                t["cwd"],
            )
        )
        for (key, cleared), v in sorted(by.items(), key=lambda x: -x[1]):
            print(
                "  %5d  %-8s %s | %s"
                % (v, "cleared" if cleared else "asks", key[0], key[1])
            )
    return 0


def _cwd_of(sid, tuid, cache):
    """The cwd the harness recorded on the transcript line that carries this tool_use id."""
    if not sid or not tuid:
        return None
    if sid not in cache:
        # One pass per session: every tool_use id in its transcripts, mapped to the line's cwd.
        base = os.path.expanduser("~/.claude*/projects/*/")
        files = glob.glob(base + sid + ".jsonl") + glob.glob(
            base + sid + "/**/*.jsonl", recursive=True
        )
        ids = {}
        for f in files:
            try:
                with open(f, errors="replace") as fh:
                    for line in fh:
                        if '"tool_use"' not in line:
                            continue
                        for m in re.finditer(r'"id":"(toolu_[A-Za-z0-9]+)"', line):
                            ids.setdefault(m.group(1), line)
            except OSError:
                continue
        cache[sid] = ids
    line = cache[sid].get(tuid)
    if line is None:
        return None
    try:
        return json.loads(line).get("cwd")
    except ValueError:
        return None


def replay_hookasks(path, H, home):
    """Re-run the hook that asked on every cc-hook-asks row; cleared = it no longer asks or denies."""
    rows = []
    with open(path) as f:
        for line in f:
            if line.startswith('{"ts"'):
                rows.append(json.loads(line))
    cache, t, by, w = (
        {},
        collections.Counter(),
        collections.Counter(),
        collections.Counter(),
    )
    for r in rows:
        argv = {"validate-bash": H["validate"], "curl-gate": H["curl"]}.get(
            r.get("hook")
        )
        if argv is None:
            continue
        cwd = _cwd_of(r.get("session"), r.get("tool_use_id"), cache)
        t["cwd"] += bool(cwd)
        d, _why = run_hook(
            argv, r.get("command") or "", cwd or "/", home, agent_id=r.get("agent_id")
        )
        cleared = d not in ("ask", "deny")
        key = (r["hook"], re.sub(r"'[^']*'", "'X'", r.get("reason") or "")[:64])
        t["n"] += 1
        t["cleared"] += cleared
        by[(key, cleared)] += 1
        w[cleared] += r.get("waited_s") or 0
    return t, by, w


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
