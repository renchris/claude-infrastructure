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
#   · fable arm → `model=claude-fable-5-1 effort=high`      : argv reads `--effort high`.
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
  # The engine grew two seams of its own for source-suppression of the resume dialog. Both are read
  # with ${VAR:-}, so an operator shell that happens to carry either would flip cases here the way a
  # real invocation flips — CC_RESUME_NO_SUPPRESS especially, which would silently turn every
  # suppression case into a fallback case and still look green. They are the SUBJECT of the cases at
  # the end of this file, so they are set explicitly there and absent everywhere else.
  unset CC_RESUME_NO_SUPPRESS CC_RESUME_THRESHOLD_MINUTES
  export CC_RR_STUB_ARGV="$BATS_TEST_TMPDIR/argv"
  export CC_RR_STUB_ENV="$BATS_TEST_TMPDIR/stub-env"
  export CC_RR_STUB_PATH="$BATS_TEST_TMPDIR/stub-path"
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
# The suppression variable arrives as ENVIRONMENT and never as argv — `env NAME=v cmd` consumes the
# assignment before exec — so recording "$*" could not see it at any value. Announcing a pin and
# passing it are separate claims (the header above, on --effort); this records the second one.
printf '%s\n' "${CLAUDE_CODE_RESUME_THRESHOLD_MINUTES-<unset>}" > "$CC_RR_STUB_ENV"
cols=${CC_RR_STUB_COLS:-80}
# SOURCE SUPPRESSION, modelled on D3f in the 2.1.220 bundle: the dialog is not raised at all when
# the session is younger than the threshold, and a session it is not raised for is resumed FULL
# AS-IS — the same outcome the menu path reaches by keystrokes, which is why this writes the same
# `continue` and records HOW it got there. The default is 70 because that is Rue()'s literal
# fallback in the bundle, and a non-numeric value takes it too (Rue reads NaN as the default, not as
# a refusal) — so a broken value here shows the dialog rather than silently suppressing it.
if [ -n "${CC_RR_STUB_HONOR_THRESHOLD:-}" ]; then
  thr=${CLAUDE_CODE_RESUME_THRESHOLD_MINUTES:-70}
  case "$thr" in ''|*[!0-9]*) thr=70 ;; esac
  age=${CC_RR_STUB_AGE_MINUTES:-130}          # the "2h 10m" the header below announces
  if [ "$age" -lt "$thr" ]; then
    printf '%s\n' suppressed > "$CC_RR_STUB_PATH"
    printf '%s\n' continue   > "$CC_RR_STUB_OUT"
    # No dialog, and deliberately no "as-is" in this text: that token is the matcher trigger, and a
    # suppressed session that still fires the matcher would not be a suppressed session.
    printf 'resumed the full session, no dialog raised\n'
    printf 'shift+tab to cycle\n'
    sleep 1
    exit 0
  fi
fi
printf '%s\n' menu > "$CC_RR_STUB_PATH"
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

# The SAME stub with the suppression variable's name removed from its bytes — a binary that cannot
# read it, which is the version-drop this engine has to survive. Substituted rather than deleted so
# every other behaviour is byte-identical: the only thing that changes is whether the token is there
# to be found, which is exactly what the engine probes for.
mk_stub_without_token() {
  mk_stub
  sed 's/CLAUDE_CODE_RESUME_THRESHOLD_MINUTES/CC_RR_ABSENT_TOKEN_______________/g' \
      "$CC_RESUME_CLAUDE_BIN" > "$CC_RESUME_CLAUDE_BIN.notoken"
  mv "$CC_RESUME_CLAUDE_BIN.notoken" "$CC_RESUME_CLAUDE_BIN"
  chmod +x "$CC_RESUME_CLAUDE_BIN"
}

selected() { cat "$CC_RR_STUB_OUT" 2>/dev/null; }
spawn_argv() { cat "$CC_RR_STUB_ARGV" 2>/dev/null; }
stub_env()  { cat "$CC_RR_STUB_ENV" 2>/dev/null; }
stub_path() { cat "$CC_RR_STUB_PATH" 2>/dev/null; }

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
  [[ "$(spawn_argv)" == *"--model claude-fable-5-1 "* ]] || false
  [[ "$(spawn_argv)" == *"--effort max"* ]] || false
  [[ "$(spawn_argv)" != *"--effort high"* ]]
}

