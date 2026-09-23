# Review of `hooks/teammate-auto-shutdown.sh`

Line numbers count from `#!/bin/bash` as line 1. Defects are ordered roughly by severity.

---

### 1. Pane lookup can pick an auto-incremented teammate's sibling and close that sibling's pane

- **What:** The config lookup returns the first member in config order that matches *any* candidate name, rather than preferring the teammate's full name. So a teammate named `X-2` resolves to the pane of the other member `X`.
- **Where:** lines 814–816
  ```
    RESOLVED=$(jq -r --args \
      '.members[]? | select(.name as $n | $ARGS.positional | index($n)) | "\(.name)\t\(.tmuxPaneId // "")"' \
      "${MEMBER_CANDIDATES[@]}" < "$CONFIG" 2>/dev/null | head -1)
  ```
- **Why it is wrong:**
  - For teammate `quality-keeper-2`, the candidate list is `(quality-keeper-2 quality-keeper)`.
  - The `-2` suffix exists only because `quality-keeper` was already a member, so that member is listed earlier in `.members`.
  - jq emits matches in config order, and `head -1` takes the sibling. `MEMBER_NAME` and `PANEID` then become the sibling's.
  - Line 951 force-closes the sibling's live pane.
  - Line 186 writes a teardown marker for the sibling, which masks the resulting death as a deliberate teardown.

### 2. Manifest and by-name worktree legs can claim a sibling's (or another team's) worktree as OWNED

- **What:** Both legs loop over records first and candidate names second. A record matching the stripped base name therefore wins whenever it comes before the member's own record. The result is marked `WORKTREE_OWNED=true`.
- **Where:**
  - line 457 `  for (( i=0; i<count; i++ )); do` (candidates checked inside, line 459)
  - line 506 `  while IFS= read -r line; do` with line 518:
    ```
          if [[ "$base" == "$m" && -d "$wt" ]]; then printf '%s\n' "$wt"; return 0; fi
    ```
- **Why it is wrong:**
  - For `worker-2`, the sibling `worker`'s manifest row or git worktree record can come first. Git lists linked worktrees roughly in name order, and `worker` sorts before `worker-2`. The sibling's tree is then returned.
  - All gates (busy marker, dirty tree, reap-guard, checkpoint) run against the wrong tree.
  - Line 973 then runs `git worktree remove "$WORKTREE" --force` on the sibling's live worktree and destroys its uncommitted work. The checkpoint for it was filed under the wrong member name.
  - The basename match at 518 is also not scoped to a team. A same-named member of another team working in the same repo matches the same way.

### 3. The `/tmp` glob fallback matches other members' and other teams' worktrees and marks them OWNED

- **What:** In `wt-*-<m>`, the `*` absorbs hyphens and any team slug. It therefore matches worktrees that are not this member's, and each match sets `WORKTREE_OWNED=true`.
- **Where:** line 585
  ```
      for candidate in /tmp/wt-*-"${m}" /tmp/worktree-*-"${m}"; do
  ```
  The same lack of team scoping applies to line 569: `      "/tmp/worktree-${m}"; do`
- **Why it is wrong:**
  - Member `keeper` matches `/tmp/wt-ui-quality-keeper`.
  - Member `reviewer` of team A matches `/tmp/wt-teamB-reviewer`.
  - The foreign tree is gated on and checkpointed. It is then force-removed at line 973, taking another live teammate's uncommitted work with it.

### 4. A failed checkpoint does not stop the `--force` removal, and the fallback patch does not contain untracked files

