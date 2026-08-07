#!/bin/bash
# shellcheck disable=SC2015  # file-wide: the selftest's `[ test ] && okp || badp` reporter idiom
# escalation-watch.sh — SessionStart: the GUARANTEED READER for the escalation dead-letter stores (D3).
#
# Why: durable escalation records are written into four stores, and until now NOTHING session-facing
# read them. The push lane (desk role → banner) is liveness-dependent and currently dead — a live
# sweep row reads `"notified":"no-desk-role","delivered":false` while carrying 12 new pages, 12 new
# alarms and 12 stuck completion pushes. With no desk pane the operator can go days blind (F6/F8/F9).
# This hook is the pull lane that cannot be dead: SessionStart fires on every new session regardless
# of roles, panes, banners or network. Advisory only (additionalContext); never blocks; fail-open;
# pure read — it mutates NOTHING, not even a damping marker.
#
# ZERO unseen records ⇒ ZERO output. That is the contract, not an optimisation: a channel that speaks
# at every session start trains the operator to skip it (alarm-polarity law — an alarm that always
# fires carries the same zero bits as one that cannot).
#
# ── UNSEEN, and the two places the frozen design misdescribed its own stores ─────────────────────
# (1) SEEN MARKER. HANDOFF_FAILURE_DETECTION_V2 §FROZEN INTERFACE calls the marker
#     `$SEEN_DIR/<record-basename>.seen` "(existing sweep convention)". It is not. The convention
#     (scripts/autonomy-sweep.sh:89-91) is `sha256(FULL PATH) | cut -c1-32`, with NO suffix — live
#     proof: all 1191 markers in the seen dir are 32-hex, none ends in `.seen`. Reproducing the
#     documented form instead of the real one would render every already-drained record forever
#     (390 live announce-alarms ⇒ a permanent 390-record nag), which is precisely the failure this
#     hook exists to avoid. So SEEN = EITHER form: the sweep's real sha key, OR `<basename>.seen`
#     for whatever `cc-escalations ack` ends up writing. Recognising an extra marker form can only
#     SUPPRESS a line, never manufacture one, so the union is safe in the direction that matters.
# (2) SWEEP LIVENESS. idl.jsonl is a SHARED ledger (waiting-recycle alone holds 9733 rows), so
#     "newest ts in idl.jsonl" measures whether ANY hook ran — it can never go stale while a session
#     is open, and the sweep could be dead for a week reading healthy. Hooks write `"hook":"<name>"`;
#     autonomy-sweep writes `"tool":"autonomy-sweep"` (autonomy-sweep.sh:214-221). This keys on the
#     sweep's own rows only: a ledger with rows but none from the sweep reads "never", not "fresh".
#     A liveness proxy that is not independent of the thing it supplements is not a proxy.
#
# The hash is BATCHED through ONE perl (Digest::SHA, core) — the idiom bin/cc-idl:38 already uses,
# and for the same reason: per-record `shasum` forks measured 10ms each, i.e. ~24s of SessionStart
# stall at live volume. perl absent ⇒ the record scan is REPORTED as not-run, never silently passed.
#
# Env seams: CC_ESCALATION_WATCH=0 (kill switch) · CC_HANDOFF_ALARM_DIR · CC_ANNOUNCE_ALARM_DIR ·
#   CC_COMPLETION_RECORDS_DIR · CC_PAGES_DIR · CC_SWEEP_SEEN_DIR · CC_IDL · CC_EXPIRED_LEDGER ·
#   CC_ESCALATION_SWEEP_MAX_AGE_S (default 900) · CC_ESCALATION_NOW (test clock).
# BSD-first (no GNU `date -d`), bash 3.2-safe, no it2, no network. Selftest: `--selftest`.
set -uo pipefail

