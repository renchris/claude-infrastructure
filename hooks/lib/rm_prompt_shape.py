#!/usr/bin/env python3
"""rm_prompt_shape.py — recognise the Bash shapes that trip Claude Code's built-in removal check.

Claude Code 2.1.284+ raises a "dangerous removal" safety dialog (circuitBreaker dangerousRemoval,
classifierApprovable false) and, in auto / bypassPermissions / plan mode, denies it on its own after
120 s when nobody answers ("will automatically deny this request in M:SS"). No allow rule clears it.
Census 2026-10-11 (docs/research/autodeny-prompts-2026-10-11/): 64 such auto-denies, 40 of them a
`bash -c` script the 2.1.293 inline-shell scanner cannot read and that removes nothing.

This module is a port of that research's prototypes (detect2.py + prfinal.py, the predicate scored
in design.md § C1). It is consulted ONLY at PermissionRequest time, i.e. after Claude Code has
already raised a Bash dialog: the same predicate run at PreToolUse time over all 260,433 Bash calls
had 8-29% precision, while over the dialogs actually raised in the 2.1.293 window it matched 32,
every one of them a dangerous-removal dialog.

Shapes:
  inline_shell   a `bash -c` / `sh -c` / `$SH -c` script that could run rm (an rm word, brace
                 expansion, or `$` in command position) and that the check cannot read (a function
                 definition, a $VAR command word, source/./eval/shift/trap, set --, IFS, alias,
                 positional assignment).
  unguarded_var  an rm/rmdir target that starts with an unguarded $VAR or "$VAR" followed by /.
  cd_rel_glob    cd/pushd X, then rm of a relative glob.
  none           anything else.

Usage:
  rm_prompt_shape.py --decide     stdin = PermissionRequest hook JSON. On a match: print the deny
                                  decision (with the rewrite recipe) and append a row to
                                  ~/.claude/logs/rm-prompt-preempt.jsonl. Otherwise print nothing.
                                  ANY error => exit 0 with no output (fail-open: the normal dialog).
  rm_prompt_shape.py --classify   stdin = a raw command. Prints the shape (or "none").

The hook only ever DENIES; there is no allow branch, so it can never let a removal through.
"""

import datetime
import hashlib
import json
import os
import re
import sys

# ── the inline-shell reader (CC 2.1.293's nan()/Hin() regexes, verbatim from the binary) ─────────
SHELLS = r"(?:ba|z|da|k|rba)?sh"
INL = re.compile(
    r"(?:^|(?<=[\s;&|(`{]))(?:[\w./-]*/)?"
    + SHELLS
    + r"\s+((?:-[A-Za-z]+\s+|--[\w-]+\s+)*)-[A-Za-z]*c[A-Za-z]*\s+"
    r'|(?:^|(?<=[\s;&|(`{]))"?\$\{?\w+\}?"?\s+-c\s+'
)
# `$SH -lc …` — a shell held in a variable (prfinal.py's addition).
VARSHELL = re.compile(r"""(?:^|[\s;&|(])"?\$\{?\w+\}?"?\s+-[A-Za-z]*c[A-Za-z]*\s""")


def read_word(s, i):
    """Read one shell word starting at s[i], resolving quotes; an unclosed quote runs to the end."""
    out = []
    n = len(s)
    while i < n:
        c = s[i]
        if c in " \t\n;&|<>()":
            break
        if c == "'":
            j = s.find("'", i + 1)
            j = n if j < 0 else j
            out.append(s[i + 1 : j])
            i = j + 1
        elif c == "$" and i + 1 < n and s[i + 1] == "'":
            j = i + 2
            while j < n and s[j] != "'":
                j += 2 if s[j] == "\\" else 1
            out.append(s[i + 2 : j])
            i = j + 1
        elif c == '"':
            j = i + 1
            buf = []
            while j < n and s[j] != '"':
                if s[j] == "\\" and j + 1 < n and s[j + 1] in '"\\$`\n':
                    buf.append(s[j + 1])
                    j += 2
                else:
                    buf.append(s[j])
                    j += 1
            out.append("".join(buf))
            i = j + 1
        elif c == "\\" and i + 1 < n:
            out.append(s[i + 1])
            i += 2
        else:
            out.append(c)
            i += 1
    return "".join(out)


