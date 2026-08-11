I found 19 defects. Line numbers count the shebang as line 1.

1. **What** — The iTerm2 resolver can select the unpatched system CLI even though the code requires the local force-close shim.

   **Where** — Line 100:

   ```bash
   _it2_bin() { command -v it2 2>/dev/null || echo "$HOME/.claude/bin/it2"; }
   ```

   **Why it is wrong** — If another `it2` appears earlier in `PATH`, `command -v` returns it instead of the required shim; as the preceding comments explain, that CLI can prompt rather than force-close, leaving the pane open or timing out.

2. **What** — Stripping a numeric suffix makes the pane resolver capable of selecting a different, unsuffixed teammate.

   **Where** — Lines 420–423 and 794–796:

   ```bash
   MEMBER_CANDIDATES=("$TEAMMATE_NAME")
   if [[ "$TEAMMATE_NAME" =~ ^(.+)-[0-9]+$ ]]; then
     MEMBER_CANDIDATES+=("${BASH_REMATCH[1]}")
   fi
   ```

   ```bash
     RESOLVED=$(jq -r --args \
       '.members[]? | select(.name as $n | $ARGS.positional | index($n)) | "\(.name)\t\(.tmuxPaneId // "")"' \
       "${MEMBER_CANDIDATES[@]}" < "$CONFIG" 2>/dev/null | head -1)
   ```

   **Why it is wrong** — For `worker-2` in a config containing both `worker` and `worker-2`, the query selects both and `head -1` follows config order, so it can resolve and close `worker`’s pane.

3. **What** — The same suffix fallback can resolve an auto-incremented teammate to the unsuffixed teammate’s worktree and mark it removable.

   **Where** — Lines 501–503 and 524–526:

   ```bash
       base="${wt##*/}"
       for m in "${MEMBER_CANDIDATES[@]}"; do
         if [[ "$base" == "$m" && -d "$wt" ]]; then printf '%s\n' "$wt"; return 0; fi
   ```

   ```bash
       if NAMED_WT=$(resolve_by_worktree_name "$_seed"); then
         WORKTREE="$NAMED_WT"
         WORKTREE_OWNED=true
   ```

   **Why it is wrong** — If `worker`’s worktree is enumerated before `worker-2`’s, a shutdown for `worker-2` returns `worker` through the stripped candidate and later checkpoints and force-removes the wrong worktree.

4. **What** — The global `/tmp` fallback treats a member-name suffix as proof of ownership despite not checking the team or repository.

   **Where** — Lines 568–572:

   ```bash
     for m in "${MEMBER_CANDIDATES[@]}"; do
       for candidate in /tmp/wt-*-"${m}" /tmp/worktree-*-"${m}"; do
         if [[ -d "$candidate" ]]; then
           WORKTREE="$candidate"        # per-member path ⇒ dedicated
           WORKTREE_OWNED=true
   ```

   **Why it is wrong** — If two teams have a member with the same name and their team slugs differ from `TEAM_NAME`, glob order can select the other team’s directory, which is then treated as owned and may be force-removed.

5. **What** — The pane resolver accepts the first nonempty pane ID without determining which duplicate team configuration is live.

   **Where** — Lines 791–801:

   ```bash
   for _root in "${TEAM_ROOTS[@]}"; do
     CONFIG="$_root/$TEAM_NAME/config.json"
     [[ -f "$CONFIG" ]] || continue
     RESOLVED=$(jq -r --args \
       '.members[]? | select(.name as $n | $ARGS.positional | index($n)) | "\(.name)\t\(.tmuxPaneId // "")"' \
       "${MEMBER_CANDIDATES[@]}" < "$CONFIG" 2>/dev/null | head -1)
     if [[ -n "$RESOLVED" && "$RESOLVED" == *$'\t'* ]]; then
       MEMBER_NAME="${RESOLVED%%$'\t'*}"
       PANEID="${RESOLVED#*$'\t'}"
       [[ -z "$MEMBER_NAME" ]] && MEMBER_NAME="$TEAMMATE_NAME"
       [[ -n "$PANEID" ]] && break
   ```

   **Why it is wrong** — When an earlier root contains a stale but nonempty ID and a later root contains the live ID, the stale one wins; an iTerm2 close then misses the target, while a recycled tmux `%N` can identify and kill an unrelated pane.

