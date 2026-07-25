#!/bin/bash
# growth-coverage-lint — the MISSING DUAL of scripts/reaper-horizon-lint.sh.
#
# THE GAP (audit 03 §3, verbatim): "The reaper lint has a FLOOR and no CEILING." reaper-horizon-lint
# fails the build when a reaper deletes evidence TOO SOON. **Nothing anywhere fails when a state dir
# or append-only log has no reaper at all.** The exhaustive grep for age reapers across
# `bin/ hooks/ scripts/ statusline.sh` returns 7 sites; everything else in the live layer has zero
# age coverage. Each of those dirs was added with a lifecycle `rm` and no horizon, and no gate could
# notice — `comms-alarms/` reached 395 files with *zero* rm sites of any kind.
#
# This gate is the ceiling. It is the fix that stops the CLASS, not the instances:
#
#   1. EVERY growth surface in the live layer is enumerated in a checked-in SSOT
#      (scripts/growth-coverage.conf), and every row must declare exactly one disposition.
#   2. A surface present on disk but ABSENT from the SSOT is a hard failure. That is the class-
#      stopper: the next state dir someone adds cannot become invisible, because it has to be
#      classified before this gate goes green again.
#   3. A row claiming `reaper=<token>` must still be findable in the source. Reapers get deleted
#      and renamed; a coverage claim that nothing verifies is worse than no claim at all
#      (audit §3i: a check must observe the thing it guards, not a description of it).
#
# THE FOUR DISPOSITIONS (one per row; `path` is relative to $GROWTH_ROOT):
#
#   reaper=<token>              An age reaper covers it. <token> is grepped in bin/ hooks/ scripts/
#                               statusline.sh — usually the script basename.
#   unbounded-by-design=<why>   A durable ledger that must NOT be reaped. The reason is mandatory:
#                               this is the row a future reader will try to "fix".
#   gap=<ref>                   KNOWN uncovered, reviewed, not yet fixed. Reported on every run and
#                               counted in the verdict; `--strict` turns these into failures. This
#                               verb exists so the honest answer to "no reaper yet" is a visible
#                               ledger entry rather than a false `unbounded-by-design`.
#   ignore=<why>                Not a growth surface we own — repo code, or harness-managed state
#                               bounded by CC's own cleanupPeriodDays.
#
# Usage:  growth-coverage-lint.sh [--strict] [--selftest]
# Exit:   0 = every surface classified and every reaper claim verified (gaps warn)
#         1 = an unclassified surface, a broken reaper claim, a malformed row, or --strict with gaps
#         2 = the SSOT itself is missing/unreadable (fail-closed — a lint that cannot read its own
#             list must not report health)
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2

GROWTH_ROOT="${GROWTH_ROOT:-$HOME/.claude}"
SSOT="${GROWTH_COVERAGE_SSOT:-$(dirname "$0")/growth-coverage.conf}"
REAPER_SCAN="${GROWTH_REAPER_SCAN:-bin hooks scripts statusline.sh}"
STRICT=0; SELFTEST=0

for a in "$@"; do
  case "$a" in
    --strict)   STRICT=1 ;;
    --selftest) SELFTEST=1 ;;
    -h|--help)  sed -n '2,/^set -uo/p' "$0" | sed 's/^# \{0,1\}//; /^set -uo/d'; exit 0 ;;
    *) echo "growth-coverage-lint: unknown arg: $a" >&2; exit 2 ;;
  esac
done

viol=0; gaps=0; warns=0; rows=0
bad()  { printf '  ⛔ %s\n' "$1"; viol=$((viol + 1)); }
warn() { printf '  ⚠️  %s\n' "$1"; warns=$((warns + 1)); }
gap()  { printf '  ▫︎ GAP %s\n' "$1"; gaps=$((gaps + 1)); }

# ── read the SSOT ─────────────────────────────────────────────────────────────────────────────
[ -r "$SSOT" ] || { echo "growth-coverage-lint: SSOT unreadable at $SSOT — FAIL-CLOSED" >&2; exit 2; }

# DECLARED_PATHS is a newline-delimited set; bash 3.2 has no associative arrays.
DECLARED_PATHS=""
declared() { case "$DECLARED_PATHS" in *"
$1
"*) return 0 ;; esac; return 1; }

echo "growth-coverage-lint: root=$GROWTH_ROOT ssot=$SSOT"

while IFS= read -r line; do
  case "$line" in ''|'#'*) continue ;; esac
  path=$(printf '%s' "$line" | awk '{print $1}')
  decl=$(printf '%s' "$line" | awk '{$1=""; sub(/^ +/,""); print}')
  [ -n "$path" ] || continue
  rows=$((rows + 1))
  DECLARED_PATHS="$DECLARED_PATHS
$path
"
  verb="${decl%%=*}"; val="${decl#*=}"
  case "$decl" in *=*) : ;; *) bad "$path  malformed row — expected '<path> <verb>=<value>', got '$decl'"; continue ;; esac
  [ -n "$val" ] || { bad "$path  '$verb=' has an empty value"; continue; }

  case "$verb" in
    reaper)
      # The claim must still be true in the source. `grep -rF` over the reaper scan roots.
      # shellcheck disable=SC2086  # REAPER_SCAN is an intentional space-separated list of roots
      if ! grep -rqF -- "$val" $REAPER_SCAN 2>/dev/null; then
        bad "$path  claims reaper='$val' but that token is nowhere in [$REAPER_SCAN] — the reaper was renamed or deleted"
      fi
      ;;
    unbounded-by-design) : ;;   # the reason is the deliverable; presence already checked
    gap)                 gap "$path — $val" ;;
    ignore)              : ;;
    *) bad "$path  unknown disposition '$verb' (want reaper | unbounded-by-design | gap | ignore)" ;;
  esac

  # A row for something that no longer exists is drift in the other direction: harmless today,
  # but it makes the SSOT read as covering more than it does.
  [ -e "$GROWTH_ROOT/$path" ] || warn "$path  declared but not present under $GROWTH_ROOT (stale row?)"
