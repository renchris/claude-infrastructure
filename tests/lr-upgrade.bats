#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031  # each @test is its own subshell; per-test exports are the intent
# cc-lr upgrade — move IDLE live sessions onto the current binary + model, in place (2026-09-22).
# Subjects: scripts/limit-recover/lr-upgrade.sh (census · launcher · drive · drain),
#           scripts/limit-recover/lr-reset-poller.sh (kind "upgrade" → queue → drainer kick),
#           bin/cc-lr upgrade (dry run · request write).
#
# Four contracts from the brief, each with a red-proof (a named mutation that turns it red):
#   A. THE SELECTION PREDICATE, including the SELF-MATCH TRAP: a `ps | grep "--parent-session-id S"`
#      lists the grep itself, which on 2026-09-22 made every session read as a lead. RED: drop the
#      argv[0]-is-claude filter in lru_has_live_teammate → case A3 goes red.
#   B. THE LAUNCHER IS PURE ASCII: printf %q turned a `—` into $'\342\200\224' and a later sed died on
#      "illegal byte sequence". RED: delete the lru_ascii_only check → case B2 goes red.
#   C. REQUEST WRITE / DRAIN: cc-lr writes kind:upgrade requests and never acts; the poller queues
#      them and kicks ONE drainer; the drainer takes the queue serially and re-judges each session.
#      RED: remove the `upgrade)` arm from the poller → C3 goes red (the request is parked as an
#      unknown kind and no drainer starts).
#   D. THE GATE BEFORE THE EXIT: capacity is probed BEFORE handoff-fire is ever invoked, so a
#      refusal types nothing. RED: move the lru_capacity call below the handoff-fire call → D1 red.
#
# Hermetic: every store is a fixture, `ps` is a snapshot FILE (LRU_PS_SNAPSHOT), the binary resolver
# and handoff-fire are stubs that record their argv, and launchctl is shimmed so no real poller is
# ever kicked from the suite.

setup() {
  command -v jq >/dev/null || skip "jq required"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LRU="$REPO/scripts/limit-recover/lr-upgrade.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export LRU_STATE="$HOME/.reso/limit-recover"; mkdir -p "$LRU_STATE"
  export LRU_REG_DIR="$BATS_TEST_TMPDIR/reg"; mkdir -p "$LRU_REG_DIR"
  export LRU_CFG_ROOT="$BATS_TEST_TMPDIR/cfgroot"; mkdir -p "$LRU_CFG_ROOT"
  export LRU_PS_SNAPSHOT="$BATS_TEST_TMPDIR/ps.txt"; : > "$LRU_PS_SNAPSHOT"
  export LRU_COMPOSER=off
  export LRU_SELF_SID=""
  export LRU_LR_LIB="$BATS_TEST_TMPDIR/absent-lr-lib.sh"
  export LRU_NOTIFY_BIN="$BATS_TEST_TMPDIR/absent-cc-notify"
  STUBS="$BATS_TEST_TMPDIR/stubs"; mkdir -p "$STUBS"
  # NEVER the real terminal: it2 is a recorder and the retype budget is zero unless a case raises it.
  printf '#!/bin/bash\necho "$*" >> %s\n' "$BATS_TEST_TMPDIR/it2.log" > "$STUBS/it2"; chmod +x "$STUBS/it2"
  export LRU_IT2_BIN="$STUBS/it2" LRU_RETYPE_MAX=0 LRU_RETYPE_GAP_S=0 LRU_ENGAGE_S=0 LRU_GAP_S=0
  NEW="/opt/cc/.claude-280/node_modules/.bin/claude"
  OLD="/opt/cc/.claude-260/node_modules/.bin/claude"
  printf '#!/bin/bash\necho %s\n' "$NEW" > "$STUBS/cc-claude-bin"; chmod +x "$STUBS/cc-claude-bin"
  export LRU_CLAUDE_BIN_CMD="$STUBS/cc-claude-bin"
  export LRU_MODEL_CONFIG="$BATS_TEST_TMPDIR/model-config.yaml"
  cat > "$LRU_MODEL_CONFIG" <<'Y'
versions:
  frontier_latest: claude-fable-5-1
  opus_latest: claude-opus-5-5     # the default
  opus_prior: claude-opus-5
roles:
  lead_default: opus
frontier_access:
  active: true
  model: claude-fable-5-1
Y
  CFG="$LRU_CFG_ROOT/.claude-t"; mkdir -p "$CFG/projects/-x"
  N=0
}

