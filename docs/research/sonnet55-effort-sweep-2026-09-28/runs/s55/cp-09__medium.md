Line numbers are approximate. The brief has no numbering, so I counted by hand. The quoted lines are verbatim.

**1. Pane close can target a sibling's pane**

- **What:** Pane resolution does not prefer the exact member name. It takes the first config entry matching either the full name or the "-N"-stripped name, so it can resolve to a different member's pane.
- **Where:** ~line 640, in Rule 5:
  ```
  RESOLVED=$(jq -r --args \
    '.members[]? | select(.name as $n | $ARGS.positional | index($n)) | "\(.name)\t\(.tmuxPaneId // "")"' \
    "${MEMBER_CANDIDATES[@]}" < "$CONFIG" 2>/dev/null | head -1)
  ```
- **Why it is wrong:** Suppose the teammate is `worker-2` and the team also has `worker`, listed earlier in `.members`. `MEMBER_CANDIDATES` is `(worker-2 worker)`, and `head -1` returns `worker`'s row. `PANEID` is then the sibling's pane, which `close_and_log` force-closes, while the idle teammate's own pane stays open. The header promises "CLOSE THE EXACT PANE", and this path does not.

**2. Same candidate matching can `--force`-remove a sibling's worktree**

- **What:** The by-name worktree leg matches on the stripped name and marks the result as owned.
- **Where:** ~line 405 (`resolve_by_worktree_name`) and ~line 421:
  ```
  if [[ "$base" == "$m" && -d "$wt" ]]; then printf '%s\n' "$wt"; return 0; fi
  ```
  ```
  WORKTREE_OWNED=true
  ```
- **Why it is wrong:** For teammate `worker-2` with a sibling `worker` that owns `.../worktrees/worker`, the basename matches candidate `worker`. That tree becomes `WORKTREE` with `OWNED=true`. The gates then read the sibling's tree, the checkpoint is written for it, and the final `git worktree remove "$WORKTREE" --force` deletes the sibling's live worktree. Nothing proves the tree belongs to `worker-2`. The manifest, TSV and /tmp legs share this flaw.

**3. Worktree is force-removed even when the checkpoint failed and the patch is incomplete or unwritten**

- **What:** Removal does not depend on `CHECKPOINT_OK`. The fallback patch omits untracked files, and its success is logged without checking the write.
- **Where:**
  - ~line 612: `git -C "$WORKTREE" diff HEAD 2>/dev/null || true`
  - ~line 615: `} > "$PATCH" 2>/dev/null`
  - ~line 616: `log "  ✓ fallback patch: $PATCH"`
  - ~line 780: `git -C "$MAIN_REPO" worktree remove "$WORKTREE" --force 2>/dev/null \`
  - ~line 770, the comment claiming safety: "Work is already checkpointed above, so removing the worktree here cannot lose work."
- **Why it is wrong:**
  - If `teammate-checkpoint.sh` fails, the hook still proceeds to the `--force` removal.
  - `git diff HEAD` covers tracked changes only, so untracked work in that case exists nowhere after removal.
  - If the redirect to `$PATCH` fails (unwritable /tmp, disk full), the log still says "✓ fallback patch".
  - The premise that work is preserved is never verified.

**4. Operator-adoption gate falls open when no transcript is found**

- **What:** If the transcript cannot be located, the belt does nothing and the close proceeds, even though the who-oracle never answered.
- **Where:** ~line 700 (the `_adopt_tj` block):
  ```
  _adopt_tj="$(_find_transcript "$SESSION_ID" || true)"
  ```
  followed by `if [[ -n "$_adopt_tj" ]]; then`, which has no `else`.
- **Why it is wrong:** With `SESSION_ID="unknown"` (the default for a missing payload field), or a transcript outside `PROJECT_ROOTS` with no registry alt-sid, `_adopt_tj` is empty. Control falls to the `{"continue": false}` output and the force-close. This is the same "cannot prove present, read as absent" mistake the `_beat_or_hold` comment says was fixed for the missing-lib case. The beat oracle is never consulted here.

**5. A malformed hold value silently disables the adoption gate**

- **What:** A non-numeric `CC_CLASSIFY_INTERACTIVE_HOLD_S` turns the gate off, and nothing is logged.
- **Where:** ~line 680:
  ```
  { [[ "$INTERACTIVE_HOLD_S" =~ ^[0-9]+$ ]] && (( INTERACTIVE_HOLD_S > 0 )); } || _hold_on=0
  ```
- **Why it is wrong:** An operator who sets `CC_CLASSIFY_INTERACTIVE_HOLD_S=6h` (or an empty string) meant to lengthen the hold. Instead `_hold_on=0` skips the whole who-gate, including `_beat_or_hold`, and adopted panes are force-closed. The only sanctioned kill switch is `..._HOLD_DISABLE=1`, and this path disables the gate without it and without a log line.
