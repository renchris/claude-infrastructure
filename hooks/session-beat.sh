#!/bin/bash
# session-beat.sh — the WRITE side of the session presence beat (SESSION_REGISTRY_V2 §4.1).
#
# Wired to UserPromptSubmit and Stop. Writes ONE small durable attestation per turn boundary:
#   ${CC_BEAT_DIR:-$HOME/.claude/cc-beats}/<sid>.json
#   {sid, pane, pid, lstart, t, kind, who, operatorT, seq}
#
# WHY THIS EXISTS. "Who drove the last turn" is the one signal a done-decision cannot fake —
# idle+clean+landed is every live conversation's steady state between prompts (2026-07-24: two live
# operator conversations reaped 12-14 min after their last typed prompt). v1 answered it by
# re-deriving it from the transcript inside every sweep. This hook answers it ONCE, here, at the
# moment the prompt arrives, on the prompt already in hand — no scan, no transcript, no cost that
# grows with history. The reap path then reads it in O(1) and can therefore re-take the reading
# IMMEDIATELY before a close, which is what makes the ≤60s freshness contract structural.
#
# THE `who` PREDICATE — kept semantically identical to hooks/lib/cc-interactive.sh so the write-time
# and read-time answers agree (acceptance A2). At UserPromptSubmit the tool_result / isMeta cases of
# that predicate cannot arise (this event fires only for a submitted prompt), so the predicate
# reduces to its remaining leg: the AUTO-TRAFFIC regex. That exclusion is load-bearing, not
# cosmetic — our own auto-drive re-prompts (session-continue's Stop-hook feedback, task
# notifications, our ⟳/⚑/⚠ advisories) arrive through this same event, and a presence signal that
# counted its own auto-drive would hold every self-driving session open forever and deadlock every
# recycle. Operator slash-commands DO count: the operator is present.
#
# `operatorT` is a STICKY high-water mark: a later who=auto beat never lowers it. Presence, once
# demonstrated, decays only by the clock — otherwise a Stop beat landing after an operator prompt
# would erase the very evidence that protects the pane.
#
# FAIL-OPEN CONTRACT (inherited verbatim from hooks/session-register.sh:26-32). This runs on EVERY
# prompt of EVERY session. A presence spine that can block, delay or kill a turn inverts its own
# purpose, so ALL slow work happens inside beat(), under a HARD timeout, and this hook ALWAYS exits 0.
# A missing beat degrades the reap decision toward REFUSE (the safe direction, R3) — it must never
# cost a session. Kill switch: CC_BEAT=off.
#
# OFF THE PROMPT PATH (docs/research/load-hook-timeouts-2026-10-11 item 7). The hook pays exactly ONE
# jq start in the foreground — the payload parse, the `who` regex is bash's own `[[ =~ ]]` — and then
# DETACHES beat() and exits. The ancestry walk (two `ps` per hop), the previous-beat read and the
# write all run after the turn has its prompt back. Before, a prompt beat held its turn for six jq
# starts plus up to 24 `ps` (counted from the code), for as long as the machine took to run them, up
# to the 3 s cap. The detach is done in
# bash, NOT with scripts/lib/detach.sh: that helper starts /usr/bin/python3 to call setsid, which
# would put back on every prompt the interpreter start this change exists to remove. `set -m` gives
# the worker its own process GROUP — the property detach.sh's header names, immunity to a group
# SIGKILL of the hook — stdin is /dev/null, stdout and stderr go to /dev/null, and once this hook
# exits the worker is reparented to launchd, out of any parent-tree walk. The one line a worker does
# log (a superseded beat, see ORDER BY EVENT) is appended to $CC_BEAT_LOG by that branch alone, so a
# beat that logs nothing creates no log file and no log directory. `async: true` in settings.json was
# the other way off the path and was rejected: it has no enforced timeout, so slow runs pile up. The
# worker keeps its own HARD timeout instead (P8_TIMEOUT, below, 20 s). The ≤60 s freshness contract
# still holds: the write lands within that bound of the prompt, not at its instant.
# ONE DEPENDENCY THIS ADDS: the ancestry walk now starts from $PPID after the hook has exited, so it
# relies on the hook's parent being claude itself (2,315 of 2,331 PPID lines in
# logs/teammate-lifecycle.log, 2026-10-12). Under a non-exec `/bin/sh -c "hook; :"` shim, or a
# `claude -p` that exits before the worker reaches `ps`, the beat records the dead parent's pid with
# an empty lstart (the foreground hook used to record claude's pid and lstart there).
#
# SYNC MODE — the `limited` kind, or CC_BEAT_SYNC=1. hooks/stop-failure-marker.sh writes the
# `limited` beat by PIPING into this hook (`printf | bash session-beat.sh limited`), so the hook's
# parent there is stop-failure-marker, not claude: detached, the walk would find claude only if that
# parent happened to outlive the worker's first `ps`. That caller is on the death path, not the prompt
# path, and its readers (cc-limited, spawn-presence) need the flip on disk when it returns. So it runs
# beat() in the FOREGROUND under the 3 s cap it always had (the bound stop-failure-marker's own
# header budgets for). CC_BEAT_SYNC=1 is the same switch for any other non-prompt-path caller.
# The `stop` beat is synchronous too: it is not on the prompt path (a Stop hook runs after the turn,
# under the same 3 s cap it always had), and `cc-await-ping --idle-scoped` takes its arm-time
# baseline on the premise that the Stop beat is already on disk when the session-continue floor
# tells the model to arm (bin/cc-await-ping, the BEAT_BASE_SEQ comment). Detached, a late Stop
# worker would land after that baseline and read as a new turn. Only the prompt beat detaches.
#
# bash 3.2-safe. jq required (absent ⇒ silent no-op, same as session-register.sh).
set -uo pipefail

