#!/usr/bin/env bash
# pane-close-retry.sh — drain scripts/lib/pane-close-queue.sh: retry the pane closes that failed (F-b).
#
# WHY THIS EXISTS. Root cause 4 of docs/research/husk-panes-2026-09-30.md: each teammate closer made
# one attempt and gave up, and the attempt was made while kitty remote control was deaf (root cause 3:
# 10-60 s of refused connections, episodes lasting an hour). So the retry has to wait for the thing
# that was broken, not for a clock: every run first asks whether `kitty @ ls` answers at all, and a
# run that gets no answer leaves every row untouched. Rows are the durable record; this is the
# actuator, run every 10 minutes from scripts/teammate-reap-alarm.sh's launchd job.
#
# RE-READ BEFORE EVERY ACT (root cause 10). rc 124 on a mutating kitty verb means "may still execute":
# the request sits in kitty's queue and is read later. So a row never carries "the last close failed,
# close again" — every run re-derives the world from a fresh `ls` and acts only on what it sees now:
#   a. pane absent ⇒ it is gone (our late close, or anyone's) ⇒ remove the row
#   b. kitty restarted ⇒ window ids restart at 1, the id names a stranger now ⇒ remove, NEVER close
#   c. the member's claude still runs ⇒ not a husk yet ⇒ leave
#   d. anything but a shell in the foreground ⇒ not a husk ⇒ leave
#   e. otherwise close, pinned to the recorded kitty generation, and verify by absence
# Unverifiable ⇒ do not close, count an attempt, and page once at CC_PCQ_MAX_ATTEMPTS so a row that
# can never resolve is still heard. A wrong-window close kills a live session; a held row costs a pane.
#
# recycle rows (pane-lifecycle fixes item 4d) are a record of a recycle handoff-fire held on a deaf
# kitty: once kitty answers, the session is told once to re-run it; see drain_recycle below. A REMOTE
# row (form=remote, or a legacy row whose argv names --source-pane/--source-session) is dropped, never
# mailed: its argv is another actuator's, so telling the subject to run it put two actuators on one
# admit after that actuator had already aborted it (docs/plans/LIMIT_RECOVER_SELF_INPLACE.md R2).
# CC_PCQ_REMOTE_RECYCLE_DROP=off restores mailing.
#
# self-close rows belong to handoff-fire's own retrier: this never acts on them. If that retrier is
# gone it pages the desk once, BEFORE the kitty gate (a dead retrier is news precisely while kitty is
# deaf), and once kitty answers it tells the session once, via cc-notify, to re-run its self-close.
#
# husk rows (husk-panes-2026-10-22 F3) are panes KEPT with no claude in them; each run hands them to
# bin/cc-pane-close until one closes, also while kitty is deaf. See drain_husk for the holds.
#
# Never fatal, `set -u`, every external call bounded. One log line per row per run.
# Seams: CC_PCQ_KITTY_BIN · CC_PCQ_IT2_BIN · CC_PCQ_PS_FILE (a `ps -axo pid=,command=` capture) ·
#        CC_PCQ_PANE_CLOSE_BIN · CC_PCQ_CUSTODY_BIN · CC_PCQ_CLOSE_TIMEOUT_S ·
#        CC_PCQ_PAGE_BIN · CC_PCQ_NOTIFY_BIN · CC_PCQ_KITTY_SOCKET_BIN · CC_PCQ_TIMEOUT_S · CC_PCQ_MAX_ATTEMPTS · CC_PCQ_LOG
#        · CC_PANE_CLOSE_QUEUE_DIR (the lib's).

set -u
# shellcheck disable=SC1091  # #! helpers run via their interpreter, not by path (kalloc leak; plan KALLOC_TRIGGER_ELIMINATION W4)
if [ -f "${BASH_SOURCE[0]%/*}/lib/cc-run.sh" ]; then . "${BASH_SOURCE[0]%/*}/lib/cc-run.sh"; else cc_argv() { CC_ARGV=("$1"); }; cc_run() { "$@"; }; fi

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
# shellcheck disable=SC1091  # runtime-resolved source; the ship gate runs shellcheck without -x
. "$HERE/lib/pane-close-queue.sh" 2>/dev/null || exit 0

LOG="${CC_PCQ_LOG:-$HOME/.claude/logs/pane-close-retry.log}"
MAX_ATTEMPTS="${CC_PCQ_MAX_ATTEMPTS:-6}"; [[ "$MAX_ATTEMPTS" =~ ^[0-9]+$ ]] || MAX_ATTEMPTS=6
TIMEOUT_S="${CC_PCQ_TIMEOUT_S:-10}"
PAGE_BIN="${CC_PCQ_PAGE_BIN:-$HERE/../bin/cc-desk-page}"
mkdir -p "$(dirname "$LOG")" 2>/dev/null || true
log() { printf '%s %s\n' "$(date -u +%FT%TZ)" "$*" >> "$LOG" 2>/dev/null || true; }

# pcq_add writes `<row>.tmp.<pid>` then mv; a writer killed in between leaves the tmp forever. pcq_list
# never lists one, so an hour-old one is nobody's (pane end of life wave C, C6).
while IFS= read -r _t; do
  [[ -n "$_t" ]] && rm -f -- "$_t" && log "leftover ${_t##*/} (a killed writer's tmp) older than 60 min — removed"
