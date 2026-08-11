1. **What** — The iTerm2 resolver does not guarantee use of the required force-close shim.

   **Where** — Lines 102 and 139:

   ```bash
   _it2_bin() { command -v it2 2>/dev/null || echo "$HOME/.claude/bin/it2"; }
   ```

   ```bash
       CLOSE_ERR=$(tas_bounded "$(_it2_bin)" session close -f -s "$pane" 2>&1 >/dev/null)  # shim → python force=True
   ```

   **Why it is wrong** — If another `it2` executable precedes the shim in `PATH`, `command -v` selects it; the file states that the real CLI does not propagate force, so the close may prompt, time out, or fail.

2. **What** — A teardown marker is written before the pane close succeeds and is retained when the close fails.

   **Where** — Lines 185–194:

   ```bash
     write_teardown_marker "$pane" "${SESSION_ID:-}" teammate-idle
     close_pane "$pane"
     local rc=$?
     local err="${CLOSE_ERR//$'\n'/ ; }"
     if (( rc == 0 )); then
       log "  ✓ closed pane $pane ($who)"
     elif [[ "$err" == *"not found"* || "$err" == *"find pane"* ]]; then
       log "  ~ pane $pane ($who) already gone (${err:-not found})"
     else
       log "  ✗ pane close FAILED (rc=$rc) for $pane ($who): ${err:-<no stderr>}"
   ```

   **Why it is wrong** — On an RPC error, timeout, or incorrect pane ID, the pane remains open but its fresh marker says it was deliberately torn down; a subsequent genuine crash can therefore be misclassified as an intentional close.

3. **What** — Valid paths beginning with `/private` are unconditionally rewritten even when the stripped path is not an equivalent directory.

   **Where** — Lines 435, 522, and 600:

   ```bash
   PAYLOAD_CWD="${PAYLOAD_CWD#/private}"
   ```

   ```bash
         [[ -n "$_c" ]] && _named_seeds+=("${_c#/private}")
   ```

   ```bash
       cfg_cwd="${cfg_cwd#/private}"
   ```

   **Why it is wrong** — For a real path such as `/private/projects/repo` with no `/projects/repo` alias, resolution is attempted against the wrong path and can fail closed or, if the stripped path happens to exist, gate on the wrong repository.

4. **What** — The stripped `-N` member name is treated as an equal match instead of a fallback, allowing the base member’s worktree to shadow the exact member’s worktree.

   **Where** — Lines 425–427, 449–455, 494, and 504–506:

   ```bash
   MEMBER_CANDIDATES=("$TEAMMATE_NAME")
   if [[ "$TEAMMATE_NAME" =~ ^(.+)-[0-9]+$ ]]; then
     MEMBER_CANDIDATES+=("${BASH_REMATCH[1]}")
   ```

   ```bash
     for (( i=0; i<count; i++ )); do
       name=$(yq eval ".members[$i].name" "$manifest" 2>/dev/null)
       for m in "${MEMBER_CANDIDATES[@]}"; do
         if [[ "$name" == "$m" ]]; then
           wt=$(yq eval ".members[$i].worktree" "$manifest" 2>/dev/null)
           wt="${wt/#\~/$HOME}"
           if [[ -n "$wt" && -d "$wt" ]]; then printf '%s\n' "$wt"; return 0; fi
   ```

   ```bash
     while IFS= read -r line; do
   ```

   ```bash
       base="${wt##*/}"
       for m in "${MEMBER_CANDIDATES[@]}"; do
         if [[ "$base" == "$m" && -d "$wt" ]]; then printf '%s\n' "$wt"; return 0; fi
   ```

   **Why it is wrong** — For an event for `worker-2` when both `worker` and `worker-2` exist, manifest or Git worktree ordering can present `worker` first, causing its tree to be checkpointed, gated, marked owned, and potentially removed.

5. **What** — The team-agnostic `/tmp` glob fallback can select another team’s same-named member worktree and marks it as owned.

   **Where** — Lines 572–577:

   ```bash
     for m in "${MEMBER_CANDIDATES[@]}"; do
       for candidate in /tmp/wt-*-"${m}" /tmp/worktree-*-"${m}"; do
         if [[ -d "$candidate" ]]; then
           WORKTREE="$candidate"        # per-member path ⇒ dedicated
           WORKTREE_OWNED=true
           break 2
   ```

   **Why it is wrong** — If two teams have a member named `reviewer` and both matching directories exist, shell ordering chooses the first path without validating its team, so the hook can checkpoint and force-remove the other team’s worktree.

