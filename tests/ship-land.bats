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
  unset SHIP_LAND_GATE_SCOPE SHIP_LAND_GATE_SCOPE_DEFAULT SHIP_LAND_GATE_POLICY \
        SHIP_LAND_GATE_SELECT SHIP_LAND_FIRST_BASE SHIP_LAND_GATE_EFFECTIVE_FULL \
        SHIP_LAND_SELECTED_N POSTLAND_STALENESS_GUARD 2>/dev/null || true
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
  ! echo "$output" | grep -qi "auto-retry"               # zero retries attempted (single-shot)
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
  cat > "$SHIMDIR/bats" <<EOF
#!/bin/bash
printf '%s\n' "\$*" >> "$BATS_ARGV"
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
  ! echo "$output" | grep -q "INERT"                           # a net that never went green
  [ "$(cat "$BATS_ARGV")" = "tests/a.bats" ]                   # is "not adopted", not "inert"
}
