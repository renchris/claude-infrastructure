#!/usr/bin/env python3
"""Decision core for the PreToolUse(Bash) smart allowlist.

WHY THIS FILE EXISTS (2026-08-20). The hook it serves used to decide on the RAW COMMAND
STRING with start-anchored regexes. That is safe only for a single command, and 90.4% of
the commands that actually block this fleet are compound (measured: 1,693 blocking Bash
commands in ~/.claude/autonomy/permission-archive, mean 11.9 segments each, 59.1%
multi-line). The consequence was an exact inversion, both halves proven by running the
subject:

  * The ONE start-anchored rule (`git commit`) carried arbitrary payloads. Because a
    PreToolUse `allow` BYPASSES the permission system completely, prefixing
    `git commit -m x && ` auto-approved commands across EIGHT of the operator's own
    36 Bash fence rules — including the hard `deny` entries `git push --force` and
    `rm -rf .git`, plus `git clean -xdf`, `wget`, `fly deploy`, `git reset --hard`,
    `git restore`, and `git push`. Wired in 5 of 5 config dirs, so this was live.
  * Every rule that was correctly whole-command-anchored (`[^;&|]+$`: sed -n, chmod)
    could never fire on a compound command at all — so the SAFE rules were inert on
    exactly the corpus that generates the prompts.

So the old design was simultaneously too permissive where it fired and useless where it
did not. The fix is not a tighter regex; it is to stop deciding on the raw string.

THE RULE THIS FILE ENFORCES:

    allow(C)  iff  C decomposes CONFIDENTLY into segments s1..sn
                   AND no si matches the operator's live permissions.ask/deny fence
                   AND no danger pattern matches
                   AND every si independently matches a positive whitelist entry

Any doubt at any step yields NO DECISION (exit 0), which defers to the rest of the
permission chain. This file can only ever say `allow` or say nothing — `deny` is
deliberately unreachable, for the same reason model-permission-decider.py gives: a wrong
`deny` wedges a session with no human in the loop, while a wrong silence costs one prompt.

THE FENCE IS READ LIVE, NEVER HARDCODED. The operator adding a rule to permissions.ask or
permissions.deny arms this decider against it with no code change here. A resident copy of
a perishable fact cannot learn that it changed.
"""

import json
import os
import re
import sys

# ── segment decomposition ────────────────────────────────────────────────────────────
# Indirection means we cannot see what will actually run, so we refuse to decide at all.
# This is the same fence-on-INDIRECTION principle as model-permission-decider.py rule 4:
# enumerate the CLASS (something else chooses the command), never the spellings.
INDIRECTION = (
    ("<(", "process substitution"),
    (">(", "process substitution"),
    ("${!", "indirect expansion"),
)

# Command substitution is NOT in the list above, deliberately. `$(…)` and backticks are not
# opaque: the text inside is a COMMAND, and the honest thing to do with a command is judge
# it, not refuse to look. Measured on the archive, 543 of 1,747 blocking commands (31%)
# contain a substitution and NOTHING else this file cannot handle — refusing them outright
# was the single largest defer cause. So decide() extracts each substitution, runs the SAME
# fence + whitelist over its contents, and only then judges the outer command with the
# substitution replaced by a placeholder. Extraction is balanced-aware and fail-closed:
# anything unbalanced yields no decision.
#
# The placeholder is deliberately not a valid verb, so a command whose VERB comes out of a
# substitution (`$(which foo) --flags`) still defers — that really is indirection.
SUBST_PLACEHOLDER = "__ccsubst__"
MAX_SUBST_DEPTH = 3


def extract_substitutions(cmd):
    """(inner_commands, outer_with_placeholders, ok).

    Handles $( … ) with nesting, and simple non-nested backticks. Single-quoted regions are
    literal in shell, so substitutions inside them are not expanded and are left alone.
    """
    inner, out = [], []
    quote, i, n = None, 0, len(cmd)
    while i < n:
        ch = cmd[i]
        if quote == "'":
            out.append(ch)
            if ch == "'":
                quote = None
            i += 1
            continue
        if quote == '"' and ch == '"':
            quote = None
            out.append(ch)
            i += 1
            continue
        if quote is None and ch in ("'", '"'):
            quote = ch
            out.append(ch)
            i += 1
            continue
        if ch == "\\" and i + 1 < n:
            out.append(ch)
            out.append(cmd[i + 1])
            i += 2
            continue
        if ch == "$" and i + 1 < n and cmd[i + 1] == "(":
            if i + 2 < n and cmd[i + 2] == "(":
                return [], "", False  # $(( arithmetic )) — not a command, refuse
            depth, j = 1, i + 2
            while j < n and depth:
                if cmd[j] == "(":
                    depth += 1
                elif cmd[j] == ")":
                    depth -= 1
                j += 1
            if depth:
                return [], "", False  # unbalanced — cannot see the whole command
            inner.append(cmd[i + 2 : j - 1])
            out.append(SUBST_PLACEHOLDER)
            i = j
            continue
        if ch == "`":
            j = cmd.find("`", i + 1)
            if j == -1:
                return [], "", False
            inner.append(cmd[i + 1 : j])
            out.append(SUBST_PLACEHOLDER)
            i = j + 1
            continue
        out.append(ch)
        i += 1
    if quote is not None:
        return [], "", False
    return inner, "".join(out), True


