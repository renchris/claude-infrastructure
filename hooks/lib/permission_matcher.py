#!/usr/bin/env python3
"""The ONE state model for Claude Code's Bash permission matcher, shared by every tool here.

WHY THIS FILE EXISTS. `bin/cc-permission-audit` grew a private matcher; `bin/cc-permission-harvest`
needs one too. Two tools with two matchers over one population disagree about that population, and
the disagreement is invisible because each is internally consistent — the failure recorded as
`sibling-auditors-must-share-the-state-model` (two checks over ONE population disagreed; only one
modelled "unlinked BY DESIGN"). So the matcher lives here once, and both tools import it.

WHAT IT MODELS. A faithful port of CC 2.1.220's Bash evaluator as decompiled and probed in
`docs/research/permission-matcher-truth-2026-08-20.md` (`ALs` the matcher, `OTo` the rule parser,
`MT` the splitter, `iae` the normaliser, `pme`/`gsn`/`_sn` the auto-mode drop). Every claim below
cites the section it came from, because this file is a claim about a SPECIFIC BUILD and can go
stale in a way ordinary code cannot. When it does, the fix is to re-probe that build and edit here
— not to add a second opinion in a caller.

THE FAILURE THIS PREVENTS, concretely. `docs/research/permission-prompts-2026-08-23.md` §3: nine of
nine allowlist proposals derived by ad-hoc string matching were refuted by an adversarial verifier,
counts inflated 2x-174x, two of them granting arbitrary code execution. Every one of those errors is
a place where the ad-hoc matcher was more permissive than `ALs`. The gates at the bottom of this file
(`ace_reason`, `arg_exec_reason`, `flag_head`, `shell_keyword`, `hook_owner`, `auto_mode_dropped`)
are that refutation made mechanical, transcribed from `docs/plans/PERMISSION_HARVEST.md` §3.2.

IMPORT-SAFE BY CONSTRUCTION: no I/O, no environment reads, no logging at import. `--selftest` under
`__main__` is the only executable entry point.

FIDELITY BOUNDARY — read this before trusting a verdict:
  * The built-in read-only command set (`is_builtin_readonly`) is SAMPLED, not enumerated, so it is
    INFORMATIONAL ONLY and no decision path here consults it. A caller that wants to subtract it
    does so explicitly.
  * The auto-mode drop predicate is code-and-doc verified and NOT probe-verified (the truth doc
    flags it as the one load-bearing claim resting on two non-probe sources).
  * Heredocs and `bash -c` were not probed; both are treated as structural, the conservative side.
"""

from __future__ import annotations

import calendar
import collections
import glob as _glob
import hashlib
import gzip
import json
import os
import re
import sys
import time

# ─────────────────────────────── shapes ────────────────────────────────────
# namedtuples, not dataclasses: 3.9-compatible without ceremony, and a caller that unpacks
# positionally still works if a field is appended.

_RuleBase = collections.namedtuple("Rule", "tool kind content head")


class Rule(_RuleBase):
    """The §4 four-field shape exactly. `raw` is the rule string re-assembled from those fields —
    a property, not a fifth field, so a caller that unpacks `tool, kind, content, head = rule`
    keeps working and two parses of the same rule compare equal."""
    __slots__ = ()

    @property
    def raw(self):
        return self.tool if self.content is None else "%s(%s)" % (self.tool, self.content)


Decomposition = collections.namedtuple("Decomposition", "kind leaves structural too_long")
Verdict = collections.namedtuple("Verdict", "outcome uncovered structural matched")
# by_file: OrderedDict path -> {"allow": [...], "deny": [...], "ask": [...],
#                                "classify_all_shell": bool}   (the F10 flag rides the file entry,
# because it is a fact about a FILE and the §4 shape has no sixth field for it — see
# `files_with_classify_all_shell`).
RuleSet = collections.namedtuple("RuleSet", "allow deny ask by_file dropped")

_RULE_KINDS = ("bare", "exact", "prefix", "wildcard")

# ─────────────────────────── §1 the rule parser (`OTo`) ─────────────────────
# `mtn` = /^(.+):\*$/ -> prefix.  `tCs` = an unescaped `*` anywhere else -> wildcard.
# Everything else is an exact literal. The TYPE comes from the rule string, never from the tool.
RULE_RE = re.compile(r"^([A-Za-z_][A-Za-z0-9_.-]*)\((.*)\)$", re.S)
_PREFIX_RE = re.compile(r"^(.+):\*$", re.S)
WILDCARD = re.compile(r"[*?\[\]]")          # used by dead_entries; NOT the rule-kind test


def _has_unescaped_star(s):
    """True iff some `*` has an even number of preceding backslashes (`tCs`)."""
    i = 0
    while True:
        i = s.find("*", i)
        if i < 0:
            return False
        back = 0
        j = i - 1
        while j >= 0 and s[j] == "\\":
            back += 1
            j -= 1
        if back % 2 == 0:
            return True
        i += 1


def parse_rule(rule):
    """Rule(tool, kind, content, head, raw) or None when the string is not a rule at all.

    kind is one of bare|exact|prefix|wildcard. `content` is None for a bare tool name — `$fe`
    filters `ruleContent===undefined` out of the content matchers entirely, so a bare name is
    matched at the TOOL level and skips every specifier test (§6 F16, and the reason `Bash(*)` is
    documented as equivalent to bare `Bash`).

    `head` is the literal command prefix the rule names, whitespace-collapsed, with a trailing
    `:*` / ` *` / `*` removed — "" when the rule names no command at all. It is what the §3.2
    gates take, so a caller never re-derives it.
    """
    if not isinstance(rule, str):
        return None
    m = RULE_RE.match(rule.strip())
    if not m:
        bare = rule.strip()
        if not bare or not re.match(r"^[A-Za-z_][A-Za-z0-9_.-]*$", bare):
            return None
        return Rule(bare, "bare", None, "")
    tool, content = m.group(1), m.group(2)
    pm = _PREFIX_RE.match(content)
    if pm is not None:
        return Rule(tool, "prefix", content, _rule_head(pm.group(1)))
    if _has_unescaped_star(content):
        return Rule(tool, "wildcard", content, _rule_head(content))
    return Rule(tool, "exact", content, _rule_head(content))


def _rule_head(content):
    s = " ".join(content.split())
    while s.endswith("*") or s.endswith(":"):
        s = s[:-1].rstrip()
    return s


# ───────────────── §1 normalisation (`iae`) + the env allowlist (`qsn`) ─────────────────
# TRANSCRIBED VERBATIM from the truth doc §1. The doc's prose calls this "a 38-name allowlist" and
# then enumerates 39 names; the ENUMERATION is what `qsn` holds, so the enumeration is what is
# copied here. (PERMISSION_HARVEST.md §4 records the same correction.) An entry added or removed
# upstream changes which commands an ALLOW rule can see past — it is not cosmetic.
ENV_ALLOWLIST = frozenset((
    "GOEXPERIMENT", "GOOS", "GOARCH", "CGO_ENABLED", "GO111MODULE",
    "RUST_BACKTRACE", "RUST_LOG", "NODE_ENV",
    "PYTHONUNBUFFERED", "PYTHONDONTWRITEBYTECODE",
    "PYTEST_DISABLE_PLUGIN_AUTOLOAD", "PYTEST_DEBUG", "ANTHROPIC_API_KEY",
    "LANG", "LANGUAGE", "LC_ALL", "LC_CTYPE", "LC_TIME", "CHARSET",
    "TERM", "COLORTERM", "NO_COLOR", "FORCE_COLOR", "TZ",
    "LS_COLORS", "LSCOLORS", "GREP_COLOR", "GREP_COLORS", "GCC_COLORS",
    "TIME_STYLE", "BLOCK_SIZE", "BLOCKSIZE", "COLUMNS", "LINES",
    "CLICOLOR", "CLICOLOR_FORCE", "CI", "DEBIAN_FRONTEND", "GIT_TERMINAL_PROMPT",
))

# `iae` step 3. NOT wrappers, and the distinction is the whole of footgun F12: `env`, `xargs -n1`,
# `watch`, `setsid`, `ionice`, `flock`, `sudo`, `npx`, `docker exec`, `devbox run`, `mise exec`,
# `direnv exec` are ENVIRONMENT RUNNERS — they approve whatever follows and are left in place so a
# rule head that names one is visible to `ace_reason`.
WRAPPERS = frozenset(("timeout", "time", "nice", "stdbuf", "nohup", "command", "builtin", "noglob"))

_ENV_ASSIGN = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*)=(\"[^\"]*\"|'[^']*'|\S*)\s+(.*)$", re.S)
_ONLY_ASSIGNMENTS = re.compile(r"^(?:[A-Za-z_][A-Za-z0-9_]*=(?:\"[^\"]*\"|'[^']*'|\S*)\s*)+$")
_TIMEOUT_DURATION = re.compile(r"^[0-9]+(?:\.[0-9]+)?[smhd]?$")
_INERT_TARGETS = frozenset(("/dev/null", "/dev/stdout", "/dev/stderr"))


def _strip_comment_lines(text):
    """`Sko`: drop any LINE whose trimmed form starts with `#`.

    Line-scoped, deliberately: a TRAILING `# note` is left in place because `iae` leaves it there
    too. The probe row `/bin/date +%s # hello` still ALLOWs under `Bash(/bin/date:*)` — not because
    the comment was stripped here, but because prefix matching only reads the head. The splitter
    (`split_leaves`) drops trailing comments, because `MT` skips tree-sitter comment NODES; these
    are two different mechanisms and collapsing them would over-strip in `rule_matches_leaf`.
    """
    if "#" not in text:
        return text
    keep = [ln for ln in text.split("\n") if not ln.strip().startswith("#")]
    return "\n".join(keep)


def _read_token(s, i):
    """(token, next_index) — one quote-aware word starting at i."""
    out, n, quote = [], len(s), None
    while i < n:
        ch = s[i]
        if quote:
            if ch == quote:
                quote = None
            else:
                out.append(ch)
            i += 1
            continue
        if ch in ("'", '"'):
            quote = ch
            i += 1
            continue
        if ch in " \t\n" or ch in "&|;<>":
            break
        if ch == "\\" and i + 1 < n:
            out.append(s[i + 1])
            i += 2
            continue
        out.append(ch)
        i += 1
    return "".join(out), i


