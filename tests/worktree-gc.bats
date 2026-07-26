#!/usr/bin/env bats
# worktree-gc — the janitor hooks/git-worktree-guard.sh:40,57 and hooks/live-session-registry.sh:2
# have always advertised. Every gate is red-proofed with a DISCRIMINATOR PAIR: the same fixture
# worktree must be KEPT with the gate tripped and REMOVED with it clear — a suite that only asserts
# the KEEP half would pass against a script that never removes anything.
#
# Liveness oracles are shimmed (CC_WTGC_CC_NOTIFY / _LSOF / _PGREP / _REGISTRY_DIR) so the suite
# never reads the host's real sessions, and idle is driven by a BACKDATED COMMITTER DATE — a
# durable git product, not a file mtime (the audit's §8-B lesson, re-asserted by test 7).

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  GC="$REPO/scripts/worktree-gc.sh"
  # Fixture $HOME before anything reads it. EVERY unset seam in the subject falls back to a path
  # under ~/ — the backlog binary, the team registry, the live-session registry, the mutex, and
  # (the one that bites) the DISPOSAL LOG, which a suite running against the live ~/ would append
  # the operator's real ledger from a test fixture. Seams are passed explicitly below; this is the
  # second net, so a seam added later without a shim degrades to an empty temp dir, never live state.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  R="$BATS_TEST_TMPDIR/main"
  OLD="$(( $(date +%s) - 7200 ))"          # 2 h ago — comfortably past the 30 min idle floor
  ANCIENT="$(( $(date +%s) - 864000 ))"    # 10 d ago — comfortably past the 72 h abandon horizon

  git init -q -b main "$R"
  git -C "$R" config user.email t@t
  git -C "$R" config user.name t
  echo a > "$R/f"
  git -C "$R" add f
  GIT_AUTHOR_DATE="$OLD +0000" GIT_COMMITTER_DATE="$OLD +0000" git -C "$R" commit -qm c1
  git -C "$R" update-ref refs/remotes/origin/main HEAD

  # Oracle shims. cc-notify replays a file so a test can flip what it reports mid-suite.
  SHIMOUT="$BATS_TEST_TMPDIR/notify.json"; echo '[]' > "$SHIMOUT"
  SHIM="$BATS_TEST_TMPDIR/cc-notify"
  printf '#!/usr/bin/env bash\ncat %s\n' "$SHIMOUT" > "$SHIM"; chmod +x "$SHIM"
  STUB="$BATS_TEST_TMPDIR/nullbin"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$STUB"; chmod +x "$STUB"
  REG="$BATS_TEST_TMPDIR/registry"; mkdir -p "$REG"
  LOCK="$BATS_TEST_TMPDIR/gc.lock"

  # The ownership oracle, shimmed the same replayed-file way: `[]` (an empty ledger) is the
  # default, so no test disposes anything by accident.
  BLOUT="$BATS_TEST_TMPDIR/backlog.json"; echo '[]' > "$BLOUT"
  BL="$BATS_TEST_TMPDIR/cc-backlog"
  printf '#!/usr/bin/env bash\ncat %s\n' "$BLOUT" > "$BL"; chmod +x "$BL"
  DLOG="$BATS_TEST_TMPDIR/disposals.jsonl"

  # Ownership oracle 2 — the team registry. Empty by default, same as the ledger: a teammate
  # worktree disposes only when a test positively records a DEAD or ARCHIVED owning team.
  TEAMS="$BATS_TEST_TMPDIR/teams"; mkdir -p "$TEAMS/_archive"
}

# team <dir> <member> — record a team at <dir> (relative to TEAMS) whose roster names <member>.
# `.dead-<x>` = torn down · `_archive/<x>` = archived · anything else = a LIVE team.
team() {
  mkdir -p "$TEAMS/$1"
  printf '{"teamName":"%s","members":[{"name":"team-lead"},{"name":"%s"}]}\n' "$1" "$2" \
    > "$TEAMS/$1/config.json"
}

