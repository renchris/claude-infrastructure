#!/usr/bin/env python3
"""instruction_budget — the ONE predicate for always-loaded instruction files (plan D7).

docs/plans/INSTRUCTION_BUDGET.md. Every Claude Code session starts by loading a set of
instruction files in full; on 2026-10-03 that set measured 180k-430k chars per session (a reso
session warned "9 instruction files add up to 428.1k"). This module is the single definition of
which files are in that set, how big the loader thinks they are, and which writes may grow them.
Four callers share it, so they cannot disagree:

  hooks/backup-before-write.sh   PreToolUse Write|Edit|MultiEdit gate      (`verdict`)
  scripts/ship-land.sh           land ratchet over the land's own diff     (`range`)
  bin/cc-instruction-budget      fleet census + auditor + filer            (`census|assert|file`)
  scripts/autonomy-sweep.sh      hourly `file` + `publish`

LOADER EMULATED (Claude Code 2.1.284, read from the bundle; method of
docs/research/instruction-budget-2026-10-03/tools/census.py, which reproduces the 428.1k warning):
  * User memory: $CFG/CLAUDE.md + $CFG/rules/**/*.md (unconditional only).
  * Project walk, every dir D from the one under '/' down to cwd: D/CLAUDE.md, D/.claude/CLAUDE.md,
    D/.claude/rules/**/*.md (unconditional only), D/CLAUDE.local.md.
  * Dedupe by path AND by symlink-resolved path across the whole session (processedPaths).
  * A rule is conditional iff its frontmatter `paths:` list, after slicing a trailing `/**` and
    dropping empties, is non-empty and not all `**`.
  * Size = body after YAML frontmatter, column-0 HTML comment blocks stripped, in UTF-16 units
    (JS .length). No trim. Whitespace-only files are skipped. Files over 4 MiB are skipped.
  * @-imports outside code, depth < 5, text extensions only.
  * claudeMdExcludes (user settings + the repo's .claude/settings*.json) applies type-blind.

VERDICT — the memory-index-budget asymmetry, per file, per conditional file and per tier:
  DENY iff (new > budget AND new > cur). Shrinking and same-size writes always pass, even on a file
  or tier already over budget, so the gate can never refuse the cure for its own condition. A file
  already over is shrink-only. Making a file conditional moves it from the always-loaded measure to
  the conditional cap, so `paths:` is not an unbudgeted escape (critic.md §2.5).

FAIL OPEN on every internal error. No agent-reachable env bypass: env seams are honoured only under
CC_IB_TEST=1; the production switch is the landed `enforce` key in config/instruction-budget.json.
Python 3.9 compatible on purpose: launchd's python3 is /usr/bin/python3 3.9.
"""

import hashlib
import json
import os
import re
import signal
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.realpath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
DEFAULT_CONFIG = os.path.join(REPO, "config", "instruction-budget.json")
MAX_BYTES = 4 * 1024 * 1024
IMPORT_DEPTH = 5
TEXT_EXT = {
    ".md",
    ".txt",
    ".text",
    ".json",
    ".yaml",
    ".yml",
    ".toml",
    ".xml",
    ".sh",
    ".py",
    ".ts",
    ".js",
}
RULES_SEG = "/.claude/rules/"


def home():
    return os.path.expanduser("~")


def testing():
    return os.environ.get("CC_IB_TEST") == "1"


def load_config(path=None):
    p = path or DEFAULT_CONFIG
    if testing() and os.environ.get("CC_IB_CONFIG"):
        p = os.environ["CC_IB_CONFIG"]
    with open(p, encoding="utf-8") as fh:
        cfg = json.load(fh)
    for k in ("per_file", "conditional_per_file", "tiers"):
        if k not in cfg:
            raise ValueError("config missing " + k)
    return cfg


# ── measure ──────────────────────────────────────────────────────────────────────────────────────


def jslen(s):
    return len(s) + sum(1 for ch in s if ord(ch) > 0xFFFF)


_FM = re.compile(r"^---\s*\n(.*?)\n---\s*(?:\n|$)", re.S)


def split_frontmatter(raw):
    """-> (paths list or None when the key is absent, body)."""
    m = _FM.match(raw)
    if not m:
        return None, raw
    fm_text, body = m.group(1), raw[m.end() :]
    # [ \t]*, never \s*: \s crosses the newline, so a YAML list (`paths:` then `  - "**"`) would be
    # captured as the scalar `- "**"` and read as conditional (census.py carries that bug).
    pm = re.search(r"^paths[ \t]*:[ \t]*(.*)$", fm_text, re.M)
    if not pm:
        return None, body
    val = pm.group(1).strip()
    items = []
    if val and val not in ("|", ">"):
        items = [
            v.strip().strip("\"'") for v in val.strip("[]").split(",") if v.strip()
        ]
    else:
        for line in fm_text[pm.end() :].splitlines():
            lm = re.match(r"^\s*-\s*(.+)$", line)
            if lm:
                items.append(lm.group(1).strip().strip("\"'"))
            elif line.strip():
                break
    return items, body


def is_conditional(paths):
    if paths is None:
        return False
    globs = [g[:-3] if g.endswith("/**") else g for g in paths]
    globs = [g for g in globs if g]
    return bool(globs) and not all(g == "**" for g in globs)


def strip_comment_blocks(body):
    if "<!--" not in body:
        return body
    return re.sub(
        r"(?m)^[ ]{0,3}<!--[\s\S]*?-->[^\n]*",
        lambda m: re.sub(r"<!--[\s\S]*?-->", "", m.group(0)),
        body,
    )


def _strip_code(body):
    body = re.sub(r"(?ms)^[ ]{0,3}(```|~~~).*?^[ ]{0,3}\1[^\n]*$", "", body)
    return re.sub(r"`[^`\n]*`", "", body)


class Info(object):
    __slots__ = ("units", "conditional", "imports", "sha")

    def __init__(self, units, conditional, imports, sha):
        self.units, self.conditional, self.imports, self.sha = (
            units,
            conditional,
            imports,
            sha,
        )