def _strip_redirections(text, inert_only):
    """Remove redirection clauses. inert_only ⇒ only `2>&1`-style fd dups and `/dev/null` targets.

    The full form is `k$e(...).commandWithoutRedirections`, one of the candidate strings `ALs`
    tries. The inert form is what `normalize_leaf` applies, because a `/dev/null` redirect is
    documented-exempt from the structural gate and must not stop a leaf matching its rule.
    """
    if ">" not in text and "<" not in text:
        return text
    out, i, n, quote = [], 0, len(text), None
    while i < n:
        ch = text[i]
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
        if ch == "\\" and i + 1 < n:
            out.append(ch)
            out.append(text[i + 1])
            i += 2
            continue
        if ch in "<>":
            start = i
            # an optional leading fd digit already sits in `out`
            fd = ""
            while out and out[-1].isdigit():
                fd = out.pop() + fd
            op, j = _redir_op(text, i)
            k = j
            while k < n and text[k] in " \t":
                k += 1
            target, k2 = _read_token(text, k)
            if inert_only and not _redir_is_inert(op, target):
                out.append(fd)
                out.append(text[start:k2])
            i = k2
            continue
        out.append(ch)
        i += 1
    return " ".join("".join(out).split()) if not inert_only else "".join(out)


def _redir_op(text, i):
    for op in (">>", ">&", ">|", "<<<", "<<", "<&", ">", "<"):
        if text.startswith(op, i):
            return op, i + len(op)
    return text[i], i + 1


def _redir_is_inert(op, target):
    """`2>&1` / `>&2` (fd duplication) and any `/dev/null` target are inert; nothing else is."""
    if op in (">&", "<&"):
        return target.isdigit() or target == "-"
    return target in _INERT_TARGETS


def _unquote_first_token(text):
    """`iae` step 4 — the FIRST token only. `"ls" -la` → `ls -la`; later tokens keep their quotes."""
    s = text.lstrip()
    lead = text[: len(text) - len(s)]
    if not s or s[0] not in ("'", '"'):
        return text
    tok, j = _read_token(s, 0)
    return lead + tok + s[j:]


def _strip_wrapper(text):
    """One wrapper peel, or None. `timeout 5 CMD` → `CMD` (probe D#13, measured ALLOW).

    The wrapper's OWN arguments go with it — otherwise `timeout 5 /bin/date` normalises to
    `5 /bin/date`, which matches nothing and silently converts a covered leaf into a gap.
    Only the argument shapes each wrapper actually takes are consumed; a wrapper is never
    allowed to eat a token that could be the command.
    """
    parts = text.split()
    if not parts:
        return None
    head = parts[0]
    if head not in WRAPPERS:
        return None
    rest = parts[1:]
    while rest and rest[0].startswith("-"):
        opt = rest.pop(0)
        if head == "timeout" and opt in ("-k", "--kill-after", "-s", "--signal") and rest:
            rest.pop(0)
        elif head == "nice" and opt == "-n" and rest:
            rest.pop(0)
    if head == "timeout" and rest and _TIMEOUT_DURATION.match(rest[0]):
        rest.pop(0)
    if not rest:
        return None                      # a bare wrapper is the whole command; do not empty it
    return " ".join(rest)


def normalize_leaf(text, *, strip_all_env=False, collapse_ws=True):
    """`iae` to a fixed point, plus the inert-redirection strip and optional whitespace collapse.

    strip_all_env mirrors `v7e`'s asymmetry (§1 step 2, footgun F6): DENY and ASK rules are matched
    with `stripAllEnvVars: true` and so see past ANY leading assignment, while ALLOW rules see past
    only the 39 names in ENV_ALLOWLIST. `FOO=1 ls` therefore defeats `allow Bash(ls:*)` and does
    NOT defeat `deny Bash(rm *)`. Passing the wrong value here is the single easiest way to make an
    allow rule look broader than it is.

    collapse_ws defaults True (the §4 contract names only strip_all_env; both are keyword-only). It
    exists because EXACT rules are compared with `===` against an UNCOLLAPSED candidate — probe
    C#11, `/usr/bin/basename  foo` DENIED under `Bash(/usr/bin/basename foo)`.
    """
    s = _strip_comment_lines(text)
    s = _strip_redirections(s, inert_only=True)
    seen = set()
    while True:
        cur = s
        if cur in seen:
            break
        seen.add(cur)
        s = _unquote_first_token(s)
        m = _ENV_ASSIGN.match(s.strip())
        if m and (strip_all_env or m.group(1) in ENV_ALLOWLIST):
            s = m.group(3)
            continue
        peeled = _strip_wrapper(s)
        if peeled is not None:
            s = peeled
            continue
        break
    return " ".join(s.split()) if collapse_ws else s.strip()


def head_of(leaf, n=2):
    """The first n tokens of a normalised leaf, joined by one space — a candidate rule head."""
    parts = normalize_leaf(leaf).split()
    return " ".join(parts[:n]) if parts else ""


# ──────────────────── §2 the splitter (`MT`) and the hard gates ─────────────────────
# MT parses with tree-sitter, recurses into {program, list, pipeline} and skips the operator and
# COMMENT nodes {&& || | ; & |& \n}. Five constructs are hard-gated before any rule is consulted and
# no allow rule of any form clears them (§2, DON'T #4). `bash -c` and heredocs join them on the
# conservative side: neither was probed, and both hand a command to an interpreter as data.
#
# QUOTE-AWARENESS IS END TO END, and that is a correction, not a flourish.
# `hooks/lib/smart-bash-allowlist.py:split_segments` refuses the whole command the moment the two
# characters `<(` appear ANYWHERE — including inside single quotes, where the shell does not expand
# them. Run against the real corpus in wave A that pre-check shredded ordinary commands into garbage
# leaves: `grep -oE '<(script|style)' f | sort` is a grep for a literal string, not a process
# substitution. This scanner mirrors that file's structure and drops that pre-check: a construct is
# structural only where the SHELL would treat it as one.
STRUCTURAL_KINDS = (
    "command_substitution", "backtick", "process_substitution", "subshell", "command_group",
    "background", "redirect_file", "heredoc", "bash_c", "too_long", "multi_cd",
    "cd_git_compound", "unbalanced",
)
MAX_COMMAND_CHARS = 10000               # `CIe`; longer commands are returned unsplit and always ask

# Grammar, not commands. Peeled so the real verb underneath is what gets judged — the measured rows
# `for i in 1 2; do /bin/date; done` and `if true; then /bin/date; fi` ALLOW under a rule that names
# only `/bin/date`, which proves the harness asks for no rule covering `do` or `done`.
_PEELED_KEYWORDS = frozenset((
    "do", "done", "then", "else", "elif", "fi", "esac", "in", "case", "if", "for", "while",
    "until", "function", "select", "coproc", "{", "}", "!", "time",
))
_OPENERS = frozenset(("do", "then", "else", "elif", "in", "!", "{", "(", "&&", "||", ";"))
_LOOP_HEAD = re.compile(r"^(?:for|while|until)\s+\S+\s+in\s+(.*)$")
_SET_OPTIONS = re.compile(r"^set(\s+[-+][A-Za-z]+)*(\s+(pipefail|posix|errexit|nounset|xtrace))*\s*$")
_SHELLS = frozenset(("bash", "sh", "zsh", "ksh", "dash", "fish"))


def _skip_balanced(s, i, opener, closer):
    """Index just past the balanced closer for the opener at i, or None when unbalanced."""
    depth, j, n = 0, i, len(s)
    quote = None
    while j < n:
        ch = s[j]
        if quote:
            if ch == quote:
                quote = None
            j += 1
            continue
        if ch in ("'", '"'):
            quote = ch
            j += 1
            continue
        if ch == "\\" and j + 1 < n:
            j += 2
            continue
        if ch == opener:
            depth += 1
        elif ch == closer:
            depth -= 1
            if depth == 0:
                return j + 1
        j += 1
    return None


def _at_command_position(buf):
    s = "".join(buf).strip()
    if not s:
        return True
    return s.rsplit(None, 1)[-1] in _OPENERS


def _skip_heredoc_bodies(cmd, i, pending):
    """Index just past the last pending heredoc body starting at line-start i, or None if a body
    never closes. Mirrors smart-bash-allowlist.strip_heredocs: the body is DATA, not commands, so it
    is never cut into leaves — `cat <<EOF` followed by `rm -rf /` on the next line is one leaf and a
    structural flag, not a `rm` verb in the top-verbs table."""
    n = len(cmd)
    for delim, strip_tabs in pending:
        while True:
            if i >= n:
                return None
            j = cmd.find("\n", i)
            line = cmd[i:] if j < 0 else cmd[i:j]
            i = n if j < 0 else j + 1
            if (line.lstrip("\t") if strip_tabs else line) == delim:
                break
    return i


