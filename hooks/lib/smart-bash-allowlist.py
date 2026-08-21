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
    ("$(", "command substitution"),
    ("`", "backtick substitution"),
    ("<(", "process substitution"),
    (">(", "process substitution"),
    ("${!", "indirect expansion"),
    ("<<", "heredoc"),
)

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
        m = _LOOP_HEAD.match(s)
        if m:
            s = m.group(1).strip()
            changed = True
            continue
        head = s.split(" ", 1)[0]
        if head in KEYWORDS:
            s = s[len(head) :].strip()
            changed = True
            continue
        m = _ENV_ASSIGN.match(s)
        if m:  # leading FOO=bar assignments are not the decided verb
            s = m.group(3).strip()
            changed = True
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


SED_N_SCRIPT = [
    re.compile(r"^[0-9]+(,[0-9]+|,\$)?[p=l]$"),
    re.compile(r"^\$[p=l]$"),
    re.compile(r"^/[^/]*/(,/[^/]*/)?[p=l]$"),
    re.compile(r"^[0-9]+,/[^/]*/[p=l]$"),
]

SAFE_CHMOD = {"644", "755", "600", "700", "750", "640", "+x", "u+x"}


def _unquote(tok):
    if len(tok) >= 2 and tok[0] == tok[-1] and tok[0] in "'\"":
        return tok[1:-1]
    return tok


def allowed_segment(seg):
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

    return None


# ── entry point ──────────────────────────────────────────────────────────────────────
def decide(cmd):
    """(decision, reason). decision is 'allow' or None (defer)."""
    if not cmd or not cmd.strip():
        return None, "empty command"

    why = danger(cmd)
    if why:
        return None, f"danger pattern: {why}"

    fence, fence_ok = load_fence()
    if not fence_ok:
        return None, "fence unreadable — refusing to decide"

    segs, ok = split_segments(cmd)
    if not ok:
        return None, "could not decompose the command with confidence"

    reasons, judged = [], 0
    for raw in segs:
        seg = normalize(raw)
        if not seg:
            continue
        crossed = crosses_fence(seg, fence)
        if crossed:
            return None, f"segment is behind the operator's own gate: {crossed}"
        r = allowed_segment(seg)
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