def parse(text, path, rules_file):
    paths, body = split_frontmatter(text)
    content = strip_comment_blocks(body)
    units = 0 if not content.strip() else jslen(content)
    imports = []
    if "@" in content:
        for m in re.finditer(r"(?:^|\s)@((?:[^\s\\]|\\ )+)", _strip_code(content)):
            d = m.group(1).split("#")[0].replace("\\ ", " ")
            if not d or d == "/":
                continue
            if not (
                d.startswith(("./", "~/", "/"))
                or (not d.startswith("@") and re.match(r"^[a-zA-Z0-9._-]", d))
            ):
                continue
            tgt = (
                os.path.expanduser(d)
                if d.startswith("~/")
                else os.path.normpath(os.path.join(os.path.dirname(path), d))
            )
            ext = os.path.splitext(tgt)[1].lower()
            if ext == "" or ext in TEXT_EXT:
                imports.append(tgt)
    return Info(
        units,
        rules_file and is_conditional(paths),
        imports,
        hashlib.sha256(content.encode("utf-8", "replace")).hexdigest(),
    )


# ── file systems: live disk (with a projected-write overlay) and a git revision ─────────────────


def phys(p):
    """Absolute path with every symlinked ANCESTOR resolved; the leaf may not exist."""
    p = os.path.normpath(os.path.abspath(p))
    head, tail = os.path.split(p)
    return os.path.join(os.path.realpath(head), tail)


class DiskFS(object):
    def __init__(self, overlay=None):
        # overlay: {phys path: text or None (None = deleted)}
        self.overlay = dict((phys(k), v) for k, v in (overlay or {}).items())

    def realpath(self, p):
        q = phys(p)
        if q in self.overlay:
            return q
        return os.path.realpath(p)

    def read(self, p):
        q = phys(p)
        if q in self.overlay:
            return self.overlay[q]
        r = os.path.realpath(p)
        if r in self.overlay:
            return self.overlay[r]
        try:
            if not os.path.isfile(p) or os.path.getsize(p) > MAX_BYTES:
                return None
            with open(p, encoding="utf-8", errors="replace") as fh:
                return fh.read()
        except OSError:
            return None

    def rules(self, rdir):
        out, seen = [], set()

        def walk(d):
            try:
                rp = os.path.realpath(d)
                if rp in seen or not os.path.isdir(d):
                    return
                seen.add(rp)
                for e in sorted(os.listdir(d)):
                    p = os.path.join(d, e)
                    if os.path.isdir(p):
                        walk(p)
                    elif e.endswith(".md"):
                        out.append(p)
            except OSError:
                pass

        walk(rdir)
        root = phys(rdir) + "/"
        have = set(phys(p) for p in out)
        for k in sorted(self.overlay):
            if k.startswith(root) and k.endswith(".md") and k not in have:
                out.append(k)
        return out


class GitFS(object):
    """Files under `repo` read at `rev`; anything outside the repo reads the live disk."""

    def __init__(self, repo, rev):
        self.repo, self.rev = repo.rstrip("/"), rev
        self.disk = DiskFS()
        self._tree = None

    def _rel(self, p):
        p = os.path.normpath(p)
        if p == self.repo or p.startswith(self.repo + "/"):
            return os.path.relpath(p, self.repo)
        return None

    def realpath(self, p):
        return (
            os.path.normpath(p) if self._rel(p) is not None else self.disk.realpath(p)
        )

    def tree(self):
        if self._tree is None:
            r = subprocess.run(
                ["git", "-C", self.repo, "ls-tree", "-r", "--name-only", self.rev],
                capture_output=True,
                text=True,
                timeout=60,
            )
            if r.returncode != 0:
                raise RuntimeError("git ls-tree failed: " + r.stderr.strip())
            self._tree = set(r.stdout.splitlines())
        return self._tree

    def read(self, p):
        rel = self._rel(p)
        if rel is None:
            return self.disk.read(p)
        if rel not in self.tree():
            return None
        r = subprocess.run(
            ["git", "-C", self.repo, "show", "%s:%s" % (self.rev, rel)],
            capture_output=True,
            timeout=60,
        )
        if r.returncode != 0 or len(r.stdout) > MAX_BYTES:
            return None
        return r.stdout.decode("utf-8", "replace")

    def rules(self, rdir):
        rel = self._rel(rdir)
        if rel is None:
            return self.disk.rules(rdir)
        pre = rel.rstrip("/") + "/"
        return [
            os.path.join(self.repo, f)
            for f in sorted(self.tree())
            if f.startswith(pre) and f.endswith(".md")
        ]


# ── excludes, config dirs, repo roots ────────────────────────────────────────────────────────────


def _glob_rx(g):
    out, i = "", 0
    while i < len(g):
        if g.startswith("**/", i):
            out += "(?:.*/)?"
            i += 3
        elif g.startswith("**", i):
            out += ".*"
            i += 2
        elif g[i] == "*":
            out += "[^/]*"
            i += 1
        elif g[i] == "?":
            out += "[^/]"
            i += 1
        else:
            out += re.escape(g[i])
            i += 1
    return re.compile("^" + out + "$")


def _settings_files(repo_root=None):
    h = home()
    fs = [
        os.path.join(h, ".claude", "settings.json"),
        os.path.join(h, ".claude", "settings.local.json"),
    ]
    cd = os.environ.get("CLAUDE_CONFIG_DIR")
    if cd:
        fs += [
            os.path.join(cd, "settings.json"),
            os.path.join(cd, "settings.local.json"),
        ]
    if repo_root:
        fs += [
            os.path.join(repo_root, ".claude", "settings.json"),
            os.path.join(repo_root, ".claude", "settings.local.json"),
        ]
    return fs


