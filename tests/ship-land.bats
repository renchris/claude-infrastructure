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
  # v2 adds SHIP_LAND_LANE to this list, and it is the sharpest member: an operator landing with
  # the kill switch on (LANE=v1) would otherwise bleed `v1` into every fixture pipeline below and
  # red the fast-lane assertions on a tree that is fine — the ROUNDS=0 defect verbatim.
  # SHIP_LAND_SMOKE_* and _TIMEOUT_BIN join for the same reason (a budget or a disabled bound
  # inherited from the outer land would decide a fixture's smoke verdict), and the SMOKE_STATE
  # handoff vars because a CAS child seeds its attestation from them.
  unset SHIP_LAND_GATE_SCOPE SHIP_LAND_GATE_SCOPE_DEFAULT SHIP_LAND_GATE_POLICY \
        SHIP_LAND_GATE_SELECT SHIP_LAND_FIRST_BASE SHIP_LAND_GATE_EFFECTIVE_FULL \
        SHIP_LAND_SELECTED_N POSTLAND_STALENESS_GUARD \
        SHIP_LAND_GATE_ROUNDS SHIP_LAND_VERIFY_RETRIES \
        SHIP_LAND_LANE SHIP_LAND_SMOKE_BUDGET_S SHIP_LAND_SMOKE_NICE SHIP_LAND_TIMEOUT_BIN \
        SHIP_LAND_SMOKE_STATE SHIP_LAND_SMOKE_N SHIP_LAND_SMOKE_S SHIP_LAND_NET_STATE \
        2>/dev/null || true
  # LOAD SHEDDING OFF for the whole suite. In v2 CC_GATE_MAX_LOAD=0 is the never-shed kill switch,
  # so every fixture's smoke RUNS. Left inherited, whether a pipeline smoked at all would depend on
  # the ambient load of the box the suite happens to run on — a test verdict decided by `uptime`.
  # These tests assert VERDICT logic; shedding has its own dedicated tests below, which set it
  # per-test.
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

@test "deletion skip does NOT disable the gate: dirty ADD alongside a delete → exit 6" {
  # The skip must drop ONLY the absent path, never the whole gate. Delete one tracked shell file AND
  # add a shellcheck-dirty one in the same commit → the surviving file must still fail the gate.
  printf '#!/usr/bin/env bash\necho "keep"\n' > old.sh
  git add old.sh && git commit -q -m "seed old.sh" && git push -q origin main

  git checkout -q -b feat/mixed
  git rm -q old.sh
  printf '#!/usr/bin/env bash\ncd /tmp/nope\necho ok\n' > new.sh   # SC2164 → shellcheck RED
  git add new.sh && git commit -q -m "chore: swap old.sh for new.sh"

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
  # a class-C decision packet was written, in cc-decide's CANONICAL schema
  pkt="$(ls "$SHIP_LAND_DECISIONS_DIR"/*.json 2>/dev/null | head -1)"
  [ -n "$pkt" ]
  # class C, not B: this packet has no default and waits for a human, and `cc-decide open`'s own
  # fail-closed gate REFUSES class-B without both --default and --deadline. C is also the class
  # operator-readout renders on the operator board.
  run jq -r '.class' "$pkt";                  [ "$output" = "C" ]
  # RED-PROOF (the defect): `.status` was absent entirely, so the packet was invisible to
  # `cc-decide list --open` (predicate `.status == "open"`) and to autonomy-sweep / cc-digest /
  # operator-readout, which share that idiom. Six live packets were parked and unreachable.
  run jq -r '.status' "$pkt";                 [ "$output" = "open" ]
  # PAIRED GUARD: an empty-string deadline, never an absent key. In jq a missing key is `null`, and
  # BOTH `null != ""` and `null < <now>` are true — so `status:"open"` with no deadline would make
  # cc-decide expire-sweep auto-fire this packet to `expired-actioned` against a null default,
  # silently closing a land-block no human ever saw. The empty string is what makes it never fire.
  run jq -r '.veto_deadline' "$pkt";          [ "$output" = "" ]
  run jq -r '.staged_artifact_path' "$pkt";   [ "$output" = "" ]
  # canonical field NAMES (session_sid / staged_artifact_path), so the board's own jq finds them
  run jq -e 'has("created") and has("session_sid") and has("route_around_taken")' "$pkt"
  [ "$status" -eq 0 ]
  # the evidence lines survive (additive schema growth is safe)
  run jq -e '.matched | length > 0' "$pkt"
  [ "$status" -eq 0 ]
  # never pushed
  git fetch -q origin main
  [ -z "$(git ls-tree origin/main -- migration.sql)" ]
}

