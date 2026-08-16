#!/usr/bin/env bats
# cc-reaper — RED-proof the disposition: a reap needs cause∈{handed-off-lead,finished-teammate} AND
# work-landed AND idle>=settle AND --reap; checkpoint runs BEFORE teardown; a post-classify dirty tree
# aborts the reap (WIP checkpointed); every never-reap cause is left untouched. Mocks classify/teardown/
# checkpoint; uses REAL temp git repos so the work-landed re-check is exercised for real.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  R="$REPO/bin/cc-reaper"
  D="$BATS_TEST_TMPDIR"; mkdir -p "$D/bin"
  # FIXTURE $HOME — must come before anything that runs the sweep. This suite read the operator's
  # LIVE ~/ until 2026-07-31, which was harmless only while nothing under $HOME fed a decision. The
  # SESSION_REGISTRY_V2 beat re-take changed that: cc-reaper now resolves ~/.claude/cc-beats, so the
  # suite saw the operator's real beats, cb_system_live returned TRUE, and every fixture sid — which
  # of course has no beat — took the R3 fail-closed path and was REFUSED. 17 of 81 tests went red on
  # trunk, all of them `td_called`, with no defect in the subject at all. A suite that reads live
  # $HOME does not test the program, it tests the box.
  export HOME="$D/home"; mkdir -p "$HOME/.claude"
  # non-$HOME seams (hermeticity ratchet): these default to ABSOLUTE /tmp paths, which a
  # fixtured $HOME cannot redirect — an absent path is right, the sensors fail open on it.
  export CC_PERMPEND_DIR="$D/permpend" CC_TELEMETRY_DIR="$D/telemetry"
  # BEAT-FAMILY seams — the OVERRIDE half of the leak fixed above, and the half a fixtured $HOME
  # cannot reach. `cb_beat_dir` reads "${CC_BEAT_DIR:-$HOME/.claude/cc-beats}": the $HOME path is
  # only the FALLBACK, so an ambient CC_BEAT_DIR wins outright and reinstates the 2026-07-31
  # incident verbatim — cb_system_live TRUE, every fixture sid beat-less, R3 fail-closed, teardown
  # never invoked. Measured 2026-08-09 on this very tree: exporting CC_BEAT_DIR at a live beat dir
  # takes the suite to 64-ok/17-FAIL, 15 of them at `td_called`, the other 2 at worktree_cleanup.
  # That is what backlog 7d71a3467e61 reported as a "trunk red"; trunk was green the whole time.
  #
  # Why $HOME alone could never have covered it, and why the lint did not catch it either:
  # test-hermeticity-lint.sh RULE 1 asks only "does setup() fixture $HOME?" (yes → hermetic), while
  # RULE 5, which owns non-$HOME seams, explicitly skips any seam whose default mentions $HOME
  # ("a $HOME-rooted default is RULE 1's business"). A `${VAR:-$HOME/…}` seam is therefore claimed
  # by rule 1 and disclaimed by rule 5, and rule 1's remedy does not actually defend it. Neither
  # rule covers the shape. Pin the variable itself; a $HOME default is not a defence.
  export CC_BEAT_DIR="$D/cc-beats"          # absent by default → cb_system_live FALSE → v1 legs
  export CC_BEAT_LIVE_MAX_S=900             # the liveness window is the DEFAULT, not the box's
  export CC_REAP_BEAT_RETAKE=on             # never let an ambient `off` silently disarm R3
  unset CC_BEAT_NOW                         # the beat clock is real time here, not a pinned one
  # real git repos: clean+shipped (landed) and dirty (not landed)
  # `git -C ""` is a NO-OP, not an error — an empty <dir> would write this identity into the cwd repo.
  mkrepo() { local r="${1:?mkrepo: repo path required}"; mkdir -p "$r"; git -C "$r" init -q; git -C "$r" config user.email t@t; git -C "$r" config user.name t
             echo a > "$r/f"; git -C "$r" add f; git -C "$r" commit -qm c1
             git -C "$r" update-ref refs/remotes/origin/main HEAD; }
  # squash-landed: clean tree, HEAD 1 ahead by COUNT, but content already on origin/main (different sha)
  mksquashland() { local r="${1:?mksquashland: repo path required}"; mkdir -p "$r"; git -C "$r" init -q
             git -C "$r" config user.email t@t; git -C "$r" config user.name t
             echo base > "$r/f"; git -C "$r" add f; git -C "$r" commit -qm base
             echo feature >> "$r/f"; git -C "$r" add f; git -C "$r" commit -qm landed
             git -C "$r" update-ref refs/remotes/origin/main HEAD
             git -C "$r" reset -q --hard HEAD~1; echo feature >> "$r/f"; git -C "$r" add f
             GIT_AUTHOR_DATE="@1000000500" GIT_COMMITTER_DATE="@1000000500" git -C "$r" commit -qm featureX; }
  mkrepo "$D/clean"
  mkrepo "$D/dirty"; echo change >> "$D/dirty/f"      # dirty tree (TRACKED modification)
  mksquashland "$D/squash"                             # clean + content-landed but count>0 ahead
  # UNTRACKED-ONLY litter: tracked tree clean + landed, but a stray file nobody committed. This is
  # the shared-checkout reality (a live sibling's scratch output) that used to read "dirty" forever.
  mkrepo "$D/untracked"; echo litter > "$D/untracked/stray-scratch.md"
  # AHEAD: clean tree but 1 genuinely-unlanded commit (content NOT on trunk) → never reapable.
  mkrepo "$D/ahead"; echo more >> "$D/ahead/f"; git -C "$D/ahead" commit -aqm unlanded
  # mock teardown: record argv + ordering; rc from TEARDOWN_RC
  cat > "$D/bin/teardown" <<EOF
#!/bin/bash
echo "TD \$*" >> "$D/order"
printf '%s\n' "\$*" >> "$D/td-calls"
exit \${TEARDOWN_RC:-0}
EOF
  # mock checkpoint: record it ran (+ ordering)
  cat > "$D/bin/checkpoint" <<EOF
#!/bin/bash
cat >> "$D/ckpt-payloads"; echo "CKPT" >> "$D/order"
EOF
  chmod +x "$D/bin/teardown" "$D/bin/checkpoint"
  export CC_REAPER_TEARDOWN_BIN="$D/bin/teardown"
  export CC_REAPER_CHECKPOINT_BIN="$D/bin/checkpoint"
  export CC_REAPER_SETTLE_S=100
  export CC_REAPER_TRUNK=origin/main
  export CC_REAPER_LOG="$D/reaper.log"
  # ── HERMETIC GARBAGE ARM (added 2026-08-12, backlog a3a070520f3d) ────────────────────────────
  # sweep() calls garbage_sweep "$reap" FIRST (bin/cc-reaper:814), so every one of the ~90
  # `run "$R" sweep --reap` cases below was running the DESTRUCTIVE arm. Its seams
  # (CC_REAPER_GARBAGE_PS_A/_PS_B, CC_REAPER_GARBAGE_KILL) are exported only by
  # mk_garbage_fixtures, which each garbage test calls ITSELF — they were never in setup(). So
  # ~90 tests read the REAL `ps -Ax` table and issued REAL `kill -TERM` (then -KILL 3 s later)
  # at any ppid-1 process matching bin/cc-reaper:344-349: orphan ps/tool/zsh/bash, where
  # `orphan-bash` is any ppid-1 bash older than 600 s whose argv misses the :339 whitelist.
  # `bats` is not in that whitelist. This suite is NOT in scripts/host-suites.manifest, so the
  # postland corpus runs it — the tree verifier was killing live processes as a side effect of
  # verifying the tree, on a box that also runs the operator's sessions.
  # NOTHING RECORDED IT, which is the half that made it survive: CC_REAPER_LOG above is redirected
  # to $D, so these kills appear in no log on the machine and the sender is unidentifiable after
  # the fact. Observed live 2026-08-12T12:53Z while investigating exactly that blindness — a
  # read-only ppid-1 watcher of mine, age 883 s, was selected `orphan-bash` and killed mid-run.
  # /dev/null is the documented fail-open seam (`snapshot unavailable — arm skipped`,
  # bin/cc-reaper:321), already asserted by "garbage: unavailable snapshot fails OPEN". Pinning it
  # here makes INERT the default and leaves mk_garbage_fixtures free to re-arm per test, so every
  # garbage case keeps its closed-world fixture and its exact-set assertion.
  export CC_REAPER_GARBAGE_PS_A=/dev/null CC_REAPER_GARBAGE_PS_B=/dev/null
  # Pinned too, though the fail-open return at :321 precedes the watchdog loop today: its default is
  # the LIVE $HOME/.claude/watchdog, and that loop `kill -0`s real pids and can add real victims.
  mkdir -p "$D/gs-wd-default"; export CC_REAPER_WATCHDOG_DIR="$D/gs-wd-default"
  # Hermetic sweep lock: without this every test would contend on the LIVE lockdir shared with the
  # launchd reaper — a real sweep mid-flight would make an arbitrary test skip its sweep and fail.
  export CC_REAPER_LOCKDIR="$D/sweep.lock.d"
  # ── hermetic paging (T-P3-3) + self-check (P0-12b): mock cc-notify + ps so no test can hit the LIVE
  #    desk or count REAL panes. Desk target is absent by default (→ no notify); surface/self-check tests
  #    opt in with set_desk. Live-pane count comes from $D/nlive (default 1 → matches the common 1-session
  #    case, so unrelated tests see Δ0 and never self-check-page). ──
  # Records the FULL argv, not "$2". v3 D2 moved paging from `cc-notify <uuid> <msg>` to
  # `cc-notify --role <role> <msg>`, which shifted the message off $2 — a stub pinned to a positional
  # index silently records the wrong field the moment the real tool's argv shape changes. Capturing
  # "$*" keeps every message-content assertion below working under BOTH shapes and additionally lets a
  # test assert the addressing form itself.
  # The ATTEMPT is recorded first, then CC_TEST_NOTIFY_RC scripts the OUTCOME — the split lets a test
  # count re-attempts of a page the transport REFUSED. Default 0 keeps every other test unchanged.
  # The real cc-notify prints a parseable `verdict=` token on STDERR and returns rc 0 for BOTH a live
  # delivery and a mailbox-only enqueue, so the stub emits one too: CC_TEST_NOTIFY_VERDICT scripts it
  # (default `delivered` = a live desk read it, the pre-2026-08-01 fixture assumption; `mailbox-only`
  # = the desk-less steady state of this machine; `none` = no token at all, the unreadable third state).
  cat > "$D/bin/notify" <<EOF
#!/bin/bash
printf 'NOTIFY %s\n' "\$*" >> "$D/notify-calls"
_v="\${CC_TEST_NOTIFY_VERDICT:-delivered}"
[ "\$_v" = none ] || printf 'cc-notify: enqueued=1 verdict=%s\n' "\$_v" >&2
exit \${CC_TEST_NOTIFY_RC:-0}
EOF
  cat > "$D/bin/ps" <<EOF
#!/bin/bash
n=\$(cat "$D/nlive" 2>/dev/null || echo 1)
for ((k=0; k<n; k++)); do echo "claude --permission-mode auto --model claude-opus-4-8 --effort max"; done
EOF
  # mock cc-reconcile: records that (and how) it was invoked so no test hits the LIVE cc-registry, and
  # the reconcile wiring (runs on --reap, before classify) is assertable.
  cat > "$D/bin/reconcile" <<EOF
#!/bin/bash
printf 'RECON %s\n' "\$*" >> "$D/reconcile-calls"
echo "cc-reconcile: mock 0 backfilled"
EOF
  # mock cc-backlog: records that `reap` was invoked (the claim-ledger sweep wiring, --reap only) so no
  # test hits the LIVE backlog. Echoes a summary line like the real one so the reaper surfaces it.
  cat > "$D/bin/backlog" <<EOF
#!/bin/bash
printf 'BACKLOG %s\n' "\$*" >> "$D/backlog-calls"
echo "cc-backlog reap: 0 reopened, 0 blocked (0 non-terminal scanned)"
EOF
  # mock cc-inbox-guard: records the sweep call (comms fail-loud backstop wiring, --reap only) so no test
  # hits the LIVE mailbox / operator phone. MUST be mocked — the real guard would sweep ~/.claude/mailbox.
  cat > "$D/bin/guard" <<EOF
