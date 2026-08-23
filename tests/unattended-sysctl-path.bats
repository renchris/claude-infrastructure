#!/usr/bin/env bats
# The loadavg instrument in postland-verify.sh and qos-census.sh must be readable in a SCHEDULED
# run, not just from a terminal.
#
# WHY THIS SUITE EXISTS (measured 2026-08-06, item ff544977e4ea — not hypothetical). Both jobs are
# launchd wrappers that EXPORT a PATH ending `/usr/bin:/bin`. `sysctl` lives in /usr/sbin, which is
# absent from both. Neither script resolved it absolutely, so the bare name worked from a shell and
# did not exist for the daemon — the failure mode that survives review by construction. Measured on
# this machine's own artifacts at the time of the fix:
#     postland stamps      34 of 80  carried "load":"0"      ← renders unreadable AS AN IDLE BOX
#     qos-census rows     859 of 867 carried loadavg1 "?"    ← the contention instrument, blind
# `${l:-0}` is the dangerous half: a dead instrument reporting the HEALTHY value is worse than no
# instrument (same shape as the swap rung in tests/capacity-alarm-launchd-path.bats, and as
# 752024be's capacity gate, whose load term had never once evaluated).
#
# WHY SCRIPT-SIDE AND NOT A PLIST PATH EDIT — this suite pins the choice so it is not silently
# reverted. Adding /usr/sbin to the two plists would fix only the launchd caller, and it would
# break launchd-parity-lint assertion (c) (live `plutil -p` vs repo SSOT; the live files are real
# copies, not symlinks) for every session in the fleet until the operator ran a bootout+bootstrap.
# Absolute resolution in the script needs no reload, covers every caller, and is the precedent this
# repo already set for this exact class: e6de2e15, 752024be, 9ac045cb.
#
# SCOPE NOTE — the sibling call sites in these files were ALREADY correct when this landed and are
# asserted here only so a regression in them cannot hide behind a green suite:
#     qos-census.sh          /usr/sbin/taskpolicy first  (pre-existing)
#     team-orphan-reaper.sh  /usr/sbin/lsof first        (9ac045cb, 2026-07-26)
#
# THE TWO qos-census CASES ASKED A QUESTION THEY NEVER MEANT TO ASK (item 6a82c9405b9e, fixed
# 2026-08-23). They invoke the real qos-census.sh to read ONE FIELD out of its JSON — and took its
# exit code as a health signal by omission, because a bare `out="$(...)"` under bats' errexit aborts
# the test on any non-zero rc. But that rc is a VERDICT ABOUT THE BOX (0 PASS / 1 FAIL / 3 NO-BURST /
# 4 SIGNAL-DEAD), so the cases were coupled to the machine's contention level and asserted nothing
# about PATH. The census emitted 429 bytes of correct JSON carrying loadavg1=21.55 and exited 3.
#
# THE FILED CAUSE WAS BACKWARDS, and this is the part worth keeping. The item read "fail when
# sibling suites run concurrently … >=2 runs in flight => PASS/FAIL, not NO-BURST". Measured
# standalone with nothing else in flight, both cases failed `with status 3` — NO-BURST. Concurrency
# was the only thing that could ever have made them pass, since rc 0 requires a burst AND coverage
# above threshold. A test that needs the box to be BUSY to go green is not flaky, it is inverted.
# The sibling suite already had it right and says so out loud: tests/qos-chokepoint.bats case (vii),
# "census reports NO-BURST (rc 3), not a pass, when nothing is in flight", via `run`.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude/logs"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  QOS="$REPO/scripts/qos-census.sh"
  PLV="$REPO/scripts/postland-verify.sh"
  # The literal PATH each job runs with, taken FROM THE PLIST rather than restated here — a copy in
  # the test could drift from the plist and pass while production is broken.
  QOS_PATH="$(plist_path "$REPO/launchd/com.claude.qos-census.plist")"
  PLV_PATH="$(plist_path "$REPO/launchd/com.claude.postland-verify.plist")"
}

