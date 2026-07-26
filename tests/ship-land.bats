#!/usr/bin/env bats
# ship-land.sh — the fail-closed landing pipeline. Scratch bare "origin" + working clone
# in BATS_TEST_TMPDIR. NEVER pushes to a real origin. land-lock/land.log/decisions all
# redirected under BATS_TEST_TMPDIR so no real machine state is touched.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SHIPLAND="$REPO/scripts/ship-land.sh"

  ORIGIN="$BATS_TEST_TMPDIR/origin.git"
  WORK="$BATS_TEST_TMPDIR/work"
  git init -q --bare "$ORIGIN"
  git clone -q "$ORIGIN" "$WORK"
  cd "$WORK"
  git config user.email tester@example.com
  git config user.name tester
  git checkout -q -b main
  echo base > base.txt
  git add base.txt
  git commit -q -m base
  git push -q -u origin main

  export LAND_LOG="$BATS_TEST_TMPDIR/land.log"
  export LAND_LOCK_DIR="$BATS_TEST_TMPDIR/lock"
  export LAND_LOCK_WAIT=10
  export SHIP_LAND_DECISIONS_DIR="$BATS_TEST_TMPDIR/decisions"
  export SHIP_LAND_SHARED_CHECKOUT="$BATS_TEST_TMPDIR/nope"   # never matches the work repo
  export CLAUDE_CODE_SESSION_ID="test-sid-123"
  export POSTLAND_DIR="$BATS_TEST_TMPDIR/postland"            # flakes.jsonl + queue, sandboxed
  export POSTLAND_VERIFY=off                                  # never spawn a real post-land child
  # env-bleed immunity: when THIS suite runs inside an outer ship-land gate, the outer
  # pipeline's scope resolution must not leak into the fixture pipelines under test.
  # SHIP_LAND_GATE_ROUNDS / _VERIFY_RETRIES were the two gaps here, and the omission was
  # load-bearing: landing this branch with ship.md's own lock-starvation remedy
  # (SHIP_LAND_GATE_ROUNDS=0 — "run the gate INSIDE the lock") bled that 0 into every fixture
  # pipeline below, so "attest: UNLOCKED gate-red …" was asserting against a code path the outer
  # flag had deliberately disabled. Reproduced clean on an otherwise 46/46-green tree: ROUNDS=0 in
  # the outer env ⇒ 45 ok / 1 not ok; unset ⇒ 46 ok / 0 not ok. A verdict about the tree must never
  # be a function of how the operator tuned the land (ship-land.sh's gate_bats scrubs the same set
  # at the gate; this is the half that also holds when someone runs bats directly).
  unset SHIP_LAND_GATE_SCOPE SHIP_LAND_GATE_SCOPE_DEFAULT SHIP_LAND_GATE_POLICY \
        SHIP_LAND_GATE_SELECT SHIP_LAND_FIRST_BASE SHIP_LAND_GATE_EFFECTIVE_FULL \
        SHIP_LAND_SELECTED_N POSTLAND_STALENESS_GUARD \
        SHIP_LAND_GATE_ROUNDS SHIP_LAND_VERIFY_RETRIES 2>/dev/null || true
  # Admission control OFF for the whole suite. The full-mode fixtures below really do reach
  # run_bats_all → gate_admit, and this suite runs on exactly the loaded box that makes it defer;
  # left on, every such test stalls for CC_GATE_ADMIT_MAX_WAIT and the suite reads as hung. These
  # tests assert VERDICT logic, never shedding behaviour (that has its own dedicated tests below).
  export CC_GATE_MAX_LOAD=0
}

on_branch_with() {  # $1=branch $2=file $3=content  → commit a change on a fresh branch
  git checkout -q -b "$1" main
  printf '%s\n' "$3" > "$2"
  git add "$2"
  git commit -q -m "feat: $2"
}

@test "green: land end-to-end → exit 0, content on trunk, land.log verify:ok" {
  git checkout -q -b feat/green main
  printf '#!/usr/bin/env bash\necho "hello"\n' > hello.sh
  git add hello.sh && git commit -q -m "feat: hello"

  run bash "$SHIPLAND" --trunk main
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "LANDED"

  git fetch -q origin main
  [ -n "$(git ls-tree origin/main -- hello.sh)" ]         # content actually on trunk
  grep -q '"verify":"ok"' "$LAND_LOG"                     # self-attesting log
  grep -q '"sid":"test-sid-123"' "$LAND_LOG"
}

@test "red gate: shellcheck-dirty shell blocks the land → exit 6, trunk unchanged" {
  git checkout -q -b feat/badgate main
  printf '#!/usr/bin/env bash\ncd /tmp/nope\necho ok\n' > bad.sh   # SC2164 → shellcheck RED
  git add bad.sh && git commit -q -m "feat: bad"

  run bash "$SHIPLAND" --trunk main
  [ "$status" -eq 6 ]
  git fetch -q origin main
  [ -z "$(git ls-tree origin/main -- bad.sh)" ]           # NOT pushed
}

@test "deleted files: git-rm of a tracked .sh/.py lands GREEN (b452/1bc4 regression) → exit 0" {
  # run_gate builds shellfiles/pyfiles by extension/shebang; before the fix it did NOT drop paths
  # removed at HEAD, so shellcheck / py_compile ran on the now-absent path → gate RED (exit 6),
  # making ANY file-removal commit unlandable. Regression: a commit that git-rm's a tracked .sh
  # AND .py must land green.
  # Seed both files STRAIGHT onto trunk (no ship-land seed) so the single delete-land is the unit
  # under test — a seed *via ship-land* would py_compile doomed.py and leave __pycache__ litter that
  # this scratch repo, unlike the real one (.gitignore: __pycache__/), does not ignore → a false
  # dirty-tree exit 2 on the next land that would mask the gate behaviour we are asserting.
  git checkout -q -b seed main
  printf '#!/usr/bin/env bash\necho "doomed"\n' > doomed.sh
  printf 'x = 1\n' > doomed.py
  git add doomed.sh doomed.py && git commit -q -m "seed doomed files"
  git push -q origin seed:main
  git fetch -q origin main

  git checkout -q -b chore/rm-doomed origin/main
  git rm -q doomed.sh doomed.py && git commit -q -m "chore: remove doomed files"
  run bash "$SHIPLAND" --trunk main
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "LANDED"
  git fetch -q origin main
  [ -z "$(git ls-tree origin/main -- doomed.sh)" ]         # deletion landed on trunk
  [ -z "$(git ls-tree origin/main -- doomed.py)" ]
}

@test "gate: extensionless python (shebang) syntax error blocks → exit 6" {
  git checkout -q -b feat/pytool main
  printf '#!/usr/bin/env python3\nx = = 1\n' > pytool       # no .py — caught via shebang scan
  git add pytool && git commit -q -m "feat: pytool"

  run bash "$SHIPLAND" --trunk main --dry-run
  [ "$status" -eq 6 ]
}

