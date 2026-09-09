#!/usr/bin/env bats
# idl-record-size.bats — W3-B17. The IDL is an append-only store ~20 producers share, and
# O_APPEND stops being atomic once a record exceeds the writer's stdio buffer (4,096 B here):
# the line goes out as >=2 write() calls and a concurrent producer can land BETWEEN them.
# W2-B17 measured exactly one such splice in the live store plus 8 gz archives -- a 6,679-byte
# backlog-health record from scripts/autonomy-sweep.sh, cut at byte 4096 by a waiting-recycle
# append -- and every census that redirects jq's stderr silently dropped 12.33% of the store
# (24.3% of hook records) while reporting a smaller, internally consistent number with no tell.
# Report: docs/research/exhaustive-drive-2026-09-08/W2-B17-jq-fatal-idl-record.md (1550268e6).
#
# THE INVARIANT THESE CASES PIN: no producer emits a record that can be torn. They are keyed on
# the emitted BYTE COUNT, not on the store staying quiet -- an absence of new fatal lines proves
# nothing at a 1.4% interleave rate (the report's §5 last paragraph).

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  # CC_TEST_SWEEP is the red-proof seam, same contract as tests/autonomy-sweep.bats: these cases
  # are re-run against a PRISTINE tree (`git archive HEAD scripts/ | tar -x`) to prove they FAIL
  # without the change. It has to be the real extracted artifact -- a hand-edited approximation of
  # the old script proves nothing (memory: control-must-replay-the-real-artifact).
  SWEEP="${CC_TEST_SWEEP:-$REPO/scripts/autonomy-sweep.sh}"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude/autonomy"
}

# Emit the named log_idl record with every shell variable stubbed, and print its byte count.
# Reads the emit out of the SUBJECT so it can never drift from what the sweep actually writes.
emit_bytes() { # <disposition>
  python3 - "$SWEEP" "$1" <<'PY' > "$BATS_TEST_TMPDIR/emit.sh"
import re, sys
lines = open(sys.argv[1]).read().split("\n")
want = "log_idl %s " % sys.argv[2]
j = [i for i, l in enumerate(lines) if l.lstrip().startswith(want)][0]
k = j
while not lines[k].rstrip().endswith("}')\""):
    k += 1
block = "\n".join(lines[j:k + 1]).replace('log_idl %s "$(' % sys.argv[2], "", 1)
block = block[:block.rfind(")\"")]
vs = sorted(set(re.findall(r"\$(_[a-z_]+)", block)))
print("#!/bin/bash\n" + "\n".join('%s="0"' % v for v in vs) + "\n" + block + " > \"$1\"")
PY
  bash "$BATS_TEST_TMPDIR/emit.sh" "$BATS_TEST_TMPDIR/extra.json" || return 1
  # The envelope log_idl wraps every extra object in, byte-for-byte as the subject builds it.
  jq -cn --arg ts "2026-09-09T00:00:00Z" --arg disp "$1" \
     --argjson np 0 --argjson na 0 --argjson npf 0 --argjson od 0 \
     --argjson fd 0 --argjson fnc 0 --argjson nha 0 \
     --argjson extra "$(cat "$BATS_TEST_TMPDIR/extra.json")" \
     '{ts:$ts,tool:"autonomy-sweep",disposition:$disp,new_pages:$np,new_alarms:$na,
       new_pushfailed:$npf,open_decisions:$od,fired_defaults:$fd,
       fired_nochange:$fnc,new_handoff_alarms:$nha} + $extra' | wc -c | tr -d ' '
}

@test "the backlog-health record is small enough that its append cannot be torn" {
  run emit_bytes backlog-health
  [ "$status" -eq 0 ]
  n="$output"
  echo "backlog-health record = $n bytes (pre-fix: 6679)" >&3
  # 4096 is the stdio buffer that makes the append non-atomic; 4000 is the writer's refusal
  # threshold. This asserts against the REFUSAL threshold, so a record that would be refused at
  # the writer can never be introduced at a call site and only discovered in production.
  [ "$n" -lt 4000 ]
}

@test "no log_idl emit in the sweep can be torn -- every disposition, not just the measured one" {
  # W2-B17's §6 names "fixed the one record we found" as a wrong reading: the defect is a SIZE
  # CLASS, so the guard has to span every emitter. The next-largest was 663 B when this landed.
  mapfile -t disps < <(grep -o '^log_idl [a-z-]*' "$SWEEP" | awk '{print $2}' | sort -u)
  [ "${#disps[@]}" -ge 5 ]
  for d in "${disps[@]}"; do
    run emit_bytes "$d"
    if [ "$status" -ne 0 ]; then continue; fi   # emits with no inline jq object: nothing to size
    echo "  $d = $output bytes" >&3
    [ "$output" -lt 4000 ]
  done
}

# ── THE WRITER'S OWN REFUSAL ─────────────────────────────────────────────────────────────────────
# The cases above pin ONE producer. These pin the CONTRACT: whatever a caller builds, the writer
# refuses the size class rather than appending a line that cannot go out in one write().