def _scan(cmd):
    """(raw_segments, structural_kinds, balanced) — one quote-aware pass, no pre-checks."""
    segs, buf, structural = [], [], []
    n, i, quote = len(cmd), 0, None
    heredocs = []                         # (delimiter, strip_leading_tabs) opened on this line

    def flag(kind):
        if kind not in structural:
            structural.append(kind)

    def cut():
        segs.append("".join(buf))
        del buf[:]

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
            if cmd[i + 1] == "\n":
                i += 2                    # a line continuation joins two physical lines
                continue
            buf.append(ch)
            buf.append(cmd[i + 1])
            i += 2
            continue
        if ch == "#" and (not buf or buf[-1] in " \t\n"):
            j = cmd.find("\n", i)         # MT skips comment nodes; the newline stays a separator
            i = n if j < 0 else j
            continue
        if ch == "$" and i + 1 < n and cmd[i + 1] == "(":
            if cmd.startswith("$((", i):
                j = _skip_balanced(cmd, i + 1, "(", ")")   # arithmetic, not a command
                if j is None:
                    flag("unbalanced")
                    buf.append(cmd[i:])
                    i = n
                    continue
                buf.append(cmd[i:j])
                i = j
                continue
            flag("command_substitution")
            j = _skip_balanced(cmd, i + 1, "(", ")")
            if j is None:
                flag("unbalanced")
                buf.append(cmd[i:])
                i = n
                continue
            buf.append(cmd[i:j])
            i = j
            continue
        if ch == "`":
            flag("backtick")
            j = cmd.find("`", i + 1)
            if j < 0:
                flag("unbalanced")
                buf.append(cmd[i:])
                i = n
                continue
            buf.append(cmd[i:j + 1])
            i = j + 1
            continue
        if ch in "<>" and i + 1 < n and cmd[i + 1] == "(":
            flag("process_substitution")
            j = _skip_balanced(cmd, i + 1, "(", ")")
            if j is None:
                flag("unbalanced")
                buf.append(cmd[i:])
                i = n
                continue
            buf.append(cmd[i:j])
            i = j
            continue
        if ch == "<" and cmd.startswith("<<", i) and not cmd.startswith("<<<", i):
            flag("heredoc")               # `K8_` refuses the fast path on /(?<!<)<<(?!<)/
            j = i + 2
            strip_tabs = j < n and cmd[j] == "-"
            if strip_tabs:
                j += 1
            while j < n and cmd[j] in " \t":
                j += 1
            delim, k2 = _read_token(cmd, j)
            buf.append(cmd[i:k2])
            if delim:
                heredocs.append((delim, strip_tabs))
            i = k2
            continue
        if ch in "<>":
            op, j = _redir_op(cmd, i)
            k = j
            while k < n and cmd[k] in " \t":
                k += 1
            target, k2 = _read_token(cmd, k)
            if op in (">", ">>", ">|", ">&") and not _redir_is_inert(op, target):
                # `2>&1` and a `/dev/null` target are inert (documented-exempt); every other OUTPUT
                # redirection is checked as a file WRITE against Edit rules and no Bash allow rule
                # authorises it (F15). Input redirection is NOT in that gate list and is not flagged.
                flag("redirect_file")
            buf.append(cmd[i:k2])
            i = k2
            continue
        if (ch == "(" or (ch == "{" and i + 1 < n and cmd[i + 1] in " \t\n")) \
                and _at_command_position(buf):
            closer = ")" if ch == "(" else "}"
            flag("subshell" if ch == "(" else "command_group")
            j = _skip_balanced(cmd, i, ch, closer)
            if j is None:
                flag("unbalanced")
                buf.append(cmd[i:])
                i = n
                continue
            # The GROUP is structural — no allow rule reaches it — but its contents are still real
            # sub-commands, and the harvester reports top verbs per structural kind. Recursing gives
            # those verbs instead of one uninterpretable leaf beginning with a bracket.
            inner, inner_struct, inner_ok = _scan(cmd[i + 1:j - 1])
            cut()
            segs.extend(inner)
            for k in inner_struct:
                flag(k)
            if not inner_ok:
                flag("unbalanced")
            i = j
            continue
        if ch in "&|;\n":
            if ch == "&":
                prev = "".join(buf).rstrip()
                nxt = cmd[i + 1] if i + 1 < n else ""
                if (prev and prev[-1] in "<>") or nxt == ">":
                    buf.append(ch)        # `2>&1`, `&>log` — fd syntax, not a separator
                    i += 1
                    continue
                if nxt != "&":
                    flag("background")    # `jsn`: classifierApprovable:false, not even auto clears
            cut()
            if ch in "&|" and i + 1 < n and cmd[i + 1] == ch:
                i += 2
            else:
                i += 1
            if ch == "\n" and heredocs:
                j = _skip_heredoc_bodies(cmd, i, heredocs)
                del heredocs[:]
                if j is None:
                    flag("unbalanced")    # a body that never closes: the whole command is unseen
                    i = n
                    continue
                i = j
            continue
        buf.append(ch)
        i += 1
    cut()
    if heredocs:
        flag("unbalanced")                # `<<EOF` with no body at all
    return segs, structural, quote is None


def _peel(seg):
    """Reduce a raw segment to the command a rule is matched against, or "" when it carries none.

    INTERIOR WHITESPACE IS PRESERVED, and that is not tidiness. `MT` hands `sW_` the sub-command's
    own text and an EXACT rule is compared to it with `===`, unnormalised — probe C#11 measured
    `/usr/bin/basename  foo` DENIED under `Bash(/usr/bin/basename foo)`. Collapsing here would make
    that row ALLOW: the matcher would silently gain a normalisation the harness does not have, and
    every double-spaced acceptance would read as covered. The peel therefore tests against a
    collapsed PROBE and cuts from the original string.
    """
    s = seg.strip()
    while s:
        probe = " ".join(s.split())
        if _LOOP_HEAD.match(probe):
            return ""                     # `for VAR in LIST` is a word list, never a command
        word = probe.split(" ", 1)[0]
        if word in _PEELED_KEYWORDS:
            s = s[len(word):].strip()
            continue
        break
    if not s:
        return ""
    probe = " ".join(s.split())
    if _ONLY_ASSIGNMENTS.match(probe) or _SET_OPTIONS.match(probe):
        return ""                         # `tPt` tracks bare assignments separately; `set -e` runs nothing
    return s


def _is_bash_c(leaf):
    parts = normalize_leaf(leaf).split()
    if not parts:
        return False
    if os.path.basename(parts[0]) not in _SHELLS:
        return False
    for t in parts[1:]:
        if t == "-c" or (t.startswith("-") and not t.startswith("--") and "c" in t):
            return True
    return False


def split_leaves(cmd):
    """Decomposition(kind, leaves, structural, too_long) for one raw command string.

    kind is 'structural' when ANY hard gate fired (no allow rule reaches such a command), else
    'compound' for more than one leaf, else 'simple'. `leaves` is always the decomposition the
    harness would evaluate, even for a structural command, so a caller can still report its verbs.
    """
    if not isinstance(cmd, str):
        return Decomposition("structural", [], ["unbalanced"], False)
    if len(cmd) > MAX_COMMAND_CHARS:
        # `MT` returns the command unsplit and the read-only analysis bails (docs: >10,000 chars
        # always prompt). Reporting a decomposition here would invent leaves the harness never saw.
        return Decomposition("structural", [cmd], ["too_long"], True)
    segs, structural, balanced = _scan(cmd)
    if not balanced and "unbalanced" not in structural:
        structural.append("unbalanced")
    leaves = [p for p in (_peel(s) for s in segs) if p]
    for leaf in leaves:
        if _is_bash_c(leaf) and "bash_c" not in structural:
            structural.append("bash_c")
    verbs = [normalize_leaf(leaf).split()[0] if normalize_leaf(leaf) else "" for leaf in leaves]
    cds = [v for v in verbs if os.path.basename(v) == "cd"]
    if len(cds) > 1:
        structural.append("multi_cd")
    elif cds and any(os.path.basename(v) == "git" for v in verbs):
        # `cd`+`git` in one command asks with bashMissKind cd-git-compound. A `cd` whose target
        # resolves to the current cwd is documented-exempt, and we cannot resolve it from a string,
        # so this over-flags in the SAFE direction: a structural row never feeds a candidate.
        structural.append("cd_git_compound")
    kind = "structural" if structural else ("compound" if len(leaves) > 1 else "simple")
    return Decomposition(kind, leaves, structural, False)


# ─────────────────────────── §1 the matcher (`ALs`) ─────────────────────────
# The authoritative text, transcribed:
#   exact:    f.command === m                       (strict ===, NO normalisation)
#   prefix:   both sides /[ \t]+/g -> " "; then  _ === g  ||  _.startsWith(g+" ")
#             ||  _ === "xargs "+g  ||  _.startsWith("xargs "+g+" ")
#   wildcard: glob, case-SENSITIVE, whitespace-collapsed, plus the same `xargs ` variant
# The candidate strings tried, in order: the trimmed command, the command with redirections
# stripped, and `iae()` of each.
#
# THE COMPOUND GUARD IS DELIBERATELY ABSENT. `ALs` refuses a prefix/wildcard match against a still
# COMPOUND string (`if (d.get(m)) return false`) unless `skipCompoundCheck` — and that flag is true
# exactly when `sW_` is evaluating an already-split sub-command. Everything here takes a LEAF, so
# the guard's precondition never holds. A caller matching a raw compound string must go through
# `command_verdict`, which splits first.


def _glob_rx(pattern):
    """`ffe`/`t2t`: escape, `*`->`.*`, `/**/`->`/(?:.*/)?`, and the one special case.

    `if (p.endsWith(" .*") && starCount === 1) p = p.slice(0,-3) + "( .*)?"` — applied to the
    REGEX, which is why `Bash(git status *)` also matches bare `git status` (§1). It is expressed
    here on the PATTERN because `re.escape` escapes a space in 3.7+, so an `endswith(" .*")` test
    against the built regex would silently never fire.
    """
    tail_optional = pattern.endswith(" *") and pattern.count("*") == 1
    body = pattern[:-2] if tail_optional else pattern
    out, i, n = [], 0, len(body)
    while i < n:
        if body.startswith("/**/", i):
            out.append("/(?:.*/)?")
            i += 4
            continue
        ch = body[i]
        out.append(".*" if ch == "*" else re.escape(ch))
        i += 1
    rx = "".join(out)
    if tail_optional:
        rx += "(" + re.escape(" ") + ".*)?"
    return re.compile("^" + rx + "$", re.S)


_GLOB_CACHE = {}


def _glob_match(pattern, subject):
    rx = _GLOB_CACHE.get(pattern)
    if rx is None:
        rx = _GLOB_CACHE[pattern] = _glob_rx(" ".join(pattern.split()))
    return rx.match(subject) is not None


def _candidates(leaf, strip_all_env):
    """The candidate strings `ALs` tries, deduped, order preserved."""
    raw = leaf.strip()
    out = [raw]
    for c in (_strip_redirections(leaf, inert_only=False).strip(),
              normalize_leaf(leaf, strip_all_env=strip_all_env, collapse_ws=False)):
        if c and c not in out:
            out.append(c)
    return out