@test "push non-ff: rejected push → exit 7, loud" {
  # server-side hook rejects the main update (simulated non-fast-forward)
  printf '#!/bin/sh\n[ "$1" = "refs/heads/main" ] && { echo "simulated non-ff" >&2; exit 1; }\nexit 0\n' > "$ORIGIN/hooks/update"
  chmod +x "$ORIGIN/hooks/update"

  on_branch_with feat/nonff f3.txt hello

  run bash "$SHIPLAND" --trunk main
  [ "$status" -eq 7 ]
  echo "$output" | grep -qi "reject"
}

@test "verify-fail: PERSISTENT concurrent drop → bounded auto-retry exhausts → exit 8, clean rollback" {
  # post-update hook resets main back to base AFTER EVERY push — the 2026-07-11 incident, but persistent:
  # our push 'succeeds' yet a concurrent rebase-land drops our commit from the trunk, every single time.
  # T-P9-7: ship-land auto-retries (bounded by SHIP_LAND_VERIFY_RETRIES=2) and, on exhaustion, leaves a
  # CLEAN committed tree (never a wedged rebase) with the ship/backup-* ref intact for manual recovery.
  base_sha="$(git -C "$ORIGIN" rev-parse main)"
  printf '#!/bin/sh\ngit update-ref refs/heads/main %s\n' "$base_sha" > "$ORIGIN/hooks/post-update"
  chmod +x "$ORIGIN/hooks/post-update"

  on_branch_with feat/dropme dropped.txt payload

  run bash "$SHIPLAND" --trunk main
  [ "$status" -eq 8 ]
  echo "$output" | grep -qi "VERIFY FAILED"
  echo "$output" | grep -qi "auto-retry"                 # it DID retry before giving up (bounded)
  grep -q '"verify":"FAIL"' "$LAND_LOG"
  grep -q '"exit":8' "$LAND_LOG"
  # rollback guarantee: no rebase left in progress, working tree clean, backup ref intact
  [ ! -d "$WORK/.git/rebase-merge" ]
  [ ! -d "$WORK/.git/rebase-apply" ]
  [ -z "$(git status --porcelain)" ]
  [ -n "$(git branch --list 'ship/backup-*')" ]
}

@test "esc-scan: DROP TABLE in the range → exit 3, decision packet parked, trunk unchanged" {
  git checkout -q -b feat/esc main
  printf 'DROP TABLE users;\n' > migration.sql
  git add migration.sql && git commit -q -m "feat: migration"

  run bash "$SHIPLAND" --trunk main
  [ "$status" -eq 3 ]
  echo "$output" | grep -qi "PARKED"
  # a class-B decision packet was written
  pkt="$(ls "$SHIP_LAND_DECISIONS_DIR"/*.json 2>/dev/null | head -1)"
  [ -n "$pkt" ]
  grep -q '"class": "B"' "$pkt"
  grep -q '"staged": true' "$pkt"
  # never pushed
  git fetch -q origin main
  [ -z "$(git ls-tree origin/main -- migration.sql)" ]
}

@test "esc-scan FAIL-CLOSED: option-like SHIP_LAND_ESC_RE ('-foo') is applied via -- → exit 3, not fail-open" {
  # RED-proof for the `--` half. Pre-fix: grep parses '-foo' as an option (rc 2), `|| true` swallows it,
  # the scan reads CLEAN and the one landing rail fails OPEN. Post-fix: `--` makes '-foo' a PATTERN that
  # matches the planted line ⇒ PARK (exit 3). The escalation regex must never be silently un-applied.
  git checkout -q -b feat/escopt main
  printf 'alpha-foo bravo\n' > note.txt
  git add note.txt && git commit -q -m "feat: note"

  export SHIP_LAND_ESC_RE='-foo'
  run bash "$SHIPLAND" --trunk main --dry-run
  [ "$status" -eq 3 ]
  echo "$output" | grep -qi "PARKED"
}

@test "esc-scan FAIL-CLOSED: an invalid SHIP_LAND_ESC_RE (grep rc≥2) → exit 3, never CLEAN" {
  # RED-proof for the rc-capture half. Pre-fix: an invalid regex makes grep exit 2, `|| true` collapses it
  # to empty (indistinguishable from rc 1 no-match) and the rail fails OPEN. Post-fix: rc≥2 emits a
  # synthetic hit ⇒ PARK (exit 3). A malformed security pattern must fail closed, never land.
  git checkout -q -b feat/escbad main
  printf 'benign change\n' > note.txt
  git add note.txt && git commit -q -m "feat: note"

  export SHIP_LAND_ESC_RE='['
  run bash "$SHIPLAND" --trunk main --dry-run
  [ "$status" -eq 3 ]
  echo "$output" | grep -qi "PARKED"
}

@test "dry-run: reconcile + gate, no push → exit 0, trunk unchanged" {
  on_branch_with feat/dry dry.txt content

  run bash "$SHIPLAND" --trunk main --dry-run
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi "dry-run"
  git fetch -q origin main
  [ -z "$(git ls-tree origin/main -- dry.txt)" ]          # NOT pushed
}

@test "shared-checkout: non-session branch on the shared checkout → exit 4" {
  on_branch_with randombranch s.txt wip

  run env SHIP_LAND_SHARED_CHECKOUT="$WORK" bash "$SHIPLAND" --trunk main
  [ "$status" -eq 4 ]
  echo "$output" | grep -qi "REFUSING"
}

@test "dirty tree: uncommitted changes → exit 2" {
  on_branch_with feat/dirty tracked.txt clean
  echo dirty >> tracked.txt                                # uncommitted modification

  run bash "$SHIPLAND" --trunk main
  [ "$status" -eq 2 ]
}

@test "nothing to land: HEAD already on trunk → exit 0" {
  # on main, nothing ahead of origin/main
  run bash "$SHIPLAND" --trunk main
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi "nothing to land"
}

@test "P0-1 gate-green producer: green gate writes gate-green==HEAD; red gate does not" {
  # boundary-handoff.sh:122 fires its advisory only when gate-green == HEAD on a clean tree.
  # Before P0-1, the only gate-green writers were test fixtures, so boundary abstained 100% in prod.
  gc="$(git rev-parse --git-common-dir)"
  rm -f "$gc/gate-green"

  # green gate via --dry-run (runs the gate, no push) → producer stamps gate-green with HEAD
  git checkout -q -b feat/gg main
  printf '#!/usr/bin/env bash\necho ok\n' > gg.sh
  git add gg.sh && git commit -q -m "feat: gg"
  run bash "$SHIPLAND" --trunk main --dry-run
  [ "$status" -eq 0 ]
  [ -f "$gc/gate-green" ]
  [ "$(cat "$gc/gate-green")" = "$(git rev-parse HEAD)" ]   # producer wrote the proven-green HEAD

  # red gate → the red HEAD must NEVER be marked green (gate-green must not advance to it)
  git checkout -q -b feat/gg-red main
  printf '#!/usr/bin/env bash\ncd /tmp/nope\necho ok\n' > bad-gg.sh   # SC2164 → shellcheck RED
  git add bad-gg.sh && git commit -q -m "feat: bad-gg"
  redhead="$(git rev-parse HEAD)"
  run bash "$SHIPLAND" --trunk main --dry-run
  [ "$status" -eq 6 ]
  [ "$(cat "$gc/gate-green" 2>/dev/null || echo none)" != "$redhead" ]   # unproven tree never green
}