lib() { echo "${CC_TEST_IDLLIB:-$REPO/hooks/lib/idl-log.sh}"; }

@test "the writer appends a record at the threshold" {
  run bash -c '
    . "$1" || exit 9
    rec="$(jq -cn --arg p "$(printf "a%.0s" $(seq 1 3900))" "{ts:\"t\",k:\$p}")"
    idl_guarded_append "$2" testhook testkind "$rec"' _ "$(lib)" "$BATS_TEST_TMPDIR/idl.jsonl"
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$BATS_TEST_TMPDIR/idl.jsonl")" -eq 1 ]
  run jq -r '.disposition // "none"' "$BATS_TEST_TMPDIR/idl.jsonl"
  [ "$output" = "none" ]
}

@test "the writer REFUSES a record over the threshold, and never truncates it" {
  run bash -c '
    . "$1" || exit 9
    rec="$(jq -cn --arg p "$(printf "a%.0s" $(seq 1 5000))" "{ts:\"t\",k:\$p}")"
    idl_guarded_append "$2" testhook testkind "$rec"' _ "$(lib)" "$BATS_TEST_TMPDIR/idl.jsonl"
  [ "$status" -eq 1 ]
  # Exactly one line, and it is the SHORT oversize record -- not a truncated fragment of the
  # original. A truncated JSON line IS the defect this guards; minting one deliberately would be
  # indistinguishable from the splice it exists to prevent.
  [ "$(wc -l < "$BATS_TEST_TMPDIR/idl.jsonl")" -eq 1 ]
  run jq -r '.disposition' "$BATS_TEST_TMPDIR/idl.jsonl"
  [ "$output" = "idl-oversize" ]
  run jq -r '.kind' "$BATS_TEST_TMPDIR/idl.jsonl"
  [ "$output" = "testkind" ]
  # every byte of the store still parses -- the refusal cannot itself be the thing that breaks jq
  run jq -e . "$BATS_TEST_TMPDIR/idl.jsonl"
  [ "$status" -eq 0 ]
  n="$(wc -c < "$BATS_TEST_TMPDIR/idl.jsonl" | tr -d ' ')"
  [ "$n" -lt 400 ]
}

@test "the oversize record names the byte count that was refused" {
  bash -c '
    . "$1" || exit 9
    rec="$(jq -cn --arg p "$(printf "a%.0s" $(seq 1 5000))" "{ts:\"t\",k:\$p}")"
    idl_guarded_append "$2" testhook testkind "$rec"' _ "$(lib)" "$BATS_TEST_TMPDIR/idl.jsonl" || true
  run jq -r '.bytes > 4000' "$BATS_TEST_TMPDIR/idl.jsonl"
  [ "$output" = "true" ]
}

# ── THE TOLERANT-READER RULE, ENFORCED AT THE CHOKEPOINT ─────────────────────────────────────────
# W2-B17's third arm. A SLURP (`jq -s` / `-rs` / `--slurp`) over the IDL fails WHOLESALE on one bad
# record: jq exits 5, and with stderr redirected the caller sees an empty result it cannot
# distinguish from an empty store. That is how 12.33% of the store went missing from every census
# that did it, reporting a smaller, internally consistent number with no tell.
#
# The production readers are ALREADY tolerant and this case does not re-fix them -- bin/cc-audit
# reads `[inputs | fromjson?]` per record and warn_malformed() reports the skipped count,
# scripts/idl-abstain-alarm.sh reads `fromjson? // empty` and reports raw-vs-parsed, and
# scripts/measure-close-vs-idl.py counts idl_parse_failures. What nothing on this box had is
# anything stopping the NEXT one from being written (memory: enforcement-must-live-at-the-
# chokepoint -- a correct reader is detection; the gate is what makes it stick).

@test "no reader slurps the LIVE IDL with jq while suppressing its stderr" {
  cd "$REPO"
  # Candidate lines: a jq slurp flag and an idl path on the same line.
  # Fixture stores are exempt by construction -- a selftest builds its own small IDL and a torn
  # record there would be the test's own doing, not the shared 20-producer append race.
  offenders=""
  while IFS= read -r hit; do
    line="${hit#*:}"; line="${line#*:}"
    case "$line" in
      *'$d/'*|*'$tmp/'*|*'BATS_TEST_TMPDIR'*|*'$TMP'*|*'seed.jsonl'*) continue ;;
    esac
    case "$line" in *'2>/dev/null'*) offenders="$offenders$hit"$'\n' ;; esac
  done < <(grep -rn -e 'jq -rs' -e 'jq -sr' -e 'jq -s ' -e 'jq --slurp' \
             --include='*.sh' --include='cc-*' bin scripts hooks 2>/dev/null \
           | grep -i 'idl' || true)
  if [ -n "$offenders" ]; then
    echo "a slurp over the live IDL with stderr suppressed reads a fatal record as an EMPTY STORE:" >&3
    echo "$offenders" >&3
    echo "use a per-record read instead: jq -Rrn '[inputs | fromjson?]' and REPORT the skipped count" >&3
  fi
  [ -z "$offenders" ]
}