def rule_matches_leaf(rule, leaf, behavior="allow"):
    """Does this parsed rule match this single sub-command?

    `behavior` selects the env-stripping asymmetry of `v7e` — deny and ask see past ANY leading
    assignment, allow sees past only ENV_ALLOWLIST. Passing "allow" for a deny rule understates the
    deny, which is the unsafe direction; callers should use `leaf_verdict`, which passes it for you.
    """
    if rule is None:
        return False
    if isinstance(rule, str):
        rule = parse_rule(rule)
        if rule is None:
            return False
    if rule.kind == "bare":
        return True                        # a bare tool name skips every specifier test (§6 F16)
    strip_all = behavior in ("deny", "ask")
    cands = _candidates(leaf, strip_all)
    if rule.kind == "exact":
        return any(c == rule.content for c in cands)
    collapsed = []
    for c in cands:
        c = " ".join(c.split())
        if c not in collapsed:
            collapsed.append(c)
    if rule.kind == "prefix":
        g = " ".join(_PREFIX_RE.match(rule.content).group(1).split())
        xg = "xargs " + g
        for c in collapsed:
            if c == g or c.startswith(g + " ") or c == xg or c.startswith(xg + " "):
                return True
        return False
    for c in collapsed:
        if _glob_match(rule.content, c):
            return True
        # `ped(f.pattern)` gates the xargs retry for allow rules; deny/ask always retry. The
        # predicate was not extracted from the binary, so the retry is applied uniformly — which
        # can only make a rule match MORE, and for deny/ask that is the safe direction. For allow
        # it is the unsafe one, so it is confined to patterns that name a bare command head.
        if behavior != "allow" or " " not in rule.content.strip().rstrip("*").strip():
            if _glob_match("xargs " + rule.content, c):
                return True
    return False


def leaf_verdict(leaf, rules, tool="Bash"):
    """(outcome, matched_rule) for ONE leaf. deny -> ask -> allow, first class that matches wins.

    `v7e` runs the three sets in that order and `sW_` lets any deny win outright, so an allow rule
    can never carve an exception out of a deny (§5, DON'T #7).
    """
    for behavior, bucket in (("deny", rules.deny), ("ask", rules.ask), ("allow", rules.allow)):
        for rule in bucket:
            if rule.tool != tool:
                continue
            if rule_matches_leaf(rule, leaf, behavior):
                return behavior, rule
    return "none", None


def command_verdict(cmd, rules, tool="Bash"):
    """Verdict(outcome, uncovered, structural, matched) for a whole raw command string.

    `sW_`: any deny wins; otherwise EVERY sub-command must allow; anything else asks. A structural
    command short-circuits — no allow rule of any specifier form reaches it (§2), so `uncovered` is
    reported for completeness but proposing a rule for it is the inflation this file exists to stop.
    """
    dec = split_leaves(cmd)
    matched, uncovered, outcomes = {}, [], []
    for leaf in dec.leaves:
        outcome, rule = leaf_verdict(leaf, rules, tool)
        outcomes.append(outcome)
        if rule is not None:
            matched[leaf] = rule.raw
        if outcome == "none":
            uncovered.append(leaf)
    if "deny" in outcomes:
        return Verdict("deny", uncovered, dec.structural, matched)
    if dec.structural:
        return Verdict("structural", uncovered, dec.structural, matched)
    if not outcomes:
        return Verdict("ask", uncovered, dec.structural, matched)
    if all(o == "allow" for o in outcomes):
        return Verdict("allow", uncovered, dec.structural, matched)
    return Verdict("ask", uncovered, dec.structural, matched)


# The built-in read-only set. INFORMATIONAL ONLY — no decision path here reads it, because the truth
# doc says plainly that its contents were "sampled, not enumerated" (`E8_`/`v8_`/`CLs` is the
# authoritative source and was not extracted). Two provenances, kept apart so a later probe can
# correct one without disturbing the other:
_READONLY_DOCS = frozenset((
    "ls", "cat", "echo", "pwd", "head", "tail", "grep", "find", "wc", "which",
    "diff", "stat", "du", "cd",
))
# probe B ran these with an EMPTY allowlist; `false` is measured the same way by the §2 row
# `while false; do /bin/date; done` -> ALLOW under a rule naming only `/bin/date`.
_READONLY_PROBED = frozenset((
    "date", "uname", "hostname", "id", "true", "false", "printf", "sleep",
))
BUILTIN_READONLY = _READONLY_DOCS | _READONLY_PROBED
GIT_READONLY = frozenset((
    "status", "log", "diff", "show", "rev-parse", "branch", "describe", "blame",
    "ls-files", "ls-tree", "cat-file", "config", "remote", "shortlog", "tag",
))


def is_builtin_readonly(leaf):
    """True iff the harness's built-in read-only set plausibly covers this leaf.

    Keys on the BARE NAME: probe B measured `/bin/date +%s` DENIED with an empty allowlist while
    `date` ran — an absolute path escapes the set. That asymmetry is the whole reason `/bin/date`
    was chosen as the probe subject, and a caller that forgets it will read a rule-allow where the
    real cause was the read-only auto-approval.
    """
    parts = normalize_leaf(leaf).split()
    if not parts:
        return False
    verb = parts[0]
    if "/" in verb:
        return False
    if verb in BUILTIN_READONLY:
        return True
    return verb == "git" and len(parts) > 1 and parts[1] in GIT_READONLY


# ────────────────────── §3 THE AUTO-MODE DROP PREDICATE ──────────────────────
#
# MOVED VERBATIM from bin/cc-permission-audit (2026-09-08), tables and reason strings unchanged, so
# tests/cc-permission-dropped.bats keeps its exact assertions and remains the regression guard for
# the move. Its rationale, preserved because it governs every caller:
#
# A SECOND, INDEPENDENT deadness axis, and it is REPORT-ONLY — never removed, not even under
# CONFIRM=1. `dead_entries` asks "is this rule redundant?"; this one asks "does the mode we actually
# run even LOAD this rule?". Every session on this box runs `--permission-mode auto`, and auto mode
# DISCARDS broad allow rules before matching: `pme()` skips each allow rule for which
# `qNt(tool, content)` is true. Such an entry is inert in the mode it lives in — dead weight that
# reads as coverage.
#
# WHY REPORT-ONLY, both halves load-bearing:
#   (a) The drop is restored when you LEAVE auto mode, so deleting the entry is a real semantic
#       change under `default`/`acceptEdits` — unlike redundancy, which is semantics-preserving in
#       any mode. Two different kinds of dead.
#   (b) The predicate is code-and-doc verified but NOT probe-verified: no observable distinguishes
#       "allowed by rule" from "allowed by classifier" in auto mode. A false prune costs the
#       operator a prompt forever; a report costs a line of output.
#
# Transcribed from the truth doc's `gsn`/`_sn`/`iSd`/`nSd`/`PHs` reading. It is a claim about a
# specific decompiled build (CC 2.1.220) and can go stale in a way `dead_entries` cannot.

# `iSd` — the dangerous-command list, verbatim from the doc.
DROP_CMDS = (
    "python", "python3", "python2", "node", "deno", "tsx", "ruby", "perl", "php", "lua",
    "npx", "bunx", "npm run", "yarn run", "pnpm run", "bun run",
    "bash", "sh", "ssh", "zsh", "fish", "eval", "exec", "env", "xargs", "sudo",
)
# `nSd` — the network/cloud subset, which gets extra conditions on top of the bare forms.
DROP_NET = ("curl", "wget", "kubectl", "aws", "gcloud", "gsutil")
# The kubectl verbs that drop even with a positional arg present.
KUBECTL_VERBS = {
    "exec", "apply", "create", "delete", "run", "cp", "port-forward", "proxy", "patch",
    "edit", "replace", "attach", "debug", "scale", "rollout", "drain", "cordon", "taint",
}
# The rule-syntax suffix a verb token carries when the rule is written in the `:*` form. A rule
# names a PREFIX, so `Bash(kubectl apply:*)` and `Bash(kubectl apply *)` are the same rule — and
# `_tail_after` already treats `:` and ` ` as the same separator at the COMMAND boundary. This
# strips the same suffix at the VERB boundary, which is the only place that equivalence was not
# being honoured. It cannot manufacture a verb: `applyfoo:*` → `applyfoo`, still not in the set.
_VERB_SUFFIX = "*:"
# The one documented survivor inside the flag-tail branch: `Bash(python -m pkg.module *)`.
DASH_M_SURVIVES = re.compile(r"^-m\s+\w+\.[\w.]+(\s*:|\s+)")
ALL_STARS = re.compile(r"^[\s*]+$")


def _tail_after(content, cmd):
    """The part of `content` after the leading `cmd` token(s), or None if `cmd` does not lead."""
    if content == cmd:
        return ""
    for sep in (":", " "):
        if content.startswith(cmd + sep):
            return content[len(cmd) + len(sep):].strip()
    if content.startswith(cmd) and content[len(cmd):].startswith("*"):
        return content[len(cmd):].strip()
    return None


def auto_mode_dropped(rule):
    """Reason string if auto mode discards this allow rule, else None. See the block above."""
    m = RULE_RE.match(rule)
    if not m:
        # No parens at all: a bare tool name. `PHs` drops every Agent rule; `gsn`'s
        # undefined-content branch drops bare `Bash`.
        bare = rule.strip()
        if bare == "Agent":
            return "Agent rule — auto mode drops every Agent allow rule"
        if bare == "Bash":
            return "bare `Bash` — auto mode drops the empty-content form"
        return None
    tool, content = m.group(1), m.group(2)
    if tool == "Agent":
        return "Agent rule — auto mode drops every Agent allow rule, whatever its specifier"
    if tool != "Bash":
        return None                      # gsn returns false for every non-Bash tool
    c = content.strip().lower()
    if c == "" or ALL_STARS.match(c):
        return "matches everything — auto mode drops the bare/wildcard Bash form"

    for cmd in DROP_CMDS + DROP_NET:
        tail = _tail_after(c, cmd)
        if tail is None:
            continue
        # Bare forms: `<cmd>`, `<cmd>:*`, `<cmd> *`, `<cmd>*`.
        if tail in ("", "*"):
            return f"`{cmd}` in bare/`:*` form — on auto mode's dangerous-command list"
        # `<cmd> …*` whose tail starts with a flag, minus the documented `-m pkg.module` case.
        if tail.startswith("-") and not DASH_M_SURVIVES.match(tail):
            return f"`{cmd}` with a flag tail (`{tail[:24]}`) — auto mode drops the flag form"
        if cmd in DROP_NET:
            if "$" in tail or "`" in tail:
                return f"`{cmd}` tail contains a substitution — auto mode drops it"
            if cmd == "kubectl":
                first = next((t for t in tail.split() if not t.startswith("-")), "")
                first = first.rstrip(_VERB_SUFFIX)
                if first in KUBECTL_VERBS:
                    return f"`kubectl {first}` — on auto mode's dropped-verb list"
            if not any(not t.startswith("-") for t in tail.split()):
                if cmd in ("curl", "wget") and "://" in tail:
                    break               # documented exception: a URL counts as the positional
                return f"`{cmd}` with no positional argument — auto mode drops it"
        break                            # first matching command decides; no second opinion
    return None


