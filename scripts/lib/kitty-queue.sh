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
#   hf_kitty_queue_depth <socket>      connections queued on the socket that hold unread data
#   kq_main_kitty_pids                 pids of the main kitty (no --instance-group in its argv)
#   kq_peer_thread <pid>               rc 0 the talk thread (KittyPeerMon) is running · 1 it is gone ·
#                                      2 unknown (sample failed or printed nothing)
#   kq_deaf <socket> <pid>             rc 0 DEAF: the queue is full AND sample shows no talk thread ·
#                                      1 not deaf, or not provably (prints the reason either way)
#
# A full queue alone is not proof: a kitty that is only slow (a large scrollback dump, a stalled
# render) also lets the queue grow. The talk thread's absence is the proof, so kq_deaf needs both, and
# an unreadable sample is "not provably deaf", never "deaf".
#
# Seams: CC_HF_NETSTAT_FILE (a `netstat -anv -f unix` capture) · CC_KITTY_WEDGED_QUEUE_N (128) ·
#   CC_KQ_SAMPLE_BIN (default /usr/bin/sample) · CC_KQ_PS_BIN (default /bin/ps).
# /bin/bash 3.2 safe (launchd runs boot-resume under it). Sourced: defines functions only.

# Bounded call. handoff-fire.sh's hf_bounded_s when the caller has it; otherwise a perl alarm that
# kills the call's process group (stock macOS has no timeout(1); the launchd PATH has no coreutils).
_kq_to() { # <secs> <cmd...>
  local s="$1"; shift
  if command -v hf_bounded_s >/dev/null 2>&1; then hf_bounded_s "$s" "$@"; return $?; fi
  /usr/bin/perl -e 'my $s = shift; my $p = fork(); if (!$p) { setpgrp(0, 0); exec @ARGV; exit 127 }
    local $SIG{ALRM} = sub { kill "KILL", -$p; exit 124 }; alarm $s; waitpid($p, 0); exit($? >> 8)' "$s" "$@"
}

hf_kitty_queue_depth() { # $1=socket (unix:/path or /path) → connections queued on it holding unread data
  local path="${1#unix:}" out=""
  if [ -n "${CC_HF_NETSTAT_FILE:-}" ]; then out="$(cat "$CC_HF_NETSTAT_FILE" 2>/dev/null || true)"
  else out="$(_kq_to 3 netstat -anv -f unix 2>/dev/null || true)"; fi
  printf '%s\n' "$out" | awk -v p="$path" '$NF == p && $3 ~ /^[0-9]+$/ && $3 > 0 { n++ } END { print n + 0 }'
}

# The MAIN kitty: a process whose executable is kitty, whose argv carries no --instance-group (the
# quick-access terminal and the staged sandbox build are started with one) and which is not a helper
# (`kitty +kitten …`). Never `pgrep -nx kitty`, which answers with whichever kitty started last.
kq_main_kitty_pids() {
  "${CC_KQ_PS_BIN:-/bin/ps}" -axo pid=,args= 2>/dev/null | awk '
    { pid = $1; exe = $2; n = split(exe, a, "/"); base = a[n]
      if (base != "kitty") next
      if ($3 ~ /^\+/) next                      # a helper: kitty +kitten …, kitty +runpy …
      for (i = 3; i <= NF; i++) if ($i ~ /^--instance-group/) next
      print pid }'
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

kq_deaf() { # <socket> <kitty pid>
  local sock="${1:-}" pid="${2:-}" q lim="${CC_KITTY_WEDGED_QUEUE_N:-128}" rc
  case "$lim" in ''|*[!0-9]*) lim=128 ;; esac
  q="$(hf_kitty_queue_depth "$sock")"
  if [ "${q:-0}" -lt "$lim" ]; then printf 'queue=%s under %s' "${q:-0}" "$lim"; return 1; fi
  rc=0; kq_peer_thread "$pid" || rc=$?
  case "$rc" in
    1) printf 'queue=%s full, and sample of kitty %s shows no KittyPeerMon thread' "$q" "$pid"; return 0 ;;
    0) printf 'queue=%s full, but the KittyPeerMon thread is running: slow, not deaf' "$q"; return 1 ;;
    *) printf 'queue=%s full, but kitty %s could not be sampled: not provably deaf' "$q" "$pid"; return 1 ;;
  esac
}
