#!/usr/bin/env bats
# reso-resume-one — the first test suite this file has ever had.
#
# It had none because until now it was not in the repo: it lived only at ~/.reso/bin/reso-resume-one
# while four tracked scripts called it (boot-resume-launch.sh:89, boot-resume.sh, lr-fire-resume.sh,
# and the resume-sessions runbook). Untracked meant outside the ship gate, outside shellcheck, and
# outside every reader that could notice it rot. The sibling suites that mention it
# (kitty-recovery-launch.bats:308, capacity-admit.bats:4) only ever STUB it — before this file the
# real binary was never executed by a single test, and three defects rode along:
#
#   1. `effort=high` was re-pinned on every fable arm, with no way for a caller to say otherwise, so
#      a Fable-5-at-max session came back at high. Landed elsewhere as 0c00b814 / 91ef8694.
#   2. the resume dialog was answered with a bare CR on a match for the 19-character literal
#      `Resume from summary` — the WRONG option, by a match that dies at the wrap.
#   3. REPO was the constant $HOME/Development/reso-management-app, so the recreate-a-reaped-worktree
#      capability that /resume-sessions Phase 1b passes --allow-missing-cwd to reach worked for
#      exactly one repository.
#
# EVERY TEST BELOW EXECUTES THE REAL FILE. The claude binary is replaced by a stub (an existing seam,
# CC_RESUME_CLAUDE_BIN) that renders the 2.1.220 resume dialog verbatim and answers arrow keys as
# Ink SelectInput does — so the matcher, the keystrokes and the spawn argv under test are the live
# ones. The stub records two facts the script cannot fake: the argv it was ACTUALLY spawned with,
# and the option value ultimately selected. Announcing the right effort and passing it are different
# claims, and only the second one matters.
#
# Measured mutants (2026-08-10), each red on exactly its own tests:
#   · matcher → `-re {Resume from summary} { send "\r" }` : NO selection at 8 and 20 cols, `compact`
#     at 80 — both halves of the live defect, in one mutant.
#   · fable arm → `model=claude-fable-5 effort=high`      : argv reads `--effort high`.
#   · resolve_repo → the constant                         : "branch does not exist in
#     reso-management-app", worktree never recreated.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  RRO="$REPO_ROOT/bin/reso-resume-one"
  [ -x "$RRO" ] || { echo "subject missing or not executable: $RRO" >&2; return 1; }

  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_RESUME_MODEL=claude-opus-5          # never read the host SSOT
  export CC_RESUME_NO_INTERACT=1                # interact needs a controlling tty; nothing else changes
  # The engine carries a capacity gate as of 2026-08-17. Every case below is about pin resolution,
  # worktree recreation and the resume dialog — none is about admission — so the gate is pinned OFF
  # here rather than left to the verifier's own load. A refusal keyed on the box being busy would
  # otherwise fire on THIS HARNESS, reddening unrelated cases on a loaded machine and passing on an
  # idle one (memory: guard-refusal-fires-on-its-own-harness). The gate's own behaviour is asserted
  # in the three dedicated cases at the end of this file, with it explicitly ON.
  export CC_ADMIT_GATE=off
  export CC_RR_STUB_ARGV="$BATS_TEST_TMPDIR/argv"
  export CC_RR_STUB_OUT="$BATS_TEST_TMPDIR/selected"
  export CC_RESUME_CLAUDE_BIN="$BATS_TEST_TMPDIR/fake-claude"
  export CC_RESUME_REPO_ROOTS="$BATS_TEST_TMPDIR/dev"
  WT="$BATS_TEST_TMPDIR/wt"; mkdir -p "$WT"
  mk_stub
}