class Excludes(object):
    def __init__(self, repo_roots=()):
        pats = []
        seen = set()
        for root in [None] + list(repo_roots):
            for f in _settings_files(root):
                if f in seen:
                    continue
                seen.add(f)
                try:
                    with open(f, encoding="utf-8") as fh:
                        pats += json.load(fh).get("claudeMdExcludes", []) or []
                except Exception:
                    pass
        self.rx = [_glob_rx(os.path.expanduser(p)) for p in pats if isinstance(p, str)]

    def __call__(self, path):
        if not self.rx:
            return False
        rp = os.path.realpath(path)
        return any(r.match(path) or r.match(rp) for r in self.rx)


def config_dirs():
    """~/.claude, every accounts.json config_dir, and $CLAUDE_CONFIG_DIR — never a hardcoded list."""
    h = home()
    out = [os.path.join(h, ".claude")]
    try:
        with open(os.path.join(h, ".claude", "accounts.json"), encoding="utf-8") as fh:
            for a in json.load(fh).get("accounts", []):
                cd = a.get("config_dir")
                if cd:
                    out.append(os.path.expanduser(cd))
    except Exception:
        pass
    if os.environ.get("CLAUDE_CONFIG_DIR"):
        out.append(os.environ["CLAUDE_CONFIG_DIR"])
    res, seen = [], set()
    for d in out:
        d = os.path.normpath(d)
        if d not in seen and os.path.isdir(d):
            seen.add(d)
            res.append(d)
    return res


def git_root(d):
    """Nearest ancestor-or-self holding .git (dir or worktree file), else None. No subprocess."""
    d = os.path.normpath(d)
    while True:
        if os.path.exists(os.path.join(d, ".git")):
            return d
        nd = os.path.dirname(d)
        if nd == d:
            return None
        d = nd


def main_repo(root):
    """A worktree's main checkout (via its .git file), else root itself."""
    g = os.path.join(root, ".git")
    try:
        if os.path.isfile(g):
            with open(g, encoding="utf-8") as fh:
                line = fh.read().strip()
            if line.startswith("gitdir:"):
                gd = line.split(":", 1)[1].strip()
                if not os.path.isabs(gd):
                    gd = os.path.normpath(os.path.join(root, gd))
                m = re.match(r"^(.*)/\.git/worktrees/[^/]+$", gd)
                if m:
                    return m.group(1)
    except OSError:
        pass
    return root


# ── classification of one written path ──────────────────────────────────────────────────────────


def owning_dir(p):
    """-> (D, kind) when p is a project-walk instruction file of directory D, else (None, None).
    kind: 'md' (CLAUDE.md / .claude/CLAUDE.md / CLAUDE.local.md) or 'rule'."""
    base = os.path.basename(p)
    parent = os.path.dirname(p)
    if base == "CLAUDE.md":
        if os.path.basename(parent) == ".claude":
            return os.path.dirname(parent), "md"
        return parent, "md"
    if base == "CLAUDE.local.md":
        return parent, "md"
    if p.endswith(".md") and RULES_SEG in p:
        return p.split(RULES_SEG, 1)[0] or "/", "rule"
    return None, None


def classify(path, cfg, cfgdirs=None):
    """-> list of memberships {tier, key, rule}; tier in user|ancestor|repo|nested|source."""
    p = phys(path)
    rp = os.path.realpath(path)
    out = []
    for c in cfgdirs if cfgdirs is not None else config_dirs():
        md = os.path.join(c, "CLAUDE.md")
        if p in (phys(md), os.path.realpath(md)) or rp == os.path.realpath(md):
            out.append(dict(tier="user", key=c, rule=False))
            continue
        rd = os.path.join(c, "rules")
        roots = set([phys(rd) + "/", os.path.realpath(rd) + "/"])
        if p.endswith(".md") and any(
            p.startswith(r) or rp.startswith(r) for r in roots
        ):
            out.append(dict(tier="user", key=c, rule=True))
    if out:
        return out  # a user file is budgeted as user; post-D2 its ancestor copy dedupes away
    srcs = cfg.get("deploy_sources") or {}
    if os.path.basename(p) in srcs and os.path.isfile(
        os.path.join(os.path.dirname(p), "install.sh")
    ):
        return [
            dict(tier="source", key=p, rule=False, maps_to=srcs[os.path.basename(p)])
        ]
    d, kind = owning_dir(p)
    if d is None:
        return out
    root = git_root(d)
    if root is None:
        out.append(dict(tier="ancestor", key=d, rule=kind == "rule"))
    elif os.path.normpath(root) == os.path.normpath(d):
        out.append(dict(tier="repo", key=d, rule=kind == "rule"))
    else:
        out.append(dict(tier="nested", key=d, rule=kind == "rule"))
    return out


# ── loaded-set emulation ─────────────────────────────────────────────────────────────────────────


class Loader(object):
    """One session's processedPaths: shared dedupe across user + every walked dir."""

    def __init__(self, fs, excl):
        self.fs, self.excl = fs, excl
        self.seen = set()
        self.rows = []  # dict(path, real, units, type, tier, imported, sha)
        self._info = {}

    def info(self, p, rules_file):
        k = (p, rules_file)
        if k not in self._info:
            t = self.fs.read(p)
            self._info[k] = None if t is None else parse(t, p, rules_file)
        return self._info[k]

    def add(self, p, typ, tier, rules_file=False, depth=0):
        if depth >= IMPORT_DEPTH or self.excl(p):
            return
        inf = self.info(p, rules_file and depth == 0)
        if inf is None:
            return
        if depth == 0 and inf.conditional:
            return
        real = self.fs.realpath(p)
        if p in self.seen or real in self.seen:
            return
        self.seen.add(p)
        self.seen.add(real)
        if inf.units == 0:
            return
        self.rows.append(
            dict(
                path=p,
                real=real,
                units=inf.units,
                type=typ,
                tier=tier,
                imported=depth > 0,
                sha=inf.sha,
            )
        )
        for imp in inf.imports:
            self.add(imp, typ, tier, False, depth + 1)

    def user(self, c):
        self.add(os.path.join(c, "CLAUDE.md"), "User", "user")
        for r in self.fs.rules(os.path.join(c, "rules")):
            self.add(r, "User", "user", True)

    def walk_dir(self, d, tier):
        self.add(os.path.join(d, "CLAUDE.md"), "Project", tier)
        self.add(os.path.join(d, ".claude", "CLAUDE.md"), "Project", tier)
        for r in self.fs.rules(os.path.join(d, ".claude", "rules")):
            self.add(r, "Project", tier, True)
        self.add(os.path.join(d, "CLAUDE.local.md"), "Local", tier)

    def total(self):
        return sum(r["units"] for r in self.rows)


