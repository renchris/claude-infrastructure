#!/usr/bin/env bats
# lr-reset-poller.sh rq_stale_reason — A BACKGROUND JOB IS NOT A TEAMMATE (bg-attach-recover, 2026-10-04).
#
# The defect, measured on d425afab: the hook lane's drain-time re-check (rq_stale_reason) asked
# "teammate?" with a raw `head -c 8192 | grep '"agentName"'` (49c16be7e). Claude Code auto-names every
# background job and writes that name at the transcript head as
#   {"type":"agent-name","agentName":"<title>","sessionId":…}
# which is a LEAD's session-name record (lr_predicate.is_teammate_head excludes it on purpose). So
# every bg session's stop-failure-marker request was retired as "a teammate — lead-owned, never a
# recovery target" and nothing ever recovered it. The fix routes the check through lrp_is_teammate
# (the SSOT shim), which also had to MOVE above rq_stale_reason: the request lane is top-level code
# that runs before the old definition, so an unmoved call is rc 127 and reads as "not a teammate"
# for real teammates too. The CONTROL case below is what catches that trap.
#
# Hermetic: fixture $HOME, a stub lr-fleet that records its argv, no census, no registry, no kitty.
# The poller reads the REAL lr-lib.sh / lr-predicate.sh / lr_predicate.py from this checkout.

setup() {
  export LR_UPGRADE_AUTO=off
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  POLLER="$REPO/scripts/limit-recover/lr-reset-poller.sh"
  export HOME="$BATS_TEST_TMPDIR/home"
  STATE="$HOME/.reso/limit-recover"
  mkdir -p "$HOME/bin" "$STATE/parked" "$STATE/resumed" "$STATE/locks" "$BATS_TEST_TMPDIR/stubs"
  SID="d425afab-0000-4000-8000-0000000000aa"
  unset CLAUDE_CONFIG_DIR KITTY_WINDOW_ID CC_TERM_KITTY_TO LR_RQ_TEAMMATE_PREDICATE LR_PREDICATE_PY LR_CONFIG_DIRS LR_RQ_BG_HOLDER
  export LR_POLLER_NO_CENSUS=1
  export CC_REGISTRY_DIR="$BATS_TEST_TMPDIR/reg"; mkdir -p "$CC_REGISTRY_DIR"
  export LR_POLLER_LAUNCH_DIR="$BATS_TEST_TMPDIR/launchers"; mkdir -p "$LR_POLLER_LAUNCH_DIR"
  export CC_KITTY_SOCKET_BIN="$BATS_TEST_TMPDIR/no-kitty-socket"
  export LR_CC_TUI_LIB="$BATS_TEST_TMPDIR/absent-cc-tui.sh"
  printf '#!/bin/bash\nexit 1\n' > "$BATS_TEST_TMPDIR/stubs/osascript"
  printf '#!/bin/bash\necho %s\n' "'{\"rows\":[{\"acct\":\"next4\",\"session_pct\":12,\"weekly_pct\":40}]}'" > "$HOME/bin/claude-accounts"
  chmod +x "$BATS_TEST_TMPDIR/stubs/osascript" "$HOME/bin/claude-accounts"
  export PATH="$BATS_TEST_TMPDIR/stubs:$PATH"
  # lr-fleet stub: records argv; with --detach it returns at once naming a live driver (the bats pid),
  # as lr-fleet.sh's real --detach contract does.
  export LR_FLEET_BIN="$BATS_TEST_TMPDIR/stubs/lr-fleet"
  cat > "$LR_FLEET_BIN" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >> "${FLEET_LOG:?}"
echo "lr-fleet: DETACHED — driver pid ${FLEET_DRIVER_PID:-4242} is recovering; the verdict arrives as mail."
echo "run=/nowhere/run log=/nowhere/run/detached.log"
exit 0
STUB
  chmod +x "$LR_FLEET_BIN"
  export FLEET_LOG="$BATS_TEST_TMPDIR/fleet.log"; : > "$FLEET_LOG"
  export FLEET_DRIVER_PID="$$"
  # The hook lane drains only with the operator's flag; every case here is about what it does THEN.
  : > "$STATE/autorecover.on"
}

