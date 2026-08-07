#!/bin/bash
# shellcheck disable=SC2329,SC1083,SC2155
# teammate-checkpoint.sh — PostToolUse + Stop + TeammateIdle hook.
#
# Creates a lightweight checkpoint of teammate work using git plumbing
# (read-tree + add -A + write-tree + commit-tree) — zero impact on the
# working tree or real index, and bypasses pre-commit hooks entirely
# (never invokes `git commit`). Captures tracked modifications AND
# untracked files (honoring .gitignore).
#
# Fires on:
#   - PostToolUse: every N tool uses (default 10)
#   - Stop:        always (end of turn)
#   - TeammateIdle: always (on idle transition — invoked synchronously by
#                   teammate-auto-shutdown.sh before it reaps the worktree)
#
# Worktree conventions supported:
#   - /tmp/worktree-<team>-<member>   (legacy, from 15-agent research)
#   - /tmp/wt-<team>-<member>         (newer, per ui-sh-100p-v2 plan)
#   - /tmp/worktree-<member>          (single-segment fallback)
#
# Output refs (per worktree):
#   - refs/checkpoints/<member>/<YYYYMMDDTHHMMSSZ>   — timestamped, append-only
#   - refs/wip/<member>/LAST                         — fast-forward alias to latest
#
# Kill switch: export TEAMMATE_CHECKPOINT_DISABLED=1
# Tuning:      export TEAMMATE_CHECKPOINT_EVERY=<N>  (default 5 — tightened
#              from 10 on 2026-04-18 after Wave 2 context-exhaustion incident:
#              teammates can crash before hitting 10 PostToolUse events, so
#              the safety-net trigger needs to fire sooner. Per-fixture commit
#              cadence in the brief template remains the primary defense.)
#              export TEAMMATE_CHECKPOINT_RETAIN_DAYS=<N>  (GC age rule, default 14)
#              export TEAMMATE_CHECKPOINT_KEEP=<N>         (GC rank cap per member, default 50)

set -uo pipefail

if [[ "${TEAMMATE_CHECKPOINT_DISABLED:-0}" == "1" ]]; then
  exit 0
fi

readonly EVERY="${TEAMMATE_CHECKPOINT_EVERY:-5}"
readonly WATCHDOG_DIR="$HOME/.claude/watchdog"
readonly LOG_FILE="$HOME/.claude/logs/teammate-checkpoint.log"
# GC retention (see the damped-GC block below for why each is the shape it is)
readonly GC_DAYS="${TEAMMATE_CHECKPOINT_RETAIN_DAYS:-14}"   # age rule
readonly GC_KEEP="${TEAMMATE_CHECKPOINT_KEEP:-50}"          # rank cap, per member
readonly GC_FLOOR=3                                         # newest-per-member, always immortal

mkdir -p "$WATCHDOG_DIR" "$(dirname "$LOG_FILE")" 2>/dev/null || true

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE" 2>/dev/null || true
}

# Parse hook JSON stdin
INPUT=$(cat 2>/dev/null || echo '{}')
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null || echo 'unknown')
EVENT=$(echo "$INPUT" | jq -r '.hook_event_name // "?"' 2>/dev/null || echo '?')
CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || echo '')
[[ -z "$CWD" ]] && CWD="$PWD"
# Prefer names from payload — Claude Code provides these for TeammateIdle;
# teammate-auto-shutdown.sh also populates them in its synthetic payload.
PAYLOAD_TEAM=$(echo "$INPUT" | jq -r '.team_name // empty' 2>/dev/null || echo '')
PAYLOAD_MEMBER=$(echo "$INPUT" | jq -r '.teammate_name // empty' 2>/dev/null || echo '')

# Normalize /private/tmp → /tmp (macOS realpath quirk)
CWD="${CWD#/private}"

