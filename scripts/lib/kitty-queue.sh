#!/usr/bin/env bash
# kitty-queue.sh — is kitty's remote control DEAF? One detector, shared (W3 P5, 2026-10-05).
#
# WHY ONE FILE. kitty 0.48.2's remote-control ("talk") thread exits for good on an accept() error and
# leaves the socket bound and listening. Connections then pile up in the accept queue with their
# requests unread until the listen backlog (128) is full, and only a kitty restart clears it
# (docs/research/husk-panes-2026-09-30.md, live capture 2026-10-01). scripts/handoff-fire.sh has
# detected that since 2026-10-01 to hold a recycle; boot-resume.sh's deaf page (W3 P5) needs the same
# reading. A second detector would drift from the first (C3-skeptic-risk M1), so the function moved
# here and both source it.
#
#   hf_kitty_queue_depth <socket>      connections queued on the socket that hold unread data;
#                                      `?` when netstat failed or timed out (unknown, never full)
#   kq_main_kitty_pids                 pids of the main kitty (no --instance-group in its argv)
#   kq_peer_thread <pid>               rc 0 the talk thread (KittyPeerMon) is running · 1 it is gone ·
#                                      2 unknown (sample failed or printed nothing)
#   kq_deaf <socket> <pid>             rc 0 DEAF: the passive evidence below, or the queue is full AND
#                                      sample shows no talk thread · 1 not deaf, or not provably
#                                      (prints the reason either way)
#   cc_kitty_rc_open                   rc 0 the RC CIRCUIT BREAKER is OPEN: lockwatch/state.json reads
#                                      kitty_rc "dead" and lockwatch/hb is fresh · 1 closed. Reads two
#                                      files and connects to nothing (lockup incident 2026-10-25,
#                                      DESIGN C4): every abandoned client of a deaf kitty is one more
#                                      held peer toward its PEER_LIMIT of 256.
#   kq_hb_kitty_stale <pid>            rc 0 the restore heartbeat kept ticking (hb.start fresh) while
#                                      its `kitten @ ls` tree for this kitty went 2+ ticks without a
#                                      refresh · 1 no such evidence. Files only.
#
# A full queue alone is not proof: a kitty that is only slow (a large scrollback dump, a stalled
# render) also lets the queue grow. The talk thread's absence is the proof, so kq_deaf needs both, and
# an unreadable sample is "not provably deaf", never "deaf".
#
# Seams: CC_HF_NETSTAT_FILE (a `netstat -anv -f unix` capture) · CC_KITTY_WEDGED_QUEUE_N (128) ·
#   CC_KQ_SAMPLE_BIN (default /usr/bin/sample) · CC_KQ_PS_BIN (default /bin/ps) · CC_LOCKWATCH_DIR ·
#   CC_KQ_HB_FRESH_S (10) · CC_KQ_NOW · CC_HEARTBEAT_DIR · CC_KQ_HB_TICK_S (300) ·
#   CC_KITTY_RC_BREAKER (on; `off` is the kill switch: the breaker never opens).
# /bin/bash 3.2 safe (launchd runs boot-resume under it). Sourced: defines functions only.

# Bounded call. handoff-fire.sh's hf_bounded_s when the caller has it; otherwise a perl alarm that
# kills the call's process group (stock macOS has no timeout(1); the launchd PATH has no coreutils).
_kq_to() { # <secs> <cmd...>
  local s="$1"; shift
  if command -v hf_bounded_s >/dev/null 2>&1; then hf_bounded_s "$s" "$@"; return $?; fi
  /usr/bin/perl -e 'my $s = shift; my $p = fork(); if (!$p) { setpgrp(0, 0); exec @ARGV; exit 127 }
    local $SIG{ALRM} = sub { kill "KILL", -$p; exit 124 }; alarm $s; waitpid($p, 0); exit($? >> 8)' "$s" "$@"
}

