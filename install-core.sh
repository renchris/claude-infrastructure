#!/bin/bash
# install-core.sh — install the claude-infrastructure "autonomy core" into Claude Code.
#
# The autonomy core is the portable part of this repo's self-managing, long-running layer: rules that
# make a session drive its work to a finished, committed state and close with a state line from git,
# plus three hooks (auto-continue, a completion gate against false "done" claims, a backup before
# every Write) and two commands (/wrap, /handoff). macOS, Linux and WSL2. It is NOT the full install
# (daemons, kitty panes, multiple accounts): that is ./install.sh, which this script never touches.
#
# One command (run it in the shell where you use Claude Code; on Windows, inside WSL2):
#   curl -fsSLo /tmp/install-core.sh https://raw.githubusercontent.com/renchris/claude-infrastructure/main/install-core.sh && bash /tmp/install-core.sh
#
# Options:
#   --config-dir DIR   install into DIR (default: $CLAUDE_CONFIG_DIR, else ~/.claude)
#   --verify           only re-run the self-checks; change nothing
#   --uninstall        remove everything it added (your backups/ and handoffs/ are kept)
#   --force            install even though the full claude-infrastructure install is present
#
# What it changes (safe to re-run; every changed file is backed up first):
#   <config>/autonomy-core/        hooks, the `autonomy` command, the rules, state, backups
#   <config>/commands/wrap.md, handoff.md   (left alone if you already have your own)
#   <config>/CLAUDE.md             appends one marked block with the rules
#   <config>/settings.json         merges in 3 hook entries; backup: settings.json.before-autonomy-core
# Then it drives each installed hook with test input and reads settings.json back; it prints READY
# only when every check passes.
#
# Undo: bash install-core.sh --uninstall
set -euo pipefail

CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
MODE=install
FORCE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --config-dir) CFG="${2:?--config-dir needs a directory}"; shift 2 ;;
    --verify)     MODE=verify; shift ;;
    --uninstall)  MODE=uninstall; shift ;;
    --force)      FORCE=1; shift ;;
    -h|--help)    sed -n '2,/^set -euo/p' "$0" | sed '$d; s/^# \{0,1\}//'; exit 0 ;;
    *)            echo "install-core.sh: unknown option: $1 (try --help)" >&2; exit 2 ;;
  esac
done
mkdir -p "$CFG"
CFG="$(cd "$CFG" && pwd)"
AC="$CFG/autonomy-core"
SETTINGS="$CFG/settings.json"
MEMORY="$CFG/CLAUDE.md"
BEGIN_MARK="<!-- BEGIN autonomy-core (managed by install-core.sh; edit outside this block) -->"
END_MARK="<!-- END autonomy-core -->"
HOOK_TAG="autonomy-core/hooks/"
STAMP="$(date +%Y%m%d-%H%M%S)"

say()  { printf '%s\n' "$*"; }
warn() { printf '  ⚠ %s\n' "$*" >&2; }
die()  { printf 'install-core.sh: %s\n' "$*" >&2; exit 1; }

# ------------------------------------------------------------------------------------ preflight
case "$(uname -s)" in
  Darwin) PLATFORM=macOS ;;
  Linux)  if grep -qi microsoft /proc/version 2>/dev/null; then PLATFORM=WSL2; else PLATFORM=Linux; fi ;;
  *)      die "unsupported system '$(uname -s)'. On Windows, run this inside WSL2 (Ubuntu), where Claude Code runs." ;;
esac
# JSON: jq first (macOS 15+ ships it, and a macOS python3 may be the stub that asks to install tools),
# then python3 (Ubuntu and WSL ship it). The hooks use the same order.
if command -v jq >/dev/null 2>&1; then JSON=jq
elif command -v python3 >/dev/null 2>&1 && python3 -c 'import json' >/dev/null 2>&1; then JSON=python3
else
  case "$PLATFORM" in
    macOS) die "needs jq or python3: brew install jq (or xcode-select --install for python3)" ;;
    *)     die "needs jq or python3: sudo apt-get install -y jq   (Fedora: sudo dnf install -y jq)" ;;
  esac
fi

# ------------------------------------------------------------------------------------ payload
# Everything below up to END EMBEDDED CORE is generated from core/ by core/build.sh,
# so this one file (and its one sha256) is the whole install. Edit core/, then rebuild.
ac_emit() {   # <relative path> <mode>; file body on stdin
  mkdir -p "$(dirname "$STAGE/$1")"
  cat > "$STAGE/$1"
  chmod "$2" "$STAGE/$1"
}
write_payload() {
# >>> BEGIN EMBEDDED CORE
ac_emit 'VERSION' 644 <<'__AUTONOMY_CORE_EOF__'
core-998713561
__AUTONOMY_CORE_EOF__
ac_emit 'hooks/lib.sh' 755 <<'__AUTONOMY_CORE_EOF__'
#!/bin/bash
# lib.sh — shared helpers for the autonomy-core hooks. Sourced, never run.
#
# Portability contract: bash 3.2 (macOS /bin/bash), GNU or BSD userland. JSON goes through jq when it
# is installed, else python3 (Ubuntu and WSL ship python3 but not jq; macOS 15+ ships jq).

AC_HOME="${AC_HOME:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck disable=SC2034  # read by the hooks that source this file
AC_STATE="$AC_HOME/state"

# ac_json_get <json> <dotted.path> → prints the value ("" when absent or null). Never fails.
ac_json_get() {
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$1" | jq -r ".${2} // empty | if type==\"string\" then . else tojson end" 2>/dev/null || true
  elif command -v python3 >/dev/null 2>&1; then
    printf '%s' "$1" | python3 -c '
import json, sys
try:
    v = json.load(sys.stdin)
    for k in sys.argv[1].split("."):
        v = v.get(k) if isinstance(v, dict) else None
    if v is not None:
        print(v if isinstance(v, str) else json.dumps(v))
except Exception:
    pass' "$2" 2>/dev/null || true
  fi
}

# ac_json_str <text> → the text as a JSON string literal, quotes included.
ac_json_str() {
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$1" | jq -Rs . 2>/dev/null
  else
    printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))' 2>/dev/null
  fi
}