@test "T-P9-7 recover: TRANSIENT concurrent drop → auto-retry re-lands → exit 0, content on trunk" {
  # post-update drops main to base only on the FIRST push (one-time marker); the auto-retry's re-push
  # then sticks and content-verify passes. Proves the bounded retry HEALS a transient drop instead of
  # stranding on the old manual exit-8 recovery. (base_sha + $ORIGIN expand at write time; \$marker is
  # literal for the hook's runtime.)
  base_sha="$(git -C "$ORIGIN" rev-parse main)"
  cat > "$ORIGIN/hooks/post-update" <<EOF
#!/bin/sh
marker="$ORIGIN/dropped-once"
if [ ! -f "\$marker" ]; then
  : > "\$marker"
  git update-ref refs/heads/main $base_sha
fi
EOF
  chmod +x "$ORIGIN/hooks/post-update"

  on_branch_with feat/heal heal.txt payload

  run bash "$SHIPLAND" --trunk main
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi "auto-retry"                 # it reconciled + re-pushed
  echo "$output" | grep -q "LANDED"
  git fetch -q origin main
  [ -n "$(git ls-tree origin/main -- heal.txt)" ]        # content really reached the trunk on retry
  grep -q '"verify":"ok"' "$LAND_LOG"
}

@test "T-P9-7 kill-switch: SHIP_LAND_VERIFY_RETRIES=0 → single-shot exit 8, no auto-retry" {
  # =0 restores the pre-T-P9-7 behavior: one push, one verify, no retry. Persistent drop → immediate exit 8.
  base_sha="$(git -C "$ORIGIN" rev-parse main)"
  printf '#!/bin/sh\ngit update-ref refs/heads/main %s\n' "$base_sha" > "$ORIGIN/hooks/post-update"
  chmod +x "$ORIGIN/hooks/post-update"

  on_branch_with feat/noretry nr.txt payload

  run env SHIP_LAND_VERIFY_RETRIES=0 bash "$SHIPLAND" --trunk main
  [ "$status" -eq 8 ]
  # NOT a bare "auto-retry" substring: with retries disabled ship-land correctly reports
  # `post-push CONTENT-VERIFY FAILED after 0 auto-retry attempt(s)`, which that substring
  # matches — so it could never distinguish "no retry happened" from "a retry happened",
  # and passed only while it was dead. Assert the PER-ATTEMPT marker instead (`auto-retry
  # <n>/<max>`, ship-land.sh), plus a positive check that the reported count is 0.
  ! echo "$output" | grep -qE "auto-retry [0-9]+/[0-9]+" || false
  echo "$output" | grep -q "after 0 auto-retry attempt" || false
  grep -q '"exit":8' "$LAND_LOG"
}

@test "T-P9-7 rollback: auto-retry rebase CONFLICT → rolled back clean, exit 5" {
  # A sibling commit on origin edits base.txt divergently; the one-time hook resets main to it after our
  # first push. The auto-retry then rebases onto the sibling and CONFLICTS on base.txt → ship-land must
  # roll the rebase back (git rebase --abort → clean tree) and exit 5, never leave a wedged mid-conflict tree.
  git checkout -q -b sibling main
  printf 'theirs\n' > base.txt
  git commit -q -am "sibling: base.txt"
  git push -q origin sibling
  sib_sha="$(git -C "$ORIGIN" rev-parse sibling)"
  git checkout -q main

  cat > "$ORIGIN/hooks/post-update" <<EOF
#!/bin/sh
marker="$ORIGIN/reset-once"
if [ ! -f "\$marker" ]; then
  : > "\$marker"
  git update-ref refs/heads/main $sib_sha
fi
EOF
  chmod +x "$ORIGIN/hooks/post-update"

  git checkout -q -b feat/conflict main
  printf 'ours\n' > base.txt                              # same line as the sibling → guaranteed conflict
  git commit -q -am "feat: base.txt ours"

  run bash "$SHIPLAND" --trunk main
  [ "$status" -eq 5 ]
  echo "$output" | grep -qi "rolled back"
  # rollback guarantee: no rebase left in progress, working tree clean
  [ ! -d "$WORK/.git/rebase-merge" ]
  [ ! -d "$WORK/.git/rebase-apply" ]
  [ -z "$(git status --porcelain)" ]
}

# ---- gate scope modes · flake exoneration · attestation fields --------------
#
# The fixture repo has no tests/ dir, so the gate's bats step never fires by default. These
# tests SEED suites onto trunk and PATH-shim `bats`: the shim's recorded argv is the durable
# product ("which suites actually ran"), and it injects a first-run-only failure for the flake
# fixture. A nested REAL bats run is deliberately avoided — argv is what is under test.

scope_fixture() {   # seed tests/{a,b}.bats onto trunk + shim bats + default to an ABSENT policy
  SHIMDIR="$BATS_TEST_TMPDIR/shims"; mkdir -p "$SHIMDIR"
  export BATS_ARGV="$BATS_TEST_TMPDIR/bats-argv"
  export FLAKE_ONCE="$BATS_TEST_TMPDIR/flake-once"   # suite file that fails its FIRST run only
  : > "$FLAKE_ONCE"
  # GATE-KILLED fixtures. The shim reproduces each shape BYTE-WISE as real bats emits it, because
  # the RED-vs-KILLED split reads the TAP: `sig` = a run that was executing and then died (plan +
  # ok lines, then 137 — the live 2026-07-26 signature); `unattrib` = the same event seen from the
  # TAP side (non-zero, zero `not ok`); `startup` = bats never ran at all (NO TAP), which is a REAL
  # red and must stay one; `red` = a named failure, the positive control that must NOT be softened.
  export KILL_MODE="$BATS_TEST_TMPDIR/kill-mode"
  : > "$KILL_MODE"
  cat > "$SHIMDIR/bats" <<EOF
#!/bin/bash
printf '%s\n' "\$*" >> "$BATS_ARGV"
case "\$(cat "$KILL_MODE" 2>/dev/null)" in
  sig)       echo "1..3"; echo "ok 1 alpha"; echo "ok 2 beta"; exit 137 ;;
  unattrib)  echo "1..3"; echo "ok 1 alpha"; exit 1 ;;
  startup)   exit 1 ;;
  red)       echo "1..1"; echo "not ok 1 boom"; exit 1 ;;
  sig-once)  if [ ! -f "$BATS_TEST_TMPDIR/killed-once" ]; then
               : > "$BATS_TEST_TMPDIR/killed-once"; echo "1..3"; echo "ok 1 alpha"; exit 137
             fi ;;
  cut-then-red) if [ ! -f "$BATS_TEST_TMPDIR/cut-once" ]; then
               : > "$BATS_TEST_TMPDIR/cut-once"; echo "1..3"; echo "ok 1 alpha"; exit 137
             else echo "1..1"; echo "not ok 1 boom"; exit 1; fi ;;
