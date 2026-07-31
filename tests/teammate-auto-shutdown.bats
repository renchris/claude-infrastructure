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
@test "unresolved WORKTREE → defers (no close/page), then SURFACEs + pages after MAX_DEFERS (never ungated close)" {
  export TEAMMATE_MAX_DEFERS=2
  local sid=sidU team=teamU member=wkrUnresolved
  tx "$sid" 9000                                    # idle transcript; NO worktree mapping ⇒ WORKTREE=""
  run hookrun "$member" "$team" "$sid" /nonexistent-cwd   # fire 1 → defer (1/2)
  [ "$status" -eq 0 ]
  [[ "$output" != *'"continue": false'* ]] || false
  [ ! -e "$D/notify-calls.log" ]
  run hookrun "$member" "$team" "$sid" /nonexistent-cwd   # fire 2 → defer (2/2)
  [ "$status" -eq 0 ]
  [[ "$output" != *'"continue": false'* ]] || false
  [ ! -e "$D/notify-calls.log" ]
  run hookrun "$member" "$team" "$sid" /nonexistent-cwd   # fire 3 → SURFACE (page), still no close
  [ "$status" -eq 0 ]
  [[ "$output" != *'"continue": false'* ]] || false
  [ -e "$D/notify-calls.log" ]                      # desk paged
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
