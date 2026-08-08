#!/usr/bin/env bats
# teammate-auto-shutdown.sh — the TeammateIdle auto-close hook. These bats RED-proof the two 2026-07-24
# safety guards added after cc-reaper closed live operator conversations (docs/research/
# session-crash-forensics-2026-07-23.md § addendum):
#   (1) FAIL-CLOSED on an unresolved WORKTREE — a close with ZERO safety gates evaluated must be
#       impossible; defer on the same counter, then SURFACE (page) rather than close ungated.
#   (2) OPERATOR-ADOPTION hold — a pane a human typed a REAL prompt into (newer than spawn+slack,
#       within the hold window) is never force-closed; surface + page instead.
# The WHO-primitive ci_last_interactive_epoch lands separately in hooks/lib/cc-interactive.sh; a tiny
# STUB is written here (setup) so these tests are independent of landing order. All I/O is hermetic:
# HOME + CLAUDE_CONFIG_DIR + PROJECT_ROOTS + it2/tmux/cc-notify/cc-sessions are redirected under a temp
# dir, so nothing touches the real fleet.

setup() {
  # M11 (MACHINE_CAPACITY_V2 §11.3) — a test's environment is PINNED, not ambient. handoff-fire.sh's
  # capacity_gate reads the box's live loadavg AND (M10) its memory headroom, exiting 9 when either is
  # past its bar, so an unpinned suite goes RED purely because the box is busy — the corpus deciding a
  # verdict on machine state instead of on the tree. Both terms are pinned off here (they are the two
  # TERMS of one exit 9, handoff-fire.sh:4487); tests/handoff-fire-capacity-gate.bats is the ONE place
  # the gate runs ON, against synthetic inputs.
  export CC_FIRE_CAPACITY_GATE=off
  export CC_FIRE_HEADROOM_GATE=off
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  H="$REPO/hooks/teammate-auto-shutdown.sh"
  D="$BATS_TEST_TMPDIR"
  NOW=1000000000
  export HOME="$D/home"
  export CLAUDE_CONFIG_DIR="$HOME/.claude"
  mkdir -p "$HOME/.claude/logs" "$HOME/.claude/watchdog" "$HOME/.claude/teams" "$D/bin" "$D/proj/slug"
  export PATH="$D/bin:$PATH"
  export CC_CLASSIFY_PROJECT_ROOTS="$D/proj"
  export CC_CLASSIFY_NOW="$NOW"
  export CC_CLASSIFY_INTERACTIVE_HOLD_S=21600
  export CC_CLASSIFY_FIRE_PROMPT_SLACK_S=300
  export CC_INTERACTIVE_LIB="$D/cc-interactive-stub.sh"
  export CC_NOTIFY_BIN="$D/bin/cc-notify"
  export TEAMMATE_CHECKPOINT_DISABLED=1   # the checkpoint is not a gate; skip its git plumbing in tests
  export TEAMMATE_CLOSE_GRACE_S=0         # detached pane close fires immediately (no 3s wait)
  LOGF="$HOME/.claude/logs/teammate-lifecycle.log"

  # ── PATH shims (each records its calls to a baked-in absolute path) ──
  cat > "$D/bin/it2" <<EOF
#!/bin/bash
echo "it2 \$*" >> "$D/it2-calls.log"
exit 0
EOF
  cat > "$D/bin/tmux" <<EOF
#!/bin/bash
echo "tmux \$*" >> "$D/tmux-calls.log"
exit 0
EOF
  cat > "$D/bin/cc-notify" <<EOF
#!/bin/bash
echo "cc-notify \$*" >> "$D/notify-calls.log"
exit 0
EOF
  cat > "$D/bin/cc-sessions" <<EOF
#!/bin/bash
[ -s "$D/sessions.json" ] && cat "$D/sessions.json" || echo '[]'
EOF
  chmod +x "$D/bin/it2" "$D/bin/tmux" "$D/bin/cc-notify" "$D/bin/cc-sessions"

  # ── the shared-lib STUB (real hooks/lib/cc-interactive.sh lands separately) ──
  # A SHIM onto the REAL hooks/lib/cc-interactive.sh — never a re-implementation. This was a hand-rolled
  # COPY of the predicate until 2026-07-29, which is fixture drift by construction: the lib grew the
  # image-only-paste leg, the whole-file fallback and then the THREE-VALUED "unreadable" answer while the
  # copy stayed two-valued, so a test of the hold's fail-closed branch would have been green against a
  # predicate that no longer exists (memory: fixture-vs-real needs a producer).
  printf '#!/usr/bin/env bash\n. "%s"\n' "$REPO/hooks/lib/cc-interactive.sh" > "$D/cc-interactive-stub.sh"
}

# ── fixtures ─────────────────────────────────────────────────────────────────────────────────────
iso() { TZ=UTC date -j -f %s "$((NOW-$1))" +%Y-%m-%dT%H:%M:%S 2>/dev/null; }   # <ago> → UTC iso (no Z)
mkinput() { printf '{"teammate_name":"%s","team_name":"%s","session_id":"%s","cwd":"%s"}' "$1" "$2" "$3" "$4"; }
hookrun()  { printf '%s' "$(mkinput "$1" "$2" "$3" "$4")" | "$H"; }            # pipe payload to the hook

# a last assistant turn <ago>s before NOW into <sid> (overwrites the transcript)
tx()  { printf '{"type":"assistant","timestamp":"%s.000Z","message":{"role":"assistant","content":[{"type":"text","text":"hi"}]}}\n' "$(iso "$2")" > "$D/proj/slug/$1.jsonl"; }
# a REAL operator-typed prompt <ago>s before NOW appended to <sid>
utx() { printf '{"type":"user","timestamp":"%s.000Z","message":{"role":"user","content":"%s"}}\n' "$(iso "$2")" "${3:-please do the thing}" >> "$D/proj/slug/$1.jsonl"; }
# register the teammate session in the mock registry with startedAt <spawn-ago>s before NOW; args: sid pane cwd spawn_ago
reg() { printf '[{"name":"t","paneUUID":"%s","account":"next","cwd":"%s","pid":%s,"session_id":"%s","startedAt":%s}]\n' \
          "$2" "$3" "$$" "$1" "$(( (NOW-$4)*1000 ))" > "$D/sessions.json"; }
# team config.json giving <member> a tmux pane id (so pane resolution finds a pane to close)
teamcfg() { mkdir -p "$HOME/.claude/teams/$1"; printf '{"members":[{"name":"%s","tmuxPaneId":"%s"}]}' "$2" "$3" > "$HOME/.claude/teams/$1/config.json"; }
# TSV member→worktree (so WORKTREE resolves); args: team member worktree
worktreetsv() { mkdir -p "$HOME/.claude/teams/$1"; printf '%s\t%s\n' "$2" "$3" > "$HOME/.claude/teams/$1/worktrees.tsv"; }
wait_for() { local i=0; while [ ! -e "$1" ] && [ "$i" -lt 60 ]; do sleep 0.05; i=$((i+1)); done; [ -e "$1" ]; }

# (i) unresolved WORKTREE → DEFER (no close), then SURFACE + page after MAX_DEFERS — never an ungated close
# ⚠ THE Nth EVENT ACTS — it does not defer an Nth time and wait for an (N+1)th.
# This test asserted the opposite until 2026-08-01 (MAX_DEFERS=2 ⇒ it expected the page on fire 3),
# and that expectation was the bug pinned as correct. An (N+1)th TeammateIdle is not guaranteed to
# exist: once the lead marks a member `isActive:false` the harness stops emitting the event, so a
# backstop that needs one more event than it is given never fires. Measured: 73 of 188 defer counters
# sat pinned at the cap, untouched >1h, with 0 follow-throughs — and vt-tests@session-a338777c held
# its pane and 653 MB for 3h09m after logging `defer (3/3)`. The header also says TeammateIdle fires
# "3-4x per teammate", so a cap of 3 needing a 4th fire is a coin flip by construction — which is
# exactly why some teammates closed cleanly and others never did.
@test "unresolved WORKTREE → defers, then the MAX_DEFERSth event itself SURFACEs + pages (never ungated close)" {
  export TEAMMATE_MAX_DEFERS=2
  local sid=sidU team=teamU member=wkrUnresolved
  tx "$sid" 9000                                    # idle transcript; NO worktree mapping ⇒ WORKTREE=""
  run hookrun "$member" "$team" "$sid" /nonexistent-cwd   # fire 1 → defer (1/2)
  [ "$status" -eq 0 ]
  [[ "$output" != *'"continue": false'* ]] || false
  [ ! -e "$D/notify-calls.log" ]
  run hookrun "$member" "$team" "$sid" /nonexistent-cwd   # fire 2 = MAX_DEFERS → SURFACE (page) NOW
  [ "$status" -eq 0 ]
  [[ "$output" != *'"continue": false'* ]] || false
  [ -e "$D/notify-calls.log" ]                      # desk paged — on the capping event, not the next
  grep -q "SURFACE" "$LOGF"
  [ ! -e "$D/tmux-calls.log" ]                       # and no pane was ever closed
}

# (ii) adopted teammate pane (real operator prompt 60s ago, spawn 1h ago) → HELD: no close, desk paged
@test "adopted pane (operator prompt 60s ago, spawn 1h ago) → HELD: no close, desk paged" {
  local sid=sidA team=teamA member=wkrAdopted pane=%77 wt="$D/wtA"
  mkdir -p "$wt"; worktreetsv "$team" "$member" "$wt"; teamcfg "$team" "$member" "$pane"
  reg "$sid" PANE-A "$wt" 3600                       # spawn 1h ago
  tx "$sid" 700; utx "$sid" 60                       # idle, but the operator typed 60s ago → ADOPTED
  run hookrun "$member" "$team" "$sid" "$wt"
  [ "$status" -eq 0 ]
  [[ "$output" != *'"continue": false'* ]] || false # NOT closed (no turn-stop emitted)
  [ -e "$D/notify-calls.log" ]                       # surfaced to the desk
  grep -q "operator-adopted" "$LOGF"
  sleep 0.3
  [ ! -e "$D/tmux-calls.log" ]                        # the detached close was never spawned
}