esac
f="\$(cat "$FLAKE_ONCE" 2>/dev/null)"
if [ -n "\$f" ] && [ "\$1" = "\$f" ]; then
  m="$BATS_TEST_TMPDIR/flaked-\$(basename "\$1")"
  if [ ! -f "\$m" ]; then : > "\$m"; exit 1; fi
fi
exit 0
EOF
  chmod +x "$SHIMDIR/bats"
  export PATH="$SHIMDIR:$PATH"
  export SHIP_LAND_GATE_POLICY="$BATS_TEST_TMPDIR/no-such-policy.sh"   # absent ⇒ hardcoded full
  mkdir -p tests
  printf '#!/usr/bin/env bats\n@test "a" { true; }\n' > tests/a.bats
  printf '#!/usr/bin/env bats\n@test "b" { true; }\n' > tests/b.bats
  git add tests && git commit -q -m "seed suites" && git push -q origin HEAD:main
  git fetch -q origin main
}

stub_selector() {  # $1=plain-call stdout, $2=--direct stdout (either may be empty/multi-line)
  local sel="$BATS_TEST_TMPDIR/gate-select.sh"
  {
    echo '#!/bin/bash'
    echo 'if [ "$1" = "--direct" ]; then'
    printf 'cat <<SELEOF\n%s\nSELEOF\n' "$2"
    echo 'else'
    printf 'cat <<SELEOF\n%s\nSELEOF\n' "$1"
    echo 'fi'
  } > "$sel"
  chmod +x "$sel"
  export SHIP_LAND_GATE_SELECT="$sel"
}

landable() {  # $1=branch $2=shell file — a commit the gate always lints
  git checkout -q -b "$1" main
  printf '#!/usr/bin/env bash\necho ok\n' > "$2"
  git add "$2" && git commit -q -m "feat: $2"
}

@test "scope: ABSENT policy file ⇒ full mode (bats tests/ runs, gate-green advances)" {
  scope_fixture
  stub_selector "tests/a.bats" ""        # selector exists but MUST be ignored in full mode
  gc="$(git rev-parse --git-common-dir)"; rm -f "$gc/gate-green"
  landable feat/scope-full sf.sh

  run bash "$SHIPLAND" --trunk main
  [ "$status" -eq 0 ]
  [ "$(cat "$BATS_ARGV")" = "tests/" ]                       # the WHOLE suite, one invocation
  [ "$(cat "$gc/gate-green")" = "$(git rev-parse HEAD)" ]     # full proof ⇒ marker advances
}

@test "scope: scoped + selector picks ONE suite ⇒ only that suite runs, gate-green NOT advanced" {
  scope_fixture
  stub_selector "tests/a.bats" ""
  gc="$(git rev-parse --git-common-dir)"; rm -f "$gc/gate-green"
  landable feat/scope-one so.sh

  run env SHIP_LAND_GATE_SCOPE=scoped bash "$SHIPLAND" --trunk main
  [ "$status" -eq 0 ]
  [ "$(cat "$BATS_ARGV")" = "tests/a.bats" ]                 # b.bats never ran; no `tests/` run
  [ ! -f "$gc/gate-green" ]                                  # scoped ≠ full-suite claim
  echo "$output" | grep -q "gate-green NOT advanced"
  grep -q '"gate_scope":"scoped"' "$LAND_LOG"
  grep -q '"selected_n":1' "$LAND_LOG"
}

@test "scope: scoped + selector says FULL ⇒ full run, gate-green advances" {
  scope_fixture
  stub_selector "FULL" ""
  gc="$(git rev-parse --git-common-dir)"; rm -f "$gc/gate-green"
  landable feat/scope-fullsel sfs.sh

  run env SHIP_LAND_GATE_SCOPE=scoped bash "$SHIPLAND" --trunk main
  [ "$status" -eq 0 ]
  [ "$(cat "$BATS_ARGV")" = "tests/" ]
  [ "$(cat "$gc/gate-green")" = "$(git rev-parse HEAD)" ]
}

@test "scope: scoped + selector picks NOTHING ⇒ bats skipped, land still proceeds" {
  scope_fixture
  stub_selector "" ""
  landable feat/scope-none sn.sh

  run env SHIP_LAND_GATE_SCOPE=scoped bash "$SHIPLAND" --trunk main
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "0 suites"
  [ ! -s "$BATS_ARGV" ]                                      # bats never invoked at all
  git fetch -q origin main
  [ -n "$(git ls-tree origin/main -- sn.sh)" ]               # lint-only land still lands
}

@test "scope: unknown SHIP_LAND_GATE_SCOPE ⇒ exit 2 (fail-closed on a typo'd policy)" {
  run env SHIP_LAND_GATE_SCOPE=bogus bash "$SHIPLAND" --trunk main
  [ "$status" -eq 2 ]
  echo "$output" | grep -q "unknown SHIP_LAND_GATE_SCOPE"
}

@test "attest: UNLOCKED gate-red now writes an exit-6 land.log line (the flake-rate denominator)" {
  git checkout -q -b feat/red-attest main
  printf '#!/usr/bin/env bash\ncd /tmp/nope\necho ok\n' > bad-attest.sh   # SC2164 ⇒ gate RED
  git add bad-attest.sh && git commit -q -m "feat: bad-attest"
  head="$(git rev-parse HEAD)"

  run bash "$SHIPLAND" --trunk main
  [ "$status" -eq 6 ]
  grep -q '"exit":6' "$LAND_LOG"
  grep -q "\"head\":\"$head\"" "$LAND_LOG"                   # replayable: WHICH tree went red
}

@test "flake exoneration: NON-direct suite passes on retry ⇒ land GREEN + flakes.jsonl entry" {
  scope_fixture
  stub_selector "tests/a.bats" "tests/b.bats"   # a is selected but is NOT a direct suite
  echo "tests/a.bats" > "$FLAKE_ONCE"           # fails once, passes the fresh-TMPDIR re-run
  landable feat/flake fl.sh

  run env SHIP_LAND_GATE_SCOPE=scoped bash "$SHIPLAND" --trunk main
  [ "$status" -eq 0 ]
  [ "$(grep -c . "$BATS_ARGV")" -eq 2 ]                      # first run + one exoneration re-run
  echo "$output" | grep -q "EXONERATED"
  grep -q '"outcome":"pass-on-retry"' "$POSTLAND_DIR/flakes.jsonl"
  grep -q '"file":"tests/a.bats"' "$POSTLAND_DIR/flakes.jsonl"
  grep -q '"phase":"land-gate"' "$POSTLAND_DIR/flakes.jsonl"
}