LST="Tue Sep 22 06:47:13 2026"
# sess <pane> <sid> <argv> [transcript-shape: rest|busy|none] [account]
sess() {
  local pane="$1" sid="$2" argv="$3" shape="${4:-rest}" acct="${5:-claude-t}" pid
  N=$((N + 1)); pid="${SESS_PID:-$((50000 + N))}"
  printf '{"paneUUID":"%s","pid":%d,"session_id":"%s","account":"%s","cwd":"%s","lstart":"%s"}\n' \
    "$pane" "$pid" "$sid" "$acct" "$BATS_TEST_TMPDIR" "$LST" > "$LRU_REG_DIR/$pane.json"
  printf '%d 1 %s %s\n' "$pid" "$LST" "$argv" >> "$LRU_PS_SNAPSHOT"
  local tx="$LRU_CFG_ROOT/.$acct/projects/-x/$sid.jsonl"; mkdir -p "$(dirname "$tx")"
  case "$shape" in
    rest) printf '%s\n' '{"type":"user","message":{"content":"hi"}}' \
            '{"type":"assistant","message":{"stop_reason":"end_turn","content":[{"type":"text"}]}}' > "$tx" ;;
    busy) printf '%s\n' '{"type":"assistant","message":{"stop_reason":"tool_use","content":[{"type":"tool_use"}]}}' > "$tx" ;;
    none) rm -f "$tx" ;;
  esac
  LASTPID="$pid"
}
proc() { printf '%d %d %s %s\n' "$1" "$2" "$LST" "$3" >> "$LRU_PS_SNAPSHOT"; }
disp_of() { printf '%s\n' "$output" | awk -F'\t' -v p="$1" '$1 == p { print $11 }'; }
census() { run bash "$LRU" --census --all; }

# ── A. THE SELECTION PREDICATE ────────────────────────────────────────────────────────────────────

@test "A1 an idle Opus session on the old binary is UPGRADE; one already current is CURRENT" {
  sess 401 aaaaaaaa-0000-4000-8000-000000000001 "$OLD --permission-mode auto --model claude-opus-5 --effort high"
  sess 402 aaaaaaaa-0000-4000-8000-000000000002 "$NEW --permission-mode auto --model claude-opus-5-5 --effort high"
  census
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(disp_of 401)" = upgrade ] || { echo "$output"; false; }
  [ "$(disp_of 402)" = current ] || { echo "$output"; false; }
  printf '%s\n' "$output" | awk -F'\t' '$1==401 { exit !($5=="claude-opus-5-5" && $6=="high" && $7=="auto") }'
}

@test "A2 a teammate and its lead are both EXCLUDED, each by name" {
  sess 410 bbbbbbbb-0000-4000-8000-000000000001 "$OLD --permission-mode auto --model claude-opus-5 --effort high"
  sess 411 bbbbbbbb-0000-4000-8000-000000000002 "/opt/cc/.claude-260/node_modules/@anthropic-ai/claude-code/bin/claude.exe --agent-id w@session-bbbbbbbb --agent-name w --parent-session-id bbbbbbbb-0000-4000-8000-000000000001 --model claude-opus-5"
  census
  [ "$(disp_of 410)" = lead-with-teammate ] || { echo "$output"; false; }
  [ "$(disp_of 411)" = teammate ] || { echo "$output"; false; }
}

@test "A3 [RED] SELF-MATCH TRAP: a grep/awk/shell line carrying the pattern does NOT make a lead" {
  S=cccccccc-0000-4000-8000-000000000001
  sess 420 "$S" "$OLD --permission-mode auto --model claude-opus-5 --effort high"
  # Exactly what a `ps | grep -- "--parent-session-id $S"` census sees of ITSELF, plus a brief that
  # merely MENTIONS the flag. None of them is a claude process.
  proc 61001 1 "grep -- --parent-session-id $S"
  proc 61002 1 "awk index(\$0, \"--parent-session-id $S\")"
  proc 61003 1 "/bin/zsh -c echo --parent-session-id $S"
  census
  [ "$(disp_of 420)" = upgrade ] || { echo "the census convicted its own population: $output"; false; }
}