# (iii) unadopted finished teammate (no operator prompt) → closes as before (regression guard)
@test "unadopted finished teammate (no operator prompt) → closes as before (regression guard)" {
  local sid=sidF team=teamF member=wkrFinished pane=%88 wt="$D/wtF"
  mkdir -p "$wt"; worktreetsv "$team" "$member" "$wt"; teamcfg "$team" "$member" "$pane"
  reg "$sid" PANE-F "$wt" 3600
  tx "$sid" 9000                                     # idle, only assistant turns — no operator prompt
  run hookrun "$member" "$team" "$sid" "$wt"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"continue": false'* ]] || false  # close-decision emitted → proceeds to close
  [ ! -e "$D/notify-calls.log" ]                     # no adoption page
  wait_for "$D/tmux-calls.log"                        # detached close fired (grace=0)
  grep -q "kill-pane -t %88" "$D/tmux-calls.log"
}

# (iii-b) THIRD STATE (2026-07-29, C-SC-1) — the transcript EXISTS but cannot be read. Until the
# predicate became three-valued this answered exactly like test (iii)'s "no operator prompt", so an
# unreadable transcript licensed the force-close: absence of evidence read as evidence of absence on
# the actuator that kills the pane. reap-guard R-d fails closed on the same input, but the reap-guard
# call is gated on $WORKTREE — so for a worktree-less teammate this belt is the ONLY who-gate.
@test "third state: transcript CORRUPT (unreadable) → HELD, no close, desk paged" {
  local sid=sidU team=teamU member=wkrUnreadable pane=%99 wt="$D/wtU"
  mkdir -p "$wt"; worktreetsv "$team" "$member" "$wt"; teamcfg "$team" "$member" "$pane"
  reg "$sid" PANE-U "$wt" 3600
  printf 'not json at all\n\x00\x01binary garbage\n{"half":\n' > "$D/proj/slug/$sid.jsonl"
  run hookrun "$member" "$team" "$sid" "$wt"
  [ "$status" -eq 0 ]
  [[ "$output" != *'"continue": false'* ]] || false  # NOT closed
  [ -e "$D/notify-calls.log" ]                        # surfaced to the desk
  grep -q "UNREADABLE" "$LOGF"
  sleep 0.3
  [ ! -e "$D/tmux-calls.log" ]                        # the detached close was never spawned
}

# ── (vi) lib ABSENT — R3 parity with bin/cc-teardown §1c (2026-07-31) ────────────────────────────
# This arm used to assert the OPPOSITE: "lib absent → WARN + adoption skipped → close proceeds",
# with a fixture carrying a REAL operator prompt 60s old. It pinned the fail-open as correct on the
# actuator that CLOSES PANES — the identical pathology cc-teardown carried until its own R3 fix, and
# the reason a grep for the guard was misleading: a `type -t ci_last_interactive_epoch` guard was
# present the whole time, it just branched the wrong way. MEASURED before the fix, on the incident
# fixture (operator prompt 950s ago, idle 900s, landed, spawn 50000s ago, reap-guard absent so this
# belt is the only who-gate): lib present ⇒ held + paged; lib absent ⇒ `it2 session close -f -s
# PANE-INC`, a live operator conversation killed. The three arms below replace it — two refusals and
# a POSITIVE CONTROL, the same shape tests/cc-teardown.bats uses for the same fix.
_lib_absent_fixture() {  # <sid> <team> <member> <pane> → adopted-looking teammate, lib unresolvable
  export CC_INTERACTIVE_LIB="$D/no-such-lib.sh"      # absent — the deploy-lag shape
  mkdir -p "$D/wt_$1"; worktreetsv "$2" "$3" "$D/wt_$1"; teamcfg "$2" "$3" "$4"
  reg "$1" "PANE-$1" "$D/wt_$1" 3600
  tx "$1" 700; utx "$1" 60                            # a REAL operator prompt 60s ago
}

@test "lib ABSENT and NO beat system → HELD, no close, desk paged (never an ungated close)" {
  export CC_BEAT_DIR="$D/no-such-beats"
  _lib_absent_fixture sidV teamV wkrDegraded %99
  run hookrun wkrDegraded teamV sidV "$D/wt_sidV"
  [ "$status" -eq 0 ]
  [[ "$output" != *'"continue": false'* ]] || false  # the turn is NOT stopped
  grep -q "presence UNPROVABLE" "$LOGF"
  [ -e "$D/notify-calls.log" ]                       # surfaced to the desk
  sleep 0.3
  [ ! -e "$D/tmux-calls.log" ]                       # the detached close was never spawned
}

@test "lib ABSENT but the BEAT shows a RECENT operator prompt → HELD (independent oracle)" {
  export CC_BEAT_DIR="$D/beats"; mkdir -p "$CC_BEAT_DIR"
  export CC_BEAT_NOW="$NOW"
  _lib_absent_fixture sidW teamW wkrBeatFresh %98
  printf '{"sid":"sidW","t":%s,"who":"operator","operatorT":%s,"seq":1}\n' "$NOW" "$((NOW-60))" \
    > "$CC_BEAT_DIR/sidW.json"
  run hookrun wkrBeatFresh teamW sidW "$D/wt_sidW"
  [ "$status" -eq 0 ]
  [[ "$output" != *'"continue": false'* ]] || false
  [ -e "$D/notify-calls.log" ]
  sleep 0.3
  [ ! -e "$D/tmux-calls.log" ]
}

# Without this, the fix could ship as a PERMANENT teammate-close outage — every idle teammate held
# and the desk paged on each — and both arms above would still be green. cc-teardown RED-proved that
# exact amplifier (routing one extra world through its refusal turned 7 of 17 selftests into REFUSE).
@test "POSITIVE CONTROL: lib ABSENT but the BEAT proves presence is OLD → closes (hold is not inert)" {
  export CC_BEAT_DIR="$D/beats"; mkdir -p "$CC_BEAT_DIR"
  export CC_BEAT_NOW="$NOW"
  export CC_CLASSIFY_INTERACTIVE_HOLD_S=600
  _lib_absent_fixture sidX teamX wkrBeatOld %97
  # system IS live (fresh t), but the operator high-water mark is far older than the hold
  printf '{"sid":"sidX","t":%s,"who":"auto","operatorT":%s,"seq":9}\n' "$NOW" "$((NOW-99999))" \
    > "$CC_BEAT_DIR/sidX.json"
  run hookrun wkrBeatOld teamX sidX "$D/wt_sidX"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"continue": false'* ]] || false  # close proceeds on the independent oracle
  grep -q "presence proven ABSENT by beat" "$LOGF"
  wait_for "$D/tmux-calls.log"
}

# kill switch: CC_CLASSIFY_INTERACTIVE_HOLD_DISABLE=1 disables the hold → an adopted-looking pane closes
@test "CC_CLASSIFY_INTERACTIVE_HOLD_DISABLE=1 → adoption hold disabled, pane closes" {
  export CC_CLASSIFY_INTERACTIVE_HOLD_DISABLE=1
  local sid=sidK team=teamK member=wkrKill pane=%70 wt="$D/wtK"
  mkdir -p "$wt"; worktreetsv "$team" "$member" "$wt"; teamcfg "$team" "$member" "$pane"
  reg "$sid" PANE-K "$wt" 3600
  tx "$sid" 700; utx "$sid" 60                        # would be adopted, but the hold is disabled
  run hookrun "$member" "$team" "$sid" "$wt"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"continue": false'* ]] || false
  [ ! -e "$D/notify-calls.log" ]
  wait_for "$D/tmux-calls.log"
  grep -q "kill-pane -t %70" "$D/tmux-calls.log"
}

# the spawn brief is NOT adoption: a prompt within spawn+SLACK does not hold (worker GC proceeds)
@test "spawn brief is not adoption: a prompt within spawn+slack leaves the worker closeable" {
  local sid=sidB team=teamB member=wkrBrief pane=%60 wt="$D/wtB"
  mkdir -p "$wt"; worktreetsv "$team" "$member" "$wt"; teamcfg "$team" "$member" "$pane"
  reg "$sid" PANE-B "$wt" 3600                        # spawn 3600s ago
  tx "$sid" 3400; utx "$sid" 3500                     # only prompt is 3500s ago = spawn+100s (inside 300s slack)
  run hookrun "$member" "$team" "$sid" "$wt"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"continue": false'* ]] || false  # brief ≠ adoption → closes
  [ ! -e "$D/notify-calls.log" ]
  wait_for "$D/tmux-calls.log"
  grep -q "kill-pane -t %60" "$D/tmux-calls.log"
}

# ── teardown markers (2026-07-25) — an auto-shutdown must not read as a CRASH ─────────────────────
# lead-crash-watchdog is a SessionStart hook with NO matcher: it arms on EVERY session, teammates
# included. Closing a teammate's pane therefore kills a session whose own watchdog then runs the
# classify ladder — no close-record (C10-pending), no jetsam, and no self-close prose (this teammate
# never chose to close) — landing on CRASH. handoff-fire got its marker 2026-07-23 and cc-teardown
# 2026-07-25; this is the same class on the TeammateIdle closer.