@test "esc-scan packet is VISIBLE to cc-decide list --open (end-to-end producer→consumer)" {
  # The whole point of the schema: ship-land's park must reach the operator's board. This asserts
  # the two tools AGREE, so a future schema drift on either side fails here rather than silently
  # parking work no one can see. Pre-fix this found nothing — the packet had no `.status`.
  git checkout -q -b feat/esc-visible main
  printf 'DROP TABLE users;\n' > migration.sql
  git add migration.sql && git commit -q -m "feat: migration"

  run bash "$SHIPLAND" --trunk main
  [ "$status" -eq 3 ]

  CC_DECISIONS_DIR="$SHIP_LAND_DECISIONS_DIR" run bash "$REPO/bin/cc-decide" list --open
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'shipland-esc-'
  echo "$output" | grep -q '^open '
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

# ── EFFECT/DISCLOSURE class split + the declared exemption manifest ───────────────────────────────
# The rail's measured precision was ZERO (land.log: 506 clean / 11 hit; 9 packets, 0 of them a real
# destructive land). These five tests pin the fix at both edges: the benign class stops parking, and
# every path that could weaken the rail still parks. The manifest under test is the SHIPPED one,
# copied out of the repo — an approximation written inline here would pass vacuously while the real
# file exempted nothing.
install_esc_manifest() {
  mkdir -p scripts
  cp "$REPO/scripts/esc-exempt.manifest" scripts/esc-exempt.manifest
  git add scripts/esc-exempt.manifest
  git commit -q -m "chore: esc exemption manifest"
  git push -q origin main
}

@test "esc-scan: the REAL session-index retention GC on a declared cache path → NOT parked" {
  # RED-proof, replaying the actual artifact: these are the verbatim added lines of 28ade39a
  # `fix(session-index): staleness-aware lock + batched sweep before any unblock`, in their real
  # file. That commit parked FOUR times (packets shipland-esc-{1ca84e4,a877ec8,3511d99b,ab66db8})
  # and is still absent from origin/main — the rail blocked a complete, gate-green fix for days.
  # Asserted as "not exit 3 / no packet" rather than "exit 0" so the verdict is about esc_scan alone
  # and cannot be flipped by unrelated gate variance in the fixture.
  install_esc_manifest
  git checkout -q -b fix/session-index main
  mkdir -p hooks/lib
  cat > hooks/lib/session-index-helpers.sh <<'EOF'
#!/usr/bin/env bash
session_index_retention_gc() {
  local s="$1"
  session_index_sql "
DELETE FROM session_chunks WHERE session_id = '$s';
DELETE FROM chunks_fts    WHERE session_id = '$s';
DELETE FROM sessions_fts  WHERE session_id = '$s';
DELETE FROM sessions      WHERE session_id = '$s';
DELETE FROM file_tracking WHERE session_id = '$s';"
  session_index_sql "VACUUM;" >/dev/null 2>&1 || true
}
EOF
  git add hooks/lib/session-index-helpers.sh
  git commit -q -m "fix(session-index): retention GC"

  run bash "$SHIPLAND" --trunk main --dry-run
  [ "$status" -ne 3 ]
  ! echo "$output" | grep -qi "PARKED" || false   # `|| false`: a bare `!` is errexit-EXEMPT ⇒ dead
  [ -z "$(ls "$SHIP_LAND_DECISIONS_DIR"/*.json 2>/dev/null)" ]
}

@test "esc-scan: destructive SQL in a hooks/ path the manifest does NOT declare → still exit 3" {
  # Narrowness control. The exemption is per-file (hooks/session-index-*.sh), never the directory:
  # the rest of hooks/ is live actuation, which is exactly what this rail exists to stop. If this
  # goes green the exemption has widened past its declared population.
  install_esc_manifest
  git checkout -q -b feat/hookdrop main
  mkdir -p hooks
  printf '#!/usr/bin/env bash\nsqlite3 "$LIVE_DB" "DELETE FROM sessions;"\n' > hooks/reaper.sh
  git add hooks/reaper.sh
  git commit -q -m "feat: reaper"

  run bash "$SHIPLAND" --trunk main --dry-run
  [ "$status" -eq 3 ]
  echo "$output" | grep -qi "PARKED"
  echo "$output" | grep -q "hooks/reaper.sh: effect:" || false   # hits are FILE-attributed, not diff-relative
}

@test "esc-scan DISCLOSURE: a private key in an EXEMPT path (docs/) → still exit 3" {
  # The load-bearing half of the class split. docs/* is exempt for the EFFECT class because prose
  # cannot execute SQL — but a key pasted into a doc is exactly as leaked as one in code, so the
  # DISCLOSURE class must ignore the manifest entirely. If this ever goes green, the fix has
  # converted a documentation carve-out into a credential-leak carve-out.
  install_esc_manifest
  git checkout -q -b docs/leak main
  mkdir -p docs
  # The marker is ASSEMBLED at runtime so this source line does not itself carry the literal. The
  # DISCLOSURE class is never exemptible by design — tests/* included — so a literal here would trip
  # the rail on every land that touches this suite. The FIXTURE still contains the real pattern, so
  # the scanner under test sees exactly what it would see in the wild.
  printf 'Example config:\n\n-----BEGIN %s PRIVATE KEY-----\nMIIEowIBAAKCAQEA\n' RSA > docs/setup.md
  git add docs/setup.md
  git commit -q -m "docs: setup"

  run bash "$SHIPLAND" --trunk main --dry-run
  [ "$status" -eq 3 ]
  echo "$output" | grep -q "docs/setup.md: secret:" || false
}

@test "esc-scan: prose describing destructive SQL in docs/ → NOT parked" {
  # Three of the nine parks were audit/research docs describing this very defect, and the cost was
  # not only a blocked land: one author respelled the SQL as prose to evade the scan ("pattern
  # spelled as prose so the ship esc-scan doesn't match quoted SQL in docs") and it matched anyway.
  # A rail that corrupts the audit record buys nothing.
  install_esc_manifest
  git checkout -q -b docs/audit main
  mkdir -p docs/research
  printf 'Fix sketch: add a retention pass — DELETE FROM sessions WHERE file_path NOT IN (live set),\nplus a periodic VACUUM. Today grep for `DELETE FROM sessions` returns zero index-prune hits.\n' \
    > docs/research/audit.md
  git add docs/research/audit.md
  git commit -q -m "docs: audit"

  run bash "$SHIPLAND" --trunk main --dry-run
  [ "$status" -ne 3 ]
  [ -z "$(ls "$SHIP_LAND_DECISIONS_DIR"/*.json 2>/dev/null)" ]
}

@test "esc-scan: a NON-ASCII filename is still scanned → exit 3, never silently skipped" {
  # Fail-open guard for the per-file rewrite. `git diff --name-only` QUOTES a non-ASCII path
  # ("caf\303\251.sql"); fed back as a pathspec it matches nothing, so the file's diff reads empty
  # and the scan skips it entirely — destructive SQL would land unseen through nothing but a filename.
  # `-z` (raw bytes, no quoting) is what makes this green. Whole-range scanning could not miss a file,
  # so this hole is created by per-file iteration and has to be closed with it.
  install_esc_manifest
  git checkout -q -b feat/unicode main
  printf 'DROP TABLE users;\n' > 'café.sql'
  git add 'café.sql'
  git commit -q -m "feat: unicode migration"

  run bash "$SHIPLAND" --trunk main --dry-run
  [ "$status" -eq 3 ]
  echo "$output" | grep -q "effect:" || false
}

@test "esc-scan TRUST ROOT: a widening added IN the range is INERT for that land → still exit 3" {
  # The anti-self-exemption property, asserted directly. Without base-read this fix would be a
  # self-service bypass: a land could append `*` to the manifest and exempt its own destructive SQL
  # in the same commit. The `*` here would match wipe.sql if the manifest were read from the working
  # tree — it parks because the manifest is read from the BASE, where that entry does not exist.
  install_esc_manifest
  git checkout -q -b feat/widen main
  printf '\n*\n' >> scripts/esc-exempt.manifest
  printf 'DELETE FROM customers;\n' > wipe.sql
  git add scripts/esc-exempt.manifest wipe.sql
  git commit -q -m "feat: widen"

  run bash "$SHIPLAND" --trunk main --dry-run
  [ "$status" -eq 3 ]
  echo "$output" | grep -q "wipe.sql: effect:" || false      # the self-granted `*` did NOT apply
  echo "$output" | grep -q "INERT for this land" || false    # and the widening was announced
}

@test "esc-scan TRUST ROOT: an exemption already on the BASE does apply → NOT parked" {
  # The other half of base-read, and the one that proves the mechanism is a delay and not a block:
  # the same entry that was inert while it sat inside the range works normally once it is on the base.
  # Without this, "everything parks" would pass for correct behaviour.
  install_esc_manifest
  git checkout -q main
  printf '\ncache/*\n' >> scripts/esc-exempt.manifest
  git add scripts/esc-exempt.manifest
  git commit -q -m "chore: declare cache/ exempt"
  git push -q origin main

  git checkout -q -b feat/usecache main
  mkdir -p cache
  printf 'DELETE FROM warm_rows;\n' > cache/gc.sql
  git add cache/gc.sql
  git commit -q -m "feat: cache gc"

  run bash "$SHIPLAND" --trunk main --dry-run
  [ "$status" -ne 3 ]
  [ -z "$(ls "$SHIP_LAND_DECISIONS_DIR"/*.json 2>/dev/null)" ]
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

@test "v2 INVERSION: a GREEN land never advances gate-green — the verifier owns that marker" {
  # P0-1 made the land the gate-green PRODUCER, on the premise that a land proved the full suite.
  # v2 removes the premise (LAND_PIPELINE_V2 §4.1/§4.2): the land runs statics + a smoke over its
  # own diff and makes no full-suite claim, so GATE_EFFECTIVE_FULL is pinned to 0 and
  # stamp_gate_green self-noops in BOTH lanes. gate-green's consumers (boundary-handoff.sh:122,
  # wrap-ledger.sh:79) read it as "the FULL suite proved THIS tree" — a claim only the post-land
  # verifier can now make. Two writers for one marker is strictly worse than a stale one.
  # This test is the exact inverse of the P0-1 test it replaces; it fails against the pre-v2 tree.
  gc="$(git rev-parse --git-common-dir)"
  rm -f "$gc/gate-green"

  git checkout -q -b feat/gg main
  printf '#!/usr/bin/env bash\necho ok\n' > gg.sh
  git add gg.sh && git commit -q -m "feat: gg"
  run bash "$SHIPLAND" --trunk main --dry-run
  [ "$status" -eq 0 ]                                        # the gate really did run GREEN…
  [ ! -f "$gc/gate-green" ]                                  # …and still wrote nothing
  echo "$output" | grep -q "gate-green NOT advanced"         # and said so, out loud, once
  echo "$output" | grep -q "verifier owns that marker"

  # A red land obviously must not advance it either — the property that survived from P0-1.
  git checkout -q -b feat/gg-red main
  printf '#!/usr/bin/env bash\ncd /tmp/nope\necho ok\n' > bad-gg.sh   # SC2164 → shellcheck RED
  git add bad-gg.sh && git commit -q -m "feat: bad-gg"
  redhead="$(git rev-parse HEAD)"
  run bash "$SHIPLAND" --trunk main --dry-run
  [ "$status" -eq 6 ]
  [ "$(cat "$gc/gate-green" 2>/dev/null || echo none)" != "$redhead" ]   # unproven tree never green
}

@test "v2 INVERSION: the v1 kill switch does NOT restore gate-green stamping either" {
  # LANE=v1 restores the corpus PROOF, never the marker. Pinned separately because "the corpus ran,
  # so surely we may stamp" is the obvious wrong turn, and it would hand the marker two writers
  # (this land and the verifier) racing on one file.
  scope_fixture
  gc="$(git rev-parse --git-common-dir)"; rm -f "$gc/gate-green"
  landable feat/gg-v1 ggv1.sh

  run env SHIP_LAND_LANE=v1 bash "$SHIPLAND" --trunk main
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "FULL corpus green"               # the corpus genuinely ran…
  [ ! -f "$gc/gate-green" ]                                  # …and still stamped nothing
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

# ════ SMOKE — the land's only test work (LAND_PIPELINE_V2 §4.1) ════════════════════════════════
#
# The fixture repo has no tests/ dir, so the gate's bats step never fires by default. These
# tests SEED suites onto trunk and PATH-shim `bats`: the shim's recorded argv is the durable
# product ("which suites actually ran"), and it injects a first-run-only failure for the flake
# fixture. A nested REAL bats run is deliberately avoided — argv is what is under test.
#
# WHAT THE v1 TESTS HERE ASSERTED, AND WHY THEY ARE GONE. This block used to pin the gate SCOPE
# machinery: full ⇒ `bats tests/`, scoped ⇒ the selector's list, and four ways scoped DEGRADED to
# a full corpus (absent selector · red map lint · INERT post-land net · policy fallback). Every
# one of those degradations is now a deleted code path, and deleting them was the point: each was
# a fail-closed rule that answered uncertainty by running MORE bats on a box that was already
# losing to bats (R7, the amplifier law). What replaces them is one rule with no degradation
# ladder at all — run the `--direct` suites of THIS diff under a wall budget, and on ANY doubt
# (no selector, selector says FULL, nothing selected, load too high, budget spent) run NOTHING and
# let the post-land verifier prove the tree. The tests below pin the inversions specifically,
# because "fail closed toward more proof" is the intuitive wrong answer someone will try to
# restore. `smoke:"…"` in land.log is the durable evidence of which branch fired.
#
# The v1 assertions were also MONOLITH-PINNED (`= "tests/"`, and counts assuming one process for
# the whole corpus) via SHIP_LAND_FULL_PER_SUITE=off. That flag and its runner are deleted; the
# only surviving corpus runner is the LANE=v1 kill switch, whose tests live in "LANE=v1 CORPUS".

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
  # A NAMED failure, not a bare rc — a FLAKE is a test that fails and then passes, and the
  # discriminator between that and a machine event is the TAP body. This shim used to emit
  # \`exit 1\` with no output, i.e. a CUT, so every test built on it was really asserting
  # cut-then-green behaviour under the word "flake". Fixed with the carve-out it mis-pinned.
  if [ ! -f "\$m" ]; then : > "\$m"; echo "1..1"; echo "not ok 1 intermittent"; exit 1; fi
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
  # DEFAULT THE SELECTOR TO A STUB (v2). Unstubbed, SHIP_LAND_GATE_SELECT falls back to the REAL
  # scripts/gate-select.sh, and in v1 that was harmless because full mode ignored selection — the
  # smoke does NOT ignore it, so an unstubbed fixture would run the real ~2s python selector
  # against a scratch repo and take its answer as a verdict input. A fixture's outcome must never
  # depend on the real repo's suite map. Empty ⇒ no direct suites ⇒ no smoke; every test that wants
  # a smoke calls stub_selector itself, which simply overwrites this.
  stub_selector "" ""
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

@test "smoke: runs ONLY the --direct suites of this diff, never the corpus" {
  # THE headline v2 property. The selector's plain (non---direct) answer names b.bats, and the
  # corpus contains BOTH a and b — so a runner that consulted either the plain selection or
  # tests/*.bats would show up here. Only the --direct list may run.
  scope_fixture
  stub_selector "tests/b.bats" "tests/a.bats"     # plain says b · DIRECT says a
  landable feat/smoke-direct sd.sh

  run bash "$SHIPLAND" --trunk main
  [ "$status" -eq 0 ]
  [ "$(cat "$BATS_ARGV")" = "tests/a.bats" ]                 # exactly the direct suite…
  [ "$(grep -cx 'tests/b.bats' "$BATS_ARGV")" -eq 0 ]        # …not the plain selection…
  [ "$(grep -cx 'tests/' "$BATS_ARGV")" -eq 0 ]              # …and never a corpus invocation
  grep -q '"gate_scope":"fast"' "$LAND_LOG"
  grep -q '"smoke":"green"' "$LAND_LOG"
  grep -q '"smoke_n":1' "$LAND_LOG"
}

@test "smoke: 0 direct suites ⇒ no bats at all, land proceeds (lint-only land)" {
  scope_fixture
  stub_selector "tests/a.bats" ""                 # a plain selection exists; NO direct suites
  landable feat/smoke-none sn.sh

  run bash "$SHIPLAND" --trunk main
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "0 direct suite"
  [ ! -s "$BATS_ARGV" ]                                      # bats never invoked at all
  grep -q '"smoke":"none"' "$LAND_LOG"
  grep -q '"smoke_n":0' "$LAND_LOG"
  git fetch -q origin main
  [ -n "$(git ls-tree origin/main -- sn.sh)" ]               # lint-only land still lands
}

@test "smoke INVERSION: an ABSENT selector lands with NO smoke — never the v1 FULL fallback" {
  # v1: a missing selector meant FULL (fail-closed toward more proof). That is the single worst
  # place to widen: the selector is missing exactly on the live-symlink path, where a brand-new
  # tracked file has no symlink yet — i.e. on the busiest boxes, and it is the measured amplifier
  # in the 2026-07-26 gate runaway (f8e40b4c577d). v2 inverts it: no selection ⇒ no smoke ⇒ the
  # verifier proves the tree. PINNED so nobody restores the widening as a "safety" improvement.
  scope_fixture
  export SHIP_LAND_GATE_SELECT="$BATS_TEST_TMPDIR/no-such-selector.sh"
  landable feat/smoke-nosel sns.sh

  run bash "$SHIPLAND" --trunk main
  [ "$status" -eq 0 ]                                        # a missing selector never blocks…
  echo "$output" | grep -q "missing/not executable"
  echo "$output" | grep -q "verifier proves this tree"
  [ ! -s "$BATS_ARGV" ]                                      # …and never widens: ZERO bats runs
  grep -q '"smoke":"none"' "$LAND_LOG"
  git fetch -q origin main
  [ -n "$(git ls-tree origin/main -- sns.sh)" ]              # and the land completes
}

@test "smoke INVERSION: selector answering FULL ⇒ no smoke (its 'cannot decide', not 'run all')" {
  # FULL is gate-select's OWN fail-closed output for any uncertainty (unmapped file, unparseable
  # range, missing python3). In v1 it bought a corpus; in v2 it can only mean "this selection is
  # untrustworthy", so it buys nothing and the verifier decides. The twin of the test above.
  scope_fixture
  stub_selector "FULL" "FULL"
  landable feat/smoke-fullsel sfs.sh

  run bash "$SHIPLAND" --trunk main
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "cannot decide"
  [ ! -s "$BATS_ARGV" ]                                      # no corpus, no single suite, nothing
  grep -q '"smoke":"none"' "$LAND_LOG"
}

@test "smoke: HOST-manifest suites are excluded — the partition binds the land lane too" {
  # §4.2.2. The verifier runs tests/*.bats MINUS scripts/host-suites.manifest, and the deploy lane
  # runs exactly that manifest POST-deploy against the live layer they actually assert. A host
  # suite that re-enters through the SMOKE rebuilds the bootstrap circle one lane over — and it
  # re-enters trivially, because touching a host suite makes it a DIRECT suite of your diff. The
  # v2 bootstrap land is exactly such a land: tests/deploy-parity.bats test 8 is TRUE-red on this
  # box right now (the live layer is missing a symlink), so unfiltered it would exit-6 a land whose
  # TREE is fine, for a live-layer fact the tree cannot control.
  #
  # A DIFFERENTIAL, not a bare negative: "a.bats did not run" is trivially true of a build whose
  # smoke runs nothing at all, so the SAME run must show the unlisted suite DID run. The manifest
  # also carries a comment and a blank line, because those are in the frozen format contract.
  scope_fixture
  stub_selector "" "$(printf 'tests/a.bats\ntests/b.bats')"
  mkdir -p scripts
  printf '# host suites — asserted POST-deploy against the live layer\n\ntests/a.bats\n' \
    > scripts/host-suites.manifest
  git add scripts && git commit -q -m "seed host manifest" && git push -q origin HEAD:main
  git fetch -q origin main
  landable feat/host-manifest hm.sh

  run bash "$SHIPLAND" --trunk main
  [ "$status" -eq 0 ]
  [ "$(grep -cx 'tests/a.bats' "$BATS_ARGV")" -eq 0 ]   # LISTED ⇒ never handed to bats (the spy)
  [ "$(grep -cx 'tests/b.bats' "$BATS_ARGV")" -eq 1 ]   # UNLISTED ⇒ still smoked (the differential)
  echo "$output" | grep -q "post-deploy check owns it"
  grep -q '"smoke":"green"' "$LAND_LOG"
  grep -q '"smoke_n":1' "$LAND_LOG"                     # the attest reflects the FILTERED count
}

@test "smoke: NO manifest ⇒ no filtering (the pre-adoption state must not silently narrow)" {
  # The control leg for the test above, on the same fixture: without the manifest BOTH suites run,
  # so the exclusion above is the manifest's doing and not an artifact of the selector or the shim.
  # It is also the state every other test in this file runs in, and the state of the tree until
  # the verifier lands its manifest — a missing file must never mean "smoke nothing".
  scope_fixture
  stub_selector "" "$(printf 'tests/a.bats\ntests/b.bats')"
  landable feat/no-manifest nm.sh

  run bash "$SHIPLAND" --trunk main
  [ "$status" -eq 0 ]
  [ "$(grep -cx 'tests/a.bats' "$BATS_ARGV")" -eq 1 ]
  [ "$(grep -cx 'tests/b.bats' "$BATS_ARGV")" -eq 1 ]
  [ "$(echo "$output" | grep -c 'post-deploy check owns it')" -eq 0 ]
  grep -q '"smoke_n":2' "$LAND_LOG"
}

@test "smoke: a manifest that swallows EVERY direct suite is a lint-only land, not an error" {
  # The degenerate case, and it must take the cheap branch: no smoke, no clone, exit 0. A land
  # touching only host suites is the normal shape of a live-layer fix.
  scope_fixture
  stub_selector "" "tests/a.bats"
  mkdir -p scripts
  printf 'tests/a.bats\ntests/b.bats\n' > scripts/host-suites.manifest
  git add scripts && git commit -q -m "seed host manifest (all)" && git push -q origin HEAD:main
  git fetch -q origin main
  landable feat/host-all hma.sh

  run bash "$SHIPLAND" --trunk main
  [ "$status" -eq 0 ]
  [ ! -s "$BATS_ARGV" ]
  echo "$output" | grep -q "0 direct suite"
  grep -q '"smoke":"none"' "$LAND_LOG"
}

@test "lane: unknown SHIP_LAND_LANE ⇒ exit 2; SHIP_LAND_GATE_SCOPE still validated for back-compat" {
  run env SHIP_LAND_LANE=bogus bash "$SHIPLAND" --trunk main
  [ "$status" -eq 2 ]
  echo "$output" | grep -q "unknown SHIP_LAND_LANE"

  # SCOPE is inert in v2 but still parsed and validated, so an operator's committed policy file or
  # stale env cannot turn a land into a hard exit-2 on an unrelated flag — and a typo stays loud.
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

@test "smoke: the run-list IS the direct-list, so NO smoke suite can ever be exonerated" {
  # A structural property of run_smoke, not of run_scoped_suite: the smoke hands its own selection
  # to the runner AS the direct set, so the carve-out covers every suite it runs. The consequence
  # is that flake-exoneration cannot fire in the fast lane at ALL for a named failure — its
  # surviving home is the LANE=v1 corpus, where NON-direct suites exist (twin in that section).
  # The `--direct` list here names ONLY a.bats while the selector's plain list names b.bats, so a
  # build that passed the plain list as the direct set would exonerate a.bats and land green.
  scope_fixture
  stub_selector "tests/b.bats" "tests/a.bats"   # plain: b · DIRECT: a — deliberately disjoint
  echo "tests/a.bats" > "$FLAKE_ONCE"           # a NAMES a failure once, passes the re-run
  landable feat/flake-direct fld.sh

  run bash "$SHIPLAND" --trunk main
  [ "$status" -eq 6 ]
  echo "$output" | grep -q "finding, not a flake"
  [ "$(echo "$output" | grep -c "EXONERATED")" -eq 0 ]       # never exonerated…
  [ ! -f "$POSTLAND_DIR/flakes.jsonl" ]                      # …⇒ never logged
  grep -q '"smoke":"red"' "$LAND_LOG"
  git fetch -q origin main
  [ -z "$(git ls-tree origin/main -- fld.sh)" ]              # and NOT landed
}

@test "attest: land.log carries head/base/tree + the v2 lane/smoke/net fields" {
  landable feat/attest-fields af.sh
  base="$(git rev-parse origin/main)"

  run bash "$SHIPLAND" --trunk main
  [ "$status" -eq 0 ]
  grep -q "\"head\":\"$(git rev-parse HEAD)\"" "$LAND_LOG"
  grep -q "\"tree\":\"$(git rev-parse 'HEAD^{tree}')\"" "$LAND_LOG"
  grep -q "\"base\":\"$base\"" "$LAND_LOG"
  grep -q '"gate_scope":"fast"' "$LAND_LOG"                  # the LANE, not the dead scope
  grep -qE '"smoke":"(green|red|partial|skipped|none)"' "$LAND_LOG"
  grep -qE '"smoke_n":[0-9]+' "$LAND_LOG"
  grep -qE '"smoke_s":[0-9]+' "$LAND_LOG"
  grep -qE '"net":"(live|inert|none)"' "$LAND_LOG"
  grep -q '"selected_n":' "$LAND_LOG"
}

# ── the post-land net: DETECTED and ATTESTED, never a control-flow input ──────────────────────
# Stamp mtimes are seeded RELATIVE to now with a SIGNED offset (`date -v -48H`), never an absolute
# literal: a fixture pinned to a wall-clock constant changes meaning as the clock advances and has
# already taken the fleet's gate down on a calendar boundary with no code change.

@test "net INVERSION: an INERT verifier WARNS and the land PROCEEDS — never a corpus degrade" {
  # v1: stamps exist but the newest GREEN one has gone cold ⇒ "do not narrow" ⇒ run the FULL
  # corpus. That is the amplifier law (R7) at its purest: the net goes inert precisely when the box
  # is wedged, and the response was to add 40 minutes of bats per land to a wedged box. v2 keeps
  # the detection and drops the escalation — warn, attest net:"inert", land. Nothing is lost: the
  # land never made the full-suite claim, so an inert net costs verification LATENCY, which R9's
  # freshness alarm surfaces to the operator.
  scope_fixture
  stub_selector "" "tests/a.bats"
  mkdir -p "$POSTLAND_DIR/stamps"
  printf '{"head":"deadbee","verdict":"green"}\n' > "$POSTLAND_DIR/stamps/deadbee.json"
  printf '{"head":"newer","verdict":"red"}\n' > "$POSTLAND_DIR/stamps/newer.json"   # red ≠ liveness
  touch -t "$(date -v -48H +%Y%m%d%H%M)" "$POSTLAND_DIR/stamps/deadbee.json"   # ran once, went cold
  landable feat/stale-net stn.sh

  run bash "$SHIPLAND" --trunk main
  [ "$status" -eq 0 ]                                        # LANDS — the whole inversion
  echo "$output" | grep -q "looks INERT"                     # …loudly
  echo "$output" | grep -q "This land PROCEEDS"
  grep -q '"net":"inert"' "$LAND_LOG"                        # …and durably
  [ "$(cat "$BATS_ARGV")" = "tests/a.bats" ]                 # the smoke is UNCHANGED by the net…
  [ "$(grep -cx 'tests/' "$BATS_ARGV")" -eq 0 ]              # …and no corpus was summoned
  git fetch -q origin main
  [ -n "$(git ls-tree origin/main -- stn.sh)" ]
}

@test "net: a fresh GREEN stamp ⇒ net:live, no warning; kill switch ⇒ net:none" {
  # The positive control for the test above: if the staleness clock were simply broken, "inert"
  # would fire always or never and both tests would still look sane in isolation. This pins the
  # OTHER side of the discriminator on the same fixture shape.
  scope_fixture
  stub_selector "" "tests/a.bats"
  mkdir -p "$POSTLAND_DIR/stamps"
  printf '{"head":"fresh","verdict":"green"}\n' > "$POSTLAND_DIR/stamps/fresh.json"   # live net
  landable feat/fresh-net frn.sh
  run bash "$SHIPLAND" --trunk main
  [ "$status" -eq 0 ]
  grep -q '"net":"live"' "$LAND_LOG"
  [ "$(echo "$output" | grep -c "looks INERT")" -eq 0 ]

  : > "$BATS_ARGV"
  touch -t "$(date -v -48H +%Y%m%d%H%M)" "$POSTLAND_DIR/stamps/fresh.json"   # cold, guard disabled
  landable feat/killswitch ks.sh
  run env POSTLAND_STALENESS_GUARD=off bash "$SHIPLAND" --trunk main
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | grep -c "looks INERT")" -eq 0 ]      # the kill switch really is one
  grep -q '"net":"none"' "$LAND_LOG"                         # guard off ⇒ nothing measured
}

@test "net: stamps with NO green one yet ⇒ 'not adopted', not 'inert' (bootstrap must not warn)" {
  scope_fixture
  stub_selector "" "tests/a.bats"
  mkdir -p "$POSTLAND_DIR/stamps"
  printf '{"head":"only","verdict":"red"}\n' > "$POSTLAND_DIR/stamps/only.json"
  touch -t "$(date -v -48H +%Y%m%d%H%M)" "$POSTLAND_DIR/stamps/only.json"   # ancient, never green
  landable feat/bootstrap bs.sh

  run bash "$SHIPLAND" --trunk main
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | grep -c "looks INERT")" -eq 0 ]      # a net that never went green is
  grep -q '"net":"none"' "$LAND_LOG"                         # "not adopted", not "inert"
}

# ════ SMOKE VERDICTS — red blocks · cut proceeds · the budget is a wall ════════════════════════
# bats masks a signal death: `bats:517-524` pipes exec bats-exec-suite through
# bats_test_count_validator under `set -o pipefail` (:501), and the validator returns 1 on a
# truncated TAP — so a killed suite surfaces as plain `1`, never 137/143. The TAP BODY is the only
# honest discriminator. v2 keeps that discriminator inside run_scoped_suite and changes only what
# the SMOKE does with a non-verdict: it proceeds. The land never claimed the corpus, so a suite
# that earned no verdict removes no claim — and blocking on one is the kill → "RED" → re-block →
# dispatcher-retry runaway (f8e40b4c577d). A NAMED failure is the opposite: O(your diff),
# reproducible, and the highest-value seconds in the pipeline ⇒ exit 6.
cut_fixture() {   # shim `bats` that can produce EITHER a cut (rc!=0, zero output) or a real red
  SHIMDIR="$BATS_TEST_TMPDIR/shims-cut"; mkdir -p "$SHIMDIR"
  export BATS_ARGV="$BATS_TEST_TMPDIR/bats-argv-cut"
  export CUT_MODE="$BATS_TEST_TMPDIR/cut-mode"
  cat > "$SHIMDIR/bats" <<EOF
#!/bin/bash
printf '%s\n' "\$*" >> "$BATS_ARGV"
case "\$(cat "$CUT_MODE" 2>/dev/null)" in
  red)  echo "1..1"; echo "not ok 1 a genuine failure"; exit 1 ;;  # a REAL red: a not-ok IS present
  hang) sleep 120; exit 0 ;;                                       # outlives any sane budget
  cut)  exit 1 ;;                                                  # a CUT: rc!=0, ZERO output, always
  red-once)                                                        # NAMES a failure, then passes —
    if [ ! -f "$BATS_TEST_TMPDIR/red-once-done" ]; then             # the carve-out's real subject
      : > "$BATS_TEST_TMPDIR/red-once-done"; echo "1..1"; echo "not ok 1 intermittent"; exit 1
    fi
    echo "1..1"; echo "ok 1 green on the re-run"; exit 0 ;;