def classify_all_shell(obj):
    """True iff this settings object sets `autoMode.classifyAllShell` (footgun F10).

    Reported because it makes the per-entry drop list moot rather than merely longer: with it on in
    ANY settings source, NO Bash allow rule survives auto mode at all. `auto_mode_dropped` is
    per-rule and structurally cannot see it.
    """
    am = obj.get("autoMode") if isinstance(obj, dict) else None
    return bool(isinstance(am, dict) and am.get("classifyAllShell") is True)


# ───────────────────── THE DEAD-ENTRY PREDICATE (redundancy) ─────────────────────
#
# MOVED VERBATIM from bin/cc-permission-audit. An approved entry is DEAD iff removing it cannot
# change what any command resolves to, proven from that same file's own `permissions.allow` list:
#   (a) DUPLICATE — a byte-identical earlier entry survives. Semantics-preserving under ANY matcher.
#   (b) SHADOWED  — it is a wildcard-free rule `Tool(literal)` and the same list holds a prefix rule
#       `Tool(base:*)` where `literal == base` OR `literal.startswith(base + " ")`. The only string
#       the exact rule can match is the literal itself, which the surviving prefix rule still
#       matches: `rule_matches_leaf`'s prefix arm is `c == g or c.startswith(g + " ")` (:768), so
#       BOTH halves are the same one line of matcher, not two opinions.
# A rule-ALGEBRA test, never a denylist of spellings. Deliberately NOT proof: a shadower living in a
# DIFFERENT settings file (files are edited independently, so the proof must live in the file being
# rewritten).
#
# ⚠ THE `literal == base` ARM WAS MISSING UNTIL 2026-09-09, and its absence was arithmetic, not
# cosmetic. The commonest acceptance cluster on this box is `{X, X <args>}`: the 2-token head is
# `X`, so the minted prefix `Bash(X:*)` shadowed `X <args>` and left `Bash(X)` behind — allow-list
# length unchanged (+1 prefix, −1 entry) for a strictly WIDER grant. Measured on the real 30-day
# proposal: 3 of 7 consolidation prefixes (`sysctl hw.memsize`, `killall -9 Dia`,
# `scripts/generate-dev-guide.sh`) retired net ZERO, and the report headline "7 prefix(es) retiring
# 15 exact entr(ies)" over-stated a true net of 8. The old comment justified the omission as "that
# is the matcher's business" — but the matcher had already decided it, in the line quoted above.


def dead_entries(allow):
    """(survivors, [(index, rule, reason)]) for one `permissions.allow` list. Order preserved."""
    prefixes = collections.defaultdict(list)
    for rule in allow:
        m = RULE_RE.match(rule)
        if not m:
            continue
        tool, arg = m.group(1), m.group(2)
        if arg.endswith(":*") and not WILDCARD.search(arg[:-2]):
            prefixes[tool].append(arg[:-2])

    survivors, dead, seen = [], [], set()
    for i, rule in enumerate(allow):
        if rule in seen:
            dead.append((i, rule, "duplicate of an earlier entry"))
            continue
        m = RULE_RE.match(rule)
        if m and not WILDCARD.search(m.group(2)):
            tool, arg = m.group(1), m.group(2)
            hit = next((b for b in prefixes[tool] if b and (arg == b or arg.startswith(b + " "))),
                       None)
            if hit is not None:
                dead.append((i, rule, f"shadowed by {tool}({hit}:*)"))
                continue
        seen.add(rule)
        survivors.append(rule)
    return survivors, dead


# ─────────────────── §3.2 THE REFUTATION GATES (PERMISSION_HARVEST.md) ───────────────────
#
# Each answers ONE question about a CANDIDATE RULE HEAD and returns a reason string (or a bool)
# rather than a verdict, so the caller records every gate's answer on every candidate — a refusal
# whose cost is invisible is a refusal nobody can audit. Every table below is TRANSCRIBED from §3.2,
# not paraphrased: these lists are the 2026-08-23 refutation made mechanical, and a name quietly
# dropped from one re-opens the exact hole that refutation closed.


def _tokens(head):
    if isinstance(head, str):
        return head.split()
    return [t for t in head if t]


def _verb(tok):
    return os.path.basename(tok) if "/" in tok else tok


# ACE_CLASS: interpreters, shells, exec wrappers, env runners, and PERSISTENCE+LAUNCH verbs. The
# rule approves whatever follows (F12/F13) or installs something that runs later.
ACE_VERBS = frozenset((
    "bash", "sh", "zsh", "fish", "dash", "ksh", "node", "deno", "bun", "tsx", "ruby", "perl",
    "php", "lua", "eval", "exec", "env", "xargs", "sudo", "source", ".", "npx", "bunx", "pnpx",
    "docker", "devbox", "mise", "direnv", "watch", "setsid", "ionice", "flock", "nohup",
    "timeout", "awk",
    # 🚨 PACKAGE MANAGERS (added 2026-09-09). `npm`/`yarn`/`pnpm` were MISSING while `bun` was
    # present, and `npm run`/`yarn run`/`pnpm run`/`bun run` all sit in DROP_CMDS ten lines up —
    # two transcriptions of one source that had silently diverged. The consequence was measured:
    # `Bash(npm:*)` passed ALL ELEVEN gates on an empty collision set and reached a FLEET proposal,
    # and it matches `npm exec`, `npm x`, `npm run <anything>` and `npm install` (registry
    # lifecycle scripts) — the arbitrary-code-execution class the 2026-08-23 refutation exists to
    # close. AUTO_MODE_DROP does not cover the gap: `_sn` matches the literal `npm run`, so
    # `Bash(npm run:*)` drops and `Bash(npm:*)` does not. Family-wide, exactly like `bun`: the
    # sub-verb head `pnpm lint` runs whatever package.json calls "lint", which is code that changes
    # when the repo does. The suite's ACE ⊇ DROP_CMDS arm now makes a future divergence a red test.
    "npm", "yarn", "pnpm",
    # SHELL-ESCAPE / BUILD-RUNNER class: each of these has a documented way to spawn a shell or run
    # an arbitrary program from an argument the head cannot pin past (GTFOBins' shell-escape set,
    # intersected with what plausibly appears in this fleet's prompts). `make`/`just`/`rake`/
    # `gradle`/`mvn`/`task` execute rules from a file in the cwd; `cargo`/`go` run build scripts and
    # `go run`; `pip`/`gem` execute setup code at install; `brew` runs formula ruby; `vim`/`less`/
    # `man`/`ed` have `:!cmd`; `nc`/`socat` have `-e`/`EXEC:`; `tmux`/`screen`/`script`/`expect`/
    # `gdb`/`lldb` spawn one directly; `sqlite3` has `.shell`; `ansible`/`terraform` execute
    # playbooks and providers. Every one of them PASSED all eleven gates before this line.
    "make", "gmake", "ninja", "rake", "gem", "pip", "pip2", "pip3", "pipx", "brew", "cargo", "go",
    "gradle", "mvn", "just", "task", "ansible", "ansible-playbook", "terraform",
    "vim", "vi", "nvim", "emacs", "less", "more", "man", "ed", "nc", "ncat", "socat",
    "tmux", "screen", "script", "expect", "gdb", "lldb", "sqlite3", "ssh-keygen",
    # persistence + launch: the rule does not run the payload, it ARRANGES for it to run later.
    "launchctl", "defaults", "crontab", "at", "osascript", "automator", "open", "security",
    "export", "set",
    # `find`: its -exec/-execdir/-ok/-delete cannot be pinned past by any leading token.
    "find",
))
_PYTHON_RE = re.compile(r"^python[0-9.]*$")


def ace_reason(head_tokens):
    """Reason string when this head's verb grants arbitrary code execution, else None."""
    toks = _tokens(head_tokens)
    if not toks:
        return None
    verb = _verb(toks[0])
    if _PYTHON_RE.match(verb):
        return f"`{verb}` is an interpreter — the rule approves whatever script follows"
    if verb in ACE_VERBS:
        return f"`{verb}` is on the ACE class list — the rule approves what it is handed, not a command"
    return None


# ARG_EXEC: an exec-bearing ARGUMENT the head's own tokens do not pin past. MEASURED:
# `git rebase -x 'touch MARK' --root` executes. A prefix rule is a grant over arguments not yet
# typed, so `Bash(git rebase:*)` fails here while `Bash(git rebase --abort:*)` (3 tokens) passes.
ARG_EXEC_ALWAYS = {
    "tar": "-I / --use-compress-program runs an arbitrary filter program",
    "rsync": "-e / --rsh runs an arbitrary remote shell",
    "ssh": "-o ProxyCommand runs an arbitrary command",
    "scp": "-o ProxyCommand runs an arbitrary command",
    "sort": "--compress-program runs an arbitrary program",
    "find": "-exec / -execdir / -ok / -delete run or destroy",
    "xargs": "the command to run is its ARGUMENT",
}
# git: sub-verb -> the tokens that make it exec-bearing. An empty tuple means the sub-verb itself is.
GIT_ARG_EXEC = {
    "rebase": ("-x", "--exec"),
    "bisect": ("run",),
    "filter-branch": (),
    "submodule": ("foreach",),
    "difftool": ("--extcmd", "--tool-cmd"),
    "mergetool": ("--extcmd", "--tool-cmd"),
}


def arg_exec_reason(head_tokens):
    """Reason string when an exec-bearing argument survives this head, else None."""
    toks = _tokens(head_tokens)
    if not toks:
        return None
    verb = _verb(toks[0])
    if verb in ARG_EXEC_ALWAYS:
        return f"`{verb}`: {ARG_EXEC_ALWAYS[verb]} — no leading token pins past it"
    if verb != "git":
        return None
    rest = toks[1:]
    if "-c" in rest:
        return "`git -c` sets arbitrary config (aliases, core.pager) — it executes"
    if not rest:
        return "bare `git` still reaches rebase -x, bisect run, filter-branch, submodule foreach"
    sub = rest[0]
    if sub not in GIT_ARG_EXEC:
        return None
    spec = GIT_ARG_EXEC[sub]
    if not spec:
        return f"`git {sub}` runs the filter arguments it is given"
    if len(rest) == 1:
        return f"`git {sub}` still admits {' / '.join(spec)} — it executes"
    if rest[1] in spec:
        return f"`git {sub} {rest[1]}` IS the exec-bearing form"
    return None