@test "marker: a completed auto-shutdown writes the dual-keyed contract-v1 marker (sid + pane)" {
  local sid=sidM team=teamM member=wkrMarker pane=%55 wt="$D/wtM"
  mkdir -p "$wt"; worktreetsv "$team" "$member" "$wt"; teamcfg "$team" "$member" "$pane"
  reg "$sid" PANE-M "$wt" 3600
  tx "$sid" 9000                                      # idle, unadopted → closes
  run hookrun "$member" "$team" "$sid" "$wt"
  [ "$status" -eq 0 ]
  wait_for "$D/tmux-calls.log"
  TD="$HOME/.claude/watchdog/teardown"
  wait_for "$TD/$sid.json"
  [ -f "$TD/$sid.json" ]                              # keyed by the TEAMMATE's session id
  [ -f "$TD/$pane.json" ]                             # …and by the pane it closed
  run cat "$TD/$sid.json"
  [[ "$output" == *'"key_kind":"sid"'* ]] || false
  [[ "$output" == *"\"sid\":\"$sid\""* ]] || false
  [[ "$output" == *"\"pane\":\"$pane\""* ]] || false
  [[ "$output" == *'"mode":"teammate-idle"'* ]] || false # the discriminator vs handoff-fire / cc-teardown
  run cat "$TD/$pane.json"
  [[ "$output" == *'"key_kind":"pane"'* ]] || false
  run python3 -c "import json,sys; json.loads(open(sys.argv[1]).read().strip())" "$TD/$sid.json"
  [ "$status" -eq 0 ]
}

@test "marker: a HELD (operator-adopted) teammate gets NO marker — a live pane is never masked" {
  # The placement invariant: the marker goes in only once the close is inevitable. Writing it at any
  # earlier decision point would mask a genuine crash of a teammate we then chose to KEEP.
  local sid=sidN team=teamN member=wkrHeld pane=%56 wt="$D/wtN"
  mkdir -p "$wt"; worktreetsv "$team" "$member" "$wt"; teamcfg "$team" "$member" "$pane"
  reg "$sid" PANE-N "$wt" 3600
  tx "$sid" 700; utx "$sid" 60                        # operator typed 60s ago → ADOPTED → held
  run hookrun "$member" "$team" "$sid" "$wt"
  [ "$status" -eq 0 ]
  grep -q "operator-adopted" "$LOGF"
  sleep 0.3
  TD="$HOME/.claude/watchdog/teardown"
  [ ! -e "$TD" ] || [ -z "$(ls -A "$TD" 2>/dev/null)" ]
}

@test "marker: an unresolved-WORKTREE SURFACE gets NO marker (the ungated-close guard stays clean)" {
  export TEAMMATE_MAX_DEFERS=1
  local sid=sidO team=teamO member=wkrSurface
  tx "$sid" 9000
  hookrun "$member" "$team" "$sid" /nonexistent-cwd >/dev/null   # defer
  hookrun "$member" "$team" "$sid" /nonexistent-cwd >/dev/null   # SURFACE + page, no close
  grep -q "SURFACE" "$LOGF"
  sleep 0.3
  TD="$HOME/.claude/watchdog/teardown"
  [ ! -e "$TD" ] || [ -z "$(ls -A "$TD" 2>/dev/null)" ]
}

@test "marker: SESSION_ID literal \"unknown\" never becomes a marker filename (pane key only)" {
  # The hook parses session_id with a `// "unknown"` default. An unknown.json marker would mask a
  # genuine crash of whatever session the reader next asks about — it must never be written.
  local team=teamP member=wkrNoSid pane=%57 wt="$D/wtP"
  mkdir -p "$wt"; worktreetsv "$team" "$member" "$wt"; teamcfg "$team" "$member" "$pane"
  printf '{"teammate_name":"%s","team_name":"%s","cwd":"%s"}' "$member" "$team" "$wt" | "$H" >/dev/null
  wait_for "$D/tmux-calls.log"
  TD="$HOME/.claude/watchdog/teardown"
  wait_for "$TD/$pane.json"
  [ -f "$TD/$pane.json" ]                             # pane-keyed marker still written
  [ ! -e "$TD/unknown.json" ]                         # …but never the sentinel-keyed one
  run cat "$TD/$pane.json"
  [[ "$output" == *'"sid":""'* ]]
}

@test "marker contract: the REAL watchdog classifies an auto-shutdown as RECYCLE/deliberate-teardown" {
  # End-to-end across the file boundary: drive the REAL hook, then the REAL reader. Neither side can
  # drift into a green-but-wrong fixture.
  local sid=sidQ team=teamQ member=wkrContract pane=%58 wt="$D/wtQ"
  mkdir -p "$wt"; worktreetsv "$team" "$member" "$wt"; teamcfg "$team" "$member" "$pane"
  reg "$sid" PANE-Q "$wt" 3600
  tx "$sid" 9000
  run hookrun "$member" "$team" "$sid" "$wt"
  [ "$status" -eq 0 ]
  TD="$HOME/.claude/watchdog/teardown"
  wait_for "$TD/$sid.json"
  W="$REPO/hooks/lead-crash-watchdog.sh"
  mkdir -p "$D/wdbase/projects/slug" "$D/reg" "$D/nojetsam"
  cp "$D/proj/slug/$sid.jsonl" "$D/wdbase/projects/slug/$sid.jsonl"   # the reader needs a transcript
  CC_ACCOUNT_BASES="$D/wdbase" CC_REGISTRY_DIR="$D/reg" CC_JETSAM_DIRS="$D/nojetsam" \
    run "$W" --classify "$sid"
  [ "$status" -eq 0 ]
  [[ "$output" == RECYCLE* ]] || false
  [[ "$output" == *deliberate-teardown* ]]
}

# ══════════════════════════════════════════════════════════════════════════════════════════════════
# 2026-07-29 — WORKTREE-RESOLUTION GAP + LIVENESS. Measured before this change: WORKTREE was
# unresolved for 100% of 2.1.183 implicit-team teammates (every resolution leg is structurally dead
# for them — no manifest exists on the machine, worktrees.tsv is written only by create-team.sh, and
# the /tmp globs cannot match ~/Development/.worktrees/<name>). Consequences: 81 SURFACE pages, and
# ~/.claude/reap-guard/ EMPTY — the birth-grace/effect-read/adoption gate had never once executed.
# The fix adds two legs, and with them the OWNERSHIP distinction these tests exist to pin: a tree
# resolved from the team config's shared `cwd` may be GATED on but must never be REMOVED.
# ══════════════════════════════════════════════════════════════════════════════════════════════════

# a real git repo with one commit (git worktree remove needs a real repo, not a bare dir)
mkrepo() {
  # `git -C ""` is a NO-OP, not an error — an empty $1 would write this identity into the cwd repo.
  : "${1:?mkrepo: repo path required}"
  mkdir -p "$1"; git -C "$1" init -q
  git -C "$1" config user.email t@t; git -C "$1" config user.name t
  echo x > "$1/f"; git -C "$1" add f; git -C "$1" commit -qm init
}
# a real LINKED worktree of <repo> at <path> on a new branch
mkwt() { git -C "$1" worktree add -q -b "$3" "$2" >/dev/null 2>&1; }
# team config.json with a per-member cwd (the implicit-team shape); args: team member pane cwd [extra-member]
teamcfg_cwd() {
  mkdir -p "$HOME/.claude/teams/$1"
  if [ -n "${5:-}" ]; then
    printf '{"members":[{"name":"%s","tmuxPaneId":"leader","cwd":"%s"},{"name":"%s","tmuxPaneId":"%s","cwd":"%s"}]}' \
      "$5" "$4" "$2" "$3" "$4" > "$HOME/.claude/teams/$1/config.json"
  else
    printf '{"members":[{"name":"%s","tmuxPaneId":"%s","cwd":"%s"}]}' "$2" "$3" "$4" > "$HOME/.claude/teams/$1/config.json"
  fi
}
# last record = an assistant tool_use with NO result ⇒ a tool is RUNNING
txtool() { printf '{"type":"assistant","timestamp":"%s.000Z","message":{"role":"assistant","content":[{"type":"tool_use","id":"%s","name":"Bash","input":{}}]}}\n' "$(iso "$2")" "${3:-tu1}" > "$D/proj/slug/$1.jsonl"; }
# the tool RETURNED (a user tool_result record appended) ⇒ turn finished
txtoolresult() { printf '{"type":"user","timestamp":"%s.000Z","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"%s"}]}}\n' "$(iso "$2")" "${3:-tu1}" >> "$D/proj/slug/$1.jsonl"; }
wait_gone() { local i=0; while [ -e "$1" ] && [ "$i" -lt 60 ]; do sleep 0.05; i=$((i+1)); done; [ ! -e "$1" ]; }

# (A) NAME leg — a worktree named for the member resolves from git itself, and IS removed.
#     POSITIVE CONTROL for the ownership gate: proves it is not merely "never remove".
@test "worktree-by-name: a member-named worktree resolves via git and IS removed (owned)" {
  local sid=sidWN team=teamWN member=gu5-verdict pane=%91
  mkrepo "$D/repo"; local wt="$D/wts/$member"; mkdir -p "$D/wts"; mkwt "$D/repo" "$wt" b-verdict
  [ -d "$wt" ]
  # NO tsv and NO cwd in config ⇒ the name leg is the ONLY thing that can resolve this.
  teamcfg "$team" "$member" "$pane"
  reg "$sid" PANE-WN "$wt" 3600
  tx "$sid" 9000
  run hookrun "$member" "$team" "$sid" "$D/repo"     # payload cwd seeds `git worktree list`
  [ "$status" -eq 0 ]
  grep -q "Auto-shutdown idle teammate: $member" "$LOGF"     # resolved ⇒ reached the reap
  wait_gone "$wt"                                            # and the OWNED worktree was removed
  grep -q "worktree removed: $wt" "$LOGF"
}