esac
if [ ! -f "$BATS_TEST_TMPDIR/cut-done" ]; then
  : > "$BATS_TEST_TMPDIR/cut-done"; exit 1                    # cut ONCE, then green on the re-run
fi
echo "1..1"; echo "ok 1 green on the re-run"; exit 0
EOF
  chmod +x "$SHIMDIR/bats"
  export PATH="$SHIMDIR:$PATH"
  export SHIP_LAND_GATE_POLICY="$BATS_TEST_TMPDIR/no-such-policy.sh"
  mkdir -p tests
  printf '#!/usr/bin/env bats\n@test "a" { true; }\n' > tests/a.bats
  git add tests && git commit -q -m "seed suites" && git push -q origin HEAD:main
  git fetch -q origin main
  stub_selector "" "tests/a.bats"                              # a is the DIRECT suite under test
}

@test "smoke: a CUT-then-green DIRECT suite LANDS — a cut is not 'intermittence in your diff'" {
  # THE DEFECT THIS TEST FOUND (v1, latent; v2, live). The DIRECT carve-out — "a suite of THIS
  # change that passes only on retry is a finding, not a flake" — was keyed on "the first run was
  # non-zero", which lumps a CUT in with a NAMED failure. v1 mostly got away with it because only
  # a minority of suites were ever direct. v2 cannot: the smoke passes its own list as the direct
  # set, so EVERY smoke suite is direct, and the per-child `timeout` deliberately manufactures cuts
  # on a slow-but-green suite. Unfixed, "the box was busy for 30s" became exit 6 on a green tree.
  # The carve-out is now keyed on a NAMED failure in the first run; the fence itself is untouched
  # (see the POSITIVE CONTROL below, and the v1-lane twin).
  cut_fixture                                             # default mode: cut once, green on re-run
  landable feat/cut cut.sh
  run bash "$SHIPLAND" --trunk main
  [ "$status" -eq 0 ]                                     # a cut must NOT be a landing failure
  echo "$output" | grep -q "CUT, not RED"
  echo "$output" | grep -q "EXONERATED"
  [ "$(grep -cx 'tests/a.bats' "$BATS_ARGV")" -eq 2 ]     # ran twice: original + the one re-run
  grep -q '"smoke":"green"' "$LAND_LOG"                   # green on the re-run ⇒ a real green
  grep -q '"outcome":"pass-on-retry"' "$POSTLAND_DIR/flakes.jsonl"   # never silent
  git fetch -q origin main
  [ -n "$(git ls-tree origin/main -- cut.sh)" ]
}