#!/bin/bash
printf 'GUARD %s\n' "\$*" >> "$D/guard-calls"
echo "cc-inbox-guard: sweep done — 0 escalation(s)"
EOF
  chmod +x "$D/bin/notify" "$D/bin/ps" "$D/bin/reconcile" "$D/bin/backlog" "$D/bin/guard"
  export CC_REAPER_NOTIFY_BIN="$D/bin/notify"
  export CC_REAPER_PS_BIN="$D/bin/ps"
  export CC_REAPER_RECONCILE_BIN="$D/bin/reconcile"
  export CC_REAPER_BACKLOG_BIN="$D/bin/backlog"
  export CC_REAPER_GUARD_BIN="$D/bin/guard"
  export CC_REAPER_PAGEDIR="$D/pages"
  export CC_REAPER_IDL="$D/idl.jsonl"
  export CC_PAGE_TO=""                        # neutralize any inherited real desk target
  export CC_PAGE_TO_FILE="$D/desk"            # absent by default → no notify; opt in via set_desk
  export CC_REAPER_SELFCHECK_MIN_PERSIST=1    # one sweep pages a real blind spot (hysteresis tests override)
  # ── T-P3-4 fired-peer markers: hermetic dir, EMPTY by default so every pre-existing test runs
  #    unmarked (⇒ operator ⇒ never promoted). Tests opt in with mark_fired. ──
  export CC_FIRED_DIR="$D/fired"
  # THE KILL SWITCH IS AMBIENT BY DESIGN (P3, 2026-08-15) — an operator who has stopped the reaper
  # has it exported in the shell they run this suite from, and every test below would then pass
  # VACUOUSLY against a program that exits at its own line 100. Unset it so each test states its
  # own switch position. The FILE half needs no unsetting: its default resolves under the
  # fixtured $HOME set at the top of setup().
  unset CC_REAPER_DISABLE CC_REAPER_DISABLE_FILE
  # The worktree-removal bound and its ledger, pinned for the same reason: an ambient
  # CC_REAPER_WT_REMOVE_MAX=0 would make every removal assertion in this file vacuous, and an
  # unpinned ledger would append the operator's real disposal record from a test fixture.
  export CC_REAPER_WT_REMOVE_MAX=4
  export CC_WTGC_DISPOSAL_LOG="$D/worktree-disposals.jsonl"
}
# Pane UUIDs must be UUID-SHAPED ([0-9A-Fa-f-]) — cc-reaper's fired_peer refuses anything else as a
# path fragment, so the legacy "PANE-A" labels deliberately cannot carry a marker.
WPANE="2BE82E97-1111-4222-8333-444455556666"
# mark_fired writes a firedAt=now stamp; paired with mock_classify's startedAt=now default this is
# TENANCY-VALID by construction (rule 2). Tests exercising staleness set firedAt/startedAt explicitly.
mark_fired()   { mkdir -p "$D/fired"; local iso; iso="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)"
                 printf '{"paneUUID":"%s","cwd":"x","firedBy":"t","firedAt":"%s","selfRetire":true}\n' "${1:-$WPANE}" "$iso" > "$D/fired/${1:-$WPANE}.json"; }
fired_marked() { [ -f "$D/fired/${1:-$WPANE}.json" ]; }
notified()  { [ -s "$D/notify-calls" ]; }
reconciled() { [ -f "$D/reconcile-calls" ]; }
backlog_reaped() { grep -q '^BACKLOG reap' "$D/backlog-calls" 2>/dev/null; }
set_desk()  { echo "DESK-UUID" > "$D/desk"; }
set_live()  { echo "$1" > "$D/nlive"; }

# emit a mock cc-classify --all --json with ONE session; args: cause cwd idle landed [pane] [startedAt-ms]
# startedAt defaults to NOW-in-ms so a fresh mark_fired stamp is tenancy-VALID (rule 2); the stale-
# tenancy test overrides it to a value beyond firedAt+BOOT_MAX.
mock_classify() {
  local cause="$1" cwd="$2" idle="$3" landed="$4" pane="${5:-PANE-X}" started="${6:-$(( $(date +%s) * 1000 ))}"
  cat > "$D/bin/classify" <<EOF
#!/bin/bash
jq -nc '[{name:"t",paneUUID:"$pane",account:"next",cwd:"$cwd",cause:"$cause",idle_s:$idle,work_landed:"$landed",startedAt:$started,successor:"PANE-SUCC",detail:"x"}]'
EOF
  chmod +x "$D/bin/classify"; export CC_REAPER_CLASSIFY_BIN="$D/bin/classify"
}
# handed-off-lead mock that mirrors REALITY: emits the lead PLUS a LIVE successor session (pid=$$,
# active) in the SAME enumerated set. cc-classify only labels a session handed-off-lead when
# find_successor found a live successor drawn from that same set, so the reaper's Gap-2 successor-
# liveness leg (2026-07-25) requires the named successor to be a live row here. args: cwd idle landed [lead-pane]
HSUCC="5CC00000-1111-4222-8333-444455556666"
mock_classify_handoff() {
  local cwd="$1" idle="$2" landed="$3" pane="${4:-PANE-A}"
  cat > "$D/bin/classify" <<EOF
#!/bin/bash
jq -nc '[{name:"lead",paneUUID:"$pane",account:"next",cwd:"$cwd",cause:"handed-off-lead",idle_s:$idle,work_landed:"$landed",successor:"$HSUCC",detail:"x"},
         {name:"succ",paneUUID:"$HSUCC",account:"next",cwd:"$cwd",cause:"active",idle_s:5,work_landed:"no",successor:null,pid:$$,detail:"x"}]'
EOF
  chmod +x "$D/bin/classify"; export CC_REAPER_CLASSIFY_BIN="$D/bin/classify"
}
td_called() { [ -f "$D/td-calls" ]; }

@test "handed-off-lead + landed + idle>settle + --reap → teardown IS called with the pane" {
  mock_classify_handoff "$D/clean" 999 yes PANE-A
  run "$R" sweep --reap
  [ "$status" -eq 0 ]
  td_called
  grep -q 'PANE-A' "$D/td-calls"
  grep -q -- '--done-evidence' "$D/td-calls"
}

# The exact negative of the test above: same candidate, same fixture, ONE seam moved. It is the
# positive control for the CC_BEAT_DIR pin in setup() — it must go GREEN only because R3 fires, and
# it is the assertion that can fail if the pin is ever removed (then the test above reds instead,
# and the diagnosis is immediate). R3 itself had no coverage at all before this.
@test "R3 fail-closed: a live beat world + a beat-less sid → reap REFUSED, teardown never invoked" {
  mkdir -p "$D/cc-beats"
  printf '{"t":%s,"operatorT":%s,"who":"operator"}\n' "$(date +%s)" "$(date +%s)" \
    > "$D/cc-beats/some-other-live-session.json"   # the world beats; OUR sid does not
  mock_classify_handoff "$D/clean" 999 yes PANE-A
  run "$R" sweep --reap
  [ "$status" -eq 0 ]
  ! td_called || false                              # refused BEFORE teardown, not after
  [[ "$output" == *"no presence beat"* ]]
}

@test "checkpoint runs BEFORE teardown (checkpoint-first)" {
  mock_classify_handoff "$D/clean" 999 yes PANE-A
  run "$R" sweep --reap
  [ "$(head -1 "$D/order")" = CKPT ]
  grep -q '^TD ' "$D/order"
}

@test "DRY-RUN (no --reap) never calls teardown even for a valid candidate" {
  mock_classify_handoff "$D/clean" 999 yes
  run "$R" sweep
  [ "$status" -eq 0 ]
  ! td_called || false
  echo "$output" | grep -q WOULD-REAP
}

@test "active is NEVER reaped" {
  mock_classify active "$D/clean" 999 yes
  run "$R" sweep --reap
  ! td_called
}

@test "owned-wait is NEVER reaped" {
  mock_classify owned-wait "$D/clean" 999 yes
  run "$R" sweep --reap
  ! td_called
}

@test "coordination-hang is NEVER reaped" {
  mock_classify coordination-hang "$D/clean" 999 yes
  run "$R" sweep --reap
  ! td_called
}

@test "rate-limited is NEVER reaped" {
  mock_classify rate-limited "$D/clean" 999 yes
  run "$R" sweep --reap
  ! td_called
}

@test "crashed is NEVER reaped (surfaced only)" {
  mock_classify crashed "$D/clean" 999 yes
  run "$R" sweep --reap
  ! td_called
}

@test "reapable cause but work NOT landed → DEFER, no teardown" {
  mock_classify handed-off-lead "$D/clean" 999 no
  run "$R" sweep --reap
  ! td_called || false
  echo "$output" | grep -q 'NOT landed'
}

@test "reapable + landed but idle < settle → not yet (self-close window), no teardown" {
  mock_classify handed-off-lead "$D/clean" 50 yes
  run "$R" sweep --reap
  ! td_called || false
  echo "$output" | grep -q 'settle'
}

@test "finished-teammate (stamped) + landed + idle>settle → teardown called" {
  mark_fired
  mock_classify finished-teammate "$D/clean" 999 yes "$WPANE"
  run "$R" sweep --reap
  td_called; grep -q "$WPANE" "$D/td-calls"
}

@test "finished (stamped) + landed + idle>settle + --reap → teardown called (new reapable cause)" {
  mark_fired
  mock_classify finished "$D/clean" 999 yes "$WPANE"
  run "$R" sweep --reap
  [ "$status" -eq 0 ]
  td_called; grep -q "$WPANE" "$D/td-calls"
}

# ── 2026-07-24 belt (Danny-Studio-60 / Opus-5 incident): finished/finished-teammate may only
#    auto-reap a SPAWNER-STAMPED fired peer — an unstamped pane is operator-launched/adopted and is
#    surfaced for confirm-close, even when a (stale/foreign) classifier labels it reapable. ──

@test "2026-07-24 belt: finished WITHOUT the fired-peer stamp → surfaced, never torn down" {
  mock_classify finished "$D/clean" 999 yes "$WPANE"   # UUID pane, deliberately NO marker
  run "$R" sweep --reap
  [ "$status" -eq 0 ]
  ! td_called || false
  echo "$output" | grep -qi 'unstamped'
}

@test "2026-07-24 belt: finished-teammate WITHOUT the stamp → surfaced, never torn down" {
  mock_classify finished-teammate "$D/clean" 999 yes "$WPANE"
  run "$R" sweep --reap
  ! td_called || false
  echo "$output" | grep -qi 'unstamped'
}

@test "2026-07-24 belt: handed-off-lead is EXEMPT (live-successor evidence needs no stamp)" {
  mock_classify_handoff "$D/clean" 999 yes PANE-A
  run "$R" sweep --reap
  td_called
}

@test "2026-07-24 belt: finished-operator (classify's surface cause) pages the desk, never reaps" {
  set_desk
  mock_classify finished-operator "$D/clean" 9000 yes PANE-OP
  run "$R" sweep --reap
  ! td_called || false
  notified
  grep -q 'finished-operator' "$D/notify-calls"
}

@test "finished + work NOT landed → DEFER, no teardown (idle alone never reaps)" {
  mock_classify finished "$D/clean" 999 no
  run "$R" sweep --reap
  ! td_called || false
  echo "$output" | grep -q 'NOT landed'
}

@test "finished (stamped) DRY-RUN surfaces WOULD-REAP, never tears down" {
  mark_fired
  mock_classify finished "$D/clean" 999 yes "$WPANE"
  run "$R" sweep
  [ "$status" -eq 0 ]
  ! td_called || false
  echo "$output" | grep -q WOULD-REAP
}

@test "post-classify RACE: classify says landed but cwd is dirty at act-time → ABORT, WIP checkpointed, no teardown" {
  mock_classify_handoff "$D/dirty" 999 yes
  run "$R" sweep --reap
  ! td_called || false              # teardown NOT called
  [ -f "$D/ckpt-payloads" ]          # but checkpoint DID run first (WIP snapshotted)
  echo "$output" | grep -q ABORT
}

@test "cc-teardown DEFER (rc10) → reaper reports not-reaped, no crash" {
  mock_classify_handoff "$D/clean" 999 yes PANE-A
  TEARDOWN_RC=10 run "$R" sweep --reap
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'NOT reaped'
}

@test "identity pin (a17 S-4): classify-time pid+lstart are forwarded to cc-teardown as --expect-*" {
  # cc-classify emits pid+lstart; cc-reaper must thread them to cc-teardown so a classify→act recycle
  # is caught. A mock classify supplies both; the teardown call must carry --expect-pid/--expect-lstart.
  mark_fired
  local now_ms=$(( $(date +%s) * 1000 ))          # tenancy-valid startedAt (rule 2) vs the fresh stamp
  cat > "$D/bin/classify" <<EOF
#!/bin/bash
jq -nc '[{name:"t",paneUUID:"$WPANE",account:"next",cwd:"$D/clean",cause:"finished",idle_s:999,work_landed:"yes",pid:4242,lstart:"Fri Jul 18 10:00:00 2026",startedAt:$now_ms,successor:"PANE-SUCC",detail:"x"}]'
EOF
  chmod +x "$D/bin/classify"; export CC_REAPER_CLASSIFY_BIN="$D/bin/classify"
  run "$R" sweep --reap
  [ "$status" -eq 0 ]
  td_called
  grep -q -- '--expect-pid' "$D/td-calls"
  grep -q -- '4242' "$D/td-calls"
  grep -q -- '--expect-lstart' "$D/td-calls"
}

@test "identity pin: no pid/lstart from classify → no --expect-* args (back-compat, no crash)" {
  mark_fired
  mock_classify finished "$D/clean" 999 yes "$WPANE"   # legacy classify JSON: no pid/lstart fields
  run "$R" sweep --reap
  [ "$status" -eq 0 ]
  td_called
  ! grep -q -- '--expect-pid' "$D/td-calls"
}

@test "landed-by-content (P0-17): cc-reaper's re-check reaps a squash-landed repo (content on trunk, count>0)" {
  # classify says finished+landed; the cwd is squash-landed (count>0). The COUNT-based re-check ABORTed
  # (permanent DEFER); the CONTENT-based re-check sees the work on trunk and reaps.
  mark_fired
  mock_classify finished "$D/squash" 999 yes "$WPANE"
  run "$R" sweep --reap
  [ "$status" -eq 0 ]
  td_called
  grep -q "$WPANE" "$D/td-calls"
}

