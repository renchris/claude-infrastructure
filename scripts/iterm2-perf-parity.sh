#!/bin/bash
# iterm2-perf-parity.sh — drift-check the render knobs declared in config/iterm2-perf.keys.
#
# WHY (row 13 M8, MACHINE_CAPACITY_V2.md §11.3). The render levers §11.9 measured are one-time
# machine tweaks, and a one-time tweak is invisible state: reverted by an app update or a
# preferences reset with nothing to notice. This turns the intended state into a CHECKED state.
#
# READ-ONLY, ABSOLUTELY. This script never writes a default. Applying them is the operator's C10
# activation (agents are classifier-blocked from it), which is exactly why the check and the actuator
# are separate files: a checker that can also "fix" drift becomes an actuator nobody audited.
# ⇒ Until that activation runs, EVERY required row reports DRIFT. That is the CORRECT reading, not a
#   bug — an unset key means the app default is live, and the app defaults are what §11.9 priced.
#
# THE SPOTLIGHT ROW IS A FALSIFIED PREMISE, KEPT AS A PROBE (§11.9(3)). M8b originally proposed
# excluding ~/.claude* from Spotlight. The controlled experiment killed that premise three ways:
#   · all 15 ~/.claude* dirs are ALREADY excluded by the dot-prefix rule (proven per-file);
#   · `.metadata_never_index` is DEAD on this OS (a probe dir carrying it was indexed anyway);
#   · the 0.49-0.80-core mds reading did NOT reproduce (sustained re-measure peaked at 2.1%).
# So NO exclusion action is taken anywhere. What survives is the cheap sudo-free question "is that
# still true?", asked per-file via mdls attribute counts.
#
# AND IT CARRIES A POSITIVE CONTROL, because the obvious form of this probe is unfalsifiable. A
# bare zero — from mdls, or from `mdfind -count` — is returned BOTH by "this file is excluded" and
# by "the instrument is broken / the path is wrong / Spotlight is off". Asserting exclusion from a
# bare zero is the defect in memory actuator-must-see-the-target-population. So the same probe runs
# against a file that MUST be indexed (~/Documents); if the control does not come back indexed, this
# row reports NO-DATA and asserts nothing. `mdutil -s <dir>` is useless here ("unknown indexing
# state" for directories) and the Privacy list is write-only-by-UI and root-gated ⇒ not checkable.
#
# Exits:  0 every required row MATCHes (and the probe is MATCH or disabled)
#         1 at least one row DRIFTs or is UNSET — actionable, so it outranks NO-DATA
#         3 no drift, but at least one row could not be established
#
# Seams: CC_IPP_PARITY=off (kill switch) · CC_IPP_KEYS · CC_IPP_DEFAULTS_BIN · CC_IPP_MDLS_BIN ·
#        CC_IPP_PROBE_FILE · CC_IPP_CONTROL_FILE · CC_IPP_PAGE=off · CC_PAGES_DIR ·
#        CC_IPP_SELFTEST=1 (positive control)
#
# bash 3.2 safe. Ships to launchd ⇒ tested under /bin/bash.

set -uo pipefail

