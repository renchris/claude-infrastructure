#!/usr/bin/env bats
# cc-husk-sweep — a pane at a bare shell over a DEAD session is resolved to (sid, account
# launcher, cwd), classified by how it died and what it left open, and resumed with the PINNED
# launcher (never the pane's own printed `claude --resume`, which uses the default account and
# cannot see another store's transcript). Every source is fixtured through the tool's seams; the
# only live thing here is the tool.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SWEEP="$REPO/bin/cc-husk-sweep"
  T="$BATS_TEST_TMPDIR"
  export CC_REGISTRY_DIR="$T/reg"; mkdir -p "$CC_REGISTRY_DIR"
  export CC_HUSK_CRASH_LOG="$T/crashes.jsonl"; : > "$CC_HUSK_CRASH_LOG"
  export CC_HUSK_LOG="$T/husk-sweep.jsonl"
  export CC_HUSK_STORES="$T/.claude-secondary:$T/.claude-tertiary"
  export CC_HUSK_PANES_JSON="$T/panes.json"
  export CC_HUSK_PS_FILE="$T/ps.txt"
  export CC_HUSK_IT2="$T/it2"
  # a fake it2 that records every send and answers a read with what was sent (echo-verify passes)
  cat > "$CC_HUSK_IT2" <<'IT2'
#!/bin/bash
log="${CC_HUSK_IT2_LOG:?}"
case "$1 $2" in
  "session send") printf 'SEND %s %s\n' "$4" "$5" >> "$log" ;;
  "session read") grep "^SEND $4 " "$log" | tail -1 | sed 's/^SEND [^ ]* //' ;;
esac
exit 0
IT2
  chmod +x "$CC_HUSK_IT2"; export CC_HUSK_IT2_LOG="$T/it2.log"; : > "$CC_HUSK_IT2_LOG"
  CWD_A="$T/wt-a"; CWD_B="$T/wt-b"; mkdir -p "$CWD_A" "$CWD_B"
  # pane 10: husk (shell 100, child zsh 101, nothing else) · pane 20: live (claude under 201)
  printf '[{"id":"10","pid":100,"cwd":"%s"},{"id":"20","pid":200,"cwd":"%s"},{"id":"30","pid":300,"cwd":"%s"}]\n' "$CWD_A" "$CWD_B" "$CWD_B" > "$CC_HUSK_PANES_JSON"
  printf '%s\n' "100 1 login -fp chris" "101 100 -zsh" "200 1 /bin/zsh" "201 200 bash cc-close-attrib" "202 201 /Users/x/.claude-260/node_modules/.bin/claude --resume z" "300 1 /bin/zsh" > "$CC_HUSK_PS_FILE"
}
slug() { printf '%s' "$1" | LC_ALL=C sed 's/[^a-zA-Z0-9]/-/g'; }
transcript() { # <store> <cwd> <sid> <last-close: yes|no|none>
  local d; d="$1/projects/$(slug "$2")"; mkdir -p "$d"
  { echo '{"type":"user"}'; [ "$4" = none ] || printf '{"type":"assistant","message":{"content":[{"type":"text","text":"... Good to close: %s — x"}]}}\n' "$4"; } > "$d/$3.jsonl"
}

@test "a pane with a claude anywhere beneath its shell is not a husk; a bare one is" {
  transcript "$T/.claude-secondary" "$CWD_A" "aaaaaaaa-0000-0000-0000-000000000001" yes
  run "$SWEEP" --json
  [ "$status" -eq 0 ]
  [[ "$output" == *'"pane":"10"'* ]] || false
  [[ "$output" != *'"pane":"20"'* ]] || false
}

@test "registry wins: sid, ACCOUNT launcher and cwd come from the surviving row" {
  printf '{"paneUUID":"10","session_id":"bbbbbbbb-0000-0000-0000-000000000002","account":"claude-tertiary","cwd":"%s","pid":999}\n' "$CWD_B" > "$CC_REGISTRY_DIR/10.json"
  transcript "$T/.claude-tertiary" "$CWD_B" "bbbbbbbb-0000-0000-0000-000000000002" no
  run "$SWEEP" --json --pane 10
  [ "$status" -eq 0 ]
  [[ "$output" == *'"sid":"bbbbbbbb-0000-0000-0000-000000000002"'* ]] || false
  [[ "$output" == *'"launcher":"claude3"'* ]] || false
  [[ "$output" == *'"source":"registry"'* ]] || false
}