# A heredoc body is DATA, not commands, so the body is stripped and only the command LINE is
# judged. The dangerous shapes survive that: `bash <<EOF` is refused because bash is a
# dispatcher, and `cat > f <<EOF` is refused by the redirect scanner.
_HEREDOC = re.compile(r"<<-?\s*(['\"]?)(\w+)\1(.*?)^\2\s*$", re.S | re.M)


def strip_heredocs(cmd):
    """(command_without_heredoc_bodies, ok). ok=False when a heredoc opens and never closes."""
    stripped = _HEREDOC.sub(" ", cmd)
    if "<<" in stripped:
        return "", False  # an unterminated heredoc — refuse to guess
    return stripped, True


# Interpreters and dispatchers that take a command as DATA. A whitelist can say nothing
# useful about `bash -c "$X"`, so any segment beginning with one of these defers.
DISPATCHERS = {
    "eval",
    "exec",
    "source",
    ".",
    "bash",
    "sh",
    "zsh",
    "ksh",
    "dash",
    "env",
    "xargs",
    "nohup",
    "setsid",
    "watch",
    "sudo",
    "doas",
    "su",
    "ssh",
    "docker",
    "kubectl",
    "make",
    "npm",
    "npx",
    "pnpm",
    "yarn",
    "bun",
    "uv",
    "pipx",
    "python",
    "python3",
    "node",
    "deno",
    "perl",
    "ruby",
    "osascript",
    "open",
    "timeout",
    "time",
    "nice",
    "taskpolicy",
    "caffeinate",
    "script",
    "expect",
}

_SPLIT_CHARS = {"&", "|", ";", "\n"}


def split_segments(cmd):
    """Split on && || ; | and newlines, respecting quotes.

    Returns (segments, ok). ok=False means we could not decompose with confidence and the
    caller must defer. Fail-closed on unbalanced quotes: a command we cannot even tokenize
    is exactly the one we must not auto-approve.
    """
    for token, _why in INDIRECTION:
        if token in cmd:
            return [], False

    segs, buf = [], []
    quote = None
    i, n = 0, len(cmd)
    while i < n:
        ch = cmd[i]
        if quote:
            if ch == "\\" and quote == '"' and i + 1 < n:
                buf.append(ch)
                buf.append(cmd[i + 1])
                i += 2
                continue
            if ch == quote:
                quote = None
            buf.append(ch)
            i += 1
            continue
        if ch in ("'", '"'):
            quote = ch
            buf.append(ch)
            i += 1
            continue
        if ch == "\\" and i + 1 < n:
            # A line continuation joins two physical lines into one command.
            if cmd[i + 1] == "\n":
                i += 2
                continue
            buf.append(ch)
            buf.append(cmd[i + 1])
            i += 2
            continue
        if ch in _SPLIT_CHARS:
            # `&` is a separator ONLY as the background operator or as `&&`. Inside a
            # redirect it is part of the file-descriptor syntax: `2>&1`, `>&2`, `&>log`.
            # Splitting there produced a phantom segment `1`, which is not a command, so
            # every `… 2>&1` in the corpus deferred for a reason that did not exist.
            if ch == "&":
                _prev = "".join(buf).rstrip()
                _next = cmd[i + 1] if i + 1 < n else ""
                if (_prev and _prev[-1] in "><") or _next == ">":
                    buf.append(ch)
                    i += 1
                    continue
            segs.append("".join(buf))
            buf = []
            # consume a doubled operator (&& / ||) as one separator
            if ch in ("&", "|") and i + 1 < n and cmd[i + 1] == ch:
                i += 2
            else:
                i += 1
            continue
        buf.append(ch)
        i += 1

    if quote is not None:
        return [], False  # unbalanced quote — cannot tokenize, so cannot decide
    segs.append("".join(buf))
    return segs, True


# Shell keywords that open or close a block. They are grammar, not commands, and are
# peeled so the real verb underneath is what gets judged.
KEYWORDS = {
    "do",
    "done",
    "then",
    "else",
    "elif",
    "fi",
    "esac",
    "in",
    "case",
    "if",
    "for",
    "while",
    "until",
    "function",
    "select",
    "coproc",
    "{",
    "}",
    "(",
    ")",
    "!",
    "[[",
    "]]",
}