# The dialog, VERBATIM from the CC 2.1.220 bundle — labels, values and render order. Reproduced
# rather than invented, because a test that answers a menu of its own design proves nothing about
# the one on the box. Word-wrapped at CC_RR_STUB_COLS, which is what makes width a variable here.
mk_stub() {
  cat > "$CC_RESUME_CLAUDE_BIN" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" > "$CC_RR_STUB_ARGV"
cols=${CC_RR_STUB_COLS:-80}
wrap() { fold -s -w "$cols"; }
LABELS=("Resume from summary (recommended)" "Resume full session as-is" "Do not ask me again")
VALUES=(compact continue never)
# Header + body stream BEFORE Ink mounts the SelectInput and enables raw mode (lr-fire-resume:178,
# measured 2026-07-11 on four monster sessions). CC_RR_STUB_MOUNT_DELAY reproduces that gap, so
# anything answered off the body is answered into a terminal that is not listening.
{
  printf 'This session is 2h 10m old and 412k tokens.\n'
  printf 'Resuming the full session will consume a substantial portion of your usage limits. We recommend resuming from a summary.\n'
} | wrap
sleep "${CC_RR_STUB_MOUNT_DELAY:-0}"
[ -n "${CC_RR_STUB_NO_MENU:-}" ] && { sleep 3; exit 0; }
stty raw -echo 2>/dev/null
i=0
render() {
  local n p
  for n in 0 1 2; do
    if [ "$n" -eq "$i" ]; then p='> '; else p='  '; fi
    printf '%s%s\n' "$p" "${LABELS[$n]}"
  done | wrap
}
render
while IFS= read -r -s -n 1 c; do
  case "$c" in
    $'\033')
      rest=""; read -r -s -n 2 -t 1 rest || true
      case "$rest" in
        '[A') [ "$i" -gt 0 ] && i=$((i - 1)) ;;
        '[B') [ "$i" -lt 2 ] && i=$((i + 1)) ;;
      esac
      render ;;
    ''|$'\r'|$'\n') printf '%s\n' "${VALUES[$i]}" > "$CC_RR_STUB_OUT"; break ;;
  esac
done
stty sane 2>/dev/null
printf 'shift+tab to cycle\n'
sleep 1
STUB
  chmod +x "$CC_RESUME_CLAUDE_BIN"
}

selected() { cat "$CC_RR_STUB_OUT" 2>/dev/null; }
spawn_argv() { cat "$CC_RR_STUB_ARGV" 2>/dev/null; }

# A repo at $BATS_TEST_TMPDIR/dev/<name> with <branch>, plus a worktree at <wtpath> that is then
# REAPED — leaving the .git/worktrees back-reference that is the whole point of the derivation.
mk_reaped_worktree() { # <repo-name> <branch> <wtpath>
  local r="$BATS_TEST_TMPDIR/dev/$1"
  mkdir -p "$r"
  git init -q "$r"
  git -C "$r" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  git -C "$r" branch "$2"
  git -C "$r" worktree add -q "$3" "$2"
  rm -rf "$3"
}

# ── 1. effort survives the resume ────────────────────────────────────────────────────────────────

@test "a fable session resumed at max comes back at max, not high" {
  # THE defect. The fable arms hardcoded effort=high with no caller override, so every Fable-5
  # session recovered one reasoning tier down while its statusline still read "Fable 5". Asserted on
  # the binary's OWN argv, not the announcement line: announcing an effort and passing it are
  # separate claims and only the second one moves the session.
  run env CC_RR_STUB_COLS=80 timeout 90 "$RRO" fable4 "$WT" SID-EFFORT --effort max
  [ "$status" -eq 0 ]
  [[ "$(spawn_argv)" == *"--model claude-fable-5"* ]] || false
  [[ "$(spawn_argv)" == *"--effort max"* ]] || false
  [[ "$(spawn_argv)" != *"--effort high"* ]]
}

