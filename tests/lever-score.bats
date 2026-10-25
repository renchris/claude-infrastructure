#!/usr/bin/env bats
# lever-score.bats — the usage levers' scorer core (docs/plans/USAGE_LEVERS.md § W7+ §3 "Scorer",
# §2 "Plumbing gate"; wave S4): bin/cc-lever-score over scripts/lib/lever_events.py, which takes its
# tokens from bin/cc-token-ledger scan().
#
# Contracts held here, each at the CLI boundary against the static fixture in
# tests/fixtures/lever-score/ (three sessions over the four account roots, plus a transplanted copy
# made in setup; expected values worked by hand from the fixture's usage blocks at read 0.0067 /
# write 0.245 / output 0.404 pp per Mtok):
#   · selftest passes: planted effect recovered, byte-identical output twice, plumbing fails closed
#   · a transcript copied into a second root, and a root reached through ~/.claude-next's symlink,
#     count once; a session's subagent transcripts are part of its row
#   · tool errors exclude hook denies; a context-wall death is found; lands split by exit class
#   · plumbing fails closed on a missing root and on >0.1% unparseable rows (each with its
#     positive control), and is never CLEAN while any check lacks data
#   · ledger --write merges by sid; the verbs wave S5 owns exit 3
# RED-proof: (a) file-absence: before S4 there is no bin/cc-lever-score. (b) mutation, run by hand
# 2026-10-25 on a scratch copy of bin/ scripts/lib/ hooks/lib/: dropping scan()'s seen_mid check
# turns test 2 red (responses 4); deleting the root-status branch turns test 4 red; dropping the
# per-store parse ratio turns test 5 red.

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
  CLI="$REPO/bin/cc-lever-score"
  FX="$BATS_TEST_TMPDIR/fx"
  mkdir -p "$FX"
  cp -R "$REPO/tests/fixtures/lever-score/." "$FX/"
  # built here, not committed: the operator's global gitignore drops any .claude-secondary/ dir.
  # Session A's transcript transplanted under a second account: the same message ids, twice.
  mkdir -p "$FX/home/.claude-secondary/projects/-Users-x-proj" "$FX/home/.claude-next"
  cp "$FX/home/.claude/projects/-Users-x-proj/aaaaaaaa-0000-4000-8000-00000000000a.jsonl" \
     "$FX/home/.claude-secondary/projects/-Users-x-proj/"
  ln -s "$FX/home/.claude/projects" "$FX/home/.claude-next/projects"
  export HOME="$FX/home" CC_LEVER_STATE_DIR="$FX/state" CC_LEVER_LOG_DIR="$FX/logs" \
         CC_LAND_LOG="$FX/land.jsonl" CC_NOW=1791072000 CC_TOKEN_LEDGER_WORKERS=1
  unset CC_LEVER_ALL CC_LEVER_D1 CC_LEVER_D2 CC_LEVER_D3 CC_LEVER_D4 CC_LEVER_EXCLUDE CC_MODEL_CONFIG \
        CC_IRS CC_WORKFLOW_SHADOW CC_IDLE_KEEPALIVE CC_SUBAGENT_LONG_BASH
  A=aaaaaaaa-0000-4000-8000-00000000000a B=bbbbbbbb-0000-4000-8000-00000000000b C=cccccccc-0000-4000-8000-00000000000c
}

ledger() { /usr/bin/python3 -I "$CLI" ledger --since 7d 2>/dev/null; }
# check <name> → that plumbing check's status, from --json
check() { /usr/bin/python3 -I "$CLI" plumbing --since 7d --json 2>/dev/null | jq -r --arg n "$1" '.checks[]|select(.check==$n)|.status'; }

@test "selftest passes: planted effect, identical output twice, plumbing fails closed" {
  run /usr/bin/python3 -I "$CLI" selftest
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"selftest: PASS"* ]] || false
  # a failed item is a line that STARTS with FAIL (a check's own name may contain the word)
  [ "$(printf '%s\n' "$output" | grep -c '^FAIL')" -eq 0 ] || false
  [ "$(printf '%s\n' "$output" | grep -c '^ok ')" -ge 15 ] || false
}