@test "flake exoneration: a DIRECT suite passing on retry is still RED ⇒ exit 6, nothing logged" {
  scope_fixture
  stub_selector "tests/a.bats" "tests/a.bats"   # same suite, now DIRECT to the change
  echo "tests/a.bats" > "$FLAKE_ONCE"
  landable feat/flake-direct fld.sh

  run env SHIP_LAND_GATE_SCOPE=scoped bash "$SHIPLAND" --trunk main
  [ "$status" -eq 6 ]
  echo "$output" | grep -q "finding, not a flake"
  [ ! -f "$POSTLAND_DIR/flakes.jsonl" ]                      # never exonerated ⇒ never logged
  git fetch -q origin main
  [ -z "$(git ls-tree origin/main -- fld.sh)" ]              # and NOT landed
}

@test "attest: land.log carries head/base/tree/gate_scope/selected_n" {
  landable feat/attest-fields af.sh
  base="$(git rev-parse origin/main)"

  run bash "$SHIPLAND" --trunk main
  [ "$status" -eq 0 ]
  grep -q "\"head\":\"$(git rev-parse HEAD)\"" "$LAND_LOG"
  grep -q "\"tree\":\"$(git rev-parse 'HEAD^{tree}')\"" "$LAND_LOG"
  grep -q "\"base\":\"$base\"" "$LAND_LOG"
  grep -qE '"gate_scope":"(full|scoped|shadow)"' "$LAND_LOG"
  grep -q '"selected_n":' "$LAND_LOG"
}

@test "scope: scoped with an ABSENT selector ⇒ FULL suite (fail-closed, the pre-T1 repo state)" {
  scope_fixture
  export SHIP_LAND_GATE_SELECT="$BATS_TEST_TMPDIR/no-such-selector.sh"
  landable feat/scope-nosel sns.sh

  run env SHIP_LAND_GATE_SCOPE=scoped bash "$SHIPLAND" --trunk main
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "missing/not executable"
  [ "$(cat "$BATS_ARGV")" = "tests/" ]        # narrowing is NEVER the failure mode
}

@test "scope: scoped + RED suite-map lint ⇒ degrades to FULL (lint never blocks a land)" {
  scope_fixture
  sel="$BATS_TEST_TMPDIR/gate-select.sh"
  printf '#!/bin/bash\n[ "$1" = lint ] && exit 1\n[ "$1" = --direct ] && exit 0\necho tests/a.bats\n' > "$sel"
  chmod +x "$sel"
  export SHIP_LAND_GATE_SELECT="$sel"
  landable feat/lint-red lr.sh

  run env SHIP_LAND_GATE_SCOPE=scoped bash "$SHIPLAND" --trunk main
  [ "$status" -eq 0 ]                            # a red MAP lint is never a red LAND
  echo "$output" | grep -q "suite-map lint RED"
  [ "$(cat "$BATS_ARGV")" = "tests/" ]           # …it buys proof, it does not block
}

@test "scope: INERT post-land net (stale green stamp) ⇒ scoped degrades to the FULL gate" {
  scope_fixture
  stub_selector "tests/a.bats" ""
  mkdir -p "$POSTLAND_DIR/stamps"
  printf '{"head":"deadbee","verdict":"green"}\n' > "$POSTLAND_DIR/stamps/deadbee.json"
  printf '{"head":"newer","verdict":"red"}\n' > "$POSTLAND_DIR/stamps/newer.json"   # red ≠ liveness
  touch -t 202001010000 "$POSTLAND_DIR/stamps/deadbee.json"    # net ran once, then went cold
  landable feat/stale-net stn.sh

  run env SHIP_LAND_GATE_SCOPE=scoped bash "$SHIPLAND" --trunk main
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "post-land net appears INERT"
  [ "$(cat "$BATS_ARGV")" = "tests/" ]
}

@test "scope: staleness guard — fresh stamp ⇒ scoped; kill switch ⇒ scoped despite a stale stamp" {
  scope_fixture
  stub_selector "tests/a.bats" ""
  mkdir -p "$POSTLAND_DIR/stamps"
  printf '{"head":"fresh","verdict":"green"}\n' > "$POSTLAND_DIR/stamps/fresh.json"   # live net
  landable feat/fresh-net frn.sh
  run env SHIP_LAND_GATE_SCOPE=scoped bash "$SHIPLAND" --trunk main
  [ "$status" -eq 0 ]
  [ "$(cat "$BATS_ARGV")" = "tests/a.bats" ]

  : > "$BATS_ARGV"
  touch -t 202001010000 "$POSTLAND_DIR/stamps/fresh.json"      # now cold, but guard disabled
  landable feat/killswitch ks.sh
  run env SHIP_LAND_GATE_SCOPE=scoped POSTLAND_STALENESS_GUARD=off bash "$SHIPLAND" --trunk main
  [ "$status" -eq 0 ]
  [ "$(cat "$BATS_ARGV")" = "tests/a.bats" ]
  ! echo "$output" | grep -q "INERT"
}

@test "flake ledger: the entry carries a signal field (what failed), not just 'it flaked'" {
  scope_fixture
  stub_selector "tests/a.bats" "tests/b.bats"
  echo "tests/a.bats" > "$FLAKE_ONCE"
  landable feat/flake-signal fs.sh

  run env SHIP_LAND_GATE_SCOPE=scoped bash "$SHIPLAND" --trunk main
  [ "$status" -eq 0 ]
  grep -q '"signal":"' "$POSTLAND_DIR/flakes.jsonl"
  grep -qv '"signal":""' "$POSTLAND_DIR/flakes.jsonl"          # populated, never empty
}

@test "scope: stamps dir with NO green stamp yet ⇒ no guard (the bootstrap land must not brick)" {
  scope_fixture
  stub_selector "tests/a.bats" ""
  mkdir -p "$POSTLAND_DIR/stamps"
  printf '{"head":"only","verdict":"red"}\n' > "$POSTLAND_DIR/stamps/only.json"
  touch -t 202001010000 "$POSTLAND_DIR/stamps/only.json"       # ancient, but never green
  landable feat/bootstrap bs.sh

  run env SHIP_LAND_GATE_SCOPE=scoped bash "$SHIPLAND" --trunk main
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q "INERT" || false                  # a net that never went green
  [ "$(cat "$BATS_ARGV")" = "tests/a.bats" ]                   # is "not adopted", not "inert"
}

# ── CUT ≠ RED on the FULL tier (run_bats_all) ────────────────────────────────────────────────
# bats masks a signal death: `bats:517-524` pipes exec bats-exec-suite through
# bats_test_count_validator under `set -o pipefail` (:501), and the validator returns 1 on a
# truncated TAP — so a killed suite surfaces as plain `1`, never 137/143. The TAP BODY is the
# only honest discriminator, which is what these two tests pin.
cut_fixture() {   # shim `bats` that can produce EITHER a cut (rc!=0, zero output) or a real red
  SHIMDIR="$BATS_TEST_TMPDIR/shims-cut"; mkdir -p "$SHIMDIR"
  export BATS_ARGV="$BATS_TEST_TMPDIR/bats-argv-cut"
  export CUT_MODE="$BATS_TEST_TMPDIR/cut-mode"
  cat > "$SHIMDIR/bats" <<EOF
#!/bin/bash
printf '%s\n' "\$*" >> "$BATS_ARGV"
if [ "\$(cat "$CUT_MODE" 2>/dev/null)" = red ]; then
  echo "1..1"; echo "not ok 1 a genuine failure"; exit 1      # a REAL red: a not-ok IS present
fi
if [ ! -f "$BATS_TEST_TMPDIR/cut-done" ]; then
  : > "$BATS_TEST_TMPDIR/cut-done"; exit 1                    # a CUT: rc!=0 with ZERO output
fi
echo "1..1"; echo "ok 1 green on the re-run"; exit 0
EOF
  chmod +x "$SHIMDIR/bats"
  export PATH="$SHIMDIR:$PATH"
  export SHIP_LAND_GATE_POLICY="$BATS_TEST_TMPDIR/no-such-policy.sh"   # absent ⇒ full tier
  mkdir -p tests
  printf '#!/usr/bin/env bats\n@test "a" { true; }\n' > tests/a.bats
  git add tests && git commit -q -m "seed suites" && git push -q origin HEAD:main
  git fetch -q origin main
}

