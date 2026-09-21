#!/usr/bin/env bats
# lr-reset-poller.sh — the in-place arms (LIMIT_RECOVER_100P, 2026-09-09).
#
# Three defects measured on 2026-09-09, one suite:
#   D1 the poller resumed 52e35019 into a NEW process while pane 616 still held the original (its
#      liveness was `pgrep -f "resume <sid>"`, blind to a fresh launch's argv) → two writers, one
#      transcript, one account. Now: a live registry row ⇒ NUDGE the pane in place, never spawn.
#   D2 spawn_gui keyed on $KITTY_WINDOW_ID, absent under launchd ⇒ `auto` fell to tmux, invisible and
#      UNANSWERABLE (a permission prompt froze it). Now: kitty via the resolved socket, runner-rooted;
#      no GUI ⇒ NOT SPAWNED, loudly; tmux only by explicit LR_POLLER_SPAWN=tmux.
#   D3 the minted launcher carried no tier ⇒ every unattended Fable recovery landed on Opus. Now: the
#      transcript's (model, effort) ride with the resume. Plus: a parked sid that /limit-recover
#      already TRANSPLANTED is retired as such, and a driver's REQUEST is drained through lr-fleet.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  POLLER="$REPO/scripts/limit-recover/lr-reset-poller.sh"
  export HOME="$BATS_TEST_TMPDIR/home"
  STATE="$HOME/.reso/limit-recover"
  mkdir -p "$HOME/bin" "$STATE/parked" "$STATE/resumed" "$STATE/locks" "$BATS_TEST_TMPDIR/stubs" "$BATS_TEST_TMPDIR/cwd"
  CWD="$BATS_TEST_TMPDIR/cwd"
  unset KITTY_WINDOW_ID CC_TERM_KITTY_TO
  export IT2_WRAPPER_NO_KITTY=1
  export CC_REGISTRY_DIR="$BATS_TEST_TMPDIR/reg"; mkdir -p "$CC_REGISTRY_DIR"
  export CC_KITTY_SOCKET_BIN="$BATS_TEST_TMPDIR/no-kitty-socket"     # no live kitty unless a case says so
  export LR_POLLER_LAUNCH_DIR="$BATS_TEST_TMPDIR/launchers"; mkdir -p "$LR_POLLER_LAUNCH_DIR"
  export LR_NUDGE_ENGAGE_S=2 LR_NUDGE_IVL=1
  cat > "$BATS_TEST_TMPDIR/stubs/osascript" <<'STUB'
printf '%s\n' "$*" >> "${OSA_LOG:?}"; exit 1
STUB
  cat > "$BATS_TEST_TMPDIR/stubs/tmux" <<'STUB'
printf '%s\n' "$*" >> "${TMUX_LOG:?}"; exit 0
STUB
  # SEAL THE ARGV CENSUS — the one seam in this suite that read the REAL process table (2026-09-20).
  # `pgrep -f "resume <sid>"` is consulted TWICE per tick, from two different programs, and neither
  # was fixtured: lr-reset-poller.sh:1139,1281 call it bare, and lr-select.py's is_running() runs
  # os.environ["LR_SELECT_PGREP_BIN"] defaulting to bare `pgrep`. Both resolve through PATH, so ONE
  # stub here seals the class rather than either spelling of it. Unsealed, any process anywhere on
  # the box whose argv holds `resume <SID>` answers YES and the poller retires the fixture's record
  # before the case's own assertion is reached — lr-select filters it `already-running`, the tick
  # logs `CONSOLIDATED 1 ready → 0 winner(s)`, and the failure surfaces as a missing NO-GUI/tmux
  # line, naming a DIFFERENT set of cases on every run (measured in ship-land: one run named the
  # TRANSPLANTED case, the next named both D2 cases, while the same suite ran green locally in BOTH
  # A/B arms of the diff in flight). Two arms of the class, one PATH entry (memory:
  # denylist-enumerates-spellings-not-the-class).
  #
  # rc 1 = "no process holds this sid", which is the state every case here means and the state the
  # real pgrep happened to return on a quiet box. LR_TEST_PGREP_RC makes the other arm reachable on
  # purpose — it was never testable before, because the only way to drive it was to have a real
  # process outside the fixture. The log is the seal's own liveness control: a case can assert the
  # census was CONSULTED, so this stub cannot rot into decoration if the call site moves.
  #
  # `ps -axo command=` (lr-lib.sh:493,673) is the other real-table census in this tree and is
  # deliberately NOT stubbed: probed 2026-09-21 with a matching line carrying a LIVE pid (pid 1 — a
  # dead pid is a blind instrument here, since the census filters on kill -0), the suite stayed
  # 19/19. It is not on any path these cases assert over. Re-probe rather than re-quote that.
  # THE SHEBANG IS LOAD-BEARING, and it is why this stub is not written like its two neighbours
  # above. A shebang-less file is executable by BASH, which falls back to running it as a script —
  # which is all the osascript/tmux stubs ever needed, since only bash invokes those. CPython does
  # not: execve returns ENOEXEC and subprocess treats that like "not executable here" and KEEPS
  # WALKING PATH, landing on /usr/bin/pgrep. So a shebang-less stub seals the bash arm, leaves the
  # python arm reading the real process table, and looks sealed — measured here on 2026-09-21, the
  # log carried exactly one line and it said `caller=bash`. Note the instrument trap on the way:
  # probing this with a pattern that matches nothing cannot see it, because the stub and the real
  # pgrep BOTH return 1 (memory: uniform-error-ratio-indicts-the-model — control the instrument).
  cat > "$BATS_TEST_TMPDIR/stubs/pgrep" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >> "${PGREP_LOG:?}"; exit "${LR_TEST_PGREP_RC:-1}"