@test "no registry row: the newest transcript for the pane's cwd names the session AND its store's account" {
  transcript "$T/.claude-secondary" "$CWD_A" "cccccccc-0000-0000-0000-000000000003" yes
  sleep 1
  transcript "$T/.claude-tertiary" "$CWD_A" "dddddddd-0000-0000-0000-000000000004" no
  run "$SWEEP" --json --pane 10
  [ "$status" -eq 0 ]
  [[ "$output" == *'"sid":"dddddddd-0000-0000-0000-000000000004"'* ]] || false
  [[ "$output" == *'"launcher":"claude3"'* ]] || false
  [[ "$output" == *'"source":"transcript"'* ]] || false
}

@test "verdict: 'Good to close: no' ⇒ RESUME; 'yes' on a non-git cwd ⇒ UNKNOWN (not shown done); the crash cause is carried" {
  transcript "$T/.claude-secondary" "$CWD_A" "eeeeeeee-0000-0000-0000-000000000005" no
  printf '{"sid":"eeeeeeee-0000-0000-0000-000000000005","cause":"external-sigterm"}\n' > "$CC_HUSK_CRASH_LOG"
  run "$SWEEP" --json --pane 10
  [[ "$output" == *'"verdict":"RESUME"'* ]] || false
  [[ "$output" == *'"death":"external-sigterm"'* ]] || false
  transcript "$T/.claude-secondary" "$CWD_B" "ffffffff-0000-0000-0000-000000000006" yes
  run "$SWEEP" --json --pane 30
  [[ "$output" == *'"verdict":"UNKNOWN"'* ]] || false
}

@test "verdict: uncommitted or unlanded work in the cwd forces RESUME whatever the session said" {
  git -C "$CWD_A" init -q && git -C "$CWD_A" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  echo x > "$CWD_A/dirty"
  transcript "$T/.claude-secondary" "$CWD_A" "aaaaaaaa-0000-0000-0000-000000000007" yes
  run "$SWEEP" --json --pane 10
  [[ "$output" == *'"work":"dirty"'* ]] || false
  [[ "$output" == *'"verdict":"RESUME"'* ]] || false
}

@test "--resume --yes types the PINNED launcher line, echo-verified, and records the attempt" {
  transcript "$T/.claude-tertiary" "$CWD_A" "abababab-0000-0000-0000-000000000008" no
  run "$SWEEP" --resume --yes --pane 10
  [ "$status" -ne 2 ]
  grep -q 'SEND 10 : hs-.*nocorrect CC_ACCOUNT_PINNED=1 claude3 --resume abababab-0000-0000-0000-000000000008' "$CC_HUSK_IT2_LOG"
  grep -q '"pane":"10","sid":"abababab-0000-0000-0000-000000000008","launcher":"claude3"' "$CC_HUSK_LOG"
  # never the pane's own default-account spelling
  if grep -q 'SEND 10 : hs-.* claude --resume' "$CC_HUSK_IT2_LOG"; then false; fi
}

@test "--resume skips DONE husks unless --all, and without --yes it types NOTHING" {
  git -C "$CWD_A" init -q && git -C "$CWD_A" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  git -C "$CWD_A" remote add origin "$CWD_A" && git -C "$CWD_A" fetch -q origin && git -C "$CWD_A" update-ref refs/remotes/origin/main HEAD
  transcript "$T/.claude-secondary" "$CWD_A" "acacacac-0000-0000-0000-000000000009" yes
  run "$SWEEP" --json --pane 10
  [[ "$output" == *'"verdict":"DONE"'* ]] || false
  run "$SWEEP" --resume --yes --pane 10
  [[ "$output" == *"nothing to resume"* ]] || false
  [ ! -s "$CC_HUSK_IT2_LOG" ]
  run "$SWEEP" --resume --pane 10 --all </dev/null
  [ "$status" -eq 3 ]
  [ ! -s "$CC_HUSK_IT2_LOG" ]
}
