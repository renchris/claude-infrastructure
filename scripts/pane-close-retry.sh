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
# kitty: once kitty answers, the session is told once to re-run it; see drain_recycle below.
#
# self-close rows belong to handoff-fire's own retrier: this never acts on them. If that retrier is
# gone it pages the desk once, BEFORE the kitty gate (a dead retrier is news precisely while kitty is
# deaf), and once kitty answers it tells the session once, via cc-notify, to re-run its self-close.
#
# Never fatal, `set -u`, every external call bounded. One log line per row per run.
# Seams: CC_PCQ_KITTY_BIN · CC_PCQ_IT2_BIN · CC_PCQ_PS_FILE (a `ps -axo pid=,command=` capture) ·
#        CC_PCQ_PAGE_BIN · CC_PCQ_NOTIFY_BIN · CC_PCQ_KITTY_SOCKET_BIN · CC_PCQ_TIMEOUT_S · CC_PCQ_MAX_ATTEMPTS · CC_PCQ_LOG
#        · CC_PANE_CLOSE_QUEUE_DIR (the lib's).

set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
# shellcheck disable=SC1091  # runtime-resolved source; the ship gate runs shellcheck without -x
. "$HERE/lib/pane-close-queue.sh" 2>/dev/null || exit 0

LOG="${CC_PCQ_LOG:-$HOME/.claude/logs/pane-close-retry.log}"
MAX_ATTEMPTS="${CC_PCQ_MAX_ATTEMPTS:-6}"; [[ "$MAX_ATTEMPTS" =~ ^[0-9]+$ ]] || MAX_ATTEMPTS=6
TIMEOUT_S="${CC_PCQ_TIMEOUT_S:-10}"
PAGE_BIN="${CC_PCQ_PAGE_BIN:-$HERE/../bin/cc-desk-page}"
mkdir -p "$(dirname "$LOG")" 2>/dev/null || true
log() { printf '%s %s\n' "$(date -u +%FT%TZ)" "$*" >> "$LOG" 2>/dev/null || true; }

ROWS="$(pcq_list)"
[[ -n "$ROWS" ]] || exit 0          # the common case: nothing queued, and kitty is never asked
command -v jq >/dev/null 2>&1 || { log "jq missing — every row held"; exit 0; }

# Same bounding idiom as hooks/teammate-auto-shutdown.sh tas_bounded: a launchd PATH has no coreutils
# `timeout`, so the absolute Homebrew paths are searched too; absent everywhere ⇒ unbounded, never
# a refusal to run.
PCQ_TIMEOUT_BIN=""
for _c in "$(command -v timeout 2>/dev/null || true)" "$(command -v gtimeout 2>/dev/null || true)" \
          /opt/homebrew/bin/timeout /usr/local/bin/timeout /opt/homebrew/bin/gtimeout /usr/local/bin/gtimeout; do
  [[ -n "$_c" && -x "$_c" ]] && { PCQ_TIMEOUT_BIN="$_c"; break; }
done
bounded() {
  if [[ -z "$PCQ_TIMEOUT_BIN" ]]; then "$@"; return $?; fi
  "$PCQ_TIMEOUT_BIN" -k 3 "$TIMEOUT_S" "$@"
}

page() { "$PAGE_BIN" --source pane-close-retry "$1" >/dev/null 2>&1 || true; }

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
  cur="$(ps -p "$rpid" -o lstart= 2>/dev/null)"
  [[ -n "$cur" && "$(_norm "$cur")" == "$(_norm "$rlst")" ]]
}
NOTIFY_ROWS=""
drain_self_close() {
  local row="$1" pane
  pane="$(pcq_get "$row" pane)"
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

N_TEAM=0 N_RCY=0
while IFS= read -r _row <&3; do
  case "$(pcq_get "$_row" kind)" in
    self-close) drain_self_close "$_row" ;;
    teammate)   N_TEAM=$((N_TEAM + 1)) ;;
    recycle)    N_RCY=$((N_RCY + 1)) ;;
  esac
