#!/bin/bash
# lead-deathwatch — L1 orchestrator of the never-wait-on-the-dead build. Turns the kqueue helper's
# event-INSTANT death signal into the two things a death demands: a CAPTURE of the orphaned WIP and a
# PAGE — never a respawn (ruling #1: capture is mechanical, recovery is human/paged).
#
# The incident: a teammate died out-of-band; the harness fires nothing on pane DEATH (only clean
# completion). L1 closes that: bin/cc-deathwatch-kqueue arms kqueue EVFILT_PROC/NOTE_EXIT on each
# REGISTERED {pid,start-time} and streams a DEATH line the instant that process exits; this orchestrator
# handles each.
#
# REGISTERED CRITERIA (desk 2026-07-14):
#   L1-a  BLIND to a pid it never registered — an unwatched pid's death fires nothing. DECLARED; covered
#         by the P8 registry (spawn-instant registration → the watch-list) + L2's unregistered-waitee RED
#         (an event-driven wait on a waitee no watcher holds lints RED). Composition, not a hole.
#   L1-b  CAPTURE-BEFORE-NOTIFY (Invariant 7): the forensics checkpoint of orphaned WIP is written to disk
#         BEFORE the death-event page — so the evidence survives even if the page path fails.
#   L1-c  {pid,start-time} recycling guard (in the helper, at ARM time): a pid whose start-time no longer
#         matches — or that is gone (ESRCH) — is a recycled/dead registration → DEATH now, never a watch
#         on a stranger. (The arm-window race — death between the guard read and the kqueue arm — rides the
#         same ESRCH path: select.kevent ADD raises → 'gone'.)
#   L1-d  death ⇒ checkpoint (MECHANICAL) + PAGE (never auto-respawn).
#   L1-e  the WATCHER's own death is LOUD (S-4 / who-watches-the-watcher): the watch loop writes a
#         heartbeat record each cycle (its ABSENCE is the supervisor's alarm) AND detects an abnormal
#         kqueue-helper exit (SIGKILL/OOM) → a watcher-died ALARM record + re-arm. A silently-dead
#         death-watcher is indistinguishable from a healthy quiet fleet — the D9 shape one meta-level up.
#
#   lead-deathwatch.sh --watch <watch-file>   run the watch loop until every watched process is dead
#   lead-deathwatch.sh --once  <watch-file>   run ONE cycle (heartbeat + arm + handle) — supervisor-driven
#   lead-deathwatch.sh --selftest             RED-prove L1-b/c/d/e against the naive/absent form
#     watch-file lines (TAB):  pid <TAB> start <TAB> label <TAB> waiter <TAB> worktree
#
# Env overrides (tests): CC_DEATH_RECORDS_DIR, CC_DEATHWATCH_KQ, CC_WAIT_PAGE_CMD, CC_DEATHWATCH_HEARTBEAT_S.
# Exit: 0 = ok · 2 = usage.
set -uo pipefail
cd "$(dirname "$0")/.." 2>/dev/null || true

RECORDS_DIR="${CC_DEATH_RECORDS_DIR:-$HOME/.claude/deathwatch}"
HEARTBEAT_S="${CC_DEATHWATCH_HEARTBEAT_S:-30}"

usage() { sed -n '2,33p' "$0" | sed 's/^# \{0,1\}//'; }
die()   { echo "lead-deathwatch: $*" >&2; exit 2; }
stamp() { date -u +%Y%m%dT%H%M%SZ; }
iso()   { date -u +%Y-%m-%dT%H:%M:%SZ; }

kq_helper() {
  [ -n "${CC_DEATHWATCH_KQ:-}" ] && { echo "$CC_DEATHWATCH_KQ"; return; }
  local sd; sd="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/.."
  if   [ -x "$sd/bin/cc-deathwatch-kqueue" ]; then echo "$sd/bin/cc-deathwatch-kqueue"
  elif command -v cc-deathwatch-kqueue >/dev/null 2>&1; then command -v cc-deathwatch-kqueue
  else echo "$HOME/.claude/bin/cc-deathwatch-kqueue"; fi
}
# page = a DIRECTIVE to a human, never a disposition (cc-notify's mailbox write is the durable half).
page() { local cmd="${CC_WAIT_PAGE_CMD:-cc-notify}"; "$cmd" "$1" "$2" >/dev/null 2>&1 || "$cmd" "$1" "$2" || true; }

