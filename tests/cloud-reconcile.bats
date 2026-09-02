#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2329
#   Structurally false under bats, not suppressed noise: every @test body IS its own subshell, so an
#   `export` inside one is *meant* to be test-local (SC2030/SC2031), and setup()'s helpers are
#   invoked from those test subshells rather than from file scope (SC2329).
#
# cloud-reconcile.sh — gate G6, the CLOUD LANDING PATH.
#
# THE GAP THIS SUBJECT CLOSES. A cloud Claude Code VM can push only its own `claude/*` working
# branch. It has no ~/.claude, no `gh`, and cannot run this repo's project-local /ship. Nothing
# LOCAL ever looks for that branch:
#   * scripts/stranded-sweep.sh:66 enumerates `refs/heads/` — LOCAL heads only. A remote-only
#     `claude/*` branch is structurally invisible to it (same for branch-reaper.sh and
#     worktree-gc.sh:374-387).
#   * scripts/ship-land.sh:1987's SHIP_LAND_SESSION_BRANCH_RE defaults to
#     `^(feat|fix|chore|docs|refactor|test|perf|style|build|ci)/.+` — `claude/*` does not match, so
#     a land attempt refuses.
# So every cloud result strands on a remote branch. This subject is the reconciler: DISCOVERY +
# ELIGIBILITY + SERIALIZATION. It lands nothing itself — it shells out to scripts/desk-land.sh,
# which owns the landing lock, the gate, the content-verify and the stranded sweep.
#
# REAL ARTIFACT, NOT AN APPROXIMATION. Every "remote" below is a REAL local bare repository and
# every branch is pushed by a REAL `git push`. The claim under test is what `git ls-remote --heads`
# actually returns, and a hand-edited approximation of that would pass vacuously
# (memory: control-must-replay-the-real-artifact).
#
# THE ONE STUB IS THE LANDER, VIA AN EXPLICIT ENV SEAM (CLOUD_RECONCILE_LAND_BIN). desk-land →
# ship-land pushes to a real trunk and runs the full gate; that is precisely the thing this suite
# must NOT invoke. The stub records its argv AND the SHIP_LAND_SESSION_BRANCH_RE it was handed, so
# the override this subject must pass is asserted rather than assumed.
#
# POSITIVE CONTROLS: every absence assertion below ("not listed", "never landed", "zero rows") is
# paired IN THE SAME TEST with a case that DOES fire off the same fixture. A grep that can find
# nothing is not evidence (memory: positive-control-the-denominator).
#
# RED-PROOF: every test fails against the pristine pre-change tree, where the subject does not
# exist:
#   t=$(mktemp -d); git archive HEAD | tar -x -C "$t"
#   CLOUD_RECONCILE_SUBJECT_ROOT="$t" bats tests/cloud-reconcile.bats   # all fail: subject missing
#
# DEAD-ASSERTION DISCIPLINE: bats runs each body under `set -eET`, and bash exempts `[[ ]]`, `(( ))`
# and `! cmd` from errexit — a non-final occurrence of those is a DEAD assertion that always passes
# (scripts/bats-assert-liveness.py). This suite uses POSIX `[ ]` and appends `|| false` after every
# non-final negation.
#
# NO WALL-CLOCK, NO NETWORK, NO LIVE $HOME.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  ROOT="${CLOUD_RECONCILE_SUBJECT_ROOT:-$REPO_ROOT}"
  CR="$ROOT/scripts/cloud-reconcile.sh"

  D="$BATS_TEST_TMPDIR"

  # Fixture $HOME: the declaration store defaults to ~/.claude/autonomy/cloud (shared with
  # bin/cc-cloud), so an unfixtured HOME would read — and this suite's fixtures would litter — the
  # operator's live autonomy dir. scripts/test-hermeticity-lint.sh runs in the land gate.
  export HOME="$D/home"; mkdir -p "$HOME"
  export GIT_CONFIG_NOSYSTEM=1
  export CC_CLOUD_STATE="$D/state"; mkdir -p "$CC_CLOUD_STATE"

  ORIGIN="$D/origin.git"
  REPO="$D/repo"
  git init -q --bare "$ORIGIN"
  git clone -q "$ORIGIN" "$REPO"
  (
    cd "$REPO" || exit 1
    git config user.email t@e.com; git config user.name tester
    git checkout -q -b main
    echo base > base.txt
    mkdir -p already
    echo landed > already/landed.txt
    git add -A; git commit -q -m base
    git push -q -u origin main
  )

  # The lander stub. Records argv and the branch-name regex it was handed; fails for any branch
  # named in LAND_STUB_FAIL so the "one failure does not abort the rest" arm is drivable.
  export LAND_STUB_LOG="$D/land.log"; : > "$LAND_STUB_LOG"
  LAND_STUB="$D/desk-land-stub.sh"
  cat > "$LAND_STUB" <<'STUB'
#!/usr/bin/env bash
{ echo "ARGS=$*"; echo "RE=${SHIP_LAND_SESSION_BRANCH_RE:-<unset>}"; } >> "${LAND_STUB_LOG:?}"
b=""
while [ $# -gt 0 ]; do
  case "$1" in --branch) b="${2:-}"; shift 2 ;; --branch=*) b="${1#--branch=}"; shift ;; *) shift ;; esac
done
case " ${LAND_STUB_FAIL:-} " in *" $b "*) exit 6 ;; esac
# 🚨 THE STUB ADVANCES origin/main, because the REAL lander does. Without this it left the world in
# a pre-land state, and every arm downstream graded a branch that was still ahead of trunk — which
# is how a post-hoc `fill-paths` shipped green and then refused on the first live round trip, where
# the landed branch was already an ancestor of trunk and the range was empty (memory:
# control-must-replay-the-real-artifact). Content-identical, sha-different: the reconciler
# re-authors, so a fast-forward here would also prove landedness by ancestry rather than by content.
if [ "${LAND_STUB_NO_ADVANCE:-0}" != 1 ] && [ -n "${LAND_STUB_REPO:-}" ]; then
  tree="$(git -C "$LAND_STUB_REPO" rev-parse "refs/heads/$b^{tree}" 2>/dev/null)" || tree=""
  if [ -n "$tree" ]; then
    new="$(git -C "$LAND_STUB_REPO" commit-tree "$tree" -p origin/main -m "landed by a re-author" 2>/dev/null)"
    [ -n "$new" ] && git -C "$LAND_STUB_REPO" push -q origin "$new:refs/heads/main" 2>/dev/null
    git -C "$LAND_STUB_REPO" fetch -q origin 2>/dev/null
  fi