# (B) SHARED cwd — THE data-loss guard. On the implicit-team model every member's config `cwd` is the
#     LEAD's worktree, recorded identically for the whole team. Resolving it is right (the gates need
#     a real tree) but removing it would `--force`-destroy the lead's tree and every sibling's work.
@test "shared team-config cwd: gated on, but the worktree is NEVER removed (lead-tree data-loss guard)" {
  local sid=sidSH team=teamSH member=gu2-seams pane=%92
  mkrepo "$D/repo2"; local shared="$D/wts2/pool"; mkdir -p "$D/wts2"; mkwt "$D/repo2" "$shared" b-pool
  [ -d "$shared" ]
  # lead + member BOTH record the same cwd ⇒ shared ⇒ not owned. No name-match, no tsv.
  teamcfg_cwd "$team" "$member" "$pane" "$shared" team-lead
  reg "$sid" PANE-SH "$shared" 3600
  tx "$sid" 9000
  run hookrun "$member" "$team" "$sid" /nonexistent-cwd
  [ "$status" -eq 0 ]
  grep -q "Auto-shutdown idle teammate: $member" "$LOGF"     # resolved: gates ran, reap proceeded
  grep -q "is SHARED by 2 members" "$LOGF"                   # and it was classified as shared
  sleep 0.5
  [ -d "$shared" ]                                           # ← the guard: tree SURVIVES the reap
  grep -q "worktree kept (shared, not owned" "$LOGF"
  ! grep -q "worktree removed: $shared" "$LOGF"
}

# (B2) a config cwd recorded for a SOLE occupant is genuinely that member's ⇒ owned ⇒ removable.
#      Keeps (B) honest: the refusal is keyed on SHARING, not on "came from config".
@test "sole-occupant team-config cwd: owned ⇒ worktree IS removed" {
  local sid=sidSO team=teamSO member=solo-worker pane=%93
  mkrepo "$D/repo3"; local wt="$D/wts3/solo"; mkdir -p "$D/wts3"; mkwt "$D/repo3" "$wt" b-solo
  teamcfg_cwd "$team" "$member" "$pane" "$wt"          # exactly ONE member records this cwd
  reg "$sid" PANE-SO "$wt" 3600
  tx "$sid" 9000
  run hookrun "$member" "$team" "$sid" /nonexistent-cwd
  [ "$status" -eq 0 ]
  wait_gone "$wt"
  grep -q "worktree removed: $wt" "$LOGF"
}

# (C) TOOL-IN-FLIGHT — a teammate mid-tool_use is LIVE. Observed 2026-07-29: a teammate actively
#     writing tests (stale=0m) was SURFACEd as confirm-close. Must defer: no close, no page.
@test "tool in flight: a mid-tool_use teammate is live → defer, no close, no page" {
  local sid=sidTF team=teamTF member=wkrLive pane=%94 wt="$D/wtTF"
  mkdir -p "$wt"; worktreetsv "$team" "$member" "$wt"; teamcfg "$team" "$member" "$pane"
  reg "$sid" PANE-TF "$wt" 3600
  txtool "$sid" 30 tu-live                              # trailing tool_use, NO tool_result
  run hookrun "$member" "$team" "$sid" "$wt"
  [ "$status" -eq 0 ]
  [[ "$output" != *'"continue": false'* ]] || false
  grep -q "tool in flight" "$LOGF"
  [ ! -e "$D/tmux-calls.log" ]                          # no pane closed
  [ ! -e "$D/it2-calls.log" ]
  [ ! -e "$D/notify-calls.log" ]                        # and NOT surfaced as confirm-close
}

# (C2) positive control for (C): the same tool_use once its RESULT has landed is a FINISHED turn.
#      Without this, (C) would also pass against a predicate that simply always says "live".
@test "tool returned: tool_use + matching tool_result → not live → closes as before" {
  local sid=sidTR team=teamTR member=wkrDone pane=%95 wt="$D/wtTR"
  mkdir -p "$wt"; worktreetsv "$team" "$member" "$wt"; teamcfg "$team" "$member" "$pane"
  reg "$sid" PANE-TR "$wt" 3600
  txtool "$sid" 9000 tu-done; txtoolresult "$sid" 8900 tu-done
  run hookrun "$member" "$team" "$sid" "$wt"
  [ "$status" -eq 0 ]
  ! grep -q "tool in flight" "$LOGF" || false
  grep -q "Auto-shutdown idle teammate: $member" "$LOGF"
}

# (D) DAMPING — the SURFACE leg re-fires on EVERY subsequent TeammateIdle (measured: one teammate
#     paged 6 times in 3 minutes; 81 pages total). Repetition on a close-order channel is what trains
#     the operator to ignore it. The LOG must stay complete; only the PAGE is damped.
@test "SURFACE page is damped: repeated unresolved-worktree fires page the desk ONCE" {
  export TEAMMATE_MAX_DEFERS=1
  local sid=sidDM team=teamDM member=wkrDamp
  tx "$sid" 9000
  run hookrun "$member" "$team" "$sid" /nonexistent-cwd    # fire 1 → defer (1/1)
  run hookrun "$member" "$team" "$sid" /nonexistent-cwd    # fire 2 → SURFACE + page
  [ -e "$D/notify-calls.log" ]
  [ "$(grep -c 'cc-notify' "$D/notify-calls.log")" -eq 1 ]
  run hookrun "$member" "$team" "$sid" /nonexistent-cwd    # fire 3 → SURFACE, page SUPPRESSED
  run hookrun "$member" "$team" "$sid" /nonexistent-cwd    # fire 4 → same
  [ "$status" -eq 0 ]
  [ "$(grep -c 'cc-notify' "$D/notify-calls.log")" -eq 1 ]  # still ONE page
  [ "$(grep -c 'SURFACE' "$LOGF")" -ge 3 ]                  # but the forensic log is complete
  grep -q "page suppressed (damped)" "$LOGF"
}

# (A2) DEAD SEED — `git worktree list` needs some LIVE path in the repo to run at all, so seeding it
#      from only the first recorded cwd silently disables the name leg whenever that path is gone.
#      Real shape (team session-8891c11f, 2026-07-29): all 7 members record one cwd that no longer
#      exists, while gu5-verdict/-decide/-cadence each still own a worktree of their own name.
#      Here the FIRST recorded cwd is dead and the member's own name-matched worktree must still win
#      (name leg ⇒ OWNED) over the shared live cwd the config also offers.
@test "dead first seed: name leg still resolves from a later live cwd (owned, not the shared tree)" {
  local sid=sidDS team=teamDS member=gu5-decide pane=%96
  mkrepo "$D/repo4"; local wt="$D/wts4/$member"; mkdir -p "$D/wts4"; mkwt "$D/repo4" "$wt" b-decide
  mkdir -p "$HOME/.claude/teams/$team"
  # lead records a DEAD cwd (listed first); the member records the live repo root (shared-looking)
  printf '{"members":[{"name":"team-lead","tmuxPaneId":"leader","cwd":"%s"},{"name":"%s","tmuxPaneId":"%s","cwd":"%s"}]}' \
    "$D/gone-worktree" "$member" "$pane" "$D/repo4" > "$HOME/.claude/teams/$team/config.json"
  [ ! -d "$D/gone-worktree" ]
  reg "$sid" PANE-DS "$wt" 3600
  tx "$sid" 9000
  run hookrun "$member" "$team" "$sid" /nonexistent-cwd     # payload cwd dead too ⇒ must use config seeds
  [ "$status" -eq 0 ]
  grep -q "Auto-shutdown idle teammate: $member" "$LOGF"
  wait_gone "$wt"                                            # the member's OWN worktree was removed…
  grep -q "worktree removed: $wt" "$LOGF"
  [ -d "$D/repo4" ]                                          # …and the shared repo root was NOT touched
}

# ── shared-cwd never-reaps: the defer must TERMINATE, and only for the shared case ────────────────
# THE DEFECT (measured 2026-08-01, team session-01d229a2). Teammates inherit the LEAD's cwd at spawn
# — a `cd` in the brief does not change what the harness records — so all four members recorded
# cwd=<the shared checkout>. That one value defeats two gates at once: the ownership test
# (occupants==1 can never hold, so removal is refused) and reap-guard, which then looks for work
# products in the LEAD's tree where a teammate working in its own worktree has produced none. So
# "no-products" was guaranteed rather than measured, this leg deferred every sweep forever, and
# three teammates sat idle-but-alive with no terminal state and no alarm.
#
# The fix must not add a close path — the only tree it could gate on is the shared checkout, which
# must never be reaped. It converts a permanent silence into ONE page. These two tests pin both
# halves, and the second is what stops the fix from becoming "reap young teammates sooner".
teamcfg_shared() {  # <team> <member> <pane> <shared-cwd> — member AND lead both record <shared-cwd>
  mkdir -p "$HOME/.claude/teams/$1"
  printf '{"members":[{"name":"team-lead","cwd":"%s"},{"name":"%s","tmuxPaneId":"%s","cwd":"%s"}]}' \
    "$4" "$2" "$3" "$4" > "$HOME/.claude/teams/$1/config.json"
}
# a reap-guard that always DEFERS. It used to `exit 1` — an unclassifiable code, which was fine
# while the hook read EVERY non-zero as one undifferentiated DEFER. It no longer does: 10 is a
# WHO/WHEN hold and 11 is an own-footprint hold, and the SURFACE text differs by cause. So the stub
# now speaks the contract, and the arm below is explicitly the WHO/WHEN one.
denying_guard() { # [<exit-code>] — default 10, the WHO/WHEN hold
  export CC_REAP_GUARD_BIN="$D/bin/reap-guard-deny"
  printf '#!/bin/bash\nexit %s\n' "${1:-10}" > "$CC_REAP_GUARD_BIN"; chmod +x "$CC_REAP_GUARD_BIN"
}
# a reap-guard that PERMITS — impossible to reach on a shared cwd before 2026-08-04, because the
# guard re-read the whole tree in its own process and the lead's dirt was always there.
permitting_guard() {
  export CC_REAP_GUARD_BIN="$D/bin/reap-guard-ok"
  printf '#!/bin/bash\nexit 0\n' > "$CC_REAP_GUARD_BIN"; chmod +x "$CC_REAP_GUARD_BIN"
}