# `?`, NOT 0, WHEN netstat DID NOT ANSWER (lr-inplace-immediacy 2026-10-18). The call used to end in
# `|| true` and awk's `n + 0`, so a netstat that failed or hit its 3 s bound read as "0 queued", and the
# held row of 2026-10-18 offered that 0 as evidence. A reading nobody took is unknown: callers treat `?`
# as "not provably full", never as full and never as empty.
hf_kitty_queue_depth() { # $1=socket (unix:/path or /path) → connections queued on it holding unread data · `?` when netstat failed or timed out
  local path="${1#unix:}" out="" rc=0
  if [ -n "${CC_HF_NETSTAT_FILE:-}" ]; then out="$(cat "$CC_HF_NETSTAT_FILE" 2>/dev/null || true)"
  else out="$(_kq_to 3 netstat -anv -f unix 2>/dev/null)" || rc=$?; fi
  if [ "$rc" != 0 ]; then printf '?\n'; return 0; fi
  printf '%s\n' "$out" | awk -v p="$path" '$NF == p && $3 ~ /^[0-9]+$/ && $3 > 0 { n++ } END { print n + 0 }'
}

# The MAIN kitty: a process whose executable is kitty, whose argv carries no --instance-group (the
# quick-access terminal and the staged sandbox build are started with one) and which is not a helper
# (`kitty +kitten …`). Never `pgrep -nx kitty`, which answers with whichever kitty started last.
# BOUNDED, AND INTO A FILE (DESIGN I2). `ps -axo args=` reads every process's argv through
# KERN_PROCARGS2, and on 2026-10-25 twenty `ps` slept inside the kern_proc handler; a bare call here
# hung its caller with them. The output goes to a regular file, never a pipe, so a ps that outlives
# its bound holds nothing this shell waits on; the bound abandons it (pgroup SIGKILL; a ps is no pty
# session leader) and the read below sees only what was written.
kq_main_kitty_pids() {
  local f
  f="$(mktemp "${TMPDIR:-/tmp}/kq-ps.XXXXXX" 2>/dev/null)" || return 0
  _kq_to "${CC_KQ_PS_TIMEOUT_S:-10}" "${CC_KQ_PS_BIN:-/bin/ps}" -axo pid=,args= > "$f" 2>/dev/null
  awk '
    { pid = $1; exe = $2; n = split(exe, a, "/"); base = a[n]
      if (base != "kitty") next
      if ($3 ~ /^\+/) next                      # a helper: kitty +kitten …, kitty +runpy …
      for (i = 3; i <= NF; i++) if ($i ~ /^--instance-group/) next
      print pid }' "$f"
  rm -f "$f" 2>/dev/null
  return 0
}

kq_peer_thread() { # <kitty pid>
  local out
  case "${1:-}" in ''|*[!0-9]*) return 2 ;; esac
  out="$(_kq_to 15 "${CC_KQ_SAMPLE_BIN:-/usr/bin/sample}" "$1" 1 2>/dev/null || true)"
  # A real sample always names its threads; none named means the call did not work.
  printf '%s\n' "$out" | grep -q 'Thread_[0-9]' || return 2
  if printf '%s\n' "$out" | grep -q 'KittyPeerMon'; then return 0; fi
  return 1
}

_kq_now() { case "${CC_KQ_NOW:-}" in ''|*[!0-9]*) date +%s 2>/dev/null ;; *) printf '%s' "$CC_KQ_NOW" ;; esac; }
_kq_mtime() { stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || printf ''; }