done < <(find "$PCQ_DIR" -maxdepth 1 -name '*.json.tmp.*' -mmin +60 2>/dev/null)

# Same bounding idiom as hooks/teammate-auto-shutdown.sh tas_bounded: a launchd PATH has no coreutils
# `timeout`, so the absolute Homebrew paths are searched too; absent everywhere ⇒ unbounded, never
# a refusal to run.
PCQ_TIMEOUT_BIN=""
for _c in "$(command -v timeout 2>/dev/null || true)" "$(command -v gtimeout 2>/dev/null || true)" \
          /opt/homebrew/bin/timeout /usr/local/bin/timeout /opt/homebrew/bin/gtimeout /usr/local/bin/gtimeout; do
  [[ -n "$_c" && -x "$_c" ]] && { PCQ_TIMEOUT_BIN="$_c"; break; }
done
bounded() {
  declare -F cc_argv >/dev/null && { cc_argv "$1"; shift; set -- "${CC_ARGV[@]}" "$@"; }   # #! via its interpreter (cc-run.sh)
  if [[ -z "$PCQ_TIMEOUT_BIN" ]]; then "$@"; return $?; fi
  "$PCQ_TIMEOUT_BIN" -k 3 "$TIMEOUT_S" "$@"
}

# The standing pane census (husk-history-2026-10-24 FIX-DESIGN §4 W3) runs on EVERY tick, so it sits
# above the empty-queue exit: a husk nobody queued is exactly what it exists to count. Read-only
# against kitty, bounded, and its rc is ignored — a census that fails never stops a drain.
TIMEOUT_S=20 bounded "${CC_PCQ_CENSUS_BIN:-$HERE/pane-census.sh}" >/dev/null 2>&1 </dev/null || true

ROWS="$(pcq_list)"
[[ -n "$ROWS" ]] || exit 0          # the common case: nothing queued, and kitty is never asked

# One drainer at a time (C4f): the launchd job, SessionEnd's detached runs and manual runs overlap, and
# pcq_add is a read-modify-write. A dead holder's lock is taken over; a lock dir with no pid yet is a
# holder between its mkdir and its write, unless it is a minute old.
LOCK="$PCQ_DIR/.drain.lock"
if ! mkdir "$LOCK" 2>/dev/null; then
  _h="$(cat "$LOCK/pid" 2>/dev/null)"
  if [[ "$_h" =~ ^[0-9]+$ ]] && kill -0 "$_h" 2>/dev/null; then
    log "another drainer (pid $_h) holds the lock — exiting"; exit 0
  fi
  _m="$(stat -f %m "$LOCK" 2>/dev/null || echo 0)"
  if [[ -z "$_h" ]] && (( $(date +%s) - ${_m:-0} < 60 )); then
    log "another drainer is taking the lock — exiting"; exit 0
  fi
  rm -f "$LOCK/pid"; rmdir "$LOCK" 2>/dev/null
  mkdir "$LOCK" 2>/dev/null || { log "drain lock contended while taking it over from dead pid ${_h:-?} — exiting"; exit 0; }
  log "drain lock of dead pid ${_h:-?} taken over"
fi
echo "$$" > "$LOCK/pid" 2>/dev/null || true
trap 'rm -f "$LOCK/pid"; rmdir "$LOCK" 2>/dev/null' EXIT

# The run's own budget (C4e): the launchd job bounds this script (timeout 270, budget 240), and a run
# cut off by that bound drops whatever husk it was on. Husks stop being handed to the closer within
# 30 s of it.
BUDGET_S="${CC_PCQ_DRAIN_TIMEOUT_S:-240}"; [[ "$BUDGET_S" =~ ^[0-9]+$ ]] || BUDGET_S=240
command -v jq >/dev/null 2>&1 || { log "jq missing — every row held"; exit 0; }

# The live kitty, resolved BEFORE any row is judged: every kind is checked against its generation
# (window ids restart at 1 per kitty process, so a row from an older kitty names a stranger). The
# LIVE socket first, then a row's recorded one: a row's socket can name a kitty that has since
# restarted, and comparing a row against its own socket could never notice that change.
KITTY="${CC_PCQ_KITTY_BIN:-$(cc_run "$HERE/../bin/cc-kitty-bin" 2>/dev/null || command -v kitty 2>/dev/null || true)}"
IT2="${CC_PCQ_IT2_BIN:-$(command -v it2 2>/dev/null || echo "$HOME/.claude/bin/it2")}"
SOCK="${KITTY_LISTEN_ON:-}"
[[ -n "$SOCK" ]] || SOCK="$(cc_run "${CC_PCQ_KITTY_SOCKET_BIN:-$HERE/../bin/cc-kitty-socket}" 2>/dev/null || true)"
if [[ -z "$SOCK" ]]; then
  while IFS= read -r _row <&3; do
    SOCK="$(pcq_get "$_row" kitty_sock)"; [[ -n "$SOCK" ]] && break
  done 3<<<"$ROWS"
fi
LIVE_GEN=""
[[ "$SOCK" =~ .*kitty-([0-9]+) ]] && LIVE_GEN="${BASH_REMATCH[1]}"

page() { cc_run "$PAGE_BIN" --source pane-close-retry "$1" >/dev/null 2>&1 || true; }

