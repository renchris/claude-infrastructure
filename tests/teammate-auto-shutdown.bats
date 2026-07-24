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
  [[ "$output" != *'"continue": false'* ]]
  [ ! -e "$D/notify-calls.log" ]
  run hookrun "$member" "$team" "$sid" /nonexistent-cwd   # fire 2 → defer (2/2)
  [ "$status" -eq 0 ]
  [[ "$output" != *'"continue": false'* ]]
  [ ! -e "$D/notify-calls.log" ]
  run hookrun "$member" "$team" "$sid" /nonexistent-cwd   # fire 3 → SURFACE (page), still no close
  [ "$status" -eq 0 ]
  [[ "$output" != *'"continue": false'* ]]
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
  [[ "$output" != *'"continue": false'* ]]          # NOT closed (no turn-stop emitted)
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
  [[ "$output" == *'"continue": false'* ]]           # close-decision emitted → proceeds to close
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
  [[ "$output" == *'"continue": false'* ]]           # close proceeds (degraded)
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
  [[ "$output" == *'"continue": false'* ]]
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
  [[ "$output" == *'"continue": false'* ]]           # brief ≠ adoption → closes
  [ ! -e "$D/notify-calls.log" ]
  wait_for "$D/tmux-calls.log"
  grep -q "kill-pane -t %60" "$D/tmux-calls.log"
}
