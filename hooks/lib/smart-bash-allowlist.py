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
import shlex
import sys
from urllib.parse import urlparse

# The shared internal-address normalizer (also used by hooks/curl-gate.py). If it cannot be loaded
# the curl arm DEFERS — this file may only ever fail toward a prompt.
sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
try:
    import curl_ssrf as _ssrf
except ImportError:
    _ssrf = None

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


# `$(( … ))` is ARITHMETIC expansion, not command substitution: the shell evaluates integer
# arithmetic and executes NOTHING. Until 2026-09-10 meeting one returned not-ok, which deferred
# the WHOLE command — measured on the beacon archive as the largest single cause of a defer
# (87 of 1,747 structural rows died on it at the top level, 91 counting nested ones), and worse,
# it MASKED every other cause in those rows: `causes()` returns early on an undecomposable
# command, so a harvest report attributed them to "cannot decompose" instead of to the verbs
# they actually carry. Refusing to look at arithmetic is also inconsistent with the paragraph
# above — a substitution is a COMMAND and we judge it; arithmetic cannot even be one.
#
# It is consumed as DATA (a placeholder), but ONLY when its contents are provably arithmetic,
# because `$((` is genuinely ambiguous: `$( (subshell) )` written without the space is a command
# substitution whose contents WOULD run. Two guards, both fail-closed:
#   * `_arith_end` requires the matching `))` PAIR — `$((cmd) )` closes on a non-`)` and defers.
#   * a POSITIVE character whitelist, plus an explicit refusal of the four shapes that could hide
#     an executable inside the body (`$(`, a backtick, `${!` indirect expansion, and process
#     substitution). `split_segments` screens the last three on the OUTER command, and replacing
#     the body with a placeholder would otherwise hide them from it.
# Anything that fails either guard defers exactly as before, so this is strictly additive.
_ARITH_CHARS = re.compile(r"^[A-Za-z0-9_ \t+\-*/%()<>=!&|^~?:,.$\[\]{}]*$")
_ARITH_NEVER = ("$(", "`", "${!", "<(", ">(")


def _arith_end(cmd, i):
    """Index of the `)` closing an arithmetic `$((` at i, or None if it is not a `))` pair."""
    depth, j, n = 0, i + 1, len(cmd)
    while j < n:
        if cmd[j] == "(":
            depth += 1
        elif cmd[j] == ")":
            depth -= 1
            if depth == 0:
                return j if j > 0 and cmd[j - 1] == ")" else None
        j += 1
    return None


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
                end = _arith_end(cmd, i)
                if end is None:
                    return [], "", False  # not a `))` pair — may be `$( (subshell) )`
                body = cmd[i + 3 : end - 1]
                if any(t in body for t in _ARITH_NEVER) or not _ARITH_CHARS.match(body):
                    return [], "", False  # something could execute in there
                out.append(SUBST_PLACEHOLDER)  # arithmetic is DATA, and runs nothing
                i = end + 1
                continue
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
    # A comment runs nothing. Before 2026-09-10 `verb()` returned None for it and the segment
    # was refused as "not on the allowlist", so ONE `# …` line deferred an entire multi-line
    # command (162 occurrences over 114 structural rows in the archive). This is the same
    # "carries no command" class as the three returns above, and it is safe for the same reason
    # they are: `split_segments` has already cut on `;` and newlines, so any text a comment
    # would have swallowed in the real shell is still judged here as its own segment — this
    # file judges MORE than bash runs, never less. A command that is ONLY comments still
    # defers, because decide() requires judged > 0.
    if s.startswith("#"):
        return ""
    return s


def verb(seg):
    # `[` and `:` are real builtins whose NAMES are punctuation, so the identifier regex below
    # cannot match them: `verb()` returned None and allowed_segment's `v is None` arm deferred
    # the segment before any rule could look at it. They are named explicitly so they reach the
    # ordinary whitelist — and therefore also reach the REDIRECT check that sits above it, which
    # is the only thing standing between `:` and `: > file`. This is the one call site (886).
    tok = seg.split(" ", 1)[0]
    if tok in ("[", ":"):
        return tok
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


