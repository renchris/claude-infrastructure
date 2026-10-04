#!/bin/bash
# shellcheck disable=SC2015  # file-wide: the selftest's `[ test ] && okp || badp` reporter idiom
# escalation-watch.sh — SessionStart: the HEALTH check on the escalation pipeline (D3).
#
# Durable escalation records land in six stores (handoff alarms, announce alarms and degrades,
# completion pushes, pages, M3 mail dead letters). The operator's COUNT of unseen records is the
# Stop readout's `◆ N escalation record(s) unseen` line (hooks/operator-readout.sh,
# escalation_unseen_count), which reads all six. This hook no longer repeats that count. It reports
# only the two conditions under which that count is WRONG while looking fine:
#
#   • the sweep is dead — autonomy-sweep has never run, or last ran more than SWEEP_MAX_AGE_S ago,
#     so records are not being drained or paged;
#   • the scan cannot run — perl/Digest::SHA is unavailable, in which case the Stop readout's
#     counter prints 0 for a board it never read.
#
# Healthy ⇒ ZERO output. That is the contract, not an optimisation: a channel that speaks at every
# session start trains the operator to skip it (alarm-polarity law).
#
# ── WHY THE PER-CLASS BLOCK IS GONE (2026-10-04) ─────────────────────────────────────────────────
# Until then this hook rendered a per-class block (`· announce-alarm: 1345 (newest 24m; …)`) as
# `additionalContext`. Measured over 7 days: 0 of ~720 sessions acted on it; Claude Code hides that
# attachment in the TUI, so the operator never saw it either; and records arrive at ~124/day against
# ~103 session starts/day, so the block changed at nearly every start and no damper could quiet it.
# The health lines now go out as a top-level `systemMessage` — rendered in the operator's terminal
# at 0 model tokens (hooks/accounts-board.sh header has the channel proof).
#
# ── SWEEP LIVENESS keys on the sweep's OWN rows ──────────────────────────────────────────────────
# idl.jsonl is a SHARED ledger (waiting-recycle alone holds 9733 rows), so "newest ts in idl.jsonl"
# measures whether ANY hook ran — it can never go stale while a session is open, and the sweep could
# be dead for a week reading healthy. Hooks write `"hook":"<name>"`; autonomy-sweep writes
# `"tool":"autonomy-sweep"` (autonomy-sweep.sh:214-221). This keys on the sweep's own rows only: a
# ledger with rows but none from the sweep reads "never", not "fresh". A liveness proxy that is not
# independent of the thing it supplements is not a proxy.
#
# Advisory only; never blocks; fail-open; pure read — it mutates NOTHING.
# Env seams: CC_ESCALATION_WATCH=0 (kill switch) · CC_IDL · CC_ESCALATION_SWEEP_MAX_AGE_S (default
#   900) · CC_ESCALATION_NOW (test clock) · CC_ESCALATION_PERL (the perl the scan check runs).
# BSD-first (no GNU `date -d`), bash 3.2-safe, no it2, no network. Selftest: `--selftest`.
set -uo pipefail

IDL="${CC_IDL:-$HOME/.claude/autonomy/idl.jsonl}"
SWEEP_MAX_AGE_S="${CC_ESCALATION_SWEEP_MAX_AGE_S:-900}"   # 3 missed 300s ticks
JQ="$(command -v jq || true)"
SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
PERL="${CC_ESCALATION_PERL:-perl}"

[ "${CC_ESCALATION_WATCH:-1}" = 0 ] && exit 0

now_s() { printf '%s\n' "${CC_ESCALATION_NOW:-$(date -u +%s)}"; }

iso_to_epoch() { # <iso-utc> → epoch, or empty. BSD date: -j -f, never GNU -d.
  [ -n "${1:-}" ] || return 0
  date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$1" +%s 2>/dev/null || true
}

fmt_age() { # <seconds> → "3m" / "2h 5m" / "4d" — pure arithmetic, no forks
  local s="${1:-0}" d h m
  [ "$s" -lt 0 ] && s=0
  d=$(( s / 86400 )); h=$(( (s % 86400) / 3600 )); m=$(( (s % 3600) / 60 ))
  if   [ "$d" -gt 0 ]; then printf '%sd %sh' "$d" "$h"
  elif [ "$h" -gt 0 ]; then printf '%sh %sm' "$h" "$m"
  else                      printf '%sm' "$m"; fi
}

