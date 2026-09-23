#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2016  # stubs are written verbatim; each @test is its own subshell; per-test exports are the intent
# cc-lr switch --pane/--sid/--from --all-idle — THE DRIVER FORM of the voluntary account switch
# (2026-09-23; VOLUNTARY_ACCOUNT_SWITCH §5 DEC-2, resolved).
# Subjects: scripts/limit-recover/lr-upgrade.sh (--switch-census · lru_switch_drive · the drain's
#           kind dispatch), scripts/limit-recover/lr-reset-poller.sh (kind "switch" → the queue),
#           bin/cc-lr switch (driver flags · dry run · request write · the SELF path left alone).
#
# THE INCIDENT: moving two idle next3 panes to next2 took five attempts and ~8 h, because every
# sanctioned path refused a healthy idle peer. What worked was a hand-written poller prompt request
# telling each subject to run `cc-lr switch --target next2` itself. These cases pin that, made a verb.
#
# RED PROOFS (fail on the unfixed tree — no --switch-census, no switch arm, no driver flags) are
# labelled [RED]; the rest are equivalence guards or refusals pinned for a future refactor.
#
# Hermetic: every store is a fixture, `ps` is a snapshot FILE, cc-tui.sh is a stub library, the
# subagent probe is a stub, launchctl and cc-notify are recorders. Nothing can type into a pane.

setup() {
  command -v jq >/dev/null || skip "jq required"
  export CC_FIRE_CAPACITY_GATE=off CC_ADMIT_GATE=off
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LRU="$REPO/scripts/limit-recover/lr-upgrade.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export LRU_STATE="$HOME/.reso/limit-recover"; mkdir -p "$LRU_STATE"
  export LRU_REG_DIR="$BATS_TEST_TMPDIR/reg"; mkdir -p "$LRU_REG_DIR"
  # The account map resolves next2 → $HOME/.claude-secondary, so the config root IS $HOME here:
  # the census (registry account → dir) and the verifier (name → dir) must agree on one tree.
  export LRU_CFG_ROOT="$HOME"
  export LRU_PS_SNAPSHOT="$BATS_TEST_TMPDIR/ps.txt"; : > "$LRU_PS_SNAPSHOT"
  export LRU_COMPOSER=off
  export LRU_SELF_SID=""
  export LRU_LR_LIB="$BATS_TEST_TMPDIR/absent-lr-lib.sh"
  STUBS="$BATS_TEST_TMPDIR/stubs"; mkdir -p "$STUBS"
  export LRU_NOTIFY_BIN="$STUBS/cc-notify"
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> %s\n' "$BATS_TEST_TMPDIR/notify.log" > "$LRU_NOTIFY_BIN"; chmod +x "$LRU_NOTIFY_BIN"
  export LRU_SA_PROBE="$STUBS/sa-probe"
  printf '#!/bin/bash\necho "live_subagents: $(cat %s/sa-count 2>/dev/null || echo 0)"\n' "$BATS_TEST_TMPDIR" > "$LRU_SA_PROBE"; chmod +x "$LRU_SA_PROBE"
  export LRU_SWITCH_POLL_S=0 LRU_SWITCH_VERIFY_S=3 LRU_GAP_S=0
  BIN="/opt/cc/.claude-280/node_modules/.bin/claude"
  N=0
  unset CLAUDE_CODE_SESSION_ID CC_PANE_ID ITERM_SESSION_ID KITTY_WINDOW_ID
}