fi
exit 0
STUB
  chmod +x "$LAND_STUB"
  export CLOUD_RECONCILE_LAND_BIN="$LAND_STUB"
  export LAND_STUB_REPO="$REPO"
  export CLOUD_RECONCILE_REPO="$REPO"

  have_subject() {   # RED-proof legibility: name the absence instead of dying on 127
    [ -x "$CR" ] || { echo "cloud-reconcile.sh is missing or not executable at $CR"; return 1; }
  }
  cr() { have_subject && bash "$CR" "$@"; }

  # Push a branch carrying $2 files, built on main. Real git, real push.
  push_branch() {  # $1=branch  $2=file-count
    local b="$1" n="${2:-1}" i w
    w="$D/w-$(printf '%s' "$b" | tr / -)"
    git -C "$REPO" worktree add -q -b "$b" "$w" main
    i=1
    while [ "$i" -le "$n" ]; do
      printf 'c%s\n' "$i" > "$w/f$i.txt"
      i=$((i + 1))
    done
    git -C "$w" add -A
    git -C "$w" -c user.email=t@e.com -c user.name=tester commit -q -m "work $b"
    git -C "$w" push -q origin "HEAD:refs/heads/$b"
    # Remove the LOCAL trace entirely — a cloud branch exists ONLY on the remote, and a local head
    # left behind would make the discovery arm pass for the wrong reason.
    git -C "$REPO" worktree remove --force "$w"
    git -C "$REPO" branch -q -D "$b"
    rm -rf "$w"
    true
  }

  # A BOOT PING — the absence contract (CLOUD_OBSERVABILITY.md §4.1/§16) made real. The VM pushes
  # its declared branch as its first act, at the commit it was placed on, and commits nothing.
  # No local head is left, exactly as push_branch does, because a cloud branch exists only on the
  # remote. Deliberately NOT an empty commit: the shipped rail prescribes a bare ref creation, and
  # the fixture has to replay the artifact the rail actually produces.
  # shellcheck disable=SC2317
  #   Same structural falsehood as the file-header's SC2329: this helper is defined in setup() and
  #   invoked from the @test subshells, which shellcheck cannot see, so its body reads unreachable.
  #   Narrow rather than added to the header's list, so a genuinely dead line elsewhere still blocks.
  push_boot_ping() {  # $1=branch
    git -C "$REPO" push -q origin "refs/heads/main:refs/heads/$1"
    true
  }

  decl() {  # $1=id  $2=branch  [$3=paths]
    { printf 'id=%s\n' "$1"
      printf 'branch=%s\n' "$2"
      printf 'remote=origin\n'
      printf 'repo=%s\n' "$REPO"
      printf 'trunk=origin/main\n'
      printf 'paths=%s\n' "${3:-}"
      printf 'declared_at=2000000000\n'
    } > "$CC_CLOUD_STATE/$1.decl"
  }

  retire() { : > "$CC_CLOUD_STATE/$1.retired"; }

  landed_branches() {  # branches the stub was asked to land, in call order
    /usr/bin/grep '^ARGS=' "$LAND_STUB_LOG" 2>/dev/null \
      | sed -n 's/.*--branch \([^ ]*\).*/\1/p'
  }

  # ── identity-wall fixtures ─────────────────────────────────────────────────────────────────
  # A cloud VM authors as `noreply@anthropic.com`, which resolves to no GitHub account. The
  # fixture repo's own identity is t@e.com (setup above), so "the operator" here IS t@e.com and
  # "the VM" is anything else — the suite pins the RELATION the subject checks, never the
  # operator's real address, which lives only in githooks/*.
  VM_EMAIL="noreply@anthropic.com"

  push_branch_as() {  # $1=branch  $2=file-count  $3=author email  [$4=committer email]
    local b="$1" n="${2:-1}" em="${3:-t@e.com}" cm="${4:-}" i w
    [ -n "$cm" ] || cm="$em"
    w="$D/w-$(printf '%s' "$b" | tr / -)"
    git -C "$REPO" worktree add -q -b "$b" "$w" main
    i=1
    while [ "$i" -le "$n" ]; do
      printf 'c%s\n' "$i" > "$w/f$i.txt"
      i=$((i + 1))
    done
    git -C "$w" add -A
    GIT_COMMITTER_EMAIL="$cm" GIT_COMMITTER_NAME=cloud \
      git -C "$w" -c user.email="$em" -c user.name=cloud commit -q -m "work $b"
    git -C "$w" push -q origin "HEAD:refs/heads/$b"
    # As push_branch: a cloud branch exists ONLY on the remote.
    git -C "$REPO" worktree remove --force "$w"
    git -C "$REPO" branch -q -D "$b"
    rm -rf "$w"
    true
  }

  push_branch_msg() {  # $1=branch  $2=author/committer email  $3=commit message (verbatim)
    local b="$1" em="$2" m="$3" w
    w="$D/w-$(printf '%s' "$b" | tr / -)"
    git -C "$REPO" worktree add -q -b "$b" "$w" main
    printf 'x\n' > "$w/f1.txt"
    git -C "$w" add -A
    printf '%s\n' "$m" > "$D/cm.txt"
    GIT_COMMITTER_EMAIL="$em" GIT_COMMITTER_NAME=cloud \
      git -C "$w" -c user.email="$em" -c user.name=cloud commit -q --no-verify -F "$D/cm.txt"
    git -C "$w" push -q origin "HEAD:refs/heads/$b"
    git -C "$REPO" worktree remove --force "$w"
    git -C "$REPO" branch -q -D "$b"
    rm -rf "$w"
    true
  }

  # The REAL githooks/commit-msg, installed where git would look for it. The strip arm exists to
  # clear THAT predicate, so a fixture stand-in would prove the mechanism and not the outcome.
  install_real_msg_hook() {
    local h
    h="$(git -C "$REPO" rev-parse --git-path hooks)"
    case "$h" in /*) ;; *) h="$REPO/$h" ;; esac
    mkdir -p "$h"
    cp "$ROOT/githooks/commit-msg" "$h/commit-msg"
    chmod +x "$h/commit-msg"
  }

  remote_sha() { git -C "$REPO" ls-remote origin "refs/heads/$1" 2>/dev/null | awk '{print $1}'; }
  local_sha()  { git -C "$REPO" rev-parse --verify --quiet "refs/heads/$1" 2>/dev/null; }

  # Mint a DIVERGENT local head with no worktree and no checkout — the residue an earlier failed
  # land leaves behind. commit-tree because the shared checkout must never be checked out.
  stale_local_head() {  # $1=branch
    local t c
    t="$(git -C "$REPO" log -1 --format=%T main)"
    c="$(git -C "$REPO" -c user.email=t@e.com -c user.name=tester commit-tree "$t" -p main -m "residue of a failed land")"
    git -C "$REPO" update-ref "refs/heads/$1" "$c"
  }

  install_msg_hook() {  # $1=the grep -E pattern the fixture hook refuses
    local h
    h="$(git -C "$REPO" rev-parse --git-path hooks)"
    case "$h" in /*) ;; *) h="$REPO/$h" ;; esac
    mkdir -p "$h"
    { echo '#!/usr/bin/env bash'
      printf 'if grep -qE %s "$1"; then echo "fixture commit-msg: BLOCKED" >&2; exit 1; fi\n' "'$1'"
      echo 'exit 0'
    } > "$h/commit-msg"
    chmod +x "$h/commit-msg"
  }
}

# ── DEFECT 1 · the identity wall ─────────────────────────────────────────────────────────────
@test "a VM-authored range is re-authored before the land, and the trailers carry the REAL shas" {
  push_branch_as claude/vm 1 "$VM_EMAIL"
  decl cloud-vm claude/vm
  orig="$(remote_sha claude/vm)"
  [ -n "$orig" ]

  CONFIRM=1 run cr --land claude/vm
  [ "$status" -eq 0 ]
  landed_branches | /usr/bin/grep -q '^claude/vm$'

  # Both identity fields, on every commit in the range: a replay that fixed only the author would
  # read clean here and still be refused by githooks/pre-push (its §BOTH FIELDS).
  bad="$(git -C "$REPO" log --format='%ae|%ce' main..refs/heads/claude/vm | /usr/bin/grep -cv '^t@e.com|t@e.com$' || true)"
  [ "$bad" = 0 ]

  # The rewrite happened at all — POSITIVE CONTROL for the count above, which reads 0 over an
  # empty range just as happily as over a clean one.
  n="$(git -C "$REPO" rev-list --count main..refs/heads/claude/vm)"
  [ "$n" = 1 ]
  [ "$(local_sha claude/vm)" != "$orig" ]

  # Provenance, and it must name the PRE-rewrite sha rather than anything derivable after the fact.
  msg="$(git -C "$REPO" log -1 --format=%B refs/heads/claude/vm)"
  printf '%s\n' "$msg" | /usr/bin/grep -qx "Original-commit: $orig"
  printf '%s\n' "$msg" | /usr/bin/grep -qx "Original-branch: claude/vm"
  printf '%s\n' "$msg" | /usr/bin/grep -qx "Cloud-session: cloud-vm"
  # …and NOT the spelling githooks/commit-msg blocks.
  printf '%s\n' "$msg" | /usr/bin/grep -qi 'co-authored-by' && false

  # HONEST, NOT LAUNDERED: the content is byte-identical and the VM's original is still on the
  # remote, so nothing about who did the work has been destroyed.
  [ "$(git -C "$REPO" log -1 --format=%T refs/heads/claude/vm)" = "$(git -C "$REPO" log -1 --format=%T "$orig")" ]
  [ "$(remote_sha claude/vm)" = "$orig" ]
}

@test "a REAPED TMPDIR does not refuse the land — the re-author falls back rather than blaming the branch" {
  # Measured 2026-08-17 on five live refusal artifacts, every one of this exact shape:
  #   mktemp: mkstemp failed on …/T/postland-run.VRdnYH/cloud-reauthor.XXXXXX: No such file…
  # postland-verify hands the corpus a private TMPDIR and REAPS it when the run ends, so anything
  # holding that value is left pointing at a deleted path. `${TMPDIR:-/tmp}` is blind to it — the
  # variable is SET, so the fallback never fires — and the only thing the caller hears is rc 70,
  # "could not be re-authored", a verdict about a branch whose content was never wrong.
  push_branch_as claude/vm 1 "$VM_EMAIL"
  decl cloud-vm claude/vm
  orig="$(remote_sha claude/vm)"

  reaped="$BATS_TEST_TMPDIR/reaped-tmpdir"
  mkdir -p "$reaped" && rmdir "$reaped"        # the exact live condition: set, non-empty, GONE
  [ ! -d "$reaped" ] || false

  CONFIRM=1 TMPDIR="$reaped" run cr --land claude/vm
  [ "$status" -eq 0 ]
  landed_branches | /usr/bin/grep -q '^claude/vm$'
  # and the re-author actually RAN — a land that skipped it would pass the status check vacuously
  [ "$(local_sha claude/vm)" != "$orig" ]
  bad="$(git -C "$REPO" log --format='%ae|%ce' main..refs/heads/claude/vm | /usr/bin/grep -cv '^t@e.com|t@e.com$' || true)"
  [ "$bad" = 0 ]

  # POSITIVE CONTROL for the guard's narrowness: a TMPDIR that IS a writable directory is still
  # honoured, so this is a presence test and not a blanket override of the caller's choice.
  good="$BATS_TEST_TMPDIR/good-tmpdir"; mkdir -p "$good"
  push_branch_as claude/vm2 1 "$VM_EMAIL"
  decl cloud-vm2 claude/vm2
  CONFIRM=1 TMPDIR="$good" run cr --land claude/vm2
  [ "$status" -eq 0 ]
  landed_branches | /usr/bin/grep -q '^claude/vm2$'
}

@test "a range ALREADY authored by the operator is not rewritten — no gratuitous history churn" {
  push_branch claude/mine 1
  push_branch_as claude/theirs 1 "$VM_EMAIL"
  decl cloud-m claude/mine
  decl cloud-t claude/theirs
  mine_orig="$(remote_sha claude/mine)"
  theirs_orig="$(remote_sha claude/theirs)"

  CONFIRM=1 run cr --all
  [ "$status" -eq 0 ]

  # Untouched: same sha, and no trailer bolted onto a message that never needed one.
  [ "$(local_sha claude/mine)" = "$mine_orig" ]
  git -C "$REPO" log -1 --format=%B refs/heads/claude/mine | /usr/bin/grep -qi 'Original-commit' && false

  # POSITIVE CONTROL, same run, same fixture: the VM-authored sibling IS rewritten, so "not
  # rewritten" cannot pass because the rewrite is broken for everything.
  [ "$(local_sha claude/theirs)" != "$theirs_orig" ]
  git -C "$REPO" log -1 --format=%B refs/heads/claude/theirs | /usr/bin/grep -qx "Original-commit: $theirs_orig"
}

@test "an author-clean but COMMITTER-dirty range is still re-authored — an author-only scan misses it" {
  # githooks/pre-push §BOTH FIELDS: a rebase rewrites the committer and keeps the author, and 2 of
  # the 95 unattributable commits it measured are exactly this shape. ship-land rebases on every
  # land, so this is the shape a cloud branch acquires on the way through, not a contrived one.
  push_branch_as claude/committer 1 t@e.com "$VM_EMAIL"
  decl cloud-c claude/committer
  orig="$(remote_sha claude/committer)"
  [ "$(git -C "$REPO" log -1 --format=%ae "$orig")" = "t@e.com" ]
  [ "$(git -C "$REPO" log -1 --format=%ce "$orig")" = "$VM_EMAIL" ]

  CONFIRM=1 run cr --land claude/committer
  [ "$status" -eq 0 ]
  [ "$(local_sha claude/committer)" != "$orig" ]
  [ "$(git -C "$REPO" log -1 --format=%ce refs/heads/claude/committer)" = "t@e.com" ]
}

@test "githooks/commit-msg REJECTS the Co-authored-by spelling and ACCEPTS the trailers the rewrite writes" {
  # THE GUARD ON THE GUARD. The trailer names above are chosen to clear this hook, and that
  # constraint is invisible in the strings themselves — so it is pinned here. A rewrite that
  # reached for `Co-authored-by:` would fail EVERY commit in the range.
  hook="$ROOT/githooks/commit-msg"
  [ -x "$hook" ]
  m="$D/msg.txt"

  printf 'work claude/x\n\nCloud-session: cloud-1\nOriginal-commit: 0123456789abcdef\nOriginal-branch: claude/x\n' > "$m"
  run bash "$hook" "$m"
  [ "$status" -eq 0 ]

  # POSITIVE CONTROL for that pass: the banned spelling off the same hook, same fixture.
  printf 'work claude/x\n\nCo-authored-by: Claude <noreply@anthropic.com>\n' > "$m"
  run bash "$hook" "$m"
  [ "$status" -ne 0 ]
  echo "$output" | /usr/bin/grep -q 'AI-authorship trailer'
}

@test "the rewrite is put through the repo's OWN commit-msg hook — a refusal writes NOTHING and lands nothing" {
  push_branch_as claude/hooked 1 "$VM_EMAIL"
  decl cloud-h claude/hooked
  orig="$(remote_sha claude/hooked)"

  # Stand in for githooks/commit-msg by refusing a trailer this rewrite actually emits: the arm
  # under test is "the hook is consulted", not which words it happens to ban today.
  install_msg_hook 'Original-branch:'

  CONFIRM=1 run cr --land claude/hooked
  [ "$status" -eq 70 ]
  echo "$output" | /usr/bin/grep -q 'commit-msg'
  [ ! -s "$LAND_STUB_LOG" ]
  # Nothing half-written: the local head is still the VM's own commit.
  [ "$(local_sha claude/hooked)" = "$orig" ]

  # POSITIVE CONTROL: with the hook out of the way the identical branch re-authors and lands.
  h="$(git -C "$REPO" rev-parse --git-path hooks)"; case "$h" in /*) ;; *) h="$REPO/$h" ;; esac
  rm -f "$h/commit-msg"
  CONFIRM=1 run cr --land claude/hooked
  [ "$status" -eq 0 ]
  landed_branches | /usr/bin/grep -q '^claude/hooked$'
  [ "$(local_sha claude/hooked)" != "$orig" ]
}

@test "the VM's OWN attribution block is what the hook blocks — it is dropped and the land proceeds" {
  # Measured on the live artifact (session_01QEiWYuB1ygLLcVwCQJoUZE, commit bd67e747): the text
  # githooks/commit-msg refuses is INHERITED, not added — a cloud VM writes its own
  # `Co-Authored-By: Claude …` + `Claude-Session: https://claude.ai/code/…` block. The first cut of
  # this rewrite blamed its own trailers for that refusal, which is the same wrong-cause defect the
  # whole change exists to remove.
  install_real_msg_hook
  push_branch_msg claude/vmtrailers "$VM_EMAIL" \
"docs(research): a thing the VM wrote

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01ABCDEF"
  decl cloud-vt claude/vmtrailers
  orig="$(remote_sha claude/vmtrailers)"

  CONFIRM=1 run cr --land claude/vmtrailers
  [ "$status" -eq 0 ]
  landed_branches | /usr/bin/grep -q '^claude/vmtrailers$'
  echo "$output" | /usr/bin/grep -q 'attribution trailer block was dropped'

  msg="$(git -C "$REPO" log -1 --format=%B refs/heads/claude/vmtrailers)"
  # The subject — what the commit SAYS — is untouched. Only the attribution block went.
  printf '%s\n' "$msg" | /usr/bin/grep -qx 'docs(research): a thing the VM wrote'
  printf '%s\n' "$msg" | /usr/bin/grep -qi 'co-authored-by' && false
  printf '%s\n' "$msg" | /usr/bin/grep -qi 'claude-session' && false
  printf '%s\n' "$msg" | /usr/bin/grep -q 'claude.ai/code' && false
  # …and the same session id survives, re-expressed in the spelling the hook allows.
  printf '%s\n' "$msg" | /usr/bin/grep -qx 'Cloud-session: cloud-vt'
  printf '%s\n' "$msg" | /usr/bin/grep -qx "Original-commit: $orig"

  # POSITIVE CONTROL: the real hook genuinely refuses the ORIGINAL message off this same fixture,
  # so "dropped" cannot pass because the hook was inert here.
  h="$(git -C "$REPO" rev-parse --git-path hooks)"; case "$h" in /*) ;; *) h="$REPO/$h" ;; esac
  git -C "$REPO" log -1 --format=%B "$orig" > "$D/orig.txt"
  run bash "$h/commit-msg" "$D/orig.txt"
  [ "$status" -ne 0 ]
}

@test "blocked text in the SUBJECT is refused, not silently edited — a rewrite re-attributes, it does not censor" {
  install_real_msg_hook
  push_branch_msg claude/badsubject "$VM_EMAIL" "docs: see https://claude.ai/code/session_01ZZ for the write-up"
  decl cloud-bs claude/badsubject
  orig="$(remote_sha claude/badsubject)"

  CONFIRM=1 run cr --land claude/badsubject
  [ "$status" -eq 70 ]
  echo "$output" | /usr/bin/grep -q 'SUBJECT or BODY'
  [ ! -s "$LAND_STUB_LOG" ]
  [ "$(local_sha claude/badsubject)" = "$orig" ]

  # POSITIVE CONTROL: the identical fixture with the blocked text in a TRAILER instead is stripped
  # and lands. The discriminator under test is WHERE the text is, not that the hook fired.
  push_branch_msg claude/badtrailer "$VM_EMAIL" \
"docs: a clean subject

Claude-Session: https://claude.ai/code/session_01ZZ"
  decl cloud-bt claude/badtrailer
  CONFIRM=1 run cr --land claude/badtrailer
  [ "$status" -eq 0 ]
  landed_branches | /usr/bin/grep -q '^claude/badtrailer$'
}

# ── DEFECT 2 · a failed land poisons its own retry ───────────────────────────────────────────
@test "a stale same-name local branch checked out NOWHERE is healed, and the land proceeds" {
  push_branch_as claude/retry 1 "$VM_EMAIL"
  decl cloud-r claude/retry
  orig="$(remote_sha claude/retry)"
  stale_local_head claude/retry
  [ "$(local_sha claude/retry)" != "$orig" ]
  # The residue really is the blocker: an unforced fetch of the remote head refuses it.
  git -C "$REPO" fetch -q origin "refs/heads/claude/retry:refs/heads/claude/retry" && false

  CONFIRM=1 run cr --land claude/retry
  [ "$status" -eq 0 ]
  echo "$output" | /usr/bin/grep -q 'healed'
  landed_branches | /usr/bin/grep -q '^claude/retry$'
  # Healed TO THE REMOTE, then re-authored off it — the residue's tree is gone.
  [ "$(git -C "$REPO" log -1 --format=%T refs/heads/claude/retry)" = "$(git -C "$REPO" log -1 --format=%T "$orig")" ]
}

@test "a stale local branch that IS checked out in a worktree still refuses — with a DIFFERENT message" {
  push_branch_as claude/owned 1 "$VM_EMAIL"
  decl cloud-o claude/owned
  stale_local_head claude/owned
  git -C "$REPO" worktree add -q "$D/wt-owned" claude/owned

  CONFIRM=1 run cr --land claude/owned
  [ "$status" -eq 65 ]
  [ ! -s "$LAND_STUB_LOG" ]
  # The two cases shared ONE string, which is why a first failure was diagnosed as a second,
  # different one. This arm is that they are now distinguishable in both directions.
  echo "$output" | /usr/bin/grep -q 'CHECKED OUT'
  echo "$output" | /usr/bin/grep -q "$D/wt-owned"
  echo "$output" | /usr/bin/grep -q 'healed' && false

  # POSITIVE CONTROL: remove the worktree and the SAME branch off the SAME fixture heals instead.
  git -C "$REPO" worktree remove --force "$D/wt-owned"
  CONFIRM=1 run cr --land claude/owned
  [ "$status" -eq 0 ]
  echo "$output" | /usr/bin/grep -q 'healed'
  echo "$output" | /usr/bin/grep -q 'CHECKED OUT' && false
  true
}

# ── THE BOUND-KILLED LAND POISONS ITS OWN BRANCH (2026-08-23) ────────────────────────────────────
# The test above proves a worktree someone OWNS still refuses. This block is the other half: the
# commonest holder of a cloud branch is not an owner at all, it is desk-land's own `.desk-land-…`
# sandbox left behind when `timeout -k 10 900` SIGKILLed the return pass (SIGKILL runs no EXIT
# trap). Measured on the live box before the fix: 9 abandoned sandboxes, every creator PID dead,
# 34 rc-65 `land-refused` rows over 4 branches since 08-18, and 0 successful lands since
# 2026-08-17T09:12Z. The refusal told a human to "remove that worktree, then re-run"; no human came.

# A PID that is certainly dead AT THE MOMENT OF USE. Reaping a completed child's number is not
# enough: under bats the box churns through PIDs fast and the number gets REUSED, at which point
# the subject correctly reads it as alive and declines to reap — a green fix looking like a red one.
# (That is the fix's safe direction doing its job, so the fixture must be the thing that is precise.)
# Scan upward from a high number until kill -0 fails, and let the caller assert it.
dead_pid() {
  local p=60000
  while kill -0 "$p" 2>/dev/null; do p=$((p + 1)); done
  printf '%s' "$p"
}

@test "an ABANDONED desk-land sandbox (creator gone) is reaped and the land proceeds" {
  push_branch_as claude/abandoned 1 "$VM_EMAIL"
  decl cloud-ab claude/abandoned
  orig="$(remote_sha claude/abandoned)"
  stale_local_head claude/abandoned
  dp="$(dead_pid)"
  { kill -0 "$dp" 2>/dev/null && false; } || true   # premise asserted, not assumed
  [ -z "$(ps -o pid= -p "$dp" 2>/dev/null | tr -d ' ')" ]
  sb="$D/.desk-land-claude-abandoned-$dp"
  git -C "$REPO" worktree add -q "$sb" claude/abandoned

  # PRECONDITION — the fixture really reaches the bug: git itself refuses to move the ref while the
  # sandbox holds it. Without this the arm could pass on a branch nothing was blocking.
  run git -C "$REPO" branch -f claude/abandoned main
  [ "$status" -ne 0 ]
  echo "$output" | /usr/bin/grep -q 'used by worktree'

  CONFIRM=1 run cr --land claude/abandoned
  [ "$status" -eq 0 ]
  echo "$output" | /usr/bin/grep -q 'ABANDONED desk-land sandbox'
  echo "$output" | /usr/bin/grep -q 'healed'
  landed_branches | /usr/bin/grep -q '^claude/abandoned$'
  [ ! -e "$sb" ]
  # healed TO THE REMOTE — the residue's tree is gone, not landed
  [ "$(git -C "$REPO" log -1 --format=%T refs/heads/claude/abandoned)" = "$(git -C "$REPO" log -1 --format=%T "$orig")" ]
}

@test "CONTROL: the pre-fix cloud-reconcile (pinned e6e5a4355) refuses 65 on that same fixture" {
  # Replayed from a LITERAL sha, never origin/main — origin/main advances past this fix the moment
  # it lands, and the control would then compare the fix to itself (that error cost a land rc 6
  # from moving-ref-control-lint on 2026-08-22). origin/main moved e6e5a4355 → beba9eab5 during the
  # session that wrote this, which is exactly the hazard.
  pre="$D/cloud-reconcile-prefix.sh"
  git -C "$REPO_ROOT" show e6e5a4355:scripts/cloud-reconcile.sh > "$pre"
  # the control must BE the pre-fix subject, or it proves nothing
  ! /usr/bin/grep -q 'reap_abandoned_land_sandbox' "$pre" || false

  push_branch_as claude/abandoned 1 "$VM_EMAIL"
  decl cloud-ab claude/abandoned
  stale_local_head claude/abandoned
  dp="$(dead_pid)"
  [ -z "$(ps -o pid= -p "$dp" 2>/dev/null | tr -d ' ')" ]   # same premise as the positive arm
  sb="$D/.desk-land-claude-abandoned-$dp"
  git -C "$REPO" worktree add -q "$sb" claude/abandoned

  CONFIRM=1 run bash "$pre" --land claude/abandoned
  [ "$status" -eq 65 ]                      # ← the permanent refusal this fix ends
  [ ! -s "$LAND_STUB_LOG" ]
  echo "$output" | /usr/bin/grep -q 'CHECKED OUT'
  echo "$output" | /usr/bin/grep -q 'healed' && false
  [ -d "$sb" ]                              # pre-fix leaves the debris exactly where it was
  true
}

@test "FAILURE DIRECTION: a desk-land sandbox whose creator is ALIVE still refuses" {
  # The fix must err by reaping too LITTLE. A live creator means a land is in flight; removing its
  # worktree would corrupt real work — strictly worse than one more pass of delay.
  push_branch_as claude/inflight 1 "$VM_EMAIL"
  decl cloud-if claude/inflight
  stale_local_head claude/inflight
  sleep 30 & live=$!
  sb="$D/.desk-land-claude-inflight-$live"
  git -C "$REPO" worktree add -q "$sb" claude/inflight

  CONFIRM=1 run cr --land claude/inflight
  [ "$status" -eq 65 ]
  [ ! -s "$LAND_STUB_LOG" ]
  echo "$output" | /usr/bin/grep -q 'CHECKED OUT'
  echo "$output" | /usr/bin/grep -q 'ABANDONED desk-land sandbox' && false
  [ -d "$sb" ]                              # the in-flight land's sandbox is untouched

  kill "$live" 2>/dev/null || true
  wait "$live" 2>/dev/null || true
  true
}

# ── discovery ────────────────────────────────────────────────────────────────────────────────
@test "--list discovers a remote-only claude/* branch (and only claude/*)" {
  push_branch claude/aaa 1
  push_branch feat/other 1

  run cr --list
  [ "$status" -eq 0 ]
  # POSITIVE CONTROL for the absence below: the claude branch IS found off this same fixture, so a
  # listing that finds nothing at all cannot pass this test.
  echo "$output" | /usr/bin/grep -q 'claude/aaa'
  echo "$output" | /usr/bin/grep -qv 'feat/other' || false
  # And it is genuinely remote-only — no local head exists for it.
  git -C "$REPO" show-ref --verify --quiet refs/heads/claude/aaa && false
  true
}

@test "--list flags an UNDECLARED branch while a declared sibling reads ELIGIBLE" {
  push_branch claude/decl 1
  push_branch claude/orphan 1
  decl cloud-1 claude/decl

  run cr --list
  [ "$status" -eq 0 ]
  echo "$output" | /usr/bin/grep -q 'claude/orphan.*NO-DECL'
  # POSITIVE CONTROL: the same run classifies the declared sibling differently, so NO-DECL is a
  # real verdict and not the only thing this lister can say.
  echo "$output" | /usr/bin/grep -q 'claude/decl.*ELIGIBLE'
}

@test "a RETIRED declaration is skipped, an active one in the same run is landed" {
  push_branch claude/dead 1
  push_branch claude/live 1
  decl cloud-dead claude/dead
  decl cloud-live claude/live
  retire cloud-dead

  CONFIRM=1 run cr --all
  [ "$status" -eq 0 ]
  landed_branches | /usr/bin/grep -q '^claude/live$'
  # POSITIVE CONTROL for the absence: the log is provably non-empty (the line above), so "dead is
  # absent" is evidence rather than a grep over nothing.
  landed_branches | /usr/bin/grep -qv '^claude/dead$' || false
}

@test "a declaration whose paths are already on trunk reads LANDED and is not re-landed" {
  push_branch claude/done 1
  push_branch claude/todo 1
  decl cloud-done claude/done "already/landed.txt"
  decl cloud-todo claude/todo "not/on/trunk.txt"

  run cr --list
  [ "$status" -eq 0 ]
  echo "$output" | /usr/bin/grep -q 'claude/done.*LANDED'
  echo "$output" | /usr/bin/grep -q 'claude/todo.*ELIGIBLE'

  CONFIRM=1 run cr --all
  [ "$status" -eq 0 ]
  landed_branches | /usr/bin/grep -q '^claude/todo$'
  landed_branches | /usr/bin/grep -qv '^claude/done$' || false
}

# ── the CONFIRM=1 gate ───────────────────────────────────────────────────────────────────────
@test "--all without CONFIRM=1 refuses and lands NOTHING; with it, the same command lands" {
  push_branch claude/gated 1
  decl cloud-g claude/gated

  run cr --all
  [ "$status" -eq 65 ]
  echo "$output" | /usr/bin/grep -q 'CONFIRM=1'
  [ ! -s "$LAND_STUB_LOG" ]

  # POSITIVE CONTROL: the identical invocation with CONFIRM=1 DOES reach the lander, so the empty
  # log above is the gate refusing and not a broken fixture.
  CONFIRM=1 run cr --all
  [ "$status" -eq 0 ]
  [ -s "$LAND_STUB_LOG" ]
}

@test "--land without CONFIRM=1 refuses; --list is always allowed" {
  push_branch claude/one 1
  decl cloud-one claude/one

  run cr --land claude/one
  [ "$status" -eq 65 ]
  [ ! -s "$LAND_STUB_LOG" ]

  # --list needs no CONFIRM and stays read-only.
  run cr --list
  [ "$status" -eq 0 ]
  echo "$output" | /usr/bin/grep -q 'claude/one'
  [ ! -s "$LAND_STUB_LOG" ]
}

# ── --dry-run ────────────────────────────────────────────────────────────────────────────────
@test "--dry-run passes --dry-run to the lander on EVERY call, and a plain run passes it on none" {
  push_branch claude/d1 1
  push_branch claude/d2 2
  decl cloud-d1 claude/d1
  decl cloud-d2 claude/d2

  CONFIRM=1 run cr --all --dry-run
  [ "$status" -eq 0 ]
  # Two calls, both carrying --dry-run. The count assertion is what makes this two-sided: a run
  # that made ONE call would satisfy a bare grep.
  [ "$(/usr/bin/grep -c '^ARGS=.*--dry-run' "$LAND_STUB_LOG")" -eq 2 ]
  [ "$(/usr/bin/grep -c '^ARGS=' "$LAND_STUB_LOG")" -eq 2 ]

  # POSITIVE CONTROL for "never without": the same two branches WITHOUT --dry-run produce two calls
  # carrying none, so the flag tracks the option rather than being always-on or always-off.
  : > "$LAND_STUB_LOG"
  CONFIRM=1 run cr --all
  [ "$status" -eq 0 ]
  [ "$(/usr/bin/grep -c '^ARGS=' "$LAND_STUB_LOG")" -eq 2 ]
  [ "$(/usr/bin/grep -c '^ARGS=.*--dry-run' "$LAND_STUB_LOG")" -eq 0 ]
}

# ── per-branch failure isolation ─────────────────────────────────────────────────────────────
@test "a lander non-zero is reported per-branch and does NOT abort the remaining branches" {
  push_branch claude/bad 1
  push_branch claude/good 2
  decl cloud-bad claude/bad
  decl cloud-good claude/good

  LAND_STUB_FAIL="claude/bad" CONFIRM=1 run cr --all
  [ "$status" -eq 70 ]
  echo "$output" | /usr/bin/grep -q 'claude/bad'
  echo "$output" | /usr/bin/grep -q '6'
  # The whole point: the survivor still ran.
  landed_branches | /usr/bin/grep -q '^claude/good$'
  [ "$(/usr/bin/grep -c '^ARGS=' "$LAND_STUB_LOG")" -eq 2 ]
}

# ── the claude/* branch-name problem ─────────────────────────────────────────────────────────
@test "the lander is handed a SHIP_LAND_SESSION_BRANCH_RE that admits claude/ — scoped, not disabled" {
  push_branch claude/re 1
  decl cloud-re claude/re

  CONFIRM=1 run cr --all
  [ "$status" -eq 0 ]
  re="$(/usr/bin/grep -m1 '^RE=' "$LAND_STUB_LOG" | sed 's/^RE=//')"
  [ -n "$re" ]
  [ "$re" != "<unset>" ]
  # It admits the cloud branch...
  printf 'claude/re' | /usr/bin/grep -qE "$re"
  # ...and it is a SCOPED widening, not `.*`: a bare, prefix-less branch name is still rejected.
  printf 'randomname' | /usr/bin/grep -qvE "$re" || false
  # POSITIVE CONTROL that the override is load-bearing: ship-land.sh:1987's DEFAULT regex, spelled
  # out here, does NOT match claude/ — so without this env the land could only refuse.
  printf 'claude/re' | /usr/bin/grep -qvE '^(feat|fix|chore|docs|refactor|test|perf|style|build|ci)/.+' || false
}

# ── serialization ────────────────────────────────────────────────────────────────────────────
@test "--all lands smallest-diff first" {
  push_branch claude/big 4
  push_branch claude/small 1
  decl cloud-big claude/big
  decl cloud-small claude/small

  CONFIRM=1 run cr --all
  [ "$status" -eq 0 ]
  [ "$(landed_branches | head -1)" = "claude/small" ]
  [ "$(landed_branches | tail -1)" = "claude/big" ]
}

# ── the sensor ───────────────────────────────────────────────────────────────────────────────
@test "an unreachable remote is a SENSOR FAILURE (69), never 'no candidates' (0)" {
  push_branch claude/reachable 1

  # POSITIVE CONTROL first: against the real remote this fixture yields rows, so the empty result
  # below is the remote being unreachable and not an empty fixture.
  run cr --list
  [ "$status" -eq 0 ]
  echo "$output" | /usr/bin/grep -q 'claude/reachable'

  git -C "$REPO" remote set-url origin "$D/no-such-remote.git"
  run cr --list
  [ "$status" -eq 69 ]
  echo "$output" | /usr/bin/grep -qv 'claude/reachable' || false
}

# ── undeclared branches: discovered, flagged, never swept up by --all ────────────────────────
@test "--all skips an undeclared branch; --land names it explicitly and lands it" {
  push_branch claude/nodecl 1
  push_branch claude/yesdecl 1
  decl cloud-y claude/yesdecl

  CONFIRM=1 run cr --all
  [ "$status" -eq 0 ]
  landed_branches | /usr/bin/grep -q '^claude/yesdecl$'
  landed_branches | /usr/bin/grep -qv '^claude/nodecl$' || false

  # Naming it explicitly is the operator vouching for it, and that path DOES land.
  : > "$LAND_STUB_LOG"
  CONFIRM=1 run cr --land claude/nodecl
  [ "$status" -eq 0 ]
  landed_branches | /usr/bin/grep -q '^claude/nodecl$'
}

@test "--land on a branch absent from the remote refuses (65) without calling the lander" {
  push_branch claude/present 1

  CONFIRM=1 run cr --land claude/absent
  [ "$status" -eq 65 ]
  [ ! -s "$LAND_STUB_LOG" ]

  # POSITIVE CONTROL: a branch that IS on the remote reaches the lander off the same fixture.
  CONFIRM=1 run cr --land claude/present
  [ "$status" -eq 0 ]
  landed_branches | /usr/bin/grep -q '^claude/present$'
}

# ── the boot ping (CLOUD_OBSERVABILITY.md §4.1/§16) ──────────────────────────────────────────
# The contract puts a ref on the remote for every cloud session that boots, INCLUDING the ones
# that then produce nothing. Those branches are new to this path — before the contract they had no
# ref at all and never reached a lander — so the emptiness has to be a verdict of its own here.
@test "--land on a boot-pinged branch is NOTHING TO LAND (66), and the lander is never called" {
  decl s-ping claude/ping
  push_boot_ping claude/ping

  CONFIRM=1 run cr --land claude/ping
  [ "$status" -eq 66 ]
  # The whole point of 66: the expensive, destructive half of the path is not entered at all.
  [ ! -s "$LAND_STUB_LOG" ]
  [[ "$output" == *"nothing to land"* ]] || false

  # POSITIVE CONTROL — off the SAME fixture, a branch that carries one file DOES reach the lander,
  # so 66 is a statement about content and not about this suite failing to land anything.
  decl s-work claude/work
  push_branch claude/work 1
  CONFIRM=1 run cr --land claude/work
  [ "$status" -eq 0 ]
  landed_branches | /usr/bin/grep -q '^claude/work$'
}

@test "--all SKIPS a boot-pinged branch without counting it as a failure, and lands the rest" {
  decl s-ping claude/ping
  push_boot_ping claude/ping
  decl s-work claude/work
  push_branch claude/work 1

  CONFIRM=1 run cr --all
  # 0, not 70: a branch with nothing in it is not a branch that failed to land. A non-zero here
  # would make every dead cloud session read as a landing fault for the whole sweep.
  [ "$status" -eq 0 ]
  [[ "$output" == *"claude/ping"* ]] || false
  landed_branches | /usr/bin/grep -q '^claude/work$'
  # …and the empty one was never handed to the lander at all.
  landed_branches | /usr/bin/grep -q '^claude/ping$' && false
  true
}

# ── usage ────────────────────────────────────────────────────────────────────────────────────
@test "no verb → 64; unknown option → 64" {
  run cr
  [ "$status" -eq 64 ]

  run cr --frobnicate
  [ "$status" -eq 64 ]
}

# ══ the POST-HOC path fill (backlog a435e3987fbf) ═══════════════════════════════════════════════
# A declaration records paths= EMPTY (the dispatcher cannot know at fire time what the VM will
# write) and landed() returns "not landed" on an empty list BY DESIGN — so a finished cloud result
# read ELIGIBLE forever and every sweep re-attempted it. The fill runs AFTER a successful land,
# when the branch is a local head and its own commits state the set exactly.

@test "a successful land FILLS the declaration's path set from the branch's own commits" {
  push_branch claude/fillme 1
  decl fillme claude/fillme                       # …declared with paths= EMPTY, as `up` writes it
  run env CONFIRM=1 CLOUD_RECONCILE_CLOUD_BIN="$ROOT/bin/cc-cloud" bash "$CR" --land claude/fillme
  [ "$status" -eq 0 ]
  grep -q '^paths=f1.txt$' "$CC_CLOUD_STATE/fillme.decl"
}

@test "…and the branch that used to re-attempt forever now classifies as LANDED" {
  # The point of the whole change, off one fixture: ELIGIBLE before, LANDED after. Without the
  # "before" half, "LANDED after" would be equally explained by a fixture that was always landed.
  push_branch claude/twice 1
  decl twice claude/twice
  run bash "$CR" --list
  [[ "$output" == *"claude/twice"*ELIGIBLE* ]] || false
  run env CONFIRM=1 CLOUD_RECONCILE_CLOUD_BIN="$ROOT/bin/cc-cloud" bash "$CR" --land claude/twice
  [ "$status" -eq 0 ]
  # The stub advanced origin/main by content under a different sha, exactly as the real lander's
  # re-author does — so this second read is over the REAL post-land world, where the branch is
  # already an ancestor of trunk and only a set derived BEFORE the land could have been written.
  run bash "$CR" --list
  [[ "$output" == *"claude/twice"*LANDED* ]] || false
}

@test "a DRY RUN never fills — filling from a land that landed nothing would fake the next verdict" {
  push_branch claude/dry 1
  decl dry claude/dry
  run env CONFIRM=1 CLOUD_RECONCILE_CLOUD_BIN="$ROOT/bin/cc-cloud" bash "$CR" --land claude/dry --dry-run
  [ "$status" -eq 0 ]
  grep -q '^paths=$' "$CC_CLOUD_STATE/dry.decl"
}

@test "a fill that could NOT run is reported, never silent" {
  # A silent failure here is invisible until the next sweep re-attempts the same finished branch —
  # which is exactly the symptom the fill exists to remove, so it must not look like success.
  push_branch claude/nofill 1
  decl nofill claude/nofill
  run env CONFIRM=1 CLOUD_RECONCILE_CLOUD_BIN="$D/no-such-cc-cloud" bash "$CR" --land claude/nofill
  [ "$status" -eq 0 ]                       # the land itself succeeded and is not retracted …
  [[ "$output" == *"NOT filled"* ]] || false   # … but the non-verdict is NAMED
  grep -q '^paths=$' "$CC_CLOUD_STATE/nofill.decl"
}
