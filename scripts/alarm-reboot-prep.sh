#!/usr/bin/env bash
# alarm-reboot-prep.sh — the agent half of the safe reboot order, run whenever the capacity alarm's
# kalloc rung fires (host-memory.2 of the 2026-09-30 backlog master plan).
#
# WHY A STANDING PROCEDURE. data.kalloc.1024 is a kernel zone only a reboot resets, and on 2026-10-18
# it panicked the box at 20,955,520 elements (~20 GiB) after 18 days up; it grew 1-4.4 GiB/day
# (docs/research/panic-2026-10-18-zone-map-shebang-leak.md). The first reboot, on 2026-09-30, went
# in a safe order; this script is that order, so every later one repeats it instead of improvising:
#
#   0. THE HEAD: the zone's level now, its share of the ceiling and the ETA to it (slope and ceiling
#      from the capacity alarm's <dir>/kalloc-zone.state), printed before anything else. On 10-17
#      the operator was told to reboot for load reasons with the 18 GB zone never mentioned.
#
#   1. record the start epoch        ~/.claude/autonomy/reboot-<date>.start
#      and the OWNER session          ~/.claude/autonomy/reboot-<date>.owner  ($CLAUDE_CODE_SESSION_ID,
#      one line, its own file: never appended to .start, see step 4). boot-resume.sh passes it to the
#      classifier as --owner, so the session that asked for the reboot is always prompted after it
#      (2026-10-21: the lead that ran this sat idle with its promised follow-up in hand).
#   2. record the live-session roster ~/.claude/autonomy/reboot-<date>.roster.json  (cc-sessions --json;
#      the resume path relaunches from it after login)
#   3. wait while a land is in flight (a ship-land.sh PROCESS) — a reboot mid-push strands the land.
#      It WAITS, bounded, with the deadline printed (CC_REBOOT_PREP_LAND_WAIT_S, default 1800 s),
#      rather than refusing: on 10-12 a refusal put a reboot off and nothing ever re-ran it. Past the
#      deadline it still records everything below and ends NOT-READY.
#      PHASE-AWARE (2026-10-21): a land's own subshells and its locked child are one land, not two,
#      and a land whose in-flight marker says it has pushed (phase=pushed|post-release, written by
#      ship-land.sh) is reported "safe to reboot" and not waited for: on 10-21 a land that had pushed
#      and verified 30 minutes earlier, stuck in its stranded-sweep, made this script say NOT-READY.
#   3b. prune what an OS update's Template Migration crawls (R22): sockets in /private/tmp/cc-socks
#      whose pid is dead, and /private/tmp/claude-<uid>/<cwd>/<session> trees of sessions that are not
#      in the roster and wrote nothing for 6 h. On 10-21 the migration ran 1534 s, its log dominated by
#      26,234 dirs_cleaner lines about cc-socks. Only after a good roster read; never in --dry-run.
#   4. record the kalloc reading the reboot is about to erase ~/.claude/autonomy/reboot-<date>.kalloc
#      (its OWN file: appended to .start as a second line, it made boot-resume.sh skip every roster
#      this script wrote, because the reader took the whole file as the epoch — W3 P3a-i, 2026-10-04)
#   5. print the operator's steps, on EVERY path (a NOT-READY verdict used to skip them all): long-running leads write a handoff first; if a root zone capture
#      is staged (~/.claude/autonomy/kalloc-root-capture.cmd, written by the ratchet analysis when
#      it could not name a driver), run it BEFORE rebooting, because the reboot erases the evidence;
#      then reboot within 24 h of the alarm. If ~/.claude/autonomy/kitty-restart-pending exists,
#      this reboot is also the kitty restart (plan W3) and the script says so.
#
#   6. THE ARRANGEMENT (2026-10-13): take a restore heartbeat now (scripts/lib/restore-heartbeat.sh
#      hb_tick, stamped with step 1's epoch), so the record boot-resume.sh restores from holds kitty's
#      tree as it is at this moment: OS windows, tabs, split geometry, which session sits in which
#      pane, and the non-Claude panes with their cwd. cc-resume-layout.sh --restore already replays
#      such a tree; what was missing is one taken at the reboot instead of up to a tick before it, and
#      a check on it. The check: the tree was read in this run (up to CC_REBOOT_PREP_TRIES=3 tries,
#      15 s each: kitty's remote control times out under load) and every session pane is in it.
#      A tree that fails is marked <heartbeat dir>/hb.layout-degraded, and the restore then uses its
#      plain row layout for that kitty, never half of an arrangement.
#   7. THE DRAFTS (2026-10-13): save the text sitting unsent in each pane's prompt box to
#      ~/.claude/autonomy/reboot-<date>.drafts/<session id>/ (directory 700, files 600; a draft may
#      hold a secret). boot-resume.sh types each one back, unsent, into the pane its session came
#      back in and deletes it. Reading is `kitty @ get-text` only (scripts/lib/reboot-drafts.sh): this
#      script sends no key to any pane, clears no box and submits nothing. A box it cannot read (a
#      dialog over it) is counted and left alone. Draft directories older than 7 days are removed.
#
#   8. kitty reads NSAppSleepDisabled at start and the reboot is also a kitty start, so the script
#      sets it itself (`defaults write net.kovidgoyal.kitty NSAppSleepDisabled -bool YES`, read back
#      by a second call) instead of printing it as a step nobody ran.
#
# --dry-run: steps 6 and 7 against the live machine, writing no reboot record: the heartbeat goes to
# <dir>/reboot-prep-dryrun/, the tree is printed pane by pane, drafts are counted and not stored, and
# the cc-resume-layout.sh command that prints the restore plan for that capture is named.
#
# --arm-restart (R14): the last step before the operator clicks Restart, so the restart needs no other
# click. On 10-21 Software Update's restart was vetoed by Dia and then by kitty's "Quit kitty?" dialog
# (kitty.conf confirm_os_window_close -1) for 4.5 minutes. It (a) takes a final restore heartbeat, (b)
# runs `kitten @ load-config -o confirm_os_window_close=0` on every live kitty (kitty has no `@ quit`;
# a plain `kitten @ load-config` undoes it without restarting), and (c) lists running apps known to
# veto a restart, with the command that quits each. It quits nothing itself. The quit it enables is
# the same session teardown a confirmed dialog produced, so the restore reads it as the reboot cut.
#
# One run at a time: a mkdir lock (<dir>/.reboot-prep.lock.d) refuses a second concurrent run (exit 2);
# on 10-21 two overlapping runs left .start 30 minutes older than its roster.
#
# It never reboots, never kills a session and never runs sudo: those are the operator's.
# Exit: 0 READY / ARMED · 3 NOT-READY (a land that has not pushed was still in flight at the deadline;
#       re-run when it finishes) / NOT-ARMED (a kitty did not take the override) · 2 usage or another run.
# Env:  CC_REBOOT_PREP_DIR (default ~/.claude/autonomy) · CC_REBOOT_PREP_DATE (default today, local)
#       CC_REBOOT_PREP_PS (default /bin/ps; stub for tests) · CC_REBOOT_PREP_SESSIONS (default cc-sessions)
#       CC_REBOOT_PREP_ZPRINT (default /usr/bin/zprint) · CC_REBOOT_PREP_TRIES (3) ·
#       CC_REBOOT_PREP_LAND_WAIT_S (1800) · CC_REBOOT_PREP_LAND_POLL_S (15) ·
#       CC_REBOOT_PREP_LSOF (default /usr/sbin/lsof; a land's cwd, to find its marker) ·
#       CC_REBOOT_PREP_SOCKS_DIR (/private/tmp/cc-socks) · CC_REBOOT_PREP_CLAUDE_TMP (/private/tmp/claude-<uid>) ·
#       CC_REBOOT_PREP_DEFAULTS (default /usr/bin/defaults; never the real one under bats) ·
#       CC_REBOOT_PREP_KITTEN (default kitty.app's kitten) · CC_REBOOT_PREP_KITTY_SOCK_PREFIX (/tmp/kitty-) ·
#       CC_HEARTBEAT_DIR (default <dir>/heartbeat) and the heartbeat library's own seams
set -uo pipefail