@test "FULL gate: a CUT (non-zero exit, ZERO 'not ok') is re-run once and CAN land green" {
  cut_fixture
  echo cut > "$CUT_MODE"
  landable feat/cut cut.sh
  run bash "$SHIPLAND" --trunk main
  [ "$status" -eq 0 ]                                     # a cut must NOT be a landing failure
  echo "$output" | grep -q "CUT, not RED"
  [ "$(grep -cx 'tests/' "$BATS_ARGV")" -eq 2 ]           # ran twice: original + exoneration
}

@test "FULL gate: a REAL red (a 'not ok' line) is NOT re-run and does NOT land" {
  cut_fixture
  echo red > "$CUT_MODE"
  landable feat/red red.sh
  run bash "$SHIPLAND" --trunk main
  [ "$status" -eq 6 ]                                     # gate RED ⇒ exit 6, unchanged
  echo "$output" | grep -q "bats RED"
  [ "$(grep -cx 'tests/' "$BATS_ARGV")" -eq 1 ]           # exactly ONE run — no free retry on red
}

# ════ admission control (gate_admit) ═══════════════════════════════════════════════════════════
# Extracted and driven directly: the contract is about WAITING, and a fixture that actually waits
# would make this suite the slow thing it exists to prevent. Assertions use `|| false` because a
# non-final [[ ]] is errexit-EXEMPT in bats and would be a DEAD assertion.
admit_probe() {  # $@ = env assignments → runs gate_admit once, echoes its stderr, returns its rc
  { sed -n '/^gate_admit() {/,/^}/p' "$SHIPLAND"
    printf 'gate_admit "the FULL bats suite"\n'
  } > "$BATS_TEST_TMPDIR/admit.sh"
  env "$@" bash "$BATS_TEST_TMPDIR/admit.sh" 2>&1
}

@test "admit: NEVER waits while the land-lock is held (IN_LAND_LOCK=1 ⇒ instant no-op)" {
  # The load-bearing one. The gate sits OUTSIDE the lock BY DESIGN (190c839); sleeping inside it
  # would serialize every other lander behind this one's wait.
  run timeout 10 bash -c "$(declare -f admit_probe); SHIPLAND='$SHIPLAND' BATS_TEST_TMPDIR='$BATS_TEST_TMPDIR' \
    admit_probe IN_LAND_LOCK=1 CC_GATE_MAX_LOAD=0.0001 CC_GATE_ADMIT_MAX_WAIT=300 CC_GATE_ADMIT_POLL=30"
  [ "$status" -eq 0 ]
  [ -z "$output" ]                                   # not even a DEFERRING line under the lock
}