def tier_units(fs, excl, m):
    """Effective units of the tier a membership belongs to (its own dedupe scope)."""
    L = Loader(fs, excl)
    if m["tier"] == "user":
        L.user(m["key"])
    elif m["tier"] in ("repo", "ancestor"):
        L.walk_dir(m["key"], m["tier"])
    else:
        return None
    return L.total()


def session(cfgdir, cwd, fs=None, excl=None):
    fs = fs or DiskFS()
    root = git_root(cwd)
    excl = excl or Excludes([root] if root else [])
    L = Loader(fs, excl)
    L.user(cfgdir)
    chain, d = [], os.path.normpath(cwd)
    while d not in ("/", ""):
        chain.insert(0, d)
        d = os.path.dirname(d)
    for d in chain:
        if root and (d == root or d.startswith(root + "/")):
            tier = "repo"
        else:
            tier = "ancestor"
        L.walk_dir(d, tier)
    return L.rows


def limits(window):
    per = max(40000, int(round(window * 0.05 * 3)))
    return per, max(120000, per)


# ── the verdict ──────────────────────────────────────────────────────────────────────────────────


def _eff(text, path, rules_file):
    """(always-loaded units, conditional units) of one file's text."""
    if text is None:
        return 0, 0
    inf = parse(text, path, rules_file)
    return (0, inf.units) if inf.conditional else (inf.units, 0)


def judge(path, cur, new, cfg, fs_cur=None, fs_new=None, excl=None, cfgdirs=None):
    """Findings for a change of `path` from text `cur` to `new` (None = absent). [] = allow."""
    ms = classify(path, cfg, cfgdirs)
    if not ms:
        return []
    roots = [m["key"] for m in ms if m["tier"] == "repo"] or [
        git_root(os.path.dirname(phys(path)))
    ]
    excl = excl or Excludes([r for r in roots if r])
    if excl(path):
        return []
    rules_file = any(m["rule"] for m in ms)
    fs_cur = fs_cur or DiskFS()
    fs_new = fs_new or DiskFS({path: new})
    out = []
    cf, cc = _eff(cur, path, rules_file)
    nf, nc = _eff(new, path, rules_file)
    per, cond = int(cfg["per_file"]), int(cfg["conditional_per_file"])
    if nf > per and nf > cf:
        out.append(
            dict(
                kind="file",
                tier=ms[0]["tier"],
                key=ms[0]["key"],
                path=path,
                cur=cf,
                new=nf,
                budget=per,
            )
        )
    if nc > cond and nc > cc:
        out.append(
            dict(
                kind="conditional",
                tier=ms[0]["tier"],
                key=ms[0]["key"],
                path=path,
                cur=cc,
                new=nc,
                budget=cond,
            )
        )
    tiers = cfg["tiers"]
    for m in ms:
        if m["tier"] not in tiers:
            continue
        budget = int(tiers[m["tier"]])
        ct = tier_units(fs_cur, excl, m)
        nt = tier_units(fs_new, excl, m)
        if ct is None or nt is None:
            continue
        if nt > budget and nt > ct:
            out.append(
                dict(
                    kind="tier",
                    tier=m["tier"],
                    key=m["key"],
                    path=path,
                    cur=ct,
                    new=nt,
                    budget=budget,
                )
            )
    return out


def project(tool, ti, cur):
    """Projected post-write text (port of memory-index-budget.sh _MIB_JQ_PROJECT); None = unknown."""

    def apply(text, old, new, all_):
        if not old:
            return text
        parts = text.split(old)
        if all_:
            return new.join(parts)
        if len(parts) < 2:
            return text
        return parts[0] + new + old.join(parts[1:])

    if tool == "Write":
        c = ti.get("content")
        return c if isinstance(c, str) else None
    base = cur if cur is not None else ""
    if tool == "Edit":
        o, n = ti.get("old_string"), ti.get("new_string")
        if not isinstance(o, str) or not isinstance(n, str):
            return None
        return apply(base, o, n, bool(ti.get("replace_all")))
    if tool == "MultiEdit":
        edits = ti.get("edits")
        if not isinstance(edits, list):
            return None
        t = base
        for e in edits:
            if not isinstance(e, dict):
                return None
            t = apply(
                t,
                e.get("old_string") or "",
                e.get("new_string") or "",
                bool(e.get("replace_all")),
            )
        return t
    return None


def _k(n):
    return "{:,}".format(n)


def destination(f, cfg):
    d = cfg.get("destinations") or {}
    if f["kind"] == "conditional":
        return d.get("conditional", "")
    if f["tier"] in ("user", "source"):
        return d.get("user", "")
    if f["tier"] == "ancestor":
        return d.get("ancestor", "")
    repo = os.path.basename(main_repo(git_root(f["key"]) or f["key"]))
    return (d.get("repos") or {}).get(repo, d.get("repo", ""))


def message(findings, cfg, where="this write"):
    lines = []
    for f in findings:
        what = {
            "file": "always-loaded file",
            "conditional": "conditional (paths:) rule",
            "tier": "%s tier at %s" % (f["tier"], f["key"].replace(home(), "~")),
        }[f["kind"]]
        subj = f["path"].replace(home(), "~") if f["kind"] != "tier" else what
        lines.append(
            "%s: %s chars -> %s (budget %s%s)"
            % (
                subj,
                _k(f["cur"]),
                _k(f["new"]),
                _k(f["budget"]),
                "" if f["kind"] == "tier" else ", " + what,
            )
        )
    dest = destination(findings[0], cfg)
    return (
        "INSTRUCTION BUDGET: %s grows always-loaded instructions past budget. %s. "
        "These files load in full into every session's context at start. Shrinking or "
        "same-size writes always pass. Where it goes instead: %s Budgets: "
        "config/instruction-budget.json (docs/plans/INSTRUCTION_BUDGET.md D7)."
        % (where, "; ".join(lines), dest)
    )


