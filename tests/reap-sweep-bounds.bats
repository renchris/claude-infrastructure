#!/usr/bin/env bats
# reap-sweep-bounds.bats — R5 / A10 (SESSION_REGISTRY_V2 §4.3.1): every external fork in the sweep is
# bounded, and the two foreign calls that do not feed the decision run AFTER it.
#
# Measured before this change: `grep -c 'timeout ' bin/cc-reaper` = 0. Three foreign binaries ran
# synchronously and unbounded between the sweep's start and the evidence — one of them cc-inbox-guard,
# the exact binary whose unbounded fork caused the 5-day gate blockage. Sweep p99 was 2,099s against a
# 300s StartInterval.
#
# DISCRIMINATOR = a MARKER FILE, never wall-clock. Each wedged stub sleeps, then writes a marker. If
# the bound fired the stub was killed mid-sleep and the marker is ABSENT; unbounded, it is PRESENT.
# A timing assertion would be flaky on a box whose reaper runs in the Darwin background QoS band
# (ProcessType Background + Nice 5, com.chrisren.cc-reaper.plist) where wall time is taxed severalfold.
#
# Every bound test is DIFFERENTIAL — it pins the bounded arm AND the unbounded arm. Asserting only
# "the sweep finished" is vacuous: it passes on a tree with no bounds at all whenever the stub is fast.
# The unbounded arm is reached via CC_REAPER_TIMEOUT_BIN= (set-but-empty), the documented disable seam,
# which is also what a box with no timeout(1) installed degrades to.
#
# Assertion style: `[ ]` throughout — a non-final `[[ ]]`/`(( ))` is errexit-EXEMPT under bats and so a
# DEAD assertion (memory: bats-dead-assertions-errexit-exemptions).
#
# NO fixture may background a job (`&`): a bats fixture's background child prints a spurious `not ok`
# beside the `ok` for a body that PASSED, and the landing gate greps `not ok`
# (memory: bats-background-job-fabricates-not-ok). Every stub here sleeps in the FOREGROUND, as a child
# of the sweep, which is precisely what timeout(1) is being asked to kill.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  R="$REPO/bin/cc-reaper"
  D="$BATS_TEST_TMPDIR"; mkdir -p "$D/bin"
  # Fixture $HOME first — an unfixtured sweep resolves the beat/registry dirs under the operator's
  # live ~/ and could read (or act on) a REAL pane. Hermeticity is also a landing-gate ratchet.
  export HOME="$D/home"; mkdir -p "$HOME/.claude"

  # …AND FIXTURE THE PROCESS TABLE, which $HOME does not reach. Every test below runs a real
  # `sweep --reap`, and the sweep's FIRST arm is garbage_sweep: unpinned, it forks two live
  # `/bin/ps -Ax` and issues real TERM/KILL to whatever the host happens to be running. That is not
  # a hypothetical — it is the measured cause of backlog 8efd655b0fe1: on a GitHub Actions macOS
  # runner the service is a launchd-parented `/bin/bash .../runsvc.sh`, the classifier's
  # `orphan-bash` shape selects it, and this suite killed the runner out from under its own job in
  # 6 of 6 cut shards, costing ~43 suites of evidence each. cc-reaper now refuses to signal an
  # ancestor of its own sweep, which is the invariant; this pin is the other half, because a suite
  # that tests classify/checkpoint/teardown BOUNDS has no business reading the live process table
  # at all. /dev/null is the spelling tests/cc-reaper.bats:98 already uses for the same reason: an
  # empty snapshot makes the arm skip fail-open before either ps fork.
  export CC_REAPER_GARBAGE_PS_A=/dev/null CC_REAPER_GARBAGE_PS_B=/dev/null

  # A landed, idle, reapable candidate — so a sweep that is NOT blocked reaches teardown. Anything
  # this suite observes short of that is attributable to a bound and nothing else.
  mkdir -p "$D/clean"; git -C "$D/clean" init -q
  git -C "$D/clean" config user.email t@t; git -C "$D/clean" config user.name t
  echo a > "$D/clean/f"; git -C "$D/clean" add f; git -C "$D/clean" commit -qm c1
  git -C "$D/clean" update-ref refs/remotes/origin/main HEAD

  cat > "$D/bin/teardown" <<EOF