# wt <name> <branch> — a clean, landed, idle worktree (the baseline REMOVE candidate).
wt() {
  git -C "$R" worktree add -q -b "$2" "$BATS_TEST_TMPDIR/$1" HEAD 2>/dev/null
  echo "$BATS_TEST_TMPDIR/$1"
}

# abandoned_wt <name> <branch> — clean + idle past the abandon horizon + genuinely UNLANDED.
# Commits are backdated so idle is read from the durable branch tip, never a file mtime.
abandoned_wt() {
  local p; p="$(wt "$1" "$2")"
  echo new > "$p/g"; git -C "$p" add g
  GIT_AUTHOR_DATE="$ANCIENT +0000" GIT_COMMITTER_DATE="$ANCIENT +0000" \
    git -C "$p" commit -qm "abandoned work"
  echo "$p"
}

# owns <id> <status> [wasDone] — what cc-backlog folds for the item owning `wt-<id>`.
owns() {
  printf '[{"id":"%s","status":"%s","wasDone":%s}]\n' "$1" "$2" "${3:-false}" > "$BLOUT"
}

run_gc() {
  run env CC_WTGC_REPO="$R" CC_WTGC_CC_NOTIFY="$SHIM" CC_WTGC_LSOF="$STUB" \
      CC_WTGC_PGREP="$STUB" CC_WTGC_REGISTRY_DIR="$REG" CC_WTGC_LOCK="$LOCK" \
      CC_WTGC_BACKLOG="${BACKLOG:-$BL}" CC_WTGC_DISPOSAL_LOG="$DLOG" \
      CC_WTGC_TEAMS_DIR="${TEAMSDIR:-$TEAMS}" \
      CC_WTGC_EXCLUDE="${EXCLUDE:-}" bash "$GC" "$@"
}

has_wt() { git -C "$R" worktree list --porcelain | grep -qF "worktree $1"; }
has_br() { git -C "$R" rev-parse --verify --quiet "refs/heads/$1" >/dev/null; }

@test "clean + idle + landed → worktree removed, branch PRESERVED (default keeps branches)" {
  p="$(wt wt-landed feat/landed)"
  run_gc
  [ "$status" -eq 0 ]
  [ ! -d "$p" ]
  ! has_wt "$p" || false       # `|| false` — a bare non-final `!` is errexit-EXEMPT ⇒ a DEAD assertion
  has_br feat/landed          # the janitor never deletes a branch without --prune-branches
}

@test "dirty tree → KEPT (removal would need --force ⇒ data loss)" {
  p="$(wt wt-dirty feat/dirty)"
  echo dirt >> "$p/f"
  run_gc
  [ -d "$p" ]
  echo "$output" | grep -q "KEEP.*wt-dirty.*dirty tree"
}

@test "live cc-notify cwd → KEPT" {
  p="$(wt wt-live feat/live)"
  printf '[{"cwd":"%s"}]\n' "$p" > "$SHIMOUT"
  run_gc
  [ -d "$p" ]
  echo "$output" | grep -q "KEEP.*wt-live.*LIVE"
}

@test "RED-PROOF of the live gate: same worktree IS removed once cc-notify reports no session" {
  # Without this half, a script that simply never removes anything would pass the KEEP test above.
  p="$(wt wt-live feat/live)"
  printf '[{"cwd":"%s"}]\n' "$p" > "$SHIMOUT"
  run_gc
  [ -d "$p" ]
  echo '[]' > "$SHIMOUT"
  run_gc
  [ ! -d "$p" ]
}

@test "live-session-registry PID alive → KEPT (the registry finally has a consumer)" {
  p="$(wt wt-reg feat/reg)"
  printf '%s\t%s\t%s\n' "$$" "sid-1" "$p" > "$REG/wt-reg"
  run_gc
  [ -d "$p" ]
  echo "$output" | grep -q "KEEP.*wt-reg.*registry"
  # Discriminator: a DEAD registry pid must not hold the worktree hostage.
  printf '%s\t%s\t%s\n' "999999" "sid-1" "$p" > "$REG/wt-reg"
  run_gc
  [ ! -d "$p" ]
}

