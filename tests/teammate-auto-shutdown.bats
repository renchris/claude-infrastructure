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
  cat > "$D/cc-interactive-stub.sh" <<'STUB'
#!/usr/bin/env bash
# TEST STUB of ci_last_interactive_epoch — mirrors cc-classify's last_interactive_epoch:
# epoch of the last REAL operator-typed prompt (string content, no isMeta, not auto-traffic); empty if none.
ci_last_interactive_epoch() {
  local f="${1:-}" rx ep
  [ -n "$f" ] && [ -f "$f" ] || return 1
  rx="${CC_CLASSIFY_AUTO_RX:-^<task-notification>|^<local-command-stdout>|^Stop hook feedback:|^\\[Request interrupted|^⟳|^⚑|^⚠}"
  ep="$(tail -c "${CC_CLASSIFY_INTERACTIVE_TAIL_BYTES:-2000000}" "$f" 2>/dev/null | jq -Rr --arg rx "$rx" '
      fromjson? | objects
      | select(.type=="user") | select(.isMeta != true)
      | (.message.content) as $c
      | ( if ($c|type)=="string" then $c
          elif ($c|type)=="array" and ([$c[]? | select(.type?=="tool_result")] | length)==0
          then ([$c[]? | select(.type?=="text") | .text] | join("\n"))
          else empty end ) as $t
      | select(($t|length) > 0)
      | select($t | test($rx) | not)
      | (.timestamp | strings | sub("\\.[0-9]+Z$"; "Z") | try fromdateiso8601 catch empty)
    ' 2>/dev/null | tail -1)"
  case "$ep" in ''|*[!0-9]*) return 1 ;; esac
  printf '%s' "$ep"
}
STUB
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

# (vi) lib ABSENT → one WARN + adoption check skipped → close proceeds (graceful degradation)
@test "lib absent → WARN + adoption skipped → close proceeds (partial-deploy degradation)" {
  export CC_INTERACTIVE_LIB="$D/no-such-lib.sh"      # absent
  local sid=sidV team=teamV member=wkrDegraded pane=%99 wt="$D/wtV"
  mkdir -p "$wt"; worktreetsv "$team" "$member" "$wt"; teamcfg "$team" "$member" "$pane"
  reg "$sid" PANE-V "$wt" 3600
  tx "$sid" 700; utx "$sid" 60                        # even WITH an operator prompt, an absent lib can't check
  run hookrun "$member" "$team" "$sid" "$wt"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"continue": false'* ]] || false  # close proceeds (degraded)
  grep -q "WARN" "$LOGF"
  [ ! -e "$D/notify-calls.log" ]                     # adoption never evaluated → no page
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