_ENV_ASSIGN = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*)=(\S*)\s+(.*)$")
# One or more assignments and nothing else. The value may be quoted and may contain
# spaces, so it is matched non-greedily up to the next assignment or end of segment.
_ONLY_ASSIGNMENTS = re.compile(
    r"^(?:[A-Za-z_][A-Za-z0-9_]*=(?:\"[^\"]*\"|'[^']*'|\S*)\s*)+$"
)
# `set` with option flags only. `set -- a b` and `set VAR` are excluded: the first
# rewrites the positional parameters, and neither is the shape this is meant to retire.
_SET_OPTIONS = re.compile(
    r"^set(\s+[-+][A-Za-z]+)*(\s+(pipefail|posix|errexit|nounset|xtrace))*\s*$"
)
_LOOP_HEAD = re.compile(r"^(?:for|while|until)\s+\S+\s+in\s+(.*)$")


def normalize(seg):
    """Reduce a raw segment to the command a rule should be matched against.

    Returns "" for a segment that carries no command (pure grammar, a redirection-only
    fragment, or a bare variable assignment).
    """
    s = " ".join(seg.strip().split())
    if not s:
        return ""
    changed = True
    while changed:
        changed = False
        if _LOOP_HEAD.match(s):
            # `for VAR in LIST` carries NO command — the list is a word list, and the loop
            # body is a separate segment (it is separated by `;` or a newline, which
            # split_segments already cut on). Treating the list as if it were a command
            # was both wrong and self-defeating: with substitutions now judged separately,
            # `for i in $(seq 1 40)` reduced to the placeholder and deferred, which is the
            # single commonest loop shape in the corpus.
            return ""
        head = s.split(" ", 1)[0]
        if head in KEYWORDS:
            s = s[len(head) :].strip()
            changed = True
            continue
        m = _ENV_ASSIGN.match(s)
        if m:  # leading FOO=bar assignments are not the decided verb
            s = m.group(3).strip()
            changed = True
            continue
        # `export FOO=bar` / `export FOO` sets a shell variable and runs nothing. Peeling
        # the keyword lets the assignment rule below retire the segment. `env` is NOT
        # treated this way — it is a dispatcher, because `env CMD …` runs CMD.
        if s == "export" or s.startswith("export "):
            s = s[len("export") :].strip()
            changed = True
            continue
    # A segment that is nothing but assignments carries no command. This is the shape of
    # the scratch-path preambles that dominate this fleet's compound commands
    # (`SP=/private/tmp/…; SB=$SP/state; …`), and judging `SP` as if it were a verb made
    # each one an unfixable defer — 123 commands in the archive died on exactly that.
    if s and _ONLY_ASSIGNMENTS.match(s):
        return ""
    # `set -e`, `set -u`, `set -euo pipefail` change shell options and run nothing.
    if _SET_OPTIONS.match(s):
        return ""
    return s


def verb(seg):
    m = re.match(r"^([A-Za-z0-9_.\-/]+)", seg)
    if not m:
        return None
    v = m.group(1)
    return v.rsplit("/", 1)[-1] if "/" in v else v


# ── the operator's live fence ────────────────────────────────────────────────────────
def _settings_paths():
    """User settings first, then any project settings in cwd. The fence is the UNION of
    every ask/deny rule we can see — the conservative direction, so a project gating a
    command cannot be undone by the user file staying silent about it."""
    cfg = os.environ.get("CLAUDE_CONFIG_DIR") or os.path.join(
        os.path.expanduser("~"), ".claude"
    )
    out = [os.path.join(cfg, "settings.json")]
    for rel in (".claude/settings.json", ".claude/settings.local.json"):
        out.append(os.path.join(os.getcwd(), rel))
    return out


_BASH_RULE = re.compile(r"^Bash\((.*)\)$")


def load_fence():
    """Every Bash rule the operator placed behind `ask` or `deny`, as match prefixes.

    Returns (prefixes, ok). ok=False when the user settings file exists but cannot be
    read or parsed — we must not auto-approve while blind to the fence.
    """
    prefixes, ok = [], True
    for idx, path in enumerate(_settings_paths()):
        if not os.path.exists(path):
            continue
        try:
            with open(path, encoding="utf-8-sig") as fh:
                perms = json.load(fh).get("permissions", {})
        except Exception:
            if idx == 0:
                ok = False  # the USER fence is the one we cannot proceed without
            continue
        for key in ("ask", "deny"):
            for rule in perms.get(key, []) or []:
                m = _BASH_RULE.match(rule if isinstance(rule, str) else "")
                if not m:
                    continue
                pat = m.group(1)
                prefixes.append(pat[:-2] if pat.endswith(":*") else pat)
    return prefixes, ok


