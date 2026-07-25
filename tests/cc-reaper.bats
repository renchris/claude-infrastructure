#!/usr/bin/env bats
# cc-reaper — RED-proof the disposition: a reap needs cause∈{handed-off-lead,finished-teammate} AND
# work-landed AND idle>=settle AND --reap; checkpoint runs BEFORE teardown; a post-classify dirty tree
# aborts the reap (WIP checkpointed); every never-reap cause is left untouched. Mocks classify/teardown/
# checkpoint; uses REAL temp git repos so the work-landed re-check is exercised for real.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  R="$REPO/bin/cc-reaper"
  D="$BATS_TEST_TMPDIR"; mkdir -p "$D/bin"
  # real git repos: clean+shipped (landed) and dirty (not landed)
  mkrepo() { local r="$1"; mkdir -p "$r"; git -C "$r" init -q; git -C "$r" config user.email t@t; git -C "$r" config user.name t
             echo a > "$r/f"; git -C "$r" add f; git -C "$r" commit -qm c1
             git -C "$r" update-ref refs/remotes/origin/main HEAD; }
  # squash-landed: clean tree, HEAD 1 ahead by COUNT, but content already on origin/main (different sha)
  mksquashland() { local r="$1"; mkdir -p "$r"; git -C "$r" init -q
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
  cat > "$D/bin/notify" <<EOF
#!/bin/bash
printf 'NOTIFY %s\n' "\$*" >> "$D/notify-calls"
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
  local m="$1" w="$2"
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
