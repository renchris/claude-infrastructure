#!/usr/bin/env bats
# hooks/live-session-registry.sh — the row must be written ATOMICALLY (a15/D5).
#
# WHY THIS SUITE EXISTS. The register path wrote `printf … > "$REG_DIR/$base"`. `>` is O_TRUNC: the
# file is emptied by one syscall and refilled by a later one. worktree-gc reads that row with
# `cut -f2` to get the session's pid; a read landing in the gap yields an empty pid, `kill -0 ""`
# fails, and a LIVE session's worktree is classified dead and REAPED. The file's own header says it
# exists to eliminate exactly that single-bad-read flakiness — so the non-atomic write re-introduced
# the bug it was written to kill, at one-printf width.
#
# WHAT IS ASSERTED, and why the main assertion is the INODE. A true interleaving race is not
# deterministically reproducible from a shell, so proving "no reader ever sees the gap" by racing is
# probabilistic (test 4 does hammer it, and is honest about being a probabilistic backstop). The
# DETERMINISTIC property is the one that makes the gap structurally impossible: the target must be
# replaced by an atomic RENAME, never modified in place. A rename swaps in a different file, so the
# target's inode CHANGES; a truncate-write keeps the same inode. Inode-change is therefore a direct,
# non-flaky witness of the mechanism — and it goes RED against the pre-fix line (verified by
# reverting the fix and re-running: test 2 fails with identical inodes).
#
# Hermetic: $HOME is fixtured (REG_DIR and the reapable-worktree gate are both $HOME-derived), so no
# real ~/.reso state is read or written.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HOOK="$REPO/hooks/live-session-registry.sh"
  export HOME="$BATS_TEST_TMPDIR/home"
  WT="$HOME/Development/.worktrees/wt-testbed"
  REG="$HOME/.reso/live-sessions"
  mkdir -p "$WT" "$REG"
  # The tenancy gate journals refusals. $HOME is already fixtured, so the default IDL path is
  # inside the fixture — pinned explicitly anyway, so a later default change cannot leak the
  # suite's writes into the operator's live ~/.claude/autonomy/idl.jsonl.
  export CC_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
}

# fire the hook as SessionStart for the fixtured worktree
fire() { # $1=sid
  printf '{"hook_event_name":"SessionStart","cwd":"%s","session_id":"%s"}' "$WT" "${1:-sid-1}" \
    | bash "$HOOK"
}

# fire with NO session_id at all — the degraded input where the key falls back to the bare
# basename. `env -u` is not usable here (the field is in stdin, not the environment), so the
# JSON is built without the key rather than with an empty one: `// empty` treats them alike,
# but an absent field is the shape a producer that never learned about sids actually emits.
fire_nosid() {
  printf '{"hook_event_name":"SessionStart","cwd":"%s"}' "$WT" | bash "$HOOK"
}

# THE KEY UNDER TEST (E14): one row per SESSION, not per worktree. Every path assertion below goes
# through this, so a future key change fails in one place instead of eight.
key() { printf '%s-%s' "wt-testbed" "${1:0:8}"; }

inode() { ls -i "$1" 2>/dev/null | awk '{print $1}'; }

@test "1: register writes the row (pid, sid, cwd) — the fix did not break the write" {
  fire "sid-alpha"
  [ -f "$REG/$(key sid-alpha)" ] || { echo "no registry row at $(key sid-alpha); dir: $(ls -A "$REG")"; false; }
  run cut -f2 "$REG/$(key sid-alpha)"
  [ "$output" = "sid-alpha" ] || { echo "sid field: got '$output'"; false; }
  run cut -f3 "$REG/$(key sid-alpha)"
  [ "$output" = "$WT" ] || { echo "cwd field: got '$output'"; false; }
  # field 1 is the claude-ancestor pid; under bats there is no claude ancestor, so it falls back to
  # $PPID — assert only that it is a non-empty integer, which is what `kill -0` consumes.
  run cut -f1 "$REG/$(key sid-alpha)"
  [[ "$output" =~ ^[0-9]+$ ]] || { echo "pid field not an integer: '$output'"; false; }
}

