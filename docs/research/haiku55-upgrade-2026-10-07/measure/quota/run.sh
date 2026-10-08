#!/usr/bin/env bash
set -u
D=/tmp/haiku55-measure/quota; CFG=$HOME/.claude-next
CA=/Users/chrisren/Development/.worktrees/haiku55-flip/bin/claude-accounts
rm -f "$D/stop"; python3 /tmp/haiku55-measure/sample.py "$CA" next "$D/series.jsonl" 30 "$D/stop" &
SP=$!
mark() { echo "{\"phase\":\"$1\",\"ts\":$(date +%s)}" >> "$D/phases.jsonl"; }
mark hold0; sleep 300
mark H1;  /tmp/haiku55-measure/burn.sh claude-haiku-5-5 medium 720 24 "$D/H1.jsonl" "$CFG"
mark hold1; sleep 360
mark O;   /tmp/haiku55-measure/burn.sh claude-opus-5-5 high 720 16 "$D/O.jsonl" "$CFG"
mark hold2; sleep 360
mark H2;  /tmp/haiku55-measure/burn.sh claude-haiku-5-5 medium 720 24 "$D/H2.jsonl" "$CFG"
mark hold3; sleep 360
mark end; touch "$D/stop"; wait $SP