@test "smoke CARVE-OUT CONTROL: a NAMED failure that passes on retry is still RED in a direct suite" {
  # The other side of the fix above: keying on `notok` must not have disabled the fence. A first
  # run that NAMES a failure and then goes green is intermittence in code you are landing — a
  # finding. If this ever passes green, the carve-out has been softened into nothing.
  cut_fixture
  echo red-once > "$CUT_MODE"                             # names a failure, then passes
  landable feat/red-once ro.sh

  run bash "$SHIPLAND" --trunk main
  [ "$status" -eq 6 ]
  echo "$output" | grep -q "finding, not a flake"
  [ ! -f "$POSTLAND_DIR/flakes.jsonl" ]                   # never exonerated ⇒ never logged
  git fetch -q origin main
  [ -z "$(git ls-tree origin/main -- ro.sh)" ]
}

@test "smoke INVERSION: a suite CUT TWICE PROCEEDS as partial — never exit 9, never a block" {
  # THE v2 inversion of the GATE-KILLED contract. Under v1 this exact fixture exited 9 and pushed
  # nothing; the tree was fine and the box was busy, so the land was blocked by a fact about the
  # MACHINE. In the fast lane a non-verdict cannot block: it is recorded (flakes.jsonl keeps the
  # denominator and names WHICH suite ran out of machine), attested smoke:"partial", and the land
  # completes. Exit 9 is now unreachable from the smoke — asserted explicitly below.
  cut_fixture
  echo cut > "$CUT_MODE"                                  # cut on EVERY run ⇒ cut twice
  landable feat/cut-twice ct.sh

  run bash "$SHIPLAND" --trunk main
  [ "$status" -eq 0 ]                                     # NOT 9, NOT 6 — it LANDS
  [ "$(echo "$output" | grep -c "GATE-KILLED")" -eq 1 ]   # the non-verdict WAS detected…
  [ "$(echo "$output" | grep -c "GATE RED")" -eq 0 ]      # …and never mislabelled a red
  echo "$output" | grep -q "smoke PARTIAL"
  [ "$(grep -cx 'tests/a.bats' "$BATS_ARGV")" -eq 2 ]     # run + ONE bounded re-run, then stop
  grep -q '"smoke":"partial"' "$LAND_LOG"
  [ "$(grep -c '"exit":9' "$LAND_LOG")" -eq 0 ]           # exit 9 is unreachable from the smoke
  grep -q '"outcome":"cut-not-red"' "$POSTLAND_DIR/flakes.jsonl"   # …but never SILENT
  grep -q '"file":"tests/a.bats"' "$POSTLAND_DIR/flakes.jsonl"     # names the suite, not "tests/"
  git fetch -q origin main
  [ -n "$(git ls-tree origin/main -- ct.sh)" ]            # the land completed
}

