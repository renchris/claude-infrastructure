#!/bin/bash
# research-job.sh <job> — the ONE launchd runner for the research program's scheduled passes
# (REPORT.md §5.5, §8 item 12, §10 item 4). The five plists in launchd/staged/com.claude.research-*
# run `/bin/bash <this> <job>`; it pins PATH to what launchd can resolve and execs
# `cc-research job <job>`, which iterates every program in certifying|certified. Re-checks run on
# this schedule only, never because a question was asked.
#
#   research-job.sh sweep|freshness|triage|drift|market
#
# Exit 2 on an unknown job; otherwise cc-research's own exit (1 = some program's pass failed).
# CC_RESEARCH_BIN overrides the cc-research binary (tests). bash 3.2-safe.
set -u

export PATH="$HOME/.claude/bin:/usr/bin:/bin"

job="${1:-}"
case "$job" in
  sweep|freshness|triage|drift|market) ;;
  *)
    echo "research-job: unknown job '$job' (one of sweep freshness triage drift market)" >&2
    exit 2
    ;;
esac

exec "${CC_RESEARCH_BIN:-cc-research}" job "$job"