def flag_head(head_tokens):
    """True when the head's LAST token starts with `-`.

    `rm -f`, `rm -r`, `sed -n`, `curl -sS` are the bare verb in disguise: the head inherits every
    verdict of its verb-only head (ACE, collision, ARG_EXEC) while looking narrower than it is.
    """
    toks = _tokens(head_tokens)
    return bool(toks) and toks[-1].startswith("-")


# F19's rule-minting splitter saves loop and test leaves as EXACT rules — 73 such acceptances exist
# in the fleet. `Bash(do:*)` is nonsense that passes every other gate.
SHELL_KEYWORDS = frozenset((
    "do", "done", "then", "fi", "else", "elif", "for", "while", "until", "if", "[", "[[",
    "#", "set", "export", "case", "esac", "function", "select", "time",
))


def shell_keyword(head_tokens):
    """True when the head's first token is shell grammar rather than a command."""
    toks = _tokens(head_tokens)
    return bool(toks) and toks[0] in SHELL_KEYWORDS


# HOOK_OWNED: a shipped PreToolUse hook owns this head's decision, and hooks run BEFORE rules — so
# proposing an allow rule here claims a clearance that cannot happen (a hook exit-2 beats an allow
# rule; even a hook `allow` does not bypass deny/ask). Static table, §3.2.
HOOK_OWNED = (
    (("rm", "rmdir"), "validate-bash.sh (rm guard) / rm-safe-allowlist.sh"),
    (("curl", "wget"), "curl-gate.py"),
)


def hook_owner(head_tokens):
    """The hook that owns this head's decision, or None."""
    toks = _tokens(head_tokens)
    if not toks:
        return None
    verb = _verb(toks[0])
    for verbs, hook in HOOK_OWNED:
        if verb in verbs:
            return hook
    if verb == "git" and len(toks) > 1 and toks[1] == "push":
        # Exactly the §3.2 row: `git push`. A 1-token `git` head is NOT claimed here even though it
        # reaches `git push` — ASK_DENY_COLLISION refuses it bidirectionally, and a table that says
        # more than its source stops being a transcription anyone can diff against §3.2.
        return "ship-rail-push-allow.sh"
    return None


# ───────────────────────── resolution of an archived prompt ─────────────────────────


def row_key(row):
    """A stable identity for one archive row, so two passes agree on which row they mean.

    Not the beacon's `tool_sig` (that is a digest over the canonical tool input, and only the beacon
    can produce it): this identifies the ROW, which is what `denial_oracle` keys its answers on.

    THE COMMAND IS PART OF THE KEY, and it has to be. The beacon writes several rows per session
    within the same second, so a key over (session, ts, resolved_ts, sig) COLLIDES — measured on a
    two-row fixture, where a transcript-proven denial of one command marked BOTH rows denied and
    would have silenced an innocent rule head forever. Two rows identical in every field including
    the command are genuinely indistinguishable and SHOULD share a key.
    """
    ident = "\x1f".join((
        str(row.get("session_id") or ""),
        str(row.get("ts") or ""),
        str(row.get("resolved_ts") or ""),
        str(row.get("tool_use_id") or ""),
        str(row.get("tool_sig") or ""),
        str(row.get("tool_name") or ""),
        command_of(row),
    ))
    return hashlib.sha1(ident.encode("utf-8", "replace")).hexdigest()[:20]


def classify_row(r):
    """approved | refused | abandoned | collateral | unknown — and a grant is PROVEN, never inferred.

    MOVED from bin/cc-permission-audit's `_classify`, with ONE deliberate split, folded from
    PERMISSION_HARVEST.md §10 B1-6: `Stop` and `SessionEnd` used to share the bucket `refused`, and
    16 of 23 "refused" rows are SessionEnd — nobody answered. A prompt nobody answered is not a
    human decision, so `REFUSED_PROMPT_COLLISION` must not fire on it. Stop ⇒ refused (the operator
    interrupted), SessionEnd ⇒ abandoned (a receipt flag, never a refusal). A caller that wants the
    old combined bucket adds them; a caller that wants a recorded human NO uses `refused` plus
    `denial_oracle`.

    The rest is unchanged, and its reasoning is the load-bearing part:

    The only evidence that a prompt was GRANTED is that the very invocation it gated is the one
    whose PostToolUse cleared it. Matching tool NAMES was the first rule and it is a guess that
    fails in the unsafe direction — this traffic is overwhelmingly Bash, so a DENIED
    `git push --force` followed by any other Bash command in the same turn gave
    cleared_tool == tool_name == "Bash" and the refusal was counted as an approval.

    Identifying the invocation by `tool_use_id` was the second rule, and it could never fire:
    PermissionRequest ships that field as the empty string in 0 of 3,641 archived records, so
    `tid and cid` was never true and every row fell through to the tool-NAME branch. The measured
    result was `approved 0 · unknown 3359` over 3,763 real prompts — a zero produced by the
    instrument.

    The rule that actually decides is the INVOCATION SIGNATURE the beacon records: a digest over the
    canonical {tool_name, tool_input} of the prompted call (`tool_sig`) and of the call that cleared
    it (`cleared_tool_sig`). The id rule is kept ABOVE it, unchanged, so a binary that starts
    populating the field silently upgrades this to proof by id. Without either, the honest answer is
    still `unknown`.

    `PostToolUseFailure` is treated exactly like `PostToolUse`: the hook fired on the same
    invocation and carries the same signature, and the tool's exit status says nothing about
    whether the operator granted the prompt.
    """
    ev = r.get("resolved_by") or "unknown"
    if ev == "Stop":
        return "refused"
    if ev == "SessionEnd":
        return "abandoned"
    if ev not in ("PostToolUse", "PostToolUseFailure"):
        return "unknown"
    tid, cid = r.get("tool_use_id") or "", r.get("cleared_tool_use_id") or ""
    if tid and cid:
        return "approved" if tid == cid else "collateral"
    sig, csig = r.get("tool_sig") or "", r.get("cleared_tool_sig") or ""
    if sig and csig:
        return "approved" if sig == csig else "collateral"
    ct, tn = r.get("cleared_tool") or "", r.get("tool_name") or ""
    if ct and tn and ct != tn:
        return "collateral"          # provably a different tool ⇒ provably not this grant
    return "unknown"                 # same name, or no ids/signatures: not evidence of anything


def command_of(row):
    """The command text of an archived row, including the truncated-payload fallback so an
    over-long prompt still contributes its identity instead of vanishing from every ranking."""
    ti = row.get("tool_input")
    if isinstance(ti, dict):
        return (ti.get("command") or ti.get("file_path")
                or ti.get("description") or row.get("tool_input_summary") or "")
    return row.get("tool_input_summary") or ""


# The transcript text of a HUMAN rejection, read out of the 2.1.220 binary (`Hpt`, `bft`). The
# sibling strings `Permission for this tool use was denied.` (`tEe`, `kRo`) are a CLASSIFIER or hook
# denial and are deliberately NOT here: folding them in would make REFUSED_PROMPT_COLLISION fire on
# decisions the operator never made, which is the same over-count in the other direction.
DENIAL_MARKERS = (
    "The user doesn't want to proceed with this tool use",
    "The user doesn’t want to proceed with this tool use",
)


def denial_oracle(rows, transcript_roots):
    """{row_key: 'denied'} for archive rows a transcript proves the operator actually rejected.

    ~19 genuine denials hide inside `collateral` (§10 B1-6): the beacon sees a later PostToolUse
    clear the pending record and can only say "not this grant", while the transcript carries the
    rejection verbatim. The join is by exact command within the same session — the honest one — plus
    a `tool_sig` arm that fires only if a transcript ever starts carrying that field. A denial whose
    `tool_use_id` resolves to no `tool_use` block is DROPPED rather than attributed by proximity:
    fail closed, because a false denial silences a rule head forever.
    """
    by_session = collections.defaultdict(list)
    for r in rows:
        sid = r.get("session_id")
        if sid:
            by_session[sid].append(r)
    out = {}
    for sid, srows in by_session.items():
        for path in _transcript_files(sid, transcript_roots):
            uses, denied_ids, denied_sigs = {}, set(), set()
            try:
                fh = open(path, encoding="utf-8-sig", errors="ignore")
            except OSError:
                continue
            with fh:
                for ln in fh:
                    if '"tool_use"' not in ln and '"tool_result"' not in ln:
                        continue
                    try:
                        o = json.loads(ln)
                    except Exception:
                        continue
                    msg = o.get("message") or {}
                    content = msg.get("content")
                    if not isinstance(content, list):
                        continue
                    for blk in content:
                        if not isinstance(blk, dict):
                            continue
                        if blk.get("type") == "tool_use":
                            uses[blk.get("id")] = (blk.get("input") or {}).get("command", "")
                        elif blk.get("type") == "tool_result":
                            text = blk.get("content")
                            if not isinstance(text, str):
                                text = json.dumps(text, ensure_ascii=False)
                            if any(mk in text for mk in DENIAL_MARKERS):
                                denied_ids.add(blk.get("tool_use_id"))
                                sig = blk.get("tool_sig") or o.get("tool_sig")
                                if sig:
                                    denied_sigs.add(sig)
            denied_cmds = {uses[i] for i in denied_ids if uses.get(i)}
            if not denied_cmds and not denied_sigs:
                continue
            for r in srows:
                if (r.get("tool_sig") and r.get("tool_sig") in denied_sigs) or \
                        (command_of(r) and command_of(r) in denied_cmds):
                    out[row_key(r)] = "denied"
    return out


def _transcript_files(sid, roots):
    """`<root>/<slug>/<sid>.jsonl` and `<root>/<slug>/<sid>/**/*.jsonl` — the subagent files hold
    most of the denials, so the recursive arm is not optional."""
    out = []
    for root in roots or ():
        root = os.path.expanduser(root)
        out += _glob.glob(os.path.join(root, "*", sid + ".jsonl"))
        out += _glob.glob(os.path.join(root, "*", sid, "**", "*.jsonl"), recursive=True)
    return sorted(set(out))


# ─────────────────────────── rule sets and their stores ───────────────────────────

