#!/usr/bin/env python3
"""Fleet instruction-load census: emulates Claude Code 2.1.284's always-loaded memory walk
(CRn / mY / $De / cet in the bundled cli, see /tmp/cc284.strings) for every cwd the fleet used.

Re-run:  python3 /tmp/ibudget/collect_cwds.py 14 && python3 /tmp/ibudget/census.py
Inputs:  /tmp/ibudget/cwds.json (from collect_cwds.py)
Outputs: /tmp/ibudget/census.json, /tmp/ibudget/census-table.md

Loader facts emulated (read from the 2.1.284 bundle):
  * User memory: $CLAUDE_CONFIG_DIR/CLAUDE.md + $CLAUDE_CONFIG_DIR/rules/**/*.md (unconditional only).
  * Project walk: every dir from the one under '/' down to cwd (root excluded); per dir:
    CLAUDE.md, .claude/CLAUDE.md, .claude/rules/**/*.md (unconditional only), CLAUDE.local.md.
  * Dedup: by path and by symlink-resolved path (processedPaths set).
  * Rule is conditional iff frontmatter `paths:` is non-empty and not all '**'.
  * Content counted = body after YAML frontmatter, with HTML-comment blocks stripped; JS .length (UTF-16 units).
  * @-imports: regex (?:^|\\s)@((?:[^\\s\\\\]|\\\\ )+) outside code; depth < 5; text extensions only;
    Project/Local imports outside cwd need hasClaudeMdExternalIncludesApproved (we count them, flagged).
  * Limits: per-file = max(40000, window*0.05*3); total = max(120000, per-file).
    1M window -> 150k/150k; 200k window -> 40k/120k.  Warning total check sums only files <= per-file limit.
"""

import os, re, json, glob, subprocess, collections, sys

H = os.path.expanduser("~")
GLOBAL_FULL = f"{H}/.claude/CLAUDE.md"
GLOBAL_RULES = f"{H}/.claude/rules"
LEDGER_NAME = ".claude/rules/bottle-generation-ledger.md"
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

_cache = {}


def jslen(s):
    return len(s) + sum(1 for ch in s if ord(ch) > 0xFFFF)


def split_frontmatter(raw):
    m = re.match(r"^---\s*\n(.*?)\n---\s*(?:\n|$)", raw, re.S)
    if not m:
        return {}, raw
    fm_text, body = m.group(1), raw[m.end() :]
    fm = {}
    # minimal YAML: capture `paths:` scalar or list
    pm = re.search(r"^paths\s*:\s*(.*)$", fm_text, re.M)
    if pm:
        val = pm.group(1).strip()
        items = []
        if val and val not in ("|", ">"):
            val = val.strip("[]")
            items = [v.strip().strip("\"'") for v in val.split(",") if v.strip()]
        else:
            after = fm_text[pm.end() :].splitlines()
            for l in after:
                lm = re.match(r"^\s*-\s*(.+)$", l)
                if lm:
                    items.append(lm.group(1).strip().strip("\"'"))
                elif l.strip() == "":
                    continue
                else:
                    break
        fm["paths"] = items
    return fm, body


def strip_html_comment_blocks(body):
    # marked lexes an HTML block only when '<!--' starts a line (<=3 spaces indent)
    return re.sub(
        r"(?m)^[ ]{0,3}<!--[\s\S]*?-->[^\n]*",
        lambda m: re.sub(r"<!--[\s\S]*?-->", "", m.group(0)),
        body,
    )


def strip_code(body):
    body = re.sub(r"(?ms)^[ ]{0,3}(```|~~~).*?^[ ]{0,3}\1[^\n]*$", "", body)
    return re.sub(r"`[^`\n]*`", "", body)