@test "2: a re-register REPLACES the row by rename (inode changes) — never truncates in place" {
  # SAME sid both times: after E14 the key carries the sid, so two DIFFERENT sids write two
  # different files and would never exercise replacement at all. One session re-registering
  # (SessionStart / Resume / Clear all fire this hook) is the real in-place-write path.
  fire "sid-first"
  local i1 i2
  i1="$(inode "$REG/$(key sid-first)")"
  [ -n "$i1" ] || { echo "could not stat the first row"; false; }
  fire "sid-first"
  i2="$(inode "$REG/$(key sid-first)")"
  [ -n "$i2" ] || { echo "could not stat the second row"; false; }
  # THE DISCRIMINATOR: same inode ⇒ the file was modified in place ⇒ an O_TRUNC gap exists ⇒ the
  # reaper can read an empty pid. Different inode ⇒ atomic rename ⇒ readers see old or new, never
  # partial. RED-proven: with `> "$REG_DIR/$base"` restored, i1 == i2 and this test fails.
  [ "$i1" != "$i2" ] || {
    echo "row was written IN PLACE (inode $i1 unchanged) — O_TRUNC gap present, reader can see an empty pid"
    false
  }
  run cut -f2 "$REG/$(key sid-first)"
  [ "$output" = "sid-first" ] || { echo "replacement row wrong: '$output'"; false; }
}

@test "3: no .tmp litter is left behind in the registry dir" {
  fire "sid-x"; fire "sid-y"; fire "sid-z"
  # the tmp name is ".<base>.<pid>" — any survivor means a failure path leaked it
  run bash -c "ls -A '$REG' | grep -c '^\\.wt-testbed' || true"
  [ "$output" = "0" ] || { echo "leaked $output tmp file(s): $(ls -A "$REG")"; false; }
}

@test "4: a concurrent reader never observes an empty or partial row (probabilistic backstop)" {
  # Honest label: this is the real-world failure shape but it is NOT the deterministic proof —
  # test 2 is. Kept because it asserts the INVARIANT the reaper depends on (a row always has a
  # non-empty pid field), and it can only ever fail for a real reason.
  fire "sid-seed"
  local bad=0 i row
  row="$REG/$(key sid-seed)"
  # one sid throughout: post-E14 a varying sid writes a DIFFERENT file each time and the reader
  # below would poll a row nobody is racing on — green, and vacuous.
  ( for i in $(seq 1 40); do fire "sid-seed" >/dev/null 2>&1; done ) &
  local writer=$!
  for i in $(seq 1 200); do
    if [ -f "$row" ]; then
      p="$(cut -f1 "$row" 2>/dev/null)"
      case "$p" in ''|*[!0-9]*) bad=$((bad + 1)) ;; esac
    fi
  done
  wait "$writer" 2>/dev/null || true
  [ "$bad" -eq 0 ] || { echo "reader saw $bad empty/partial pid field(s) — the O_TRUNC gap is observable"; false; }
}

# ── TENANCY (backlog 55e1e65c7548) ─────────────────────────────────────────────────────────────
# The atomic-write tests above make the row impossible to read HALF-written. These make it
# impossible for a nested session to overwrite it WHOLE. A cwd is inherited by every child process,
# so a `claude -p` probe fired from inside a worktree session lands on this same row and used to
# replace the tenant's pid with its own — which is dead seconds later. worktree-gc's
# `registry_live()` then answers NOT-LIVE and the worktree falls back to the flaky cwd/lsof oracle
# this file's header exists to eliminate: one throwaway probe disarms the guard for its own session.

