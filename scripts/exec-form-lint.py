#!/usr/bin/env python3
"""exec-form-lint.py — rule R2's predicate: a tracked #! file run BY PATH from our shell code.

macOS 15.8.1 keeps ~1.1 KiB of kernel memory (data.kalloc.1024) for every #! file the kernel execs by
path, until reboot (docs/plans/KALLOC_TRIGGER_ELIMINATION_2026-10-22.md W4; REPORT §3 Phase 4). Our
own call sites were ~7-9% of the census. The cure is to run the interpreter with the script as its
argument: `cc_run "$X" …` / `cc_argv "$X"; timeout 5 "${CC_ARGV[@]}" …` (scripts/lib/cc-run.sh), or
the script's own shebang written out (`/bin/bash "$HOME/.claude/scripts/x.sh"`).

A FINDING is a simple command whose program word, past assignments and relays (exec, command,
nohup, time, nice, env, timeout, gtimeout, taskpolicy, caffeinate, xargs, `find … -exec`, and any
local `*bounded` wrapper that does not itself call cc_argv), names a tracked executable #! file:
  - a literal path whose tail is the file's repo path (`"$HOME/.claude/bin/cc-backlog"`,
    `"$REPO/scripts/x.sh"`, `scripts/x.sh`), or a beside-script path (`"$(dirname "$0")/x"`) that
    lands on one in the calling file's own directory;
  - a variable whose assignment in the same file names one (`B="${CC_B_BIN:-$HOME/.claude/bin/b}"`,
    `B="$(resolve_bin "$o" cc-backlog)"`), then run as `"$B"`.
A bare name (`cc-backlog add`) is a PATH lookup and is out of this rule's scope, as are Python
subprocess sites (scripts/lib/cc_run.py is their runner) and tests/ (rule R4, test-stub-lint.sh).

Heuristic by nature: it reads one logical line at a time, skips heredoc bodies and comments, and
cannot see through a variable assigned in another file. It is a RATCHET (config/exec-form-baseline.tsv),
so a miss costs a finding, never a false refusal of an unchanged file.

Usage: exec-form-lint.py [--root DIR] (--files F… | --all) [--list]
Prints `H<TAB>path<TAB>line<TAB>word<TAB>target` per finding and `F<TAB>path` per file scanned.
"""

from __future__ import annotations

import argparse
import os
import re
import shlex
import subprocess
import sys
from collections.abc import Iterable

SKIP_PREFIXES = ("tests/", "docs/", "vendor/")
SHELL_EXT = (".sh", ".bash", ".zsh")
SHELL_SHEBANG = re.compile(rb"^#!\s*\S*/(?:env\s+)?(?:ba|z)?sh\b")

# Relays: words that run their operand. Each maps to its own flags that take a value.
WRAPPERS: dict[str, tuple[str, ...]] = {
    "exec": ("-a",),
    "command": (),
    "nohup": (),
    "time": (),
    "nice": ("-n",),
    "env": ("-u", "-P", "-S"),
    "timeout": ("-k", "-s", "--kill-after", "--signal"),
    "gtimeout": ("-k", "-s", "--kill-after", "--signal"),
    "taskpolicy": ("-c", "-d", "-g", "-t", "-l", "-p"),
    "caffeinate": ("-t", "-w"),
    "xargs": ("-n", "-I", "-J", "-L", "-P", "-s", "-E", "-R", "-S", "-d"),
}
# ")" and "}" close a construct, so they do not start a command; case patterns are handled apart.
CMD_START = {
    ";",
    "&&",
    "||",
    "|",
    "&",
    "(",
    "{",
    ";;",
    ";&",
    ";;&",
    "|&",
    "`",
    "$(",
    "\n",
}
KEYWORDS = {
    "if",
    "then",
    "else",
    "elif",
    "do",
    "while",
    "until",
    "!",
    "for",
    "case",
    "in",
}
ASSIGN_RE = re.compile(
    r"^(?:local\s+|readonly\s+|export\s+|declare\s+(?:-[a-zA-Z]+\s+)*)?([A-Za-z_][A-Za-z0-9_]*)=(.*)$",
    re.S,
)
OPERAND_RE = re.compile(r"^\d+(\.\d+)?[smhd]?$")
VAR_RE = re.compile(r"^\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?$")
HEREDOC_RE = re.compile(r"<<-?\s*\\?(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\1")
FUNC_RE = re.compile(r"^\s*(?:function\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*\(\)\s*\{?")
RESOLVE_RE = re.compile(r"resolve_bin\s+\S+\s+['\"]?([A-Za-z0-9_.+-]+)")
OWN_DIR_HINT = re.compile(
    r"dirname|\$0|\$\{0|BASH_SOURCE|__file__|HERE|SELF|_DIR|DIR\b|_dir|ROOT|_root"
)