#!/bin/bash
echo "TD" >> "$D/order"
exit 0
EOF
  cat > "$D/bin/checkpoint" <<'EOF'
#!/bin/bash
cat > /dev/null
EOF
  # STAMP TENANCY (2026-07-24 rule 2): the finished-teammate belt reaps only a pane whose CURRENT
  # session booted within CC_FIRED_BOOT_MAX_S of the fire — so firedAt and startedAt must both be
  # anchored to NOW, not to a fixed literal. A hardcoded past date makes the stamp read `none`, the
  # belt refuses, and every test below would silently measure a refusal instead of a bound.
  NOW_S="$(date +%s)"
  # BSD renders an epoch with `date -r`; GNU reads `-r` as a REFERENCE FILE and needs `-d @<epoch>`.
  # BSD first — GNU's failure on a bare number is clean ("No such file or directory"), so the
  # operator's box never evaluates the second arm. MEASURED 2026-08-31 (BACKLOG_DRAIN_24_7 off-box
  # cause census): with only the BSD arm this is empty on Linux, and because it runs in `setup` it
  # took ALL 14 cases of this suite down with `fixture broken`, on pristine trunk.
  FIRED_ISO="$(date -u -r "$NOW_S" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u -d "@$NOW_S" '+%Y-%m-%dT%H:%M:%SZ')"
  STARTED_MS="$(( NOW_S * 1000 ))"

  # Fast (healthy) classify: one reapable candidate.
  cat > "$D/bin/classify" <<EOF
#!/bin/bash
echo "CLASSIFY" >> "$D/order"
cat <<'JSON'
[{"cause":"finished-teammate","name":"w1","paneUUID":"2BE82E97-1111-4222-8333-444455556666","cwd":"CWD","idle_s":9999,
  "work_landed":"yes","session_id":"s1","pid":1,"lstart":"x","startedAt":STARTED}]
JSON
EOF
  # `sed -i ''` is the BSD spelling — BSD REQUIRES a backup suffix and takes `''` as "none", while
  # GNU takes the same `''` as the next FILENAME and dies `sed: can't read : No such file or
  # directory`, status 2. `-i.bak` is the one spelling both accept. MEASURED 2026-08-31
  # (BACKLOG_DRAIN_24_7 off-box cause census): this line is in `setup`, so it took all 14 cases of
  # this suite down on pristine trunk, and it did so BEHIND the `date -u -r` fault above — two
  # dialects in one setup, the second invisible until the first was cured.
  sed -i.bak -e "s#CWD#$D/clean#" -e "s#STARTED#$STARTED_MS#" "$D/bin/classify"
  rm -f "$D/bin/classify.bak"
  chmod +x "$D/bin/teardown" "$D/bin/checkpoint" "$D/bin/classify"

  export CC_REAPER_TEARDOWN_BIN="$D/bin/teardown"
  export CC_REAPER_CHECKPOINT_BIN="$D/bin/checkpoint"
  export CC_REAPER_CLASSIFY_BIN="$D/bin/classify"
  export CC_REAPER_SETTLE_S=100
  export CC_REAPER_TRUNK=origin/main
  export CC_REAPER_LOG="$D/reaper.log"
  export CC_REAPER_LOCKDIR="$D/sweep.lock.d"
  # ── HERMETIC GARBAGE ARM — the residue of backlog a3a070520f3d, which 46a57a1d fixed in
  # tests/cc-reaper.bats ONLY. Same defect, same binary, different suite, and it survived the fix
  # because that one was filed against a single file: the audit was never widened to the other
  # callers of `sweep`. This suite is the whole remainder — it and cc-reaper.bats are the only two
  # in tests/ that run the real `"$R" sweep`.
  # sweep() calls garbage_sweep "$reap" FIRST (bin/cc-reaper:814), so each of the 9
  # `run "$R" sweep --reap` cases below ran the DESTRUCTIVE arm. Unset, its snapshot seams take the
  # `else` leg at bin/cc-reaper:318-320 and exec the LIVE `/bin/ps -Ax` table; every ppid-1 process
  # matching :344-349 is then TERMed, and -KILLed 3 s later. `orphan-bash` is any ppid-1 bash older
  # than 600 s whose argv misses the :339 whitelist, and `bats` is not on it. This suite is NOT in
  # scripts/host-suites.manifest, so the postland corpus runs it — the tree verifier signalling live
  # processes as a side effect of verifying the tree, on the box that also runs the operator's
  # sessions. CC_REAPER_LOG above is redirected into $D, so nothing on the machine records who did
  # it; that blindness is what let the same shape survive twice.
  # Nothing here asserts on the garbage arm, so pinning it is inert to what this suite measures:
  # these tests discriminate on BOUNDS (reconcile/inbox-guard/classify/backlog marker files).
  # /dev/null is the documented fail-open seam (`snapshot unavailable — arm skipped`,
  # bin/cc-reaper:321), so INERT becomes the default here as it is there.
  export CC_REAPER_GARBAGE_PS_A=/dev/null CC_REAPER_GARBAGE_PS_B=/dev/null
  # Pinned too, though the fail-open return at :321 precedes the watchdog loop today: that loop
  # `kill -0`s real pids and can add real victims, and rule 5 of the hermeticity lint disclaims a
  # $HOME-rooted default as rule 1's business — so the fixtured $HOME above is not a defence to rely on.
  mkdir -p "$D/gs-wd"; export CC_REAPER_WATCHDOG_DIR="$D/gs-wd"
  # The fired-peer stamp the finished-teammate cause requires at act time.
  export CC_FIRED_DIR="$D/fired"; mkdir -p "$D/fired"
  printf '{"firedAt":"%s"}' "$FIRED_ISO" > "$D/fired/2BE82E97-1111-4222-8333-444455556666.json"
  # No desk target ⇒ no paging; no ps stub needed beyond a live count of 1.
  export CC_REAPER_NOTIFY_BIN="/usr/bin/true"
}