@test "A4 a session mid-turn is EXCLUDED; one with no transcript on its account is EXCLUDED" {
  sess 430 dddddddd-0000-4000-8000-000000000001 "$OLD --model claude-opus-5 --effort high" busy
  sess 431 dddddddd-0000-4000-8000-000000000002 "$OLD --model claude-opus-5 --effort high" none
  census
  [ "$(disp_of 430)" = mid-turn ] || { echo "$output"; false; }
  [ "$(disp_of 431)" = no-transcript ] || { echo "$output"; false; }
}

@test "A5 background job: real work EXCLUDES; a cc-await-ping watcher alone does not (unless strict)" {
  sess 440 eeeeeeee-0000-4000-8000-000000000001 "$OLD --model claude-opus-5 --effort high"; W="$LASTPID"
  proc 62001 "$W" "/bin/zsh -c source /h/.claude-t/shell-snapshots/snapshot-zsh-1.sh && eval 'bats tests/x.bats'"
  proc 62002 62001 "bats tests/x.bats"
  sess 441 eeeeeeee-0000-4000-8000-000000000002 "$OLD --model claude-opus-5 --effort high"; A="$LASTPID"
  proc 62011 "$A" "/bin/zsh -c source /h/.claude-t/shell-snapshots/snapshot-zsh-2.sh && eval '~/.claude/bin/cc-await-ping 441 --timeout 14400 | tail -2'"
  proc 62012 62011 "/bin/bash /h/.claude/bin/cc-await-ping 441 --timeout 14400"
  proc 62013 62011 "tail -2"
  census
  [ "$(disp_of 440)" = background-job ] || { echo "$output"; false; }
  [ "$(disp_of 441)" = upgrade ] || { echo "a parked wake watcher blocked the upgrade: $output"; false; }
  LRU_WATCHER_IS_JOB=1 census
  [ "$(disp_of 441)" = background-job ] || { echo "the strict kill switch did not restore the brief's letter: $output"; false; }
}

@test "A6 two live rows for one sid are both DUPLICATE; the running session itself is SELF" {
  sess 450 ffffffff-0000-4000-8000-000000000001 "$OLD --model claude-opus-5 --effort high"
  sess 451 ffffffff-0000-4000-8000-000000000001 "$OLD --model claude-opus-5 --effort high"
  sess 452 ffffffff-0000-4000-8000-000000000003 "$OLD --model claude-opus-5 --effort high"
  LRU_SELF_SID=ffffffff-0000-4000-8000-000000000003 census
  [ "$(disp_of 450)" = duplicate ] && [ "$(disp_of 451)" = duplicate ] || { echo "$output"; false; }
  [ "$(disp_of 452)" = self ] || { echo "$output"; false; }
}

@test "A7 Fable stays Fable: a binary-only move targets frontier_access.model" {
  sess 460 12121212-0000-4000-8000-000000000001 "$OLD --permission-mode auto --model claude-fable-5-1 --effort xhigh"
  sess 461 12121212-0000-4000-8000-000000000002 "$NEW --permission-mode auto --model claude-fable-5-1 --effort xhigh"
  census
  [ "$(disp_of 460)" = upgrade ] || { echo "$output"; false; }
  printf '%s\n' "$output" | awk -F'\t' '$1==460 { exit !($5=="claude-fable-5-1" && $6=="xhigh") }' || { echo "$output"; false; }
  [ "$(disp_of 461)" = current ] || { echo "$output"; false; }
}

@test "A8 argv: last WELL-FORMED flag wins; prompt text that mentions a flag is not a flag" {
  sess 470 13131313-0000-4000-8000-000000000001 "$OLD --model claude-opus-5 --effort high --effort max do --effort (set-teammate-effort.sh) and --model is text"
  census
  printf '%s\n' "$output" | awk -F'\t' '$1==470 { exit !($4=="claude-opus-5" && $6=="max") }' || { echo "$output"; false; }
}