# helper: fire the hook as a NESTED claude. The outer tier seeds the row with its own pid (the
# tenant registering); the inner runs the hook (the probe squatting).
# `ln -s /bin/bash …/claude` gives a process whose `ps -o comm=` basename is `claude` — a COPY of
# /bin/bash does not execute on this box (measured; it fails silently, which would make the fixture
# pass vacuously). The trailing `:` defeats bash's last-command exec optimisation, which otherwise
# collapses both tiers onto ONE pid and the ancestry the test exercises silently does not exist.
nested_fire() { # $1=sid
  local fake="$BATS_TEST_TMPDIR/fake"; mkdir -p "$fake"; ln -sf /bin/bash "$fake/claude"
  cat > "$BATS_TEST_TMPDIR/outer.sh" <<'OUT'
printf '%s\t%s\t%s\n' "$$" "TENANT-SID" "$NF_WT" > "$HOME/.reso/live-sessions/wt-testbed"
"$NF_FAKE/claude" "$NF_INNER"
:
OUT
  cat > "$BATS_TEST_TMPDIR/inner.sh" <<'IN'
# NO session_id: after E14 a sid-bearing probe lands on its own key and could not overwrite the
# tenant even with the gate deleted, so passing one here would make tests 5 and 6 assert the gate
# over a case that never reaches it. This is the input shape where the gate is still load-bearing.
printf '{"hook_event_name":"SessionStart","cwd":"%s"}' "$NF_WT" | bash "$NF_HOOK"
:
IN
  NF_WT="$WT" NF_SID="${1:-}" NF_FAKE="$fake" NF_HOOK="$HOOK" \
    NF_INNER="$BATS_TEST_TMPDIR/inner.sh" "$fake/claude" "$BATS_TEST_TMPDIR/outer.sh"
}

@test "5: a nested claude does NOT overwrite its live parent's row (headless-probe squat)" {
  # GREEN PRE-FIX BY CONSTRUCTION — this is a PRESERVATION case, not red-proof: it asserts E14 did
  # not break the tenancy gate on the bare-key path it still owns. Its guarantee is carried by
  # mutant M4 (drop the ancestry refusal), not by failing before the fix.
  nested_fire
  run cut -f2 "$REG/wt-testbed"
  [ "$output" = "TENANT-SID" ] || { echo "row was stolen: $(cat "$REG/wt-testbed")"; false; }
}

@test "6: the tenancy refusal is journalled (a silent no-op reads as an inert gate)" {
  # PRESERVATION case (see test 5). Carried by mutant M5 (drop the IDL write).
  nested_fire
  [ -s "$CC_IDL" ] || { echo "no IDL record written"; false; }
  # `run grep` + `[ ]`, never `[[ ]]`: bash exempts the `[[` keyword from errexit, so a non-final
  # one evaluates and DISCARDS its false result (scripts/bats-assert-liveness.py, which caught it).
  run grep -Fc '"disposition":"refused"' "$CC_IDL"
  [ "$status" -eq 0 ]
  run grep -Fc '"hook":"live-session-registry"' "$CC_IDL"
  [ "$status" -eq 0 ]
}

@test "7: a live incumbent that is NOT an ancestor still writes (basename collision / pid reuse)" {
  # Two repos sharing ~/Development/.worktrees can produce the same basename (worktree-gc.sh:368),
  # and a stale row's pid can be recycled. Neither is our ancestor, so neither may wedge the row —
  # a gate that refused here would cause the reap this whole file exists to prevent.
  sleep 30 & local other=$!
  # seeded at the key THIS fire will write, so the incumbent is genuinely in the way; seeding the
  # bare key would make the test pass because the paths differ, proving nothing about the gate.
  printf '%s\t%s\t%s\n' "$other" "OTHER-SID" "$WT" > "$REG/$(key sid-mine)"
  fire "sid-mine"
  kill "$other" 2>/dev/null || true; wait "$other" 2>/dev/null || true
  run cut -f2 "$REG/$(key sid-mine)"
  [ "$output" = "sid-mine" ] || { echo "legitimate write was refused: $(cat "$REG/wt-testbed")"; false; }
}

@test "8: a dead-pid row still writes (the worktree's next session registers normally)" {
  sleep 30 & local gone=$!; kill "$gone" 2>/dev/null || true; wait "$gone" 2>/dev/null || true
  printf '%s\t%s\t%s\n' "$gone" "OLD-SID" "$WT" > "$REG/$(key sid-next)"
  fire "sid-next"
  run cut -f2 "$REG/$(key sid-next)"
  [ "$output" = "sid-next" ]
}

