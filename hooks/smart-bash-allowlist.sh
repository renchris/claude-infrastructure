#!/bin/bash
# smart-bash-allowlist.sh — PreToolUse hook that conditionally auto-allows
# common safe commands, reducing permission prompt fatigue.
#
# Safety invariant: re-runs the DANGER_PATTERNS from validate-bash.sh and
# refuses to emit "allow" if any match. Kill switch: SMART_ALLOWLIST_DISABLED=1.
#
# Runs BEFORE validate-bash.sh in the hooks array. If this hook emits "allow",
# validate-bash.sh still runs (hooks chain independently in Claude Code's
# model — first non-empty decision wins; but deny always overrides).
#
# Auto-allows:
#   1. git commit        — unless --no-verify/--amend-published
#   3. sed -i <file>     — target under CWD, not in DENY_DIR/DENY_SENSITIVE
#   5. chmod <safe-mode> — 644/755/600/700/750/640/+x/u+x only, under CWD
#   6. sed -n <script>   — read-only paging (positive whitelist; see rule 6)
#
# RULE NUMBERS 2 AND 4 ARE RETIRED, NOT RENUMBERED — the gap is deliberate, so that a reader
# comparing this file against the decision packet or the tests can see that two rules were
# REMOVED rather than that the list was always this short.
#
# WHY THEY WERE REMOVED (2026-08-12). Both auto-approved a command the operator had independently
# placed behind an `ask` rule in ~/.claude/settings.json (`Bash(git push:*)`, and deletion via the
# global rm guard). A PreToolUse hook emitting "allow" BYPASSES the permission system, so wiring
# this hook would have silently revoked those gates as a side effect of a prompt-reduction change
# — the operator would keep the rule and lose the guard, with nothing in either file recording it.
#
# Rule 4 was also DEAD, and mis-specified underneath the deadness — measured, not read:
#   • Its extraction regex `[[:alnum:]_.\-/]+` is an INVALID CHARACTER RANGE. /usr/bin/grep exits 2
#     with "invalid character range", so GIT_PUSH_MATCH was always empty and rule 4 never allowed
#     any push at all, on any branch, for its whole life.
#   • Underneath that, its reject list was `^(develop|production|prod|release.*)$` — `main` and
#     `master` ABSENT. So repairing the bracket expression, which any reader would call a typo fix,
#     would have SILENTLY ARMED `git push origin main` against a standing never-push-to-main rule.
# A latent defect sitting behind a broken matcher is the worst arrangement of the two: there is no
# symptom to motivate the repair, and the repair is what makes it dangerous.
#
# (Recorded because the first pass of this analysis got it wrong in the operator-facing direction:
# it reported that `git push origin main` WOULD be auto-allowed. The missing main|master was real;
# the consequence attached to it was not, because the rule could not fire. The control in
# tests/smart-bash-allowlist-narrow.bats is what caught it — a true fact next to a wrong
# consequence reads exactly like a diagnosis.)
#
# Neither rule carried the prompt volume that justified them: the measured blockers in the beacon
# archive (1,124 prompts, 2026-07-31 →) are compound commands, and rules 1/3/5/6 cover those.

#
# ── 2026-08-20: THE LINE ABOVE IS FALSE, AND ITS FALSENESS WAS THE WHOLE DEFECT ──────
# "rules 1/3/5/6 cover those [compound commands]" was never true, and running the hook
# proves it in BOTH directions at once:
#   * Rules 3/5/6 are whole-command-anchored (`[^;&|]+$`), so on a compound command they
#     cannot fire AT ALL. `cd /tmp && sed -n 1,20p f` got no decision.
#   * Rule 1 was anchored only at the START, so it fired on ANY command beginning with
#     `git commit` — carrying whatever followed. Since a PreToolUse `allow` BYPASSES the
#     permission system entirely, `git commit -m x && <anything>` auto-approved across
#     EIGHT of the operator's own 36 Bash fence rules, including the hard `deny` entries
#     `git push --force` and `rm -rf .git`, plus `git clean -xdf`, `wget`, `fly deploy`,
#     `git reset --hard`, `git restore` and `git push`. Wired in 5 of 5 config dirs.
# So the safe rules were inert on the corpus that generates the prompts, and the one
# unsafe rule was a universal bypass. Measured: 90.4% of the 1,693 blocking commands in
# ~/.claude/autonomy/permission-archive are compound (mean 11.9 segments, 59.1% multi-line).
#
# The suite that guarded this file could not see it: every case it tried was a SINGLE
# command, so it asserted the fence held on exactly the shape where nothing threatened it.
#
# THE FIX is not a tighter regex — it is to stop deciding on the raw string. The decision
# core now lives in lib/smart-bash-allowlist.py, which decomposes the command and requires
# EVERY segment to independently clear the operator's live permissions.ask/deny fence and
# match a positive whitelist. Anything it cannot decompose with confidence gets no
# decision. This file stays the wired entry point so the 5 config dirs need no re-wiring.

# Kill switch
[[ "${SMART_ALLOWLIST_DISABLED:-0}" == "1" ]] && exit 0

set -uo pipefail

# Delegate to the decision core. `exec` so the hook's exit status is the core's own.
# If python3 is missing the hook must DEFER (exit 0), never fail in the allow direction.
#
# RESOLVE OUR OWN REAL PATH FIRST. `${BASH_SOURCE[0]%/*}` is the directory we were INVOKED
# through, not the directory we live in, and this hook is invoked through the ~/.claude
# symlink layer — so the first cut looked for the core at ~/.claude/hooks/lib/, which is a
# real directory of PER-FILE symlinks that has no link for a newly added file. The core was
# therefore unreadable and this hook deferred every command: fail-safe, but completely
# inert, and inert in the way nothing reports (a deferring allowlist looks exactly like an
# allowlist with nothing to say). Measured live before the fix.
#
# Resolving the chain makes the core reachable from wherever the layer points, so the hook
# works the moment the checkout advances and does not also depend on someone remembering to
# mint a symlink for each new sibling file.
_self="${BASH_SOURCE[0]}"
while [[ -L "$_self" ]]; do
  _link=$(readlink "$_self") || break
  case "$_link" in
    /*) _self="$_link" ;;
    *)  _self="$(cd -P -- "$(dirname -- "$_self")" 2>/dev/null && pwd)/$_link" ;;
  esac
done
_CORE="$(cd -P -- "$(dirname -- "$_self")" 2>/dev/null && pwd)/lib/smart-bash-allowlist.py"
# Fall back to the invoked-path sibling, so a future layer that DOES link the core still
# works even if the resolution above cannot run.
[[ -r "$_CORE" ]] || _CORE="${BASH_SOURCE[0]%/*}/lib/smart-bash-allowlist.py"
if [[ ! -r "$_CORE" ]] || ! command -v python3 >/dev/null 2>&1; then
  cat >/dev/null 2>&1 || true   # drain stdin so the harness never sees a broken pipe
  exit 0
fi
exec python3 "$_CORE"