STUB
  chmod +x "$BATS_TEST_TMPDIR/stubs/osascript" "$BATS_TEST_TMPDIR/stubs/tmux" "$BATS_TEST_TMPDIR/stubs/pgrep"
  # Belt and braces: lr-select.py documents LR_SELECT_PGREP_BIN as its test seam (its own § Env
  # (tests)). Naming the stub by ABSOLUTE PATH does not depend on PATH order surviving whatever the
  # poller, or a future wrapper between them, does to the environment.
  export LR_SELECT_PGREP_BIN="$BATS_TEST_TMPDIR/stubs/pgrep"
  export OSA_LOG="$BATS_TEST_TMPDIR/osa.log" TMUX_LOG="$BATS_TEST_TMPDIR/tmux.log"; : > "$OSA_LOG"; : > "$TMUX_LOG"
  export PGREP_LOG="$BATS_TEST_TMPDIR/pgrep.log"; : > "$PGREP_LOG"
  export PATH="$BATS_TEST_TMPDIR/stubs:$PATH"
  cat > "$HOME/bin/claude-accounts" <<'STUB'
echo '{"rows":[{"acct":"next4","session_pct":12,"weekly_pct":40}]}'
STUB
  chmod +x "$HOME/bin/claude-accounts"
  # the it2 shim seam: records the nudge; when IT2_ENGAGE=1 it appends a fresh assistant turn to the
  # transcript, which is exactly what a real nudge produces and what the oracle looks for
  export LR_IT2_BIN="$BATS_TEST_TMPDIR/stubs/it2"
  cat > "$LR_IT2_BIN" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >> "${IT2_LOG:?}"
if [ "${IT2_ENGAGE:-0}" = 1 ]; then
  sleep 1
  printf '{"type":"assistant","timestamp":"%s","message":{"role":"assistant","model":"claude-opus-5","content":[{"type":"text","text":"resumed"}]}}\n' \
    "$(date -u -v+5S +%FT%T.000Z 2>/dev/null || date -u +%FT%T.000Z)" >> "${IT2_TX:?}"