SETTINGS_NAMES = ("settings.json", "settings.local.json")
# Discovery is a bounded walk, not `**` — a recursive glob of $HOME does not terminate in usable
# time. Explicit paths skip it entirely (that is what tests use).
WALK_SKIP = {
    "node_modules", "Library", "Applications", ".Trash", ".git", ".venv", "venv",
    "site-packages", "Movies", "Music", "Pictures", "Downloads", ".npm", ".cache",
    "dist", "build", ".next",
    # `.worktrees` holds 222 FULL CHECKOUTS on this box (~537k paths). A walk that descends into it
    # spends its whole budget statting source trees to find at most one `.claude/` per worktree, and
    # that one sits at the worktree's TOP level where SETTINGS_GLOB_SHAPES already reaches it. Any
    # caller that still wants the walk (`walk=True`) gets a bounded one because of this line.
    ".worktrees",
}
WALK_MAXDEPTH = 5
DEFAULT_SETTINGS_ROOTS = ("~/.claude*", "~/Development")

# ── WHY DISCOVERY IS A SET OF FIXED-OFFSET GLOBS AND NO LONGER A WALK (2026-09-09) ──
#
# MEASURED: `discover_settings(roots=("~/Development",))` alone cost **229.6 s** wall (2.4 s user —
# i.e. ~99 % of it was I/O wait), and it is the first thing the harvester's pipeline does, so a
# `cc-permission-harvest 30` sat on a dead terminal for minutes before reading its first archive
# row. Three runs bounded it from the other side: with an EMPTY corpus, EMPTY transcripts and a
# 1-day window the tool still hit rc 124 at 241 s — runtime independent of every input the window
# selects, which is the signature of a fixed traversal cost. A `timeout -s INT 75` traceback named
# the line: `os.walk` → `posixpath.islink`, under this function.
#
# CAUSE: `~/Development/.worktrees` holds 222 worktrees, each a full checkout, and `.worktrees` was
# not in WALK_SKIP. The `.claude` test (`basename(dirpath).startswith(".claude")`) runs AFTER
# descending, so it prunes nothing — the walk stats hundreds of thousands of paths to find 161
# files.
#
# THE REPLACEMENT IS POPULATION-PRESERVING, AND THAT WAS MEASURED, NOT ASSUMED. A first draft of
# these shapes (`*/.claude`, `.worktrees/*/.claude` only) was checked against a real `find` of
# ~/Development and MISSED FIVE FILES: `.worktrees/drain/lane-infra/.claude/settings.json` and
# `.worktrees/fix/backlog-machinery-c4a1/…` (a worktree name containing a slash),
# `_worktrees/<wt>/.claude/…` ×2 (an underscore, not a dot) and
# `cloud-agent/knowledge-base/.claude/…` (a project one level down). The shapes below find 162 files
# against the walk's 161 — a strict superset — in **4.1 s**.
#
# `*` NEVER MATCHES A LEADING DOT, which is exactly why `.worktrees` appears as a LITERAL segment
# here and `_worktrees` does not need to: `*/*` already covers it. Drop the literal and 105 worktree
# files vanish from the population silently.
SETTINGS_GLOB_SHAPES = ("", "*", "*/*", ".worktrees/*", ".worktrees/*/*")


def ruleset_from_lists(allow=(), deny=(), ask=(), mode="default", by_file=None,
                       classify_all_shell=False):
    """Build a RuleSet from raw rule strings — the constructor `load_rulesets` delegates to.

    Additive to the §4 contract and public on purpose: the collision set a caller needs is the UNION
    of every discovered deny/ask, which is a list of strings, not a list of files.

    mode='auto' moves each allow rule `auto_mode_dropped` names into `dropped`, so it can no longer
    cover a leaf. That is the whole point of B2-3: 7 fleet allows are auto-inert and 17.3% of gap
    rows were over-credited through them. `classify_all_shell` is the F10 case — set in ANY source,
    EVERY Bash allow rule is dropped, which `auto_mode_dropped` cannot see per-rule.
    """
    allow_rules, dropped = [], []
    for raw in allow:
        rule = parse_rule(raw)
        if rule is None:
            continue
        if mode == "auto":
            if classify_all_shell and rule.tool == "Bash":
                dropped.append((raw, "autoMode.classifyAllShell drops EVERY Bash allow rule"))
                continue
            why = auto_mode_dropped(raw)
            if why:
                dropped.append((raw, why))
                continue
        allow_rules.append(rule)
    return RuleSet(
        allow_rules,
        [r for r in (parse_rule(x) for x in deny) if r is not None],
        [r for r in (parse_rule(x) for x in ask) if r is not None],
        by_file if by_file is not None else collections.OrderedDict(),
        dropped,
    )


def files_with_classify_all_shell(ruleset):
    """The paths in `by_file` whose settings set `autoMode.classifyAllShell` (footgun F10)."""
    return [p for p, e in ruleset.by_file.items() if e.get("classify_all_shell")]


def _read_settings(path):
    try:
        with open(path, encoding="utf-8") as fh:
            obj = json.load(fh)
    except Exception:
        return None
    return obj if isinstance(obj, dict) else None


def load_rulesets(paths, mode="auto"):
    """RuleSet over the UNION of every path's permissions lists (§5: lists UNION, nothing overrides).

    Identical rule STRINGS dedupe (`$fe` keys its map by ruleContent), and `by_file` keeps the
    per-file lists so a consolidation proposal knows which file an entry came from. An unreadable or
    non-JSON file is skipped silently HERE and reported by the caller, which is the only layer that
    knows whether a missing file is an outage or an absence.
    """
    allow, deny, ask, seen = [], [], [], {"allow": set(), "deny": set(), "ask": set()}
    by_file = collections.OrderedDict()
    shell_off = False
    for path in paths:
        obj = _read_settings(path)
        if obj is None:
            continue
        perms = obj.get("permissions") or {}
        entry = {"classify_all_shell": classify_all_shell(obj)}
        shell_off = shell_off or entry["classify_all_shell"]
        for key, bucket in (("allow", allow), ("deny", deny), ("ask", ask)):
            vals = perms.get(key)
            vals = [v for v in vals if isinstance(v, str)] if isinstance(vals, list) else []
            entry[key] = vals
            for v in vals:
                if v not in seen[key]:
                    seen[key].add(v)
                    bucket.append(v)
        by_file[path] = entry
    return ruleset_from_lists(allow, deny, ask, mode=mode, by_file=by_file,
                             classify_all_shell=shell_off)


def config_dirs_under(start, shapes=SETTINGS_GLOB_SHAPES):
    """Every `.claude*` DIRECTORY at a fixed offset below `start` — one readdir per shape level.

    `start` itself counts when it is already a config dir, which is what makes `roots=("~/.claude*",)`
    work: the fleet forks ARE the `.claude*` directories, not parents of one.
    """
    base = start.rstrip("/") or "/"
    out = []
    if os.path.basename(base).startswith(".claude") and os.path.isdir(base):
        out.append(base)
    for shape in shapes:
        pat = os.path.join(base, shape, ".claude*") if shape else os.path.join(base, ".claude*")
        out.extend(p for p in _glob.glob(pat) if os.path.isdir(p))
    return out


def discover_settings(explicit=None, names=SETTINGS_NAMES, roots=None, scope=None, walk=False):
    """[(path, scope)] with scope ∈ fleet|project|worktree, sorted, bounded.

    `fleet` = a `~/.claude*` directory (the five forked config dirs — the apply target that must be
    written as a set or the change silently lands on one account). `worktree` = anything under a
    `.worktrees` path: EVIDENCE, never a target, because a worktree is disposable. Everything else
    is `project` — where the 975 exact acceptances actually live.

    `roots=None` means DEFAULT_SETTINGS_ROOTS. Traversal is SETTINGS_GLOB_SHAPES (see the block
    above it for the measurement that replaced the walk: 229.6 s → 4.1 s, population a superset).

    `walk=True` keeps the legacy bounded `os.walk`, for a root whose shapes are not known in advance;
    `bin/cc-permission-audit` passes it with `roots=("~",)` to keep its pre-lib discovery population.
    That walk is now bounded too — `.worktrees` joined WALK_SKIP — so neither path can spend minutes
    inside 222 checkouts.
    """
    if explicit:
        return [(p, _settings_scope(p)) for p in explicit
                if scope is None or _settings_scope(p) == scope]
    out = []
    for root in (roots or DEFAULT_SETTINGS_ROOTS):
        for start in sorted(_glob.glob(os.path.expanduser(root))):
            if not os.path.isdir(start):
                continue
            if not walk:
                for dirpath in config_dirs_under(start):
                    for name in names:
                        path = os.path.join(dirpath, name)
                        if os.path.isfile(path):
                            out.append(path)
                continue
            base = start.rstrip("/").count("/")
            for dirpath, dirnames, filenames in os.walk(start):
                if dirpath.count("/") - base >= WALK_MAXDEPTH:
                    dirnames[:] = []
                else:
                    dirnames[:] = [d for d in dirnames if d not in WALK_SKIP]
                if not os.path.basename(dirpath).startswith(".claude"):
                    continue
                for name in names:
                    if name in filenames:
                        out.append(os.path.join(dirpath, name))
    rows = [(p, _settings_scope(p)) for p in sorted(set(out))]
    return [r for r in rows if scope is None or r[1] == scope]


def _settings_scope(path):
    real = os.path.abspath(os.path.expanduser(path))
    home = os.path.expanduser("~").rstrip("/")
    parent = os.path.dirname(real)
    if os.path.dirname(parent) == home and os.path.basename(parent).startswith(".claude"):
        return "fleet"
    if os.sep + ".worktrees" + os.sep in real:
        return "worktree"
    return "project"


