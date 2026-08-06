#!/bin/bash
# unattended-path-lint — a RATCHET on bare-name binary resolution along the UNATTENDED paths.
#
# THE CLASS. A bare command name resolves against whatever PATH the caller happens to have. In the
# operator's shell that is a rich PATH with Homebrew on it, so the name always resolves and the code
# always looks right. On a path nobody watches — a launchd job, a hook fired inside a spawned
# session — the same name may not exist, and the failure is a 127 that most call sites never check.
# That is the worst available polarity: GREEN where a human tests it, DEAD where it runs.
#
# It has now recurred five times, each time fixed as an instance:
#   · e6de2e15 — four sites at once (git-worktree-guard lsof, ship-land sysctl, capacity-alarm's
#     other sysctl, cc-authbrowser lsof). All four failed OPEN: a safety refusal that permitted the
#     removal it exists to block, a load shed that never shed, an alarm that went silent, an
#     adoption check that never recognised its own browser.
#   · 86588cbf / bin/cc-kitty-bin — `${CC_TERM_KITTY:-kitty}` in six files. Measured 2026-08-01: a
#     teammate pane close from a hook exited `kitty: command not found` rc=1 and the pane survived
#     3h09m with its 653 MB claude.exe resident; the identical command from the operator's shell
#     closed it, rc=0.
#   · tests/capacity-alarm-launchd-path.bats (2026-07-30) calls itself "the recurrence guard for the
#     CLASS, not just for sysctl" — but it is scoped to ONE script and ONE plist, and within three
#     days the identical defect existed at four other sites. Fixing instances is O(n) forever;
#     asserting the invariant is O(1). That suite is this lint's ancestor and its RED-control shape
#     is reused below.
#
# ── WHY THE POPULATION IS BOTH PLISTS AND HOOKS ──────────────────────────────────────────────────
# The generator item for this lint (cb6701bf2217) specified the trigger as "each plist under
# launchd/ that EXPORTS its own PATH ... read FROM THE PLIST". Measured 2026-08-06, that trigger
# selects almost nothing and MISSES the exposed surface entirely:
#
#   (A) Only ONE plist sets PATH through the <EnvironmentVariables> dict. The rest set it INLINE
#       inside a ProgramArguments string (`/bin/bash -c 'export PATH="$HOME/.claude/bin:..."; exec
#       ...'`) or run under a login shell (`zsh -lc`, inheriting ~/.zprofile) or not at all. A lint
#       reading the plist's PATH *key* therefore judges one job and calls the corpus clean. So the
#       plist half here parses all four shapes — see plist_effective_path().
#
#   (B) Hooks were out of that spec's scope, and hooks are where the class actually survives. No
#       hook hardens PATH (`grep -l 'export PATH=' hooks/*.sh` was EMPTY) and settings.json declares
#       no PATH env, so a hook simply inherits the PATH of the Claude Code process that fired it.
#
# ── WHAT A HOOK'S PATH ACTUALLY IS, AND WHY THIS LINT ASSERTS THE FLOOR ──────────────────────────
# Do not read "hooks run with PATH=/usr/bin:/bin:/usr/sbin:/sbin" as uniformly true — it is not, and
# assuming it was is how the generating report acquired a false instance. Measured 2026-08-06:
# ~/.claude/logs/sessions.log holds 7,420 "MCP Status (attempt" entries, most recent that same day.
# That line is only reachable PAST `command -v claude` in hooks/session-start.sh, and `claude`
# resolves nowhere but an fnm multishell directory — i.e. those hooks ran with the operator's full
# interactive PATH, and the report's claim that this probe "is always skipped" is refuted.
#
# Both observations are true because a hook inherits its CC process's PATH, and that PATH is a
# function of how the session was STARTED — operator shell, spawn script, or launchd. So the honest
# invariant is not "every hook runs stock"; it is that a hook MAY run stock and cannot tell. This
# lint therefore asserts the FLOOR (the stock macOS PATH) rather than the lucky case, for the same
# reason cc-kitty-bin exists: the population you cannot see is the one that breaks.
#
# ── THE RULE ─────────────────────────────────────────────────────────────────────────────────────
# A file on an unattended path may not invoke, at COMMAND POSITION and by BARE NAME, a binary that
# is unreachable on that path's own PATH. Two kinds are reported, deliberately distinguished:
#   bare    — no `command -v` guard anywhere in the file. A miss is a 127 and a fabricated verdict.
#   guarded — the file tests for the binary. It will not crash, but the capability is silently lost,
#             which for a gate or an actuator is failing OPEN.
# Both are findings; the allowlist decides what BLOCKS, exactly as self-path-lint does.
#
# ── WHY A RATCHET ────────────────────────────────────────────────────────────────────────────────
# The corpus carries a small, tractable set today. Grandfathering them BY FILE+BINARY keeps the rule
# free on new code while the existing set is fixed on its own schedule, and the list can only
# SHRINK: fixing a site while leaving its allowlist line is itself RED (a stuck entry), which is
# what stops a ratchet from silently becoming a permanent exemption list.
#
# ── WHY THE SCANNER IS A STATE MACHINE AND NOT A GREP ────────────────────────────────────────────
# Both cheap spellings were tried and both produced a wrong corpus:
#   · A grep for a name after a command-position delimiter reported every binary named inside
#     completion-assert.sh's CA_CMD_RE — a single-quoted REGEX listing cc-backlog|claude|npx|pnpm as
#     PROSE — as four invocations.
#   · A tokenizer that treated a double-quoted string as one opaque token MISSED the highest-severity
#     real site in the corpus, `out="$(shellcheck ...)"` at hooks/task-quality-gate.sh:164, because
#     the `"` swallowed the `$(`. A command substitution INSIDE double quotes is still a command.
# Only the second failure was survivable to find, and only because a known-true site was held back
# as a control. scan_shell() below tracks quote state properly; --selftest pins both shapes.
#
# The scanner runs on /usr/bin/python3 — deliberately, since a lint that forbids depending on a
# non-stock binary must not itself depend on one. /usr/bin/jq and /usr/libexec/PlistBuddy are stock
# for the same reason; there is no yq, no shellcheck, no coreutils here.
#
# Exit: 0 = clean · 1 = violation · 2 = bad usage / unusable scan tree / unrunnable scanner (LOUD,
# never silent-green — a check that could not run has nothing to say about the tree).
#
# Env seams: CC_UNATTENDED_ALLOWLIST overrides the embedded allowlist (used by --selftest) ·
#            CC_UNATTENDED_OWN narrows which findings BLOCK to the caller's own files.

