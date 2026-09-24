#!/bin/bash
# migration-class: c10
# migration-step: add the claudeMdExcludes glob "**/.claude/rules/agent-operating-lessons-situational.md" to the ONE shared ~/.claude/settings.json that every account's settings.json links to since 0037 — so it changes ALL accounts at once (operator ruling 2026-09-23: accounts are interchangeable, config is all-or-nothing), and every session on every account stops loading the situational rules half. The glob drops the situational file in EVERY repo, and only claude-infrastructure's resident file points at it, so lessons the memory rotor routes into other repos' situational files stop loading. It refuses to run unless `cc-settings-parity check` reports every account linked (else it would reach some accounts and not others). It edits settings.json, which is C10
# migration-run: bash ~/Development/claude-infrastructure/migrations/0036-rules-situational-exclude.sh
# migration-verify: "$HOME/.claude/bin/cc-settings-parity" check >/dev/null 2>&1 && jq -e --arg g '**/.claude/rules/agent-operating-lessons-situational.md' '(.claudeMdExcludes // []) | any(.[]; . == $g)' "$HOME/.claude/settings.json" >/dev/null
#
# The verifier is config-dir-INVARIANT on purpose (as in 0037): registration-state.sh re-runs it once
# per config dir with CC_CLAUDE_DIR re-aimed, and this effect is a fact about the whole fleet — the
# glob is in the shared file AND every account links to that file — so every dir gives one answer.
#
# REWRITTEN 2026-09-24 (token-efficiency wave 2, item 1). The first version wrote to ONE account's
# settings.json (default ~/.claude-tertiary, CC_RULES_SPLIT_ACCOUNT_DIR) as the A/B arm. Since 0037
# that file is a symlink to ~/.claude/settings.json, so running the old version would have changed
# the whole fleet while its step line claimed one account. The per-account arm was withdrawn by the
# 2026-09-23 ruling; the A/B moved offline (docs/research/token-efficiency-2026-09-23/eval/, rank 4).
#
# 0036 — item F4 of docs/research/token-efficiency-2026-09-23/OPPORTUNITIES.md (rank 4).
#
# WHAT IT DOES. `.claude/rules/agent-operating-lessons.md` in claude-infrastructure loaded ~27.9k
# tokens into every context started in that repo. It was split (same diff as this file) into a
# resident half — the header and the 19 lessons the audit labelled RESIDENT — and
# `agent-operating-lessons-situational.md`, which holds the other 189 bullets verbatim
# (docs/research/token-efficiency-2026-09-23/audit/C7.labels.md, C7.verify.md). With no exclude set,
# both halves load and nothing changes. This migration adds one glob to the shared
# `claudeMdExcludes`, so sessions on every account load only the resident half.
#
# MEASURED BEFORE STAGING, headless `/context` from the worktree root on 2.1.280:
#   no exclude:                          resident 3.5k + situational 24.6k tokens, memory files 87.9k
#   --settings with this glob (one run): resident 3.5k, situational absent,      memory files 63.4k
# so the glob is honoured for a project rules file, and it removes ~24.5k tokens per context.
#
# ALL ACCOUNTS OR NONE. The resident half tells a session to grep the situational file for the
# symptom before diagnosing a failing test, gate, hook, land or tool. Whether sessions do that, and
# what it costs when they do not, is measured OFFLINE (headless runs with and without this glob via
# --settings; REPORT.md rank 4 carries the verdict). There is no per-account arm any more.
#
# WHY A GLOB THAT MATCHES EVERY REPO. `**/` also matches a worktree or any other checkout of this
# repo. It also matches a same-named file in any other repo (the memory rotor creates one wherever it
# routes lessons), and that is intended: a situational half is situational wherever it lives. The
# cost, stated in the migration-step line so the operator sees it before running this: lessons the
# rotor routes in OTHER repos stop loading, and nothing in those repos tells a session to grep the
# file, because only claude-infrastructure's resident file carries that pointer. For those repos this
# is a demotion, not a move (F4 review, minor 6).
#
# REVERT. Remove the glob from ~/.claude/settings.json's claudeMdExcludes (the backup beside it is the
# exact prior file). Takes effect in NEW sessions on every account; running panes keep what they loaded.
set -uo pipefail