plist_path() {
  /usr/libexec/PlistBuddy -c 'Print :ProgramArguments:2' "$1" 2>/dev/null \
    | sed -n 's/.*export PATH="\([^"]*\)".*/\1/p'
}

# qos-census.sh exits a VERDICT ABOUT THE LIVE BOX, not a statement about whether it produced
# output (scripts/qos-census.sh:15-21): 0 PASS · 1 FAIL · 3 NO-BURST · 4 SIGNAL-DEAD. This suite
# asks only whether the loadavg1 FIELD is readable on the launchd PATH, so every one of those four
# is a legitimate run — but 2 (usage error) and 127 (not found) are genuine breaks and must still
# fail. Widening this to "any rc" would let the two cases below go green on a census that never ran.
verdict_rc_ok() { case "$1" in 0|1|3|4) return 0 ;; *) return 1 ;; esac; }

# ── the controls come first: if these ever pass, everything below proves nothing ─────────────────

@test "RED CONTROL: both plists really do omit /usr/sbin, so a bare sysctl is genuinely hidden" {
  [ -n "$QOS_PATH" ] || { echo "could not parse PATH from the qos-census plist"; false; }
  [ -n "$PLV_PATH" ] || { echo "could not parse PATH from the postland-verify plist"; false; }
  local p
  for p in "$QOS_PATH" "$PLV_PATH"; do
    p="${p//\$HOME/$HOME}"
    # If this ever resolves, the plist gained /usr/sbin and the suite below is vacuous.
    run env -i PATH="$p" HOME="$HOME" bash -c 'command -v sysctl'
    [ "$status" -ne 0 ] || { echo "sysctl IS reachable on: $p — this suite no longer discriminates"; false; }
  done
}

@test "RED CONTROL: the pre-fix bare-name form really fails on that PATH (mutant from the real file)" {
  # Derived FROM THE SHIPPING FILE, not hand-written: a hand-made approximation can pass vacuously.
  # The mutant restores exactly what the fix replaced — a bare `sysctl -n vm.loadavg`.
  local p="${QOS_PATH//\$HOME/$HOME}" out
  out="$(env -i PATH="$p" HOME="$HOME" bash -c 'sysctl -n vm.loadavg 2>/dev/null | awk "{print \$2}"')"
  [ -z "$out" ] || { echo "bare sysctl returned [$out] on the launchd PATH — the defect is not reproducible here"; false; }
  # ...and the absolute form, on the same PATH, does answer. Both halves, or this proves nothing.
  out="$(env -i PATH="$p" HOME="$HOME" bash -c '/usr/sbin/sysctl -n vm.loadavg 2>/dev/null | awk "{print \$2}"')"
  [ -n "$out" ] || skip "/usr/sbin/sysctl does not answer on this host — nothing to assert"
}

# ── qos-census: end-to-end, the real script, on the real plist PATH ──────────────────────────────