done < "$SSOT"

# ── the class-stopper: anything on disk that no row classifies ────────────────────────────────
# Scope is deliberately the two roots where state actually accumulates, plus the append-only files
# beside them. Walking all of ~/.claude would drown the signal in harness caches.
undeclared=0
check_present() { # <relative-path>
  declared "$1" && return 0
  bad "$1  UNCLASSIFIED growth surface — add a row to $(basename "$SSOT") (reaper | unbounded-by-design | gap | ignore)"
  undeclared=$((undeclared + 1))
}

if [ -d "$GROWTH_ROOT" ]; then
  for d in "$GROWTH_ROOT"/*/; do
    [ -d "$d" ] || continue
    check_present "$(basename "$d")"
  done
  for d in "$GROWTH_ROOT"/autonomy/*/; do
    [ -d "$d" ] || continue
    check_present "autonomy/$(basename "$d")"
  done
  # append-only files that sit directly in the two roots (logs/ is classified as one surface —
  # its rotation policy is owned by the rotation job, not by per-file rows here)
  for f in "$GROWTH_ROOT"/*.jsonl "$GROWTH_ROOT"/*.log "$GROWTH_ROOT"/autonomy/*.jsonl "$GROWTH_ROOT"/autonomy/*.log; do
    [ -f "$f" ] || continue
    rel="${f#"$GROWTH_ROOT"/}"
    check_present "$rel"
  done
fi

# ── selftest: prove each failure mode actually fires ──────────────────────────────────────────
if [ "$SELFTEST" -eq 1 ]; then
  echo "  ── selftest ──"
  st_fail=0
  d=$(mktemp -d "${TMPDIR:-/tmp}/growth-lint-selftest.XXXXXX") || exit 2
  mkdir -p "$d/root/covered" "$d/root/surprise"
  printf 'covered reaper=growth-coverage-lint.sh\n' > "$d/ssot.conf"
  # (a) an unclassified dir on disk must FAIL
  if GROWTH_ROOT="$d/root" GROWTH_COVERAGE_SSOT="$d/ssot.conf" bash "$0" >/dev/null 2>&1; then
    echo "  ⛔ selftest: an unclassified dir did NOT fail the gate"; st_fail=$((st_fail + 1))
  else
    echo "  ok  an unclassified dir fails the gate"
  fi
  # (b) once classified, it must PASS
  printf 'surprise ignore=selftest fixture\n' >> "$d/ssot.conf"
  if GROWTH_ROOT="$d/root" GROWTH_COVERAGE_SSOT="$d/ssot.conf" bash "$0" >/dev/null 2>&1; then
    echo "  ok  classifying it clears the gate"
  else
    echo "  ⛔ selftest: a fully classified root still failed"; st_fail=$((st_fail + 1))
  fi
  # (c) a reaper claim naming a token that does not exist must FAIL.
  # The token is ASSEMBLED at runtime on purpose: any literal written here would itself live in
  # this file, which is inside the reaper scan roots, so `grep -rF` would find it and the case
  # would silently pass. (It did, first time round.)
  st_tok="growth-lint-$(printf '%s' absent)-reaper-token"
  printf 'covered reaper=%s\n' "$st_tok" > "$d/ssot2.conf"
  printf 'surprise ignore=selftest fixture\n' >> "$d/ssot2.conf"
  if GROWTH_ROOT="$d/root" GROWTH_COVERAGE_SSOT="$d/ssot2.conf" bash "$0" >/dev/null 2>&1; then
    echo "  ⛔ selftest: a dangling reaper claim did NOT fail the gate"; st_fail=$((st_fail + 1))
  else
    echo "  ok  a dangling reaper claim fails the gate"
  fi
  # (d) an unreadable SSOT must fail-closed with exit 2, never report health
  GROWTH_ROOT="$d/root" GROWTH_COVERAGE_SSOT="$d/nope.conf" bash "$0" >/dev/null 2>&1
  if [ "$?" -eq 2 ]; then echo "  ok  a missing SSOT fails closed (exit 2)"
  else echo "  ⛔ selftest: a missing SSOT did not fail closed"; st_fail=$((st_fail + 1)); fi
  rm -rf "$d"
  [ "$st_fail" -gt 0 ] && viol=$((viol + st_fail))
fi

# ── verdict ───────────────────────────────────────────────────────────────────────────────────
printf 'growth-coverage-lint: %s row(s) · %s unclassified · %s known gap(s) · %s warning(s)\n' \
  "$rows" "$undeclared" "$gaps" "$warns"
if [ "$STRICT" -eq 1 ] && [ "$gaps" -gt 0 ]; then
  echo "growth-coverage-lint: ⛔ --strict and $gaps declared gap(s) remain"
  exit 1
fi
if [ "$viol" -gt 0 ]; then
  echo "growth-coverage-lint: ⛔ $viol violation(s). An unbounded surface nobody declared is how"
  echo "  comms-alarms/ reached 395 files with zero rm sites and no gate could notice."
  exit 1
fi
echo "growth-coverage-lint: clean — every live-layer growth surface is classified and every reaper claim resolves"
exit 0
