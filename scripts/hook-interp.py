#!/usr/bin/env python3
"""hook-interp.py — run every Claude Code hook and the status line through an explicit interpreter.

WHY. On macOS 15.7.9 every execve() of a `#!` script retains one 1 KiB element in data.kalloc.1024
that outlives the process (+0.94/exec measured on-box); `/bin/bash script` retains about 0. That zone
reached its ~20 GiB ceiling and panicked the kernel on 2026-10-18, and ~100 hook commands plus the
status line ran as bare `#!` paths. docs/research/panic-2026-10-18-zone-map-shebang-leak.md §1-2.

The rewrite is the kernel's own: for a command whose first word is a `#!` file, prefix the shebang's
interpreter, verbatim. `~/.claude/hooks/x.sh arg` becomes `/bin/bash ~/.claude/hooks/x.sh arg`, so
`~` and `$HOME` still expand in the shell Claude Code runs the command through, `$0` is the same
path, and `#!/usr/bin/env bash` keeps resolving bash on the hook's own PATH (env and bash are both
Mach-O, so neither leaks). Only `.hooks.<Event>[].hooks[]` and `.statusLine` are touched; mcpServers
also carry `command` keys and are not hooks.

An interpreter outside KNOWN is refused, never emitted: every reader that matches hook commands by
string strips a prefix only from this set (scripts/lib/hook-cmd-bare.jq, cmd_bare below), so an
unknown prefix would make those readers miss the hook and re-add it.

Usage:
  hook-interp.py rewrite <settings.json> [--root DIR] [--hermetic]   rewritten JSON on stdout,
                                                                     one "rewrote|kept" line per command on stderr
  hook-interp.py lint    <settings.json> [--root DIR] [--hermetic]   exit 1 on any bare `#!` command
  hook-interp.py list    <settings.json> [--root DIR] [--hermetic]   TSV: verdict, where, command
  hook-interp.py bare    <command>                                   the command with its prefix stripped
  hook-interp.py --selftest

--root DIR maps `~/.claude/<rel>` (and `$HOME/.claude/<rel>`, `<HOME>/.claude/<rel>`) onto DIR/<rel>
when the HOME copy is absent; --hermetic resolves ONLY through --root (the land gate's mode, so the
verdict never depends on the live layer). Exit: 0 clean · 1 findings or refusal · 2 usage/unreadable.
"""

import json
import os
import re
import shutil
import sys
import tempfile

KNOWN = (
    "/bin/bash",
    "/bin/sh",
    "/bin/zsh",
    "/usr/bin/env bash",
    "/usr/bin/env sh",
    "/usr/bin/env zsh",
    "/usr/bin/env python3",
    "/usr/bin/env python",
)
# Mirrors scripts/lib/hook-cmd-bare.jq byte-for-byte in meaning; tests/hook-interp.bats holds the two
# to one corpus. Strips only when a path follows, so `/bin/bash -c '…'` stays what it is.
BARE_RE = re.compile(
    r"^(/bin/(ba|z)?sh|/usr/bin/env +(ba|z)?sh|/usr/bin/env +python3?) +(?=[~$/])"
)
CLAUDE_PREFIXES = ("~/.claude/", "$HOME/.claude/", "${HOME}/.claude/")


def cmd_bare(cmd):
    return BARE_RE.sub("", cmd, count=1)


def first_word(cmd):
    s = cmd.lstrip()
    m = re.match(r"[^\s;&|<>()]+", s)
    return m.group(0) if m else ""


def candidates(word, roots, hermetic, home):
    out = []
    rel = None
    for p in CLAUDE_PREFIXES + (home.rstrip("/") + "/.claude/",):
        if word.startswith(p):
            rel = word[len(p) :]
            break
    if not hermetic:
        w = word
        if w.startswith("~/"):
            w = home + w[1:]
        w = w.replace("${HOME}", home).replace("$HOME", home)
        if "/" in w:
            out.append(w)
        else:
            found = shutil.which(w)
            if found:
                out.append(found)
    if hermetic and rel is None and word.startswith("/"):
        out.append(word)  # a system path (/bin/bash) is not the live layer
    if rel is not None:
        out.extend(os.path.join(r, rel) for r in roots)
    elif "/" not in word:
        out.extend(os.path.join(r, "bin", word) for r in roots)
    return out