# ── write scope (operator ruling 2026-10-20, decision 29d62f1ad390) ──────────────────────
# The prompts this hook could not clear were dominated by WRITES the operator answers yes to
# every time — `cat > f`, `echo x >> log`, `cp a b`, `git add` — 14-day census in
# docs/research/permission-prompt-reduction-2026-10-20/REPORT.md. A write is admitted when its
# target is in one of two places, decided on the RESOLVED path:
#   · the project: the hook's cwd subtree, except `.git/` internals and the protected paths
#     above, and never when that cwd is $HOME or `/` (then "the project" would be everything);
#   · agent scratch: strictly under /private/tmp, outside the fleet's RESERVED top-level names
#     (the same list hooks/validate-bash.sh's SCRATCH-TEMP category uses — dot-files, cc-*,
#     claude-*, land-lock*, com.*, tmux-*, kitty-<digits>, launchd*, powerlog, Cursor-*), or
#     inside THIS session's own harness scratchpad.
# A RELATIVE target is resolved against every directory the command may be in when it runs —
# the hook's cwd plus each literal `cd` target — and must pass against ALL of them; a `cd` this
# cannot read literally makes every relative write undecidable. Before this, `cd /etc && sed -i
# … hosts` judged `hosts` against the hook's own cwd.
_SCRATCH_RESERVED = re.compile(
    r"^(\.|cc-|claude|land-lock|com\.|tmux-|kitty-[0-9]|launchd|powerlog|Cursor-)|\.sock$"
)
_SESSION_ID = None  # set by main() from the payload, for the own-scratchpad case
# Both set by decide() per command: the absolute dirs the command may run in (None when a `cd`
# is undecidable), and the fence prefixes, so the git arm re-checks a `git -C x push` form.
_CWD_CANDIDATES = None
_FENCE_CUR = None
_CD_RE = re.compile(r"(?:^|[;&|({\s])cd(?:[ \t]+([^;&|\s)]+))?(?=$|[;&|)\s])")


def _cwd_candidates(cmd):
    try:
        cands = [os.getcwd()]
    except OSError:
        return None
    if re.search(r"(^|[^\w-])(pushd|popd)(\s|$)", cmd):
        return None
    for m in _CD_RE.finditer(cmd):
        t = m.group(1)
        if not t:
            return None  # a bare `cd` goes to $HOME
        t = _unquote(t)
        if "$" in t:
            # `D=$(mktemp -d); cd $D` — a directory this command made (MKTEMP_CWD: everything
            # relative under it is new), or a single literal binding; anything else is undecidable.
            kind, t = _resolve_var_path(t)
            if kind == "mktemp":
                cands.append(MKTEMP_CWD)
                continue
            if kind is None:
                return None
        if t.startswith("~/"):
            t = os.path.expanduser(t)
        if not t.startswith("/") or any(c in t for c in "$`*?") or ".." in t:
            return None
        cands.append(t)
    return cands


MKTEMP_CWD = "\0mktemp-cwd"  # a cwd candidate that is a directory this command created


def _scratch_write_ok(real):
    if not real.startswith("/private/tmp/"):
        return False
    rest = real[len("/private/tmp/") :]
    top = rest.split("/", 1)[0]
    if not top or top in (".", ".."):
        return False
    if _SESSION_ID and re.fullmatch(r"[0-9a-fA-F-]{36}", _SESSION_ID):
        own = re.match(r"^claude-[0-9]+/[^/]+/%s/." % re.escape(_SESSION_ID), rest)
        if own:
            return True
    return not _SCRATCH_RESERVED.search(top)


def _in_write_scope(p):
    try:
        real = os.path.realpath(p)
        root = os.path.realpath(os.getcwd())
    except OSError:
        return False
    if _protected(real):
        return False
    home = os.path.realpath(os.path.expanduser("~"))
    if root not in ("/", home) and (
        real == root or real.startswith(root.rstrip("/") + "/")
    ):
        return not re.search(r"(^|/)\.git(/|$)", real[len(root) :])
    return _scratch_write_ok(real)


def write_target_ok(tok):
    """True when a file this command WRITES may be written without asking."""
    p = _unquote(tok)
    if p in ("/dev/null", "/dev/stdout", "/dev/stderr"):
        return True
    if "$" in p:
        # `"$D/out.txt"` — resolved from this command's own single binding of D (a literal path,
        # or a `$(mktemp -d)` it made); anything else stays a variable and is refused below.
        kind, p = _resolve_var_path(p)
        if kind == "mktemp":
            return True
        if kind is None:
            return False
    # A POSITIVE character class: `>(cmd)` (process substitution), a glob, a variable, `~` and
    # quoting tricks all fall outside it, so none of them can be read as a path.
    if not _PATH_CHARS.fullmatch(p or "") or ".." in p.split("/"):
        return False
    if _protected(p):
        return False
    if p.startswith("/"):
        return _in_write_scope(p)
    cands = _CWD_CANDIDATES
    if not cands:
        return False
    return all(c == MKTEMP_CWD or _in_write_scope(os.path.join(c, p)) for c in cands)


def redirect_targets(seg):
    """The file targets of every output redirect in the segment, or None when unparseable.

    Same quote-aware walk as redirects_to_file below; null/std streams and fd dups are omitted.
    """
    out, quote, i, n = [], None, 0, len(seg)
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
            while j < n and seg[j] in ">|":
                j += 1
            while j < n and seg[j] == " ":
                j += 1
            k = j
            if k < n and seg[k] in "'\"":
                q = seg[k]
                k = seg.find(q, k + 1)
                if k < 0:
                    return None
                k += 1
            else:
                while k < n and seg[k] not in " \t":
                    k += 1
            t = seg[j:k]
            if not t:
                return None
            if not _SAFE_REDIRECT_TARGET.match(t):
                out.append(t)
            i = k
            continue
        i += 1
    return out


