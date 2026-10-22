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
  hook-interp.py lint-plist <job.plist>... --root DIR                 exit 1 on a launchd job that execs a
                                                                     tracked `#!` script by path
  hook-interp.py lint-args --root DIR < args                         the same, for one job's arguments,
                                                                     one per stdin line
  hook-interp.py --selftest

--root DIR maps `~/.claude/<rel>` (and `$HOME/.claude/<rel>`, `<HOME>/.claude/<rel>`) onto DIR/<rel>
when the HOME copy is absent; --hermetic resolves ONLY through --root (the land gate's mode, so the
verdict never depends on the live layer). Exit: 0 clean · 1 findings or refusal · 2 usage/unreadable.
"""

import html
import json
import os
import plistlib
import re
import shlex
import shutil
import sys
import tempfile
from xml.parsers.expat import ExpatError

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


# ── launchd jobs ──────────────────────────────────────────────────────────────────────────────────
# A launchd job leaks the same element every time it execs a `#!` main by path, at its StartInterval
# (docs/research/kalloc-longterm-2026-10-21/REPORT.md §3 Phase 1, "Launchd jobs"). Two shapes reach a
# script: ProgramArguments[0] is the script itself, or a shell's `-c` string runs it as a command
# word. Only paths that map into THIS checkout are judged (~/.claude/<rel>, the checkout's own
# ~/Development/claude-infrastructure/<rel>, or a bare name on ~/.claude/bin): another repo's script
# is not this tree's to classify, and a system binary is Mach-O.
PLIST_REPO_RE = re.compile(
    r"^(?:~|\$HOME|\$\{HOME\}|/Users/[^/]+)/(?:\.claude|Development/claude-infrastructure)/"
)
SHELLS = ("bash", "sh", "zsh")
# Words that run their operand rather than being the program: the operand is the command word. Each
# maps to the flags of its own that take a value, so `taskpolicy -c utility x.sh` judges x.sh.
WRAPPERS = {
    "exec": ("-a",),
    "nohup": (),
    "command": (),
    "env": ("-u", "-P", "-S"),
    "taskpolicy": ("-c", "-d", "-g", "-t", "-l", "-p"),
    "nice": ("-n",),
    "timeout": ("-k", "-s"),
    "gtimeout": ("-k", "-s"),
    "perl": (
        "-e",
        "-E",
    ),  # the `alarm shift; exec @ARGV` relay: perl -e CODE SECS prog args
}
CMD_START = (";", "&&", "||", "|", "&", "(", ")", "{", "}", ";;", "|&", "\n")
KEYWORDS = ("if", "then", "else", "elif", "do", "while", "until", "!")
ASSIGN_RE = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*)=(.*)$", re.S)
OPERAND_RE = re.compile(r"^\d+(\.\d+)?[smhd]?$")


def plist_target(word, roots):
    """The in-checkout file a plist word names, or None when it is not this tree's to judge."""
    m = PLIST_REPO_RE.match(word)
    if m:
        rel = word[m.end() :]
    elif word and "/" not in word and not word.startswith("$"):
        rel = "bin/" + word  # a bare name: every job puts ~/.claude/bin first on PATH
    else:
        return None
    for r in roots:
        p = os.path.join(r, rel)
        if os.path.isfile(p):
            return p
    return None


def shell_words(s):
    lex = shlex.shlex(s, posix=True, punctuation_chars=";&|()<>")
    lex.whitespace_split = True
    lex.commenters = ""
    try:
        return list(lex)
    except ValueError:
        return (
            s.split()
        )  # an unbalanced quote: judge the words anyway rather than go blind


def command_words(s):
    """Each simple command's program word in a `-c` string, past assignments and wrappers.
    A `NAME=value` seen earlier in the string is substituted into a `$NAME` command word, so
    `D=…/x.sh; exec "$D"` is judged as x.sh."""
    words = shell_words(s)
    env = {}
    out = []
    i, start = 0, True
    while i < len(words):
        w = words[i]
        if w in CMD_START:
            start = True
            i += 1
            continue
        if not start:
            i += 1
            continue
        if w in KEYWORDS:
            i += 1
            continue
        m = ASSIGN_RE.match(w)
        if m:
            env[m.group(1)] = m.group(2)
            i += 1
            continue
        base = os.path.basename(w)
        if base in WRAPPERS:
            valued = WRAPPERS[base]
            i += 1
            while i < len(words):
                a = words[i]
                if a in valued:
                    i += 2
                elif a.startswith("-") or OPERAND_RE.match(a) or ASSIGN_RE.match(a):
                    i += 1
                else:
                    break
            continue
        v = re.match(r"^\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?$", w)
        out.append(env.get(v.group(1), w) if v else w)
        start = False
        i += 1
    return out


