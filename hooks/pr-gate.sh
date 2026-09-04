#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════════════════════
# pr-gate.sh — PreToolUse/Bash. Ask whether a PR should exist; refuse one that buries its answer.
# ═══════════════════════════════════════════════════════════════════════════════════════════════
# WHY: the shipped /pr command used to prescribe "Summary of changes (bullet points)", which is
#   the defect Minto names directly — a category where an idea belongs. "There are three changes"
#   tells the reader the KIND and not the IDEA. /pr now teaches the opposite; this hook is what
#   makes it hold when nobody types /pr, which is the common path.
#
# WHAT IT CHECKS — three things, in the order that matters, and the shortness is deliberate.
#   0. SHOULD THIS PR EXIST — a solo repo with no reviewer named gets ASKED, because a PR you
#      open, approve and merge yourself reviews nothing. Existence outranks shape: polishing
#      the description of a PR that should not have been opened is a local optimum, and this
#      file was guilty of exactly that for its first day of life.
#   1. LEADS WITH THE ANSWER — the first content line asserts something. Not a heading, not a
#      bullet, not boilerplate ("Summary of changes", "This PR contains").
#   2. IS CONCISE — body under CC_PR_MAX_WORDS (default 400).
#
# Checks 1 and 2 DENY (mechanical defects, no legitimate case). Check 0 ASKS (a judgement with
# real exceptions the hook cannot observe). Matching the verdict to the certainty is the design.
#
# WHAT IT DELIBERATELY DOES NOT CHECK, and why refusing to was the whole design problem:
#   No demanded sections. No Situation/Complication/Resolution headers. No "must contain a Risk
#   line". Every one of those would MANUFACTURE prose to satisfy a checker — a gate that makes
#   descriptions longer in the name of a method whose entire point is getting to the answer
#   faster. This gate can only ever DELETE a defect, never require an addition.
#
# THE HONEST LIMIT: pyramid compliance is semantic and a hook is syntactic. This cannot tell
#   whether line 1 is genuinely the answer — only that it is shaped like an assertion rather
#   than a label. It catches the mechanical defect and is silent on the interesting one. That is
#   worth having precisely because the mechanical defect is the one that recurs.
#
# FAIL-OPEN everywhere: this sits on the global PreToolUse/Bash chain, where a hook failure must
#   never block a tool by accident. Every error path exits 0 silently.
#
# Kill switch: CC_PR_PYRAMID=off
# ═══════════════════════════════════════════════════════════════════════════════════════════════

[ "$CC_PR_PYRAMID" = "off" ] && exit 0

INPUT=$(cat 2>/dev/null) || exit 0
[ -n "$INPUT" ] || exit 0

# ── FAST PATH ────────────────────────────────────────────────────────────────────────────────
# Nearly every Bash call in every session reaches this line and must leave immediately. A raw
# substring test on the payload costs a few ms; anything heavier is paid by commands that have
# nothing to do with PRs. Only a payload naming `gh pr create`/`gh pr edit` goes further.
case "$INPUT" in
  *"gh pr create"*|*"gh pr edit"*) ;;
  *) exit 0 ;;
esac

command -v jq >/dev/null 2>&1 || exit 0
command -v python3 >/dev/null 2>&1 || exit 0

CMD=$(printf '%s' "$INPUT" | jq -r '
  if (.tool_name // "") == "Bash" then (.tool_input.command // "") else "" end' 2>/dev/null) || exit 0
[ -n "$CMD" ] || exit 0

# Re-test the PARSED command. The fast path matched raw payload bytes, which can hit on a
# transcript quotation rather than a command actually being run.
case "$CMD" in
  *"gh pr create"*|*"gh pr edit"*) ;;
  *) exit 0 ;;
esac

# ── CHECK 0: SHOULD THIS PR EXIST AT ALL? ─────────────────────────────────────────────────────
# This runs FIRST because existence outranks shape. Polishing the description of a PR that
# should not have been opened is a local optimum — measured, on this machine: a solo repo took
# a change through a branch, a PR, a self-merge and a branch deletion, drew ZERO reviews, was
# gated by NO branch protection, and burned 6 CI runs where a direct push takes 2. Every other
# commit in that repo had gone straight to main, correctly.
#
# THE VERDICT IS "ask", NOT "deny", and the difference is the whole point. A body that opens
# with a bullet is a defect with no legitimate case, so it is refused. Whether a PR is warranted
# is a JUDGEMENT with real exceptions — a protected branch that requires one, an outside
# reviewer, a public repo where the PR is the discussion. A hook cannot see branch protection
# without a network call it has no business making on the PreToolUse path, so it must not
# pretend to settle what it cannot observe. It raises the question and a human answers it.
#
# Kill switch for the whole file is CC_PR_PYRAMID=off; to answer just this one in advance,
# name a reviewer: `--reviewer <who>` on the command, or PR_REVIEWER=<who> in the environment.
# 🚨 A COMMAND-POSITION test, not a substring one. `*"gh pr create"*` also matches prose that
# merely mentions it — `echo 'run gh pr create later'` — and this check has no shlex parse behind
# it to catch that the way the body checks do (they exit when no --body is found). So: the phrase
# must sit at the start of the string or immediately after a separator, optionally behind env
# assignments. `echo "; gh pr create"` still slips through; that errs toward ASK, which is the
# safe direction for a question a human answers anyway.
if printf '%s' "$CMD" | grep -Eq '(^|[;&|]|&&|\|\|)[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*gh[[:space:]]+pr[[:space:]]+create([[:space:]]|$)'; then
    if [ -z "${PR_REVIEWER:-}" ] && ! printf '%s' "$CMD" | grep -Eq -- '(--reviewer|[[:space:]]-r)[[:space:]=]'; then
      PR_CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // ""' 2>/dev/null)
      [ -d "$PR_CWD" ] || PR_CWD=$PWD
      # Local proxy for "is anyone else here": distinct author emails in recent history.
      # Bounded at 500 commits so this stays cheap on a large repo.
      AUTHORS=$(git -C "$PR_CWD" log -500 --format='%ae' 2>/dev/null | sort -u | grep -c . || echo 0)
      if [ "$AUTHORS" = "1" ]; then
        SOLO_MSG="every commit in this repo's recent history has ONE author, and no reviewer is \
requested — so this PR would be opened, approved and merged by the same person. That is \
ceremony, not review: it gates nothing a direct push does not, and it costs an extra branch, \
merge, branch deletion and duplicate CI run.