def scripts(cmd):
    for m in INL.finditer(cmd):
        yield read_word(cmd, m.end())


def varshell_scripts(cmd):
    for m in VARSHELL.finditer(cmd):
        yield read_word(cmd, m.end())


NAN1 = re.compile(r"\{[^{}\s]*(?:,|\.\.)")
NAN2 = re.compile(r"(?:^|[^\w.-])rm(?:dir)?(?![\w.-])", re.I)
NAN3 = re.compile(r"(?:^|[;&|(){}\n`!])\s*(?:\w+\+?=\S*\s+)*\$")


def nan(e):
    """Could this -c script run rm? (CC's own test: rm word, brace expansion, $ in command position.)"""
    n = re.sub(r"""\$(?=['"])|['"\\]""", "", e)
    return bool(NAN1.search(n) or NAN2.search(n) or NAN3.search(n))


HIN_RE = re.compile(
    r"""\bfunction\b|\balias\b|\bIFS\b|\w\s*\(\s*\)|(?:^|[\s;&|(){}])(?:argv|[0-9]+)(?:\[[^\]]*\])?="""
    r"""|(?:^|[\s;&|(){}!])set\s[^;&|\n]*(?:\$\(|`)"""
)
WRAP = {
    "env",
    "command",
    "exec",
    "nohup",
    "nice",
    "time",
    "builtin",
    "sudo",
    "xargs",
    "timeout",
    "stdbuf",
    "caffeinate",
    "then",
    "do",
    "else",
    "elif",
    "if",
    "while",
    "until",
    "!",
}


def segs(e):
    for part in re.split(r"[;&|\n(){}`]+", e):
        toks = part.split()
        if toks:
            yield toks


def hin(e):
    """Can the check NOT read this script? Returns the reason, or None when it is readable."""
    if HIN_RE.search(e):
        return "hin_re"
    for toks in segs(e):
        k = 0
        while k < len(toks) and (
            toks[k] in WRAP
            or re.match(r"^(?:-|\d+$)", toks[k])
            or re.match(r"^\w+=", toks[k])
        ):
            k += 1
        if k >= len(toks):
            continue
        w = toks[k].strip("\"'")
        if re.match(r"^(?:shift|source|\.|eval|trap)$", w):
            return "src_eval"
        if re.match(r"^\$(?!\{?[0-9@*#])", w):
            return "dollar_cmd"
        if w == "set" and any(
            t in ("-", "--") or not re.match(r"^[-+]", t) for t in toks[k + 1 :]
        ):
            return "set_args"
    return None


# ── rm-target shapes ─────────────────────────────────────────────────────────────────────────────
RM_OCC = re.compile(
    r"""(?:^|[;&|\n({`]|&&|\|\||\bthen\b|\bdo\b|\belse\b)\s*(?:sudo\s+|command\s+|xargs\s+)?"""
    r"""(?:/bin/|/usr/bin/)?(rm|rmdir)\s+([^;&|\n)]*)"""
)
VAR_SLASH = re.compile(r"""\$\{?([A-Za-z_]\w*|[0-9@*])\}?"?/(?:[*?\[$/"']|\s|$)""")
CD = re.compile(r"""(?:^|[;&|\n(]|&&)\s*(?:cd|pushd)\s+\S""")


def rm_targets(cmd):
    for m in RM_OCC.finditer(cmd):
        args = [a for a in m.group(2).split() if not a.startswith(("-", "2>", ">"))]
        yield m.group(1), args, m.start()


def unguarded_var(cmd):
    for _v, args, _pos in rm_targets(cmd):
        for a in args:
            if "${" in a and ":?" in a:
                continue
            if VAR_SLASH.search(a):
                return a
    return None