def git_ls(root: str) -> list[tuple[str, str]]:
    out = subprocess.run(
        ["git", "-C", root, "ls-files", "-s", "-z"], capture_output=True, check=True
    ).stdout
    rows = []
    for rec in out.split(b"\0"):
        if not rec:
            continue
        meta, path = rec.split(b"\t", 1)
        rows.append((meta.split()[0].decode(), path.decode("utf-8", "surrogateescape")))
    return rows


def head(path: str, n: int = 64) -> bytes:
    try:
        with open(path, "rb") as f:
            return f.read(n)
    except OSError:
        return b""


class Universe:
    """Tracked executable #! files, by repo path and by basename."""

    def __init__(self, root: str, rows: Iterable[tuple[str, str]]) -> None:
        self.paths: set[str] = set()
        self.by_name: dict[str, set[str]] = {}
        for mode, p in rows:
            if mode == "100755" and head(os.path.join(root, p), 2) == b"#!":
                self.paths.add(p)
                self.by_name.setdefault(os.path.basename(p), set()).add(p)

    def tail_match(self, word: str) -> str | None:
        """The tracked path that `word` ends with (after a '/' or at its start); longest wins."""
        best = None
        for p in self.by_name.get(os.path.basename(word.rstrip("/")), ()):
            if word == p or word.endswith("/" + p) or word.endswith('"' + p):
                if best is None or len(p) > len(best):
                    best = p
        return best


def shell_words(s: str) -> list[str]:
    s = s.replace("$(", " $( ").replace("`", " ` ")
    lex = shlex.shlex(s, posix=True, punctuation_chars=";&|(){}<>")
    lex.whitespace_split = True
    lex.commenters = "#"
    try:
        words = list(lex)
    except ValueError:
        return s.split()
    # shlex splits "$(" into "$" "(": put it back so it reads as a command start.
    out: list[str] = []
    for w in words:
        if w == "(" and out and out[-1] == "$":
            out[-1] = "$("
        else:
            out.append(w)
    return out


def open_quote(s: str) -> bool:
    """True when `s` ends inside a single or double quote (comments and escapes respected)."""
    q = ""
    i, n = 0, len(s)
    while i < n:
        c = s[i]
        if q == "'":
            if c == "'":
                q = ""
        elif c == "\\":
            i += 1
        elif q == '"':
            if c == '"':
                q = ""
        elif c in "'\"":
            q = c
        elif c == "#" and (i == 0 or s[i - 1] in " \t;&|("):
            break
        i += 1
    return q != ""


PATH_SUBS = re.compile(
    r"^\s*(command\s+-v|type\s+-P|echo|printf|dirname|cd|readlink|realpath|resolve_|_resolve|pwd)"
)


def strip_output_subs(value: str) -> str:
    """Drop `$(…)` bodies whose OUTPUT is not a path (`$(cc-kitty-bin)` yields a kitty binary)."""
    out, i, n = [], 0, len(value)
    while i < n:
        if value.startswith("$(", i):
            depth, j = 1, i + 2
            while j < n and depth:
                depth += {"(": 1, ")": -1}.get(value[j], 0)
                j += 1
            body = value[i + 2 : j - 1]
            out.append(value[i:j] if PATH_SUBS.match(body) else "")
            i = j
        else:
            out.append(value[i])
            i += 1
    return "".join(out)


def placeholder(body: str) -> str:
    """One quote-free word standing for a cut-out `$(body)`; keeps its letters so a beside-script
    prefix (`$(dirname "$0")/x`) still reads as one."""
    return "__CC_SUB_" + re.sub(r"[^A-Za-z0-9_]", "", body)[:48] + "__"


