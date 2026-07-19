#!/bin/bash
# shellcheck disable=SC2015  # file-wide: the selftest's `cmd && okp || badp` reporter idiom
# caffeinate-floor.sh — T-P16-4: the machine-awake FLOOR, independent of CC per-turn caffeinate.
#
# Why (p16 G-P16-2 / T-P16-4): the only thing keeping the desk awake at idle today is the AC
# `pmset sleep 0` policy (manual, unenforced — T-P16-3 guards that) plus CC's own per-turn
# `caffeinate -i -t 300` children, which RELEASE 300 s after the last turn. In the 24/7 steady state
# every session is idle, and on BATTERY the AC `sleep 0` does not apply (the profile is a hostile
# `sleep 1`), so nothing holds a sleep assertion → the machine idle-sleeps in ~1 min, freezing every
# session. This is the durable floor: a RunAtLoad + KeepAlive LaunchAgent that holds a `caffeinate`
# idle-sleep assertion FOREVER, so a caffeinate assertion is present in `pmset -g assertions` even
# with ZERO active CC turns (the T-P16-4 acceptance criterion).
#
# FLAGS (CC_CAFFEINATE_FLAGS, default "-i -s"):
#   -i  prevent idle system sleep — applies on AC *and* battery (the battery `sleep 1` cover).
#   -s  prevent system sleep — valid only on AC (harmless on battery).
#   NOT -d (the display may sleep — saves the panel; display sleep is benign to headless work) and
#   NOT -u. Downgrade to "-s" for an AC-only floor that lets the machine sleep on battery (preserves
#   UPS runtime through a sustained outage at the cost of freezing sessions on battery) — the
#   activation snippet documents this battery-policy tradeoff; loading the plist ratifies the default.
#
# EXEC model: `--run` exec's caffeinate, so the KeepAlive-tracked launchd process IS the assertion
# holder — if it is ever killed, launchd relaunches it (≥10 s throttle). No `-t` timeout ⇒ it holds
# the assertion until killed (that is the point, and the discriminator vs the per-turn `-t 300`).
# C10: the OPERATOR loads the plist; the agent never loads it. Kill-switch: launchctl bootout.
# Selftest: `--selftest` (deterministic — never execs a real, blocking caffeinate).
set -uo pipefail

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
FLAGS="${CC_CAFFEINATE_FLAGS:--i -s}"
CAFFEINATE_BIN="${CC_CAFFEINATE_BIN:-caffeinate}"
LOG="${CC_CAFFEINATE_LOG:-$HOME/.claude/autonomy/caffeinate-floor.log}"
# how --verify enumerates caffeinate processes; overridable for tests (emits one line per caffeinate).
PS_CMD="${CC_CAFFEINATE_PS:-pgrep -fl caffeinate}"

now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }

run() { # exec caffeinate so the KeepAlive-tracked process IS the assertion holder
  mkdir -p "$(dirname "$LOG")" 2>/dev/null || true
  printf '%s caffeinate-floor: exec %s %s\n' "$(now_iso)" "$CAFFEINATE_BIN" "$FLAGS" >> "$LOG" 2>/dev/null || true
  # word-split $FLAGS intentionally (multiple flags); exec so this process becomes caffeinate.
  # shellcheck disable=SC2086
  exec "$CAFFEINATE_BIN" $FLAGS
}

# floor_present — true iff some caffeinate process is running WITHOUT a `-t` timeout, i.e. a
# persistent floor rather than a CC per-turn `caffeinate -i -t 300` keepalive (which always carries
# `-t`). This is independent of whether the floor uses -i, -s, or both — the absence of `-t` is the
# durable signature. Returns 0 (present) / 1 (absent).
floor_present() {
  local line seen=1
  while IFS= read -r line; do
    case "$line" in *caffeinate*) : ;; *) continue ;; esac   # a caffeinate line
    case "$line" in *" -t "*|*" -t") continue ;; esac         # per-turn keepalive (has a timeout) → skip
    seen=0; break                                             # a caffeinate line with no -t → the floor
  done < <($PS_CMD 2>/dev/null)
  return "$seen"
}