def strip_redirects(seg):
    """The segment with every redirection operator and its target removed, quote-aware.

    Quote-aware for the same reason as the scanners: a `>` inside an awk program or a grep
    pattern is DATA and must survive, or `awk '{print > "f"}'` would lose its write form.
    """
    out, quote, i, n = [], None, 0, len(seg)
    while i < n:
        ch = seg[i]
        if quote:
            out.append(ch)
            if ch == quote:
                quote = None
            i += 1
            continue
        if ch in ("'", '"'):
            quote = ch
            out.append(ch)
            i += 1
            continue
        if ch == "\\":
            out.append(seg[i : i + 2])
            i += 2
            continue
        if ch in "<>" or (ch in "0123456789&" and i + 1 < n and seg[i + 1] == ">"):
            j = i + 1
            while j < n and seg[j] in "<>|&0123456789-":
                j += 1
            while j < n and seg[j] == " ":
                j += 1
            k = j
            if k < n and seg[k] in "'\"":
                e = seg.find(seg[k], k + 1)
                k = n if e < 0 else e + 1
            else:
                while k < n and seg[k] not in " \t":
                    k += 1
            # `2>&1`, `>&2`: the operator scan above already consumed the fd, nothing follows
            if seg[i:j].rstrip().endswith(("&1", "&2", "&-")) or (
                j > i and seg[j - 1] in "0123456789-" and "&" in seg[i:j]
            ):
                k = j
            out.append(" ")
            i = k
            continue
        out.append(ch)
        i += 1
    return " ".join("".join(out).split())


_PATH_CHARS = re.compile(r"[A-Za-z0-9_./@%+=:,-]+")


# ── rm inside a compound: the same scratch category as validate-bash.sh ──────────────────
# rm-safe-allowlist.sh (below) already admits a literal /tmp target; what it cannot see is the
# spelling agents actually write, `T=$(mktemp -d …) … rm -rf "$T"` or `D=/tmp/x; … rm -rf "$D"`.
# validate-bash.sh resolves those (SAME-COMMAND VARIABLE RESOLUTION, SELF-CREATED-TEMP) and, since
# 2026-10-20, permits agent scratch outside the reserved names; this is the matching ALLOW, so the
# deletion it no longer asks about is not handed to the classifier instead. validate-bash's own
# verdict still applies on top — its ask outranks this allow.
_CMD_ORIG = (
    None  # set by decide(): the heredoc-free command before substitution extraction
)
_DEEP_ARTIFACT = re.compile(
    r"(^|/)(__pycache__|node_modules|\.next|\.turbo|\.pytest_cache|\.mypy_cache|\.ruff_cache"
    r"|\.tox|htmlcov)(/|$)"
)
_MKTEMP_DIR_SUBST = re.compile(
    r"^\$\(\s*(?:/usr/bin/)?mktemp\s+(?:-[a-zA-Z]*d[a-zA-Z]*|--directory)(?:\s+[^;&|$`()\s]+)*\s*\)$"
)


def _assigned_value(name):
    """The one value this command binds NAME to, or None when it binds it zero or several ways."""
    text = _CMD_ORIG or ""
    vals = re.findall(
        r"(?:^|[\s;&|(])%s=(\"\$\([^()]*\)\"|\$\([^()]*\)|\"[^\"]*\"|'[^']*'|[^\s;&|]*)"
        % re.escape(name),
        text,
    )
    if len(set(vals)) != 1:
        return None
    if re.search(
        r"\b(read|mapfile|readarray)\b[^;&|\n]*\b%s\b|\bfor\s+%s\s+in\b|\b%s\+="
        % ((re.escape(name),) * 3),
        text,
    ):
        return None  # bound out of sight as well
    return vals[0]


def _has_socket(path, depth=4):
    import stat

    base = path.rstrip("/").count("/")
    for root, dirs, files in os.walk(path):
        if root.count("/") - base >= depth:
            dirs[:] = []
        for f in files + dirs:
            try:
                if stat.S_ISSOCK(os.lstat(os.path.join(root, f)).st_mode):
                    return True
            except OSError:
                continue
    return False