fi
exit "${IT2_RC:-0}"
STUB
  chmod +x "$LR_IT2_BIN"; export IT2_LOG="$BATS_TEST_TMPDIR/it2.log"; : > "$IT2_LOG"
}
SLUG() { printf '%s' "$1" | tr '/' '-'; }
mk_parked() { # $1=sid [$2=model $3=effort]
  local sid="$1" proj ts
  proj="$HOME/.claude-quaternary/projects/$(SLUG "$CWD")"; mkdir -p "$proj"
  ts="$(python3 -c "from datetime import datetime,timezone;print(datetime.now(timezone.utc).isoformat().replace('+00:00','Z'))")"
  {
    printf '{"type":"user","cwd":"%s","gitBranch":"main","timestamp":"%s"}\n' "$CWD" "$ts"
    if [ -n "${2:-}" ]; then printf '{"type":"assistant","timestamp":"%s","effort":"%s","message":{"role":"assistant","model":"%s","content":[{"type":"text","text":"work"}]}}\n' "$ts" "$3" "$2"; else printf '{"type":"assistant","timestamp":"%s"}\n' "$ts"; fi
    printf '{"type":"assistant","timestamp":"%s","isApiErrorMessage":true,"message":{"role":"assistant","content":[{"type":"text","text":"You'"'"'ve hit your session limit"}]}}\n' "$ts"
  } > "$proj/$sid.jsonl"
  export IT2_TX="$proj/$sid.jsonl"
  printf '{"sid":"%s","acct":"next4","cfg":"%s","cwd":"%s","kind":"session","reset_at_utc":"2026-01-01T00:00:00Z","parked_at":"2026-01-01T00:00:00Z"}\n' \
    "$sid" "$HOME/.claude-quaternary" "$CWD" > "$STATE/parked/$sid.json"
}
row() { printf '{"paneUUID":"%s","session_id":"%s","pid":%d,"account":"claude-quaternary","cwd":"%s"}\n' "$1" "$2" "${3:-$$}" "$CWD" > "$CC_REGISTRY_DIR/$1.json"; }
# The incident sid, with a ZEROED tail. The full 2026-09-09 uuid is LIVE on this box (a tmux
# `claude --resume <that uuid>` has been running since 00:51Z), and both liveness censuses under
# test — lr-select's `pgrep -f "resume <sid>"` and lr-lib's `ps -axo command=` / `--resume <sid>`
# — read the REAL process table, so the fixture's own registry row stopped being the only voice:
# --locate said DUPLICATE where the case pins RECOVERABLE, and the poller retired the record before
# it could nudge. A fixture may never name an identifier that can exist outside it (memory:
# hermetic-in-stubs-not-in-interpreter). The `52e35019` prefix is kept — it is what the display
# assertions match on, and it is how this suite stays legible against the incident it was written from.
  SID="52e35019-17e8-40f6-a54f-000000000000"

