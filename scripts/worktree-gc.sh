#!/usr/bin/env bash
# worktree-gc.sh — the sanctioned worktree janitor for claude-infrastructure.
#
# WHY THIS FILE EXISTS: `hooks/git-worktree-guard.sh` (:6, :40, :57) tells the operator three
# times to reap with `bash scripts/worktree-gc.sh --prune` ("gates on live-claude-cwd / lsof /
# idle>30m / .teammate-busy and KEEPS the branch"), and `hooks/live-session-registry.sh:2`
# calls itself "durable per-worktree liveness registry for worktree-gc". Both promises pointed
# at a file that was absent from the checkout, from origin/main and from all of history — so
# every blocked operator fell back to raw `git worktree remove` / `git branch -D`, which
# bypasses every gate the guard exists to enforce (worktree audit 2026-07-25, §8-E).
#
# SAFETY MODEL — a worktree is removed ONLY when ALL of these hold; any miss ⇒ KEEP + reason:
#   1. it is a linked worktree of THIS repo, read from `git worktree list --porcelain`
#      (NEVER a directory glob: ~/Development/.worktrees is SHARED ACROSS 5 REPOS and hosts
#      other repos' live sessions — audit §6, the highest-severity finding),
#   2. the directory exists and is not excluded (CC_WTGC_EXCLUDE) / locked / .teammate-busy,
#   3. `git status --porcelain` is empty (dirty ⇒ removal would need --force ⇒ data loss),
#   4. no live session: union of `cc-notify --list --json` cwds, live `claude` proc cwds
#      (lsof -d cwd), any process holding files open under it, and the live-session registry
#      PID — over-matching is SAFE here, it can only ever cause a KEEP. Each oracle counts on
#      its ANSWER, never on its presence: the process-cwd probe opens with a positive control
#      against the caller's own pid, and a probe that cannot answer that makes gate 4 UNKNOWN
#      rather than clear (§ claude_cwds — a present-but-blind lsof used to read as an idle box),
#   5. idle > 30 min measured by the BRANCH TIP COMMITTER DATE, never directory mtime (a
#      `git status` sweep rewrites .git/worktrees/<n>/index, so admin-dir mtime is not a
#      freshness signal — audit §8-B),
#   6. the branch is LANDED by patch-equivalence: `git cherry <trunk> <branch>` has zero `+`
#      (catches the rebase/cherry-pick landing that plain ancestry misses).
# Removal is always `git worktree remove` — NEVER --force. Branch deletion is always
# `git branch -d` — NEVER -D. Those two refusals are git's own second gate on our evidence;
# a refusal is a KEEP, never something to force through (audit §8-H).
#
# THE DISPOSE CLASS — abandoned-but-UNLANDED (backlog c7bdab960795, 2026-07-26).
# Gate 6 protects live WIP correctly, but it is UNCONDITIONAL: a worktree whose work was
# deliberately never landed can never satisfy it, so nothing reaps it — not this janitor, and
# not `cc-reaper`, which reaps only a `work_landed()`-true cwd (bin/cc-reaper:361-382, the same
# patch-equivalence test). Measured 2026-07-26: 24 tracked-clean, genuinely-unlanded worktrees
# sat in that permanent-KEEP bucket. (A further 13 of the 37 originally filed were simply LIVE;
# gate 4 rules those correctly, and that half of the filed number was never the gap.)
#
# A worktree DISPOSES only when every gate above passes AND all three of:
#   A1. the branch tip is older than CC_WTGC_ABANDON_HOURS (default 72 h) — a horizon far past
#       any inter-turn gap. The 30 min idle floor is calibrated for LANDED work and is far too
#       short to mean "abandoned",
#   A2. the OWNER is TERMINAL — finished, or provably gone. THREE oracles, any one sufficient,
#       all fail-closed: (i) basename `wt-<id>` folded to status `done` by cc-backlog; (ii) a
#       teammate worktree `wt-tm-<m>` whose owning TEAM registry entry is DEAD (`.dead-*`) or
#       ARCHIVED (`_archive/`); (iii) an explicit, path-exact, sha-pinned dispose WARRANT.
#       Oracle (ii) is not a widening — it is what makes A2 reach
#       reality: a teammate worktree has no backlog id at all, and an item only goes `done`
#       when work LANDS, which gate 6 already reaps. Measured on the live checkout 2026-07-26:
#       of 21 dispose-eligible worktrees, 0 had a `done` item and 7 belonged to one dead team,
#       so oracle (i) alone carves out a near-empty set and the class stays stuck. Unparseable
#       name, unknown id, non-`done` status, a `wasDone` item somebody reopened, an unreadable
#       ledger, a LIVE owning team, or no owning team at all are each NOT-terminal ⇒ KEEP.
#       This is the discriminator that separates abandoned from merely-idle; age alone NEVER
#       disposes. Note what (ii) does and does not claim: a dead team proves the owner is not
#       coming back, NEVER that the work succeeded — which is exactly the DISPOSE claim,
#   A3. the commits are provably preserved at a durable ref — the branch resolves to the
#       worktree HEAD and `git for-each-ref --points-at` names it BEFORE removal, and AFTER
#       removal the ref still points at that sha and `git cherry` still yields the SAME unlanded
#       patch SET. Set identity, never a rev-list count: a count is blind to shared history,
#       same-patch shas and rebase-landed work. A verification miss is reported and exits 4.
#
# ORACLE 3 — THE EXPLICIT DISPOSE WARRANT (backlog d9fd066ebd28, 2026-07-30).
# Oracles (i) and (ii) are both INFERRED: they read a record somebody kept for another purpose.
# A worktree named for a feature rather than a backlog id — `wt-board-commands`,
# `fix/reaper-desk-registration` — has neither a `wt-<id>` name nor a `tm/*` team entry, so BOTH
# inferred oracles are structurally silent and no amount of age can ever reap it. That residue
# regrows on every feature-named worktree, so reaping the current members by hand is whack-a-mole,
# not a fix: the missing piece is a way to RECORD the abandon decision, which is exactly what the
# inferred oracles were standing in for.
# A warrant is one TSV line in CC_WTGC_WARRANTS:   <canonical-path>\t<head-sha>\t<reason>
# and it is the narrowest possible authorisation — it fails closed in five separate directions:
#   · PATH-EXACT, on the CANONICAL path, never a basename and never a prefix: basenames collide
#     across the 5 repos sharing ~/Development/.worktrees (audit §6), so a basename warrant could
#     authorise a DIFFERENT repo's worktree. Proximity is not evidence; the key is the identity.
#   · SHA-PINNED to the branch tip the decision was made against (a ≥7-char prefix is accepted;
#     anything shorter is malformed). If the tip MOVED, work resumed after the warrant was
#     written, so the warrant is STALE ⇒ KEEP. This is what stops a warrant rotting into a
#     standing licence — the failure mode this residue is itself an instance of.
#   · REASON-REQUIRED: an empty third field is malformed ⇒ KEEP. The ledger has to be able to
#     answer, months later, why this directory went; "somebody ran the command" is not an answer.
#   · A LIVE owning team VETOES it (an active wave outranks a decision made before the wave).
#   · It authorises A2 and NOTHING ELSE. Every KEEP gate, A1's age floor and A3's
#     before/after preservation proof are unchanged and still binding.
# Write one with `--warrant <path> --reason '<why>'`, which resolves the branch tip itself so the
# sha pin cannot be mistyped; revoke by deleting the line. A spent warrant is harmless: the path
# has to be a live worktree again AND the branch has to still be at the pinned sha.
#
# Disposal therefore removes a DIRECTORY, never a commit — the branch IS the durable ref and is
# preserved exactly as in the landed path, so a disposed worktree is restored with one
# `git worktree add <path> <branch>`. Acting requires --dispose-abandoned; WITHOUT it the class
# is still classified and printed (`DISPOSE?`), so a dispose plan citing this script can never
# silently mean "nothing happens" — the failure mode the class was filed for. Every disposal
# appends an intent record to CC_WTGC_DISPOSAL_LOG; that record is what later distinguishes an
# abandoned-BY-DECISION worktree from a dropped-BY-ACCIDENT one, which git alone cannot do
# (docs/research/STRANDED_EXPOSURE_2026-07-26.md §7).
#
# Branches are KEPT by default (a vanished worktree must stay recoverable via its branch).
# --prune-branches deletes only landed, worktree-less, unprotected branches.
#
#   worktree-gc.sh                      # remove reapable worktrees, keep every branch
#   worktree-gc.sh --prune              # identical (the invocation git-worktree-guard.sh prints)
#   worktree-gc.sh --dry-run            # print the plan, mutate nothing
#   worktree-gc.sh --prune-branches     # also delete landed worktree-less branches (-d only)
#   worktree-gc.sh --dispose-abandoned  # also reap the DISPOSE class (branch always preserved)
#   worktree-gc.sh --warrant <path> --reason '<why>'   # record oracle 3 for ONE path, then exit
#   CC_WTGC_DISABLE=1 worktree-gc.sh    # KILL SWITCH: exits 0 having inspected and mutated nothing
#
# Env seams (all optional; the CC_WTGC_* bins exist so bats can fixture the oracles):
#   CC_WTGC_DISABLE       KILL SWITCH. Unset or `0` is the only ENABLED reading; any other value
#                         disables, and the pass exits 0 printing `verdict=disabled` — no git call,
#                         no lock, no warrant, no removal.
#   CC_WTGC_DISABLE_FILE  the same switch as a FILE, for the paths an env var cannot reach: a
#                         launchd job inherits no shell environment (default:
#                         ~/.claude/autonomy/worktree-gc.disabled). Set it EMPTY to ignore the file.
#   CC_WTGC_EXCLUDE       colon-separated paths never touched (also covers nested worktrees)
#   CC_WTGC_REPO          repo to sweep (default: the repo containing $PWD)
#   CC_WTGC_TRUNK         landedness base (default: origin/main)
#   CC_WTGC_IDLE_MIN      idle floor in minutes (default: 30)
#   CC_WTGC_ABANDON_HOURS DISPOSE-class age floor in hours (default: 72)
#   CC_WTGC_BACKLOG       ownership oracle 1 — backlog ledger (default: ~/.claude/bin/cc-backlog)
#   CC_WTGC_TEAMS_DIR     ownership oracle 2 — team registry (default: ~/.claude/teams)
#   CC_WTGC_WARRANTS      ownership oracle 3 — explicit dispose warrants, TSV
#                         (default: ~/.claude/autonomy/worktree-warrants.tsv). Deliberately NOT
#                         JSON: this is the oracle that has to still work when the inferred ones
#                         cannot, so it must not inherit their `jq` dependency.
#   CC_WTGC_DISPOSAL_LOG  append-only disposal ledger
#                         (default: ~/.claude/autonomy/worktree-disposals.jsonl)
#   CC_WTGC_CC_NOTIFY / CC_WTGC_LSOF / CC_WTGC_PGREP / CC_WTGC_JQ    oracle binaries. Pointing one
#                         at a binary that RUNS but cannot answer is not a way to disable a gate:
#                         an unanswerable probe is refused, not believed. Use CC_WTGC_DISABLE.
#   CC_WTGC_REGISTRY_DIR  live-session registry (default: ~/.reso/live-sessions)
#   CC_WTGC_LOCK          mutex dir (default: ~/.claude/state/worktree-gc.lock)
#
# bash 3.2-safe (macOS default): no associative arrays, no mapfile, no [[ -v ]].
set -uo pipefail