@test ".teammate-busy marker → KEPT" {
  p="$(wt wt-busy feat/busy)"
  touch "$p/.teammate-busy"
  run_gc
  [ -d "$p" ]
  echo "$output" | grep -q "KEEP.*wt-busy.*teammate-busy"
}

@test "unlanded branch → KEPT (patch-equivalence, not ancestry, is the landed test)" {
  p="$(wt wt-unlanded feat/unlanded)"
  echo new > "$p/g"
  git -C "$p" add g
  GIT_AUTHOR_DATE="$OLD +0000" GIT_COMMITTER_DATE="$OLD +0000" git -C "$p" commit -qm orphan
  run_gc
  [ -d "$p" ]
  echo "$output" | grep -q "KEEP.*wt-unlanded.*not on origin/main"
}

@test "branch tip younger than the idle floor → KEPT" {
  p="$(wt wt-fresh feat/fresh)"
  git -C "$p" commit -q --amend --no-edit --date=now   # same patch-id (still landed), fresh tip
  run_gc
  [ -d "$p" ]
  echo "$output" | grep -q "KEEP.*wt-fresh.*idle floor"
}

@test "idle is measured by BRANCH TIP, not directory mtime (audit §8-B)" {
  # A `git status` sweep rewrites .git/worktrees/<n>/index, so admin-dir mtime reads fresh for
  # every worktree. A janitor gating on mtime would KEEP this one forever; it must still remove it.
  p="$(wt wt-touched feat/touched)"
  touch "$p/f" "$p"
  run_gc
  [ ! -d "$p" ]
}

@test "CC_WTGC_EXCLUDE hard-excludes a path that otherwise passes every gate" {
  p="$(wt wt-excl feat/excl)"
  EXCLUDE="$p" run_gc
  [ -d "$p" ]
  echo "$output" | grep -q "KEEP.*wt-excl.*hard-excluded"
}

@test "--dry-run mutates nothing" {
  p="$(wt wt-dry feat/dry)"
  run_gc --dry-run --prune-branches
  [ "$status" -eq 0 ]
  [ -d "$p" ]
  has_br feat/dry
  echo "$output" | grep -q "would remove"
}

@test "--prune-branches deletes a landed, worktree-less branch with -d" {
  p="$(wt wt-pb feat/pb)"
  run_gc --prune-branches
  [ ! -d "$p" ]
  ! has_br feat/pb
}

@test "--prune-branches NEVER touches protected refs (backup/recovery classes + main)" {
  git -C "$R" branch ship/backup-abc123
  git -C "$R" branch backup/daemon-window
  git -C "$R" branch agent-a324-prerebase-backup
  run_gc --prune-branches
  has_br ship/backup-abc123
  has_br backup/daemon-window
  has_br agent-a324-prerebase-backup
  has_br main
}

@test "--prune-branches never deletes an unlanded branch" {
  p="$(wt wt-ub feat/ub)"
  echo new > "$p/g"; git -C "$p" add g
  GIT_AUTHOR_DATE="$OLD +0000" GIT_COMMITTER_DATE="$OLD +0000" git -C "$p" commit -qm orphan
  run_gc --prune-branches
  [ -d "$p" ]
  has_br feat/ub
}

@test "broken admin record (directory vanished) is pruned; its branch survives" {
  p="$(wt wt-broken feat/broken)"
  rm -rf "$p"
  run_gc
  ! has_wt "$p" || false
  has_br feat/broken
}

@test "a held lock serializes the pass — nothing is removed" {
  p="$(wt wt-lock feat/lock)"
  mkdir -p "$LOCK"
  run_gc
  [ "$status" -eq 0 ]
  [ -d "$p" ]
  echo "$output" | grep -q "another pass holds"
}