@test "D1: the original pane is ALIVE → the poller NUDGES it in place; nothing is spawned; the record retires as handled" {
  mk_parked "$SID"; row 616 "$SID"
  IT2_ENGAGE=1 LR_POLLER_AUTOFIRE=1 run bash "$POLLER" --once
  [ "$status" -eq 0 ] || { echo "$output"; cat "$STATE/poller.log"; false; }
  grep -q 'session run -s 616 /limit-recover' "$IT2_LOG"
  grep -qE "NUDGED $SID in pane 616 \(in place on claude-quaternary, pid $$\) — engaged" "$STATE/poller.log" || { cat "$STATE/poller.log"; false; }
  [ ! -s "$TMUX_LOG" ]; [ ! -s "$OSA_LOG" ]
  [ -z "$(ls "$LR_POLLER_LAUNCH_DIR" 2>/dev/null)" ]                 # no launcher minted ⇒ no second process
  [ -f "$STATE/resumed/$SID.json" ]
}
@test "D1: a nudge that does NOT engage leaves the record PARKED and still spawns nothing over the live process" {
  mk_parked "$SID"; row 616 "$SID"
  IT2_ENGAGE=0 LR_POLLER_AUTOFIRE=1 run bash "$POLLER" --once
  [ "$status" -eq 0 ]
  grep -qE "NUDGE-FAILED $SID" "$STATE/poller.log" || { cat "$STATE/poller.log"; false; }
  grep -qE "ERROR +$SID — nudge into the live pane failed; NOT spawning a duplicate" "$STATE/poller.log"
  [ -f "$STATE/parked/$SID.json" ]; [ ! -s "$TMUX_LOG" ]
  [ -z "$(ls "$LR_POLLER_LAUNCH_DIR" 2>/dev/null)" ]
}
@test "D1 CONTROL: a registry row whose pid is DEAD is a stale row — the poller proceeds to a spawn as before" {
  mk_parked "$SID"; row 616 "$SID" 4194105
  LR_POLLER_SPAWN=tmux LR_POLLER_AUTOFIRE=1 run bash "$POLLER" --once
  [ "$status" -eq 0 ]
  [ ! -s "$IT2_LOG" ]
  grep -q 'new-session' "$TMUX_LOG"
}
@test "D1: --dry-run with a live original says it WOULD nudge and types nothing" {
  mk_parked "$SID"; row 616 "$SID"
  LR_POLLER_AUTOFIRE=1 run bash "$POLLER" --once --dry-run
  grep -qE "LIVE +$SID — original pane 616 is alive \(pid $$\); would NUDGE in place, never spawn \(dry-run\)" "$STATE/poller.log" || { cat "$STATE/poller.log"; false; }
  [ ! -s "$IT2_LOG" ]
}
@test "SELF: a tick reads no variable before assigning it — _LRP_SELF is set before the lr-lib ladder" {
  # 59e415e12 read _LRP_SELF at the lr-lib ladder and assigned it ~190 lines later. set -u killed
  # only the $(dirname …) subshell, so every tick exited 0 while printing the error and losing rung 1.
  mk_parked "$SID"
  LR_POLLER_AUTOFIRE=1 run bash "$POLLER" --once --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" != *"unbound variable"* ]] || { echo "$output"; false; }
}
@test "SYMLINKED STORE: a limited session under a symlinked <cfg>/projects (the real .claude-next) is detected and parked" {
  # ~/.claude-next/projects -> ~/.claude/projects on this box. Without find -H the detect pass listed
  # 0 transcripts there, so no `next` session was ever parked (poller.log: 0 next, 63 other).
  local sid real ts
  sid="0f0f0f0f-0000-4000-8000-00000000abcd"
  real="$HOME/.claude/projects/$(SLUG "$CWD")"
  mkdir -p "$real" "$HOME/.claude-next"; ln -s "$HOME/.claude/projects" "$HOME/.claude-next/projects"
  ts="$(python3 -c "from datetime import datetime,timezone;print(datetime.now(timezone.utc).isoformat().replace('+00:00','Z'))")"
  {
    printf '{"type":"user","cwd":"%s","gitBranch":"main","timestamp":"%s","message":{"role":"user","content":"work"}}\n' "$CWD" "$ts"
    printf '{"type":"assistant","uuid":"u2","sessionId":"%s","timestamp":"%s","error":"rate_limit","apiErrorStatus":429,"isApiErrorMessage":true,"message":{"id":"m2","type":"message","role":"assistant","model":"<synthetic>","content":[{"type":"text","text":"You'"'"'ve hit your session limit · resets 11:40am (America/Chicago)"}]}}\n' "$sid" "$ts"
  } > "$real/$sid.jsonl"
  LR_POLLER_AUTOFIRE=1 run bash "$POLLER" --once --dry-run
  [ "$status" -eq 0 ]
  grep -qE "PARKED $sid \(next, session\)" "$STATE/poller.log" || { echo "$output"; cat "$STATE/poller.log"; false; }
}

# ── the transplant fixture, split in two (W5-A, 2026-09-20) ────────────────────────────────────
# This case used to end at the lock: a tombstone/lock naming another store retired the record, full
# stop. W5-A gates the retire on the SUCCESSOR being real, because the move and the recovery are two
# different facts and the record is the only thing that re-fires the second one. `mk_transplanted`
# builds the move; each case then supplies — or withholds — the successor evidence.
mk_transplanted() { # → sets $other
  other="$HOME/.claude-tertiary"; mkdir -p "$other/projects/x"; : > "$other/projects/x/$SID.jsonl"
  printf '{"sid":"%s","from":"%s","to":"%s"}\n' "$SID" "$HOME/.claude-quaternary" "$other" > "$STATE/locks/$SID.lock"
}
row_on() { # $1=pane $2=sid $3=account — the `row` helper above is hardwired to claude-quaternary
  printf '{"paneUUID":"%s","session_id":"%s","pid":%d,"account":"%s","cwd":"%s"}\n' \
    "$1" "$2" "$$" "$3" "$CWD" > "$CC_REGISTRY_DIR/$1.json"
}