@test "omitted, --effort leaves prior behaviour byte-identical (fable ⇒ high)" {
  # The other half of the contract lr-handoff states: the flag must be additive. A fix that changed
  # the default would move every existing caller — boot-resume.sh and the runbook pass no flag.
  run env CC_RR_STUB_COLS=80 timeout 90 "$RRO" fable4 "$WT" SID-DEFAULT
  [ "$status" -eq 0 ]
  [[ "$(spawn_argv)" == *"--model claude-fable-5-1 "* ]] || false
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
  [[ "$(spawn_argv)" == *"--model claude-fable-5-1 "* ]] || false
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
  # `! … || { …; false; }`, never `… && { …; false; }`: under errexit the `&&` form absorbs its own
  # failure, so the assertion can never fail and asserts NOTHING. tests/bats-assert-liveness.bats
  # caught this exact line as dead on the first pass, which is the ratchet working.
  ! echo "$output" | grep -q "reso-resume-one: capacity-admit" \
    || { echo "the engine evaluated the gate a second time: $output"; false; }
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

# ── SOURCE-SUPPRESSION OF THE RESUME DIALOG (backlog 267ebd112350) ───────────────────────────────
# The matcher above wins a keystroke race against Ink's raw-mode mount. The binary will not RAISE
# the dialog at all for a session younger than CLAUDE_CODE_RESUME_THRESHOLD_MINUTES, and a session
# it does not ask about is resumed FULL AS-IS — the matcher's own answer, with no race to enter.
#
# THE ASSERTIONS ARE POSITIVE, never "no menu appeared": absence is also what a hang looks like, and
# a case that passes on absence would go on passing after the spawn stopped happening at all. So
# every claim below is a fact the SPAWNED PROCESS emitted — the value it received in its
# environment, the path it took, and the option that ended up in force.
#
# ONE MUTANT PER SITE: the value reaching the process, the suppressed outcome, the OFF knob, and a
# binary that cannot read the variable are four distinct behaviours and get four cases. Deleting the
# spawn-line variable reds the first three; deleting the probe reds the fourth.

@test "SUPPRESSION reaches the spawned binary as ENVIRONMENT, not merely as an announcement" {
  # `env NAME=v cmd` consumes the assignment, so this can never be seen in argv — and announcing a
  # pin while failing to pass it is the exact defect the --effort cases at the top were written for.
  run env CC_RR_STUB_COLS=80 timeout 90 "$RRO" next2 "$WT" SID-THRESH-ENV
  [ "$status" -eq 0 ]
  local v; v="$(stub_env)"
  case "$v" in
    ''|*[!0-9]*) echo "no numeric threshold reached the spawned process: '$v'" >&2; false ;;
  esac
  # The PROPERTY, not the digits: a ceiling has to outlast any session worth recovering, and pinning
  # the literal here would tripwire its own constant instead of guarding the mechanism.
  [ "$v" -gt 1440 ] \
    || { echo "the threshold ($v) does not clear a day — a session older than it still gets the dialog"; false; }
  [[ "$output" == *"suppression: PRIMARY"* ]] || false
  # and the value is a seam, not a literal — the override has to reach the same place
  run env CC_RESUME_THRESHOLD_MINUTES=4321 CC_RR_STUB_COLS=80 timeout 90 "$RRO" next2 "$WT" SID-THRESH-OVR
  [ "$status" -eq 0 ]
  [ "$(stub_env)" = "4321" ] \
    || { echo "the override did not reach the process: $(stub_env)"; false; }
}