def split_subs(s: str) -> list[str]:
    """`s` with every `$(…)` / backtick body cut out (a placeholder word left behind), followed by
    those bodies, recursively. shlex cannot see a command inside a double-quoted `"$(cmd)"`, and
    nested quotes inside one (`"$(dirname "$0")"`) leave debris; cutting them out fixes both."""
    outer: list[str] = []
    bodies: list[str] = []
    i, n, q = 0, len(s), ""
    while i < n:
        c = s[i]
        if q != "'" and c == "\\" and i + 1 < n:
            outer.append(s[i : i + 2])
            i += 2
            continue
        if q == "'":
            q = "" if c == "'" else q
        elif s.startswith("$(", i) and not s.startswith("$((", i):
            depth, j = 1, i + 2
            while j < n and depth:
                depth += {"(": 1, ")": -1}.get(s[j], 0)
                j += 1
            bodies.extend(split_subs(s[i + 2 : j - 1]))
            outer.append(placeholder(s[i + 2 : j - 1]))
            i = j
            continue
        elif c == "`":
            j = s.find("`", i + 1)
            j = n if j < 0 else j
            bodies.extend(split_subs(s[i + 1 : j]))
            outer.append(placeholder(s[i + 1 : j]))
            i = j + 1
            continue
        elif c == '"':
            q = "" if q == '"' else '"'
        elif c == "'" and not q:
            q = "'"
        outer.append(c)
        i += 1
    return ["".join(outer), *bodies]


def logical_lines(text: str) -> Iterable[tuple[int, str]]:
    """(first line number, text) per logical line: continuations joined, heredoc bodies skipped."""
    lines = text.split("\n")
    i, n = 0, len(lines)
    while i < n:
        start = i + 1
        cur = lines[i]
        # Join continuations, and lines inside an open quote (a multi-line string is one word).
        while i + 1 < n and (cur.endswith("\\") or open_quote(cur)):
            i += 1
            cur = (cur[:-1] + " " if cur.endswith("\\") else cur + "\n") + lines[i]
        i += 1
        stripped = cur.lstrip()
        if stripped.startswith("#"):
            continue
        yield start, cur
        for m in HEREDOC_RE.finditer(cur.replace("<<<", "")):
            tag = m.group(2)
            dash = cur[m.start() + 2 : m.start() + 3] == "-"
            while i < n and (lines[i].strip() if dash else lines[i]) != tag:
                i += 1
            i += 1