# ⚠ REWRITTEN 2026-08-04, NOT DELETED. Its premise — "a close here would be the ungated-close defect
# wearing a fix's clothes" — conflated GATING with REMOVING. The close still runs the busy marker,
# rule 3, tool-in-flight, the checkpoint and the adoption belt; what a shared tree forbids is the
# `git worktree remove --force` below it, and that guard is untouched. What this arm still pins, and
# what nothing else in the corpus pins, is the refusal: a WHO/WHEN hold on a shared cwd must
# terminate in a SURFACE and must NOT close. The permitting twin below is the other direction.
@test "shared cwd: a WHO/WHEN reap-guard hold is bounded, SURFACEs, and never closes the pane" {
  local team=tshared member=mshared pane=%99 shared="$D/sharedco"
  mkdir -p "$shared"; teamcfg_shared "$team" "$member" "$pane" "$shared"
  denying_guard 10
  # Four sweeps: MAX_DEFERS is 3, so the 4th must surface rather than defer a 4th time.
  for _ in 1 2 3 4; do hookrun "$member" "$team" sidshared "$shared" >/dev/null 2>&1 || true; done
  grep -q "SURFACE $member" "$LOGF" || { echo "never terminated — still deferring:"; cat "$LOGF"; false; }
  grep -q "SHARED cwd" "$LOGF"      || { echo "surfaced, but not for the shared-cwd reason"; false; }
  grep -q "WHO/WHEN hold" "$LOGF"   || { echo "surfaced without naming the CAUSE — the old text claimed"; \
                                         echo "'no gate can ever read its real tree', which is now false"; false; }
  [ ! -s "$D/it2-calls.log" ] || { echo "pane was CLOSED despite a WHO/WHEN hold:"; cat "$D/it2-calls.log"; false; }
}

@test "shared cwd: once reap-guard PERMITS, the pane closes and the shared tree is KEPT, not removed" {
  # The direction @521 could not express while every non-zero was one DEFER. It is the whole policy
  # in one arm: the close and the removal are different acts, and only the removal is forbidden here.
  local team=tsharedok member=msharedok pane=PANE-SOK shared="$D/sharedok"
  mkdir -p "$shared"; teamcfg_shared "$team" "$member" "$pane" "$shared"
  permitting_guard
  tx sidsharedok 9000
  run hookrun "$member" "$team" sidsharedok "$shared"
  [ "$status" -eq 0 ]
  wait_for "$D/it2-calls.log"
  sleep 0.3
  grep -q "✓ closed pane $pane" "$LOGF"
  grep -q "worktree kept (shared, not owned by $member)" "$LOGF"
  [ -d "$shared" ]
}

@test "RED-PROOF: a DEDICATED cwd keeps the unbounded defer (the fix must not reap young teammates)" {
  # Same denying guard, same four sweeps — but the member owns its cwd, so the DEFER is informative
  # (birth-grace / operator-adoption are self-resolving) and must stay uncounted and unsurfaced.
  # Without this, "bound the defer" would silently become "reap anything reap-guard is protecting".
  local team=towned member=mowned pane=%98 wt="$D/wt_owned"
  mkdir -p "$wt"; worktreetsv "$team" "$member" "$wt"; teamcfg "$team" "$member" "$pane"
  denying_guard
  for _ in 1 2 3 4; do hookrun "$member" "$team" sidowned "$wt" >/dev/null 2>&1 || true; done
  ! grep -q "SURFACE $member" "$LOGF" || { echo "a dedicated-cwd defer was surfaced — fix over-reaches:"; cat "$LOGF"; false; }
  [ ! -s "$D/it2-calls.log" ] || { echo "pane closed despite reap-guard DEFER"; false; }
}

# ── SPAWN-TIME RESOLUTION (2026-08-03) ───────────────────────────────────────────────────────────
# reap-guard's birth-grace leg (R-a) is only as good as the spawn instant it is handed. The hook used
# to read that instant from `cc-sessions` alone and, on a miss, substitute `date +%s` — i.e. NOW.
# `cc-sessions` indexes LAUNCHER-started sessions; a teammate is spawned by the HARNESS and is never
# in it. Measured 2026-08-03: 14/14 registry entries carried `startedAt` and 0/2 live teammate sids
# resolved, so every teammate was handed age=0 and pinned inside the 300s grace forever — 310 of 373
# reap-guard decision records on the box read "age 0s < birth grace 300s", and the last
# `✓ closed pane` in teammate-lifecycle.log was 2026-07-25. A lookup MISS had become a VALUE, and the
# value it became was the one that defers forever.
# These three pin the resolution ORDER and, crucially, that the fallback stays alive and the
# unresolved case stays LOUD — a fix that reached "always trust joinedAt" would be just as blind.

# reap-guard stub that RECORDS the argv it was handed, then DEFERs (exit 10) so nothing is closed.
# Recording is the whole point: the assertion is about the value passed IN, not the decision out.
recording_guard() {
  export CC_REAP_GUARD_BIN="$D/bin/reap-guard-rec"
  cat > "$CC_REAP_GUARD_BIN" <<EOF
#!/bin/bash
echo "\$*" >> "$D/guard-argv.log"
exit 10
EOF
  chmod +x "$CC_REAP_GUARD_BIN"
}
# team config carrying joinedAt (epoch-MILLISECONDS), as every real team config on this box does
teamcfg_joined() { mkdir -p "$HOME/.claude/teams/$1"
  printf '{"members":[{"name":"%s","tmuxPaneId":"%s","joinedAt":%s}]}' "$2" "$3" "$4" \
    > "$HOME/.claude/teams/$1/config.json"; }

@test "spawn-time: a teammate ABSENT from cc-sessions still gets its real age from the config's joinedAt" {
  local team=tjoin member=mjoin pane=%97 wt="$D/wt_join" joined_s=$((NOW-3600))
  mkdir -p "$wt"; worktreetsv "$team" "$member" "$wt"
  teamcfg_joined "$team" "$member" "$pane" "$((joined_s*1000))"
  printf '[]' > "$D/sessions.json"     # the MEASURED reality: teammates are not in the launcher registry
  recording_guard
  hookrun "$member" "$team" sidjoin "$wt" >/dev/null 2>&1 || true
  grep -q -- "--spawn-time $joined_s" "$D/guard-argv.log" \
    || { echo "spawn-time was not taken from joinedAt (pre-fix this was 'now', so age was always 0):";
         cat "$D/guard-argv.log" 2>/dev/null; false; }
}

@test "POSITIVE CONTROL: with no joinedAt, spawn-time still falls back to the cc-sessions registry" {
  # Without this the fix could 'pass' by ignoring cc-sessions entirely — a dead fallback that nothing
  # would report. Pins that the OLD source is still consulted when the new one cannot answer.
  local team=treg member=mreg pane=%96 wt="$D/wt_reg" spawn_ago=7200
  mkdir -p "$wt"; worktreetsv "$team" "$member" "$wt"; teamcfg "$team" "$member" "$pane"
  reg sidreg "$pane" "$wt" "$spawn_ago"
  recording_guard
  hookrun "$member" "$team" sidreg "$wt" >/dev/null 2>&1 || true
  grep -q -- "--spawn-time $((NOW-spawn_ago))" "$D/guard-argv.log" \
    || { echo "cc-sessions fallback is DEAD — joinedAt-first broke the old path:";
         cat "$D/guard-argv.log" 2>/dev/null; false; }
}

@test "spawn-time: neither source resolves → logged as UNRESOLVED, never a silent 'now'" {
  # The third state. Deferring is still correct here (never an ungated close), but a permanent defer
  # must be VISIBLE in the log rather than masquerading as a perpetually just-born teammate.
  local team=tnone member=mnone pane=%95 wt="$D/wt_none"
  mkdir -p "$wt"; worktreetsv "$team" "$member" "$wt"; teamcfg "$team" "$member" "$pane"
  printf '[]' > "$D/sessions.json"
  recording_guard
  hookrun "$member" "$team" sidnone "$wt" >/dev/null 2>&1 || true
  grep -q "spawn-time UNRESOLVED" "$LOGF" \
    || { echo "an unresolvable spawn-time was silently replaced by now:"; cat "$LOGF"; false; }
}

# ── F1: OWNERSHIP, NOT THE WORKTREE, WHEN THE TREE IS SHARED (2026-08-03) ────────────────────────
# A lead may deliberately put N teammates in ONE worktree (disjoint FILES; automated worktree
# creation has a .git/config.lock race + data-loss bug). Each member then saw its SIBLINGS' edits
# via `git status` on the shared cwd and deferred as if the dirt were its own — all five members of
# session-ba3d4b59 deferred on "dirty tree" at once, none dirty on anything it had written.
# These four pin the fix AND its two must-not-change directions; without the latter, "ignore the
# dirty tree" would quietly become "reap a member that really did leave work behind".