@test "no liveness oracle at all → refuse to remove (exit 3), never a blind reap" {
  p="$(wt wt-nooracle feat/nooracle)"
  run env CC_WTGC_REPO="$R" CC_WTGC_CC_NOTIFY=/nonexistent/cc-notify \
      CC_WTGC_LSOF=/nonexistent/lsof CC_WTGC_PGREP=/nonexistent/pgrep \
      CC_WTGC_REGISTRY_DIR="$REG" CC_WTGC_LOCK="$LOCK" bash "$GC"
  [ "$status" -eq 3 ]
  [ -d "$p" ]
}

@test "--prune (the invocation git-worktree-guard.sh prints) is accepted; junk flags exit 2" {
  p="$(wt wt-alias feat/alias)"
  run_gc --prune
  [ "$status" -eq 0 ]
  [ ! -d "$p" ]
  run_gc --bogus
  [ "$status" -eq 2 ]
}

@test "the no-force / no-D discipline is in the source, not just the docs" {
  # Audit §8-H: `git worktree remove` and `git branch -d` refusing is the LAST net under our
  # evidence. Substituting --force / -D discards it, so the suite guards the source itself.
  body="$(sed 's/#.*$//' "$GC")"          # comments explain the ban; only real commands can break it
  ! printf '%s\n' "$body" | grep -qE 'worktree[[:space:]]+remove[^;]*--force' || false
  ! printf '%s\n' "$body" | grep -qE 'branch[[:space:]]+(-D|-d[[:space:]]+-f|--delete[[:space:]]+--force)'
}

# ── The DISPOSE class: abandoned-but-UNLANDED (backlog c7bdab960795) ─────────────────────────
# Gate 6 (landed-by-patch-id) is unconditional, so before this class NOTHING could reap a
# worktree whose work deliberately never lands — 24 such worktrees were measured stuck on
# 2026-07-26. Each of A1/A2/A3 gets a DISCRIMINATOR PAIR: the same fixture must be KEPT with
# the gate tripped and DISPOSED with it clear. Without both halves an implementation that
# never disposes — i.e. the bug being fixed — would pass the suite.

@test "DISPOSE: abandoned + owning item done + past horizon → reaped, branch PRESERVED" {
  p="$(abandoned_wt wt-abc123456789 feat/abandoned)"
  owns abc123456789 done
  run_gc --dispose-abandoned
  [ "$status" -eq 0 ]
  [ ! -d "$p" ]
  ! has_wt "$p" || false
  has_br feat/abandoned                     # disposal removes a DIRECTORY, never a commit
  echo "$output" | grep -q "dispose .*wt-abc123456789.*abandoned-unlanded"
}

@test "DISPOSE is opt-in: the same worktree is CLASSIFIED and PRINTED without the flag, never reaped" {
  # Absence must be loud. A dispose plan citing this script has to SEE the class even when it
  # did not pass the flag that acts on it — "no operator action required" silently meaning
  # "nothing happens" is the exact failure this class was filed for.
  p="$(abandoned_wt wt-abc123456789 feat/abandoned)"
  owns abc123456789 done
  run_gc                                    # the bare invocation git-worktree-guard.sh prints
  [ -d "$p" ]
  echo "$output" | grep -q "DISPOSE? .*wt-abc123456789"
  echo "$output" | grep -q "1 abandoned-unlanded worktree(s) are reapable"
}

@test "A1 RED-PROOF (age): inside the abandon horizon → KEPT; past it → disposed" {
  p="$(wt wt-abc123456789 feat/young)"
  echo new > "$p/g"; git -C "$p" add g
  GIT_AUTHOR_DATE="$OLD +0000" GIT_COMMITTER_DATE="$OLD +0000" git -C "$p" commit -qm wip
  owns abc123456789 done
  run_gc --dispose-abandoned
  [ -d "$p" ]
  echo "$output" | grep -q "not abandoned: idle 2h < 72h abandon horizon"
  # Discriminator — the ONLY thing that changes is the tip date.
  GIT_COMMITTER_DATE="$ANCIENT +0000" git -C "$p" commit -q --amend --no-edit --date="$ANCIENT +0000"
  run_gc --dispose-abandoned
  [ ! -d "$p" ]
}