6. **What** — Shared-worktree occupancy compares a normalized selected path against unnormalized config paths and can therefore mark a shared directory as owned.

   **Where** — Lines 594–602:

   ```bash
       cfg_cwd=$(jq -r --arg m "$m" '.members[]? | select(.name==$m) | .cwd // empty' "$TEAM_CONFIG" 2>/dev/null | head -1)
       cfg_cwd="${cfg_cwd#/private}"
   ```

   ```bash
       _occupants=$(jq -r --arg c "$cfg_cwd" '[.members[]? | select((.cwd // "") == $c)] | length' "$TEAM_CONFIG" 2>/dev/null)
       if [[ "$_occupants" == "1" ]]; then
         WORKTREE_OWNED=true
   ```

   **Why it is wrong** — If one member records `/tmp/x` and another records the equivalent `/private/tmp/x`, only the first string is counted, so `_occupants` becomes `1` and the shared directory is eligible for force-removal.

7. **What** — Both dirty-tree checks interpret errors from `git status` as a clean tree.

   **Where** — Lines 44, 624, and 765:

   ```bash
   set -uo pipefail
   ```

   ```bash
     if git -C "$WORKTREE" status --porcelain 2>/dev/null | grep -q .; then
   ```

   ```bash
     if git -C "$WORKTREE" status --porcelain 2>/dev/null | grep -q .; then
   ```

   **Why it is wrong** — A corrupt repository, permission error, or a sufficiently large output that makes `git` receive SIGPIPE after `grep -q` exits yields a nonzero pipeline status; the code then skips both the dirty defer and the fallback-patch block.

8. **What** — The tool-in-flight predicate only recognizes a tool call when the transcript’s final record is the originating assistant record.

   **Where** — Lines 374–385:

   ```bash
     last_rec="$(tail -n 1 "$f" 2>/dev/null)"
     [[ -n "$last_rec" ]] || return 1
     printf '%s' "$last_rec" \
       | jq -e '.type=="assistant" and ((.message.content // []) | map(select(.type=="tool_use")) | length > 0)' \
         >/dev/null 2>&1 || return 1
     tu_id="$(printf '%s' "$last_rec" \
       | jq -r '(.message.content // []) | map(select(.type=="tool_use")) | last | .id // empty' 2>/dev/null)"
     if [[ -n "$tu_id" ]]; then
       # a matching tool_result anywhere ⇒ the tool returned ⇒ not in flight
       jq -rc 'select(.type=="user") | (.message.content // []) | if type=="array" then .[] else empty end
               | select(.type=="tool_result") | .tool_use_id // empty' "$f" 2>/dev/null \
         | grep -qxF "$tu_id" && return 1
   ```

   **Why it is wrong** — A progress record appended during a long-running tool, or a result for one call while another parallel call remains outstanding, makes the last record non-assistant and the function reports no tool in flight, allowing a live worker to be closed.

9. **What** — Special handling for an unowned/shared worktree runs only when `reap-guard` rejects, so a successful result from the wrong checkout is accepted as evidence about the teammate.

   **Where** — Lines 677 and 692:

   ```bash
     if ! "$REAP_GUARD" decide --worktree "$WORKTREE" --member "$TEAMMATE_NAME" --spawn-time "$_spawn_s" --session-id "$SESSION_ID" >/dev/null 2>&1; then
   ```

   ```bash
       if ! $WORKTREE_OWNED; then
   ```

   **Why it is wrong** — If the recorded shared CWD is the lead’s checkout and it contains products made by the lead or a sibling, `reap-guard` can succeed on those effects; the shared-path branch is skipped and the target teammate is closed on evidence that is not attributable to it.

10. **What** — A missing or non-executable reap guard causes all of its birth-grace, no-products, and adoption checks to be skipped while shutdown continues.

    **Where** — Lines 672, 710, and 717–718:

    ```bash
    if [[ -n "$WORKTREE" && -x "$REAP_GUARD" ]]; then
    ```

    ```bash
    elif [[ -n "$WORKTREE" ]]; then
    ```

    ```bash
      log "  WARN: reap-guard not executable ($REAP_GUARD) — R-a/R-b/R-d belt SKIPPED (degraded; the operator-adoption belt below is now the only who-gate)"
    fi
    ```

    **Why it is wrong** — When the executable is absent, a just-born or clean no-products teammate receives none of the checks the preceding comments call the “LAST gate” and can fall through to shutdown.