ALARM_DIR="${CC_HANDOFF_ALARM_DIR:-$HOME/.claude/handoff-alarms}"
ANNOUNCE_DIR="${CC_ANNOUNCE_ALARM_DIR:-$HOME/.claude/cc-announce-alarms}"
COMPLETION_DIR="${CC_COMPLETION_RECORDS_DIR:-$HOME/.claude/completion-push}"
PAGES_DIR="${CC_PAGES_DIR:-$HOME/.claude/autonomy/pages}"
SEEN_DIR="${CC_SWEEP_SEEN_DIR:-$HOME/.claude/autonomy/sweep-seen}"
IDL="${CC_IDL:-$HOME/.claude/autonomy/idl.jsonl}"
EXPIRED_LEDGER="${CC_EXPIRED_LEDGER:-$HOME/.claude/autonomy/expired-unread.jsonl}"
SWEEP_MAX_AGE_S="${CC_ESCALATION_SWEEP_MAX_AGE_S:-900}"   # 3 missed 300s ticks
JQ="$(command -v jq || true)"
SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
DETAIL_MAX=80

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

emit() { # <context-string> — SessionStart additionalContext, the activation-watch.sh mechanism
  if [ -n "$JQ" ]; then
    "$JQ" -cn --arg c "$1" '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$c}}'
  else
    printf '%s\n' "$1"   # SessionStart also injects plain stdout as context (frontier-status precedent)
  fi
}

# ── candidate list ────────────────────────────────────────────────────────────────────────────────
# Emits `class<TAB>path` for every RECORD FILE, before the seen/verified filters. Bash globs + a
# `[ -f ]` guard: zero forks, and an unmatched glob expands literally, so the guard is load-bearing.
candidates() {
  local f
  for f in "$ALARM_DIR"/*.json;                do [ -f "$f" ] && printf 'handoff-alarm\t%s\n' "$f"; done
  for f in "$ANNOUNCE_DIR"/announce-alarm-*.json;   do [ -f "$f" ] && printf 'announce-alarm\t%s\n' "$f"; done
  # announce-degrade-* are RECORDS of a degraded-but-delivered announce, not alarms — same store,
  # different meaning, so they are counted as their own class rather than folded into the alarms.
  for f in "$ANNOUNCE_DIR"/announce-degrade-*.json; do [ -f "$f" ] && printf 'announce-degrade\t%s\n' "$f"; done
  for f in "$COMPLETION_DIR"/*.json;           do [ -f "$f" ] && printf 'completion-push\t%s\n' "$f"; done
  for f in "$PAGES_DIR"/*.page;                do [ -f "$f" ] && printf 'page\t%s\n' "$f"; done
  # Load-bearing: the last `[ -f ]` is FALSE on an empty board, and under `pipefail` that rc would
  # propagate through the perl pipeline and report a healthy empty board as "the scan DID NOT RUN".
  return 0
}

# ── the ONE batched pass: hash → seen-filter → verified-filter ───────────────────────────────────
# In: `class<TAB>path`. Out: `class<TAB>mtime<TAB>path`, unseen only. One fork for the whole corpus.
unseen_rows() {
  command -v perl >/dev/null 2>&1 || return 1
  candidates | SEEN_DIR="$SEEN_DIR" perl -MDigest::SHA=sha256_hex -ne '
    chomp;
    my ($cls, $path) = split /\t/, $_, 2;
    next unless defined $path && length $path;
    my $seen = $ENV{SEEN_DIR};
    # BOTH marker forms — see header note (1). Either one means drained.
    my $key = substr(sha256_hex($path), 0, 32);
    (my $base = $path) =~ s{.*/}{};
    next if -e "$seen/$key" || -e "$seen/$base.seen";
    if ($cls eq "completion-push") {
      # Only records whose verdict is NOT "verified" are stuck. FRAGILE BY NATURE: these files are
      # pretty-printed multi-line JSON, so the literal carries a space after the colon. Tolerating
      # both spacings costs nothing and cannot over-match — it still only matches the verdict field
      # being exactly "verified", and being STRICT here is the safe direction (a missed "verified"
      # is one noisy line; a false "verified" is the silent loss this hook exists to prevent).
      open(my $fh, "<", $path) or next;
      local $/; my $body = <$fh>; close $fh;
      next if defined $body && $body =~ /"verdict"\s*:\s*"verified"/;
    }
    my $mt = (stat($path))[9];
    $mt = 0 unless defined $mt;
    print "$cls\t$mt\t$path\n";
  ' 2>/dev/null
}