@test "A2 RED-PROOF (ownership): a non-terminal owning item → KEPT; flipping it to done → disposed" {
  # Age alone must NEVER dispose: this fixture is 10 days idle in both halves.
  p="$(abandoned_wt wt-abc123456789 feat/abandoned)"
  owns abc123456789 claimed
  run_gc --dispose-abandoned
  [ -d "$p" ]
  echo "$output" | grep -q "owning item abc123456789 is 'claimed', not terminal"
  owns abc123456789 done
  run_gc --dispose-abandoned
  [ ! -d "$p" ]
}

@test "A2: a REOPENED item (wasDone latch set, status back to open) is not terminal → KEPT" {
  p="$(abandoned_wt wt-abc123456789 feat/abandoned)"
  owns abc123456789 open true
  run_gc --dispose-abandoned
  [ -d "$p" ]
  echo "$output" | grep -q "was REOPENED"
}

@test "A2: no owning backlog item (a feature-named worktree) → KEPT" {
  p="$(abandoned_wt wt-board-commands feat/board)"
  owns abc123456789 done                    # a populated ledger that simply lacks this owner
  run_gc --dispose-abandoned
  [ -d "$p" ]
  echo "$output" | grep -q "no owning backlog item 'board-commands'"
}

@test "A2 fails CLOSED: an unreadable ownership oracle KEEPS, it never disposes blind" {
  p="$(abandoned_wt wt-abc123456789 feat/abandoned)"
  BACKLOG=/nonexistent/cc-backlog run_gc --dispose-abandoned
  [ -d "$p" ]
  echo "$output" | grep -q "ownership unprovable"
}

@test "A3: the disposed commits stay reachable — same tip, same unlanded patch SET (not a count)" {
  p="$(abandoned_wt wt-abc123456789 feat/abandoned)"
  owns abc123456789 done
  head_before="$(git -C "$R" rev-parse refs/heads/feat/abandoned)"
  set_before="$(git -C "$R" cherry origin/main feat/abandoned | awk '/^\+ /{print $2}' | sort)"
  run_gc --dispose-abandoned
  [ ! -d "$p" ]
  [ "$(git -C "$R" rev-parse refs/heads/feat/abandoned)" = "$head_before" ]
  [ "$(git -C "$R" cherry origin/main feat/abandoned | awk '/^\+ /{print $2}' | sort)" = "$set_before" ]
  git -C "$R" for-each-ref --points-at "$head_before" --format='%(refname)' | grep -qx refs/heads/feat/abandoned
  git -C "$R" cat-file -e "$head_before^{commit}"          # the object itself survives
}

@test "A3: a disposal that cannot be verified as preserved exits 4 and says so" {
  # Fixtured through the CC_WTGC_GIT seam: a git wrapper that moves the branch the instant
  # `worktree remove` succeeds — the shape of a concurrent rewrite landing inside the act
  # window. Without this the "VERIFIED preserved" claim would be decoration.
  p="$(abandoned_wt wt-abc123456789 feat/abandoned)"
  owns abc123456789 done
  SABOTEUR="$BATS_TEST_TMPDIR/git-saboteur"
  cat > "$SABOTEUR" <<'SH'
#!/usr/bin/env bash
real=/usr/bin/git
command -v git >/dev/null 2>&1 && real=$(command -v git)
"$real" "$@"; rc=$?
hit=0; for a in "$@"; do [ "$a" = "remove" ] && hit=1; done
if [ "$hit" = 1 ] && [ "$rc" -eq 0 ]; then
  "$real" -C "$SAB_REPO" update-ref refs/heads/feat/abandoned "$SAB_TRUNK" 2>/dev/null
fi
exit "$rc"
SH
  chmod +x "$SABOTEUR"
  run env CC_WTGC_REPO="$R" CC_WTGC_CC_NOTIFY="$SHIM" CC_WTGC_LSOF="$STUB" \
      CC_WTGC_PGREP="$STUB" CC_WTGC_REGISTRY_DIR="$REG" CC_WTGC_LOCK="$LOCK" \
      CC_WTGC_BACKLOG="$BL" CC_WTGC_DISPOSAL_LOG="$DLOG" CC_WTGC_GIT="$SABOTEUR" \
      SAB_REPO="$R" SAB_TRUNK="$(git -C "$R" rev-parse origin/main)" \
      bash "$GC" --dispose-abandoned
  [ "$status" -eq 4 ]
  echo "$output" | grep -q "PRESERVATION UNVERIFIED"
  grep -q '"verified":"FAILED"' "$DLOG"
}

