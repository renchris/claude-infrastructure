#!/usr/bin/env python3
"""Prototype loader emulator for the guard-design report (read-only; writes nothing).

Emulates CC 2.1.284 instruction-file loading for (config_dir, cwd), per the binary carve in
/tmp/cc284.strings: VLn (per-ancestor CLAUDE.md, .claude/CLAUDE.md, CLAUDE.local.md,
.claude/rules/** unconditional), User = $CFG/CLAUDE.md + $CFG/rules/**, lRn (paths: frontmatter
-> conditional unless empty / all '**'), vbe (block HTML comments stripped), @imports depth<5,
claudeMdExcludes (picomatch, approximated with fnmatch-on-**), dedupe by realpath.
Usage: guard-design-proto.py <config_dir> <cwd> [window_tokens]
"""

import fnmatch, json, os, re, sys

FM = re.compile(r"^---\s*\n([\s\S]*?)---\s*\n?")
CMT = re.compile(r"(?m)^<!--[\s\S]*?-->[ \t]*\n?")
IMP = re.compile(r"(?:^|\s)@((?:[^\s\\]|\\ )+)")
TEXT_EXT = {".md", ".txt", ""}


def parse(raw):
    m = FM.match(raw)
    body, globs = raw, None
    if m:
        body = raw[m.end() :]
        fm = m.group(1)
        pm = re.search(r"(?m)^paths\s*:\s*(.*)$", fm)
        if pm:
            v = pm.group(1).strip()
            items = []
            if v:
                items = [x.strip().strip("\"'") for x in v.strip("[]").split(",")]
            else:  # block list
                after = fm[pm.end() :]
                for ln in after.splitlines():
                    mm = re.match(r"\s*-\s*(.+)", ln)
                    if mm:
                        items.append(mm.group(1).strip().strip("\"'"))
                    elif ln.strip():
                        break
            items = [g[:-3] if g.endswith("/**") else g for g in items]
            items = [g for g in items if g]
            if items and not all(g == "**" for g in items):
                globs = items
    if "```" not in body:
        body = CMT.sub("", body)
    return body, globs


def units(s):
    return sum(2 if ord(c) > 0xFFFF else 1 for c in s)


def excluded(path, pats):
    for p in pats:
        if fnmatch.fnmatch(path, p) or fnmatch.fnmatch(path, p.replace("**/", "*/")):
            return True
    return False


def main():
    cfg, cwd = os.path.abspath(sys.argv[1]), os.path.abspath(sys.argv[2])
    window = int(sys.argv[3]) if len(sys.argv) > 3 else 1_000_000
    per_file = max(40000, round(window * 0.05 * 3))
    total_lim = max(120000, per_file)
    try:
        settings = json.load(open(os.path.join(cfg, "settings.json")))
    except Exception:
        settings = {}
    pats = settings.get("claudeMdExcludes") or []
    seen, out = set(), []

    def load(path, typ, depth=0, conditional_ok=False):
        if depth >= 5 or not os.path.isfile(path):
            return
        real = os.path.realpath(path)
        if real in seen or path in seen:
            return
        if typ in ("User", "Project", "Local") and excluded(path, pats):
            return
        seen.add(real)
        seen.add(path)
        try:
            raw = open(path, encoding="utf-8", errors="replace").read()
        except Exception:
            return
        body, globs = parse(raw)
        if globs and not conditional_ok:
            return
        if not body.strip():
            return
        out.append((path, typ, units(body)))
        txt = re.sub(r"```[\s\S]*?```", "", body)
        txt = re.sub(r"`[^`\n]*`", "", txt)
        for m in IMP.finditer(txt):
            d = m.group(1).split("#")[0].replace("\\ ", " ")
            if not d or not (
                d.startswith(("./", "~/", "/")) or re.match(r"^[a-zA-Z0-9._-]", d)
            ):
                continue
            tgt = (
                os.path.expanduser(d)
                if d.startswith("~/")
                else os.path.join(os.path.dirname(path), d)
            )
            if os.path.splitext(tgt)[1].lower() in TEXT_EXT and os.path.isfile(tgt):
                load(tgt, typ, depth + 1)

    def rules(dirp, typ):
        if not os.path.isdir(dirp):
            return
        for root, dirs, files in os.walk(dirp, followlinks=True):
            dirs.sort()
            for f in sorted(files):
                if f.endswith(".md"):
                    load(os.path.join(root, f), typ)

    load("/Library/Application Support/ClaudeCode/CLAUDE.md", "Managed")
    load(os.path.join(cfg, "CLAUDE.md"), "User")
    rules(os.path.join(cfg, "rules"), "User")
    parts = cwd.strip("/").split("/")
    dirs = ["/"] + ["/" + "/".join(parts[:i]) for i in range(1, len(parts) + 1)]
    for d in dirs:
        load(os.path.join(d, "CLAUDE.md"), "Project")
        load(os.path.join(d, ".claude", "CLAUDE.md"), "Project")
        load(os.path.join(d, "CLAUDE.local.md"), "Local")
        rules(os.path.join(d, ".claude", "rules"), "Project")
    tot = sum(u for _, _, u in out)
    tot_trig = sum(u for _, _, u in out if u <= per_file)
    for p, t, u in out:
        flag = " OVER-PER-FILE" if u > per_file else ""
        print(f"{u:>8}  {t:<8} {p}{flag}")
    print(
        f"files={len(out)} total={tot} total_counted_for_trigger={tot_trig} per_file_limit={per_file} total_limit={total_lim}"
        f" total_warning={'YES' if tot_trig > total_lim else 'no'}"
        f" per_file_warnings={sum(1 for _, _, u in out if u > per_file)}"
    )


if __name__ == "__main__":
    main()