6. **What** — Cross-root resolution accepts the first matching team state without proving it is the live state, so stale configuration can supply the wrong worktree or pane.

   **Where** — Lines 84, 471–480, and 800–810:

   ```bash
   _team_roots+=("$HOME"/.claude*/teams)
   ```

   ```bash
   for _root in "${TEAM_ROOTS[@]}"; do
     _cand_cfg="$_root/$TEAM_NAME/config.json"
     [[ -f "$_cand_cfg" ]] || continue
     [[ -z "$TEAM_CONFIG" ]] && TEAM_CONFIG="$_cand_cfg"        # first existing = weakest fallback
     for m in "${MEMBER_CANDIDATES[@]}"; do
       if jq -e --arg m "$m" '.members[]? | select(.name==$m)' "$_cand_cfg" >/dev/null 2>&1; then
         TEAM_CONFIG="$_cand_cfg"; break 2
       fi
     done
   done
   ```

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

   **Why it is wrong** — When a stale same-named team directory appears before the live root and still contains the member and a nonempty pane ID, it wins; the live lookup fallback is then skipped and the hook operates on stale state.

7. **What** — Shared-worktree detection compares unnormalized path strings and can incorrectly declare a physically shared worktree owned by one member.

   **Where** — Lines 599–607 and 959:

   ```bash
       cfg_cwd=$(jq -r --arg m "$m" '.members[]? | select(.name==$m) | .cwd // empty' "$TEAM_CONFIG" 2>/dev/null | head -1)
       cfg_cwd="${cfg_cwd#/private}"
       [[ -n "$cfg_cwd" && -d "$cfg_cwd" ]] || continue
       WORKTREE="$cfg_cwd"
   ```

   ```bash
       _occupants=$(jq -r --arg c "$cfg_cwd" '[.members[]? | select((.cwd // "") == $c)] | length' "$TEAM_CONFIG" 2>/dev/null)
       if [[ "$_occupants" == "1" ]]; then
         WORKTREE_OWNED=true
   ```

   ```bash
     if [[ -n "$WORKTREE" ]] && $WORKTREE_OWNED; then
   ```

   **Why it is wrong** — If one member records `/tmp/wt` and a sibling records the equivalent `/private/tmp/wt`, only the first string is counted, ownership becomes true, and the shared worktree can be force-removed.

8. **What** — Both dirty-tree predicates can classify an unreadable or sufficiently verbose dirty tree as clean.

   **Where** — Lines 45, 629, and 775:

   ```bash
   set -uo pipefail
   ```

   ```bash
     if git -C "$WORKTREE" status --porcelain 2>/dev/null | grep -q .; then
   ```

   ```bash
     if git -C "$WORKTREE" status --porcelain 2>/dev/null | grep -q .; then
   ```

   **Why it is wrong** — A Git error such as corruption or a permission failure makes the condition false, and with large output `grep -q` can exit after its first match while Git receives SIGPIPE, which `pipefail` also makes false; the dirty defer and later patch creation are then skipped.

9. **What** — Defer-counter writes are unchecked, so persistence failure disables the supposedly bounded defer behavior.

   **Where** — Lines 90, 646, 706, and 741:

   ```bash
   mkdir -p "$LOG_DIR" "$WATCHDOG_DIR" 2>/dev/null || true
   ```

   ```bash
     echo "$DEFER_COUNT" > "$DEFER_COUNTER"
   ```

   ```bash
           echo "$DEFER_COUNT" > "$DEFER_COUNTER"
   ```

   ```bash
       echo "$DEFER_COUNT" > "$DEFER_COUNTER"
   ```

   **Why it is wrong** — If the watchdog directory is unwritable or the filesystem is full, each invocation still logs/returns as a defer but the next invocation rereads the old count, so the cap and its reap-or-surface follow-through may never occur.