# ── L1-b: CAPTURE the orphaned WIP to disk, and RETURN the record path — the caller pages AFTER. ──────
# If a git worktree is given, checkpoint tracked+untracked WIP into a ref via plumbing (teammate-
# checkpoint style: a temp index, no working-tree touch, no hooks). The JSON record is the always-written
# capture; the ref is the WIP snapshot when there is one.
capture_orphan_wip() { # <label> <pid> <start> <reason> <waiter> <worktree>
  local label="$1" pid="$2" start="$3" reason="$4" waiter="$5" worktree="$6"
  mkdir -p "$RECORDS_DIR" 2>/dev/null || true
  local ts ref="" rec
  ts="$(stamp)-$$-${RANDOM}"
  if [ -n "$worktree" ] && git -C "$worktree" rev-parse --git-dir >/dev/null 2>&1; then
    local parent tree commit idx
    parent="$(git -C "$worktree" rev-parse HEAD 2>/dev/null || true)"
    idx="$(mktemp "${TMPDIR:-/tmp}/dw-idx.XXXXXX")"
    if [ -n "$parent" ] && GIT_INDEX_FILE="$idx" git -C "$worktree" read-tree HEAD 2>/dev/null \
       && GIT_INDEX_FILE="$idx" git -C "$worktree" add -A 2>/dev/null \
       && tree="$(GIT_INDEX_FILE="$idx" git -C "$worktree" write-tree 2>/dev/null)" \
       && commit="$(git -C "$worktree" commit-tree "$tree" -p "$parent" -m "deathwatch checkpoint $label $ts" 2>/dev/null)"; then
      ref="refs/deathwatch/$label/$ts"
      git -C "$worktree" update-ref "$ref" "$commit" 2>/dev/null || ref=""
    fi
    rm -f "$idx"
  fi
  rec="$RECORDS_DIR/death-${label}-${ts}.json"
  jq -n --arg label "$label" --arg pid "$pid" --arg start "$start" --arg reason "$reason" \
        --arg waiter "$waiter" --arg worktree "$worktree" --arg ref "$ref" --arg captured "$(iso)" \
     '{kind:"death", label:$label, pid:$pid, start:$start, reason:$reason, waiter:$waiter,
       worktree:$worktree, checkpoint_ref:$ref, captured:$captured}' > "$rec" 2>/dev/null
  command -v sync >/dev/null 2>&1 && sync 2>/dev/null || true
  echo "$rec"
}

# ── L1-d: handle a death — CAPTURE first (L1-b), then PAGE. There is NO respawn path in this file. ────
handle_death() { # <label> <pid> <reason> <waiter> <worktree>
  local label="$1" pid="$2" reason="$3" waiter="$4" worktree="$5" rec
  rec="$(capture_orphan_wip "$label" "$pid" "" "$reason" "$waiter" "$worktree")"   # 1. CAPTURE (before page)
  local ref; ref="$(jq -r '.checkpoint_ref // ""' "$rec" 2>/dev/null)"
  page "$waiter" "☠️ DEATH: $label (pid $pid, $reason) died out-of-band. Orphaned WIP captured${ref:+ at $ref}; forensics: $rec. RE-OBSERVE the effect and assign a HUMAN owner — NOT respawned (ruling #1). This wait is now on a dead waitee (see its L2 contract)."   # 2. PAGE, never respawn
  echo "$rec"
}

# ── L1-e: the watcher's own liveness. Heartbeat each cycle (absence=alarm); alarm on helper death. ────
write_heartbeat() { # <n-watched>
  mkdir -p "$RECORDS_DIR" 2>/dev/null || true
  jq -n --arg n "$1" --arg ts "$(iso)" --arg pid "$$" \
     '{kind:"heartbeat", watching:($n|tonumber), ts:$ts, watcher_pid:($pid|tonumber)}' \
     > "$RECORDS_DIR/heartbeat.json" 2>/dev/null || true
}
write_alarm() { # <alarm-kind> <detail>
  mkdir -p "$RECORDS_DIR" 2>/dev/null || true
  jq -n --arg k "$1" --arg d "$2" --arg ts "$(iso)" \
     '{kind:"alarm", alarm:$k, detail:$d, ts:$ts}' > "$RECORDS_DIR/alarm-$(stamp)-$$-${RANDOM}.json" 2>/dev/null || true
}

# count watch-file entries whose pid is still alive (the loop's "work remaining").
live_entries() { # <watch-file>
  local f="$1" n=0 pid rest
  [ -f "$f" ] || { echo 0; return; }
  while IFS=$'\t' read -r pid rest; do
    case "$pid" in ''|'#'*) continue ;; esac
    kill -0 "$pid" 2>/dev/null && n=$((n+1))
  done < "$f"
  echo "$n"
}