@test "A9 a reused pid (registry lstart ≠ process lstart) is STALE-ROW, never a live target" {
  sess 480 14141414-0000-4000-8000-000000000001 "$OLD --model claude-opus-5 --effort high"
  jq --arg l "Mon Sep 21 01:00:00 2026" '.lstart = $l' "$LRU_REG_DIR/480.json" > "$BATS_TEST_TMPDIR/r" && mv "$BATS_TEST_TMPDIR/r" "$LRU_REG_DIR/480.json"
  census
  [ "$(disp_of 480)" = stale-row ] || { echo "$output"; false; }
}

@test "A10 a multi-line argv's continuation line that starts with a number is not a process" {
  sess 490 15151515-0000-4000-8000-000000000001 "$OLD --model claude-opus-5 --effort high"
  # a continuation line whose first word is 490's pid-shaped text, and a second fake row claiming
  # a teammate for it — neither is a well-formed process line.
  printf '%s\n' "50001 is the number I meant --parent-session-id 15151515-0000-4000-8000-000000000001" >> "$LRU_PS_SNAPSHOT"
  census
  [ "$(disp_of 490)" = upgrade ] || { echo "$output"; false; }
}

# ── B. THE LAUNCHER IS PURE ASCII ─────────────────────────────────────────────────────────────────

# shellcheck disable=SC1090  # the subject, resolved from the repo at runtime
mint() { ( . "$LRU"; lru_mint_launcher "$@" ); }

@test "B1 the launcher resumes the SAME uuid on the SAME account via lr-fire-resume, pure ASCII" {
  run mint "$BATS_TEST_TMPDIR/run1" "$CFG" "$BATS_TEST_TMPDIR" 16161616-0000-4000-8000-000000000001 claude-opus-5-5 high auto /tmp/tok
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  L="$output"; [ -f "$L" ]
  ! LC_ALL=C grep -q '[^[:print:][:space:]]' "$L" || { echo "non-ASCII byte in $L"; false; }
  grep -q 'lr-fire-resume.sh' "$L" && grep -q -- '--model claude-opus-5-5 --effort high --permission-mode auto' "$L"
  grep -q '16161616-0000-4000-8000-000000000001' "$L"
  grep -q '^export LR_ADMIT_TOKEN=/tmp/tok$' "$L"
  grep -q '^export LR_SUBMIT_TOKEN=run:16161616:upgrade:' "$L"
  bash -n "$L"
}

@test "B2 [RED] a non-ASCII byte anywhere in the launcher REFUSES it (nothing to type)" {
  run mint "$BATS_TEST_TMPDIR/run2" "$CFG" "$BATS_TEST_TMPDIR/wt—dash" 17171717-0000-4000-8000-000000000001 claude-opus-5-5 high auto ""
  [ "$status" -ne 0 ] || { echo "a non-ASCII launcher was minted: $output"; false; }
  [ ! -f "$BATS_TEST_TMPDIR/run2/launch.sh" ] || { echo "the refused launcher was left where a typist could find it"; false; }
  [[ "$output" == *"not pure ASCII"* ]] || { echo "$output"; false; }
}

# ── C. REQUEST WRITE / QUEUE / DRAIN ──────────────────────────────────────────────────────────────

cc_lr_env() {
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "%s"\n' "$BATS_TEST_TMPDIR/launchctl.log" > "$STUBS/launchctl"
  chmod +x "$STUBS/launchctl"
  export PATH="$STUBS:$PATH"
  export LR_STATE_DIR="$LRU_STATE" CC_LR_UPGRADE_BIN="$LRU" CC_PANE_ID=999
}

