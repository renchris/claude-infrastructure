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
  # STUB doubles as BOTH process-oracle binaries, and since 2026-08-15 it has to model an oracle
  # that ANSWERS rather than one that is merely present — the subject now reads absence as proof
  # only from a probe that passed its own positive control (scripts/worktree-gc.sh:claude_cwds).
  #   · as `pgrep`: rc 1, no output — the real binary's documented "nothing matched", which is an
  #     ANSWER. (It shipped as `exit 0` with no output, which no real pgrep can ever emit.)
  #   · as `lsof`:  answers the control query for the caller's own pid with a cwd that is not any
  #     fixture worktree, so the harvest is still empty and every REMOVE assertion below still
  #     drives the real removal path.
  # MEASURED when the subject's control landed against the OLD stub: 33 of 83 tests went red,
  # i.e. a third of this suite had been proving removals over an lsof that could not see a single
  # process's cwd. That is the whole defect, reproduced inside the harness that was meant to catch
  # it — an instrument that answers nothing must not be able to certify an absence.
  STUB="$BATS_TEST_TMPDIR/nullbin"
  cat > "$STUB" <<'SH'
#!/usr/bin/env bash
for a in "$@"; do [ "$a" = cwd ] && { printf 'p%s\nn/\n' "$$"; exit 0; }; done
exit 1
SH
  chmod +x "$STUB"
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

  # Ownership oracle 3 — explicit dispose warrants. ABSENT by default (not merely empty), so the
  # no-warrant KEEP is the resting state and no test disposes on a warrant it did not write.
  WTS="$BATS_TEST_TMPDIR/warrants.tsv"

  # THE KILL SWITCH IS AMBIENT BY DESIGN — an operator who has disabled the reaper has it exported
  # in the shell they run this suite from, and every test below would then pass VACUOUSLY against a
  # janitor that exits at line 1. Unset it here so each test states its own switch position. The
  # FILE half needs no unsetting: its default resolves under the fixtured $HOME set above.
  unset CC_WTGC_DISABLE CC_WTGC_DISABLE_FILE
  # AND the runner's own re-entrancy marker, for the same reason one level out (R-c's sibling, R-a).
  # `bin/cc-bats:397` exports CC_BATS_ACTIVE=1 and `:394` short-circuits the whole shim when it is
  # already set, so this suite inherits a DIFFERENT environment depending on whether it was invoked
  # as `bats` or as `cc-bats` — and the postland corpus and a developer's terminal do not agree on
  # which. Sibling suites already unset it (tests/qos-chokepoint.bats:49). The subject reads no
  # CC_BATS_* itself today, so this changes no assertion; it removes the invocation path as a
  # variable, which is what stops a future PATH-shim edit from making the two runs disagree
  # silently. (memory: hermetic-in-stubs-not-in-interpreter — an environment hypothesis is only
  # tested at an environment you actually cleaned.)
  unset CC_BATS_ACTIVE CC_BATS_SEEN CC_BATS_QOS CC_BATS_QOS_MODE CC_BATS_QOS_BAND CC_BATS_QUIET
}

# team <dir> <member> — record a team at <dir> (relative to TEAMS) whose roster names <member>.
# `.dead-<x>` = torn down · `_archive/<x>` = archived · anything else = a LIVE team.
team() {
  mkdir -p "$TEAMS/$1"
  printf '{"teamName":"%s","members":[{"name":"team-lead"},{"name":"%s"}]}\n' "$1" "$2" \
    > "$TEAMS/$1/config.json"
}

# wt <name> <branch> — a clean, landed, idle worktree (the baseline REMOVE candidate).
#
# 🚨 THE ADD'S rc IS ASSERTED, AND THE DIRECTORY IS ASSERTED TO EXIST, because this suite's whole
# REMOVE half reads `[ ! -d "$p" ]` — an assertion a fixture that never CREATED $p satisfies for
# free. Until 2026-08-13 the `worktree add` below discarded its rc into `2>/dev/null` and echoed the
# path unconditionally, so a fixture failure was indistinguishable from a correct disposal.
# MEASURED, by pointing the add at a ref that does not exist so it fails every time: **22 of this
# suite's 79 tests still passed** over a fixture that created nothing at all. The subject here is a
# REAPER; a green suite that cannot tell "removed it" from "it was never there" is the exact shape
# of the vacuous pass this corpus keeps re-learning (memory: verification-harness-vacuous-pass-traps).
# Recorded as R-c in docs/plans/WORKTREE_MANAGEMENT_V2.md §6, which called an explicit fixture
# assertion "worth" having; the measurement above is why it was not optional.
#
# `stderr` is no longer swallowed either — a silenced instrument failure is what made this
# survivable. Fail LOUD and fail EARLY: returning 1 from a command substitution propagates under
# bats' errexit, so a broken fixture reds its own test instead of certifying the subject.
wt() {
  local p="$BATS_TEST_TMPDIR/$1"
  git -C "$R" worktree add -q -b "$2" "$p" HEAD \
    || { echo "wt: FIXTURE FAILED — 'worktree add -b $2 $p' returned $?" >&2; return 1; }
  [ -d "$p" ] || { echo "wt: FIXTURE FAILED — $p absent after a successful add" >&2; return 1; }
  echo "$p"
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
      CC_WTGC_TEAMS_DIR="${TEAMSDIR:-$TEAMS}" CC_WTGC_WARRANTS="${WARRANTS:-$WTS}" \
      CC_WTGC_EXCLUDE="${EXCLUDE:-}" \
      CC_WTGC_SESSION_REGISTRY="${SESSREG:-$BATS_TEST_TMPDIR/no-session-registry}" \
      CC_WTGC_ACTIVE_MIN="${ACTIVEMIN:-0}" bash "$GC" "$@"
}
# The two seams above are the 2026-08-17 occupancy signals (backlog 63484cfeab2a), and both are
# NEUTRALISED by default here — deliberately, and this needs its reason on the record.
#
# SESSREG: the session-cwd registry defaults to a path under the real ~/.claude, so an unshimmed
# read would consult the OPERATOR'S live sessions from a fixture. Pointed at a nonexistent dir,
# which the subject treats as "no store" (not as a broken instrument) and contributes nothing.
#
# ACTIVEMIN=0: the recent-untracked-write signal is LIVENESS-FREE — it fires on any untracked file
# younger than the window, and a bats fixture writes every one of its files SECONDS ago. Left at
# the shipped 30, it would mark literally every fixture worktree occupied and the whole suite would
# assert KEEP against a janitor that can no longer remove anything — the vacuous pass this file's
# discriminator-pair discipline exists to prevent. So the 89 tests about the OTHER gates stay about
# those gates, and the new axis is pinned in BOTH directions by its own pair below, which sets
# ACTIVEMIN explicitly. A default of 0 here is therefore not a narrowing: it is the only value at
# which those tests still test what their names say.

# warrant <path> <sha> <reason> — hand-write oracle 3's TSV record, so a test can fixture a
# MALFORMED or STALE warrant that the --warrant writer would refuse to produce. The path is
# canonicalised exactly as the writer does: on macOS $BATS_TEST_TMPDIR is under /var → /private/var,
# and a raw path would silently never match, which would make every test below vacuously "KEEP".
warrant() {
  local p; p="$(cd "$1" 2>/dev/null && pwd -P)" || p=""
  [ -n "$p" ] || p="$1"
  printf '%s\t%s\t%s\n' "$p" "$2" "$3" >> "$WTS"
}

# 🚨 THIS HELPER COULD NEVER RETURN 0, AND NOTHING NOTICED — the R-c control found it (plan §6).
# Two independent defects, both invisible because all 14 call sites assert it NEGATIVELY:
#   1. PATH FORM. git records a worktree by its RESOLVED physical path, but $BATS_TEST_TMPDIR is
#      the symlinked form: on macOS git reports `/private/var/folders/…` where the fixture holds
#      `/var/folders/…`. Measured — `grep -qF "worktree /var/…"` against a LIVE worktree: no match.
#      So every `! has_wt "$p"` and every `run has_wt "$p"; [ "$status" -ne 0 ]` was passing
#      because the instrument always failed, never because the janitor removed anything. That is
#      the same vacuity R-c names for `[ ! -d "$p" ]`, one layer down and strictly worse: `! -d`
#      at least reads the real filesystem. scripts/worktree-gc.sh has carried a canon() helper
#      folding /private/tmp for exactly this reason since it was written.
#   2. PREFIX COLLISION. A bare `grep -F "worktree $1"` matches a LONGER sibling path — `wt-1`
#      matches the line for `wt-10` — so even with the path form fixed it could report a removed
#      worktree as present. `-x` makes the comparison whole-line.
# Fold /private off BOTH sides, then compare exactly. A removed worktree is absent from the list
# either way, so the negative direction keeps working; the positive direction now works at all,
# which is what the (R-c positive control) test below pins.
has_wt() {
  git -C "$R" worktree list --porcelain | sed -n 's/^worktree //p' | sed 's#^/private##' \
    | grep -qxF "${1#/private}"
}
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

# ── The kill switch (AC-7). Every case below is paired with an act-rule, because a switch is one
#    `exit 0` away from being indistinguishable from a janitor that simply never works.
#    The switch's promise is INERTNESS, so the assertions are about what did NOT happen: no removal,
#    no lock, no warrant record, and — the one that pins the placement rather than the behaviour —
#    no git call at all.

@test "KILL SWITCH: CC_WTGC_DISABLE=1 removes nothing, calls git ZERO times, exits 0" {
  p="$(wt wt-kill feat/kill)"
  GITARGV="$BATS_TEST_TMPDIR/git.argv"
  GSHIM="$BATS_TEST_TMPDIR/gitshim"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> %s\nexec /usr/bin/env git "$@"\n' "$GITARGV" > "$GSHIM"
  chmod +x "$GSHIM"
  CC_WTGC_DISABLE=1 CC_WTGC_GIT="$GSHIM" run_gc --prune-branches --dispose-abandoned
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'verdict=disabled env=CC_WTGC_DISABLE'
  [ -d "$p" ]                 # the baseline REMOVE candidate is untouched
  has_br feat/kill
  [ ! -f "$GITARGV" ]         # never shelled out — the switch sits above the config block
  [ ! -d "$LOCK" ]            # and above the mutex, so it takes no lock either
}

@test "KILL SWITCH RED-PROOF: CC_WTGC_DISABLE=0 is ENABLED — the same worktree IS removed" {
  # The paired act-rule AND the value-semantics discriminator in one: a switch that read every
  # setting as "disabled" would pass the test above while being a permanently broken janitor.
  p="$(wt wt-kill feat/kill)"
  CC_WTGC_DISABLE=0 run_gc
  [ "$status" -eq 0 ]
  [ ! -d "$p" ]
  ! echo "$output" | grep -q 'verdict=disabled' || false
}

