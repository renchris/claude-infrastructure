#!/bin/bash
# utc-stamp-lint — a RATCHET on timestamps that CLAIM UTC and carry local time (M4).
#
# WHY. Timestamp format is a system-wide contract here, not a per-script style choice. Producers
# write ISO stamps; consumers compare them — lexically in jq (`.lastTs < $cutoff` in cc-backlog),
# numerically after epoch conversion (cc-inbox-guard, cc-reaper) — and every one of those comparisons
# is against a `date -u` baseline. So ONE producer emitting local time under a UTC label shifts every
# downstream age gate by the TZ offset. In PDT that is 7 hours: a freshness check reads hours stale,
# an age gate fires early, a "reaper DORMANT" alarm fires against a reaper that ran seconds ago.
#
# THE SCAR THIS IS BUILT FROM, recovered from git rather than paraphrased. cc-reaper's log() was:
#     log(){ printf '[%s] %s\n' "$(date '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null)" ... }
# fixed in b4e3c355 to `date -u '+%Y-%m-%dT%H:%M:%SZ'`, whose commit subject is exactly the failure
# mode: "log() stamps true UTC — a bare date read hours stale as Z, faking 'reaper DORMANT'". The
# selftest below replays that literal line as its RED control.
#
# THE RULE — narrow on purpose, and decidable from one line: a stamp whose format string ends in a
# literal `Z` is ASSERTING UTC ("Z" is the Zulu designator; it has no other meaning in ISO-8601). If
# the `date` call producing it has no `-u`, the assertion is FALSE on any box not set to UTC. That is
# a self-contradiction inside a single expression — no cross-file inference, no judgement about
# whether some consumer compares it, and therefore no false positives to train people to ignore.
#
# WHAT IS DELIBERATELY *NOT* FLAGGED, measured over the tree rather than guessed:
#   • `date -u '+…Z'`               — 84 sites. Correct, and the overwhelming majority.
#   • `date '+%Y-%m-%dT%H:%M:%S%z'` — 4 sites (cc-notify, mailbox-pending). Local time WITH an
#     explicit offset is unambiguous and correctly consumed: cc-inbox-guard:134 parses it with
#     `-f '%Y-%m-%dT%H:%M:%S%z'`. Flagging these would be wrong, not merely noisy.
#   • `date '+%Y-%m-%d %H:%M:%S'` log prefixes — dozens. No UTC claim, human-facing, nothing
#     compares them against a UTC baseline.
#   • Python `datetime.now()` renderings — claude-accounts:1171,1209 are LOCAL wall-clock displays by
#     design (their own comments say so: "aware → local, to match 'live · Mon HH:MM'"). A naive
#     datetime rendered with a literal Z would be the same defect class, so that form IS matched.
# High precision beats high recall for a rule that BLOCKS lands: the tree currently has ZERO
# violations, so this ships as a true ratchet with an EMPTY allowlist — nothing grandfathered.
#
# Exit: 0 = clean · 1 = violation · 2 = bad usage / unreadable scan dir (LOUD, never silent-green)
#
# Env seams: CC_UTC_ALLOWLIST overrides the embedded ratchet · CC_UTC_OWN scopes which violations may
# BLOCK (see OWN-SCOPE).
set -uo pipefail