11. **What** — The operator-presence check falls through when no transcript can be located instead of invoking the second oracle or holding.

    **Where** — Lines 867–873:

    ```bash
        _adopt_tj="$(_find_transcript "$SESSION_ID" || true)"
        if [[ -z "$_adopt_tj" && -n "$PANEID" ]]; then
          _alt_sid="$(cc-sessions --json 2>/dev/null | jq -r --arg p "$PANEID" \
                      '.[] | select(.paneUUID==$p) | (.session_id // .sessionId) // empty' 2>/dev/null | head -1)"
          [[ -n "$_alt_sid" ]] && _adopt_tj="$(_find_transcript "$_alt_sid" || true)"
        fi
        if [[ -n "$_adopt_tj" ]]; then
    ```

    **Why it is wrong** — If neither session lookup produces a transcript, the entire WHO check is skipped and execution reaches the close even though operator presence is unprovable.

12. **What** — When a transcript is found through `_alt_sid`, its adoption timing is still compared with the original session’s spawn time.

    **Where** — Lines 868–871 and 895:

    ```bash
        if [[ -z "$_adopt_tj" && -n "$PANEID" ]]; then
          _alt_sid="$(cc-sessions --json 2>/dev/null | jq -r --arg p "$PANEID" \
                      '.[] | select(.paneUUID==$p) | (.session_id // .sessionId) // empty' 2>/dev/null | head -1)"
          [[ -n "$_alt_sid" ]] && _adopt_tj="$(_find_transcript "$_alt_sid" || true)"
    ```

    ```bash
          _spawn_s="$(_spawn_epoch "$SESSION_ID" || echo 0)"; [[ "$_spawn_s" =~ ^[0-9]+$ ]] || _spawn_s=0
    ```

    **Why it is wrong** — If the original ID is missing or belongs to another session, the teammate transcript’s initial spawn brief is compared against zero or another session’s start and can be falsely classified as an operator-adoption prompt.

13. **What** — Checkpoint payloads are built by interpolating variables into JSON without escaping them.

    **Where** — Lines 643–644 and 756:

    ```bash
      "$HOOK_DIR/teammate-checkpoint.sh" <<<"{\"hook_event_name\":\"TeammateIdle\",\"session_id\":\"$SESSION_ID\",\"cwd\":\"$WORKTREE\",\"team_name\":\"$TEAM_NAME\",\"teammate_name\":\"$TEAMMATE_NAME\"}" \
        2>/dev/null || true
    ```

    ```bash
      if "$HOOK_DIR/teammate-checkpoint.sh" <<<"{\"hook_event_name\":\"TeammateIdle\",\"session_id\":\"$SESSION_ID\",\"cwd\":\"$WORKTREE\",\"team_name\":\"$TEAM_NAME\",\"teammate_name\":\"$TEAMMATE_NAME\"}" 2>/dev/null; then
    ```

    **Why it is wrong** — A valid path or name containing a quote, backslash, or newline produces malformed JSON, causing the checkpoint to fail even though the referenced worktree is valid.

14. **What** — The fallback patch does not preserve untracked-file contents or reconstructible binary changes.

    **Where** — Lines 773–776:

    ```bash
          echo "# --- status ---"
          git -C "$WORKTREE" status --porcelain 2>/dev/null || true
          echo "# --- diff HEAD (tracked changes only) ---"
          git -C "$WORKTREE" diff HEAD 2>/dev/null || true
    ```

    **Why it is wrong** — When checkpointing fails and the tree contains untracked files or modified binary files, the patch contains only names or a binary-difference notice; force-removing the worktree then destroys the actual contents.