emit() { # <message> — top-level systemMessage: the operator's terminal, never model context
  if [ -n "$JQ" ]; then
    # shellcheck disable=SC2016  # $c is a jq variable bound by --arg, not a shell expansion
    "$JQ" -cn --arg c "$1" '{systemMessage:$c}'
  else
    # No plain-stdout fallback: SessionStart injects bare stdout as model context, the channel this
    # hook left. Without jq, python3 encodes it; without either, stay silent (fail-open).
    CC_MSG="$1" python3 -c 'import json,os;print(json.dumps({"systemMessage":os.environ["CC_MSG"]}))' 2>/dev/null || true
  fi
}

scan_health() { # → the warn line when the record scan cannot run, or empty
  # The same capability the Stop readout's counter needs: one perl with Digest::SHA. Checked by
  # RUNNING it — `command -v perl` passes on a perl whose core module is missing.
  "$PERL" -MDigest::SHA=sha256_hex -e 1 >/dev/null 2>&1 && return 0
  printf '⚠ escalation record scan DID NOT RUN (perl/Digest::SHA unavailable) — the unseen-record count in the Stop readout is ABSENT, not zero\n'
}

sweep_liveness() { # → the warn line, or empty when the sweep is fresh
  local row ts age now
  now="$(now_s)"
  # The sweep's OWN rows, never the shared ledger's newest — see header note (2).
  # Tail window first: the ledger is ~17 MB and a full grep of it was ~0.45s of every session start,
  # while the newest sweep row sits a few hundred lines from the end (1 MB ≈ 3,900 rows ≈ hours of
  # ledger against a 300s sweep). The window's first line is dropped because it is cut mid-row; a
  # window with no sweep row (a small file, or a sweep dead for a long time) falls back to the full
  # scan, so the answer is the same either way. `LC_ALL=C grep -F`: BSD grep under a UTF-8 locale
  # is ~8x slower on this input, and a literal ASCII pattern cannot match differently byte-wise.
  row="$(tail -c 1048576 "$IDL" 2>/dev/null | tail -n +2 | LC_ALL=C grep -F '"tool":"autonomy-sweep"' | tail -1 || true)"
  [ -n "$row" ] || row="$(LC_ALL=C grep -F '"tool":"autonomy-sweep"' "$IDL" 2>/dev/null | tail -1 || true)"
  if [ -n "$row" ]; then
    ts="${row#*\"ts\":\"}"; ts="${ts%%\"*}"
    ts="$(iso_to_epoch "$ts")"
  else
    ts=""
  fi
  if [ -z "$ts" ]; then
    printf '⚠ autonomy-sweep has NEVER run (no row in %s) — escalation records are NOT being drained\n' "$IDL"
    return 0
  fi
  age=$(( now - ts ))
  [ "$age" -lt "$SWEEP_MAX_AGE_S" ] && return 0
  printf '⚠ autonomy-sweep last ran %s ago — escalation records are NOT being drained\n' "$(fmt_age "$age")"
}

watch() {
  # INDEPENDENT of any record count: a dead sweep is itself the alarm, and it is loudest in exactly
  # the state where zero records have been collected.
  local body="" scan sweep
  scan="$(scan_health)"
  sweep="$(sweep_liveness)"
  [ -n "$scan" ]  && body="${scan%$'\n'}"
  [ -n "$sweep" ] && body="${body:+$body$'\n'}${sweep%$'\n'}"
  [ -n "$body" ] || exit 0
  emit "ESCALATION PIPELINE: $body"
  exit 0
}