# a real git repo at <dir> with one committed file, then <n> dirty files owned by "a sibling"
shared_repo() {
  # `git -C ""` is a NO-OP, not an error — an empty $1 would write this identity into the cwd repo.
  : "${1:?shared_repo: repo path required}"
  git init -q "$1" 2>/dev/null
  git -C "$1" config user.email t@t; git -C "$1" config user.name t
  echo base > "$1/base.txt"; git -C "$1" add base.txt; git -C "$1" commit -qm base
}
# transcript for <sid> recording a Write tool_use of <path> (what session-writes.sh attributes on)
tx_wrote() {
  printf '{"type":"assistant","timestamp":"%s.000Z","message":{"role":"assistant","content":[{"type":"tool_use","id":"t1","name":"Write","input":{"file_path":"%s"}}]}}\n' \
    "$(iso 60)" "$2" > "$D/proj/slug/$1.jsonl"
}

@test "F1: shared cwd dirty ONLY with a sibling's files → this member is not deferred for it" {
  local team=tf1 member=mf1 pane=%94 shared="$D/f1repo"
  shared_repo "$shared"; echo sib > "$shared/sibling.txt"      # dirt this member never wrote
  teamcfg_shared "$team" "$member" "$pane" "$shared"
  tx_wrote sidf1 "$shared/mine.txt"                             # member wrote mine.txt — and COMMITTED nothing dirty
  recording_guard                                               # stop before any close; we assert the DEFER REASON
  hookrun "$member" "$team" sidf1 "$shared" >/dev/null 2>&1 || true
  grep -q "NOTHING this member wrote is" "$LOGF" \
    || { echo "a sibling's dirt still convicted this member:"; cat "$LOGF"; false; }
  # `if grep …; then … false; fi`, never `! grep … || { … }`: a `!`-prefixed statement is EXEMPT from
  # errexit, so the negated form asserts nothing bats can act on (scripts/bats-assert-liveness.py
  # flags it DEAD). Here `false` is the last command of a reachable branch, so the test really fails.
  if grep -q "defer $member (1/3): dirty tree" "$LOGF"; then
    echo "still deferred on the whole-tree dirty read:"; cat "$LOGF"; false
  fi
}

@test "F1 POSITIVE CONTROL: the member's OWN dirty file still defers it (relaxation is narrow)" {
  # The direction that proves the fix did not become "shared cwd ⇒ never dirty". Same shared tree,
  # but the dirty path is one this member's transcript records writing.
  local team=tf2 member=mf2 pane=%93 shared="$D/f2repo"
  shared_repo "$shared"; echo mine > "$shared/mine.txt"
  teamcfg_shared "$team" "$member" "$pane" "$shared"
  tx_wrote sidf2 "$shared/mine.txt"
  recording_guard
  hookrun "$member" "$team" sidf2 "$shared" >/dev/null 2>&1 || true
  # Asserts BEHAVIOUR only, never the new log line — that is what makes this a real control: it must
  # pass on the pristine PRE-F1 tree as well as the fixed one. A control that keys on a string the
  # fix introduces can only ever fail before and pass after, which is a second copy of the RED proof
  # wearing a control's clothes and proves nothing about over-reach.
  grep -q "defer $member (1/3): dirty tree" "$LOGF" \
    || { echo "own-dirt no longer produces the dirty-tree defer — the relaxation over-reached:";
         cat "$LOGF"; false; }
}

@test "F1 POSITIVE CONTROL: cannot-tell (no transcript) keeps the whole-tree defer — ignorance never licenses a close" {
  local team=tf3 member=mf3 pane=%92 shared="$D/f3repo"
  shared_repo "$shared"; echo sib > "$shared/sibling.txt"
  teamcfg_shared "$team" "$member" "$pane" "$shared"
  rm -f "$D/proj/slug/sidf3.jsonl"                              # no transcript ⇒ session-writes rc 2
  recording_guard
  hookrun "$member" "$team" sidf3 "$shared" >/dev/null 2>&1 || true
  grep -q "defer $member (1/3): dirty tree" "$LOGF" \
    || { echo "an UNREADABLE attribution cleared the dirty flag — fail-open:"; cat "$LOGF"; false; }
}

@test "F1 POSITIVE CONTROL: an OWNED worktree is untouched — the whole-tree read still governs" {
  # On a dedicated tree the whole-tree answer IS this member's answer. If the new branch ran here it
  # could clear a real dirty flag using a transcript that simply has no Write records.
  local team=tf4 member=mf4 pane=%91 wt="$D/f4repo"
  shared_repo "$wt"; echo dirt > "$wt/anything.txt"
  worktreetsv "$team" "$member" "$wt"; teamcfg "$team" "$member" "$pane"
  tx_wrote sidf4 "$wt/unrelated.txt"                            # member wrote something else entirely
  recording_guard
  hookrun "$member" "$team" sidf4 "$wt" >/dev/null 2>&1 || true
  grep -q "defer $member (1/3): dirty tree" "$LOGF" \
    || { echo "an OWNED worktree's dirty defer was weakened by per-file attribution:"; cat "$LOGF"; false; }
  # Same reason as above — an errexit-reachable branch, not a `!` the shell exempts.
  if grep -q "NOTHING this member wrote is" "$LOGF"; then
    echo "the shared-cwd branch ran on an OWNED worktree:"; cat "$LOGF"; false
  fi
}

# ══ THE DETACHED-CLOSE TERMINAL VERDICT (2026-08-03) ═══════════════════════════════════════════════
# Why these exist: no teammate pane closed on this box between 2026-07-25 and 2026-08-03, and the
# LAST link in the chain was this one. The close runs in a detached subshell, so it is reparented to
# launchd; bin/cc-in-kitty answers "which terminal am I in?" by walking $PPID to $KITTY_PID, and an
# orphan's walk reaches pid 1 first. It returns "DEFINITIVE no", bin/it2 routes to iTerm2 — which is
# not running — and the close dies rc=1. All three closes that survived every gate since the kitty
# migration failed exactly there (lc-accounts, lc-shell, photo-score).
#
# The env vars survive reparenting; only the LINEAGE is destroyed. So the verdict is resolved in the
# hook body, while still attached, and handed down through cc-in-kitty's own CC_TERM seam.
# scripts/handoff-fire.sh:715-731 fixed this for its own watcher on 2026-08-01 and the remedy was
# never generalised — these tests are what stops that happening again.

# A shim that records the CC_TERM it was invoked with, so the pin is observed at the CONSUMER rather
# than asserted at the producer. A test that only checked "the function exported it" would pass even
# if the detached subshell never inherited it — which is the entire failure being fixed.
_term_probe_it2() {
  cat > "$D/bin/it2" <<EOF
#!/bin/bash
echo "CC_TERM=\${CC_TERM:-<unset>} args=\$*" >> "$D/it2-env.log"
exit 0
EOF
  chmod +x "$D/bin/it2"
}
_cik() { # $1 = exit code the stubbed cc-in-kitty should return
  cat > "$D/bin/cc-in-kitty-stub" <<EOF
#!/bin/bash
exit $1
EOF
  chmod +x "$D/bin/cc-in-kitty-stub"
  export CC_IN_KITTY_BIN="$D/bin/cc-in-kitty-stub"
}
_close_run() { # drive one full close; $1=pane
  local sid=sidT team=teamT member=wkrTerm wt="$D/wtT"
  mkdir -p "$wt"; worktreetsv "$team" "$member" "$wt"; teamcfg "$team" "$member" "$1"
  reg "$sid" PANE-T "$wt" 3600
  tx "$sid" 9000
  run hookrun "$member" "$team" "$sid" "$wt"
  [ "$status" -eq 0 ]
}

@test "TERM PIN: attached-and-kitty pins CC_TERM=kitty into the detached close" {
  _term_probe_it2; _cik 0
  _close_run PANE-K
  wait_for "$D/it2-env.log"
  grep -q "CC_TERM=kitty" "$D/it2-env.log"
}

@test "TERM PIN: a not-kitty verdict pins iterm2 — both directions, so nothing drifts" {
  _term_probe_it2; _cik 1
  _close_run PANE-I
  wait_for "$D/it2-env.log"
  grep -q "CC_TERM=iterm2" "$D/it2-env.log"
}

# UNVERIFIABLE (exit 2) must pin NOTHING. Pinning a guess here would be worse than the bug: it would
# route a close to a terminal nobody established, and the fail-closed behaviour is the safe default.
@test "TERM PIN POSITIVE CONTROL: an UNVERIFIABLE verdict pins nothing" {
  _term_probe_it2; _cik 2
  _close_run PANE-U
  wait_for "$D/it2-env.log"
  grep -q "CC_TERM=<unset>" "$D/it2-env.log"
}

@test "TERM PIN POSITIVE CONTROL: an explicit CC_TERM is never overwritten" {
  _term_probe_it2; _cik 0
  export CC_TERM=iterm2                      # operator/test override must win over the probe
  _close_run PANE-O
  wait_for "$D/it2-env.log"
  grep -q "CC_TERM=iterm2" "$D/it2-env.log"
}

# ══ ✓ MEANS GONE, NOT rc=0 ════════════════════════════════════════════════════════════════════════
# `✓ closed pane` is the subsystem's only outcome signal and scripts/teammate-reap-alarm.sh now reads
# it as the health metric, so it has to mean what it says. rc is a claim about the CALL; these pin it
# to a claim about the WORLD.

_it2_says() { # $1 = what `session list` prints, $2 = exit code for `session close`
  cat > "$D/bin/it2" <<EOF
#!/bin/bash
if [ "\$1" = session ] && [ "\$2" = list ]; then printf '%s\n' "$1"; exit 0; fi
if [ "\$1" = session ] && [ "\$2" = close ]; then echo "close-attempted" >> "$D/it2-calls.log"; exit $2; fi
exit 0
EOF
  chmod +x "$D/bin/it2"
}