def _resolve_var_path(t):
    """("mktemp", None) for a path under a dir this command's `$(mktemp -d)` made; ("path", p)
    for `$NAME[/rest]` bound once to a literal; (None, None) when the binding is undecidable.
    A token without a leading variable comes back unchanged as ("path", t)."""
    m = re.fullmatch(
        r"\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?((?:/[A-Za-z0-9_.@%+=:,-]+)*)/?", t
    )
    if not m:
        return ("path", t) if "$" not in t else (None, None)
    v = _assigned_value(m.group(1))
    if v is None or ".." in m.group(2).split("/"):
        return None, None
    vv = v[1:-1] if len(v) >= 2 and v[0] == v[-1] == '"' else v
    if _MKTEMP_DIR_SUBST.match(vv):
        return (
            "mktemp",
            None,
        )  # a directory THIS command created, wherever mktemp put it
    if v.startswith("'") or "$" in vv or "`" in vv:
        return None, None
    return "path", _unquote(v) + m.group(2)


def _rm_scratch_target(tok):
    kind, t = _resolve_var_path(tok)
    if kind == "mktemp":
        return True
    if kind is None:
        return False
    if not _PATH_CHARS.fullmatch(t or "") or ".." in t.split("/"):
        return False
    if not t.startswith("/") and _DEEP_ARTIFACT.search(t):
        return True
    if t.startswith("/"):
        cands = [t]
    elif _CWD_CANDIDATES:
        cands = [os.path.join(c, t) for c in _CWD_CANDIDATES if c != MKTEMP_CWD]
    else:
        return False
    for c in cands:
        real = os.path.realpath(c)
        if not _scratch_write_ok(real):
            return False
        if os.path.isdir(real) and _has_socket(real):
            return False
    return True


def _rm_scratch_segment(seg):
    # The rm hook's kill switch disarms this extension of it as well (smart-bash-allowlist-compound
    # "rm is DELEGATED"): disarming the owner must not leave a second path that still allows.
    if os.environ.get("RM_SAFE_ALLOWLIST_DISABLED") == "1":
        return None
    argv = _argv(seg)
    if not argv:
        return None
    targets = []
    for a in argv[1:]:
        if a == "--" or a in ("--recursive", "--force", "--verbose", "--dir"):
            continue
        if a.startswith("-"):
            if not re.fullmatch(r"-[rfRdv]+", a):
                return None
            continue
        targets.append(a)
    if targets and all(_rm_scratch_target(t) for t in targets):
        return "rm: agent scratch target(s), resolved"
    return None


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
}
# --resolve is deliberately NOT cleared (2026-09-29): it sends the connection to an address of its
# own choosing, so the URL host this arm vets is not the machine curl talks to. It defers to the
# normal permission flow; it was 2 commands in the whole archive.
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


# ── 2026-10-20 widening: wrappers, local git, scoped writes, inert builtins ───────────────
# Census and evidence counts: docs/research/permission-prompt-reduction-2026-10-20/REPORT.md.
# Every arm is a POSITIVE grammar: an unrecognised flag, a variable where a path must be, or a
# form that executes something (`rebase -x`, `clone ext::`, `-c core.*`, `push --receive-pack`)
# defers to the normal permission flow exactly as before.
WRAPPERS = {"timeout", "time", "nice", "nohup", "taskpolicy"}
_DURATION = re.compile(r"^[0-9]+(\.[0-9]+)?[smhd]?$")


def _unwrap(v, p):
    """The wrapped command's argv for a WRAPPERS verb, or None when the grammar is not plain."""
    i = 1
    if v == "timeout":
        while i < len(p) and p[i].startswith("-"):
            if p[i] in ("-s", "-k", "--signal", "--kill-after") and i + 1 < len(p):
                i += 2
            elif p[i] in ("--foreground", "--preserve-status", "-v", "--verbose") or p[
                i
            ].startswith(("--signal=", "--kill-after=")):
                i += 1
            else:
                return None
        if i >= len(p) or not _DURATION.match(p[i]):
            return None
        i += 1
    elif v == "time":
        if i < len(p) and p[i] == "-p":
            i += 1
    elif v == "nice":
        if i + 1 < len(p) and p[i] == "-n":
            i += 2
        elif i < len(p) and re.match(r"^-[0-9]+$", p[i]):
            i += 1
    elif v == "taskpolicy":
        while i < len(p) and p[i].startswith("-"):
            if p[i] in ("-c", "-p", "-t", "-l") and i + 1 < len(p):
                i += 2
            elif p[i] in ("-b", "-B", "-d", "-g", "-a"):
                i += 1
            else:
                return None
    rest = p[i:]
    return rest or None


def _argv(seg):
    """The segment's argv WITHOUT its redirections. Every file a redirect writes was judged at the
    top of allowed_segment; what is left (`2>&1`, `>/dev/null`) is not an argument, and leaving it
    in made `git push origin HEAD:main 2>&1` read `2>&1` as a refspec (175 refused segments)."""
    try:
        return shlex.split(strip_redirects(seg), posix=True)
    except ValueError:
        return None