# ── self-close rows: observe, page once, tell the session once — never act ─────────────────────
# Two one-shot signals with different preconditions. The desk page needs only a dead retrier, so it
# runs before the kitty gate. The note to the session itself ("re-run your self-close") is useful
# only once the terminal answers again, so it is queued here and sent after the gate passes.
_norm() { printf '%s' "$1" | tr -s ' ' | sed 's/^ //;s/ $//'; }
_retrier_alive() { # <row> → rc 0 iff the recorded retrier pid is running with the SAME start time
  local rpid rlst cur
  rpid="$(pcq_get "$1" retrier_pid)"; rlst="$(pcq_get "$1" retrier_lstart)"
  [[ "$rpid" =~ ^[0-9]+$ && -n "$rlst" ]] || return 1
  # pid AND start time: a recycled pid with a different lstart is somebody else, i.e. the retrier is gone.
  # Read the producer's way (handoff-fire _hf_lstart writes UTC, C locale): a local-time read never
  # matched, so a live retrier read dead (C6e).
  cur="$(TZ=UTC LC_ALL=C ps -p "$rpid" -o lstart= 2>/dev/null)"
  [[ -n "$cur" && "$(_norm "$cur")" == "$(_norm "$rlst")" ]]
}
NOTIFY_ROWS=""
drain_self_close() {
  local row="$1" pane kpid ks first
  pane="$(pcq_get "$row" pane)"
  [[ "$pane" =~ ^[0-9]+$ ]] || { pcq_remove "$row"; log "self-close pane=$pane not a kitty window id — row removed"; return; }
  # A row from an older kitty is about a window that no longer exists (husk-panes-2026-10-22 F2c):
  # self-close-85.json from 2026-10-01 was logged 2,325 times against the pane 85 of a later kitty.
  # Rows now carry kitty_pid (wave A); a legacy row without it is judged by its first_ts against the
  # running kitty's start. Either way it is dropped, never acted on.
  kpid="$(pcq_get "$row" kitty_pid)"
  if [[ -n "$kpid" && -n "$LIVE_GEN" && "$kpid" != "$LIVE_GEN" ]]; then
    pcq_remove "$row"; log "self-close pane=$pane dropped: kitty restarted since ($kpid → $LIVE_GEN)"; return
  fi
  if [[ -z "$kpid" ]]; then
    ks="$(_kitty_start_epoch)"; first="$(pcq_get "$row" first_ts)"
    first="$(TZ=UTC date -j -f '%Y-%m-%dT%H:%M:%SZ' "$first" +%s 2>/dev/null || echo "")"
    if [[ "$ks" =~ ^[0-9]+$ && "$first" =~ ^[0-9]+$ ]] && (( first < ks )); then
      pcq_remove "$row"; log "self-close pane=$pane dropped: the row predates the running kitty"; return
    fi
  fi
  if _retrier_alive "$row"; then log "self-close pane=$pane retrier $(pcq_get "$row" retrier_pid) alive — skipped"; return; fi
  if [[ "$(pcq_get "$row" paged)" == 1 ]]; then
    log "self-close pane=$pane already paged — held for handoff-fire"
  else
    page "pane-close-retry: self-close of pane $pane (sid $(pcq_get "$row" sid)) never completed and its retrier is gone — reason $(pcq_get "$row" reason), since $(pcq_get "$row" first_ts). Row: $row"
    pcq_add self-close "$pane" paged=1 >/dev/null 2>&1 || true
    log "self-close pane=$pane retrier gone — paged once"
  fi
  [[ "$(pcq_get "$row" notified)" == 1 ]] || NOTIFY_ROWS="$NOTIFY_ROWS$row"$'\n'
}
# Once kitty answers, a row of THIS kitty is judged against its window list (C6): nothing else ever
# spends a row whose session died with its pane, so 7 of 8 live rows named panes long gone.
_sc_this_kitty() { # <row> → rc 0 iff the row was written in the running kitty
  local kpid ks first
  kpid="$(pcq_get "$1" kitty_pid)"
  if [[ -n "$kpid" ]]; then [[ -n "$LIVE_GEN" && "$kpid" == "$LIVE_GEN" ]]; return; fi
  ks="$(_kitty_start_epoch)"
  first="$(TZ=UTC date -j -f '%Y-%m-%dT%H:%M:%SZ' "$(pcq_get "$1" first_ts)" +%s 2>/dev/null || echo "")"
  [[ "$ks" =~ ^[0-9]+$ && "$first" =~ ^[0-9]+$ ]] && (( first >= ks ))
}
REG_DIR="${CC_PCQ_REGISTRY_DIR:-$HOME/.claude/cc-registry}"
judge_self_close() { # <row> — uses $LS; removes the row when its pane is gone or another session holds it
  local row="$1" pane sid rsid
  [[ -f "$row" ]] && _sc_this_kitty "$row" || return 0
  pane="$(pcq_get "$row" pane)"
  if [[ -z "$(pane_window "$pane")" ]]; then
    pcq_remove "$row"; log "self-close pane=$pane ✓ pane gone — row removed"; return
  fi
  sid="$(pcq_get "$row" sid)"
  rsid="$(jq -r '.session_id // empty' "$REG_DIR/$pane.json" 2>/dev/null)"
  if [[ -n "$sid" && -n "$rsid" && "$rsid" != "$sid" ]]; then
    pcq_remove "$row"; log "self-close pane=$pane its registry names session $rsid, not the row's $sid — another session holds the pane; row removed, never acted on"
  fi
}