DRY=0 ARM=0
case "${1:-}" in
  -h|--help) sed -n '2,/^set -uo/p' "$0" | sed '$d'; exit 0 ;;
  --dry-run) DRY=1 ;;
  --arm-restart) ARM=1 ;;
  '') ;;
  *) echo "usage: $0 [--dry-run | --arm-restart] [--help]" >&2; exit 2 ;;
esac

DIR="${CC_REBOOT_PREP_DIR:-$HOME/.claude/autonomy}"
DAY="${CC_REBOOT_PREP_DATE:-$(date +%Y-%m-%d)}"
PS="${CC_REBOOT_PREP_PS:-/bin/ps}"
LSOF="${CC_REBOOT_PREP_LSOF:-/usr/sbin/lsof}"
SESSIONS="${CC_REBOOT_PREP_SESSIONS:-cc-sessions}"
ZPRINT="${CC_REBOOT_PREP_ZPRINT:-/usr/bin/zprint}"
CAPTURE_CMD="$DIR/kalloc-root-capture.cmd"
mkdir -p "$DIR" || { echo "alarm-reboot-prep: cannot create $DIR" >&2; exit 2; }

# ── one run at a time (see the header) ─────────────────────────────────────────────────────────────
# mkdir is the atomic test-and-set. A lock whose holder pid is gone is stale (a killed run) and is
# taken over; a live holder refuses this run, naming it, rather than waiting on it.
LOCK="$DIR/.reboot-prep.lock.d"
if ! mkdir "$LOCK" 2>/dev/null; then
  holder="$(head -n 1 "$LOCK/pid" 2>/dev/null | tr -cd '0-9')"
  if [ -n "$holder" ] && kill -0 "$holder" 2>/dev/null; then
    echo "alarm-reboot-prep: another run is in flight (pid $holder, lock $LOCK) — not starting a second one; read its verdict, or re-run once it exits" >&2
    exit 2
  fi
  rm -f "$LOCK/pid" 2>/dev/null; rmdir "$LOCK" 2>/dev/null
  mkdir "$LOCK" 2>/dev/null || { echo "alarm-reboot-prep: cannot take the lock $LOCK" >&2; exit 2; }
fi
printf '%s\n' "$$" > "$LOCK/pid" 2>/dev/null
trap 'rm -f "$LOCK/pid" 2>/dev/null; rmdir "$LOCK" 2>/dev/null' EXIT