input=$(cat 2>/dev/null)

[ "${CC_BEAT:-on}" = off ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0

# kind: explicit arg wins (Stop passes `stop`); default is a prompt beat.
kind="${1:-prompt}"
sync=0
{ [ "$kind" = limited ] || [ "$kind" = stop ] || [ "${CC_BEAT_SYNC:-}" = 1 ]; } && sync=1

# The worker's HARD timeout. 3 s in the foreground (SYNC MODE), where every second of it is the
# caller's; detached, the bound only has to keep workers from piling up and land the beat inside the
# reader's 60 s freshness window. 20 s does both. A 3 s cap was measured too tight once detached:
# at load ~600 (2026-10-12) tests/session-beat.bats, whose walk climbs a deep bats ancestry, saw 7
# of its detached beats never written within 20 s under the 3 s cap.
if [ "$sync" = 1 ]; then P8_TIMEOUT="${CC_BEAT_TIMEOUT:-3}"; else P8_TIMEOUT="${CC_BEAT_TIMEOUT:-20}"; fi

# ONE jq start for every payload field. Line 1 is "<sid> TAB <ms> TAB <cwd>" as @tsv; everything
# after the first newline is the RAW prompt, so the `who` regex sees exactly the text the old
# per-field `jq -r '.prompt'` produced (an @tsv field would arrive with its \t \n \\ escaped).
# <ms> is the EVENT's clock, read here in the foreground where boundaries are still in turn order;
# see ORDER BY EVENT in beat().
_parsed=$(printf '%s' "$input" | jq -r '
  ([(.session_id // "" | tostring), (now * 1000 | floor | tostring), (.cwd // "" | tostring)] | @tsv),
  (.prompt // "" | tostring)' 2>/dev/null)
_head="${_parsed%%$'\n'*}"
prompt=""
case "$_parsed" in *$'\n'*) prompt="${_parsed#*$'\n'}" ;; esac
sid="${_head%%$'\t'*}"
_rest=""
case "$_head" in *$'\t'*) _rest="${_head#*$'\t'}" ;; esac
tms="${_rest%%$'\t'*}"
cwd=""
case "$_rest" in *$'\t'*) cwd="${_rest#*$'\t'}" ;; esac
[ -n "$sid" ] || exit 0
# sid is the IDENTITY key, deliberately NOT the pane: tmux panes inherit the server's
# ITERM_SESSION_ID, so a pane-keyed beat would have N sessions overwrite one row.
case "$sid" in *[!0-9A-Za-z_-]*) exit 0 ;; esac   # path-safety: sid becomes a filename
case "$tms" in ''|*[!0-9]*) tms=$(( $(date +%s) * 1000 )) ;; esac   # unreachable when jq parsed sid
# Undo @tsv's escaping of the cwd (\\ \t \n \r); 0x02 holds an escaped backslash meanwhile (not
# 0x01, bash's internal CTLESC byte, which mangles inside ${//}).
cwd="${cwd//\\\\/$'\002'}"; cwd="${cwd//\\t/$'\t'}"; cwd="${cwd//\\n/$'\n'}"; cwd="${cwd//\\r/$'\r'}"
cwd="${cwd//$'\002'/\\}"
[ -z "$cwd" ] && cwd="$PWD"

# ── the `who` decision, made here, once ──
# `[[ =~ ]]` (POSIX ERE) agrees with the reader's jq `test` (hooks/lib/cc-interactive.sh) on this
# regex: every alternative is ^-anchored at the string's start, and neither engine treats ^ as a
# line anchor here (measured both on multi-line prompts, 2026-10-11).
who=auto
if [ "$kind" = prompt ]; then
  rx="${CC_CLASSIFY_AUTO_RX:-^<task-notification>|^<local-command-stdout>|^Stop hook feedback:|^\\[Request interrupted|^⟳|^⚑|^⚠|^⛔}"
  if [ -n "$prompt" ] && ! [[ $prompt =~ $rx ]]; then
    who=operator
  fi
fi

beat() {
  local pane dir tmp prev prevOp prevT now seq cpid lstart walk c i lock held me owner
  # KITTY_WINDOW_ID last, for the same measured no-address class session-register.sh:127 carries:
  # without it a kitty-hosted session's beat records pane "" while its stop-failure marker records
  # a real pane, and a reader comparing the two sees a disagreement that is purely this gap.
  pane="${CC_PANE_ID:-${ITERM_SESSION_ID:-${KITTY_WINDOW_ID:-}}}"; pane="${pane##*:}"

  # `t` is the event's own second, taken from the foreground stamp — not this worker's clock, which
  # can trail the event by as long as the walk below took.
  now=$((tms / 1000))

  # Durable claude-ancestor PID + its lstart — identity is (pid,lstart), never pid alone: a
  # RECYCLED pid must not masquerade as this session (the reaper's a17 S-4 pin, now the beat's too).
  #
  # TZ=UTC IS PART OF THE IDENTITY, NOT A FORMATTING PREFERENCE. `ps -o lstart=` renders in the
  # AMBIENT zone, so the stored string is only comparable to a reader that happened to be running in
  # the same zone — and it stops being comparable to its own past self at the next DST flip, which
  # makes every beat on disk read as a DIFFERENT process while the sessions are still alive (memory
  # process-start-time-renders-in-ambient-timezone). Measured 2026-09-08 on 51 live beats: 0 matched
  # a `TZ=UTC` reader and 22 matched an ambient one, i.e. the census was already keyed on a
  # coincidence between two unpinned renderings. Pinning HERE is what makes the field mean the same
  # thing to every reader, in every zone, on both sides of a DST boundary; the reader
  # (scripts/lib/spawn-presence.sh) pins its own sample the same way. `bin/cc-await-ping`'s
  # _pid_ident is the idiom being copied.
  walk="$PPID"; cpid=""; i=0
  while [ -n "$walk" ] && [ "$walk" -gt 1 ] 2>/dev/null && [ "$i" -lt 12 ]; do
    c=$(ps -o comm= -p "$walk" 2>/dev/null); c="${c##*/}"
    case "$c" in claude|claude.exe|claude-*) cpid="$walk"; break ;; esac
    walk=$(ps -o ppid= -p "$walk" 2>/dev/null | tr -d ' ')
    i=$((i + 1))
  done
  [ -z "$cpid" ] && cpid="$PPID"
  lstart=$(TZ=UTC ps -o lstart= -p "$cpid" 2>/dev/null | tr -s ' ' | sed 's/^ *//;s/ *$//')

  dir="${CC_BEAT_DIR:-$HOME/.claude/cc-beats}"
  mkdir -p "$dir" 2>/dev/null || return 0

  # ONE WRITER PER SID AT A TIME. In the foreground the turn itself serialized a session's beats (the
  # prompt beat finished before the turn could reach Stop); detached, a slow prompt worker can still
  # be walking `ps` when the Stop worker starts, and two unserialized read-modify-writes would let the
  # later one write back a STALE operatorT — erasing the presence this file exists to keep. The walk
  # above stays outside the lock; only the short read-modify-write below is inside it.
  # The lock is a SYMLINK whose target is the holder's pid: `ln -s` creates it atomically WITH its
  # owner, so there is no window in which a lock exists that names nobody. A holder is taken over only
  # when `kill -0` says it is DEAD (killed by the HARD timeout), so a dead holder costs its successors
  # nothing, and a live but slow one (at load ~600 a read-modify-write can outlast any guessed bound)
  # is never robbed. A live holder is waited for up to half the HARD timeout, by the CLOCK, not a try
  # count (at load ~600 each `sleep` fork can take a second); past that the worker writes WITHOUT the
  # lock rather than lose the beat, and leaves the holder's lock alone. A lock is removed only while
  # it still names its remover. Residual: two workers that see the same dead holder at the same
  # instant can both take over; that needs three beats of one sid in flight plus a killed holder.
  # $me is this worker's own pid (bash 3.2 has no BASHPID): `exec` makes sh the comsub child itself.
  me=$(exec /bin/sh -c 'echo "$PPID"')
  lock="$dir/.$sid.lk"; i=$SECONDS; held=0
  while [ -n "$me" ]; do
    if ln -sn "$me" "$lock" 2>/dev/null; then held=1; break; fi
    owner=$(readlink "$lock" 2>/dev/null)
    case "$owner" in *[!0-9]*) owner="" ;; esac
    if [ -n "$owner" ] && ! kill -0 "$owner" 2>/dev/null \
       && [ "$(readlink "$lock" 2>/dev/null)" = "$owner" ] && rm -f "$lock" 2>/dev/null; then
      continue
    fi
    [ $((SECONDS - i)) -ge $((P8_TIMEOUT / 2)) ] && break
    sleep 0.1
  done

  # Carry the sticky operator high-water mark and the sequence forward from the previous beat.
  # A beat from before the event stamp existed is ordered by its whole-second `t`.
  prevOp=""; seq=0; prevT=0
  if [ -f "$dir/$sid.json" ]; then
    prev=$(jq -r '[(.operatorT // ""), (.seq // 0),
                   (.tms // (if (.t | type) == "number" then .t * 1000 | floor else 0 end))] | @tsv' \
           "$dir/$sid.json" 2>/dev/null)
    prevOp="${prev%%$'\t'*}"; prev="${prev#*$'\t'}"
    seq="${prev%%$'\t'*}"
    prevT="${prev#*$'\t'}"
  fi
  case "$seq"   in ''|*[!0-9]*) seq=0 ;; esac
  case "$prevOp" in *[!0-9]*) prevOp="" ;; esac
  case "$prevT" in ''|*[!0-9]*) prevT=0 ;; esac

  # ORDER BY EVENT, NOT BY ARRIVAL. Detached, a turn's prompt beat and its Stop beat (or a Stop beat
  # and the very next "Stop hook feedback:" prompt, milliseconds later) are two workers, and the lock
  # above decides only that they do not write at once — not which writes LAST. Whichever reaches it
  # second used to win, so a stalled worker left the previous boundary's kind on disk until the next
  # one, possibly hours: cc-wake refuses a session whose last beat is not a Stop, session-busy reads
  # a mid-turn session as idle, and cc-await-ping reads a late `prompt` as a new turn. Measured with
  # 0-1.4 s of `ps` jitter per call: the stale Stop beat survived into the next turn in 6 of 12
  # trials. A worker whose event is OLDER than the beat on disk therefore writes nothing of its own —
  # kind, t, who, seq stay the newer event's — and only raises the operatorT high-water mark.
  tmp="$dir/.$sid.$$.tmp"
  if [ "$prevT" -gt "$tms" ]; then
    if [ "$who" = operator ] && { [ -z "$prevOp" ] || [ "$now" -gt "$prevOp" ]; }; then
      if jq --argjson opT "$now" '.operatorT = $opT' "$dir/$sid.json" > "$tmp" 2>/dev/null; then
        mv -f "$tmp" "$dir/$sid.json" 2>/dev/null || rm -f "$tmp" 2>/dev/null
      else
        rm -f "$tmp" 2>/dev/null
      fi
    fi
    # The only line a worker logs, and the only place the log (and its directory) is created.
    { [ -d "${_log%/*}" ] || mkdir -p "${_log%/*}"; } 2>/dev/null \
      && printf 'session-beat: sid=%s %s beat (event %s) superseded by the newer beat on disk (event %s)\n' \
           "$sid" "$kind" "$tms" "$prevT" >>"$_log" 2>/dev/null
    [ "$held" = 1 ] && [ "$(readlink "$lock" 2>/dev/null)" = "$me" ] && rm -f "$lock" 2>/dev/null
    return 0
  fi

  seq=$((seq + 1))
  # A high-water mark in fact as well as in name: a worker that took its clock reading before a
  # sibling's later one must not lower the mark that sibling wrote.
  if [ "$who" = operator ] && { [ -z "$prevOp" ] || [ "$now" -gt "$prevOp" ]; }; then prevOp="$now"; fi

  if jq -n --arg sid "$sid" --arg pane "$pane" --arg cwd "$cwd" --arg kind "$kind" \
          --arg who "$who" --arg lstart "$lstart" --arg opT "$prevOp" \
          --argjson pid "$cpid" --argjson t "$now" --argjson tms "$tms" --argjson seq "$seq" \
        '{sid:$sid, pane:$pane, cwd:$cwd, pid:$pid, lstart:$lstart, t:$t, tms:$tms, kind:$kind,
          who:$who, operatorT:(if $opT=="" then null else ($opT|tonumber) end), seq:$seq}' \
        > "$tmp" 2>/dev/null; then
    mv -f "$tmp" "$dir/$sid.json" 2>/dev/null || rm -f "$tmp" 2>/dev/null
  else
    rm -f "$tmp" 2>/dev/null
  fi
  [ "$held" = 1 ] && [ "$(readlink "$lock" 2>/dev/null)" = "$me" ] && rm -f "$lock" 2>/dev/null
  return 0
}