@test "KILL SWITCH: the FILE at its default path disables a run that exports nothing" {
  # The property launchd depends on: a scheduled job inherits no shell environment, so the env var
  # alone could never reach the 04:15 sweep. $HOME is fixtured, so this is the real default path.
  p="$(wt wt-killf feat/killf)"
  mkdir -p "$HOME/.claude/autonomy"
  : > "$HOME/.claude/autonomy/worktree-gc.disabled"
  run_gc
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "verdict=disabled file=$HOME/.claude/autonomy/worktree-gc.disabled"
  [ -d "$p" ]
  # …and removing the file re-enables it (the act-rule — the switch is not a one-way latch).
  rm -f "$HOME/.claude/autonomy/worktree-gc.disabled"
  run_gc
  [ ! -d "$p" ]
}

@test "KILL SWITCH: CC_WTGC_DISABLE_FILE= (explicitly empty) ignores the file half" {
  # The documented one-invocation bypass. Without it an operator cannot even look, because the
  # switch deliberately gates --dry-run too.
  p="$(wt wt-killb feat/killb)"
  mkdir -p "$HOME/.claude/autonomy"
  : > "$HOME/.claude/autonomy/worktree-gc.disabled"
  # `=''` not `=` — the empty value is the POINT here (the script's `${VAR-default}` treats set-
  # but-empty as "no file switch"), and the bare form is indistinguishable from a typo to a reader
  # and to shellcheck (SC1007).
  CC_WTGC_DISABLE=0 CC_WTGC_DISABLE_FILE='' run_gc --dry-run
  [ "$status" -eq 0 ]
  [ -d "$p" ]                                   # --dry-run still removes nothing
  echo "$output" | grep -q "would remove"       # but it DID run — the bypass reached the plan
}

@test "KILL SWITCH gates the WARRANT WRITER — the mutation that lives above the mutex" {
  # --warrant appends a TSV record and exits before the lock and before every gate, so a switch
  # placed at the sweep would have let a disabled janitor keep writing dispose authorisations.
  p="$(abandoned_wt wt-killw feat/killw)"
  CC_WTGC_DISABLE=1 run_gc --warrant "$p" --reason "kill-switch test"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'verdict=disabled'
  [ ! -f "$WTS" ]
  # Act-rule: the same command with the switch off DOES write the record.
  run_gc --warrant "$p" --reason "kill-switch test"
  [ "$status" -eq 0 ]
  grep -q "kill-switch test" "$WTS"
}