# Build a stub that sleeps past its bound and only THEN writes its marker. Presence of the marker is
# the whole discriminator: bound fired ⇒ killed mid-sleep ⇒ no marker.
mkwedge() { # <path> <marker> <label>
  cat > "$1" <<EOF
#!/bin/bash
echo "$3" >> "$D/order"
sleep 8
touch "$2"
EOF
  chmod +x "$1"
}

@test "R5/A10: cc-reaper contains timeout bounds at all (the acceptance grep that read 0)" {
  run grep -c 'timeout ' "$REPO/bin/cc-reaper"
  [ "$status" -eq 0 ]
  [ "$output" -gt 0 ]
}

@test "HERMETICITY: every sweep here skips the garbage arm — this suite never reads the live process table" {
  # The pin in setup() is only worth having if its removal is LOUD. Unpinned, the sweep's first arm
  # forks two live `/bin/ps -Ax` and TERMs whatever the host is running under a launchd parent —
  # which is how this suite killed the GitHub Actions runner service in 6 of 6 cut shards
  # (backlog 8efd655b0fe1). Asserted on the arm's own log line rather than on the absence of a
  # kill, because absence is exactly what a fixture that reaches nothing also produces.
  run "$R" sweep --reap
  run grep -c 'garbage: snapshot unavailable' "$D/reaper.log"
  [ "$output" -ge 1 ] || { echo "the garbage arm ran against the LIVE process table: $(grep garbage "$D/reaper.log")" >&2; return 1; }
}

@test "every foreign invocation in the sweep goes through the bounded helper (none left bare)" {
  # The chokepoint check: a bound that covers three of four calls leaves the fourth as the wedge.
  run grep -c '_rp_bounded ' "$REPO/bin/cc-reaper"
  [ "$status" -eq 0 ]
  [ "$output" -ge 4 ]
}

@test "DIFFERENTIAL: a wedged cc-reconcile is KILLED by its bound — and unbounded it runs to completion" {
  mkwedge "$D/bin/reconcile" "$D/reconcile-finished" "RECONCILE"
  export CC_REAPER_RECONCILE_BIN="$D/bin/reconcile"
  export CC_REAPER_RECONCILE_TIMEOUT_S=2

  run "$R" sweep --reap
  [ ! -e "$D/reconcile-finished" ]                       # bound fired: stub died mid-sleep
  run grep -c 'bound-fired reconcile' "$D/reaper.log"    # and said so — a silent bound hides an inert one
  [ "$output" -ge 1 ]

  # UNBOUNDED ARM — without timeout(1) the identical stub runs to completion. This is what proves the
  # arm above is attributable to the bound rather than to a stub that never ran.
  rm -f "$D/reaper.log" "$D/order"
  CC_REAPER_TIMEOUT_BIN='' run "$R" sweep --reap
  [ -e "$D/reconcile-finished" ]
}