def shebang(path):
    try:
        with open(path, "rb") as f:
            head = f.read(256)
    except OSError:
        return None
    if not head.startswith(b"#!"):
        return ""
    line = head.split(b"\n", 1)[0][2:].decode("utf-8", "replace").strip()
    return re.sub(r"\s+", " ", line)


def classify(cmd, roots, hermetic, home):
    """→ (verdict, interp). verdict ∈ explicit | bare | binary | unresolved | unknown-interp | mismatch."""
    stripped = cmd_bare(cmd)
    if stripped != cmd:
        prefix = cmd[: len(cmd) - len(stripped)].strip()
        prefix = re.sub(r"\s+", " ", prefix)
        word = first_word(stripped)
        for c in candidates(word, roots, hermetic, home):
            sb = shebang(c)
            if sb is None:
                continue
            if sb and sb != prefix:
                return "mismatch", sb
            return "explicit", prefix
        return "explicit", prefix
    word = first_word(cmd)
    if not word:
        return "binary", ""
    resolvable = "/" in word or any(word.startswith(p) for p in ("~", "$"))
    for c in candidates(word, roots, hermetic, home):
        sb = shebang(c)
        if sb is None:
            continue
        if sb == "":
            return "binary", ""
        if sb not in KNOWN:
            return "unknown-interp", sb
        return "bare", sb
    return ("unresolved", "") if resolvable else ("binary", "")


def hook_slots(doc):
    """Yield (where, container, key) for every hook command and the status line."""
    hooks = doc.get("hooks")
    if isinstance(hooks, dict):
        for ev, groups in hooks.items():
            if not isinstance(groups, list):
                continue
            for gi, g in enumerate(groups):
                if not isinstance(g, dict) or not isinstance(g.get("hooks"), list):
                    continue
                for hi, h in enumerate(g["hooks"]):
                    if (
                        isinstance(h, dict)
                        and isinstance(h.get("command"), str)
                        and h.get("type", "command") == "command"
                    ):
                        yield "hooks.%s[%d].hooks[%d]" % (ev, gi, hi), h, "command"
    sl = doc.get("statusLine")
    if (
        isinstance(sl, dict)
        and isinstance(sl.get("command"), str)
        and sl.get("type", "command") == "command"
    ):
        yield "statusLine", sl, "command"


def load(path):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError) as e:
        print("hook-interp: cannot read %s: %s" % (path, e), file=sys.stderr)
        sys.exit(2)


def run(mode, path, roots, hermetic):
    home = os.environ.get("HOME", os.path.expanduser("~"))
    doc = load(path)
    findings = 0
    rows = []
    for where, obj, key in hook_slots(doc):
        cmd = obj[key]
        verdict, interp = classify(cmd, roots, hermetic, home)
        rows.append((verdict, where, cmd))
        if mode == "rewrite":
            if verdict == "bare":
                obj[key] = "%s %s" % (interp, cmd.lstrip())
                print("rewrote\t%s\t%s" % (where, obj[key]), file=sys.stderr)
            elif verdict == "unresolved":
                # A command naming a script that is not on disk cannot be classified, so it is left
                # exactly as it is; lint still reports it.
                print("kept\tunresolved\t%s\t%s" % (where, cmd), file=sys.stderr)
            elif verdict in ("unknown-interp", "mismatch"):
                findings += 1
                print("refused\t%s\t%s\t%s" % (verdict, where, cmd), file=sys.stderr)
        elif verdict in ("bare", "unresolved", "unknown-interp", "mismatch"):
            findings += 1
    if mode == "rewrite":
        if findings:
            print(
                "hook-interp: verdict=refused n=%d — nothing written" % findings,
                file=sys.stderr,
            )
            return 1
        json.dump(doc, sys.stdout, indent=2, ensure_ascii=False)
        sys.stdout.write("\n")
        return 0
    if mode == "list":
        for r in rows:
            print("\t".join(r))
        return 0
    for verdict, where, cmd in rows:
        if verdict in ("bare", "unresolved", "unknown-interp", "mismatch"):
            hint = {
                "bare": "run it as `<shebang-interpreter> <path>`, e.g. /bin/bash ~/.claude/hooks/x.sh",
                "unresolved": "the script it names does not exist",
                "unknown-interp": "its shebang is outside the set cmd_bare strips; use one of: "
                + ", ".join(KNOWN),
                "mismatch": "the prefix does not match the script's own shebang",
            }[verdict]
            print("%s: %s %s — %s" % (path, where, json.dumps(cmd), hint))
    print(
        "hook-interp lint: verdict=%s n=%d checked=%d"
        % ("RED" if findings else "clean", findings, len(rows))
    )
    return 1 if findings else 0