class FileScan:
    def __init__(self, uni: Universe, rel: str, text: str) -> None:
        self.uni, self.rel, self.text = uni, rel, text
        self.dir = os.path.dirname(rel)
        self.assign: dict[str, list[str]] = {}
        self.safe_wrappers: set[str] = set()
        self.relay_funcs: set[str] = set()
        lines = text.split("\n")
        for idx, line in enumerate(lines):
            m = FUNC_RE.match(line)
            if m:
                body = "\n".join(lines[idx : idx + 8])
                name = m.group(1)
                if "cc_argv" in body or "cc_run" in body:
                    self.safe_wrappers.add(name)
                elif name.endswith("bounded"):
                    self.relay_funcs.add(name)
        for _, line in logical_lines(text):
            for part in re.split(r"[;&|]\s*", line.strip()):
                m = ASSIGN_RE.match(part.strip())
                if m:
                    self.assign.setdefault(m.group(1), []).append(m.group(2))

    def target_of_value(self, value: str, depth: int = 0) -> str | None:
        m = RESOLVE_RE.search(value)
        if m:
            for p in sorted(self.uni.by_name.get(m.group(1), ())):
                if p.startswith(("bin/", "scripts/")):
                    return p
        for tok in re.findall(r"[^\s\"'(){}:=]+", strip_output_subs(value)):
            t = self.target_of_word(tok, depth + 1)
            if t:
                return t
        return None

    def target_of_word(self, word: str, depth: int = 0) -> str | None:
        if depth > 4 or not word:
            return None
        v = VAR_RE.match(word)
        if v:
            for value in self.assign.get(v.group(1), ()):
                t = self.target_of_value(value, depth + 1)
                if t:
                    return t
            return None
        if "/" not in word or word.startswith(")"):
            return None  # a bare name is a PATH lookup; ")…" is shlex debris of nested quotes
        t = self.uni.tail_match(word)
        if t:
            return t
        prefix, _, name = word.rpartition("/")
        if name and OWN_DIR_HINT.search(prefix):
            cand = os.path.normpath(os.path.join(self.dir, name))
            if cand in self.uni.paths:
                return cand
        return None

    def findings(self) -> list[tuple[int, str, str]]:
        hits: list[tuple[int, str, str]] = []
        for lineno, line in logical_lines(self.text):
            if "/" not in line and "$" not in line:
                continue
            for seg in split_subs(line):
                for word in self.command_words(shell_words(seg)):
                    t = self.target_of_word(word)
                    if t:
                        hits.append((lineno, word, t))
        return hits

    def command_words(self, words: list[str]) -> list[str]:
        out: list[str] = []
        i, start, n = 0, True, len(words)

        def skip_to(*ends: str) -> int:
            j = i + 1
            while j < n and words[j] not in ends:
                j += 1
            return j

        def pattern_end(j: int) -> int:
            """Index of the `)` closing a case pattern list starting at j (`a|b)`), or -1."""
            while j + 1 < n and words[j] not in CMD_START and words[j] != ")":
                if words[j + 1] == ")":
                    return j + 1
                if words[j + 1] != "|":
                    return -1
                j += 2
            return -1

        while i < n:
            w = words[i]
            if w == "(" and i > 0 and words[i - 1].endswith("="):
                i = (
                    skip_to(")") + 1
                )  # `declare -a NAME=( … )`: an array literal, not a subshell
                continue
            if w in CMD_START:
                start = True
                i += 1
                continue
            if w in ("-exec", "-execdir", "-ok"):
                start = True  # find … -exec CMD
                i += 1
                continue
            if not start:
                i += 1
                continue
            # A case pattern list (`a|b)`), at the line's start or after `in` / `;;`.
            if i == 0 or words[i - 1] in ("in", ";;", ";&", ";;&"):
                e = pattern_end(i)
                if e >= 0:
                    i, start = e + 1, True
                    continue
            if w in ("[[", "for", "select", "case"):
                i = skip_to({"[[": "]]", "case": "in"}.get(w, "do"), ";") + 1
                start = w != "[["
                continue
            if w in KEYWORDS or w in ("<", ">", ">>", ")", "}", "esac", "done", "fi"):
                i += 1
                continue
            if w.endswith("=") and i + 1 < n and words[i + 1] == "(":
                i = skip_to(")") + 1  # NAME=( … ) is an array literal, not a subshell
                continue
            if ASSIGN_RE.match(w):
                i += 1
                continue
            base = os.path.basename(w)
            if base in self.safe_wrappers:
                start = False
                i += 1
                continue
            if base == "command" and i + 1 < n and words[i + 1] in ("-v", "-V"):
                i, start = i + 2, False  # a lookup, not a run
                continue
            if base in WRAPPERS or base in self.relay_funcs:
                valued = WRAPPERS.get(base, ())
                i += 1
                while i < n:
                    a = words[i]
                    if a in valued:
                        i += 2
                    elif a.startswith("-") or OPERAND_RE.match(a) or ASSIGN_RE.match(a):
                        i += 1
                    else:
                        break
                continue
            out.append(w)
            start = False
            i += 1
        return out


def is_shell(root: str, rel: str) -> bool:
    if rel.endswith(".bats") or rel.startswith(SKIP_PREFIXES):
        return False
    if rel.endswith(SHELL_EXT):
        return True
    return bool(SHELL_SHEBANG.match(head(os.path.join(root, rel))))


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=".")
    ap.add_argument("--files", nargs="*")
    ap.add_argument("--all", action="store_true")
    a = ap.parse_args(argv)
    root = os.path.abspath(a.root)
    try:
        rows = git_ls(root)
    except (OSError, subprocess.CalledProcessError) as e:
        print(f"exec-form-lint: git ls-files failed in {root}: {e}", file=sys.stderr)
        return 2
    uni = Universe(root, rows)
    if a.all:
        scope = [p for _, p in rows if is_shell(root, p)]
    else:
        scope = [f[2:] if f.startswith("./") else f for f in (a.files or [])]
        scope = [
            f
            for f in scope
            if os.path.isfile(os.path.join(root, f)) and is_shell(root, f)
        ]
    for rel in sorted(set(scope)):
        try:
            with open(
                os.path.join(root, rel), encoding="utf-8", errors="surrogateescape"
            ) as f:
                text = f.read()
        except OSError as e:
            print(f"exec-form-lint: cannot read {rel}: {e}", file=sys.stderr)
            return 2
        print(f"F\t{rel}")
        for lineno, word, target in FileScan(uni, rel, text).findings():
            print(f"H\t{rel}\t{lineno}\t{word}\t{target}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
