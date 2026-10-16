#!/usr/bin/env bash
# y_crosscheck.sh — re-derive the report's headline numbers by a DIFFERENT method than the script
# that produced them (raw git / jq / gh REST / cc-custody / the tool the census replicates), and
# compare with data/z_headlines.txt. Stands in for the separate auditor agent, which the research
# block refused this session (Workflow and Agent are research verbs while the program certifies).
#
# Usage (from the repo root):
#   bash docs/research/tm2-cost-vs-outcome-2026-10-16/scripts/y_crosscheck.sh
# Prints one line per check: PASS|FAIL|NOTE <name>: headline=<x> independent=<y>. Exit 1 on any FAIL.
set -u
R=docs/research/tm2-cost-vs-outcome-2026-10-16
H="$R/data/z_headlines.txt"
TM2="$HOME/Development/.worktrees/tm2-plan"
P="$TM2/docs/research/truememory-2.0-2026-09-28/program"
fail=0

hl() { awk -F' = ' -v k="$1" '$1==k {print $2}' "$H"; }
check() { # name headline independent
  if [ "$2" = "$3" ]; then echo "PASS $1: headline=$2 independent=$3"
  else echo "FAIL $1: headline=$2 independent=$3"; fail=1; fi
}
near() { # name headline independent tolerance_pct
  if python3 -I -c "import sys; a,b,t=map(float,sys.argv[1:]); sys.exit(0 if abs(a-b)<=t/100*max(abs(a),abs(b)) else 1)" "$2" "$3" "$4"
  then echo "PASS $1: headline=$2 independent=$3 (within $4%)"
  else echo "FAIL $1: headline=$2 independent=$3 (tolerance $4%)"; fail=1; fi
}

# 1 kit commits: plain git count, no classifier
check kit_commits "$(hl kit_commits)" "$(git log origin/main --since=2026-09-28 --oneline -- scripts/research-kit | wc -l | tr -d ' ')"
# 2 kit defect fixes: subjects starting fix( or revert( on kit commits (a cruder rule than the hand classes)
echo "NOTE kit_commits_D: headline=$(hl kit_commits_D) subject-rule fix/revert=$(git log origin/main --since=2026-09-28 --format=%s -- scripts/research-kit | grep -cE '^(fix|revert)')"
# 3 fleet responses: the tool the census replicates (its own scan, run earlier into data/)
near fleet_responses "$(hl fleet_n)" "$(awk '/billed response/ {for(i=1;i<=NF;i++) if($i ~ /^[0-9]+$/ && $(i+1) ~ /billed/) print $i}' "$R/data/k_ccqp_census.txt")" 0.1
# 4 holes, decisions, premises: distinct ids with jq
check holes_distinct "$(hl holes_distinct)" "$(jq -r '.id // empty' "$P/holes.jsonl" | sort -u | wc -l | tr -d ' ')"
check decisions "$(hl decisions)" "$(jq -r '.id // empty' "$P/decisions.jsonl" | sort -u | wc -l | tr -d ' ')"
check premises "$(hl premises)" "$(jq -r '.id // empty' "$P/premises.jsonl" | sort -u | wc -l | tr -d ' ')"
check probes "$(hl probes)" "$(jq -r '.id // empty' "$P/probes.jsonl" | sort -u | wc -l | tr -d ' ')"
# 5 per-round new material: the round matrices with jq
for k in 1 2 3 4 5 6; do
  check "round_${k}_new_material" "$(hl round_${k}_new_material)" "$(jq -r '.new_material' "$P/rounds/$k/matrix.json")"
done
# 6 certification material total = sum of the matrices
check material_real_new_certification_rounds_1_6 "$(hl material_real_new_certification_rounds_1_6)" \
  "$(for k in 1 2 3 4 5 6; do jq -r '.new_material' "$P/rounds/$k/matrix.json"; done | paste -sd+ - | bc)"
# 7 plan critique rounds 1-23: verified counts straight from the commit subjects with grep/sed
check plan_critique_rounds_1_23_verified_findings "$(hl plan_critique_rounds_1_23_verified_findings)" \
  "$(git -C "$TM2" log --format=%s -- docs/plans/TRUEMEMORY_2_0.md docs/research/truememory-2.0-2026-09-28 | grep -E 'critique round ([1-9]|1[0-9]|2[0-3]) record \(' \
     | sed -E 's/.*critique round ([0-9]+) record \(([0-9]+) verified.*/\1 \2/' | sort -un | awk '{s+=$2} END {print s}')"
# 8 upstream PRs by us: REST instead of gh pr list
check upstream_prs_opened_by_us "$(hl upstream_prs_opened_by_us)" \
  "$(gh api 'repos/buildingjoshbetter/TrueMemory/pulls?state=all&per_page=100' --paginate -q '[.[]|select(.user.login=="renchris")]|length' | paste -sd+ - | bc)"
# 9 quota: the two methods must agree within 10%
near pp_core_M1_vs_M2 "$(hl pp_M1_core)" "$(hl pp_M2_core)" 10
# 10 span: date arithmetic on the first TM2 plan commit
check span_days_since_first_tm2_plan_commit "$(hl span_days_since_first_tm2_plan_commit)" \
  "$(python3 -I -c "from datetime import datetime as d; print(round((d.fromisoformat('2026-10-16T14:00:00+00:00')-d.fromisoformat('$(git -C "$TM2" log -1 --format=%cI b2401a113)')).total_seconds()/86400,2))")"
# 11 fires: count open rows in the custody ledger with grep
check fires "$(hl fires)" "$(cc-custody list | awk -F'\t' '$2=="open" && ($3 ~ /^fire-tm2/ || $3 ~ /^fire-kit-/ || $3 ~ /^fire-method/)' | wc -l | tr -d ' ')"
# 12 gate now: count row states in the certifying gate log with grep
g="$HOME/Development/claude-private/tm2-plan/tm2-cert.log"
check gate_pass_now "$(hl gate_pass_now)" "$(grep -cE '^ ?[0-9]+\. .* PASS$' "$g")"
check gate_filed_now "$(hl gate_filed_now)" "$(grep -cE '^ ?[0-9]+\. .* FILED$' "$g")"
# 13 operator packets naming truememory: grep -l count
check operator_packets "$(hl operator_packets)" "$(grep -li truememory "$HOME"/.claude/autonomy/decisions/*.json | wc -l | tr -d ' ')"
exit $fail