def crosses_fence(seg, prefixes):
    """True when this segment is something the operator gated.

    Matched as a prefix on the normalized segment, which is how the harness's own Bash
    rules read. Deliberately generous: `git push` fences `git push origin main`, and a
    bare `rm -rf /` entry still fences the exact command.
    """
    for p in prefixes:
        if not p:
            continue
        if seg == p or seg.startswith(p + " ") or seg.startswith(p):
            return p
    return None


# ── danger patterns (whole command) ──────────────────────────────────────────────────
# Carried over from validate-bash.sh. These are a BACKSTOP, not the safety story: the
# positive whitelist below is what actually bounds the decision. Kept because a match
# here should refuse even a command whose segments all look individually innocent.
DANGER = [
    (r"rm -rf /[^a-zA-Z]", "rm -rf on a root path"),
    (r"\bsudo\s+rm\b", "sudo rm"),
    (r":\(\)\{ :\|:& \};:", "fork bomb"),
    (
        r"\b(DROP\s+TABLE|DROP\s+DATABASE|DROP\s+INDEX|ALTER\s+TABLE|CREATE\s+TABLE|TRUNCATE)\b",
        "DDL",
    ),
    (r"drizzle-kit\s+push", "drizzle-kit push"),
    (r"git\s+add\s+(-f|--force)\b", "git add --force"),
    (r"(^|\s)--no-verify(\s|$)", "--no-verify"),
    (r"turso\s+db\s+(shell|destroy)\b", "turso db shell/destroy"),
    (r"chmod\s+(-R\s+)?777\b", "chmod 777"),
    # Bundled short flags are the normal spelling: `git clean -xdf` must match as surely
    # as `git clean -x`. The prior `-[xX]\b` required a word boundary immediately after
    # the letter, so every bundled form slipped past it.
    (
        r"git\s+clean\b[^;&|]*\s-[A-Za-z]*[xX]",
        "git clean -x/-X (deletes gitignored assets)",
    ),
]
DANGER = [(re.compile(p, re.I), why) for p, why in DANGER]


def danger(cmd):
    for rx, why in DANGER:
        if rx.search(cmd):
            return why
    return None


# ── positive whitelist ───────────────────────────────────────────────────────────────
DENY_DIR = re.compile(
    r"(^|/)lib/error-logger|(^|/)lib/rate-limit|(^|/)src/app/actions|(^|/)src/app/api"
    r"|(^|/)middleware\.|(^|/)next\.config|(^|/)drizzle/|(^|/)\.env($|\.)"
    r"|(^|/)package\.json$|(^|/)pnpm-lock|(^|/)tsconfig\.json$|(^|/)\.npmrc$"
    r"|(^|/)\.nvmrc$|(^|/)\.mcp\.json$|(^|/)infrastructure/|(^|/)\.github/workflows/"
    r"|(^|/)pre-build/|(^|/)\.claude/(hooks/|agents/|settings\.json$|settings\.local\.json$)"
)
DENY_SENSITIVE = re.compile(
    r"(^|/)(auth|session|cookie|token|secret)(\.config)?\.(ts|tsx|js|jsx|json)$"
    r"|(^|/)(auth|session|cookie|token|secret)-(handler|helpers?|service|utils?|middleware"
    r"|manager|provider|guard)\.(ts|tsx|js|jsx)$"
    r"|(^|/)(auth|session|cookies?|tokens?|secrets?)/"
)


def path_escapes_project(p):
    """True when a write target must NOT be auto-allowed.

    Note the ERE-lookahead history: this guard was once written as `^/(?!…)`, which POSIX
    ERE does not support, so /usr/bin/grep exited 2 and the branch never fired — inert and
    fail-OPEN for its whole life. Expressed here as explicit cases so it cannot fail that
    way again.
    """
    if ".." in p or "*" in p or "?" in p:
        return True
    if not p.startswith("/"):
        return False
    # BOTH SIDES MUST BE RESOLVED. os.getcwd() returns the PHYSICAL path, so on macOS a
    # caller who passes the equally-valid logical spelling (/var/folders/… for
    # /private/var/folders/…) was refused as "outside the project" — an over-rejection the
    # bash original did not have, because $PWD keeps the logical form. Resolving both is
    # also the safe direction for the case that matters: a symlink inside the project that
    # points out of it resolves outside and is correctly refused.
    try:
        target = os.path.realpath(p)
        root = os.path.realpath(os.getcwd())
    except OSError:
        return True
    return not (target == root or target.startswith(root.rstrip("/") + "/"))


def _protected(p):
    return bool(DENY_DIR.search(p) or DENY_SENSITIVE.search(p))


_SCRATCH_ROOTS = ("/tmp/", "/private/tmp/", "/var/folders/", "/private/var/folders/")