LST="Tue Sep 22 06:47:13 2026"
# sess <pane> <sid> [shape rest|busy|none] [account dir basename, default claude-tertiary = next3] [argv]
sess() {
  local pane="$1" sid="$2" shape="${3:-rest}" acct="${4:-claude-tertiary}" argv="${5:-$BIN --model claude-opus-5-5 --effort high}" pid
  N=$((N + 1)); pid="${SESS_PID:-$((50000 + N))}"
  printf '{"paneUUID":"%s","pid":%d,"session_id":"%s","account":"%s","cwd":"%s","lstart":"%s"}\n' \
    "$pane" "$pid" "$sid" "$acct" "$BATS_TEST_TMPDIR" "$LST" > "$LRU_REG_DIR/$pane.json"
  printf '%d 1 %s %s\n' "$pid" "$LST" "$argv" >> "$LRU_PS_SNAPSHOT"
  local tx="$HOME/.$acct/projects/-x/$sid.jsonl"; mkdir -p "$(dirname "$tx")"
  case "$shape" in
    rest) printf '%s\n' '{"type":"user","message":{"content":"hi"}}' \
            '{"type":"assistant","message":{"stop_reason":"end_turn","content":[{"type":"text","text":"idle"}]}}' > "$tx" ;;
    busy) printf '%s\n' '{"type":"assistant","message":{"stop_reason":"tool_use","content":[{"type":"tool_use"}]}}' > "$tx" ;;
    none) rm -f "$tx" ;;
  esac
}
disp_of() { printf '%s\n' "$output" | awk -F'\t' -v p="$1" '$1 == p { print $7 }'; }
# The TUI library stub: composer contents from composer-<pane>; cc_tui_submit RECORDS its payload
# and then plays the subject per $SUBMIT_ACT (flip = the subject moved itself; reply = it answered
# and stayed; none = nothing happened) and returns $SUBMIT_RC.
tui_stub() {
  export LRU_TUI_LIB="$BATS_TEST_TMPDIR/tui.sh"
  cat > "$LRU_TUI_LIB" <<EOF
cc_tui_composer() { cat "$BATS_TEST_TMPDIR/composer-\$1" 2>/dev/null; return 0; }
cc_tui_submit() {
  printf '%s|%s\n' "\$1" "\$(cat "\$2")" >> "$BATS_TEST_TMPDIR/submit.log"
  local reg="$LRU_REG_DIR/\$1.json" sid acct
  sid="\$(jq -r .session_id "\$reg")"; acct="\$(jq -r .account "\$reg")"
  case "\${SUBMIT_ACT:-none}" in
    flip)  mkdir -p "$HOME/.claude-secondary/projects/-x"
           cp "$HOME/.\$acct/projects/-x/\$sid.jsonl" "$HOME/.claude-secondary/projects/-x/"
           jq '.account = "claude-secondary"' "\$reg" > "\$reg.t" && mv "\$reg.t" "\$reg" ;;
    reply) sleep 1
           printf '%s\n' '{"type":"user","message":{"content":"x"}}' \
             '{"type":"assistant","message":{"stop_reason":"end_turn","content":[{"type":"text","text":"not moving: next2 is near its weekly cap"}]}}' \
             >> "$HOME/.\$acct/projects/-x/\$sid.jsonl" ;;
  esac
  return \${SUBMIT_RC:-0}
}
EOF
}
cc_lr_env() {
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "%s"\n' "$BATS_TEST_TMPDIR/launchctl.log" > "$STUBS/launchctl"
  chmod +x "$STUBS/launchctl"
  export PATH="$STUBS:$PATH"
  export LR_STATE_DIR="$LRU_STATE" CC_LR_UPGRADE_BIN="$LRU" CC_PANE_ID=999
}

# ── A. THE SELECTION — lr-upgrade's idle oracle, reused ──────────────────────────────────────────

@test "A1 [RED] an idle session on next3 is MOVE; mid-turn, teammate and no-transcript are held, each by name" {
  sess 401 aaaaaaaa-0000-4000-8000-000000000001
  sess 402 aaaaaaaa-0000-4000-8000-000000000002 busy
  sess 403 aaaaaaaa-0000-4000-8000-000000000003 rest claude-tertiary "$BIN --agent-id w@session-x --agent-name w --model claude-opus-5-5"
  sess 404 aaaaaaaa-0000-4000-8000-000000000004 none
  run bash "$LRU" --switch-census --from next3 --target next2
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(disp_of 401)" = move ] || { echo "$output"; false; }
  [ "$(disp_of 402)" = mid-turn ] || { echo "$output"; false; }
  [ "$(disp_of 403)" = teammate ] || { echo "$output"; false; }
  [ "$(disp_of 404)" = no-transcript ] || { echo "$output"; false; }
  printf '%s\n' "$output" | awk -F'\t' '$1==401 { exit !($3=="next3") }'
}