def plist_args(path):
    """ProgramArguments (or [Program]) of a job, read by plistlib, else out of the raw XML."""
    try:
        with open(path, "rb") as f:
            doc = plistlib.load(f)
        if isinstance(doc.get("ProgramArguments"), list):
            return [str(a) for a in doc["ProgramArguments"]]
        if isinstance(doc.get("Program"), str):
            return [doc["Program"]]
        return []
    except (OSError, ValueError, ExpatError):
        pass  # a template plistlib cannot parse; the raw-XML read below still sees its arguments
    try:
        with open(path, encoding="utf-8") as f:
            text = re.sub(r"<!--.*?-->", "", f.read(), flags=re.S)
    except OSError:
        return None
    m = re.search(r"<key>ProgramArguments</key>\s*<array>(.*?)</array>", text, re.S)
    if m:
        return [
            html.unescape(a)
            for a in re.findall(r"<string>(.*?)</string>", m.group(1), re.S)
        ]
    m = re.search(r"<key>Program</key>\s*<string>(.*?)</string>", text, re.S)
    return [html.unescape(m.group(1))] if m else []


def plist_findings(args, roots):
    """→ [(where, word, interpreter)] for every in-checkout `#!` script the job execs by path."""
    found = []

    def judge(where, word):
        t = plist_target(word, roots)
        sb = shebang(t) if t else None
        if sb:
            found.append((where, word, sb))

    if not args:
        return found
    judge("ProgramArguments[0]", args[0])
    if os.path.basename(args[0]) in SHELLS:
        for i in range(1, len(args) - 1):
            if re.match(r"^-[a-z]*c[a-z]*$", args[i]):
                for w in command_words(args[i + 1]):
                    judge("ProgramArguments[%d] -c" % (i + 1), w)
                break
    return found


def lint_plists(paths, roots):
    findings, rc = 0, 0
    for path in paths:
        args = plist_args(path)
        if args is None:
            print("hook-interp: cannot read %s" % path, file=sys.stderr)
            rc = 2
            continue
        for where, word, sb in plist_findings(args, roots):
            findings += 1
            print(
                "%s: %s execs %s by path — run it as `%s %s`"
                % (path, where, json.dumps(word), sb, word)
            )
    print(
        "hook-interp lint-plist: verdict=%s n=%d checked=%d"
        % ("RED" if findings else "clean", findings, len(paths))
    )
    return rc or (1 if findings else 0)


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
        # launchd ProgramArguments → how many by-path `#!` execs the job has.
        perl = "exec /usr/bin/perl -e 'alarm shift; exec @ARGV' 240 "
        jobs = [
            (["/bin/bash", "-c", 'exec "$HOME/.claude/hooks/b.sh" --x'], 1),
            (["/bin/bash", "-c", 'exec /bin/bash "$HOME/.claude/hooks/b.sh"'], 0),
            (
                [
                    "/bin/zsh",
                    "-lc",
                    "if [ -x /usr/sbin/taskpolicy ]; then exec /usr/sbin/taskpolicy -c utility"
                    " ~/.claude/hooks/e.sh; fi; exec ~/.claude/hooks/e.sh",
                ],
                2,
            ),
            (["/bin/bash", "-c", perl + '"$HOME/.claude/bin/tool" --k'], 1),
            (
                [
                    "/bin/bash",
                    "-c",
                    perl + '/usr/bin/env bash "$HOME/.claude/bin/tool"',
                ],
                0,
            ),
            (["/bin/bash", "-c", 'D="$HOME/.claude/hooks/b.sh"; exec "$D"'], 1),
            (["/bin/bash", "-c", "PATH=/usr/bin tool --x 2>&1 | head -5"], 1),
            (["/bin/bash", "-c", "a; /bin/bash ~/.claude/hooks/b.sh; rc=$?; tool"], 1),
            (["/Users/x/.claude/hooks/p.py", "run"], 1),
            (["/bin/bash", "/Users/x/.claude/hooks/b.sh"], 0),
            (["/bin/bash", "-c", "exec ~/.claude/hooks/gone.sh"], 0),
        ]
        for args, want in jobs:
            got = len(plist_findings(args, [d]))
            if got != want:
                bad += 1
                print(
                    "selftest FAIL: plist %r → %d finding(s), want %d"
                    % (args, got, want),
                    file=sys.stderr,
                )
        print(
            "hook-interp selftest: %s (%d cases)"
            % ("FAIL" if bad else "ok", len(cases) + 4 + len(jobs))
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
    if argv[:2] == ["lint-args", "--root"] and len(argv) == 3:
        # One argument per stdin line: a LOADED job's arguments as `launchctl print` lists them, so a
        # migration can tell whether the running job still has the by-path form its plist dropped.
        args = [a for a in sys.stdin.read().split("\n") if a]
        found = plist_findings(args, [os.path.abspath(argv[2])])
        for where, word, sb in found:
            print("%s execs %s by path (%s)" % (where, json.dumps(word), sb))
        return 1 if found else 0
    if argv[:1] == ["lint-plist"]:
        paths, roots, i = [], [], 1
        while i < len(argv):
            if argv[i] == "--root" and i + 1 < len(argv):
                roots.append(os.path.abspath(argv[i + 1]))
                i += 2
            else:
                paths.append(argv[i])
                i += 1
        if not paths or not roots:
            print(
                "hook-interp: lint-plist needs <job.plist>... --root DIR",
                file=sys.stderr,
            )
            return 2
        return lint_plists(paths, roots)
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