# ── ONE cycle: heartbeat → arm the helper (bounded by the heartbeat interval) → handle deaths. ────────
# Returns 0 normally; if the helper exits ABNORMALLY (killed/crashed), writes a watcher-died alarm and
# returns 3 (the caller re-arms). This is where the who-watches-the-watcher answer is mechanical.
run_cycle() { # <watch-file>  [<timeout override, s>]
  local wf="$1" to="${2:-}" nw out hrc
  [ -n "$to" ] || to="$HEARTBEAT_S"
  nw="$(live_entries "$wf")"
  write_heartbeat "$nw"
  out="$("$(kq_helper)" --timeout "$to" "$wf" 2>/dev/null)"; hrc=$?
  if [ "$hrc" -gt 128 ] || { [ "$hrc" -ne 0 ] && [ "$hrc" -ne 2 ]; }; then
    write_alarm "watcher-died" "kqueue helper exited abnormally ($hrc) — a silently-dead death-watcher hides real deaths; re-arming."
    return 3
  fi
  # map label -> worktree (field 5) for handling
  local tag label pid reason waiter worktree
  printf '%s\n' "$out" | while IFS=$'\t' read -r tag label pid reason waiter; do
    [ "$tag" = "DEATH" ] || continue
    worktree="$(awk -F'\t' -v l="$label" '$3==l{print $5; exit}' "$wf" 2>/dev/null)"
    handle_death "$label" "$pid" "$reason" "$waiter" "$worktree" >/dev/null
  done
  return 0
}

cmd_watch() { # <watch-file>  — loop until every watched process is dead
  local wf="${1:?--watch needs a watch-file}"
  [ -f "$wf" ] || die "no watch-file at $wf"
  while [ "$(live_entries "$wf")" -gt 0 ]; do
    run_cycle "$wf" || true   # a helper-death alarm returns 3; loop re-arms
  done
  write_heartbeat 0
  echo "lead-deathwatch: all watched processes dead — loop complete." >&2
}

# ── selftest: SEE every L1 RED-proof fire. Real child through kqueue; every assertion TRAPS. ──────────
PASS=0; FAIL=0
okp()  { printf '  ok   %-60s\n' "$1"; PASS=$((PASS+1)); }
badp() { printf '  FAIL %-60s\n' "$1"; FAIL=$((FAIL+1)); }