@test "A2 [RED] a lead with a live teammate, in-flight subagents, a non-empty composer: none moves" {
  sess 410 bbbbbbbb-0000-4000-8000-000000000001
  printf '%d 1 %s %s\n' 60001 "$LST" "$BIN --agent-id m@session-bbbbbbbb --parent-session-id bbbbbbbb-0000-4000-8000-000000000001" >> "$LRU_PS_SNAPSHOT"
  sess 411 bbbbbbbb-0000-4000-8000-000000000002
  sess 412 bbbbbbbb-0000-4000-8000-000000000003
  tui_stub; export LRU_COMPOSER=on
  printf 'half a draft' > "$BATS_TEST_TMPDIR/composer-412"
  echo 2 > "$BATS_TEST_TMPDIR/sa-count"
  run bash "$LRU" --switch-census --from next3 --target next2 --pane 411
  [ "$(disp_of 411)" = subagents-in-flight ] || { echo "$output"; false; }
  rm -f "$BATS_TEST_TMPDIR/sa-count"
  run bash "$LRU" --switch-census --from next3 --target next2
  [ "$(disp_of 410)" = lead-with-teammate ] || { echo "$output"; false; }
  [ "$(disp_of 412)" = composer-occupied ] || { echo "$output"; false; }
  [ "$(disp_of 411)" = move ] || { echo "$output"; false; }
}

@test "A3 the --from filter selects by account NAME; a session already on the target is ON-TARGET; self is SELF" {
  sess 420 cccccccc-0000-4000-8000-000000000001
  sess 421 cccccccc-0000-4000-8000-000000000002 rest claude-secondary
  sess 422 cccccccc-0000-4000-8000-000000000003
  run bash "$LRU" --switch-census --from next3 --target next2
  [ -z "$(disp_of 421)" ] || { echo "a next2 session was selected by --from next3: $output"; false; }
  LRU_SELF_SID=cccccccc-0000-4000-8000-000000000003 run bash "$LRU" --switch-census --target next2
  [ "$(disp_of 421)" = on-target ] || { echo "$output"; false; }
  [ "$(disp_of 422)" = self ] || { echo "$output"; false; }
  [ "$(disp_of 420)" = move ] || { echo "$output"; false; }
}

# ── B. cc-lr switch, the driver form ────────────────────────────────────────────────────────────

@test "B1 [RED] cc-lr switch --from next3 --all-idle --dry-run prints one row per candidate and writes NOTHING" {
  cc_lr_env
  sess 501 dddddddd-0000-4000-8000-000000000001
  sess 502 dddddddd-0000-4000-8000-000000000002 busy
  run bash "$REPO/bin/cc-lr" switch --from next3 --all-idle --target next2 --dry-run
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"501   dddddddd  next3 → next2"*"move"* ]] || { echo "$output"; false; }
  [[ "$output" == *"502   dddddddd  next3 → next2"*"mid-turn"* ]] || { echo "$output"; false; }
  [[ "$output" == *"1 to move · DRY RUN"* ]] || { echo "$output"; false; }
  [ -z "$(ls -A "$LRU_STATE/requests" 2>/dev/null)" ] || { echo "a dry run wrote a request"; false; }
  [ ! -s "$BATS_TEST_TMPDIR/launchctl.log" ] || { echo "a dry run kicked the poller"; false; }
}