_GIT_SAFE_CONFIG = re.compile(
    r"^(user\.(name|email)|commit\.gpgsign|tag\.gpgsign|init\.defaultbranch|advice\.[a-z.]+"
    r"|color\.[a-z.]+|protocol\.file\.allow|pull\.(rebase|ff)|rerere\.enabled"
    r"|merge\.conflictstyle|safe\.directory|gc\.auto|maintenance\.auto)$",
    re.I,
)
_GIT_REF = re.compile(r"^[A-Za-z0-9_./@{}^~-]+$")
GIT_READ_EXTRA = {
    "cherry",
    "ls-remote",
    "range-diff",
    "show-ref",
    "show-branch",
    "fsck",
}
# Local history operations. Every one leaves the previous state reachable through the reflog
# or the working tree, which is why the operator answers yes to them; the lossy forms of
# reset/restore are decided by hooks/validate-bash.sh's GIT-OWNERSHIP block, whose `ask`
# outranks this allow (hook decisions merge deny > ask > allow).
GIT_LOCAL_WRITE = {
    "add",
    "commit",
    "switch",
    "rebase",
    "merge",
    "cherry-pick",
    "revert",
    "stash",
    "clone",
    "init",
    "worktree",
    "pull",
    "tag",
    "branch",
    "mv",
    "rm",
    "notes",
    "apply",
    "am",
    "config",
    "reset",
    "restore",
    "checkout",
    "push",
}
_PUSH_FLAGS = {
    "-q",
    "--quiet",
    "-u",
    "--set-upstream",
    "--porcelain",
    "-v",
    "--verbose",
    "--tags",
    "--follow-tags",
    "--atomic",
    "--no-progress",
    "--progress",
    "-n",
    "--dry-run",
}


def _git_norm(argv):
    """(sub, args) after peeling the harmless global options, or None when one re-aims git."""
    i = 1
    while i < len(argv) and argv[i].startswith("-"):
        t = argv[i]
        if t == "-C" and i + 1 < len(argv):
            # Which repo a LOCAL history operation runs in does not change what it can do, so a
            # variable dir (`git -C "$W"`) is fine here; one argv token, nothing that executes.
            d = argv[i + 1]
            if not d or "`" in d or "$(" in d:
                return None
            i += 2
        elif t == "-c" and i + 1 < len(argv):
            if not _GIT_SAFE_CONFIG.match(argv[i + 1].split("=", 1)[0]):
                return None  # core.pager / core.hooksPath / alias.* run programs
            i += 2
        elif t in ("--no-pager", "-P", "--no-optional-locks", "--literal-pathspecs"):
            i += 1
        elif t in ("--version", "--help"):
            # `git --version`: read-only, judged as the `version` subcommand
            return "version", []
        else:
            return None  # --git-dir, --work-tree, --exec-path … re-aim or execute
    if i >= len(argv):
        return None
    return argv[i], argv[i + 1 :]


def _push_ok(args):
    words = []
    for a in args:
        if a.startswith("-"):
            if a not in _PUSH_FLAGS:
                return False  # --force*, -f, --mirror, --delete, --prune, --receive-pack, --exec
            continue
        words.append(a)
    if not words:
        return True
    remote = words[0]
    if "::" in remote or not _PATH_CHARS.fullmatch(remote):
        return False
    for r in words[1:]:
        if r.startswith(("+", ":")) or not _GIT_REF.fullmatch(r.replace(":", "")):
            return False
    return True


def _git_sub_ok(sub, args):
    flags = [a for a in args if a.startswith("-")]
    words = [a for a in args if not a.startswith("-")]
    if sub == "push":
        return _push_ok(args)
    if sub == "add":
        return not any(
            f in ("-f", "--force") or re.fullmatch(r"-[A-Za-z]*f[A-Za-z]*", f)
            for f in flags
        )
    if sub == "commit":
        return True  # --no-verify is refused by DANGER on the whole command
    if sub == "switch":
        return not any(f in ("-f", "--force", "--discard-changes") for f in flags)
    if sub == "checkout":
        # `checkout <x>` may be a PATH and discard its changes; only the branch-making forms pass.
        return (
            any(f in ("-b", "-B", "--detach", "--orphan") for f in flags)
            and "--" not in args
        )
    if sub == "rebase":
        return not any(
            f in ("-x", "--exec", "-i", "--interactive")
            or f.startswith(("--exec=", "-x"))
            for f in flags
        )
    if sub == "merge":
        return not any(
            f in ("-s", "--strategy") or f.startswith("--strategy=") for f in flags
        )
    if sub == "stash":
        # drop is decided by validate-bash (a tag-selected entry only); pop and clear never pass
        return not words or words[0] in (
            "push",
            "save",
            "list",
            "show",
            "apply",
            "create",
            "drop",
        )
    if sub == "clone":
        if any(
            f
            in (
                "-c",
                "--config",
                "-u",
                "--upload-pack",
                "--template",
                "--separate-git-dir",
            )
            or f.startswith(
                ("--config=", "--upload-pack=", "--template=", "--separate-git-dir=")
            )
            for f in flags
        ):
            return False
        if not words or "::" in words[0]:
            return False  # ext:: and other transport helpers run programs
        return len(words) < 2 or _new_dir_ok(words[-1])
    if sub == "init":
        return all(_new_dir_ok(w) for w in words)
    if sub == "worktree":
        if not words:
            return False
        if words[0] == "add":
            return not any(f in ("-f", "--force") for f in flags)
        if words[0] == "remove":
            return not any(f in ("-f", "--force") for f in flags)
        return words[0] in ("list", "prune", "lock", "unlock", "repair", "move")
    if sub == "rm":
        return "--cached" in flags or not any(f in ("-f", "--force") for f in flags)
    if sub == "config":
        if any(f in ("--global", "--system", "--file", "-f", "--blob") for f in flags):
            return False
        if any(
            f in ("--get", "--get-all", "--get-regexp", "--list", "-l") for f in flags
        ):
            return True
        return bool(words) and bool(_GIT_SAFE_CONFIG.match(words[0]))
    return True  # pull, tag, branch, notes, apply, am, cherry-pick, revert, mv, reset, restore