@test "smoke POSITIVE CONTROL: a NAMED failure is RED (exit 6) and does NOT land" {
  # Without this the test above is worthless: a smoke that proceeded on EVERYTHING would pass it.
  # A named `not ok` is a verdict about the diff and must block, re-run or not.
  cut_fixture
  echo red > "$CUT_MODE"
  landable feat/red red.sh
  run bash "$SHIPLAND" --trunk main
  [ "$status" -eq 6 ]                                     # gate RED ⇒ exit 6, unchanged from v1
  echo "$output" | grep -q "smoke RED"
  [ "$(echo "$output" | grep -c "GATE-KILLED")" -eq 0 ]   # a verdict is never softened
  grep -q '"smoke":"red"' "$LAND_LOG"
  git fetch -q origin main
  [ -z "$(git ls-tree origin/main -- red.sh)" ]           # fail-closed: nothing landed
}

@test "smoke: the wall BUDGET kills a hanging suite and the land PROCEEDS as partial" {
  # R5: every step bounded by an absolute-path timeout(1), and ONE deadline for the whole phase so
  # the bound cannot multiply across children (run_scoped_suite alone calls bats twice per suite).
  # The v1 failure this replaces is the unbounded cc-inbox-guard fork that hung gates for five days
  # — rc 124 with notok=0, a HANG that no exit code distinguished from a pass.
  cut_fixture
  echo hang > "$CUT_MODE"                                 # sleeps 120s; the budget is 3s
  landable feat/budget bg.sh

  run env SHIP_LAND_SMOKE_BUDGET_S=3 bash "$SHIPLAND" --trunk main
  [ "$status" -eq 0 ]                                     # bounded ⇒ it PROCEEDS, it does not hang
  echo "$output" | grep -q "smoke PARTIAL"
  grep -q '"smoke":"partial"' "$LAND_LOG"
  git fetch -q origin main
  [ -n "$(git ls-tree origin/main -- bg.sh)" ]
}

@test "smoke: the budget is a TOTAL, so later suites are skipped rather than each given a fresh one" {
  # The per-call-vs-per-run distinction that turned a 600s admission bound into 21h of "bounded"
  # waiting. With two hanging suites and a 3s TOTAL, suite b must never be STARTED — a per-suite
  # budget would run it for another 3s. Pinned because the multiplication bug is invisible in any
  # single-suite fixture.
  cut_fixture
  printf '#!/usr/bin/env bats\n@test "b" { true; }\n' > tests/b.bats
  git add tests/b.bats && git commit -q -m "seed b" && git push -q origin HEAD:main
  git fetch -q origin main
  stub_selector "" "$(printf 'tests/a.bats\ntests/b.bats')"
  echo hang > "$CUT_MODE"
  landable feat/budget-total bgt.sh

  run env SHIP_LAND_SMOKE_BUDGET_S=3 bash "$SHIPLAND" --trunk main
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "budget 3s exhausted"
  [ "$(grep -cx 'tests/b.bats' "$BATS_ARGV")" -eq 0 ]     # never STARTED — the total really is total
  grep -q '"smoke":"partial"' "$LAND_LOG"
  grep -q '"smoke_n":1' "$LAND_LOG"                       # one suite attempted, honestly counted
}

# ════ LOAD SHEDDING — shed is a SKIP, never a wait (R7) ════════════════════════════════════════
# gate_admit is DELETED, so its four tests (kill switch · fail-open · bounded wait · no-wait under
# the lock) went with it. Three of those properties survive in load_above_ceiling, which is a pure
# predicate with no clock: the "bounded wait" one has no successor BY DESIGN — there is no wait to
# bound. Driven by extraction because the contract is a decision, not a pipeline. Assertions use
# `|| false` because a non-final [[ ]] / bare compound is errexit-EXEMPT in bats ⇒ a DEAD assertion.
shed_probe() {  # $@ = env assignments → runs load_above_ceiling once, echoes ABOVE/BELOW
  { sed -n '/^load_above_ceiling() {/,/^}/p' "$SHIPLAND"
    printf 'if load_above_ceiling; then echo ABOVE; else echo BELOW; fi\n'
  } > "$BATS_TEST_TMPDIR/shed.sh"
  # Positive control: a silent sed miss (renamed/moved function) would leave a probe that echoes
  # BELOW for every input and "passes" three of the four assertions vacuously.
  grep -q 'sysctl -n vm.loadavg' "$BATS_TEST_TMPDIR/shed.sh" || return 1
  env "$@" bash "$BATS_TEST_TMPDIR/shed.sh" 2>&1
}

@test "shed: an unsatisfiable ceiling reads ABOVE; a huge one reads BELOW (it measures at all)" {
  run bash -c "$(declare -f shed_probe); SHIPLAND='$SHIPLAND' BATS_TEST_TMPDIR='$BATS_TEST_TMPDIR' \
    shed_probe CC_GATE_MAX_LOAD=0.0001"
  [ "$status" -eq 0 ]
  [ "$output" = "ABOVE" ]                            # 0.0001 is below any real loadavg
  run bash -c "$(declare -f shed_probe); SHIPLAND='$SHIPLAND' BATS_TEST_TMPDIR='$BATS_TEST_TMPDIR' \
    shed_probe CC_GATE_MAX_LOAD=100000"
  [ "$status" -eq 0 ]
  [ "$output" = "BELOW" ]                            # …and both directions are reachable
}

@test "shed: kill switch (0|off) and a non-numeric ceiling BOTH fail OPEN (never invent a skip)" {
  # Fail-open here means "run the bounded smoke", which is safe in a way it was not for gate_admit:
  # the thing being admitted is now capped by a wall budget, so a broken sensor costs latency and
  # can never restore the corpus.
  for v in 0 off bogus; do
    run bash -c "$(declare -f shed_probe); SHIPLAND='$SHIPLAND' BATS_TEST_TMPDIR='$BATS_TEST_TMPDIR' \
      shed_probe CC_GATE_MAX_LOAD=$v"
    [ "$status" -eq 0 ]
    [ "$output" = "BELOW" ] || false
  done
}

@test "shed: NEVER sleeps — the deleted wait must not come back as a poll loop" {
  # The load-bearing regression. gate_admit's sleep is what starved five gates below their OWN
  # ceiling; a successor that "just polls briefly" would rebuild it. Two independent assertions:
  # the predicate is instant, and the SOURCE contains no sleep anywhere in the land path.
  start="$(date +%s)"
  run bash -c "$(declare -f shed_probe); SHIPLAND='$SHIPLAND' BATS_TEST_TMPDIR='$BATS_TEST_TMPDIR' \
    shed_probe CC_GATE_MAX_LOAD=0.0001"
  [ "$status" -eq 0 ]
  [ "$(( $(date +%s) - start ))" -le 2 ]                              # instant, even when ABOVE

  # Full-line comments are stripped FIRST, then `sleep` must be followed by an argument. Written
  # that way because the naive pattern matched this file's own PROSE about the deleted sleeps and
  # failed on a tree with no sleep in it — a test that cannot pass is not a test. Controls run
  # while writing it: `do sleep 5`, `{ sleep 3; }`, `sleep "$step"`, `&& sleep 1`,
  # `sleep $((step+jit))` each score 1; a comment saying "sleeping 600 seconds per call" scores 0.
  [ "$(grep -vE '^[[:space:]]*#' "$SHIPLAND" | grep -cE '(^|[^[:alnum:]_])sleep[[:space:]]+[-0-9"'"'"'$]')" -eq 0 ] || false
}

@test "shed: load >= ceiling ⇒ smoke SKIPPED, ZERO bats, land proceeds and attests it" {
  # The end-to-end half: the predicate above, wired into a real pipeline. Shedding defers to the
  # post-land verifier, never to a queue — so the land completes with no test work at all.
  scope_fixture
  stub_selector "" "tests/a.bats"
  landable feat/shed shd.sh

  run env CC_GATE_MAX_LOAD=0.0001 bash "$SHIPLAND" --trunk main
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "smoke SKIPPED"
  echo "$output" | grep -q "never a wait"
  [ ! -s "$BATS_ARGV" ]                                   # not one suite was started
  grep -q '"smoke":"skipped"' "$LAND_LOG"
  grep -q '"smoke_n":0' "$LAND_LOG"
  git fetch -q origin main
  [ -n "$(git ls-tree origin/main -- shd.sh)" ]           # a busy box never blocks a land
}