# bounded <seconds> <cmd...> — run it in its own process group and kill the group at the bound
# (exit 124), so a wedged defaults/kitten read cannot hold the reboot procedure open (E-8).
bounded() {
  local t="$1"; shift
  [ -x /usr/bin/perl ] || { "$@"; return $?; }
  /usr/bin/perl -e 'my $t = shift; my $p = fork; exit 125 unless defined $p;
    if (!$p) { setpgrp(0, 0); exec @ARGV; exit 127 }
    $SIG{ALRM} = sub { kill "KILL", -$p; exit 124 };
    alarm $t; waitpid($p, 0); exit($? >> 8)' "$t" "$@"
}

# The heartbeat (step 6, --arm-restart) and drafts (step 7) libraries resolve beside this file, then
# in the live layer; missing is loud, never fatal: the roster still restores the fleet.
HERE="$(cd "$(dirname "$0")" 2>/dev/null && pwd -P)"
for _lib in restore-heartbeat.sh reboot-drafts.sh; do
  for _c in "$HERE/lib/$_lib" "$HOME/.claude/scripts/lib/$_lib"; do
    # shellcheck disable=SC1090  # runtime-resolved source; the ship gate runs shellcheck without -x
    [ -f "$_c" ] && . "$_c" 2>/dev/null && break
  done
done
unset _lib _c

now="$(date +%s)"

# ── 0. the head: the zone level and the ETA, before anything else ──────────────────────────────────
# Bounded the way the capacity alarm bounds the same read (perl alarm, output to a file): a zprint
# wedged in the kernel must not hold the reboot procedure open. Empty ⇒ "unreadable", never 0.
zone_bytes() {
  local out b=""
  [ -x /usr/bin/perl ] || return 0
  out="$(mktemp "${TMPDIR:-/tmp}/reboot-prep-zp.XXXXXX" 2>/dev/null)" || return 0
  /usr/bin/perl -e 'my $t = shift; my $p = fork; exit 1 unless defined $p;
    if (!$p) { exec @ARGV; exit 127 }
    $SIG{ALRM} = sub { kill "KILL", $p; exit 124 };
    alarm $t; waitpid($p, 0); exit($? >> 8)' 10 "$ZPRINT" data.kalloc.1024 > "$out" 2>/dev/null
  b="$(awk '$1 == "data.kalloc.1024" && $2 ~ /^[0-9]+$/ && $7 ~ /^[0-9]+$/ { printf "%.0f", $2 * $7; exit }' "$out" 2>/dev/null)"
  rm -f "$out"
  printf '%s' "$b"
}
kz() { sed -n "s/^$1=//p" "$DIR/kalloc-zone.state" 2>/dev/null | head -1; }
kbytes="$(zone_bytes)"
kalloc=""; [ -n "$kbytes" ] && kalloc="$(awk -v b="$kbytes" 'BEGIN{printf "%.2f", b/1073741824}')"
kz_ceil="$(kz ceiling_gib)"; kz_slope="$(kz slope_gib_day)"; kz_ssrc="$(kz slope_src)"
zline="${kalloc:-unreadable}${kalloc:+ GiB}"
if [ -n "$kalloc" ] && [ -n "$kz_ceil" ]; then
  zline="$zline = $(awk -v g="$kalloc" -v c="$kz_ceil" 'BEGIN{printf "%.0f", 100 * g / c}')% of the ~$kz_ceil GiB panic ceiling"
  eta=""
  [ -n "$kz_slope" ] && eta="$(awk -v g="$kalloc" -v c="$kz_ceil" -v r="$kz_slope" 'BEGIN{
      if (g + 0 >= c + 0) printf "0.0"; else if (r + 0 > 0) printf "%.1f", (c - g) / r }')"
  if [ -n "$eta" ]; then
    zline="$zline · +$kz_slope GiB/day ($kz_ssrc) · ceiling in ~$eta d ($(date -r "$(awk -v n="$now" -v d="$eta" 'BEGIN{printf "%.0f", n + d * 86400}')" +%Y-%m-%d 2>/dev/null))"
  else
    zline="$zline · no ETA (slope ${kz_slope:-unknown})"
  fi
elif [ -n "$kalloc" ]; then
  zline="$zline · ceiling and ETA unknown (no capacity-alarm zone state at $DIR/kalloc-zone.state)"
fi
if [ "$DRY" = 1 ]; then
  echo "alarm-reboot-prep --dry-run — $(date '+%Y-%m-%d %H:%M %z') (no reboot record written)"
elif [ "$ARM" = 1 ]; then
  echo "alarm-reboot-prep --arm-restart — $(date '+%Y-%m-%d %H:%M %z')"
else
  echo "alarm-reboot-prep — $(date '+%Y-%m-%d %H:%M %z')"
fi
echo "  data.kalloc.1024   $zline"