def _scratch_path(p):
    """True for a SUBPATH of an accepted scratch root — never the root itself.

    `mkdir -p /tmp` is pointless; `mkdir -p /tmp` with a trailing component is the shape
    the corpus actually contains (session scratchpads under /private/tmp/claude-501/…).
    Requiring a subpath keeps the allowance narrow, matching rm-safe-allowlist.sh's own
    treatment of the same roots.
    """
    if ".." in p or "*" in p or "?" in p:
        return False
    for root in _SCRATCH_ROOTS:
        if p.startswith(root) and len(p) > len(root):
            return True
    return False


_RM_HOOK = os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "..", "rm-safe-allowlist.sh"
)


def _rm_hook_allows(seg):
    """Reason string when rm-safe-allowlist.sh would allow this segment alone, else None.

    Fail-closed on every error path — a missing hook, a non-zero exit, a timeout, or output
    we cannot parse all mean "no decision", which costs one prompt. The subprocess is
    bounded well under the 5s hook timeout so a wedged child cannot make the whole hook
    time out (a timed-out PreToolUse hook has its verdict DISCARDED and falls through to
    the auto-mode classifier, which is a worse outcome than deferring on purpose).
    """
    try:
        import subprocess

        r = subprocess.run(
            ["bash", _RM_HOOK],
            input=json.dumps({"tool_name": "Bash", "tool_input": {"command": seg}}),
            capture_output=True,
            text=True,
            timeout=2,
        )
    except Exception:
        return None
    if r.returncode != 0 or not r.stdout.strip():
        return None
    try:
        out = json.loads(r.stdout)
        if out["hookSpecificOutput"]["permissionDecision"] == "allow":
            return "rm: rm-safe-allowlist would allow this target standing alone"
    except Exception:
        return None
    return None


SED_N_SCRIPT = [
    re.compile(r"^[0-9]+(,[0-9]+|,\$)?[p=l]$"),
    re.compile(r"^\$[p=l]$"),
    re.compile(r"^/[^/]*/(,/[^/]*/)?[p=l]$"),
    re.compile(r"^[0-9]+,/[^/]*/[p=l]$"),
]

SAFE_CHMOD = {"644", "755", "600", "700", "750", "640", "+x", "u+x"}

# ── redirection ──────────────────────────────────────────────────────────────────────
# A read-only verb stops being read-only the moment its output is redirected into a file,
# and `>` is also how awk and sed write without any shell involvement. One scanner covers
# both, because it looks at the raw segment text rather than at the parsed arguments.
_SAFE_REDIRECT_TARGET = re.compile(r"^(?:&[0-9-]|/dev/null|/dev/stderr|/dev/stdout)$")


def redirects_to_file(seg):
    """True when the segment redirects anywhere except a null/std stream.

    Quote-aware so that a `>` inside an argument (a grep pattern, a commit message) is not
    mistaken for a redirect — but note the deliberate asymmetry: an awk program is quoted,
    and `awk '{print > "f"}'` DOES write. awk is therefore refused separately on its own
    write forms rather than being cleared by this scanner alone.
    """
    quote, i, n = None, 0, len(seg)
    while i < n:
        ch = seg[i]
        if quote:
            if ch == quote:
                quote = None
            i += 1
            continue
        if ch in ("'", '"'):
            quote = ch
            i += 1
            continue
        if ch == "\\":
            i += 2
            continue
        if ch == ">":
            j = i + 1
            while j < n and seg[j] == ">":
                j += 1
            while j < n and seg[j] == " ":
                j += 1
            k = j
            while k < n and seg[k] not in " \t":
                k += 1
            if not _SAFE_REDIRECT_TARGET.match(seg[j:k]):
                return True
            i = k
            continue
        i += 1
    return False


# ── read-only verbs ─────────────────────────────────────────────────────────────────
# Chosen from the measured corpus, not from imagination: these are the verbs that appear
# in ~/.claude/autonomy/permission-archive as segments of commands that actually blocked.
# Membership here means "cannot modify the machine when invoked without a redirect"; every
# verb whose SAFETY DEPENDS ON ITS FLAGS gets an explicit guard below instead.
READ_ONLY = {
    "cat",
    "head",
    "tail",
    "wc",
    "ls",
    "file",
    "stat",
    "du",
    "df",
    "basename",
    "dirname",
    "realpath",
    "readlink",
    "pwd",
    "echo",
    "printf",
    "date",
    "uname",
    "hostname",
    "whoami",
    "id",
    "which",
    "type",
    "sleep",
    "true",
    "false",
    "test",
    "seq",
    "uniq",
    "cut",
    "tr",
    "column",
    "comm",
    "diff",
    "cmp",
    "rev",
    "fold",
    "shasum",
    "md5",
    "cksum",
    "jq",
    "yq",
    "grep",
    "egrep",
    "fgrep",
    "rg",
    "ag",
    "tree",
    "ps",
    "pgrep",
    "lsof",
    "tput",
    "expr",
    "dirname",
    "nl",
    "strings",
    "hexdump",
    "xxd",
    "od",
    "wc",
    "logname",
    "groups",
    "arch",
    "sw_vers",
    "sysctl",
}