# ════ GATE-KILLED, LANE=v1 — signal death is a THIRD state, never RED (backlog 9c5d0ba74e79) ═══
# The live signature these reproduce: a gate ran green through 1359 tests, then `bats tests/
# Killed: 9`, and ship-land printed "gate: bats RED / not pushing" — byte-indistinguishable from a
# real red, so the retry read as flaky tests instead of "we ran out of machine".
#
# WHY THESE ARE NOW v1-LANED. exit 9 is a claim "the gate ran and earned no verdict", and only a
# runner that OWNS a verdict can make it. The fast lane's smoke owns none — it is a bounded look at
# your diff, so a cut there proceeds (see "smoke INVERSION: a suite CUT TWICE PROCEEDS"). The v1
# corpus still owns the full-suite verdict, so the whole 6-vs-9 split lives on here, unchanged, and
# is exercised on every run of this suite rather than rotting behind an untested kill switch.
# The two lanes' rules are NOT in tension: v1 blocks on a non-verdict because it was asked to
# PROVE the tree; the fast lane proceeds because it never claimed to.
# RED-PROOF: every assertion below fails against the pre-c605a2e tree, where EVERY non-zero bats
# exit produced "GATE RED" + exit 6. The `red` and `startup` cases are the positive controls — if
# the kill path ever starts swallowing genuine failures, those two go red.
# Counts are per-suite arithmetic: scope_fixture seeds TWO suites, so a corpus-wide cut is 2 × (run
# + one bounded re-run) = 4 invocations, not 2.

@test "v1 gate-killed: a SIGNAL-killed corpus exits 9 (not 6), pushes nothing, retries once each" {
  scope_fixture
  echo sig > "$KILL_MODE"
  gc="$(git rev-parse --git-common-dir)"; rm -f "$gc/gate-green"
  landable feat/killed gk.sh

  run env SHIP_LAND_LANE=v1 bash "$SHIPLAND" --trunk main
  [ "$status" -eq 9 ]                                          # 9 = no verdict, NOT 6 = red
  echo "$output" | grep -q "GATE-KILLED" || false
  ! echo "$output" | grep -q "GATE RED" || false               # never both, never the wrong one
  [ "$(grep -c . "$BATS_ARGV")" -eq 4 ]                        # 2 suites × (run + ONE re-run)
  [ ! -f "$gc/gate-green" ]                                    # a kill proves nothing ⇒ no marker
  git fetch -q origin main
  [ -z "$(git ls-tree origin/main -- gk.sh)" ]                 # fail-closed: nothing landed
}

@test "v1 gate-killed: land.log attests exit 9, so a kill is not in the red denominator" {
  scope_fixture
  echo sig > "$KILL_MODE"
  landable feat/killed-log gkl.sh

  run env SHIP_LAND_LANE=v1 bash "$SHIPLAND" --trunk main
  [ "$status" -eq 9 ]
  grep -q '"exit":9' "$LAND_LOG" || false
  # `|| false` is load-bearing: a non-final `!` compound is errexit-EXEMPT in bats, so this line
  # was a DEAD assertion that could never fail (scripts/bats-assert-liveness.py flags it).
  ! grep -q '"exit":6' "$LAND_LOG" || false
  grep -q '"gate_scope":"v1"' "$LAND_LOG"                      # and names the lane that ran it
}

@test "v1 gate-killed: a non-zero suite that names NO failing test is a kill, not a red" {
  # The exact shape of the two poisoned live stamps: failing=["tests/"], retries=0. The retry
  # ladder identified ZERO failing FILES — the signature of signal-kill, not test failure.
  scope_fixture
  echo unattrib > "$KILL_MODE"
  landable feat/unattrib gu.sh

  run env SHIP_LAND_LANE=v1 bash "$SHIPLAND" --trunk main
  [ "$status" -eq 9 ]
  echo "$output" | grep -q "GATE-KILLED" || false
}

@test "v1 gate-killed POSITIVE CONTROL: a suite that NAMES a failing test still exits 6" {
  # If this ever goes green-by-accident the whole split is worthless — a real red MUST stay a red.
  scope_fixture
  echo red > "$KILL_MODE"
  landable feat/really-red gr.sh

  run env SHIP_LAND_LANE=v1 bash "$SHIPLAND" --trunk main
  [ "$status" -eq 6 ]
  echo "$output" | grep -q "GATE RED" || false
  ! echo "$output" | grep -q "GATE-KILLED" || false
}

@test "v1 gate-killed: a suite that emits NO TAP at all is ALSO a non-verdict (exit 9, fail-closed)" {
  # An earlier draft split "never got going" from "died mid-run" and called the former a RED.
  # Retired deliberately: the ONE discriminator is `not ok` in the TAP, and a second rule keyed on
  # a plan line buys nothing — a suite that never starts also names no failing test, and both
  # outcomes are equally fail-closed. This test PINS that choice rather than leaving it implicit.
  scope_fixture
  echo startup > "$KILL_MODE"
  landable feat/no-tap gn.sh

  run env SHIP_LAND_LANE=v1 bash "$SHIPLAND" --trunk main
  [ "$status" -eq 9 ]
  echo "$output" | grep -q "GATE-KILLED" || false
  git fetch -q origin main
  [ -z "$(git ls-tree origin/main -- gn.sh)" ]                 # the property that actually matters
}

@test "v1 gate-killed: a cut-then-green re-run LANDS (the whole point of the single re-run)" {
  scope_fixture
  echo sig-once > "$KILL_MODE"                                 # the FIRST invocation only
  landable feat/kill-then-green kg.sh

  run env SHIP_LAND_LANE=v1 bash "$SHIPLAND" --trunk main
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "CUT, not RED" || false             # it named the non-verdict…
  [ "$(grep -c . "$BATS_ARGV")" -eq 3 ]                        # …re-ran only the cut suite…
  git fetch -q origin main
  [ -n "$(git ls-tree origin/main -- kg.sh)" ]                 # …and landed
}

@test "v1 gate-killed: a cut re-run that turns up REAL failures is a red (6), not a kill (9)" {
  # The re-run's TAP is captured precisely so this case is decidable. Before, both outcomes printed
  # "RED (or cut twice)" — a guess handed to the caller at the moment the answer decides whether
  # retrying is correct. A real failure surfacing on the re-run must win.
  scope_fixture
  echo cut-then-red > "$KILL_MODE"
  landable feat/cut-then-red ctr.sh

  run env SHIP_LAND_LANE=v1 bash "$SHIPLAND" --trunk main
  [ "$status" -eq 6 ]
  echo "$output" | grep -q "on the re-run" || false
}

@test "v1 gate-killed: a REAL red alongside a kill exits 6 — a verdict outranks a non-verdict" {
  # Mixed run: shellcheck names a genuine defect while the suite dies. Reporting 9 would tell the
  # caller "just retry", losing a real finding. GATE_RED wins.
  scope_fixture
  echo sig > "$KILL_MODE"
  git checkout -q -b feat/mixed main
  printf '#!/usr/bin/env bash\nfoo=$(ls)\necho $foo\n' > mixed.sh    # SC2086 ⇒ shellcheck red
  git add mixed.sh && git commit -q -m "feat: mixed"

  run env SHIP_LAND_LANE=v1 bash "$SHIPLAND" --trunk main
  [ "$status" -eq 6 ]
  echo "$output" | grep -q "shellcheck RED" || false
  echo "$output" | grep -q "GATE RED" || false
  # Load-bearing, and what makes this RED-PROVABLE rather than tautological: pre-fix EVERY failure
  # was 6, so the exit code alone cannot distinguish the trees. This asserts the kill was actually
  # DETECTED and then outranked — not that detection never happened.
  echo "$output" | grep -q "GATE-KILLED" || false
}