@test "KILL SWITCH is above the repo resolution — it works where the janitor cannot even start" {
  # Pins the PLACEMENT, not the behaviour: outside a repo the config block exits 2 ("not inside a
  # git repository"). Disabled must mean nothing happened, never a different refusal.
  NOTREPO="$BATS_TEST_TMPDIR/notrepo"; mkdir -p "$NOTREPO"
  run env CC_WTGC_REPO="$NOTREPO" CC_WTGC_DISABLE=1 bash "$GC"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'verdict=disabled'
  # Act-rule: the same invocation without the switch is the exit-2 refusal.
  run env CC_WTGC_REPO="$NOTREPO" bash "$GC"
  [ "$status" -eq 2 ]
  echo "$output" | grep -q 'not inside a git repository'
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

# ── ANSWERABILITY (P1, docs/plans/MASTER_FLEET_FOOTPRINT.md · 2026-08-15) ─────────────────────
# The gate above covers the oracle set being ABSENT. The class that actually swept an occupied
# worktree is the oracle set being PRESENT AND BLIND: `command -v lsof` succeeds, so the process
# oracle counted, and every query it answered with silence was read as "nobody is here". Every
# test below is a DISCRIMINATOR PAIR — blind instrument KEEPS, answering instrument REMOVES THE
# SAME WORKTREE — because a subject that simply stopped removing anything would pass the KEEP
# halves alone, and that is the shape of every vacuous pass this corpus has had to re-learn.
#
# blind_lsof — present, executable, exits 0, and cannot report a cwd for anyone. This is a
# sandboxed / permission-denied / wrong-flavour lsof, and it is indistinguishable from an idle
# machine to any consumer that reads only stdout.
blind_lsof() {
  local b="$BATS_TEST_TMPDIR/lsof-blind"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$b"; chmod +x "$b"
  echo "$b"
}

@test "a PRESENT but BLIND lsof does not count as an oracle — exit 3, never a blind reap" {
  # The load-bearing half. With cc-notify gone, the process oracle is the ONLY candidate; before
  # the answerability control it counted on `command -v` alone, so ORACLES reached 1 on a probe
  # that could not see a single cwd and the "cannot prove idle ⇒ refuse" floor was satisfied by
  # an instrument that proves nothing.
  p="$(wt wt-blind feat/blind)"
  run env CC_WTGC_REPO="$R" CC_WTGC_CC_NOTIFY=/nonexistent/cc-notify \
      CC_WTGC_LSOF="$(blind_lsof)" CC_WTGC_PGREP="$STUB" \
      CC_WTGC_REGISTRY_DIR="$REG" CC_WTGC_LOCK="$LOCK" bash "$GC"
  [ "$status" -eq 3 ]
  [ -d "$p" ]
}

@test "RED PROOF: the same worktree IS removed once lsof can answer its own control" {
  p="$(wt wt-blind feat/blind)"
  run env CC_WTGC_REPO="$R" CC_WTGC_CC_NOTIFY=/nonexistent/cc-notify \
      CC_WTGC_LSOF="$STUB" CC_WTGC_PGREP="$STUB" \
      CC_WTGC_REGISTRY_DIR="$REG" CC_WTGC_LOCK="$LOCK" bash "$GC"
  [ "$status" -eq 0 ]
  [ ! -d "$p" ]
}

@test "a blind lsof KEEPS at act time even when cc-notify carries the pass, and NAMES why" {
  # cc-notify answers, so ORACLES is 1 and the sweep runs to the act gate. recheck_live() skips
  # cc-notify by design (its registry is derived from these same processes) and the sessions it
  # exists to catch are exactly the UNREGISTERED ones — so a blind process probe there leaves the
  # last gate before `worktree remove` with nothing but a record's silence. It must fail CLOSED.
  p="$(wt wt-actblind feat/actblind)"
  run env CC_WTGC_REPO="$R" CC_WTGC_CC_NOTIFY="$SHIM" CC_WTGC_LSOF="$(blind_lsof)" \
      CC_WTGC_PGREP="$STUB" CC_WTGC_REGISTRY_DIR="$REG" CC_WTGC_LOCK="$LOCK" \
      CC_WTGC_BACKLOG="$BL" CC_WTGC_DISPOSAL_LOG="$DLOG" bash "$GC"
  [ "$status" -eq 0 ]
  [ -d "$p" ]
  # The two readings must never share a line: this is an unknown, not an occupancy.
  echo "$output" | grep -q "LIVE at act time (occupancy UNPROVEN"
  echo "$output" | grep -q "lsof cannot read the cwd of this very process"
  ! echo "$output" | grep -q "a session started inside the classify window" || false
  # ...and the degraded oracle is announced at the top, not only per-worktree.
  echo "$output" | grep -q "process-cwd oracle UNAVAILABLE"
}

@test "RED PROOF: with cc-notify unchanged, an ANSWERING lsof removes that same worktree" {
  p="$(wt wt-actblind feat/actblind)"
  run env CC_WTGC_REPO="$R" CC_WTGC_CC_NOTIFY="$SHIM" CC_WTGC_LSOF="$STUB" \
      CC_WTGC_PGREP="$STUB" CC_WTGC_REGISTRY_DIR="$REG" CC_WTGC_LOCK="$LOCK" \
      CC_WTGC_BACKLOG="$BL" CC_WTGC_DISPOSAL_LOG="$DLOG" bash "$GC"
  [ "$status" -eq 0 ]
  [ ! -d "$p" ]
  ! echo "$output" | grep -q "process-cwd oracle UNAVAILABLE" || false
}

@test "pgrep rc 1 is an ANSWER (nothing matched); rc 2 is a failure to read the process table" {
  # The asymmetry is the point. `pgrep` documents 1 as "no processes matched" — a finding — and
  # reserves ≥2 for an error, which is not. Collapsing them would either wedge the janitor on
  # every idle box (if 1 refused) or restore the original defect (if 2 were trusted).
  PG2="$BATS_TEST_TMPDIR/pgrep-err"
  printf '#!/usr/bin/env bash\nexit 2\n' > "$PG2"; chmod +x "$PG2"
  p="$(wt wt-pgerr feat/pgerr)"
  run env CC_WTGC_REPO="$R" CC_WTGC_CC_NOTIFY="$SHIM" CC_WTGC_LSOF="$STUB" \
      CC_WTGC_PGREP="$PG2" CC_WTGC_REGISTRY_DIR="$REG" CC_WTGC_LOCK="$LOCK" \
      CC_WTGC_BACKLOG="$BL" CC_WTGC_DISPOSAL_LOG="$DLOG" bash "$GC"
  [ -d "$p" ]
  echo "$output" | grep -q "pgrep exited 2 — the process table was not read"
  # Discriminator: rc 1 on the same fixture is an answered-empty machine and the worktree goes.
  printf '#!/usr/bin/env bash\nexit 1\n' > "$PG2"; chmod +x "$PG2"
  run env CC_WTGC_REPO="$R" CC_WTGC_CC_NOTIFY="$SHIM" CC_WTGC_LSOF="$STUB" \
      CC_WTGC_PGREP="$PG2" CC_WTGC_REGISTRY_DIR="$REG" CC_WTGC_LOCK="$LOCK" \
      CC_WTGC_BACKLOG="$BL" CC_WTGC_DISPOSAL_LOG="$DLOG" bash "$GC"
  [ ! -d "$p" ]
}

@test "the control is not satisfied by output about SOMEONE ELSE — it reads the caller's own pid" {
  # A control that any output satisfies is not a control. This shim is chatty: it answers the
  # per-claude harvest query for pid 1 in full, and is silent only about the caller. If the
  # subject accepted "lsof said something" it would sail through; the KEEP below is what proves
  # it accepts nothing but a cwd line for the pid it can independently vouch for.
  SEL="$BATS_TEST_TMPDIR/lsof-selective"
  cat > "$SEL" <<'SH'
#!/usr/bin/env bash
pid=""; prev=""; q=0
for a in "$@"; do [ "$prev" = "-p" ] && pid="$a"; [ "$a" = "cwd" ] && q=1; prev="$a"; done
[ "$q" = 1 ] || exit 1
[ -z "$ANSWER_FOR" ] || [ "$pid" = "$ANSWER_FOR" ] || exit 0   # silent about every other pid
printf 'p%s\nn/tmp\n' "$pid"
SH
  chmod +x "$SEL"
  PG1="$BATS_TEST_TMPDIR/pgrep-one"
  printf '#!/usr/bin/env bash\necho 1\n' > "$PG1"; chmod +x "$PG1"
  p="$(wt wt-selective feat/selective)"
  run env CC_WTGC_REPO="$R" CC_WTGC_CC_NOTIFY="$SHIM" CC_WTGC_LSOF="$SEL" \
      CC_WTGC_PGREP="$PG1" CC_WTGC_REGISTRY_DIR="$REG" CC_WTGC_LOCK="$LOCK" \
      CC_WTGC_BACKLOG="$BL" CC_WTGC_DISPOSAL_LOG="$DLOG" ANSWER_FOR=1 bash "$GC"
  [ -d "$p" ]
  echo "$output" | grep -q "process-cwd oracle UNAVAILABLE"
  echo "$output" | grep -q "LIVE at act time (occupancy UNPROVEN"
  # Discriminator: make the SAME shim answer every pid — including the caller's — and the same
  # worktree is removed. Only the control's subject changed; nothing else about the run did.
  run env CC_WTGC_REPO="$R" CC_WTGC_CC_NOTIFY="$SHIM" CC_WTGC_LSOF="$SEL" \
      CC_WTGC_PGREP="$PG1" CC_WTGC_REGISTRY_DIR="$REG" CC_WTGC_LOCK="$LOCK" \
      CC_WTGC_BACKLOG="$BL" CC_WTGC_DISPOSAL_LOG="$DLOG" ANSWER_FOR= bash "$GC"
  [ ! -d "$p" ]
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
  # empty machine, the act-time sweep (the very next `-d cwd` call for the CLAUDE pid) sees the
  # new session. That is the real code path, driven only through the oracle seams the suite
  # already uses.
  #
  # The counter is keyed on the pid pgrep names (1), NOT on every `-d cwd` call, because the
  # subject now opens each probe with an answerability control against its OWN pid. Counting that
  # control would make the shim's state depend on a query that is about the instrument rather than
  # about the machine — the born session would appear one probe early. The control is answered
  # unconditionally here: this test is about a session being BORN, not about a blind lsof, and
  # that distinction is exactly what the subject now keeps apart.
  p="$(wt wt-born feat/born)"
  CNT="$BATS_TEST_TMPDIR/lsof.n"
  BORN="$BATS_TEST_TMPDIR/lsof-born"
  cat > "$BORN" <<'SH'
#!/usr/bin/env bash
q=0; pid=""; prev=""
for a in "$@"; do [ "$prev" = "-p" ] && pid="$a"; [ "$a" = "cwd" ] && q=1; prev="$a"; done
[ "$q" = 1 ] || exit 1
[ "$pid" = 1 ] || { printf 'p%s\nn/\n' "$pid"; exit 0; }   # the control: always answerable
n=$(( $(cat "$LSOF_N" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$LSOF_N"
[ "$n" -gt 1 ] && printf 'p1\nn%s\n' "$BORN_CWD"
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
  echo "$output" | grep -q "LIVE at act time (a session started inside the classify window)"
  # Discriminator: with a machine that is empty at BOTH reads — pgrep names no claude at all, and
  # lsof still answers its control — the same worktree is removed. The emptiness has to come from
  # pgrep, not from a silent lsof: a silent lsof is now UNANSWERABLE, which is a KEEP for a
  # different reason, and a discriminator that passes for the wrong reason discriminates nothing.
  rm -f "$CNT"
  printf '#!/usr/bin/env bash\nexit 1\n' > "$PGB"; chmod +x "$PGB"
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
  echo "$output" | grep -q "2 unlanded worktree(s) are past the 72h horizon with NO ownership oracle at all"
  # Discriminator: give ONE of them a provable owner and the residue drops to 1.
  team .dead-session-x-1785016677 tm-gates
  run_gc --dispose-abandoned
  [ ! -d "$b" ]
  echo "$output" | grep -q "1 unlanded worktree(s) are past the 72h horizon with NO ownership oracle at all"
}

@test "the residue line stays SILENT when nothing is stuck (no false alarm)" {
  p="$(wt wt-landed feat/landed)"                  # clean · idle · landed ⇒ the normal path
  run_gc
  ! echo "$output" | grep -q "NO ownership oracle at all" || false
  ! echo "$output" | grep -q "owner is provably NOT terminal" || false
}

# ── The RESIDUE SPLIT: two stuck states, opposite remedies ───────────────────────────────────
# Measured 2026-07-30: 6 stuck past the horizon, 4 of them owned-by-a-blocked-item. One counter
# spanning both had to name one remedy for both, and the remedy it named — "record the owner
# terminal (cc-backlog done <id>)" — is FALSIFYING the ledger when applied to the owned half.

@test "residue split: a SILENT oracle set and a NOT-TERMINAL owner are counted and prescribed apart" {
  a="$(abandoned_wt wt-board-commands feat/board)"     # no ledger row, no team, no warrant ⇒ silent
  b="$(abandoned_wt wt-abc123456789 feat/blocked)"     # an oracle RULES: owned, and not terminal
  owns abc123456789 blocked
  run_gc --dispose-abandoned
  [ -d "$a" ]
  [ -d "$b" ]
  echo "$output" | grep -q "1 unlanded worktree(s) are past the 72h horizon with NO ownership oracle at all"
  echo "$output" | grep -q "1 unlanded worktree(s) are past the 72h horizon but their owner is provably NOT terminal"
  # The load-bearing half: the owned line must NOT prescribe marking the item done, and the
  # silent line must offer the warrant. Swapped remedies are the defect this test exists for.
  echo "$output" | grep -q "do NOT mark an item done to reap a directory"
  echo "$output" | grep -q -- "--warrant <path> --reason"
}

# ── A2 oracle 3: the EXPLICIT DISPOSE WARRANT ────────────────────────────────────────────────
# Oracles 1 and 2 are INFERRED — they read a record kept for another purpose, so a worktree named
# for a feature (`wt-board-commands`, `wt-reaper-desk-reg`) is invisible to both and no amount of
# age reaches it. That residue regrows on every feature-named worktree, so the fix has to be a way
# to RECORD the decision, not a one-time sweep. Every direction below is red-proofed with a
# discriminator pair: an oracle that never resolves, and one that resolves too easily, are both bugs.

@test "A2/warrant RED-PROOF: no warrant → KEPT; the SAME worktree disposes once one is written" {
  p="$(abandoned_wt wt-board-commands feat/board)"
  owns other-item "done"                              # a populated ledger that simply lacks this owner
  run_gc --dispose-abandoned
  [ -d "$p" ]                                       # ← neither inferred oracle can reach it
  echo "$output" | grep -q "no owning backlog item 'board-commands'"
  # Discriminator — the ONLY thing that changes is the warrant existing.
  warrant "$p" "$(git -C "$R" rev-parse refs/heads/feat/board)" "superseded by trunk 652f66db"
  run_gc --dispose-abandoned
  [ ! -d "$p" ]
  has_br feat/board                                 # the branch is still the durable ref
  echo "$output" | grep -q "explicit dispose warrant — superseded by trunk 652f66db"
}

@test "A2/warrant: a STALE warrant (the tip moved after the decision) → KEPT, never disposed" {
  # THE anti-rot property. A warrant records a decision about a specific state; if work resumed
  # after it was written the decision no longer describes reality, and a warrant that survived
  # that would be a standing licence — the exact failure class this whole residue is an instance of.
  p="$(abandoned_wt wt-board-commands feat/board)"
  warrant "$p" "$(git -C "$R" rev-parse refs/heads/feat/board)" "abandoned"
  echo resumed > "$p/resumed"; git -C "$p" add resumed
  GIT_AUTHOR_DATE="$ANCIENT +0000" GIT_COMMITTER_DATE="$ANCIENT +0000" \
    git -C "$p" commit -qm "work resumed after the warrant"
  run_gc --dispose-abandoned
  [ -d "$p" ]
  echo "$output" | grep -q "dispose warrant is STALE"
}

@test "A2/warrant is PATH-EXACT: a warrant for a DIFFERENT path never authorises this one" {
  # ~/Development/.worktrees is shared across 5 repos (audit §6), so a basename or prefix match
  # could authorise another repo's worktree entirely. Proximity is not evidence.
  p="$(abandoned_wt wt-board-commands feat/board)"
  warrant "${p}-other" "$(git -C "$R" rev-parse refs/heads/feat/board)" "a neighbour, not this one"
  warrant "$(basename "$p")" "$(git -C "$R" rev-parse refs/heads/feat/board)" "bare basename"
  run_gc --dispose-abandoned
  [ -d "$p" ]
  ! echo "$output" | grep -q "explicit dispose warrant" || false
  # Discriminator — a warrant for the path ITSELF, and nothing else changed, does authorise it.
  warrant "$p" "$(git -C "$R" rev-parse refs/heads/feat/board)" "this exact path"
  run_gc --dispose-abandoned
  [ ! -d "$p" ]
  echo "$output" | grep -q "explicit dispose warrant — this exact path"
}

@test "A2/warrant fails CLOSED on a MALFORMED record: no reason, and a too-short pin" {
  p="$(abandoned_wt wt-board-commands feat/board)"
  warrant "$p" "$(git -C "$R" rev-parse refs/heads/feat/board)" ""     # the reason IS the record
  run_gc --dispose-abandoned
  [ -d "$p" ]
  echo "$output" | grep -q "dispose warrant is MALFORMED (no reason recorded)"
  # A pin under 7 chars matches too many commits to be a content check at all.
  : > "$WTS"
  warrant "$p" "abc12" "too short to pin anything"
  run_gc --dispose-abandoned
  [ -d "$p" ]
  echo "$output" | grep -q "under 7 chars"
}

@test "A2/warrant: the LAST record for a path wins, so a re-warrant supersedes a stale one" {
  p="$(abandoned_wt wt-board-commands feat/board)"
  warrant "$p" "0000000000000000000000000000000000000000" "written against an older tip"
  warrant "$p" "$(git -C "$R" rev-parse refs/heads/feat/board)" "re-warranted at the current tip"
  run_gc --dispose-abandoned
  [ ! -d "$p" ]
  echo "$output" | grep -q "re-warranted at the current tip"
}

@test "A2/warrant: a BLOCKED item is NOT a veto — it still reaches oracle 3, and keeps ITS own reason" {
  # The two "owner is not terminal" signals must stay attributable to the oracle that raised them.
  # Conflated, a merely-blocked backlog item takes the LIVE-TEAM veto branch: the KEEP line then
  # quotes the team oracle ("not a teammate worktree"), which is not even about this worktree, and
  # oracle 3 is never consulted — so the one class an operator most needs to warrant is unreachable.
  p="$(abandoned_wt wt-abc123456789 feat/blocked)"
  owns abc123456789 blocked
  run_gc --dispose-abandoned
  [ -d "$p" ]
  echo "$output" | grep -q "owning item abc123456789 is 'blocked', not terminal"
  ! echo "$output" | grep -q "not a teammate worktree" || false
  # And the warrant does reach it — a blocked item is parked work, not an active wave.
  warrant "$p" "$(git -C "$R" rev-parse refs/heads/feat/blocked)" "operator abandoned the blocked item"
  run_gc --dispose-abandoned
  [ ! -d "$p" ]
  has_br feat/blocked
}

@test "A2/warrant: a LIVE owning team VETOES it — an active wave outranks an earlier decision" {
  p="$(abandoned_wt wt-tm-gates tm/gates)"
  team session-current tm-gates
  warrant "$p" "$(git -C "$R" rev-parse refs/heads/tm/gates)" "operator thought this was done"
  run_gc --dispose-abandoned
  [ -d "$p" ]
  echo "$output" | grep -q "teammate of a LIVE team"
  # Discriminator: the warrant was never the problem — tear the team down and it fires.
  mv "$TEAMS/session-current" "$TEAMS/.dead-session-current-1785016677"
  run_gc --dispose-abandoned
  [ ! -d "$p" ]
}

@test "A2/warrant authorises A2 ONLY — every other gate still KEEPS" {
  # A warrant answers "is the owner finished". It must not become a skeleton key for dirty trees,
  # live sessions, busy teammates, or the age floor.
  d="$(abandoned_wt wt-w-dirty feat/wdirty)"; echo scratch > "$d/dirty"
  b="$(abandoned_wt wt-w-busy feat/wbusy)";  : > "$b/.teammate-busy"
  y="$(wt wt-w-young feat/wyoung)"                       # unlanded with a tip of NOW ⇒ idle floor
  echo fresh > "$y/n"; git -C "$y" add n; git -C "$y" commit -qm "fresh unlanded work"
  for p in "$d" "$b" "$y"; do
    warrant "$p" "$(git -C "$p" rev-parse HEAD)" "warranted, but another gate holds"
  done
  run_gc --dispose-abandoned
  [ -d "$d" ]
  [ -d "$b" ]
  [ -d "$y" ]
  echo "$output" | grep -q "KEEP.*wt-w-dirty.*dirty tree"
  echo "$output" | grep -q "KEEP.*wt-w-busy.*teammate-busy"
  echo "$output" | grep -q "KEEP.*wt-w-young.*idle floor"
}

@test "A2/warrant: A1's age floor still binds — a warrant does not shortcut the abandon horizon" {
  # 2 h old: past the 30 min idle floor (so the ABANDON horizon is the gate under test, not the
  # idle one) but far short of 72 h. A warrant answers "is the owner finished", never "is it old".
  p="$(wt wt-board-commands feat/board)"
  echo new > "$p/g"; git -C "$p" add g
  GIT_AUTHOR_DATE="$OLD +0000" GIT_COMMITTER_DATE="$OLD +0000" \
    git -C "$p" commit -qm "unlanded, but only 2h idle"
  warrant "$p" "$(git -C "$R" rev-parse refs/heads/feat/board)" "warranted before the horizon"
  run_gc --dispose-abandoned
  [ -d "$p" ]
  echo "$output" | grep -q "not abandoned: idle 2h < 72h abandon horizon"
  # Discriminator: age it past the horizon and the same warrant fires.
  GIT_AUTHOR_DATE="$ANCIENT +0000" GIT_COMMITTER_DATE="$ANCIENT +0000" \
    git -C "$p" commit -q --amend --no-edit
  : > "$WTS"
  warrant "$p" "$(git -C "$R" rev-parse refs/heads/feat/board)" "warranted past the horizon"
  run_gc --dispose-abandoned
  [ ! -d "$p" ]
}

@test "A2/warrant: the disposal ledger records WHICH oracle authorised it" {
  p="$(abandoned_wt wt-board-commands feat/board)"
  warrant "$p" "$(git -C "$R" rev-parse refs/heads/feat/board)" "superseded by trunk 64886172"
  run_gc --dispose-abandoned
  [ ! -d "$p" ]
  grep -q '"owner_item":"wt-board-commands"' "$DLOG"
  grep -q '"owner_proof":"explicit dispose warrant — superseded by trunk 64886172"' "$DLOG"
}

@test "A2/warrant: a STALE or MALFORMED warrant is NAMED on the KEEP line, never silently ignored" {
  # Silence would read as "nobody ever wrote one" — the opposite of the truth, and it would send
  # the operator to re-write a warrant that already exists.
  p="$(abandoned_wt wt-board-commands feat/board)"
  owns other-item "done"                     # a populated ledger that simply lacks this owner
  warrant "$p" "abc12" "malformed pin"
  run_gc --dispose-abandoned
  [ -d "$p" ]
  echo "$output" | grep -q "no owning backlog item 'board-commands'; dispose warrant is MALFORMED"
  # Discriminator: with NO warrant at all the line carries only the ledger's verdict — the
  # warrant clause must appear because a record exists and was rejected, not unconditionally.
  : > "$WTS"
  run_gc --dispose-abandoned
  echo "$output" | grep -q "no owning backlog item 'board-commands'"
  ! echo "$output" | grep -q "dispose warrant" || false
}

# ── The BLAST RADIUS. `git status --porcelain` (gate 3) cannot see gitignored content and
# `git worktree remove` deletes it anyway at exit 0 — reproduced 2026-07-30. Measured on the live
# residue, 6 of 6 candidates carry ignored content, so a KEEP gate here would make oracle 3 inert
# by construction (how oracle 1 failed). It is NAMED instead, at both points that matter.

@test "BLAST RADIUS: the ledger records the gitignored content a disposal destroys" {
  p="$(abandoned_wt wt-board-commands feat/board)"
  echo 'secrets.env' > "$p/.gitignore"; git -C "$p" add .gitignore
  GIT_AUTHOR_DATE="$ANCIENT +0000" GIT_COMMITTER_DATE="$ANCIENT +0000" \
    git -C "$p" commit -qm "ignore secrets"
  echo 'API_KEY=paid-asset' > "$p/secrets.env"
  [ -z "$(git -C "$p" status --porcelain)" ]          # gate 3 is BLIND to it — the whole problem
  warrant "$p" "$(git -C "$R" rev-parse refs/heads/feat/board)" "abandoned"
  run_gc --dispose-abandoned
  [ ! -d "$p" ]
  grep -q '"destroyed_ignored":"secrets.env"' "$DLOG"
  echo "$output" | grep -q "gitignored content destroyed with it"
}

@test "BLAST RADIUS: a disposal with no ignored content records an EMPTY field, not a fabricated one" {
  p="$(abandoned_wt wt-board-commands feat/board)"
  warrant "$p" "$(git -C "$R" rev-parse refs/heads/feat/board)" "abandoned"
  run_gc --dispose-abandoned
  [ ! -d "$p" ]
  grep -q '"destroyed_ignored":""' "$DLOG"
  ! echo "$output" | grep -q "gitignored content destroyed" || false
}

# ── The --warrant WRITER. A warrant nobody can write is inert, so the writer is the mechanism,
# not a convenience — and every refusal below is a warrant that would have been silently rejected
# at read time, which is the "no operator action required means nothing happens" failure again.

@test "--warrant writes a record pinned to the CURRENT branch tip, and disposes nothing itself" {
  p="$(abandoned_wt wt-board-commands feat/board)"
  run_gc --warrant "$p" --reason "superseded by trunk"
  [ "$status" -eq 0 ]
  [ -d "$p" ]                                        # writing a warrant is not itself a disposal
  head="$(git -C "$R" rev-parse refs/heads/feat/board)"
  grep -qF "$(printf '%s\t%s\tsuperseded by trunk' "$p" "$head")" "$WTS"
  # And the record it wrote is one the reader actually honours — writer and reader agree.
  run_gc --dispose-abandoned
  [ ! -d "$p" ]
}

@test "--warrant REFUSES a path that is not a linked worktree of this repo" {
  # Records come only from `git worktree list` — a warrant must never be writable against a bare
  # directory, because ~/Development/.worktrees holds 5 repos' trees and existence proves nothing.
  mkdir -p "$BATS_TEST_TMPDIR/not-a-worktree"
  run_gc --warrant "$BATS_TEST_TMPDIR/not-a-worktree" --reason "nope"
  [ "$status" -eq 2 ]
  echo "$output" | grep -q "is not a linked worktree"
  [ ! -f "$WTS" ]
}

@test "--warrant REFUSES the primary checkout" {
  run_gc --warrant "$R" --reason "nope"
  [ "$status" -eq 2 ]
  echo "$output" | grep -q "refusing to warrant the primary checkout"
  [ ! -f "$WTS" ]
}

@test "--warrant REFUSES without a reason — an unexplained warrant is malformed at read time" {
  p="$(abandoned_wt wt-board-commands feat/board)"
  run_gc --warrant "$p"
  [ "$status" -eq 2 ]
  echo "$output" | grep -q -- "--warrant requires --reason"
  [ ! -f "$WTS" ]
}

@test "--warrant REFUSES a detached HEAD — no branch would preserve the commits" {
  git -C "$R" worktree add -q --detach "$BATS_TEST_TMPDIR/wt-det" HEAD
  run_gc --warrant "$BATS_TEST_TMPDIR/wt-det" --reason "abandoned"
  [ "$status" -eq 2 ]
  echo "$output" | grep -q "detached HEAD"
  [ ! -f "$WTS" ]
}

@test "--warrant REFUSES a reason containing a tab — it would corrupt its own TSV record" {
  p="$(abandoned_wt wt-board-commands feat/board)"
  run_gc --warrant "$p" --reason "$(printf 'a\tb')"
  [ "$status" -eq 2 ]
  [ ! -f "$WTS" ]
}

@test "--warrant --dry-run writes NOTHING" {
  p="$(abandoned_wt wt-board-commands feat/board)"
  run_gc --warrant "$p" --reason "abandoned" --dry-run
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "would warrant"
  [ ! -f "$WTS" ]
}

@test "--warrant shows the BLAST RADIUS at decision time, where the decision is made" {
  p="$(abandoned_wt wt-board-commands feat/board)"
  echo 'secrets.env' > "$p/.gitignore"; git -C "$p" add .gitignore
  GIT_AUTHOR_DATE="$ANCIENT +0000" GIT_COMMITTER_DATE="$ANCIENT +0000" \
    git -C "$p" commit -qm "ignore secrets"
  echo 'API_KEY=paid-asset' > "$p/secrets.env"
  run_gc --warrant "$p" --reason "abandoned"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "BLAST RADIUS"
  echo "$output" | grep -q "! secrets.env"
}

@test "a flag that takes a value REFUSES to be left dangling, and --reason needs --warrant" {
  run_gc --warrant
  [ "$status" -eq 2 ]
  echo "$output" | grep -q -- "--warrant requires a value"
  run_gc --reason "orphaned"
  [ "$status" -eq 2 ]
  echo "$output" | grep -q -- "--reason is only meaningful with --warrant"
}

# ── LANDED-DIRT: the dirty rung asks CONTENT before it vetoes ────────────────────────────────────
# The dirty gate used to KEEP any non-empty tree, so a worktree holding nothing but content already
# on the trunk was immortal. It cannot be settled by `landed()`: that reads COMMITS, and the live
# dirt is dominated by paths STAGED-or-untracked and never committed — measured 2026-08-10, `git
# cherry` called 72 of 84 dirty trees landed while four staged paths (three assets/blender/*.webp
# renders + tools/blender/clawd_bmo.py, in six worktrees each) were absent from origin/main and on
# NO ref anywhere. So these tests are a DISCRIMINATOR SET on the per-path predicate, and the
# load-bearing member is the ABSENT one: it is the case that would have destroyed real assets.
#
# Fixture shape: trunk gains a file the worktree's branch predates. The branch is therefore an
# ANCESTOR of trunk (landed by patch-id, idle by its backdated tip), and the working tree is dirty
# only with respect to that older HEAD — exactly the live shape.
dirt_wt() { # <name> <branch> <path> <content> → worktree dirty with <path>=<content>
  # rc asserted, stderr not swallowed — the same reason as wt() above, and this is the SECOND site.
  # Measured 2026-08-13: fixing wt() alone took the broken-fixture survivor count from 22 to 17, and
  # every one of the 17 that touches a worktree comes through HERE. A per-site defect needs a
  # per-site fix; one site cured is not the class cured.
  git -C "$R" worktree add -q -b "$2" "$BATS_TEST_TMPDIR/$1" HEAD \
    || { echo "dirt_wt: FIXTURE FAILED — 'worktree add -b $2 $BATS_TEST_TMPDIR/$1' returned $?" >&2; return 1; }
  [ -d "$BATS_TEST_TMPDIR/$1" ] || { echo "dirt_wt: FIXTURE FAILED — $1 absent after a successful add" >&2; return 1; }
  printf '%s' "$4" > "$BATS_TEST_TMPDIR/$1/$3"
  # Canonicalised for the SAME reason warrant() is: on macOS $BATS_TEST_TMPDIR lives under /var,
  # which is a symlink to /private/var. Once trunk_add() has added and removed a worktree, git
  # records subsequent paths resolved, so a raw path would never match the subject's own output and
  # every assertion below would be vacuously un-greppable.
  (cd "$BATS_TEST_TMPDIR/$1" && pwd -P)
}

# trunk_add <path> <content> — advance origin/main past the worktrees' branch point.
trunk_add() {
  local t="$BATS_TEST_TMPDIR/trunkwt"
  # Third site. This one is the most dangerous of the three to leave swallowed: it is what ADVANCES
  # origin/main, so a silent failure here leaves trunk where the branches already are, and every
  # "landed" predicate downstream then reads a shape the test never built.
  git -C "$R" worktree add -q --detach "$t" HEAD \
    || { echo "trunk_add: FIXTURE FAILED — 'worktree add --detach $t' returned $?" >&2; return 1; }
  printf '%s' "$2" > "$t/$1"
  git -C "$t" add "$1"
  GIT_AUTHOR_DATE="$OLD +0000" GIT_COMMITTER_DATE="$OLD +0000" git -C "$t" commit -qm "trunk adds $1"
  git -C "$R" update-ref refs/remotes/origin/main "$(git -C "$t" rev-parse HEAD)"
  git -C "$R" worktree remove --force "$t"
}

@test "dirty BUT every dirty path is byte-identical on trunk → surfaced as a candidate, NOT kept" {
  trunk_add x.md hello
  p="$(dirt_wt wt-redundant feat/redundant x.md hello)"
  run_gc
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "DIRT?   $p"
  echo "$output" | grep -q "dirty worktree(s) hold nothing but content already byte-identical"
  # The candidate is NOT acted on without its own flag.
  has_wt "$p"
}

@test "the same tree IS reaped once --dispose-landed-dirt is passed (the REMOVE half)" {
  trunk_add x.md hello
  p="$(dirt_wt wt-redundant2 feat/redundant2 x.md hello)"
  run_gc --dispose-landed-dirt
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "dispose-dirt  $p"
  run has_wt "$p"
  [ "$status" -ne 0 ]
}

@test "RED PROOF: a dirty path ABSENT from trunk is KEPT and NAMED, even with the flag passed" {
  trunk_add x.md hello
  # The Blender case: a staged/untracked asset that exists nowhere on the trunk.
  p="$(dirt_wt wt-asset feat/asset clawd-bmo-hero.webp RENDER)"
  run_gc --dispose-landed-dirt
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "KEEP    $p"
  echo "$output" | grep -q "absent from origin/main: clawd-bmo-hero.webp"
  has_wt "$p"
}

@test "a dirty path that DIFFERS from trunk is KEPT and NAMED, even with the flag passed" {
  trunk_add x.md hello
  p="$(dirt_wt wt-diff feat/diff x.md CHANGED)"
  run_gc --dispose-landed-dirt
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "KEEP    $p"
  echo "$output" | grep -q "differs from origin/main: x.md"
  has_wt "$p"
}

@test "a DELETION is divergence by construction — kept, never treated as redundant" {
  trunk_add x.md hello
  p="$(dirt_wt wt-del feat/del x.md hello)"
  rm -f "$p/f"                                  # f is tracked at the branch HEAD
  run_gc --dispose-landed-dirt
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "KEEP    $p"
  echo "$output" | grep -q "deletion/unmerged entry"
  has_wt "$p"
}

@test "the content gate only drops the dirty VETO — a LIVE oracle still wins over redundant dirt" {
  trunk_add x.md hello
  p="$(dirt_wt wt-live feat/live x.md hello)"
  touch "$p/.teammate-busy"
  run_gc --dispose-landed-dirt
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "KEEP    $p"
  echo "$output" | grep -q ".teammate-busy marker present"
  has_wt "$p"
}

@test "--dry-run reports the landed-dirt disposal and mutates NOTHING" {
  trunk_add x.md hello
  p="$(dirt_wt wt-dry feat/dry x.md hello)"
  run_gc --dispose-landed-dirt --dry-run
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "dispose-dirt  $p"
  echo "$output" | grep -q "DRY-RUN — nothing was mutated"
  has_wt "$p"
}

# ── LANDED-DIRT leaves a DISPOSAL RECORD, like every other path that destroys a directory ────────
# The asymmetry is the defect, not the stakes. `--dispose-abandoned` has always written one and its
# own comment says why — that record is what later distinguishes abandoned-BY-DECISION from
# dropped-BY-ACCIDENT, which git alone cannot. This path reaped 32 directories on 2026-08-11 and
# appended nothing, so the only durable trace of the gitignored bytes it destroyed was an echo that
# scrolled past. (backlog 34f41cc9118b)

@test "LANDED-DIRT: the disposal is RECORDED, carrying the gitignored blast radius it destroys" {
  # The ignore rule goes in the repo-level exclude, NOT a committed .gitignore. Two reasons, both
  # measured while writing this: trunk_add() advances `refs/remotes/origin/main` ONLY and leaves
  # $R's HEAD where it was, so a .gitignore added through it never reaches the branch dirt_wt cuts;
  # and committing one ON the branch would take the worktree out of the population under test,
  # which requires the branch to be LANDED. info/exclude lives in the common git dir and so applies
  # to the linked worktree while changing no ref at all.
  trunk_add x.md hello
  p="$(dirt_wt wt-rec feat/rec x.md hello)"
  echo 'secrets.env' >> "$R/.git/info/exclude"
  echo 'API_KEY=paid-asset' > "$p/secrets.env"
  # Positive control on the fixture: the file must be INVISIBLE to the dirty gate, which is the
  # whole premise of the blast radius. If this reads non-empty the ignore never took and every
  # assertion below would be measuring the wrong thing.
  [ -z "$(git -C "$p" status --porcelain -- secrets.env)" ]
  run_gc --dispose-landed-dirt
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "dispose-dirt  $p"
  run has_wt "$p"
  [ "$status" -ne 0 ]
  # Count, never `grep -q` on a pipe — under pipefail -q SIGPIPEs the producer and the filter fails
  # on the very input it matched (memory: grep-q-under-pipefail-inverts-the-verdict).
  n="$(grep -cF '"destroyed_ignored":"secrets.env"' "$DLOG" || true)"
  [ "${n:-0}" -eq 1 ]
  # LANDED is what DEFINES this class, so 0 unlanded patches is a measured fact, not a default.
  n="$(grep -cF '"unlanded_patches":0' "$DLOG" || true)"
  [ "${n:-0}" -eq 1 ]
  # The recovery pointer names the TRUNK, because --prune-branches may delete this now-landed,
  # now-worktree-less branch later in the very same run.
  n="$(grep -cF '"preserved_at":"origin/main"' "$DLOG" || true)"
  [ "${n:-0}" -eq 1 ]
}

@test "LANDED-DIRT: --dry-run records NOTHING — a ledger row for a removal that never happened is worse than none" {
  trunk_add x.md hello
  p="$(dirt_wt wt-dryrec feat/dryrec x.md hello)"
  run_gc --dispose-landed-dirt --dry-run
  [ "$status" -eq 0 ]
  has_wt "$p"
  [ ! -s "$DLOG" ]
}

@test "CONTROL: the ABANDONED path's record is byte-unchanged — preserved_at still names its branch" {
  # The optional 11th parameter must default to exactly what every existing caller produced, or
  # this fix silently rewrites the field the other class depends on. That branch is UNLANDED, so
  # --prune-branches skips it and the ref genuinely IS the recovery pointer there.
  p="$(abandoned_wt wt-board-commands feat/board)"
  warrant "$p" "$(git -C "$R" rev-parse refs/heads/feat/board)" "abandoned"
  run_gc --dispose-abandoned
  [ ! -d "$p" ]
  n="$(grep -cF '"preserved_at":"refs/heads/feat/board"' "$DLOG" || true)"
  [ "${n:-0}" -eq 1 ]
}

# ── The INDEX is the second copy, and the working file's hash cannot see it ──────────────────────
# The discriminator set above ranges entirely over the WORKING FILE, so it is uniformly blind to the
# one place a "staged-but-never-committed" byte can hide from `hash-object`: an index entry the
# working file no longer matches. This PAIR is the axis, and the mild half is the load-bearing one —
# a gate keyed on "index equals trunk" would pass the RED below and silently retire every ordinary
# unstaged edit with it, so the pair proves reachability, not equality.
@test "RED PROOF: a STAGED blob on no ref is KEPT, even though the working file matches trunk" {
  trunk_add x.md hello
  p="$(dirt_wt wt-staged feat/staged x.md SECRET)"
  git -C "$p" add x.md                       # index: SECRET — on no ref anywhere
  printf '%s' hello > "$p/x.md"              # working file: byte-identical to trunk ⇒ `AM`
  run_gc --dispose-landed-dirt
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "KEEP    $p"
  echo "$output" | grep -q "staged bytes on no ref: x.md"
  has_wt "$p"
}

@test "an index entry equal to HEAD is REACHABLE — a plain unstaged edit still disposes" {
  trunk_add f trunkver                       # f is tracked at the branch HEAD, holding `a`
  p="$(dirt_wt wt-unstaged feat/unstaged f trunkver)"
  # ` M`: index still holds HEAD's `a` — unequal to trunk, but durable on the preserved branch.
  [ "$(git -C "$p" ls-files -s -- f | awk '{print $2}')" = "$(git -C "$p" rev-parse HEAD:f)" ]
  run_gc --dispose-landed-dirt
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "dispose-dirt  $p"
  run has_wt "$p"
  [ "$status" -ne 0 ]
}

# ── §6 R-c: the fixture helper itself, controlled ───────────────────────────────────────────────
# Every REMOVE-half assertion in this suite is `[ ! -d "$p" ]`, and an ABSENT path satisfies that
# exactly as well as a REAPED one. So `wt()`'s rc is not a nicety — it is the only thing standing
# between "the janitor removed it" and "the fixture never built it". These two cases pin that.
# They FAIL against the pre-R-c helper (which swallowed stderr, ignored the rc, and echoed the
# path regardless), which is what makes them a control rather than a restatement.

@test "(R-c control) wt() FAILS LOUD when 'worktree add' fails — a vacuous REMOVE assertion is impossible" {
  wt wt-dup-a feat/dup >/dev/null            # takes the branch name
  run wt wt-dup-b feat/dup                   # git refuses: branch already checked out
  [ "$status" -ne 0 ]
  # Keyed on the helper's own stable token, not on a phrase this test happens to like: two
  # sessions fixed wt() independently and the surviving wording is the other one's.
  echo "$output" | grep -q "FIXTURE FAILED"
  # …and it must NOT have handed back a usable path: that string is what a caller would have
  # assigned to $p and then asserted `[ ! -d "$p" ]` against, passing for the wrong reason.
  [ ! -d "$BATS_TEST_TMPDIR/wt-dup-b" ]
}

@test "(R-c positive control) wt() still returns a REAL directory on the happy path" {
  p="$(wt wt-happy feat/happy)"
  [ -d "$p" ]                                 # the discriminator: not merely a non-empty string
  [ "$p" = "$BATS_TEST_TMPDIR/wt-happy" ]
  run has_wt "$p"
  [ "$status" -eq 0 ]                         # git agrees it is a registered worktree
}

# ── the machine `counts` line — the janitor's half of the wrapper contract ──────────────────────
# tests/worktree-gc-infra.bats stubs the janitor (its L1), so it can only ever assert what the
# wrapper does with a payload the FIXTURE wrote. That is exactly how the wrapper's positional
# reader went off by one unnoticed when `landed-dirt` was added. This is the other half: the REAL
# janitor emitting the real line, so the two suites cannot drift into agreeing with each other
# about a format neither one produces.

@test "the janitor emits a machine counts line whose named fields match the human summary" {
  wt wt-c1 feat/c1 >/dev/null
  run_gc --dry-run
  [ "$status" -eq 0 ]
  line="$(printf '%s\n' "$output" | grep -m1 '^worktree-gc: counts ')"
  [ -n "$line" ]
  f() { printf '%s\n' "$line" | sed -n "s/.*[[:space:]]$1=\([^[:space:]]*\).*/\1/p" | head -1; }
  # every field the wrapper reads must be present and numeric (elapsed carries an `s` suffix)
  for k in removed disposed landed_dirt kept branches_deleted refusals; do
    v="$(f "$k")"
    [ -n "$v" ] || { echo "missing field: $k"; false; }
    case "$v" in ''|*[!0-9]*) echo "non-numeric $k=$v"; false ;; esac
  done
  case "$(f elapsed)" in *s) ;; *) echo "elapsed lacks its unit"; false ;; esac
  [ "$(f lock_staleness_window)" = "3600s" ]
  [ "$(f dry_run)" = "1" ]
}

@test "counts and the human summary agree — neither may drift from the other" {
  # Two worktrees, one of which the janitor removes; the numbers must be the SAME on both lines.
  wt wt-c2 feat/c2 >/dev/null
  run_gc --dry-run
  [ "$status" -eq 0 ]
  human="$(printf '%s\n' "$output" | grep -m1 '^worktree-gc: removed ')"
  counts="$(printf '%s\n' "$output" | grep -m1 '^worktree-gc: counts ')"
  cf() { printf '%s\n' "$counts" | sed -n "s/.*[[:space:]]$1=\([^[:space:]]*\).*/\1/p" | head -1; }
  # pull the six numbers out of the human line positionally — here that is legitimate, because
  # this test's whole job is to prove the two spellings carry the same values.
  # shellcheck disable=SC2046
  set -- $(printf '%s\n' "$human" | tr -cd '0-9 \n')
  [ "$#" -eq 6 ]                       # if this trips, the human line gained/lost a field
  [ "$1" = "$(cf removed)" ]
  [ "$2" = "$(cf disposed)" ]
  [ "$3" = "$(cf landed_dirt)" ]
  [ "$4" = "$(cf kept)" ]
  [ "$5" = "$(cf branches_deleted)" ]
  [ "$6" = "$(cf refusals)" ]
}

# ════ THE TWO 2026-08-17 OCCUPANCY SIGNALS (backlog 63484cfeab2a) ════════════════════════════════
#
# WHAT WAS SWEPT: an OCCUPIED worktree, mid-session, 2026-08-10 01:50. Every oracle above keys on a
# LIVE PROCESS — cc-notify's cwd list, `lsof -d cwd`, open files, the registry PID. A worktree a
# session holds only through its Bash tool's `cd` has NO resident process between commands, so all
# four read UNOCCUPIED while work is in flight. The two signals below are the ones that can see it.
#
# They are pinned SEPARATELY and each with its own REMOVE half, because they are separate axes and
# a shared pair would let either one carry the other (memory: sibling-guard-makes-the-fixture-vacuous).

@test "session-cwd registry: a live session registered AT the worktree → KEPT" {
  p="$(wt wt-sessreg feat/sessreg)"
  SESSREG="$BATS_TEST_TMPDIR/sessreg"; mkdir -p "$SESSREG"
  printf '{"pid":%s,"cwd":"%s"}\n' "$$" "$p" > "$SESSREG/pane-1.json"
  run_gc
  [ -d "$p" ]
}

@test "session-cwd registry REMOVE half: the same worktree goes once the row names somewhere else" {
  # Without this, a subject that never removes anything would pass the KEEP test above.
  p="$(wt wt-sessreg2 feat/sessreg2)"
  SESSREG="$BATS_TEST_TMPDIR/sessreg2"; mkdir -p "$SESSREG"
  printf '{"pid":%s,"cwd":"%s"}\n' "$$" "$p" > "$SESSREG/pane-1.json"
  run_gc
  [ -d "$p" ]
  printf '{"pid":%s,"cwd":"%s"}\n' "$$" "$BATS_TEST_TMPDIR" > "$SESSREG/pane-1.json"
  run_gc
  [ ! -d "$p" ]
}

@test "session-cwd registry: a row whose PID is DEAD does not keep the worktree alive" {
  # The store is swept by liveness, so a stale row must not be able to make a worktree immortal —
  # the failure mode where a crashed session's registry file pins its worktree forever.
  p="$(wt wt-sessdead feat/sessdead)"
  SESSREG="$BATS_TEST_TMPDIR/sessdead"; mkdir -p "$SESSREG"
  # PID 2^22 is above every kernel pid_max here, so it is reliably unallocated.
  printf '{"pid":4194304,"cwd":"%s"}\n' "$p" > "$SESSREG/pane-1.json"
  run_gc
  [ ! -d "$p" ]
}

@test "session-cwd registry: a session cwd'd in a SUBDIRECTORY still occupies the worktree" {
  # `is_live_cwd` is an EXACT match, so a session that cd'd one level in was invisible to it.
  p="$(wt wt-sessdeep feat/sessdeep)"
  mkdir -p "$p/sub/dir"
  SESSREG="$BATS_TEST_TMPDIR/sessdeep"; mkdir -p "$SESSREG"
  printf '{"pid":%s,"cwd":"%s/sub/dir"}\n' "$$" "$p" > "$SESSREG/pane-1.json"
  run_gc
  [ -d "$p" ]
}

# ignored_scratch <worktree> — commit a .gitignore (backdated, so it cannot revive the idle clock)
# and drop an IGNORED scratch file in the tree.
#
# It must be IGNORED, not merely untracked, and the REMOVE half below is what proved it: a plain
# untracked file shows in `git status --porcelain` as `??`, so gate 3 keeps the worktree and the
# KEEP half passes without the new signal ever being consulted — green for the wrong reason, which
# is the one outcome a discriminator pair exists to catch. Ignored content is the case where gate 3
# is genuinely blind (the BLAST RADIUS block above), so a KEEP here can only come from this axis.
# The .gitignore goes on TRUNK, not into a commit in the worktree. Committing it locally was the
# second wrong-reason green: it left the branch UNLANDED, so the "unlanded → KEEP" gate held the
# tree and the REMOVE half could never fire no matter how stale the file got. Two gates masked this
# axis before the pair isolated it, which is the whole argument for writing the REMOVE half first.
# The ignore rule must be on the BRANCH the worktree checks out AND on trunk. `trunk_add` only
# moves refs/remotes/origin/main, while `wt` branches from R's HEAD, so using it alone left the
# scratch file merely untracked — porcelain non-empty, gate 3 keeping the tree, this axis untested
# again. Committing it into the worktree instead left the branch UNLANDED and that gate kept it.
# Both wrong-reason greens were caught by the REMOVE half rather than by reading the code.
ignore_on_trunk() {
  printf 'agent-scratch.log\n' > "$R/.gitignore"
  git -C "$R" add .gitignore
  GIT_AUTHOR_DATE="$OLD +0000" GIT_COMMITTER_DATE="$OLD +0000" \
    git -C "$R" commit -qm "ignore scratch"
  git -C "$R" update-ref refs/remotes/origin/main HEAD
}

ignored_scratch() {
  local p="$1"
  printf 'scratch\n' > "$p/agent-scratch.log"
  [ -z "$(git -C "$p" status --porcelain)" ]        # gate 3 is BLIND — the KEEP is this axis alone
}

@test "recent ignored write → KEPT, with NO live process anywhere (the liveness-free axis)" {
  # This is the signal that would actually have stopped the 01:50 sweep: no process, no registry
  # row, nothing for a liveness oracle to find — only the residue of work in flight.
  ignore_on_trunk
  p="$(wt wt-active feat/active)"
  ignored_scratch "$p"
  ACTIVEMIN=30 run_gc
  [ -d "$p" ]
}

@test "recent-write REMOVE half: backdate that same file past the window and it is swept" {
  ignore_on_trunk
  p="$(wt wt-active2 feat/active2)"
  ignored_scratch "$p"
  ACTIVEMIN=30 run_gc
  [ -d "$p" ]                                       # KEPT while the write is recent
  touch -t 200001010000 "$p/agent-scratch.log"      # …now it is 26 years stale
  ACTIVEMIN=30 run_gc
  [ ! -d "$p" ]
}

@test "recent-write: a TRACKED file's mtime does NOT count as activity" {
  # A fresh `git worktree add` stamps every checked-out file with the CHECKOUT time, so counting
  # tracked files would read a pristine 2-minute-old worktree as permanently active — the signal
  # would fire on the whole population and mean nothing (memory: alarm-polarity-and-attention-budget).
  p="$(wt wt-tracked feat/tracked)"
  touch "$p/f"                                      # `f` is tracked, and now has a NOW mtime
  ACTIVEMIN=30 run_gc
  [ ! -d "$p" ]
}

@test "recent activity outranks --dispose-landed-dirt: the flag does not overrule occupancy" {
  # The interaction the shipped disposal feature creates, pinned rather than left to chance. A tree
  # whose dirt is byte-identical on trunk is disposable — but if something wrote here in the last
  # 30 minutes, the safe reading is that a session is working, and occupancy wins. Getting this
  # backwards is the original bug with an extra flag on it.
  trunk_add x.md hello
  p="$(dirt_wt wt-dirt-active feat/dirtactive x.md hello)"
  ACTIVEMIN=30 run_gc --dispose-landed-dirt
  [ "$status" -eq 0 ]
  has_wt "$p"
  # …and the same tree IS disposed once its writes age out, so the KEEP above is the signal firing,
  # not the disposal path being broken.
  find "$p" -type f -not -path "$p/.git/*" -exec touch -t 200001010000 {} +
  ACTIVEMIN=30 run_gc --dispose-landed-dirt
  run has_wt "$p"
  [ "$status" -ne 0 ]
}

# ── The shared object store's git `maintenance.lock` (section 4) ─────────────────────────────────
# WHY THIS AXIS EXISTS. Every worktree's `git commit` fires `git maintenance run --auto` against the
# ONE shared object store and git serialises them on `<objectdir>/maintenance.lock`. A holder killed
# mid-run leaves it behind and every later run on the box becomes a permanent SILENT no-op — no log,
# no non-zero exit, no alarm. `docs/research/memory-econ-rearchitecture-2026-08-10/git-maint.md` §8
# named it the store's single point of failure and §9 filed the reaper as "L2 — missing". It then
# happened: 2026-08-19, claude-infrastructure's lock stranded since 2026-08-12 13:18 — 7 days,
# 15,155 loose objects, 154 MiB, with no gc.log and no gc.pid.
#
# HARNESS LAWS FOR THIS BLOCK:
#   L-a  every KEEP has a paired ACT. The reap is proved by the SAME ancient lock surviving when one
#        gate is tripped and vanishing when it is not — a block that only asserted KEEP would pass
#        against a reaper that can never remove anything.
#   L-b  the fixture NEVER calls the subject. It writes the lock itself and resolves the path with
#        plain `git rev-parse`, so a subject that computes the wrong path is caught, not followed.
#   L-c  the locator asserts what it found. `mk_maint_lock` fails LOUD if the file it just created
#        is absent, so no case can pass over a lock that was never there.

# mk_maint_lock [ancient] — create the maintenance lock the subject will look for, and PROVE it.
# The path is derived independently of the subject (L-b); `ancient` backdates it past any floor.
mk_maint_lock() {
  local common
  common="$(git -C "$R" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"
  [ -n "$common" ] || { echo "mk_maint_lock: FIXTURE FAILED — no --git-common-dir for $R" >&2; return 1; }
  MAINTLOCK="$common/objects/maintenance.lock"
  mkdir -p "$(dirname "$MAINTLOCK")"
  : > "$MAINTLOCK"
  [ "${1:-}" = ancient ] && touch -t 200001010000 "$MAINTLOCK"
  [ -e "$MAINTLOCK" ] || { echo "mk_maint_lock: FIXTURE FAILED — $MAINTLOCK absent after creation" >&2; return 1; }
  echo "$MAINTLOCK"
}

# maint_field <name> — read a named field off the machine counts line. Named, never positional:
# this file's own history is a positional reader that mislabelled three columns for weeks.
maint_field() {
  local line
  line="$(printf '%s\n' "$output" | grep -m1 '^worktree-gc: counts ')"
  [ -n "$line" ] || { echo "maint_field: no counts line in output" >&2; return 1; }
  printf '%s\n' "$line" | sed -n "s/.*[[:space:]]$1=\([^[:space:]]*\).*/\1/p" | head -1
}

# says <text> — how many output lines contain <text>. COUNTED, never `grep -q`: under `pipefail` a
# `-q` SIGPIPEs its own producer and the pipeline fails on the input it just matched
# (memory: grep-q-under-pipefail-inverts-the-verdict).
says() {
  local n
  n="$(printf '%s\n' "$output" | grep -cF -- "$1" || true)"
  printf '%s\n' "${n:-0}"
}

# lsof_stub <mode> — replace the shared STUB for one test.
#   holder  answers the cwd positive control AND reports an open fd on any maintenance.lock
#   blind   answers NOTHING, not even the control — the probe that must never certify an absence
lsof_stub() {
  local f="$BATS_TEST_TMPDIR/lsof-$1"
  if [ "$1" = holder ]; then
    cat > "$f" <<'SH'
#!/usr/bin/env bash
for a in "$@"; do [ "$a" = cwd ] && { printf 'p%s\nn/\n' "$$"; exit 0; }; done
case "$*" in *maintenance.lock*) printf 'git 999 t 5w %s\n' "$*"; exit 0 ;; esac
exit 1
SH
  else
    printf '#!/usr/bin/env bash\nexit 1\n' > "$f"
  fi
  chmod +x "$f"
  echo "$f"
}

