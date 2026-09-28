#!/usr/bin/env bash
# rules-loaded.sh — does Claude Code actually LOAD a given `.claude/rules/*.md` file, or is it
# listed in `claudeMdExcludes`?
#
# WHY THIS EXISTS. Migration 0036 set `claudeMdExcludes` to drop
# `**/.claude/rules/agent-operating-lessons-situational.md`, while six hook and bin strings kept
# telling the model that file loads unconditionally — one of them told it to DELETE the MEMORY.md
# bullet that was then the rule's only resident pointer. Wording about what loads must be computed
# from the setting that decides it, never restated (docs/research/truememory-2026-09-27.md §3.1).
#
# `rules_file_loads <abs-path>` prints exactly one of `loads|excluded|unknown` and returns 0.
#   loads     the settings file parsed and no claudeMdExcludes glob matches the path
#   excluded  a glob matches (bash pattern match, where `*` also crosses `/`, so `**/x` matches)
#   unknown   no jq, no readable settings, invalid JSON, a non-array value, or an empty path
# It fails open to `unknown` and NEVER to `loads`: a false `loads` is the defect this replaces.
#
# Scope, stated rather than hidden: it reads ONE file, `${RULES_LOADED_SETTINGS:-~/.claude/settings.json}`
# (every account root links to it since migration 0037). A project-level claudeMdExcludes is not
# consulted, and the auto-memory kill switch is a separate question (#8's `killswitch=` field).
# One jq fork per call, so callers use it on actuation paths, never per prompt.
rules_file_loads() {
  local p="${1:-}" s="${RULES_LOADED_SETTINGS:-$HOME/.claude/settings.json}" globs g
  if [ -z "$p" ] || ! command -v jq >/dev/null 2>&1 || [ ! -r "$s" ]; then
    printf 'unknown\n'; return 0
  fi
  if ! globs=$(jq -r '(.claudeMdExcludes // []) | if type == "array" then .[] | strings else error("not an array") end' "$s" 2>/dev/null); then
    printf 'unknown\n'; return 0
  fi
  while IFS= read -r g; do
    [ -n "$g" ] || continue
    # shellcheck disable=SC2053  # $g is a glob by design; quoting it would make it a literal
    if [[ $p == $g ]]; then printf 'excluded\n'; return 0; fi
  done <<EOF
$globs
EOF
  printf 'loads\n'
}