@test "statics RED still runs the smoke, so one cycle names BOTH findings" {
  # The fast-lane twin of the test above, and a deliberate design choice worth pinning: run_gate
  # does NOT skip the smoke when the statics already went red. ≤120s on an already-doomed land buys
  # the author every finding in ONE round-trip instead of one per re-run — the same reasoning as
  # run_corpus's no-fail-fast rule.
  scope_fixture
  stub_selector "" "tests/a.bats"
  export CUT_MODE="$BATS_TEST_TMPDIR/unused-cut-mode"
  echo red > "$KILL_MODE"                                      # the smoke suite names a failure…
  git checkout -q -b feat/both main
  printf '#!/usr/bin/env bash\nfoo=$(ls)\necho $foo\n' > both.sh     # …and shellcheck names one too
  git add both.sh && git commit -q -m "feat: both"

  run bash "$SHIPLAND" --trunk main
  [ "$status" -eq 6 ]
  echo "$output" | grep -q "shellcheck RED" || false           # BOTH findings surfaced…
  echo "$output" | grep -q "smoke RED" || false                # …in the same cycle
  [ "$(grep -cx 'tests/a.bats' "$BATS_ARGV")" -ge 1 ]          # the smoke really ran
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
printf 'ROUNDS=[%s] RETRIES=[%s] SCOPE=[%s] LOCKWAIT=[%s] LOCKTTL=[%s] MAXLOAD=[%s] LANE=[%s] BUDGET=[%s] TMOUT=[%s] ARGS=[%s]\n' \
  "${SHIP_LAND_GATE_ROUNDS-unset}" "${SHIP_LAND_VERIFY_RETRIES-unset}" \
  "${SHIP_LAND_GATE_SCOPE-unset}" "${LAND_LOCK_WAIT-unset}" "${LAND_LOCK_TTL-unset}" \
  "${CC_GATE_MAX_LOAD-unset}" "${SHIP_LAND_LANE-unset}" "${SHIP_LAND_SMOKE_BUDGET_S-unset}" \
  "${SHIP_LAND_TIMEOUT_BIN-unset}" "$*"
STUB
  chmod +x "$BATS_TEST_TMPDIR/bin/bats"

  # Extract the function rather than sourcing ship-land.sh (sourcing would RUN the pipeline).
  sed -n '/^gate_bats() {/,/^}/p' "$SHIPLAND" > "$BATS_TEST_TMPDIR/probe.sh"
  # Positive control: a silent sed miss (function renamed/moved) would leave an empty probe that
  # "passes" every unset assertion vacuously. Require the function to actually be there.
  grep -q 'env -u SHIP_LAND_GATE_ROUNDS' "$BATS_TEST_TMPDIR/probe.sh" || false
  printf 'gate_bats tests/foo.bats\n' >> "$BATS_TEST_TMPDIR/probe.sh"

  run env PATH="$BATS_TEST_TMPDIR/bin:$PATH" \
      SHIP_LAND_GATE_ROUNDS=0 SHIP_LAND_VERIFY_RETRIES=9 SHIP_LAND_GATE_SCOPE=full \
      LAND_LOCK_WAIT=10800 LAND_LOCK_TTL=99 CC_GATE_MAX_LOAD=31 \
      SHIP_LAND_LANE=v1 SHIP_LAND_SMOKE_BUDGET_S=1 SHIP_LAND_TIMEOUT_BIN= \
      bash "$BATS_TEST_TMPDIR/probe.sh"
  [ "$status" -eq 0 ]
  # every LANDER knob the tests assert against arrives UNSET, whatever the operator set
  echo "$output" | grep -q 'ROUNDS=\[unset\]'   || false
  echo "$output" | grep -q 'RETRIES=\[unset\]'  || false
  echo "$output" | grep -q 'SCOPE=\[unset\]'    || false
  echo "$output" | grep -q 'LOCKWAIT=\[unset\]' || false
  echo "$output" | grep -q 'LOCKTTL=\[unset\]'  || false
  # THE SHARPEST ONE (v2). The lane decides whether a pipeline runs a smoke or the whole corpus,
  # and this suite asserts fast-lane semantics — so an operator landing with the kill switch on
  # would bleed `v1` into all ~50 fixture pipelines here and red a tree that is fine. That is the
  # ROUNDS=0 defect verbatim, on the flag v2 introduces.
  echo "$output" | grep -q 'LANE=\[unset\]'     || false
  # …and the two knobs that would silently change a fixture's smoke: a budget, and bounding turned
  # OFF via a set-but-EMPTY timeout bin (which `${VAR:-}` cannot even distinguish from unset).
  echo "$output" | grep -q 'BUDGET=\[unset\]'   || false
  echo "$output" | grep -q 'TMOUT=\[unset\]'    || false
  # FORCED to 0, deliberately NOT unset: 0 is the never-shed kill switch, so a fixture's smoke
  # always runs. Inherited, whether a nested pipeline smoked at all would depend on the ambient
  # load of the box the suite happens to run on — a test verdict decided by `uptime`.
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

@test "hermeticity: the SAME suite WITH a fixtured \$HOME lands green and the smoke still runs" {
  herm_fixture
  stub_selector "" "tests/leak.bats"                     # the added suite is DIRECT to this change
  add_suite feat/herm leak.bats 'export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"'

  run bash "$SHIPLAND" --trunk main
  [ "$status" -eq 0 ]                                    # positive control: the ratchet discriminates
  [ "$(cat "$BATS_ARGV")" = "tests/leak.bats" ]          # and does not short-circuit a clean tree
  git fetch -q origin main
  [ -n "$(git ls-tree origin/main -- tests/leak.bats)" ]
}

@test "hermeticity: it fires even on a land whose smoke selects NOTHING (selection can't reach it)" {
  # The hole that let both leaks land: gate-select maps a changed tests/X.bats to X.bats, and the
  # ratchet suite only to scripts/test-hermeticity-lint.sh — so no selection can ever reach it.
  # v2 makes this MORE important, not less: the fast lane's smoke is pure selection, so a ratchet
  # that lived inside selection would now be unreachable on every land, not merely most. It sits
  # OUTSIDE the lane machinery on purpose and runs before any suite in either lane.
  herm_fixture
  stub_selector "" ""                                    # zero direct suites ⇒ no smoke at all
  add_suite feat/leak-noselect leak.bats 'REPO="$(pwd)"'

  run bash "$SHIPLAND" --trunk main
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
# ════ LANE=v1 CORPUS — the kill switch, kept exercised so it cannot rot ════════════════════════
# SHIP_LAND_LANE=v1 restores the pre-inversion full-corpus gate for one release. It is an ENV
# switch rather than a revert because a revert would itself need the gate — the bootstrap deadlock
# the plan exists to escape — and an UNTESTED escape hatch rots exactly when it is needed, so it
# is asserted here on every run.
# WHAT v1 STILL OWNS: the full-suite verdict, and therefore the whole 6-vs-9 split (above) and the
# flake-exoneration machinery (below) — exoneration can only fire for a NON-direct suite, and the
# fast lane runs direct suites only, so the v1 corpus is its last live home.
# WHAT v1 DOES NOT RESTORE, permanently: bats under the land-lock (asserted in land-gate-cas.bats,
# both lanes) and gate-green stamping (asserted above). The kill switch buys back the PROOF, never
# the pathologies — those were the architecture, not the tier.
# The runner is ONE bats process per suite (GATE_ARCHITECTURE_PLAN §3: P(green) = (1-q)^n at
# q=2.94%/suite ⇒ 2.3% at n=126 → 49.9% with the re-run). The monolithic `bats tests/` runner and
# its SHIP_LAND_FULL_PER_SUITE kill switch are DELETED, so no test here may assert `= "tests/"`.
persuite_fixture() {  # seed tests/{a,b}.bats + a shim whose behaviour is keyed PER SUITE FILE —
                      # the only shape that can express a corpus mixing a kill with a real red,
                      # which is where "a verdict outranks a non-verdict" has to arbitrate.
  SHIMDIR="$BATS_TEST_TMPDIR/shims-ps"; mkdir -p "$SHIMDIR"
  export BATS_ARGV="$BATS_TEST_TMPDIR/bats-argv-ps"
  export MODE_DIR="$BATS_TEST_TMPDIR/modes"; mkdir -p "$MODE_DIR"
  # Shapes are byte-wise what real bats emits: `sig` = executing, then killed (plan + ok lines,
  # then 137 — the live 2026-07-26 signature, ZERO `not ok`); `red` = a NAMED failure, the positive
  # control that must never be softened; `sig-once` = cut on the first run only. Default: green.
  cat > "$SHIMDIR/bats" <<EOF
#!/bin/bash
printf '%s\n' "\$*" >> "$BATS_ARGV"
b="\$(basename "\${1:-none}")"
case "\$(cat "$MODE_DIR/\$b" 2>/dev/null)" in
  sig)  echo "1..3"; echo "ok 1 alpha"; echo "ok 2 beta"; exit 137 ;;
  red)  echo "1..1"; echo "not ok 1 boom"; exit 1 ;;
  sig-once) if [ ! -f "$BATS_TEST_TMPDIR/ps-cut-\$b" ]; then
              : > "$BATS_TEST_TMPDIR/ps-cut-\$b"; echo "1..3"; echo "ok 1 alpha"; exit 137
            fi ;;
  red-once) if [ ! -f "$BATS_TEST_TMPDIR/ps-red-\$b" ]; then       # NAMES a failure, then passes
              : > "$BATS_TEST_TMPDIR/ps-red-\$b"; echo "1..1"; echo "not ok 1 intermittent"; exit 1
            fi ;;
esac
echo "1..1"; echo "ok 1 fine"; exit 0
EOF
  chmod +x "$SHIMDIR/bats"
  export PATH="$SHIMDIR:$PATH"
  export SHIP_LAND_GATE_POLICY="$BATS_TEST_TMPDIR/no-such-policy.sh"
  mkdir -p tests
  printf '#!/usr/bin/env bats\n@test "a" { true; }\n' > tests/a.bats
  printf '#!/usr/bin/env bats\n@test "b" { true; }\n' > tests/b.bats
  git add tests && git commit -q -m "seed suites" && git push -q origin HEAD:main
  git fetch -q origin main
  stub_selector "" ""            # no direct suites: exoneration is what this tier is kept for
}

@test "v1 lane: the corpus runner runs EVERY suite, one process each — and the fast lane does not" {
  # The kill switch's whole contract in one test, with its own control: the SAME fixture and the
  # SAME selector, run twice. LANE=v1 runs both seeded suites; the default fast lane runs NOTHING
  # (the selector offers no direct suites). Without the second half this would pass on a build
  # where the lane flag was ignored and the corpus ran unconditionally.
  persuite_fixture
  landable feat/v1-corpus v1c.sh

  run env SHIP_LAND_LANE=v1 bash "$SHIPLAND" --trunk main
  [ "$status" -eq 0 ]
  [ "$(grep -cx 'tests/a.bats' "$BATS_ARGV")" -eq 1 ]      # the WHOLE corpus…
  [ "$(grep -cx 'tests/b.bats' "$BATS_ARGV")" -eq 1 ]
  [ "$(grep -c . "$BATS_ARGV")" -eq 2 ]                    # …nothing else, nothing twice
  [ "$(grep -cx 'tests/' "$BATS_ARGV")" -eq 0 ]            # and NEVER the deleted monolith call
  echo "$output" | grep -q "FULL corpus green"
  grep -q '"gate_scope":"v1"' "$LAND_LOG"

  : > "$BATS_ARGV"
  landable feat/v1-control v1ctl.sh
  run bash "$SHIPLAND" --trunk main                        # CONTROL: same fixture, default lane
  [ "$status" -eq 0 ]
  [ ! -s "$BATS_ARGV" ]                                    # zero suites — the lane really decides
}

@test "v1 lane: a CUT suite is re-run ONCE in a fresh TMPDIR and can land green" {
  persuite_fixture
  echo sig-once > "$MODE_DIR/a.bats"
  landable feat/ps-cut psc.sh

  run env SHIP_LAND_LANE=v1 bash "$SHIPLAND" --trunk main
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "CUT, not RED"
  [ "$(grep -cx 'tests/a.bats' "$BATS_ARGV")" -eq 2 ]      # the cut suite: run + ONE re-run
  # The point of per-suite, as an assertion: the neighbour paid nothing for a's kill. Under the
  # deleted monolith that same kill discarded the entire corpus and was attested exit:6 RED.
  [ "$(grep -cx 'tests/b.bats' "$BATS_ARGV")" -eq 1 ]
  grep -q '"outcome":"pass-on-retry"' "$POSTLAND_DIR/flakes.jsonl"
  grep -q '"file":"tests/a.bats"' "$POSTLAND_DIR/flakes.jsonl"
  grep -q '"phase":"land-gate"' "$POSTLAND_DIR/flakes.jsonl"
  # The ledger names WHAT failed, not just "it flaked" — an unactionable line is not a denominator.
  grep -q '"signal":"' "$POSTLAND_DIR/flakes.jsonl"
  [ "$(grep -c '"signal":""' "$POSTLAND_DIR/flakes.jsonl")" -eq 0 ]
  git fetch -q origin main
  [ -n "$(git ls-tree origin/main -- psc.sh)" ]
}