# Resolve this script's own symlink chain BEFORE deriving the repo root: the deployed copy under
# ~/.claude/scripts/ is a symlink into the checkout, and config/ is a top-level dir that does not
# auto-deploy (memory shared-lib-source-ladder-collapses-when-deployed). Resolving $0 first is what
# makes the deployed copy find the keys file at all. bash 3.2 has no `readlink -f`.
SELF="$0"
while [ -L "$SELF" ]; do
  _link="$(readlink "$SELF" 2>/dev/null || true)"
  [ -z "$_link" ] && break
  case "$_link" in /*) SELF="$_link" ;; *) SELF="$(dirname "$SELF")/$_link" ;; esac
done
REPO="$(cd "$(dirname "$SELF")/.." 2>/dev/null && pwd -P || echo "")"

KEYS="${CC_IPP_KEYS:-$REPO/config/iterm2-perf.keys}"
DEFAULTS_BIN="${CC_IPP_DEFAULTS_BIN:-defaults}"
MDLS_BIN="${CC_IPP_MDLS_BIN:-mdls}"
WANT_JSON=0; QUIET=0

while [ $# -gt 0 ]; do
  if   [ "$1" = "--json" ];     then WANT_JSON=1
  elif [ "$1" = "--quiet" ];    then QUIET=1
  elif [ "$1" = "--selftest" ]; then CC_IPP_SELFTEST=1
  elif [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    sed -n '2,/^set -uo/p' "$0" | sed 's/^# \{0,1\}//; /^set -uo/d'; exit 0
  else echo "iterm2-perf-parity.sh: unknown arg '$1'" >&2; exit 64
  fi
  shift
done

if [ "${CC_IPP_PARITY:-on}" = "off" ]; then
  [ "$QUIET" = 1 ] || echo "iterm2-perf-parity: disabled (CC_IPP_PARITY=off)"
  exit 0
fi

# ── the comparison ladder (R6: the live path calls this same function) ────────────────────────────
# `defaults read` prints 1/0 for booleans, but a key written as a string can come back true/false —
# so both spellings normalize. Floats compare NUMERICALLY: "30" and "30.0" are the same setting, and
# a string compare would report a permanent phantom drift on a correctly-set box.
cmp_val() { # <type> <expected> <live> → MATCH | DRIFT
  local t="$1" e="$2" v="$3"
  case "$t" in
    bool)
      case "$e" in true|TRUE|yes|1) e=1 ;; *) e=0 ;; esac
      case "$v" in true|TRUE|yes|1) v=1 ;; false|FALSE|no|0) v=0 ;; *) printf 'DRIFT'; return 0 ;; esac
      [ "$e" = "$v" ] && printf 'MATCH' || printf 'DRIFT' ;;
    float|int)
      case "$v" in ''|*[!0-9.eE+-]*) printf 'DRIFT'; return 0 ;; esac
      if awk -v a="$e" -v b="$v" 'BEGIN{exit !(a+0 == b+0)}'; then printf 'MATCH'; else printf 'DRIFT'; fi ;;
    *)
      [ "$e" = "$v" ] && printf 'MATCH' || printf 'DRIFT' ;;
  esac
}

# Classify the Spotlight probe. Split out so the selftest exercises the REAL decision, including the
# case the whole row exists to prevent: probe 0 with a DEAD control must never read as MATCH.
classify_probe() { # <probe_count> <control_count> → MATCH | DRIFT | NO-DATA
  local p="$1" c="$2"
  case "$p" in ''|*[!0-9]*) printf 'NO-DATA'; return 0 ;; esac
  case "$c" in ''|*[!0-9]*) printf 'NO-DATA'; return 0 ;; esac
  [ "$c" -lt 1 ] && { printf 'NO-DATA'; return 0; }   # control not indexed ⇒ the instrument is blind
  [ "$p" -eq 0 ] && { printf 'MATCH';   return 0; }   # excluded, and we can prove the probe works
  printf 'DRIFT'
}

if [ "${CC_IPP_SELFTEST:-0}" = "1" ]; then
  fails=0
  for probe in "bool:false:0:MATCH" "bool:false:1:DRIFT" "bool:true:1:MATCH" \
               "float:30:30:MATCH" "float:30:30.0:MATCH" "float:30:60:DRIFT" "float:30::DRIFT"; do
    t="${probe%%:*}"; r="${probe#*:}"; e="${r%%:*}"; r="${r#*:}"; v="${r%%:*}"; want="${r#*:}"
    got="$(cmp_val "$t" "$e" "$v")"
    if [ "$got" = "$want" ]; then echo "  control OK   $t expected='$e' live='$v' → $got"
    else echo "  control FAIL $t expected='$e' live='$v' → $got (want $want)"; fails=$((fails+1)); fi
  done
  for probe in "0:3:MATCH" "5:3:DRIFT" "0:0:NO-DATA" "0::NO-DATA" ":3:NO-DATA"; do
    p="${probe%%:*}"; r="${probe#*:}"; c="${r%%:*}"; want="${r#*:}"
    got="$(classify_probe "$p" "$c")"
    if [ "$got" = "$want" ]; then echo "  control OK   probe='$p' control='$c' → $got"
    else echo "  control FAIL probe='$p' control='$c' → $got (want $want)"; fails=$((fails+1)); fi
  done
  [ "$fails" -eq 0 ] && { echo "iterm2-perf-parity: selftest GREEN (MATCH/DRIFT/NO-DATA reachable)"; exit 0; }
  echo "iterm2-perf-parity: selftest RED ($fails)" >&2; exit 70
fi

if [ ! -f "$KEYS" ]; then
  echo "iterm2-perf-parity: keys file not found: $KEYS" >&2
  exit 3
fi

# Is the reader usable at all? A missing `defaults` must make every row NO-DATA, never DRIFT —
# "cannot measure" and "measured, and it is wrong" are different findings with different remedies.
DEFAULTS_OK=1
command -v "$DEFAULTS_BIN" >/dev/null 2>&1 || DEFAULTS_OK=0

N_MATCH=0; N_DRIFT=0; N_UNSET=0; N_NODATA=0
ROWS=""; REPORT=""

# Redirected (not piped) so the counters live in THIS shell — a `... | while read` subshell would
# discard every increment and report 0/0/0 forever. Each command's stdin is closed so it cannot eat
# the keys file out from under the loop.
# `read` splits the five fields itself — the earlier form forked awk four times PER ROW (32 forks
# for the shipped 8-row file) to do what the shell already does for free. Fork cost is a first-class
# concern in this row (§11.2 prices hook chains by fork count), and a checker that runs on a cadence
# should not be the thing it would flag.
# shellcheck disable=SC2034  # `why` is a deliberate SINK: it swallows the rest-of-line rationale so
# the prose cannot leak into `expected`. Dropping it would make `read` stop at 4 fields and silently
# fold the first rationale word into the expected value, turning every row into phantom drift.
while read -r domain key type expected why || [ -n "$domain" ]; do
  case "$domain" in ''|'#'*) continue ;; esac
  [ -z "$key" ] || [ -z "$type" ] || [ -z "$expected" ] && continue

  if [ "$DEFAULTS_OK" = 0 ]; then
    state="NO-DATA"; live=""
  else
    live="$("$DEFAULTS_BIN" read "$domain" "$key" 2>/dev/null </dev/null || true)"
    if [ -z "$live" ]; then
      # UNSET ⇒ the app default is live. SET is the activation, so this counts as drift.
      state="UNSET"
    else
      state="$(cmp_val "$type" "$expected" "$live")"
    fi
  fi

  case "$state" in
    MATCH)   N_MATCH=$((N_MATCH+1)) ;;
    DRIFT)   N_DRIFT=$((N_DRIFT+1)) ;;
    UNSET)   N_UNSET=$((N_UNSET+1)) ;;
    NO-DATA) N_NODATA=$((N_NODATA+1)) ;;
  esac
  REPORT="$REPORT  $(printf '%-8s %-46s expected=%-6s live=%s' "$state" "$key" "$expected" "${live:-<unset>}")
"
  ROWS="$ROWS{\"key\":\"$key\",\"state\":\"$state\",\"expected\":\"$expected\",\"live\":\"${live:-}\"},"
done < "$KEYS"

# ── the Spotlight-exclusion probe row (§11.9(3)) ──────────────────────────────────────────────────
PROBE_FILE="${CC_IPP_PROBE_FILE:-}"
if [ -z "$PROBE_FILE" ]; then
  PROBE_FILE="$(find "$HOME/.claude/projects" -name '*.jsonl' -type f 2>/dev/null | head -1 || true)"
fi
CONTROL_FILE="${CC_IPP_CONTROL_FILE:-}"
if [ -z "$CONTROL_FILE" ]; then
  CONTROL_FILE="$(find "$HOME/Documents" -type f ! -name '.*' 2>/dev/null | head -1 || true)"
fi

count_idx_attrs() { # <file> → number of indexed-content attributes, or empty when unmeasurable
  local f="$1"
  [ -n "$f" ] && [ -f "$f" ] || return 0
  command -v "$MDLS_BIN" >/dev/null 2>&1 || return 0
  "$MDLS_BIN" "$f" 2>/dev/null </dev/null | grep -cE 'kMDItemContentType|kMDItemKind' || true
}

PROBE_COUNT="$(count_idx_attrs "$PROBE_FILE")"
CONTROL_COUNT="$(count_idx_attrs "$CONTROL_FILE")"
PROBE_STATE="$(classify_probe "${PROBE_COUNT:-}" "${CONTROL_COUNT:-}")"
case "$PROBE_STATE" in
  MATCH)   N_MATCH=$((N_MATCH+1)) ;;
  DRIFT)   N_DRIFT=$((N_DRIFT+1)) ;;
  NO-DATA) N_NODATA=$((N_NODATA+1)) ;;
esac
REPORT="$REPORT  $(printf '%-8s %-46s probe=%s control=%s' \
  "$PROBE_STATE" "spotlight-exclusion(~/.claude)" "${PROBE_COUNT:-?}" "${CONTROL_COUNT:-?}")
"
ROWS="$ROWS{\"key\":\"spotlight_exclusion\",\"state\":\"$PROBE_STATE\",\"probe_attrs\":\"${PROBE_COUNT:-}\",\"control_attrs\":\"${CONTROL_COUNT:-}\"}"

# DRIFT outranks NO-DATA: a definite, actionable finding should not be masked by an unrelated blind
# row. NO-DATA only governs when nothing drifted, so "all match" can never be printed over a row
# that was never established.
DRIFT_TOTAL=$((N_DRIFT + N_UNSET))
if   [ "$DRIFT_TOTAL" -gt 0 ]; then RC=1; VERDICT="DRIFT"
elif [ "$N_NODATA"    -gt 0 ]; then RC=3; VERDICT="NO-DATA"
else                                RC=0; VERDICT="MATCH"
fi

TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
JSON="$(printf '{"ts":"%s","verdict":"%s","match":%s,"drift":%s,"unset":%s,"no_data":%s,"rows":[%s]}' \
  "$TS" "$VERDICT" "$N_MATCH" "$N_DRIFT" "$N_UNSET" "$N_NODATA" "$ROWS")"

# ── page on drift, SELF-CLEAR when parity is restored ─────────────────────────────────────────────
# One fixed slug (the capacity-alarm.sh:163-199 pattern): a cadence job overwrites rather than
# accumulates, and a page whose condition has passed is misinformation, not history.
PAGES_DIR="${CC_PAGES_DIR:-$HOME/.claude/autonomy/pages}"
PAGE="$PAGES_DIR/iterm2-perf-drift.page"
if [ "${CC_IPP_PAGE:-on}" != "off" ]; then
  if [ "$VERDICT" = "DRIFT" ]; then
    mkdir -p "$PAGES_DIR" 2>/dev/null || true
    {
      date +%s 2>/dev/null || echo 0
      printf 'iTerm2 render knobs ADRIFT — %s of %s checked rows not at their declared value\n' \
        "$DRIFT_TOTAL" "$((N_MATCH + N_DRIFT + N_UNSET + N_NODATA))"
      printf 'Expected until the C10 activation runs: this file DECLARES the state, it never sets it.\n'
      printf 'Largest lever adrift is worth ~0.5-0.9 cores (§11.9(2)); full list + magnitudes:\n'
      printf '  %s\n' "$KEYS"
      # `$(…)` strips trailing newlines, so the final row would otherwise butt against `re-run:`.
      printf 'drifted rows:\n%s\n' "$(printf '%s' "$REPORT" | grep -E '^  (DRIFT|UNSET)' || true)"
      printf 're-run:  %s\n' "$0"
    } > "$PAGE" 2>/dev/null || true
  else
    rm -f "$PAGE" "$PAGE.notified" 2>/dev/null || true
  fi
fi

if [ "$QUIET" != 1 ] && [ "$WANT_JSON" != 1 ]; then
  echo "iterm2-perf-parity — $TS"
  echo "  keys: $KEYS"
  printf '%s' "$REPORT"
  echo "  ---"
  echo "  match=$N_MATCH  drift=$N_DRIFT  unset=$N_UNSET  no-data=$N_NODATA"
  echo "  VERDICT: $VERDICT"
  if [ "$VERDICT" = "DRIFT" ]; then
    echo "  This script is READ-ONLY. Applying these is the operator's activation, not an agent's."
  fi
fi
[ "$WANT_JSON" = 1 ] && printf '%s\n' "$JSON"
exit "$RC"