# Only act in a worktree or repo we manage. Gate on git-common-dir (discovery
# §4 #4) so the checkpoint covers the repo ROOT + ~/Development/.worktrees, not
# just /tmp/wt-* — otherwise solo-root and Track-R worktree sessions are a
# permanent recovery blind spot. The clean-tree skip below prevents over-firing.
case "$CWD" in
  /tmp/worktree-*|/tmp/wt-*) ;;                 # legacy + current teammate paths
  "$HOME"/Development/.worktrees/*) ;;          # Track R worktrees (branch-named)
  *)
    # Any other dir: act only if it is inside a git working tree (root or
    # linked worktree). --git-common-dir resolves for both; fails elsewhere.
    git -C "$CWD" rev-parse --git-common-dir >/dev/null 2>&1 || exit 0
    ;;
esac

# Skip mid-rebase/merge — avoid corrupting in-flight git operations
if [[ -d "$CWD/.git/rebase-merge" || -d "$CWD/.git/rebase-apply" || -f "$CWD/.git/MERGE_HEAD" ]]; then
  log "skip $CWD: rebase/merge in progress"
  exit 0
fi

# ── Damped GC (audit 09 D-10; re-derived 2026-08-06, cc-backlog 700269d9c450) ────────────────
# This hook is the fixed per-tool-call tax (`matcher: ""` = every tool, every session) and it GC'd
# nothing, unlike memory-nudge.sh:26 (`-mtime +1 -delete`) or completion-assert.sh (`.fired`,
# `-mtime +7`): 76 orphan cp-*.count files were live and this repo alone exceeded 1000 append-only
# refs/checkpoints/** refs — a measurable git cost on every ref walk.
#
# THE RE-DERIVATION. That sweep landed and the store STILL reached 6,101 refs / 613 KB packed-refs.
# Three defects, each measured here rather than inferred:
#
#  (1) THE SWEEP NEVER FINISHED — the load-bearing one. settings.json registers this hook with
#      `"timeout": 10`, and the old loop forked one `git update-ref -d` per ref, each rewriting the
#      whole packed-refs file under its lock. Measured on a 6,000-ref / 417 KB-packed-refs repo:
#      500 sequential deletes = 5.69 s vs 0.128 s for the same 500 batched through
#      `update-ref --stdin` — 44x. The live sweep needed ~669, so it was SIGKILLed at 10 s daily:
#      the log shows 449 drops spanning 22:55:17→22:55:26 on 2026-08-06 and no completion line, and
#      only 3 `gc: swept` lines exist in 19 MB of log (2026-07-29..07-31, when the store was still
#      small enough to finish). A second, independent failure rode along and was invisible: a
#      `packed-refs.lock` contended by ~20 concurrent sessions makes a delete fail, and `&& log`
#      swallowed it silently — which is why the survivors are not the clean order-suffix that pure
#      truncation would leave. The two are NOT separated here; batching collapses both, since one
#      transaction takes the lock once. Because the stamp is taken FIRST, a truncated sweep also
#      blocked retry for 24 h, so capacity (~449/day) sat BELOW production (~576/day) and the store
#      grew monotonically.
#      → deletions are now ONE batched transaction, and a failed batch is LOGGED, never swallowed.
#        Verified: deleting a ref a sibling already removed is a no-op at rc 0, so a concurrent
#        session cannot abort the transaction.
#
#  (2) THE DAMPER WAS MACHINE-WIDE. One `.gc-stamp` for the box meant the first session to fire in
#      ANY repo consumed the day's sweep for EVERY repo (the 2026-07-31 sweep ran with CWD in a
#      worktree; claude-infrastructure simply went unswept). The stamp is now keyed on the producing
#      directory via parameter expansion, so the common path still costs no extra fork.
#
#  (3) AGE ALONE CANNOT BOUND A HIGH-RATE MEMBER. A session working at a repo ROOT keys on the repo
#      basename, so ~20 concurrent sessions shared ONE member: `claude-infrastructure` held 2,630 of
#      the 6,101 refs, all INSIDE the 14-day window where the age rule cannot reach them (14 d x
#      24 refs/h = 8,064 for a single member). A rank cap now bounds each member; measured against
#      the live store, cap 50 takes it 6,101 → 3,401 and the worst member 2,630 → 50.
#
# NOT CHANGED, deliberately. The `*)` arm above still checkpoints a repo ROOT: 263ba715 widened it
# on purpose so solo-root sessions are not a permanent recovery blind spot, and the bloat was never
# caused by its breadth — it was caused by (1). Bound the store, keep the coverage. Also measured
# and NOT acted on: `:status --porcelain | grep -q .` is the pipefail early-exit shape, but it does
# not invert here (0/40 false-cleans at 5, 200 and 1,500 dirty files — porcelain output stays under
# the 64 KB pipe buffer, so git never blocks and is never SIGPIPEd), and no ref in the live store is
# older than 30 days, so a hard ceiling above the newest-N floor would collect nothing today.
#
# Damped to at most once/day at ONE fork on the common path: `find` tests existence AND age in a
# single process, so an already-swept stamp (<1 day) prints its own path and we skip immediately.
# Key = the sanitized producing dir, right-truncated to stay inside NAME_MAX (255 here; ".gc-stamp"
# + 180 = 189). The length test is EXPLICIT and not `${GC_KEY: -180}` alone: in bash a negative
# offset larger than the string expands to the EMPTY string (zsh returns the whole string, which is
# how the first cut of this passed a zsh spot-check and shipped inert — every directory keyed to a
# bare `.gc-stamp`, i.e. exactly the machine-wide damper this replaces). Two dirs sharing a 180-char
# tail would share a damper, which is the old behaviour for those two only — never machine-wide.
GC_KEY="${CWD//\//-}"
(( ${#GC_KEY} > 180 )) && GC_KEY="${GC_KEY: -180}"
GC_STAMP="$WATCHDOG_DIR/.gc-stamp$GC_KEY"
if [[ -z "$(find "$GC_STAMP" -mtime -1 2>/dev/null)" ]]; then
  : > "$GC_STAMP" 2>/dev/null || true   # stamp FIRST — a failing sweep must not retry every call
  # (a) orphan per-session counters — a crashed or reaped teammate never reaches a session-end
  #     path, so this is the belt for everything session-end misses. Per-directory stamps are swept
  #     on the same pass at a much longer age (a retired worktree stops sweeping and its stamp is
  #     then pure litter); +30d can never reap the stamp this run just took, and a live dir re-touches
  #     its own stamp daily. The glob is deliberately wide enough to also collect the pre-2026-08-06
  #     machine-wide `.gc-stamp`, which no code writes any more.
  find "$WATCHDOG_DIR" -maxdepth 1 -name 'cp-*.count' -mtime +2 -delete 2>/dev/null || true
  find "$WATCHDOG_DIR" -maxdepth 1 -name '.gc-stamp*' -mtime +30 -delete 2>/dev/null || true
  # (b) checkpoint refs — a ref survives iff it is one of the newest GC_FLOOR for its member
  #     (respawn needs a recent snapshot however stale the worktree), else it must clear BOTH the
  #     age rule and the per-member rank cap. Ref names carry a fixed-width UTC stamp, so
  #     `--sort=-refname` is newest-first per member in a single pass.
  GC_CUTOFF=$(( $(date -u +%s) - GC_DAYS * 86400 ))
  GC_PREV=""; GC_KEPT=0; GC_DEL=0; GC_BATCH=""
  while IFS=' ' read -r _rn _rd; do
    [[ -n "$_rn" ]] || continue
    case "$_rd" in ''|*[!0-9]*) _rd=0 ;; esac
    _m="${_rn#refs/checkpoints/}"; _m="${_m%/*}"
    if [[ "$_m" != "$GC_PREV" ]]; then GC_PREV="$_m"; GC_KEPT=0; fi
    GC_KEPT=$((GC_KEPT + 1))
    (( GC_KEPT <= GC_FLOOR )) && continue
    # delete iff over the rank cap OR past the age cutoff; otherwise it survives
    (( GC_KEPT > GC_KEEP )) || [[ "$_rd" -lt "$GC_CUTOFF" ]] || continue
    GC_BATCH+="delete $_rn"$'\n'
    GC_DEL=$((GC_DEL + 1))
  done <<EOF
$(git -C "$CWD" for-each-ref --sort=-refname --format='%(refname) %(committerdate:unix)' refs/checkpoints/ 2>/dev/null)
EOF
  if (( GC_DEL > 0 )); then
    if printf '%s' "$GC_BATCH" | git -C "$CWD" update-ref --stdin 2>/dev/null; then
      log "gc: dropped $GC_DEL refs in $CWD (rank>$GC_KEEP or age>${GC_DAYS}d, keep $GC_FLOOR/member)"
    else
      log "WARN: gc batch delete FAILED for $GC_DEL refs in $CWD"   # never swallow it — see (1)
    fi
  fi
  log "gc: swept $WATCHDOG_DIR cp-*.count (>2d) + $CWD checkpoint refs (>${GC_DAYS}d or rank>$GC_KEEP, keep $GC_FLOOR/member): $GC_DEL dropped"
fi

# Per-session counter (avoid collisions across parallel teammates)
COUNTER_FILE="$WATCHDOG_DIR/cp-$SESSION_ID.count"
COUNT=0
[[ -f "$COUNTER_FILE" ]] && COUNT=$(cat "$COUNTER_FILE" 2>/dev/null || echo 0)

# Always checkpoint on Stop + TeammateIdle; otherwise every EVERY tool uses
SHOULD_SNAPSHOT=false
case "$EVENT" in
  Stop|TeammateIdle)
    SHOULD_SNAPSHOT=true
    ;;
  *)
    COUNT=$((COUNT + 1))
    echo "$COUNT" > "$COUNTER_FILE"
    if (( COUNT % EVERY == 0 )); then
      SHOULD_SNAPSHOT=true
    fi
    ;;
esac

$SHOULD_SNAPSHOT || exit 0

# Only snapshot if there's something to snapshot
if ! git -C "$CWD" status --porcelain 2>/dev/null | grep -q .; then
  log "no checkpoint needed for $CWD — tree clean"
  exit 0
fi

# Derive member name. Preference order:
#   1. PAYLOAD_MEMBER from hook JSON (Claude Code native events + our synthetic payload)
#   2. Strip PAYLOAD_TEAM prefix from the basename ("wt-<team>-<member>" → "<member>")
#   3. Parse from basename using convention
#
# Conventions for step 3:
#   /tmp/worktree-<team>-<member>  — legacy ("worktree-" prefix, team slug)
#   /tmp/wt-<team>-<member>        — newer ("wt-" prefix, team slug like "ui-sh-v2")
#   /tmp/worktree-<member>         — single-segment (no team prefix)
BASENAME=$(basename "$CWD")
if [[ -n "$PAYLOAD_MEMBER" ]]; then
  MEMBER="$PAYLOAD_MEMBER"
elif [[ -n "$PAYLOAD_TEAM" ]]; then
  # Strip either "wt-<team>-" or "worktree-<team>-" prefix
  MEMBER="$BASENAME"
  # quote the expansion separately: unquoted it is a glob PATTERN, so a team name carrying
  # *, ?, [ ] would strip the wrong prefix (or none at all)
  MEMBER="${MEMBER#wt-"$PAYLOAD_TEAM"-}"
  MEMBER="${MEMBER#worktree-"$PAYLOAD_TEAM"-}"
else
  # Last-resort fallback: strip prefix + assume single-segment member.
  # For multi-segment conventions, the caller should pass PAYLOAD_TEAM.
  case "$BASENAME" in
    wt-*) MEMBER="${BASENAME#wt-}" ;;
    worktree-*) MEMBER="${BASENAME#worktree-}" ;;
    *) MEMBER="$BASENAME" ;;
  esac
fi
[[ -z "$MEMBER" ]] && MEMBER="$BASENAME"

TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)
MSG="checkpoint: ${EVENT} count=${COUNT} ts=${TIMESTAMP}"

# Snapshot BOTH tracked modifications AND untracked files (respecting .gitignore)
# via a temp index — zero impact on the teammate's working tree or real index.
# (git stash create alone misses untracked files; new files a teammate writes
# would be lost on a crash, defeating the point.)
HEAD_SHA=$(git -C "$CWD" rev-parse HEAD 2>/dev/null || echo "")
if [[ -z "$HEAD_SHA" ]]; then
  log "no HEAD for $CWD — skipping checkpoint"
  exit 0
fi

TMP_INDEX=$(mktemp)
# If anything fails, drop the temp index — we never touch the real one
cleanup_index() { rm -f "$TMP_INDEX"; }
trap cleanup_index EXIT

CHECKPOINT_SHA=$(
  GIT_INDEX_FILE="$TMP_INDEX" git -C "$CWD" read-tree HEAD 2>/dev/null &&
  GIT_INDEX_FILE="$TMP_INDEX" git -C "$CWD" add -A 2>/dev/null &&
  TREE=$(GIT_INDEX_FILE="$TMP_INDEX" git -C "$CWD" write-tree 2>/dev/null) &&
  [[ -n "$TREE" && "$TREE" != "$(git -C "$CWD" rev-parse HEAD^{tree} 2>/dev/null)" ]] &&
  git -C "$CWD" commit-tree "$TREE" -p "$HEAD_SHA" -m "$MSG" 2>/dev/null
) || CHECKPOINT_SHA=""

if [[ -z "$CHECKPOINT_SHA" ]]; then
  log "no checkpoint needed for $CWD — tree matches HEAD"
  exit 0
fi

# Record under refs/checkpoints/<member>/<timestamp> so `git reflog` can list them
TS_REF="refs/checkpoints/$MEMBER/$TIMESTAMP"
LAST_REF="refs/wip/$MEMBER/LAST"

if git -C "$CWD" update-ref "$TS_REF" "$CHECKPOINT_SHA" 2>/dev/null; then
  log "checkpoint $CWD $MEMBER $EVENT count=$COUNT sha=$CHECKPOINT_SHA ref=$TS_REF"
  # Fast-forward the LAST alias too (O(1) "give me the latest" for respawn)
  git -C "$CWD" update-ref "$LAST_REF" "$CHECKPOINT_SHA" 2>/dev/null \
    && log "  → fast-forwarded $LAST_REF"
else
  log "WARN: update-ref failed for $TS_REF"
fi

exit 0