def read_mem(path):
    """Return dict(path, real, chars, conditional, imports) or None."""
    if path in _cache:
        return _cache[path]
    res = None
    try:
        if os.path.isfile(path) and os.path.getsize(path) <= 4194304:
            raw = open(path, encoding="utf-8", errors="replace").read()
            fm, body = split_frontmatter(raw)
            paths = fm.get("paths") or []
            conditional = bool(paths) and not all(p in ("**", "**/*") for p in paths)
            content = strip_html_comment_blocks(body) if "<!--" in body else body
            imports = []
            if "@" in content:
                for m in re.finditer(
                    r"(?:^|\s)@((?:[^\s\\]|\\ )+)", strip_code(content)
                ):
                    d = m.group(1).split("#")[0].replace("\\ ", " ")
                    if not d or d == "/":
                        continue
                    if not (
                        d.startswith("./")
                        or d.startswith("~/")
                        or d.startswith("/")
                        or (not d.startswith("@") and re.match(r"^[a-zA-Z0-9._-]", d))
                    ):
                        continue
                    tgt = (
                        os.path.expanduser(d)
                        if d.startswith("~/")
                        else os.path.normpath(os.path.join(os.path.dirname(path), d))
                    )
                    ext = os.path.splitext(tgt)[1].lower()
                    if os.path.isfile(tgt) and (ext == "" or ext in TEXT_EXT):
                        imports.append(tgt)
            res = dict(
                path=path,
                real=os.path.realpath(path),
                chars=jslen(content),
                conditional=conditional,
                imports=imports,
                empty=not content.strip(),
            )
    except OSError:
        res = None
    _cache[path] = res
    return res


def rules_files(rdir, seen_dirs=None):
    seen_dirs = seen_dirs or set()
    out = []
    try:
        rp = os.path.realpath(rdir)
        if rp in seen_dirs or not os.path.isdir(rdir):
            return out
        seen_dirs.add(rp)
        for e in sorted(os.listdir(rdir)):
            p = os.path.join(rdir, e)
            if os.path.isdir(p):
                out += rules_files(p, seen_dirs)
            elif e.endswith(".md") and os.path.isfile(p):
                out.append(p)
    except OSError:
        pass
    return out


def _glob_rx(g):
    out, i = "", 0
    while i < len(g):
        if g.startswith("**/", i):
            out += "(?:.*/)?"; i += 3
        elif g.startswith("**", i):
            out += ".*"; i += 2
        elif g[i] == "*":
            out += "[^/]*"; i += 1
        elif g[i] == "?":
            out += "[^/]"; i += 1
        else:
            out += re.escape(g[i]); i += 1
    return re.compile("^" + out + "$")


def _settings_excludes():
    pats = []
    for f in [f"{H}/.claude/settings.json", f"{H}/.claude/settings.local.json"]:
        try:
            pats += json.load(open(f)).get("claudeMdExcludes", []) or []
        except Exception:
            pass
    return pats


EXCLUDE_PATTERNS = _settings_excludes()
EXCLUDE_RX = [_glob_rx(os.path.expanduser(p)) for p in EXCLUDE_PATTERNS]
TYPEBLIND = False  # True = scenario B implemented via claudeMdExcludes, which also hits User type


def load(cwd, config_dir, scenario="A"):
    """Emulate the always-loaded set. Returns list of (path, type, chars)."""
    files, seen = [], set()

    def excluded(path, typ):
        # existing settings.json claudeMdExcludes (type-blind among User/Project/Local)
        if any(rx.match(path) or rx.match(os.path.realpath(path)) for rx in EXCLUDE_RX):
            return True
        if scenario in ("B", "C") and (typ == "Project" or TYPEBLIND):
            if path == GLOBAL_FULL or path.startswith(GLOBAL_RULES + "/"):
                return True
        return False

    def add(path, typ, depth=0):
        if depth >= 5 or excluded(path, typ):
            return
        info = read_mem(path)
        if not info or path in seen or info["real"] in seen:
            return
        seen.add(path)
        seen.add(info["real"])
        if info["empty"]:
            return
        chars = info["chars"]
        if scenario == "C" and path.endswith(LEDGER_NAME):
            chars = 6000
        files.append((path, typ, chars, depth > 0))
        for imp in info["imports"]:
            add(imp, typ, depth + 1)

    def add_rules(rdir, typ):
        for p in rules_files(rdir):
            info = read_mem(p)
            if info and not info["conditional"]:
                add(p, typ)

    add(os.path.join(config_dir, "CLAUDE.md"), "User")
    add_rules(os.path.join(config_dir, "rules"), "User")
    chain, d = [], cwd
    while d != "/" and d:
        chain.insert(0, d)
        d = os.path.dirname(d)
    for d in chain:
        add(os.path.join(d, "CLAUDE.md"), "Project")
        add(os.path.join(d, ".claude", "CLAUDE.md"), "Project")
        add_rules(os.path.join(d, ".claude", "rules"), "Project")
        add(os.path.join(d, "CLAUDE.local.md"), "Local")
    return files