# ── --arm-restart (R14, see the header): final heartbeat, kitty's quit dialog off, vetoing apps ───────
if [ "$ARM" = 1 ]; then
  # (a) the final heartbeat: an ordinary tick at this moment, so the restore record is seconds old.
  hb_v="NOT TAKEN — scripts/lib/restore-heartbeat.sh did not load"
  if command -v hb_tick >/dev/null 2>&1; then
    hb_tick >/dev/null 2>&1; hb_rc=$?
    case "$hb_rc" in 0) hb_v="taken" ;; *) hb_v="taken with errors (rc $hb_rc) — the restore falls back to the last good tick" ;; esac
  fi
  echo "  final heartbeat    $hb_v"
  # (b) every live kitty: its socket is <prefix><pid> (kitty.conf listen_on unix:/tmp/kitty-{kitty_pid}).
  kb="${CC_REBOOT_PREP_KITTEN:-}"
  [ -n "$kb" ] || { command -v _hb_kitten_bin >/dev/null 2>&1 && kb="$(_hb_kitten_bin)"; }
  kpre="${CC_REBOOT_PREP_KITTY_SOCK_PREFIX:-/tmp/kitty-}"
  n_k=0; n_kfail=0; k_line=""
  for s in "$kpre"*; do
    [ -S "$s" ] || continue
    kp="${s#"$kpre"}"; case "$kp" in ''|*[!0-9]*) continue ;; esac
    kill -0 "$kp" 2>/dev/null || continue                 # a socket left by a dead kitty
    n_k=$((n_k + 1))
    if [ -n "$kb" ] && bounded 15 "$kb" @ --to "unix:$s" load-config -o confirm_os_window_close=0 >/dev/null 2>&1; then
      k_line="${k_line} $kp:off"
    else
      n_kfail=$((n_kfail + 1)); k_line="${k_line} $kp:FAILED"
    fi
  done
  if [ "$n_k" = 0 ]; then
    echo "  kitty quit dialog  no live kitty found at ${kpre}<pid> — nothing to arm"
  elif [ "$n_kfail" = 0 ]; then
    echo "  kitty quit dialog  off for ${n_k} kitty(s):${k_line} (undo without restarting: kitten @ load-config)"
  else
    echo "  kitty quit dialog  ${n_kfail} of ${n_k} kitty(s) did NOT take the override:${k_line} — its \"Quit kitty?\" dialog will block the restart until answered"
  fi
  # (c) apps that can veto a restart: a quit dialog or unsaved work stops loginwindow's restart.
  veto_re="${CC_REBOOT_PREP_VETO_APPS:-Dia|Arc|Google Chrome|Firefox|Safari|Terminal|iTerm2|iTerm|Xcode|Cursor|Visual Studio Code|Code|Microsoft Word|Microsoft Excel|Microsoft PowerPoint}"
  vetoers="$("$PS" -axo pid=,ppid=,args= 2>/dev/null | sed -n 's|.*/\([^/]*\)\.app/Contents/MacOS/.*|\1|p' \
             | grep -Ex "$veto_re" | sort -u | paste -sd ',' - | sed 's/,/, /g')"
  if [ -n "$vetoers" ]; then
    echo "  can veto restart   $vetoers — quit them first (each: osascript -e 'quit app \"<name>\"'), or answer their dialog"
  else
    echo "  can veto restart   none of the known vetoing apps is running"
  fi
  if [ "$n_kfail" -gt 0 ]; then echo "verdict=NOT-ARMED reason=kitty-override"; exit 3; fi
  echo "verdict=ARMED"
  exit 0
fi

# ── 3. lands in flight: WAIT, bounded, deadline printed (see the header) ───────────────────────────
# A land in flight is a process whose PROGRAM is ship-land.sh (argv[0], or argv[1] under a shell) —
# never `pgrep -f ship-land.sh`, which also matches every agent session whose brief merely MENTIONS
# the name (measured 2026-09-30: 6 of 6 matches were claude sessions, 0 were lands).
# ONE LAND, ONE PID: a land's own subshells and its locked child (behind land-lock) run the same
# program, so a match whose ancestor is another match is dropped (10-21: the lander's subshell was
# counted as a second land).
find_lands() {
  "$PS" -axo pid=,ppid=,args= 2>/dev/null | awk '
    { pp[$1] = $2; a0 = $3; a1 = $4
      if (a0 ~ /(^|\/)ship-land\.sh$/ || (a0 ~ /(^|\/)(ba|z|da)?sh$/ && a1 ~ /(^|\/)ship-land\.sh$/)) land[$1] = 1 }
    END { for (p in land) { q = pp[p]; n = 0; drop = 0
            while (q != "" && q + 0 > 1 && n < 64) { if (q in land) { drop = 1; break }; q = pp[q]; n++ }
            if (!drop) print p } }' | sort -n | tr '\n' ' '
}
# land_phase <pid> → the phase ship-land.sh wrote into that land's in-flight marker (pre-push, pushed,
# post-release), or "unknown". The marker lives in the git dir of the land's cwd and must name <pid>:
# a marker naming another pid is somebody else's land.
land_phase() {
  local cwd gd f
  cwd="$(bounded 10 "$LSOF" -a -p "$1" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p' | head -n 1)"
  [ -n "$cwd" ] && gd="$(git -C "$cwd" rev-parse --absolute-git-dir 2>/dev/null)" || { echo unknown; return 0; }
  f="$gd/ship-land-inflight"
  [ "$(sed -n 's/^pid=//p' "$f" 2>/dev/null | head -n 1)" = "$1" ] || { echo unknown; return 0; }
  sed -n 's/^phase=//p' "$f" 2>/dev/null | head -n 1 | grep . || echo unknown
}
# classify_lands → lands (the pids a reboot would strand: not yet pushed, or phase unknown) and
# lands_safe ("pid (phase)" for lands past their push), in THIS shell.
classify_lands() {
  local p ph
  lands=""; lands_safe=""
  for p in $(find_lands); do
    ph="$(land_phase "$p")"
    case "$ph" in
      pushed|post-release) lands_safe="${lands_safe}${p} (${ph}) " ;;
      *) lands="${lands}${p} " ;;
    esac
  done
}
lands=""; lands_safe=""
if [ "$DRY" = 1 ]; then
  classify_lands       # read-only: reported below, never waited for