@test "B2 [RED] --pane writes ONE kind:switch request with target, pane and req id, and kicks without -k" {
  cc_lr_env
  sess 511 eeeeeeee-0000-4000-8000-000000000001
  sess 512 eeeeeeee-0000-4000-8000-000000000002
  run bash "$REPO/bin/cc-lr" switch --pane 511 --target next2 --no-wait
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  r="$LRU_STATE/requests/cc-lr-switch-eeeeeeee-0000-4000-8000-000000000001.json"
  [ -f "$r" ] || { ls -la "$LRU_STATE/requests"; echo "$output"; false; }
  [ "$(jq -r .kind "$r")" = switch ] || { cat "$r"; false; }
  [ "$(jq -r .target "$r")" = next2 ] || { cat "$r"; false; }
  [ "$(jq -r .source_pane "$r")" = 511 ] || { cat "$r"; false; }
  [ "$(jq -r .requested_by "$r")" = 999 ] || { cat "$r"; false; }
  [ -n "$(jq -r '.req_id // empty' "$r")" ] || { cat "$r"; false; }
  nreq=0; for q in "$LRU_STATE"/requests/*.json; do [ -f "$q" ] && nreq=$((nreq + 1)); done
  [ "$nreq" -eq 1 ] || { ls "$LRU_STATE/requests"; false; }
  grep -q '^kickstart gui/' "$BATS_TEST_TMPDIR/launchctl.log"
  ! grep -q -- '-k' "$BATS_TEST_TMPDIR/launchctl.log" || { echo "the poller was kicked with -k"; false; }
}

@test "B3 a held session writes no request and reports NOTMOVED with its disposition" {
  cc_lr_env
  sess 521 ffffffff-0000-4000-8000-000000000001 busy
  run bash "$REPO/bin/cc-lr" switch --pane 521 --target next2 --no-wait
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *"521   ffffffff  NOTMOVED (mid-turn)"* ]] || { echo "$output"; false; }
  [ -z "$(ls -A "$LRU_STATE/requests" 2>/dev/null)" ] || false
}

@test "B4 refusals: target auto, an unknown account, no subject, --from without --all-idle — rc 3, nothing written" {
  cc_lr_env
  sess 531 12121212-0000-4000-8000-000000000001
  run bash "$REPO/bin/cc-lr" switch --pane 531 --target auto
  [ "$status" -eq 3 ] || { echo "$output"; false; }
  [[ "$output" == *"explicit --target"* ]] || { echo "$output"; false; }
  run bash "$REPO/bin/cc-lr" switch --pane 531 --target nosuch9
  [ "$status" -eq 3 ] || { echo "$output"; false; }
  [[ "$output" == *"not an account"* ]] || { echo "$output"; false; }
  run bash "$REPO/bin/cc-lr" switch --all-idle --target next2
  [ "$status" -eq 3 ] || { echo "$output"; false; }
  run bash "$REPO/bin/cc-lr" switch --from next3 --target next2
  [ "$status" -eq 3 ] || { echo "$output"; false; }
  [ -z "$(ls -A "$LRU_STATE/requests" 2>/dev/null)" ] || false
}

@test "B5 plain 'cc-lr switch' (no driver flag) never reaches the driver: it still composes lr-handoff for SELF" {
  # EQUIVALENCE GUARD — the SELF verb must be untouched by the driver form.
  cc_lr_env
  export CC_LR_HANDOFF_BIN="$STUBS/lr-handoff"
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> %s\n' "$BATS_TEST_TMPDIR/handoff.argv" > "$CC_LR_HANDOFF_BIN"; chmod +x "$CC_LR_HANDOFF_BIN"
  export CC_LR_UPGRADE_BIN="$STUBS/absent-upgrade"
  run env CLAUDE_CODE_SESSION_ID=13131313-0000-4000-8000-000000000001 CC_PANE_ID=417 bash "$REPO/bin/cc-lr" switch --target next2
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  grep -q -- '--sid 13131313-0000-4000-8000-000000000001 .*--in-place --voluntary' "$BATS_TEST_TMPDIR/handoff.argv"
  [ -z "$(ls -A "$LRU_STATE/requests" 2>/dev/null)" ] || false
}

# ── C. THE POLLER ACCEPTS kind:switch ───────────────────────────────────────────────────────────

@test "C1 [RED] the poller QUEUES a kind:switch request for the one drainer — never parks it as unknown, never drives it inline" {
  POLLER="$REPO/scripts/limit-recover/lr-reset-poller.sh"
  export LR_POLLER_NO_CENSUS=1
  export CC_REGISTRY_DIR="$BATS_TEST_TMPDIR/preg"; mkdir -p "$CC_REGISTRY_DIR"
  export LR_POLLER_LAUNCH_DIR="$BATS_TEST_TMPDIR/launchers"; mkdir -p "$LR_POLLER_LAUNCH_DIR"
  export CC_KITTY_SOCKET_BIN="$BATS_TEST_TMPDIR/no-kitty-socket"
  printf '#!/bin/bash\nexit 1\n' > "$STUBS/osascript"; chmod +x "$STUBS/osascript"
  mkdir -p "$HOME/bin"; printf '#!/bin/bash\necho %s\n' "'{\"rows\":[]}'" > "$HOME/bin/claude-accounts"; chmod +x "$HOME/bin/claude-accounts"
  export PATH="$STUBS:$PATH"
  export LR_FLEET_BIN="$STUBS/lr-fleet"; printf '#!/bin/bash\necho "$*" >> %s\n' "$BATS_TEST_TMPDIR/fleet.log" > "$LR_FLEET_BIN"; chmod +x "$LR_FLEET_BIN"
  export LR_UPGRADE_BIN="$STUBS/lr-upgrade"
  printf '#!/bin/bash\necho "$*" >> %s\n' "$BATS_TEST_TMPDIR/drain.log" > "$LR_UPGRADE_BIN"; chmod +x "$LR_UPGRADE_BIN"
  PSTATE="$HOME/.reso/limit-recover"; mkdir -p "$PSTATE/requests" "$PSTATE/parked" "$PSTATE/resumed"
  printf '{"kind":"switch","sid":"30303030-0000-4000-8000-000000000001","source_pane":"530","target":"next2","requested_by":"999"}\n' \
    > "$PSTATE/requests/cc-lr-switch-30303030.json"
  LR_POLLER_AUTOFIRE=1 run bash "$POLLER" --once
  [ -f "$PSTATE/upgrade-queue/cc-lr-switch-30303030.json" ] || { cat "$PSTATE/poller.log"; false; }
  [ ! -e "$PSTATE/results/cc-lr-switch-30303030.unknown-kind.json" ] || false
  [ ! -s "$BATS_TEST_TMPDIR/fleet.log" ] || { echo "a switch was driven as a recovery"; false; }
  grep -q 'SWITCH-QUEUED 30303030.*-> next2' "$PSTATE/poller.log" || { cat "$PSTATE/poller.log"; false; }
}

# ── D. THE DRIVE: re-judge, then ONE canonical line, then the registry flip decides ──────────────

@test "D1 [RED] the drain re-judges at execution time: a session that went BUSY is NOTMOVED and never typed into" {
  tui_stub
  sess 541 40404040-0000-4000-8000-000000000001 busy
  mkdir -p "$LRU_STATE/upgrade-queue"
  printf '{"kind":"switch","sid":"40404040-0000-4000-8000-000000000001","source_pane":"541","target":"next2","req_id":"r1","requested_by":"999"}\n' \
    > "$LRU_STATE/upgrade-queue/a.json"
  run bash "$LRU" --drain
  [ ! -s "$BATS_TEST_TMPDIR/submit.log" ] || { echo "typed into a busy session: $(cat "$BATS_TEST_TMPDIR/submit.log")"; false; }
  r="$LRU_STATE/results/switch-40404040-0000-4000-8000-000000000001.json"
  [ "$(jq -r .verdict "$r")" = NOTMOVED ] || { cat "$r"; false; }
  [[ "$(jq -r .reason "$r")" == mid-turn* ]] || { cat "$r"; false; }
  [ "$(jq -r .req_id "$r")" = r1 ] || false
  grep -q '^999 CC-LR-SWITCH pane 541 .*verdict=NOTMOVED' "$BATS_TEST_TMPDIR/notify.log" || { cat "$BATS_TEST_TMPDIR/notify.log"; false; }
  [ -z "$(ls -A "$LRU_STATE/upgrade-queue")" ] || false
}

@test "D2 [RED] an idle session gets ONE canonical operator-ruling line; the registry flip proves SWITCHED" {
  tui_stub; export SUBMIT_ACT=flip
  sess 551 50505050-0000-4000-8000-000000000001
  run bash "$LRU" --switch-drive 50505050-0000-4000-8000-000000000001 551 next2 --requested-by 999 --req-id r2
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(grep -c . "$BATS_TEST_TMPDIR/submit.log")" -eq 1 ] || { cat "$BATS_TEST_TMPDIR/submit.log"; false; }
  [ "$(cat "$BATS_TEST_TMPDIR/submit.log")" = "551|[operator-ruling cc-lr-switch req=r2] Run in Bash now: cc-lr switch --target next2" ] \
    || { cat "$BATS_TEST_TMPDIR/submit.log"; false; }
  r="$LRU_STATE/results/switch-50505050-0000-4000-8000-000000000001.json"
  [ "$(jq -r .verdict "$r")" = SWITCHED ] || { cat "$r"; false; }
  [ "$(jq -r .from "$r")" = next3 ] || { cat "$r"; false; }
  [ "$(jq -r .to "$r")" = next2 ] || { cat "$r"; false; }
  [ "$(jq -r .proven "$r")" = yes ] || { cat "$r"; false; }
  # THE MUTEX WAS RELEASED before the submit — the subject's own `cc-lr switch` takes it.
  [ ! -e "$LRU_STATE/runs/by-sid/50505050-0000-4000-8000-000000000001.active" ] || false
}

@test "D3 the canonical line is ONE ASCII line and carries no kill phrase" {
  run bash -c ". '$LRU'; lru_switch_prompt next2 r9"
  [ "$(printf '%s\n' "$output" | grep -c .)" -eq 1 ]
  # (not `! cmd` mid-test — under errexit a negated command can never fail the case)
  if printf '%s' "$output" | LC_ALL=C grep -q '[^ -~]'; then echo "non-ASCII: $output"; false; fi
  if printf '%s' "$output" | grep -qiE 'and stop|no auto-continue|just do'; then echo "kill phrase: $output"; false; fi
  [[ "$output" == "[operator-ruling cc-lr-switch req=r9]"* ]] || { echo "$output"; false; }
}

@test "D4 the subject took its turn and STAYED: NOTMOVED, quoting its reply — never FAILED, never SWITCHED" {
  tui_stub; export SUBMIT_ACT=reply LRU_SWITCH_VERIFY_S=20
  SESS_PID=$$ sess 561 60606060-0000-4000-8000-000000000001
  run bash "$LRU" --switch-drive 60606060-0000-4000-8000-000000000001 561 next2 --requested-by 999 --req-id r3
  [ "$status" -eq 3 ] || { echo "$output"; false; }
  r="$LRU_STATE/results/switch-60606060-0000-4000-8000-000000000001.json"
  [ "$(jq -r .verdict "$r")" = NOTMOVED ] && [[ "$(jq -r .reason "$r")" == *"near its weekly cap"* ]] || { cat "$r"; false; }
}

@test "D5 a submit the TUI refused (composer occupied) is NOTMOVED; a submit with no outcome in the bound is FAILED" {
  tui_stub
  sess 571 70707070-0000-4000-8000-000000000001
  SUBMIT_RC=3 run bash "$LRU" --switch-drive 70707070-0000-4000-8000-000000000001 571 next2 --req-id r4
  [ "$status" -eq 3 ] || { echo "$output"; false; }
  [ "$(jq -r .verdict "$LRU_STATE/results/switch-70707070-0000-4000-8000-000000000001.json")" = NOTMOVED ] || false
  LRU_SWITCH_VERIFY_S=1 run bash "$LRU" --switch-drive 70707070-0000-4000-8000-000000000001 571 next2 --req-id r5
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [ "$(jq -r .verdict "$LRU_STATE/results/switch-70707070-0000-4000-8000-000000000001.json")" = FAILED ] || false
}