set -uo pipefail

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/$(basename "${BASH_SOURCE[0]}")"
ROOT="$(cd "$(dirname "$SELF")/.." 2>/dev/null && pwd -P)" || ROOT=""

STOCK_PATH="/usr/bin:/bin:/usr/sbin:/sbin"
PY="/usr/bin/python3"

# ── The ratchet ──────────────────────────────────────────────────────────────────────────────────
# One "<repo-relative-file>:<binary>" per line. Entries are grandfathered SITES, not blanket
# exemptions for the binary: the same binary in a new file is still RED. Delete a line the moment
# its site is fixed — a stuck entry is reported and fails the run.
# WHY 37 AND NOT ZERO. These are the sites measured on 2026-08-06, grandfathered by CLASS so a later
# reader can retire them on evidence rather than guessing:
#   · timeout / gtimeout (12 sites) — almost all are `command -v timeout || command -v gtimeout` with
#     an ELSE that runs the same command unbounded. The bound degrades; the verdict does not change.
#     Both names are listed per site because the guard tries them in turn and either can be the one
#     that resolves.
#   · ~/.claude/bin siblings — cc-backlog, cc-dispatch, cc-decide, cc-do, cc-blockers, cc-notify,
#     cc-teardown. These sit behind resolver ladders that already prefer an absolute path, so the
#     bare name is the ladder's LAST rung rather than its only one.
#   · claude / agent-browser / npx / ruff — these live only in fnm and framework directories whose
#     names carry a pid, so no fixed prefix can reach them and PATH hardening cannot fix them.
#     bin/cc-claude-bin is the right resolver for `claude`, and the right separate change.
#   · THE THREE THAT ARE REAL DEFECTS AND ARE FILED, NOT DISMISSED — postland-verify.sh:sysctl,
#     qos-census.sh:sysctl, team-orphan-reaper.sh:lsof. sysctl and lsof live in /usr/sbin and those
#     plists' PATHs stop at /usr/bin:/bin; both sysctl sites feed a `${x:-0}` default, so a scheduled
#     run records loadavg 0 rather than failing. An unreadable instrument rendering as the HEALTHY
#     value is the exact shape that produced this lint's ancestor, and lsof is the exact site class
#     e6de2e15 fixed. They are not fixed HERE because the fix is a PLIST edit and
#     launchd-parity-lint asserts live `plutil -p` == repo SSOT: editing the repo plist without the
#     operator's launchctl reload would turn that gate RED for every session in the fleet until they
#     acted. Filed so the repo edit and the reload land together.
#   · it2 (teammate-auto-shutdown) — `command -v it2 || echo "$HOME/.claude/bin/it2"`. It is not
#     repo-provided (a real file in ~/.claude/bin, not a symlink into bin/), and the guard already
#     carries the ABSOLUTE fallback this lint asks for. Listed because the name is still tried
#     first, not because the site is wrong — it is the exemplar of the correct shape.
#   · bun / cargo (cc-dispatch) — a project-type ladder wrapped in `|| true`, explicitly best-effort
#     ("install failure does NOT fail provisioning"). Genuinely benign.
# The launchd half's entries are grandfathered for a REASON OF BLAST RADIUS, not of severity. The
# two `sysctl` sites are the same defect that produced this lint's ancestor: sysctl lives in
# /usr/sbin, those two plists' PATHs stop at /usr/bin:/bin, and both call sites feed a `${x:-0}` /
# `${x:-}` default — so a scheduled run records loadavg 0 rather than failing. An unreadable
# instrument rendering as the HEALTHY value is the worst shape available, and it is now the THIRD
# recurrence. They are not fixed HERE because the fix is a plist edit, and launchd-parity-lint
# asserts live `plutil -p` == repo SSOT: editing the repo plist without the operator's launchctl
# reload would turn that gate RED for every session in the fleet until they acted. Filed separately
# so the repo edit and the reload land together.
EMBEDDED_ALLOWLIST="$(cat <<'ALLOW'
bin/cc-dispatch:bun
bin/cc-dispatch:cargo
bin/screenshot-to-clipboard.sh:timeout
hooks/anti-deference-nudge.sh:cc-decide
hooks/completion-assert.sh:cc-backlog
hooks/completion-assert.sh:timeout
hooks/dispatch-assert.sh:cc-dispatch
hooks/lead-crash-watchdog.sh:cc-teardown
hooks/lead-crash-watchdog.sh:gtimeout
hooks/lead-crash-watchdog.sh:timeout
hooks/live-session-registry.sh:claude
hooks/teammate-auto-shutdown.sh:it2
hooks/notify.sh:gtimeout
hooks/notify.sh:timeout
hooks/operator-readout.sh:cc-blockers
hooks/operator-readout.sh:cc-do
hooks/post-file-edit.sh:npx
hooks/post-file-edit.sh:ruff
hooks/pre-session-validate.sh:timeout
hooks/session-register.sh:cc-backlog
hooks/session-register.sh:timeout
hooks/session-start.sh:agent-browser
hooks/session-start.sh:claude
hooks/waiting-recycle.sh:gtimeout
hooks/waiting-recycle.sh:timeout
scripts/autonomy-sweep.sh:gtimeout
scripts/autonomy-sweep.sh:timeout
scripts/lead-supervisor.sh:cc-notify
scripts/lead-supervisor.sh:gtimeout
scripts/lead-supervisor.sh:timeout
scripts/postland-verify.sh:sysctl
scripts/qos-census.sh:sysctl
scripts/qos-census.sh:taskpolicy
scripts/team-orphan-reaper.sh:lsof
scripts/watch-claude-code-2118-hold.sh:gh
scripts/watch-claude-code-2118-hold.sh:gtimeout
scripts/watch-claude-code-2118-hold.sh:timeout
scripts/worktree-gc-infra-run.sh:timeout
ALLOW
)"