elif [ "$ARM" = 0 ]; then
  classify_lands
  if [ -n "${lands// /}" ]; then
    wait_s="${CC_REBOOT_PREP_LAND_WAIT_S:-1800}"; poll_s="${CC_REBOOT_PREP_LAND_POLL_S:-15}"
    case "$wait_s" in ''|*[!0-9]*) wait_s=1800 ;; esac
    case "$poll_s" in ''|*[!0-9]*|0) poll_s=15 ;; esac
    deadline=$((now + wait_s))
    echo "  lands in flight    pids ${lands% } — waiting for them to finish, deadline $(date -r "$deadline" '+%H:%M:%S') (${wait_s}s)"
    while [ -n "${lands// /}" ] && [ "$(date +%s)" -lt "$deadline" ]; do
      /bin/sleep "$poll_s"
      classify_lands
    done
    [ -z "${lands// /}" ] && echo "  lands in flight    finished or past their push after $(( $(date +%s) - now ))s"
    now="$(date +%s)"     # on EVERY path: the records below describe the machine after the wait
  fi
fi

roster="$DIR/reboot-$DAY.roster.json"
n=""
if [ "$DRY" = 0 ]; then
  printf '%s\n' "$now" > "$DIR/reboot-$DAY.start"
  if "$SESSIONS" --json > "$roster.tmp" 2>/dev/null && [ -s "$roster.tmp" ]; then
    mv -f "$roster.tmp" "$roster"
    n="$(grep -o '"paneUUID"' "$roster" 2>/dev/null | wc -l | tr -d ' ')"   # occurrences, not lines
  else
    rm -f "$roster.tmp"; n="unknown (cc-sessions failed — record the panes by hand)"
  fi
  # The OWNER (step 1): the session running this prep, one line in its own file. A run from outside
  # any session leaves an earlier owner of the same day in place rather than erasing it.
  owner_sid="$(printf '%s' "${CLAUDE_CODE_SESSION_ID:-}" | tr -cd 'A-Za-z0-9_-')"
  if [ -n "$owner_sid" ]; then
    printf '%s\n' "$owner_sid" > "$DIR/reboot-$DAY.owner.tmp" && mv -f "$DIR/reboot-$DAY.owner.tmp" "$DIR/reboot-$DAY.owner"
    owner_line="$owner_sid  → $DIR/reboot-$DAY.owner"
  elif [ -s "$DIR/reboot-$DAY.owner" ]; then
    owner_line="$(head -n 1 "$DIR/reboot-$DAY.owner") (kept from an earlier run today; this run is not inside a session)"
  else
    owner_line="none (not run from a Claude session; boot-resume prompts no owner)"
  fi
fi

# ── 3b. prune what Template Migration crawls (R22, see the header) ───────────────────────────────────
prune_line=""
# Under bats with the seams unset this deletes nothing on the real machine (a test once reached the
# live layer through an unset seam; restore-heartbeat.sh's header has the same rule).
under_bats_unseamed() { [ -n "${BATS_TEST_FILENAME:-}" ] && [ -z "${CC_REBOOT_PREP_SOCKS_DIR:-}" ]; }
if [ "$DRY" = 0 ] && [ -s "$roster" ] && [ "$n" -ge 0 ] 2>/dev/null && ! under_bats_unseamed; then
  socks="${CC_REBOOT_PREP_SOCKS_DIR:-/private/tmp/cc-socks}"; n_sock=0
  for s in "$socks"/*.sock; do
    [ -e "$s" ] || continue
    sp="${s##*/}"; sp="${sp%.sock}"; case "$sp" in ''|*[!0-9]*) continue ;; esac
    kill -0 "$sp" 2>/dev/null && continue
    rm -f "$s" 2>/dev/null && n_sock=$((n_sock + 1))
  done
  ctmp="${CC_REBOOT_PREP_CLAUDE_TMP:-/private/tmp/claude-$(id -u)}"; n_tree=0
  # Live = in the roster, this session, or named by a Claude Code pid file whose pid is alive
  # (<config>/sessions/<pid>.json; a session cc-sessions missed is still not pruned).
  live="$(jq -r '.[]? | select(type == "object") | .session_id // empty' "$roster" 2>/dev/null
          printf '%s\n' "${CLAUDE_CODE_SESSION_ID:-}"
          for pf in "${CC_REBOOT_PREP_CC_HOMES:-$HOME/.claude}"*/sessions/[0-9]*.json; do
            [ -f "$pf" ] || continue; pp="${pf##*/}"; pp="${pp%.json}"
            kill -0 "$pp" 2>/dev/null && jq -r '.sessionId // empty' "$pf" 2>/dev/null
          done)"
  for t in "$ctmp"/*/*/; do
    t="${t%/}"; [ -d "$t" ] && [ ! -L "$t" ] || continue
    ts="${t##*/}"
    case "$ts" in *[!0-9a-f-]*|'') continue ;; esac            # session-id shaped only
    [ "${#ts}" -ge 32 ] || continue
    # a case match, not `printf | grep -q`: under pipefail an early-exit grep SIGPIPEs the printf
    # and the match reads FALSE, which here would prune a live session's tree
    case $'\n'"$live"$'\n' in *$'\n'"$ts"$'\n'*) continue ;; esac
    [ -n "$(find "$t" -type f -mmin -360 -print 2>/dev/null | head -n 1)" ] && continue   # wrote a file in the last 6 h
    rm -rf "${t:?}" 2>/dev/null && n_tree=$((n_tree + 1))
    rmdir "${t%/*}" 2>/dev/null || true                        # its cwd dir, once empty
  done
  prune_line="$n_sock dead-pid socket(s) in $socks, $n_tree tmp tree(s) of sessions not in the roster in $ctmp"