# ac_block <reason> → the Stop-hook JSON that keeps the session working, with <reason> as its next prompt.
ac_block() {
  printf '{"decision":"block","reason":%s}\n' "$(ac_json_str "$1")"
}

# ac_key <text> → a short filesystem-safe key (cksum is POSIX; no md5/sha tool differences).
ac_key() {
  printf '%s' "$1" | cksum | awk '{print $1}'
}
__AUTONOMY_CORE_EOF__
ac_emit 'hooks/continue.sh' 755 <<'__AUTONOMY_CORE_EOF__'
#!/bin/bash
# continue.sh — Stop hook: keep working on an armed "next step" instead of stopping.
#
# The model arms it when it stops with in-scope work left:
#   ~/.claude/autonomy-core/bin/autonomy continue set "<the one next step>"
# and every Stop after that is turned into another turn whose prompt is that step, until the model
# clears it (`autonomy continue clear`) or the cap is reached (AUTONOMY_CONTINUE_MAX, default 8).
# Re-arming with `set` resets the count, so a long job can chain; the cap bounds a stuck loop.
#
# The sentinel is keyed on the session id when Claude Code exports one, else on the working
# directory, so two sessions in two directories never drive each other.
# Kill switch: AUTONOMY_CORE_CONTINUE=off. This hook always exits 0; it blocks only via JSON.

# shellcheck disable=SC1091  # lib.sh sits beside this hook
. "$(dirname "$0")/lib.sh"
dir="$AC_STATE/continue"
mkdir -p "$dir" 2>/dev/null

# ---- CLI: set | clear | status (run from the model's Bash tool) ----
case "${1:-}" in
  set|clear|status)
    sid="${CLAUDE_CODE_SESSION_ID:-}"
    if [ -n "$sid" ]; then f="$dir/sid-$(ac_key "$sid")"; else f="$dir/cwd-$(ac_key "$PWD")"; fi
    case "$1" in
      set)
        printf '%s' "${2:-Continue the in-scope work.}" > "$f"
        rm -f "$f.count"
        echo "armed: the next stop continues with: ${2:-Continue the in-scope work.}" ;;
      clear)
        rm -f "$f" "$f.count" "$dir/cwd-$(ac_key "$PWD")" "$dir/cwd-$(ac_key "$PWD").count"
        echo "cleared: stops are no longer auto-continued here" ;;
      status)
        if [ -f "$f" ]; then echo "armed ($(cat "$f.count" 2>/dev/null || echo 0)/${AUTONOMY_CONTINUE_MAX:-8}): $(cat "$f")"
        else echo "not armed"; fi ;;
    esac
    exit 0 ;;
esac

# ---- Stop hook ----
[ "${AUTONOMY_CORE_CONTINUE:-on}" = off ] && exit 0
input="$(cat)"
sid="$(ac_json_get "$input" session_id)"
cwd="$(ac_json_get "$input" cwd)"
f=""
if [ -n "$sid" ] && [ -f "$dir/sid-$(ac_key "$sid")" ]; then f="$dir/sid-$(ac_key "$sid")"
elif [ -n "$cwd" ] && [ -f "$dir/cwd-$(ac_key "$cwd")" ]; then f="$dir/cwd-$(ac_key "$cwd")"
fi
[ -n "$f" ] || exit 0

max="${AUTONOMY_CONTINUE_MAX:-8}"
n="$(cat "$f.count" 2>/dev/null || echo 0)"
case "$n" in ''|*[!0-9]*) n=0 ;; esac
if [ "$n" -ge "$max" ]; then
  step="$(cat "$f")"
  rm -f "$f" "$f.count"
  printf '{"systemMessage":%s}\n' "$(ac_json_str "autonomy-core: auto-continue stopped after $max turns on: $step")"
  exit 0
fi
n=$((n + 1))
printf '%s' "$n" > "$f.count"
ac_block "Auto-continue ($n/$max): $(cat "$f")

