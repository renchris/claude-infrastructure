#!/bin/bash
# migration-class: c10
# migration-step: add the claudeMdExcludes glob "**/.claude/rules/agent-operating-lessons-situational.md" to ONE account's settings.json (default ~/.claude-tertiary, override CC_RULES_SPLIT_ACCOUNT_DIR) so that account's sessions stop loading the situational rules half — the A/B arm of the rules split. The glob drops the situational file in EVERY repo on that account, and only claude-infrastructure's resident file points at it, so lessons the memory rotor routes in other repos stop loading on that account. It edits settings.json, which is C10
# migration-run: bash ~/Development/claude-infrastructure/migrations/0036-rules-situational-exclude.sh
# migration-verify: jq -e --arg g '**/.claude/rules/agent-operating-lessons-situational.md' '(.claudeMdExcludes // []) | any(.[]; . == $g)' "${CC_RULES_SPLIT_ACCOUNT_DIR:-$HOME/.claude-tertiary}/settings.json" >/dev/null
#
# 0036 — item F4 of docs/research/token-efficiency-2026-09-23/OPPORTUNITIES.md (rank 4).
#
# WHAT IT DOES. `.claude/rules/agent-operating-lessons.md` in claude-infrastructure loaded ~27.9k
# tokens into every context started in that repo. It was split (same diff as this file) into a
# resident half — the header and the 19 lessons the audit labelled RESIDENT — and
# `agent-operating-lessons-situational.md`, which holds the other 189 bullets verbatim
# (docs/research/token-efficiency-2026-09-23/audit/C7.labels.md, C7.verify.md). With no exclude set,
# both halves load and nothing changes. This migration adds one glob to one account's
# `claudeMdExcludes`, so that account's sessions load only the resident half; the other accounts
# stay on the full load, which is the control arm.
#
# MEASURED BEFORE STAGING, headless `/context` from the worktree root on 2.1.280:
#   no exclude:                          resident 3.5k + situational 24.6k tokens, memory files 87.9k
#   --settings with this glob (one run): resident 3.5k, situational absent,      memory files 63.4k
# so the glob is honoured for a project rules file, and it removes ~24.5k tokens per context.
#
# WHY ONE ACCOUNT, NOT THE FLEET. The resident half tells a session to grep the situational file for
# the symptom before diagnosing a failing test, gate, hook, land or tool. Whether sessions actually
# do that, and what it costs them when they do not, is the question the A/B answers. Rolling it to
# every account would remove the comparison.
#
# WHY A GLOB THAT MATCHES EVERY REPO. `**/` also matches a worktree or any other checkout of this
# repo, which is what a per-account arm needs. It also matches a same-named file in any other repo
# (the memory rotor now creates one wherever it routes lessons), and that is intended: a situational
# half is situational wherever it lives. The cost, stated in the migration-step line so the operator
# sees it before running this: on the flagged account, lessons the rotor routes in OTHER repos stop
# loading, and nothing in those repos tells a session to grep the file, because only
# claude-infrastructure's resident file carries that pointer. For those repos the arm is a demotion,
# not a move (F4 review, minor 6).
#
# REVERT. Remove the glob from that settings.json's claudeMdExcludes (the backup beside it is the
# exact prior file). Takes effect in NEW sessions; running panes keep what they loaded.
set -uo pipefail

GLOB='**/.claude/rules/agent-operating-lessons-situational.md'
dir="${CC_RULES_SPLIT_ACCOUNT_DIR:-$HOME/.claude-tertiary}"
f="$dir/settings.json"

command -v jq >/dev/null 2>&1 || { printf '0036: jq required\n' >&2; exit 1; }
[ -f "$f" ] || { printf '0036: %s — no settings.json there; not creating one\n' "$f" >&2; exit 1; }
# Edit the real file, not a symlink standing in for it: `mv` over a symlink would replace the link.
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
  printf '0036: %s — added claudeMdExcludes %s (backup: %s). Takes effect in NEW sessions.\n' "$f" "$GLOB" "$bak"
  exit 0
fi
rm -f "$tmp"
printf '0036: %s — edit did not verify; left unchanged\n' "$f" >&2
exit 1
