#!/usr/bin/env bash
# pty-census.sh — count DYNAMIC ptys (the resource `kern.tty.ptmx_max` actually governs)
# and report occupancy as a fraction of that limit.
#
# WHY THIS EXISTS, and why the obvious one-liner is wrong
# ------------------------------------------------------
# Every prior census in this program used `ls /dev/ttys* | wc -l`. That glob matches TWO
# disjoint device classes and only one of them is a ptmx-allocated pty:
#
#   /dev/ttys000 .. /dev/ttys999   major 0x10 (16), owner <user>:tty, created on open,
#                                  REMOVED on last close   ← the ptmx clones, 3-digit by
#                                  construction (`/dev/ttys%03d`) — these are the resource
#   /dev/ttys0   .. /dev/ttysf     major 0x40 (64), root:wheel, present since boot, static
#                                  legacy BSD pty slave nodes — 16 of them, ALWAYS, never
#                                  allocated, never released, never counted against ptmx_max
#
# So the naive glob reports a CONSTANT +16 offset. Measured on this box 2026-08-09:
# 27 glob matches = 11 real ptys + 16 legacy nodes. Every published ptys/session figure in
# this program was inflated by 16/N — which at the small N those figures were taken at
# (6 and 15 sessions) is a factor of 2-4, i.e. the entire claimed effect.
#
# The predicate here is `/dev/ttys[0-9][0-9][0-9]`: exactly the 3-digit clones, which is the
# same construction the ~999 architectural ceiling is derived from.
#
# Exit 0 always for the human/`--json` readouts (this is a GAUGE, never a gate — wave D owns
# gate terms and a refusing term is operator-gated). `--assert-under PCT` is opt-in and is the
# only mode that can exit non-zero, for use by a test.

set -uo pipefail

PROG=${0##*/}
FORMAT=human
ASSERT_UNDER=""

usage() {
  cat <<EOF
$PROG — dynamic pty occupancy against kern.tty.ptmx_max

  --json               machine-readable single object
  --terse              one line, for embedding in an existing readout
  --assert-under PCT   exit 1 if occupancy pct >= PCT (opt-in; nothing calls this by default)
  -h, --help

Counts /dev/ttys[0-9][0-9][0-9] — the ptmx clones. Does NOT count the 16 static legacy
/dev/ttys[0-9a-f] nodes, which are not ptys and are not governed by ptmx_max.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --json)  FORMAT=json; shift ;;
    --terse) FORMAT=terse; shift ;;
    --assert-under) ASSERT_UNDER="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "$PROG: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

# --- the census ------------------------------------------------------------------------------
# CC_PTY_DEV_DIR is a TEST SEAM, not a feature: /dev cannot be fixtured, and a predicate this
# error-prone that no test can reach is exactly how the +16 offset survived three documents.
# Production never sets it.
DEV="${CC_PTY_DEV_DIR:-/dev}"

# `ls -d` on a non-matching glob prints nothing and errors; the count is what we want either way.
pty_used=$(ls -d "$DEV"/ttys[0-9][0-9][0-9] 2>/dev/null | wc -l | tr -d ' ')
pty_used=${pty_used:-0}

# The legacy nodes, counted explicitly so the offset is VISIBLE in the output rather than
# silently corrected. A reader who has the old number in hand can reconcile it here.
pty_legacy=$(ls -d "$DEV"/ttys[0-9a-f] 2>/dev/null | wc -l | tr -d ' ')
pty_legacy=${pty_legacy:-0}

pty_max="${CC_PTY_MAX:-$(sysctl -n kern.tty.ptmx_max 2>/dev/null || echo 0)}"
case "$pty_max" in ''|*[!0-9]*) pty_max=0 ;; esac

# Architectural ceiling: slave nodes are named /dev/ttys%03d, so 3 digits bounds it at 1000
# names (000-999) no matter what the sysctl is raised to.
pty_arch_max=999

# Sessions, counted by COMMAND POSITION — never `pgrep -f claude`, which matches every session
# whose argv merely MENTIONS claude (this fleet's indexed `pgrep-f-matches-agent-briefs`
# failure; it is what contaminated the census this instrument replaces). `ps -axo comm=` emits the
# executable path ALONE, with no argv, so a brief quoting "claude" cannot reach this predicate at
# all — the contamination is excluded by the column choice, before the match even runs.
if [ -n "${CC_PTY_PS_FILE:-}" ] && [ -r "${CC_PTY_PS_FILE}" ]; then
  ps_snap=$(cat "$CC_PTY_PS_FILE")            # test seam; production reads live ps
else
  ps_snap=$(ps -axo comm= 2>/dev/null)
fi
sessions=$(printf '%s\n' "$ps_snap" | awk '{n=split($0,p,"/"); if (p[n]=="claude") c++} END{print c+0}')

pct=0
if [ "$pty_max" -gt 0 ]; then
  pct=$(( pty_used * 100 / pty_max ))
fi

per_session="n-a"
if [ "${sessions:-0}" -gt 0 ]; then
  per_session=$(awk -v u="$pty_used" -v s="$sessions" 'BEGIN{printf "%.2f", u/s}')
fi

case "$FORMAT" in
  json)
    printf '{"pty_used":%s,"pty_max":%s,"pty_pct":%s,"pty_arch_max":%s,"pty_legacy_nodes":%s,"sessions":%s,"ptys_per_session":"%s"}\n' \
      "$pty_used" "$pty_max" "$pct" "$pty_arch_max" "$pty_legacy" "${sessions:-0}" "$per_session"
    ;;
  terse)
    printf 'ptys %s/%s (%s%%) · %s/session over %s sessions\n' \
      "$pty_used" "$pty_max" "$pct" "$per_session" "${sessions:-0}"
    ;;
  *)
    printf 'ptys        %s / %s  (%s%%)   arch ceiling %s (/dev/ttys%%03d)\n' \
      "$pty_used" "$pty_max" "$pct" "$pty_arch_max"
    printf 'sessions    %s   ⇒ %s ptys/session\n' "${sessions:-0}" "$per_session"
    printf 'excluded    %s static legacy /dev/ttys[0-9a-f] nodes (NOT ptys, not ptmx_max-governed)\n' "$pty_legacy"
    ;;
esac

if [ -n "$ASSERT_UNDER" ]; then
  case "$ASSERT_UNDER" in ''|*[!0-9]*) echo "$PROG: --assert-under needs an integer percent" >&2; exit 2 ;; esac
  [ "$pct" -lt "$ASSERT_UNDER" ] || exit 1
fi
exit 0