detail_of() { # <path> → first DETAIL_MAX chars of the record's human field, single-line
  local f="${1:-}" d=""
  [ -f "$f" ] || return 0
  if [ -n "$JQ" ]; then
    d="$("$JQ" -r 'if type=="object" then (.detail // .event // .alarm // .class // "") else "" end' "$f" 2>/dev/null || true)"
  fi
  # No jq, or a non-JSON record (a .page file holds a bare epoch): fall back to the raw first line.
  [ -n "$d" ] || d="$(head -1 "$f" 2>/dev/null || true)"
  d="$(printf '%s' "$d" | tr '\n\t' '  ')"
  printf '%s' "${d:0:$DETAIL_MAX}"
}

sweep_liveness() { # → the warn line, or empty when the sweep is fresh
  local row ts age now
  now="$(now_s)"
  # The sweep's OWN rows, never the shared ledger's newest — see header note (2).
  row="$(grep '"tool":"autonomy-sweep"' "$IDL" 2>/dev/null | tail -1 || true)"
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

expired_line() { # → the warn line for records that aged out UNREAD in the last 24h, or empty
  [ -f "$EXPIRED_LEDGER" ] || return 0
  local cut n now
  now="$(now_s)"
  # ISO-8601 UTC sorts lexically = chronologically, so the cutoff is a string compare (one awk).
  cut="$(date -u -r "$(( now - 86400 ))" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || true)"
  [ -n "$cut" ] || return 0
  n="$(awk -v cut="$cut" -F'"ts":"' 'NF>1 { split($2, a, "\""); if (a[1] >= cut) n++ } END { print n+0 }' \
       "$EXPIRED_LEDGER" 2>/dev/null || echo 0)"
  case "$n" in ''|*[!0-9]*) n=0 ;; esac
  [ "$n" -gt 0 ] || return 0
  printf '⚠ %s record(s) expired UNREAD in the last 24h\n' "$n"
}

watch() {
  local rows="" body="" scan_note="" now cls
  now="$(now_s)"

  if rows="$(unseen_rows)"; then :; else
    # An unrunnable check is a FINDING, not a pass (the activation-watch `DID NOT RUN` precedent).
    rows=""
    scan_note='⚠ escalation record scan DID NOT RUN (perl/Digest::SHA unavailable) — record counts below are ABSENT, not zero'
  fi

  # Aggregate per class. One pass per class over the UNSEEN rows only (~tens of lines, not the whole
  # corpus), which keeps this to pure bash with NO eval and no dynamic variable names — the sibling
  # autonomy-sweep.sh declares "no eval" in its own header, and a parallel c_*/n_*/p_* triple read
  # back through `eval` is exactly the shape that makes a static check blind.
  local classes="handoff-alarm announce-alarm announce-degrade completion-push page"
  local total=0 rcls mt path cnt newest npath det line
  while IFS=$'\t' read -r rcls mt path; do
    [ -n "${path:-}" ] && total=$(( total + 1 ))
  done <<EOF
$rows
EOF

  if [ "$total" -gt 0 ]; then
    body='ESCALATIONS (unseen dead-letter records):'
    for cls in $classes; do
      cnt=0; newest=0; npath=""
      while IFS=$'\t' read -r rcls mt path; do
        [ "$rcls" = "$cls" ] && [ -n "${path:-}" ] || continue
        case "${mt:-0}" in ''|*[!0-9]*) mt=0 ;; esac
        cnt=$(( cnt + 1 ))
        [ "$mt" -gt "$newest" ] && { newest="$mt"; npath="$path"; }
      done <<EOF
