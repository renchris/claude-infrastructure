Reviewing the hook text only, as instructed. Findings below.

**Defect 1 — the stripped base-name candidate can select a sibling member's pane and worktree**

- What: MEMBER_CANDIDATES includes the trailing "-N"-stripped name, and the pane and worktree resolvers match any candidate in file order, so an auto-incremented member can resolve to the sibling whose existence caused the increment.
- Where:
  ```
  MEMBER_CANDIDATES+=("${BASH_REMATCH[1]}")
  ```
  ```
  '.members[]? | select(.name as $n | $ARGS.positional | index($n)) | "\(.name)\t\(.tmuxPaneId // "")"' \
  ```
  ```
  if [[ "$base" == "$m" && -d "$wt" ]]; then printf '%s\n' "$wt"; return 0; fi
  ```
- Why it is wrong: a member is named `quality-keeper-2` precisely because `quality-keeper` already exists on the team. The jq select matches whichever config member appears first, and `head -1` keeps it, so if `quality-keeper` is listed before `quality-keeper-2` the hook records the sibling's `tmuxPaneId` and force-closes the sibling's live pane. Likewise `resolve_by_worktree_name` iterates git's worktree list in git order and returns the first basename matching any candidate, so `WORKTREE` can become the sibling's dedicated tree with `WORKTREE_OWNED=true`, and the detached block then runs `git worktree remove --force` on it. This contradicts the file's stated invariant that a forced close can never hit the wrong pane.

**Defect 2 — the operator-adoption belt silently falls open when no transcript is found**

- What: when `_find_transcript` yields nothing (including the `SESSION_ID` default of `unknown`), the who-oracle is never consulted and the code proceeds straight to the close.
- Where:
  ```
  if [[ -n "$_adopt_tj" ]]; then
  ```
- Why it is wrong: the block has no else arm. A teammate whose session id is missing from the payload, whose transcript lives under a root not in `PROJECT_ROOTS`, or whose pane UUID is not in the `cc-sessions` registry produces an empty `_adopt_tj`, and the hook then emits `{"continue": false}` and force-closes the pane with zero who-evidence. The comments define this exact case as "the WHO-oracle could not answer" and route it to `_beat_or_hold`, yet the code only calls `_beat_or_hold` for the absent-lib case. Note `_tool_in_flight` also returns "not in flight" for the same unknown/missing-transcript inputs, so both transcript-based gates are skipped together.

**Defect 3 — the worktree is force-removed even when the checkpoint failed, and the fallback patch does not carry untracked files**

- What: worktree removal is gated only on `WORKTREE_OWNED`, not on `CHECKPOINT_OK`, while the fallback patch contains only tracked changes.
- Where:
  ```
  git -C "$WORKTREE" diff HEAD 2>/dev/null || true
  ```
  ```
  if [[ -n "$WORKTREE" ]] && $WORKTREE_OWNED; then
  ```
  ```
  git -C "$MAIN_REPO" worktree remove "$WORKTREE" --force 2>/dev/null \
  ```
- Why it is wrong: when `teammate-checkpoint.sh` fails (the header's own "corrupt repo, permission issue" case), the only preserved artifact is the patch, whose header tells the reader to "rely on this patch". That patch is `git diff HEAD`, which omits every untracked file. Three seconds later `--force` removal deletes the tree, so any new files the teammate created are lost. The comment on the detached block, "Work is already checkpointed above, so removing the worktree here cannot lose work", is false on the `CHECKPOINT_OK=false` path that the code deliberately continues through.

**Defect 4 — the fallback patch is reported as written regardless of whether the write succeeded**

- What: the success log line is unconditional after a redirection whose failure is discarded.
- Where:
  ```
  } > "$PATCH" 2>/dev/null
  log "  ✓ fallback patch: $PATCH"
  ```
- Why it is wrong: if `/tmp` is unwritable or the redirection fails for any reason, the block is not executed and nothing is written, but the log still reports a recoverable trace exists. Combined with Defect 3, the operator is told a dirty tree was preserved right before it is force-removed.

**Defect 5 — the session id is taken from the hook payload, which on the lead-side model is the lead's session**

- What: `SESSION_ID` is treated as the idle teammate's session for the transcript gates and the teardown marker, but the header states the hook fires on the lead, whose payload `session_id` is the lead's.
- Where:
  ```
  SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null)
  ```
  ```
  write_teardown_marker "$pane" "${SESSION_ID:-}" teammate-idle
  ```
- Why it is wrong: on any run where the payload session is the lead's, `_tool_in_flight` and `ci_last_interactive_epoch` read the lead's transcript, so a recent operator prompt to the lead holds every teammate, or a lead mid-tool_use defers every teammate. Worse, `write_teardown_marker` writes `<lead-sid>.json` with `mode=teammate-idle`, which the file's own comment says will mask a genuine crash of that session. The code never reconciles the payload session with the teammate identified by `--agent-id`. I cannot confirm from the text which model produces which session id, but the file asserts the lead-side case exists.

**Defect 6 — the shared-cwd SURFACE misreports how many reap-guard defers occurred**

- What: the reap-guard shared-cwd arm shares `DEFER_COUNT` with the dirty-tree defers, so it can SURFACE on its first visit while logging that reap-guard deferred `MAX_DEFERS` times.
- Where:
  ```
  if (( DEFER_COUNT + 1 < MAX_DEFERS )); then
  ```
  ```
  log "⚑ SURFACE $TEAMMATE_NAME (team=$TEAM_NAME): reap-guard has deferred $MAX_DEFERS times on a SHARED cwd ($WORKTREE) — ...
  ```
- Why it is wrong: two dirty-tree defers bring `DEFER_COUNT` to 2. On the third event the dirty gate passes through, reap-guard defers once on a shared cwd, and the arithmetic immediately takes the SURFACE branch. The page and log state that reap-guard deferred three times, which is not what happened, and the operator is paged for a condition that was checked exactly once.