Keep working on it. When it is finished, blocked on a decision only the user can make, or out of scope, run: $AC_HOME/bin/autonomy continue clear
Re-arm with a new next step (\`$AC_HOME/bin/autonomy continue set \"...\"\`) if more in-scope work remains."
exit 0
__AUTONOMY_CORE_EOF__
ac_emit 'hooks/completion-gate.sh' 755 <<'__AUTONOMY_CORE_EOF__'
#!/bin/bash
# completion-gate.sh — Stop hook: a "done" claim must agree with git.
#
# When the model's last message says the work is done, complete, finished, landed or safe to close,
# and the repository it is working in still has uncommitted tracked changes or commits its upstream
# does not have, the stop is blocked once and the facts are fed back. The model then finishes the
# work or says plainly what remains; the same git state is never blocked twice, so it cannot loop.
#
# It reads facts only (git status, the upstream count), never judges scope. Outside a git repository,
# with no upstream, or with no readable last message it stays silent.
# Kill switch: AUTONOMY_CORE_GATE=off. This hook always exits 0; it blocks only via JSON.

# shellcheck disable=SC1091  # lib.sh sits beside this hook
. "$(dirname "$0")/lib.sh"
[ "${AUTONOMY_CORE_GATE:-on}" = off ] && exit 0
command -v git >/dev/null 2>&1 || exit 0

input="$(cat)"
msg="$(ac_json_get "$input" last_assistant_message)"
[ -n "$msg" ] || exit 0
cwd="$(ac_json_get "$input" cwd)"
[ -n "$cwd" ] && [ -d "$cwd" ] && cd "$cwd" 2>/dev/null || true
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

# A completion claim, not a negated or conditional one. Lower-cased for the match.
low="$(printf '%s' "$msg" | tr '[:upper:]' '[:lower:]')"
printf '%s' "$low" | grep -Eq '(^|[^a-z])(done|complete|completed|finished|landed|shipped)([^a-z]|$)|safe to close|good to close: yes|all set|✅' || exit 0
printf '%s' "$low" | grep -Eq '(not|isn.t|aren.t|once|when|until|before|if) (yet )?(fully )?(done|complete|completed|finished)|good to close: no' && exit 0

dirty="$(git status --porcelain --untracked-files=no 2>/dev/null | wc -l | tr -d ' ')"
untracked="$(git status --porcelain 2>/dev/null | grep -c '^??' | tr -d ' ')"
ahead=0
if git rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
  ahead="$(git rev-list --count '@{u}..HEAD' 2>/dev/null || echo 0)"
fi
[ "$dirty" -gt 0 ] || [ "$ahead" -gt 0 ] || exit 0

# Once per (session, git state): the second stop on the same state is allowed through.
sid="$(ac_json_get "$input" session_id)"
fp="$(ac_key "$(git rev-parse HEAD 2>/dev/null)|$(git status --porcelain 2>/dev/null)|$ahead")"
mark="$AC_STATE/gate/$(ac_key "${sid:-nosid}|$(pwd)")"
mkdir -p "$AC_STATE/gate" 2>/dev/null
[ "$(cat "$mark" 2>/dev/null)" = "$fp" ] && exit 0
printf '%s' "$fp" > "$mark"

facts=""
[ "$dirty" -gt 0 ] && facts="$facts
- $dirty tracked file(s) with uncommitted changes (git status)"
[ "$ahead" -gt 0 ] && facts="$facts
- $ahead commit(s) not pushed to $(git rev-parse --abbrev-ref '@{u}' 2>/dev/null)"
[ "$untracked" -gt 0 ] && facts="$facts
- $untracked untracked file(s)"
ac_block "Your last message says the work is done, but git in $(pwd) disagrees:$facts

Finish it (commit, and push if this work should be pushed), or say plainly what remains and who owns it. If these changes are not yours, say so and stop; this check will not fire again on this same git state."
exit 0
__AUTONOMY_CORE_EOF__
ac_emit 'hooks/backup-before-write.sh' 755 <<'__AUTONOMY_CORE_EOF__'
#!/bin/bash
# backup-before-write.sh — PreToolUse(Write) hook: copy a file before a Write replaces it.
#
# The Write tool replaces a whole file. On a plan, a doc or a CLAUDE.md that has gathered decisions
# over many sessions, one careless rewrite loses them. This keeps a copy of every file a Write is about
# to replace, under <install>/backups/<date>/, for 14 days (AUTONOMY_BACKUP_DAYS).
# Restore the newest copy with: ~/.claude/autonomy-core/bin/autonomy restore <path>
#
# It never blocks a write: every path exits 0, and a backup failure is only reported.

# shellcheck disable=SC1091  # lib.sh sits beside this hook
. "$(dirname "$0")/lib.sh"
input="$(cat)"
path="$(ac_json_get "$input" tool_input.file_path)"
[ -n "$path" ] && [ -f "$path" ] || exit 0

root="$AC_HOME/backups"
day="$root/$(date +%Y%m%d)"
mkdir -p "$day" 2>/dev/null || exit 0
# The whole path, flattened, so the same name in two directories never collides.
flat="$(printf '%s' "$path" | sed 's#/#%#g')"
# Named by time; a second copy within the same second gets -01, -02, … so none is overwritten and the
# names still sort oldest to newest.
base="$day/$flat.$(date +%H%M%S)"
dest="$base"
n=0
while [ -e "$dest" ]; do n=$((n + 1)); dest="$base-$(printf '%02d' "$n")"; done
cp -p "$path" "$dest" 2>/dev/null \
  || echo "autonomy-core: could not back up $path before the write" >&2

# Prune whole days older than the retention window (find -mtime works on GNU and BSD alike).
find "$root" -mindepth 1 -maxdepth 1 -type d -mtime +"${AUTONOMY_BACKUP_DAYS:-14}" -exec rm -rf {} + 2>/dev/null
exit 0
__AUTONOMY_CORE_EOF__
ac_emit 'bin/autonomy' 755 <<'__AUTONOMY_CORE_EOF__'
#!/bin/bash
# autonomy — the autonomy-core command line.
#
#   autonomy continue set "<next step>"   keep working on <next step> instead of stopping
#   autonomy continue clear | status      stop auto-continuing here / show what is armed
#   autonomy ledger                       one-line state of the current git repo, from live reads
#   autonomy restore <path> [--list]      put back the newest pre-Write backup of <path>
#   autonomy doctor                       check the install; exit 1 on any problem
#   autonomy version
AC_HOME="$(cd "$(dirname "$0")/.." && pwd)"
export AC_HOME
# shellcheck disable=SC1091  # installed beside this command
. "$AC_HOME/hooks/lib.sh"

ledger() {
  if ! command -v git >/dev/null 2>&1 || ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "READOUT=— Not a git repository; nothing to report"; return 0
  fi
  local top branch tracked untracked ahead=0 target="" readout
  top="$(git rev-parse --show-toplevel)"
  branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)"
  tracked="$(git status --porcelain --untracked-files=no | wc -l | tr -d ' ')"
  untracked="$(git status --porcelain | grep -c '^??' | tr -d ' ')"
  if git rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
    target="$(git rev-parse --abbrev-ref '@{u}')"
    ahead="$(git rev-list --count '@{u}..HEAD' 2>/dev/null || echo 0)"
  elif [ -n "$(git remote 2>/dev/null)" ]; then
    target="any remote (no upstream set)"
    ahead="$(git rev-list --count HEAD --not --remotes 2>/dev/null || echo 0)"
  fi
  if [ $((tracked + untracked)) -gt 0 ]; then
    readout="🔧 Loose ends — $((tracked + untracked)) uncommitted change(s) ($tracked tracked, $untracked untracked)"
  elif [ "$ahead" -gt 0 ]; then
    readout="📦 Committed, not pushed — $ahead commit(s) exist only on this machine"
  elif [ -z "$target" ]; then
    readout="✅ Clean — committed (no remote configured, so nothing to push)"
  else
    readout="✅ Complete — clean and pushed to $target"
  fi
  echo "READOUT=$readout"
  echo "repo:      $top ($branch)"
  echo "changes:   $tracked tracked, $untracked untracked"
  echo "unpushed:  ${target:+$ahead commit(s) vs $target}${target:-n/a (no remote)}"
  echo "continue:  $(bash "$AC_HOME/hooks/continue.sh" status)"
}

restore() {
  local path="${1:-}" list="${2:-}" flat newest
  [ -n "$path" ] || { echo "usage: autonomy restore <path> [--list]" >&2; return 2; }
  case "$path" in /*) ;; *) path="$PWD/$path" ;; esac
  flat="$(printf '%s' "$path" | sed 's#/#%#g')"
  # Day directories sort by name (YYYYMMDD) and copies by time suffix, so the last line is the newest.
  newest="$(find "$AC_HOME/backups" -mindepth 2 -maxdepth 2 -type f -name "$flat.*" 2>/dev/null | sort | tail -1)"
  if [ "$list" = --list ]; then find "$AC_HOME/backups" -mindepth 2 -maxdepth 2 -type f -name "$flat.*" 2>/dev/null | sort; return 0; fi
  [ -n "$newest" ] || { echo "no backup of $path under $AC_HOME/backups" >&2; return 1; }
  # Keep the current version too, so a restore can itself be undone.
  if [ -f "$path" ]; then
    printf '{"tool_input":{"file_path":%s}}' "$(ac_json_str "$path")" | bash "$AC_HOME/hooks/backup-before-write.sh"
  fi
  cp -p "$newest" "$path" && echo "restored $path from $newest"
}

doctor() {
  local bad=0 cfg settings f
  cfg="$(cd "$AC_HOME/.." && pwd)"
  settings="$cfg/settings.json"
  for f in hooks/lib.sh hooks/continue.sh hooks/completion-gate.sh hooks/backup-before-write.sh bin/autonomy CLAUDE.core.md; do
    if [ -f "$AC_HOME/$f" ]; then echo "  ok    $f"; else echo "  FAIL  missing $AC_HOME/$f"; bad=1; fi
  done
  if command -v jq >/dev/null 2>&1; then echo "  ok    JSON via jq"
  elif command -v python3 >/dev/null 2>&1; then echo "  ok    JSON via python3"
  else echo "  FAIL  neither jq nor python3 is installed (the hooks cannot read their input)"; bad=1; fi
  for f in continue.sh completion-gate.sh backup-before-write.sh; do
    if grep -q "autonomy-core/hooks/$f" "$settings" 2>/dev/null; then echo "  ok    $f registered in settings.json"
    else echo "  FAIL  $f is not registered in $settings"; bad=1; fi
  done
  if grep -q 'BEGIN autonomy-core' "$cfg/CLAUDE.md" 2>/dev/null; then echo "  ok    rules block in CLAUDE.md"
  else echo "  FAIL  no autonomy-core rules block in $cfg/CLAUDE.md"; bad=1; fi
  command -v git >/dev/null 2>&1 && echo "  ok    git" || echo "  warn  git not installed: the completion gate and ledger stay silent"
  return "$bad"
}

case "${1:-}" in
  continue) shift; bash "$AC_HOME/hooks/continue.sh" "${1:-status}" "${2:-}" ;;
  ledger)   ledger ;;
  restore)  shift; restore "$@" ;;
  doctor)   doctor ;;
  version)  cat "$AC_HOME/VERSION" 2>/dev/null || echo unknown ;;
  *)        sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; [ -z "${1:-}" ] || exit 2 ;;
esac
__AUTONOMY_CORE_EOF__
ac_emit 'CLAUDE.core.md' 644 <<'__AUTONOMY_CORE_EOF__'
# Autonomy core — how to run long and finish

These rules make a session drive its work to a finished, verified, committed state on its own, stop
only for real decisions, and close with a state line taken from git rather than from memory. Three
hooks back them: auto-continue, a completion gate, and a backup before every Write. The command line
is `__AC_HOME__/bin/autonomy`.

## Freeze the scope first

The first time a task will change files, restate the ask as one line, `Scope (frozen): …`, in the plan
or in chat. At the end, "done" means that line is met; it is not a fresh judgment. If the scope cannot
be reconstructed, ask.

## Drive to done without asking

- Inside the frozen scope, keep going: finish, run the project's checks (tests, typecheck, lint), fix
  what fails (up to about two debugging cycles, then commit what works and report), and commit.
- Commit as you go: one commit per finished logical step, staging explicit paths only. Never commit
  changes you did not make.
- A follow-on you discover (a bug next to yours, a missing test) is done now, without asking, when it
  is clearly net-positive, well understood, as safe as the main task and small. Note it as
  `Scope (grown): +<item>`. Otherwise mention it in one line and drop it.
- Stop and ask only for a real decision: something destructive or irreversible, auth or security, a
  choice between options with different outcomes for the user, or information you cannot find. State
  the decision in one sentence with your recommendation and how sure you are, in percent.
- Offering in-scope work ("say the word and I'll do X") is not a close. Do it, or say why not.

## Keep working instead of stopping

- If you would stop with in-scope work left, arm the next step:
  `__AC_HOME__/bin/autonomy continue set "<the one next step>"`. The stop turns into another turn with
  that step (at most 8 in a row; re-arming resets the count).
- Clear it as soon as the work is finished, blocked on the user, or out of scope:
  `__AC_HOME__/bin/autonomy continue clear`.
- The completion gate blocks a stop once when your message says "done" but git still shows
  uncommitted tracked changes or unpushed commits. Finish the work, or say plainly what remains.

## Use /goal for long runs

`/goal <condition>` (built into Claude Code) keeps a session taking turns until a separate evaluator
judges the condition met. It only sees what the session prints, so write the condition in three parts:

    <one measurable end state> — proven by <a command the session runs and prints>; do not <constraint>

Example: `all tests in tests/api pass and the branch is pushed — proven by printing the pytest summary
and git status -sb; do not change the public API`. A condition that names an activity or perfection
("continue until 100% perfect") never clears. A goal is checked only when the session stops, so a
session that hands off or ends mid-turn is never evaluated.

## Context is a budget

Check fill with `/context`. From about 50%, plan a pause point; before about 75%, commit, write down
what a fresh session would need, and hand off with `/handoff`. Never ride a session into the context
limit: the session then fails every later turn.

## Files that accumulate decisions

Plans, design docs, research notes and CLAUDE.md files are integrated, never overwritten: use Edit
for changes and appended sections, and Write only to create a file. Every Write that replaces a file
is backed up first; `__AC_HOME__/bin/autonomy restore <path>` puts the newest copy back.

## Close every turn that changed files with a readout

Run `__AC_HOME__/bin/autonomy ledger` (or `/wrap`) and start the close with its `READOUT` glyph:

- 🔧 loose ends: uncommitted changes, or a check failed. Not a close: keep going.
- 📦 committed but not pushed: push it if pushing is how this project lands work; otherwise say so.
- ✅ clean and pushed: say it plainly, without hedging.

Line 2 answers `Good to close: yes` or `Good to close: no — <what remains, and who owns it>`. Claim
"done" only when the frozen scope is met, the checks ran green this turn, and the ledger reads ✅.
__AUTONOMY_CORE_EOF__
ac_emit 'commands/wrap.md' 644 <<'__AUTONOMY_CORE_EOF__'
---
description: Close the turn with the git-derived state readout (autonomy core)
---
<!-- autonomy-core -->
Close this turn with a state readout taken from live reads, not from memory.

1. Run `__AC_HOME__/bin/autonomy ledger` and read its `READOUT=` line.
2. If the readout is 🔧 and the loose ends are in scope, do not close: finish them (commit, run the
   checks), then run the ledger again. If they are not yours, say whose they are in one line.
3. Write the close:
   - Line 1: the READOUT glyph and state, plus one clause naming what the work was.
   - Line 2: `Good to close: yes` or `Good to close: no — <what remains, and who owns it>`.
   - Then at most three lines: what is now true against the frozen scope, the commit sha that holds
     the detail, and anything the user must do (as one command they can paste).
4. If auto-continue is still armed (`continue:` line) and the work is finished, clear it:
   `__AC_HOME__/bin/autonomy continue clear`.
__AUTONOMY_CORE_EOF__
ac_emit 'commands/handoff.md' 644 <<'__AUTONOMY_CORE_EOF__'
---
description: Hand this session's work to a fresh context in the same terminal (autonomy core)
---
<!-- autonomy-core -->
Hand off to a fresh session so the work continues with an empty context. $ARGUMENTS

1. Commit finished work first (explicit paths, one commit per logical step). Uncommitted work that is
   not finished stays in the tree; say so in the bridge.
2. Write the bridge to `__AC_HOME__/handoffs/<YYYYMMDD-HHMM>-<short-topic>.md` with these sections, each
   short and concrete (file paths, commands, shas; nothing a successor could not act on):
   - **Scope (frozen)**: the one-line contract, plus any `Scope (grown)` lines.
   - **Done**: what is finished, with commit shas.
   - **Next**: the ordered remaining steps, the first one exact enough to start without reading anything else.
   - **Decisions and dead ends**: what was decided and why, and approaches already rejected, so the
     successor does not repeat them. This is the part only this context holds.
   - **Verify with**: the commands that prove the end state.
   - **Goal**: a `/goal` condition for the successor (`<end state> — proven by <command>; do not <constraint>`).
3. Clear auto-continue: `__AC_HOME__/bin/autonomy continue clear`.
4. Tell the user, as the last thing in your message, exactly:

   ▶ Run `/clear`, then paste:

   `Read <bridge path> and continue from its Next section.`

   (or, in a new terminal: `claude "Read <bridge path> and continue from its Next section."`)
__AUTONOMY_CORE_EOF__
# <<< END EMBEDDED CORE
}

# ------------------------------------------------------------------------------------ settings.json
# merge_settings <add|remove> <file>: drop every hook entry whose command runs one of our hooks, then
# (for add) append ours. Removing first makes a re-run, or a move to another directory, idempotent.
# Prints the new JSON; the caller writes it only when it differs from what is on disk.
merge_settings() {
  local op="$1" file="$2"
  if [ "$JSON" = jq ]; then
    local src='{}'
    [ -s "$file" ] && src="$(cat "$file")"
    printf '%s' "$src" | jq --arg tag "$HOOK_TAG" --arg ac "$AC" --arg op "$op" '
      def ours: any(.hooks[]?; (.command // "") | contains($tag));
      def cmd(f): {type:"command", command:("bash \"" + $ac + "/hooks/" + f + "\""), timeout:10};
      .hooks = ((.hooks // {}) | with_entries(.value |= map(select(ours | not))))
      | if $op == "add" then
          .hooks.Stop = ((.hooks.Stop // []) + [{hooks:[cmd("continue.sh")]}, {hooks:[cmd("completion-gate.sh")]}])
          | .hooks.PreToolUse = ((.hooks.PreToolUse // []) + [{matcher:"Write", hooks:[cmd("backup-before-write.sh")]}])
        else . end
      | .hooks |= with_entries(select(.value | length > 0))
      | if (.hooks | length) == 0 then del(.hooks) else . end'
  else
    python3 - "$file" "$HOOK_TAG" "$AC" "$op" <<'PY'
import json, os, sys
path, tag, ac, op = sys.argv[1:5]
s = json.load(open(path)) if os.path.exists(path) and open(path).read().strip() else {}
def ours(e): return any(tag in (h.get("command") or "") for h in e.get("hooks", []))
def cmd(f): return {"type": "command", "command": 'bash "%s/hooks/%s"' % (ac, f), "timeout": 10}
hooks = {k: [e for e in v if not ours(e)] for k, v in (s.get("hooks") or {}).items()}
if op == "add":
    hooks.setdefault("Stop", []).extend([{"hooks": [cmd("continue.sh")]}, {"hooks": [cmd("completion-gate.sh")]}])
    hooks.setdefault("PreToolUse", []).append({"matcher": "Write", "hooks": [cmd("backup-before-write.sh")]})
hooks = {k: v for k, v in hooks.items() if v}
if hooks: s["hooks"] = hooks
else: s.pop("hooks", None)
print(json.dumps(s, indent=2, ensure_ascii=False))
PY
  fi
}

json_valid() {  # <file>
  if [ "$JSON" = jq ]; then jq -e . "$1" >/dev/null 2>&1
  else python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$1" >/dev/null 2>&1; fi
}

apply_settings() {  # <add|remove>
  local new
  if [ "$1" = remove ] && ! grep -q "$HOOK_TAG" "$SETTINGS" 2>/dev/null; then
    say "  = settings.json has no core hooks"; return 0
  fi
  if [ -s "$SETTINGS" ] && ! json_valid "$SETTINGS"; then
    die "$SETTINGS is not valid JSON; fix it (or move it aside) and re-run. Nothing was changed there."
  fi
  new="$(merge_settings "$1" "$SETTINGS")" || die "could not merge $SETTINGS"
  if [ -f "$SETTINGS" ] && [ "$new" = "$(cat "$SETTINGS")" ]; then
    say "  = settings.json already up to date"; return 0
  fi
  if [ -f "$SETTINGS" ]; then
    [ -f "$SETTINGS.before-autonomy-core" ] || cp -p "$SETTINGS" "$SETTINGS.before-autonomy-core"
    cp -p "$SETTINGS" "$SETTINGS.bak-autonomy-core-$STAMP"
  fi
  printf '%s\n' "$new" > "$SETTINGS.tmp.$$" && mv "$SETTINGS.tmp.$$" "$SETTINGS"
  json_valid "$SETTINGS" || die "wrote invalid JSON to $SETTINGS (restore: cp $SETTINGS.bak-autonomy-core-$STAMP $SETTINGS)"
  if [ "$1" = add ]; then say "  ✓ settings.json: 3 hooks merged in"; else say "  ✓ settings.json: core hooks removed"; fi
  [ -f "$SETTINGS.bak-autonomy-core-$STAMP" ] && say "    previous copy: $SETTINGS.bak-autonomy-core-$STAMP"
  return 0
}

# ------------------------------------------------------------------------------------ CLAUDE.md block
strip_block() {  # <file> → the file without our block and without trailing blank lines, on stdout
  awk -v b="$BEGIN_MARK" -v e="$END_MARK" '
    $0==b {skip=1; next}  $0==e {skip=0; next}  skip {next}
    {line[++n]=$0; if ($0 ~ /[^[:space:]]/) last=n}
    END {for (i=1; i<=last; i++) print line[i]}' "$1"
}
apply_memory() {  # <add|remove>
  local tmp="$MEMORY.tmp.$$"
  if [ -f "$MEMORY" ]; then strip_block "$MEMORY" > "$tmp"; else : > "$tmp"; fi
  if [ "$1" = add ]; then
    # One blank line between your own text and the block (none when there is no text).
    if [ -s "$tmp" ]; then printf '\n' >> "$tmp"; fi
    { printf '%s\n' "$BEGIN_MARK"; cat "$AC/CLAUDE.core.md"; printf '%s\n' "$END_MARK"; } >> "$tmp"
  fi
  if [ -f "$MEMORY" ] && cmp -s "$tmp" "$MEMORY"; then rm -f "$tmp"; say "  = CLAUDE.md block already up to date"; return 0; fi
  if [ -f "$MEMORY" ] && [ ! -f "$MEMORY.before-autonomy-core" ]; then cp -p "$MEMORY" "$MEMORY.before-autonomy-core"; fi
  if [ "$1" = remove ] && [ ! -s "$tmp" ]; then
    # The file held nothing but our block: remove it rather than leave an empty CLAUDE.md.
    rm -f "$tmp" "$MEMORY"; say "  ✓ CLAUDE.md removed (it held only the core's rules)"; return 0
  fi
  mv "$tmp" "$MEMORY"
  if [ "$1" = add ]; then say "  ✓ CLAUDE.md rules block written"; else say "  ✓ CLAUDE.md rules block removed"; fi
}

# ------------------------------------------------------------------------------------ verify
verify() {
  local fail=0 r out probe_sid="autonomy-core-selftest-$$" tmp
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/autonomy-core-verify.XXXXXX")"
  check() { if [ "$1" = 0 ]; then say "  PASS  $2"; else say "  FAIL  $2"; fail=1; fi; }

  "$AC/bin/autonomy" doctor >"$tmp/doctor" 2>&1; check $? "install is complete (autonomy doctor)"
  grep FAIL "$tmp/doctor" | sed 's/^/        /' || true

  # auto-continue: armed → the Stop is blocked with the step; cleared → the Stop passes.
  CLAUDE_CODE_SESSION_ID="$probe_sid" "$AC/bin/autonomy" continue set "selftest step" >/dev/null
  out="$(printf '{"session_id":"%s","cwd":"%s"}' "$probe_sid" "$tmp" | bash "$AC/hooks/continue.sh")"
  case "$out" in *'"decision":"block"'*"selftest step"*|*'"decision": "block"'*"selftest step"*) check 0 "auto-continue blocks a stop while a step is armed" ;;
    *) check 1 "auto-continue blocks a stop while a step is armed (got: ${out:-nothing})" ;; esac
  CLAUDE_CODE_SESSION_ID="$probe_sid" "$AC/bin/autonomy" continue clear >/dev/null
  out="$(printf '{"session_id":"%s","cwd":"%s"}' "$probe_sid" "$tmp" | bash "$AC/hooks/continue.sh")"
  if [ -z "$out" ]; then r=0; else r=1; fi; check $r "auto-continue lets the stop through once cleared"

  # completion gate: "done" over a dirty repo is blocked once, then allowed on the same state.
  if command -v git >/dev/null 2>&1; then
    ( cd "$tmp" && git init -q repo && cd repo && git config user.email selftest@example.invalid \
        && git config user.name selftest && echo a > f && git add f && git commit -qm init && echo b > f ) >/dev/null 2>&1
    local stop_json
    stop_json="$(printf '{"session_id":"%s","cwd":"%s","last_assistant_message":"All done."}' "$probe_sid" "$tmp/repo")"
    out="$(printf '%s' "$stop_json" | bash "$AC/hooks/completion-gate.sh")"
    case "$out" in *block*) check 0 "completion gate blocks \"done\" over uncommitted changes" ;;
      *) check 1 "completion gate blocks \"done\" over uncommitted changes (got: ${out:-nothing})" ;; esac
    out="$(printf '%s' "$stop_json" | bash "$AC/hooks/completion-gate.sh")"
    if [ -z "$out" ]; then r=0; else r=1; fi; check $r "completion gate does not fire twice on the same git state"
    rm -f "$AC/state/gate/$(printf '%s' "$probe_sid|$(cd "$tmp/repo" && pwd)" | cksum | awk '{print $1}')"
  else
    say "  SKIP  completion gate probe (git is not installed)"
  fi

  # backup before write: the file about to be replaced is copied, and restore puts it back.
  printf 'original\n' > "$tmp/doc.md"
  printf '{"tool_name":"Write","tool_input":{"file_path":"%s"}}' "$tmp/doc.md" | bash "$AC/hooks/backup-before-write.sh"
  printf 'rewritten\n' > "$tmp/doc.md"
  "$AC/bin/autonomy" restore "$tmp/doc.md" >/dev/null 2>&1
  if [ "$(cat "$tmp/doc.md")" = original ]; then r=0; else r=1; fi; check $r "a file replaced by Write is backed up and restorable"
  find "$AC/backups" -name "$(printf '%s' "$tmp" | sed 's#/#%#g')*" -exec rm -f {} + 2>/dev/null || true

  # settings.json reads back with all three hooks, as valid JSON.
  json_valid "$SETTINGS" && [ "$(grep -c "$HOOK_TAG" "$SETTINGS")" -ge 3 ]
  check $? "settings.json is valid JSON and runs the 3 hooks"

  rm -rf "$tmp"
  return "$fail"
}

# ------------------------------------------------------------------------------------ main
say "autonomy core → $CFG  ($PLATFORM, JSON via $JSON)"

if [ "$MODE" = verify ]; then
  verify && { say "READY"; exit 0; } || { say "NOT READY — see the FAIL lines above."; exit 1; }
fi

if [ "$MODE" = uninstall ]; then
  apply_settings remove
  [ -f "$MEMORY" ] && apply_memory remove
  for c in wrap handoff; do
    if grep -q '<!-- autonomy-core -->' "$CFG/commands/$c.md" 2>/dev/null; then rm -f "$CFG/commands/$c.md"; say "  ✓ removed /$c"; fi
  done
  rm -rf "${AC:?}/hooks" "${AC:?}/bin" "${AC:?}/state" "${AC:?}/CLAUDE.core.md" "${AC:?}/VERSION"
  rmdir "$AC" 2>/dev/null || say "  kept $AC (your backups/ and handoffs/)"
  say "Removed. Restart Claude Code so it stops running the hooks."
  exit 0
fi

# The full install already provides all of this (and more); two copies would double every hook.
if [ -e "$CFG/hooks/session-continue.sh" ] && [ "$FORCE" != 1 ]; then
  die "the full claude-infrastructure install is already in $CFG (hooks/session-continue.sh), and it includes this core. Nothing changed. (--force installs anyway.)"
fi
command -v git >/dev/null 2>&1 || warn "git is not installed: the completion gate and 'autonomy ledger' stay silent without it"
command -v claude >/dev/null 2>&1 || warn "Claude Code is not on PATH. Install it: curl -fsSL https://claude.ai/install.sh | bash"

STAGE="$(mktemp -d "${TMPDIR:-/tmp}/autonomy-core-stage.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
write_payload
# The rules and commands name the install directory; fill it in (| and & are escaped for sed).
ac_sed="$(printf '%s' "$AC" | sed 's/[|&\\]/\\&/g')"
for f in "$STAGE/CLAUDE.core.md" "$STAGE"/commands/*.md; do
  sed "s|__AC_HOME__|$ac_sed|g" "$f" > "$f.new" && mv "$f.new" "$f"
done

mkdir -p "$AC/hooks" "$AC/bin" "$AC/state" "$AC/backups" "$AC/handoffs" "$CFG/commands"
for f in hooks/lib.sh hooks/continue.sh hooks/completion-gate.sh hooks/backup-before-write.sh bin/autonomy CLAUDE.core.md VERSION; do
  cp "$STAGE/$f" "$AC/$f"
done
chmod 755 "$AC"/hooks/*.sh "$AC/bin/autonomy"
say "  ✓ $AC (version $(cat "$AC/VERSION"))"
for c in wrap handoff; do
  dest="$CFG/commands/$c.md"
  if [ -f "$dest" ] && ! grep -q '<!-- autonomy-core -->' "$dest"; then
    warn "$dest is your own /$c; left alone (the core's version is not installed)"
  else
    cp "$STAGE/commands/$c.md" "$dest"; say "  ✓ /$c command"
  fi
done
apply_memory add
apply_settings add

say ""
say "Verifying:"
if verify; then
  say ""
  say "READY. Restart Claude Code (hooks load when a session starts), then try /wrap in a git repo."
  say "Command line: $AC/bin/autonomy   ·   undo: bash install-core.sh --uninstall"
else
  say ""
  say "NOT READY — see the FAIL lines above. Undo with: bash install-core.sh --uninstall"
  exit 1
fi