# run_gc_lsof <lsof-binary> — run_gc with ONE seam swapped. Everything else is identical to run_gc,
# so a difference in verdict can only come from the holder oracle.
run_gc_lsof() {
  local L="$1"; shift
  run env CC_WTGC_REPO="$R" CC_WTGC_CC_NOTIFY="$SHIM" CC_WTGC_LSOF="$L" \
      CC_WTGC_PGREP="$STUB" CC_WTGC_REGISTRY_DIR="$REG" CC_WTGC_LOCK="$LOCK" \
      CC_WTGC_BACKLOG="$BL" CC_WTGC_DISPOSAL_LOG="$DLOG" CC_WTGC_TEAMS_DIR="$TEAMS" \
      CC_WTGC_WARRANTS="$WTS" \
      CC_WTGC_SESSION_REGISTRY="$BATS_TEST_TMPDIR/no-session-registry" \
      CC_WTGC_ACTIVE_MIN=0 bash "$GC" "$@"
}

@test "maintenance lock: stranded and unheld → REAPED, and the box's silent no-op ends" {
  # The ACT half of L-a, and the one the 7-day live incident needed.
  lk="$(mk_maint_lock ancient)"
  run_gc
  [ "$status" -eq 0 ] || false
  [ ! -e "$lk" ] || false
  [ "$(maint_field maint_lock)" = reaped ] || false
  [ "$(says 'REAPED the stranded git maintenance lock')" -ge 1 ]
}