Push to the trunk instead. If a PR IS warranted here — a protected branch that requires one, \
an outside reviewer, or a public repo where the PR is the discussion — say so by naming the \
reviewer (\`--reviewer <who>\`, or PR_REVIEWER=<who>) and this will not ask again."
        jq -nc --arg m "$SOLO_MSG" '{
          hookSpecificOutput: {
            hookEventName: "PreToolUse",
            permissionDecision: "ask",
            permissionDecisionReason: ("PR necessity: " + $m)
          }
        }'
        exit 0
      fi
    fi
fi

VERDICT=$(printf '%s' "$CMD" | CC_PR_MAX_WORDS="${CC_PR_MAX_WORDS:-400}" python3 -c '
import os, re, shlex, sys

try:
    cmd = sys.stdin.read()
    try:
        argv = shlex.split(cmd)
    except ValueError:
        sys.exit(0)          # unbalanced quotes — not ours to adjudicate

    body = None
    for i, a in enumerate(argv):
        if a in ("--body", "-b") and i + 1 < len(argv):
            body = argv[i + 1]
        elif a.startswith("--body="):
            body = a.split("=", 1)[1]
        elif a in ("--body-file", "-F") and i + 1 < len(argv):
            p = argv[i + 1]
            if p == "-":
                sys.exit(0)   # body on stdin — unreadable here, stay out of the way
            try:
                body = open(os.path.expanduser(p)).read()
            except OSError:
                sys.exit(0)

    if body is None:
        sys.exit(0)           # --fill, --web, or an edit not touching the body

    # Strip HTML comments (PR templates are full of them) and fenced code, which is legitimately
    # allowed to start with anything at all.
    text = re.sub(r"<!--.*?-->", "", body, flags=re.S)
    lines, fence = [], False
    for ln in text.splitlines():
        if ln.lstrip().startswith("```"):
            fence = not fence
            continue
        if not fence:
            lines.append(ln)

    content = [ln for ln in lines if ln.strip()]
    if not content:
        sys.exit(0)           # an empty body is a different problem, not this one

    first = content[0].strip()
    words = len(" ".join(lines).split())
    cap = int(os.environ.get("CC_PR_MAX_WORDS", "400"))

    # (1) LEADS WITH THE ANSWER
    if first.startswith("#"):
        print("LABEL|the body opens with the heading %r. A heading names the KIND of thing "
              "below it; line 1 should be the IDEA — one sentence saying what is now true "
              "that was not. Put the heading second, or drop it." % first[:60])
        sys.exit(0)
    if re.match(r"^([-*+]|\d+[.)])\s", first):
        print("LIST|the body opens with a list item (%r). A list is the level BELOW the answer: "
              "it tells the reader there are N things without saying what they add up to. State "
              "the conclusion first, then let the list support it." % first[:60])
        sys.exit(0)
    m = re.match(r"^(summary of changes|changes made|overview|description|what changed|"
                 r"this (pr|mr|change|patch) (contains|includes)|list of changes)\b",
                 first, re.I)
    if m:
        print("BOILER|the body opens with %r, which is a label rather than an assertion. "
              "Replace it with the answer itself — what a reviewer would need to know if "
              "they read nothing else." % m.group(0))
        sys.exit(0)

    # (2) IS CONCISE
    if words > cap:
        print("LONG|the body is %d words against a %d cap. Do not compress it — CUT it. "
              "Reasoning, dead ends and measurements belong in the commit body (git show) or a "
              "linked doc; the PR says what changed and what a reviewer must check. Raise the "
              "cap deliberately with CC_PR_MAX_WORDS if this one genuinely needs the room."
              % (words, cap))
        sys.exit(0)
except Exception:
    sys.exit(0)               # fail-open, always
' 2>/dev/null) || exit 0

[ -n "$VERDICT" ] || exit 0

CODE="${VERDICT%%|*}"
MSG="${VERDICT#*|}"

jq -nc --arg m "$MSG" --arg c "$CODE" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: ("PR description [" + $c + "]: " + $m +
      "\n\nRewrite the body and re-run. Method: ~/.claude/commands/pr.md. " +
      "Kill switch for this one call: CC_PR_PYRAMID=off")
  }
}'
exit 0