def warn(files, per, tot):
    big = [f for f in files if f[2] > per]
    small_sum = sum(f[2] for f in files if f[2] <= per)
    return bool(big), small_sum > tot


# ---------- repo attribution ----------
_git = {}


def repo_of(cwd):
    if cwd in _git:
        return _git[cwd]
    r = None
    if os.path.isdir(cwd):
        try:
            cd = subprocess.run(
                [
                    "git",
                    "-C",
                    cwd,
                    "rev-parse",
                    "--path-format=absolute",
                    "--git-common-dir",
                    "--show-toplevel",
                ],
                capture_output=True,
                text=True,
                timeout=20,
            ).stdout.strip()
            lines = cd.splitlines()
            if lines:
                common = lines[0]
                r = os.path.dirname(common) if common.endswith("/.git") else common
                top = lines[1] if len(lines) > 1 else ""
                # sibling checkouts directly under ~/Development (e.g. reso-qa-runner) get their own row
                if os.path.dirname(top) == f"{H}/Development":
                    r = top
        except Exception:
            pass
    _git[cwd] = r
    return r


def guess_deleted_worktree_repo(cwd):
    enc = re.sub(r"[^A-Za-z0-9]", "-", cwd)
    c = collections.Counter()
    for f in glob.glob(f"{H}/.claude*/projects/{enc}/*.jsonl")[:3]:
        try:
            s = open(f, errors="ignore").read(3_000_000)
        except OSError:
            continue
        c.update(
            x
            for x in re.findall(r"/Users/chrisren/Development/([A-Za-z0-9_.-]+)", s)
            if x != ".worktrees"
        )
    for name, _ in c.most_common():
        p = f"{H}/Development/{name}"
        if os.path.isdir(os.path.join(p, ".git")):
            return p
    return None


def bucket(cwd):
    """-> (repo_label, emulate_cwd, note)"""
    if cwd.startswith("UNDECODED:"):
        return ("(undecoded project dir)", None, "no cwd in transcript")
    if (cwd.startswith("/private/tmp") or cwd.startswith("/tmp")
            or cwd.startswith("/private/var/folders")):
        return ("(tmp / eval-harness dirs, outside $HOME)", cwd, "existing ancestors only")
    if cwd.startswith(f"{H}/.claude/"):
        return ("~/.claude/** (autonomy evals, fixtures)", cwd, "")
    r = repo_of(cwd)
    if r:
        return (r.replace(H, "~"), cwd, "live path")
    if cwd.startswith(f"{H}/Development/.worktrees/"):
        g = guess_deleted_worktree_repo(cwd)
        if g:
            return (
                g.replace(H, "~"),
                g,
                "deleted worktree; emulated at main checkout (transcript path-mention heuristic)",
            )
        return ("(deleted worktree, repo unknown)", cwd, "ancestors only")
    if (
        cwd.startswith("/private/tmp")
        or cwd.startswith("/tmp")
        or cwd.startswith("/private/var/folders")
    ):
        return (
            "(tmp / eval-harness dirs, outside $HOME)",
            cwd,
            "existing ancestors only",
        )
    if cwd.startswith(f"{H}/.claude/"):
        return ("~/.claude/** (non-git: autonomy etc.)", cwd, "")
    if os.path.isdir(cwd):
        return (
            (cwd if cwd.count("/") <= 5 else "/".join(cwd.split("/")[:6])).replace(
                H, "~"
            )
            + " (non-git)",
            cwd,
            "",
        )
    return ("(other gone dirs under $HOME)", cwd, "existing ancestors only")