@test "maintenance lock: HELD by a live process → KEPT (the lock working is not a fault)" {
  # KEEP half paired with the reap above: identical ancient lock, only the holder oracle differs.
  # Age can never be the test — a long live repack is exactly as old as a strand.
  lk="$(mk_maint_lock ancient)"
  run_gc_lsof "$(lsof_stub holder)"
  [ "$status" -eq 0 ] || false
  [ -e "$lk" ] || false
  [ "$(maint_field maint_lock)" = held ]
}

@test "maintenance lock: present, unheld, but YOUNGER than the floor → KEPT" {
  # The second gate. A lock created moments ago is indistinguishable from a live run whose opener
  # is not visible yet, so the floor refuses rather than guesses.
  lk="$(mk_maint_lock)"
  run_gc
  [ "$status" -eq 0 ] || false
  [ -e "$lk" ] || false
  [ "$(maint_field maint_lock)" = young ]
}

@test "maintenance lock: --dry-run reports the strand and removes NOTHING" {
  lk="$(mk_maint_lock ancient)"
  run_gc --dry-run
  [ "$status" -eq 0 ] || false
  [ -e "$lk" ] || false
  [ "$(maint_field maint_lock)" = would-reap ] || false
  [ "$(says 'is STRANDED')" -ge 1 ]
}