# Verbs whose safety is a function of their arguments. Each returns a reason or None.
FIND_UNSAFE = re.compile(r"(^|\s)-(delete|exec|execdir|ok|okdir|fprint|fprintf|fls)\b")
SORT_UNSAFE = re.compile(r"(^|\s)(-o|--output)\b")
AWK_UNSAFE = re.compile(r"(system\s*\(|\bprint(f)?\s*>|\|\s*&|\bclose\s*\()")
GIT_READ = {
    "status",
    "log",
    "diff",
    "show",
    "rev-parse",
    "rev-list",
    "ls-tree",
    "ls-files",
    "cat-file",
    "describe",
    "merge-base",
    "blame",
    "shortlog",
    "for-each-ref",
    "symbolic-ref",
    "check-ignore",
    "count-objects",
    "reflog",
    "whatchanged",
    "grep",
    "name-rev",
    "var",
    "version",
    "diff-tree",
    "diff-index",
    "verify-commit",
    "check-attr",
    "hash-object",
    "fetch",
    "remote",
    "branch",
    "tag",
    "stash",
    "worktree",
    "config",
    "bisect",
    "help",
}
# The read subcommands above that ALSO have a mutating form, with the forms that make them
# mutate. Anything not explicitly cleared here falls through to no decision.
GIT_SUBCOMMAND_READ_ONLY = {
    "remote": re.compile(r"^(-v|--verbose|show|get-url)?\s*$"),
    "branch": re.compile(
        r"^(-a|-r|-v|-vv|--list|--all|--remotes|--show-current|--contains\s+\S+)*\s*$"
    ),
    "tag": re.compile(r"^(-l|--list|-n[0-9]*)?\s*(\S*)\s*$"),
    "stash": re.compile(r"^(list|show)\b.*$"),
    "worktree": re.compile(r"^list\b.*$"),
    "config": re.compile(r"^(--get|--get-all|--get-regexp|--list|-l)\b.*$"),
    "bisect": re.compile(r"^(log|view)\b.*$"),
}

# curl: a POSITIVE whitelist of flags. A deny-list here would be enumerating spellings
# (-o / --output / -O / --remote-name all write a file), which is the failure mode this
# file exists to avoid. Every token must be a cleared flag, a value for one, or an
# http(s) URL — anything else, including any unrecognised flag, defers.
CURL_FLAGS_NOARG = {
    "-s",
    "-S",
    "-L",
    "-f",
    "-i",
    "-I",
    "-k",
    "-g",
    "-G",
    "-v",
    "--get",
    "--verbose",
    "--silent",
    "--show-error",
    "--location",
    "--fail",
    "--include",
    "--head",
    "--insecure",
    "--compressed",
    "--http1.1",
    "--http2",
    "--no-progress-meter",
    "--fail-with-body",
    "--globoff",
}
CURL_FLAGS_WITHARG = {
    "-m",
    "--max-time",
    "--connect-timeout",
    "-H",
    "--header",
    "-A",
    "--user-agent",
    "-w",
    "--write-out",
    "-b",
    "--cookie",
    "-e",
    "--referer",
    "--retry",
    "--retry-delay",
    "--retry-max-time",
    "-r",
    "--range",
    "--resolve",
}
_URL = re.compile(r"^['\"]?https?://", re.I)
# curl flags whose argument is a FILE THAT GETS WRITTEN. Kept as a named set so the
# containment check applies uniformly and a future flag is added in one place. Everything
# NOT listed here and not in the two flag sets above still rejects the whole invocation,
# so this stays a positive whitelist — -d/--data, -T/--upload-file and -X never appear.
CURL_FLAGS_WRITEFILE = {
    "-o",
    "--output",
    "-c",
    "--cookie-jar",
    "-D",
    "--dump-header",
    "--trace",
    "--trace-ascii",
    "--stderr",
}


def _unquote(tok):
    if len(tok) >= 2 and tok[0] == tok[-1] and tok[0] in "'\"":
        return tok[1:-1]
    return tok