@test "a close that returns rc=0 while the pane SURVIVES is logged as a failure, not a ✓" {
  _cik 0; _it2_says "PANE-Z" 0                # enumerator still lists it after a 'successful' close
  _close_run PANE-Z
  wait_for "$D/it2-calls.log"
  sleep 0.3
  grep -q "STILL PRESENT" "$LOGF"
  run grep -c "✓ closed pane" "$LOGF"
  [ "$output" -eq 0 ]
}

@test "a survived close RETRACTS its teardown marker — a false 'closed on purpose' corrupts crash triage" {
  _cik 0; _it2_says "PANE-Z" 0
  _close_run PANE-Z
  wait_for "$D/it2-calls.log"
  sleep 0.3
  [ ! -e "$HOME/.claude/watchdog/teardown/PANE-Z.json" ]
  [ ! -e "$HOME/.claude/watchdog/teardown/sidT.json" ]
}

@test "a hard-failed close also retracts its marker" {
  _cik 0; _it2_says "PANE-Z" 1                # close returns rc 1 (the live iTerm2-connect failure)
  _close_run PANE-Z
  wait_for "$D/it2-calls.log"
  sleep 0.3
  grep -q "pane close FAILED" "$LOGF"
  [ ! -e "$HOME/.claude/watchdog/teardown/PANE-Z.json" ]
}

@test "POSITIVE CONTROL: a VERIFIED-absent close still logs ✓ and KEEPS its marker" {
  _cik 0; _it2_says "SOME-OTHER-PANE" 0       # enumerator readable, our pane genuinely gone
  _close_run PANE-Z
  wait_for "$D/it2-calls.log"
  sleep 0.3
  grep -q "✓ closed pane PANE-Z" "$LOGF"
  [ -e "$HOME/.claude/watchdog/teardown/PANE-Z.json" ]
}

# ══ THE SHARED-CWD CLOSE: GATE ON THE MEMBER'S OWN FOOTPRINT (2026-08-04) ═════════════════════════
# The hook already computed the right answer and then threw it away. On a shared cwd it logs
# "shared cwd is dirty, but NOTHING this member wrote is" — 10/10 members did, live — and then hands
# reap-guard a worktree path with no channel for that verdict, so reap-guard re-reads the WHOLE tree
# in its own process and re-convicts the member on the LEAD's dirt one gate later. The refusal became
# `⚑ SURFACE … Pane NOT closed`: 231 firings across 80 (team,member) pairs, 0 panes closed.
#
# These arms run the REAL scripts/reap-guard.sh. That matters: 30 of the tests above never reach it
# at all (the fixture HOME contains no scripts/reap-guard.sh, so the hook logs "not executable" and
# skips the belt) and the other 9 stub it to a single exit code — so no test in this file could tell
# a WHO-refusal from a WHAT-on-the-wrong-tree refusal, which is the whole discrimination.

# The REAL guard, wired the way the live hook wires it.
real_guard() {
  export CC_REAP_GUARD_BIN="$REPO/scripts/reap-guard.sh"
  export CC_REAP_RECORDS_DIR="$D/reap-records"
  export CC_REAP_PROJECT_ROOTS="$D/proj"      # reap-guard R-d resolves the member's transcript here
}
# reap-guard reads the REAL clock — CC_CLASSIFY_NOW governs the hook's own belts and nothing else —
# so anything the guard must date has to be real-epoch based, or every member sits inside the 300s
# birth grace forever and the suite proves nothing.
rnow()  { date +%s; }
riso()  { date -u -v-"${1}"S +%Y-%m-%dT%H:%M:%S 2>/dev/null || date -u -d "@$(( $(rnow) - $1 ))" +%Y-%m-%dT%H:%M:%S; }

# A REAL linked worktree (git worktree add), shared by a lead + 2 siblings + the member, dirty ONLY
# from a file a SIBLING wrote. This is the measured live shape, not a simplification of it: on
# 2026-08-04 the shared checkout's single piece of dirt was one untracked file authored by the lead.
shared_linked_worktree() { # <team> <member> <pane> → echoes the shared worktree path
  # `git -C ""` is a NO-OP, not an error — an unset $D would write this identity into the cwd repo.
  local team="${1:?shared_linked_worktree: team required}" member="$2" pane="$3" repo="${D:?}/slw-repo" wt="${D:?}/slw-shared" joined
  git init -q "$repo" 2>/dev/null
  git -C "$repo" config user.email t@t; git -C "$repo" config user.name t
  echo base > "$repo/base.txt"; git -C "$repo" add base.txt; git -C "$repo" commit -qm base
  git -C "$repo" worktree add -q -b slw-branch "$wt" >/dev/null 2>&1
  echo "the lead wrote this" > "$wt/sibling.txt"        # the ONLY dirt, and it is a sibling's
  joined=$(( ( $(rnow) - 3600 ) * 1000 ))               # past the birth grace on the guard's clock
  mkdir -p "$HOME/.claude/teams/$team"
  printf '{"members":[{"name":"team-lead","cwd":"%s","joinedAt":%s},{"name":"sib-two","cwd":"%s","joinedAt":%s},{"name":"%s","tmuxPaneId":"%s","cwd":"%s","joinedAt":%s}]}' \
    "$wt" "$joined" "$wt" "$joined" "$member" "$pane" "$wt" "$joined" \
    > "$HOME/.claude/teams/$team/config.json"
  printf '%s' "$wt"
}
# The lead's shutdown_request as the harness actually records it in the member's transcript: a
# user-role record whose text opens `<teammate-message teammate_id="team-lead">`. Byte-for-byte the
# shape of a typed prompt — which is why both WHO-predicates counted it as operator presence and
# re-armed a 6-hour adoption hold against the very close the lead had just asked for.
tx_leadmail() { # <sid> <ago-seconds-REAL>
  printf '{"type":"user","isMeta":null,"timestamp":"%s.000Z","message":{"role":"user","content":"<teammate-message teammate_id=\\"team-lead\\">Please wrap up. shutdown_request: finish your commit and go idle.</teammate-message>"}}\n' \
    "$(riso "$2")" >> "$D/proj/slug/$1.jsonl"
}
# A GENUINE operator prompt on the same clock — the control that keeps the 2026-07-24 incident class
# closed. Real-epoch stamped so BOTH belts see it: reap-guard R-d dates it against the real clock,
# and the hook's own belt (CC_CLASSIFY_NOW) reads it as newer than spawn either way.
tx_operator() { # <sid> <ago-seconds-REAL>
  printf '{"type":"user","isMeta":null,"timestamp":"%s.000Z","message":{"role":"user","content":"actually hold on, let me look at this"}}\n' \
    "$(riso "$2")" >> "$D/proj/slug/$1.jsonl"
}
# tx_wrote + the matching tool_result. tx_wrote alone leaves a tool_use with no result, which is a
# TOOL IN FLIGHT — an unbounded, correct hold that lands BEFORE reap-guard, so a fixture using it
# never reaches the gate under test. The F1 arms above never noticed: they stub reap-guard and
# assert the defer REASON, so they stop short of this leg by construction.
tx_wrote_done() { # <sid> <written-path>
  tx_wrote "$1" "$2"
  txtoolresult "$1" 60 t1
}

@test "shared cwd + a SIBLING's dirt: the close is gated on own footprint, so the pane CLOSES" {
  local team=tsc1 member=mscclean pane=PANE-SC1 sid=sidsc1 wt
  wt="$(shared_linked_worktree "$team" "$member" "$pane")"
  real_guard
  git -C "$wt" update-ref "refs/wip/$member/LAST" HEAD          # this member produced durable work
  tx_wrote_done "$sid" "$wt/mine.txt"                           # it wrote mine.txt — and left it CLEAN
  run hookrun "$member" "$team" "$sid" "$wt"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"continue": false'* ]] || false             # the turn-stop that precedes the close
  grep -q "NOTHING this member wrote is" "$LOGF"
  wait_for "$D/it2-calls.log"
  sleep 0.3
  grep -q "session close" "$D/it2-calls.log"
  grep -q "✓ closed pane $pane" "$LOGF"
  # PRISTINE-TREE PROOF: before this commit reap-guard's own record for this decision was a DEFER on
  # the whole-tree read. Assert the record, not just the outcome — it is what distinguishes "the leg
  # was skipped" from "the leg ran and happened to pass".
  rec="$(find "$D/reap-records" -name "reap-$member-*.json" | head -1)"
  [ "$(jq -r '.decision' "$rec")" = "REAP" ]
}

@test "POSITIVE CONTROL: the same tree dirty from THIS member's OWN file never closes" {
  # The direction that proves the relaxation is narrow. Identical fixture, identical sibling file —
  # the ONLY change is that the member's transcript records writing the dirty path. Four sweeps, so
  # rule 3's bounded defer is exhausted and reap-guard's own-footprint leg (exit 11) is the thing
  # actually refusing by the end. If this closes, "ignore the shared tree" became "ignore the dirt".
  local team=tsc2 member=mscmine pane=PANE-SC2 sid=sidsc2 wt
  wt="$(shared_linked_worktree "$team" "$member" "$pane")"
  real_guard
  git -C "$wt" update-ref "refs/wip/$member/LAST" HEAD
  tx_wrote_done "$sid" "$wt/sibling.txt"                        # the dirty file IS this member's
  for _ in 1 2 3 4; do hookrun "$member" "$team" "$sid" "$wt" >/dev/null 2>&1 || true; done
  sleep 0.3
  grep -q "own files are among the dirty ones" "$LOGF"
  # BEHAVIOUR ONLY — deliberately NO assertion on `dirty-tree-mine`, the reason_kind this commit
  # introduces. A control that keys on a string the fix invents can only fail before and pass after,
  # which is a second copy of the RED proof wearing a control's clothes (see the F1 control above).
  # It has to pass on the PRISTINE tree as well, and it does. The exit-11 contract is pinned at the
  # CLI level in tests/reap-guard.bats, where asserting the new code IS the point.
  if [ -s "$D/it2-calls.log" ]; then
    echo "a member's OWN dirt was closed over:"; cat "$D/it2-calls.log"; cat "$LOGF"; false
  fi
}