@test "maintenance lock: an lsof that cannot answer its own control makes the holder UNPROVABLE → KEPT" {
  # Fail-closed, the same rule gate 4 applies. A probe that answers nothing must never be able to
  # certify an absence — that inversion is what let this suite prove 33 removals over a blind lsof.
  lk="$(mk_maint_lock ancient)"
  run_gc_lsof "$(lsof_stub blind)"
  [ "$status" -eq 0 ] || false
  [ -e "$lk" ] || false
  [ "$(maint_field maint_lock)" = unprovable ]
}

@test "maintenance lock: absent → reported as absent, and SILENT (an alarm that always fires carries no bits)" {
  run_gc
  [ "$status" -eq 0 ] || false
  [ "$(maint_field maint_lock)" = absent ] || false
  [ "$(says 'maintenance lock')" -eq 0 ]
}

@test "maintenance lock: CC_WTGC_MAINT_LOCK_MIN raises the floor — the same ancient lock is then KEPT" {
  # Pairs with the reap: identical fixture, identical oracles, only the floor moves. Proves the
  # floor is a real gate and not decoration, without needing a precisely-aged file.
  lk="$(mk_maint_lock ancient)"
  export CC_WTGC_MAINT_LOCK_MIN=99999999
  run_gc
  [ "$status" -eq 0 ] || false
  [ -e "$lk" ] || false
  [ "$(maint_field maint_lock)" = young ]
}