@test "DIFFERENTIAL: a wedged cc-backlog is KILLED by its bound — and unbounded it runs to completion" {
  mkwedge "$D/bin/backlog" "$D/backlog-finished" "BACKLOG"
  export CC_REAPER_BACKLOG_BIN="$D/bin/backlog"
  export CC_REAPER_BACKLOG_TIMEOUT_S=2

  run "$R" sweep --reap
  [ ! -e "$D/backlog-finished" ]
  run grep -c 'bound-fired backlog-reap' "$D/reaper.log"
  [ "$output" -ge 1 ]

  rm -f "$D/reaper.log" "$D/order"
  CC_REAPER_TIMEOUT_BIN='' run "$R" sweep --reap
  [ -e "$D/backlog-finished" ]
}

@test "DIFFERENTIAL: a wedged cc-inbox-guard is KILLED by its bound — and unbounded it runs to completion" {
  # The 5-day-gate-blockage binary. Its unbounded fork is the concrete incident R5 exists to prevent.
  mkwedge "$D/bin/guard" "$D/guard-finished" "GUARD"
  export CC_REAPER_GUARD_BIN="$D/bin/guard"
  export CC_REAPER_GUARD_TIMEOUT_S=2

  run "$R" sweep --reap
  [ ! -e "$D/guard-finished" ]
  run grep -c 'bound-fired inbox-guard' "$D/reaper.log"
  [ "$output" -ge 1 ]

  rm -f "$D/reaper.log" "$D/order"
  CC_REAPER_TIMEOUT_BIN='' run "$R" sweep --reap
  [ -e "$D/guard-finished" ]
}

@test "a wedged foreign binary does NOT stop the sweep from reaping (bounded ⇒ degrade, never block)" {
  # The point of the bound is not merely to kill the stub — it is that the DECISION still happens.
  # Unbounded, this same sweep would sit in the fork instead of reaching teardown.
  mkwedge "$D/bin/reconcile" "$D/reconcile-finished" "RECONCILE"
  export CC_REAPER_RECONCILE_BIN="$D/bin/reconcile"
  export CC_REAPER_RECONCILE_TIMEOUT_S=2
  run "$R" sweep --reap
  run grep -c '^TD$' "$D/order"
  [ "$output" -ge 1 ]
}

@test "FAIL-CLOSED: a wedged cc-classify yields NO candidates — a bounded evidence producer never half-reaps" {
  # If the thing that PRODUCES the verdict wedges, there is no verdict. The failure direction must be
  # "reap nothing", never "reap on a partial candidate set".
  cat > "$D/bin/classify-slow" <<EOF
#!/bin/bash
sleep 8
echo '[{"cause":"finished-teammate","name":"w1","paneUUID":"2BE82E97-1111-4222-8333-444455556666","cwd":"$D/clean","idle_s":9999,"work_landed":"yes","session_id":"s1"}]'
EOF
  chmod +x "$D/bin/classify-slow"
  export CC_REAPER_CLASSIFY_BIN="$D/bin/classify-slow"
  export CC_REAPER_CLASSIFY_TIMEOUT_S=2

  run "$R" sweep --reap
  [ ! -e "$D/order" ]                                    # teardown never called
  run grep -c 'bound-fired classify' "$D/reaper.log"
  [ "$output" -ge 1 ]
  run grep -c 'sweep end: 0 classified' "$D/reaper.log"  # empty set, not a partial one
  [ "$output" -ge 1 ]
}