def rules_in_force_for_cwd(fleet, cwd, stop_at=None, fallback=None, mode="auto"):
    """(RuleSet, 'recovered'|'unrecoverable') — the rules that governed one archived prompt.

    A project-local allow rule is not a fleet gap, so crediting one to the fleet manufactures a
    candidate that a rule already covers. 40.9% of archived rows carry a cwd that no longer exists
    (`unrecoverable`); those rows must be excluded from MIN_EVIDENCE counting by the caller, and the
    optional `fallback` RuleSet (conservatively, the union of every discovered project-local set) is
    unioned in so an unrecoverable row cannot be counted as a gap either.

    The walk climbs from cwd to `stop_at` (default: $HOME) reading every `.claude/settings*.json` on
    the way, which over-credits relative to the harness (it reads only cwd's project file and the
    git root's local file) — the safe direction for a gap count. A FLEET-scope file met on the way
    (`~/.claude/…` at the top of the walk) is skipped: it is already in `fleet`, and re-reading it
    here would resurrect allow rules that `mode='auto'` or F10 dropped from that set.
    """
    if not cwd or not os.path.isdir(cwd):
        merged = _union_rulesets(fleet, fallback, mode)
        return merged, "unrecoverable"
    found, here = [], os.path.abspath(cwd)
    stop = os.path.abspath(stop_at) if stop_at else os.path.expanduser("~")
    while True:
        for name in SETTINGS_NAMES:
            p = os.path.join(here, ".claude", name)
            if os.path.isfile(p) and _settings_scope(p) != "fleet":
                found.append(p)
        parent = os.path.dirname(here)
        if here == stop or parent == here:
            break
        here = parent
    local = load_rulesets(found, mode=mode) if found else None
    return _union_rulesets(fleet, local, mode), "recovered"


def _union_rulesets(a, b, mode):
    if b is None:
        return a
    if a is None:
        return b
    by_file = collections.OrderedDict(a.by_file)
    by_file.update(b.by_file)
    return RuleSet(
        a.allow + [r for r in b.allow if r not in a.allow],
        a.deny + [r for r in b.deny if r not in a.deny],
        a.ask + [r for r in b.ask if r not in a.ask],
        by_file,
        a.dropped + b.dropped,
    )


# ─────────────────────────── the beacon archive ───────────────────────────


def read_archive(archdir, cutoff=0):
    """(rows, bad, unreadable, files, heartbeat_age_s) — every archive row in range.

    MOVED from `_read_rows`, with the heartbeat added. Two failure modes are handled per-ROW rather
    than per-file, and that is load-bearing: the first cut wrapped the whole file loop in
    `except Exception: continue`, so a single type-corrupt field (a string `resolved_ts` meeting a
    numeric comparison) aborted every REMAINING row in that file — five ten-minute blocks reported
    as "nothing has actually blocked". A row is a row; one bad one may cost itself and nothing else.

    `heartbeat_age_s` is None when `.archive-alive` is absent. Absence of rows means one of four
    things and the caller must keep them apart: no archiver (blind), an archiver that ran and saw
    nothing (all-clear), an unreadable directory (blind), and an archiver that has STOPPED (blind —
    the heartbeat is how you tell that from the all-clear).
    """
    rows, bad, unreadable = [], 0, 0
    files = sorted(_glob.glob(os.path.join(archdir, "*.jsonl")))
    for f in files:
        try:
            fh = open(f, encoding="utf-8-sig", errors="ignore")   # utf-8-sig strips a BOM
        except OSError:
            unreadable += 1                                       # never silently an all-clear
            continue
        with fh:
            while True:
                try:
                    ln = fh.readline()
                except OSError:
                    unreadable += 1
                    break
                if not ln:
                    break
                ln = ln.strip()
                if not ln:
                    continue
                try:
                    o = json.loads(ln)
                    if not isinstance(o, dict):
                        raise ValueError("not an object")
                    rts = o.get("resolved_ts")
                    if cutoff:
                        if not isinstance(rts, (int, float)) or rts < cutoff:
                            continue
                    rows.append(o)
                except Exception:
                    bad += 1                                      # counted, never guessed at
    beat = os.path.join(archdir, ".archive-alive")
    try:
        age = time.time() - os.path.getmtime(beat)
    except OSError:
        age = None
    return rows, bad, unreadable, files, age


# ─────────────────────────── the command-log corpus ───────────────────────────
# `~/.claude/logs/bash-commands.log` is a POST-HOOK pass-through record written at
# validate-bash.sh:1341, after every deny/warn path has exited — so it is pre-scrubbed of everything
# a danger regex would look for (§10 B1-3) and is the WIDENING RECEIPT only, never a prompt count.
# Records are ANCHORED: 82% of its LINES are continuation fragments of a multi-line command
# (1,636,089 lines vs 286,466 records), so a line-wise reader over-counts by ~5.7x.
_RECORD_RE = re.compile(r"^\[(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z)\] \[([^\]]*)\] (.*)$")


def read_corpus(paths, since_ts=0):
    """iter[(epoch_ts, session_id, command)] over anchored RECORDS, `.gz` rotations included."""
    for path in paths:
        opener = gzip.open if path.endswith(".gz") else open
        try:
            fh = opener(path, "rt", encoding="utf-8-sig", errors="ignore")
        except (OSError, EOFError):
            continue
        cur = None
        with fh:
            for ln in fh:
                m = _RECORD_RE.match(ln.rstrip("\n"))
                if m is None:
                    if cur is not None:
                        cur[2].append(ln.rstrip("\n"))
                    continue
                if cur is not None and cur[0] >= since_ts:
                    yield cur[0], cur[1], "\n".join(cur[2])
                try:
                    ts = calendar.timegm(time.strptime(m.group(1), "%Y-%m-%dT%H:%M:%SZ"))
                except ValueError:
                    ts = 0
                cur = (ts, m.group(2), [m.group(3)])
        if cur is not None and cur[0] >= since_ts:
            yield cur[0], cur[1], "\n".join(cur[2])


# ───────────────────── cc-permission-audit's PRE-LIB semantics ─────────────────────
#
# 🚨 NOT THE MATCHER. These three are the loose string test `bin/cc-permission-audit` shipped before
# this file existed, moved here so ONE file holds both state models and the divergence is visible at
# the seam instead of hidden in two. New code must use `normalize_leaf` / `rule_matches_leaf`.
#
# They differ from the real matcher in exactly one measured way, and it is not cosmetic:
# `legacy_norm` strips EVERY leading `VAR=value` assignment, while an ALLOW rule sees past only the
# 39 names in ENV_ALLOWLIST (footgun F6 — `FOO=1 ls` defeats `Bash(ls:*)`). So the audit's ranking
# half treats `FOO=1 git status` as covered and the harness does not. The audit's own suite pins
# that behaviour ("leading env assignments are stripped before matching"), so changing it is a
# behaviour change with its own evidence to gather — not something a refactor may do silently.
# `legacy_matches` is also loose on the other side: its third arm `c.startswith(r)` has no space
# boundary, so `Bash(git:*)` matches `github-cli …`.


def legacy_load_rules(path):
    """(allow, deny, ask) as bare CONTENT strings with a trailing `:*` removed — pre-lib shape."""
    o = json.load(open(path))
    p = o.get("permissions", {})

    def bash_rules(key):
        out = []
        for r in p.get(key, []):
            m = re.match(r"^Bash\((.*)\)$", r)
            if m:
                pat = m.group(1)
                out.append(pat[:-2] if pat.endswith(":*") else pat)
        return out

    return bash_rules("allow"), bash_rules("deny"), bash_rules("ask")


def legacy_norm(cmd):
    """Collapse a command to the comparable prefix the pre-lib audit would match."""
    c = " ".join(cmd.strip().split())
    while True:
        m = re.match(r"^(?:[A-Za-z_][A-Za-z0-9_]*=\S*\s+)(.*)$", c)
        if not m:
            break
        c = m.group(1)
    return c


def legacy_head(cmd, n=2):
    parts = legacy_norm(cmd).split()
    return " ".join(parts[:n]) if parts else ""


def legacy_matches(cmd, rules):
    c = legacy_norm(cmd)
    for r in rules:
        if c == r or c.startswith(r + " ") or c.startswith(r):
            return r
    return None


def _selftest():
    """A five-second smoke of the load-bearing rows; the real fidelity suite is
    tests/permission-matcher.bats, one @test per row of the truth doc's tables."""
    rs = ruleset_from_lists(allow=["Bash(/bin/date:*)"])
    checks = [
        ("prefix on a compound", command_verdict("/bin/date +%s && /bin/date -u", rs).outcome, "allow"),
        ("uncovered leaf asks", command_verdict("/bin/date +%s && /bin/hostname", rs).outcome, "ask"),
        ("substitution is structural",
         command_verdict("echo $(/bin/date +%s)", rs).structural, ["command_substitution"]),
        ("quoted `<(` is not process substitution",
         split_leaves("grep -oE '<(script|style)' f | sort").structural, []),
        ("quoted `<(` still splits",
         len(split_leaves("grep -oE '<(script|style)' f | sort").leaves), 2),
        ("wrapper stripped", normalize_leaf("timeout 5 /bin/date +%s"), "/bin/date +%s"),
        ("allowlisted env stripped", normalize_leaf("LC_ALL=C /bin/date"), "/bin/date"),
        ("other env kept for allow", normalize_leaf("FOO=1 /bin/date"), "FOO=1 /bin/date"),
        ("other env stripped for deny",
         normalize_leaf("FOO=1 /bin/date", strip_all_env=True), "/bin/date"),
        ("wildcard tail is optional",
         rule_matches_leaf(parse_rule("Bash(git status *)"), "git status"), True),
        ("exact is byte-exact",
         rule_matches_leaf(parse_rule("Bash(git status)"), "git  status"), False),
        ("the splitter does not collapse a leaf's interior whitespace",
         command_verdict("/usr/bin/basename  foo",
                         ruleset_from_lists(allow=["Bash(/usr/bin/basename foo)"])).outcome, "ask"),
        ("auto drops python3", bool(auto_mode_dropped("Bash(python3:*)")), True),
        ("git rebase is ARG_EXEC", bool(arg_exec_reason("git rebase")), True),
        ("git rebase --abort pins past", arg_exec_reason("git rebase --abort"), None),
        ("a heredoc body is data, not leaves",
         split_leaves("cat > f <<'EOF'\nrm -rf /\nEOF\nls").leaves, ["cat > f <<'EOF'", "ls"]),
        ("an unterminated heredoc is unbalanced",
         "unbalanced" in split_leaves("cat <<EOF\nbody").structural, True),
        ("Rule is the four-field §4 shape", len(parse_rule("Bash(ls:*)")), 4),
        ("RuleSet is the five-field §4 shape", len(ruleset_from_lists()), 5),
    ]
    bad = [(n, got, want) for n, got, want in checks if got != want]
    for name, got, want in bad:
        sys.stderr.write("FAIL %s: %r != %r\n" % (name, got, want))
    sys.stdout.write("permission_matcher selftest: %d/%d\n" % (len(checks) - len(bad), len(checks)))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(_selftest() if "--selftest" in sys.argv[1:] else 0)