15. **What** — Fallback-patch failures are ignored, logged as success, and do not prevent destructive worktree removal.

    **Where** — Lines 774–778 and 946–950:

    ```bash
          git -C "$WORKTREE" status --porcelain 2>/dev/null || true
          echo "# --- diff HEAD (tracked changes only) ---"
          git -C "$WORKTREE" diff HEAD 2>/dev/null || true
        } > "$PATCH" 2>/dev/null
        log "  ✓ fallback patch: $PATCH"
    ```

    ```bash
      if [[ -n "$WORKTREE" ]] && $WORKTREE_OWNED; then
        MAIN_REPO=$(git -C "$WORKTREE" rev-parse --git-common-dir 2>/dev/null | sed 's|/\.git$||')
        if [[ -n "$MAIN_REPO" && -d "$MAIN_REPO" ]]; then
          git -C "$MAIN_REPO" worktree remove "$WORKTREE" --force 2>/dev/null \
            && log "  ✓ worktree removed: $WORKTREE"
    ```

    **Why it is wrong** — If `/tmp` is unwritable/full or either Git capture command fails, the code still logs a successful patch and later force-removes the worktree without any proven recovery artifact.

16. **What** — A teardown marker is written before the pane-close attempt succeeds.

    **Where** — Lines 179–180:

    ```bash
      write_teardown_marker "$pane" "${SESSION_ID:-}" teammate-idle
      close_pane "$pane"
    ```

    **Why it is wrong** — If the close times out, targets a nonexistent pane, or otherwise fails, the marker still asserts an intentional teardown and can cause a later genuine crash within its freshness window to be misclassified.

17. **What** — Worktree removal is independent of whether a pane was found or successfully closed.

    **Where** — Lines 926–940 and 946–950:

    ```bash
      if [[ -n "$PANEID" ]]; then
        close_and_log "$PANEID" "$MEMBER_NAME"
      else
        # Implicit-team tty-method fallback (unbounded here — no 5s hook limit), in
        # case the in-body env-method missed (e.g. ITERM_SESSION_ID absent). Still
        # safety-gated via _find_teammate_pid's --agent-id match.
        [[ -z "$TEAMMATE_PID" ]] && TEAMMATE_PID=$(_find_teammate_pid || true)
        LATE_PANE=$(_pane_from_tty "$TEAMMATE_PID" || true)
        if [[ -n "$LATE_PANE" ]]; then
          log "  ↳ implicit-team: pane $LATE_PANE for $MEMBER_NAME via tty (teammate pid $TEAMMATE_PID)"
          close_and_log "$LATE_PANE" "$MEMBER_NAME"
        else
          log "  ! no pane id resolved for $MEMBER_NAME — left for CC session-end cleanup"
        fi
      fi
    ```

    ```bash
      if [[ -n "$WORKTREE" ]] && $WORKTREE_OWNED; then
        MAIN_REPO=$(git -C "$WORKTREE" rev-parse --git-common-dir 2>/dev/null | sed 's|/\.git$||')
        if [[ -n "$MAIN_REPO" && -d "$MAIN_REPO" ]]; then
          git -C "$MAIN_REPO" worktree remove "$WORKTREE" --force 2>/dev/null \
            && log "  ✓ worktree removed: $WORKTREE"
    ```

    **Why it is wrong** — If close resolution fails or `close_pane` returns an RPC/timeout error, the teammate process may remain live while its owned working directory is nevertheless force-removed.

18. **What** — The hook reports that the pane is closed and work preserved before the asynchronous close has run or succeeded.

    **Where** — Line 918:

    ```bash
    echo '{"continue": false, "stopReason": "Idle teammate auto-shutdown (work preserved in refs/wip/LAST + /tmp/*.patch; pane closed via it2/tmux)"}'
    ```

    **Why it is wrong** — This output is emitted before the grace-period subprocess and remains the reported result when no pane ID exists, closing fails, checkpointing fails, or patch creation fails.

19. **What** — Failure of `git worktree remove` is silently discarded by the detached subprocess.

    **Where** — Lines 949–955 and 957:

    ```bash
          git -C "$MAIN_REPO" worktree remove "$WORKTREE" --force 2>/dev/null \
            && log "  ✓ worktree removed: $WORKTREE"
    ```

    ```bash
    ) >/dev/null 2>&1 &
    ```

    ```bash
    exit 0
    ```

    **Why it is wrong** — If removal fails because the worktree is locked, the repository is invalid, or permissions deny it, no failure is logged and the background exit status cannot affect the already-successful hook, so the promised cleanup is reported as complete while the worktree remains.