# ════ selftest ═══════════════════════════════════════════════════════════════════════════════════
PASS=0; FAIL=0
# shellcheck disable=SC2317
okp()  { printf '  ok   %-58s\n' "$1"; PASS=$((PASS+1)); }
# shellcheck disable=SC2317
badp() { printf '  FAIL %-58s\n' "$1"; FAIL=$((FAIL+1)); }
# shellcheck disable=SC2317
selftest() {
  local d out rc; d="$(mktemp -d "${TMPDIR:-/tmp}/escalation-watch-selftest.XXXXXX")" || { echo mktemp; exit 1; }
  # shellcheck disable=SC2064
  trap "rm -rf '$d'" EXIT
  echo "escalation-watch --selftest:"

  local NOW=1786100000
  row() { printf '{"ts":"%s","%s":"%s","disposition":"fired"}\n' "$(date -u -r "$(( NOW - $1 ))" +%Y-%m-%dT%H:%M:%SZ)" "$2" "$3"; }
  ewrun() { CC_IDL="$1" CC_ESCALATION_NOW="$NOW" "$SELF"; }

  # healthy: a fresh sweep row + a working scan → NOTHING AT ALL (the absence-of-noise contract)
  row 60 tool autonomy-sweep > "$d/idl.jsonl"
  out="$(ewrun "$d/idl.jsonl")"; rc=$?
  { [ -z "$out" ] && [ "$rc" -eq 0 ]; } && okp "fresh sweep + working scan → EMPTY stdout (control)" || badp "spurious output on a healthy pipeline"

  # stale sweep
  row 3600 tool autonomy-sweep > "$d/stale-idl.jsonl"
  out="$(ewrun "$d/stale-idl.jsonl")"
  printf '%s' "$out" | grep -q 'last ran 1h 0m ago' && okp "stale sweep names its age" || badp "stale-sweep line missing"
  printf '%s' "$out" | grep -q 'NOT being drained' && okp "stale sweep says what it costs" || badp "stale-sweep consequence missing"
  if [ -n "$JQ" ]; then
    printf '%s' "$out" | "$JQ" -e '(.systemMessage | length > 0) and (has("hookSpecificOutput") | not)' >/dev/null 2>&1 \
      && okp "output is ONE top-level systemMessage, no model context" || badp "output is not a bare systemMessage"
  else okp "jq absent — python3 encoder path (skipped JSON check)"; fi

  # never ran: absent ledger, and a ledger full of OTHER hooks' rows (the header's whole point)
  out="$(ewrun "$d/absent.jsonl")"
  printf '%s' "$out" | grep -q 'NEVER run' && okp "absent ledger reads NEVER-RAN, not fresh" || badp "absent ledger read as healthy"
  row 5 hook waiting-recycle > "$d/foreign-idl.jsonl"
  out="$(ewrun "$d/foreign-idl.jsonl")"
  printf '%s' "$out" | grep -q 'NEVER run' && okp "foreign IDL rows do NOT fake sweep liveness" || badp "foreign rows read as a live sweep"

  # scan cannot run — with a FRESH sweep, so the line is attributable to the scan alone
  printf '#!/bin/bash\nexit 2\n' > "$d/noperl"; chmod +x "$d/noperl"
  out="$(CC_ESCALATION_PERL="$d/noperl" ewrun "$d/idl.jsonl")"
  printf '%s' "$out" | grep -q 'scan DID NOT RUN' && okp "an unrunnable scan is REPORTED, not a pass" || badp "unrunnable scan silently passed"
  printf '%s' "$out" | grep -q 'NOT being drained' && badp "scan line dragged a sweep line in with it" || okp "scan line stands alone on a live sweep"

  # the record block is gone: no class name, no count, whatever the stores hold
  out="$(ewrun "$d/stale-idl.jsonl")"
  printf '%s' "$out" | grep -Eq 'ESCALATIONS \(unseen|announce-alarm|expired UNREAD' && badp "a per-class or expired line is still rendered" || okp "no per-class counts, no expired line"

  # kill switch
  out="$(CC_ESCALATION_WATCH=0 ewrun "$d/stale-idl.jsonl")"; rc=$?
  { [ -z "$out" ] && [ "$rc" -eq 0 ]; } && okp "CC_ESCALATION_WATCH=0 → silent, exit 0" || badp "kill switch did not silence"

  echo "escalation-watch --selftest: $PASS passed, $FAIL failed"
  [ "$FAIL" -eq 0 ] || exit 1
  echo "escalation-watch --selftest: GREEN — healthy-silent control · stale sweep · never-ran · foreign-row control · unrunnable scan · no record block · kill switch · bare systemMessage."
}

case "${1:-}" in
  --selftest) selftest ;;
  *)          watch ;;
esac