@test "every disposal appends its INTENT to the ledger — what git alone cannot record" {
  p="$(abandoned_wt wt-abc123456789 feat/abandoned)"
  owns abc123456789 done
  head="$(git -C "$R" rev-parse refs/heads/feat/abandoned)"
  run_gc --dispose-abandoned
  [ -f "$DLOG" ]
  [ "$(grep -c . "$DLOG")" -eq 1 ]
  grep -q '"event":"worktree-disposed"' "$DLOG"
  grep -q "\"branch\":\"feat/abandoned\"" "$DLOG"
  grep -q "\"head\":\"$head\"" "$DLOG"
  grep -q "\"patch_shas\":\"$head\"" "$DLOG"          # the recoverable evidence, not just a count
  grep -q '"owner_item":"abc123456789"' "$DLOG"
  grep -q '"verified":"points-at+cherry-set"' "$DLOG"
  # A KEPT worktree must never appear in the ledger.
  [ "$(grep -c . "$DLOG")" -eq 1 ]
}

@test "--dispose-abandoned + --prune-branches still never deletes the disposed branch" {
  # The branch is the durable ref the whole policy rests on; disposal must not make it
  # collectable. (--prune-branches only ever deletes LANDED branches, and this one is not.)
  p="$(abandoned_wt wt-abc123456789 feat/abandoned)"
  owns abc123456789 done
  run_gc --dispose-abandoned --prune-branches
  [ ! -d "$p" ]
  has_br feat/abandoned
}

@test "--dispose-abandoned does not loosen any earlier gate (dirty / live / busy still KEEP)" {
  d="$(abandoned_wt wt-aaa111222333 feat/ab-dirty)"; echo dirt >> "$d/f"
  l="$(abandoned_wt wt-bbb111222333 feat/ab-live)"
  b="$(abandoned_wt wt-ccc111222333 feat/ab-busy)"; touch "$b/.teammate-busy"
  printf '[{"cwd":"%s"}]\n' "$l" > "$SHIMOUT"
  printf '[{"id":"aaa111222333","status":"done","wasDone":false},{"id":"bbb111222333","status":"done","wasDone":false},{"id":"ccc111222333","status":"done","wasDone":false}]\n' > "$BLOUT"
  run_gc --dispose-abandoned
  [ -d "$d" ]
  [ -d "$l" ]
  [ -d "$b" ]
  [ ! -f "$DLOG" ]
}

@test "a parked git operation with a CLEAN tree → KEPT (the dirty gate cannot see it)" {
  # A stopped-but-clean rebase/merge leaves `git status --porcelain` empty, so without this
  # gate the worktree reads as a plain landed candidate and removal discards the operation.
  p="$(wt wt-parked feat/parked)"
  git -C "$p" rev-parse HEAD > "$(git -C "$p" rev-parse --absolute-git-dir)/MERGE_HEAD"
  run_gc
  [ -d "$p" ]
  echo "$output" | grep -q "KEEP.*wt-parked.*parked here (MERGE_HEAD)"
  # Discriminator: clear the parked operation and the same worktree is removed.
  rm -f "$(git -C "$p" rev-parse --absolute-git-dir)/MERGE_HEAD"
  run_gc
  [ ! -d "$p" ]
}