@test "ORDERING: the two non-decision foreign calls run AFTER the reap, not between evidence and act" {
  # cc-backlog and cc-inbox-guard feed no part of the reap decision, yet ran BEFORE classify — putting
  # two unbounded forks between the sweep's start and the evidence. They still ride the cadence; they
  # may no longer delay a decision or the act that follows it.
  printf '#!/bin/bash\necho BACKLOG >> "%s"\n' "$D/order" > "$D/bin/backlog"
  printf '#!/bin/bash\necho GUARD >> "%s"\n'   "$D/order" > "$D/bin/guard"
  chmod +x "$D/bin/backlog" "$D/bin/guard"
  export CC_REAPER_BACKLOG_BIN="$D/bin/backlog"
  export CC_REAPER_GUARD_BIN="$D/bin/guard"

  run "$R" sweep --reap
  [ -e "$D/order" ]
  # Expected sequence: CLASSIFY … TD … BACKLOG, GUARD
  run bash -c "grep -n '^TD\$'      '$D/order' | head -1 | cut -d: -f1"
  td="$output"
  run bash -c "grep -n '^BACKLOG\$' '$D/order' | head -1 | cut -d: -f1"
  bk="$output"
  run bash -c "grep -n '^GUARD\$'   '$D/order' | head -1 | cut -d: -f1"
  gd="$output"
  [ -n "$td" ]; [ -n "$bk" ]; [ -n "$gd" ]
  [ "$td" -lt "$bk" ]
  [ "$td" -lt "$gd" ]
}

@test "A8: decided_age is measured from CLASSIFY, and sweep_age is logged beside it (neither hidden)" {
  # decided_age previously started at sweep_t0 — before classify ran — so it charged the decision→act
  # gap for foreign work that finished before the evidence existed. Both spans are now emitted, so the
  # narrower number can never be read as the wider one having improved.
  run grep -c 'decided_age=\${decided_age}s sweep_age=\${sweep_age}s' "$REPO/bin/cc-reaper"
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]
  run grep -c 'decided_age=$(( decided_at - classify_t0 ))' "$REPO/bin/cc-reaper"
  [ "$output" -ge 1 ]
}

@test "the suspend guard still reads sweep_t0 (changing the A8 span must not move the sleep detector)" {
  # Gap-3 detects a machine sleep DURING the sweep via intra = now_act - sweep_t0. Re-anchoring
  # decided_age to classify_t0 must leave that detector on its original, wider span.
  run grep -c 'intra=$(( now_act - sweep_t0 ))' "$REPO/bin/cc-reaper"
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]
}

@test "SIZING: the inbox-guard bound clears the measured background-band cost of a HEALTHY sweep" {
  # A bound BELOW a healthy run is a permanent non-verdict — the exact failure the R5 SIZING note
  # in bin/cc-reaper forbids by name ("it fires on healthy work and proves nothing"), and the
  # reason this suite's own header refuses to assert wall-clock. The rule was written; the
  # constant was never re-derived against a run in the band launchd actually gives this job.
  #
  # MEASURED 2026-08-25 (recycle #219), isolated 872-box mailbox copy, non-dry, BOTH arms emitting
  # the identical 362 escalations — one input moved, the scheduling band:
  #     foreground                     PRI 31 (6/6 samples)     38s
  #     taskpolicy -c background       PRI  4 (12/48 samples)  249s   <- ProcessType Background
  # PRI 4 is unreachable without taskpolicy (nice alone leaves 31), so the arm demonstrably moved.
  # At 60s the bound fired on 1,564 of 1,646 logged sweeps (95.0%), and 82-100% on every one of
  # 12 days INCLUDING the quietest, while reconcile/backlog-reap/classify swung 0-100% with load.
  #
  # This is a FLOOR over EVERY site, not an equality pin: a later re-derivation may raise the
  # bound, and a partial edit that lowers any one site back under the measured healthy cost must
  # red. Deliberately well under the shipped 600 so honest re-tuning is not tripwired.
  total="$(grep -cE 'CC_REAPER_GUARD_TIMEOUT_S:-[0-9]+' "$REPO/bin/cc-reaper")"
  [ "$total" -ge 2 ]
  # strip THROUGH the ':-' — 's/.*://' leaves the '-' and yields a negative, which reds on a
  # perfectly good constant (caught by this very assertion on its first run).
  low="$(grep -oE 'CC_REAPER_GUARD_TIMEOUT_S:-[0-9]+' "$REPO/bin/cc-reaper" | sed 's/.*:-//' | sort -n | head -1)"
  [ -n "$low" ]
  [ "$low" -ge 300 ]
}