def _git_segment(seg):
    argv = _argv(seg)
    if not argv:
        return None
    g = _git_norm(argv)
    if g is None:
        return None
    sub, args = g
    canon = " ".join(["git", sub] + args)
    if _FENCE_CUR and crosses_fence(canon, _FENCE_CUR):
        return None  # `git -C x push` must meet the same fence `git push` does
    if sub in GIT_READ or sub in GIT_READ_EXTRA:
        guard = GIT_SUBCOMMAND_READ_ONLY.get(sub)
        if guard is None or guard.match(" ".join(args)):
            return f"git {sub}: read-only"
        if sub not in GIT_LOCAL_WRITE and sub not in (
            "branch",
            "tag",
            "stash",
            "worktree",
        ):
            return None
    if sub in GIT_LOCAL_WRITE or sub in ("branch", "tag", "stash", "worktree"):
        if _git_sub_ok(sub, args):
            return f"git {sub}: local history operation (reflog-recoverable)"
    return None


_SECRET_SOURCE = re.compile(
    r"(^|/)\.(ssh|aws|gnupg|netrc|docker|kube|config/gh)(/|$)|(^|/)id_[a-z0-9]+$|\.pem$|\.p12$"
    r"|(^|/)\.env($|\.)|keychain|(^|/)credentials(\.json)?$|\.claude[^/]*/\.credentials"
)
_INERT_BUILTINS = {
    "read",
    "continue",
    "break",
    "exit",
    "return",
    "shift",
    "wait",
    "umask",
    "unset",
}
READ_ONLY_EXTRA = {
    "uptime",
    "shellcheck",
    "nproc",
    "getconf",
    "vm_stat",
    "sha256sum",
    "ioreg",
}


def _new_dir_ok(tok):
    """A clone/init destination: in the write scope, or a path that does not exist yet under
    ~/Development (a NEW directory — git refuses a non-empty existing one, so nothing is lost)."""
    if write_target_ok(tok):
        return True
    kind, p = _resolve_var_path(_unquote(tok))
    if kind == "mktemp":
        return True
    if (
        kind is None
        or not _PATH_CHARS.fullmatch((p or "").lstrip("~"))
        or ".." in p.split("/")
    ):
        return False
    p = os.path.expanduser(p)
    dev = os.path.realpath(os.path.expanduser("~/Development")) + "/"
    return (
        os.path.isabs(p)
        and not os.path.exists(p)
        and os.path.realpath(p).startswith(dev)
    )


_TAR_LETTERS = set("cxtvzjJfpkCOPa")