verify() {
  if floor_present; then
    printf 'caffeinate-floor: PRESENT — a persistent caffeinate floor assertion is held (no -t timeout)\n'
    return 0
  fi
  printf 'caffeinate-floor: ABSENT — no persistent floor (only per-turn -t keepalives, if any)\n'
  return 1
}

# ════ selftest — RED-prove flag construction + the present/absent discriminator ═══════════════════
PASS=0; FAIL=0
# shellcheck disable=SC2317
okp()  { printf '  ok   %-56s\n' "$1"; PASS=$((PASS+1)); }
# shellcheck disable=SC2317
badp() { printf '  FAIL %-56s\n' "$1"; FAIL=$((FAIL+1)); }
# shellcheck disable=SC2317
selftest() {
  local d out; d="$(mktemp -d "${TMPDIR:-/tmp}/caffeinate-floor-selftest.XXXXXX")" || { echo mktemp; exit 1; }
  # shellcheck disable=SC2064
  trap "rm -rf '$d'" EXIT
  echo "caffeinate-floor --selftest:"

  # (1) --run builds `caffeinate <flags>` — CC_CAFFEINATE_BIN=/bin/echo makes exec print + exit
  out="$(CC_CAFFEINATE_BIN=/bin/echo CC_CAFFEINATE_LOG="$d/run.log" "$SELF" --run 2>/dev/null)"
  [ "$out" = "-i -s" ] && okp "default --run execs 'caffeinate -i -s'" || badp "run flags wrong: '$out'"
  out="$(CC_CAFFEINATE_BIN=/bin/echo CC_CAFFEINATE_FLAGS='-s' CC_CAFFEINATE_LOG="$d/run2.log" "$SELF" --run 2>/dev/null)"
  [ "$out" = "-s" ] && okp "CC_CAFFEINATE_FLAGS=-s downgrade (AC-only floor)" || badp "downgrade wrong: '$out'"
  grep -q 'exec' "$d/run.log" && okp "--run logs the exec line" || badp "--run did not log"

  # (2) --verify PRESENT: fixture has the floor (-i -s, no -t) alongside a per-turn -t 300
  printf '40000 caffeinate -i -s\n30000 caffeinate -i -t 300\n' > "$d/present.ps"
  CC_CAFFEINATE_PS="cat $d/present.ps" "$SELF" --verify >/dev/null 2>&1 \
    && okp "--verify PRESENT (floor with no -t) → exit 0" || badp "PRESENT floor not detected"

  # (3) --verify ABSENT: only a per-turn -t 300 keepalive (no persistent floor)
  printf '30000 caffeinate -i -t 300\n' > "$d/perturn.ps"
  CC_CAFFEINATE_PS="cat $d/perturn.ps" "$SELF" --verify >/dev/null 2>&1 \
    && badp "per-turn -t keepalive falsely counted as the floor" || okp "--verify ABSENT (only per-turn -t) → exit 1"

  # (4) --verify ABSENT: no caffeinate at all
  : > "$d/none.ps"
  CC_CAFFEINATE_PS="cat $d/none.ps" "$SELF" --verify >/dev/null 2>&1 \
    && badp "no-caffeinate falsely GREEN" || okp "--verify ABSENT (no caffeinate) → exit 1"

  # (5) a downgraded -s-only floor is still detected (no -t)
  printf '41000 caffeinate -s\n' > "$d/sonly.ps"
  CC_CAFFEINATE_PS="cat $d/sonly.ps" "$SELF" --verify >/dev/null 2>&1 \
    && okp "-s-only floor still detected as PRESENT" || badp "-s-only floor missed"

  echo "caffeinate-floor --selftest: $PASS passed, $FAIL failed"
  [ "$FAIL" -eq 0 ] || exit 1
  echo "caffeinate-floor --selftest: GREEN — run builds the flags; present/absent discriminates the floor from per-turn -t keepalives."
}

case "${1:-}" in
  --selftest) selftest ;;
  --run|"")   run ;;
  --verify)   verify ;;
  *) printf 'caffeinate-floor: unknown arg %s (use --run | --verify | --selftest)\n' "$1" >&2; exit 2 ;;
esac