def allowed_segment(seg, sole=False):
    """The positive whitelist. Returns a reason string, or None to defer.

    Every entry judges a SINGLE segment; the caller requires all of them to pass. Nothing
    here may admit a command by its prefix alone — that is precisely the defect this file
    replaces.
    """
    v = verb(seg)
    if v is None:
        return None
    if v in DISPATCHERS:
        return None  # something else chooses the real command — never decide

    # A substitution standing in the VERB position is genuine indirection: the machine will
    # execute whatever text the substitution produced. Judging the inner command does not
    # help — `$(which foo) --flags` runs `foo`, not `which`. In ARGUMENT position the same
    # placeholder is only data, which is why this is checked on the verb alone.
    if v == SUBST_PLACEHOLDER or v.startswith(SUBST_PLACEHOLDER):
        return None

    parts = seg.split()

    # git commit — a local operation. --no-verify is already refused by DANGER.
    if v == "git" and len(parts) >= 2 and parts[1] == "commit":
        return "git commit: local commit, no --no-verify"

    # sed -n — read-only paging. -n suppresses auto-print, so sed emits only what an
    # explicit p/=/l prints. Validated by POSITIVE whitelist of the script shape: a
    # blacklist here enumerates spellings (w/W/e) rather than the class.
    if v == "sed" and len(parts) >= 3 and parts[1] == "-n":
        script = _unquote(parts[2])
        if any(rx.match(script) for rx in SED_N_SCRIPT):
            return "sed -n: read-only paging (whitelisted address+print script)"
        return None

    # sed -i — in-place edit, target must be inside the project and unprotected.
    if v == "sed" and len(parts) >= 2 and parts[1].startswith("-i"):
        target = _unquote(parts[-1])
        if path_escapes_project(target) or _protected(target):
            return None
        return "sed -i: target under CWD, not in protected paths"

    # chmod — safe modes only, target inside the project.
    if v == "chmod" and len(parts) >= 3:
        if parts[1] not in SAFE_CHMOD:
            return None
        for target in parts[2:]:
            t = _unquote(target)
            if path_escapes_project(t) or _protected(t):
                return None
        return "chmod: safe mode, targets under CWD"

    # rm — DELEGATED, never re-implemented. hooks/rm-safe-allowlist.sh already owns the
    # question "is this deletion safe", is separately tested, and honours its own kill
    # switch. Asking IT whether it would allow this exact segment standing alone means we
    # invent no deletion policy here and cannot drift from it. It was the second-largest
    # defer cause (332 segments) precisely because it, too, is whole-command-anchored and
    # so could never see a segment of a compound command.
    if v == "rm":
        # OWNERSHIP BOUNDARY: a command that is ONLY an rm belongs to rm-safe-allowlist.sh,
        # which is wired in the same PreToolUse chain and will answer it directly. This
        # hook stays out of that case — retired rule 2 said deletion stays behind the
        # operator's own gate here, and tests/smart-bash-allowlist-narrow.bats pins it.
        # The delegation exists purely for the case rm-safe CANNOT reach: rm as one
        # segment of a compound, where its own whole-command anchor makes it inert.
        if sole:
            return None
        return _rm_hook_allows(seg)

    # ── everything below is read-only, so a redirect disqualifies it outright ────────
    if redirects_to_file(seg):
        return None

    # cd — navigation only. It changes no file, and the containment checks above are
    # evaluated against the hook's own cwd, which a `cd` in a SEGMENT cannot move (each
    # segment is judged independently, and the hook never executes anything).
    if v == "cd":
        return "cd: navigation"

    # git, read-only subcommands.
    if v == "git" and len(parts) >= 2:
        sub = parts[1]
        if sub not in GIT_READ:
            return None
        guard = GIT_SUBCOMMAND_READ_ONLY.get(sub)
        if guard is not None:
            # These subcommands have BOTH a read and a mutating form (`git branch -d`,
            # `git config <k> <v>`, `git worktree add`). Only the explicitly-cleared read
            # spelling passes; every other spelling falls through to the normal gate.
            if not guard.match(" ".join(parts[2:])):
                return None
        return f"git {sub}: read-only"

    if v == "find":
        if FIND_UNSAFE.search(seg):
            return None
        return "find: traversal without -delete/-exec"

    if v == "sort":
        if SORT_UNSAFE.search(seg):
            return None
        return "sort: no -o output file"

    if v in ("awk", "gawk", "mawk"):
        # A quoted awk program can write with `print > "f"` or run a shell with system(),
        # neither of which the shell-level redirect scanner can see.
        if AWK_UNSAFE.search(seg):
            return None
        return "awk: no system() and no in-program write"

    if v == "curl":
        i = 1
        while i < len(parts):
            tok = parts[i]
            if tok in CURL_FLAGS_NOARG:
                i += 1
                continue
            if tok in CURL_FLAGS_WITHARG:
                i += 2
                continue
            if "=" in tok and tok.split("=", 1)[0] in CURL_FLAGS_WITHARG:
                i += 1
                continue
            # Bundled short flags (-sSL, -sG, -sI) are the ordinary spelling, and
            # enumerating every permutation is exactly the enumerate-the-spellings failure
            # this file avoids elsewhere. Accept a bundle only when EVERY letter in it is
            # independently cleared — one uncleared letter rejects the whole token.
            if (
                len(tok) > 1
                and tok[0] == "-"
                and tok[1] != "-"
                and all(("-" + c) in CURL_FLAGS_NOARG for c in tok[1:])
            ):
                i += 1
                continue
            # Flags that WRITE A FILE get the same containment rule as every other write in
            # this file: /dev/null, or a target under the project or an accepted scratch
            # root, and never a protected path. Refusing them outright was both the largest
            # curl rejection in the corpus (518 segments, mostly `-o /dev/null` for a
            # status-code probe and `-o <scratchpath>` for a download) and inconsistent —
            # `sed -i` and `mkdir` were already judged exactly this way.
            if tok in CURL_FLAGS_WRITEFILE and i + 1 < len(parts):
                _t = _unquote(parts[i + 1])
                if not (
                    _t == "/dev/null"
                    or (
                        not _protected(_t)
                        and (_scratch_path(_t) or not path_escapes_project(_t))
                    )
                ):
                    return None
                i += 2
                continue
            if _URL.match(tok):
                i += 1
                continue
            # An unrecognised token — including any flag not on the positive list, which
            # is how -o/-O/-d/-T/-X stay out — means we cannot vouch for this invocation.
            return None
        return "curl: fetch-only flags, no output file, no upload, no method override"

    # mkdir — creating a directory is the least destructive write there is, but it still
    # must land inside the project or an accepted scratch root.
    if v == "mkdir":
        targets = [_unquote(t) for t in parts[1:] if not t.startswith("-")]
        if not targets:
            return None
        for t in targets:
            if not (_scratch_path(t) or not path_escapes_project(t)):
                return None
            if _protected(t):
                return None
        return "mkdir: targets under CWD or an accepted scratch root"

    if v in READ_ONLY:
        return f"{v}: read-only, no redirect"

    return None