10. **What** — Checkpoint payloads are constructed by raw string interpolation rather than valid JSON escaping.

    **Where** — Lines 649 and 766:

    ```bash
      "$HOOK_DIR/teammate-checkpoint.sh" <<<"{\"hook_event_name\":\"TeammateIdle\",\"session_id\":\"$SESSION_ID\",\"cwd\":\"$WORKTREE\",\"team_name\":\"$TEAM_NAME\",\"teammate_name\":\"$TEAMMATE_NAME\"}" \
    ```

    ```bash
      if "$HOOK_DIR/teammate-checkpoint.sh" <<<"{\"hook_event_name\":\"TeammateIdle\",\"session_id\":\"$SESSION_ID\",\"cwd\":\"$WORKTREE\",\"team_name\":\"$TEAM_NAME\",\"teammate_name\":\"$TEAMMATE_NAME\"}" 2>/dev/null; then
    ```

    **Why it is wrong** — A legal worktree path containing a quote or backslash produces invalid JSON or a different decoded path, causing the checkpoint to fail or target the wrong directory.

11. **What** — The advertised fallback patch does not contain the contents of untracked files.

    **Where** — Lines 784–786 and 962:

    ```bash
          git -C "$WORKTREE" status --porcelain 2>/dev/null || true
          echo "# --- diff HEAD (tracked changes only) ---"
          git -C "$WORKTREE" diff HEAD 2>/dev/null || true
    ```

    ```bash
          git -C "$MAIN_REPO" worktree remove "$WORKTREE" --force 2>/dev/null \
    ```

    **Why it is wrong** — When the checkpoint fails and the tree contains an untracked file, the patch records only its status/name, after which forced worktree removal deletes its unrecoverable contents.

12. **What** — Patch-generation failures are ignored while the hook unconditionally logs that the fallback patch was written.

    **Where** — Lines 784, 786–788:

    ```bash
          git -C "$WORKTREE" status --porcelain 2>/dev/null || true
    ```

    ```bash
          git -C "$WORKTREE" diff HEAD 2>/dev/null || true
        } > "$PATCH" 2>/dev/null
        log "  ✓ fallback patch: $PATCH"
    ```

    **Why it is wrong** — If `/tmp` cannot create the file, or either Git command fails, execution continues and records success even though the patch is absent or incomplete; the worktree can subsequently be removed.

13. **What** — Pane resolution likewise lets the stripped base member shadow the exact numbered member.

    **Where** — Lines 425–427 and 803–810:

    ```bash
   MEMBER_CANDIDATES=("$TEAMMATE_NAME")
   if [[ "$TEAMMATE_NAME" =~ ^(.+)-[0-9]+$ ]]; then
     MEMBER_CANDIDATES+=("${BASH_REMATCH[1]}")
    ```

    ```bash
     RESOLVED=$(jq -r --args \
       '.members[]? | select(.name as $n | $ARGS.positional | index($n)) | "\(.name)\t\(.tmuxPaneId // "")"' \
       "${MEMBER_CANDIDATES[@]}" < "$CONFIG" 2>/dev/null | head -1)
     if [[ -n "$RESOLVED" && "$RESOLVED" == *$'\t'* ]]; then
       MEMBER_NAME="${RESOLVED%%$'\t'*}"
       PANEID="${RESOLVED#*$'\t'}"
       [[ -z "$MEMBER_NAME" ]] && MEMBER_NAME="$TEAMMATE_NAME"
       [[ -n "$PANEID" ]] && break
    ```

    **Why it is wrong** — For `worker-2` with `worker` earlier in `config.json`, `head -1` returns `worker`’s pane, so the hook can close the wrong teammate while leaving `worker-2` open.

14. **What** — When the WHO primitive exists but no transcript can be found, the operator-adoption gate silently proceeds instead of consulting the beat or holding.

    **Where** — Lines 877 and 879–885:

    ```bash
       _beat_or_hold "the who-oracle ($INTERACTIVE_LIB) is absent"
    ```

    ```bash
       _adopt_tj="$(_find_transcript "$SESSION_ID" || true)"
       if [[ -z "$_adopt_tj" && -n "$PANEID" ]]; then
         _alt_sid="$(cc-sessions --json 2>/dev/null | jq -r --arg p "$PANEID" \
                     '.[] | select(.paneUUID==$p) | (.session_id // .sessionId) // empty' 2>/dev/null | head -1)"
         [[ -n "$_alt_sid" ]] && _adopt_tj="$(_find_transcript "$_alt_sid" || true)"
       fi
       if [[ -n "$_adopt_tj" ]]; then
    ```

    **Why it is wrong** — If both transcript lookups fail while the primitive is installed, the guarded body is skipped and `_beat_or_hold` is never called; with the other reap guard unavailable, an operator-adopted pane whose transcript is missing or inaccessible is closed on an unproven premise.