# ── stamp tenancy binding (2026-07-24 rule 2): a stamp gates a pane's CURRENT session only if that
#    session booted within firedAt+BOOT_MAX. A later tenant reusing a previously-fired pane inherits a
#    STALE stamp — never auto-reaped, and the stamp is GC'd. ──────────────────────────────────────────
@test "stale-tenancy stamp: a pane whose current session booted long after the fire is NOT reaped + stamp GC'd (rule 2)" {
  # firedAt = 2h ago; the current session started NOW (startedAt ≫ firedAt+BOOT_MAX=+1800). Pre-fix:
  # file-exists ⇒ belt passes ⇒ reaped. Post-fix: stale tenancy ⇒ auto-reap refused AND the stamp GC'd.
  set_desk; set_live 1
  local old_iso; old_iso="$(date -u -r "$(( $(date +%s) - 7200 ))" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)"
  mkdir -p "$D/fired"; printf '{"paneUUID":"%s","cwd":"x","firedBy":"t","firedAt":"%s","selfRetire":true}\n' "$WPANE" "$old_iso" > "$D/fired/$WPANE.json"
  mock_classify finished "$D/clean" 9000 yes "$WPANE" "$(( $(date +%s) * 1000 ))"   # tenant booted NOW
  run "$R" sweep --reap
  [ "$status" -eq 0 ]
  ! td_called || false                               # NOT reaped (stale stamp rejected by the belt)
  [ ! -f "$D/fired/$WPANE.json" ]                     # stamp GC'd
  grep -q 'stale-tenancy stamp GC' "$D/reaper.log"
  echo "$output" | grep -qi 'unstamped/stale'
}

# ─────────────────────────────────────────────────────────────────────────────────────────────────
# ITEM A — the dirty-check must ignore UNTRACKED files (backlog 99adcddc2cc8)
# ─────────────────────────────────────────────────────────────────────────────────────────────────

@test "untracked-only litter does NOT read dirty — a landed session is still reaped (99adcddc2cc8)" {
  # THE BUG: work_landed used a bare `status --porcelain`, so ONE stray untracked file in a shared
  # cwd (a live sibling's scratch output — never this session's uncommitted work) made every co-cwd
  # session permanently "dirty". The post-classify re-check ABORTed forever and nothing could close.
  mark_fired
  mock_classify finished "$D/untracked" 999 yes "$WPANE"
  run "$R" sweep --reap
  [ "$status" -eq 0 ]
  td_called                                          # reaped, not ABORTed
  ! echo "$output" | grep -q ABORT
}

@test "a TRACKED modification still reads dirty → ABORT (the relaxation removes no real safety)" {
  mark_fired
  mock_classify finished "$D/dirty" 999 yes "$WPANE"
  run "$R" sweep --reap
  ! td_called || false
  echo "$output" | grep -q ABORT
}

# ─────────────────────────────────────────────────────────────────────────────────────────────────
# T-P3-4 — AUTO-REAP the desk-fired worker pile (backlog 9113c6abb6c5). The four SAFETY INVARIANTS
# come first: what must NEVER be auto-reaped is proven before what must.
# ─────────────────────────────────────────────────────────────────────────────────────────────────

@test "SAFETY 1: an operator/role session (NO fired marker) that is finished-shared-review is NEVER auto-reaped — still surfaced" {
  # The load-bearing invariant. Identical state to the reapable case in every respect EXCEPT the
  # spawner's marker: idle, landed, tracked-clean, shared cwd. Unmarked ⇒ operator ⇒ hands off.
  set_desk; set_live 1
  mock_classify finished-shared-review "$D/untracked" 9000 no "$WPANE"    # no mark_fired
  run "$R" sweep --reap
  [ "$status" -eq 0 ]
  ! td_called || false                               # NOT reaped
  notified; grep -q 'finished-shared-review' "$D/notify-calls"   # surfaced exactly as before
}

@test "SAFETY 2: owned-wait / coordination-hang / crashed are NEVER auto-reaped — even WITH a fired marker" {
  # A marker is necessary but never sufficient: the cause gate is independent. A fired worker that
  # is hung mid-coordination, or whose process died, is a HUMAN's problem, not a reap candidate.
  set_desk; set_live 1
  for c in owned-wait coordination-hang crashed; do
    rm -f "$D/td-calls"; mark_fired "$WPANE"
    mock_classify "$c" "$D/untracked" 9000 yes "$WPANE"
    run "$R" sweep --reap
    [ "$status" -eq 0 ]
    ! td_called || false
  done
}

@test "SAFETY 3: a desk-fired peer whose TRACKED tree is dirty is NOT reaped — surfaced" {
  set_desk; set_live 1; mark_fired "$WPANE"
  mock_classify finished-shared-review "$D/dirty" 9000 no "$WPANE"
  run "$R" sweep --reap
  ! td_called || false
  echo "$output" | grep -q 'TRACKED tree dirty'
  notified                                           # falls through to the surface path
}

@test "SAFETY 4: a desk-fired peer whose work is NOT landed is NOT reaped — surfaced" {
  # Clean tree, but 1 commit genuinely absent from trunk. Reaping would strand it.
  set_desk; set_live 1; mark_fired "$WPANE"
  mock_classify finished-shared-review "$D/ahead" 9000 no "$WPANE"
  run "$R" sweep --reap
  ! td_called || false
  notified
}

@test "a desk-fired peer that is finished + landed + tracked-clean IS auto-reaped — no page, no confirm-close" {
  # The acute pain, fixed: this is the state 13+ workers were stuck in, each awaiting a hand-close.
  set_desk; set_live 1; mark_fired "$WPANE"
  mock_classify finished-shared-review "$D/untracked" 9000 no "$WPANE"
  run "$R" sweep --reap
  [ "$status" -eq 0 ]
  td_called; grep -q "$WPANE" "$D/td-calls"
  echo "$output" | grep -q 'promote'
  ! notified || false                                # auto-reaped SILENTLY — the operator is not paged
  # the DURABLE audit string must state the basis it actually has (fired peer + tracked-clean),
  # not the generic "clean & 0 ahead" evidence a promoted reap does NOT rest on
  grep -q 'T-P3-4 auto-reap' "$D/td-calls"
  grep -q 'desk-fired peer worker' "$D/td-calls"
}

@test "promotion still obeys the settle window (self-close keeps its first chance)" {
  set_desk; set_live 1; mark_fired "$WPANE"
  mock_classify finished-shared-review "$D/untracked" 50 no "$WPANE"   # idle < settle(100)
  run "$R" sweep --reap
  ! td_called || false
  echo "$output" | grep -q 'settle'
}

@test "DRY-RUN promotes but NEVER tears down (WOULD-REAP only)" {
  set_desk; set_live 1; mark_fired "$WPANE"
  mock_classify finished-shared-review "$D/untracked" 9000 no "$WPANE"
  run "$R" sweep
  [ "$status" -eq 0 ]
  ! td_called || false
  echo "$output" | grep -q WOULD-REAP
}

@test "a successful reap retires the fired-peer marker (the marker dir cannot grow forever)" {
  set_desk; set_live 1; mark_fired "$WPANE"
  fired_marked                                       # present before
  mock_classify finished-shared-review "$D/untracked" 9000 no "$WPANE"
  run "$R" sweep --reap
  td_called
  ! fired_marked                                     # retired with the pane
}

@test "a REFUSED teardown (rc10) keeps the fired-peer marker (the pane is still live)" {
  set_desk; set_live 1; mark_fired "$WPANE"
  mock_classify finished-shared-review "$D/untracked" 9000 no "$WPANE"
  TEARDOWN_RC=10 run "$R" sweep --reap
  [ "$status" -eq 0 ]
  fired_marked                                       # NOT dropped — the session lives on
}

@test "kill-switch CC_REAPER_AUTOREAP_FIRED=0 restores the old surface-only behaviour" {
  set_desk; set_live 1; mark_fired "$WPANE"
  export CC_REAPER_AUTOREAP_FIRED=0
  mock_classify finished-shared-review "$D/untracked" 9000 no "$WPANE"
  run "$R" sweep --reap
  ! td_called || false
  notified
}

@test "a non-UUID pane can never carry a marker (path-fragment guard fails safe)" {
  # fired_peer refuses anything not [0-9A-Fa-f-]; a marker filed under such a name is inert.
  set_desk; set_live 1
  mkdir -p "$D/fired"; echo '{"selfRetire":true}' > "$D/fired/../fired/PANE-X.json"
  mock_classify finished-shared-review "$D/untracked" 9000 no PANE-X
  run "$R" sweep --reap
  ! td_called || false
  notified
}

# ─────────────────────────────────────────────────────────────────────────────────────────────────
# worktree_cleanup — the relaxed dirty-check must NOT let `worktree remove --force` delete untracked
# work. Untracked counts as dirty HERE and only here, because here deletion is real.
# ─────────────────────────────────────────────────────────────────────────────────────────────────

mkworktree() { # <main-repo> <wt-path> — a real LINKED worktree under a */.worktrees/* path
  local m="${1:?mkworktree: main-repo path required}" w="$2"
  mkdir -p "$m"; git -C "$m" init -q; git -C "$m" config user.email t@t; git -C "$m" config user.name t
  echo a > "$m/f"; git -C "$m" add f; git -C "$m" commit -qm c1
  git -C "$m" update-ref refs/remotes/origin/main HEAD
  mkdir -p "$(dirname "$w")"
  git -C "$m" worktree add -q "$w" -b wt-branch >/dev/null 2>&1
}

@test "worktree_cleanup REMOVES a fully clean linked worktree after a reap" {
  mkworktree "$D/main" "$D/.worktrees/wt-clean"
  mark_fired
  mock_classify finished-teammate "$D/.worktrees/wt-clean" 999 yes "$WPANE"
  run "$R" sweep --reap
  td_called
  echo "$output" | grep -q 'worktree removed'
  [ ! -d "$D/.worktrees/wt-clean" ]
}

@test "worktree_cleanup LEAVES a worktree holding untracked files (--force would delete them)" {
  # The pane is still reaped — only the on-disk tree is preserved. Without this guard the relaxed
  # work_landed would let an uncommitted research report be deleted by `worktree remove --force`.
  mkworktree "$D/main2" "$D/.worktrees/wt-litter"
  echo "uncommitted research report" > "$D/.worktrees/wt-litter/REPORT.md"
  mark_fired
  mock_classify finished-teammate "$D/.worktrees/wt-litter" 999 yes "$WPANE"
  run "$R" sweep --reap
  td_called                                          # pane reaped
  echo "$output" | grep -q 'LEFT INTACT'
  [ -f "$D/.worktrees/wt-litter/REPORT.md" ]         # the work survives
}

# ─────────────────────────────────────────────────────────────────────────────────────────────────
# P3 (docs/plans/MASTER_FLEET_FOOTPRINT.md · 2026-08-15) — the highest-blast-radius unattended
# actuator on the box: launchd-LOADED, kills processes, tears down panes, removes worktrees. It had
# per-ARM switches (CC_REAPER_GARBAGE, CC_WATCHDOG_CENSUS) and no way to stop the program, so
# "disable the reaper" meant knowing a launchctl label. Three mechanisms, each red-proofed by a
# DISCRIMINATOR PAIR — switch on KEEPS, switch off REAPS THE SAME FIXTURE — because a subject that
# had simply stopped reaping would pass every disabled-half on its own.
#
# 🚨 THESE FIXTURES DRIVE handed-off-lead, NOT finished-teammate, and that is deliberate. The
# `finished*` causes additionally require a fired-peer stamp whose TENANCY check parses `firedAt`
# with `TZ=UTC date -j -f` (bin/cc-reaper:577) — a BSD/macOS-only invocation. On GNU date it fails,
# the stamp reads INVALID, and the reap is refused, so every `mark_fired` test in this file is
# structurally unrunnable off macOS (measured: the whole td_called family reds on Linux, against an
# unmodified subject). handed-off-lead reaches the SAME teardown → worktree_cleanup path with no
# stamp and no date parsing, so these gates are verifiable wherever the suite is run. The stamp
# path is not what P3 is about, and a gate that can only be checked on one machine is half a gate.
# ─────────────────────────────────────────────────────────────────────────────────────────────────

HS1="5CC00000-1111-4222-8333-44445555AAA1"
HS2="5CC00000-1111-4222-8333-44445555AAA2"