# ── husk rows: a pane KEPT with no claude in it (husk-panes-2026-10-22 F3) ──────────────────────────
# Written by cc-pane-runner's keep sites and the crash watchdog. The close itself is bin/cc-pane-close
# with its fail-closed gates unchanged (identity, nothing live, meant to end, clean tree): this only
# retries it, on every tick, until it closes or the row stops being a husk. Pane 42 (2026-10-22) was
# kept at 03:07Z because kitty was deaf; kitty answered at 04:28Z and nothing ever asked again.
# Holds, before the closer is asked:
#   a. kitty generation changed ⇒ the id names a stranger ⇒ row removed, never closed
#   b. (kitty answers) pane absent ⇒ gone; foreground not a bare shell ⇒ in use (a resume) ⇒ removed
#   c. its tty was READ since the drainer first saw the row (atime moved: someone typed) ⇒ the
#      operator took it over ⇒ removed, never closed. A bare shell at a prompt does not show that a
#      human has left it (skeptics.md F3). The baseline is taken at first sight, not by the producer,
#      because a shell's own start-up may read the tty (prompt themes query the terminal).
#   d. an OPEN custody row names this pane (opened in this kitty's lifetime) ⇒ its orchestrator may
#      still resume it ⇒ held, no attempt counted; bin/cc-custody return|abandon re-runs this drain.
# A refusal counts an attempt and pages once at CC_PCQ_MAX_ATTEMPTS, as teammate rows do.