$rows
EOF
      [ "$cnt" -gt 0 ] || continue
      line="$(printf '· %s: %s (newest %s' "$cls" "$cnt" "$(fmt_age $(( now - newest )))")"
      det="$(detail_of "$npath")"
      [ -n "$det" ] && line="$line; $det"
      body="$body"$'\n'"$line)"
    done
  fi

  # These two are INDEPENDENT of the record count: a dead sweep is itself the alarm, and it is
  # loudest in exactly the state where zero records have been collected.
  local sweep expired
  sweep="$(sweep_liveness)"
  expired="$(expired_line)"
  [ -n "$scan_note" ] && body="${body:+$body$'\n'}$scan_note"
  [ -n "$sweep" ]     && body="${body:+$body$'\n'}${sweep%$'\n'}"
  [ -n "$expired" ]   && body="${body:+$body$'\n'}${expired%$'\n'}"

  [ -n "$body" ] || exit 0
  emit "$body"
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

  mkdir -p "$d/alarms" "$d/announce" "$d/completion" "$d/pages" "$d/seen"
  local NOW=1786100000
  # a fresh sweep row, so the liveness line stays out of the record assertions
  printf '{"ts":"%s","tool":"autonomy-sweep","disposition":"fired"}\n' \
    "$(date -u -r "$(( NOW - 60 ))" +%Y-%m-%dT%H:%M:%SZ)" > "$d/idl.jsonl"

  printf '{"kind":"handoff-alarm","class":"strand-risk","detail":"pane 1FBFCD05 never closed","ts":"x"}\n' > "$d/alarms/alarm-1.json"
  printf '{"kind":"alarm","alarm":"announce-not-verified","detail":"announce to D08B NOT verified"}\n'      > "$d/announce/announce-alarm-1.json"
  printf '{"kind":"alarm","detail":"degraded delivery"}\n'                                                 > "$d/announce/announce-degrade-1.json"
  printf '{\n  "kind": "completion-push",\n  "detail": "stuck push",\n  "verdict": "push-failed(rc=5)"\n}\n' > "$d/completion/push-1.json"
  printf '{\n  "kind": "completion-push",\n  "detail": "fine",\n  "verdict": "verified"\n}\n'                > "$d/completion/push-2.json"
  printf '1785402302\n' > "$d/pages/p-1.page"

  ewrun() { CC_HANDOFF_ALARM_DIR="$d/alarms" CC_ANNOUNCE_ALARM_DIR="$d/announce" \
            CC_COMPLETION_RECORDS_DIR="$d/completion" CC_PAGES_DIR="$d/pages" \
            CC_SWEEP_SEEN_DIR="$d/seen" CC_IDL="$d/idl.jsonl" \
            CC_EXPIRED_LEDGER="$d/expired.jsonl" CC_ESCALATION_NOW="$NOW" "$SELF"; }

  out="$(ewrun)"
  printf '%s' "$out" | grep -q 'handoff-alarm: 1'    && okp "handoff-alarm class rendered"    || badp "handoff-alarm NOT rendered"
  printf '%s' "$out" | grep -q 'announce-alarm: 1'   && okp "announce-alarm class rendered"   || badp "announce-alarm NOT rendered"
  printf '%s' "$out" | grep -q 'announce-degrade: 1' && okp "announce-degrade counted apart"  || badp "announce-degrade NOT separate"
  printf '%s' "$out" | grep -q 'completion-push: 1'  && okp "completion-push: only non-verified counted" || badp "completion-push count wrong"
  printf '%s' "$out" | grep -q 'page: 1'             && okp "page class rendered"             || badp "page NOT rendered"
  printf '%s' "$out" | grep -q 'ESCALATIONS'         && okp "header rendered"                 || badp "no header"
  printf '%s' "$out" | grep -q 'pane 1FBFCD05'       && okp "newest detail carried"           || badp "detail missing"
  if [ -n "$JQ" ]; then
    printf '%s' "$out" | "$JQ" -e '.hookSpecificOutput.hookEventName=="SessionStart"' >/dev/null 2>&1 \
      && okp "output is valid SessionStart additionalContext JSON" || badp "output not valid SessionStart JSON"
  else okp "jq absent — plain-stdout fallback (skipped JSON check)"; fi

  # seen suppression — BOTH marker forms (header note 1)
  local k
  k="$(printf '%s' "$d/alarms/alarm-1.json" | shasum -a 256 | cut -c1-32)"; : > "$d/seen/$k"
  : > "$d/seen/announce-alarm-1.json.seen"
  out="$(ewrun)"
  printf '%s' "$out" | grep -q 'handoff-alarm'  && badp "sha-key marker did not suppress"  || okp "sweep sha-key marker suppresses"
  printf '%s' "$out" | grep -q 'announce-alarm:' && badp ".seen marker did not suppress"   || okp "<basename>.seen marker suppresses"
  rm -f "$d/seen/$k" "$d/seen/announce-alarm-1.json.seen"

  # kill switch
  out="$(CC_ESCALATION_WATCH=0 ewrun)"; rc=$?
  { [ -z "$out" ] && [ "$rc" -eq 0 ]; } && okp "CC_ESCALATION_WATCH=0 → silent, exit 0" || badp "kill switch did not silence"

  # zero records + live sweep → NOTHING AT ALL (the absence-of-noise contract)
  local e="$d/empty"; mkdir -p "$e/alarms" "$e/announce" "$e/completion" "$e/pages" "$e/seen"
  out="$(CC_HANDOFF_ALARM_DIR="$e/alarms" CC_ANNOUNCE_ALARM_DIR="$e/announce" \
         CC_COMPLETION_RECORDS_DIR="$e/completion" CC_PAGES_DIR="$e/pages" \
         CC_SWEEP_SEEN_DIR="$e/seen" CC_IDL="$d/idl.jsonl" CC_EXPIRED_LEDGER="$e/none.jsonl" \
         CC_ESCALATION_NOW="$NOW" "$SELF")"; rc=$?
  { [ -z "$out" ] && [ "$rc" -eq 0 ]; } && okp "zero records + live sweep → EMPTY stdout (control)" || badp "spurious output on a clean board"

  # sweep-stale line — and it must fire with ZERO records, where it is the only signal
  printf '{"ts":"%s","tool":"autonomy-sweep","disposition":"fired"}\n' \
    "$(date -u -r "$(( NOW - 3600 ))" +%Y-%m-%dT%H:%M:%SZ)" > "$d/stale-idl.jsonl"
  out="$(CC_HANDOFF_ALARM_DIR="$e/alarms" CC_ANNOUNCE_ALARM_DIR="$e/announce" \
         CC_COMPLETION_RECORDS_DIR="$e/completion" CC_PAGES_DIR="$e/pages" \
         CC_SWEEP_SEEN_DIR="$e/seen" CC_IDL="$d/stale-idl.jsonl" CC_EXPIRED_LEDGER="$e/none.jsonl" \
         CC_ESCALATION_NOW="$NOW" "$SELF")"
  printf '%s' "$out" | grep -q 'NOT being drained' && okp "stale sweep renders with ZERO records" || badp "stale-sweep line missing"

  # a ledger full of OTHER hooks' rows is NOT sweep liveness (header note 2 — the whole point)
  printf '{"ts":"%s","hook":"waiting-recycle","disposition":"abstained"}\n' \
    "$(date -u -r "$(( NOW - 5 ))" +%Y-%m-%dT%H:%M:%SZ)" > "$d/foreign-idl.jsonl"
  out="$(CC_HANDOFF_ALARM_DIR="$e/alarms" CC_ANNOUNCE_ALARM_DIR="$e/announce" \
         CC_COMPLETION_RECORDS_DIR="$e/completion" CC_PAGES_DIR="$e/pages" \
         CC_SWEEP_SEEN_DIR="$e/seen" CC_IDL="$d/foreign-idl.jsonl" CC_EXPIRED_LEDGER="$e/none.jsonl" \
         CC_ESCALATION_NOW="$NOW" "$SELF")"
  printf '%s' "$out" | grep -q 'NEVER run' && okp "foreign IDL rows do NOT fake sweep liveness" || badp "foreign rows read as a live sweep"

  # expired-unread: last 24h only
  printf '{"ts":"%s","kind":"expired-unread"}\n' "$(date -u -r "$(( NOW - 3600 ))"  +%Y-%m-%dT%H:%M:%SZ)" >  "$d/expired.jsonl"
  printf '{"ts":"%s","kind":"expired-unread"}\n' "$(date -u -r "$(( NOW - 200000 ))" +%Y-%m-%dT%H:%M:%SZ)" >> "$d/expired.jsonl"
  out="$(ewrun)"
  printf '%s' "$out" | grep -q '1 record(s) expired UNREAD' && okp "expired counts the last 24h ONLY" || badp "expired window wrong"

  echo "escalation-watch --selftest: $PASS passed, $FAIL failed"
  [ "$FAIL" -eq 0 ] || exit 1
  echo "escalation-watch --selftest: GREEN — 5 classes · verified-filter · both seen forms · kill switch · empty-board control · stale sweep · foreign-row control · expired window."
}

case "${1:-}" in
  --selftest) selftest ;;
  *)          watch ;;
esac