def _idl(disposition, reason, path, sid="?"):
    try:
        p = os.environ.get("CC_IDL") or os.path.join(
            home(), ".claude", "autonomy", "idl.jsonl"
        )
        os.makedirs(os.path.dirname(p), exist_ok=True)
        row = dict(
            ts=time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            hook="backup-before-write:instruction-budget",
            sid=sid,
            disposition=disposition,
            reason=reason[:600],
            path=path,
        )
        with open(p, "a", encoding="utf-8") as fh:
            fh.write(json.dumps(row) + "\n")
    except Exception:
        pass


def _timeout(_s, _f):
    raise TimeoutError("instruction-budget verdict timed out")


def cmd_verdict(argv):
    """stdin = PreToolUse payload. Prints the deny JSON or nothing. Always exits 0 (fail open)."""
    path, sid = "?", "?"
    try:
        signal.signal(signal.SIGALRM, _timeout)
        signal.alarm(4)
        payload = json.loads(sys.stdin.read() or "{}")
        sid = payload.get("session_id") or "?"
        ti = payload.get("tool_input") or {}
        path = ti.get("file_path") or ""
        if not path:
            return 0
        if not os.path.isabs(path):
            path = os.path.join(payload.get("cwd") or os.getcwd(), path)
        path = os.path.normpath(path)
        cfg = load_config()
        cur = DiskFS().read(path)
        new = project(payload.get("tool_name") or "", ti, cur)
        if new is None:
            return 0
        findings = judge(path, cur, new, cfg)
        if not findings:
            return 0
        msg = message(findings, cfg)
        if cfg.get("enforce") is True:
            _idl("denied", msg, path, sid)
            print(
                json.dumps(
                    {
                        "hookSpecificOutput": {
                            "hookEventName": "PreToolUse",
                            "permissionDecision": "deny",
                            "permissionDecisionReason": msg,
                        }
                    }
                )
            )
        else:
            _idl("shadow-deny", msg, path, sid)
        return 0
    except Exception as e:  # fail open, but leave a row saying the write was not judged
        _idl("abstained", "%s: %s" % (type(e).__name__, e), path, sid)
        return 0
    finally:
        signal.alarm(0)


# ── land ratchet ─────────────────────────────────────────────────────────────────────────────────


def _git(repo, *a):
    r = subprocess.run(
        ["git", "-C", repo] + list(a), capture_output=True, text=True, timeout=60
    )
    if r.returncode != 0:
        raise RuntimeError("git %s failed: %s" % (" ".join(a), r.stderr.strip()))
    return r.stdout.strip()


def range_findings(repo, rng, cfg):
    if ".." in rng:
        a, b = rng.split("...", 1) if "..." in rng else rng.split("..", 1)
        b = b or "HEAD"
    else:
        a, b = rng, "HEAD"
    base = _git(repo, "merge-base", a, b)
    head = _git(repo, "rev-parse", b)
    changed = [
        ln
        for ln in _git(
            repo, "diff", "--name-only", "--no-renames", base, head
        ).splitlines()
        if ln
    ]
    fs_b, fs_h = GitFS(repo, base), GitFS(repo, head)
    excl = Excludes([repo])
    out = []
    for rel in changed:
        p = os.path.join(repo, rel)
        if not classify(p, cfg, cfgdirs=[]):
            continue
        out += judge(
            p,
            fs_b.read(p),
            fs_h.read(p),
            cfg,
            fs_cur=fs_b,
            fs_new=fs_h,
            excl=excl,
            cfgdirs=[],
        )
    # one tier finding per tier, not one per file that touched it
    seen, res = set(), []
    for f in out:
        k = (f["kind"], f["tier"], f["key"], f["path"] if f["kind"] != "tier" else "")
        if k not in seen:
            seen.add(k)
            res.append(f)
    return res


def cmd_range(argv):
    """rc 0 clean (or shadow) · 1 refuse · 2 non-verdict."""
    try:
        rng = argv[0] if argv else ""
        if not rng:
            print(
                "usage: cc-instruction-budget range <base>..<head> [--repo R]",
                file=sys.stderr,
            )
            return 2
        repo = (
            argv[argv.index("--repo") + 1]
            if "--repo" in argv
            else _git(os.getcwd(), "rev-parse", "--show-toplevel")
        )
        cfg = load_config()
        fs = range_findings(repo, rng, cfg)
    except Exception as e:
        print(
            "instruction-budget range: NON-VERDICT — %s: %s" % (type(e).__name__, e),
            file=sys.stderr,
        )
        return 2
    if not fs:
        print(
            "instruction-budget range: clean — no always-loaded instruction file or tier grew past budget"
        )
        return 0
    msg = message(fs, cfg, where="this land")
    if cfg.get("enforce") is True:
        print("instruction-budget range: REFUSE — " + msg)
        return 1
    print("instruction-budget range: SHADOW (enforce=false, not refusing) — " + msg)
    return 0


# ── census / assert / file / publish ─────────────────────────────────────────────────────────────