15. **What** — The late tty fallback reuses a previously validated PID without revalidating that it still belongs to the teammate.

    **Where** — Lines 821, 823, 938, and 945–949:

    ```bash
     TEAMMATE_PID=$(_find_teammate_pid || true)
    ```

    ```bash
       PANEID=$(_pane_from_env "$TEAMMATE_PID" || true)
    ```

    ```bash
     sleep "$CLOSE_GRACE_S"
    ```

    ```bash
       [[ -z "$TEAMMATE_PID" ]] && TEAMMATE_PID=$(_find_teammate_pid || true)
       LATE_PANE=$(_pane_from_tty "$TEAMMATE_PID" || true)
       if [[ -n "$LATE_PANE" ]]; then
         log "  ↳ implicit-team: pane $LATE_PANE for $MEMBER_NAME via tty (teammate pid $TEAMMATE_PID)"
         close_and_log "$LATE_PANE" "$MEMBER_NAME"
    ```

    **Why it is wrong** — If environment lookup fails, then the teammate process exits and its PID is recycled during the grace period, `_pane_from_tty` resolves the replacement process’s terminal and the hook closes an unrelated pane.

16. **What** — An owned worktree is force-removed regardless of whether a pane was resolved or the attempted pane close succeeded.

    **Where** — Lines 939–952 and 959–963:

    ```bash
     if [[ -n "$PANEID" ]]; then
       close_and_log "$PANEID" "$MEMBER_NAME"
     else
    ```

    ```bash
       if [[ -n "$LATE_PANE" ]]; then
         log "  ↳ implicit-team: pane $LATE_PANE for $MEMBER_NAME via tty (teammate pid $TEAMMATE_PID)"
         close_and_log "$LATE_PANE" "$MEMBER_NAME"
       else
         log "  ! no pane id resolved for $MEMBER_NAME — left for CC session-end cleanup"
       fi
    ```

    ```bash
     if [[ -n "$WORKTREE" ]] && $WORKTREE_OWNED; then
       MAIN_REPO=$(git -C "$WORKTREE" rev-parse --git-common-dir 2>/dev/null | sed 's|/\.git$||')
       if [[ -n "$MAIN_REPO" && -d "$MAIN_REPO" ]]; then
         git -C "$MAIN_REPO" worktree remove "$WORKTREE" --force 2>/dev/null \
           && log "  ✓ worktree removed: $WORKTREE"
    ```

    **Why it is wrong** — On a missing pane ID, timeout, RPC error, or modal close failure, the teammate can remain live while its working directory is deleted from underneath it.

17. **What** — Worktree-removal failures are suppressed and produce no failure result or log.

    **Where** — Lines 960–964:

    ```bash
       MAIN_REPO=$(git -C "$WORKTREE" rev-parse --git-common-dir 2>/dev/null | sed 's|/\.git$||')
       if [[ -n "$MAIN_REPO" && -d "$MAIN_REPO" ]]; then
         git -C "$MAIN_REPO" worktree remove "$WORKTREE" --force 2>/dev/null \
           && log "  ✓ worktree removed: $WORKTREE"
       fi
    ```

    **Why it is wrong** — If repository resolution fails or Git refuses removal, the worktree remains, stderr is discarded, and the hook still exits successfully without recording that teardown was incomplete.

18. **What** — The hook reports work preservation and pane closure as completed before the detached actions run and even when they later fail.

    **Where** — Lines 931 and 968:

    ```bash
   echo '{"continue": false, "stopReason": "Idle teammate auto-shutdown (work preserved in refs/wip/LAST + /tmp/*.patch; pane closed via it2/tmux)"}'
    ```

    ```bash
   ) >/dev/null 2>&1 &
    ```

    **Why it is wrong** — A failed checkpoint, failed or incomplete patch, unresolved pane, failed close, or terminated background process leaves one or both claims false, but the already-emitted hook response still reports them as successful.