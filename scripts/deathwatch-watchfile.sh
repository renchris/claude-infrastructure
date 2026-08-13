#!/bin/bash
# deathwatch-watchfile — derive lead-deathwatch's watch-file from the P8 session registry.
#
# WHY THIS FILE EXISTS (backlog ed6d0716caa7 / 0328e7cc5742, verified 2026-08-12). L1 death-watch
# was BUILT and could not be ACTIVATED, because nothing in this repo ever wrote the file it watches.
# Every reference to `lead-deathwatch.sh --watch <watch-file>` in the tree was a SPECIFICATION:
# migrations/0004-lead-deathwatch-l1-activation.sh (step 2 BLOCKED), docs/NEVER-WAIT-ACTIVATION.md
# (a template "you adapt + install"), and two 2026-07-18 audit rows. Nothing wrote a line in
# lead-deathwatch.sh:30's format; ~/.claude/deathwatch held only fixtures its 2026-07-15 --selftest
# left behind. That is the `spec-named-mechanism-may-be-prose-only` class: a mechanism cited by name,
# existing only in prose. This is the writer.
#
# 🚨 THIS IS THE AGENT HALF ONLY. The launchd load is the OPERATOR's and MUST come second.
# Migration 0004's own header states why, and it is not ceremony: a launchd job installed before a
# producer exists arms kqueue on an EMPTY watch-list forever and reports a perfectly healthy
# heartbeat while watching NOTHING — a watcher whose liveness proves nothing about its coverage,
# which is the exact failure L1-e exists to prevent, reintroduced one level up. Completeness of the
# DETECTOR (scripts/wait-safety-gate.sh GREEN) is not the same claim as COVERAGE of the fleet.
#
# ── THE FORMAT COUPLING, which is the one thing here that can fail silently and catastrophically ──
# Output lines are TAB-separated:  pid <TAB> start <TAB> label <TAB> waiter <TAB> worktree
#
# `start` is the {pid,start-time} recycling guard's other half (L1-c), and bin/cc-deathwatch-kqueue
# compares it by STRING EQUALITY against its own `pid_start()`, which is
# `ps -o lstart= -p <pid>` with Python's `.strip()` — and NOTHING else. So this producer must emit
# byte-for-byte what that call yields:
#   * NO whitespace collapsing. `ps -o lstart=` pads single-digit days to two columns
#     ("Mon Aug  4 …"), and bin/cc-reaper's proc_lstart DOES collapse runs of spaces (`tr -s ' '`).
#     Reusing that helper here would look obviously right and would make every watched session
#     mismatch, i.e. read as `recycled`, i.e. emit an INSTANT false DEATH for the entire live fleet.
#     A page storm for a healthy machine is strictly worse than no watcher at all.
#   * NO locale forcing. The month name comes from the C library, so `LC_ALL=C` here against an
#     un-forced reader is the same mismatch by another route (memory:
#     c-locale-turns-character-ops-into-byte-ops). Both sides inherit the environment; under launchd
#     they share one. This is asserted, not argued: tests/deathwatch-watchfile.bats round-trips real
#     output through the REAL helper's guard and fails if a live pid ever reads `recycled`.
#
# ── WHAT IS AND IS NOT WATCHED ────────────────────────────────────────────────────────────────────
# A registry row is watched iff it carries a pid AND that pid is alive right now. Rows skipped:
#   * no `pid` (a `provisional:true` row registered before its process existed) — nothing to arm on.
#   * pid gone — the death ALREADY happened, unobserved. Emitting it would make the watcher page a
#     death that is hours old the moment it starts, which is a false-timing alarm, not coverage.
#     These are COUNTED and reported (a growing count means the registry's own GC is not running),
#     never silently dropped.
#
# Exit: 0 wrote a watch-file (possibly empty — an empty fleet is a real answer)
#       2 usage · 3 the registry directory is unreadable (fail-closed: never truncate a good
#         watch-file because the registry vanished for one tick).
set -uo pipefail

REG_DIR="${CC_REGISTRY_DIR:-$HOME/.claude/cc-registry}"
OUT="${CC_DEATHWATCH_WATCHFILE:-$HOME/.claude/deathwatch/watch-list}"
# The page target for a death with no specific waiter. lead-deathwatch calls `cc-notify "$waiter"`,
# so this must be a name cc-notify can RESOLVE — a role or a session. It is reported, not assumed:
# see the deliverability warning below.
WAITER="${CC_DEATHWATCH_WAITER:-desk}"
ROLES_DIR="${CC_ROLES_DIR:-$HOME/.claude/cc-roles}"
PRINT=0

