#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2016  # stubs are written verbatim; each @test is its own subshell; per-test exports are the intent
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
  # The real gates are never this suite's subject (case D stubs capacity-admit via LRU_CA_LIB), and
  # the poller cases reach code that could read live load — pin both off, one export per term.
  export CC_FIRE_CAPACITY_GATE=off
  export CC_ADMIT_GATE=off
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
  # The census asks handoff-fire's own subagent predicate (--probe-live-subagents); here it is a stub
  # whose answer a case sets through $BATS_TEST_TMPDIR/sa-count, so no case reaches the real script
  # and no hf-stub log (C5, D1) sees a census probe.
  export LRU_SA_PROBE="$STUBS/sa-probe"
  printf '#!/bin/bash
echo "$*" >> %s/sa-probe.log
echo "live_subagents: $(cat %s/sa-count 2>/dev/null || echo 0)"
' "$BATS_TEST_TMPDIR" "$BATS_TEST_TMPDIR" > "$LRU_SA_PROBE"; chmod +x "$LRU_SA_PROBE"
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

@test "A2 LRU_TEAM_PROC=off restores the blanket exclusions: a teammate and its lead, each by name" {
  sess 410 bbbbbbbb-0000-4000-8000-000000000001 "$OLD --permission-mode auto --model claude-opus-5 --effort high"
  sess 411 bbbbbbbb-0000-4000-8000-000000000002 "/opt/cc/.claude-260/node_modules/@anthropic-ai/claude-code/bin/claude.exe --agent-id w@session-bbbbbbbb --agent-name w --parent-session-id bbbbbbbb-0000-4000-8000-000000000001 --model claude-opus-5"
  LRU_TEAM_PROC=off census
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
  [ "$(disp_of 450)" = duplicate ] || { echo "$output"; false; }
  [ "$(disp_of 451)" = duplicate ] || { echo "$output"; false; }
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
  grep -q 'lr-fire-resume.sh' "$L" && grep -q -- '--model claude-opus-5-5 --effort high --permission-mode auto' "$L" || false
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

@test "B3 the ASCII refusal holds under LC_ALL=C, where printf %q would hide the byte as an escape" {
  LC_ALL=C run mint "$BATS_TEST_TMPDIR/run3" "$CFG" "$BATS_TEST_TMPDIR/wt—dash" 17171717-0000-4000-8000-000000000002 claude-opus-5-5 high auto ""
  [ "$status" -ne 0 ] || { echo "minted under LC_ALL=C: $output"; cat "$BATS_TEST_TMPDIR/run3/launch.sh" 2>/dev/null; false; }
  [ ! -f "$BATS_TEST_TMPDIR/run3/launch.sh" ] || false
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
  [[ "$output" == *"DRY RUN"* ]] || false
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
  [ "$(jq -r .kind "$r")" = upgrade ] && [ "$(jq -r .source_pane "$r")" = 511 ] && [ "$(jq -r .requested_by "$r")" = 999 ] || false
  [ -n "$(jq -r '.req_id // empty' "$r")" ]
  nreq=0; for q in "$LRU_STATE"/requests/*.json; do [ -f "$q" ] && nreq=$((nreq + 1)); done
  [ "$nreq" -eq 1 ] || { ls "$LRU_STATE/requests"; false; }
  [[ "$output" == *"· 512   19191919  skipped mid-turn"* ]] || { echo "$output"; false; }
  [[ "$output" == *"pending"* ]] || false
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
  [[ "$(jq -r .reason "$LRU_STATE/results/upgrade-22222222-0000-4000-8000-00000000dead.json")" == "not live"* ]] || false
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
  [ "$(jq -r .verdict "$r")" = skipped ] || { cat "$r"; false; }
  [[ "$(jq -r .reason "$r")" == "capacity: load 9.9/core"* ]] || { cat "$r"; false; }
  grep -q '^probe ' "$BATS_TEST_TMPDIR/order.log"
  ! grep -q '^hf ' "$BATS_TEST_TMPDIR/order.log" || { echo "handoff-fire ran despite the refusal"; cat "$BATS_TEST_TMPDIR/order.log"; false; }
}

teardown() { if [ -n "${LIVE_PID:-}" ]; then kill "$LIVE_PID" 2>/dev/null || true; fi; }

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

# ── E. THE VERDICT IS THE PROCESS; THE CONFIRMATION TURN IS A SEPARATE, WEAKER FACT ────────────────
# Field run 2026-09-22 (panes 480, 495): both came up correctly on 2.1.280, and lr-fire-resume's
# prompt injection recorded FAILED:submit in both (~25-column panes). The first cut of this driver
# reported them "failed" — naming a completed move a failure. RED: restore the old tail (a
# `failed` result when no assistant turn arrives) → E1 goes red.

@test "E1 [RED] relaunched on the target with no confirmation turn is UPGRADED, flagged UNCONFIRMED" {
  gate_env 0
  export LRU_LR_LIB="$REPO/scripts/limit-recover/lr-lib.sh"
  SID=25252525-0000-4000-8000-000000000001
  sleep 300 & LIVE_PID=$!
  SESS_PID="$LIVE_PID" sess 551 "$SID" "$OLD --permission-mode auto --model claude-opus-5 --effort high"
  # handoff-fire, as the field saw it: the old session exits, a NEW claude comes up on the target
  # binary + model resuming the same uuid, and lr-fire-resume records that its prompt never landed.
  cat > "$LRU_HF_BIN" <<STUB
#!/bin/bash
L=""; while [ \$# -gt 0 ]; do [ "\$1" = --resume-launcher ] && L="\$2"; shift; done
kill $LIVE_PID
( exec -a "$NEW" perl -e 'sleep 300' -- --permission-mode auto --model claude-opus-5-5 --effort high --resume $SID ) &
echo \$! > "$BATS_TEST_TMPDIR/new.pid"
printf '{"state":"FAILED:submit","detail":"no record of the prompt in the transcript within 180s"}\n' >> "\$(dirname "\$L")/events.jsonl"
sleep 1; exit 1
STUB
  chmod +x "$LRU_HF_BIN"
  run bash "$LRU" --drive "$SID" 551
  NEWPID="$(cat "$BATS_TEST_TMPDIR/new.pid" 2>/dev/null)"; kill "$NEWPID" 2>/dev/null || true
  r="$LRU_STATE/results/upgrade-$SID.json"
  [ "$(jq -r .verdict "$r")" = upgraded ] || { cat "$r"; echo "$output"; false; }
  [[ "$(jq -r .reason "$r")" == *"now claude-opus-5-5 on .claude-280"*"UNCONFIRMED (lr-fire-resume: FAILED:submit)"*"press Enter in pane 551"* ]] || { cat "$r"; false; }
  [ ! -s "$BATS_TEST_TMPDIR/it2.log" ] || { echo "retyped over a session that was already up"; false; }
}

# ── F. ZERO-HUMAN (operator ruling 2026-09-22): the rail's own junk, and the auto-trigger ──────────

tui_stub() { # composer contents come from $BATS_TEST_TMPDIR/composer-<pane>
  export LRU_COMPOSER=on LRU_TUI_LIB="$BATS_TEST_TMPDIR/tui.sh"
  printf 'cc_tui_composer() { cat "%s/composer-$1" 2>/dev/null; return 0; }\n' "$BATS_TEST_TMPDIR" > "$LRU_TUI_LIB"
}

@test "F1 [RED] a composer holding the RAIL's own unsent prompt is not an operator draft; anything else still is" {
  tui_stub
  sess 561 26262626-0000-4000-8000-000000000001 "$OLD --model claude-opus-5 --effort high"
  sess 562 26262626-0000-4000-8000-000000000002 "$OLD --model claude-opus-5 --effort high"
  sess 563 26262626-0000-4000-8000-000000000003 "$OLD --model claude-opus-5 --effort high"
  printf 'OPUS55-UPGRADE(operatorrequest):relaunchTHISsessioninplace' > "$BATS_TEST_TMPDIR/composer-561"
  printf 'pleasefixthelogin' > "$BATS_TEST_TMPDIR/composer-562"
  printf 'notesOPUS55-UPGRADE(' > "$BATS_TEST_TMPDIR/composer-563"      # the marker must be a PREFIX
  census
  [ "$(disp_of 561)" = upgrade ] || { echo "$output"; false; }
  [ "$(disp_of 562)" = composer-occupied ] || { echo "$output"; false; }
  [ "$(disp_of 563)" = composer-occupied ] || { echo "$output"; false; }
  LRU_SCRUB_RAIL_JUNK=off census
  [ "$(disp_of 561)" = composer-occupied ] || { echo "the kill switch did not restore the strict read: $output"; false; }
}

@test "F2 the drive files the residue RECEIPT handoff-fire's composer gate scrubs by, then recycles" {
  gate_env 0; tui_stub
  export CC_COMPOSER_RESIDUE_DIR="$BATS_TEST_TMPDIR/residue"
  sleep 300 & LIVE_PID=$!
  SESS_PID="$LIVE_PID" sess 564 27272727-0000-4000-8000-000000000001 "$OLD --model claude-opus-5 --effort high"
  printf 'In-placeupgrade:thissessionwasrelaunchedbycc-lrupgradeonthecurrent' > "$BATS_TEST_TMPDIR/composer-564"
  run bash "$LRU" --drive 27272727-0000-4000-8000-000000000001 564
  [ -f "$CC_COMPOSER_RESIDUE_DIR/564" ] || { echo "no receipt: $output"; false; }
  [ "$(cut -f2- "$CC_COMPOSER_RESIDUE_DIR/564")" = "$(cat "$BATS_TEST_TMPDIR/composer-564")" ] || { cat "$CC_COMPOSER_RESIDUE_DIR/564"; false; }
  grep -q '^hf .*--same-account' "$BATS_TEST_TMPDIR/order.log" || { cat "$BATS_TEST_TMPDIR/order.log"; false; }
}

@test "F3 auto-enqueue queues each UPGRADE row once — never beside a busy queue, never when switched off" {
  sess 571 28282828-0000-4000-8000-000000000001 "$OLD --model claude-opus-5 --effort high"
  sess 572 28282828-0000-4000-8000-000000000002 "$OLD --model claude-opus-5 --effort high" busy
  touch "$LRU_STATE/upgrade-auto.off"
  run bash "$LRU" --auto-enqueue
  [ -z "$(ls -A "$LRU_STATE/upgrade-queue" 2>/dev/null)" ] || { echo "queued while switched off"; false; }
  rm -f "$LRU_STATE/upgrade-auto.off"
  run bash "$LRU" --auto-enqueue
  q="$LRU_STATE/upgrade-queue/auto-upgrade-28282828-0000-4000-8000-000000000001.json"
  [ -f "$q" ] || { ls -la "$LRU_STATE/upgrade-queue"; echo "$output"; false; }
  [ "$(jq -r .requested_by "$q")" = poller-auto ] || false
  [ ! -e "$LRU_STATE/upgrade-queue/auto-upgrade-28282828-0000-4000-8000-000000000002.json" ] || { echo "a mid-turn session was queued"; false; }
  rm -f "$q"; mkdir -p "$LRU_STATE/upgrade-queue"; echo '{}' > "$LRU_STATE/upgrade-queue/pending.json"
  run bash "$LRU" --auto-enqueue
  [ ! -e "$q" ] || { echo "queued beside a non-empty queue"; false; }
}

@test "F4 [RED] the poller's tick runs the auto-trigger and kicks the drainer; LR_UPGRADE_AUTO=off stops it" {
  poller_env
  export LR_POLLER_NO_CENSUS=0
  printf '#!/bin/bash\necho "$*" >> %s\ncase "$1" in --auto-enqueue) mkdir -p %s/upgrade-queue; echo "{}" > %s/upgrade-queue/auto-x.json; printf "570\\t29292929-0000\\n";; esac\n' \
    "$BATS_TEST_TMPDIR/drain.log" "$PSTATE" "$PSTATE" > "$LR_UPGRADE_BIN"
  LR_UPGRADE_AUTO=off LR_POLLER_AUTOFIRE=1 run bash "$POLLER" --once
  ! grep -q -- '--auto-enqueue' "$BATS_TEST_TMPDIR/drain.log" 2>/dev/null || { echo "ran with the switch off"; false; }
  LR_POLLER_AUTOFIRE=1 run bash "$POLLER" --once
  grep -q -- '--auto-enqueue' "$BATS_TEST_TMPDIR/drain.log" || { cat "$PSTATE/poller.log"; false; }
  grep -q 'UPGRADE-AUTO queued: 570(29292929)' "$PSTATE/poller.log" || { cat "$PSTATE/poller.log"; false; }
  await_file "$BATS_TEST_TMPDIR/drain.log"; i=0; while ! grep -qx -- '--drain' "$BATS_TEST_TMPDIR/drain.log" && [ $i -lt 50 ]; do sleep 0.1; i=$((i+1)); done
  grep -qx -- '--drain' "$BATS_TEST_TMPDIR/drain.log" || { cat "$PSTATE/poller.log"; false; }
}

# ── G. THE PER-SESSION TARGET PIN (2026-09-23) ────────────────────────────────────────────────────
# A7 pins "Fable keeps Fable" as the DEFAULT. The operator ruled one live Fable session (pane 480)
# should move to Opus 5.5, and without a per-session override the census called it `current`
# forever. These cases pin the override and every one of its bounds.

@test "G1 [RED] a pin moves a current Fable session to opus_latest; auto-enqueue then queues it" {
  S=29292929-0000-4000-8000-000000000001
  sess 580 "$S" "$NEW --permission-mode auto --model claude-fable-5-1 --effort xhigh"
  census; [ "$(disp_of 580)" = current ] || { echo "$output"; false; }
  run bash "$LRU" --pin-target "$S" opus
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  census
  [ "$(disp_of 580)" = upgrade ] || { echo "$output"; false; }
  printf '%s\n' "$output" | awk -F'\t' '$1==580 { exit !($5=="claude-opus-5-5" && $6=="xhigh") }' || { echo "$output"; false; }
  run bash "$LRU" --auto-enqueue
  [ -f "$LRU_STATE/upgrade-queue/auto-upgrade-$S.json" ] || { echo "$output"; ls -la "$LRU_STATE/upgrade-queue"; false; }
}

@test "G2 a pin can only name an SSOT target — an arbitrary id is REFUSED and leaves no pin" {
  S=29292929-0000-4000-8000-000000000002
  run bash "$LRU" --pin-target "$S" claude-sonnet-5
  [ "$status" -eq 2 ] || { echo "$output"; false; }
  [ ! -e "$LRU_STATE/upgrade-target/$S" ] || { echo "a refused pin was left on disk"; false; }
  run bash "$LRU" --pin-target "not-a-sid;rm" opus
  [ "$status" -eq 3 ] || { echo "$output"; false; }
}

@test "G3 an EXPIRED pin is ignored, and 'clear' removes a live one — both fall back to Fable-keeps-Fable" {
  S=29292929-0000-4000-8000-000000000003
  sess 582 "$S" "$NEW --permission-mode auto --model claude-fable-5-1 --effort xhigh"
  run bash "$LRU" --pin-target "$S" opus; [ "$status" -eq 0 ] || { echo "$output"; false; }
  touch -t 202001010000 "$LRU_STATE/upgrade-target/$S"
  census; [ "$(disp_of 582)" = current ] || { echo "a stale pin still steered: $output"; false; }
  run bash "$LRU" --pin-target "$S" opus
  run bash "$LRU" --pin-target "$S" clear; [ "$status" -eq 0 ] || { echo "$output"; false; }
  census; [ "$(disp_of 582)" = current ] || { echo "$output"; false; }
}

@test "G4 a pin is per SID: an unpinned Fable session beside a pinned one keeps Fable" {
  sess 583 29292929-0000-4000-8000-000000000004 "$NEW --permission-mode auto --model claude-fable-5-1 --effort xhigh"
  sess 584 29292929-0000-4000-8000-000000000005 "$NEW --permission-mode auto --model claude-fable-5-1 --effort xhigh"
  run bash "$LRU" --pin-target 29292929-0000-4000-8000-000000000004 opus
  census
  [ "$(disp_of 583)" = upgrade ] || { echo "$output"; false; }
  [ "$(disp_of 584)" = current ] || { echo "$output"; false; }
}

# ── H. A HARNESS NOTIFICATION IS NOT A TURN (2026-09-23) ───────────────────────────────────────────
# Pane 480 was resumed onto 2.1.280 with a lost background task; the harness appended a
# <task-notification> user record and no turn followed. Every at-rest check read it as mid-turn.
@test "H1 [RED] a stale unanswered <task-notification> is at rest — the session is UPGRADE, not mid-turn" {
  S=30303030-0000-4000-8000-000000000001
  sess 590 "$S" "$OLD --permission-mode auto --model claude-opus-5 --effort high"
  printf '%s\n' '{"type":"user","message":{"content":"<task-notification>\n<status>stopped</status>\n</task-notification>"},"timestamp":"2026-09-22T10:00:05Z"}' \
    >> "$LRU_CFG_ROOT/.claude-t/projects/-x/$S.jsonl"
  census
  [ "$(disp_of 590)" = upgrade ] || { echo "$output"; false; }
}

@test "H2 a FRESH notification, or a stale typed prompt, stays mid-turn" {
  S=30303030-0000-4000-8000-000000000002; T=30303030-0000-4000-8000-000000000003
  sess 591 "$S" "$OLD --model claude-opus-5 --effort high"
  printf '{"type":"user","message":{"content":"<task-notification>x</task-notification>"},"timestamp":"%s"}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$LRU_CFG_ROOT/.claude-t/projects/-x/$S.jsonl"
  sess 592 "$T" "$OLD --model claude-opus-5 --effort high"
  printf '%s\n' '{"type":"user","message":{"content":"please continue"},"timestamp":"2026-09-22T10:00:05Z"}' \
    >> "$LRU_CFG_ROOT/.claude-t/projects/-x/$T.jsonl"
  census
  [ "$(disp_of 591)" = mid-turn ] || { echo "$output"; false; }
  [ "$(disp_of 592)" = mid-turn ] || { echo "$output"; false; }
}

# ── T. THE TEAM PROCEDURE (2026-09-23; research docs/research/team-inplace-upgrade-2026-09-23/) ───
# A lead and its pane teammates are upgradable: TEAMMATES FIRST (their identity flags ride the
# launcher), then the LEAD, whose team dir is held aside across its exit (the vendor's exit cleanup
# kills every member it finds in the file and deletes the dir) and put back by the launcher, which
# also sets CLAUDE_INTERNAL_ASSISTANT_TEAM_NAME so the relaunched lead adopts the file instead of
# rewriting it leader-only. Each [RED] case fails with the procedure reverted.

LEAD_SID=abcd1234-0000-4000-8000-000000000001
MATE_SID=abcd1234-0000-4000-8000-000000000002
MATE_EXE="/opt/cc/.claude-260/node_modules/@anthropic-ai/claude-code/bin/claude.exe"
mate_argv() { # $1 = binary (default the old exe) $2 = model
  printf '%s --agent-id m@session-abcd1234 --agent-name m --team-name session-abcd1234 --agent-color cyan --parent-session-id %s --agent-type general-purpose --permission-mode auto --effort high --model %s' \
    "${1:-$MATE_EXE}" "$LEAD_SID" "${2:-claude-opus-5}"
}
team_file() { # the team config on the fixture account, member m present unless $1=nomember
  local td="$CFG/teams/session-abcd1234"; mkdir -p "$td/inboxes"
  if [ "${1:-}" = nomember ]; then
    printf '{"name":"session-abcd1234","leadSessionId":"%s","members":[{"agentId":"team-lead@session-abcd1234","name":"team-lead"}]}\n' "$LEAD_SID" > "$td/config.json"
  else
    printf '{"name":"session-abcd1234","leadSessionId":"%s","members":[{"agentId":"team-lead@session-abcd1234","name":"team-lead"},{"agentId":"m@session-abcd1234","name":"m","tmuxPaneId":"702","backendType":"iterm2"}]}\n' "$LEAD_SID" > "$td/config.json"
  fi
  printf '[]\n' > "$td/inboxes/m.json"
}

@test "T1 [RED] a teammate at rest is UPGRADE-TEAMMATE; its lead waits for it (LEAD-AWAITS-TEAMMATES)" {
  team_file
  sess 701 "$LEAD_SID" "$OLD --permission-mode auto --model claude-opus-5 --effort high"
  sess 702 "$MATE_SID" "$(mate_argv)"
  census
  [ "$(disp_of 702)" = upgrade-teammate ] || { echo "$output"; false; }
  [ "$(disp_of 701)" = lead-awaits-teammates ] || { echo "$output"; false; }
}

@test "T2 a teammate is held by name: no team file, an UNREAD shutdown_request, no identity" {
  sess 701 "$LEAD_SID" "$OLD --model claude-opus-5 --effort high"
  sess 702 "$MATE_SID" "$(mate_argv)"
  census
  [ "$(disp_of 702)" = teammate-no-team ] || { echo "no file: $output"; false; }
  team_file nomember; census
  [ "$(disp_of 702)" = teammate-no-team ] || { echo "not a member: $output"; false; }
  team_file
  printf '[{"from":"team-lead","read":false,"text":"{\\"type\\":\\"shutdown_request\\",\\"requestId\\":\\"r1\\"}"}]\n' > "$CFG/teams/session-abcd1234/inboxes/m.json"
  census
  [ "$(disp_of 702)" = teammate-shutdown-pending ] || { echo "unread shutdown: $output"; false; }
  printf '[{"from":"team-lead","read":true,"text":"{\\"type\\":\\"shutdown_request\\",\\"requestId\\":\\"r1\\"}"}]\n' > "$CFG/teams/session-abcd1234/inboxes/m.json"
  census
  [ "$(disp_of 702)" = upgrade-teammate ] || { echo "a READ request must not hold: $output"; false; }
  : > "$LRU_PS_SNAPSHOT"; rm -f "$LRU_REG_DIR"/*.json
  sess 703 abcd1234-0000-4000-8000-000000000003 "$MATE_EXE --agent-id m@session-abcd1234 --agent-name m --model claude-opus-5"
  census
  [ "$(disp_of 703)" = teammate-unidentified ] || { echo "no team name: $output"; false; }
}

@test "T3 [RED] once every live teammate is current the lead is UPGRADE-LEAD; with no team file it is held" {
  team_file
  sess 701 "$LEAD_SID" "$OLD --permission-mode auto --model claude-opus-5 --effort high"
  sess 702 "$MATE_SID" "$(mate_argv "$NEW" claude-opus-5-5)"
  census
  [ "$(disp_of 702)" = current ] || { echo "$output"; false; }
  [ "$(disp_of 701)" = upgrade-lead ] || { echo "$output"; false; }
  rm -rf "$CFG/teams/session-abcd1234"
  census
  [ "$(disp_of 701)" = lead-no-team-file ] || { echo "$output"; false; }
}

@test "T4 [RED] in-flight Agent-tool subagents read SUBAGENTS-IN-FLIGHT, from handoff-fire's own probe" {
  sess 710 abcd1234-0000-4000-8000-000000000010 "$OLD --model claude-opus-5 --effort high"; P="$LASTPID"
  echo 2 > "$BATS_TEST_TMPDIR/sa-count"
  census
  [ "$(disp_of 710)" = subagents-in-flight ] || { echo "$output"; false; }
  grep -q -- "--probe-live-subagents --source-session abcd1234-0000-4000-8000-000000000010 --source-pid $P" "$BATS_TEST_TMPDIR/sa-probe.log" \
    || { cat "$BATS_TEST_TMPDIR/sa-probe.log"; false; }
  echo 0 > "$BATS_TEST_TMPDIR/sa-count"
  census
  [ "$(disp_of 710)" = upgrade ] || { echo "$output"; false; }
}

@test "T5 [RED] the launchers carry the team identity: a member rejoins as itself, a lead adopts its file" {
  export LRU_FIRE_RESUME="$STUBS/fire-resume"
  printf '#!/bin/bash\nfor a in "$@"; do printf "%%s\\n" "$a"; done > %s/fr-$3.argv\nenv > %s/fr-$3.env\n' "$BATS_TEST_TMPDIR" "$BATS_TEST_TMPDIR" > "$LRU_FIRE_RESUME"; chmod +x "$LRU_FIRE_RESUME"
  # shellcheck disable=SC1090
  . "$LRU"
  targs="$(lru_team_args "$(mate_argv)")"
  [ "$targs" = "--agent-id m@session-abcd1234 --agent-name m --team-name session-abcd1234 --agent-color cyan --parent-session-id $LEAD_SID --agent-type general-purpose" ] || { echo "targs: $targs"; false; }
  Lm="$(lru_mint_launcher "$BATS_TEST_TMPDIR/runm" "$CFG" "$BATS_TEST_TMPDIR" "$MATE_SID" claude-opus-5-5 high auto "" teammate "$targs" "")"
  lru_ascii_only "$Lm"
  bash "$Lm"
  A="$BATS_TEST_TMPDIR/fr-$MATE_SID.argv"
  grep -qx -- '--extra-args' "$A" || { cat "$A"; false; }
  grep -qxF -- "$targs" "$A" || { cat "$A"; false; }
  grep -qx -- 'CLAUDECODE=1 CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1' "$A" || { cat "$A"; false; }
  awk 'p { exit !($0 == "") } $0 == "--prompt" { p = 1 }' "$A" || { echo "a teammate must get NO prompt"; cat "$A"; false; }
  grep -qx 'LR_SUBMIT_TOKEN=' "$BATS_TEST_TMPDIR/fr-$MATE_SID.env" || { echo "a teammate must arm no submit token"; false; }
  # the lead: the held team dir is back BEFORE the relaunch runs, and the adopt variable rides along
  mkdir -p "$(lru_team_hold_path "$CFG" session-abcd1234)"; echo held > "$(lru_team_hold_path "$CFG" session-abcd1234)/config.json"
  Ll="$(lru_mint_launcher "$BATS_TEST_TMPDIR/runl" "$CFG" "$BATS_TEST_TMPDIR" "$LEAD_SID" claude-opus-5-5 high auto "" lead "" session-abcd1234)"
  lru_ascii_only "$Ll"
  bash "$Ll"
  [ "$(cat "$CFG/teams/session-abcd1234/config.json")" = held ] || { echo "the launcher did not restore the team"; false; }
  [ ! -e "$(lru_team_hold_path "$CFG" session-abcd1234)" ] || false
  grep -qx 'CLAUDE_INTERNAL_ASSISTANT_TEAM_NAME=session-abcd1234' "$BATS_TEST_TMPDIR/fr-$LEAD_SID.argv" || { cat "$BATS_TEST_TMPDIR/fr-$LEAD_SID.argv"; false; }
  grep -q 'team-lead.json' "$BATS_TEST_TMPDIR/fr-$LEAD_SID.argv" || { echo "the lead is not told where its unread replies land"; false; }
}

@test "T6 [RED] the lead's team dir is HELD when handoff-fire runs, and restored when it refuses before /exit" {
  gate_env 0
  team_file
  sleep 300 & LIVE_PID=$!
  SESS_PID="$LIVE_PID" sess 701 "$LEAD_SID" "$OLD --permission-mode auto --model claude-opus-5 --effort high"
  sess 702 "$MATE_SID" "$(mate_argv "$NEW" claude-opus-5-5)"
  cat > "$LRU_HF_BIN" <<STUB
#!/bin/bash
{ [ -d "$CFG/teams/session-abcd1234" ] && echo team=present || echo team=absent
  [ -d "$CFG/teams/.session-abcd1234.lr-upgrade-hold" ] && echo hold=present || echo hold=absent
  echo "env=\${HF_ENGAGE_BY_PROCESS:-unset}"; echo "args=\$*"; } > "$BATS_TEST_TMPDIR/hf-state"
echo "!! recycle REFUSED: composer holds a draft"; exit 2
STUB
  chmod +x "$LRU_HF_BIN"
  run bash "$LRU" --drive "$LEAD_SID" 701
  kill "$LIVE_PID" 2>/dev/null || true
  grep -qx team=absent "$BATS_TEST_TMPDIR/hf-state" \
    || { echo "the lead met its /exit with its team dir in place (the exit cleanup would kill the member):"; cat "$BATS_TEST_TMPDIR/hf-state"; false; }
  grep -qx hold=present "$BATS_TEST_TMPDIR/hf-state" || { cat "$BATS_TEST_TMPDIR/hf-state"; false; }
  [ -f "$CFG/teams/session-abcd1234/config.json" ] || { echo "the refused drive did not give the lead its team back: $output"; false; }
  [ ! -e "$CFG/teams/.session-abcd1234.lr-upgrade-hold" ] || false
  [ "$(jq -r .verdict "$LRU_STATE/results/upgrade-$LEAD_SID.json")" = skipped ] || false
}

@test "T7 [RED] a teammate drive passes its own --team-member-id and asks for engagement by process" {
  gate_env 0
  team_file
  sess 701 "$LEAD_SID" "$OLD --permission-mode auto --model claude-opus-5 --effort high"
  sleep 300 & LIVE_PID=$!
  SESS_PID="$LIVE_PID" sess 702 "$MATE_SID" "$(mate_argv)"
  cat > "$LRU_HF_BIN" <<STUB
#!/bin/bash
{ echo "env=\${HF_ENGAGE_BY_PROCESS:-unset}"; echo "args=\$*"; } > "$BATS_TEST_TMPDIR/hf-state"
exit 2
STUB
  chmod +x "$LRU_HF_BIN"
  run bash "$LRU" --drive "$MATE_SID" 702
  kill "$LIVE_PID" 2>/dev/null || true
  grep -q -- "--team-member-id m@session-abcd1234" "$BATS_TEST_TMPDIR/hf-state" || { cat "$BATS_TEST_TMPDIR/hf-state"; echo "$output"; false; }
  grep -qx 'env=1' "$BATS_TEST_TMPDIR/hf-state" || { cat "$BATS_TEST_TMPDIR/hf-state"; false; }
  # the member's identity is on the launcher handoff-fire was given
  L="$(sed -n 's/.*--resume-launcher \([^ ]*\).*/\1/p' "$BATS_TEST_TMPDIR/hf-state")"
  grep -qF 'm@session-abcd1234' "$L" || { cat "$L"; false; }
}

@test "T8 --team-restore APPENDS inbox entries a recreated team dir received; nothing is dropped" {
  held="$CFG/teams/.session-abcd1234.lr-upgrade-hold"; live="$CFG/teams/session-abcd1234"
  mkdir -p "$held/inboxes" "$live/inboxes"
  echo '{"members":[1,2]}' > "$held/config.json"
  echo '[{"id":"old"}]' > "$held/inboxes/team-lead.json"
  echo '[{"id":"new"}]' > "$live/inboxes/team-lead.json"
  echo '[{"id":"only-new"}]' > "$live/inboxes/m.json"
  run bash "$LRU" --team-restore "$CFG" session-abcd1234
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(jq -c '[.[].id]' "$live/inboxes/team-lead.json")" = '["old","new"]' ] || { cat "$live/inboxes/team-lead.json"; false; }
  [ "$(jq -c '[.[].id]' "$live/inboxes/m.json")" = '["only-new"]' ] || false
  [ "$(jq -c .members "$live/config.json")" = '[1,2]' ] || false
  [ ! -e "$held" ] || false
}

@test "T9 [RED] --scrub-composer: an EXACT named stray is scrubbable; anything more is still a draft" {
  tui_stub
  sess 720 abcd1234-0000-4000-8000-000000000020 "$OLD --model claude-opus-5 --effort high"
  printf 'e' > "$BATS_TEST_TMPDIR/composer-720"
  census
  [ "$(disp_of 720)" = composer-occupied ] || { echo "an unnamed stray must hold: $output"; false; }
  LRU_SCRUB_EXACT=e census
  [ "$(disp_of 720)" = upgrade ] || { echo "the named stray still held: $output"; false; }
  printf 'ex' > "$BATS_TEST_TMPDIR/composer-720"
  LRU_SCRUB_EXACT=e census
  [ "$(disp_of 720)" = composer-occupied ] || { echo "a GROWN composer was scrubbed: $output"; false; }
  # cc-lr: the flag reaches the census and rides the request; never with --all
  cc_lr_env
  printf 'e' > "$BATS_TEST_TMPDIR/composer-720"
  run bash "$REPO/bin/cc-lr" upgrade --all --no-wait --scrub-composer e
  [ "$status" -eq 3 ] || { echo "--all accepted a scrub: $output"; false; }
  run bash "$REPO/bin/cc-lr" upgrade 720 --no-wait --scrub-composer e
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  r="$LRU_STATE/requests/cc-lr-upgrade-abcd1234-0000-4000-8000-000000000020.json"
  [ "$(jq -r .scrub_composer "$r")" = e ] || { cat "$r"; false; }
}

@test "T10 [RED] the drain hands the request's scrub_composer to the drive, which files the receipt for it" {
  gate_env 0; tui_stub
  export CC_COMPOSER_RESIDUE_DIR="$BATS_TEST_TMPDIR/residue"
  sleep 300 & LIVE_PID=$!
  SESS_PID="$LIVE_PID" sess 721 abcd1234-0000-4000-8000-000000000021 "$OLD --model claude-opus-5 --effort high"
  printf 'e' > "$BATS_TEST_TMPDIR/composer-721"
  mkdir -p "$LRU_STATE/upgrade-queue"
  printf '{"kind":"upgrade","sid":"abcd1234-0000-4000-8000-000000000021","source_pane":"721","req_id":"r9","scrub_composer":"e"}\n' > "$LRU_STATE/upgrade-queue/s.json"
  run bash "$LRU" --drain
  kill "$LIVE_PID" 2>/dev/null || true
  [ "$(cut -f2- "$CC_COMPOSER_RESIDUE_DIR/721" 2>/dev/null)" = e ] || { echo "no receipt for the named stray: $output"; false; }
  grep -q '^hf .*--same-account' "$BATS_TEST_TMPDIR/order.log" || { cat "$BATS_TEST_TMPDIR/order.log"; false; }
}

@test "T11 [RED] a team relaunch asks handoff-fire to CANCEL the exit dialog; an ordinary one does not" {
  gate_env 0
  team_file
  sleep 300 & LIVE_PID=$!
  SESS_PID="$LIVE_PID" sess 702 "$MATE_SID" "$(mate_argv)"
  sess 701 "$LEAD_SID" "$OLD --permission-mode auto --model claude-opus-5 --effort high"
  printf '#!/bin/bash\necho "bgwork=${CC_RECYCLE_BGWORK_ANSWER:-unset}" >> %s/bg.log\nexit 2\n' "$BATS_TEST_TMPDIR" > "$LRU_HF_BIN"; chmod +x "$LRU_HF_BIN"
  run bash "$LRU" --drive "$MATE_SID" 702
  kill "$LIVE_PID" 2>/dev/null || true
  grep -qx 'bgwork=cancel' "$BATS_TEST_TMPDIR/bg.log" || { cat "$BATS_TEST_TMPDIR/bg.log"; echo "$output"; false; }
  : > "$BATS_TEST_TMPDIR/bg.log"
  sleep 300 & LIVE_PID=$!
  SESS_PID="$LIVE_PID" sess 703 abcd1234-0000-4000-8000-000000000030 "$OLD --permission-mode auto --model claude-opus-5 --effort high"
  run bash "$LRU" --drive abcd1234-0000-4000-8000-000000000030 703
  kill "$LIVE_PID" 2>/dev/null || true
  grep -qx 'bgwork=on' "$BATS_TEST_TMPDIR/bg.log" || { cat "$BATS_TEST_TMPDIR/bg.log"; false; }
}