@test "omitted, --effort leaves prior behaviour byte-identical (fable ⇒ high)" {
  # The other half of the contract lr-handoff states: the flag must be additive. A fix that changed
  # the default would move every existing caller — boot-resume.sh and the runbook pass no flag.
  run env CC_RR_STUB_COLS=80 timeout 90 "$RRO" fable4 "$WT" SID-DEFAULT
  [ "$status" -eq 0 ]
  [[ "$(spawn_argv)" == *"--model claude-fable-5"* ]] || false
  [[ "$(spawn_argv)" == *"--effort high"* ]]
}

@test "CC_RESUME_EFFORT reaches a fable account too — the arm must not re-pin over it" {
  # SECOND SITE, and it needs its own mutant because the first one cannot reach it. The flag is
  # applied AFTER the account case, so re-pinning effort=high inside a fable arm is inert against
  # --effort and a mutant there reds nothing. It is NOT inert against the env seam, which is set
  # BEFORE the case: with the re-pin restored this reads high. Deleting the re-pins is therefore a
  # behaviour change on this path, not tidying, and this is the only test that says so.
  run env CC_RESUME_EFFORT=xhigh CC_RR_STUB_COLS=80 timeout 90 "$RRO" fable2 "$WT" SID-ENVEFFORT
  [ "$status" -eq 0 ]
  [[ "$(spawn_argv)" == *"--model claude-fable-5"* ]] || false
  [[ "$(spawn_argv)" == *"--effort xhigh"* ]]
}

@test "an unrecognised --effort is refused BEFORE any worktree is touched" {
  # Liveness, not quoting (lr-handoff:145): the binary would refuse this itself, but by then this
  # process has recreated a worktree and handed a pane to a session that never comes up.
  mk_reaped_worktree solo feat/solo "$BATS_TEST_TMPDIR/reaped"
  run timeout 30 "$RRO" next "$BATS_TEST_TMPDIR/reaped" SID-BAD feat/solo --effort maximum
  [ "$status" -eq 2 ]
  [[ "$output" == *"--effort must be low|medium|high|xhigh|max"* ]] || false
  [ ! -d "$BATS_TEST_TMPDIR/reaped" ]
}

# ── 2 + 3. the menu is answered, at every width, with full-session-as-is ─────────────────────────

@test "the dialog is answered with full-session-as-is at 80 columns" {
  # A bare CR takes the cursor's resting place — option 1, "Resume from summary" — which /compacts
  # the transcript and (REFERENCE.md §5) drops the session-scoped /goal hook, so the recovered
  # session sits idle. The operator wants the session, not a precis of it.
  run env CC_RR_STUB_COLS=80 timeout 90 "$RRO" next2 "$WT" SID-80
  [ "$status" -eq 0 ]
  [ "$(selected)" = "continue" ]
  [ "$(selected)" != "compact" ]
}

@test "the dialog is answered with full-session-as-is at 40 columns" {
  run env CC_RR_STUB_COLS=40 timeout 90 "$RRO" next2 "$WT" SID-40
  [ "$status" -eq 0 ]
  [ "$(selected)" = "continue" ]
}

@test "the dialog is answered with full-session-as-is at 20 columns" {
  # The pre-fix literal `Resume from summary` is 19 characters and Ink hard-wraps to the pane, so
  # from here down the old matcher does not fire AT ALL: the menu sits unanswered until the timeout.
  # Measured on the mutant: no selection whatsoever at 20 and at 8.
  run env CC_RR_STUB_COLS=20 timeout 90 "$RRO" next2 "$WT" SID-20
  [ "$status" -eq 0 ]
  [ "$(selected)" = "continue" ]
}

@test "the dialog is answered with full-session-as-is at 8 columns" {
  # 8 is past word-wrapping into hard character breaks — `(recommended)` is split mid-word here.
  # `as-is` is five characters, so it is still one token, which is the property the trigger buys.
  run env CC_RR_STUB_COLS=8 timeout 90 "$RRO" next2 "$WT" SID-8
  [ "$status" -eq 0 ]
  [ "$(selected)" = "continue" ]
}

