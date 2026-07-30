#!/usr/bin/env bash
# Argv-level detectors for hooks/validate-bash.sh. Two functions, one model: a command STRING is
# not argv, so every question about "is this really being executed" is answered after tokenizing.
#   is_true_flag  <flag> <cmd>   — is <flag> a real argv token, or just text in a message body?
#   rm_argv_scan  <cmd>          — normalize every `rm` invocation to (recursive, force, target)
#
# ── is_true_flag — layered detector for real argv flags vs. substring-only matches.
#
# Problem: naive grep on bash command strings false-positives when the flag
# substring appears inside a quoted message body, heredoc, or similar payload.
# Example: `git commit -m "discuss --no-verify policy"` — the string --no-verify
# is NOT an argv flag to git, just text, so it should not trigger a block.
#
# Contract:
#   is_true_flag <flag> <command>
#   exit 0 → flag IS a real argv token in a non-inert command (BLOCK)
#   exit 1 → substring only, not an argv flag (ALLOW)
#   exit 2 → unclear / parse failure (FAIL SAFE: caller should BLOCK + log)
#
# Dependencies: python3 (stdlib shlex). If absent → exit 2.
# Budget: ~4ms absent path, ~32ms present path.
#
# Design:
#   Layer 1 (fast, ~1ms): `grep -qF` short-circuit on literal substring.
#   Layer 2 (accurate, ~30ms): shlex.split + heredoc pre-strip + per-clause
#     argv analysis with awareness of message-body flags (-m / -F / etc.) for
#     known message commands (git commit, git tag, git merge, git notes,
#     git revert, git cherry-pick, hg commit, svn commit) and inert heads
#     (echo, printf, cat, tee, true, :).
#
# Fail-safe: ValueError from shlex (unclosed quotes) → UNCLEAR → caller blocks.
# Rollback: set VALIDATE_BASH_LEGACY=1 in caller to fall back to regex-only.

is_true_flag() {
  local flag="$1"
  local cmd="$2"

  # ── Layer 1 (fast): literal substring check. If flag never appears anywhere,
  #                    we can short-circuit without forking python. ~1ms.
  if ! printf '%s' "$cmd" | grep -qF -- "$flag"; then
    return 1  # absent → allow
  fi

  # ── Layer 2 (accurate): tokenize + argv-position analysis via python3.
  #                        Writes decision to stdout: REAL | SUBSTR | UNCLEAR.
  command -v python3 >/dev/null 2>&1 || return 2

  local decision
  decision=$(FLAG="$flag" CMD="$cmd" python3 - <<'PYEOF' 2>/dev/null
import os
import re
import shlex
import sys

FLAG = os.environ.get("FLAG", "")
CMD = os.environ.get("CMD", "")


# Heredoc stripping: shlex doesn't understand heredocs, so we pre-strip their
# bodies to a sentinel. A heredoc body is never considered argv, but any FLAG
# substring inside the body is remembered for the SUBSTR decision.
def strip_heredocs(src):
    flag_in_body = False
    pat = re.compile(r"(<<-?)\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\2")
    out_parts = []
    pos = 0
    while True:
        m = pat.search(src, pos)
        if not m:
            out_parts.append(src[pos:])
            break
        out_parts.append(src[pos:m.start()])
        out_parts.append("HEREDOC_INPUT_SENTINEL")
        delim = m.group(3)
        allow_tabs = m.group(1) == "<<-"
        nl = src.find("\n", m.end())
        if nl < 0:
            pos = m.end()
            continue
        body_start = nl + 1
        body_end = body_start
        i = body_start
        while i < len(src):
            line_end = src.find("\n", i)
            if line_end < 0:
                line = src[i:]
                next_i = len(src)
            else:
                line = src[i:line_end]
                next_i = line_end + 1
            terminator = line.lstrip("\t") if allow_tabs else line
            if terminator == delim:
                body_end = i
                pos = next_i
                break
            i = next_i
        else:
            body_end = len(src)
            pos = len(src)
        body = src[body_start:body_end]
        if FLAG and FLAG in body:
            flag_in_body = True
    return ("".join(out_parts), flag_in_body)


CMD, HEREDOC_HAD_FLAG = strip_heredocs(CMD)

# Commands that legitimately receive arbitrary strings as message bodies.
MESSAGE_COMMANDS = {
    ("git", "commit"),
    ("git", "tag"),
    ("git", "merge"),
    ("git", "notes"),
    ("git", "revert"),
    ("git", "cherry-pick"),
    ("hg", "commit"),
    ("svn", "commit"),
}
MESSAGE_FLAGS = {"-m", "--message", "-F", "--file", "-C", "--reuse-message"}
INERT_HEADS = {"echo", "printf", "cat", "tee", "true", ":"}

try:
    tokens = shlex.split(CMD, comments=True, posix=True)
except ValueError as e:
    print("UNCLEAR")
    sys.exit(0)

if not tokens:
    print("SUBSTR")
    sys.exit(0)

PIPELINE_OPS = {"|", "||", "&&", ";", "&"}
clauses = [[]]
for tok in tokens:
    if tok in PIPELINE_OPS:
        clauses.append([])
    else:
        clauses[-1].append(tok)
clauses = [c for c in clauses if c]


def strip_env_prefix(argv):
    i = 0
    while i < len(argv) and "=" in argv[i] and not argv[i].startswith("-"):
        name = argv[i].split("=", 1)[0]
        if name and (name[0].isalpha() or name[0] == "_") and all(c.isalnum() or c == "_" for c in name):
            i += 1
        else:
            break
    return argv[i:]


real_hit = False
substr_hit = False

for argv in clauses:
    argv = strip_env_prefix(argv)
    if not argv:
        continue
    head = argv[0]
    sub = argv[1] if len(argv) > 1 else None
    cmd_key = (head, sub) if sub else None

    is_message_cmd = cmd_key in MESSAGE_COMMANDS
    is_inert = head in INERT_HEADS

    skip_next = False
    for i, tok in enumerate(argv):
        if skip_next:
            skip_next = False
            if tok == FLAG or FLAG in tok:
                substr_hit = True
            continue

        if is_message_cmd and tok in MESSAGE_FLAGS:
            skip_next = True
            continue

        if is_message_cmd and "=" in tok:
            lhs = tok.split("=", 1)[0]
            if lhs in MESSAGE_FLAGS:
                if FLAG in tok:
                    substr_hit = True
                continue

        if tok == FLAG:
            if is_inert:
                substr_hit = True
            else:
                real_hit = True
        elif FLAG in tok:
            substr_hit = True

if real_hit:
    print("REAL")
elif substr_hit or HEREDOC_HAD_FLAG:
    print("SUBSTR")
else:
    print("SUBSTR")
PYEOF
  )

  case "$decision" in
    REAL)    return 0 ;;
    SUBSTR)  return 1 ;;
    *)
      mkdir -p "${HOME}/.claude/logs"
      printf '%s\t%s\t%s\n' \
        "$(date -u +%FT%TZ)" "$flag" "$cmd" \
        >> "${HOME}/.claude/logs/validate-bash-unclear.log"
      return 2
      ;;
  esac
}