fi

# ── 6. the arrangement, 7. the drafts (see the header). The libraries were sourced at the top.
SNAP_ROOT="${CC_HEARTBEAT_DIR:-$DIR/heartbeat}"
if [ "$DRY" = 1 ]; then
  rm -rf "${DIR:?}/reboot-prep-dryrun"
  ( umask 077; mkdir -p "$DIR/reboot-prep-dryrun" ) 2>/dev/null
  SNAP_ROOT="$DIR/reboot-prep-dryrun/heartbeat"
fi
export CC_HEARTBEAT_DIR="$SNAP_ROOT" CC_HB_NOW="$now" CC_HB_LS_TIMEOUT="${CC_HB_LS_TIMEOUT:-15}"
# The heartbeat reads the same cc-sessions this script was pointed at (a path; a bare name is its own default).
[ -n "${CC_REBOOT_PREP_SESSIONS:-}" ] && [ -z "${CC_HB_SESSIONS_BIN:-}" ] && export CC_HB_SESSIONS_BIN="$CC_REBOOT_PREP_SESSIONS"
TRIES="${CC_REBOOT_PREP_TRIES:-3}"

snap_check() { # <heartbeat kitty dir> → nothing when its tree is whole, else one line saying why not
  local d="$1" tree m miss
  tree="$d/hb.kitty-ls.json"
  [ -f "$tree" ] || { echo "kitty did not answer the tree read"; return 0; }
  # Read in THIS run: a failed read leaves the last good file in place (the heartbeat's rule), and
  # that one describes an earlier moment.
  m="$(/usr/bin/stat -f %m "$tree" 2>/dev/null || stat -c %Y "$tree" 2>/dev/null)"
  case "$m" in ''|*[!0-9]*) m=0 ;; esac
  [ "$m" -ge "$now" ] || { echo "kitty did not answer the tree read (the tree on disk is from $(date -r "$m" '+%H:%M:%S' 2>/dev/null || echo "$m"))"; return 0; }
  miss="$(jq -r --slurpfile r "$d/hb.roster.json" '
      [ .[]?.tabs[]?.windows[]?.id | tostring ] as $ids
      | [ $r[0][]? | select(type == "object" and (.session_id // "") != "") | ((.paneUUID // "") | tostring)
          | select(. == "" or (. as $p | $ids | index($p) | not)) ] | length' "$tree" 2>/dev/null)"
  case "$miss" in ''|*[!0-9]*) echo "the tree could not be read back"; return 0 ;; esac
  [ "$miss" = 0 ] || echo "$miss session pane(s) are not in the tree"
  return 0
}

SNAP_DIRS=""; n_kitty=0; n_degraded=0; hb_rc=127; layout_v=none
if command -v hb_tick >/dev/null 2>&1; then
  uuid="$(_hb_bootuuid)"; [ -n "$uuid" ] || uuid=nouuid
  try=0
  while :; do
    try=$((try + 1))
    hb_tick >/dev/null 2>&1; hb_rc=$?
    SNAP_DIRS=""; n_kitty=0; n_degraded=0
    for d in "$SNAP_ROOT/$uuid"/*; do
      [ -d "$d" ] || continue
      case "${d##*/}" in 0|*[!0-9]*) continue ;; esac          # 0 = the sessions outside any kitty
      [ "$(_hb_start_of "$d")" = "$now" ] || continue          # this run's tick only
      n_kitty=$((n_kitty + 1)); SNAP_DIRS="${SNAP_DIRS}${d}
"
      [ -z "$(snap_check "$d")" ] || n_degraded=$((n_degraded + 1))
    done
    { [ "$n_degraded" -gt 0 ] || [ "$hb_rc" = 2 ]; } && [ "$try" -lt "$TRIES" ] || break
  done
fi

ARR=""      # the lines to print, one per kitty
while IFS= read -r d; do
  [ -n "$d" ] || continue
  why="$(snap_check "$d")"
  if [ -n "$why" ]; then
    printf '%s\n' "$why" > "$d/hb.layout-degraded"
    ARR="${ARR}  arrangement        kitty ${d##*/}: DEGRADED after ${try} tries — ${why}. The restore will use its plain
                     row layout for this kitty, NOT the arrangement on screen now.