SELF="$0"
while [ -L "$SELF" ]; do
  _link="$(readlink "$SELF")"
  case "$_link" in
    /*) SELF="$_link" ;;
    *)  SELF="$(dirname "$SELF")/$_link" ;;
  esac
done
ROOT="$(cd "$(dirname "$SELF")/.." && pwd)"

# ── the ratchet: files grandfathered with a lying UTC stamp. ONLY EVER DELETE LINES. ──
# EMPTY, and that is the point — the tree was swept clean before this landed (the one historical
# violation, cc-reaper:59, was fixed in b4e3c355). An allowlist that starts empty can only shrink.
EMBEDDED_ALLOWLIST=""

# OWN-SCOPE — same three-state contract as test-hermeticity-lint / test-walltime-lint, and for the
# same measured reason: a whole-tree BLOCKING lint is a fleet-wide hard stop (a lander refused over a
# file it never touched), which is itself the defect that discipline exists to prevent. States:
# own-set ABSENT ⇒ strict whole-tree · SET-BUT-EMPTY ⇒ "I change no file" ⇒ nothing blocks · SET ⇒
# block on those only. `${VAR:-}` cannot express that, so presence rides on argument count here and
# on `${CC_UTC_OWN+set}` at the entry point.
in_own() {  # $1=path · $2=own-set text · $3=1 if an own-set was supplied at all
  [ "${3:-0}" = "1" ] || return 0
  [ -n "$2" ] || return 1
  printf '%s\n' "$2" | grep -qxF "$1"
}

in_allowlist() { printf '%s\n' "$2" | grep -qxF "$1"; }

# lying_stamps <file> → "<line>:<text>" per violation.
#
# Two families, both anchored on a Z-terminated format string:
#   (a) shell — a `date` invocation whose flags do not include -u, producing '+…Z'. The negative
#       lookahead is spelled out longhand because BREs have none: match `date` followed by any run of
#       non-`u` short flags, then the format. `date -u`, `date -ur`, `TZ=UTC date` all miss it.
#   (b) python — a NAIVE datetime (`datetime.now()` with no tz argument) whose output is stamped with
#       a literal Z, e.g. `datetime.now().strftime('…Z')` or an isoformat with "Z" appended.
# Comment lines are skipped: prose about a stamp is documentation, and flagging it trains people to
# ignore the lint. `TZ=UTC` anywhere on the line also exonerates — that is the other legitimate way
# to produce true UTC (cc-reaper:299 uses it).
lying_stamps() { # $1=file
  grep -nE "date[[:space:]]+((-[^u[:space:]]+|\+[^[:space:]]*)[[:space:]]+)*['\"]?\+[^'\"]*Z['\"]?" "$1" 2>/dev/null \
    | grep -vE '^[0-9]+:[[:space:]]*#' \
    | grep -vE 'date[[:space:]]+-[a-zA-Z]*u|TZ=UTC|CC_[A-Z_]*=|utc_ok'
  grep -nE "datetime\.now\(\)[^#]*(strftime|isoformat)[^#]*Z" "$1" 2>/dev/null \
    | grep -vE '^[0-9]+:[[:space:]]*#' \
    | grep -vE 'timezone\.utc|tz=|TZ=UTC|utc_ok'
}

# lint <dir> <allowlist-text> [own-set-text] — 0 clean · 1 violations · 2 unusable scan dir
lint_dir() {
  local dir="$1" allow="$2" own="${3:-}" own_scoped=0 f rel hits bad=0 seen=0 other=0 stuck=0
  [ "$#" -ge 3 ] && own_scoped=1
  [ -d "$dir" ] || { echo "utc-stamp-lint: ⛔ not a directory: $dir" >&2; return 2; }
  # Every executable/script under the scan root. -type f only; symlinks into the live layer would
  # double-report the same repo file.
  while IFS= read -r f; do
    [ -f "$f" ] || continue
    case "$f" in *.pyc|*/.git/*) continue ;; esac
    # A DETECTOR MUST NOT SCAN ITSELF. This file necessarily CONTAINS the pattern it hunts — its
    # selftest fixtures replay the real b4e3c355 scar line byte-for-byte, because a control that
    # hand-approximates the artifact passes vacuously (memory: control-must-replay-the-real-artifact).
    # Those lines are pattern-bearing DATA, not stamps this script emits, and rewriting them to dodge
    # the regex would destroy the very property that makes them a valid control. Text is never
    # evidence (memory: detector-matching-its-own-skill-description).
    # What validates THIS file is `--selftest`, which is wired into the gate alongside the scan.
    # For any OTHER file that legitimately carries the pattern as data, the per-line escape hatch is
    # a trailing `utc_ok` marker — see lying_stamps.
    case "$(basename "$f")" in utc-stamp-lint.sh) continue ;; esac
    seen=$((seen + 1))
    rel="${f#"$dir"/}"
    hits="$(lying_stamps "$f")"
    if [ -n "$hits" ]; then
      if in_allowlist "$rel" "$allow"; then
        continue
      elif in_own "$rel" "$own" "$own_scoped"; then
        printf '  LYING-Z %s\n' "$rel"
        printf '%s\n' "$hits" | sed 's/^/            /'
        bad=$((bad + 1))
      else
        printf '  lying?  %s (NOT in your diff — advisory, not blocking)\n' "$rel"
        other=$((other + 1))
      fi
    elif in_allowlist "$rel" "$allow"; then
      if in_own "$rel" "$own" "$own_scoped"; then
        printf '  RATCHET %s is clean now — delete its allowlist line\n' "$rel"
        stuck=$((stuck + 1))
      else
        printf '  ratchet? %s is fixed but still grandfathered (NOT in your diff — advisory)\n' "$rel"
        other=$((other + 1))
      fi
    fi
  done <<EOF
$(find "$dir" -type f \( -name '*.sh' -o -name '*.py' -o -name '*.bats' -o ! -name '*.*' \) 2>/dev/null)
EOF
  [ "$seen" -gt 0 ] || { echo "utc-stamp-lint: ⛔ no scannable files under $dir" >&2; return 2; }
  [ "$other" -eq 0 ] || echo "utc-stamp-lint: $other pre-existing item(s) NOT in your diff — reported, not blocking (own-scope)."

  if [ "$bad" -gt 0 ]; then
    echo "utc-stamp-lint: ⛔ $bad file(s) above stamp a literal Z from a non-UTC clock."
    echo "  Why it matters: 'Z' ASSERTS UTC, and every consumer in this repo compares stamps against"
    echo "  a \`date -u\` baseline — lexically in jq, numerically after epoch conversion. One local-time"
    echo "  producer shifts every downstream age gate by the TZ offset (7h in PDT), so a freshness"
    echo "  check reads hours stale. That is cc-reaper's b4e3c355 scar: a bare \`date\` faked a"
    echo "  'reaper DORMANT' alarm against a reaper that had just run."
    # shellcheck disable=SC2016  # literal guidance: the author must type -u, not this box's clock
    echo '  Fix: add -u — date -u '"'"'+%Y-%m-%dT%H:%M:%SZ'"'"'   (or drop the Z and emit %z instead,'
    echo "       which is legal and correctly parsed: see cc-notify + cc-inbox-guard:134.)"
  fi
  if [ "$stuck" -gt 0 ]; then
    echo "utc-stamp-lint: ⛔ $stuck file(s) above are fixed but still grandfathered."
    echo "  Fix: delete their lines from EMBEDDED_ALLOWLIST in $0 — the ratchet only shrinks."
  fi
  [ $((bad + stuck)) -eq 0 ] || return 1
  echo "utc-stamp-lint: clean — $seen file(s) scanned; $(printf '%s\n' "$allow" | grep -c .) grandfathered, 0 lying UTC stamps."
  return 0
}

# ── --selftest: every case proves a RED path fires or a GREEN path does not, both directions ──────
if [ "${1:-}" = "--selftest" ]; then
  d="$(mktemp -d)"; trap 'rm -rf "$d"' EXIT
  for c in scar utc tzutc offset logfmt comment pynaive pyaware; do mkdir -p "$d/$c"; done
  mk() { printf '#!/bin/bash\n%s\n' "$2" > "$d/$1/probe.sh"; }
  mkpy() { printf '#!/usr/bin/env python3\n%s\n' "$2" > "$d/$1/probe.py"; }

  # THE CONTROL IS THE REAL ARTIFACT, recovered from git (memory: control-must-replay-the-real-
  # artifact) — the exact cc-reaper line b4e3c355 fixed, not an approximation of it.
  mk scar    "log(){ printf '[%s] %s\\n' \"\$(date '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null)\" \"\$*\" >> \"\$LOG_FILE\"; }"
  mk utc     "log(){ printf '[%s]\\n' \"\$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null)\"; }"
  mk tzutc   "ep(){ TZ=UTC date -j -f '%Y-%m-%dT%H:%M:%S' \"\$1\" +%s; }"
  mk offset  "ts=\"\$(date '+%Y-%m-%dT%H:%M:%S%z')\""
  mk logfmt  "log(){ echo \"[\$(date '+%Y-%m-%d %H:%M:%S')] \$1\" >> \"\$LOG\"; }"
  mk comment "# a bare \`date '+%Y-%m-%dT%H:%M:%SZ'\` here would be the b4e3c355 scar
now(){ date -u +%s; }"
  mkpy pynaive "stamp = datetime.now().strftime('%Y-%m-%dT%H:%M:%SZ')"
  mkpy pyaware "stamp = datetime.now(timezone.utc).isoformat().replace('+00:00', 'Z')"

  fails=0
  chk() { # <dir> <expected-rc> <message>
    lint_dir "$d/$1" "" >/dev/null 2>&1; local rc=$?
    [ "$rc" -eq "$2" ] || { echo "SELFTEST FAIL: $3 (rc $rc, expected $2)"; fails=1; }
  }
  chk scar    1 "the REAL cc-reaper scar line did not go RED"
  chk utc     0 "date -u went RED — the correct form must stay legal"
  chk tzutc   0 "TZ=UTC went RED — the other legitimate UTC form must stay legal"
  chk offset  0 "an explicit %z offset went RED — local+offset is unambiguous and correctly parsed"
  chk logfmt  0 "a plain log-prefix timestamp went RED — it makes no UTC claim"
  chk comment 0 "a scar quoted in a COMMENT went RED — prose is not code"
  chk pynaive 1 "a naive datetime.now() stamped with Z did not go RED"
  chk pyaware 0 "an AWARE datetime rendered as Z went RED — that is the correct Python form"

  # allowlist, both directions
  lint_dir "$d/scar" "probe.sh" >/dev/null 2>&1 || { echo "SELFTEST FAIL: a grandfathered violation did not go GREEN"; fails=1; }
  lint_dir "$d/utc"  "probe.sh" >/dev/null 2>&1; [ "$?" -eq 1 ] || { echo "SELFTEST FAIL: a fixed-but-still-allowlisted file did not go RED (ratchet not shrinking)"; fails=1; }

  # own-scope, all three states
  lint_dir "$d/scar" "" "other.sh"  >/dev/null 2>&1 || { echo "SELFTEST FAIL: a violation OUTSIDE the own-set blocked"; fails=1; }
  lint_dir "$d/scar" "" "probe.sh"  >/dev/null 2>&1; [ "$?" -eq 1 ] || { echo "SELFTEST FAIL: a violation INSIDE the own-set did not block — own-scope disabled the rule"; fails=1; }
  lint_dir "$d/scar" "" ""          >/dev/null 2>&1 || { echo "SELFTEST FAIL: an EMPTY own-set blocked — set-empty collapsed into unset"; fails=1; }
  lint_dir "$d/scar" ""             >/dev/null 2>&1; [ "$?" -eq 1 ] || { echo "SELFTEST FAIL: an ABSENT own-set did not block — strict default lost"; fails=1; }

  # the real tree must be clean, and a bad dir is a NON-VERDICT (2), never a false all-clear
  for real in bin hooks scripts; do
    lint_dir "$ROOT/$real" "$EMBEDDED_ALLOWLIST" >/dev/null 2>&1; rc_real=$?
    case "$rc_real" in
      0) ;;
      2) echo "SELFTEST FAIL: could not scan $ROOT/$real — a NON-VERDICT (bad ROOT?), not a clean tree"; fails=1 ;;
      *) echo "SELFTEST FAIL: $ROOT/$real carries a lying UTC stamp not on the allowlist"; fails=1 ;;
    esac
  done
  lint_dir "$d/nope" "" >/dev/null 2>&1; [ "$?" -eq 2 ] || { echo "SELFTEST FAIL: a missing scan dir did not exit 2 (LOUD)"; fails=1; }

  if [ "$fails" -eq 0 ]; then
    echo "utc-stamp-lint --selftest: 17/17 — RED on the real b4e3c355 scar line + a naive-datetime Z + a stuck ratchet entry; GREEN on date -u, TZ=UTC, an explicit %z offset, a plain log prefix, a commented scar and an aware datetime; own-scope blocks INSIDE / advises OUTSIDE / passes set-empty / stays strict when absent; bin+hooks+scripts clean; LOUD on a bad dir."
    exit 0
  fi
  echo "utc-stamp-lint --selftest: FAILED — the lint does not discriminate."
  exit 1
fi

rc=0
# Default targets built as a real ARRAY. `for t in "${@:-$A $B $C}"` looks equivalent and is not: with
# no args the quoted default expands as ONE word, so $target became the whole "bin hooks scripts"
# string, matched no directory, and the loop body never ran — a bare invocation was a silent no-op
# that still exited 0. A lint whose default mode is a false green is worse than no lint (memory:
# claimed-outcome-vs-checked-outcome). Caught by running it with no arguments.
if [ "$#" -gt 0 ]; then
  targets=("$@")
else
  targets=("$ROOT/bin" "$ROOT/hooks" "$ROOT/scripts")
fi
scanned=0
for target in "${targets[@]}"; do
  [ -d "$target" ] || continue
  scanned=$((scanned + 1))
  if [ -n "${CC_UTC_OWN+set}" ]; then
    lint_dir "$target" "${CC_UTC_ALLOWLIST-$EMBEDDED_ALLOWLIST}" "$CC_UTC_OWN" || rc=1
  else
    lint_dir "$target" "${CC_UTC_ALLOWLIST-$EMBEDDED_ALLOWLIST}" || rc=1
  fi
done
# Scanning NOTHING is a non-verdict, not a pass — the fail-closed direction. Without this, a bad ROOT
# or a mistyped path would print nothing and exit 0, which every caller would read as "clean".
if [ "$scanned" -eq 0 ]; then
  echo "utc-stamp-lint: ⛔ no scannable target directories (looked at: ${targets[*]}) — NOT a clean verdict" >&2
  exit 2
fi
exit "$rc"