done 3<<<"$ROWS"
(( N_TEAM > 0 || N_RCY > 0 )) || [[ -n "$NOTIFY_ROWS" ]] || exit 0

# ── the gate: does kitty remote control answer? ────────────────────────────────────────────────
# The LIVE socket first, then a row's recorded one. A row's socket can name a kitty that has since
# restarted: asking it would hold every row forever, and comparing a row against its own socket
# could never notice the generation change in (b).
KITTY="${CC_PCQ_KITTY_BIN:-$("$HERE/../bin/cc-kitty-bin" 2>/dev/null || command -v kitty 2>/dev/null || true)}"
IT2="${CC_PCQ_IT2_BIN:-$(command -v it2 2>/dev/null || echo "$HOME/.claude/bin/it2")}"
SOCK="${KITTY_LISTEN_ON:-}"
[[ -n "$SOCK" ]] || SOCK="$("${CC_PCQ_KITTY_SOCKET_BIN:-$HERE/../bin/cc-kitty-socket}" 2>/dev/null || true)"
if [[ -z "$SOCK" ]]; then
  while IFS= read -r _row <&3; do
    SOCK="$(pcq_get "$_row" kitty_sock)"; [[ -n "$SOCK" ]] && break
  done 3<<<"$ROWS"
fi
LIVE_GEN=""
[[ "$SOCK" =~ .*kitty-([0-9]+) ]] && LIVE_GEN="${BASH_REMATCH[1]}"

kls() { [[ -n "$KITTY" && -n "$SOCK" ]] || return 1; bounded "$KITTY" @ --to "$SOCK" ls 2>/dev/null; }
LS=""
# Replaces $LS only with a READABLE listing: a failed re-list must never become an empty one, which
# pane_window would read as "every pane gone" and remove the rows after it.
_ls_fresh() {
  local out
  out="$(kls)" && jq -e 'type == "array"' >/dev/null 2>&1 <<<"$out" || return 1
  LS="$out"
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
  [[ -n "$_row" ]] || continue
  _p="$(pcq_get "$_row" pane)"
  bounded "$NOTIFY_BIN" "$_p" "SELF-CLOSE RETRY: your self-close of pane $_p aborted at $(pcq_get "$_row" first_ts) because the terminal did not answer; it answers now — re-run: handoff-fire.sh self-close $(pcq_get "$_row" argv)" \
    >/dev/null 2>&1 </dev/null; _rc=$?
  pcq_add self-close "$_p" notified=1 >/dev/null 2>&1 || true
  log "self-close pane=$_p terminal answers — told the session to re-run its self-close (cc-notify rc=$_rc)"
done 3<<<"$NOTIFY_ROWS"
(( N_TEAM > 0 || N_RCY > 0 )) || exit 0

pane_window() { # <pane> → that window's JSON from $LS, or nothing
  jq -c --arg p "$1" '[.[]?.tabs[]?.windows[]? | select((.id | tostring) == $p)][0] // empty' <<<"$LS" 2>/dev/null
}

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

# Count an unresolved attempt; page once when the count reaches MAX_ATTEMPTS. The row stays either way.
bump() {
  local row="$1" pane="$2" why="$3" n
  n="$(pcq_get "$row" attempts)"; [[ "$n" =~ ^[0-9]+$ ]] || n=0; n=$((n + 1))
  pcq_add teammate "$pane" attempts="$n" last_verdict="$why" >/dev/null 2>&1 || true
  log "teammate pane=$pane attempt $n: $why — row kept"
  if (( n >= MAX_ATTEMPTS )) && [[ "$(pcq_get "$row" paged)" != 1 ]]; then
    page "pane-close-retry: pane $pane ($(pcq_get "$row" agent_id)) still not closed after $n attempts since $(pcq_get "$row" first_ts): $why. Close it manually. Row: $row"
    pcq_add teammate "$pane" paged=1 >/dev/null 2>&1 || true
  fi
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
exit 0