@test "a session born INSIDE the classify→act window is re-checked and KEPT, not reaped" {
  # LIVE_CWDS is computed once at startup; a 65-worktree sweep takes minutes. The pre-mutation
  # re-check reads process truth again at ACT time — the 2026-06-12 incident class.
  # No production test-seam: the lsof shim is simply STATEFUL — the startup cwd sweep sees an
  # empty machine, the act-time sweep (the very next `-d cwd` call) sees the new session. That
  # is the real code path, driven only through the oracle seams the suite already uses.
  p="$(wt wt-born feat/born)"
  CNT="$BATS_TEST_TMPDIR/lsof.n"
  BORN="$BATS_TEST_TMPDIR/lsof-born"
  cat > "$BORN" <<'SH'
#!/usr/bin/env bash
q=0; for a in "$@"; do [ "$a" = "cwd" ] && q=1; done
[ "$q" = 1 ] || exit 0
n=$(( $(cat "$LSOF_N" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$LSOF_N"
[ "$n" -gt 1 ] && printf 'p1\nn%s\n' "$BORN_CWD" || false
exit 0
SH
  chmod +x "$BORN"
  PGB="$BATS_TEST_TMPDIR/pgrep-born"
  printf '#!/usr/bin/env bash\necho 1\n' > "$PGB"; chmod +x "$PGB"
  run env CC_WTGC_REPO="$R" CC_WTGC_CC_NOTIFY="$SHIM" CC_WTGC_LSOF="$BORN" \
      CC_WTGC_PGREP="$PGB" CC_WTGC_REGISTRY_DIR="$REG" CC_WTGC_LOCK="$LOCK" \
      CC_WTGC_BACKLOG="$BL" CC_WTGC_DISPOSAL_LOG="$DLOG" \
      LSOF_N="$CNT" BORN_CWD="$p" bash "$GC"
  [ -d "$p" ]
  echo "$output" | grep -q "LIVE at act time"
  # Discriminator: with a machine that is empty at BOTH reads, the same worktree is removed.
  echo 99 > "$CNT"; : > "$CNT"
  rm -f "$CNT"
  cat > "$BORN" <<'SH'
#!/usr/bin/env bash
exit 0
SH
  chmod +x "$BORN"
  run env CC_WTGC_REPO="$R" CC_WTGC_CC_NOTIFY="$SHIM" CC_WTGC_LSOF="$BORN" \
      CC_WTGC_PGREP="$PGB" CC_WTGC_REGISTRY_DIR="$REG" CC_WTGC_LOCK="$LOCK" \
      CC_WTGC_BACKLOG="$BL" CC_WTGC_DISPOSAL_LOG="$DLOG" bash "$GC"
  [ ! -d "$p" ]
}

# ── A2 oracle 2: the TEAM registry ───────────────────────────────────────────────────────────
# A teammate worktree has no backlog id, so oracle 1 can only ever answer "no owning item" and
# the whole tm/* class stays permanently un-reapable — 7 of the 21 dispose-eligible worktrees
# measured on the live checkout 2026-07-26, against 0 that oracle 1 could serve. Each direction
# gets a discriminator pair, because an oracle that never resolves is the bug being fixed.

@test "A2/team RED-PROOF: teammate of a LIVE team → KEPT; same team torn down → disposed" {
  p="$(abandoned_wt wt-tm-gates tm/gates)"
  team session-abcd tm-gates                       # a live team is an ACTIVE wave
  run_gc --dispose-abandoned
  [ -d "$p" ]
  echo "$output" | grep -q "teammate of a LIVE team"
  # Discriminator — the ONLY thing that changes is the team going dead.
  mv "$TEAMS/session-abcd" "$TEAMS/.dead-session-abcd-1785016677"
  run_gc --dispose-abandoned
  [ ! -d "$p" ]
  has_br tm/gates                                  # the branch is still the durable ref
  echo "$output" | grep -q "owning team session-abcd-1785016677 is DEAD"
}

@test "A2/team: an ARCHIVED team also proves the owner is gone → disposed" {
  p="$(abandoned_wt wt-tm-hooks tm/hooks)"
  team _archive/session-old tm-hooks
  run_gc --dispose-abandoned
  [ ! -d "$p" ]
  echo "$output" | grep -q "owning team session-old is ARCHIVED"
}

@test "A2/team fails CLOSED: no team names the teammate → KEPT, never disposed blind" {
  p="$(abandoned_wt wt-tm-gates tm/gates)"
  team session-other tm-somebody-else              # a populated registry that lacks this member
  run_gc --dispose-abandoned
  [ -d "$p" ]
  echo "$output" | grep -q "no owning team names teammate 'tm-gates'"
}

@test "A2/team: a LIVE team OUTVOTES a dead one naming the same member → KEPT" {
  # A member name recurs across waves. If any team still claims it the worktree is live work,
  # so the dead-team hit must NOT be enough on its own.
  p="$(abandoned_wt wt-tm-gates tm/gates)"
  team .dead-session-old-1785016677 tm-gates
  team session-current tm-gates
  run_gc --dispose-abandoned
  [ -d "$p" ]
  echo "$output" | grep -q "teammate of a LIVE team"
}

@test "A2/team: the disposal ledger records WHICH oracle authorised it" {
  # Months later the ledger has to answer why the directory went; "done item" and "dead team"
  # are different warrants and a bare `"verified"` cannot tell them apart.
  p="$(abandoned_wt wt-tm-wtgc tm/wtgc)"
  team .dead-session-x-1785016677 tm-wtgc
  run_gc --dispose-abandoned
  [ ! -d "$p" ]
  grep -q '"owner_item":"tm-wtgc"' "$DLOG"
  grep -q '"owner_proof":"owning team session-x-1785016677 is DEAD"' "$DLOG"
}

@test "A2/team: a teammate worktree does NOT bypass the ledger route for wt-<id> names" {
  # The two oracles must not leak into each other: a dead team naming `tm-gates` says nothing
  # about a backlog-named worktree, which still needs its own item done.
  p="$(abandoned_wt wt-abc123456789 feat/abandoned)"
  team .dead-session-x-1785016677 tm-gates
  owns abc123456789 claimed
  run_gc --dispose-abandoned
  [ -d "$p" ]
  echo "$output" | grep -q "owning item abc123456789 is 'claimed', not terminal"
}

@test "the un-ownable RESIDUE is COUNTED and reported, never buried among the KEEP lines" {
  # The 2026-07-26 measurement (37 stuck) was invisible precisely because each one was just
  # another KEEP line among dozens. A permanent-KEEP bucket that nothing can ever reap has to
  # announce its own size, or it silently regrows.
  a="$(abandoned_wt wt-board-commands feat/board)"
  b="$(abandoned_wt wt-tm-gates tm/gates)"
  run_gc --dispose-abandoned
  [ -d "$a" ]
  [ -d "$b" ]
  echo "$output" | grep -q "2 unlanded worktree(s) are past the 72h horizon but have NO provable owner"
  # Discriminator: give ONE of them a provable owner and the residue drops to 1.
  team .dead-session-x-1785016677 tm-gates
  run_gc --dispose-abandoned
  [ ! -d "$b" ]
  echo "$output" | grep -q "1 unlanded worktree(s) are past the 72h horizon but have NO provable owner"
}

@test "the residue line stays SILENT when nothing is stuck (no false alarm)" {
  p="$(wt wt-landed feat/landed)"                  # clean · idle · landed ⇒ the normal path
  run_gc
  ! echo "$output" | grep -q "NO provable owner" || false
}