# THE BREAKER. lockprobe (lane A) sets kitty_rc "dead" from passive evidence only (the main thread's
# CPU flat while its RC sockets rise); an active probe would itself be another held peer. Believed
# only while lockprobe's heartbeat is fresh: a stale hb DISARMS the breaker, because a dead watchdog's
# last word is not evidence about kitty now.
cc_kitty_rc_open() {
  local dir="${CC_LOCKWATCH_DIR:-$HOME/.claude/autonomy/lockwatch}" st="" now hbt fresh
  [ "${CC_KITTY_RC_BREAKER:-on}" != off ] || return 1
  [ -f "$dir/state.json" ] || return 1
  IFS= read -r -d '' st < "$dir/state.json" 2>/dev/null || true
  case "$st" in *'"kitty_rc":"dead"'*|*'"kitty_rc": "dead"'*) ;; *) return 1 ;; esac
  hbt="$(_kq_mtime "$dir/hb")"; now="$(_kq_now)"
  case "$hbt$now" in ''|*[!0-9]*) return 1 ;; esac
  fresh="${CC_KQ_HB_FRESH_S:-10}"; case "$fresh" in ''|*[!0-9]*) fresh=10 ;; esac
  [ $(( now - hbt )) -le "$fresh" ]
}

kq_hb_kitty_stale() { # <kitty pid>
  local root="${CC_HEARTBEAT_DIR:-$HOME/.claude/autonomy/heartbeat}" d best="" bs=0 s ls now tick
  case "${1:-}" in ''|*[!0-9]*) return 1 ;; esac
  tick="${CC_KQ_HB_TICK_S:-300}"; case "$tick" in ''|*[!0-9]*|0) tick=300 ;; esac
  for d in "$root"/*/"$1"; do
    [ -f "$d/hb.start" ] || continue
    s=""; read -r s _ < "$d/hb.start" 2>/dev/null
    case "$s" in ''|*[!0-9]*) continue ;; esac
    [ "$s" -gt "$bs" ] && { bs="$s"; best="$d"; }
  done
  [ -n "$best" ] && [ -f "$best/hb.kitty-ls.json" ] || return 1
  now="$(_kq_now)"; ls="$(_kq_mtime "$best/hb.kitty-ls.json")"
  case "$now$ls" in ''|*[!0-9]*) return 1 ;; esac
  # The heartbeat itself must be current, or its silence is about the heartbeat, not about kitty.
  [ $(( now - bs )) -le $(( 3 * tick )) ] || return 1
  [ $(( bs - ls )) -gt $(( 2 * tick )) ] || return 1
  KQ_HB_STALE_WHY="the restore heartbeat ticked at $bs but its kitten @ ls tree for kitty $1 is $(( bs - ls ))s older (over 2 ticks of ${tick}s)"
  return 0
}

kq_deaf() { # <socket> <kitty pid>
  local sock="${1:-}" pid="${2:-}" q lim="${CC_KITTY_WEDGED_QUEUE_N:-128}" rc
  case "$lim" in ''|*[!0-9]*) lim=128 ;; esac
  # PASSIVE EVIDENCE FIRST, the same predicate the breaker reads (DESIGN C4: one detector), and it
  # costs no netstat and no sample of a kitty that may not answer either.
  if cc_kitty_rc_open; then printf 'lockwatch reads kitty_rc=dead with a fresh heartbeat'; return 0; fi
  KQ_HB_STALE_WHY=""
  if kq_hb_kitty_stale "$pid"; then printf '%s' "$KQ_HB_STALE_WHY"; return 0; fi
  q="$(hf_kitty_queue_depth "$sock")"
  case "$q" in ''|*[!0-9]*) printf 'queue=%s unreadable (netstat failed): not provably deaf' "${q:-?}"; return 1 ;; esac
  if [ "$q" -lt "$lim" ]; then printf 'queue=%s under %s' "$q" "$lim"; return 1; fi
  rc=0; kq_peer_thread "$pid" || rc=$?
  case "$rc" in
    1) printf 'queue=%s full, and sample of kitty %s shows no KittyPeerMon thread' "$q" "$pid"; return 0 ;;
    0) printf 'queue=%s full, but the KittyPeerMon thread is running: slow, not deaf' "$q"; return 1 ;;
    *) printf 'queue=%s full, but kitty %s could not be sampled: not provably deaf' "$q" "$pid"; return 1 ;;
  esac
}
