#!/usr/bin/env bash
# Argv-level detectors for hooks/validate-bash.sh. Three functions, one model: a command STRING is
# not argv, so every question about "is this really being executed" is answered after tokenizing.
#   is_true_flag          <flag> <cmd>  — is <flag> a real argv token, or just text in a body?
#   rm_argv_scan          <cmd>         — normalize each `rm` to (recursive, force, target)
#   strip_heredoc_bodies  <cmd>         — drop every heredoc BODY; what is left can be argv
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

# ── git_add_force_scan — argv normalization for `git add --force` ──────────────────────────────
#
# WHY a third detector, and not two more is_true_flag calls: `git add -f` is a TWO-part predicate —
# a force flag AND the invocation it belongs to — and is_true_flag answers only the first half, for
# the WHOLE command string. The caller then had to re-associate the two by hand, with a separate
# `grep 'git[[:space:]]+add'`, and a command string is not one invocation:
#
#     rm -f f.txt && git add f.txt        DENY   ← the -f is rm's; the git add is innocent
#     grep -f pats.txt in.txt && git add out.txt   DENY
#     git add out.txt && rsync -f rules a b       DENY
#
# The deny even named a thing the command does not do ("git add -f blocked"), which is how it was
# found: a plain `git add f.txt` in a throwaway fixture repo was refused mid-investigation, on a
# line whose only `-f` belonged to the `rm` that made the fixture (backlog 44750ff72ae7; the same
# pair of clauses is finding 1 of tests/fixtures/codex-probe/runs/cp-01__D.md).
#
# And the mirror-image half, which is the more dangerous one: the flag had to be spelled EXACTLY
# `-f` or `--force` as its own argv token, so the guard's actual purpose — refusing a force-add of
# a gitignored file — walked past every bundle and every global-option prefix:
#
#     git add -fv ignored.bin             PASS   ← same flag, company in the bundle
#     git add -Af node_modules            PASS
#     git -C /tmp/x add -f ignored.bin    PASS   ← `add` is not argv[1] when git has a global opt
#     git add --forc x                    PASS   ← parse-options takes any unambiguous abbreviation
#     git stage -f ignored.bin            PASS   ← `stage` is git's own synonym for `add`
#
# Both halves are ONE defect — a denylist that enumerates SPELLINGS instead of naming the class
# (memory: denylist-enumerates-spellings-not-the-class) — and both are answered the same way
# rm_argv_scan answers it above: tokenize, find the invocation, and read the flag off ITS argv.
#
# Contract:
#   git_add_force_scan <command>
#   stdout: one TAB-separated line per real `git add` / `git stage` invocation:
#             <force 0|1> \t <the argv token that proves it, or '-'>
#           No git-add invocation → empty stdout, exit 0.
#   exit 0 → scan completed; stdout is the whole truth
#   exit 2 → UNCLEAR (python3 absent, or shlex could not tokenize) — caller MUST fall back to text
#            matching and must not read an empty stdout as "nothing found" (the fail-open shape).
#
# Found wherever the invocation really is: `sudo git add`, `env X=1 git add`, `/usr/bin/git add`,
# `xargs git add`, `bash -c 'git add …'`, `eval git add …` — same walk as rm_argv_scan, for the
# same reason. Deliberately NOT normalized: the pathspecs. Which paths are gitignored is git's
# question, not this library's, and the rule does not depend on the answer.
git_add_force_scan() {
  local cmd="$1"

  _git_add_unclear() { # <cause>
    mkdir -p "${HOME}/.claude/logs" 2>/dev/null || true
    printf '%s\t%s\t%s\n' \
      "$(date -u +%FT%TZ 2>/dev/null || echo '?')" \
      "git-add-force-scan-UNCLEAR($1)" "text fallback, argv NOT parsed: $cmd" \
      >> "${HOME}/.claude/logs/validate-bash-unclear.log" 2>/dev/null || true
  }

  if ! command -v python3 >/dev/null 2>&1; then
    _git_add_unclear "python3-absent"
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

# git's own global options that CONSUME the next token. Without them the subcommand walk below
# reads `/tmp/x` as the subcommand of `git -C /tmp/x add -f` and the invocation disappears.
GIT_VALUE_GLOBALS = {
    "-C", "-c", "--git-dir", "--work-tree", "--namespace",
    "--exec-path", "--config-env", "--super-prefix", "--attr-source",
}
# `git stage` is git's own documented synonym for `git add` — a spelling, not a different command.
ADD_ALIASES = {"add", "stage"}


def subcommand_index(argv, i):
    """argv[i] is the git token → index of its subcommand, or None."""
    j = i + 1
    while j < len(argv):
        tok = argv[j]
        if not tok.startswith("-"):
            return j
        if "=" not in tok and tok in GIT_VALUE_GLOBALS:
            j += 2
        else:
            j += 1
    return None


def force_token(rest):
    """The argv token that makes this a force-add, or None. Last one wins (it is the same flag)."""
    found = None
    end_of_flags = False
    for tok in rest:
        if end_of_flags:
            continue
        if tok == "--":                    # everything after is a pathspec: `git add -- -f.txt`
            end_of_flags = True
            continue
        if tok.startswith("--") and len(tok) > 2:
            name = tok.split("=", 1)[0]
            # parse-options accepts any UNAMBIGUOUS abbreviation, and --force is the only long
            # option of `git add` that begins with f — so --f … --force all mean force. The
            # auto-generated negation `--no-force` is a different name and does not match.
            if len(name) >= 3 and "--force".startswith(name):
                found = tok
            continue
        if len(tok) > 1 and tok.startswith("-"):
            # A bundle: order and company are irrelevant, and no short option of `git add` takes
            # an inline value, so a bare `f` among the letters is the force flag.
            if "f" in tok[1:]:
                found = tok
            continue
    return found


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
    if depth > 3:
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
        head = os.path.basename(argv[0])
        if head in SHELL_HEADS:
            for i in range(1, len(argv) - 1):
                if argv[i] == "-c":
                    out.extend(scan(argv[i + 1], depth + 1))
                    break
        elif head == "eval":
            out.extend(scan(" ".join(argv[1:]), depth + 1))

        # EVERY position, for the reason rm_argv_scan gives: sudo/env/time/xargs all place the
        # real command mid-argv. A MENTION survives as one quoted token ("never git add -f"),
        # whose basename is never "git" — that is what keeps a commit message describing this
        # rule committable.
        for i, tok in enumerate(argv):
            if os.path.basename(tok) != "git":
                continue
            si = subcommand_index(argv, i)
            if si is None or argv[si] not in ADD_ALIASES:
                continue
            out.append(force_token(argv[si + 1:]))
    return out


try:
    results = scan(CMD)
except ValueError:                         # unbalanced quotes → the caller must fall back
    sys.exit(3)

for tok in results:
    safe = "-" if tok is None else "".join((c if ord(c) >= 32 else "?") for c in tok)
    sys.stdout.write("%d\t%s\n" % (0 if tok is None else 1, safe))
PYEOF
  )
  rc=$?

  if [[ "$rc" != "0" ]]; then
    _git_add_unclear "unparseable"
    return 2
  fi

  [[ -n "$out" ]] && printf '%s\n' "$out"
  return 0
}