# mock_classify_handoffs <cwd1> [<cwd2>] — one or two handed-off leads, each with its own LIVE
# successor row (the reaper's Gap-2 leg requires the named successor to be live in the same
# enumerated set). Successors sit in a NEUTRAL cwd, never in the worktree under test, so nothing
# about the removal depends on where they happen to live.
mock_classify_handoffs() {
  local rows
  rows="{name:\"lead1\",paneUUID:\"PANE-L1\",account:\"next\",cwd:\"$1\",cause:\"handed-off-lead\",idle_s:999,work_landed:\"yes\",successor:\"$HS1\",detail:\"x\"},
        {name:\"succ1\",paneUUID:\"$HS1\",account:\"next\",cwd:\"$D/clean\",cause:\"active\",idle_s:5,work_landed:\"no\",successor:null,pid:$$,detail:\"x\"}"
  if [ -n "${2:-}" ]; then
    rows="$rows,
        {name:\"lead2\",paneUUID:\"PANE-L2\",account:\"next\",cwd:\"$2\",cause:\"handed-off-lead\",idle_s:999,work_landed:\"yes\",successor:\"$HS2\",detail:\"x\"},
        {name:\"succ2\",paneUUID:\"$HS2\",account:\"next\",cwd:\"$D/clean\",cause:\"active\",idle_s:5,work_landed:\"no\",successor:null,pid:$$,detail:\"x\"}"
  fi
  cat > "$D/bin/classify" <<EOF
#!/bin/bash
jq -nc '[$rows]'
EOF
  chmod +x "$D/bin/classify"; export CC_REAPER_CLASSIFY_BIN="$D/bin/classify"
}

@test "KILL SWITCH: CC_REAPER_DISABLE=1 classifies nothing, tears down nothing, removes nothing" {
  mkworktree "$D/main-ks" "$D/.worktrees/wt-ks"
  mock_classify_handoffs "$D/.worktrees/wt-ks"
  CC_REAPER_DISABLE=1 run "$R" sweep --reap
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'verdict=disabled env=CC_REAPER_DISABLE'
  ! td_called || false                               # the pane is untouched
  [ -d "$D/.worktrees/wt-ks" ]                       # and so is the tree
  # It is a switch on the PROGRAM, not on one arm: the sweep's other unattended writers — reconcile,
  # the backlog reap — never ran either.
  [ ! -f "$D/reconcile-calls" ]
  [ ! -f "$D/backlog-calls" ]
}

@test "KILL SWITCH RED-PROOF: CC_REAPER_DISABLE=0 is ENABLED — the same fixture IS reaped" {
  mkworktree "$D/main-ks" "$D/.worktrees/wt-ks"
  mock_classify_handoffs "$D/.worktrees/wt-ks"
  CC_REAPER_DISABLE=0 run "$R" sweep --reap
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q 'verdict=disabled' || false
  td_called
  [ ! -d "$D/.worktrees/wt-ks" ]
}

@test "KILL SWITCH: the FILE half disables a run that exports nothing (the launchd path)" {
  # The half that matters. A launchd job inherits no shell environment, so the env switch cannot
  # reach the loaded job at all — it would stop the reaper everywhere EXCEPT where it runs
  # unattended. $HOME is fixtured, so this writes the DEFAULT path, not a seam.
  mkworktree "$D/main-ksf" "$D/.worktrees/wt-ksf"
  mock_classify_handoffs "$D/.worktrees/wt-ksf"
  mkdir -p "$HOME/.claude/autonomy"; : > "$HOME/.claude/autonomy/cc-reaper.disabled"
  run "$R" sweep --reap
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'verdict=disabled file='
  ! td_called || false
  [ -d "$D/.worktrees/wt-ksf" ]
  # ...and removing the file re-arms it, with nothing else changed.
  rm -f "$HOME/.claude/autonomy/cc-reaper.disabled"
  run "$R" sweep --reap
  td_called
  [ ! -d "$D/.worktrees/wt-ksf" ]
}

@test "KILL SWITCH: any value but unset/0 disables — a typo'd switch must never stay armed" {
  mkworktree "$D/main-kt" "$D/.worktrees/wt-kt"
  mock_classify_handoffs "$D/.worktrees/wt-kt"
  CC_REAPER_DISABLE=false run "$R" sweep --reap     # reads as ENABLED under any truthiness rule
  echo "$output" | grep -q 'verdict=disabled'
  [ -d "$D/.worktrees/wt-kt" ]
}

@test "KILL SWITCH: CC_REAPER_DISABLE_FILE= (explicitly empty) ignores the file half" {
  mkworktree "$D/main-ke" "$D/.worktrees/wt-ke"
  mock_classify_handoffs "$D/.worktrees/wt-ke"
  mkdir -p "$HOME/.claude/autonomy"; : > "$HOME/.claude/autonomy/cc-reaper.disabled"
  CC_REAPER_DISABLE_FILE='' run "$R" sweep --reap
  ! echo "$output" | grep -q 'verdict=disabled' || false
  [ ! -d "$D/.worktrees/wt-ke" ]
}

@test "KILL SWITCH does not launder a typo'd COMMAND — argv validation still wins" {
  # A disabled reaper answering `sweeep` with exit 0 would turn the switch into a way to hide a
  # mistake: the operator sees a clean exit and believes the reaper is merely off.
  CC_REAPER_DISABLE=1 run "$R" sweeep
  [ "$status" -eq 2 ]
  echo "$output" | grep -q "unknown command"
}

@test "KILL SWITCH leaves --help reachable — it is where the switch is documented" {
  CC_REAPER_DISABLE=1 run "$R" --help
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'KILL SWITCH'
  echo "$output" | grep -q 'cc-reaper.disabled'
}

@test "KILL SWITCH also stops the GARBAGE arm — it is a switch on the program, not on a leg" {
  CC_REAPER_DISABLE=1 run "$R" garbage --reap
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'verdict=disabled'
  ! echo "$output" | grep -q 'reap commands' || false
}

@test "RUNAWAY BOUND: past CC_REAPER_WT_REMOVE_MAX the sweep stops REMOVING and says so" {
  # Every gate above this one judges ONE worktree. The failure class P3 exists for is a sweep whose
  # judgment is systematically wrong — a moved trunk, stale classify evidence — and per-item
  # correctness cannot bound that. Only a count can.
  mkworktree "$D/main-b" "$D/.worktrees/wt-b1"
  git -C "$D/main-b" worktree add -q "$D/.worktrees/wt-b2" -b wt-branch2 >/dev/null 2>&1
  mock_classify_handoffs "$D/.worktrees/wt-b1" "$D/.worktrees/wt-b2"
  CC_REAPER_WT_REMOVE_MAX=1 run "$R" sweep --reap
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'worktree removal BOUND HIT'
  echo "$output" | grep -q 'removal bound 1 reached this sweep'
  # Exactly one survives — and BOTH panes were still torn down: this is a brake on destruction,
  # never a stop on the reap. A directory left on disk is recoverable; that is the whole trade.
  n=0
  [ -d "$D/.worktrees/wt-b1" ] && n=$((n+1))
  [ -d "$D/.worktrees/wt-b2" ] && n=$((n+1))
  [ "$n" -eq 1 ]
  [ "$(grep -c . "$D/td-calls")" -ge 2 ]
}

@test "RUNAWAY BOUND RED-PROOF: raise it by one and BOTH of the same worktrees go" {
  mkworktree "$D/main-b" "$D/.worktrees/wt-b1"
  git -C "$D/main-b" worktree add -q "$D/.worktrees/wt-b2" -b wt-branch2 >/dev/null 2>&1
  mock_classify_handoffs "$D/.worktrees/wt-b1" "$D/.worktrees/wt-b2"
  CC_REAPER_WT_REMOVE_MAX=2 run "$R" sweep --reap
  ! echo "$output" | grep -q 'BOUND HIT' || false
  [ ! -d "$D/.worktrees/wt-b1" ]
  [ ! -d "$D/.worktrees/wt-b2" ]
}

@test "RUNAWAY BOUND: an unparseable value falls back to the DEFAULT, never to unbounded" {
  # A typo must not widen a destructive budget. `-1` is the one accepted opt-out and it is spelled
  # out; `abc` is not a request for unlimited removals.
  mkworktree "$D/main-bv" "$D/.worktrees/wt-bv"
  mock_classify_handoffs "$D/.worktrees/wt-bv"
  CC_REAPER_WT_REMOVE_MAX=abc run "$R" sweep --reap
  [ ! -d "$D/.worktrees/wt-bv" ]                     # default 4 > 1 removal ⇒ this one still goes
  ! echo "$output" | grep -q 'BOUND HIT' || false
}

@test "the DISPOSAL LEDGER records every removal, and the gitignored bytes it destroyed" {
  # `git status --porcelain` — the untracked guard above — cannot see ignored content, and
  # `git worktree remove` deletes it anyway at exit 0. Nothing refuses on it (the live population is
  # dominated by node_modules), so the record is the ONLY trace those bytes ever existed.
  mkworktree "$D/main-l" "$D/.worktrees/wt-l"
  printf 'secrets.env\n' > "$D/.worktrees/wt-l/.gitignore"
  git -C "$D/.worktrees/wt-l" add .gitignore
  git -C "$D/.worktrees/wt-l" commit -qm ignore
  echo 'TOKEN=live' > "$D/.worktrees/wt-l/secrets.env"     # invisible to --porcelain, deleted anyway
  # The worktree is now 1 commit ahead of trunk; land it so work_landed still holds.
  git -C "$D/main-l" update-ref refs/remotes/origin/main "$(git -C "$D/.worktrees/wt-l" rev-parse HEAD)"
  mock_classify_handoffs "$D/.worktrees/wt-l"
  run "$R" sweep --reap
  [ ! -d "$D/.worktrees/wt-l" ]
  echo "$output" | grep -q 'gitignored content destroyed with it'
  # One JSON line, in the SAME ledger scripts/worktree-gc.sh writes — the operator's question is
  # "what was in that directory", never "which of my two reapers removed it". `actor` separates them.
  [ -s "$CC_WTGC_DISPOSAL_LOG" ]
  run jq -r '.actor + " " + .event + " " + .destroyed_ignored' "$CC_WTGC_DISPOSAL_LOG"
  [ "$output" = "cc-reaper worktree-disposed secrets.env" ]
}

@test "a REFUSED removal writes no disposal record — the ledger states facts, not intentions" {
  # The pair for the test above: a record written before the removal succeeded would make the
  # ledger's whole purpose (what was destroyed) unfalsifiable.
  mkworktree "$D/main-r" "$D/.worktrees/wt-r"
  echo litter > "$D/.worktrees/wt-r/stray.md"        # untracked ⇒ the guard leaves it intact
  mock_classify_handoffs "$D/.worktrees/wt-r"
  run "$R" sweep --reap
  [ -d "$D/.worktrees/wt-r" ]
  [ ! -s "$CC_WTGC_DISPOSAL_LOG" ]
}

@test "the no-force discipline is in the SOURCE — this reaper no longer overrides git's refusal" {
  # The law is audit §8-H and tests/worktree-gc.bats guards the janitor's source for it; cc-reaper
  # was the one actuator still forcing, and it is the one that runs with nobody to ask. `--force`
  # discards git's own second opinion on OUR evidence, on a tree we have already proven clean — so
  # it could only ever override a refusal we had not anticipated.
  body="$(grep -v '^[[:space:]]*#' "$R")"
  ! printf '%s\n' "$body" | grep -qE 'worktree[[:space:]]+remove[^;]*--force' || false
}

# ─────────────────────────────────────────────────────────────────────────────────────────────────
# T-P3-3 — surfaced-not-reaped causes get a DESK PAGE consumer (FM2 "surfaced ≠ acted" gap G-P3-3)
# ─────────────────────────────────────────────────────────────────────────────────────────────────

@test "T-P3-3: coordination-hang → desk PAGE (cc-notify) within one sweep, never reaped" {
  set_desk; set_live 1
  mock_classify coordination-hang "$D/clean" 9000 no PANE-H
  run "$R" sweep --reap
  [ "$status" -eq 0 ]
  notified                                         # a cc-notify reached the desk
  grep -q 'REAPER SURFACE' "$D/notify-calls"
  grep -q 'coordination-hang' "$D/notify-calls"
  ! td_called                                      # surfaced only — NEVER torn down
}

@test "T-P3-3: crashed and finished-shared-review each page the desk" {
  set_desk; set_live 1
  mock_classify crashed "$D/clean" 9000 no PANE-C
  run "$R" sweep --reap
  notified; grep -q 'crashed' "$D/notify-calls"
  : > "$D/notify-calls"; rm -rf "$D/pages"
  mock_classify finished-shared-review "$D/clean" 9000 no PANE-R
  run "$R" sweep --reap
  notified; grep -q 'finished-shared-review' "$D/notify-calls"
}

@test "T-P3-3 truthfulness: a REFUSED page is NOT damped — no cause marker, and it retries next sweep" {
  # The defect class (F1): notify_desk `|| true`'d cc-notify and handle_surface wrote the per-cause
  # damping marker + said "PAGE → desk" regardless. A page the transport REFUSED (rc 3 unresolvable
  # role / rc 5 unwritable inbox) was therefore claimed as delivered AND damped forever.
  set_desk; set_live 1
  mock_classify coordination-hang "$D/clean" 9000 no PANE-H
  CC_TEST_NOTIFY_RC=3 run "$R" sweep --reap
  [ "$status" -eq 0 ]
  [ -n "$(grep -c 'NOTIFY' "$D/notify-calls" 2>/dev/null)" ]
  [ "$(grep -c 'NOTIFY' "$D/notify-calls")" -eq 1 ]        # one attempt was made…
  run grep -q 'PAGE   ' "$D/reaper.log"                    # …but never claimed as a delivered page
  [ "$status" -ne 0 ]
  # the per-cause damping marker must NOT exist, else the retry is suppressed forever
  [ "$(find "$D/pages" -name '*.cause' 2>/dev/null | wc -l | tr -d ' ')" -eq 0 ]
  run grep -q 'UNDELIVERED' "$D/reaper.log"
  [ "$status" -eq 0 ]
  # next sweep, channel still refusing → RE-ATTEMPTED (2 attempts), not damped out of existence
  CC_TEST_NOTIFY_RC=3 run "$R" sweep --reap
  [ "$(grep -c 'NOTIFY' "$D/notify-calls")" -eq 2 ]
  # channel recovers → delivered, marker recorded, and the next identical sweep is damped
  run "$R" sweep --reap
  [ "$(grep -c 'NOTIFY' "$D/notify-calls")" -eq 3 ]
  [ "$(find "$D/pages" -name '*.cause' 2>/dev/null | wc -l | tr -d ' ')" -eq 1 ]
  run "$R" sweep --reap
  [ "$(grep -c 'NOTIFY' "$D/notify-calls")" -eq 3 ]        # damping intact — only the lie was removed
}

@test "T-P3-3 damping: the SAME surface cause pages ONCE across sweeps (no per-sweep composer storm)" {
  set_desk; set_live 1
  mock_classify coordination-hang "$D/clean" 9000 no PANE-H
  run "$R" sweep --reap; notified                  # first sweep pages
  : > "$D/notify-calls"
  run "$R" sweep --reap                             # identical second sweep
  [ "$status" -eq 0 ]
  ! notified || false                               # damped — no second notify
  echo "$output" | grep -q 'damped'
}

@test "T-P3-3: a cause CHANGE on the same pane re-pages (coordination-hang → crashed)" {
  set_desk; set_live 1
  mock_classify coordination-hang "$D/clean" 9000 no PANE-H
  run "$R" sweep --reap
  : > "$D/notify-calls"
  mock_classify crashed "$D/clean" 9000 no PANE-H   # same pane, worsened cause
  run "$R" sweep --reap
  notified; grep -q 'crashed' "$D/notify-calls"
}

@test "T-P3-3: a non-surface never-reap cause (active/owned-wait/rate-limited) NEVER pages" {
  set_desk; set_live 1
  for c in active owned-wait rate-limited; do
    : > "$D/notify-calls"
    mock_classify "$c" "$D/clean" 9000 no PANE-X
    run "$R" sweep --reap
    [ "$status" -eq 0 ]
    ! notified || false
  done
}

@test "T-P3-3 dry-run: a surface cause prints WOULD-PAGE and NEVER notifies" {
  set_desk; set_live 1
  mock_classify coordination-hang "$D/clean" 9000 no PANE-H
  run "$R" sweep
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'WOULD-PAGE'
  ! notified
}

@test "T-P3-3 re-arm: a pane leaving the surface set drops its damping marker (recovery re-pages later)" {
  set_desk; set_live 1
  mock_classify coordination-hang "$D/clean" 9000 no PANE-H
  run "$R" sweep --reap
  [ -f "$D/pages/PANE-H.cause" ]                    # marker written on first page
  mock_classify active "$D/clean" 10 no PANE-H      # recovered → no longer surfaced
  run "$R" sweep --reap
  [ ! -f "$D/pages/PANE-H.cause" ]                  # marker pruned → re-armed
}

# ─────────────────────────────────────────────────────────────────────────────────────────────────
# NO DESK IS REGISTERED — a supported configuration, not a fault (2026-08-01)
#
# `cc-notify --role desk` returns rc 0 with verdict=mailbox-only/unverified FOREVER on a machine that
# runs no desk orchestrator (the role file holds a self-closed iTerm2 pane and nothing can create a
# successor). notify_desk checked ONLY $? , so every such page was claimed as a delivery ("→ desk")
# AND the per-(session,cause) damper was written — silencing, permanently, a finding nothing alive had
# read. The three outcomes are now partitioned as in scripts/lead-supervisor.sh (e5894631):
# REACHED (rc 0 + verdict=delivered) · RECORDED (rc 0 + anything else) · REFUSED (rc != 0).
# ─────────────────────────────────────────────────────────────────────────────────────────────────
save_out() { printf '%s\n' "$output" > "$D/sweep.out"; }   # $output survives the NEXT run/grep this way

@test "no-desk RECORDED: a mailbox-only page (rc 0) is never claimed as a desk delivery" {
  set_desk; set_live 1
  mock_classify coordination-hang "$D/clean" 9000 no PANE-H
  CC_TEST_NOTIFY_VERDICT=mailbox-only run "$R" sweep --reap
  save_out
  [ "$status" -eq 0 ]
  [ "$(grep -c 'NOTIFY' "$D/notify-calls")" -eq 1 ]                  # the send WAS attempted
  ! grep -q -- '→ desk' "$D/sweep.out" || false                      # …and must NOT be claimed as reaching one
  grep -q 'NO live desk received it' "$D/sweep.out"                  # says plainly what happened
  grep -q 'verdict=mailbox-only' "$D/sweep.out"
  grep -q 'page RECORDED verdict=mailbox-only' "$D/reaper.log"
  grep -q 'surface-page RECORDED' "$D/reaper.log"
  ! grep -q 'surface-page DELIVERED' "$D/reaper.log" || false
}

@test "no-desk RECORDED: the mailbox record still damps — no per-sweep re-page storm" {
  # The anti-storm half, and the reason RECORDED returns 0: the record stands and re-deriving it every
  # 300s sweep is the 2026-07-19 composer storm. Truthfulness must not cost damping.
  set_desk; set_live 1
  mock_classify coordination-hang "$D/clean" 9000 no PANE-H
  CC_TEST_NOTIFY_VERDICT=mailbox-only run "$R" sweep --reap
  [ -f "$D/pages/PANE-H.cause" ]                                     # (session,cause) damper KEPT
  [ "$(grep -c 'NOTIFY' "$D/notify-calls")" -eq 1 ]
  CC_TEST_NOTIFY_VERDICT=mailbox-only run "$R" sweep --reap          # identical second sweep
  [ "$status" -eq 0 ]
  [ "$(grep -c 'NOTIFY' "$D/notify-calls")" -eq 1 ]                   # not re-sent
}

@test "no-desk REACHED control: verdict=delivered DOES claim the desk (the gate is not always-recorded)" {
  set_desk; set_live 1
  mock_classify coordination-hang "$D/clean" 9000 no PANE-H
  CC_TEST_NOTIFY_VERDICT=delivered run "$R" sweep --reap
  save_out
  [ "$status" -eq 0 ]
  grep -q -- '→ desk' "$D/sweep.out"
  ! grep -q 'NO live desk received it' "$D/sweep.out" || false
  grep -q 'surface-page DELIVERED' "$D/reaper.log"
}

@test "no-desk UNREADABLE: an rc-0 page with NO verdict token is a third state, never promoted" {
  # A verdict we cannot read is not a delivery. Fail-closed: it takes the RECORDED path, keeps the
  # damper, and says so — it must never inherit the `delivered` claim by default.
  set_desk; set_live 1
  mock_classify coordination-hang "$D/clean" 9000 no PANE-H
  CC_TEST_NOTIFY_VERDICT=none run "$R" sweep --reap
  save_out
  [ "$status" -eq 0 ]
  ! grep -q -- '→ desk' "$D/sweep.out" || false
  grep -q 'verdict=unreadable' "$D/sweep.out"
  grep -q 'page RECORDED verdict=unreadable' "$D/reaper.log"
}

@test "no-desk REFUSED: rc != 0 still wins over a delivered verdict (marker withheld, retried)" {
  # The rc arm is unchanged and takes precedence: a transport that refused took NOTHING, whatever the
  # (stale/partial) token on its stderr says.
  set_desk; set_live 1
  mock_classify coordination-hang "$D/clean" 9000 no PANE-H
  CC_TEST_NOTIFY_RC=3 CC_TEST_NOTIFY_VERDICT=delivered run "$R" sweep --reap
  [ "$status" -eq 0 ]
  [ "$(find "$D/pages" -name '*.cause' 2>/dev/null | wc -l | tr -d ' ')" -eq 0 ]
  grep -q 'page SEND FAILED rc=3' "$D/reaper.log"
  grep -q 'UNDELIVERED' "$D/reaper.log"
}

@test "no-desk: the self-check blind-spot page stops claiming a desk when none received it" {
  set_desk; set_live 4                                               # 4 live panes, 1 enumerated
  mock_classify active "$D/clean" 10 no PANE-1
  CC_TEST_NOTIFY_VERDICT=mailbox-only run "$R" sweep --reap
  save_out
  [ "$status" -eq 0 ]
  grep -q 'BLIND to 3' "$D/notify-calls"                             # the finding is still recorded
  ! grep -q 'self-check: PAGE' "$D/sweep.out" || false
  grep -q 'self-check: RECORD' "$D/sweep.out"
  grep -q 'NO live desk received it' "$D/sweep.out"
  grep -q 'self-check RECORDED' "$D/reaper.log"
}

@test "no-desk: safeguard-blocked stops reporting '+ desk' when the desk mailbox took it" {
  mock_classify_safeguard "$WPANE" "$D/clean"; mark_fired "$WPANE"; set_desk
  CC_TEST_NOTIFY_VERDICT=mailbox-only run "$R" sweep --reap
  save_out
  [ "$status" -eq 0 ]
  grep -q 'REAPER SURFACE' "$D/notify-calls"                         # the desk page is still ATTEMPTED
  ! grep -q -- '+ desk +' "$D/sweep.out" || false
  grep -q 'desk MAILBOX (no live desk' "$D/sweep.out"
  grep -q 'desk=recorded' "$D/reaper.log"
}

# ─────────────────────────────────────────────────────────────────────────────────────────────────
# P0-12b — enumerated≈live-panes self-check: surface the delta when the reaper is blind to live panes
# ─────────────────────────────────────────────────────────────────────────────────────────────────

@test "P0-12b: live panes > enumerated → desk PAGE (blind-spot surface), never a reap" {
  set_desk; set_live 4                              # 4 live interactive panes
  mock_classify active "$D/clean" 10 no PANE-1      # but only 1 enumerated
  run "$R" sweep --reap                             # MIN_PERSIST=1 → pages on the first sweep
  [ "$status" -eq 0 ]
  notified
  grep -q 'SELF-CHECK' "$D/notify-calls"
  grep -q 'BLIND to 3' "$D/notify-calls"
  ! td_called
}

@test "P0-12b: live == enumerated → no page (the reaper sees every live pane)" {
  set_desk; set_live 1
  mock_classify active "$D/clean" 10 no PANE-1
  run "$R" sweep --reap
  [ "$status" -eq 0 ]
  ! notified || false
  echo "$output" | grep -q 'reaper sees all live panes'
}

@test "P0-12b hysteresis: a blind-spot delta must PERSIST before it pages (kills a start/exit race)" {
  set_desk; set_live 3
  export CC_REAPER_SELFCHECK_MIN_PERSIST=2
  mock_classify active "$D/clean" 10 no PANE-1
  run "$R" sweep --reap                             # sweep 1 → persist 1/2, observe only
  ! notified || false
  echo "$output" | grep -q 'persist 1/2'
  run "$R" sweep --reap                             # sweep 2 → persist 2/2, page
  notified; grep -q 'SELF-CHECK' "$D/notify-calls"
}

@test "P0-12b dry-run: a blind spot prints WOULD-PAGE and NEVER notifies" {
  set_desk; set_live 4
  mock_classify active "$D/clean" 10 no PANE-1
  run "$R" sweep
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'self-check: WOULD-PAGE'
  ! notified
}

@test "P0-12b: live_pane_count counts claude.exe panes (eval-track binary), not only claude" {
  # The eval-track (2.1.x claude-next) install's binary is .../bin/claude.exe as argv0 — NOT `claude`.
  # session-register.sh:63 registers it (matches claude|claude.exe|claude-*), so it IS enumerated; but
  # the self-check's INDEPENDENT truth signal (live_pane_count) matched only claude/*/claude/cli.js and
  # SILENTLY DROPPED every claude.exe pane. Result: live undercounts, the live−enum delta is biased, and
  # the blind-spot detector is desensitized (and false-pages at other session mixes). RED before the fix:
  # 3 live claude.exe panes read as 0 live ⇒ "reaper sees all live panes" ⇒ no page (blind to the blind spot).
  set_desk
  cat > "$D/bin/ps" <<'PSEOF'
#!/bin/bash
echo "/Users/x/.claude-183/node_modules/@anthropic-ai/claude-code/bin/claude.exe --permission-mode auto --model claude-opus-4-8"
echo "claude.exe --permission-mode auto --effort max"
echo "/opt/claude/bin/claude.exe --model claude-opus-4-8"
PSEOF
  chmod +x "$D/bin/ps"
  cat > "$D/bin/classify" <<'CLEOF'
#!/bin/bash
echo '[]'
CLEOF
  chmod +x "$D/bin/classify"; export CC_REAPER_CLASSIFY_BIN="$D/bin/classify"
  run "$R" sweep --reap
  [ "$status" -eq 0 ]
  notified
  grep -q 'BLIND to 3' "$D/notify-calls"            # all 3 claude.exe panes counted as live
}

@test "reconcile runs on --reap (heals the registry before the self-check surfaces a delta)" {
  mock_classify active "$D/clean" 10 no PANE-1
  run "$R" sweep --reap
  [ "$status" -eq 0 ]
  reconciled                                        # cc-reconcile was invoked
  echo "$output" | grep -q 'cc-reconcile: mock'     # its summary is surfaced on stdout
}

@test "cc-backlog reap runs on --reap (heals the CLAIM ledger, its summary surfaced)" {
  mock_classify active "$D/clean" 10 no PANE-1
  run "$R" sweep --reap
  [ "$status" -eq 0 ]
  backlog_reaped                                    # cc-backlog reap was invoked
  echo "$output" | grep -q 'cc-backlog reap:'       # its summary is surfaced on stdout
}

@test "cc-backlog reap does NOT run on a DRY-RUN sweep (dry-run writes nothing)" {
  mock_classify active "$D/clean" 10 no PANE-1
  run "$R" sweep
  [ "$status" -eq 0 ]
  ! backlog_reaped                                  # no claim-ledger mutation on a dry-run
}

@test "reconcile does NOT run on a DRY-RUN sweep (dry-run writes nothing)" {
  mock_classify active "$D/clean" 10 no PANE-1
  run "$R" sweep
  [ "$status" -eq 0 ]
  ! reconciled
}

# ─────────────────────────────────────────────────────────────────────────────────────────────────
# log() timestamps — TRUE UTC, never local-time mislabeled with a Z (cc-backlog 6d898339d690)
# ─────────────────────────────────────────────────────────────────────────────────────────────────

@test "log() stamps true UTC, not local time mislabeled Z (cc-backlog 6d898339d690)" {
  # Regression: log() used a bare \`date\` (LOCAL time) under a literal Z (UTC marker), so
  # cc-reaper.log read TZ-offset hours stale to any freshness check → a false 'reaper DORMANT /
  # no sweep since HH:MMZ' page while the reaper was in fact sweeping every ~5 min. Force a fixed
  # non-UTC zone; the emitted [..Z] stamp, parsed AS UTC, must land inside the sweep's real UTC
  # window — a local-as-Z value is a full 5h out and fails.
  export TZ='Etc/GMT-5'                              # UTC+5, DST-free (POSIX offset sign is inverted)
  mock_classify active "$D/clean" 999 yes
  local before after ts epoch
  before=$(date -u +%s)
  run "$R" sweep --reap
  after=$(date -u +%s)
  [ "$status" -eq 0 ]
  ts=$(grep 'sweep start' "$D/reaper.log" | tail -1 | sed -E 's/^\[([0-9T:-]+)Z\].*/\1/')
  [ -n "$ts" ]
  epoch=$(date -j -u -f "%Y-%m-%dT%H:%M:%S" "$ts" +%s)   # -u: interpret the stamp AS UTC (TZ-independent)
  [ -n "$epoch" ]
  [ "$epoch" -ge "$((before - 120))" ]               # the 5h (18000s) mislabel dwarfs the ±120s slack
  [ "$epoch" -le "$((after + 120))" ]
}

# ─────────────────────────────────────────────────────────────────────────────────────────────────
# Gap-2 independent second legs (2026-07-25): coordination-abandoned + handed-off-lead each get an
# act-time leg of their own (the stamp belt above only covers finished/finished-teammate). Both fail
# CLOSED — any ambiguity ⇒ surface, never reap.
# ─────────────────────────────────────────────────────────────────────────────────────────────────

@test "Gap-2 leg: coordination-abandoned with a RECENT operator prompt → auto-reap REFUSED (surfaced)" {
  set_desk
  local sid="11111111-2222-3333-4444-555566667777" pane="A0A02222-1111-4333-8444-555566667777"
  mkdir -p "$D/proj/slug"; export CC_REAPER_PROJECT_ROOTS="$D/proj"
  local ts; ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"       # operator prompt ~now (< 6h hold)
  printf '{"type":"user","isMeta":false,"message":{"role":"user","content":"keep going please"},"timestamp":"%s"}\n' "$ts" > "$D/proj/slug/$sid.jsonl"
  cat > "$D/bin/classify" <<EOF
#!/bin/bash
jq -nc '[{name:"lead",paneUUID:"$pane",account:"next",cwd:"$D/clean",session_id:"$sid",cause:"coordination-abandoned",idle_s:9999,work_landed:"yes",successor:null,detail:"x"}]'
EOF
  chmod +x "$D/bin/classify"; export CC_REAPER_CLASSIFY_BIN="$D/bin/classify"
  run "$R" sweep --reap
  [ "$status" -eq 0 ]
  ! td_called || false                                 # never reaped — the operator is present
  grep -q 'operator prompt' "$D/reaper.log"
}

@test "Gap-2 leg: coordination-abandoned with an OLD operator prompt (>hold) → still reaped (no over-block)" {
  local sid="99999999-2222-3333-4444-555566667777" pane="B0B02222-1111-4333-8444-555566667777"
  mkdir -p "$D/proj/slug"; export CC_REAPER_PROJECT_ROOTS="$D/proj"
  local ts; ts="$(date -u -v-10H +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '10 hours ago' +%Y-%m-%dT%H:%M:%SZ)"
  printf '{"type":"user","isMeta":false,"message":{"role":"user","content":"old prompt"},"timestamp":"%s"}\n' "$ts" > "$D/proj/slug/$sid.jsonl"
  cat > "$D/bin/classify" <<EOF
#!/bin/bash
jq -nc '[{name:"lead",paneUUID:"$pane",account:"next",cwd:"$D/clean",session_id:"$sid",cause:"coordination-abandoned",idle_s:9999,work_landed:"yes",successor:null,detail:"x"}]'
EOF
  chmod +x "$D/bin/classify"; export CC_REAPER_CLASSIFY_BIN="$D/bin/classify"
  run "$R" sweep --reap
  [ "$status" -eq 0 ]
  td_called                                            # 10h-old prompt → not adopted → reaps
  grep -q "$pane" "$D/td-calls"
}

@test "Gap-2 leg: coordination-abandoned with an UNRESOLVABLE transcript → surfaced, never reaped (fail-closed)" {
  set_desk
  local pane="C0C02222-1111-4333-8444-555566667777"
  export CC_REAPER_PROJECT_ROOTS="$D/proj-empty"; mkdir -p "$D/proj-empty"
  cat > "$D/bin/classify" <<EOF
#!/bin/bash
jq -nc '[{name:"lead",paneUUID:"$pane",account:"next",cwd:"$D/clean",session_id:"no-such-sid",cause:"coordination-abandoned",idle_s:9999,work_landed:"yes",successor:null,detail:"x"}]'
EOF
  chmod +x "$D/bin/classify"; export CC_REAPER_CLASSIFY_BIN="$D/bin/classify"
  run "$R" sweep --reap
  [ "$status" -eq 0 ]
  ! td_called || false
  grep -q 'fail-closed' "$D/reaper.log"
}

@test "Gap-2 leg: coordination-abandoned whose transcript is CORRUPT → surfaced, never reaped (empty-answer split)" {
  # The transcript RESOLVES (so the unresolvable leg above never fires) but holds not one well-formed
  # record. Before the 2026-07-25 split ce_last_interactive_age answered "" — indistinguishable from
  # "nobody typed" — and this pane was REAPED on absence of evidence.
  set_desk
  local sid="c0ffee11-2222-3333-4444-555566667777" pane="F0F02222-1111-4333-8444-555566667777"
  mkdir -p "$D/proj/slug"; export CC_REAPER_PROJECT_ROOTS="$D/proj"
  printf 'not json at all\nhalf a record {"type":"user"\n\001\002 binary junk\n' > "$D/proj/slug/$sid.jsonl"
  cat > "$D/bin/classify" <<EOF
#!/bin/bash
jq -nc '[{name:"lead",paneUUID:"$pane",account:"next",cwd:"$D/clean",session_id:"$sid",cause:"coordination-abandoned",idle_s:9999,work_landed:"yes",successor:null,detail:"x"}]'
EOF
  chmod +x "$D/bin/classify"; export CC_REAPER_CLASSIFY_BIN="$D/bin/classify"
  run "$R" sweep --reap
  [ "$status" -eq 0 ]
  # `[ ! -f … ]`, NOT `! td_called`: bash exempts a `!`-inverted command from errexit, so a MID-test
  # `! td_called` can never fail a bats test (verified, bats 1.13) — a negative that must BITE has to be
  # a plain test command or the test's last line.
  [ ! -f "$D/td-calls" ]                               # never reaped — adoption is UNKNOWN, not absent
  grep -q 'transcript unreadable (fail-closed)' "$D/reaper.log"
}

@test "Gap-2 leg: handed-off-lead whose successor is NOT live at act time → auto-reap REFUSED (surfaced)" {
  set_desk
  local pane="D0D02222-1111-4333-8444-555566667777" succ="D5D53333-1111-4333-8444-555566667777"
  # the named successor pane is ABSENT from the classify set → its pid is unknown → continuity unproven
  cat > "$D/bin/classify" <<EOF
#!/bin/bash
jq -nc '[{name:"lead",paneUUID:"$pane",account:"next",cwd:"$D/clean",session_id:"sid-h",cause:"handed-off-lead",idle_s:9999,work_landed:"yes",successor:"$succ",detail:"x"}]'
EOF
  chmod +x "$D/bin/classify"; export CC_REAPER_CLASSIFY_BIN="$D/bin/classify"
  run "$R" sweep --reap
  [ "$status" -eq 0 ]
  ! td_called || false
  grep -q 'not alive at act time' "$D/reaper.log"
}

@test "Gap-2 leg: handed-off-lead with a LIVE successor in the classify set → still reaped (no over-block)" {
  local pane="E0E02222-1111-4333-8444-555566667777" succ="E5E53333-1111-4333-8444-555566667777"
  # the successor row carries pid=$$ (this test proc, alive) → continuity proven → reaps normally
  cat > "$D/bin/classify" <<EOF
#!/bin/bash
jq -nc '[{name:"lead",paneUUID:"$pane",account:"next",cwd:"$D/clean",session_id:"sid-h",cause:"handed-off-lead",idle_s:9999,work_landed:"yes",successor:"$succ",detail:"x"},
         {name:"succ",paneUUID:"$succ",account:"next",cwd:"$D/clean",session_id:"sid-s",cause:"active",idle_s:5,work_landed:"no",successor:null,pid:$$,detail:"x"}]'
EOF
  chmod +x "$D/bin/classify"; export CC_REAPER_CLASSIFY_BIN="$D/bin/classify"
  run "$R" sweep --reap
  [ "$status" -eq 0 ]
  td_called
  grep -q "$pane" "$D/td-calls"
}

# ─────────────────────────────────────────────────────────────────────────────────────────────────
# Gap-3 suspend-guard (2026-07-25): a sweep whose wall-clock crossed a machine SUSPEND must reap
# nothing (the classify idle values are stale across the jump). Clock seamed via CC_REAPER_NOW_FILE —
# a durable value, not a file mtime. The reapable candidate is a handed-off-lead with a live successor
# (passes every other gate) so ONLY the suspend-guard can defer it.
# ─────────────────────────────────────────────────────────────────────────────────────────────────

@test "Gap-3 suspend-guard: inter-sweep gap > threshold (machine slept between sweeps) → reap DEFERRED" {
  local NOW=1900000000
  export CC_REAPER_NOW_FILE="$D/now"; echo "$NOW" > "$D/now"
  export CC_REAPER_BEAT_FILE="$D/beat"; echo "$((NOW-10000))" > "$D/beat"   # last sweep ended 10000s ago
  export CC_REAPER_SUSPEND_S=900
  mock_classify_handoff "$D/clean" 9999 yes PANE-A
  run "$R" sweep --reap
  [ "$status" -eq 0 ]
  ! td_called || false
  grep -q 'suspend-defer' "$D/reaper.log"
}

@test "Gap-3 suspend-guard: intra-sweep span > threshold (slept mid-sweep) → reap DEFERRED" {
  local NOW=1900000000
  export CC_REAPER_NOW_FILE="$D/now"; echo "$NOW" > "$D/now"
  export CC_REAPER_BEAT_FILE="$D/beat"; echo "$((NOW-60))" > "$D/beat"       # recent last sweep (no inter-suspend)
  export CC_REAPER_SUSPEND_S=900
  # classify BUMPS the clock +10000s while running → simulates a suspend DURING classify
  cat > "$D/bin/classify" <<EOF
#!/bin/bash
echo "$((NOW+10000))" > "$D/now"
jq -nc '[{name:"lead",paneUUID:"PANE-A",account:"next",cwd:"$D/clean",cause:"handed-off-lead",idle_s:9999,work_landed:"yes",successor:"$HSUCC",detail:"x"},
         {name:"succ",paneUUID:"$HSUCC",account:"next",cwd:"$D/clean",cause:"active",idle_s:5,work_landed:"no",successor:null,pid:$$,detail:"x"}]'
EOF
  chmod +x "$D/bin/classify"; export CC_REAPER_CLASSIFY_BIN="$D/bin/classify"
  run "$R" sweep --reap
  [ "$status" -eq 0 ]
  ! td_called || false
  grep -q 'suspend-defer' "$D/reaper.log"
}

@test "Gap-3 suspend-guard: a normal sweep (no suspend) still reaps a valid candidate (no over-block)" {
  local NOW=1900000000
  export CC_REAPER_NOW_FILE="$D/now"; echo "$NOW" > "$D/now"
  export CC_REAPER_BEAT_FILE="$D/beat"; echo "$((NOW-60))" > "$D/beat"
  export CC_REAPER_SUSPEND_S=900
  mock_classify_handoff "$D/clean" 9999 yes PANE-A
  run "$R" sweep --reap
  [ "$status" -eq 0 ]
  td_called
  grep -q 'PANE-A' "$D/td-calls"
}

@test "Gap-3 suspend-guard: --reap writes the sweep-end heartbeat; DRY-RUN writes none" {
  local NOW=1900000000
  export CC_REAPER_NOW_FILE="$D/now"; echo "$NOW" > "$D/now"
  export CC_REAPER_BEAT_FILE="$D/beat"; rm -f "$D/beat"
  mock_classify active "$D/clean" 5 no PANE-Z
  run "$R" sweep                                # DRY-RUN → writes nothing
  [ "$status" -eq 0 ]
  [ ! -f "$D/beat" ]
  run "$R" sweep --reap                         # --reap → heartbeat = this sweep's clock (durable)
  [ "$status" -eq 0 ]
  [ "$(cat "$D/beat")" = "$NOW" ]
}

# ── safeguard-blocked disposition (2026-07-25): SURFACE (originator page + board row + desk page),
#    NEVER reap; auto-recovery is OPT-IN (default OFF). Refusal text carries apostrophes → the mock
#    classify writes JSON via jq --arg to a file (never bakes the text into a single-quoted jq string).
mock_classify_safeguard() { # [pane] [cwd] [model] [refusal]
  local pane="${1:-$WPANE}" cwd="${2:-x}" model="${3:-Fable 5}" \
        refusal="${4:-API Error: Fable 5's safeguards flagged this message. Claude Code can't respond to this request with Fable 5.}"
  jq -nc --arg p "$pane" --arg c "$cwd" --arg m "$model" --arg r "$refusal" \
    '[{name:"peer",paneUUID:$p,account:"claude-quaternary",cwd:$c,cause:"safeguard-blocked",idle_s:200,work_landed:"na",blocked_model:$m,refusal:$r,successor:null,detail:"model safeguards refused"}]' > "$D/classify.json"
  printf '#!/bin/bash\ncat "%s"\n' "$D/classify.json" > "$D/bin/classify"
  chmod +x "$D/bin/classify"; export CC_REAPER_CLASSIFY_BIN="$D/bin/classify"
}
set_recover() { printf '#!/bin/bash\necho "RECOVER $*" >> "%s"\n' "$D/recover-calls" > "$D/bin/recover"
                chmod +x "$D/bin/recover"; export CC_REAPER_RECOVER_BIN="$D/bin/recover"; }

@test "safeguard-blocked --reap → SURFACED not reaped: originator paged, desk paged, board row, recover cmd" {
  mock_classify_safeguard "$WPANE" "$D/clean"; mark_fired "$WPANE"; set_desk
  run "$R" sweep --reap
  [ "$status" -eq 0 ]
  ! td_called || false                                     # NEVER reaped
  grep -q '"kind":"safeguard-blocked"' "$D/idl.jsonl"      # blockers-board row
  grep -q "NOTIFY t .*SAFEGUARD-BLOCKED" "$D/notify-calls" # ORIGINATOR (firedBy=t) paged
  grep -q "cc-recover-safeguard $WPANE" "$D/notify-calls"  # recovery command surfaced
  grep -q 'REAPER SURFACE' "$D/notify-calls"               # desk paged too
}

@test "safeguard-blocked — auto-recovery is OFF by default (helper NOT invoked)" {
  mock_classify_safeguard "$WPANE" "$D/clean"; mark_fired "$WPANE"; set_desk; set_recover
  run "$R" sweep --reap                                    # CC_REAPER_SAFEGUARD_AUTORECOVER unset → 0
  [ "$status" -eq 0 ]
  [ ! -f "$D/recover-calls" ]                              # surface-only; desk decides
}

@test "safeguard-blocked — auto-recovery ON (opt-in) invokes the helper with the pane + --execute" {
  mock_classify_safeguard "$WPANE" "$D/clean"; mark_fired "$WPANE"; set_desk; set_recover
  export CC_REAPER_SAFEGUARD_AUTORECOVER=1
  run "$R" sweep --reap
  [ "$status" -eq 0 ]
  grep -q "RECOVER $WPANE --execute" "$D/recover-calls"
}

@test "safeguard-blocked — DRY-RUN sweep sends nothing (would-surface only)" {
  mock_classify_safeguard "$WPANE" "$D/clean"; mark_fired "$WPANE"; set_desk
  run "$R" sweep                                           # no --reap
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi 'WOULD-SURFACE.*safeguard-blocked'
  [ ! -f "$D/notify-calls" ]                               # nothing paged
  [ ! -f "$D/idl.jsonl" ]                                  # no board row
}

@test "safeguard-blocked — no firedBy marker: desk + board still surface (no originator page, no crash)" {
  mock_classify_safeguard "$WPANE" "$D/clean"; set_desk    # NO mark_fired → no firedBy originator
  run "$R" sweep --reap
  [ "$status" -eq 0 ]
  ! td_called || false
  grep -q '"kind":"safeguard-blocked"' "$D/idl.jsonl"      # board row still written
  grep -q 'REAPER SURFACE' "$D/notify-calls"               # desk still paged
}

# ── single-instance sweep lock ───────────────────────────────────────────────────────────────────
# A --reap sweep can outrun its own launchd StartInterval; unserialized, the ticks overlapped and
# CONTENDED, so each overlap made the next sweep slower (measured 291s → 1534s, up to 5 concurrent).
# These pin the two properties that matter: overlap is impossible, and no lock state can ever wedge
# the reaper into permanent dormancy (which would silently stop ALL reaping — a worse failure).

# stamp a lock as held by <pid>, pinned with that pid's REAL lstart (what a true holder writes)
hold_lock() { mkdir -p "$CC_REAPER_LOCKDIR"; printf '%s\n' "$1" > "$CC_REAPER_LOCKDIR/pid"
              ps -o lstart= -p "$1" 2>/dev/null | tr -s ' ' | sed 's/^ *//;s/ *$//' > "$CC_REAPER_LOCKDIR/lstart"; }

@test "sweep lock: a second sweep SKIPS while a live holder owns the tick (never overlaps)" {
  mock_classify active "$D/clean" 10 no PANE-1
  sleep 60 & local holder=$!
  hold_lock "$holder"
  run "$R" sweep --reap
  kill "$holder" 2>/dev/null || true
  [ "$status" -eq 0 ]                                  # a skip is a normal tick, NOT a launchd failure
  echo "$output" | grep -q 'skipping this tick'
  echo "$output" | grep -qv 'classified' || true
  [ ! -f "$D/td-calls" ]                               # skipped => did no work at all
}

@test "sweep lock: a DEAD holder's lock is broken, the sweep proceeds (a crash cannot dormant it)" {
  mock_classify active "$D/clean" 10 no PANE-1
  mkdir -p "$CC_REAPER_LOCKDIR"; printf '999998\n' > "$CC_REAPER_LOCKDIR/pid"
  printf 'Fri Jan  1 00:00:00 2027\n' > "$CC_REAPER_LOCKDIR/lstart"
  touch -t 202601010000 "$CC_REAPER_LOCKDIR"           # age past the stamp grace
  run "$R" sweep --reap
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'classified'                # it ran, rather than skipping forever
  grep -q 'breaking' "$D/reaper.log"
}

@test "sweep lock: a RECYCLED pid (alive, WRONG lstart) is not a live holder (no permanent dormancy)" {
  mock_classify active "$D/clean" 10 no PANE-1
  sleep 60 & local other=$!                            # a real live process that is NOT our sweep
  mkdir -p "$CC_REAPER_LOCKDIR"; printf '%s\n' "$other" > "$CC_REAPER_LOCKDIR/pid"
  printf 'Thu Jan  1 00:00:00 2000\n' > "$CC_REAPER_LOCKDIR/lstart"   # pin cannot match
  touch -t 202601010000 "$CC_REAPER_LOCKDIR"
  run "$R" sweep --reap
  kill "$other" 2>/dev/null || true
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'classified'                # kill -0 alone would have skipped here forever
}

@test "sweep lock: an UNSTAMPED fresh lock is a racer mid-acquire — skipped, never broken" {
  mock_classify active "$D/clean" 10 no PANE-1
  mkdir -p "$CC_REAPER_LOCKDIR"                        # no pid file yet, dir just created
  # Pin the grace WIDE: what's under test is the SKIP behavior for an unstamped lock inside the
  # grace, not the 5s default. Under load >5s can elapse between the mkdir above and the reaper's
  # age check, which flips this into the break branch and fails a correct implementation.
  CC_REAPER_LOCK_STAMP_GRACE_S=60 run "$R" sweep --reap
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'skipping this tick'
  [ -d "$CC_REAPER_LOCKDIR" ]                          # the racer's lock survived (else BOTH would run)
}

@test "sweep lock: an unstamped lock PAST the stamp grace is stale — broken, sweep proceeds" {
  mock_classify active "$D/clean" 10 no PANE-1
  mkdir -p "$CC_REAPER_LOCKDIR"                        # same fixture: unstamped, no pid file
  # ...and grace=0 makes ANY unstamped lock past the window, deterministically (no clock dependence).
  # The companion branch to the test above: the grace must be a WINDOW, not a permanent exemption —
  # an unstamped lock left behind by a crashed racer must never dormant the reaper forever.
  CC_REAPER_LOCK_STAMP_GRACE_S=0 run "$R" sweep --reap
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'classified'                # it broke the lock and did the work
  grep -q 'sweep lock: stale (pid=none' "$D/reaper.log"
}

@test "sweep lock: a HUNG holder past LOCK_MAX_AGE_S is broken (liveness alone cannot wedge it)" {
  mock_classify active "$D/clean" 10 no PANE-1
  sleep 60 & local holder=$!
  hold_lock "$holder"                                  # genuinely alive AND correctly pinned
  touch -t 202601010000 "$CC_REAPER_LOCKDIR"           # ...but holding far past the max age
  CC_REAPER_LOCK_MAX_AGE_S=60 run "$R" sweep --reap
  kill "$holder" 2>/dev/null || true
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'classified'
}

@test "sweep lock: released when the sweep ends (the next tick is never blocked by the last)" {
  mock_classify active "$D/clean" 10 no PANE-1
  run "$R" sweep --reap
  [ "$status" -eq 0 ]
  [ ! -d "$CC_REAPER_LOCKDIR" ]
  run "$R" sweep --reap                                # and the very next tick runs for real
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'classified'
}

# ── the lock binds --reap ONLY ────────────────────────────────────────────────────────────────────
# A DRY-RUN writes nothing (reconcile / backlog-reap / inbox-guard are all --reap-gated), so it has
# no state to race on. Gating it was wrong in BOTH directions: a human running the diagnostic would
# suppress a real reap tick for its duration, and the diagnostic went unavailable during exactly the
# long sweep that prompted it. These pin both halves so neither can regress.

@test "sweep lock: a DRY-RUN does not take the lock (it cannot suppress a real reap tick)" {
  mock_classify active "$D/clean" 10 no PANE-1
  run "$R" sweep                                       # no --reap
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'classified'                # it really ran
  [ ! -d "$CC_REAPER_LOCKDIR" ]                        # ...and never created the lock
}

@test "sweep lock: a DRY-RUN runs even while a live --reap holds the lock (diagnostic stays usable)" {
  mock_classify active "$D/clean" 10 no PANE-1
  sleep 60 & local holder=$!
  hold_lock "$holder"                                  # a live, correctly-pinned --reap holder
  run "$R" sweep                                       # the diagnostic must NOT skip
  kill "$holder" 2>/dev/null || true
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'classified'
  [ -d "$CC_REAPER_LOCKDIR" ]                          # and it left the holder's lock untouched
}

# ── GARBAGE ARM (2026-08-07, the load-781 incident) — fully fixture-driven: PS_A/PS_B replace
# the live process table, CC_REAPER_GARBAGE_KILL collects instead of killing, and the watchdog
# store is relocated. The fixture is a CLOSED world, so the exact-set assertion is the right
# one here (nothing outside the table can appear).

mk_garbage_fixtures() {
  GA="$D/gs_ps_a.txt"; GB="$D/gs_ps_b.txt"; KLOG="$D/gs_kills.log"
  cat > "$D/gs-killer" <<'EOF'
#!/bin/bash
printf '%s %s %s\n' "$3" "$1" "$2" >> "$KILL_LOG"
EOF
  chmod +x "$D/gs-killer"
  mkdir -p "$D/gs-wd"
  export CC_REAPER_GARBAGE_PS_A="$GA" CC_REAPER_GARBAGE_PS_B="$GB" \
         CC_REAPER_GARBAGE_KILL="$D/gs-killer" KILL_LOG="$KLOG" \
         CC_REAPER_WATCHDOG_DIR="$D/gs-wd"
  : > "$KLOG"
  # pid ppid etime ucomm — the closed world. 9xxxx pids never exist on the host, so the KILL
  # escalation pass (which does a REAL kill -0 existence check) skips them by construction.
  cat > "$GA" <<'EOF'
90001 1 25:00 ps
90002 1 00:30 ps
90003 1 45:00 zsh
90004 1 45:00 zsh
90014 90004 20:00 claude.exe
90005 1 45:00 bash
90006 1 45:00 bash
90007 555 40:00 bash
90008 556 40:00 bash
90018 90008 39:00 claude.exe
90013 1 45:00 bash
EOF
  cat > "$GB" <<'EOF'
90001 ps -A -o pid= -o ppid=
90002 ps -A -o pid= -o ppid=
90003 -zsh
90004 -zsh
90014 /Users/x/.claude-220/node_modules/.bin/claude --model m
90005 bash /Users/x/Development/claude-infrastructure/scripts/lead-supervisor.sh --daemon
90006 bash /Users/x/.claude/hooks/session-register.sh
90007 bash /Users/x/.claude/bin/cc-close-attrib /Users/x/.claude-220/node_modules/.bin/claude --model m
90008 bash /Users/x/.claude/bin/cc-close-attrib /Users/x/.claude-220/node_modules/.bin/claude --model m
90018 /Users/x/.claude-220/node_modules/.bin/claude --model m
90013 bash /Users/x/.claude/hooks/lead-crash-watchdog.sh
EOF
}

@test "garbage --reap: exactly the residue dies — orphan ps/zsh/bash + stuck wrapper; nothing protected" {
  mk_garbage_fixtures
  # dead-lead watchdog: lead 999999 is dead by construction; the daemon pid must be LIVE for the
  # arm to bother. A CHILD we spawn, never "$$": this test's own pid is an ANCESTOR of the sweep it
  # is about to run, and the arm now refuses those outright (see the ancestor case below), so
  # asserting a TERM on "$$" would from here on assert the guard is broken.
  sleep 120 & GSPID=$!
  printf '%s' "$GSPID" > "$D/gs-wd/sid-a.daemon"; printf '999999' > "$D/gs-wd/sid-a.pid"
  # a watchdog whose daemon is ALREADY dead must be ignored (nothing to reap)
  printf '999998' > "$D/gs-wd/sid-b.daemon"; printf '999997' > "$D/gs-wd/sid-b.pid"
  run "$R" garbage --reap
  kill "$GSPID" 2>/dev/null || true
  [ "$status" -eq 0 ]
  # exact TERM set over the closed world:
  #   90001 orphan-ps (25:00 ≥ 60s) · 90003 orphan-zsh (no claude below) ·
  #   90006 orphan-bash (not whitelisted) · 90007 stuck-wrapper (no live claude child) · the child watchdog
  # and the protections each have a twin candidate that must NOT appear:
  #   90002 too-young ps · 90004 zsh WITH a live claude child · 90005 whitelisted daemon ·
  #   90008 wrapper WITH a live claude child · 90013 the watchdog class is file-driven, never argv-driven
  got_terms="$(awk '$1=="TERM"{print $2}' "$KLOG" | sort -n | tr '\n' ' ')"
  want_terms="$(printf '%s\n' 90001 90003 90006 90007 "$GSPID" | sort -n | tr '\n' ' ')"
  [ "$got_terms" = "$want_terms" ]
  # the KILL escalation reached only the one pid that truly exists (the child)
  ! awk '$1=="KILL"{print $2}' "$KLOG" | grep -qvx "$GSPID"
}

# ── THE ANCESTOR GUARD (2026-08-15, backlog 8efd655b0fe1). The kill discipline enumerates what must
# not be touched by IDENTITY — claude, kitty, a whitelisted daemon — and every clause names somebody
# else. Nothing said "not the tree we are running inside", and the classifier selects on SHAPE: on a
# GitHub Actions macOS runner the service is a launchd-parented `/bin/bash .../runsvc.sh`, i.e.
# textbook `orphan-bash`, and tests/reap-sweep-bounds.bats killed the runner out from under its own
# job in 6 of 6 cut shards. The pair below is one mechanism proved in both directions: identical
# candidate shape, and the ONLY difference is whether the pid is in this sweep's own pid chain.
@test "garbage: an ANCESTOR of the sweep is REFUSED, and a same-shaped non-ancestor is not" {
  mk_garbage_fixtures
  # sid-anc: this test's pid — an ancestor of the cc-reaper the next line runs. MUST be refused.
  printf '%s' "$$" > "$D/gs-wd/sid-anc.daemon"; printf '999999' > "$D/gs-wd/sid-anc.pid"
  # sid-ctl: a child we spawn — same class, same fixture shape, NOT an ancestor. MUST be signalled.
  sleep 120 & GSPID=$!
  printf '%s' "$GSPID" > "$D/gs-wd/sid-ctl.daemon"; printf '999998' > "$D/gs-wd/sid-ctl.pid"
  run "$R" garbage --reap
  kill "$GSPID" 2>/dev/null || true
  [ "$status" -eq 0 ]
  # the control fired — without this the refusal below could be a fixture that reaches nothing
  awk '$1=="TERM"{print $2}' "$KLOG" | grep -qx "$GSPID" || {
    echo "the NON-ancestor control was never signalled — the fixture proves nothing"; return 1; }
  # and the ancestor never reached the actuator's collector at all
  if awk '{print $2}' "$KLOG" | grep -qx "$$"; then
    echo "the sweep signalled its own ancestor $$ — the CI-runner kill is back"; return 1
  fi
}

# ── THE LAND PATH IS NEVER GARBAGE (2026-08-16, the SIGTERM-143 land bleed). `ship-land.sh` reported
# `verdict=killed signal=SIGTERM` on every re-land retry of 6 branches for 5 days — 543
# refs/land/failed pins since 2026-08-10 — and the killer was this arm: a backgrounded
# `handoff-fire.sh land …` is a launchd-parented bash that outruns the 600 s floor on any real gate,
# and neither land script carried a whitelist token. The pair below is the mechanism in both
# directions in ONE closed world, so the exemption cannot quietly widen into "the arm collects
# nothing": the two land shapes must survive AND the unrelated orphan beside them must still die.
@test "garbage: an in-progress land is never collected, and an unrelated orphan beside it still is" {
  mk_garbage_fixtures
  cat > "$GA" <<'EOF'
90101 1 45:00 bash
90102 1 45:00 bash
90103 1 45:00 bash
EOF
  cat > "$GB" <<'EOF'
90101 bash scripts/ship-land.sh
90102 /bin/bash /Users/x/.claude/scripts/desk-land.sh --branch claude/fire-20260812T120520Z-80623-1
90103 /bin/bash /Users/x/some/unrelated/orphan.sh
EOF
  run "$R" garbage --reap
  [ "$status" -eq 0 ]
  got="$(awk '$1=="TERM"{print $2}' "$KLOG" | sort -n | tr '\n' ' ')"
  # the control (90103) fired, so the fixture reaches the actuator; the two lands did not.
  [ "$got" = "90103 " ]
}

# ── THE PID THAT CHANGED HANDS (2026-08-16). The kill-time re-verification checked `ucomm` only, and
# orphan-bash / stuck-wrapper / dead-lead-watchdog all carry the ERE `^bash$` — so for the three
# classes that dominate the candidate set it asked "is this a bash?" of a pid it had already decided
# was a bash, and every recycled pid running a shell script answered yes. This box allocates ~40
# pids/s and wraps the whole 99999-pid space in ~41 min while a sweep forks a `/bin/ps -p` per
# candidate between snapshot and signal, which is how lands died at 7 s under a 600 s floor.
#
# These two run the REAL actuator — CC_REAPER_GARBAGE_KILL is unset, because the collector seam
# short-circuits ahead of the argv check and a test that kept it would assert nothing. One closed
# world, one live victim, and the ONLY difference between the pair is whether the recorded argv is
# still the argv the pid carries.
@test "garbage: a candidate whose argv changed under it (pid reuse) is REFUSED, not signalled" {
  mk_garbage_fixtures
  unset CC_REAPER_GARBAGE_KILL
  : > "$CC_REAPER_LOG"
  bash -c 'sleep 300; true' & VICTIM=$!
  printf '%s 1 45:00 bash\n' "$VICTIM" > "$GA"
  printf '%s /bin/bash /Users/x/.claude/a-long-dead-orphan.sh\n' "$VICTIM" > "$GB"
  run "$R" garbage --reap
  [ "$status" -eq 0 ]
  alive=0; kill -0 "$VICTIM" 2>/dev/null || alive=1
  kill "$VICTIM" 2>/dev/null || true
  [ "$alive" -eq 0 ]                      # it SURVIVED — the wrong process was not killed
  grep -q "REFUSED TERM $VICTIM — argv no longer matches" "$CC_REAPER_LOG"
}

@test "garbage: …and the same candidate carrying its REAL argv is still signalled (control)" {
  mk_garbage_fixtures
  unset CC_REAPER_GARBAGE_KILL
  bash -c 'sleep 300; true' & VICTIM=$!
  printf '%s 1 45:00 bash\n' "$VICTIM" > "$GA"
  printf '%s %s\n' "$VICTIM" "$(/bin/ps -p "$VICTIM" -o args= | sed 's/^ *//')" > "$GB"
  run "$R" garbage --reap
  [ "$status" -eq 0 ]
  # give the TERM a moment to be delivered before asking. `alive` is assigned through `||` rather
  # than from `$?`: under bats a bare failing command IS the test failure, so `kill -0` on the
  # corpse this test wants would abort before the assertion it exists to make.
  sleep 1
  alive=0; kill -0 "$VICTIM" 2>/dev/null || alive=1
  kill -9 "$VICTIM" 2>/dev/null || true
  [ "$alive" -eq 1 ]                      # it DIED — so the refusal above is a real discrimination
}

@test "garbage DRY-RUN reports the refusal too — the two modes may not disagree" {
  mk_garbage_fixtures
  printf '%s' "$$" > "$D/gs-wd/sid-anc.daemon"; printf '999999' > "$D/gs-wd/sid-anc.pid"
  run "$R" garbage
  [ "$status" -eq 0 ]
  # A dry run that printed "would reap" over a pid REAP refuses is a false report of what happens.
  echo "$output" | grep -q "REFUSED — this sweep runs inside it.*pid=$$" || {
    echo "dry-run did not mark the ancestor as refused: $output"; return 1; }
  # An `A && { …; return 1; }` here is DEAD under errexit (the gate's dead-assertion ratchet names
  # it [and-absorbed], and bats-assert-liveness-fix.py declines this shape rather than guess), so
  # the negative half is written as an if-statement, which consumes the status instead of absorbing
  # it. Proven live in both directions by a mutant that prints BOTH strings — see the commit.
  if echo "$output" | grep -q "would reap.*pid=$$"; then
    echo "dry-run still offers to reap the ancestor"; return 1
  fi
}

@test "garbage DRY-RUN: prints the would-reap set, kills nothing" {
  mk_garbage_fixtures
  run "$R" garbage
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'would reap.*orphan-ps pid=90001'
  echo "$output" | grep -q 'would reap.*stuck-wrapper pid=90007'
  [ ! -s "$KLOG" ]                                     # the collector was never invoked
}

@test "garbage: CC_REAPER_GARBAGE=0 kill switch disables the arm" {
  mk_garbage_fixtures
  CC_REAPER_GARBAGE=0 run "$R" garbage --reap
  [ "$status" -eq 0 ]
  [ ! -s "$KLOG" ]
}

@test "garbage: unavailable snapshot fails OPEN (arm skipped, rc 0, nothing killed)" {
  mk_garbage_fixtures
  rm -f "$GA" "$GB"
  run "$R" garbage --reap
  [ "$status" -eq 0 ]
  [ ! -s "$KLOG" ]
}

@test "sweep runs the garbage arm FIRST (before classify), same reap gate" {
  mk_garbage_fixtures
  mock_classify active "$D/clean" 10 no PANE-1
  run "$R" sweep                                       # DRY-RUN sweep
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'garbage arm:'              # the arm reported inside the sweep
  [ ! -s "$KLOG" ]                                     # and a DRY-RUN sweep killed nothing
}

@test "classify bound-fire retries ONCE at 3x — the bound must fit the band, not the bench" {
  # first call sleeps past the 1s bound (rc 124); the retry answers instantly. Pre-fix the sweep
  # failed closed on the FIRST 124 — every load-781 sweep read "NO candidates" at exactly the
  # moment reaping mattered most.
  cnt="$D/cls-count"; : > "$cnt"
  cat > "$D/cls" <<EOF
#!/bin/bash
echo x >> "$cnt"
if [ "\$(wc -l < "$cnt" | tr -d ' ')" -eq 1 ]; then sleep 2; fi
echo '[]'
EOF
  chmod +x "$D/cls"
  export CC_REAPER_CLASSIFY_BIN="$D/cls" CC_REAPER_CLASSIFY_TIMEOUT_S=1
  export CC_REAPER_GARBAGE_PS_A=/dev/null CC_REAPER_GARBAGE_PS_B=/dev/null   # pin the arm cheap
  run "$R" sweep
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$cnt" | tr -d ' ')" -eq 2 ]            # bound fired once, the retry actually ran
  echo "$output" | grep -q 'classified'                # and the sweep completed on the retry's verdict
}