@test "the answer waits for the option list — the body text alone must not trigger it" {
  # The 2026-07-11 scar, encoded. The body ("we recommend resuming from a summary") streams seconds
  # before raw mode exists, so a matcher keyed on it fires into a terminal that is not listening:
  # the keystrokes are swallowed, the one-shot guard is already spent, and the menu then hangs
  # forever. With a 6s mount delay, a body-triggered answer produces NO selection.
  run env CC_RR_STUB_COLS=80 CC_RR_STUB_MOUNT_DELAY=6 timeout 120 "$RRO" next2 "$WT" SID-DELAY
  [ "$status" -eq 0 ]
  [ "$(selected)" = "continue" ]
}

@test "a session that never shows the dialog is resumed anyway" {
  # Small sessions never reach the prompt. The one-shot answer must not become a precondition.
  run env CC_RR_STUB_COLS=80 CC_RR_STUB_NO_MENU=1 timeout 60 "$RRO" next "$WT" SID-NOMENU
  [ "$status" -eq 0 ]
  [[ "$(spawn_argv)" == *"--resume SID-NOMENU"* ]]
}

# ── 4. a NON-reso repo's reaped worktree is recreated ────────────────────────────────────────────

@test "a reaped worktree is recreated in whatever repo actually owns it" {
  # The headline capability, and the reason /resume-sessions Phase 1b passes --allow-missing-cwd.
  # Against the constant it worked for reso-management-app and no other repo, so every non-reso
  # session admitted on that promise died at "worktree <wt> missing".
  mk_reaped_worktree notreso feat/only-here "$BATS_TEST_TMPDIR/wts/only-here"
  run env CC_RESUME_DRYRUN=1 timeout 60 "$RRO" next "$BATS_TEST_TMPDIR/wts/only-here" SID-WT feat/only-here
  [ "$status" -eq 0 ]
  [ -d "$BATS_TEST_TMPDIR/wts/only-here" ]
  run git -C "$BATS_TEST_TMPDIR/wts/only-here" rev-parse --abbrev-ref HEAD
  [ "$output" = "feat/only-here" ]
}

@test "the owning repo is found by ITS OWN back-reference, not by the worktree path" {
  # The paths on this box are pooled (~/Development/.worktrees/<branch>) and name no repo, so the
  # derivation has to come from the repo side. A decoy repo carrying the SAME branch name must not
  # be able to answer when the real owner's .git/worktrees entry exists.
  mk_reaped_worktree owner shared/name "$BATS_TEST_TMPDIR/wts/shared"
  mkdir -p "$BATS_TEST_TMPDIR/dev/decoy"
  git init -q "$BATS_TEST_TMPDIR/dev/decoy"
  git -C "$BATS_TEST_TMPDIR/dev/decoy" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  git -C "$BATS_TEST_TMPDIR/dev/decoy" branch shared/name
  run env CC_RESUME_DRYRUN=1 timeout 60 "$RRO" next "$BATS_TEST_TMPDIR/wts/shared" SID-OWN shared/name
  [ "$status" -eq 0 ]
  # Matched on the tail, not the whole path: git answers with the PHYSICAL path and the fixture root
  # is reached through a symlink on this platform — the very mismatch that made the derivation miss
  # its back-reference and silently fall through to the branch fallback. /dev/decoy would fail this.
  run git -C "$BATS_TEST_TMPDIR/wts/shared" rev-parse --path-format=absolute --git-common-dir
  [[ "$output" == */dev/owner/.git* ]]
}