@test "TRANSPLANTED: a lock to ANOTHER store + a LIVE row there retires the record, nothing fired" {
  mk_parked "$SID"; mk_transplanted
  row_on 701 "$SID" claude-tertiary            # the successor is a PROCESS, not a claim
  LR_POLLER_SPAWN=tmux LR_POLLER_AUTOFIRE=1 run bash "$POLLER" --once
  [ "$status" -eq 0 ]
  grep -qE "TRANSPLANTED $SID \(next4\) → $other; parked record retired" "$STATE/poller.log" || { cat "$STATE/poller.log"; false; }
  [ -f "$STATE/resumed/$SID.json" ]; [ ! -s "$TMUX_LOG" ]
}

@test "TRANSPLANTED CONTROL: the move alone does NOT retire — no successor evidence ⇒ LEFT PARKED" {
  # The defect W5-A closes: the `mv` was unconditional on the transplant READ, and the HUSK branch
  # logged HUSK and then fell through to it — the poller retired the very records its own log said
  # it was not retiring. A tombstone says the session MOVED; nothing here says it came up.
  mk_parked "$SID"; mk_transplanted
  LR_POLLER_SPAWN=tmux LR_POLLER_AUTOFIRE=1 run bash "$POLLER" --once
  [ "$status" -eq 0 ]
  grep -qE "HUSK $SID \(run .* state .*\) — moved to $other but the successor has neither RECOVERED nor a live row there; record LEFT PARKED" "$STATE/poller.log" \
    || { cat "$STATE/poller.log"; false; }
  [ -f "$STATE/parked/$SID.json" ]; [ ! -f "$STATE/resumed/$SID.json" ]; [ ! -s "$TMUX_LOG" ]
}

@test "TRANSPLANTED: a run whose own state log reads RECOVERED retires WITHOUT any registry row" {
  # lr_state_current's FIRST production caller in the tree. Leg (1) of the gate, on its own.
  mk_parked "$SID"; mk_transplanted
  mkdir -p "$STATE/$SID/bundle-20260920T000000Z"
  printf '{"ts":"x","run":"r","state":"RECOVERED","stage":"s","detail":"d","writer":"w","attempt":1}\n' \
    > "$STATE/$SID/bundle-20260920T000000Z/events.jsonl"
  LR_POLLER_SPAWN=tmux LR_POLLER_AUTOFIRE=1 run bash "$POLLER" --once
  grep -qE "TRANSPLANTED $SID \(next4\) → $other; parked record retired \(the successor carries it: RECOVERED\)" "$STATE/poller.log" \
    || { cat "$STATE/poller.log"; false; }
  [ -f "$STATE/resumed/$SID.json" ]
}

@test "TRANSPLANTED CONTROL: a NON-RECOVERED state log is not a recovery — the newest bundle wins" {
  # The same leg, the other way round: without this the case above passes for a predicate that
  # merely checks that events.jsonl EXISTS. `relaunch-typed` is a real value from the live store.
  mk_parked "$SID"; mk_transplanted
  mkdir -p "$STATE/$SID/bundle-20260919T000000Z" "$STATE/$SID/bundle-20260920T000000Z"
  printf '{"ts":"x","run":"r","state":"RECOVERED","stage":"s","detail":"d","writer":"w","attempt":1}\n' \
    > "$STATE/$SID/bundle-20260919T000000Z/events.jsonl"
  printf '{"ts":"x","run":"r","state":"relaunch-typed","stage":"s","detail":"d","writer":"w","attempt":1}\n' \
    > "$STATE/$SID/bundle-20260920T000000Z/events.jsonl"
  LR_POLLER_SPAWN=tmux LR_POLLER_AUTOFIRE=1 run bash "$POLLER" --once
  grep -q "state relaunch-typed" "$STATE/poller.log" || { cat "$STATE/poller.log"; false; }
  [ -f "$STATE/parked/$SID.json" ]; [ ! -f "$STATE/resumed/$SID.json" ]
}

@test "TRANSPLANTED CONTROL: a live row on the SOURCE account is the HUSK, never the successor" {
  # Why lr_registry_live_rows (sid only) cannot serve this gate: the same yes means the opposite
  # thing depending on WHICH store answered, and the source-side yes is the state W10 exists for.
  mk_parked "$SID"; mk_transplanted
  row_on 616 "$SID" claude-quaternary
  LR_POLLER_SPAWN=tmux LR_POLLER_AUTOFIRE=1 run bash "$POLLER" --once
  grep -q "record LEFT PARKED" "$STATE/poller.log" || { cat "$STATE/poller.log"; false; }
  [ ! -f "$STATE/resumed/$SID.json" ]
}