# Count an unresolved attempt; page once when the count reaches MAX_ATTEMPTS. The row stays either way.
# Defined here, above the kitty gate, because the deaf branch drains husk rows too.
bump() { # <row> <pane> <why> [kind, default teammate]
  local row="$1" pane="$2" why="$3" kind="${4:-teammate}" n who
  n="$(pcq_get "$row" attempts)"; [[ "$n" =~ ^[0-9]+$ ]] || n=0; n=$((n + 1))
  pcq_add "$kind" "$pane" attempts="$n" last_verdict="$why" >/dev/null 2>&1 || true
  log "$kind pane=$pane attempt $n: $why — row kept"
  if (( n >= MAX_ATTEMPTS )) && [[ "$(pcq_get "$row" paged)" != 1 ]]; then
    who="$(pcq_get "$row" agent_id)"; [[ -n "$who" ]] || who="kept: $(pcq_get "$row" reason)"
    page "pane-close-retry: pane $pane ($who) still not closed after $n attempts since $(pcq_get "$row" first_ts): $why. Close it manually. Row: $row"
    pcq_add "$kind" "$pane" paged=1 >/dev/null 2>&1 || true
  fi
}
CUSTODY_BIN="${CC_PCQ_CUSTODY_BIN:-$HERE/../bin/cc-custody}"
CUSTODY_OPEN=""; CUSTODY_READ=0
_kitty_start_epoch() { # → the live kitty's start epoch, or nothing
  local l
  [[ -z "${CC_PCQ_KITTY_START_EPOCH:-}" ]] || { printf '%s' "$CC_PCQ_KITTY_START_EPOCH"; return 0; }   # test seam
  [[ -n "$LIVE_GEN" ]] || return 0
  l="$(ps -p "$LIVE_GEN" -o lstart= 2>/dev/null)"; [[ -n "$l" ]] || return 0
  LC_ALL=C date -j -f '%a %b %d %T %Y' "$(_norm "$l")" +%s 2>/dev/null || true
}
custody_open_for() { # <pane> <floor epoch> → rc 0 iff an open custody row names the pane, opened at/after floor
  local p="$1" floor="$2" ts ep
  if (( CUSTODY_READ == 0 )); then
    CUSTODY_READ=1
    [[ -x "$CUSTODY_BIN" ]] && CUSTODY_OPEN="$(bounded "$CUSTODY_BIN" list --open --json 2>/dev/null \
      | jq -r 'def cell(ph): (if . == null then "" else . end) | tostring
                             | gsub("[\\t\\r\\n]"; " ") | if . == "" then ph else . end;
               .[]? | select((.targetPane // "") != "") | [(.targetPane | cell("-")), (.ts | cell("-"))] | @tsv' 2>/dev/null)"
  fi
  while IFS=$'\t' read -r tp ts; do
    [[ "$tp" == "$p" ]] || continue
    ep="$(TZ=UTC date -j -f '%Y-%m-%dT%H:%M:%SZ' "$ts" +%s 2>/dev/null || echo 0)"
    (( ep >= floor )) && return 0
  done <<<"$CUSTODY_OPEN"
  return 1
}
#   e. hold=operator (C4): the closer's fullscreen guard refused it as the LAST pane of its OS window
#      (pane 165 on 2026-10-22). Only the operator's ⌘W can close that, so it is paged once and no
#      longer asked or counted while that window holds the same number of panes; a change releases it.
os_window_of() { # <pane> → "<os window id> <windows across its tabs>" from $LS, or nothing
  jq -r --arg p "$1" '[.[]? | select([.tabs[]?.windows[]?.id | tostring] | index($p))
                      | "\(.id) \([.tabs[]?.windows[]?] | length)"][0] // empty' <<<"$LS" 2>/dev/null
}
husk_rows_oldest_first() { # → husk row paths, least recently tried (oldest last_ts) first
  local r
  while IFS= read -r r; do
    [[ "$(pcq_get "$r" kind)" == husk ]] && printf '%s\t%s\n' "$(pcq_get "$r" last_ts)" "$r"
  done <<<"$ROWS" | LC_ALL=C sort | cut -f2-
}
drain_husk() { # uses $LS when kitty answered; LS="" means deaf (no pane/foreground read possible)
  local row="$1" pane kpid win t at base floor first out rc pc ow hold
  pane="$(pcq_get "$row" pane)"; kpid="$(pcq_get "$row" kitty_pid)"
  [[ "$pane" =~ ^[0-9]+$ ]] || { pcq_remove "$row"; log "husk pane=$pane not a kitty window id — row removed"; return; }
  if [[ -n "$kpid" && -n "$LIVE_GEN" && "$kpid" != "$LIVE_GEN" ]]; then
    pcq_remove "$row"; log "husk pane=$pane kitty generation changed ($kpid → $LIVE_GEN) — row removed, never closed"; return
  fi
  if [[ -n "$LS" ]]; then
    win="$(pane_window "$pane")"
    [[ -n "$win" ]] || { pcq_remove "$row"; log "husk pane=$pane ✓ pane gone — row removed"; return; }
    shell_only "$win" || { pcq_remove "$row"; log "husk pane=$pane foreground is not a bare shell — in use, row removed"; return; }
  fi
  t="$(pcq_get "$row" tty)"
  if [[ -n "$t" && -e "$t" ]] && at="$(stat -f %a "$t" 2>/dev/null)" && [[ "$at" =~ ^[0-9]+$ ]]; then
    base="$(pcq_get "$row" tty_atime)"
    if [[ ! "$base" =~ ^[0-9]+$ ]]; then
      pcq_add husk "$pane" tty_atime="$at" >/dev/null 2>&1 || true
    elif (( at > base )); then
      first="$(pcq_get "$row" first_ts)"   # read before the remove: after it the row is gone and the log said "since "
      pcq_remove "$row"; log "husk pane=$pane its tty was typed in since $first — the operator owns it; row removed, never closed"; return
    fi
  fi
  if [[ "$(pcq_get "$row" hold)" == operator ]]; then
    [[ -n "$LS" ]] || { log "husk pane=$pane held for the operator (⌘W) — kitty is deaf, its window unread"; return; }
    ow="$(os_window_of "$pane")"; hold="$(pcq_get "$row" hold_os_window) $(pcq_get "$row" hold_windows)"
    if [[ "$ow" == "$hold" ]]; then log "husk pane=$pane held for the operator (⌘W) — its window is unchanged"; return; fi
    pcq_add husk "$pane" hold= >/dev/null 2>&1 || true
    log "husk pane=$pane hold released — its window changed (os window + panes: $hold → ${ow:-?})"
  fi
  floor="$(_kitty_start_epoch)"
  if [[ -z "$floor" ]]; then   # no kitty start: a day before the row, so a reused id's old debt is not read as this pane's
    first="$(pcq_get "$row" first_ts)"
    floor="$(TZ=UTC date -j -f '%Y-%m-%dT%H:%M:%SZ' "$first" +%s 2>/dev/null || echo 0)"; floor=$(( floor > 86400 ? floor - 86400 : 0 ))
  fi
  if custody_open_for "$pane" "$floor"; then
    log "husk pane=$pane an open custody row names it — held until it is returned or abandoned"; return
  fi
  if (( BUDGET_S - SECONDS < 30 )); then
    log "husk pane=$pane deferred — within 30s of the run's ${BUDGET_S}s bound"; return
  fi
  pc="${CC_PCQ_PANE_CLOSE_BIN:-$HERE/../bin/cc-pane-close}"
  [[ -x "$pc" ]] || { bump "$row" "$pane" "cc-pane-close not executable at $pc" husk; return; }
  local ct="${CC_PCQ_CLOSE_TIMEOUT_S:-60}"
  if [[ -n "$LS" ]]; then out="$(TIMEOUT_S="$ct" bounded "$pc" --pane "$pane" 2>&1 </dev/null)"; rc=$?
  else out="$(CC_PANE_CLOSE_REMOTE=off TIMEOUT_S="$ct" bounded "$pc" --pane "$pane" 2>&1 </dev/null)"; rc=$?; fi
  case "$out" in
    *": CLOSED"*|*": NOTHING TO CLOSE"*|*": ALREADY CLOSED"*)
      pcq_remove "$row"; log "husk pane=$pane ✓ ${out//$'\n'/ }"; return ;;
  esac
  # The closer was cut off and said nothing: there is no answer to repaint from (C4c). A timeout is
  # its own class (FIX-DESIGN §4 W3): it says the box was slow, not that the pane refused, so it is
  # counted apart and never toward the attempts page — 25 of the closer's rows were rc 124 (census).
  if (( rc == 124 )) && [[ -z "$out" ]]; then
    local nt; nt="$(pcq_get "$row" timeouts)"; [[ "$nt" =~ ^[0-9]+$ ]] || nt=0; nt=$((nt + 1))
    pcq_add husk "$pane" timeouts="$nt" last_verdict=timeout >/dev/null 2>&1 || true
    log "husk pane=$pane closer exceeded its ${ct}s bound (timeout $nt) — row kept, not counted as an attempt"
    jq -nc --arg ts "$(date -u +%FT%TZ)" --arg p "$pane" --arg r "cc-pane-close rc=124 with no output after ${ct}s (pane-close-retry)" \
      --arg sid "$(pcq_get "$row" sid)" '{ts: $ts, pane: $p, verdict: "timeout", reason: $r, sid: $sid}' \
      >> "${CC_PANE_CLOSE_LOG:-$HOME/.claude/logs/pane-close.jsonl}" 2>/dev/null || true
    return
  fi
  # The last pane of a fullscreen OS window: operator-only, so held and paged once, never counted (C4a).
  if [[ "$out" == *refused-fs* && -n "$LS" ]] && ow="$(os_window_of "$pane")" && [[ "$ow" == *" 1" ]]; then
    pcq_add husk "$pane" hold=operator hold_windows=1 hold_os_window="${ow% *}" paged=1 >/dev/null 2>&1 || true
    page "pane-close-retry: ⌘W pane $pane on its Desktop — the last pane of a fullscreen window; only the operator can close it. Row: $row"
    log "husk pane=$pane the last pane of fullscreen OS window ${ow% *} — held for the operator (⌘W), paged once"
  else
    bump "$row" "$pane" "cc-pane-close rc=$rc: ${out//$'\n'/ }" husk
  fi
  # The pane's screen follows the facts (F5): cc-pane-verdict re-derives its state from the closer's
  # answer and repaints only when that state changed since the last paint.
  local pv="${CC_PCQ_VERDICT_BIN:-$HERE/../bin/cc-pane-verdict}"
  [[ -x "$pv" ]] && TIMEOUT_S=15 bounded "$pv" --pane "$pane" --recompute --reason "$(pcq_get "$row" reason)" \
    --closer-out "$out" --sid "$(pcq_get "$row" sid)" --tty "$t" --kitty-pid "$kpid" >/dev/null 2>&1 </dev/null
  return 0
}