@test "two repos could answer and neither back-references it ⇒ REFUSE, never pick one" {
  # Checking a worktree out of the wrong repository is worse than not recreating it, and it is what
  # a "first match wins" fallback would do. Branch names repeat across repos by design.
  local a="$BATS_TEST_TMPDIR/dev/a" b="$BATS_TEST_TMPDIR/dev/b"
  for r in "$a" "$b"; do
    mkdir -p "$r"; git init -q "$r"
    git -C "$r" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
    git -C "$r" branch main2
  done
  run env CC_RESUME_DRYRUN=1 timeout 60 "$RRO" next "$BATS_TEST_TMPDIR/wts/ambig" SID-AMB main2
  [ "$status" -eq 3 ]
  [[ "$output" == *"cannot tell which repo owns"* ]] || false
  [ ! -d "$BATS_TEST_TMPDIR/wts/ambig" ]
}

@test "--repo names the owner outright when nothing can derive it" {
  local r="$BATS_TEST_TMPDIR/elsewhere/repo"       # deliberately outside CC_RESUME_REPO_ROOTS
  mkdir -p "$r"; git init -q "$r"
  git -C "$r" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  git -C "$r" branch feat/explicit
  run env CC_RESUME_DRYRUN=1 timeout 60 "$RRO" next "$BATS_TEST_TMPDIR/wts/exp" SID-EXP feat/explicit --repo "$r"
  [ "$status" -eq 0 ]
  [ -d "$BATS_TEST_TMPDIR/wts/exp" ]
}

# ── caller compatibility ─────────────────────────────────────────────────────────────────────────

@test "the 4th positional is still the branch — every existing caller's argv is unchanged" {
  # boot-resume-launch.sh:89, boot-resume.sh and the runbook all pass <acct> <wt> <sid> <branch>
  # positionally, and lr-select.py's 4th TSV column feeds it verbatim. Flags are additive AFTER it.
  mk_reaped_worktree compat feat/compat "$BATS_TEST_TMPDIR/wts/compat"
  run env CC_RESUME_DRYRUN=1 timeout 60 "$RRO" next "$BATS_TEST_TMPDIR/wts/compat" SID-COMPAT feat/compat
  [ "$status" -eq 0 ]
  [ -d "$BATS_TEST_TMPDIR/wts/compat" ]
}

@test "an unknown account is refused, and an unknown flag is not swallowed as a branch" {
  run timeout 30 "$RRO" nosuchacct "$WT" SID-X
  [ "$status" -eq 2 ]
  run timeout 30 "$RRO" next "$WT" SID-X --nonsense
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown arg --nonsense"* ]]
}

# ── deployment: the live tool must BE this file, not a copy of it ────────────────────────────────