usage() {
  cat >&2 <<'USAGE'
usage: unattended-path-lint.sh [ROOT]        scan a repo root (default: this script's repo)
       unattended-path-lint.sh --selftest    prove the detector still discriminates, both directions
       unattended-path-lint.sh --list        print the scanned populations and their PATHs, then exit

exit 0 clean · 1 finding · 2 unusable (a NON-VERDICT, never a clean bill)
USAGE
}

die2() { echo "unattended-path-lint: $*" >&2; exit 2; }

# ── The scanner ──────────────────────────────────────────────────────────────────────────────────
# stdin: nothing. argv: shell files. stdout: "<file>\t<line>\t<word>" for every unquoted word in
# command position. Quote state is tracked; `$(...)` and backticks re-open command position even
# inside double quotes; single quotes and heredoc bodies are opaque; comments are dropped.
scan_shell() {
  [ -x "$PY" ] || die2 "$PY is not executable — the scanner cannot run (NON-VERDICT)"
  "$PY" - "$@" <<'PY'
import sys

KEYWORDS = {
    "if","then","else","elif","fi","for","while","until","do","done","case","esac","function",
    "select","time","in","return","break","continue","exit","shift","local","declare","typeset",
    "readonly","export","unset","eval","exec","source","set","trap","wait","echo","printf","read",
    "cd","pwd","test","true","false","let","alias","unalias","builtin","command","type","hash",
    "umask","ulimit","jobs","kill","getopts","shopt","enable","mapfile","readarray","pushd","popd",
    "caller","compgen","complete","disown","logout","suspend","times","and","or","not","fg","bg",
}
# Words that KEEP command position open for the token after them. `if`/`while`/`until`/`elif` belong
# here and not in KEYWORDS-that-close: `if command -v claude` is a COMMAND after `if`, and treating
# `if` as closing the position meant every `if command -v <tool>` guard in the corpus went unseen —
# 19 further real sites, including the entire guarded class this lint claims to report.
TRANSPARENT = {"then", "else", "do", "elif", "if", "while", "until", "!", "time", "exec",
               "command", "xargs", "builtin", "nohup", "env"}


def scan(text):
    """Yield (lineno, word) for each unquoted command-position word."""
    i, n = 0, len(text)
    line = 1
    at_cmd = True
    dq_depth = 0          # inside "..."
    sub_stack = []        # open $( / ` contexts
    out = []

    while i < n:
        c = text[i]

        if c == "\n":
            line += 1
            i += 1
            if dq_depth == 0:
                at_cmd = True
            continue

        if c in " \t":
            i += 1
            continue

        # comment: only outside quotes and only at a token boundary
        if c == "#" and dq_depth == 0 and (i == 0 or text[i - 1] in " \t\n;|&("):
            while i < n and text[i] != "\n":
                i += 1
            continue

        # line continuation
        if c == "\\" and i + 1 < n:
            if text[i + 1] == "\n":
                line += 1
            i += 2
            continue

        # single quotes are opaque everywhere except inside double quotes (where ' is literal)
        if c == "'" and dq_depth == 0:
            i += 1
            while i < n and text[i] != "'":
                if text[i] == "\n":
                    line += 1
                i += 1
            i += 1
            at_cmd = False
            continue

        if c == '"':
            dq_depth = 1 - dq_depth if dq_depth in (0, 1) else dq_depth
            i += 1
            if dq_depth == 0:
                at_cmd = False
            continue

        # command substitution re-opens command position even inside double quotes
        if c == "$" and i + 1 < n and text[i + 1] == "(":
            # $(( arithmetic )) is NOT a command substitution
            if i + 2 < n and text[i + 2] == "(":
                i += 3
                continue
            sub_stack.append(dq_depth)
            dq_depth = 0
            at_cmd = True
            i += 2
            continue

        if c == "`":
            sub_stack.append(dq_depth)
            dq_depth = 0
            at_cmd = True
            i += 1
            continue

        if c == ")" and sub_stack:
            dq_depth = sub_stack.pop()
            at_cmd = False
            i += 1
            continue

        if dq_depth:
            i += 1
            continue

        # heredoc: skip the body wholesale
        if c == "<" and text.startswith("<<", i):
            j = i + 2
            if j < n and text[j] == "-":
                j += 1
            while j < n and text[j] in " \t":
                j += 1
            q = ""
            if j < n and text[j] in "'\"":
                q = text[j]
                j += 1
            tag = ""
            while j < n and (text[j].isalnum() or text[j] in "_-"):
                tag += text[j]
                j += 1
            if q and j < n and text[j] == q:
                j += 1
            if not tag:
                i += 2
                continue
            # advance to end of this line, then consume until a line that is exactly the tag
            while j < n and text[j] != "\n":
                j += 1
            while j < n:
                j += 1
                line += 1
                k = j
                while k < n and text[k] in " \t":
                    k += 1
                if text.startswith(tag, k):
                    e = k + len(tag)
                    while e < n and text[e] in " \t":
                        e += 1
                    if e >= n or text[e] == "\n":
                        j = e
                        break
                while j < n and text[j] != "\n":
                    j += 1
            i = j
            at_cmd = True
            continue

        if c in ";|&(){}":
            if c in ";|&({":
                at_cmd = True
            i += 1
            continue

        if c in "<>":
            # a redirection and its target are not a command
            i += 1
            at_cmd = False
            continue

        # a word
        start = i
        while i < n and text[i] not in " \t\n;|&()<>\"'`#\\":
            i += 1
        word = text[start:i]
        if not word:
            i += 1
            continue

        if at_cmd:
            if word in TRANSPARENT:
                at_cmd = True
                continue
            # A FLAG or an env-style assignment belongs to the transparent word before it and must
            # not consume the command position. Without this, `command -v claude` yields `-v` as the
            # command and `claude` is never seen at all — which silently exempted every
            # `command -v <tool>` guard in the corpus, i.e. precisely the "guarded" half this lint
            # claims to report. Same for `env -u VAR cmd` and `FOO=bar cmd`.
            if word.startswith("-") or ("=" in word and not word.startswith("=")):
                at_cmd = True
                continue
            if word not in KEYWORDS:
                out.append((line, word))
            at_cmd = False
        else:
            at_cmd = False

    return out


import re

# A name DEFINED as a function in the same file is not an external binary, however bare it looks.
# Without this the scan reports helpers like `emit` and `log` — and it reports them as MISSING, which
# is the most confusing possible finding, since the definition is a few lines up.
FUNCDEF = re.compile(r"^[ \t]*(?:function[ \t]+)?([A-Za-z_][A-Za-z0-9_:.-]*)[ \t]*\(\)[ \t]*\{?",
                     re.MULTILINE)

for path in sys.argv[1:]:
    try:
        text = open(path, encoding="utf-8", errors="replace").read()
    except OSError:
        continue
    local_funcs = set(FUNCDEF.findall(text))
    for lineno, word in scan(text):
        if word in local_funcs:
            continue
        print("%s\t%d\t%s" % (path, lineno, word))
PY
}

# A word is only a candidate if it LOOKS like a bare command name: no slash (a path resolves on its
# own), no variable expansion, no assignment, not numeric (redirection operands like `2` reach here).
plausible_binary() {
  case "$1" in
    */*|*'$'*|*=*|*'['*|*'*'*|*'!'*|'') return 1 ;;
    [0-9]*) return 1 ;;
  esac
  case "$1" in
    [A-Za-z_]*) : ;;
    *) return 1 ;;
  esac
  return 0
}

# Reachability is resolved IN-PROCESS, never by forking `env -i sh -c 'command -v'`. That spelling is
# the obvious one and it cost 41s on this corpus — a fork per (file, word) pair, thousands of them —
# against sibling ratchets that are sub-second. A gate nobody can afford to run is a gate that gets
# turned off. `command -v` on a given PATH is exactly "the first executable FILE of that name in one
# of its directories", which is a loop, so this computes the same answer with no process at all.
# No memo table: /bin/bash on macOS is 3.2, which has no associative arrays, and the loop is already
# fast enough that one would buy nothing (0.19s for the whole corpus). `declare -A` here failed LOUDLY
# under 3.2 rather than silently — but the arithmetic that followed it did not, so a cache-shaped
# optimisation nearly turned the scan into a syntax error that still exited non-zero for the wrong reason.
# Expand the variables a PATH string can legitimately contain, as the shell that runs it will.
#
# `$HOME/.claude/bin` maps to the SCANNED TREE'S OWN bin/, not to the operator's real one, because
# ~/.claude/bin is a directory of per-file SYMLINKS into a checkout — whether cc-sessions is present
# there today is a DEPLOY-STATE question, not a fact about the tree. Keying on it made the verdict
# differ between a real and a fixtured $HOME (4 sites flipped), which is the same mistake
# self-path-lint calls out by name: a rule whose answer depends on what is currently symlinked makes
# a file go red or green without changing. Judging against the repo's bin/ is tree-derived, stable,
# and answers the question actually being asked — will this name resolve for the job that runs it.
expand_path_string() { # $1=PATH string, $2=repo root
  local p="$1" root="$2"
  p="${p//\$\{HOME\}/$HOME}"
  p="${p//\$HOME\/.claude\/bin/$root/bin}"
  p="${p//\$HOME/${HOME:-/tmp}}"
  p="${p//\$\{PATH\}/$STOCK_PATH}"
  p="${p//\$PATH/$STOCK_PATH}"
  printf '%s\n' "$p"
}

reachable_on() { # $1=PATH $2=binary
  local d rc=1 oldifs="$IFS"
  IFS=':'
  for d in $1; do
    [ -n "$d" ] || d="."
    if [ -x "$d/$2" ] && [ ! -d "$d/$2" ]; then rc=0; break; fi
  done
  IFS="$oldifs"
  return $rc
}

# Is the binary a real FILE anywhere this box installs one? A word that resolves nowhere is scanner
# noise (a case label, a bare word), not a dependency — reporting it would be a finding nobody can act on.
#
# Deliberately NOT `command -v` in the current shell. The operator's zsh carries functions and
# aliases — `claude` is a shell function, `print` is a zsh builtin — so an interactive `command -v`
# answers "is this a word my shell knows", which is a different question and says yes to things that
# are not binaries at all. An earlier revision used it and reported `emit`, a function defined inside
# the very file being scanned, as a missing binary. Test for an executable FILE only.
installed_somewhere() {
  # Search the inherited PATH for an executable FILE — deliberately NOT `command -v`, which in the
  # operator's zsh also answers yes to functions, builtins and aliases. `claude` is a shell function
  # and `print` is a zsh builtin; an earlier revision used `command -v` and duly reported `emit`, a
  # function defined inside the very file being scanned, as a missing binary. The inherited PATH is
  # searched rather than a fixed prefix list because npx/claude/ruff live in per-shell fnm and
  # framework directories whose names carry a pid — no static list can enumerate them, and dropping
  # them would silently narrow the lint.
  reachable_on "${PATH}:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:$HOME/.claude/bin:$HOME/.local/bin:$HOME/bin" "$1"
}

# File-level guard detection. `command -v X` / `type -p X` / `hash X` anywhere in the file means the
# author considered absence; the capability is still lost, but it will not 127.
file_guards() { # $1=file $2=binary
  grep -qE "(command[[:space:]]+-v|type[[:space:]]+-[pP]|hash)[[:space:]]+(--[[:space:]]+)?${2}([[:space:]]|\$|\"|')" "$1" 2>/dev/null
}

# ── The launchd half ─────────────────────────────────────────────────────────────────────────────
# Four shapes, because reading only the EnvironmentVariables key judges ONE job in this corpus.
#
# Read through PlistBuddy, one ProgramArguments element at a time, NOT `plutil -extract ... json`.
# plutil's JSON escapes every `/` as `\/` and every `"` as `\"`, so the obvious extraction
# (`s/.*export PATH="\([^"]*\)".*/\1/p`) silently matches nothing and every inline-PATH plist reports
# as bucket 4 — the near-vacuous verdict this lint was built to end, reproduced in the lint itself.
# It was caught only because --list prints the per-plist PATH and a known inline-PATH job read
# "default". PlistBuddy prints the element raw, which is also what the ancestor suite does.
plist_arg_strings() { # $1=plist -> one ProgramArguments element per line, unescaped
  local pl="$1" i=0 s
  while :; do
    s="$(/usr/libexec/PlistBuddy -c "Print :ProgramArguments:$i" "$pl" 2>/dev/null)" || break
    printf '%s\n' "$s"
    i=$((i + 1))
    [ "$i" -gt 32 ] && break
  done
}

plist_effective_path() { # $1=plist -> stdout: a PATH string, or the LOGIN_SHELL sentinel
  local pl="$1" p="" args

  # 1. EnvironmentVariables:PATH
  p="$(/usr/libexec/PlistBuddy -c 'Print :EnvironmentVariables:PATH' "$pl" 2>/dev/null)" || p=""
  if [ -n "$p" ]; then printf '%s\n' "$p"; return 0; fi

  args="$(plist_arg_strings "$pl")"
  if [ -n "$args" ]; then
    # 2. an inline `export PATH="..."` / `PATH=...` anywhere in ProgramArguments
    p="$(printf '%s\n' "$args" | /usr/bin/sed -n 's/.*export PATH="\([^"]*\)".*/\1/p' | head -1)"
    [ -z "$p" ] && p="$(printf '%s\n' "$args" | /usr/bin/sed -n "s/.*export PATH='\([^']*\)'.*/\1/p" | head -1)"
    if [ -n "$p" ]; then printf '%s\n' "$p"; return 0; fi
    # 3. a LOGIN shell inherits the operator's ~/.zprofile PATH — not assertable from the plist, and
    #    deliberately NOT treated as stock: claiming a floor we cannot read would be a fabricated
    #    verdict in the SAFE direction, which is how a lint goes quietly useless.
    #
    #    Detect it by the -l FLAG, never by the interpreter path. The first spelling here tested the
    #    shell name and so matched the string "/bin/bash" itself — every plist that runs a plain
    #    `/bin/bash -c` was classified LOGIN_SHELL and skipped ENTIRELY, i.e. the largest at-risk
    #    bucket was exempted by the check meant to be conservative. A `-l` appears only as its own
    #    argument or inside a combined flag cluster (-lc, -cl).
    if printf '%s\n' "$args" | grep -qE '^-[a-zA-Z]*l[a-zA-Z]*$|^--login$'; then
      printf 'LOGIN_SHELL\n'; return 0
    fi
  fi

  # 4. nothing declared => launchd's own default
  printf '%s\n' "$STOCK_PATH"
}

# NOTE the `sed -E`. The first spelling used BRE with `\|` alternation, which GNU sed accepts and
# BSD sed — the sed on this box — treats as a LITERAL pipe. So the prefix was never stripped, every
# target came back as `$HOME/scripts/foo.sh`, the `[ -f "$root/$HOME/..."]` test failed for all of
# them, and the whole launchd half scanned NOTHING while reporting a clean corpus. It survived a
# full run against the real tree looking exactly like "the plists are fine". Only the plist positive
# control caught it, which is why the generating item made that control mandatory.
plist_target_scripts() { # $1=plist -> repo-relative script paths it executes
  plist_arg_strings "$1" \
    | grep -oE '[A-Za-z0-9_./$-]*/(scripts|bin|hooks)/[A-Za-z0-9_.-]+' \
    | sed -E 's#.*/(scripts|bin|hooks)/#\1/#' \
    | sort -u
}

# A hook that hardens its OWN PATH is judged against what it hardened to — the same courtesy the
# plist half extends to an inline `export PATH=`. Without this the lint would keep reporting a site
# after the prescribed fix was applied, which makes the fix unverifiable and the lint unusable.
# Only assignments in the file's opening section count: a PATH set half way down does not protect
# the calls above it, and treating it as though it did would be a fabricated clean verdict.
file_effective_path() { # $1=file $2=repo root -> stdout: PATH string ('' if it hardens nothing)
  local head p=""
  head="$(/usr/bin/sed -n '1,60p' "$1" 2>/dev/null)"
  p="$(printf '%s\n' "$head" | /usr/bin/sed -n 's/^[[:space:]]*\(export[[:space:]]\{1,\}\)\{0,1\}PATH="\([^"]*\)".*/\2/p' | tail -1)"
  [ -z "$p" ] && p="$(printf '%s\n' "$head" | /usr/bin/sed -n "s/^[[:space:]]*\(export[[:space:]]\{1,\}\)\{0,1\}PATH='\([^']*\)'.*/\2/p" | tail -1)"
  [ -n "$p" ] || return 0
  expand_path_string "$p" "${2:-$ROOT}"
}

# ── The hook half ────────────────────────────────────────────────────────────────────────────────
# The population is what settings.json actually fires, not everything in hooks/. A file nobody
# invokes is not on an unattended path, and judging it would inflate the ratchet with dead weight.
#
# The population is EVERY hooks/*.sh in the scanned tree — deliberately NOT the subset named by the
# live ~/.claude/settings.json, which is what this function did first. Intersecting with settings.json
# made the verdict a function of the OPERATOR'S MACHINE rather than of the tree:
#   · under a fixtured $HOME the file is unreadable, so every --selftest fixture scanned an EMPTY
#     population and passed vacuously — the same shape as a hermetic $HOME routing tests into a
#     branch production never takes;
#   · and reading the operator's real settings.json from a test suite is itself the live-state leak
#     that test-hermeticity-lint exists to stop. It caught this, correctly, at the gate.
# Scanning the directory is deterministic, hermetic, and strictly WIDER. A hook that settings.json
# does not currently fire is still a hook, and wiring one up must not be the act that first exposes
# a latent bare-name call.
hook_population() { # $1=root
  ( cd "$1" 2>/dev/null && ls hooks/*.sh 2>/dev/null )
}

# ── The scan ─────────────────────────────────────────────────────────────────────────────────────
# $1=root  $2=allowlist  $3=own-set (optional; presence carried by arity, see the entrypoint)
lint_tree() {
  local root="$1" allow="${2-}" own="${3-}" have_own="${3+set}"
  [ -n "$root" ] && [ -d "$root" ] || { echo "unattended-path-lint: scan root '$root' is not a directory (NON-VERDICT)" >&2; return 2; }
  [ -d "$root/hooks" ] || [ -d "$root/launchd" ] || { echo "unattended-path-lint: '$root' has neither hooks/ nor launchd/ — nothing this lint governs (NON-VERDICT)" >&2; return 2; }

  local findings=0 blocking=0 used_allow="" report=""

  # Newline-delimited membership, tested with bash's own pattern match rather than `printf | grep`.
  # The grep spelling forks once per SCANNED WORD — thousands of forks — and was most of a 16s run
  # against sibling ratchets that are sub-second. Both operands are newline-wrapped so a match is
  # whole-line and `foo` cannot match inside `foobar`.
  has_line() { # $1=haystack $2=exact line
    case $'\n'"$1"$'\n' in *$'\n'"$2"$'\n'*) return 0 ;; esac
    return 1
  }

  emit() { # $1=file $2=line $3=bin $4=kind $5=whichPATH
    local key="$1:$3"
    if has_line "$allow" "$key"; then
      used_allow="$used_allow$key"$'\n'
      return 0
    fi
    findings=$((findings + 1))
    local mark="  "
    if [ -z "$have_own" ] || has_line "$own" "$1"; then
      blocking=$((blocking + 1)); mark="✗ "
    else
      mark="· "
    fi
    report="${report}${mark}${1}:${2}: \`${3}\` is unreachable on ${5} (${4})"$'\n'
  }

  # -- hooks --
  local hooks_list; hooks_list="$(hook_population "$root")"
  if [ -n "$hooks_list" ]; then
    local files=()
    while IFS= read -r f; do [ -n "$f" ] && files+=("$root/$f"); done <<< "$hooks_list"
    if [ "${#files[@]}" -gt 0 ]; then
      local out; out="$(scan_shell "${files[@]}")" || return 2
      local seen="" hardened_cache=""
      while IFS=$'\t' read -r f l w; do
        [ -n "$w" ] || continue
        plausible_binary "$w" || continue
        local rel="${f#"$root"/}"
        has_line "$seen" "$rel:$w" && continue
        # The PATH this file will actually run with: its own hardening if it has any, else the floor.
        local tgt="" desc="the stock PATH a hook may inherit"
        case "$hardened_cache" in
          *"|$rel="*) tgt="${hardened_cache#*"|$rel="}"; tgt="${tgt%%|*}" ;;
          *) tgt="$(file_effective_path "$f" "$root")"; hardened_cache="$hardened_cache|$rel=$tgt|" ;;
        esac
        if [ -n "$tgt" ]; then desc="the PATH this hook hardens to"; else tgt="$STOCK_PATH"; fi
        reachable_on "$tgt" "$w" && continue
        seen="$seen$rel:$w"$'\n'
        # ORDER MATTERS. The allowlist is consulted BEFORE the is-it-installed-anywhere filter, so an
        # entry counts as USED whenever its site still invokes the binary — even on a box where that
        # binary is not installed at all. Filtering first made the ratchet environment-sensitive in
        # the fail-CLOSED direction: strip Homebrew and fnm from PATH and every non-stock finding
        # vanishes, so all eight hook entries read as STUCK and the gate goes RED over a machine's
        # tool inventory rather than over the land. A stuck entry must mean "this site was FIXED",
        # never "I could not see the binary from here".
        if has_line "$allow" "$rel:$w"; then used_allow="$used_allow$rel:$w"$'\n'; continue; fi
        installed_somewhere "$w" || continue
        local kind="bare"; file_guards "$f" "$w" && kind="guarded"
        emit "$rel" "$l" "$w" "$kind" "$desc"
      done <<< "$out"
    fi
  fi

  # -- launchd --
  if [ -d "$root/launchd" ]; then
    local pl
    for pl in "$root"/launchd/*.plist; do
      [ -f "$pl" ] || continue
      local ppath; ppath="$(plist_effective_path "$pl")"
      [ "$ppath" = "LOGIN_SHELL" ] && continue
      # Expand the two variables a wrapper's PATH can legitimately contain, the way the wrapper's own
      # shell will at runtime. `$PATH` inside a launchd wrapper is launchd's DEFAULT PATH — several
      # jobs spell their PATH as `$HOME/.claude/bin:$PATH`, and leaving it literal would test a
      # directory named '$PATH' and report the whole job unreachable.
      ppath="$(expand_path_string "$ppath" "$root")"
      local tgt
      while IFS= read -r tgt; do
        [ -n "$tgt" ] || continue
        [ -f "$root/$tgt" ] || continue
        local out; out="$(scan_shell "$root/$tgt")" || return 2
        local seen=""
        while IFS=$'\t' read -r f l w; do
          [ -n "$w" ] || continue
          plausible_binary "$w" || continue
          has_line "$seen" "$tgt:$w" && continue
          reachable_on "$ppath" "$w" && continue
          seen="$seen$tgt:$w"$'\n'
          # Same ordering rule as the hook half above — allowlist before installability.
          if has_line "$allow" "$tgt:$w"; then used_allow="$used_allow$tgt:$w"$'\n'; continue; fi
          installed_somewhere "$w" || continue
          local kind="bare"; file_guards "$root/$tgt" "$w" && kind="guarded"
          emit "$tgt" "$l" "$w" "$kind" "$(basename "$pl")'s own PATH"
        done <<< "$out"
      done <<< "$(plist_target_scripts "$pl")"
    done
  fi

  # -- stuck ratchet entries: a site fixed but never de-listed --
  local stuck=""
  while IFS= read -r key; do
    [ -n "$key" ] || continue
    has_line "$used_allow" "$key" || stuck="$stuck  $key"$'\n'
  done <<< "$allow"

  if [ -n "$report" ]; then
    echo "unattended-path-lint: bare-name binaries on unattended paths" >&2
    printf '%s' "$report" >&2
    echo "  Fix: resolve it absolutely (bin/cc-kitty-bin / bin/cc-claude-bin are the precedents), or" >&2
    echo "  harden PATH at the top of the file the way the launchd wrappers already do." >&2
  fi
  if [ -n "$stuck" ]; then
    echo "unattended-path-lint: STUCK RATCHET — these sites are allowlisted but no longer violate:" >&2
    printf '%s' "$stuck" >&2
    echo "  Fix: delete their lines from EMBEDDED_ALLOWLIST in $SELF — the ratchet only shrinks." >&2
    return 1
  fi
  [ "$blocking" -gt 0 ] && return 1
  [ "$findings" -gt 0 ] && echo "unattended-path-lint: $findings finding(s), none in this land's own files — advisory." >&2
  return 0
}

# ── --list ───────────────────────────────────────────────────────────────────────────────────────
if [ "${1:-}" = "--list" ]; then
  [ -n "$ROOT" ] || die2 "cannot resolve repo root"
  echo "HOOK POPULATION (settings.json-invoked), judged against: $STOCK_PATH"
  hook_population "$ROOT" | sed 's/^/  /'
  echo
  echo "LAUNCHD POPULATION (per-plist effective PATH):"
  for pl in "$ROOT"/launchd/*.plist; do
    [ -f "$pl" ] || continue
    printf '  %-46s %s\n' "$(basename "$pl")" "$(plist_effective_path "$pl")"
  done
  exit 0
fi

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then usage; exit 0; fi

# ── --selftest ───────────────────────────────────────────────────────────────────────────────────
# Every case proves a RED path FIRES or a GREEN path does NOT. The generating item made a positive
# control mandatory for BOTH halves — "positive control required for both halves or the lint is
# vacuous" — so the plist half is exercised with a real plist fixture, not only the hook half.
# The fixture bodies below are SHELL SOURCE held as data — every `$` in them must reach the
# scanner unexpanded, so SC2016 is the intended spelling for this whole block, not a slip.
# shellcheck disable=SC2016
if [ "${1:-}" = "--selftest" ]; then
  checks=0; fails=0
  d="$(mktemp -d)" || die2 "mktemp failed"
  trap 'rm -rf "$d"' EXIT

  expect() { # $1=want $2=got $3=label
    checks=$((checks + 1))
    if [ "$1" != "$2" ]; then echo "SELFTEST FAIL: $3 (want $1, got $2)"; fails=$((fails + 1)); fi
  }

  mk() { # $1=dir-under-d $2=relpath $3=body
    mkdir -p "$d/$1/$(dirname "$2")"
    printf '%s\n' "$3" > "$d/$1/$2"
  }

  # A tree with hooks/ so lint_tree accepts it. No settings.json is readable under this $HOME, so
  # hook_population falls back to the whole directory — the widening direction, asserted below.
  newtree() { mkdir -p "$d/$1/hooks" "$d/$1/launchd"; }

  # 1. RED — the unguarded shape, and specifically the one a greedy tokenizer MISSED: a command
  #    substitution inside double quotes. If this ever goes green the scanner has regressed to the
  #    version that called task-quality-gate.sh:164 clean.
  newtree t1
  mk t1 hooks/a.sh 'out="$(shellcheck foo.sh 2>&1)"'
  ( CC_UNATTENDED_ALLOWLIST="" "$SELF" "$d/t1" >/dev/null 2>&1 ); expect 1 "$?" 'a bare binary inside "$( )" was not detected'

  # 2. RED — the plainest shape, bare at line start.
  newtree t2; mk t2 hooks/a.sh 'tmux kill-pane -t "$p"'
  ( CC_UNATTENDED_ALLOWLIST="" "$SELF" "$d/t2" >/dev/null 2>&1 ); expect 1 "$?" 'a bare binary at command position was not detected'

  # 3. GREEN — an absolute path is the fix, and must not be reported.
  newtree t3; mk t3 hooks/a.sh 'out="$(/opt/homebrew/bin/shellcheck foo.sh)"'
  ( CC_UNATTENDED_ALLOWLIST="" "$SELF" "$d/t3" >/dev/null 2>&1 ); expect 0 "$?" 'an absolute path was reported as a violation'

  # 4. GREEN — the false positive that killed the grep version: a binary NAME inside a single-quoted
  #    regex is prose. completion-assert.sh's CA_CMD_RE is the real line this replays.
  newtree t4
  mk t4 hooks/a.sh "CA_CMD_RE='^(cc-backlog|claude|npx|pnpm|tmux|shellcheck)([[:space:]]|\$)'"
  ( CC_UNATTENDED_ALLOWLIST="" "$SELF" "$d/t4" >/dev/null 2>&1 ); expect 0 "$?" 'a binary name inside a single-quoted regex was reported as an invocation'

  # 5. GREEN — a name in a comment is prose.
  newtree t5; mk t5 hooks/a.sh '# we deliberately do not call shellcheck or tmux here
true'
  ( CC_UNATTENDED_ALLOWLIST="" "$SELF" "$d/t5" >/dev/null 2>&1 ); expect 0 "$?" 'a binary name in a comment was reported'

  # 6. GREEN — a heredoc body is data.
  newtree t6; mk t6 hooks/a.sh 'cat <<'"'"'EOF'"'"'
shellcheck tmux yq
EOF'
  ( CC_UNATTENDED_ALLOWLIST="" "$SELF" "$d/t6" >/dev/null 2>&1 ); expect 0 "$?" 'a heredoc body was scanned as code'

  # 7. GREEN — a stock binary is not this lint's business, however bare.
  newtree t7; mk t7 hooks/a.sh 'sed -n 1p "$f" | awk "{print}"'
  ( CC_UNATTENDED_ALLOWLIST="" "$SELF" "$d/t7" >/dev/null 2>&1 ); expect 0 "$?" 'a stock-PATH binary was reported'

  # 8. GREEN — grandfathered by the allowlist, and the entry is USED so it is not stuck.
  newtree t8; mk t8 hooks/a.sh 'tmux kill-pane'
  ( CC_UNATTENDED_ALLOWLIST="hooks/a.sh:tmux" "$SELF" "$d/t8" >/dev/null 2>&1 ); expect 0 "$?" 'an allowlisted site still blocked'

  # 9. RED — a STUCK entry: allowlisted but the site is clean. This is the property that stops the
  #    ratchet becoming a permanent exemption list.
  newtree t9; mk t9 hooks/a.sh 'true'
  ( CC_UNATTENDED_ALLOWLIST="hooks/a.sh:tmux" "$SELF" "$d/t9" >/dev/null 2>&1 ); expect 1 "$?" 'a stuck ratchet entry did not fail'

  # 10. RED CONTROL on the PLIST half — a plist whose own PATH omits /opt/homebrew, running a script
  #     that calls a Homebrew binary bare. Without this the plist half is vacuous, which is exactly
  #     the failure mode the generating item named.
  newtree t10
  mk t10 scripts/j.sh 'yq eval .a "$f"'
  cat > "$d/t10/launchd/com.test.j.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.test.j</string>
  <key>ProgramArguments</key><array>
    <string>/bin/bash</string><string>-c</string>
    <string>export PATH="/usr/bin:/bin"; exec "\$HOME/scripts/j.sh"</string>
  </array>
</dict></plist>
PLIST
  ( CC_UNATTENDED_ALLOWLIST="" "$SELF" "$d/t10" >/dev/null 2>&1 ); expect 1 "$?" 'the plist half did not fire on an INLINE export PATH (the near-vacuous trigger this lint exists to fix)'

  # 11. GREEN on the plist half — the same script under a plist whose inline PATH DOES carry brew.
  newtree t11
  mk t11 scripts/j.sh 'yq eval .a "$f"'
  cat > "$d/t11/launchd/com.test.j.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.test.j</string>
  <key>ProgramArguments</key><array>
    <string>/bin/bash</string><string>-c</string>
    <string>export PATH="/opt/homebrew/bin:/usr/bin:/bin"; exec "\$HOME/scripts/j.sh"</string>
  </array>
</dict></plist>
PLIST
  ( CC_UNATTENDED_ALLOWLIST="" "$SELF" "$d/t11" >/dev/null 2>&1 ); expect 0 "$?" 'a plist whose inline PATH DOES reach the binary was still reported'

  # 12. LOUD — a non-verdict must never read as clean.
  ( CC_UNATTENDED_ALLOWLIST="" "$SELF" "$d/nope" >/dev/null 2>&1 ); expect 2 "$?" 'a missing scan root did not exit 2'
  mkdir -p "$d/bare"
  ( CC_UNATTENDED_ALLOWLIST="" "$SELF" "$d/bare" >/dev/null 2>&1 ); expect 2 "$?" 'a root with neither hooks/ nor launchd/ did not exit 2'

  # 13. own-scope: a finding OUTSIDE the own-set is advisory (exit 0); INSIDE it blocks (exit 1).
  #     Set-but-empty must not collapse to "unset" — that would silently reinstate the hard stop.
  newtree t13; mk t13 hooks/a.sh 'tmux kill-pane'
  ( CC_UNATTENDED_OWN="hooks/a.sh" CC_UNATTENDED_ALLOWLIST="" "$SELF" "$d/t13" >/dev/null 2>&1 ); expect 1 "$?" 'own-scope did not block on a file INSIDE the own-set'
  ( CC_UNATTENDED_OWN="hooks/other.sh" CC_UNATTENDED_ALLOWLIST="" "$SELF" "$d/t13" >/dev/null 2>&1 ); expect 0 "$?" 'own-scope blocked on a file OUTSIDE the own-set'
  ( CC_UNATTENDED_OWN="" CC_UNATTENDED_ALLOWLIST="" "$SELF" "$d/t13" >/dev/null 2>&1 ); expect 0 "$?" 'own-scope set-but-empty blocked'
  ( unset CC_UNATTENDED_OWN; CC_UNATTENDED_ALLOWLIST="" "$SELF" "$d/t13" >/dev/null 2>&1 ); expect 1 "$?" 'own-scope UNSET did not block'

  # 14. GREEN on the real tree with the shipped allowlist — the ratchet must be satisfiable today,
  #     or it cannot be wired into the gate at all.
  if [ -n "$ROOT" ] && [ -d "$ROOT/hooks" ]; then
    ( unset CC_UNATTENDED_OWN; "$SELF" "$ROOT" >/dev/null 2>&1 ); expect 0 "$?" 'the real tree is not clean under the shipped allowlist'
  fi

  if [ "$fails" -eq 0 ]; then
    echo "unattended-path-lint --selftest: $checks/$checks — RED on a bare binary inside \"\$( )\" (the shape a greedy tokenizer missed), on a bare binary at command position, on a stuck ratchet entry, and on a plist whose INLINE export PATH cannot reach the binary; GREEN on an absolute path, a name inside a single-quoted regex, a name in a comment, a heredoc body, a stock binary, a grandfathered site, and a plist whose inline PATH does reach; LOUD on a missing root and a root with no governed layers; own-scope blocks INSIDE / advises OUTSIDE across all three arity states; GREEN on the real tree."
    exit 0
  fi
  echo "unattended-path-lint --selftest: FAILED ($fails of $checks) — the detector does not discriminate."
  exit 1
fi

# ── entrypoint ───────────────────────────────────────────────────────────────────────────────────
# CC_UNATTENDED_OWN — newline-delimited repo-relative paths the caller is answerable for. UNSET ⇒
# every finding blocks. SET-BUT-EMPTY ⇒ nothing blocks (a docs-only land). `${VAR+set}` separates
# those two; `${VAR:-}` would collapse them and silently reinstate the hard stop.
if [ -n "${CC_UNATTENDED_OWN+set}" ]; then
  lint_tree "${1:-$ROOT}" "${CC_UNATTENDED_ALLOWLIST-$EMBEDDED_ALLOWLIST}" "$CC_UNATTENDED_OWN"
else
  lint_tree "${1:-$ROOT}" "${CC_UNATTENDED_ALLOWLIST-$EMBEDDED_ALLOWLIST}"
fi