@test "qos-census reads a NUMERIC loadavg1 on its own launchd PATH" {
  local p="${QOS_PATH//\$HOME/$HOME}" out load rc=0
  # --no-append: never touch the operator's live census log from a test.
  # The `|| rc=$?` is load-bearing, not defensive tidying: an UNGUARDED assignment here coupled this
  # case to the box's contention level, because errexit aborts the test on any non-zero rc and the
  # quiet-box verdict is NO-BURST (3). Measured 2026-08-23, standalone with no sibling suite in
  # flight: `failed with status 3`. The rc is judged explicitly below instead.
  out="$(env -i PATH="$p" HOME="$HOME" bash "$QOS" --json --no-append 2>/dev/null)" || rc=$?
  verdict_rc_ok "$rc" || { echo "qos-census exited $rc, which is not one of its four verdicts"; false; }
  [ -n "$out" ] || { echo "qos-census produced no output on PATH=$p"; false; }
  load="$(printf '%s' "$out" | sed -n 's/.*"loadavg1":"\([^"]*\)".*/\1/p')"
  echo "loadavg1=[$load]"
  [ -n "$load" ] || { echo "no loadavg1 field in: $out"; false; }
  [ "$load" != "?" ] || { echo "loadavg1 is still the unreadable placeholder on the launchd PATH"; false; }
  # A number, not merely non-empty — "?" is not the only way this can be a non-value.
  case "$load" in ''|*[!0-9.]*) echo "loadavg1=[$load] is not numeric"; false ;; esac
}

@test "qos-census renders '?' — never a number — when sysctl is genuinely unreachable" {
  # The seam is set-but-EMPTY, which is honored verbatim; this is the ONLY way to reach the
  # unreadable branch on a host where /usr/sbin/sysctl exists. Without it this direction is untested
  # and the fallback could rot into rendering 0 again.
  local p="${QOS_PATH//\$HOME/$HOME}" out load rc=0
  # Guarded for the same reason as the case above — see verdict_rc_ok().
  out="$(env -i PATH="$p" HOME="$HOME" QOS_CENSUS_SYSCTL= bash "$QOS" --json --no-append 2>/dev/null)" || rc=$?
  verdict_rc_ok "$rc" || { echo "qos-census exited $rc, which is not one of its four verdicts"; false; }
  [ -n "$out" ] || { echo "qos-census produced no output with the probe disabled"; false; }
  load="$(printf '%s' "$out" | sed -n 's/.*"loadavg1":"\([^"]*\)".*/\1/p')"
  echo "loadavg1=[$load]"
  [ "$load" = "?" ] || { echo "unreadable sysctl rendered [$load]; must be '?', never a number"; false; }
}

@test "CONTROL: the verdict allowance accepts qos-census's four verdicts and REJECTS anything else" {
  # The two cases above stop failing on a quiet box because they no longer treat qos-census's rc as
  # a health signal. That relaxation has a too-weak direction, and this is the half that proves it
  # did not happen: if verdict_rc_ok were widened to "any rc", both cases would go green on a census
  # that was never found (127) or was mis-invoked (2), asserting nothing at all.
  local rc
  for rc in 0 1 3 4; do
    verdict_rc_ok "$rc" || { echo "rc $rc is a documented qos-census verdict and must be ACCEPTED"; false; }
  done
  for rc in 2 5 126 127; do
    if verdict_rc_ok "$rc"; then echo "rc $rc is NOT a verdict and must be REJECTED"; false; fi
  done
  # The four accepted codes are read off the script's own header, not restated from memory — if that
  # contract is edited, this must be edited with it.
  # -E, and the `$` matters more than the alternation. In a BSD BRE, `$` is an anchor ONLY at the
  # very end of the whole expression; in any earlier branch it is a LITERAL dollar sign. So
  # `grep -c 'Exit 3\.$\|Exit 0\.$\|Exit 1\.$\|Exit 4\.$'` reads 1, identical to `grep -c 'Exit
  # 4\.$'` alone — the first three branches match nothing, which is how this assertion first went
  # red. (Alternation itself is fine: dropping every `$` reads 4. Verified 2026-08-23 on BSD grep
  # 2.6.0-FreeBSD; a pattern containing a literal `Exit 3.$` IS matched by the BRE form.)
  local n; n="$(grep -cE 'Exit [0134]\.$' "$QOS")"
  [ "$n" -eq 4 ] || { echo "qos-census documents $n verdict exits, not 4 — verdict_rc_ok is stale"; false; }
}

# ── postland-verify: the resolution block + load1(), replayed from the shipping file ─────────────

# Extract the REAL block rather than restating it. The anchor is asserted to match exactly once, so
# a rename or a second copy fails loudly instead of silently testing nothing.
plv_block() {
  sed -n '/^# ── PATH-INDEPENDENT sysctl(8) (item ff544977e4ea/,/^}$/p' "$PLV"
}

@test "postland-verify's sysctl resolution block is findable exactly once" {
  local n; n="$(grep -c '^# ── PATH-INDEPENDENT sysctl(8) (item ff544977e4ea' "$PLV")"
  [ "$n" -eq 1 ] || { echo "anchor matched $n times — the extraction below is unreliable"; false; }
  local blk; blk="$(plv_block)"
  [ -n "$blk" ] || { echo "extracted an empty block"; false; }
  printf '%s' "$blk" | grep -q 'load1()' || { echo "block does not contain load1(); extraction is wrong:"; echo "$blk"; false; }
}

@test "postland-verify resolves sysctl absolutely and load1 answers on its own launchd PATH" {
  local p="${PLV_PATH//\$HOME/$HOME}" inc="$BATS_TEST_TMPDIR/blk.sh"
  plv_block > "$inc"
  run env -i PATH="$p" HOME="$HOME" bash -c "source '$inc'; printf '%s|%s' \"\$SYSCTL_BIN\" \"\$(load1)\""
  [ "$status" -eq 0 ] || { echo "sourcing the block failed: $output"; false; }
  echo "resolved|load = $output"
  local bin="${output%%|*}" load="${output#*|}"
  [ "$bin" = "/usr/sbin/sysctl" ] || { echo "resolved [$bin], expected /usr/sbin/sysctl"; false; }
  [ -n "$load" ] || { echo "load1 was empty on the launchd PATH — the instrument is still blind"; false; }
  case "$load" in ''|*[!0-9.]*) echo "load1=[$load] is not numeric"; false ;; esac
}

@test "postland-verify's seam honors set-but-EMPTY verbatim (the probe can be turned OFF)" {
  # A seam that cannot disable the thing is not a seam, and the unreadable branch would be untestable.
  local p="${PLV_PATH//\$HOME/$HOME}" inc="$BATS_TEST_TMPDIR/blk.sh"
  plv_block > "$inc"
  run env -i PATH="$p" HOME="$HOME" CC_POSTLAND_SYSCTL_BIN= bash -c "source '$inc'; printf '[%s][%s]' \"\$SYSCTL_BIN\" \"\$(load1)\""
  [ "$status" -eq 0 ] || { echo "sourcing the block failed: $output"; false; }
  [ "$output" = "[][]" ] || { echo "expected both empty with the probe disabled, got $output"; false; }
}

@test "an unreadable load is stamped '?' and never '0' in either postland record" {
  # The whole point of the item: `${l:-0}` made a dead instrument read as an idle machine. Assert on
  # the RENDERING defaults in the shipping file, both sites (the stamp and the flake row).
  run grep -n 'load":"%s"' "$PLV"
  [ "$status" -eq 0 ]
  grep -q '"${l:-?}"' "$PLV" || { echo "env_fingerprint no longer defaults load to '?'"; false; }
  grep -q '"${load:-?}"' "$PLV" || { echo "record_flake no longer defaults loadavg to '?'"; false; }
  # The exact pre-fix defaults must be gone, not merely joined by the new ones.
  ! grep -q '"${l:-0}"' "$PLV" || { echo "the '0' default survives in env_fingerprint"; false; }
  ! grep -q '"${load:-0}"' "$PLV" || { echo "the '0' default survives in record_flake"; false; }
}

# ── the class guard: no /usr/sbin binary may be re-introduced by bare name in these files ────────

@test "CLASS: every sysctl/lsof/taskpolicy call word in these scripts is absolute or a variable" {
  # Not a re-implementation of unattended-path-lint — a tight, file-scoped assertion that the three
  # /usr/sbin binaries these scripts use are never invoked by bare name in COMMAND position.
  # `command -v <name>` is a lookup, not an invocation, and is the sanctioned fallback rung.
  local f bad="" hits
  for f in "$PLV" "$QOS" "$REPO/scripts/team-orphan-reaper.sh"; do
    # command position = start of line / after ( { | & ; or $( — excluding `command -v` lookups.
    hits="$(grep -nE '(^|[;&|(){]|\$\()[[:space:]]*(sysctl|lsof|taskpolicy)[[:space:]]' "$f" \
            | grep -vE 'command -v' || true)"
    [ -z "$hits" ] || bad="$bad
$(basename "$f"):
$hits"
  done
  [ -z "$bad" ] || { echo "bare-name /usr/sbin invocation(s) in command position:$bad"; false; }
}