GLOB='**/.claude/rules/agent-operating-lessons-situational.md'
dir="$HOME/.claude"
f="$dir/settings.json"
parity="${CC_SETTINGS_PARITY_BIN:-$HOME/.claude/bin/cc-settings-parity}"

command -v jq >/dev/null 2>&1 || { printf '0036: jq required\n' >&2; exit 1; }
[ -f "$f" ] || { printf '0036: %s — no settings.json there; not creating one\n' "$f" >&2; exit 1; }
# All accounts or none: every account's settings.json must link to this one file, or the edit would
# reach some accounts and not others (the per-account arm the 2026-09-23 ruling withdrew).
if ! "$parity" check >/dev/null 2>&1; then
  printf '0036: accounts do not all share %s (%s check failed) — refusing, the glob would not reach every account. Converge with migration 0037 first.\n' "$f" "$parity" >&2
  exit 1
fi
# Edit the real file (README rule 7): `mv` over a symlink would replace the link with a real file.
if [ -L "$f" ]; then
  t="$(readlink "$f")"; case "$t" in /*) f="$t" ;; *) f="$dir/$t" ;; esac
fi
jq -e . "$f" >/dev/null 2>&1 || { printf '0036: %s — not valid JSON; left unchanged\n' "$f" >&2; exit 1; }

if jq -e --arg g "$GLOB" '(.claudeMdExcludes // []) | any(.[]; . == $g)' "$f" >/dev/null 2>&1; then
  printf '0036: %s — glob already present\n' "$f"
  exit 0
fi
if ! jq -e '(.claudeMdExcludes // []) | type == "array"' "$f" >/dev/null 2>&1; then
  printf '0036: %s — claudeMdExcludes is not an array; left unchanged\n' "$f" >&2
  exit 1
fi

bak="$f.bak-0036-$(date +%Y%m%d%H%M%S)"
cp -p "$f" "$bak" || { printf '0036: %s — backup FAILED, not touching it\n' "$f" >&2; exit 1; }

tmp="$f.tmp-0036-$$"
if ! jq --arg g "$GLOB" '.claudeMdExcludes = ((.claudeMdExcludes // []) + [$g])' "$f" > "$tmp" 2>/dev/null \
   || ! [ -s "$tmp" ] || ! jq -e . "$tmp" >/dev/null 2>&1; then
  rm -f "$tmp"; printf '0036: %s — jq edit FAILED; left unchanged\n' "$f" >&2; exit 1
fi

# Verify BY CONTENT before replacing the live file: every other key is unchanged, the prior
# excludes are all still there, and the glob was appended exactly once.
same_rest=$(jq -n --slurpfile a "$f" --slurpfile b "$tmp" \
  '($a[0] | del(.claudeMdExcludes)) == ($b[0] | del(.claudeMdExcludes))')
same_excl=$(jq -n --slurpfile a "$f" --slurpfile b "$tmp" --arg g "$GLOB" \
  '(($a[0].claudeMdExcludes // []) + [$g]) == $b[0].claudeMdExcludes')
if [ "$same_rest" = true ] && [ "$same_excl" = true ]; then
  mv "$tmp" "$f" || { rm -f "$tmp"; printf '0036: %s — replace FAILED; left unchanged\n' "$f" >&2; exit 1; }
  if ! "$parity" check >/dev/null 2>&1; then
    printf '0036: %s — glob added, but %s check now FAILS: an account no longer shares the file. Restore with: cp -p %s %s\n' "$f" "$parity" "$bak" "$f" >&2
    exit 1
  fi
  printf '0036: %s — added claudeMdExcludes %s for EVERY account (backup: %s). Takes effect in NEW sessions.\n' "$f" "$GLOB" "$bak"
  exit 0
fi
rm -f "$tmp"
printf '0036: %s — edit did not verify; left unchanged\n' "$f" >&2
exit 1