@test "v1 lane: a corpus of CUT suites is a NON-VERDICT (exit 9), never a red" {
  persuite_fixture
  echo sig > "$MODE_DIR/a.bats"
  echo sig > "$MODE_DIR/b.bats"
  gc="$(git rev-parse --git-common-dir)"; rm -f "$gc/gate-green"
  landable feat/ps-killed psk.sh

  run env SHIP_LAND_LANE=v1 bash "$SHIPLAND" --trunk main
  [ "$status" -eq 9 ]                                      # c605a2e's non-verdict, PRESERVED
  echo "$output" | grep -q "GATE-KILLED"
  [ "$(echo "$output" | grep -c "GATE RED")" -eq 0 ]       # never both, never the wrong one
  [ "$(grep -c . "$BATS_ARGV")" -eq 4 ]                    # 2 suites × (run + ONE bounded re-run)
  [ ! -f "$gc/gate-green" ]
  grep -q '"exit":9' "$LAND_LOG"                           # …and is not in the red denominator
  grep -q '"outcome":"cut-not-red"' "$POSTLAND_DIR/flakes.jsonl"
  grep -q '"file":"tests/a.bats"' "$POSTLAND_DIR/flakes.jsonl"   # WHICH suite ran out of machine
  git fetch -q origin main
  [ -z "$(git ls-tree origin/main -- psk.sh)" ]            # fail-closed: nothing landed
}

@test "v1 lane POSITIVE CONTROL: a suite that NAMES a failing test is RED (6), re-run or not" {
  # If this ever goes green-by-accident the whole split is worthless. The runner grants one
  # exoneration re-run; a NAMED failure must survive it unchanged.
  persuite_fixture
  echo red > "$MODE_DIR/a.bats"
  landable feat/ps-red psr.sh

  run env SHIP_LAND_LANE=v1 bash "$SHIPLAND" --trunk main
  [ "$status" -eq 6 ]
  echo "$output" | grep -q "GATE RED"
  echo "$output" | grep -q "failed twice"
  [ "$(echo "$output" | grep -c "GATE-KILLED")" -eq 0 ]    # a verdict is never softened into one
  git fetch -q origin main
  [ -z "$(git ls-tree origin/main -- psr.sh)" ]
}

@test "v1 lane: one suite CUT + another RED ⇒ exit 6 — a verdict outranks a non-verdict" {
  # The case that decides whether the loop may fail-fast: it may not. Stopping at a's kill would
  # report 9 ("retry when quieter") for a tree that is genuinely broken — the dispatcher would then
  # retry it forever (f8e40b4c577d).
  persuite_fixture
  echo sig > "$MODE_DIR/a.bats"            # no verdict…
  echo red > "$MODE_DIR/b.bats"            # …and a real one, AFTER it in glob order
  landable feat/ps-mixed psm.sh

  run env SHIP_LAND_LANE=v1 bash "$SHIPLAND" --trunk main
  [ "$status" -eq 6 ]
  echo "$output" | grep -q "GATE-KILLED"                   # the cut WAS detected…
  echo "$output" | grep -q "GATE RED"                      # …and then outranked
  git fetch -q origin main
  [ -z "$(git ls-tree origin/main -- psm.sh)" ]
}

@test "v1 lane: a DIRECT suite whose NAMED failure vanishes on retry is never exonerated" {
  # THE correctness fence on the exoneration re-run, and it must hold in v1 too: intermittence in
  # code you are landing is a FINDING, not a flake. The fast-lane twin is "smoke CARVE-OUT
  # CONTROL…" above; this is the half where non-direct suites also exist to be confused with it.
  # The fixture NAMES a failure (`red-once`) rather than being killed: keying the carve-out on a
  # named `not ok` is the v2 correction — see the cut-then-green tests — and a fixture that is
  # merely SIGKILLed would now (correctly) land, so it can no longer stand in for this rule.
  persuite_fixture
  stub_selector "" "tests/a.bats"          # a IS direct to this change…
  echo red-once > "$MODE_DIR/a.bats"       # …and its named failure vanishes on the re-run
  landable feat/ps-direct psd.sh

  run env SHIP_LAND_LANE=v1 bash "$SHIPLAND" --trunk main
  [ "$status" -eq 6 ]                                      # pass-on-retry is NOT a pass here
  echo "$output" | grep -q "finding, not a flake"
  [ ! -f "$POSTLAND_DIR/flakes.jsonl" ]                    # never exonerated ⇒ never logged
  git fetch -q origin main
  [ -z "$(git ls-tree origin/main -- psd.sh)" ]            # and NOT landed
}

@test "v1 lane: a DIRECT suite that was CUT and then passed DOES land (the same correction)" {
  # The v1-lane twin of the fast-lane cut-then-green test. Pinned in both lanes because the fix
  # lives in run_scoped_suite, which both share — a regression would hit v1 silently, where nobody
  # is looking, and then surface in the fast lane as a mystery false red.
  persuite_fixture
  stub_selector "" "tests/a.bats"          # a IS direct…
  echo sig-once > "$MODE_DIR/a.bats"       # …and it was KILLED, then passed
  landable feat/ps-direct-cut psdc.sh

  run env SHIP_LAND_LANE=v1 bash "$SHIPLAND" --trunk main
  [ "$status" -eq 0 ]                                      # a machine event is not your finding
  echo "$output" | grep -q "EXONERATED"
  grep -q '"outcome":"pass-on-retry"' "$POSTLAND_DIR/flakes.jsonl"
  git fetch -q origin main
  [ -n "$(git ls-tree origin/main -- psdc.sh)" ]
}

@test "v1 lane: a GREEN hermeticity ratchet hands the whole corpus to the runner" {
  # The ratchet returns EARLY on red — fail-fast, because an unfixtured suite contaminates every
  # other result in the run — so the composition that needs pinning is the GREEN one: ratchet
  # passes ⇒ the runner still gets every suite, one process each.
  herm_fixture
  add_suite feat/herm-ps leak.bats 'export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"'

  run env SHIP_LAND_LANE=v1 bash "$SHIPLAND" --trunk main
  [ "$status" -eq 0 ]
  [ "$(grep -cx 'tests/a.bats' "$BATS_ARGV")" -eq 1 ]      # the suite herm_fixture seeded…
  [ "$(grep -cx 'tests/leak.bats' "$BATS_ARGV")" -eq 1 ]   # …and the one this land adds
  [ "$(grep -cx 'tests/' "$BATS_ARGV")" -eq 0 ]            # never the deleted monolith call
  git fetch -q origin main
  [ -n "$(git ls-tree origin/main -- tests/leak.bats)" ]
}

# ════ NOTHING HEAVY UNDER THE LAND-LOCK — enforced at the suite-start chokepoint ═══════════════
# v1's in-lock full gate produced a 3h36m lock holder and, when the corpus hung, a multi-day jam
# while every other lander queued. v2 bans it structurally: run_gate refuses to start ANY suite
# while IN_LAND_LOCK=1, in EITHER lane, so the ban cannot be forgotten at a call site. The
# end-to-end proofs (rounds-exhausted fallback · the content-drop recovery re-gate) live in
# tests/land-gate-cas.bats, which owns the lock pipeline. What is pinned HERE is the sharper unit
# fact: the short-circuit happens BEFORE gate_home_setup, so the lock does not even pay for a
# $HOME clone it will never use.

iso_home_fixture() {  # force REAL $HOME isolation, cheaply — the spy needs the mechanism ON
  # A fixture $HOME first, and it is load-bearing: SHIP_LAND_GATE_HOME_ISO=on forces a real APFS
  # clone, and this suite does not otherwise fixture HOME — left unset, the positive control below
  # would clone the operator's live 2.1 GB ~/.claude (~9 s and real disk churn) to prove a point
  # about a directory listing. Clones land inside the sandbox, never in the real $TMPDIR and never
  # inside the fixture $HOME (a clone rooted under its own source is an infinite regress).
  export HOME="$BATS_TEST_TMPDIR/iso-home"; mkdir -p "$HOME/.claude"
  export SHIP_LAND_GATE_HOME_ROOT="$BATS_TEST_TMPDIR/isoroot"; mkdir -p "$SHIP_LAND_GATE_HOME_ROOT"
  export SHIP_LAND_GATE_HOME_ISO=on
}

@test "in-lock: the smoke short-circuits BEFORE gate_home_setup — no clone under the lock" {
  # SPY: gate_home_setup is un-silent by construction — it announces either an isolated $HOME or
  # (under a fixture pipeline) that it skipped isolation. Absence of BOTH lines is therefore proof
  # it was never reached, not merely that isolation was off. SHIP_LAND_GATE_HOME_ROOT gives a
  # second, independent witness: a clone would have to appear in that directory.
  scope_fixture
  stub_selector "" "tests/a.bats"                          # a real smoke selection exists…
  iso_home_fixture                                         # …and isolation is FORCED on
  landable feat/inlock-noclone ilc.sh

  # ROUNDS=0 sends the gate straight into the lock — the fallback path, where v1 ran the corpus.
  run env SHIP_LAND_GATE_ROUNDS=0 bash "$SHIPLAND" --trunk main
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "no bats inside the land-lock"
  [ ! -s "$BATS_ARGV" ]                                              # no suite started…
  [ "$(echo "$output" | grep -c 'HOME. isolated')" -eq 0 ]           # …and gate_home_setup…
  [ "$(echo "$output" | grep -c 'isolation skipped')" -eq 0 ]        # …was never REACHED at all
  [ "$(find "$SHIP_LAND_GATE_HOME_ROOT" -maxdepth 1 -name 'gate-home.*' | grep -c .)" -eq 0 ]
  grep -q '"smoke":"none"' "$LAND_LOG"
}

@test "in-lock POSITIVE CONTROL: the SAME fixture unlocked DOES clone and DOES smoke" {
  # Without this the test above passes on any build where isolation is simply broken, or where the
  # selector never selected anything. Same fixture, same flags, one difference: no lock.
  scope_fixture
  stub_selector "" "tests/a.bats"
  iso_home_fixture
  landable feat/unlocked-clone ulc.sh

  run bash "$SHIPLAND" --trunk main                        # default ROUNDS ⇒ the UNLOCKED gate
  [ "$status" -eq 0 ]
  [ "$(cat "$BATS_ARGV")" = "tests/a.bats" ]               # the smoke ran…
  echo "$output" | grep -q 'isolated'                      # …and gate_home_setup WAS reached
  grep -q '"smoke":"green"' "$LAND_LOG"
}
