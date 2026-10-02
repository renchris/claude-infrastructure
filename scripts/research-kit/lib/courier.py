"""courier.py — one reviewer, rater or verifier per vendor CLI (REPORT.md §3.2 step 6, §3.8, §8 item 7).

  courier.sh preflight --program P
  courier.sh bundle    --program P --round K --plan SEEDED [--extra PATH ...]
  courier.sh run       --program P --round K --pid ID --vendor V --strategy S --role R --brief F
  courier.sh integrity --program P --round K

Every vendor CLI is resolved by ABSOLUTE path through the operator's interactive shell, because an
agent's PATH hides codex and agy (§3.4). A lane is DEAD when its CLI is missing, exits non-zero,
times out or replies with nothing parseable. A dead lane is reported and never filled: no reply is
ever synthesised, and a dead lane's slots are never handed to another vendor (§3.8).

Measured on this machine, 2026-10-01 (the reasons the resolution below is not a bare `which`):
  - Anthropic: the `claude` on PATH (Homebrew, 2.1.278) refuses claude-opus-5-5 ("2.1.280 or newer is
    required"); the operator's `claude` launcher function pins its own binary (`_bin=` in ~/.zshrc), so
    that binary is read out of the launcher.
  - OpenAI: `codex exec --json` never names its model; the responding id is in codex's own session
    record, ~/.codex/sessions/**/rollout-*-<thread_id>.jsonl.
  - Google: the `gemini` CLI is RETIRED for individual accounts — after a successful sign-in it answers
    `IneligibleTierError: UNSUPPORTED_CLIENT … migrate to the Antigravity suite` — so the Google lane runs
    the Antigravity CLI, `agy` (installed to ~/.local/bin by antigravity.google/cli/install.sh), headless:
    `--print … --output-format json --mode plan --sandbox`. A second `agy` on PATH is the Antigravity
    EDITOR's launcher (a symlink into Antigravity.app) and is never a reviewer, so any candidate that
    resolves into an .app bundle is skipped.
Test overrides: CC_RESEARCH_BIN_ANTHROPIC|OPENAI|GOOGLE, CC_RESEARCH_CODEX_SESSIONS.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

sys.path.insert(0, str(Path(__file__).resolve().parent))
import kit  # noqa: E402
import probe_run  # noqa: E402

LAUNCHD_PATH = "/usr/bin:/bin:/usr/sbin:/sbin"
EXCLUDE = {
    "holes.jsonl",
    "rounds",
    "cert",
    "challenges.jsonl",
    "changes.jsonl",
    "verdicts.jsonl",
    ".claude",
    "CLAUDE.md",
    "reconcile.jsonl",
    "rehearsal.json",
}
LANE_BIN = {
    "anthropic": "ANTHROPIC",
    "frontier": "ANTHROPIC",
    "openai": "OPENAI",
    "google": "GOOGLE",
}
DEAD, VOID = 3, 4


# ── resolution ──────────────────────────────────────────────────────────────────────────────────


def resolve(vendor: str) -> Tuple[Optional[str], str]:
    """(absolute binary or None, how it was resolved)."""
    env = os.environ.get(f"CC_RESEARCH_BIN_{LANE_BIN[vendor]}")
    if env is not None:
        return (env if env and Path(env).is_file() else None), "env override"
    if LANE_BIN[vendor] == "ANTHROPIC":
        # The launcher (`claude` -> `_claude_pinned`) names its versioned binary; take the newest
        # one that exists, since a stale Homebrew `claude` on PATH cannot run the pinned models.
        _, body = probe_run.interactive(
            "functions | grep -o '[$A-Za-z0-9/._-]*claude-[0-9][0-9]*/node_modules/.bin/claude' | sort -u"
        )
        found = []
        for cand in body.split():
            p = cand.replace("$HOME", str(Path.home()))
            m = re.search(r"\.claude-(\d+)/", p)
            if m and Path(p).is_file():
                found.append((int(m.group(1)), p))
        if found:
            return max(found)[1], "claude launcher binary"
        rc, p = probe_run.interactive("whence -p claude")
        return (p if rc == 0 and Path(p).is_file() else None), "interactive whence"
    if vendor == "google":
        _, body = probe_run.interactive("whence -a agy")
        cands = [str(Path.home() / ".local" / "bin" / "agy")] + body.split()
        for c in cands:
            if (
                c.startswith("/")
                and Path(c).is_file()
                and ".app/" not in os.path.realpath(c)
            ):
                return c, "antigravity cli (not the editor launcher)"
        return (
            None,
            "interactive whence: no Antigravity CLI (agy outside an .app bundle)",
        )
    rc, p = probe_run.interactive("whence -p codex")
    if rc != 0 or not p.startswith("/"):
        return None, "interactive whence: not found"
    return (p if Path(p).exists() else None), "interactive whence"


def pins(slug: str) -> Dict[str, str]:
    return dict(
        (kit.read_json(kit.records_dir(slug) / "frame.json", {}) or {}).get(
            "reviewer_pins"
        )
        or {}
    )


def argv_for(
    vendor: str, binary: str, prompt: str, model: Optional[str], cwd: Path
) -> List[str]:
    if LANE_BIN[vendor] == "ANTHROPIC":
        return (
            [binary, "-p", "--setting-sources", "local", "--output-format", "json"]
            + (["--model", model] if model else [])
            + [prompt]
        )
    if vendor == "openai":
        return (
            [
                binary,
                "exec",
                "-s",
                "read-only",
                "--skip-git-repo-check",
                "--json",
                "-C",
                str(cwd),
            ]
            + (["-m", model] if model else [])
            + [prompt]
        )
    return [
        binary,
        "--print",
        prompt,
        "--output-format",
        "json",
        "--mode",
        "plan",
        "--sandbox",
        "--add-dir",
        str(cwd),
    ] + (["--model", model] if model else [])


def call(
    slug: str,
    vendor: str,
    binary: str,
    prompt: str,
    model: Optional[str],
    cwd: Path,
    timeout: int,
) -> Dict[str, Any]:
    """Run one vendor process. Returns {exit, raw, stderr, reply, model_ids, wall_s, error}."""
    env = dict(os.environ)
    t0 = time.time()
    try:
        p = subprocess.run(
            argv_for(vendor, binary, prompt, model, cwd),
            cwd=str(cwd),
            env=env,
            stdin=subprocess.DEVNULL,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
        rc, out, err = p.returncode, p.stdout, p.stderr
    except subprocess.TimeoutExpired as e:
        partial = e.stdout or ""
        if isinstance(partial, bytes):
            partial = partial.decode(errors="replace")
        rc, out, err = 124, partial, f"timeout after {timeout}s"
    except OSError as e:
        rc, out, err = 127, "", str(e)
    res: Dict[str, Any] = {
        "exit": rc,
        "raw": out,
        "stderr": err,
        "reply": None,
        "model_ids": [],
        "wall_s": round(time.time() - t0, 1),
        "error": None,
    }
    try:
        res["reply"], res["model_ids"] = parse(vendor, out)
        if vendor == "google" and not res["model_ids"]:
            res["model_ids"] = agy_models(binary, json.loads(out).get("conversation_id") or "")
    except (ValueError, KeyError, TypeError) as e:
        res["error"] = f"unparseable reply: {e}"
    if rc != 0:
        # The last stderr line names the failure; a CLI that states it only in its JSON (agy:
        # status ERROR, empty stderr) keeps that statement rather than a bare exit code.
        lines = err.strip().splitlines()
        last = lines[-1] if lines else (res["error"] or f"exit {rc}")
        res["error"] = re.sub(r"\x1b\[[0-9;]*[A-Za-z]", "", last)[:300]
    elif not res["reply"] and not res["error"]:
        res["error"] = "empty reply"
    return res


def parse(vendor: str, out: str) -> Tuple[Optional[str], List[str]]:
    if LANE_BIN[vendor] == "ANTHROPIC":
        d = json.loads(out)
        if d.get("is_error"):
            raise ValueError(str(d.get("result"))[:200])
        usage = d.get("modelUsage") or {}
        ids = sorted(usage, key=lambda k: -(usage[k] or {}).get("outputTokens", 0))
        return d.get("result"), ids
    if vendor == "openai":
        reply, thread = None, None
        for line in out.splitlines():
            if not line.strip().startswith("{"):
                continue
            ev = json.loads(line)
            if ev.get("type") == "thread.started":
                thread = ev.get("thread_id")
            item = ev.get("item") or {}
            if (
                ev.get("type") == "item.completed"
                and item.get("type") == "agent_message"
            ):
                reply = item.get("text")
        return reply, codex_models(thread) if thread else []
    d = json.loads(out)
    if d.get("status") == "ERROR" or d.get("error"):
        raise ValueError(str(d.get("error") or "status ERROR")[:200])
    ids = (
        [str(d["model"])]
        if d.get("model")
        else list(((d.get("stats") or {}).get("models") or {}).keys())
    )
    return d.get("response"), ids


def agy_models(binary: str, conversation: str) -> List[str]:
    """The model the Antigravity CLI ran, from its own log: `agy --print --output-format json` never
    names it, but the process log that holds the conversation id records the selected model's label
    ("Propagating selected model override to backend: label=..."), and `agy models` maps label to id."""
    if not conversation:
        return []
    root = Path(os.environ.get("CC_RESEARCH_AGY_LOGS") or (Path.home() / ".gemini" / "antigravity-cli" / "log"))
    label = None
    for f in sorted(root.glob("cli-*.log"), key=lambda p: p.stat().st_mtime, reverse=True)[:20]:
        text = f.read_text(errors="replace")
        if conversation in text:
            labels = re.findall(r'selected model override to backend: label="([^"]+)"', text)
            label = labels[-1] if labels else None
            break
    if not label:
        return []
    try:
        p = subprocess.run([binary, "models"], stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=60)
    except (OSError, subprocess.SubprocessError):
        return []
    for line in p.stdout.splitlines():
        mid, _, name = line.partition("\t")
        if name.strip() == label:
            return [mid.strip()]
    return []


def codex_models(thread: str) -> List[str]:
    root = Path(
        os.environ.get("CC_RESEARCH_CODEX_SESSIONS")
        or (Path.home() / ".codex" / "sessions")
    )
    ids: List[str] = []
    for f in sorted(root.rglob(f"rollout-*{thread}.jsonl")):
        for m in re.findall(r'"model":"([^"]+)"', f.read_text(errors="replace")):
            if m not in ids:
                ids.append(m)
    return ids


# ── verbs ───────────────────────────────────────────────────────────────────────────────────────


def cmd_preflight(a: argparse.Namespace) -> int:
    pinned = pins(a.program)
    out: Dict[str, Any] = {}
    work = kit.sealed_dir(a.program, create=True) / "preflight-cwd"
    work.mkdir(exist_ok=True)
    for v in kit.VENDORS:
        binary, how = resolve(v)
        rec: Dict[str, Any] = {
            "binary": binary,
            "resolved_by": how,
            "ok": False,
            "model_id": None,
            "pinned": pinned.get(v),
            "error": None,
            "at": kit.now_iso(),
        }
        if not binary:
            rec["error"] = f"CLI not found ({how})"
        else:
            r = call(
                a.program,
                v,
                binary,
                "Do not use any tools. Answer with exactly the single word OK.",
                pinned.get(v),
                work,
                a.timeout,
            )
            rec["model_id"] = (r["model_ids"] or [None])[0]
            rec["error"] = r["error"]
            rec["ok"] = r["error"] is None
            if rec["ok"] and pinned.get(v) and rec["model_id"] != pinned.get(v):
                rec["ok"], rec["error"] = (
                    False,
                    f"responding model {rec['model_id']} != pin {pinned.get(v)}",
                )
        out[v] = rec
        print(
            f"{v:<10} {'live' if rec['ok'] else 'DEAD'}  {rec['model_id'] or '-'}  "
            f"{binary or '-'}{'  — ' + str(rec['error']) if rec['error'] else ''}"
        )
    kit.write_json_atomic(kit.sealed_dir(a.program) / "preflight.json", out)
    return DEAD if any(not r["ok"] for r in out.values()) else 0


def round_id(v: str) -> str:
    """A round id: a certification round number, `fc<n>` for the frame critique, `delta-<hole>-<n>`."""
    if not re.match(r"^[A-Za-z0-9][A-Za-z0-9-]{0,63}$", v):
        raise argparse.ArgumentTypeError(f"bad round id {v!r}")
    return v


def bundle_dir(slug: str, k: str) -> Path:
    return kit.sealed_dir(slug) / "rounds" / str(k) / "bundle"


def cmd_bundle(a: argparse.Namespace) -> int:
    b = bundle_dir(a.program, a.round)
    if b.exists():
        raise kit.KitError(
            f"bundle {b} already exists; every round gets a fresh bundle"
        )
    rec = kit.records_dir(a.program)
    b.mkdir(parents=True)
    for d in (b, b.parent, b.parent.parent):
        os.chmod(d, 0o700)
    shutil.copyfile(a.plan, b / Path(a.plan).name)
    for src in sorted(rec.iterdir()) if rec.is_dir() else []:
        if src.name in EXCLUDE or src.name.startswith("."):
            continue
        dst = b / src.name
        if src.is_dir():
            shutil.copytree(src, dst, ignore=shutil.ignore_patterns(*EXCLUDE))
        else:
            shutil.copyfile(src, dst)
    for extra in a.extra or []:
        # lockfile-pinned dependency source and the git-log digest (§3.8 "It contains")
        e = Path(extra)
        (b / "deps").mkdir(exist_ok=True)
        if e.is_dir():
            shutil.copytree(e, b / "deps" / e.name)
        else:
            shutil.copyfile(e, b / "deps" / e.name)
    manifest = {
        str(p.relative_to(b)): hashlib.sha256(p.read_bytes()).hexdigest()
        for p in sorted(b.rglob("*"))
        if p.is_file()
    }
    data = json.dumps(manifest, indent=2, sort_keys=True).encode() + b"\n"
    (b / "manifest.json").write_bytes(data)
    h = hashlib.sha256(data).hexdigest()
    (b.parent / "bundle.sha256").write_text(h + "\n")
    print(f"{b} {h}")
    return 0


def panel_dir(slug: str, k: str) -> Path:
    return kit.records_dir(slug) / "rounds" / str(k) / "panels"


def extract_panel(reply: Optional[str]) -> Optional[Dict[str, Any]]:
    """The reviewer's JSON object, bare or fenced; None when there is none with the brief's shape."""
    if not reply:
        return None
    for cand in [reply] + re.findall(r"```(?:json)?\s*(\{.*?\})\s*```", reply, re.S):
        try:
            d = json.loads(cand)
        except ValueError:
            continue
        if isinstance(d, dict) and {"lenses", "findings"} <= set(d):
            return d
    return None


def integrity_needles(slug: str) -> List[str]:
    rec = kit.records_dir(slug)
    frame = kit.read_json(rec / "frame.json", {}) or {}
    needles = {str(rec), os.path.realpath(rec), str(kit.sealed_dir(slug) / "vault")}
    if frame.get("deliverable_repo"):
        needles.add(str(frame["deliverable_repo"]))
    return sorted(n for n in needles if n and n != "/")


def cmd_run(a: argparse.Namespace) -> int:
    b = bundle_dir(a.program, a.round)
    if not (b / "manifest.json").is_file():
        raise kit.KitError(
            f"no bundle for round {a.round}; run courier.sh bundle first"
        )
    pinned = pins(a.program).get(a.vendor)
    binary, how = resolve(a.vendor)
    pd = panel_dir(a.program, a.round)
    pd.mkdir(parents=True, exist_ok=True)
    panel: Dict[str, Any] = {
        "pid": a.pid,
        "round": a.round,
        "vendor": a.vendor,
        "family": kit.VENDOR_FAMILY[a.vendor],
        "binary": binary,
        "strategy": a.strategy,
        "role": a.role,
        "pinned_model": pinned,
        "bundle_hash": (b.parent / "bundle.sha256").read_text().strip(),
        "snapshot_sha": (
            kit.read_json(kit.records_dir(a.program) / "freeze.json", {}) or {}
        ).get("snapshot_sha"),
        "lenses": [],
        "rows": [],
        "findings": [],
        "integrity": {"hits": []},
    }
    if not binary:
        panel.update(
            status="dead",
            error=f"CLI not found ({how})",
            responding_model=None,
            wall_s=0,
        )
        (pd / f"{a.pid}.raw").write_text("")
    else:
        r = call(
            a.program, a.vendor, binary, Path(a.brief).read_text(), pinned, b, a.timeout
        )
        (pd / f"{a.pid}.raw").write_text(r["raw"])
        panel.update(
            responding_model=(r["model_ids"] or [None])[0],
            wall_s=r["wall_s"],
            error=r["error"],
        )
        body = extract_panel(r["reply"])
        hits = [n for n in integrity_needles(a.program) if n in r["raw"]]
        panel["integrity"]["hits"] = hits
        if r["error"]:
            panel["status"] = "dead"
        elif hits or (pinned and panel["responding_model"] != pinned):
            panel["status"] = "void"
        else:
            panel["status"] = "complete" if body else "partial"
            for f in ("lenses", "rows", "findings"):
                panel[f] = (body or {}).get(f, [])
    kit.write_json_atomic(pd / f"{a.pid}.json", panel)
    print(
        f"{a.pid} {a.vendor} {panel['status']} {panel.get('responding_model') or '-'}"
    )
    return {"dead": DEAD, "void": VOID}.get(panel["status"], 0)


def cmd_integrity(a: argparse.Namespace) -> int:
    pd = panel_dir(a.program, a.round)
    needles = integrity_needles(a.program)
    voided = []
    for raw in sorted(pd.glob("*.raw")):
        hits = [n for n in needles if n in raw.read_text(errors="replace")]
        if not hits:
            continue
        pj = raw.with_suffix(".json")
        panel = kit.read_json(pj, {}) or {"pid": raw.stem}
        panel["status"] = "void"
        panel.setdefault("integrity", {})["hits"] = hits
        kit.write_json_atomic(pj, panel)
        voided.append(raw.stem)
    print("voided: " + (" ".join(voided) if voided else "none"))
    return VOID if voided else 0


def main(argv: Optional[List[str]] = None) -> int:
    ap = argparse.ArgumentParser(prog="courier.sh")
    sub = ap.add_subparsers(dest="verb", required=True)
    p = sub.add_parser("preflight")
    p.add_argument("--program", required=True)
    p.add_argument("--timeout", type=int, default=180)
    p.set_defaults(fn=cmd_preflight)
    p = sub.add_parser("bundle")
    p.add_argument("--program", required=True)
    p.add_argument("--round", type=round_id, required=True)
    p.add_argument("--plan", required=True)
    p.add_argument("--extra", action="append")
    p.set_defaults(fn=cmd_bundle)
    p = sub.add_parser("run")
    p.add_argument("--program", required=True)
    p.add_argument("--round", type=round_id, required=True)
    p.add_argument("--pid", required=True)
    p.add_argument("--vendor", required=True, choices=kit.VENDORS)
    p.add_argument("--strategy", required=True)
    p.add_argument("--role", required=True, choices=("reviewer", "rater", "verifier"))
    p.add_argument("--brief", required=True)
    p.add_argument("--timeout", type=int, default=1800)
    p.set_defaults(fn=cmd_run)
    p = sub.add_parser("integrity")
    p.add_argument("--program", required=True)
    p.add_argument("--round", type=round_id, required=True)
    p.set_defaults(fn=cmd_integrity)
    a = ap.parse_args(argv)
    try:
        kit.check_slug(a.program)
        return int(a.fn(a))
    except kit.KitError as e:
        print(f"courier.sh: {e}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