@test "admit: kill switch CC_GATE_MAX_LOAD=0 returns immediately" {
  run timeout 10 bash -c "$(declare -f admit_probe); SHIPLAND='$SHIPLAND' BATS_TEST_TMPDIR='$BATS_TEST_TMPDIR' \
    admit_probe CC_GATE_MAX_LOAD=0 CC_GATE_ADMIT_MAX_WAIT=300 CC_GATE_ADMIT_POLL=30"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "admit: fails OPEN on a non-numeric ceiling and on a zero poll (never blocks a land)" {
  run timeout 10 bash -c "$(declare -f admit_probe); SHIPLAND='$SHIPLAND' BATS_TEST_TMPDIR='$BATS_TEST_TMPDIR' \
    admit_probe CC_GATE_MAX_LOAD=bogus CC_GATE_ADMIT_MAX_WAIT=300 CC_GATE_ADMIT_POLL=30"
  [ "$status" -eq 0 ]
  run timeout 10 bash -c "$(declare -f admit_probe); SHIPLAND='$SHIPLAND' BATS_TEST_TMPDIR='$BATS_TEST_TMPDIR' \
    admit_probe CC_GATE_MAX_LOAD=0.0001 CC_GATE_ADMIT_MAX_WAIT=300 CC_GATE_ADMIT_POLL=0"
  [ "$status" -eq 0 ]
}

@test "admit: an unsatisfiable ceiling DEFERS, then PROCEEDS when the budget expires (bounded)" {
  # 0.0001 is below any real loadavg ⇒ the wait can never be satisfied; a 1s budget bounds it.
  run timeout 30 bash -c "$(declare -f admit_probe); SHIPLAND='$SHIPLAND' BATS_TEST_TMPDIR='$BATS_TEST_TMPDIR' \
    admit_probe CC_GATE_MAX_LOAD=0.0001 CC_GATE_ADMIT_MAX_WAIT=1 CC_GATE_ADMIT_POLL=1"
  [ "$status" -eq 0 ]                                # bounded: it PROCEEDS, it does not fail
  echo "$output" | grep -q "DEFERRING" || false      # it announced the deferral
  echo "$output" | grep -q "proceeding anyway" || false
}

# ════ GATE-KILLED — signal death is a THIRD state, never RED (backlog 9c5d0ba74e79) ════════════
# The live signature these reproduce: a gate ran green through 1359 tests, then `bats tests/
# Killed: 9`, and ship-land printed "gate: bats RED / not pushing" — byte-indistinguishable from a
# real red, so the retry read as flaky tests instead of "we ran out of machine".
# RED-PROOF: every assertion below fails against the pre-fix tree, where EVERY non-zero bats exit
# produced "GATE RED" + exit 6. The `red` and `startup` cases are the positive controls — if the
# kill path ever starts swallowing genuine failures, those two go red.

@test "gate-killed: a SIGNAL-killed full suite exits 9 (not 6), pushes nothing, retries once" {
  scope_fixture
  echo sig > "$KILL_MODE"
  gc="$(git rev-parse --git-common-dir)"; rm -f "$gc/gate-green"
  landable feat/killed gk.sh

  run bash "$SHIPLAND" --trunk main
  [ "$status" -eq 9 ]                                          # 9 = no verdict, NOT 6 = red
  echo "$output" | grep -q "GATE-KILLED" || false
  ! echo "$output" | grep -q "GATE RED" || false               # never both, never the wrong one
  [ "$(grep -c . "$BATS_ARGV")" -eq 2 ]                        # first run + ONE bounded re-run
  [ ! -f "$gc/gate-green" ]                                    # a kill proves nothing ⇒ no marker
  git fetch -q origin main
  [ -z "$(git ls-tree origin/main -- gk.sh)" ]                 # fail-closed: nothing landed
}

@test "gate-killed: land.log attests exit 9, so a kill is not counted in the red denominator" {
  scope_fixture
  echo sig > "$KILL_MODE"
  landable feat/killed-log gkl.sh

  run bash "$SHIPLAND" --trunk main
  [ "$status" -eq 9 ]
  grep -q '"exit":9' "$LAND_LOG" || false
  ! grep -q '"exit":6' "$LAND_LOG"
}

@test "gate-killed: a non-zero suite that names NO failing test is a kill, not a red" {
  # The exact shape of the two poisoned live stamps: failing=["tests/"], retries=0. The retry
  # ladder identified ZERO failing FILES — the signature of signal-kill, not test failure.
  scope_fixture
  echo unattrib > "$KILL_MODE"
  landable feat/unattrib gu.sh

  run bash "$SHIPLAND" --trunk main
  [ "$status" -eq 9 ]
  echo "$output" | grep -q "GATE-KILLED" || false
}

@test "gate-killed POSITIVE CONTROL: a suite that NAMES a failing test still exits 6" {
  # If this ever goes green-by-accident the whole split is worthless — a real red MUST stay a red.
  scope_fixture
  echo red > "$KILL_MODE"
  landable feat/really-red gr.sh

  run bash "$SHIPLAND" --trunk main
  [ "$status" -eq 6 ]
  echo "$output" | grep -q "GATE RED" || false
  ! echo "$output" | grep -q "GATE-KILLED" || false
  [ "$(grep -c . "$BATS_ARGV")" -eq 1 ]                        # a RED is never re-run
}

@test "gate-killed: a suite that emits NO TAP at all is ALSO a non-verdict (exit 9, fail-closed)" {
  # An earlier draft of this branch split "never got going" from "died mid-run" and called the
  # former a RED. Retired deliberately on reconciliation: the ONE discriminator is `not ok` in the
  # TAP — shared by the FULL and SCOPED tiers so they cannot disagree about what a cut is — and a
  # second rule keyed on a plan line buys nothing, since a suite that never starts also names no
  # failing test and both outcomes are equally fail-closed. This test PINS that choice rather than
  # leaving it implicit.
  scope_fixture
  echo startup > "$KILL_MODE"
  landable feat/no-tap gn.sh

  run bash "$SHIPLAND" --trunk main
  [ "$status" -eq 9 ]
  echo "$output" | grep -q "GATE-KILLED" || false
  git fetch -q origin main
  [ -z "$(git ls-tree origin/main -- gn.sh)" ]                 # the property that actually matters
}

@test "gate-killed: a cut-then-green re-run LANDS (the whole point of the single re-run)" {
  scope_fixture
  echo sig-once > "$KILL_MODE"                                 # cut once, then normal
  landable feat/kill-then-green kg.sh

  run bash "$SHIPLAND" --trunk main
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "CUT, not RED" || false             # it named the non-verdict…
  [ "$(grep -c . "$BATS_ARGV")" -eq 2 ]                        # …re-ran…
  git fetch -q origin main
  [ -n "$(git ls-tree origin/main -- kg.sh)" ]                 # …and landed
}

@test "gate-killed: a cut re-run that turns up REAL failures is a red (6), not a kill (9)" {
  # The re-run's TAP is now captured precisely so this case is decidable. Before, both outcomes
  # printed "RED (or cut twice)" — a guess handed to the caller at the moment the answer decides
  # whether retrying is correct. A real failure surfacing on the re-run must win.
  scope_fixture
  echo cut-then-red > "$KILL_MODE"
  landable feat/cut-then-red ctr.sh

  run bash "$SHIPLAND" --trunk main
  [ "$status" -eq 6 ]
  echo "$output" | grep -q "on the re-run" || false
  ! echo "$output" | grep -q "GATE-KILLED"
}

@test "gate-killed: a REAL red alongside a kill exits 6 — a verdict outranks a non-verdict" {
  # Mixed run: shellcheck names a genuine defect while the suite dies. Reporting 9 would tell the
  # caller "just retry", losing a real finding. GATE_RED wins.
  scope_fixture
  echo sig > "$KILL_MODE"
  git checkout -q -b feat/mixed main
  printf '#!/usr/bin/env bash\nfoo=$(ls)\necho $foo\n' > mixed.sh    # SC2086 ⇒ shellcheck red
  git add mixed.sh && git commit -q -m "feat: mixed"

  run bash "$SHIPLAND" --trunk main
  [ "$status" -eq 6 ]
  echo "$output" | grep -q "shellcheck RED" || false
  echo "$output" | grep -q "GATE RED" || false
  # Load-bearing, and what makes this RED-PROVABLE rather than tautological: pre-fix EVERY failure
  # was 6, so the exit code alone cannot distinguish the trees. This asserts the kill was actually
  # DETECTED and then outranked — not that detection never happened.
  echo "$output" | grep -q "GATE-KILLED" || false
}

@test "env hygiene: gate_bats scrubs LANDER tuning so a flag cannot forge a verdict" {
  # Regression for the defect that produced this test: landing with ship.md's own lock-starvation
  # remedy (SHIP_LAND_GATE_ROUNDS=0) bled into the gate's bats subprocess and turned a 46/46-green
  # tree into an exit-6 "GATE RED". A verdict about the TREE must never be a function of how the
  # operator tuned THIS land. Asserts the contract at the gate boundary, where it protects every
  # suite — setup()'s unset list is the same guarantee from the suite side.
  #
  # A stub `bats` reports exactly what the gate handed the suite; real bats never runs (this test
  # lives INSIDE bats, so invoking it for real would recurse).
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  cat > "$BATS_TEST_TMPDIR/bin/bats" <<'STUB'
#!/bin/bash
printf 'ROUNDS=[%s] RETRIES=[%s] SCOPE=[%s] LOCKWAIT=[%s] LOCKTTL=[%s] MAXLOAD=[%s] ARGS=[%s]\n' \
  "${SHIP_LAND_GATE_ROUNDS-unset}" "${SHIP_LAND_VERIFY_RETRIES-unset}" \
  "${SHIP_LAND_GATE_SCOPE-unset}" "${LAND_LOCK_WAIT-unset}" "${LAND_LOCK_TTL-unset}" \
  "${CC_GATE_MAX_LOAD-unset}" "$*"
STUB
  chmod +x "$BATS_TEST_TMPDIR/bin/bats"

  # Extract the function rather than sourcing ship-land.sh (sourcing would RUN the pipeline) —
  # same idiom postland-verify.sh's selftest uses for gate_admit.
  sed -n '/^gate_bats() {/,/^}/p' "$SHIPLAND" > "$BATS_TEST_TMPDIR/probe.sh"
  # Positive control: a silent sed miss (function renamed/moved) would leave an empty probe that
  # "passes" every unset assertion vacuously. Require the function to actually be there.
  grep -q 'env -u SHIP_LAND_GATE_ROUNDS' "$BATS_TEST_TMPDIR/probe.sh" || false
  printf 'gate_bats tests/foo.bats\n' >> "$BATS_TEST_TMPDIR/probe.sh"

  run env PATH="$BATS_TEST_TMPDIR/bin:$PATH" \
      SHIP_LAND_GATE_ROUNDS=0 SHIP_LAND_VERIFY_RETRIES=9 SHIP_LAND_GATE_SCOPE=full \
      LAND_LOCK_WAIT=10800 LAND_LOCK_TTL=99 CC_GATE_MAX_LOAD=31 \
      bash "$BATS_TEST_TMPDIR/probe.sh"
  [ "$status" -eq 0 ]
  # every LANDER knob the tests assert against arrives UNSET, whatever the operator set
  echo "$output" | grep -q 'ROUNDS=\[unset\]'   || false
  echo "$output" | grep -q 'RETRIES=\[unset\]'  || false
  echo "$output" | grep -q 'SCOPE=\[unset\]'    || false
  echo "$output" | grep -q 'LOCKWAIT=\[unset\]' || false
  echo "$output" | grep -q 'LOCKTTL=\[unset\]'  || false
  # FORCED to 0, deliberately NOT unset: a test must never sit in admission control (it would
  # stall the gate up to CC_GATE_ADMIT_MAX_WAIT per call and read as a hang).
  echo "$output" | grep -q 'MAXLOAD=\[0\]'      || false
  # and the scrub must not eat the arguments
  echo "$output" | grep -q 'ARGS=\[tests/foo.bats\]' || false
}

# ---- test-hermeticity ratchet: enforced by the LAND, not only by suite ~1706 -----------------
#
# A suite that does not fixture $HOME runs against the operator's live ~/. Before this, the only
# enforcement was tests/test-hermeticity-lint.bats, and it caught nothing at land time: `scoped`
# (the committed default) maps a new tests/*.bats to ITSELF, never to the ratchet, and a FULL run
# reaches the ratchet at test ~1706 — after the point machine-wide contention SIGKILLs most gates.
# Two suites landed leaky in one session that way, each fleet-blocking every later lander.
#
# These use the REAL scripts/test-hermeticity-lint.sh (a stub would only prove ship-land can call
# a stub), with CC_HERM_ALLOWLIST="" so the verdict comes from the fixture tree alone and never
# from the real repo's 109 grandfathered names.
herm_fixture() {   # shim bats (argv = "did bats run at all"), install the REAL ratchet, seed trunk
  SHIMDIR="$BATS_TEST_TMPDIR/shims"; mkdir -p "$SHIMDIR"
  export BATS_ARGV="$BATS_TEST_TMPDIR/bats-argv"; : > "$BATS_ARGV"
  cat > "$SHIMDIR/bats" <<EOF
#!/bin/bash
printf '%s\n' "\$*" >> "$BATS_ARGV"
exit 0
EOF
  chmod +x "$SHIMDIR/bats"
  export PATH="$SHIMDIR:$PATH"
  export SHIP_LAND_GATE_POLICY="$BATS_TEST_TMPDIR/no-such-policy.sh"   # absent ⇒ hardcoded full
  export CC_HERM_ALLOWLIST=""                                          # nothing grandfathered here
  mkdir -p scripts tests
  cp "$REPO/scripts/test-hermeticity-lint.sh" scripts/test-hermeticity-lint.sh
  chmod +x scripts/test-hermeticity-lint.sh
  printf '#!/usr/bin/env bats\nsetup() {\n  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"\n}\n@test "a" { true; }\n' \
    > tests/a.bats
  git add scripts tests && git commit -q -m "seed ratchet + a hermetic suite" \
    && git push -q origin HEAD:main
  git fetch -q origin main
}

add_suite() {   # $1=branch $2=suite basename $3=setup() body
  git checkout -q -b "$1" main
  { echo '#!/usr/bin/env bats'; echo 'setup() {'; echo "  $3"; echo '}'; echo '@test "x" { true; }'; } \
    > "tests/$2"
  git add "tests/$2" && git commit -q -m "test: $2"
}

@test "hermeticity: a NEW suite without a \$HOME fixture does NOT land → exit 6, file named, bats never ran" {
  herm_fixture
  add_suite feat/leak leak.bats 'REPO="$(pwd)"'          # no fixture HOME ⇒ runs against live ~/

  run bash "$SHIPLAND" --trunk main
  [ "$status" -eq 6 ]
  echo "$output" | grep -q 'LEAK'
  echo "$output" | grep -q 'leak.bats'                   # names the offending file, not a summary
  echo "$output" | grep -q 'test-hermeticity RED'
  # The whole point: it fails BEFORE the ~1700-test run, so the author sees it in seconds rather
  # than at test ~1706 of a gate that contention usually kills first.
  [ ! -s "$BATS_ARGV" ]
  git fetch -q origin main
  [ -z "$(git ls-tree origin/main -- tests/leak.bats)" ] # never reached trunk
}

@test "hermeticity: the SAME suite WITH a fixtured \$HOME lands green and bats still runs" {
  herm_fixture
  add_suite feat/herm leak.bats 'export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"'

  run bash "$SHIPLAND" --trunk main
  [ "$status" -eq 0 ]                                    # positive control: the ratchet discriminates
  [ "$(cat "$BATS_ARGV")" = "tests/" ]                   # and does not short-circuit a clean tree
  git fetch -q origin main
  [ -n "$(git ls-tree origin/main -- tests/leak.bats)" ]
}

@test "hermeticity: it fires in SCOPED mode too, even when the selector picks nothing" {
  # The hole that let both leaks land: gate-select maps a changed tests/X.bats to X.bats, and the
  # ratchet suite only to scripts/test-hermeticity-lint.sh — so no selection can ever reach it.
  # A lint-only land (selector picks 0 suites) is the extreme case and must STILL be blocked.
  herm_fixture
  stub_selector "" ""
  add_suite feat/leak-scoped leak.bats 'REPO="$(pwd)"'

  run env SHIP_LAND_GATE_SCOPE=scoped bash "$SHIPLAND" --trunk main
  [ "$status" -eq 6 ]
  echo "$output" | grep -q 'leak.bats'
  [ ! -s "$BATS_ARGV" ]
  git fetch -q origin main
  [ -z "$(git ls-tree origin/main -- tests/leak.bats)" ]
}

@test "hermeticity: a tree whose ratchet script is absent still lands (nothing to enforce)" {
  # Resolution is repo-root-relative on purpose — the tree being landed is judged by the ratchet it
  # SHIPS. A repo without one must not become unlandable; deleting ours stays loud via
  # tests/test-hermeticity-lint.bats, which execs it by path.
  scope_fixture                                          # seeds tests/ but no scripts/ ratchet
  landable feat/no-ratchet nr.sh

  run bash "$SHIPLAND" --trunk main
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | grep -c 'test-hermeticity RED')" -eq 0 ]   # -qv would pass on ANY other line
}