@test "SIZING: the backlog-reap bound clears the measured background-band cost of a HEALTHY reap" {
  # THE SIBLING OF THE TEST ABOVE, and it exists because that test's own change ACQUITTED this
  # bound in the same breath. The R5 SIZING note recorded "backlog-reap 42.9% ... tracking load,
  # i.e. behaving like detectors" — a 12-day AGGREGATE, while the conviction beside it was a
  # PER-DAY series. Re-derived per day (2026-08-25, recycle #223; predicate: fires / (fires +
  # completions), both patterns POS-controlled against the same log), backlog-reap does not track
  # load: 6.7% on 08-15 climbing monotonically to 100.0% on 08-25 — 76 fires and ZERO completions.
  #
  # MEASURED, live 14.4k-line ledger copied to a mktemp store with BOTH write seams redirected
  # (CC_BACKLOG_FILE + CC_BACKLOG_IDL); the live ledger's sha256 was byte-identical before and
  # after, so isolation is proven by content, not asserted. Non-dry, both arms clearing the
  # IDENTICAL 11 rows and writing 12 verdict rows — one input moved, the scheduling band:
  #     foreground                     PRI 31 (32/32 samples)     96s
  #     taskpolicy -c background       PRI  4 (78/78 samples)    617s   <- ProcessType Background
  # PRI 4 is unreachable without taskpolicy (nice alone leaves 31), so the arm demonstrably moved.
  # The READ-ONLY half is 18s foreground / 41s in-band, so 68% of a 60s budget went before the
  # first write: in this band the reap affords ZERO writes inside 60s.
  #
  # WHAT THE OLD BOUND COST: cmd_reap runs the off-box cure sweep LAST, so the cut always lands
  # there. Eleven blocked rows were all adjudicated curable by the sweep's own dry run (7 STALLED
  # 7-20h, 4 LANDED with content on origin/main) while the newest COMPLETED cure sweep in the log
  # was 23.5h old — three have ever completed, against 732 bound-fires.
  #
  # A FLOOR over EVERY site, not an equality pin — a later re-derivation may raise the shipped
  # value, and a partial edit that drops any one site back under the measured healthy cost must
  # red. 700 clears the 617s healthy run with margin and sits well under the shipped 900, so
  # honest re-tuning is not tripwired.
  total="$(grep -cE 'CC_REAPER_BACKLOG_TIMEOUT_S:-[0-9]+' "$REPO/bin/cc-reaper")"
  [ "$total" -ge 2 ]
  # strip THROUGH the ':-' — 's/.*://' leaves the '-' and yields a negative, which reds on a
  # perfectly good constant (the scar the sibling test above records).
  low="$(grep -oE 'CC_REAPER_BACKLOG_TIMEOUT_S:-[0-9]+' "$REPO/bin/cc-reaper" | sed 's/.*:-//' | sort -n | head -1)"
  [ -n "$low" ]
  [ "$low" -ge 700 ]
}

@test "the backlog-reap bound message does not attribute the cut to the claim sweep alone" {
  # ATTRIBUTION, not detection: the failure was already visible — 732 log lines said so — and every
  # one of them named "claim-ledger sweep INCOMPLETE". cmd_reap is claim sweep THEN cure sweep, so
  # the stage actually truncated is systematically the LAST one, and the log named the stage that
  # had usually already finished. An operator reading those lines learns the wrong subsystem.
  run grep -c 'bound-fired backlog-reap: exceeded' "$REPO/bin/cc-reaper"
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]

  # ASSERT ON THE EMITTING LINE, NOT ON THE FILE. The retired phrase deliberately survives in the
  # comment that documents why it was retired, so a file-wide `grep -c ... -eq 0` reds on its own
  # documentation (memory: a token can survive its own fix as data — grep the CODE LINE). This
  # assertion caught exactly that on its first run.
  #
  # POSITIVE CONTROL FIRST, through the SAME pattern prefix: if `log "bound-fired backlog-reap.*`
  # could not match at all, the zero below would be vacuous rather than a verdict.
  run grep -c 'log "bound-fired backlog-reap.*reap INCOMPLETE this cadence' "$REPO/bin/cc-reaper"
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]
  # ...and only now is the absence meaningful: no EMITTED message still blames the claim ledger.
  [ "$(grep -c 'log "bound-fired backlog-reap.*claim-ledger sweep INCOMPLETE' "$REPO/bin/cc-reaper")" -eq 0 ]

  # and the replacement must NAME the cure sweep as the stage the bound cuts first
  run grep -c 'cure sweep, which runs LAST' "$REPO/bin/cc-reaper"
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]
}