@test "SUPPRESSION positive — the session comes up full, with no dialog ever raised" {
  # THE claim, asserted on what the spawned process reports rather than on what it did not print.
  # The stub models D3f: under the threshold there is no dialog and the full session is resumed, so
  # `continue` is in force having been reached WITHOUT the menu, and it says which path that was.
  run env CC_RR_STUB_HONOR_THRESHOLD=1 CC_RR_STUB_COLS=80 timeout 90 "$RRO" next2 "$WT" SID-SUPPRESSED
  [ "$status" -eq 0 ]
  [ "$(stub_path)" = "suppressed" ] \
    || { echo "the dialog was raised and answered by keystrokes, not suppressed: $(stub_path)"; false; }
  [ "$(selected)" = "continue" ] \
    || { echo "suppressed, but the session did not come up as the full session: $(selected)"; false; }
}

@test "FALLBACK is reachable — CC_RESUME_NO_SUPPRESS withholds the variable and the matcher answers" {
  # The matcher is not decoration: it is what survives the binary dropping the variable, so it must
  # be exercised on purpose rather than left to be exercised by an outage. With the knob set the
  # variable must be ABSENT — not empty — because an empty value is read as NaN and falls back to
  # the default 70, which would raise the dialog and make "off" indistinguishable from "on".
  run env CC_RESUME_NO_SUPPRESS=1 CC_RR_STUB_HONOR_THRESHOLD=1 CC_RR_STUB_COLS=80 \
      timeout 90 "$RRO" next2 "$WT" SID-NOSUP
  [ "$status" -eq 0 ]
  [ "$(stub_env)" = "<unset>" ] \
    || { echo "the knob is off but the variable still reached the process: $(stub_env)"; false; }
  [ "$(stub_path)" = "menu" ] \
    || { echo "the dialog was not raised, so the matcher was never exercised: $(stub_path)"; false; }
  [ "$(selected)" = "continue" ] \
    || { echo "the fallback matcher failed to take the full session: $(selected)"; false; }
  [[ "$output" == *"suppression: OFF (CC_RESUME_NO_SUPPRESS)"* ]] || false
  # CONTROL — WITHOUT THIS THE CASE IS VACUOUS. An engine that never suppresses anything also passes
  # every line above, so "forced off" and "never on" are the same observation from the knob's side.
  # The identical invocation with the knob removed must take the suppressed path instead.
  run env CC_RR_STUB_HONOR_THRESHOLD=1 CC_RR_STUB_COLS=80 timeout 90 "$RRO" next2 "$WT" SID-NOSUP-CTL
  [ "$(stub_path)" = "suppressed" ] \
    || { echo "the control did not suppress — there is nothing for the knob to turn off: $(stub_path)"; false; }
}

@test "VERSION DROP is LOUD — a binary without the token announces UNSUPPORTED and is still resumed" {
  # The variable is reached through a minified internal symbol behind an unnamed flag, so a bump can
  # stop reading it with no other visible consequence than the dialog coming back. The engine probes
  # the resolved binary's own bytes for the token and says so. Not a refusal: refusing to recover a
  # crashed session because a suppression hint went away would be the fix causing the outage.
  mk_stub_without_token
  run env CC_RR_STUB_HONOR_THRESHOLD=1 CC_RR_STUB_COLS=80 timeout 90 "$RRO" next2 "$WT" SID-UNSUP
  [ "$status" -eq 0 ]
  [[ "$output" == *"suppression: UNSUPPORTED"* ]] || false
  [ "$(stub_path)" = "menu" ] \
    || { echo "a binary that cannot read the token still skipped the dialog: $(stub_path)"; false; }
  [ "$(selected)" = "continue" ] \
    || { echo "the matcher did not carry a binary the suppression could not reach: $(selected)"; false; }
  # CONTROL — the same stub WITH the token must announce and behave the other way, or this case is
  # pinning a stub that was never going to suppress anything whatever the engine did.
  mk_stub
  run env CC_RR_STUB_HONOR_THRESHOLD=1 CC_RR_STUB_COLS=80 timeout 90 "$RRO" next2 "$WT" SID-UNSUP-CTL
  [[ "$output" == *"suppression: PRIMARY"* ]] || false
  [ "$(stub_path)" = "suppressed" ] \
    || { echo "the control did not suppress — the token is not what the two cases differ on: $(stub_path)"; false; }
}