selftest() {
  local d SELF REC
  d="$(mktemp -d "${TMPDIR:-/tmp}/dw-selftest.XXXXXX")" || die "mktemp"
  trap 'rm -rf "$d"' EXIT
  SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
  REC="$d/records"
  # each case drives a FRESH subprocess `--once` so it resolves CC_DEATH_RECORDS_DIR at its own top-level
  # (the cc-wait selftest pattern), and stub the page (cc-notify) so nothing real is sent.
  printf '#!/bin/bash\nprintf "DEATH\\tbmember\\t424242\\texit\\twaiterX\\n"\n' > "$d/kqemit"; chmod +x "$d/kqemit"
  printf '#!/bin/bash\nexit 0\n'  > "$d/noop";     chmod +x "$d/noop"      # a page that succeeds silently
  printf '#!/bin/bash\nexit 7\n'  > "$d/failpage"; chmod +x "$d/failpage"  # a page that always FAILS
  printf '#!/bin/bash\nkill -9 $$\n' > "$d/kqkill"; chmod +x "$d/kqkill"   # a helper that self-SIGKILLs
  # shellcheck disable=SC2016  # $2 is INTENTIONALLY literal — it expands inside the generated stub, not now
  printf '#!/bin/bash\nprintf "%%s\\n" "$2" >> "%s/pagelog"\n' "$d" > "$d/logpage"; chmod +x "$d/logpage"
  printf '424242\tx\tbmember\twaiterX\t\n' > "$d/wl-b"

  echo "lead-deathwatch --selftest — every L1 RED-proof must be SEEN to fire:"

  # ---- L1-b: CAPTURE-BEFORE-NOTIFY — the page FAILS, the forensics record STILL exists on disk. ----
  rm -rf "$REC"
  CC_DEATH_RECORDS_DIR="$REC" CC_DEATHWATCH_KQ="$d/kqemit" CC_WAIT_PAGE_CMD="$d/failpage" "$SELF" --once "$d/wl-b" 1 >/dev/null 2>&1
  if ls "$REC"/death-bmember-*.json >/dev/null 2>&1; then okp "L1-b capture-before-notify: record survives a FAILED page (evidence not lost)"
  else badp "L1-b capture-before-notify: record MISSING after a failed page"; fi

  # ---- L1-d: a death → capture record + EXACTLY ONE page saying NOT respawned (no respawn path). ---
  rm -rf "$REC"; : > "$d/pagelog"
  CC_DEATH_RECORDS_DIR="$REC" CC_DEATHWATCH_KQ="$d/kqemit" CC_WAIT_PAGE_CMD="$d/logpage" "$SELF" --once "$d/wl-b" 1 >/dev/null 2>&1
  local npages; npages="$( [ -f "$d/pagelog" ] && wc -l <"$d/pagelog" | tr -d ' ' || echo 0 )"
  if [ "$npages" -eq 1 ] && grep -q 'NOT respawned' "$d/pagelog" && ls "$REC"/death-bmember-*.json >/dev/null 2>&1; then
    okp "L1-d death → checkpoint record + EXACTLY ONE page (says NOT respawned); no respawn"
  else badp "L1-d expected 1 page saying 'NOT respawned' + a record (got $npages pages)"; fi

  # ---- L1-c: {pid,start} guard — a LIVE pid with a WRONG start → DEATH(recycled), not false-alive. --
  rm -rf "$REC"
  sleep 30 & local live=$!
  printf '%s\tBOGUS_START_STRING\trecyc\twaiterY\t\n' "$live" > "$d/wl-recyc"
  CC_DEATH_RECORDS_DIR="$REC" CC_WAIT_PAGE_CMD="$d/noop" "$SELF" --once "$d/wl-recyc" 3 >/dev/null 2>&1
  if ls "$REC"/death-recyc-*.json >/dev/null 2>&1; then okp "L1-c {pid,start} guard: live pid + WRONG start → DEATH(recycled), not false-alive"
  else badp "L1-c recycling guard did not fire DEATH on a start mismatch"; fi
  kill "$live" 2>/dev/null; wait "$live" 2>/dev/null || true

  # ---- L1-c ESRCH: an already-gone pid → DEATH(gone). The arm-window race rides this same path. ----
  rm -rf "$REC"
  printf '99999998\twhatever\tgoneone\twaiterZ\t\n' > "$d/wl-gone"
  CC_DEATH_RECORDS_DIR="$REC" CC_WAIT_PAGE_CMD="$d/noop" "$SELF" --once "$d/wl-gone" 3 >/dev/null 2>&1
  if ls "$REC"/death-goneone-*.json >/dev/null 2>&1; then okp "L1-c ESRCH: an already-gone pid → DEATH(gone) (arm-window race rides this)"
  else badp "L1-c gone-pid did not produce a DEATH record"; fi

  # ---- e2e: a REAL child exit flows through kqueue NOTE_EXIT → DEATH captured. --------------------
  rm -rf "$REC"
  sleep 1 & local child=$!
  local cstart; cstart="$(ps -o lstart= -p "$child" | sed 's/^ *//;s/ *$//')"
  printf '%s\t%s\treal\twaiterR\t\n' "$child" "$cstart" > "$d/wl-real"
  CC_DEATH_RECORDS_DIR="$REC" CC_WAIT_PAGE_CMD="$d/noop" "$SELF" --once "$d/wl-real" 5 >/dev/null 2>&1
  if ls "$REC"/death-real-*.json >/dev/null 2>&1; then okp "e2e: real child exit → kqueue NOTE_EXIT → DEATH captured"
  else badp "e2e real child death was not captured"; fi

  # ---- L1-e heartbeat: a cycle writes a proof-of-life record (its ABSENCE is the supervisor alarm). -
  rm -rf "$REC"
  printf '99999997\tx\tnone\tw\t\n' > "$d/wl-hb"
  CC_DEATH_RECORDS_DIR="$REC" CC_WAIT_PAGE_CMD="$d/noop" "$SELF" --once "$d/wl-hb" 1 >/dev/null 2>&1
  if [ -f "$REC/heartbeat.json" ]; then okp "L1-e heartbeat record written each cycle (S-4 absence-is-alarm)"
  else badp "L1-e no heartbeat record — the watcher's own liveness is invisible"; fi

  # ---- L1-e helper-death: a SIGKILLing helper stub → a watcher-died ALARM record + re-arm (rc 3). --
  rm -rf "$REC"
  printf '11111\ty\tv\tw\t\n' > "$d/wl-kill"
  CC_DEATH_RECORDS_DIR="$REC" CC_DEATHWATCH_KQ="$d/kqkill" CC_WAIT_PAGE_CMD="$d/noop" "$SELF" --once "$d/wl-kill" 3 >/dev/null 2>&1; local crc=$?
  if ls "$REC"/alarm-*.json >/dev/null 2>&1 && [ "$crc" -eq 3 ]; then
    okp "L1-e helper SIGKILL mid-block → watcher-died ALARM + re-arm (rc 3)"
  else badp "L1-e a killed kqueue helper produced NO alarm (silently-dead watcher)"; fi

  echo "lead-deathwatch --selftest: $PASS passed, $FAIL failed"
  [ "$FAIL" -eq 0 ] || exit 1
  echo "lead-deathwatch --selftest: GREEN — L1-b/c/d/e all fire RED-provably (real kqueue exit + SIGKILL alarm)."
  exit 0
}

case "${1:-}" in
  --watch)    shift; cmd_watch "${1:-}" ;;
  --once)     shift; run_cycle "${1:?--once needs a watch-file}" "${2:-}" ;;
  --selftest) selftest ;;
  -h|--help|"") usage; exit 0 ;;
  *)          die "unknown argument '$1' (use --watch | --once | --selftest)" ;;
esac