usage() { sed -n '2,47p' "$0" | sed 's/^# \{0,1\}//'; }
while [ $# -gt 0 ]; do
  case "$1" in
    --print)   PRINT=1 ;;
    --out)     shift; OUT="${1:-}" ;;
    --out=*)   OUT="${1#--out=}" ;;
    -h|--help) usage; exit 0 ;;
    *) echo "deathwatch-watchfile: unknown arg: $1" >&2; exit 2 ;;
  esac
  shift
done

[ -d "$REG_DIR" ] || { echo "deathwatch-watchfile: registry dir unreadable: $REG_DIR" >&2; exit 3; }

# ── the start-time oracle. See the FORMAT COUPLING block: `.strip()`-equivalent and nothing more. ──
# `sed` trims leading/trailing blanks only; interior runs are preserved deliberately.
proc_start_raw() { ps -o lstart= -p "$1" 2>/dev/null | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'; }

rows=0; skipped_nopid=0; skipped_dead=0
tmp="$(mktemp "${TMPDIR:-/tmp}/deathwatch-wl.XXXXXX")" || exit 3
trap 'rm -f "$tmp"' EXIT

for f in "$REG_DIR"/*.json; do
  [ -f "$f" ] || continue
  # One jq per row keeps the fields together; a row whose JSON is corrupt yields empty and is skipped
  # rather than aborting the sweep — one bad file must not cost the whole fleet its watcher.
  # PADDED at the emitter: tab is IFS-WHITESPACE, so an empty cell does not read back empty — it
  # shifts every later column LEFT, silently, exit 0. Here that would read a LABEL into `cwd` and
  # emit a watch-file line whose worktree is a session name. `//` alone is not enough: it substitutes
  # for null/false and never for a present-but-EMPTY string, which is the case that bites (a registry
  # row with `"name": ""`). Only `cwd` is last and may legitimately be empty.
  line="$(jq -r 'def cell(ph): (if . == null then "" else . end) | tostring
                              | gsub("[\\t\\r\\n]"; " ") | if . == "" then ph else . end;
                 select(.pid != null)
                 | [ (.pid | cell("-")), ((.name // .paneUUID) | cell("unknown")), (.cwd // "") ]
                 | @tsv' "$f" 2>/dev/null)"
  [ -n "$line" ] || { skipped_nopid=$((skipped_nopid + 1)); continue; }
  IFS=$'\t' read -r pid label cwd <<EOF
$line
EOF
  [ -n "${pid:-}" ] || { skipped_nopid=$((skipped_nopid + 1)); continue; }
  start="$(proc_start_raw "$pid")"
  [ -n "$start" ] || { skipped_dead=$((skipped_dead + 1)); continue; }
  printf '%s\t%s\t%s\t%s\t%s\n' "$pid" "$start" "$label" "$WAITER" "$cwd" >> "$tmp"
  rows=$((rows + 1))
done

if [ "$PRINT" -eq 1 ]; then
  cat "$tmp"
else
  mkdir -p "$(dirname "$OUT")" 2>/dev/null || true
  # Atomic: the watcher may be reading this file at any instant, and a half-written watch-file is a
  # partially-armed fleet that still heartbeats healthy.
  mv -f "$tmp" "$OUT" || { echo "deathwatch-watchfile: could not write $OUT" >&2; exit 3; }
  trap - EXIT
  echo "deathwatch-watchfile: $rows watched, $skipped_nopid no-pid, $skipped_dead already-dead → $OUT"
fi

# ── deliverability: a captured death nobody is told about ─────────────────────────────────────────
# lead-deathwatch pages `cc-notify "$waiter"`. If that name resolves to nothing, L1-b still writes
# the forensics record to disk (capture precedes page by design), so this degrades to
# "WIP captured, nobody notified" — loud, never fatal. Measured 2026-08-12: cc-roles/ held only an
# EMPTY `orchestrator` file and no `desk`, so the default waiter resolved to nothing at all. A role
# file that exists but is empty is the `a dead uuid is still non-empty` trap in its other direction,
# so emptiness is checked, not just existence.
if [ "$rows" -gt 0 ] && [ ! -s "$ROLES_DIR/$WAITER" ] && ! printf '%s' "$WAITER" | grep -q -- '-[0-9][0-9]*$'; then
  echo "deathwatch-watchfile: ⚠ waiter '$WAITER' resolves to nothing (no non-empty $ROLES_DIR/$WAITER, and it is not a session name) — deaths will be CAPTURED to disk but the page will reach no one. Wire the role, or set CC_DEATHWATCH_WAITER." >&2
fi
exit 0