@test "shared cwd + UNATTRIBUTABLE dirt (no transcript) fails CLOSED — ignorance never closes a pane" {
  local team=tsc3 member=mscunk pane=PANE-SC3 sid=sidsc3 wt
  wt="$(shared_linked_worktree "$team" "$member" "$pane")"
  real_guard
  git -C "$wt" update-ref "refs/wip/$member/LAST" HEAD
  rm -f "$D/proj/slug/$sid.jsonl"                               # session_dirty_mine rc 2 ⇒ unknown
  for _ in 1 2 3 4; do hookrun "$member" "$team" "$sid" "$wt" >/dev/null 2>&1 || true; done
  sleep 0.3
  if [ -s "$D/it2-calls.log" ]; then
    echo "an UNATTRIBUTABLE tree licensed a close:"; cat "$D/it2-calls.log"; false
  fi
  rec="$(find "$D/reap-records" -name "reap-$member-*.json" | head -1)"
  [ "$(jq -r '.reason_kind' "$rec")" = "dirty-tree-unattributable" ]
}

@test "R-b on a shared cwd: a READ-ONLY member has no ref by construction → REAP, not a forever-defer" {
  # teammate-checkpoint.sh:201-204 exits 0 WITHOUT writing a ref when the tree matches HEAD, so a
  # member that only read files can never satisfy the per-member-ref clause. The whole-tree commit
  # clause it used to fall back on is vacuous on a shared tree (the lead's commits are newer than
  # every member's spawn), so R-b there is either this or a permanent defer.
  local team=tsc4 member=mscnoref pane=PANE-SC4 sid=sidsc4 wt before
  wt="$(shared_linked_worktree "$team" "$member" "$pane")"
  real_guard
  tx "$sid" 9000                                                # read-only: no Write records, no refs
  before="$(git -C "$wt" status --porcelain)"
  run hookrun "$member" "$team" "$sid" "$wt"
  [ "$status" -eq 0 ]
  wait_for "$D/it2-calls.log"
  sleep 0.3
  grep -q "✓ closed pane $pane" "$LOGF"
  rec="$(find "$D/reap-records" -name "reap-$member-*.json" | head -1)"
  [ "$(jq -r '.reason_kind' "$rec")" = "shared-no-refs" ]
  # POSITIVE CONTROL — the pane close and the worktree removal are DIFFERENT ACTS. The removal is
  # still gated on ownership + whole-tree cleanliness, so a shared tree must survive the close with
  # not one byte of its state touched. This is the only reason relaxing the close gate is safe.
  [ -d "$wt" ]
  [ -f "$wt/sibling.txt" ]
  [ "$(git -C "$wt" status --porcelain)" = "$before" ]
  grep -q "worktree kept (shared, not owned by $member)" "$LOGF"
}

@test "a lead's <teammate-message> is not adoption — the requested close still happens" {
  local team=tsc5 member=mscmail pane=PANE-SC5 sid=sidsc5 wt
  wt="$(shared_linked_worktree "$team" "$member" "$pane")"
  real_guard
  tx "$sid" 9000
  tx_leadmail "$sid" 120                                        # the lead asked it to leave, 2min ago
  run hookrun "$member" "$team" "$sid" "$wt"
  [ "$status" -eq 0 ]
  wait_for "$D/it2-calls.log"
  sleep 0.3
  grep -q "✓ closed pane $pane" "$LOGF"
  # Pristine-tree behaviour was the inverse: the shutdown_request re-armed a 6h adoption hold against
  # the very close it requested. Assert the hold did NOT fire, on both belts.
  if grep -q "operator-adopted" "$LOGF"; then
    echo "the lead's own shutdown_request was read as operator adoption:"; cat "$LOGF"; false
  fi
}

@test "POSITIVE CONTROL: a GENUINE operator prompt on the same tree still HOLDS the pane open" {
  # The 2026-07-24 incident class. Same fixture, same clock, same everything — the only difference is
  # that a human typed. If this closes, the shared-cwd relaxation has reopened the incident.
  local team=tsc6 member=mscadopt pane=PANE-SC6 sid=sidsc6 wt
  wt="$(shared_linked_worktree "$team" "$member" "$pane")"
  real_guard
  reg "$sid" "$pane" "$wt" 3600                                 # spawn 1h ago on the hook's clock
  tx "$sid" 9000
  tx_operator "$sid" 120                                        # a human typed 2 minutes ago
  run hookrun "$member" "$team" "$sid" "$wt"
  [ "$status" -eq 0 ]
  [[ "$output" != *'"continue": false'* ]] || false
  sleep 0.3
  if [ -s "$D/it2-calls.log" ]; then
    echo "an ADOPTED pane was closed:"; cat "$D/it2-calls.log"; cat "$LOGF"; false
  fi
}

# ══ THE CLOSE-TARGET IDENTITY PIN (2026-08-04) ════════════════════════════════════════════════════
# A kitty window id is a per-process counter restarting at 1 with every kitty, so a recorded id
# survives a restart as a VALID id naming an unrelated LIVE window — the premise "a stale id can only
# no-op" this hook carried in a comment is an iTerm2 fact, not a kitty one. bin/it2-kitty grew two
# optional pins; these assert this hook actually passes them, and only on the backend that has them.

@test "IDENTITY PIN: on the kitty backend the close carries the member's --agent-name cmdline pin" {
  _term_probe_it2; _cik 0                                       # cc-in-kitty says kitty ⇒ CC_TERM=kitty
  _close_run PANE-K
  wait_for "$D/it2-env.log"
  grep -q -- "--expect-cmdline-match --agent-name wkrTerm" "$D/it2-env.log"
}

@test "IDENTITY PIN POSITIVE CONTROL: a NON-kitty backend passes no pin at all (byte-identical close)" {
  # The real `it2` CLI has never heard of these flags. Passing them to iTerm2 would turn every close
  # into an argument error — a pin that becomes an outage is worse than no pin.
  _term_probe_it2; _cik 1
  _close_run PANE-I
  wait_for "$D/it2-env.log"
  if grep -q -- "--expect-" "$D/it2-env.log"; then
    echo "a kitty-only identity pin was sent to the iTerm2 backend:"; cat "$D/it2-env.log"; false
  fi
}

@test "IDENTITY PIN: an unresolvable kitty generation OMITS that flag and keeps the cmdline pin" {
  # The two flags are independent by design. $KITTY_PID is inherited env and can be STALE; a stale
  # generation handed to the shim makes it refuse every close (exit 66), i.e. it would manufacture
  # the outage the pin exists to prevent. Verify-or-omit, never trust-and-refuse.
  _term_probe_it2; _cik 0
  export KITTY_PID=999999                                        # a pid that is not a live kitty
  _close_run PANE-K
  wait_for "$D/it2-env.log"
  grep -q -- "--expect-cmdline-match --agent-name wkrTerm" "$D/it2-env.log"
  if grep -q -- "--expect-generation" "$D/it2-env.log"; then
    echo "an unverifiable KITTY_PID was pinned anyway:"; cat "$D/it2-env.log"; false
  fi
}

@test "IDENTITY PIN: exit 66 is a REFUSAL — never a ✓, and it retracts its teardown marker" {
  _cik 0
  cat > "$D/bin/it2" <<EOF
#!/bin/bash
if [ "\$1" = session ] && [ "\$2" = list ]; then printf 'PANE-Z\n'; exit 0; fi
if [ "\$1" = session ] && [ "\$2" = close ]; then echo "close-attempted" >> "$D/it2-calls.log"; exit 66; fi
exit 0
EOF
  chmod +x "$D/bin/it2"
  _close_run PANE-Z
  wait_for "$D/it2-calls.log"
  sleep 0.3
  grep -q "identity pin REFUSED" "$LOGF"
  [ ! -e "$HOME/.claude/watchdog/teardown/PANE-Z.json" ]
  run grep -c "✓ closed pane" "$LOGF"
  [ "$output" -eq 0 ]
}

# memory: lookup-miss-is-not-absence. A NAME searched in a list can only ever MISS, so an UNREADABLE
# enumerator must not be allowed to manufacture either verdict. It keeps the ✓ (fail-safe in the
# direction that does not invent a failure the alarm would then have to explain) — but it must reach
# that ✓ through the cannot-tell branch, not by accident.
@test "POSITIVE CONTROL: an UNREADABLE enumerator keeps the ✓ rather than inventing a failure" {
  _cik 0
  cat > "$D/bin/it2" <<EOF
#!/bin/bash
if [ "\$1" = session ] && [ "\$2" = list ]; then exit 3; fi     # enumerator broken
if [ "\$1" = session ] && [ "\$2" = close ]; then echo c >> "$D/it2-calls.log"; exit 0; fi
exit 0
EOF
  chmod +x "$D/bin/it2"
  _close_run PANE-Z
  wait_for "$D/it2-calls.log"
  sleep 0.3
  grep -q "✓ closed pane PANE-Z" "$LOGF"
  run grep -c "STILL PRESENT" "$LOGF"
  [ "$output" -eq 0 ]
}