N_TEAM=0 N_RCY=0 N_HUSK=0 N_SC=0
while IFS= read -r _row <&3; do
  case "$(pcq_get "$_row" kind)" in
    # A surviving self-close row counts toward the gate: only kitty's list can say its pane is gone (C6).
    self-close) drain_self_close "$_row"; [[ -f "$_row" ]] && N_SC=$((N_SC + 1)) ;;
    teammate)   N_TEAM=$((N_TEAM + 1)) ;;
    recycle)    _p="$(pcq_get "$_row" pane)"
                if [[ "${_p##*:}" =~ ^[0-9]+$ ]]; then N_RCY=$((N_RCY + 1))
                else pcq_remove "$_row"; log "recycle pane=$_p not a kitty window id — row removed"; fi ;;
    husk)       N_HUSK=$((N_HUSK + 1)) ;;
  esac
done 3<<<"$ROWS"
(( N_TEAM > 0 || N_RCY > 0 || N_HUSK > 0 || N_SC > 0 )) || [[ -n "$NOTIFY_ROWS" ]] || exit 0

# ── the gate: does kitty remote control answer? ────────────────────────────────────────────────
# SOCK/LIVE_GEN were resolved near the top (the live socket first, then a row's recorded one).

kls() { [[ -n "$KITTY" && -n "$SOCK" ]] || return 1; bounded "$KITTY" @ --to "$SOCK" ls 2>/dev/null; }
LS=""
# Replaces $LS only with a READABLE listing: a failed re-list must never become an empty one, which
# pane_window would read as "every pane gone" and remove the rows after it.
_ls_fresh() {
  local out
  out="$(kls)" && jq -e 'type == "array"' >/dev/null 2>&1 <<<"$out" || return 1
  LS="$out"
}
pane_window() { # <pane> → that window's JSON from $LS, or nothing
  jq -c --arg p "$1" '[.[]?.tabs[]?.windows[]? | select((.id | tostring) == $p)][0] // empty' <<<"$LS" 2>/dev/null
}
if ! _ls_fresh; then
  # ── A DEAF KITTY IS NOT A REASON TO HOLD A HUSK (2026-10-01) ─────────────────────────────────
  # Holding every row until remote control answers left panes 69 and 76 open for hours while
  # kitty refused connections. bin/cc-pane-close closes a pane by signalling its window shell — no
  # socket — behind its own fail-closed gates (identity by watchdog registration + window start
  # time, nothing live, a teammate/ruled-done session, no uncommitted work), so a teammate row is
  # handed to it here. Its refusal keeps the row exactly as before, with the refusal logged.
  PC_BIN="${CC_PCQ_PANE_CLOSE_BIN:-$HERE/../bin/cc-pane-close}"
  _held=0
  while IFS= read -r _row <&3; do
    [[ "$(pcq_get "$_row" kind)" == teammate ]] || continue
    _p="$(pcq_get "$_row" pane)"
    if [[ -x "$PC_BIN" && "$_p" =~ ^[0-9]+$ ]] \
       && _out="$(CC_PANE_CLOSE_REMOTE=off bounded "$PC_BIN" --pane "$_p" 2>&1 </dev/null)"; then
      pcq_remove "$_row"; log "teammate pane=$_p ✓ closed without remote control — ${_out//$'\n'/ }"
    else
      _held=$((_held + 1)); log "teammate pane=$_p held — kitty unresponsive and cc-pane-close did not close it: ${_out:-<not run>}"
    fi
    _out=""
  done 3<<<"$ROWS"
  # husk rows take the same no-socket path, through drain_husk's own holds (it reads LS="" as deaf).
  while IFS= read -r _row <&3; do
    [[ -n "$_row" ]] && drain_husk "$_row"
  done 3< <(husk_rows_oldest_first)
  (( N_RCY == 0 )) || log "kitty unresponsive — $N_RCY owed recycle(s) held until it answers"
  log "kitty unresponsive — $_held row(s) held (sock=${SOCK:-none})"
  exit 0
