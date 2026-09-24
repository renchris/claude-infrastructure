#!/usr/bin/env python3
"""Parse frontmatter of every user skill, legacy command and custom agent.

MEASURED inputs: ~/.claude/skills/*/SKILL.md, ~/.claude/commands/*.md, ~/.claude/agents/*.md.
Mirrors Claude Code 2.1.280's listing text: entry = "- <name>: <description>[ - <when_to_use>]",
description capped at skillListingMaxDescChars (default 1536). Writes JSON to stdout.

Why a skill can show no description in the listing (binary 2.1.280, fn JBt / Fmt):
  (a) frontmatter has no description AND no when_to_use -> the model-invocable skill list (Qle)
      requires hasUserSpecifiedDescription||whenToUse; entries without one may still be shown by
      name via another path, or with a derived description (first heading) in other sessions;
  (b) skillOverrides[name] == "name-only";
  (c) listing over budget -> priority mode: non-bundled skills sorted by usage score
      (usageCount * max(0.5**(days/7), 0.1)) and greedily given their full text while it fits;
      the rest are listed as "- <name>".
"""

import glob, json, os, re, sys
import yaml

HOME = os.path.expanduser("~")
MAXDESC = 1536


def fm(path):
    t = open(path, encoding="utf-8", errors="replace").read()
    m = re.match(r"^---\s*\n(.*?)\n---\s*\n", t, re.S)
    body = t[m.end() :] if m else t
    meta = {}
    err = None
    if m:
        try:
            meta = yaml.safe_load(m.group(1)) or {}
            if not isinstance(meta, dict):
                meta = {}
        except Exception as e:  # strict YAML fails on unquoted ": " inside a value;
            # Claude Code reads these files anyway (their descriptions appear in live
            # listings), so fall back to a line-based "key: rest-of-line" parse.
            err = f"{type(e).__name__}: {str(e)[:120]}"
            for line in m.group(1).splitlines():
                mm = re.match(r"^([A-Za-z_][\w-]*):\s?(.*)$", line)
                if mm:
                    v = mm.group(2).strip()
                    if len(v) >= 2 and v[0] == v[-1] and v[0] in "\"'":
                        v = v[1:-1]
                    meta[mm.group(1)] = (
                        True if v == "true" else (False if v == "false" else v)
                    )
    first_heading = next(
        (l.lstrip("# ").strip() for l in body.splitlines() if l.strip()), ""
    )
    return meta, err, bool(m), len(t), first_heading


rows = []
for kind, pat in [
    ("skill", HOME + "/.claude/skills/*/SKILL.md"),
    ("command", HOME + "/.claude/commands/*.md"),
    ("agent", HOME + "/.claude/agents/*.md"),
]:
    for p in sorted(glob.glob(pat)):
        meta, err, has_fm, size, h1 = fm(p)
        name = meta.get("name") or (
            os.path.basename(os.path.dirname(p))
            if kind == "skill"
            else os.path.basename(p)[:-3]
        )
        desc = meta.get("description")
        desc = "" if desc is None else str(desc)
        wtu = meta.get("when_to_use") or meta.get("when-to-use") or ""
        wtu = str(wtu)
        full = f"{desc} - {wtu}" if wtu else desc
        rows.append(
            dict(
                kind=kind,
                name=str(name),
                path=p,
                realpath=os.path.realpath(p),
                file_chars=size,
                has_frontmatter=has_fm,
                yaml_error=err,
                desc_chars=len(desc),
                when_to_use_chars=len(wtu),
                listing_desc_chars=len(full),
                listing_entry_chars=(len(str(name)) + 4 + min(len(full), MAXDESC))
                if full
                else len(str(name)) + 2,
                capped_at_1536=len(full) > MAXDESC,
                disable_model_invocation=bool(meta.get("disable-model-invocation")),
                user_invocable=meta.get("user-invocable"),
                model=meta.get("model"),
                omitClaudeMd=meta.get("omitClaudeMd"),
                first_heading=h1[:80],
                description=desc,
                when_to_use=wtu,
            )
        )
json.dump(rows, sys.stdout, indent=1)