"
    continue
  fi
  rm -f "$d/hb.layout-degraded"
  counts="$(jq -r --slurpfile r "$d/hb.roster.json" '
      [ $r[0][]? | select(type == "object" and (.session_id // "") != "") | ((.paneUUID // "") | tostring) ] as $s
      | [ .[]?.tabs[]?.windows[]? ] as $w
      | "\(length) OS window(s), \([.[]?.tabs | length] | add // 0) tab(s), \($w | length) pane(s): \([$w[] | select((.id | tostring) as $i | $s | index($i))] | length) session(s), \([$w[] | select((.id | tostring) as $i | $s | index($i) | not)] | length) other"' \
      "$d/hb.kitty-ls.json" 2>/dev/null)"
  ARR="${ARR}  arrangement        kitty ${d##*/}: ${counts:-recorded} → $d/hb.kitty-ls.json
"
  if [ "$DRY" = 1 ]; then
    ARR="${ARR}$(jq -r --slurpfile r "$d/hb.roster.json" '
      ($r[0] | map(select(type == "object" and (.session_id // "") != "")
                   | {key: ((.paneUUID // "") | tostring), value: (.session_id[0:8] + "  " + ((.name // "") | tostring))})
             | from_entries) as $m
      | .[]? | "      OS window \(.id): \(.tabs | length) tab(s)",
          (.tabs | to_entries[] | "        tab \(.key + 1) [\(.value.layout // "?")]",
             (.value.windows[]? | "          pane \(.id)  " + (if $m[(.id | tostring)] then "session " + $m[(.id | tostring)]
                                                                else "shell in " + ((.cwd // "?") | tostring) end)))' \
      "$d/hb.kitty-ls.json" 2>/dev/null)
      restore plan:  $HERE/../bin/cc-resume-layout.sh --desktops --restore --dry-run --tree $d/hb.kitty-ls.json </dev/null
"
  fi
done <<EOF
$SNAP_DIRS
EOF
if [ "$n_kitty" -gt 0 ]; then
  layout_v=ok; [ "$n_degraded" -gt 0 ] && layout_v=degraded
elif [ "$hb_rc" = 127 ]; then
  layout_v=failed
  ARR="  arrangement        NOT RECORDED — scripts/lib/restore-heartbeat.sh did not load. The restore will use its plain row layout.
"
elif [ "$hb_rc" = 2 ]; then
  layout_v=failed
  ARR="  arrangement        NOT RECORDED after ${try} tries — the heartbeat could not be taken (cc-sessions failed). The restore
                     will use its plain row layout.
"
else
  ARR="  arrangement        none to record (no session runs in a kitty pane)
"
fi

# The drafts, from the sessions the heartbeat just listed (else the roster above).
DRAFTS="$DIR/reboot-$DAY.drafts"
droster="$DIR/.reboot-prep-roster.$$"
d_sum=""; d_line=""
if [ -n "$SNAP_DIRS" ]; then
  while IFS= read -r d; do [ -n "$d" ] && cat "$d/hb.roster.json" 2>/dev/null; done <<EOF | jq -s 'add // []' > "$droster" 2>/dev/null
$SNAP_DIRS
EOF
elif [ "$DRY" = 0 ] && [ -s "$roster" ]; then
  cp "$roster" "$droster" 2>/dev/null
fi
if [ "$DRY" = 0 ]; then
  # Today's earlier capture is replaced (what is in the boxes NOW is the truth), old ones expire.
  rm -rf "${DRAFTS:?}"
  for d in "$DIR"/reboot-*.drafts; do
    [ -d "$d" ] && [ ! -L "$d" ] || continue
    st="$(head -n 1 "${d%.drafts}.start" 2>/dev/null | awk '{ print $1 }')"
    case "$st" in ''|*[!0-9]*) st="$(/usr/bin/stat -f %m "$d" 2>/dev/null || stat -c %Y "$d" 2>/dev/null)" ;; esac
    case "$st" in ''|*[!0-9]*) continue ;; esac
    [ $((now - st)) -gt 604800 ] && rm -rf "${DIR:?}/${d##*/}"
  done
fi
if ! command -v rd_capture >/dev/null 2>&1; then
  d_line="NOT CAPTURED — scripts/lib/reboot-drafts.sh did not load"
elif [ ! -s "$droster" ]; then
  d_line="none to capture (no session list)"
else
  if [ "$DRY" = 1 ]; then d_sum="$(rd_capture "$droster" "" 2>/dev/null)"; else d_sum="$(rd_capture "$droster" "$DRAFTS" 2>/dev/null)"; fi
  if [ -z "$d_sum" ]; then
    d_line="NOT CAPTURED — the prompt-box reader did not load"
  else
    dv() { printf '%s\n' "$d_sum" | tr ' ' '\n' | sed -n "s/^$1=//p" | head -n 1; }
    d_line="$(dv saved) non-empty"
    if [ "$DRY" = 1 ]; then d_line="${d_line} (counted, not stored: dry run)"; else d_line="${d_line}, saved"; fi
    [ "$(dv partial)" -gt 0 ] 2>/dev/null && d_line="${d_line} ($(dv partial) hold a pasted block that exists only in the session's memory and cannot be saved)"
    d_line="${d_line}; $(dv empty) empty"
    [ "$(dv unreadable)" -gt 0 ] 2>/dev/null && d_line="${d_line}; $(dv unreadable) unreadable (a dialog over the box, or no answer) and left alone"
    [ "$(dv unread)" -gt 0 ] 2>/dev/null && d_line="${d_line}; $(dv unread) NOT READ (kitty stopped answering inside the ${CC_REBOOT_DRAFT_BUDGET:-120}s budget)"
    [ "$DRY" = 0 ] && [ -d "$DRAFTS" ] && d_line="${d_line} → $DRAFTS"
  fi
fi
rm -f "$droster"

if [ "$DRY" = 1 ]; then
  printf '%s' "$ARR"
  echo "  unsent drafts      $d_line"
  echo "capture layout=$layout_v kitty=$n_kitty degraded=$n_degraded ${d_sum:-drafts=none}"
  dsid="$(printf '%s' "${CLAUDE_CODE_SESSION_ID:-}" | tr -cd 'A-Za-z0-9_-')"
  echo "  owner session      ${dsid:-none (not run from a Claude session)}  (a real run writes it → $DIR/reboot-$DAY.owner)"
  [ -n "${lands_safe// /}" ] && echo "  lands past push    pids ${lands_safe% } — safe to reboot"
  [ -n "${lands// /}" ] && echo "  lands in flight    pids ${lands% } not yet pushed — a real run would wait for them"
  [ -z "${lands// /}${lands_safe// /}" ] && echo "  lands in flight    none"
  echo "verdict=DRY-RUN"
  exit 0
fi

printf '%s kalloc1024_gb=%s\n' "$now" "${kalloc:-unreadable}" > "$DIR/reboot-$DAY.kalloc"

echo "  start epoch        $now  → $DIR/reboot-$DAY.start"
echo "  live sessions      $n  → $roster"
printf '%s' "$ARR"
echo "  unsent drafts      $d_line"
echo "capture layout=$layout_v kitty=$n_kitty degraded=$n_degraded ${d_sum:-drafts=none}"
echo "  zone reading       ${kalloc:-unreadable}${kalloc:+ GiB} (the reading this reboot erases) → $DIR/reboot-$DAY.kalloc"
echo "  owner session      $owner_line"
[ -n "$prune_line" ] && echo "  pruned             $prune_line"
[ -n "${lands_safe// /}" ] && echo "  lands past push    pids ${lands_safe% } — pushed and content-verified or pushing done; safe to reboot"
if [ -n "${lands// /}" ]; then
  echo "  lands in flight    pids ${lands% } still running at the deadline and not yet pushed — NOT READY: re-run when ship-land.sh has exited"
elif [ -z "${lands_safe// /}" ]; then
  echo "  lands in flight    none"
fi
# Kitty's sleep key (step 8): set, then read back by a different call. Never the real defaults under
# bats unless a stub is named; CC_KITTY_HYGIENE=off leaves it alone.
if [ "${CC_KITTY_HYGIENE:-on}" != off ] && { [ -z "${BATS_TEST_FILENAME:-}" ] || [ -n "${CC_REBOOT_PREP_DEFAULTS:-}" ]; }; then
  dfl="${CC_REBOOT_PREP_DEFAULTS:-/usr/bin/defaults}"; dfl_s="${CC_REBOOT_PREP_DEFAULTS_S:-30}"
  bounded "$dfl_s" "$dfl" write net.kovidgoyal.kitty NSAppSleepDisabled -bool YES >/dev/null 2>&1
  if [ "$(bounded "$dfl_s" "$dfl" read net.kovidgoyal.kitty NSAppSleepDisabled 2>/dev/null | tr -d '[:space:]')" = 1 ]; then
    echo "  kitty sleep key    NSAppSleepDisabled = YES (set and read back; kitty reads it at the post-reboot start)"
  else
    echo "  kitty sleep key    NOT SET — the write did not read back. Before rebooting (it is also a kitty start): defaults write net.kovidgoyal.kitty NSAppSleepDisabled -bool YES"
  fi
fi
echo
echo "Operator steps, in order:"
echo "  1. Long-running leads write a handoff first (the FLEET_V2 lead included); every other"
echo "     session resumes from its own handoff or from the roster above."
if [ -s "$CAPTURE_CMD" ]; then
  echo "  2. A root zone capture is STAGED. Run it before rebooting — the reboot erases the evidence:"
  echo "       bash $CAPTURE_CMD"
  echo "  3. Reboot before the ceiling ETA above."
else
  echo "  2. Reboot before the ceiling ETA above. (No root capture is staged: the ratchet analysis named"
  echo "     a driver, or has not asked for one.)"
fi
# The kitty restart rides the next alarm reboot after the operator's kitty build choice (plan W3):
# whoever stages the build drops this marker with one line saying what the restart installs.
if [ -s "$DIR/kitty-restart-pending" ]; then
  echo "  This reboot is ALSO the kitty restart: $(head -1 "$DIR/kitty-restart-pending")"
  echo "     (remove $DIR/kitty-restart-pending once kitty is back on the new build)"
fi
echo "  Right before clicking Restart: bash $HERE/alarm-reboot-prep.sh --arm-restart"
echo "     (a final heartbeat, kitty's quit dialog off, and the apps that would veto the restart)"
echo "  After login, resume sessions with the resume-sessions skill; the next capacity-alarm tick"
echo "  should read data.kalloc.1024 under 3 GB."
if [ -n "${lands// /}" ]; then
  echo "verdict=NOT-READY reason=land-in-flight"
  exit 3
fi
echo "verdict=READY"
exit 0