@test "~/.reso/bin/reso-resume-one is a symlink into the checkout, so it cannot drift" {
  # The reason this file was stale for weeks: an untracked copy has no reader that can notice it
  # rot. deploy-parity-assert.sh scores ~/bin by content precisely because copies drift; a symlink
  # makes drift structurally impossible, which is why claude-accounts is deployed the same way.
  # HOME is rewritten in setup, so the real deployed path is rebuilt from the login name here
  # deliberately — this is the ONE assertion that must read the live box rather than a fixture.
  local live target
  live="/Users/$(id -un)/.reso/bin/reso-resume-one"
  [ -L "$live" ] || skip "not deployed on this box (install.sh has not run): $live"
  target="$(readlink "$live")"
  # An absolute target ending in bin/reso-resume-one. Absolute matters: install.sh links by
  # absolute src, and a relative one would resolve differently depending on the caller.
  case "$target" in
    /*/bin/reso-resume-one) ;;
    *) echo "deployed symlink points somewhere unexpected: $target" >&2; return 1 ;;
  esac
  # The claim is CONTENT identity with the gated file, not merely that a link exists. A symlink
  # makes that structurally true, which is exactly why it was chosen over the copy that rotted —
  # so assert the property, and let the mechanism be what makes it cheap to hold.
  cmp -s "$live" "$target"
}

# ── THE CAPACITY GATE IN THE ENGINE'S OWN BODY (backlog eda267ff4b14) ────────────────────────────
# §12.1 listed this engine as a capacity BYPASS: every in-repo invocation reaches it through
# scripts/boot-resume-launch.sh, which is gated, but a DIRECT call — the runbook's, an operator's,
# the Agent-tool path — spawned a session against no admission check at all. That was defended by
# "ungateable because untracked" until 5c38ad5a tracked the file here.
# tests/capacity-admit-coverage.bats case 25 pinned the residue and instructed its own rewrite for
# the moment this landed; these are the cases that make the rewrite true.
#
# THE GATE IS DRIVEN DETERMINISTICALLY, never off the verifier's real load — the same
# CC_ADMIT_LOADAVG_OVERRIDE / CC_ADMIT_HEADROOM_OVERRIDE seams tests/capacity-admit.bats uses. A
# case whose verdict depends on how busy the box happens to be is not a test.
# ONE MUTANT PER SITE: shed · admit · absent-library are three distinct behaviours of this block and
# get three cases; a single "the gate exists" grep would credit none of them and would re-create the
# spelling-pinned assertion that tests/reso-keepalive.bats already had to unlearn.

@test "GATE shed — an overloaded box DEFERS the resume with exit 9, before any work is done" {
  # 9 is `shed`, deliberately distinct from 2 (usage), 3 (missing dep) and 4 (launch failed): a
  # failure needs fixing, a shed needs the box to settle, and the operator action differs.
  run env -u CC_ADMIT_DONE CC_ADMIT_GATE=on \
      CC_ADMIT_LOADAVG_OVERRIDE=999 CC_ADMIT_HEADROOM_OVERRIDE=64 \
      CC_ADMIT_STATE_DIR="$BATS_TEST_TMPDIR/admit-shed" \
      CC_RESUME_DRYRUN=1 timeout 60 "$RRO" next "$BATS_TEST_TMPDIR/wts/gate-shed" SID-SHED feat/gate-shed
  [ "$status" -eq 9 ] || { echo "expected shed (9), got $status: $output"; false; }
  echo "$output" | grep -q "DEFERRED, not lost" \
    || { echo "a shed must say the session is deferred rather than lost: $output"; false; }
}

@test "GATE admit — a quiet box resumes, and the admission is ANNOUNCED not silent" {
  # An admitted spawn still says which terms it evaluated. A gate that is silent when it admits is
  # indistinguishable from a gate that is not there, which is the state this row closed.
  run env -u CC_ADMIT_DONE CC_ADMIT_GATE=on \
      CC_ADMIT_LOADAVG_OVERRIDE=0.1 CC_ADMIT_HEADROOM_OVERRIDE=64 \
      CC_ADMIT_STATE_DIR="$BATS_TEST_TMPDIR/admit-ok" \
      CC_RESUME_DRYRUN=1 timeout 60 "$RRO" next "$BATS_TEST_TMPDIR/wts/gate-ok" SID-OK feat/gate-ok
  [ "$status" -ne 9 ] || { echo "a quiet box was shed: $output"; false; }
  echo "$output" | grep -q "reso-resume-one: capacity-admit" \
    || { echo "the admission was not announced: $output"; false; }
}

@test "GATE absent-library is LOUD and NOT fatal — the gate must never cause the outage it prevents" {
  # §12.2's rule, verbatim: inertness must be LOUD rather than a silent admit. And refusing to
  # recover a crashed box because a telemetry library is missing would be strictly worse than the
  # ungated state this replaced — so it announces and proceeds.
  # Forced via the SET-BUT-EMPTY seam, because nothing else can reach this branch from a checkout:
  # the engine's first search path is its own sibling scripts/lib/, which always resolves in-repo.
  run env -u CC_ADMIT_DONE CC_ADMIT_GATE=on CC_RESUME_ADMIT_LIB= \
      CC_ADMIT_LOADAVG_OVERRIDE=999 CC_ADMIT_HEADROOM_OVERRIDE=64 \
      CC_RESUME_DRYRUN=1 timeout 60 "$RRO" next "$BATS_TEST_TMPDIR/wts/gate-nolib" SID-NOLIB feat/gate-nolib
  [ "$status" -ne 9 ] || { echo "an absent library caused a shed — the gate became the outage: $output"; false; }
  echo "$output" | grep -q "capacity-admit: ABSENT" \
    || { echo "inertness must be LOUD, not a silent admit: $output"; false; }
  # CONTROL — the load above is shed-level, so this case would pass vacuously if the seam did not
  # actually disable the library. With the seam removed the SAME invocation must shed, which proves
  # the case is exercising absence rather than a gate that was never going to refuse anyway.
  run env -u CC_ADMIT_DONE CC_ADMIT_GATE=on \
      CC_ADMIT_LOADAVG_OVERRIDE=999 CC_ADMIT_HEADROOM_OVERRIDE=64 \
      CC_ADMIT_STATE_DIR="$BATS_TEST_TMPDIR/admit-nolib-ctl" \
      CC_RESUME_DRYRUN=1 timeout 60 "$RRO" next "$BATS_TEST_TMPDIR/wts/gate-nolib" SID-NOLIB feat/gate-nolib
  [ "$status" -eq 9 ] || { echo "the control did not shed — the absent-library case is vacuous: $output"; false; }
}

@test "GATE is not evaluated TWICE — the launcher's own admission suppresses the engine's" {
  # boot-resume-launch.sh runs this exact gate before invoking the engine, and the consecutive-
  # refusal BUDGET is shared state: a second evaluation per resume spends it twice as fast and
  # releases the bound early on a box that never settled. CC_ADMIT_DONE marks the admission that
  # already happened. It can only ever SUPPRESS a redundant evaluation — nothing but the launcher
  # sets it — so a shed-level load must still resume when it is present.
  run env CC_ADMIT_DONE=1 CC_ADMIT_GATE=on \
      CC_ADMIT_LOADAVG_OVERRIDE=999 CC_ADMIT_HEADROOM_OVERRIDE=64 \
      CC_ADMIT_STATE_DIR="$BATS_TEST_TMPDIR/admit-dup" \
      CC_RESUME_DRYRUN=1 timeout 60 "$RRO" next "$BATS_TEST_TMPDIR/wts/gate-dup" SID-DUP feat/gate-dup
  [ "$status" -ne 9 ] || { echo "the engine re-evaluated a gate the launcher had already passed: $output"; false; }
  echo "$output" | grep -q "reso-resume-one: capacity-admit" \
    && { echo "the engine evaluated the gate a second time: $output"; false; }
  # and the launcher must actually SET it, or the suppression above pins a marker nobody sends
  grep -q 'export CC_ADMIT_DONE=1' "$REPO_ROOT/scripts/boot-resume-launch.sh" \
    || { echo "boot-resume-launch.sh does not mark its admission — the engine will double-evaluate"; false; }
  # CONTROL — WITHOUT THIS THE CASE IS VACUOUS, and measurably so: run against the pre-gate engine
  # it PASSED, while cases 18-20 correctly went red. An engine with NO gate also fails to evaluate
  # one twice, so "suppressed" and "never there" are the same observation from the marker's side.
  # The identical invocation with the marker removed must shed — that is the only thing that tells
  # them apart, and it is what stops this case certifying the very state the gate replaced.
  run env -u CC_ADMIT_DONE CC_ADMIT_GATE=on \
      CC_ADMIT_LOADAVG_OVERRIDE=999 CC_ADMIT_HEADROOM_OVERRIDE=64 \
      CC_ADMIT_STATE_DIR="$BATS_TEST_TMPDIR/admit-dup-ctl" \
      CC_RESUME_DRYRUN=1 timeout 60 "$RRO" next "$BATS_TEST_TMPDIR/wts/gate-dup" SID-DUP feat/gate-dup
  [ "$status" -eq 9 ] \
    || { echo "the control did not shed — there is no gate for the marker to suppress: $output"; false; }
}
