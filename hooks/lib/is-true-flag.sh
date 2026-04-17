#!/usr/bin/env bash
# is_true_flag — layered detector for real argv flags vs. substring-only matches.
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