# ── E14: ONE ROW PER SESSION, NOT PER WORKTREE (headless-substrate spec 03, §4 A2) ──────────────
# A pooled worktree hosts several sessions. Measured on the live box 2026-08-19: wt-pool-2 and
# wt-pool-8 each carried TWO live `claude` procs whose PARENTS DIFFER — siblings, not the nested
# ancestry the tenancy gate above covers — so the second overwrote the first's row and the registry
# recorded one pid out of two. The unrecorded session then has no positive liveness proof: when the
# recorded pid exits, `registry_live()` answers NOT-LIVE for an OCCUPIED worktree and the reaper
# falls back to the flaky cwd/lsof oracle this whole file exists to eliminate.

# Extract the reaper's own oracle. It had NO test coverage before this change, and E14 is exactly
# the kind of change that must not be asserted only on the writer's side: a per-session key that no
# reader globs for is strictly WORSE than the bug it replaces.
load_registry_live() {
  local src="$REPO/scripts/worktree-gc.sh" tmp="$BATS_TEST_TMPDIR/reg.sh"
  {
    sed -n '/^canon() {/,/^}/p'         "$src"
    sed -n '/^registry_live() {/,/^}/p' "$src"
  } > "$tmp"
  # ANTI-VACUITY: a rename or reshape upstream would leave the extract EMPTY and every case below
  # would then pass over nothing at all (memory: stale sed range markers invert, they do not fail).
  grep -q '^canon() {'         "$tmp" || { echo "canon() not extracted from $src"; return 1; }
  grep -q '^registry_live() {' "$tmp" || { echo "registry_live() not extracted from $src"; return 1; }
  grep -q 'REGISTRY_DIR'       "$tmp" || { echo "extract never references REGISTRY_DIR"; return 1; }
  # Read by the registry_live() extract sourced on the next line — a use shellcheck cannot see
  # through a dynamic `.`, so the SC2034 here is instrument blindness, not a dead assignment.
  # shellcheck disable=SC2034
  REGISTRY_DIR="$REG"
  # shellcheck disable=SC1090
  . "$tmp"
}

@test "9: two sibling sessions on ONE pooled worktree each keep their OWN row" {
  fire "sid-aaaa1111"
  fire "sid-bbbb2222"
  [ -f "$REG/$(key sid-aaaa1111)" ] || {
    echo "the first session's row is gone — the second erased it; dir: $(ls -A "$REG")"; false; }
  [ -f "$REG/$(key sid-bbbb2222)" ] || { echo "the second session's row is missing"; false; }
  run cut -f2 "$REG/$(key sid-aaaa1111)"
  [ "$output" = "sid-aaaa1111" ] || { echo "first row carries the wrong sid: '$output'"; false; }
}

@test "10: one session's SessionEnd does not remove a SIBLING's row" {
  fire "sid-aaaa1111"
  fire "sid-bbbb2222"
  printf '{"hook_event_name":"SessionEnd","cwd":"%s","session_id":"%s"}' "$WT" "sid-bbbb2222" \
    | bash "$HOOK"
  [ -f "$REG/$(key sid-aaaa1111)" ] || {
    echo "a sibling's row was removed by ANOTHER session's SessionEnd — that session is now invisible"; false; }
  [ ! -f "$REG/$(key sid-bbbb2222)" ] || { echo "the ending session did not remove its own row"; false; }
}

@test "11: registry_live keeps a worktree whose only live row is SESSION-keyed" {
  load_registry_live
  sleep 30 & local live=$!
  printf '%s\t%s\t%s\n' "$live" "sid-aaaa1111" "$WT" > "$REG/$(key sid-aaaa1111)"
  run registry_live "wt-testbed" "$(cd "$WT" && pwd -P)"
  kill "$live" 2>/dev/null || true; wait "$live" 2>/dev/null || true
  [ "$status" -eq 0 ] || {
    echo "NOT-LIVE over a live session-keyed row: an OCCUPIED worktree is reapable"; false; }
}