def cd_rel_glob(cmd):
    for _v, args, pos in rm_targets(cmd):
        if not CD.search(cmd[: pos + 1]):
            continue
        for a in args:
            s = a.strip("\"'")
            if s.startswith(("/", "~", "$")):
                continue
            if re.search(r"[*?\[]", s):
                return a
    return None


# A removal word inside a -c script: rm, rmdir, unlink, shred as a command word, find … -delete,
# or -exec/-execdir rm. Decides which inline_shell recipe is safe to give.
REMOVAL = re.compile(
    r"""(?:^|[^\w.-])(?:rm|rmdir|unlink|shred)(?![\w.-])|\bfind\b[^;&|\n]*\s-delete\b"""
    r"""|-exec(?:dir)?\s+(?:\S*/)?rm\b""",
    re.I,
)


MAX_CMD = 32768


def classify(cmd):
    """Return (shape, token, removal) — shape is inline_shell|unguarded_var|cd_rel_glob|none.

    token is the offending rm target for the rm shapes; removal (inline_shell only) is True when
    the command or any -c script in it contains a removal word. The WHOLE command is checked, not
    only the -c script: a removal next to the wrapper (`bash -c '...'; rm -rf $T`) must not get the
    "write the script to a file" recipe either (one of the three census G4 rows has that shape).
    """
    if not isinstance(cmd, str) or not cmd:
        return "none", "", False
    # NAN3, RM_OCC and CD backtrack quadratically on long whitespace runs (measured 2026-10-11: a
    # ~100 KB `bash -c` script with 500-line blank runs took 6.2 s, ~96 KB of real text 8.3 s,
    # against the hook's 10 s timeout). Past the cap, pass through: the normal dialog shows.
    if len(cmd) > MAX_CMD:
        return "none", "", False
    found = []
    for sc in scripts(cmd):
        found.append(sc)
        if nan(sc) or "$'" in sc:
            if hin(sc):
                return (
                    "inline_shell",
                    "",
                    _has_removal(cmd, list(scripts(cmd)) + list(varshell_scripts(cmd))),
                )
    tok = unguarded_var(cmd)
    if tok:
        return "unguarded_var", tok, False
    tok = cd_rel_glob(cmd)
    if tok:
        return "cd_rel_glob", tok, False
    if VARSHELL.search(cmd):
        return (
            "inline_shell",
            "",
            _has_removal(cmd, found + list(varshell_scripts(cmd))),
        )
    return "none", "", False


def _has_removal(cmd, scs):
    return bool(REMOVAL.search(cmd)) or any(REMOVAL.search(s) for s in scs if s)


# ── the deny recipes ─────────────────────────────────────────────────────────────────────────────
# Claude Code's own rule, carried verbatim in every recipe: the hook's message REPLACES Claude
# Code's deny text, so it must not lose that sentence (verdicts.md, safety lens, C1 change 1).
PERSON_ONLY = (
    "Only a person may approve a removal this check stops; do not work around it by "
    "splitting, scripting, or re-issuing the removal through another tool or shell."
)
PREFIX = (
    "Denied at once by the rm-prompt-preempt hook, so this call does not wait in a 2-minute "
    "unattended prompt that Claude Code would then deny anyway. Nothing ran."
)


def _tok(t):
    t = t if len(t) <= 120 else t[:117] + "..."
    return t.replace("`", "'")