def collect_cwds(days):
    """Distinct session cwds from ~/.claude*/projects transcripts touched in `days` + live procs."""
    h = home()
    cut = time.time() - days * 86400
    out, seen_pd = {}, set()
    try:
        pds = sorted(
            os.path.join(h, e, "projects")
            for e in os.listdir(h)
            if e.startswith(".claude")
        )
    except OSError:
        pds = []
    for pd in pds:
        rp = os.path.realpath(pd)
        if rp in seen_pd or not os.path.isdir(pd):
            continue
        seen_pd.add(rp)
        for d in os.scandir(pd):
            try:
                if not d.is_dir() or d.stat().st_mtime < cut:
                    continue
                cwd, n = None, 0
                for f in os.scandir(d.path):
                    if not f.name.endswith(".jsonl") or f.stat().st_mtime < cut:
                        continue
                    n += 1
                    if cwd:
                        continue
                    with open(f.path, errors="ignore") as fh:
                        for i, line in enumerate(fh):
                            if i > 60:
                                break
                            if '"cwd"' in line:
                                try:
                                    cwd = json.loads(line).get("cwd")
                                except Exception:
                                    pass
                                if cwd:
                                    break
                if cwd and n:
                    out[cwd] = out.get(cwd, 0) + n
            except OSError:
                continue
    try:
        r = subprocess.run(
            ["lsof", "-a", "-d", "cwd", "-c", "claude", "-Fn"],
            capture_output=True,
            text=True,
            timeout=30,
        )
        for ln in r.stdout.splitlines():
            if ln.startswith("n/"):
                out.setdefault(ln[1:], 0)
    except Exception:
        pass
    return out


def bucket(cwd):
    """-> repo label root (main checkout for worktrees), or None to skip."""
    h = home()
    # $HOME only: the fleet's sessions live there, and /tmp eval harnesses are fixtures, not fleet.
    if not (cwd == h or cwd.startswith(h + "/")) or not os.path.isdir(cwd):
        return None
    root = git_root(cwd)
    if root:
        return main_repo(root)
    if cwd.startswith(os.path.join(h, ".claude") + "/"):
        return os.path.join(h, ".claude")
    return cwd


def population(days, extra_roots=()):
    """{label: [cwds]} — the recent fleet plus $HOME, plus any explicit roots."""
    groups = {}
    for cwd in list(collect_cwds(days)) + [home()] + list(extra_roots):
        lab = bucket(cwd)
        if lab:
            groups.setdefault(lab, set()).add(cwd)
    return groups


def global_user_reals(cfgdirs):
    s = set()
    fs = DiskFS()
    for c in cfgdirs:
        md = os.path.join(c, "CLAUDE.md")
        if os.path.exists(md):
            s.add(os.path.realpath(md))
        for r in fs.rules(os.path.join(c, "rules")):
            s.add(os.path.realpath(r))
    return s


def analyse(rows, cfg, gset):
    per = int(cfg["per_file"])
    tiers = dict(
        (t, sum(r["units"] for r in rows if r["tier"] == t))
        for t in ("user", "ancestor", "repo")
    )
    dups = []
    for r in rows:
        if r["type"] != "User" and r["real"] in gset:
            dups.append(
                "%s loaded as %s on top of the user copy"
                % (r["path"].replace(home(), "~"), r["type"])
            )
    by_sha = {}
    for r in rows:
        by_sha.setdefault(r["sha"], []).append(r)
    for sha, rs in by_sha.items():
        if len(set(x["real"] for x in rs)) > 1:
            dups.append(
                "identical content loaded twice: "
                + ", ".join(x["path"].replace(home(), "~") for x in rs)
            )
    over = [r for r in rows if r["units"] > per]
    return dict(
        tiers=tiers,
        total=sum(r["units"] for r in rows),
        files=len(rows),
        over=over,
        dups=dups,
    )


def census_data(days, extra_roots=()):
    cfg = load_config()
    cfgdirs = config_dirs()
    gset = global_user_reals(cfgdirs)
    out = []
    for lab, cwds in sorted(population(days, extra_roots).items()):
        for c in cfgdirs:
            reps = {}
            for cwd in cwds:
                reps[cwd] = session(c, cwd)
            rep = max(reps, key=lambda k: (sum(r["units"] for r in reps[k]), k))
            rows = reps[rep]
            a = analyse(rows, cfg, gset)
            sig = tuple(sorted((r["real"], r["units"], r["type"]) for r in rows))
            hit = None
            for e in out:
                if e["label"] == lab and e["sig"] == sig:
                    hit = e
            if hit:
                hit["cfgs"].append(c)
                continue
            out.append(dict(label=lab, cwd=rep, cfgs=[c], rows=rows, sig=sig, **a))
    return cfg, out


def classes(cfg, data):
    """{condition suffix: dict(owner, repo, title)} — one entry per breach class."""
    per = int(cfg["per_file"])
    tb = cfg["tiers"]
    res = {}

    def add(cls, owner, repo, text):
        e = res.setdefault(cls, dict(owner=owner, repo=repo, lines=[]))
        if text not in e["lines"]:
            e["lines"].append(text)

    for e in data:
        lab = e["label"].replace(home(), "~")
        cf = ",".join(os.path.basename(c) for c in e["cfgs"])
        if e["dups"]:
            add(
                "dedupe",
                "claude-infrastructure",
                None,
                "%s [%s]: %s" % (lab, cf, "; ".join(e["dups"][:3])),
            )
        for t in ("user", "ancestor", "repo"):
            big = [r for r in e["over"] if r["tier"] == t]
            if e["tiers"][t] > int(tb[t]) or big:
                txt = "%s tier %s > %s%s" % (
                    t,
                    _k(e["tiers"][t]),
                    _k(int(tb[t])),
                    "".join(
                        "; %s %s > %s"
                        % (r["path"].replace(home(), "~"), _k(r["units"]), _k(per))
                        for r in big
                    ),
                )
                if t == "repo":
                    add(
                        "repo-" + os.path.basename(e["label"]),
                        os.path.basename(e["label"]),
                        e["label"],
                        txt,
                    )
                elif t == "user":
                    add("user", "claude-infrastructure", None, "[%s] %s" % (cf, txt))
                else:
                    add(
                        "ancestor",
                        "claude-infrastructure",
                        None,
                        "%s [%s]: %s" % (lab, cf, txt),
                    )
    return res