@test "TRANSPLANTED: the LEFT-PARKED line is said ONCE per record, not once per tick" {
  # This arm is reached on every tick for as long as the record sits here. 1,800 identical lines is
  # a shape this daemon has already produced once (§ the fire-failure latch).
  mk_parked "$SID"; mk_transplanted
  LR_POLLER_SPAWN=tmux LR_POLLER_AUTOFIRE=1 run bash "$POLLER" --once
  LR_POLLER_SPAWN=tmux LR_POLLER_AUTOFIRE=1 run bash "$POLLER" --once
  [ "$(grep -c 'record LEFT PARKED' "$STATE/poller.log")" = 1 ] || { cat "$STATE/poller.log"; false; }
}

@test "D2: auto with no reachable GUI is NOT SPAWNED and loud — tmux is never reached for" {
  mk_parked "$SID"
  LR_POLLER_AUTOFIRE=1 run bash "$POLLER" --once
  [ "$status" -eq 0 ]
  grep -qE "NO-GUI +$SID — no reachable kitty/iTerm2; NOT spawned" "$STATE/poller.log" || { cat "$STATE/poller.log"; false; }
  [ ! -s "$TMUX_LOG" ]; [ -f "$STATE/parked/$SID.json" ]
}
@test "D2 CONTROL: LR_POLLER_SPAWN=tmux is an EXPLICIT choice and still works" {
  mk_parked "$SID"
  LR_POLLER_SPAWN=tmux LR_POLLER_AUTOFIRE=1 run bash "$POLLER" --once
  grep -q 'new-session' "$TMUX_LOG"; [ -f "$STATE/resumed/$SID.json" ]
}
@test "D2: a kitty reachable by SOCKET (no \$KITTY_WINDOW_ID — the launchd case) gets a VISIBLE, RUNNER-rooted window" {
  mk_parked "$SID"
  unset IT2_WRAPPER_NO_KITTY
  cat > "$BATS_TEST_TMPDIR/stubs/kitty-sock" <<'STUB'
#!/bin/bash
echo unix:/tmp/fake-kitty-1
STUB
  chmod +x "$BATS_TEST_TMPDIR/stubs/kitty-sock"; export CC_KITTY_SOCKET_BIN="$BATS_TEST_TMPDIR/stubs/kitty-sock"
  cat > "$BATS_TEST_TMPDIR/stubs/kitty" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >> "${KITTY_LOG:?}"; echo 901
STUB
  chmod +x "$BATS_TEST_TMPDIR/stubs/kitty"; export CC_TERM_KITTY="$BATS_TEST_TMPDIR/stubs/kitty" KITTY_LOG="$BATS_TEST_TMPDIR/kitty.log"; : > "$KITTY_LOG"
  LR_POLLER_AUTOFIRE=1 run bash "$POLLER" --once
  [ "$status" -eq 0 ] || { echo "$output"; cat "$STATE/poller.log"; false; }
  grep -q -- '@ --to unix:/tmp/fake-kitty-1 launch --type=os-window' "$KITTY_LOG" || { cat "$KITTY_LOG"; false; }
  grep -q -- 'CC_PANE_CMD=bash .*lr-poller-launch-52e35019-' "$KITTY_LOG"
  ! grep -q -- '-- /bin/bash' "$KITTY_LOG" || false
  [ ! -s "$TMUX_LOG" ]
  grep -qE "RESUMED $SID on next4 \(autofire, gui\)" "$STATE/poller.log"
}