fi

# The terminal answers now, so a self-close that aborted because it did not can simply be re-run.
# Sent to the pane the session lives in, once per row (notified=1 whatever the rc: a note that
# cannot land is not worth repeating every 10 minutes; the desk page above is the durable signal).
NOTIFY_BIN="${CC_PCQ_NOTIFY_BIN:-$HERE/../bin/cc-notify}"
[[ -x "$NOTIFY_BIN" ]] || NOTIFY_BIN="$HOME/.claude/bin/cc-notify"
while IFS= read -r _row <&3; do
  [[ "$(pcq_get "$_row" kind)" == self-close ]] && judge_self_close "$_row"
done 3<<<"$ROWS"
while IFS= read -r _row <&3; do
  [[ -n "$_row" && -f "$_row" ]] || continue
  _p="$(pcq_get "$_row" pane)"
  bounded "$NOTIFY_BIN" "$_p" "SELF-CLOSE RETRY: your self-close of pane $_p aborted at $(pcq_get "$_row" first_ts) because the terminal did not answer; it answers now — re-run: handoff-fire.sh self-close $(pcq_get "$_row" argv)" \
    >/dev/null 2>&1 </dev/null; _rc=$?
  pcq_add self-close "$_p" notified=1 >/dev/null 2>&1 || true
  log "self-close pane=$_p terminal answers — told the session to re-run its self-close (cc-notify rc=$_rc)"
done 3<<<"$NOTIFY_ROWS"
(( N_TEAM > 0 || N_RCY > 0 || N_HUSK > 0 )) || exit 0