def selftest():
    d = tempfile.mkdtemp(prefix="hook-interp-st.")
    try:
        os.makedirs(os.path.join(d, "hooks"))
        os.makedirs(os.path.join(d, "bin"))
        for name, body in (
            ("hooks/b.sh", "#!/bin/bash\n"),
            ("hooks/e.sh", "#!/usr/bin/env bash\n"),
            ("hooks/p.py", "#!/usr/bin/env python3\n"),
            ("hooks/k.sh", "#!/usr/local/bin/fish\n"),
            ("bin/tool", "#!/bin/bash\n"),
        ):
            with open(os.path.join(d, name), "w") as f:
                f.write(body)
        home = "/nonexistent-home"
        cases = [
            ("~/.claude/hooks/b.sh arg", "bare", "/bin/bash"),
            ("$HOME/.claude/hooks/e.sh", "bare", "/usr/bin/env bash"),
            ("~/.claude/hooks/p.py", "bare", "/usr/bin/env python3"),
            ("/bin/bash ~/.claude/hooks/b.sh", "explicit", "/bin/bash"),
            ("/bin/bash ~/.claude/hooks/p.py", "mismatch", "/usr/bin/env python3"),
            ("~/.claude/hooks/k.sh", "unknown-interp", "/usr/local/bin/fish"),
            ("~/.claude/hooks/gone.sh", "unresolved", ""),
            ("tool --x", "bare", "/bin/bash"),
            ("date '+%s' >> ~/.claude/logs/x.log", "binary", ""),
            ("/bin/bash -c 'echo hi'", "binary", ""),
        ]
        bad = 0
        for cmd, want_v, want_i in cases:
            got = classify(cmd, [d], True, home)
            if got != (want_v, want_i):
                bad += 1
                print(
                    "selftest FAIL: %r → %r, want %r" % (cmd, got, (want_v, want_i)),
                    file=sys.stderr,
                )
        for cmd, want in (
            ("/bin/bash ~/.claude/hooks/b.sh a", "~/.claude/hooks/b.sh a"),
            ("/usr/bin/env python3 $HOME/x.py", "$HOME/x.py"),
            ("/bin/bash -c foo", "/bin/bash -c foo"),
            ("~/.claude/x.sh", "~/.claude/x.sh"),
        ):
            if cmd_bare(cmd) != want:
                bad += 1
                print(
                    "selftest FAIL: cmd_bare(%r) = %r" % (cmd, cmd_bare(cmd)),
                    file=sys.stderr,
                )
        print(
            "hook-interp selftest: %s (%d cases)"
            % ("FAIL" if bad else "ok", len(cases) + 4)
        )
        return 1 if bad else 0
    finally:
        shutil.rmtree(d, ignore_errors=True)


def main(argv):
    if argv[:1] == ["--selftest"]:
        return selftest()
    if len(argv) >= 2 and argv[0] == "bare":
        print(cmd_bare(argv[1]))
        return 0
    if len(argv) < 2 or argv[0] not in ("rewrite", "lint", "list"):
        print(
            __doc__.split("Usage:", 1)[1].split("--root DIR maps", 1)[0],
            file=sys.stderr,
        )
        return 2
    mode, path, rest = argv[0], argv[1], argv[2:]
    roots, hermetic = [], False
    i = 0
    while i < len(rest):
        if rest[i] == "--root" and i + 1 < len(rest):
            roots.append(os.path.abspath(rest[i + 1]))
            i += 2
        elif rest[i] == "--hermetic":
            hermetic = True
            i += 1
        else:
            print("hook-interp: unknown argument %s" % rest[i], file=sys.stderr)
            return 2
    if hermetic and not roots:
        print("hook-interp: --hermetic needs --root", file=sys.stderr)
        return 2
    return run(mode, path, roots, hermetic)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