- **What:** The removal at the end never looks at `CHECKPOINT_OK`. The "fallback" patch records untracked files by name only. So when the checkpoint fails, untracked work is destroyed.
- **Where:**
  - line 796 `      git -C "$WORKTREE" diff HEAD 2>/dev/null || true`
  - line 970 `  if [[ -n "$WORKTREE" ]] && $WORKTREE_OWNED; then`
  - line 973 `      git -C "$MAIN_REPO" worktree remove "$WORKTREE" --force 2>/dev/null \`
- **Why it is wrong:**
  - Suppose `teammate-checkpoint.sh` fails (logged at 780) and the teammate created new files it never `git add`ed. This is the normal case on the dirty-tree-at-cap path.
  - The patch contains only `?? path` lines from `status`, because `diff HEAD` excludes untracked files.
  - The detached block still force-removes the tree, and those files are lost permanently.
  - The comment at 946–947, "cannot lose work", is false in this case.

### 5. The operator-adoption belt fails open when the transcript cannot be found

- **What:** With the lib present, the who-check runs only if a transcript path was found. Otherwise the check is skipped with no call to `_beat_or_hold` and no log line, and execution falls through to the close.
- **Where:** line 896
  ```
      if [[ -n "$_adopt_tj" ]]; then
  ```
- **Why it is wrong:**
  - Several ordinary conditions leave `_adopt_tj` empty:
    - `SESSION_ID` is `unknown`.
    - The transcript lives under a config dir not in the hard-coded `PROJECT_ROOTS` (even though `TEAM_ROOTS` globs every `~/.claude*`).
    - The transcript is deeper than `-maxdepth 2`.
    - `PANEID` is empty or missing from the registry.
  - In any of these cases, "could not read who typed" becomes a licence to force-close the pane.
  - This contradicts line 342, which says the beat is "Consulted whenever the transcript WHO-oracle could not answer". It also contradicts the rc-2 reasoning at 900–906.
  - The same fall-through happens when `ci_last_interactive_epoch` returns an rc other than 0, 1 or 2, or returns rc 0 with non-numeric output.

### 6. A git failure is read as a clean tree, so the "corrupt repo" fallback never fires

- **What:** Both the dirty-tree gate and the fallback-patch trigger treat `git status` failing as "no changes".
- **Where:** line 640 and line 785 (identical)
  ```
    if git -C "$WORKTREE" status --porcelain 2>/dev/null | grep -q .; then
  ```
- **Why it is wrong:**
  - In a corrupt repo, or with an index/permission error (the very case line 10 says the fallback covers), `git status` exits non-zero with no stdout.
  - The consequences:
    - `TREE_DIRTY` stays false, so there is no defer.
    - The checkpoint likely fails too.
    - No patch is written.
  - The pane is then closed with neither a checkpoint nor a patch.

### 7. A failed patch write is logged as a success

- **What:** The patch redirection's outcome is never checked, and `✓ fallback patch` is logged unconditionally.
- **Where:** lines 797–798
  ```
      } > "$PATCH" 2>/dev/null
      log "  ✓ fallback patch: $PATCH"
  ```
- **Why it is wrong:**
  - If `/tmp` is full or the path is unwritable, no patch exists, but the log claims one does.
  - The close and the `--force` removal then proceed on that false record. After a failed checkpoint, the log shows a recovery path that isn't there.

### 8. The birth-grace fallback turns into a permanent, silent defer

- **What:** When the registry has no `startedAt`, spawn time is set to "now" on *every* invocation, so birth-grace can never elapse.
- **Where:**
  - line 692
    ```
      if [[ "$_started_ms" =~ ^[0-9]+$ ]]; then _spawn_s=$(( _started_ms / 1000 )); else _spawn_s="$(date +%s)"; fi
    ```
  - with line 726
    ```
        log "defer $TEAMMATE_NAME (team=$TEAM_NAME): reap-guard DEFER (birth-grace / no-products / operator-adopted)"
    ```
- **Why it is wrong:**
  - Take an OWNED teammate whose session is never in `cc-sessions`: for example `SESSION_ID=unknown`, `cc-sessions` not on the hook's minimal PATH, or a registry row that was overwritten.
  - Reap-guard defers it every time. The OWNED branch exits without charging `MAX_DEFERS` and without surfacing anything.
  - The teammate is never reaped and never paged. That is exactly the "guard that always defers" failure the comments at 694–705 condemn.
  - Line 711's claim that birth-grace is "self-resolving" is false for this input.

### 9. The teardown marker is written before a close that can fail

- **What:** The marker is written ahead of `close_pane` and is not retracted when the close fails.
- **Where:** lines 186–187
  ```
    write_teardown_marker "$pane" "${SESSION_ID:-}" teammate-idle
    close_pane "$pane"
  ```
- **Why it is wrong:**
  - `close_pane` can fail in several ways: a `timeout` exit 124 under the 2026-07-26 wedge, an RPC error, or a tmux error, all logged at 195.
  - The teammate then stays alive, but a `mode=teammate-idle` marker exists for it.
  - A genuine crash inside the reader's freshness window is then classified as a deliberate teardown.
  - Line 184's premise that "the close is inevitable" does not hold.

### 10. The worktree is force-removed even when the pane was not closed

- **What:** The removal runs regardless of whether any pane was resolved or closed.
- **Where:** line 970
  ```
    if [[ -n "$WORKTREE" ]] && $WORKTREE_OWNED; then
  ```
- **Why it is wrong:**
  - Two cases leave the teammate's claude.exe still running:
    - No pane id was resolved (line 962, "left for CC session-end cleanup").
    - The close failed (line 195).
  - In both cases its cwd is deleted with `--force`. Anything it writes after the checkpoint is lost, and any later turn runs in a deleted directory.

### 11. The shared-cwd case lets a reap-guard *pass* license the close

- **What:** Only a DEFER on a non-owned (shared) tree is treated as uninformative. A PASS computed on that same wrong tree still proceeds to close.
- **Where:** line 693
  ```
    if ! "$REAP_GUARD" decide --worktree "$WORKTREE" --member "$TEAMMATE_NAME" --spawn-time "$_spawn_s" --session-id "$SESSION_ID" >/dev/null 2>&1; then
  ```
- **Why it is wrong:**
  - With `WORKTREE_OWNED=false`, the comments at 694–698 say reap-guard is reading the lead's checkout.
  - If the lead has produced work since this teammate spawned, the no-products check passes on the lead's evidence. The dirty-tree gate at 640 is likewise measuring the lead's tree.
  - A teammate that produced nothing is therefore closed on a premise about someone else's tree.

### 12. The detached tty fallback re-walks from a possibly recycled `$PPID`, and the safety match checks only the name

- **What:** The late re-walk starts from `$PPID` several seconds after the fact. The only thing standing in for "this teammate" is the member name, with no team or session check.
- **Where:**
  - line 956
    ```
        [[ -z "$TEAMMATE_PID" ]] && TEAMMATE_PID=$(_find_teammate_pid || true)
    ```
  - line 231
    ```
          if [[ -n "$m" && "$cmd" == *"--agent-id ${m}@"* ]]; then
    ```
- **Why it is wrong:**
  - Line 956 runs only when the in-body walk already failed, i.e. the LEAD-side model. There, `$PPID` is the `/bin/sh` shim that lines 30–33 say is dead and PID-recycled by then.
  - Walking up from a recycled pid can reach a same-named teammate of *another* team. `--agent-id reviewer@` matches `reviewer@session-<any>`.
  - That teammate's pane is then force-closed, violating the guarantee at line 220.

### 13. `_it2_bin` does not guarantee the required shim

- **What:** The function returns whichever `it2` comes first on PATH. It falls back to the shim only when no `it2` exists at all.
- **Where:** line 105
  ```
  _it2_bin() { command -v it2 2>/dev/null || echo "$HOME/.claude/bin/it2"; }
  ```
- **Why it is wrong:**
  - Suppose the hook's minimal PATH has the real it2 CLI (for example a pip install in a Python bin dir) ahead of `~/.claude/bin`, or lacks `~/.claude/bin` entirely.
  - The real CLI then runs. Per lines 99–104, it drops `-f`, and iTerm2 raises the running-job modal on the pane instead of closing it.

### 14. A malformed hold value silently disables the only remaining who-gate

- **What:** A non-numeric `CC_CLASSIFY_INTERACTIVE_HOLD_S` turns off the whole operator-adoption belt, including the fail-closed `_beat_or_hold` path, without any log line.
- **Where:** line 860
  ```
  { [[ "$INTERACTIVE_HOLD_S" =~ ^[0-9]+$ ]] && (( INTERACTIVE_HOLD_S > 0 )); } || _hold_on=0
  ```
- **Why it is wrong:**
  - A value like `6h` or `21600s` is a configuration mistake, not use of the kill switch (that is a separate variable, line 859).
  - It still disables the belt silently. When reap-guard is also absent, line 737 notes this belt is the only who-gate left, so a live operator conversation gets closed.

### 15. On the LEAD-side model, the payload `session_id` identifies the lead, not the teammate

- **What:** Every sid-keyed step uses the hook payload's `session_id`. Under the LEAD-side firing described at lines 3 and 30–31, that is the lead's session.
- **Where:**
  - line 404
    ```
    SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null)
    ```
  - consumed at line 186 (`write_teardown_marker "$pane" "${SESSION_ID:-}" teammate-idle`)
- **Why it is wrong:**
  - The marker file becomes `<lead-sid>.json` with `mode=teammate-idle`. A genuine lead crash within the freshness window is then masked. This is the hazard lines 157–158 describe for `unknown.json`.
  - `_tool_in_flight` (676) and the adoption check (890) read the lead's transcript instead of the teammate's.

### 16. (Minor) The SURFACE messages overstate the defer count

- **What:** The log and page text says the teammate was deferred `$MAX_DEFERS` times, but under the N−1 scheme only `MAX_DEFERS−1` deferrals occur. The shared counter may also have been advanced by dirty-tree defers rather than the stated cause.
- **Where:** line 756
  ```
    log "⚑ SURFACE $TEAMMATE_NAME (team=$TEAM_NAME): WORKTREE unresolved after $MAX_DEFERS defers — refusing ungated close, paging desk (session=$SESSION_ID)"
  ```
  (and the same claim at line 721 and in the page at 762–763)
- **Why it is wrong:** With the default of 3, the forensic log and the operator page report 3 unresolved-worktree defers. Only 2 happened, and possibly none of them were for this cause.
