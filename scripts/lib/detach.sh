#!/usr/bin/env bash
# detach.sh — the setsid spawner, ONE copy, sourced rather than re-typed.
#
# LIFTED VERBATIM from scripts/handoff-fire.sh's detach() (the `start_new_session=True` body), which
# carries the argument for why nohup+disown is not enough:
#
#   when a typed /exit interrupts the in-flight Bash tool call running the parent script, Claude Code
#   reaps that tool call's entire process GROUP with SIGKILL — a nohup'd child shares that pgid (and
#   its PPID is the parent while the parent still runs), so the child dies instantly: 0-byte log, no
#   error, nothing done. Observed 2× on 2026-07-13 and reproduced synthetically the same day.
#   start_new_session=True gives the child its OWN session+pgid and PPID 1 immediately: immune to
#   group kill and to a parent-tree walk alike, with no race to win.
#
# The same property is what `lr-fleet.sh --one … --detach` needs, for a second reason: the INVOKING
# session must get its turn back. On 2026-09-19 the lead spent 24.4 turn-minutes inside foreground
# `until` polls over blocking recoveries, and 86 min 52 s of operator-visible screenshots queued
# behind those turns (U11 §2).
#
# handoff-fire.sh keeps its own copy: it is a single 12,383-line file that is copied and executed
# standalone by the deployed layer, and making it depend on a sibling lib at the moment it is
# spawning a watcher would trade a real failure mode for a cosmetic one. Both copies are the same
# six lines; this file is the one NEW consumers source.
#
# Usage:  . scripts/lib/detach.sh ;  pid="$(detach "$LOG" env FOO=1 bash script.sh --args)"
# stdin is /dev/null, stdout+stderr are appended UNBUFFERED to $1, and the child's pid is printed.

detach() { # $1=logfile  $2...=command  → prints the detached child's pid on stdout
  [ $# -ge 2 ] || { echo "detach: usage: detach <logfile> <command> [args…]" >&2; return 2; }
  /usr/bin/python3 - "$@" <<'PY'
import subprocess, sys
log = open(sys.argv[1], 'ab', 0)
p = subprocess.Popen(sys.argv[2:], start_new_session=True,
                     stdout=log, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL)
print(p.pid)
PY
}