# ── rm_argv_scan — argv normalization for `rm` invocations ─────────────────────────────────────
#
# Why a second detector and not more is_true_flag calls: the catastrophic-rm rule is not "does
# flag X appear anywhere", it is a THREE-part predicate — recursive AND force AND a catastrophic
# target — and each part has several equivalent spellings. Answering it one flag at a time leaves
# the caller to re-associate flags with the invocation they belong to, which is where the original
# hardcoded `-rf` regex went wrong: `rm -rf src && rm -rf /` is ONE command string and TWO
# invocations, and only the second one is fatal.
#
# Contract:
#   rm_argv_scan <command>
#   stdout: one TAB-separated line per (rm invocation × target):
#             <recursive 0|1> \t <force 0|1> \t <target>
#           No real rm invocation, or an rm with no targets → empty stdout, exit 0.
#   exit 0 → scan completed; stdout is the whole truth
#   exit 2 → UNCLEAR (python3 absent, or shlex could not tokenize) — caller MUST fall back and
#            must not read an empty stdout as "nothing found" (that is the fail-open shape).
#
# Spellings normalized (every one of these reports recursive=1 force=1):
#   -rf · -fr · -Rf · -r -f · -f -r · -rvf · --recursive --force · -r --force · … -- <target>
# and the invocation is found wherever it really is: `sudo rm`, `env X=1 rm`, `time rm`,
# `/bin/rm`, `find . -exec rm …`, `xargs rm …`, `bash -c 'rm …'`, `eval rm …`.
#
# Deliberately NOT normalized: the target itself. shlex removes quoting ("$HOME" → $HOME) but
# nothing is expanded and no tilde is resolved, so the caller matches the LITERAL argv text and
# the policy of WHICH targets are catastrophic stays in the hook, not in this library.
rm_argv_scan() {
  local cmd="$1"

  # An UNCLEAR must never be silent. It does not fail OPEN here — the caller falls back to text
  # matching, which still denies — but that fallback also over-blocks message bodies, so when an
  # operator asks "why was my commit message refused", this line is the answer. Both causes are
  # logged, which is why this is a function and not the early `return 2` its sibling above uses.
  _rm_argv_unclear() { # <cause>
    mkdir -p "${HOME}/.claude/logs" 2>/dev/null || true
    printf '%s\t%s\t%s\n' \
      "$(date -u +%FT%TZ 2>/dev/null || echo '?')" \
      "rm-argv-scan-UNCLEAR($1)" "text fallback, argv NOT parsed: $cmd" \
      >> "${HOME}/.claude/logs/validate-bash-unclear.log" 2>/dev/null || true
  }

  if ! command -v python3 >/dev/null 2>&1; then
    _rm_argv_unclear "python3-absent"
    return 2
  fi

  local out rc
  out=$(CMD="$cmd" python3 - <<'PYEOF' 2>/dev/null
import os
import shlex
import sys

CMD = os.environ.get("CMD", "")

PIPELINE_OPS = {"|", "||", "&&", ";", ";;", "&"}
SHELL_HEADS = {"bash", "sh", "zsh", "ksh", "dash"}


def parse_rm(argv):
    """argv[0] is the rm token. → (recursive, force, [targets])."""
    recursive = force = False
    targets = []
    end_of_flags = False
    for tok in argv[1:]:
        if not end_of_flags and tok == "--":
            end_of_flags = True
            continue
        if not end_of_flags and tok.startswith("--") and len(tok) > 2:
            name = tok.split("=", 1)[0]
            if name == "--recursive":
                recursive = True
            elif name == "--force":
                force = True
            continue                       # any other long flag (--no-preserve-root, …)
        if not end_of_flags and len(tok) > 1 and tok.startswith("-"):
            for ch in tok[1:]:             # a bundle: order and company are irrelevant
                if ch in ("r", "R"):
                    recursive = True
                elif ch == "f":
                    force = True
            continue
        targets.append(tok)
    return (recursive, force, targets)


def strip_env_prefix(argv):
    i = 0
    while i < len(argv) and "=" in argv[i] and not argv[i].startswith("-"):
        name = argv[i].split("=", 1)[0]
        if name and (name[0].isalpha() or name[0] == "_") and all(c.isalnum() or c == "_" for c in name):
            i += 1
        else:
            break
    return argv[i:]


def scan(src, depth=0):
    out = []
    if depth > 3:                          # bounded: `bash -c "bash -c …"` cannot recurse forever
        return out
    tokens = shlex.split(src, comments=True, posix=True)
    clauses = [[]]
    for tok in tokens:
        if tok in PIPELINE_OPS:
            clauses.append([])
        else:
            clauses[-1].append(tok)

    for argv in clauses:
        argv = strip_env_prefix(argv)
        if not argv:
            continue
        # A nested shell hides its whole command inside ONE string argument, so without
        # re-scanning it `bash -c 'rm -rf /'` reads as a bash invocation with no rm in it.
        head = os.path.basename(argv[0])
        if head in SHELL_HEADS:
            for i in range(1, len(argv) - 1):
                if argv[i] == "-c":
                    out.extend(scan(argv[i + 1], depth + 1))
                    break
        elif head == "eval":
            out.extend(scan(" ".join(argv[1:]), depth + 1))

        # EVERY position, not just argv[0] — `sudo rm`, `time rm`, `find . -exec rm …`,
        # `xargs rm …` all place rm mid-argv. A MENTION survives as a single quoted token
        # ("fix: rm -rf / bug"), whose basename is never "rm"; that is precisely what keeps a
        # commit message describing this rule from being read as an execution of it.
        for i, tok in enumerate(argv):
            if os.path.basename(tok) == "rm":
                out.append(parse_rm(argv[i:]))
    return out


try:
    results = scan(CMD)
except ValueError:                         # unbalanced quotes → the caller must fall back
    sys.exit(3)

for recursive, force, targets in results:
    for t in targets:
        # Control characters would break the TSV line framing. No catastrophic target contains
        # one, so folding them can only cost a WARN precision, never hide a DENY.
        safe = "".join((c if ord(c) >= 32 else "?") for c in t)
        sys.stdout.write("%d\t%d\t%s\n" % (1 if recursive else 0, 1 if force else 0, safe))
PYEOF
  )
  rc=$?

  if [[ "$rc" != "0" ]]; then
    _rm_argv_unclear "unparseable"
    return 2
  fi

  [[ -n "$out" ]] && printf '%s\n' "$out"
  return 0
}