# ── THE FAIL-OPEN PIPELINE IN is_live_cwd (drain recycle #242) ────────────────────────────────────
# The last two members of the class recycle #241 drained out of six own-scope lints, and the two its
# derived class guard cannot see: that guard's population is scripts/*-lint.sh × {in_own,
# in_allowlist} (tests/gate-ownscope-leak.bats), and this is neither a lint nor either name. Absent
# from a detector's population is not exempt — it is invisible.
#
# THE SHAPE. is_live_cwd is a one-line function whose whole body is `printf … | grep -qxF "$1"`. It
# is the FUNCTION-FINAL statement, so its rc is exactly what scripts/worktree-gc.sh's occupancy
# ladder reads at its `elif is_live_cwd "$cpath"` rung. Under the `set -uo pipefail` this script
# sets, `grep -q` exits the instant it matches, printf takes SIGPIPE, and the caller is handed a
# non-zero that means NOT LIVE. A MATCH would read as "nobody is here" — in the janitor that REMOVES
# worktrees. scripts/deploy-link-parity.sh:264 wrote this scar out once already.
#
# LATENT, NOT LIVE, AND THE DIFFERENCE IS THE HONEST PART. LIVE_CWDS is the registered-session cwd
# list: measured 545 bytes on this box 2026-08-26T18:14Z, some 100x under the floor below. Four
# further keep-arms sit beneath this rung (registry_live, session_occupancy_keep, recently_active,
# lsof), so an inverted answer loses THIS arm rather than collecting an occupied worktree outright.
# It is drained because that feed is an operational quantity that only grows and nothing announces
# the crossing — not because it is failing today.
#
# THE REGIME IS MEASURED, NOT INHERITED (2026-08-26, load ~14-16, 20 trials per size, needle on line
# 1, with a second column counting the needle in the set the subject actually sees):
#     builtin producer   printf | grep -q    safe 37,121 · 1/20 inverted 55,721 · ALWAYS 87,122+
#     external producer  cat    | grep -q    safe 55,722 · 19/20 inverted 65,580 · ALWAYS 87,151+
# THE TWO AGREE, and that is a correction to how the first table reads. #241 measured the builtin
# two-stage and an external THREE-stage form and landed both; read together they suggest the
# producer's externality is what moves the floor. Re-run at #241's own grid points it does not: an
# external producer is still safe at 55,722 where the builtin was already 1/20 racy. What moved the
# floor in the three-stage row was the extra STAGE — an intermediate `sed` that writes line by line
# and can never hand grep one buffer-sized write. Cite the STAGE COUNT, not the producer.