@test "C1 cc-lr upgrade --dry-run prints one row per live session and writes NOTHING" {
  cc_lr_env
  sess 501 18181818-0000-4000-8000-000000000001 "$OLD --model claude-opus-5 --effort high"
  sess 502 18181818-0000-4000-8000-000000000002 "$NEW --model claude-opus-5-5 --effort high"
  run bash "$REPO/bin/cc-lr" upgrade --all --dry-run
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"501   18181818  .claude-260"*"upgrade"* ]] || { echo "$output"; false; }
  [[ "$output" == *"502   18181818  .claude-280"*"current"* ]] || { echo "$output"; false; }
  [[ "$output" == *"DRY RUN"* ]]
  [ -z "$(ls -A "$LRU_STATE/requests" 2>/dev/null)" ] || { echo "a dry run wrote a request"; false; }
  [ ! -s "$BATS_TEST_TMPDIR/launchctl.log" ] || { echo "a dry run kicked the poller"; false; }
}

@test "C2 cc-lr upgrade writes ONE kind:upgrade request per candidate, names every skip, kicks without -k" {
  cc_lr_env
  sess 511 19191919-0000-4000-8000-000000000001 "$OLD --model claude-opus-5 --effort high"
  sess 512 19191919-0000-4000-8000-000000000002 "$OLD --model claude-opus-5 --effort high" busy
  sess 513 19191919-0000-4000-8000-000000000003 "$NEW --model claude-opus-5-5 --effort high"
  run bash "$REPO/bin/cc-lr" upgrade --all --no-wait
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  r="$LRU_STATE/requests/cc-lr-upgrade-19191919-0000-4000-8000-000000000001.json"
  [ -f "$r" ] || { ls -la "$LRU_STATE/requests"; echo "$output"; false; }
  [ "$(jq -r .kind "$r")" = upgrade ] && [ "$(jq -r .source_pane "$r")" = 511 ] && [ "$(jq -r .requested_by "$r")" = 999 ]
  [ -n "$(jq -r '.req_id // empty' "$r")" ]
  nreq=0; for q in "$LRU_STATE"/requests/*.json; do [ -f "$q" ] && nreq=$((nreq + 1)); done
  [ "$nreq" -eq 1 ] || { ls "$LRU_STATE/requests"; false; }
  [[ "$output" == *"· 512   19191919  skipped mid-turn"* ]] || { echo "$output"; false; }
  [[ "$output" == *"pending"* ]]
  grep -q '^kickstart gui/' "$BATS_TEST_TMPDIR/launchctl.log"
  ! grep -q -- '-k' "$BATS_TEST_TMPDIR/launchctl.log" || { echo "the poller was kicked with -k"; false; }
}

@test "C2b a subject is REQUIRED: a bare 'cc-lr upgrade' relaunches nothing" {
  cc_lr_env
  run bash "$REPO/bin/cc-lr" upgrade
  [ "$status" -eq 3 ]
}

poller_env() {
  POLLER="$REPO/scripts/limit-recover/lr-reset-poller.sh"
  export LR_POLLER_NO_CENSUS=1
  export CC_REGISTRY_DIR="$BATS_TEST_TMPDIR/preg"; mkdir -p "$CC_REGISTRY_DIR"
  export LR_POLLER_LAUNCH_DIR="$BATS_TEST_TMPDIR/launchers"; mkdir -p "$LR_POLLER_LAUNCH_DIR"
  export CC_KITTY_SOCKET_BIN="$BATS_TEST_TMPDIR/no-kitty-socket"
  unset KITTY_WINDOW_ID CC_TERM_KITTY_TO
  printf '#!/bin/bash\nexit 1\n' > "$STUBS/osascript"; chmod +x "$STUBS/osascript"
  mkdir -p "$HOME/bin"; printf '#!/bin/bash\necho %s\n' "'{\"rows\":[]}'" > "$HOME/bin/claude-accounts"; chmod +x "$HOME/bin/claude-accounts"
  export PATH="$STUBS:$PATH"
  export LR_FLEET_BIN="$STUBS/lr-fleet"; printf '#!/bin/bash\necho "$*" >> %s\n' "$BATS_TEST_TMPDIR/fleet.log" > "$LR_FLEET_BIN"; chmod +x "$LR_FLEET_BIN"
  export LR_UPGRADE_BIN="$STUBS/lr-upgrade"
  printf '#!/bin/bash\necho "$*" >> %s\n' "$BATS_TEST_TMPDIR/drain.log" > "$LR_UPGRADE_BIN"; chmod +x "$LR_UPGRADE_BIN"
  PSTATE="$HOME/.reso/limit-recover"; mkdir -p "$PSTATE/requests" "$PSTATE/parked" "$PSTATE/resumed"
}
await_file() { local i=0; while [ ! -s "$1" ] && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i + 1)); done; [ -s "$1" ]; }

@test "C3 [RED] the poller QUEUES a kind:upgrade request and kicks ONE drainer — it never drives it inline" {
  poller_env
  printf '{"kind":"upgrade","sid":"20202020-0000-4000-8000-000000000001","source_pane":"520","requested_by":"999"}\n' \
    > "$PSTATE/requests/cc-lr-upgrade-20202020.json"
  LR_POLLER_AUTOFIRE=1 run bash "$POLLER" --once
  [ -f "$PSTATE/upgrade-queue/cc-lr-upgrade-20202020.json" ] || { cat "$PSTATE/poller.log"; false; }
  [ ! -e "$PSTATE/requests/cc-lr-upgrade-20202020.json" ]
  [ ! -s "$BATS_TEST_TMPDIR/fleet.log" ] || { echo "an upgrade was driven as a recovery"; false; }
  grep -q 'UPGRADE-QUEUED 20202020' "$PSTATE/poller.log"
  await_file "$BATS_TEST_TMPDIR/drain.log" || { cat "$PSTATE/poller.log"; false; }
  grep -qx -- '--drain' "$BATS_TEST_TMPDIR/drain.log"
}

@test "C4 the poller does not start a second drainer while one holds the lock" {
  poller_env
  mkdir -p "$PSTATE/upgrade-queue" "$PSTATE/upgrade-drain.lock"; echo "$$" > "$PSTATE/upgrade-drain.lock/pid"
  printf '{"kind":"upgrade","sid":"21212121-0000-4000-8000-000000000001","source_pane":"521"}\n' > "$PSTATE/upgrade-queue/q.json"
  LR_POLLER_AUTOFIRE=1 run bash "$POLLER" --once
  grep -q "UPGRADE-DRAIN already running (pid $$)" "$PSTATE/poller.log" || { cat "$PSTATE/poller.log"; false; }
  sleep 0.5; [ ! -s "$BATS_TEST_TMPDIR/drain.log" ]
}

@test "C5 the drainer takes the queue serially, re-judges each session, and empties the queue" {
  export LRU_HF_BIN="$STUBS/hf"; printf '#!/bin/bash\necho "$*" >> %s\nexit 1\n' "$BATS_TEST_TMPDIR/hf.log" > "$LRU_HF_BIN"; chmod +x "$LRU_HF_BIN"
  sess 531 22222222-0000-4000-8000-000000000001 "$OLD --model claude-opus-5 --effort high" busy
  mkdir -p "$LRU_STATE/upgrade-queue"
  printf '{"kind":"upgrade","sid":"22222222-0000-4000-8000-000000000001","source_pane":"531","req_id":"r1"}\n' > "$LRU_STATE/upgrade-queue/a.json"
  printf '{"kind":"upgrade","sid":"22222222-0000-4000-8000-00000000dead","source_pane":"532","req_id":"r2"}\n' > "$LRU_STATE/upgrade-queue/b.json"
  run bash "$LRU" --drain
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  # 531 went busy AFTER the request was written: re-judged at execution time, skipped, untouched
  [ "$(jq -r .verdict "$LRU_STATE/results/upgrade-22222222-0000-4000-8000-000000000001.json")" = skipped ]
  [ "$(jq -r .reason "$LRU_STATE/results/upgrade-22222222-0000-4000-8000-000000000001.json")" = mid-turn ]
  [ "$(jq -r .req_id "$LRU_STATE/results/upgrade-22222222-0000-4000-8000-000000000001.json")" = r1 ]
  [[ "$(jq -r .reason "$LRU_STATE/results/upgrade-22222222-0000-4000-8000-00000000dead.json")" == "not live"* ]]
  [ ! -s "$BATS_TEST_TMPDIR/hf.log" ] || { echo "handoff-fire was invoked for a session that failed re-judgement"; false; }
  [ -z "$(ls -A "$LRU_STATE/upgrade-queue")" ] && [ -f "$LRU_STATE/claimed/a.json" ] && [ ! -e "$LRU_STATE/upgrade-drain.lock" ]
}

# ── D. THE GATE BEFORE THE EXIT ───────────────────────────────────────────────────────────────────

gate_env() { # $1 = probe rc (0 admit / 9 refuse)
  export LRU_CA_LIB="$BATS_TEST_TMPDIR/ca.sh"
  cat > "$LRU_CA_LIB" <<EOF
cc_capacity_probe() { echo "probe \$*" >> "$BATS_TEST_TMPDIR/order.log"; return $1; }
cc_capacity_admit_reason() { echo "load 9.9/core over 1.5"; }
cc_capacity_token_mint() { echo "$BATS_TEST_TMPDIR/tok-\$1"; }
EOF
  export LRU_HF_BIN="$STUBS/hf"
  printf '#!/bin/bash\necho "hf $*" >> %s\nexit 1\n' "$BATS_TEST_TMPDIR/order.log" > "$LRU_HF_BIN"; chmod +x "$LRU_HF_BIN"
}

@test "D1 [RED] a capacity REFUSAL is decided before handoff-fire runs: nothing is typed" {
  gate_env 9
  sess 541 23232323-0000-4000-8000-000000000001 "$OLD --model claude-opus-5 --effort high"
  run bash "$LRU" --drive 23232323-0000-4000-8000-000000000001 541
  [ "$status" -eq 3 ] || { echo "$output"; false; }
  r="$LRU_STATE/results/upgrade-23232323-0000-4000-8000-000000000001.json"
  [ "$(jq -r .verdict "$r")" = skipped ] && [[ "$(jq -r .reason "$r")" == "capacity: load 9.9/core"* ]] || { cat "$r"; false; }
  grep -q '^probe ' "$BATS_TEST_TMPDIR/order.log"
  ! grep -q '^hf ' "$BATS_TEST_TMPDIR/order.log" || { echo "handoff-fire ran despite the refusal"; cat "$BATS_TEST_TMPDIR/order.log"; false; }
}

teardown() { [ -n "${LIVE_PID:-}" ] && kill "$LIVE_PID" 2>/dev/null; true; }

@test "D2 an ADMITTED session: probe first, then the same-account recycle with the token in its launcher" {
  gate_env 0
  # A REAL live process stands in for the session, so "the old process is still alive" is a
  # measured fact and the drive stops at the pre-exit arm — it never reaches the retype path.
  sleep 300 & LIVE_PID=$!
  SESS_PID="$LIVE_PID" sess 542 24242424-0000-4000-8000-000000000001 "$OLD --permission-mode plan --model claude-opus-5 --effort xhigh"
  run bash "$LRU" --drive 24242424-0000-4000-8000-000000000001 542
  [ "$(head -1 "$BATS_TEST_TMPDIR/order.log" | cut -c1-5)" = "probe" ] || { cat "$BATS_TEST_TMPDIR/order.log"; false; }
  h="$(grep '^hf ' "$BATS_TEST_TMPDIR/order.log")"
  [[ "$h" == *"--recycle --same-account --source-pane 542 --source-session 24242424-0000-4000-8000-000000000001"* ]] || { echo "$h"; false; }
  [[ "$h" == *"--resume-cfg $CFG"* && "$h" == *"--await"* ]] || { echo "$h"; false; }
  L="$(printf '%s' "$h" | sed -n 's/.*--resume-launcher \([^ ]*\).*/\1/p')"
  grep -q "^export LR_ADMIT_TOKEN=$BATS_TEST_TMPDIR/tok-24242424" "$L"
  grep -q -- '--model claude-opus-5-5 --effort xhigh --permission-mode plan' "$L"
  # the old process is still alive (the stub typed nothing), so this is a pre-exit refusal: untouched
  [ "$(jq -r .verdict "$LRU_STATE/results/upgrade-24242424-0000-4000-8000-000000000001.json")" = skipped ]
}