def recipe(shape, tok, removal):
    if shape == "inline_shell" and not removal:
        body = (
            "Claude Code's built-in removal check cannot read this `bash -c` script (it has a "
            'function, a "$@" runner, a $VAR used as a command, source/./eval, set -- or a '
            "{a,b} brace expansion), so it would prompt and then deny. Re-issue it in a readable "
            "form: write the script to a file and run `bash /tmp/<name>.sh` (`timeout N bash "
            "/tmp/<name>.sh` for a bound), or run the statements directly in this Bash call. The "
            "Bash tool is zsh, which does not word-split $VAR: bind a multi-word command as a "
            'function, `AB(){ agent-browser --session x "$@"; }`, never `AB="..."; $AB`.'
        )
    elif shape == "inline_shell":
        body = (
            "Claude Code's built-in removal check cannot read this `bash -c` script, and the "
            "script removes files. Re-issue it without the -c wrapper so the check can read the "
            'removal, and give every rm target a literal absolute path or "${VAR:?}" (for '
            'example `rm -rf "${D:?}"/build`). Do not move the removal into a script file, '
            "python, find -delete or another shell."
        )
    elif shape == "unguarded_var":
        body = (
            "The rm target `%s` starts with a variable followed by a slash; if the variable is "
            "empty the target becomes / or /*, so Claude Code's removal check stops it. Re-issue "
            'it with "${VAR:?}"/... (for example `rm -f "${D:?}"/*.jpg`) or the literal absolute '
            "path. If the variable came from cd, pwd, dirname or git rev-parse, only a literal "
            "path passes." % _tok(tok)
        )
    elif shape == "cd_rel_glob":
        body = (
            "This command changes directory and then removes the relative glob `%s`, which "
            "Claude Code's removal check cannot resolve. Re-issue the removal with the absolute "
            "path: `rm -f /abs/dir/<glob>`." % _tok(tok)
        )
    else:
        return None
    return "%s %s %s" % (PREFIX, body, PERSON_ONLY)


ACT_MODES = ("auto", "bypassPermissions", "plan")


def _log(row):
    try:
        d = os.path.join(os.path.expanduser("~"), ".claude", "logs")
        os.makedirs(d, exist_ok=True)
        line = json.dumps(row, ensure_ascii=True, separators=(",", ":")) + "\n"
        fd = os.open(
            os.path.join(d, "rm-prompt-preempt.jsonl"),
            os.O_WRONLY | os.O_APPEND | os.O_CREAT,
            0o600,
        )
        try:
            os.write(fd, line.encode("utf-8"))
        finally:
            os.close(fd)
    except Exception:
        pass  # a log failure never blocks the deny; the companion pager then still pages


def decide(raw):
    """Return the decision JSON string for a PermissionRequest input, or None to pass through."""
    hi = json.loads(raw)
    if not isinstance(hi, dict) or hi.get("tool_name") != "Bash":
        return None
    mode = hi.get("permission_mode")
    if (
        mode not in ACT_MODES
    ):  # the 120 s timer exists only in these modes (2.1.293 wln gate)
        return None
    ti = hi.get("tool_input")
    cmd = ti.get("command") if isinstance(ti, dict) else None
    if not isinstance(cmd, str) or not cmd:
        return None
    shape, tok, removal = classify(cmd)
    msg = recipe(shape, tok, removal)
    if not msg:
        return None
    row = {
        "ts": datetime.datetime.now(datetime.timezone.utc).strftime(
            "%Y-%m-%dT%H:%M:%S.%fZ"
        ),
        "session_id": hi.get("session_id") or "",
        "agent_id": hi.get("agent_id") or "",
        "shape": shape,
        "removal": bool(removal),
        "permission_mode": mode,
        "cmd_head": cmd[:200],
        "cmd_sha256": hashlib.sha256(cmd.encode("utf-8", "surrogatepass")).hexdigest(),
    }
    out = json.dumps(
        {
            "hookSpecificOutput": {
                "hookEventName": "PermissionRequest",
                "decision": {"behavior": "deny", "message": msg},
            }
        },
        ensure_ascii=True,
    )
    _log(row)
    return out


def main(argv):
    try:
        if len(argv) > 1 and argv[1] == "--classify":
            print(classify(sys.stdin.read())[0])
            return 0
        if len(argv) > 1 and argv[1] == "--decide":
            out = decide(sys.stdin.read())
            if out:
                sys.stdout.write(out + "\n")
                sys.stdout.flush()
            return 0
        sys.stderr.write("usage: rm_prompt_shape.py --decide | --classify\n")
        return 0
    except (
        BaseException
    ):  # fail-open: no output, exit 0 => Claude Code shows its normal dialog
        return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