def _archive_segment(v, seg):
    """tar / unzip / split, with every file they WRITE inside the write scope."""
    argv = _argv(seg)
    if not argv:
        return None
    a = argv[1:]
    if v == "unzip":
        dest, i = ".", 0
        while i < len(a):
            if a[i] == "-d" and i + 1 < len(a):
                dest, i = a[i + 1], i + 2
            elif a[i] in (
                "-q",
                "-qq",
                "-o",
                "-n",
                "-j",
                "-l",
                "-t",
                "-v",
                "-oq",
                "-qo",
            ):
                i += 1
            elif a[i].startswith("-"):
                return None
            else:
                i += 1
        return (
            "unzip: extracts into the project or agent scratch"
            if write_target_ok(dest)
            else None
        )
    if v == "split":
        words, i = [], 0
        while i < len(a):
            if a[i] in ("-l", "-b", "-n", "-a") and i + 1 < len(a):
                i += 2
            elif a[i] in ("-d",) or re.fullmatch(r"-[0-9]+", a[i]):
                i += 1
            elif a[i].startswith("-"):
                return None
            else:
                words.append(a[i])
                i += 1
        ok = len(words) == 2 and write_target_ok(words[1] + "x")
        return "split: pieces under the project or agent scratch" if ok else None
    # tar: one leading mode bundle (with or without `-`), then -C/-f with values and paths.
    if not a:
        return None
    mode = a[0].lstrip("-")
    if not mode or set(mode) - _TAR_LETTERS or len(set(mode) & set("cxt")) != 1:
        return None
    rest, archive, dest, i = a[1:], None, ".", 0
    if "f" in mode and rest:
        archive, rest = rest[0], rest[1:]
    while i < len(rest):
        t = rest[i]
        if t in ("-C", "--directory") and i + 1 < len(rest):
            dest, i = rest[i + 1], i + 2
        elif t == "-f" and i + 1 < len(rest):
            archive, i = rest[i + 1], i + 2
        elif re.fullmatch(r"--strip-components=[0-9]+|-v|-z|-p|--exclude=[^ ]+", t):
            i += 1
        elif t.startswith("-"):
            return None  # -I / --use-compress-program / --to-command / --checkpoint-action …
        else:
            i += 1
    if "c" in mode:
        ok = archive is not None and write_target_ok(archive)
    elif "x" in mode:
        ok = write_target_ok(dest)
    else:
        ok = True  # t: lists only
    return "tar: writes under the project or agent scratch" if ok else None


def _write_verb_segment(v, seg):
    """Reason, None (defer), or False when this verb is not one of the scoped write verbs."""
    if v in _INERT_BUILTINS:
        return f"{v}: shell builtin, runs nothing"
    if v in READ_ONLY_EXTRA:
        return f"{v}: read-only, no redirect"
    if v == "command":
        a = seg.split()
        return (
            "command -v: lookup only" if len(a) >= 2 and a[1] in ("-v", "-V") else None
        )
    if v in ("local", "declare", "typeset"):
        a = seg.split()
        if any(x in ("-f", "-F") for x in a[1:]):
            return "declare -f: lists functions"
        return (
            f"{v}: variable declaration"
            if all(
                re.match(r"^(-[a-zA-Z]+|[A-Za-z_][A-Za-z0-9_]*(=.*)?)$", x)
                for x in a[1:]
            )
            else None
        )
    if v in ("tar", "unzip", "split"):
        return _archive_segment(v, seg)
    if v not in ("tee", "cp", "mv", "touch", "mktemp", "ln"):
        return False
    argv = _argv(seg)
    if not argv:
        return None
    flags = [a for a in argv[1:] if a.startswith("-")]
    words = [a for a in argv[1:] if not a.startswith("-")]
    if v == "tee":
        if any(f not in ("-a", "--append", "-i") for f in flags):
            return None
        return (
            "tee: files under the project or agent scratch"
            if all(write_target_ok(w) for w in words)
            else None
        )
    if v == "touch":
        if flags or not words:
            return None
        return (
            "touch: files under the project or agent scratch"
            if all(write_target_ok(w) for w in words)
            else None
        )
    if v == "mktemp":
        if any(not re.fullmatch(r"-[dqut]+", f) for f in flags) or len(words) > 1:
            return None
        if "-t" in "".join(flags):
            return None  # -t takes a prefix in TMPDIR; rare, keep it out
        return (
            "mktemp: creates a NEW unique file or directory"
            if (not words or write_target_ok(words[0]))
            else None
        )
    if v == "ln":
        if any(
            f not in ("-s", "-f", "-n", "-sf", "-sfn", "-snf", "-fs", "-h")
            for f in flags
        ):
            return None
        return (
            "ln: link created under the project or agent scratch"
            if (len(words) == 2 and write_target_ok(words[-1]))
            else None
        )
    ok_flags = {
        "-r",
        "-R",
        "-p",
        "-f",
        "-a",
        "-n",
        "-v",
        "-X",
        "-L",
        "-P",
        "-H",
        "-rf",
        "-Rf",
        "-fR",
        "-fr",
        "-rp",
        "-Rp",
        "-pR",
        "-av",
        "-rv",
        "-Rv",
    }
    if any(f not in ok_flags for f in flags) or len(words) < 2:
        return None
    if v == "cp":
        srcs, dst = words[:-1], words[-1]
        resolved = []
        for s in srcs:
            kind, r = _resolve_var_path(s) if "$" in s else ("path", s)
            if kind is None or "`" in s:
                return None
            resolved.append(r or "")
        if any(_SECRET_SOURCE.search(s) or _protected(s) for s in resolved):
            return None
        return (
            "cp: destination under the project or agent scratch"
            if write_target_ok(dst)
            else None
        )
    # mv REMOVES its sources, so every path it names must be in scope.
    return (
        "mv: source and destination under the project or agent scratch"
        if all(write_target_ok(w) for w in words)
        else None
    )


