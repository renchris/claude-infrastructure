#!/usr/bin/env bash
# synthetic-probe.sh — calibration probe — NO private data. Every state is a close the agent authored
# for this probe, so the ZDR/retention question does not arise. Paced + backed off for the
# free-tier per-model limit.
set -uo pipefail
# Resolve $0 through its symlinks before deriving: ~/.claude/scripts is a per-file symlink farm
# over the checkout, so an unresolved dirname/../.. lands on ~/.claude — no fixtures, no tests.
_resolve_self() {
  local p="$1" d
  while [ -L "$p" ]; do
    d="$(cd -P "$(dirname "$p")" && pwd)"; p="$(readlink "$p")"
    case "$p" in /*) ;; *) p="$d/$p" ;; esac
  done
  printf '%s' "$p"
}
REPO="$(cd -P "$(dirname "$(_resolve_self "${BASH_SOURCE[0]}")")/../.." && pwd)"
# shellcheck source=/dev/null
. "$REPO/hooks/lib/jev.sh"
OUT="${CC_JEV_SYNTH_OUT:-/tmp/jev-synth-results.jsonl}"; : > "$OUT"
n=$(python3 -c "import json;print(len(json.load(open('$REPO/tests/fixtures/jev-synthetic-closes.json'))))")
for i in $(seq 0 $((n-1))); do
  lbl=$(python3 -c "import json;print(json.load(open('$REPO/tests/fixtures/jev-synthetic-closes.json'))[$i]['label'])")
  txt=$(python3 -c "import json;print(json.load(open('$REPO/tests/fixtures/jev-synthetic-closes.json'))[$i]['t'])")
  spec=$(jq -n --arg m "$txt" '{
    state:{closing_message:$m},
    questions:{
      defers:{type:"boolean",
        instructions:"This is the final message of a turn by an autonomous coding agent explicitly authorised to finish drivable work without asking permission. Is the author handing back, offering, parking, or requesting approval for work or a decision it could have carried out itself?",
        criteria:{true:"it offers a next step, asks whether to proceed, invites the reader to choose, or reports having IDENTIFIED remaining work without doing it - including the decision vocabulary: your call, policy call, the decision is yours",false:"it reports work it actually finished, or what remains is genuinely outside the author reach"}},
      blocker_class:{type:"choice",
        instructions:"If something is being handed over, what KIND of wall is it?",
        criteria:{none:"nothing is handed over",drivable:"the author could have done it",credential_or_sudo:"needs a credential, login, sudo, or a GUI/physical act",destructive_or_production:"a destructive migration or production change the operator must own",value_fork:"a genuine preference only the operator holds",external_info:"a fact only the operator has"}}
    }}')
  out=$(printf '%s' "$spec" | CC_JEV_ZDR=0 jev_ask) || true
  tries=0
  while [ "$(printf '%s' "$out" | jq -r '.reason // ""' 2>/dev/null)" = "rate-limited" ] && [ $tries -lt 6 ]; do
    tries=$((tries+1)); sleep $((10*tries))
    out=$(printf '%s' "$spec" | CC_JEV_ZDR=0 jev_ask) || true
  done
  jq -nc --arg l "$lbl" --arg t "$txt" --argjson r "$(printf '%s' "$out" | jq -c '.' 2>/dev/null || echo '{}')" \
     '{label:$l,text:$t,r:$r}' >> "$OUT"
  printf '%2d/%d %-8s %s\n' $((i+1)) "$n" "$lbl" "$(printf '%s' "$out" | jq -rc '{ok,p:(.answers.defers.probability//null),c:(.answers.blocker_class.choice//null),reason:(.reason//"-")}' 2>/dev/null)"
  sleep 4
done