# ── entry point ──────────────────────────────────────────────────────────────────────
def decide(cmd, _fence=None, _depth=0):
    """(decision, reason). decision is 'allow' or None (defer).

    _fence / _depth exist for the recursive pass over command substitutions: the inner
    command is judged by this same function, against the same fence, so a substitution can
    never be a way around a rule that binds the outer command.
    """
    if not cmd or not cmd.strip():
        return None, "empty command"

    why = danger(cmd)
    if why:
        return None, f"danger pattern: {why}"

    if _fence is None:
        _fence, fence_ok = load_fence()
        if not fence_ok:
            return None, "fence unreadable — refusing to decide"
    fence = _fence

    cmd, heredocs_ok = strip_heredocs(cmd)
    if not heredocs_ok:
        return None, "unterminated heredoc"

    # Judge every command substitution FIRST, with the same rules and the same fence.
    if _depth >= MAX_SUBST_DEPTH:
        return None, "substitution nested deeper than the audit limit"
    inner, cmd, subst_ok = extract_substitutions(cmd)
    if not subst_ok:
        return None, "could not decompose the command with confidence"
    for sub in inner:
        d, sub_why = decide(sub, _fence=fence, _depth=_depth + 1)
        if d != "allow":
            return None, f"inside a substitution: {sub_why}"

    segs, ok = split_segments(cmd)
    if not ok:
        return None, "could not decompose the command with confidence"

    judgeable = [s for s in (normalize(raw) for raw in segs) if s]
    reasons, judged = [], 0
    for seg in judgeable:
        crossed = crosses_fence(seg, fence)
        if crossed:
            return None, f"segment is behind the operator's own gate: {crossed}"
        r = allowed_segment(seg, sole=(len(judgeable) == 1))
        if r is None:
            return None, f"segment not on the allowlist: {seg[:60]}"
        reasons.append(r)
        judged += 1

    if judged == 0:
        return None, "no judgeable command in the input"
    return "allow", "; ".join(dict.fromkeys(reasons))


def main():
    try:
        payload = json.load(sys.stdin)
    except Exception:
        return 0  # malformed input — defer, never guess
    cmd = ""
    if isinstance(payload, dict):
        ti = payload.get("tool_input")
        if isinstance(ti, dict):
            cmd = ti.get("command") or ""
    try:
        decision, reason = decide(cmd)
    except Exception as exc:  # a crash must cost a prompt, not a bypass
        sys.stderr.write(f"smart-bash-allowlist: deferring after error: {exc}\n")
        return 0
    if decision != "allow":
        return 0
    json.dump(
        {
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": "allow",
                "permissionDecisionReason": reason,
            }
        },
        sys.stdout,
    )
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