# ── task-less (2026-08-08): the booted-but-brief-less pane ────────────────────────────────────────
# cc-classify used to answer `active` for a pane that started claude and never produced an assistant
# turn. `active` is in NEITHER regex here, so such a pane was never reaped AND never paged — it just
# persisted with no board row. The fix routes it to a NEW cause that is surfaced only. These tests pin
# BOTH halves, because the value of the fix is entirely in the second one holding forever.

@test "task-less pages the desk (the blind spot's whole fix: an empty pane finally gets a board row)" {
  set_desk
  mock_classify task-less "$D/clean" 7200 yes PANE-TL
  run "$R" sweep --reap
  ! td_called || false
  notified
  grep -q 'task-less' "$D/notify-calls"
}

@test "task-less is NEVER reaped — landed, idle far past settle, --reap, and still no teardown" {
  # Every gate a reapable cause would clear is deliberately satisfied here: work landed, idle 99999s
  # (>> settle), --reap armed, desk wired. The ONLY thing standing between this pane and a teardown is
  # its absence from REAPABLE_RE. Killing a live session on a wrong verdict is the destructive path this
  # item explicitly declined to open, so this test is the contract that it stays closed.
  set_desk
  mock_classify task-less "$D/clean" 99999 yes PANE-TL
  run "$R" sweep --reap
  ! td_called || false
}

@test "task-less is not promotable either — a fired-peer stamp must not turn it into an auto-reap" {
  # AUTOREAP_FIRED_RE promotes a surfaced cause to reapable when the spawner stamped the pane. A
  # task-less pane is very often exactly such a stamped worker (a fire that landed a pane but no brief),
  # so this is the realistic path by which a never-reap cause could quietly acquire a teardown.
  set_desk; mark_fired "PANE-TL"
  mock_classify task-less "$D/clean" 99999 yes PANE-TL
  run "$R" sweep --reap
  ! td_called || false
  notified
}

@test "REAPABLE_RE / AUTOREAP_FIRED_RE do not name task-less; SURFACE_PAGE_RE does (structural)" {
  grep -q "^REAPABLE_RE=.*handed-off-lead" "$R"                 # anchor: the line still exists as expected
  ! grep -E '^(REAPABLE_RE|AUTOREAP_FIRED_RE)=' "$R" | grep -q 'task-less' || false
  grep -E '^SURFACE_PAGE_RE=' "$R" | grep -q 'task-less'
}