@test "D3: the minted launcher carries the transcript's tier (--model/--effort)" {
  mk_parked "$SID" claude-fable-5-1 xhigh
  LR_POLLER_SPAWN=tmux LR_POLLER_AUTOFIRE=1 run bash "$POLLER" --once
  # shellcheck disable=SC2012  # a single mktemp-minted launcher in a fixture dir — find(1) buys nothing here
  l="$(ls "$LR_POLLER_LAUNCH_DIR"/lr-poller-launch-52e35019-*.sh | head -1)"
  grep -q -- '--model claude-fable-5-1 --effort xhigh --prompt /limit-recover' "$l" || { cat "$l"; false; }
}
@test "D3 CONTROL: no tier on disk ⇒ no flags, the old launcher byte-for-byte" {
  mk_parked "$SID"
  LR_POLLER_SPAWN=tmux LR_POLLER_AUTOFIRE=1 run bash "$POLLER" --once
  # shellcheck disable=SC2012  # a single mktemp-minted launcher in a fixture dir — find(1) buys nothing here
  l="$(ls "$LR_POLLER_LAUNCH_DIR"/lr-poller-launch-52e35019-*.sh | head -1)"
  grep -q -- "$SID --prompt /limit-recover" "$l" || { cat "$l"; false; }
  ! grep -q -- '--model' "$l"
}

@test "REQUESTS: a driver's request is drained through lr-fleet --one, the result recorded, the request MOVED to claimed/" {
  # W5-A extended this case in two places rather than replacing it. (a) the drain is now DETACHED —
  # `--one` is a 115-658 s call and was held inside the tick lock; (b) the request is MOVED, not
  # `rm -f`'d, because a consumed request that reached nobody is indistinguishable from one that was
  # never written. The original assertion — that requests/ no longer holds it — is kept verbatim and
  # joined by the one that says where it went.
  mkdir -p "$STATE/requests"
  printf '{"sid":"%s","target":"next3","source_pane":"616","requested_by":"driver-abc","ts":"x"}\n' "$SID" > "$STATE/requests/$SID.json"
  export LR_FLEET_BIN="$BATS_TEST_TMPDIR/stubs/lr-fleet"
  cat > "$LR_FLEET_BIN" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >> "${FLEET_LOG:?}"; echo "fleet ran"; exit 0
STUB
  chmod +x "$LR_FLEET_BIN"; export FLEET_LOG="$BATS_TEST_TMPDIR/fleet.log"; : > "$FLEET_LOG"
  LR_POLLER_AUTOFIRE=1 run bash "$POLLER" --once
  [ "$status" -eq 0 ]
  grep -q -- "--one $SID --target next3 --source-pane 616 --from-daemon --detach" "$FLEET_LOG" || { cat "$FLEET_LOG"; false; }
  [ ! -f "$STATE/requests/$SID.json" ]
  [ -f "$STATE/claimed/$SID.json" ] || { ls -la "$STATE/claimed" 2>&1; false; }
  python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["rc"]==0 and d["requested_by"]=="driver-abc", d' "$STATE/results/$SID.json"
  grep -qE "REQUEST $SID — dispatched rc=0" "$STATE/poller.log"
}
@test "REQUESTS: --dry-run only reports the request; it is not executed" {
  mkdir -p "$STATE/requests"
  printf '{"sid":"%s","target":"next3"}\n' "$SID" > "$STATE/requests/$SID.json"
  export LR_FLEET_BIN="$BATS_TEST_TMPDIR/stubs/lr-fleet"; printf '#!/bin/bash\nexit 0\n' > "$LR_FLEET_BIN"; chmod +x "$LR_FLEET_BIN"
  LR_POLLER_AUTOFIRE=1 run bash "$POLLER" --once --dry-run
  [ -f "$STATE/requests/$SID.json" ]
  grep -qE "DRY +request $SID.json would be executed" "$STATE/poller.log"
}

# ── HERMETICITY: the argv census may not read the real machine (2026-09-20) ────────────────────
# The seal itself, proven both ways. These two cases are the reason setup() stubs `pgrep`, and they
# are written so that deleting that stub reddens them — a fixture nobody tests is a fixture that
# rots back out (memory: control-rots-silently).
teardown() {
  local p
  [ -f "${BATS_TEST_TMPDIR:-}/decoy.pid" ] || return 0
  p="$(cat "$BATS_TEST_TMPDIR/decoy.pid" 2>/dev/null)"
  case "$p" in ''|*[!0-9]*) return 0 ;; esac
  # NEVER signal a bare recorded pid. Pids are REISSUED, so a decoy that has already exited leaves
  # this holding a number the kernel may since have handed to a bystander — the refusal reads as
  # honoured while pointing at the wrong process (memory: a-stale-pid-does-not-decay-into-
  # harmlessness-it-decays-into-a-gu). Confirm the process is still OURS by its argv first.
  /bin/ps -o command= -p "$p" 2>/dev/null | grep -q -- "$SID" || return 0
  # `|| true` is mandatory, not defensive: under bats' errexit a kill on an exited-AND-REAPED child
  # returns 1 and aborts the body, a window that only opens under LOAD (scripts/bats-kill-guard-lint.sh).
  kill "$p" 2>/dev/null || true
  return 0
}