def allowed_segment(seg, sole=False):
    """The positive whitelist. Returns a reason string, or None to defer.

    Every entry judges a SINGLE segment; the caller requires all of them to pass. Nothing
    here may admit a command by its prefix alone — that is precisely the defect this file
    replaces.
    """
    v = verb(seg)
    if v is None:
        # `done < list` leaves a segment that is only an INPUT redirect: it reads a file and runs
        # nothing. Anything else left after the redirects are removed is judged as usual.
        if seg.lstrip().startswith("<") and not redirects_to_file(seg):
            rest = strip_redirects(seg)
            return (
                allowed_segment(rest, sole) if rest else "input redirect: reads a file"
            )
        return None

    # Redirect targets are judged FIRST, for every arm below. A redirect into the project or agent
    # scratch is a write the operator always allows (write scope, above); anything else defers.
    # The verb is then judged with its redirects removed. Before 2026-10-20 the git-commit, sed
    # and chmod arms returned ahead of the redirect scanner, so `git commit -m x > anywhere`
    # was admitted with its redirect unexamined.
    if redirects_to_file(seg):
        targets = redirect_targets(seg)
        if targets is None or not all(write_target_ok(t) for t in targets):
            return None
        inner = allowed_segment(strip_redirects(seg), sole)
        return (
            None
            if inner is None
            else inner + "; redirect into the project or agent scratch"
        )

    # A wrapper that only changes HOW a command runs (a time limit, a priority, a QoS clamp)
    # is judged by the command it runs. They sit in DISPATCHERS for the general case; these
    # five have a fixed argv grammar, so the wrapped command is recoverable exactly.
    if v in WRAPPERS:
        inner = _unwrap(v, seg.split())
        if not inner:
            return None
        r = allowed_segment(" ".join(inner), sole)
        return None if r is None else f"{v} → {r}"

    if v in DISPATCHERS:
        return None  # something else chooses the real command — never decide

    # A substitution standing in the VERB position is genuine indirection: the machine will
    # execute whatever text the substitution produced. Judging the inner command does not
    # help — `$(which foo) --flags` runs `foo`, not `which`. In ARGUMENT position the same
    # placeholder is only data, which is why this is checked on the verb alone.
    if v == SUBST_PLACEHOLDER or v.startswith(SUBST_PLACEHOLDER):
        return None

    parts = seg.split()

    if v == "git":
        return _git_segment(seg)

    r = _write_verb_segment(v, seg)
    if r is not False:
        return r

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
        return _rm_hook_allows(seg) or _rm_scratch_segment(seg)

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
                # A URL to cloud metadata or a private network (in any spelling: decimal, hex,
                # IPv4-mapped, nip.io, …) defers — not denied, because a LAN read like the router
                # admin page is legitimate outside reso; the classifier decides.
                if _ssrf is None:
                    return None
                try:
                    host = urlparse(_unquote(tok)).hostname
                except ValueError:
                    return None
                if _ssrf.is_internal_host(host):
                    return None
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

    # `[` IS `test` and `:` IS `true` — both spellings of entries already in READ_ONLY, which
    # held only the word-shaped halves. `[ -f x ]` was refused while `test -f x` was allowed:
    # one operator-visible inconsistency, 133 occurrences over 102 structural rows. Neither can
    # write: the redirect scanner above has already refused `: > file`, which is the one way a
    # no-op touches the filesystem. `[` must close with `]`, or it is not the builtin at all.
    if v == "[":
        if parts[-1] != "]":
            return None
        return "[: test builtin, read-only, no redirect"
    if v == ":":
        return ": no-op builtin, read-only, no redirect"
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
    if _depth == 0:
        # Per-command context for the write-scope and git arms. Module globals rather than
        # parameters so allowed_segment keeps its signature (tests/sba-mutate.py drives it).
        global _CWD_CANDIDATES, _FENCE_CUR, _CMD_ORIG
        _CMD_ORIG = cmd  # first: the cwd candidates resolve `cd $D` through it
        _CWD_CANDIDATES = _cwd_candidates(cmd)
        _FENCE_CUR = fence

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
    # normalize() peels leading `VAR=` assignments, so an env proxy or a relocated curlrc on a curl
    # command would be invisible to the curl arm. Either one moves where curl connects: defer.
    if any(verb(s) == "curl" for s in judgeable) and (
        _ssrf is None
        or _ssrf.ENV_PROXY_RE.search(cmd)
        or _ssrf.ENV_CURLRC_RE.search(cmd)
    ):
        return None, "curl with a proxy or curlrc environment override"
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
    global _SESSION_ID
    if isinstance(payload, dict):
        sid = payload.get("session_id")
        _SESSION_ID = sid if isinstance(sid, str) else None
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