# Wall-clock start, for the `elapsed=` line at the bottom (plan §6 R-b). Stamped HERE, before arg
# parsing and before the oracles, so it measures the whole pass — the liveness oracles are computed
# once up front and are a real part of a sweep's duration.
GC_T0="$(date +%s)"

DRY_RUN=0
PRUNE_BRANCHES=0
DISPOSE_ABANDONED=0
DISPOSE_LANDED_DIRT=0
WARRANT_PATH=""
WARRANT_REASON=""
USAGE="usage: worktree-gc.sh [--prune-branches] [--dispose-abandoned] [--dispose-landed-dirt] [--dry-run]
       worktree-gc.sh --warrant <worktree-path> --reason '<why this is abandoned>'"
# `--warrant` and `--reason` take a VALUE, so the loop carries a one-slot latch: a flag sets WANT,
# and the next argument is consumed as that flag's value instead of being parsed as a flag. A
# trailing flag with no value left is an ERROR, never a silently-empty warrant.
WANT=""
for arg in "$@"; do
  if [ -n "$WANT" ]; then
    case "$WANT" in
      warrant) WARRANT_PATH="$arg" ;;
      reason)  WARRANT_REASON="$arg" ;;
    esac
    WANT=""
    continue
  fi
  case "$arg" in
    --dry-run|-n)         DRY_RUN=1 ;;
    --prune-branches)     PRUNE_BRANCHES=1 ;;
    --dispose-abandoned)  DISPOSE_ABANDONED=1 ;;
    --dispose-landed-dirt) DISPOSE_LANDED_DIRT=1 ;;
    --warrant)            WANT=warrant ;;
    --reason)             WANT=reason ;;
    --prune)              : ;;   # compat alias: the guard hook's advertised invocation == default
    -h|--help)
      sed -n '2,/^# bash 3\.2-safe/p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) echo "worktree-gc: unknown flag '$arg'" >&2
       echo "$USAGE" >&2
       exit 2 ;;
  esac
done
if [ -n "$WANT" ]; then
  echo "worktree-gc: --$WANT requires a value" >&2
  echo "$USAGE" >&2
  exit 2
fi
if [ -z "$WARRANT_PATH" ] && [ -n "$WARRANT_REASON" ]; then
  echo "worktree-gc: --reason is only meaningful with --warrant" >&2
  echo "$USAGE" >&2
  exit 2
fi

# ── KILL SWITCH. Checked HERE — after argv validation, above everything else — because "disabled"
#    has to mean NOTHING HAPPENED, and every line below is already something happening: the config
#    block shells out to `git rev-parse` (and decides the exit-2 "not inside a git repository"
#    refusal), the warrant writer appends a TSV record, the mutex mkdir's a lock directory. A
#    switch checked any lower would have already run git, already written, or already refused for
#    the wrong reason. Disabled works outside a repo too, which is the property that proves the
#    placement rather than merely asserting it.
#
#    TWO SPELLINGS, because neither one alone covers every path this reaper is reached by:
#      · the ENV var covers a shell, a session, a wrapper that exports it, and the invocation
#        hooks/git-worktree-guard.sh tells the operator to type three times (:6, :40, :57) —
#        the one path no wrapper flag can ever gate.
#      · the FILE covers what an env var structurally cannot: com.claude.worktree-gc-infra is a
#        launchd job, and launchd jobs inherit no shell environment, so `export CC_WTGC_DISABLE=1`
#        is invisible to the 04:15 sweep. The file lives on the disk that job runs from, so one
#        `touch` stops every path (conclusion-must-reach-the-enforcing-store).
#    The wrappers keep their own file flags (worktree-gc-infra.disabled, reso's equivalent): belt
#    and braces on a destructive surface, and they stop the work earlier — before the fetch.
#
#    UNSET or `0` is the ONLY enabled reading. `1`, `true`, `false`, `off`, a typo — all disable,
#    because this gate's ambiguity must resolve toward NOT REMOVING THINGS
#    (gate-default-decides-failure-direction). `$HOME` is deliberately unguarded: with HOME unset
#    this line aborts the script, which is also the safe direction — the alternative, an empty
#    default that never matches, would silently sweep on (addon-failure-exceeds-its-blast-radius).
DISABLE_FILE="${CC_WTGC_DISABLE_FILE-$HOME/.claude/autonomy/worktree-gc.disabled}"
DISABLED_BY=""
case "${CC_WTGC_DISABLE:-}" in
  ''|0) ;;
  *)    DISABLED_BY="env=CC_WTGC_DISABLE" ;;
esac
if [ -z "$DISABLED_BY" ] && [ -n "$DISABLE_FILE" ] && [ -f "$DISABLE_FILE" ]; then
  DISABLED_BY="file=$DISABLE_FILE"
fi
if [ -n "$DISABLED_BY" ]; then
  # `verdict=disabled` is a PARSEABLE TOKEN, not prose. scripts/worktree-gc-infra-run.sh reads this
  # exact line to file its own `verdict=disabled` row; without it, a disabled janitor exits 0
  # printing no summary line, and that wrapper's rc-0 arm files `error stage=parse
  # reason=no-summary-line` — a false alarm every night for as long as the switch is on
  # (new-nonverdict-state-strands-its-consumers; claimed-outcome-vs-checked-outcome).
  echo "worktree-gc: verdict=disabled $DISABLED_BY — nothing inspected, nothing mutated."
  echo "worktree-gc: clear that switch to re-enable. For ONE read-only look without clearing it:"
  echo "worktree-gc:   CC_WTGC_DISABLE=0 CC_WTGC_DISABLE_FILE='' bash scripts/worktree-gc.sh --dry-run"
  exit 0
fi

GIT_BIN="${CC_WTGC_GIT:-git}"
JQ_BIN="${CC_WTGC_JQ:-jq}"
LSOF_BIN="${CC_WTGC_LSOF:-lsof}"
PGREP_BIN="${CC_WTGC_PGREP:-pgrep}"
CC_NOTIFY_BIN="${CC_WTGC_CC_NOTIFY:-$HOME/.claude/bin/cc-notify}"
REGISTRY_DIR="${CC_WTGC_REGISTRY_DIR:-$HOME/.reso/live-sessions}"
TRUNK="${CC_WTGC_TRUNK:-origin/main}"
IDLE_MIN="${CC_WTGC_IDLE_MIN:-30}"
LOCK_DIR="${CC_WTGC_LOCK:-$HOME/.claude/state/worktree-gc.lock}"
ABANDON_HOURS="${CC_WTGC_ABANDON_HOURS:-72}"
BACKLOG_BIN="${CC_WTGC_BACKLOG:-$HOME/.claude/bin/cc-backlog}"
TEAMS_DIR="${CC_WTGC_TEAMS_DIR:-$HOME/.claude/teams}"
DISPOSAL_LOG="${CC_WTGC_DISPOSAL_LOG:-$HOME/.claude/autonomy/worktree-disposals.jsonl}"
WARRANTS_FILE="${CC_WTGC_WARRANTS:-$HOME/.claude/autonomy/worktree-warrants.tsv}"

MAIN="$("$GIT_BIN" -C "${CC_WTGC_REPO:-$PWD}" rev-parse --show-toplevel 2>/dev/null)"
if [ -z "$MAIN" ]; then
  echo "worktree-gc: not inside a git repository (set CC_WTGC_REPO)" >&2
  exit 2
fi
# Always drive off the MAIN checkout, even when invoked from a linked worktree.
MAIN="$("$GIT_BIN" -C "$MAIN" rev-parse --path-format=absolute --git-common-dir 2>/dev/null | sed 's#/\.git$##')"
[ -d "$MAIN" ] || MAIN="$("$GIT_BIN" -C "${CC_WTGC_REPO:-$PWD}" rev-parse --show-toplevel)"