_log="${CC_BEAT_LOG:-$HOME/.claude/logs/session-beat.log}"

# beat() under its HARD timeout; returns once the beat is written or killed.
# The timer stops its OWN `sleep` on TERM: a timer killed outright would orphan a P8_TIMEOUT-long
# `sleep` on every beat, about two per turn per session. `_dead` closes the gap between forking the
# `sleep` and learning its pid: a TERM landing there is remembered and the `sleep` is stopped on the
# next line instead of outliving the timer.
capped_beat() {
  local _w _k
  beat >/dev/null 2>&1 &
  _w=$!
  ( _s=""; _dead=0
    trap '_dead=1; [ -n "$_s" ] && kill "$_s" 2>/dev/null' TERM
    sleep "$P8_TIMEOUT" & _s=$!
    [ "$_dead" = 1 ] && { kill "$_s" 2>/dev/null; exit 0; }
    wait "$_s" && kill -9 "$_w" 2>/dev/null ) >/dev/null 2>&1 &
  _k=$!
  wait "$_w" >/dev/null 2>&1
  kill "$_k" >/dev/null 2>&1
  wait "$_k" >/dev/null 2>&1
}

if [ "$sync" = 1 ]; then
  capped_beat </dev/null >/dev/null 2>&1
  exit 0
fi

# The worker: capped_beat in its own process group, stdin, stdout and stderr all /dev/null (see OFF
# THE PROMPT PATH above). The hook returns as soon as the worker is forked; nothing the worker does
# can hold this hook's stdout pipe open, so the harness reads EOF at once.
set -m
(
  set +m
  capped_beat
) </dev/null >/dev/null 2>&1 &
exit 0