# ── strip_heredoc_bodies — the same "text is not execution" question, one layer out.
#
#   strip_heredoc_bodies <command>
#     stdout = <command> with every heredoc BODY and its terminator line REMOVED, and each
#              `<<DELIM` operator replaced by the token HEREDOC_INPUT_SENTINEL.
#     exit 0, always. This is a TOTAL function: there is no UNCLEAR, so no caller needs a
#     fallback branch for a parse that failed — only for the library being absent.
#
# WHY a caller wants it: a heredoc body is INPUT. `git commit -F - <<'MSG' … MSG` hands its body to
# git's stdin, so nothing inside it is ever a command, a flag or a target — exactly like the inside
# of a quoted string, except that a quote-stripping pass leaves it completely untouched. Any
# detector that decides on the raw command string therefore convicts prose, and it does so on the
# one input shape (a multi-line commit message) whose whole purpose is to DESCRIBE the thing the
# detector blocks. Measured: backlog 15b99887cd5e.
#
# WHY it exists BESIDE the strip_heredocs() inside is_true_flag's python: that one must keep the
# body CONTENTS, because its entire job is to answer "was the flag in the body?" — it cannot be
# reduced to "print the source without bodies". This one is only that, and it is called on the hot
# path of EVERY Bash tool call, so it answers in ~2 ms of awk instead of ~30 ms of python fork. The
# GRAMMAR is deliberately identical to that function's, so the two cannot disagree about what a
# heredoc IS: `<<` or `<<-`, an optional ' " or \ quoting of the delimiter, and a delimiter word of
# [A-Za-z_][A-Za-z0-9_]*.
#
# Two deliberate imprecisions, both chosen so a miss OVER-blocks (the caller's safe direction)
# rather than under-blocks:
#   · quote state is tracked PER LINE, so `-m "we replaced <<EOF"` is not read as an opener. An
#     apostrophe that desynchronises that state costs a real heredoc going unstripped — which is
#     the OLD behaviour, an over-block — and never a real opener being swallowed.
#   · `<<<` is a herestring, not an opener, and neither is the second `<` of one. Reading it as an
#     opener would silently delete every following line of a compound command: the under-block.
strip_heredoc_bodies() {
  local cmd="$1"

  # Layer 1, as everywhere in this file: no `<<` at all → the answer is the input, zero forks.
  if [[ "$cmd" != *'<<'* ]]; then
    printf '%s' "$cmd"
    return 0
  fi

  # printf, never echo: a body may legitimately begin with `-n` or contain backslash escapes.
  # The quote CHARACTERS arrive as -v variables so the awk program needs neither of them in its
  # own source, and can therefore stay one shell single-quoted string with nothing escaped.
  printf '%s' "$cmd" | awk -v SQ="'" -v DQ='"' '
    function pop_body(   i) {            # start the next queued body, or leave body mode
      if (qn == 0) { body = 0; return }
      bdelim = qd[1]; btabs = qt[1]
      for (i = 1; i < qn; i++) { qd[i] = qd[i+1]; qt[i] = qt[i+1] }
      qn--
      body = 1
    }
    function scan(line,   out, i, n, k, c, q, d, sq, dq, tabs) {
      out = ""; i = 1; n = length(line); sq = 0; dq = 0
      while (i <= n) {
        c = substr(line, i, 1)
        if (c == SQ && dq == 0) { sq = 1 - sq; out = out c; i++; continue }
        if (c == DQ && sq == 0) { dq = 1 - dq; out = out c; i++; continue }
        if (sq == 0 && dq == 0 && substr(line, i, 2) == "<<" &&
            substr(line, i + 2, 1) != "<" &&
            (i == 1 || substr(line, i - 1, 1) != "<")) {
          k = i + 2
          tabs = 0
          if (substr(line, k, 1) == "-") { tabs = 1; k++ }
          while (k <= n && (substr(line, k, 1) == " " || substr(line, k, 1) == "\t")) k++
          q = substr(line, k, 1)
          if (q == SQ || q == DQ) { k++ } else { if (q == "\\") k++; q = "" }
          d = ""
          while (k <= n && substr(line, k, 1) ~ /^[A-Za-z0-9_]$/) { d = d substr(line, k, 1); k++ }
          if (d ~ /^[A-Za-z_]/ && (q == "" || substr(line, k, 1) == q)) {
            if (q != "") k++
            qn++; qd[qn] = d; qt[qn] = tabs
            out = out "HEREDOC_INPUT_SENTINEL"
            i = k
            continue
          }
        }
        out = out c; i++
      }
      return out
    }
    BEGIN { qn = 0; body = 0 }
    {
      if (body) {
        t = $0
        if (btabs) sub(/^\t+/, "", t)   # `<<-` strips leading TABS from the terminator, only tabs
        if (t == bdelim) pop_body()
        next                             # body line and terminator line alike: never argv
      }
      print scan($0)
      if (qn > 0) pop_body()             # a body opened on this line begins on the next
    }
  '
}