def render(data):
    hdr = (
        "repo",
        "config dirs",
        "files",
        "total",
        "user",
        "ancestor",
        "repo tier",
        "largest",
        ">40k",
        "dup",
    )
    rows = []
    worst = {}
    for e in data:
        worst[e["label"]] = max(worst.get(e["label"], 0), e["total"])
    for e in sorted(data, key=lambda x: (-worst[x["label"]], x["label"], -x["total"])):
        big = max(e["rows"], key=lambda r: r["units"]) if e["rows"] else None
        rows.append(
            (
                e["label"].replace(home(), "~"),
                ",".join(os.path.basename(c) for c in e["cfgs"]),
                str(e["files"]),
                _k(e["total"]),
                _k(e["tiers"]["user"]),
                _k(e["tiers"]["ancestor"]),
                _k(e["tiers"]["repo"]),
                ("%s %s" % (os.path.basename(big["path"]), _k(big["units"])))
                if big
                else "-",
                str(len(e["over"])),
                "DUP" if e["dups"] else "-",
            )
        )
    w = [
        max(len(h), *(len(r[i]) for r in rows)) if rows else len(h)
        for i, h in enumerate(hdr)
    ]

    def fmt(r):
        return "| " + " | ".join(c.ljust(w[i]) for i, c in enumerate(r)) + " |"

    return "\n".join(
        [fmt(hdr), "|" + "|".join("-" * (x + 2) for x in w) + "|"]
        + [fmt(r) for r in rows]
    )


def _opt(argv, name, default=None):
    return (
        argv[argv.index(name) + 1]
        if name in argv and argv.index(name) + 1 < len(argv)
        else default
    )


def cmd_census(argv):
    try:
        days = float(_opt(argv, "--days", "7"))
        cfg, data = census_data(days)
    except Exception as e:
        print(
            "instruction-budget census: NON-VERDICT — %s: %s" % (type(e).__name__, e),
            file=sys.stderr,
        )
        return 3
    if "--json" in argv:
        print(
            json.dumps(
                [dict((k, v) for k, v in e.items() if k != "sig") for e in data],
                indent=1,
            )
        )
        return 0
    print(render(data))
    print(
        "\nper-file budget %s · tiers user %s / ancestor %s / repo %s · units = loader chars "
        "(UTF-16, frontmatter + comment blocks stripped) · DUP = an instruction file loaded twice"
        % (
            _k(int(cfg["per_file"])),
            _k(int(cfg["tiers"]["user"])),
            _k(int(cfg["tiers"]["ancestor"])),
            _k(int(cfg["tiers"]["repo"])),
        )
    )
    return 0


def _assert_data(argv):
    days = float(_opt(argv, "--days", "7"))
    repo = _opt(argv, "--repo")
    cfg, data = census_data(days, [repo] if repo else [])
    cl = classes(cfg, data)
    want = _opt(argv, "--class")
    if want:
        cl = dict((k, v) for k, v in cl.items() if k == want)
    return cfg, data, cl


def cmd_assert(argv):
    """rc 0 clean · 1 breach · 3 non-verdict."""
    try:
        _cfg, _data, cl = _assert_data(argv)
    except Exception as e:
        print(
            "instruction-budget assert: NON-VERDICT — %s: %s" % (type(e).__name__, e),
            file=sys.stderr,
        )
        return 3
    if not cl:
        print(
            "instruction-budget assert: GREEN — no budget breach and no duplicate load"
        )
        return 0
    for k, v in sorted(cl.items()):
        print("BREACH [%s] %s" % (k, " | ".join(v["lines"])))
    return 1


TITLES = {
    "dedupe": "An instruction file loads twice per session (the migration-0042 shape: a global file "
    "loaded as Project on top of its user copy). Fix: docs/plans/INSTRUCTION_BUDGET.md D2 "
    "(W1 install.sh step + migration 0053).",
    "user": "The user-tier instructions (account CLAUDE.md + rules) exceed budget. Every session pays "
    "it. Fix: shrink CLAUDE.global.slim.md (move detail to CLAUDE.global.md or a skill).",
    "ancestor": "Instruction files ABOVE a repo root load into every session under them (ancestor "
    "budget 0). Fix: D2 for ~/.claude/*; move any other ancestor file into the repo it serves.",
    "repo": "This repo's always-loaded instructions exceed budget. Fix: move bodies and run history to "
    "non-loaded record files, keep one-line hooks (INSTRUCTION_BUDGET.md D5/D6).",
}


def cmd_file(argv):
    try:
        _cfg, _data, cl = _assert_data(argv)
    except Exception as e:
        print(
            "instruction-budget file: NON-VERDICT — %s: %s; nothing filed, nothing claimed clean"
            % (type(e).__name__, e),
            file=sys.stderr,
        )
        return 3
    if not cl:
        print("instruction-budget file: GREEN — nothing to file")
        return 0
    backlog = (os.environ.get("CC_BACKLOG_BIN") if testing() else None) or os.path.join(
        home(), ".claude", "bin", "cc-backlog"
    )
    me = os.environ.get("CC_IB_SELF") or os.path.join(
        home(), ".claude", "bin", "cc-instruction-budget"
    )
    if not os.access(backlog, os.X_OK):
        print(
            "instruction-budget file: cannot file — no cc-backlog at " + backlog,
            file=sys.stderr,
        )
        return 1
    for k, v in sorted(cl.items()):
        base = "repo" if k.startswith("repo-") else k
        fals = "%s assert --class %s%s" % (
            me,
            k,
            (" --repo " + v["repo"]) if v["repo"] else "",
        )
        title = (
            "%s Live: %s. Census: `cc-instruction-budget census`; this row closes itself when "
            "`%s` exits 0." % (TITLES[base], " | ".join(v["lines"])[:900], fals)
        )
        subprocess.run(
            [
                backlog,
                "add",
                "--project",
                v["owner"],
                "--source",
                "cc-instruction-budget",
                "--condition",
                "instruction-budget-" + k,
                "--falsifier",
                fals,
                "--title",
                title,
            ],
            capture_output=True,
            timeout=60,
        )
        print("instruction-budget file: filed/updated instruction-budget-" + k)
    return 1