@test "is_live_cwd still answers LIVE on a cwd list past the pipe-buffer regime" {
  # THE BEHAVIOURAL ARM. It pins the MECHANISM rather than a spelling, so it survives any rewording
  # of the fix (memory: control-calibrated-to-implementation-decays — #240 lost a run to a stub keyed
  # on the exact flag string its own correct fix removed). The function is EXTRACTED from the shipped
  # script and sourced, never re-implemented (memory: control-must-replay-the-real-artifact).
  # 120,000 bytes is past the always-inverted floor of BOTH producer shapes above, so a re-introduced
  # `grep -q` fails this on every run rather than one run in twenty.
  local f="$BATS_TEST_TMPDIR/is_live_cwd.sh" s="$BATS_TEST_TMPDIR/cwds.txt"
  /usr/bin/sed -n '/^is_live_cwd()/p' "$REPO/scripts/worktree-gc.sh" > "$f"
  [ -s "$f" ] || { echo "is_live_cwd not found in worktree-gc.sh — the extractor has stopped matching" >&2; return 1; }
  awk 'BEGIN{ printf "/Users/x/Development/.worktrees/zz-needle\n";
              for (i = 1; i <= 2600; i++) printf "/Users/x/Development/.worktrees/filler-%06d-aaaaaaaaaaaaaaaaaa\n", i }' > "$s"
  [ "$(wc -c < "$s")" -ge 87151 ] || { echo "fixture is under the inverting floor — it cannot discriminate" >&2; return 1; }

  # POSITIVE: a registered cwd reads LIVE (rc 0). A re-introduced -q answers 1 or 141 here.
  run bash -c "set -uo pipefail; . '$f'; LIVE_CWDS=\"\$(cat '$s')\"; is_live_cwd '/Users/x/Development/.worktrees/zz-needle'; echo rc=\$?"
  [ "$output" = "rc=0" ] || { echo "a REGISTERED cwd read as NOT-LIVE: $output" >&2; return 1; }

  # NEGATIVE: an unregistered cwd must still answer non-zero, so this cannot pass by always saying 0.
  run bash -c "set -uo pipefail; . '$f'; LIVE_CWDS=\"\$(cat '$s')\"; is_live_cwd '/Users/x/Development/.worktrees/absent'; echo rc=\$?"
  [ "$output" = "rc=1" ] || { echo "an UNREGISTERED cwd did not answer 1: $output" >&2; return 1; }
}

# ── THE FAIL-OPEN PIPELINE IN THE BRANCH-PRUNE GUARD (drain recycle #243) ─────────────────────────
# The third member of is_live_cwd's class in this file, and the only one on a DESTRUCTIVE path. It
# is also the one the detector could already SEE: pipefail-sigpipe-lint --census listed
# scripts/worktree-gc.sh:1303 and pipefail-sigpipe-allow.txt grandfathered it at count 1, so this
# drain SHRINKS the ratchet and deletes that allowlist row in the same diff (census LOST=1, NEW=0).
#
# WHY THE DIRECTION MATTERS HERE MORE THAN AT THE OTHER TWO SITES. The predicate answers "does this
# branch still hold a worktree", and its whole job is to STOP a delete. Inverted, a branch that is
# still checked out reads as having no worktree and falls through to `git branch -d`. The comment
# beside it calls `branch -d` the second gate, and it is — but it only refuses an UNMERGED branch,
# and every candidate that reaches it has already passed `landed`, so on exactly this population it
# refuses nothing. The two sites #242 drained sat under four further keep-arms; this one has none.
@test "holds_worktree still answers FOUND on a branch list past the pipe-buffer regime" {
  # THE BEHAVIOURAL ARM, pinning the MECHANISM and not a spelling, so it survives any rewording of
  # the fix (memory: control-calibrated-to-implementation-decays). The function is EXTRACTED from
  # the shipped script and sourced, never re-implemented (memory: control-must-replay-the-real-
  # artifact). 120,000 bytes is past the always-inverted floor of both 2-stage rows measured by
  # #241/#242 (87,122 builtin · 87,151 external), so a re-introduced `grep -q` fails this on EVERY
  # run rather than one run in twenty — deterministic by construction, not racy.
  local f="$BATS_TEST_TMPDIR/holds_worktree.sh" s="$BATS_TEST_TMPDIR/branches.txt"
  /usr/bin/sed -n '/^holds_worktree()/p' "$REPO/scripts/worktree-gc.sh" > "$f"
  [ -s "$f" ] || { echo "holds_worktree not found in worktree-gc.sh — the extractor has stopped matching" >&2; return 1; }
  awk 'BEGIN{ printf "drain/zz-needle\n";
              for (i = 1; i <= 2600; i++) printf "wave/filler-%06d-aaaaaaaaaaaaaaaaaaaaaaaa\n", i }' > "$s"
  [ "$(wc -c < "$s")" -ge 87151 ] || { echo "fixture is under the inverting floor — it cannot discriminate" >&2; return 1; }

  # POSITIVE: a branch that still holds a worktree reads FOUND (rc 0), which is the KEEP. A
  # re-introduced -q answers non-zero here and the branch would be deleted out from under it.
  run bash -c "set -uo pipefail; . '$f'; WT_BRANCHES=\"\$(cat '$s')\"; holds_worktree 'drain/zz-needle'; echo rc=\$?"
  [ "$output" = "rc=0" ] || { echo "a branch WITH a live worktree read as having none: $output" >&2; return 1; }

  # NEGATIVE: a branch with no worktree must still answer non-zero, so this cannot pass by always
  # saying 0 — which would turn the guard into a blanket KEEP and quietly disable --prune-branches.
  run bash -c "set -uo pipefail; . '$f'; WT_BRANCHES=\"\$(cat '$s')\"; holds_worktree 'drain/absent'; echo rc=\$?"
  [ "$output" = "rc=1" ] || { echo "a branch with NO worktree did not answer 1: $output" >&2; return 1; }
}

@test "the branch-prune guard CALLS holds_worktree — the drain reached the destructive site" {
  # The arm above proves the FUNCTION is sound; this proves the guard actually uses it. Without it
  # the extractor could pass against a sound helper that nothing calls, which is the whole failure
  # mode of a drain that edits a definition and leaves the call site alone.
  local n
  n="$(/usr/bin/grep -c -e 'if holds_worktree "$branch"; then' "$REPO/scripts/worktree-gc.sh" | head -1)"
  [ "${n:-0}" -eq 1 ] || { echo "the prune guard does not call holds_worktree exactly once (got ${n:-0})" >&2; return 1; }
  # ...and the rc-destroying spelling is gone from the file entirely.
  n="$(/usr/bin/grep -c -e 'grep -qxF' "$REPO/scripts/worktree-gc.sh" | head -1)"
  [ "${n:-0}" -eq 1 ] || { echo "expected exactly the one surviving grep -qxF (a FILE read, not a pipeline), got ${n:-0}" >&2; return 1; }
}