@test "12: a DEAD sibling row does not condemn a worktree a LIVE row still occupies" {
  load_registry_live
  sleep 30 & local gone=$!; kill "$gone" 2>/dev/null || true; wait "$gone" 2>/dev/null || true
  sleep 30 & local live=$!
  # THE DEAD ROW SORTS FIRST (aaaa < dddd), deliberately. A glob expands in sorted order, so with
  # the live row first this case would pass just as well against a reader that stops at the first
  # row it finds — it would pin "some row is live", not "ANY row keeps the worktree". Mutant M6
  # (return on the first row regardless of liveness) is what proves this ordering is load-bearing.
  printf '%s\t%s\t%s\n' "$gone" "sid-aaaa1111" "$WT" > "$REG/$(key sid-aaaa1111)"
  printf '%s\t%s\t%s\n' "$live" "sid-dddd4444" "$WT" > "$REG/$(key sid-dddd4444)"
  run registry_live "wt-testbed" "$(cd "$WT" && pwd -P)"
  kill "$live" 2>/dev/null || true; wait "$live" 2>/dev/null || true
  [ "$status" -eq 0 ] || { echo "one dead row condemned a worktree that a live row occupies"; false; }
}

@test "13: a LEGACY bare-key row is still honoured (pre-fix rows AND the reso-side writer)" {
  # GREEN PRE-FIX BY CONSTRUCTION — a PRESERVATION case, not red-proof. It pins that widening the
  # read did not narrow it: ~/.reso/worktree-gc-run.sh:96 is a SECOND writer into this shared store,
  # in another repo, and it still keys bare, so the bare key is permanent, not a transition window.
  # Its guarantee is carried by mutant M2 (drop the bare key from the glob list).
  load_registry_live
  sleep 30 & local live=$!
  printf '%s\t%s\t%s\n' "$live" "scan" "$WT" > "$REG/wt-testbed"
  run registry_live "wt-testbed" "$(cd "$WT" && pwd -P)"
  kill "$live" 2>/dev/null || true; wait "$live" 2>/dev/null || true
  [ "$status" -eq 0 ] || {
    echo "a legacy bare-key row stopped counting — every pre-fix row and every reso-scanner row is now invisible"; false; }
}

@test "14: a PREFIX-neighbour's row cannot make an unoccupied worktree read live" {
  # GREEN PRE-FIX BY CONSTRUCTION (pre-fix there is no glob at all) — PRESERVATION, carried by
  # mutant M3 (drop the recorded-cwd check). This is the hazard the wider read introduces and the
  # reason the per-row cwd check is load-bearing rather than legacy: base "wt-pool" globs
  # "wt-pool-*", which MATCHES a session row belonging to the DIFFERENT worktree wt-pool-2.
  load_registry_live
  local nb="$HOME/Development/.worktrees/wt-pool-2" me="$HOME/Development/.worktrees/wt-pool"
  mkdir -p "$nb" "$me"
  sleep 30 & local live=$!
  printf '%s\t%s\t%s\n' "$live" "sid-neighbour" "$nb" > "$REG/wt-pool-2-sid-neig"
  run registry_live "wt-pool" "$(cd "$me" && pwd -P)"
  kill "$live" 2>/dev/null || true; wait "$live" 2>/dev/null || true
  [ "$status" -ne 0 ] || {
    echo "wt-pool read LIVE off wt-pool-2's row — the glob manufactured liveness for an empty worktree"; false; }
}

@test "15: with NO session_id the key falls back to the bare basename (degraded input)" {
  # The tenancy gate's remaining domain (tests 5/6) exists only because this fallback does.
  fire_nosid
  [ -f "$REG/wt-testbed" ] || { echo "no bare-key row; dir: $(ls -A "$REG")"; false; }
  run bash -c "ls -A '$REG' | grep -c '^wt-testbed-' || true"
  [ "$output" = "0" ] || { echo "a sid-suffixed row appeared with no sid in the input: $(ls -A "$REG")"; false; }
}