def main():
    cwds = json.load(open("/tmp/ibudget/cwds.json"))
    SLIM_CFG = (
        f"{H}/.claude-quaternary"  # all 4 account dirs -> CLAUDE.slim.md + rules.slim
    )
    DEFAULT_CFG = f"{H}/.claude"  # sessions with CLAUDE_CONFIG_DIR unset/= ~/.claude
    groups = collections.defaultdict(
        lambda: dict(sessions=0, cwds=[], live=0, notes=set())
    )
    for cwd, v in cwds.items():
        label, emu, note = bucket(cwd)
        g = groups[label]
        g["sessions"] += v["sessions"]
        g["live"] += "LIVE" in v["accounts"]
        if note:
            g["notes"].add(note)
        if emu:
            g["cwds"].append(emu)
    rows = []
    for label, g in groups.items():
        if not g["cwds"]:
            rows.append(
                dict(
                    repo=label,
                    sessions=g["sessions"],
                    live=g["live"],
                    n_cwds=0,
                    notes=sorted(g["notes"]),
                )
            )
            continue
        # representative = the cwd with the maximum scenario-A load (subdir cwds may pick up nested CLAUDE.md)
        per = {}
        for c in set(g["cwds"]):
            per[c] = load(c, SLIM_CFG, "A")
        rep = max(per, key=lambda c: (sum(f[2] for f in per[c]), c))
        res = dict(
            repo=label,
            sessions=g["sessions"],
            live=g["live"],
            n_cwds=len(set(g["cwds"])),
            rep_cwd=rep,
            notes=sorted(g["notes"]),
        )
        for sc in "ABC":
            fl = load(rep, SLIM_CFG, sc)
            tot = sum(f[2] for f in fl)
            w1m = warn(fl, 150000, 150000)
            w200 = warn(fl, 40000, 120000)
            res[sc] = dict(
                total=tot,
                n=len(fl),
                over40k=[(p.replace(H, "~"), c) for p, t, c, _ in fl if c > 40000],
                top3=[
                    (p.replace(H, "~"), t, c)
                    for p, t, c, _ in sorted(fl, key=lambda f: -f[2])[:3]
                ],
                files=[(p.replace(H, "~"), t, c, imp) for p, t, c, imp in fl],
                warn_1m=dict(file_over=w1m[0], total_over=w1m[1]),
                warn_200k=dict(file_over=w200[0], total_over=w200[1]),
            )
        fd = load(rep, DEFAULT_CFG, "A")
        res["A_default_cfg_total"] = sum(f[2] for f in fd)
        global TYPEBLIND
        TYPEBLIND = True
        fdb = load(rep, DEFAULT_CFG, "B")
        TYPEBLIND = False
        res["B_default_cfg_total_if_exclude_glob_is_typeblind"] = sum(
            f[2]
            for f in fdb
            if f[0] != GLOBAL_FULL and not f[0].startswith(GLOBAL_RULES + "/")
        )
        rows.append(res)
    rows.sort(key=lambda r: -(r.get("A", {}).get("total", 0)))
    json.dump(rows, open("/tmp/ibudget/census.json", "w"), indent=1)
    L = [
        "| repo | sessions 14d | live cwds | A total | B total | C total | files>40k (A) | top 3 (A) | top 2 (C) | C >150k | C >120k | C files>40k |",
        "|---|---|---|---|---|---|---|---|---|---|---|---|",
    ]
    k = lambda n: f"{n / 1000:.1f}k"
    for r in rows:
        if "A" not in r:
            L.append(
                f"| {r['repo']} | {r['sessions']} | {r['live']} | n/a | | | | | | | |"
            )
            continue
        top = "; ".join(
            f"{os.path.basename(p) if not p.startswith('~/.claude') else p} {k(c)}"
            for p, t, c in r["A"]["top3"]
        )
        o40 = "; ".join(f"{p.split('/')[-1]} {k(c)}" for p, c in r["A"]["over40k"])
        C = r["C"]["total"]
        topc = "; ".join(f"{p.replace('~/Development/', '')} {k(c)}" for p, t, c in r["C"]["top3"][:2])
        o40c = "; ".join(f"{p.split('/')[-1]} {k(c)}" for p, c in r["C"]["over40k"]) or "-"
        L.append(
            f"| {r['repo']} | {r['sessions']} | {r['live']} | {k(r['A']['total'])} | {k(r['B']['total'])} | {k(C)} | {o40} | {top} | {topc} | {'YES' if C > 150000 else 'no'} | {'YES' if C > 120000 else 'no'} | {o40c} |"
        )
    open("/tmp/ibudget/census-table.md", "w").write("\n".join(L) + "\n")
    print("\n".join(L))


if __name__ == "__main__":
    main()