@test "HERMETIC: a REAL live process carrying --resume <SID> cannot reach this suite's verdict" {
  # THE RED PROOF. Without the setup() stub this case fails exactly as ship-land did: the live
  # decoy answers `pgrep -f "resume <sid>"`, lr-select filters the candidate `already-running`, the
  # tick logs `CONSOLIDATED 1 ready → 0 winner(s)` and retires the record — so the D2 verdict below
  # is never written. The decoy is a stand-in for whatever the real fleet happened to be running;
  # the point is that NO process outside this fixture may vote.
  mk_parked "$SID"
  printf '#!/bin/bash\nsleep "$1"\n' > "$BATS_TEST_TMPDIR/decoy.sh"; chmod +x "$BATS_TEST_TMPDIR/decoy.sh"
  bash "$BATS_TEST_TMPDIR/decoy.sh" 30 --resume "$SID" & echo $! > "$BATS_TEST_TMPDIR/decoy.pid"
  # POSITIVE CONTROL, via the REAL pgrep by absolute path: assert the decoy is genuinely visible to
  # an unsealed census AT THE MOMENT OF THE READING. Without this the case passes on a box where the
  # decoy never came up, certifying a seal it never loaded (memory: a-cure-is-verified-only-under-
  # the-load-that-caused-it).
  local i=0
  until /usr/bin/pgrep -f "resume $SID" >/dev/null 2>&1; do
    i=$((i + 1)); [ "$i" -lt 50 ] || { echo "decoy never became visible to the real pgrep"; false; }
    sleep 0.1
  done
  LR_POLLER_AUTOFIRE=1 run bash "$POLLER" --once
  [ "$status" -eq 0 ]
  grep -qE "NO-GUI +$SID — no reachable kitty/iTerm2; NOT spawned" "$STATE/poller.log" || { cat "$STATE/poller.log"; false; }
  ! grep -q 'CONSOLIDATED' "$STATE/poller.log" || { cat "$STATE/poller.log"; false; }
  [ -f "$STATE/parked/$SID.json" ]
}

@test "HERMETIC CONTROL: the sealed census is LOAD-BEARING — rc 0 still retires the record" {
  # The mutation control for the case above. If the stub were never consulted — the call site moved,
  # or a future edit dropped the PATH entry — forcing a match would change nothing and the seal would
  # be decoration that certifies itself. Driving the other arm is also new capability: before the
  # stub, `already-running` could only be reached by having a real process outside the fixture, which
  # is precisely what made this suite non-hermetic in the first place.
  mk_parked "$SID"
  LR_TEST_PGREP_RC=0 LR_POLLER_AUTOFIRE=1 run bash "$POLLER" --once
  [ "$status" -eq 0 ]
  [ -s "$PGREP_LOG" ] || { echo "the argv census was never consulted — the seal is decoration"; false; }
  grep -q -- "resume $SID" "$PGREP_LOG" || { cat "$PGREP_LOG"; false; }
  # This line is what reddens if the stub ever loses its shebang. `already-running` is lr-select's
  # own word, written to ITS OWN triage file — only the PYTHON arm can put it there — so it proves
  # the seam reached the caller that a shebang-less stub silently leaks past. The bash arm is
  # already covered by the log assertion above. It is asserted HERE and not in poller.log because
  # the poller's own arm (:1281) also matches under rc 0 and retires the record first, so the
  # LISTED line never gets written — the verdict is real, the place it surfaces is not poller.log.
  grep -q "already-running" "$STATE/last-triage.txt" || { cat "$STATE/last-triage.txt"; false; }
  [ ! -f "$STATE/parked/$SID.json" ]; [ ! -s "$TMUX_LOG" ]
}