# canon <path> — resolve symlinks and fold /private/tmp → /tmp so cc-notify cwds, lsof output
# and the worktree registry compare on one canonical form (macOS /tmp is a symlink).
canon() {
  local p="${1:-}" r
  [ -n "$p" ] || return 0
  r="$(cd "$p" 2>/dev/null && pwd -P)" || r=""
  [ -n "$r" ] && p="$r"
  case "$p" in /private/tmp/*) p="/tmp/${p#/private/tmp/}" ;; esac
  printf '%s' "$p"
}

# ── Oracle 3 WRITER: `--warrant <path> --reason '<why>'` records ONE abandon decision. ───
# Runs before the mutex and before every oracle — it appends a text line and exits, it never
# touches a worktree. Every validation here fails LOUD (exit 2) instead of writing a record that
# would be silently rejected as malformed at read time: a warrant that quietly never fires is the
# same "no operator action required means nothing happens" failure the DISPOSE class was filed for.
if [ -n "$WARRANT_PATH" ]; then
  WP="$(canon "$WARRANT_PATH")"; [ -n "$WP" ] || WP="$WARRANT_PATH"
  if [ -z "$WARRANT_REASON" ]; then
    echo "worktree-gc: --warrant requires --reason '<why this is abandoned>'." >&2
    echo "worktree-gc: The reason IS the record — a disposal ledger that cannot say why the" >&2
    echo "worktree-gc: directory went is exactly what git alone already fails to give us." >&2
    exit 2
  fi
  TAB="$(printf '\t')"
  case "$WARRANT_REASON" in
    *"$TAB"*|*'
'*) echo "worktree-gc: --reason must not contain a tab or a newline (it is one TSV field)" >&2
       exit 2 ;;
  esac
  if [ "$(canon "$MAIN")" = "$WP" ]; then
    echo "worktree-gc: refusing to warrant the primary checkout ($MAIN)" >&2
    exit 2
  fi
  # Records come ONLY from `git worktree list` — never a directory test. A warrant must not be
  # writable against a bare directory, and ~/Development/.worktrees is shared across 5 repos
  # (audit §6), so "the path exists" proves nothing about which repo owns it.
  W_FOUND=0; W_BRANCH=""; W_DETACHED=0; _p=""; _b=""; _d=0
  while IFS= read -r line; do
    case "$line" in
      "worktree "*)          _p="${line#worktree }"; _b=""; _d=0 ;;
      "branch refs/heads/"*) _b="${line#branch refs/heads/}" ;;
      "detached")            _d=1 ;;
      "")
        if [ -n "$_p" ] && [ "$(canon "$_p")" = "$WP" ]; then
          W_FOUND=1; W_BRANCH="$_b"; W_DETACHED="$_d"
        fi
        _p=""; _b=""; _d=0 ;;
    esac
  done < <({ "$GIT_BIN" -C "$MAIN" worktree list --porcelain 2>/dev/null; echo; })
  if [ "$W_FOUND" = "0" ]; then
    echo "worktree-gc: '$WARRANT_PATH' is not a linked worktree of $MAIN." >&2
    echo "worktree-gc: Warrants are keyed on git's own worktree records, never on a directory." >&2
    exit 2
  fi
  if [ "$W_DETACHED" = "1" ] || [ -z "$W_BRANCH" ]; then
    echo "worktree-gc: '$WARRANT_PATH' is on a detached HEAD — no branch would preserve its" >&2
    echo "worktree-gc: commits after disposal, so there is nothing to pin the warrant to." >&2
    echo "worktree-gc: Give it a branch first: git -C '$WARRANT_PATH' switch -c <name>" >&2
    exit 2
  fi
  W_HEAD="$("$GIT_BIN" -C "$MAIN" rev-parse --verify --quiet "refs/heads/$W_BRANCH" 2>/dev/null)"
  if [ -z "$W_HEAD" ]; then
    echo "worktree-gc: cannot resolve refs/heads/$W_BRANCH — refusing to write an unpinnable warrant" >&2
    exit 2
  fi
  # The blast radius, shown HERE because here is where the decision is actually made. `git status
  # --porcelain` cannot see gitignored content and `git worktree remove` deletes it anyway at exit
  # 0 — so without this line the operator authorises a loss nothing would ever have told them about.
  W_IGNORED="$("$GIT_BIN" -C "$WP" status --porcelain --ignored 2>/dev/null | sed -n 's/^!! //p' | sort)"
  if [ "$DRY_RUN" = "1" ]; then
    echo "would warrant  $WP [$W_BRANCH] @ $W_HEAD — $WARRANT_REASON   [DRY-RUN — nothing was written]"
    exit 0
  fi
  mkdir -p "$(dirname "$WARRANTS_FILE")" 2>/dev/null
  if ! printf '%s\t%s\t%s\n' "$WP" "$W_HEAD" "$WARRANT_REASON" >> "$WARRANTS_FILE" 2>/dev/null; then
    echo "worktree-gc: could not append the warrant to $WARRANTS_FILE" >&2
    exit 2
  fi
  echo "worktree-gc: dispose warrant recorded in $WARRANTS_FILE"
  echo "  path    $WP"
  echo "  pinned  $W_BRANCH @ $W_HEAD  (if that tip moves, work resumed ⇒ the warrant goes STALE and is ignored)"
  echo "  reason  $WARRANT_REASON"
  if [ -n "$W_IGNORED" ]; then
    echo "worktree-gc: BLAST RADIUS — disposal also destroys this worktree's gitignored content,"
    echo "worktree-gc: which no gate can see and git preserves nowhere:"
    printf '%s\n' "$W_IGNORED" | sed 's/^/    ! /'
  fi
  echo "worktree-gc: the DIRECTORY is reaped by the next 'worktree-gc.sh --dispose-abandoned';"
  echo "worktree-gc: refs/heads/$W_BRANCH is PRESERVED (restore: git worktree add $WP $W_BRANCH)."
  echo "worktree-gc: revoke by deleting that line from $WARRANTS_FILE."
  exit 0
fi

# claude_cwds — raw cwd of every live `claude` process. Factored out of the oracle block below
# so the pre-mutation re-check can re-read the SAME truth: the classify→act window is minutes
# wide on a 65-worktree sweep, and a session that starts inside it would otherwise be reaped
# from under (the 2026-06-12 incident that git-worktree-guard.sh exists for).
#
# 🚨 THE EXIT STATUS IS THE ANSWERABILITY CHANNEL, and it is the whole contract:
#     0 → the probe ANSWERED. stdout may legitimately be empty: "no claude process holds a cwd".
#     2 → the probe COULD NOT ANSWER. stdout is meaningless and absence proves NOTHING.
# Until 2026-08-15 there was no second reading. Both `command -v` guards `return 0`, every failure
# inside the loop went to /dev/null, and the function's only output channel was stdout — so "no
# live claude" and "lsof could not answer" were literally the same value, and the two consumers
# both read that value as PROOF OF ABSENCE and removed a directory on it. That collapse swept an
# OCCUPIED worktree mid-session on 2026-08-11 (`close-integrity`, 01:50) and is what
# docs/plans/MASTER_FLEET_FOOTPRINT.md §P1 names as the defect: **a probe that ACTS on absence must
# confirm the safe state** (memory: probe-that-acts-on-absence-must-confirm-presence).
#
# Confirming it needs a POSITIVE CONTROL, not more error-swallowing, because the failures that
# matter here are SILENT ones — a sandboxed lsof, a seatbelt denial, a Linux lsof built without
# the flags, a pgrep that matches nothing because it is blind rather than because the box is idle.
# None of those set an exit code we can trust. So the probe is asked a question whose answer we
# already know: **read the cwd of our OWN pid**. We own that process, it provably exists, and it
# provably has a cwd — an lsof that cannot report it cannot report anyone's, and its silence about
# `claude` is therefore not evidence. The control's OUTPUT is discarded; only that it answered at
# all is the finding. pgrep gets the weaker treatment it can support: rc 1 is a real ANSWER (the
# binary's documented no-match), rc ≥ 2 is a failure to read the process table at all.
#
# The reason lives in a FILE, not a variable, because every caller reads this function through a
# command substitution and a subshell cannot assign to its parent. A refusal nobody can attribute
# is the same defect one layer up — it would put "occupancy unknown" and "occupied" on one line.
CWDS_WHY_FILE="${TMPDIR:-/tmp}/worktree-gc.cwdswhy.$$"
cwds_why() { cat "$CWDS_WHY_FILE" 2>/dev/null; }
_cwds_unanswerable() { printf '%s\n' "$1" > "$CWDS_WHY_FILE" 2>/dev/null; return 2; }
claude_cwds() {
  local cpid pids rc ctl
  : > "$CWDS_WHY_FILE" 2>/dev/null
  command -v "$PGREP_BIN" >/dev/null 2>&1 \
    || _cwds_unanswerable "pgrep ($PGREP_BIN) is not executable here" || return 2
  command -v "$LSOF_BIN" >/dev/null 2>&1 \
    || _cwds_unanswerable "lsof ($LSOF_BIN) is not executable here" || return 2
  # The control runs FIRST: an unanswerable probe must never look like a harvest that came up dry.
  # Drained through `sed`, never `grep -q`: -q closes the pipe on its first match, lsof dies of
  # SIGPIPE, and under `pipefail` a SUCCESSFUL control would report 141 — a positive control that
  # fails precisely when it passes is worse than none at all.
  ctl="$("$LSOF_BIN" -a -p "$$" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p')"
  [ -n "$ctl" ] \
    || _cwds_unanswerable "lsof cannot read the cwd of this very process (pid $$) — it cannot see any process's cwd, so its silence about claude is not evidence" \
    || return 2
  pids="$("$PGREP_BIN" -f claude 2>/dev/null)"; rc=$?
  [ "$rc" -le 1 ] \
    || _cwds_unanswerable "pgrep exited $rc — the process table was not read" || return 2
  for cpid in $(printf '%s\n' "$pids" | sort -u); do
    case "$cpid" in ''|*[!0-9]*) continue ;; esac
    "$LSOF_BIN" -a -p "$cpid" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p'
  done
  return 0
}

# ── Mutex: serialize every MUTATING pass (audit §8-D — cc-reaper:267, desk-land.sh,
#    lr-fire-resume.sh, teammate-auto-shutdown.sh and the guard hook all remove/prune too;
#    concurrent worktree mutation is the GH #34645/#48927 data-loss class). ────────────
LOCK_HELD=0
# shellcheck disable=SC2329  # invoked indirectly via `trap cleanup EXIT` (shellcheck can't see traps)
cleanup() { [ "$LOCK_HELD" = "1" ] && rmdir "$LOCK_DIR" 2>/dev/null; rm -f "$REMOVED_BR" "$CWDS_WHY_FILE" 2>/dev/null; }
REMOVED_BR="${TMPDIR:-/tmp}/worktree-gc.removed.$$"
trap cleanup EXIT
if [ "$DRY_RUN" = "0" ]; then
  mkdir -p "$(dirname "$LOCK_DIR")" 2>/dev/null
  if mkdir "$LOCK_DIR" 2>/dev/null; then
    LOCK_HELD=1
  else
    # Break a lock left behind by a crashed pass (>60 min), never a live one.
    if [ -d "$LOCK_DIR" ] && [ -n "$(find "$LOCK_DIR" -maxdepth 0 -mmin +60 2>/dev/null)" ]; then
      rmdir "$LOCK_DIR" 2>/dev/null
      mkdir "$LOCK_DIR" 2>/dev/null && LOCK_HELD=1
    fi
    if [ "$LOCK_HELD" = "0" ]; then
      echo "worktree-gc: another pass holds $LOCK_DIR — skipping (no concurrent worktree mutation)."
      exit 0
    fi
  fi
fi
: > "$REMOVED_BR"

# ── Liveness oracles, computed once. ─────────────────────────────────────────────────
# (a) registered sessions — cc-notify --list --json emits LIVE rows only (pid alive + pane present)
NOTIFY_CWDS=""
ORACLES=0
if [ -x "$CC_NOTIFY_BIN" ] && command -v "$JQ_BIN" >/dev/null 2>&1; then
  if NOTIFY_RAW="$("$CC_NOTIFY_BIN" --list --json 2>/dev/null)"; then
    NOTIFY_CWDS="$(printf '%s' "$NOTIFY_RAW" | "$JQ_BIN" -r '.[]?.cwd // empty' 2>/dev/null)"
    ORACLES=$((ORACLES + 1))
  fi
fi
# (b) process-level cwd sweep — catches panes that never registered (session-register.sh was
#     only wired ~2026-07-18 and SessionStart is write-once: memory reaper-blindness-...).
#
# COUNTED ON ITS ANSWER, NEVER ON ITS PRESENCE. The predicate here used to be `command -v pgrep &&
# command -v lsof` — i.e. the oracle counted because its binaries EXIST. A present-but-blind lsof
# then satisfied the ORACLES floor below all by itself, so a box where nothing could read a cwd
# passed the "cannot prove idle ⇒ refuse" gate and swept every worktree as idle. Existence is not
# an answer; only an answer is.
CLAUDE_CWDS=""
PROC_ORACLE_WHY=""
if CLAUDE_CWDS="$(claude_cwds)"; then
  ORACLES=$((ORACLES + 1))
else
  PROC_ORACLE_WHY="$(cwds_why)"
  CLAUDE_CWDS=""
  echo "worktree-gc: process-cwd oracle UNAVAILABLE — ${PROC_ORACLE_WHY:-it could not answer}."
  echo "worktree-gc: unregistered sessions are INVISIBLE this pass; every removal will be refused at act time."
fi
LIVE_CWDS="$(printf '%s\n%s\n' "$NOTIFY_CWDS" "$CLAUDE_CWDS" | while IFS= read -r c; do
  [ -n "$c" ] || continue
  printf '%s\n' "$(canon "$c")"
done | sort -u)"
if [ "$ORACLES" = "0" ] && [ "$DRY_RUN" = "0" ]; then
  echo "worktree-gc: no liveness oracle available (cc-notify + jq absent AND pgrep/lsof absent)."
  echo "worktree-gc: cannot prove a worktree is idle ⇒ refusing to remove anything. Re-run with --dry-run to inspect."
  exit 3
fi

is_live_cwd() { printf '%s\n' "$LIVE_CWDS" | grep -qxF "$1"; }

registry_live() { # <basename> <canon-path> → 0 iff a registered session PID is still alive here
  local base="$1" path="$2" row pid rcwd
  [ -f "$REGISTRY_DIR/$base" ] || return 1
  row="$(cat "$REGISTRY_DIR/$base" 2>/dev/null)"
  pid="$(printf '%s' "$row" | cut -f1)"
  rcwd="$(printf '%s' "$row" | cut -f3)"
  case "${pid:-}" in ''|*[!0-9]*) return 1 ;; esac
  kill -0 "$pid" 2>/dev/null || return 1
  # A bare basename can collide across the 5 repos sharing ~/Development/.worktrees (audit §6):
  # only honour the row when its recorded cwd is this worktree (or was never recorded).
  [ -z "$rcwd" ] && return 0
  [ "$(canon "$rcwd")" = "$path" ]
}

landed() { # <branch> → 0 iff every commit since the merge-base is on the trunk by patch-id
  local br="$1" out
  "$GIT_BIN" -C "$MAIN" rev-parse --verify --quiet "$TRUNK" >/dev/null 2>&1 || return 1
  out="$("$GIT_BIN" -C "$MAIN" cherry "$TRUNK" "$br" 2>/dev/null)" || return 1
  ! printf '%s\n' "$out" | grep -q '^+'
}

DIRT_BLOCKER=""
dirt_landed() { # <path> → 0 iff EVERY dirty path is byte-identical on $TRUNK; else 1 + DIRT_BLOCKER
  # The dirty-tree KEEP protects work in progress, but it never asked the second question: is the
  # "work" already on the trunk? `landed()` CANNOT answer it — that reads COMMITS, and this dirt is
  # dominated by paths STAGED-but-never-committed. Measured over the live population 2026-08-10:
  # 79 of 84 dirty trees carry tracked entries, and `git cherry` calls 72 of them landed — while
  # four staged paths (tools/blender/clawd_bmo.py + three assets/blender/clawd-bmo-*.webp, held in
  # SIX worktrees each) are absent from origin/main entirely and exist on no ref anywhere. Trusting
  # `landed()` here would have force-removed the only copies of expensive generated assets, which is
  # exactly the class ~/.claude/CLAUDE.md protects by name.
  #
  # So the question is asked PER DIRTY PATH against trunk CONTENT — the same shape as
  # ship-backup-reap.sh's predicate, including its bias: ANY uncertainty KEEPS. This function only
  # ever removes the dirty rung's VETO; every liveness/ownership gate below it still runs, and the
  # removal itself needs --dispose-landed-dirt on top.
  #
  # TWO COPIES, NOT ONE — the INDEX is the second, and `hash-object` on the working file is blind to
  # it (ruled 2026-08-11 while disposing this class over the live fleet, backlog 82dfe711cd09). The
  # 32 candidates were unanimous — one artifact set (the recycle-banner four), staged `A ` in 30 and
  # untracked in 2, every blob byte-identical to origin/main — so the hole below fired ZERO times and
  # is LATENT, not active. It is still a hole in a destroying predicate: at status `AM`/`MM` the index
  # holds a blob the working file does not, `clear_redundant_dirt`'s `git reset` drops it, and it is
  # then reachable from no ref and prunable. That is precisely the "staged bytes sit on no ref" trap
  # this whole class was filed for — the working file's copy is simply not the copy at risk.
  # The rule is REACHABILITY, never equality-with-trunk: a plain unstaged edit (` M`) legitimately
  # carries an index blob equal to HEAD and unequal to trunk, and demanding trunk there would KEEP
  # every such tree forever. So a staged blob passes iff it is the trunk's or this HEAD's — HEAD
  # because the branch is preserved by every removal path here, which is what makes it durable.
  local path="$1" porc ent st p tb wb ib hb
  DIRT_BLOCKER=""
  porc="$("$GIT_BIN" -C "$path" status --porcelain 2>/dev/null)" || { DIRT_BLOCKER="status unreadable"; return 1; }
  while IFS= read -r ent; do
    [ -n "$ent" ] || continue
    st="${ent:0:2}"; p="${ent:3}"
    # A rename, deletion or unmerged entry is divergence by construction — never byte-identical.
    case "$ent" in *' -> '*) DIRT_BLOCKER="rename in the tree"; return 1 ;; esac
    case "$st" in *D*|*U*) DIRT_BLOCKER="deletion/unmerged entry"; return 1 ;; esac
    # git QUOTES paths with spaces/UTF-8/control bytes. Decoding that is a second parser and a
    # second way to be wrong about which file we are about to destroy — refuse instead of guess.
    case "$p" in '"'*) DIRT_BLOCKER="quoted path (not decoded): $p"; return 1 ;; esac
    [ -f "$path/$p" ] || { DIRT_BLOCKER="not a regular file: $p"; return 1; }
    tb="$("$GIT_BIN" -C "$MAIN" rev-parse --verify --quiet "$TRUNK:$p" 2>/dev/null)"
    [ -n "$tb" ] || { DIRT_BLOCKER="absent from $TRUNK: $p"; return 1; }
    wb="$("$GIT_BIN" -C "$path" hash-object -- "$path/$p" 2>/dev/null)"
    [ -n "$wb" ] || { DIRT_BLOCKER="unhashable: $p"; return 1; }
    [ "$wb" = "$tb" ] || { DIRT_BLOCKER="differs from $TRUNK: $p"; return 1; }
    # `ls-files -s` prints `<mode> <sha> <stage>\t<path>`; unmerged entries would print several rows,
    # and those already returned above. An untracked path has no index entry at all ⇒ nothing staged
    # ⇒ nothing this rung can lose, and the empty read correctly skips it.
    ib="$("$GIT_BIN" -C "$path" ls-files -s -- "$p" 2>/dev/null | awk 'NR==1{print $2}')"
    if [ -n "$ib" ] && [ "$ib" != "$tb" ]; then
      hb="$("$GIT_BIN" -C "$path" rev-parse --verify --quiet "HEAD:$p" 2>/dev/null)"
      [ "$ib" = "$hb" ] || { DIRT_BLOCKER="staged bytes on no ref: $p"; return 1; }
    fi
  done <<EOF
$porc
EOF
  return 0
}

clear_redundant_dirt() { # <path> → 0 iff the tree is CLEAN afterwards, having lost nothing
  # Called ONLY after dirt_landed() has just re-proven every dirty path byte-identical to the
  # trunk, so each action below restores content that is already durably on origin/main. The point
  # is to reach a clean tree WITHOUT --force, so git's own refusal survives as the final gate.
  #   · staged        → unstage it (a path absent from HEAD simply becomes untracked)
  #   · tracked file  → restore it from HEAD
  #   · untracked     → delete it (its bytes are on the trunk)
  # The verdict is the tree's own emptiness, never the rc of these commands: if anything remains —
  # a shape the parser missed, a submodule, a permission failure — we return 1 and KEEP.
  local path="$1" porc ent p
  porc="$("$GIT_BIN" -C "$path" status --porcelain 2>/dev/null)" || return 1
  while IFS= read -r ent; do
    [ -n "$ent" ] || continue
    p="${ent:3}"
    "$GIT_BIN" -C "$path" reset -q -- "$p" 2>/dev/null || true
    if "$GIT_BIN" -C "$path" cat-file -e "HEAD:$p" 2>/dev/null; then
      "$GIT_BIN" -C "$path" checkout -q -- "$p" 2>/dev/null || true
    else
      rm -f -- "$path/$p" 2>/dev/null || true
    fi
  done <<EOF
$porc
EOF
  porc="$("$GIT_BIN" -C "$path" status --porcelain 2>/dev/null)" || return 1
  [ -z "$porc" ] || { DIRT_BLOCKER="tree still dirty after restore"; return 1; }
  return 0
}

# ── DISPOSE class: abandoned-but-unlanded (A1 age · A2 owning item terminal · A3 preserved) ──

unlanded_set() { # <branch> → the SET of unlanded commit shas, one per line, sorted
  # `git cherry` '+' rows only — patch-equivalence, so a rebase/squash landing is excluded.
  # The SET (not its cardinality) is the disposal invariant: a count cannot tell a preserved
  # branch from one that was rewritten under us into a different N commits.
  "$GIT_BIN" -C "$MAIN" cherry "$TRUNK" "$1" 2>/dev/null | awk '/^\+ /{print $2}' | sort
}

durable_refs() { # <sha> → every ref pointing AT this commit (the preservation proof)
  "$GIT_BIN" -C "$MAIN" for-each-ref --points-at "$1" --format='%(refname)' 2>/dev/null
}

op_in_progress() { # <path> → 0 iff a rebase/merge/cherry-pick/bisect is parked in this worktree
  # A stopped-but-CLEAN rebase leaves `git status --porcelain` empty, so the dirty gate misses
  # it — and `git worktree remove` would discard the parked operation with no way back.
  local gd m
  gd="$("$GIT_BIN" -C "$1" rev-parse --absolute-git-dir 2>/dev/null)" || return 1
  [ -n "$gd" ] || return 1
  for m in rebase-merge rebase-apply MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD BISECT_LOG; do
    if [ -e "$gd/$m" ]; then OP_KIND="$m"; return 0; fi
  done
  return 1
}

# The ownership oracle. Loaded lazily (only a DISPOSE candidate pays for it) and memoised as a
# TRI-STATE: an unreadable ledger must stay unreadable for the whole pass, never silently
# re-read as "fine" on the second lookup.
BACKLOG_STATE=0; BACKLOG_TABLE=""; BACKLOG_ERR=""; ITEM_ID=""; ITEM_WHY=""; OP_KIND=""
TEAM_WHY=""; OWNER_KIND=""; WARRANT_WHY=""
# OWNER_ACTIVE splits the two ways A2 can fail, because they take OPPOSITE remedies and lumping
# them together makes the residue line name the WRONG one. 1 = an oracle positively answered "not
# terminal" (an open/claimed/blocked item, a reopened item, a live team) ⇒ the work is owned and
# parked, so the remedy is to land it or resolve the item — NEVER `cc-backlog done`, which would
# falsify the ledger to reap a directory. 0 = every oracle was SILENT ⇒ nothing will ever rule on
# it, which is the residue oracle 3 exists to drain.
OWNER_ACTIVE=0
load_backlog() {
  case "$BACKLOG_STATE" in 1) return 0 ;; 2) return 1 ;; esac
  BACKLOG_STATE=2
  [ -x "$BACKLOG_BIN" ] || { BACKLOG_ERR="cc-backlog not executable at $BACKLOG_BIN"; return 1; }
  command -v "$JQ_BIN" >/dev/null 2>&1 || { BACKLOG_ERR="jq unavailable"; return 1; }
  local raw
  raw="$("$BACKLOG_BIN" list --all --json 2>/dev/null)" \
    || { BACKLOG_ERR="cc-backlog list --all --json failed"; return 1; }
  BACKLOG_TABLE="$(printf '%s' "$raw" | "$JQ_BIN" -r '.[]? | [.id, .status, (.wasDone|tostring)] | @tsv' 2>/dev/null)" \
    || { BACKLOG_ERR="cc-backlog JSON unparseable"; return 1; }
  [ -n "$BACKLOG_TABLE" ] || { BACKLOG_ERR="cc-backlog ledger is empty"; return 1; }
  BACKLOG_STATE=1
  return 0
}

item_terminal() { # <worktree-basename> → 0 iff its owning backlog item folds to `done`
  ITEM_ID=""; ITEM_WHY=""
  local base="$1" id row st wd
  case "$base" in wt-?*) id="${base#wt-}" ;; *) id="$base" ;; esac
  load_backlog || { ITEM_WHY="ownership unprovable — $BACKLOG_ERR"; return 1; }
  row="$(printf '%s\n' "$BACKLOG_TABLE" | awk -F'\t' -v k="$id" '$1==k{print;exit}')"
  [ -n "$row" ] || { ITEM_WHY="no owning backlog item '$id'"; return 1; }
  st="$(printf '%s' "$row" | cut -f2)"; wd="$(printf '%s' "$row" | cut -f3)"
  if [ "$st" = "done" ]; then ITEM_ID="$id"; return 0; fi
  if [ "$wd" = "true" ]; then ITEM_WHY="owning item $id was REOPENED (now '$st')"
  else                        ITEM_WHY="owning item $id is '$st', not terminal"; fi
  OWNER_ACTIVE=1     # an oracle RULED, and said the work is still owned — not the silent residue
  return 1
}

team_terminal() { # <worktree-basename> → 0 iff the owning TEAM has concluded
  # The SECOND ownership oracle, and the one that makes A2 reach reality. A teammate worktree
  # (`wt-tm-<m>`, branch `tm/<m>`) is owned by a TEAM, never by a backlog row — cc-backlog has no
  # id for it, so oracle 1 can only ever answer "no owning backlog item" and the whole tm/* class
  # stays permanently un-reapable. Measured 2026-07-26 on the live checkout: of 21 dispose-
  # eligible worktrees, 0 had a `done` backlog item (an item goes done when work LANDS, and
  # landed work is already reaped by gate 6 — so oracle 1 alone carves out a near-empty set),
  # while 7 were teammate worktrees of ONE dead team.
  #
  # A team registry entry that is DEAD (`.dead-*`) or ARCHIVED (`_archive/`) proves the OWNER IS
  # GONE. It deliberately does NOT claim the work succeeded — that is exactly the DISPOSE claim:
  # nobody is coming back, and the branch keeps every commit either way.
  # Fails closed in both unknown directions: named by a LIVE team ⇒ an active wave ⇒ KEEP; named
  # by no team at all ⇒ ownership unprovable ⇒ KEEP.
  TEAM_WHY=""
  local base="$1" member cfg d name live_hit=0 dead_hit=""
  case "$base" in
    wt-tm-?*) member="${base#wt-}" ;;      # wt-tm-gates → member tm-gates → branch tm/gates
    *) TEAM_WHY="not a teammate worktree — this oracle does not apply"; return 1 ;;
  esac
  [ -d "$TEAMS_DIR" ] || { TEAM_WHY="ownership unprovable — no team registry at $TEAMS_DIR"; return 1; }
  command -v "$JQ_BIN" >/dev/null 2>&1 || { TEAM_WHY="ownership unprovable — jq unavailable"; return 1; }
  # Three globs: live teams, DEAD teams (dot-prefixed ⇒ invisible to `*`), archived teams.
  for cfg in "$TEAMS_DIR"/*/config.json "$TEAMS_DIR"/.[!.]*/config.json "$TEAMS_DIR"/_archive/*/config.json; do
    [ -f "$cfg" ] || continue
    # shellcheck disable=SC2016  # $m is a JQ variable bound by --arg, never a shell expansion
    "$JQ_BIN" -e --arg m "$member" \
      '[.members[]?|(.name//.agentName//"")]|index($m)!=null' "$cfg" >/dev/null 2>&1 || continue
    d="$(dirname "$cfg")"; name="$(basename "$d")"
    case "$d" in
      "$TEAMS_DIR"/_archive/*) dead_hit="owning team $name is ARCHIVED" ;;
      *) case "$name" in
           .dead-*) dead_hit="owning team ${name#.dead-} is DEAD" ;;
           *)       live_hit=1 ;;
         esac ;;
    esac
  done
  if [ "$live_hit" = "1" ]; then
    TEAM_WHY="teammate of a LIVE team — an active wave"
    OWNER_ACTIVE=1   # an oracle RULED, and said the work is still owned — not the silent residue
    return 1
  fi
  [ -n "$dead_hit" ] || { TEAM_WHY="no owning team names teammate '$member'"; return 1; }
  ITEM_ID="$member"; TEAM_WHY="$dead_hit"
  return 0
}

ignored_inventory() { # <path> → the gitignored entries removal would destroy, comma-joined
  # `git status --porcelain` — gate 3, and cc-reaper's untracked guard — is BLIND to ignored
  # content, and `git worktree remove` deletes it anyway at exit 0 with no --force and no warning
  # (reproduced 2026-07-30: a worktree holding only `secrets.env` removes clean and the file is
  # gone). Disposal cannot refuse on it — measured on the live residue, 6 of 6 candidates carry
  # `.claude-plans/`/`.claude-tasks/`/`__pycache__/`, so a KEEP gate here would make oracle 3
  # inert by construction, which is precisely how oracle 1 failed. So it is NAMED instead: shown
  # at warrant time, where the decision is actually made, and recorded in the ledger, so a
  # destructive act always states its blast radius.
  "$GIT_BIN" -C "$1" status --porcelain --ignored 2>/dev/null \
    | sed -n 's/^!! //p' | sort | tr '\n' ',' | sed 's/,$//'
}

warrant_terminal() { # <canon-path> <branch> → 0 iff an explicit, path-exact, sha-current warrant applies
  # ORACLE 3, and the only NON-inferred one: oracles 1 and 2 read a record kept for another
  # purpose, so a worktree named for a feature rather than a backlog id or a team member is
  # invisible to both and no amount of age can reach it. Deliberately reads a TSV with awk and
  # never jq — this is the oracle that has to work when the inferred ones cannot, so it must not
  # inherit their dependency. Fails closed on absent / malformed / STALE.
  WARRANT_WHY=""
  local cpath="$1" branch="$2" row w_head w_reason head
  [ -f "$WARRANTS_FILE" ] || { WARRANT_WHY="no dispose warrant recorded"; return 1; }
  # LAST match wins, so re-warranting a path supersedes an earlier record without an edit.
  # $1==p is an EXACT compare on the canonical path — never a basename (basenames collide across
  # the 5 repos sharing ~/Development/.worktrees) and never a prefix.
  # A trailing slash is the one hand-edit slip forgiven here; everything else must match exactly.
  row="$(awk -F'\t' -v p="$cpath" '{k=$1; sub(/\/+$/,"",k)} k==p{r=$0} END{if (r != "") print r}' \
    "$WARRANTS_FILE" 2>/dev/null)"
  [ -n "$row" ] || { WARRANT_WHY="no dispose warrant names this path"; return 1; }
  w_head="$(printf '%s' "$row" | cut -f2)"
  w_reason="$(printf '%s' "$row" | cut -f3-)"
  [ -n "$w_reason" ] || { WARRANT_WHY="dispose warrant is MALFORMED (no reason recorded)"; return 1; }
  case "$w_head" in
    ''|*[!0-9a-fA-F]*) WARRANT_WHY="dispose warrant is MALFORMED (pinned sha '$w_head' is not a sha)"; return 1 ;;
  esac
  # A short pin would match many commits — a pin that loose is not a content check at all.
  if [ "${#w_head}" -lt 7 ]; then
    WARRANT_WHY="dispose warrant is MALFORMED (pinned sha '$w_head' is under 7 chars)"; return 1
  fi
  head="$("$GIT_BIN" -C "$MAIN" rev-parse --verify --quiet "refs/heads/$branch" 2>/dev/null)"
  [ -n "$head" ] || { WARRANT_WHY="dispose warrant unverifiable — refs/heads/$branch will not resolve"; return 1; }
  case "$head" in
    "$w_head"*) : ;;
    *) WARRANT_WHY="dispose warrant is STALE — pinned at $w_head but $branch is now $head (work resumed after the decision)"
       return 1 ;;
  esac
  WARRANT_WHY="explicit dispose warrant — $w_reason"
  return 0
}

owner_terminal() { # <basename> <canon-path> <branch> → 0 iff ANY oracle proves the owner is finished or gone
  # All three oracles are consulted before a KEEP: the backlog one answers for `wt-<id>`, the team
  # one for `wt-tm-<m>`, and the warrant for anything an operator has explicitly ruled on.
  # ITEM_WHY is left holding the verdict of the oracle that was actually APPLICABLE, so the KEEP
  # line names a real reason instead of the wrong oracle's miss.
  OWNER_KIND=""; WARRANT_WHY=""; OWNER_ACTIVE=0
  if item_terminal "$1"; then OWNER_KIND="backlog item $ITEM_ID done"; return 0; fi
  local bl_why="$ITEM_WHY" bl_active="$OWNER_ACTIVE"
  # Reset before the team oracle so the flag it leaves is attributable to THAT oracle alone.
  # Without this, a merely-blocked backlog item is indistinguishable from a live team, and the
  # veto below would fire on it — naming the wrong oracle's reason and skipping oracle 3 entirely.
  OWNER_ACTIVE=0
  if team_terminal "$1"; then OWNER_KIND="$TEAM_WHY"; return 0; fi
  local tm_live="$OWNER_ACTIVE"
  # A LIVE owning team VETOES the warrant: an active wave outranks a decision recorded before it,
  # and the same precedence already governs a live team against a dead one naming the same member.
  # A merely-blocked ITEM is NOT a veto — a warrant is a later, more specific decision than the
  # ledger status, and disposal only ever removes the directory.
  if [ "$tm_live" = "1" ]; then ITEM_WHY="$TEAM_WHY"; OWNER_ACTIVE=1; return 1; fi
  if warrant_terminal "$2" "$3"; then
    ITEM_ID="$1"
    OWNER_KIND="$WARRANT_WHY"
    return 0
  fi
  OWNER_ACTIVE="$bl_active"
  case "$1" in
    wt-tm-?*) ITEM_WHY="$TEAM_WHY" ;;
    *)        ITEM_WHY="$bl_why" ;;
  esac
  # Name oracle 3's verdict too whenever it had something to report. A STALE or MALFORMED warrant
  # is a real finding: staying silent about it would read as "nobody ever wrote one", which is the
  # opposite of the truth and would leave the operator re-writing a warrant that already exists.
  case "$WARRANT_WHY" in
    ''|'no dispose warrant'*) : ;;
    *) ITEM_WHY="$ITEM_WHY; $WARRANT_WHY" ;;
  esac
  return 1
}

# RECHECK_WHY — why the act-time gate said LIVE. Two readings that must never share a line:
# "a session started inside the classify window" (occupancy PROVEN) and "the probe could not
# answer" (occupancy UNKNOWN). Both KEEP, but only the first is a normal Tuesday; the second is a
# broken instrument on a box that is still being swept, and an operator who cannot see the
# difference cannot fix it.
RECHECK_WHY=""
recheck_live() { # <path> <canon-path> → 0 iff something looks live HERE, right now, OR unprovable
  # Re-read at ACT time, not classify time. Deliberately narrower than the startup union (it
  # skips cc-notify, whose registry is derived from these same processes) — it exists to catch a
  # session BORN inside the classify→act window, and over-matching here can only cause a KEEP.
  #
  # FAILS CLOSED. This is the LAST gate before a directory is destroyed, so its "not live" has to
  # mean the probe LOOKED and saw nobody — never that it could not look. `registry_live` alone is
  # not a substitute: it reads a written record, and the sessions this exists to catch are exactly
  # the ones that never wrote one, so a pass with cc-notify as its only working oracle would sail
  # through here on a record's silence about a session that was never in it.
  local path="$1" cpath="$2" c cwds rc
  RECHECK_WHY="a session started inside the classify window"
  registry_live "$(basename "$path")" "$cpath" && return 0
  cwds="$(claude_cwds)"; rc=$?
  if [ "$rc" -ne 0 ]; then
    RECHECK_WHY="occupancy UNPROVEN — $(cwds_why)"
    return 0
  fi
  while IFS= read -r c; do
    [ -n "$c" ] || continue
    [ "$(canon "$c")" = "$cpath" ] && return 0
  done <<EOF
$cwds
EOF
  if command -v "$LSOF_BIN" >/dev/null 2>&1 && "$LSOF_BIN" -- "$path" 2>/dev/null | grep . >/dev/null; then
    return 0
  fi
  RECHECK_WHY=""
  return 1
}

verify_preserved() { # <branch> <head-sha> <unlanded-set-before> → 0 iff nothing moved
  local branch="$1" head="$2" before="$3" now
  now="$("$GIT_BIN" -C "$MAIN" rev-parse --verify --quiet "refs/heads/$branch" 2>/dev/null)"
  [ -n "$now" ] && [ "$now" = "$head" ] || return 1
  durable_refs "$head" | grep . >/dev/null || return 1
  [ "$(unlanded_set "$branch")" = "$before" ]
}

json_esc() { printf '%s' "${1:-}" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

log_disposal() { # <path> <branch> <head> <n> <patch-shas> <item> <idle-h> <verified> <owner-proof> <ignored>
  # `owner_proof` records WHICH oracle authorised the disposal (a done backlog item, a dead or
  # archived team, or an explicit warrant). Without it the ledger cannot answer, months later, why
  # this directory went. `destroyed_ignored` is the blast radius: the gitignored paths that went
  # with it, which git records NOWHERE and no gate can see — the only trace they ever existed.
  local dir; dir="$(dirname "$DISPOSAL_LOG")"
  mkdir -p "$dir" 2>/dev/null || return 0
  printf '{"ts":"%s","event":"worktree-disposed","path":"%s","branch":"%s","head":"%s","unlanded_patches":%s,"patch_shas":"%s","owner_item":"%s","owner_proof":"%s","idle_hours":%s,"preserved_at":"refs/heads/%s","verified":"%s","destroyed_ignored":"%s"}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$(json_esc "$1")" "$(json_esc "$2")" "$3" "$4" \
    "$(json_esc "$5")" "$(json_esc "$6")" "$(json_esc "${9:-}")" "$7" "$(json_esc "$2")" "$8" \
    "$(json_esc "${10:-}")" \
    >> "$DISPOSAL_LOG" 2>/dev/null || true
}

excluded() { # <canon-path> → 0 iff hard-excluded by CC_WTGC_EXCLUDE (exact or ancestor)
  local p="$1" e rest="${CC_WTGC_EXCLUDE:-}"
  [ -n "$rest" ] || return 1
  while [ -n "$rest" ]; do
    e="${rest%%:*}"
    if [ "$rest" = "$e" ]; then rest=""; else rest="${rest#*:}"; fi
    [ -n "$e" ] || continue
    e="$(canon "$e")"
    [ "$p" = "$e" ] && return 0
    case "$p" in "$e"/*) return 0 ;; esac
  done
  return 1
}

protected_branch() { # never deleted, whatever the evidence says
  case "$1" in
    main|master)                            return 0 ;;
    ship/backup-*|backup/*|*-prerebase-backup) return 0 ;;
  esac
  return 1
}

N_REMOVED=0; N_KEPT=0; N_BR_DELETED=0; N_REFUSED=0; N_DISPOSED=0; N_DISPOSE_CAND=0; VERIFY_FAIL=0
N_DIRT_CAND=0; N_DIRT_REMOVED=0
N_UNOWNED=0; N_OWNER_ACTIVE=0
PREFIX=""; [ "$DRY_RUN" = "1" ] && PREFIX="would "

dispose_record() { # <path> <canon> <branch> <base> <idle-hours> <n-unlanded> — the DISPOSE action
  # Reached only once A1 (age) and A2 (owning item terminal) hold and every KEEP gate has passed.
  # A3 (durable-ref preservation) is proved HERE, twice: before removal and again after it.
  local path="$1" cpath="$2" branch="$3" base="$4" idle_h="$5" n="$6"
  local head wt_head before shas note ignored
  # Read the blast radius BEFORE removal — afterwards the directory is gone and the answer is
  # unrecoverable, which is exactly why this content has never been accounted for anywhere.
  ignored="$(ignored_inventory "$path")"
  head="$("$GIT_BIN" -C "$MAIN" rev-parse --verify --quiet "refs/heads/$branch" 2>/dev/null)"
  wt_head="$("$GIT_BIN" -C "$path" rev-parse HEAD 2>/dev/null)"
  before="$(unlanded_set "$branch")"
  if [ -z "$head" ] || [ "$head" != "$wt_head" ] || ! durable_refs "$head" | grep -x "refs/heads/$branch" >/dev/null; then
    echo "KEEP    $path [$branch] — DISPOSE refused: no durable ref proves the commits survive removal"
    N_KEPT=$((N_KEPT + 1)); N_REFUSED=$((N_REFUSED + 1))
    return 0
  fi
  shas="$(printf '%s\n' "$before" | tr '\n' ',' | sed 's/,$//')"
  note="abandoned-unlanded · $n patch(es) preserved on refs/heads/$branch · $OWNER_KIND · idle ${idle_h}h"

  if [ "$DISPOSE_ABANDONED" = "0" ]; then
    echo "DISPOSE? $path [$branch] — $note — pass --dispose-abandoned to reap (branch KEPT)"
    N_DISPOSE_CAND=$((N_DISPOSE_CAND + 1))
    return 0
  fi
  if [ "$DRY_RUN" = "1" ]; then
    echo "would dispose  $path [$branch] — $note"
    N_DISPOSED=$((N_DISPOSED + 1))
    return 0
  fi
  if recheck_live "$path" "$cpath"; then
    echo "KEEP    $path [$branch] — LIVE at act time ($RECHECK_WHY)"
    N_KEPT=$((N_KEPT + 1))
    return 0
  fi
  # NEVER --force, exactly as on the landed path: git's refusal is the second gate on our evidence.
  if ! "$GIT_BIN" -C "$MAIN" worktree remove "$path" 2>/dev/null; then
    echo "KEEP    $path [$branch] — git REFUSED 'worktree remove' (it changed since the gates ran)"
    N_KEPT=$((N_KEPT + 1)); N_REFUSED=$((N_REFUSED + 1))
    return 0
  fi
  if verify_preserved "$branch" "$head" "$before"; then
    log_disposal "$path" "$branch" "$head" "$n" "$shas" "$ITEM_ID" "$idle_h" "points-at+cherry-set" "$OWNER_KIND" "$ignored"
    echo "dispose $path [$branch] — $note · VERIFIED preserved (restore: git worktree add <path> $branch)"
    [ -n "$ignored" ] && echo "        └ gitignored content destroyed with it (git records this nowhere else): $ignored"
    N_DISPOSED=$((N_DISPOSED + 1))
  else
    log_disposal "$path" "$branch" "$head" "$n" "$shas" "$ITEM_ID" "$idle_h" "FAILED" "$OWNER_KIND" "$ignored"
    echo "worktree-gc: PRESERVATION UNVERIFIED after removing $path [$branch] — the unlanded patch set at" >&2
    echo "worktree-gc: refs/heads/$branch no longer matches what was there. Recover from $head." >&2
    N_DISPOSED=$((N_DISPOSED + 1)); VERIFY_FAIL=$((VERIFY_FAIL + 1))
  fi
}

# ── 1. Broken admin records (dir gone, .git link gone) — pure bookkeeping, zero content. ──
if [ "$DRY_RUN" = "1" ]; then
  PRUNABLE="$("$GIT_BIN" -C "$MAIN" worktree prune --dry-run -v 2>/dev/null)"
  [ -n "$PRUNABLE" ] && printf '%s\n' "$PRUNABLE" | sed 's/^/would prune  /'
else
  "$GIT_BIN" -C "$MAIN" worktree prune -v 2>/dev/null | sed 's/^/prune  /'
fi

# ── 2. Per-worktree gates. Records come ONLY from git — never a directory listing. ───────
wt=""; br=""; detached=0; locked=0
process_record() {
  local path="$wt" branch="$br" base reason="" dirty_porc=""
  [ -n "$path" ] || return 0
  [ "$path" = "$MAIN" ] && return 0                       # never the primary checkout
  local cpath; cpath="$(canon "$path")"
  base="$(basename "$path")"

  if   excluded "$cpath";                                    then reason="hard-excluded (CC_WTGC_EXCLUDE)"
  elif [ ! -d "$path" ];                                     then reason="directory is gone (admin record only — 'git worktree prune' handles it)"
  elif [ "$locked" = "1" ];                                  then reason="locked worktree"
  elif [ -f "$path/.teammate-busy" ];                        then reason=".teammate-busy marker present"
  # Two commands, so the LAST one decides the branch: this keeps the `status` fork lazy (the four
  # rungs above still short-circuit it) while capturing its output for the removal path, which must
  # know whether it is removing a tree whose dirt was PROVEN redundant.
  elif dirty_porc="$("$GIT_BIN" -C "$path" status --porcelain 2>/dev/null)"
       [ -n "$dirty_porc" ] && ! dirt_landed "$path"; then
                                                                  reason="dirty tree, $DIRT_BLOCKER (removal would need --force ⇒ data loss)"
  elif op_in_progress "$path";                               then reason="a git operation is parked here ($OP_KIND) — removal would discard it"
  elif is_live_cwd "$cpath";                                 then reason="LIVE — a registered session / running claude is cwd'd here"
  elif registry_live "$base" "$cpath";                       then reason="LIVE — live-session-registry PID still alive"
  elif command -v "$LSOF_BIN" >/dev/null 2>&1 && "$LSOF_BIN" -- "$path" 2>/dev/null | grep . >/dev/null; then
                                                                  reason="open by a live process"
  elif [ "$detached" = "1" ] || [ -z "$branch" ];            then reason="detached HEAD (manual review — no branch records where the work went)"
  else
    local tip now age
    tip="$("$GIT_BIN" -C "$MAIN" log -1 --format=%ct "$branch" 2>/dev/null)"
    now="$(date +%s)"
    case "${tip:-}" in ''|*[!0-9]*) tip="" ;; esac
    if [ -z "$tip" ]; then
      reason="branch tip date unreadable"
    else
      age=$(( (now - tip) / 60 ))
      if [ "$age" -lt "$IDLE_MIN" ]; then
        reason="branch tip is ${age}m old (< ${IDLE_MIN}m idle floor)"
      elif ! landed "$branch"; then
        # Unlanded. Live WIP or abandoned? Age alone cannot tell them apart — A2, the owner's
        # terminality, is the discriminator. Any miss falls through to the same permanent KEEP as
        # before, now NAMING which abandonment gate held it — and, when it is A2 that held it, the
        # worktree is counted into the un-ownable residue so the total is reported, not buried.
        local n why=""
        n="$(unlanded_set "$branch" | grep -c . | tr -d ' ')"
        if [ "$((age / 60))" -lt "$ABANDON_HOURS" ]; then
          why="idle $((age / 60))h < ${ABANDON_HOURS}h abandon horizon"
        elif ! owner_terminal "$base" "$cpath" "$branch"; then
          why="$ITEM_WHY"
          # Two DIFFERENT stuck states with OPPOSITE remedies — see OWNER_ACTIVE. Counting them
          # as one number makes the summary prescribe the wrong fix for whichever half it is not
          # describing, and `cc-backlog done` on a merely-blocked item would falsify the ledger
          # to reap a directory.
          if [ "$OWNER_ACTIVE" = "1" ]; then N_OWNER_ACTIVE=$((N_OWNER_ACTIVE + 1))
          else                               N_UNOWNED=$((N_UNOWNED + 1)); fi
        else
          dispose_record "$path" "$cpath" "$branch" "$base" "$((age / 60))" "$n"
          return 0
        fi
        reason="$n commit(s) not on $TRUNK by patch-id (unlanded — ship first; not abandoned: $why)"
      fi
    fi
  fi

  if [ -n "$reason" ]; then
    echo "KEEP    $path [${branch:-detached}] — $reason"
    N_KEPT=$((N_KEPT + 1))
    return 0
  fi

  # ── LANDED-DIRT class ────────────────────────────────────────────────────────────────────────
  # Reaching here with a non-empty tree means dirt_landed() PROVED every dirty path byte-identical
  # to the trunk, and every liveness/ownership rung below the dirty gate then passed too. It is
  # still its OWN opt-in flag rather than a widening of --dispose-abandoned: that class preserves
  # unlanded COMMITS on a branch and is a different risk with a different proof, and the cron must
  # be able to enable exactly one of them.
  if [ -n "$dirty_porc" ]; then
    if [ "$DISPOSE_LANDED_DIRT" = "0" ]; then
      echo "DIRT?   $path [$branch] — dirty but every dirty path is byte-identical on $TRUNK — pass --dispose-landed-dirt to reap"
      # The BLAST RADIUS at DECISION time, exactly as the DISPOSE class reports it. Every TRACKED
      # path here is provably on the trunk, so the only thing a removal actually destroys is the
      # gitignored content — and git records that nowhere else, so if this line does not print it,
      # nothing ever will. Measured 2026-08-10: 12 of 12 sampled candidates carry some (node_modules/,
      # .claude-tasks/, .ruff_cache/ — regenerable, but that is the reader's call to make, not ours).
      _dirt_ign="$(ignored_inventory "$path")"
      [ -n "$_dirt_ign" ] && echo "        └ gitignored content a disposal would destroy: $_dirt_ign"
      N_DIRT_CAND=$((N_DIRT_CAND + 1))
      return 0
    fi
    if [ "$DRY_RUN" = "1" ]; then
      echo "${PREFIX}dispose-dirt  $path [$branch] — dirt redundant with $TRUNK · idle · landed"
      N_DIRT_REMOVED=$((N_DIRT_REMOVED + 1))
      printf '%s\n' "$branch" >> "$REMOVED_BR"
      return 0
    fi
    if recheck_live "$path" "$cpath"; then
      echo "KEEP    $path [$branch] — LIVE at act time ($RECHECK_WHY)"
      N_KEPT=$((N_KEPT + 1))
      return 0
    fi
    # RE-PROVE the dirt at act time — a session can start editing inside the classify→act window.
    if ! dirt_landed "$path"; then
      echo "KEEP    $path [$branch] — dirt CHANGED after classification ($DIRT_BLOCKER)"
      N_KEPT=$((N_KEPT + 1)); N_REFUSED=$((N_REFUSED + 1))
      return 0
    fi
    # NO --force, exactly as on the other two removal paths. It would have been the easy way to get
    # a dirty tree removed, and it is precisely what audit §8-H bans (tests/worktree-gc.bats guards
    # the SOURCE for it): `git worktree remove` refusing is the LAST net under our own evidence, and
    # this class needs that net MORE than the others, not less — the predicate above is a parser,
    # and a path shape it mis-reads is exactly what git's own opinion would still catch.
    # So instead of overriding the refusal, REMOVE ITS CAUSE: every dirty path here is proven
    # byte-identical to the trunk, so restoring it loses nothing, and a tree that does not come out
    # clean is one we never understood — git then refuses on its own and we KEEP.
    # Read the blast radius BEFORE removal — afterwards the directory is gone and the answer is
    # unrecoverable, the same reason dispose_record() reads it first.
    _dirt_ign="$(ignored_inventory "$path")"
    if ! clear_redundant_dirt "$path"; then
      echo "KEEP    $path [$branch] — could not clear proven-redundant dirt ($DIRT_BLOCKER)"
      N_KEPT=$((N_KEPT + 1)); N_REFUSED=$((N_REFUSED + 1))
      return 0
    fi
    if "$GIT_BIN" -C "$MAIN" worktree remove "$path" 2>/dev/null; then
      echo "dispose-dirt  $path [$branch] — dirt redundant with $TRUNK (re-proven at act time) · idle · landed"
      [ -n "$_dirt_ign" ] && echo "        └ gitignored content destroyed with it (git records this nowhere else): $_dirt_ign"
      N_DIRT_REMOVED=$((N_DIRT_REMOVED + 1))
      printf '%s\n' "$branch" >> "$REMOVED_BR"
    else
      echo "KEEP    $path [$branch] — git REFUSED the removal after the tree was restored"
      N_KEPT=$((N_KEPT + 1)); N_REFUSED=$((N_REFUSED + 1))
    fi
    return 0
  fi

  if [ "$DRY_RUN" = "1" ]; then
    echo "${PREFIX}remove  $path [$branch] — clean · idle · landed on $TRUNK"
    N_REMOVED=$((N_REMOVED + 1))
    printf '%s\n' "$branch" >> "$REMOVED_BR"
    return 0
  fi
  if recheck_live "$path" "$cpath"; then
    echo "KEEP    $path [$branch] — LIVE at act time ($RECHECK_WHY)"
    N_KEPT=$((N_KEPT + 1))
    return 0
  fi
  # NEVER --force: git's refusal is the second gate on our evidence.
  if "$GIT_BIN" -C "$MAIN" worktree remove "$path" 2>/dev/null; then
    echo "remove  $path [$branch] — clean · idle · landed on $TRUNK"
    N_REMOVED=$((N_REMOVED + 1))
    printf '%s\n' "$branch" >> "$REMOVED_BR"
  else
    echo "KEEP    $path [$branch] — git REFUSED 'worktree remove' (it changed since the gates ran)"
    N_KEPT=$((N_KEPT + 1)); N_REFUSED=$((N_REFUSED + 1))
  fi
}

while IFS= read -r line; do
  case "$line" in
    "worktree "*) wt="${line#worktree }"; br=""; detached=0; locked=0 ;;
    "branch refs/heads/"*) br="${line#branch refs/heads/}" ;;
    "detached") detached=1 ;;
    "locked"|"locked "*) locked=1 ;;
    "") process_record; wt=""; br=""; detached=0; locked=0 ;;
  esac
done < <({ "$GIT_BIN" -C "$MAIN" worktree list --porcelain 2>/dev/null; echo; })

# ── 3. Branches. KEPT by default; --prune-branches deletes only the provably redundant. ──
if [ "$PRUNE_BRANCHES" = "1" ]; then
  WT_BRANCHES="$("$GIT_BIN" -C "$MAIN" worktree list --porcelain 2>/dev/null | sed -n 's#^branch refs/heads/##p')"
  while IFS= read -r branch; do
    [ -n "$branch" ] || continue
    protected_branch "$branch" && continue
    # Still holding a worktree ⇒ never delete (git-worktree-guard.sh:35-44 blocks it too:
    # a vanished worktree must stay recoverable via its branch).
    if printf '%s\n' "$WT_BRANCHES" | grep -qxF "$branch"; then
      if grep -qxF "$branch" "$REMOVED_BR" 2>/dev/null; then
        echo "KEEP-BR $branch — worktree record still present"
      fi
      continue
    fi
    landed "$branch" || continue
    if [ "$DRY_RUN" = "1" ]; then
      echo "${PREFIX}delete  branch $branch — landed on $TRUNK, no worktree"
      N_BR_DELETED=$((N_BR_DELETED + 1))
      continue
    fi
    # NEVER -D: git's merged-check is the second gate; a refusal is a KEEP.
    if "$GIT_BIN" -C "$MAIN" branch -d "$branch" >/dev/null 2>&1; then
      echo "delete  branch $branch — landed on $TRUNK, no worktree"
      N_BR_DELETED=$((N_BR_DELETED + 1))
    else
      echo "KEEP-BR $branch — git REFUSED 'branch -d' (not merged into HEAD/upstream)"
      N_REFUSED=$((N_REFUSED + 1))
    fi
  done < <("$GIT_BIN" -C "$MAIN" for-each-ref --format='%(refname:short)' refs/heads/ 2>/dev/null)
fi

SUFFIX=""; [ "$DRY_RUN" = "1" ] && SUFFIX="   [DRY-RUN — nothing was mutated]"
echo "worktree-gc: removed $N_REMOVED worktree(s) · disposed $N_DISPOSED abandoned · $N_DIRT_REMOVED landed-dirt · kept $N_KEPT · deleted $N_BR_DELETED branch(es) · $N_REFUSED refusal(s)$SUFFIX"
# ── §6 R-b: the sweep's own wall-clock, against the mutex's staleness window ──────────────────────
# F-9: the lock is a bare `mkdir "$LOCK_DIR"` whose staleness test reads the dir's OWN, never
# refreshed, creation mtime (`find "$LOCK_DIR" -maxdepth 0 -mmin +60`). A pass that outruns 3,600 s
# therefore has its live lock BROKEN by the next pass, and two concurrent passes mutate worktrees —
# the GH #34645/#48927 data-loss class the mutex exists to prevent. R-b said the real duration "is
# not answerable by reading", and it is not: it has to be measured, on the real population, which
# only the scheduled sweep ever sees. So the janitor reports it and the nightly wrapper logs it.
#
# 🚨 ON ITS OWN LINE, DELIBERATELY. scripts/worktree-gc-infra-run.sh reduces the SUMMARY line
# above with `tr -cd '0-9 \n'` and `set --`, i.e. it takes its five fields POSITIONALLY. Adding
# `elapsed=` to that line would insert a sixth number and shift every field left of it — the
# unpadded-emitter defect, in the one place where a silent column shift would corrupt the
# fleet's own history. A new line cannot do that: the wrapper greps `-m1 '^worktree-gc: removed '`.
GC_ELAPSED_S=$(( $(date +%s) - GC_T0 ))
# ── THE MACHINE LINE. Named fields, so a reader can never be off by one. ─────────────────────────
# The summary line above is for humans and MUST NOT be parsed: scripts/worktree-gc-infra-run.sh
# used to reduce it with `tr -cd '0-9 \n'` and take five fields POSITIONALLY, and that reader had
# been wrong since `$N_DIRT_REMOVED landed-dirt` was inserted as the third number (§9,
# --dispose-landed-dirt). Measured on the real format: it logged landed-dirt AS kept, kept AS
# branches, branches AS refusals, and dropped the refusal count entirely — three mislabelled
# numbers in every nightly row, silently, exit 0. A positional reader over a human sentence makes
# ADDING A FIELD a breaking change to history, which is the defect, not the symptom.
# Every value is ASCII and whitespace-free so `k=v` splitting is total.
echo "worktree-gc: counts removed=$N_REMOVED disposed=$N_DISPOSED landed_dirt=$N_DIRT_REMOVED kept=$N_KEPT branches_deleted=$N_BR_DELETED refusals=$N_REFUSED elapsed=${GC_ELAPSED_S}s lock_staleness_window=3600s dry_run=$DRY_RUN"
[ "$PRUNE_BRANCHES" = "0" ] && echo "worktree-gc: branches preserved (pass --prune-branches to delete landed, worktree-less ones)"
# Absence must be LOUD: a dispose plan that cites this script has to see the class it asked about,
# whether or not it passed the flag that acts on it.
if [ "$N_DISPOSE_CAND" -gt 0 ]; then
  echo "worktree-gc: $N_DISPOSE_CAND abandoned-unlanded worktree(s) are reapable — pass --dispose-abandoned to reap them (every branch is preserved; disposals are logged to $DISPOSAL_LOG)"
fi
if [ "$N_DIRT_CAND" -gt 0 ]; then
  echo "worktree-gc: $N_DIRT_CAND dirty worktree(s) hold nothing but content already byte-identical on $TRUNK — pass --dispose-landed-dirt to reap them"
fi
# The un-ownable RESIDUE, reported as the TWO states it actually is. Reporting a count at all is
# what keeps the permanent-KEEP bucket from silently regrowing into the 2026-07-26 measurement (37
# stuck, invisible because every one was just another KEEP line among dozens) — but a single number
# spanning both states has to name one remedy for two opposite situations, and the remedy it named
# ("record the owner terminal") is actively WRONG for the owned half: marking a merely-blocked item
# `done` falsifies the ledger in order to reap a directory. Measured 2026-07-30: 6 stuck, 4 of them
# owned-and-blocked, i.e. the message was misprescribing for the majority of what it counted.
if [ "$N_UNOWNED" -gt 0 ]; then
  echo "worktree-gc: $N_UNOWNED unlanded worktree(s) are past the ${ABANDON_HOURS}h horizon with NO ownership oracle at all — nothing will ever rule on them. Land the branch, record the owner terminal (cc-backlog done <id> / tear the team down), or warrant the path explicitly:"
  echo "worktree-gc:   bash scripts/worktree-gc.sh --warrant <path> --reason '<why it is abandoned>'"
fi
if [ "$N_OWNER_ACTIVE" -gt 0 ]; then
  echo "worktree-gc: $N_OWNER_ACTIVE unlanded worktree(s) are past the ${ABANDON_HOURS}h horizon but their owner is provably NOT terminal (an open/claimed/blocked item, or a live team) — this is owned, parked work, not residue. Land it or resolve the item; do NOT mark an item done to reap a directory."
fi
if [ "$VERIFY_FAIL" -gt 0 ]; then
  echo "worktree-gc: $VERIFY_FAIL disposal(s) could NOT be verified as preserved — see $DISPOSAL_LOG" >&2
  exit 4
fi
exit 0
