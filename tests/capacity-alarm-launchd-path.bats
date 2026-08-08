#!/usr/bin/env bats
# The launchd wrapper OVERWRITES PATH, so every binary capacity-alarm.sh invokes must be reachable
# on the plist's own PATH string — not on an interactive shell's PATH.
#
# WHY THIS SUITE EXISTS (measured 2026-07-30, not hypothetical). The wrapper's PATH omitted
# /usr/sbin, where `sysctl` lives. launchd's own default PATH includes /usr/sbin, but the wrapper
# replaces it. Result: in every SCHEDULED run — never in a hand-run from a terminal, which is
# exactly why it survived review — three rungs failed open:
#     rung 1 swap · rung 3 kernel pressure · rung 5 compressor segments
# The 17:25:59Z scheduled row read pressure_level=null, seg_pct=null, swap_used_mb=0. That last one
# is the dangerous shape: `${SWAP_MB:-0}` renders an unreadable instrument as the HEALTHY value.
# A dead rung that reports OK is worse than no rung (memory feature-durability-mechanism-not-memory).
#
# This suite is the recurrence guard for the CLASS, not just for sysctl: it extracts the binaries
# the script actually calls and checks each against the plist's literal PATH.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude/logs"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  PLIST="$REPO/launchd/com.claude.capacity-alarm.plist"
  SCRIPT="$REPO/scripts/capacity-alarm.sh"
}

# The literal PATH the job will run with, taken from the plist rather than restated here — a copy
# in the test could drift from the plist and pass while production is broken.
plist_path() {
  /usr/libexec/PlistBuddy -c 'Print :ProgramArguments:2' "$PLIST" 2>/dev/null \
    | sed -n 's/.*export PATH="\([^"]*\)".*/\1/p'
}

@test "the plist exposes a parseable PATH override" {
  run plist_path
  [ "$status" -eq 0 ]
  [ -n "$output" ]
}

@test "every binary capacity-alarm.sh invokes is reachable on the plist PATH" {
  local p; p="$(plist_path)"
  [ -n "$p" ] || { echo "could not parse PATH from plist"; false; }
  local missing=""
  # HOME is expanded by the wrapper's shell at runtime; expand it here the same way.
  p="${p//\$HOME/$HOME}"
  # `tr` joined 2026-08-05 with rung 7 — it was already invoked (the pressure and segment-page reads
  # pipe through it) and already absent from this list, which is the drift an ENUMERATED list always
  # accumulates while its docstring claims to extract what the script "actually calls".
  for bin in sysctl zprint vm_stat ps python3 top awk sed tr; do
    if ! env -i PATH="$p" HOME="$HOME" bash -c "command -v $bin" >/dev/null 2>&1; then
      missing="$missing $bin"
    fi
  done
  [ -z "$missing" ] || { echo "UNREACHABLE on the launchd PATH:$missing"; echo "PATH=$p"; false; }
}

@test "RED CONTROL: the pre-fix PATH (no /usr/sbin) really does hide sysctl" {
  # If this control ever passes, the environment changed and the suite above proves nothing —
  # a control that cannot fail is not a control.
  run env -i PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin" bash -c 'command -v sysctl'
  [ "$status" -ne 0 ]
}

@test "the sysctl-backed rungs go SKIPPED, never healthy, when sysctl is genuinely unreadable" {
  # Prove the failure MODE, so a regression is loud rather than a silent green: SEG_PCT must be
  # empty (=> rung 5 skipped) rather than a fabricated 0.
  #
  # THE INVARIANT IS UNCHANGED; ITS MECHANISM MOVED (2026-08-08, backlog 2c1388d063bf). Until then
  # this test made sysctl unreadable by stripping /usr/sbin from PATH — a PROXY for unreadability
  # that was only ever valid while the rung resolved by bare name. Now that read_segments resolves
  # absolutely (the whole point: the plist's PATH is a fact about another file and has been wrong
  # before), the proxy no longer induces the state, and a test asserting REFUSED on a PATH strip
  # would be asserting that the fix did not happen. So the unreadable state is induced through the
  # seam, which is strictly better: it holds for ANY resolution strategy, including the next one.
  # (The first attempt to convert these sites, e6de2e15, left this test alone; it went red and the
  # post-land verifier auto-reverted three unrelated fixes along with it.)
  run env -i PATH="/usr/bin:/bin" HOME="$HOME" bash -c '
    '"$(sed -n '/^read_segments() {/,/^}/p' "$SCRIPT")"'
    SYSCTL=/nonexistent/sysctl
    read_segments && echo "RETURNED-A-VALUE" || echo "REFUSED"'
  [ "$output" = "REFUSED" ]
}

@test "rung 5: read_segments ANSWERS with /usr/sbin off the PATH — the property the proxy stood for" {
  # The positive half, and the one the old PATH-strip test could never assert. It pins what the strip
  # was really a proxy for: this rung does not depend on the plist carrying /usr/sbin. Both halves
  # are needed — REFUSED-when-unreadable above without this one is satisfied by a rung that never
  # answers at all, which is precisely the silent death the suite exists to catch.
  run env -i PATH="/usr/bin:/bin" HOME="$HOME" bash -c '
    '"$(sed -n '/^read_segments() {/,/^}/p' "$SCRIPT")"'
    read_segments >/dev/null && echo OK || echo REFUSED'
  [ "$output" = "OK" ]
}