tick() { LR_POLLER_AUTOFIRE=1 run bash "$POLLER" --once; }
plog() { cat "$STATE/poller.log" >&2; }
# The same weekly-limit record the sibling suite's lim_tx writes, so rq_stale_reason reads LIMITED.
lim_rec() {
  printf '{"type":"assistant","timestamp":"2026-10-04T07:59:47Z","isApiErrorMessage":true,"error":"rate_limit","message":{"role":"assistant","content":[{"type":"text","text":"You'"'"'ve hit your weekly limit · resets Oct 5"}]}}\n'
}
txdir() { local d="$HOME/.claude-tertiary/projects/-Users-x-proj"; mkdir -p "$d"; printf '%s' "$d"; }
bg_tx() { # $1=sid → a LIMITED transcript headed the way every auto-named bg job is (d425afab's line 2)
  local f; f="$(txdir)/$1.jsonl"
  printf '{"type":"ai-title","aiTitle":"Some bg job","sessionId":"%s"}\n{"type":"agent-name","agentName":"Some bg job","sessionId":"%s"}\n' "$1" "$1" > "$f"
  lim_rec >> "$f"; printf '%s' "$f"
}
tm_tx() { # $1=sid → a LIMITED transcript headed by a real member record (type=user + agentName + teamName)
  local f; f="$(txdir)/$1.jsonl"
  printf '{"type":"user","agentName":"worker-1","teamName":"t1","sessionId":"%s","message":{"role":"user","content":"go"}}\n' "$1" > "$f"
  lim_rec >> "$f"; printf '%s' "$f"
}
hook_rq() { # $1=transcript path → a stop-failure-marker request for $SID
  mkdir -p "$STATE/requests"
  printf '{"sid":"%s","requested_by":"stop-failure-marker","account":"next4","transcript_path":"%s"}\n' "$SID" "$1" \
    > "$STATE/requests/$SID.json"
}

@test "[RED] a hook request for an auto-named BACKGROUND session is NOT retired as a teammate — it dispatches" {
  hook_rq "$(bg_tx "$SID")"
  tick
  [ "$status" -eq 0 ]
  grep -q -- "--one $SID" "$FLEET_LOG" || { cat "$FLEET_LOG"; plog; false; }
  ! grep -q "REQUEST-RETIRED $SID — a teammate" "$STATE/poller.log" || { plog; false; }
  [ ! -e "$STATE/results/$SID.retired.json" ] || { cat "$STATE/results/$SID.json"; false; }
}

@test "CONTROL: a real teammate (type=user + agentName + teamName) is still retired as lead-owned — never dispatched" {
  # Also the relocation guard: lrp_is_teammate left below the request lane is rc 127 here, which
  # reads as "not a teammate" and would dispatch this request.
  hook_rq "$(tm_tx "$SID")"
  tick
  [ "$status" -eq 0 ]
  [ ! -s "$FLEET_LOG" ] || { echo "a teammate was dispatched: $(cat "$FLEET_LOG")"; plog; false; }
  grep -q "REQUEST-RETIRED $SID — a teammate — lead-owned, never a recovery target" "$STATE/poller.log" || { plog; false; }
  [ -f "$STATE/results/$SID.retired.json" ] || { ls -la "$STATE/results" >&2; false; }
  [ "$(jq -r .verdict "$STATE/results/$SID.json")" = retired ]
}

@test "KILL SWITCH: LR_RQ_TEAMMATE_PREDICATE=off restores the raw grep — the bg fixture is retired as a teammate" {
  export LR_RQ_TEAMMATE_PREDICATE=off
  hook_rq "$(bg_tx "$SID")"
  tick
  [ "$status" -eq 0 ]
  [ ! -s "$FLEET_LOG" ] || { cat "$FLEET_LOG"; plog; false; }
  grep -q "REQUEST-RETIRED $SID — a teammate — lead-owned, never a recovery target" "$STATE/poller.log" || { plog; false; }
}