def cmd_publish(argv):
    """Write the @import reachability set the hook's forkless pre-screen reads."""
    try:
        _cfg, data = census_data(float(_opt(argv, "--days", "7")))
        s = set()
        for e in data:
            for r in e["rows"]:
                if r["imported"]:
                    s.add(r["path"])
                    s.add(r["real"])
        d = os.path.join(home(), ".claude", "state", "instruction-budget")
        os.makedirs(d, exist_ok=True)
        fd, tmp = tempfile.mkstemp(dir=d)
        with os.fdopen(fd, "w") as fh:
            fh.write("".join(p + "\n" for p in sorted(s)))
        os.replace(tmp, os.path.join(d, "loaded-set.txt"))
        print("instruction-budget publish: %d import target(s)" % len(s))
        return 0
    except Exception as e:
        print("instruction-budget publish: failed — %s" % e, file=sys.stderr)
        return 3


def cmd_measure(argv):
    for p in argv:
        t = DiskFS().read(p)
        if t is None:
            print("%s\tabsent" % p)
            continue
        inf = parse(t, p, RULES_SEG in phys(p) or "/rules/" in p)
        print(
            "%s\t%d\t%s"
            % (p, inf.units, "conditional" if inf.conditional else "always")
        )
    return 0


def cmd_enforce(argv):
    print("true" if load_config().get("enforce") is True else "false")
    return 0


def cmd_selftest(argv):
    """RED and GREEN fixtures through judge() and range_findings(), enforce forced on in-process."""
    import shutil

    ok, bad = [], []
    t = tempfile.mkdtemp(prefix="ib-selftest.")
    try:
        cfg = dict(load_config(), enforce=True)
        repo = os.path.join(t, "repo")
        os.makedirs(os.path.join(repo, ".claude", "rules"))
        os.makedirs(os.path.join(repo, ".git"))
        big = os.path.join(repo, ".claude", "rules", "big.md")
        x = "x" * (int(cfg["per_file"]) + 100)
        with open(big, "w") as fh:
            fh.write(x)

        def check(name, cond):
            (ok if cond else bad).append(name)

        check(
            "growth of an over-budget file is refused",
            judge(big, x, x + "y", cfg, cfgdirs=[]),
        )
        check(
            "shrink of an over-budget file passes",
            not judge(big, x, x[:-1], cfg, cfgdirs=[]),
        )
        check(
            "a non-instruction path is never judged",
            not judge(os.path.join(repo, "src", "a.md"), "", x + x, cfg, cfgdirs=[]),
        )
        small = os.path.join(repo, ".claude", "rules", "s.md")
        check(
            "a new rule pushing the repo tier over is refused",
            any(
                f["kind"] == "tier"
                for f in judge(small, None, "z" * 30000, cfg, cfgdirs=[])
            ),
        )
        check(
            "a conditional rule over its own cap is refused",
            any(
                f["kind"] == "conditional"
                for f in judge(
                    big, x, "---\npaths:\n  - src/**\n---\n" + x + "y", cfg, cfgdirs=[]
                )
            ),
        )
        # range: a git repo whose second commit grows the rule
        g = os.path.join(t, "g")
        os.makedirs(os.path.join(g, ".claude", "rules"))
        env = dict(
            os.environ,
            GIT_AUTHOR_NAME="t",
            GIT_AUTHOR_EMAIL="t@t",
            GIT_COMMITTER_NAME="t",
            GIT_COMMITTER_EMAIL="t@t",
        )

        def run(*a):
            return subprocess.run(
                [
                    "git",
                    "-C",
                    g,
                    "-c",
                    "core.hooksPath=/dev/null",
                    "-c",
                    "core.excludesFile=/dev/null",
                    "-c",
                    "commit.gpgSign=false",
                ]
                + list(a),
                capture_output=True,
                env=env,
                check=True,
            )

        run("init", "-q")
        with open(os.path.join(g, ".claude", "rules", "r.md"), "w") as fh:
            fh.write(x)
        run("add", "-A")
        run("commit", "-qm", "base")
        with open(os.path.join(g, ".claude", "rules", "r.md"), "a") as fh:
            fh.write("more")
        run("commit", "-qam", "grow")
        check(
            "range refuses its own growth", bool(range_findings(g, "HEAD~1..HEAD", cfg))
        )
        with open(os.path.join(g, ".claude", "rules", "r.md"), "w") as fh:
            fh.write("small")
        run("commit", "-qam", "shrink")
        check("range passes a shrink", not range_findings(g, "HEAD~1..HEAD", cfg))
    except Exception as e:
        bad.append("selftest crashed: %s: %s" % (type(e).__name__, e))
    finally:
        shutil.rmtree(t, ignore_errors=True)
    for n in ok:
        print("ok   " + n)
    for n in bad:
        print("FAIL " + n)
    print("instruction-budget selftest: %d passed, %d failed" % (len(ok), len(bad)))
    return 0 if not bad else 1


COMMANDS = dict(
    verdict=cmd_verdict,
    range=cmd_range,
    census=cmd_census,
    assert_=cmd_assert,
    file=cmd_file,
    publish=cmd_publish,
    measure=cmd_measure,
    enforce=cmd_enforce,
    selftest=cmd_selftest,
)


def main(argv):
    if not argv or argv[0] in ("-h", "--help", "help"):
        print(
            "usage: cc-instruction-budget census [--days N] [--json] | assert [--class C] [--repo R] |"
            " file | publish | range <base>..<head> [--repo R] | verdict (stdin) | measure <file>… |"
            " enforce | selftest"
        )
        return 0
    name = argv[0].lstrip("-")
    fn = COMMANDS.get("assert_" if name == "assert" else name)
    if fn is None:
        print("cc-instruction-budget: unknown subcommand " + argv[0], file=sys.stderr)
        return 2
    return fn(argv[1:])


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