# rc 0 running · 1 not · 2 cannot tell. The FIRST argv word must be claude/claude.exe and the id must
# sit in a real `--agent-id <id>` pair: a brief that merely MENTIONS the id (memory:
# pgrep-f-matches-agent-briefs) is in some other process's argv and never counts.
member_running() {
  local id="$1" tbl
  [[ -n "$id" ]] || return 2
  if [[ -n "${CC_PCQ_PS_FILE:-}" ]]; then tbl="$(cat "$CC_PCQ_PS_FILE" 2>/dev/null)"
  else tbl="$(ps -axo pid=,command= 2>/dev/null)"; fi
  [[ -n "$tbl" ]] || return 2
  printf '%s\n' "$tbl" | awk -v id="$id" '
    { b = $2; sub(/.*\//, "", b); if (b != "claude" && b != "claude.exe") next
      for (i = 3; i < NF; i++) if ($i == "--agent-id" && $(i + 1) == id) { f = 1; exit } }
    END { exit !f }'
}

shell_only() { # <window json> → rc 0 iff it has foreground processes and every one is a login shell
  jq -e '(.foreground_processes // []) as $fp | ($fp | length) > 0
         and all($fp[]; ((.cmdline[0] // "") | sub(".*/"; "")) as $b
                        | ["zsh","bash","sh","-zsh","-bash","-sh","login"] | any(. == $b))' \
    <<<"$1" >/dev/null 2>&1
}

drain_teammate() {
  local row="$1" pane agent kpid win rc
  pane="$(pcq_get "$row" pane)"; agent="$(pcq_get "$row" agent_id)"; kpid="$(pcq_get "$row" kitty_pid)"
  [[ "$pane" =~ ^[0-9]+$ ]] || { bump "$row" "$pane" "id is not a kitty window id"; return; }
  win="$(pane_window "$pane")"
  if [[ -z "$win" ]]; then
    pcq_remove "$row"; log "teammate pane=$pane ✓ pane gone — row removed"; return
  fi
  if [[ -n "$kpid" && -n "$LIVE_GEN" && "$kpid" != "$LIVE_GEN" ]]; then
    pcq_remove "$row"
    log "teammate pane=$pane kitty generation changed ($kpid → $LIVE_GEN) — the id names a different window now; row removed, never closed"
    return
  fi
  [[ -n "$kpid" && -n "$LIVE_GEN" ]] \
    || { bump "$row" "$pane" "kitty generation unverifiable (row ${kpid:-?}, live ${LIVE_GEN:-?}) — not closing"; return; }
  member_running "$agent"; rc=$?
  if (( rc == 0 )); then log "teammate pane=$pane member $agent still running — not a husk yet, held"; return; fi
  (( rc == 1 )) || { bump "$row" "$pane" "member liveness unreadable (agent_id='$agent')"; return; }
  if ! shell_only "$win"; then
    log "teammate pane=$pane foreground is not shell-only — not a husk, held"; return
  fi
  ( export CC_TERM=kitty CC_TERM_KITTY_TO="$SOCK"
    bounded "$IT2" session close -f -s "$pane" --expect-generation "$kpid" >/dev/null 2>&1 ); rc=$?
  if (( rc != 0 )); then
    bump "$row" "$pane" "close rc=$rc (124 may still execute — the next run re-reads first)"; return
  fi
  if _ls_fresh && [[ -z "$(pane_window "$pane")" ]]; then
    pcq_remove "$row"; log "teammate pane=$pane ✓ closed and verified gone — row removed"
  else
    bump "$row" "$pane" "close rc=0 but the pane is still listed, or the re-list did not answer"
  fi
}

# ── recycle rows: a recycle handoff-fire HELD because kitty did not answer (pane-lifecycle item 4d) ─
# Never an act on the pane: nothing here types, closes or waits. Once kitty answers, the session is
# told ONCE to re-run its own recycle as its own Bash call — the call's output then reaches the session
# that owns the consequences, which no helper here could arrange. Measured before this was built
# (2026-10-01, /tmp/wake-coverage-2026-10-01.md): mail to an idle session woke it 92.9% of the time
# (287/309, 95% CI 89.5-95.3), falling to 31% after 1-4 h idle and 0% past ~4 h, so a note that lands
# during a long outage may wait for the next human turn; the row is the durable record either way.
# Removed, never acted on, when its window is gone or kitty has restarted (ids restart at 1, so the id
# names a stranger); a later recycle of the pane that arms its watcher removes it from handoff-fire.
drain_recycle() {
  local row="$1" pane id gen
  pane="$(pcq_get "$row" pane)"; id="${pane##*:}"
  [[ "$(pcq_get "$row" kitty_sock)" =~ .*kitty-([0-9]+) ]] && gen="${BASH_REMATCH[1]}" || gen=""
  if [[ -n "$gen" && -n "$LIVE_GEN" && "$gen" != "$LIVE_GEN" ]]; then
    pcq_remove "$row"; log "recycle pane=$pane kitty generation changed ($gen → $LIVE_GEN) — row removed, nobody told"; return
  fi
  if [[ "$id" =~ ^[0-9]+$ && -z "$(pane_window "$id")" ]]; then
    pcq_remove "$row"; log "recycle pane=$pane ✓ pane gone — row removed"; return
  fi
  # A REMOTE ROW IS NEVER HANDED TO ITS SUBJECT (R2, docs/plans/LIMIT_RECOVER_SELF_INPLACE.md). The
  # remote form (a move-lane worker's handoff-fire --recycle --source-pane P --source-session S) files
  # its row keyed on P, the SUBJECT's pane, holding the WORKER's argv. Mailing it told the subject to
  # run, from inside its own turn, a remote-form command about itself — one that can never pass the
  # at-rest proof — while the worker still held the claim and lr-handoff had already aborted the admit
  # (tombstone, lock, target copy withdrawn), so the argv was dead and two actuators acted on one
  # admit. The actuator that filed the row owns its retry. form=remote is the new key; a legacy row
  # has no form, so its argv decides; an explicit form=self stays a self row. Checked before
  # "already told" so a remote row mailed by the old code is cleaned up too.
  # CC_PCQ_REMOTE_RECYCLE_DROP=off restores mailing.
  local form argv record_id
  form="$(pcq_get "$row" form)"; argv="$(pcq_get "$row" argv)"
  if [[ "${CC_PCQ_REMOTE_RECYCLE_DROP:-on}" != off ]] \
     && { [[ "$form" == remote ]] || { [[ "$form" != self ]] && [[ "$argv" == *--source-pane* || "$argv" == *--source-session* ]]; }; }; then
    record_id="$(pcq_get "$row" record_id)"
    pcq_remove "$row"
    log "recycle pane=$pane remote form (its actuator owns the retry: record ${record_id:-?}) — row removed, the subject is never told to run another actuator's argv"
    return
  fi
  if [[ "$(pcq_get "$row" notified)" == 1 ]]; then log "recycle pane=$pane already told — held until it recycles"; return; fi
  bounded "$NOTIFY_BIN" "$pane" "RECYCLE RETRY: your --recycle of pane $pane was held at $(pcq_get "$row" first_ts) because the terminal did not answer ($(pcq_get "$row" reason)); it answers now — re-run it as its own Bash call, bare (no outer timeout, no grep filter): handoff-fire.sh $(pcq_get "$row" argv)" \
    >/dev/null 2>&1 </dev/null; _rc=$?
  pcq_add recycle "$pane" notified=1 >/dev/null 2>&1 || true
  log "recycle pane=$pane terminal answers — told the session to re-run its recycle (cc-notify rc=$_rc)"
}

while IFS= read -r _row <&3; do
  case "$(pcq_get "$_row" kind)" in
    teammate) drain_teammate "$_row" ;;
    recycle)  drain_recycle "$_row" ;;
  esac
done 3<<<"$ROWS"
# Husks last and least recently tried first (C4d): a run cut off by its bound used to drop the same
# alphabetically-last row every time.
while IFS= read -r _row <&3; do
  [[ -n "$_row" ]] && drain_husk "$_row"
done 3< <(husk_rows_oldest_first)
exit 0