@test "the SHIPPED script fills swap and pressure with /usr/sbin off the PATH (end-to-end)" {
  # The two above pin the mechanism on one extracted function; this pins that the shipped code path
  # actually CHOOSES it, for the rungs that die most quietly. `swap_used_mb` is the dangerous shape
  # named in this file's header — ${SWAP_MB:-0} renders a dead instrument as the HEALTHY value — so
  # assert it is neither null nor absent, on the PATH where it used to be exactly that.
  run env -i PATH="/usr/bin:/bin" HOME="$HOME" /bin/bash "$SCRIPT" --json --no-append
  [[ "$output" == *'"swap_used_mb":'* ]] || false
  [[ "$output" != *'"swap_used_mb":null'* ]] || false
  [[ "$output" == *'"seg_pct":'* ]] || false
  [[ "$output" != *'"seg_pct":null'* ]]
}

@test "sysctl is reachable on the CURRENT plist PATH (the actual fix)" {
  local p; p="$(plist_path)"; p="${p//\$HOME/$HOME}"
  run env -i PATH="$p" HOME="$HOME" bash -c 'command -v sysctl'
  [ "$status" -eq 0 ]
}

# ── CADENCE (2026-07-31) ──────────────────────────────────────────────────────────────────────
# The interval is a load-bearing part of the instrument, and it lives in a DIFFERENT file from the
# reasoning that justifies it — the exact shape in which a number silently regresses. At 600 s this
# sensor could not resolve the panic it exists to catch (healthy sample -> dead inside one interval,
# last row 20m23s stale). Pin it, in a form that says WHY, so a future "600 is cheaper" edit has to
# argue with a red test rather than with a comment nobody reads.
@test "cadence: StartInterval is 60s — 600s could not resolve the 2026-07-31 panic" {
  local iv
  iv="$(/usr/libexec/PlistBuddy -c 'Print :StartInterval' "$PLIST" 2>/dev/null)"
  [ "$iv" = "60" ]
}

# A faster sampler writes 10x the rows, so the rotation target is not a nicety here — it is the
# other half of the cadence change. Unrotated + 640 KB/day is how idl.jsonl reached 183 MB.
@test "cadence: the 60s sampler's log is a rotation target (the exhaust ships with the rate)" {
  grep -q 'logs/capacity-alarm\.jsonl' "$REPO/scripts/rotate-autonomy-logs.sh"
}

# The plist and the script must not disagree about the cadence. The script's header states 60s and
# derives its warning-margin claim from it; if someone edits one and not the other, the surviving
# number is a lie in whichever file kept it.
@test "cadence: the script header and the plist agree on 60s" {
  grep -qE 'interval is now 60 s' "$REPO/scripts/capacity-alarm.sh"
}

# ── RUNG 7 IS PATH-INDEPENDENT BY CONSTRUCTION (D4, 2026-08-05) ──────────────────────────────────
# Everything above proves one thing several ways: the plist's PATH string currently carries
# /usr/sbin, so the bare-name `sysctl` sites resolve. That is a property of a STRING IN ANOTHER FILE,
# it has already been false once, and three rungs died silently for the whole time it was. Rung 7
# does not depend on it — it resolves /usr/sbin/sysctl directly. These tests are the difference
# between "the plist happens to be right today" and "this rung cannot be broken by editing it".
#
# The class is neither hypothetical nor historical. It is failing RIGHT NOW one file over: every
# capacity-gate row in ~/.claude/logs/handoffs.jsonl reads `hw.ncpu unreadable ('') — load term not
# evaluated`, which is this exact sysctl, resolved by bare name, from a hook context.
@test "rung 7: an ABSOLUTE sysctl reads load with /usr/sbin off the PATH — the launchd shape" {
  run env -i PATH="/usr/bin:/bin" HOME="$HOME" bash -c '
    '"$(sed -n '/^read_load() {/,/^}/p' "$SCRIPT")"'
    SYSCTL=/usr/sbin/sysctl
    read_load >/dev/null && echo OK || echo REFUSED'
  [ "$output" = "OK" ]
}

@test "RED CONTROL: the SAME read by BARE NAME really does fail on that PATH" {
  # If this ever passes, /usr/sbin joined the minimal PATH and the test above proves nothing — a
  # control that cannot fail is not a control (the pre-fix-PATH control above is the same idea).
  run env -i PATH="/usr/bin:/bin" HOME="$HOME" bash -c '
    '"$(sed -n '/^read_load() {/,/^}/p' "$SCRIPT")"'
    SYSCTL=sysctl
    read_load >/dev/null && echo OK || echo REFUSED'
  [ "$output" = "REFUSED" ]
}

@test "rung 7: the SHIPPED script fills load_per_core with /usr/sbin off the PATH (end-to-end)" {
  # The two above pin the mechanism; this pins that the script actually CHOOSES it. An absolute-path
  # default is only worth having if the shipped code path takes it — and a rung that silently reads
  # SKIPPED in every scheduled run is indistinguishable from a rung that was never added.
  run env -i PATH="/usr/bin:/bin" HOME="$HOME" /bin/bash "$SCRIPT" --json --no-append
  [[ "$output" == *'"load_per_core":'* ]] || false
  [[ "$output" != *'"load_per_core":null'* ]] || false
  [[ "$output" != *'"ncpu":null'* ]]
}