@test "UNREADABLE: with the predicate module absent the request is retired with the named reason, never dispatched" {
  # Control is the [RED] case: the same bg fixture with the module present dispatches.
  export LR_PREDICATE_PY="$BATS_TEST_TMPDIR/nonexistent/lr_predicate.py"
  hook_rq "$(bg_tx "$SID")"
  tick
  [ "$status" -eq 0 ]
  [ ! -s "$FLEET_LOG" ] || { cat "$FLEET_LOG"; plog; false; }
  grep -q "REQUEST-RETIRED $SID — the teammate test could not run (predicate refused)" "$STATE/poller.log" || { plog; false; }
  [ -f "$STATE/results/$SID.retired.json" ]
}

# bg_job <pid> [procStart] — a kind=bg sessions file for $SID under the JOB's store (quaternary, not
# the store holding the transcript: the d425afab shape). The live pid is the bats process itself, so
# nothing is spawned; its procStart is rendered the way Claude Code writes it (C locale, UTC).
bg_job() {
  local st="${2-$(LC_ALL=C TZ=UTC ps -o lstart= -p "$1" | tr -s ' ' | sed 's/^ //; s/ $//')}"
  mkdir -p "$HOME/.claude-quaternary/sessions" "$HOME/.claude-quaternary/projects"
  jq -n --argjson pid "$1" --arg sid "$SID" --arg st "$st" \
    '{pid:$pid, sessionId:$sid, kind:"bg", jobId:"032aa97f", status:"idle", procStart:$st}' \
    > "$HOME/.claude-quaternary/sessions/$1.json"
}

@test "[RED] BG HOLDER: a limited bg session whose job is still LIVE is retired (only cc-lr switch moves it), never dispatched to lr-fleet; CONTROL the same head with the job gone dispatches" {
  hook_rq "$(bg_tx "$SID")"
  bg_job "$$"
  tick
  [ "$status" -eq 0 ]
  [ ! -s "$FLEET_LOG" ] || { echo "dispatched beside a live bg job: $(cat "$FLEET_LOG")"; plog; false; }
  grep -q "REQUEST-RETIRED $SID — a live background job (pid $$ under $HOME/.claude-quaternary) - only cc-lr switch moves it" "$STATE/poller.log" || { plog; false; }
  # CONTROL: the job's pid is dead (a subshell that has exited) — the request dispatches as before
  rm -f "$HOME/.claude-quaternary/sessions/$$.json" "$STATE/results/$SID".* 2>/dev/null
  ( : ) & local dead=$!; wait "$dead" 2>/dev/null || true
  bg_job "$dead" "Tue Sep 22 06:47:13 2026"
  hook_rq "$(bg_tx "$SID")"
  tick
  grep -q -- "--one $SID" "$FLEET_LOG" || { cat "$FLEET_LOG"; plog; false; }
}

@test "BG HOLDER: a live pid whose start does not match procStart (a recycled pid) holds nothing — dispatched" {
  hook_rq "$(bg_tx "$SID")"
  bg_job "$$" "Tue Sep 22 06:47:13 2026"
  tick
  grep -q -- "--one $SID" "$FLEET_LOG" || { echo "recycled pid read as a holder"; plog; false; }
}

@test "BG HOLDER KILL SWITCH: LR_RQ_BG_HOLDER=off dispatches beside a live job (the pre-fix lane)" {
  bg_job "$$"; hook_rq "$(bg_tx "$SID")"
  LR_RQ_BG_HOLDER=off tick
  grep -q -- "--one $SID" "$FLEET_LOG" || { cat "$FLEET_LOG"; plog; false; }
}

@test "without the autorecover flag the bg request is LEFT in place (HOOK-HELD), not retired as a teammate" {
  rm -f "$STATE/autorecover.on"
  hook_rq "$(bg_tx "$SID")"
  tick
  [ "$status" -eq 0 ]
  [ ! -s "$FLEET_LOG" ] || { cat "$FLEET_LOG"; false; }
  [ -f "$STATE/requests/$SID.json" ] || { plog; false; }
  [ ! -e "$STATE/results/$SID.retired.json" ]
  grep -q "HOOK-HELD 1 hook-originated request(s) NOT drained" "$STATE/poller.log" || { plog; false; }
}