@test "ledger: a copied transcript and a symlinked root count once; subagents join their session" {
  run ledger
  [ "$status" -eq 0 ] || false
  [ "$(printf '%s\n' "$output" | grep -c '"kind":"ledger"')" -eq 3 ] || false
  a="$(printf '%s\n' "$output" | jq -c --arg s "$A" 'select(.sid==$s)|[.responses,.tokens.cache_read,.pp.mid]')"
  [ "$a" = '[2,3000,0.000114]' ] || { echo "A=$a"; false; }
  b="$(printf '%s\n' "$output" | jq -c --arg s "$B" 'select(.sid==$s)|[.responses,.contexts,.tokens.cache_write_5m,.pp.mid]')"
  [ "$b" = '[2,2,500,0.0002]' ] || { echo "B=$b"; false; }
}

@test "ledger: hook denies leave tool errors, a wall death is found, lands split by exit class" {
  run ledger
  [ "$status" -eq 0 ] || false
  a="$(printf '%s\n' "$output" | jq -c --arg s "$A" 'select(.sid==$s)|[.tool_errors,.tool_errors_hook,.lands.ok,.lands.excluded,.ptl.death]')"
  [ "$a" = '[1,1,1,1,false]' ] || { echo "A=$a"; false; }
  b="$(printf '%s\n' "$output" | jq -c --arg s "$B" 'select(.sid==$s)|.lands.failed')"
  [ "$b" = 1 ] || false
  c="$(printf '%s\n' "$output" | jq -c --arg s "$C" 'select(.sid==$s)|[.ptl.n,.ptl.death]')"
  [ "$c" = '[1,true]' ] || { echo "C=$c"; false; }
}

@test "plumbing fails closed on a missing projects root (positive control: all four present)" {
  [ "$(check 'four projects roots read')" = pass ] || false
  mv "$HOME/.claude-secondary/projects" "$HOME/.claude-secondary/projects.gone"
  [ "$(check 'four projects roots read')" = fail ] || false
  run /usr/bin/python3 -I "$CLI" plumbing --since 7d
  [ "$status" -eq 1 ] || false
  [[ "$output" == *"~/.claude-secondary/projects (missing)"* ]] || false
}

@test "plumbing fails closed on >0.1% unparseable rows (positive control: clean stores pass)" {
  [ "$(check 'parse failures <= 0.1%')" = pass ] || false
  printf '{"kind":"gap","ts":"2026-10-01T10:\n' >> "$CC_LEVER_LOG_DIR/idle-keepalive.jsonl"
  [ "$(check 'parse failures <= 0.1%')" = fail ] || false
}

@test "plumbing is never CLEAN while a check lacks data, and exits 1" {
  run /usr/bin/python3 -I "$CLI" plumbing --since 7d --json
  [ "$status" -eq 1 ] || false
  [ "$(printf '%s' "$output" | jq -r '.verdict')" = PLUMBING ] || false
  [ "$(printf '%s' "$output" | jq -r '[.checks[]|select(.status=="fail")]|length')" -eq 0 ] || false
  [ "$(printf '%s' "$output" | jq -r '.no_data')" -gt 0 ] || false
}

@test "ledger --write merges by sid: a second run replaces rows, never duplicates them" {
  /usr/bin/python3 -I "$CLI" ledger --since 7d --write >/dev/null 2>&1
  /usr/bin/python3 -I "$CLI" ledger --since 7d --write >/dev/null 2>&1
  [ "$(wc -l < "$CC_LEVER_LOG_DIR/lever-ledger.jsonl" | tr -d ' ')" -eq 3 ] || false
  [ "$(jq -r .sid "$CC_LEVER_LOG_DIR/lever-ledger.jsonl" | sort -u | wc -l | tr -d ' ')" -eq 3 ] || false
}

@test "the verbs wave S5 owns exit 3, and a bad window is a usage error" {
  for v in score aa report failures guards; do
    run /usr/bin/python3 -I "$CLI" "$v"
    [ "$status" -eq 3 ] || { echo "$v → $status"; false; }
    [[ "$output" == *"wave S5"* ]] || false
  done
  run /usr/bin/python3 -I "$CLI" ledger --since nonsense
  [ "$status" -eq 2 ] || false
}
