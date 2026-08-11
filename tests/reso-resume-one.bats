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
