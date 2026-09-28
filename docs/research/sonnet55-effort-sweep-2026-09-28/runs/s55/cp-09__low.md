I found six defects. I had no line-number tooling, so the line numbers are approximate (±a few lines) and the code lines are verbatim.

**1. The pane lookup can select the wrong member and close another teammate's pane.**
- **Where:** about line 590, `'.members[]? | select(.name as $n | $ARGS.positional | index($n)) | "\(.name)\t\(.tmuxPaneId // "")"' \` followed by `"${MEMBER_CANDIDATES[@]}" < "$CONFIG" 2>/dev/null | head -1)`
- **Why it is wrong:** `MEMBER_CANDIDATES` holds both `quality-keeper-2` and the stripped `quality-keeper`. The filter matches either name and `head -1` takes the first member in config order. When both `quality-keeper` and `quality-keeper-2` exist and the base name is listed first, an idle event for `-2` resolves to the base member's `tmuxPaneId`. The hook then force-closes a different live teammate's pane, and the marker and log name the wrong member.
- **Same pattern elsewhere:** `resolve_from_manifest` (`for m in "${MEMBER_CANDIDATES[@]}"; do` inside the manifest loop) and `resolve_by_worktree_name` (`if [[ "$base" == "$m" && -d "$wt" ]]; then printf '%s\n' "$wt"; return 0; fi`) also take the first entry matching any candidate, not the exact name. They can pick the sibling's worktree, which is then marked owned and removed.

**2. The operator-adoption gate closes the pane when the transcript cannot be found.**
- **Where:** about line 745, `if [[ -n "$_adopt_tj" ]]; then` (the block has no `else`).
- **Why it is wrong:** the lib is present but `_find_transcript` finds nothing, for example because the session lives under an unlisted project root. Nothing is checked, and control falls through to the `{"continue": false}` output and `close_and_log`. "Could not locate the evidence" is treated as "nobody typed". This is the same absence-as-license premise that the lib-absent and unreadable branches explicitly refuse, and it can force-close an operator-adopted pane.

**3. A failed fallback-patch write is logged as a success.**
- **Where:** about lines 705–715, `} > "$PATCH" 2>/dev/null` followed by `log "  ✓ fallback patch: $PATCH"`
- **Why it is wrong:** if the redirect fails (unwritable or full `/tmp`), the block does not run and no patch exists. The log line still reports "✓ fallback patch" unconditionally. Nothing checks that the file was created or is non-empty.

**4. The worktree is force-removed after a failed checkpoint, and after a failed pane close.**
- **Where:** about line 850, `git -C "$MAIN_REPO" worktree remove "$WORKTREE" --force 2>/dev/null \`, guarded only by `if [[ -n "$WORKTREE" ]] && $WORKTREE_OWNED; then`
- **Why it is wrong:** the comment says "Work is already checkpointed above", but `CHECKPOINT_OK` can be false. The fallback patch contains only tracked changes (`git diff HEAD`), so untracked files are lost on `--force` removal. The removal also runs when `close_pane` failed. In that case the session is still alive and its worktree is deleted under it.

**5. `pipefail` can defeat the tool-in-flight "already returned" check.**
- **Where:** about lines 386–388, `| grep -qxF "$tu_id" && return 1`
- **Why it is wrong:** the script sets `pipefail`. If `grep -q` matches and exits early, `jq` can be killed by SIGPIPE (status 141), so the pipeline status is non-zero. The `&& return 1` is then skipped and the function returns 0, reporting a finished tool call as still in flight. The result depends on timing. The teammate is then deferred instead of reaped, unboundedly and without counting against `MAX_DEFERS`.

**6. A malformed hold setting silently disables the adoption gate.**
- **Where:** about line 715, `{ [[ "$INTERACTIVE_HOLD_S" =~ ^[0-9]+$ ]] && (( INTERACTIVE_HOLD_S > 0 )); } || _hold_on=0`
- **Why it is wrong:** a typo such as `CC_CLASSIFY_INTERACTIVE_HOLD_S=6h` or `=0` sets `_hold_on=0`, skipping both presence oracles, with no log line. Adopted panes are then force-closed as if the kill switch had been thrown, but nothing records it.
