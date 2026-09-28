I found four defects. Line numbers were counted by hand from the pasted text. Those after about line 640 may be off by a few lines, but the quoted text is verbatim.

**1. A transcript that cannot be found skips the operator-adoption gate, and the pane is closed.**
- **What:** When the WHO-oracle lib is present but no transcript is located, no hold, page or beat check runs, and control falls through to the force-close.
- **Where:** about lines 895–901:
  - `_adopt_tj="$(_find_transcript "$SESSION_ID" || true)"`
  - `if [[ -n "$_adopt_tj" ]]; then`
  - There is no `else` branch. `_beat_or_hold` has a single call site, in the lib-absent branch.
- **Why it is wrong:** `_find_transcript` fails when `SESSION_ID` is the default `"unknown"`, when the transcript is not under `PROJECT_ROOTS`, or when the file is gone. The alternate-sid lookup through `cc-sessions` can also come back empty. In each case `_adopt_tj` is empty, the `if` is skipped, and the hook emits `{"continue": false}` and closes the pane. That is the "cannot prove absent, so treat as absent" case the file's own comments say must fail closed. The same fall-through happens when `ci_last_interactive_epoch` exits with a code other than 0, 1 or 2, or exits 0 with a non-numeric value. The `[[ "$_iep" =~ ^[0-9]+$ ]]` test then skips the check.

**2. The auto-increment name fallback can select a sibling member, so the wrong pane is closed or the wrong worktree is force-removed.**
- **What:** `MEMBER_CANDIDATES` holds both the full name and the `-N`-stripped name. Three resolvers walk members or worktrees in outer-loop order and take the first match for either candidate, without preferring the exact name.
- **Where:**
  - Line ≈819–821, the pane lookup: `RESOLVED=$(jq -r --args \` with the filter `.members[]? | select(.name as $n | $ARGS.positional | index($n)) | ...` and `head -1`.
  - Line ≈460–461, the manifest lookup: `for m in "${MEMBER_CANDIDATES[@]}"; do` inside the outer members loop, then `if [[ "$name" == "$m" ]]; then`.
  - Line ≈518–520, the worktree-name lookup: the outer `while read line` loop, then `if [[ "$base" == "$m" && -d "$wt" ]]; then`.
- **Why it is wrong:** Take teammate `quality-keeper-2` while a member or worktree named `quality-keeper` also exists and is listed first. The first result is the sibling's entry, not the idle teammate's. The pane lookup then returns the sibling's `tmuxPaneId`, and `close_and_log` force-closes that live pane. The manifest and worktree-name paths return the sibling's worktree with `WORKTREE_OWNED=true`. That worktree is then `git worktree remove --force`d.

**3. The worktree is force-removed even when the checkpoint failed, and the fallback patch omits untracked files.**
- **What:** The removal does not depend on `CHECKPOINT_OK`. The fallback patch covers tracked changes only.
- **Where:**
  - About line 980: `git -C "$MAIN_REPO" worktree remove "$WORKTREE" --force 2>/dev/null \`
  - Line ≈800–801: `echo "# --- diff HEAD (tracked changes only) ---"` and `git -C "$WORKTREE" diff HEAD 2>/dev/null || true`
  - The comment ahead of the detached block: "Work is already checkpointed above, so removing the worktree here cannot lose work."
- **Why it is wrong:** If `teammate-checkpoint.sh` fails (line ≈785, `log "  ✗ checkpoint failed for $WORKTREE — writing fallback patch"`), the code still goes on to remove the worktree with `--force`. Untracked files are then gone permanently, since they are absent from `git diff HEAD` and were never checkpointed. The comment's premise is false in that case.
- **Related:** The patch write at line ≈802 is `} > "$PATCH" 2>/dev/null`, and line ≈803 logs `✓ fallback patch` unconditionally. A failed write is reported as a success.

**4. Under `pipefail`, `grep -q` can turn a positive result into a negative one.**
- **What:** `set -o pipefail` is on, and `grep -q` exits at its first match. If the upstream command is still writing, it dies of SIGPIPE and the pipeline returns 141, so the `if` or `&&` sees failure.
- **Where:**
  - Line ≈642: `if git -C "$WORKTREE" status --porcelain 2>/dev/null | grep -q .; then`
  - Line ≈790: `if git -C "$WORKTREE" status --porcelain 2>/dev/null | grep -q .; then`
  - Line ≈397: `| grep -qxF "$tu_id" && return 1`
- **Why it is wrong:** With a large `status --porcelain` output, for example many untracked files, `git` writes more than the first buffer after `grep` has already exited. The pipeline status becomes non-zero, so a dirty tree is read as clean:
  - `TREE_DIRTY` stays `false`, so the dirty-tree defer is skipped and a mid-work teammate is reaped.
  - No fallback patch is written.
  - In `_tool_in_flight`, a matching `tool_result` that was found still fails to `return 1`. The function then reports the tool as in flight.
