# Review of `hooks/teammate-auto-shutdown.sh`

Line numbers are counted from line 1 (`#!/bin/bash`) of the file as given in the brief.

---

### 1. The pane lookup can pick a sibling teammate's pane

**What:** The config.json pane lookup returns the first member that matches *any* name candidate. For an auto-incremented teammate, that is often a different, live teammate.

**Where:** lines 814–816
```
  RESOLVED=$(jq -r --args \
    '.members[]? | select(.name as $n | $ARGS.positional | index($n)) | "\(.name)\t\(.tmuxPaneId // "")"' \
    "${MEMBER_CANDIDATES[@]}" < "$CONFIG" 2>/dev/null | head -1)
```

**Why it is wrong:**
- Suppose the idle teammate is `quality-keeper-2`. Its candidates are `quality-keeper-2` and `quality-keeper`.
- The `-2` suffix exists only because `quality-keeper` was already a member, so that sibling is usually listed first in `.members`.
- `head -1` therefore returns the sibling's `name` and `tmuxPaneId`.
- The detached block then force-closes the sibling's pane (`it2 session close -f` / `tmux kill-pane`) and writes a teardown marker for the sibling.
- The full-name candidate is never given priority.

---

### 2. The worktree-name leg and the manifest leg can claim a sibling's worktree as owned

**What:** Both legs loop over worktrees (or manifest members) on the outside and name candidates on the inside. A stripped candidate can therefore match a sibling's entry before the exact name is ever tried, and the result is marked `WORKTREE_OWNED=true`.

**Where:**
- lines 517–518
  ```
      for m in "${MEMBER_CANDIDATES[@]}"; do
        if [[ "$base" == "$m" && -d "$wt" ]]; then printf '%s\n' "$wt"; return 0; fi
  ```
- lines 457–460
  ```
    for (( i=0; i<count; i++ )); do
      name=$(yq eval ".members[$i].name" "$manifest" 2>/dev/null)
      for m in "${MEMBER_CANDIDATES[@]}"; do
        if [[ "$name" == "$m" ]]; then
  ```
- line 541
  ```
        WORKTREE_OWNED=true
  ```

**Why it is wrong:**
- Take teammate `quality-keeper-2`. If `git worktree list` (or the manifest) lists `.../quality-keeper` before `.../quality-keeper-2`, the stripped candidate matches first.
- `WORKTREE` becomes the sibling's tree and is marked owned.
- Every gate (busy-marker, dirty-tree, reap-guard) and the checkpoint then run against the wrong tree.
- Line 973 finally runs `git worktree remove --force` on the sibling's live worktree, destroying its uncommitted work.

---

### 3. The `/tmp` glob fallback matches other members' and other teams' worktrees and marks them owned

**What:** The glob ignores the team slug, and `*` can also absorb part of the member name. The first hit is treated as this member's dedicated tree.

**Where:** lines 585–588
```
    for candidate in /tmp/wt-*-"${m}" /tmp/worktree-*-"${m}"; do
      if [[ -d "$candidate" ]]; then
        WORKTREE="$candidate"        # per-member path ⇒ dedicated
        WORKTREE_OWNED=true
```

**Why it is wrong:** The first matching directory is taken as owned in two cases:
- **Same name in another team:** teammate `reviewer` of team B, whose own tree did not match exactly, hits `/tmp/wt-teamA-reviewer`.
- **Suffix collision:** a member named `keeper` (or a stripped candidate `keeper`) hits `/tmp/wt-team-quality-keeper`.

In either case the detached block `--force`-removes another live teammate's worktree.

---

### 4. The worktree is force-removed even when the checkpoint failed

**What:** Removal is never gated on `CHECKPOINT_OK`. The fallback patch cannot hold the content of untracked files.

**Where:**
- lines 970 and 973
  ```
    if [[ -n "$WORKTREE" ]] && $WORKTREE_OWNED; then
  ```
  ```
        git -C "$MAIN_REPO" worktree remove "$WORKTREE" --force 2>/dev/null \
  ```
- line 796
  ```
        git -C "$WORKTREE" diff HEAD 2>/dev/null || true
  ```

**Why it is wrong:**
- The header's stated failure modes are a corrupt repo or a permission error. In those cases `teammate-checkpoint.sh` fails and line 780 logs "checkpoint failed".
- The patch contains only `git diff HEAD` (tracked changes) plus a status listing. New files appear by name only.
- The detached block still force-removes the worktree, so untracked work is permanently lost.
- The comment on lines 946–947 ("Work is already checkpointed above, so removing the worktree here cannot lose work") is false in exactly this case.

---

### 5. The operator-adoption belt fails open when the transcript cannot be found or the oracle returns an unexpected code

**What:** If no transcript is located, the whole who-check is skipped and the close proceeds. The same happens for any return code other than 2 that yields a non-numeric answer. The beat oracle is never consulted in either case.

**Where:**
- line 896
  ```
      if [[ -n "$_adopt_tj" ]]; then
  ```
- lines 898–899
  ```
        _iep="$(ci_last_interactive_epoch "$_adopt_tj" 2>/dev/null)" || _irc=$?
        if (( _irc == 2 )); then
  ```

**Why it is wrong:**
- `_find_transcript` searches only `-maxdepth 2` of the configured roots. If it misses, or if both `SESSION_ID` and the `paneUUID` registry lookup fail to map, `_adopt_tj` is empty.
- An oracle failure such as rc 127 or 3 leaves `_iep` empty and is treated like rc 1 ("nobody typed").
- In all of these cases presence is unproven, yet execution falls through to `{"continue": false}` and a force-close.
- This contradicts `_beat_or_hold`'s contract at line 342 ("Consulted whenever the transcript WHO-oracle could not answer"). Line 735 also claims this belt "now fails closed".

---

### 6. A malformed hold-window value silently disables the belt, including its fail-closed branch

**What:** A non-numeric `CC_CLASSIFY_INTERACTIVE_HOLD_S` turns the entire operator-adoption block off with no log.

**Where:** line 860
```
{ [[ "$INTERACTIVE_HOLD_S" =~ ^[0-9]+$ ]] && (( INTERACTIVE_HOLD_S > 0 )); } || _hold_on=0
```

**Why it is wrong:**
- A value such as `6h` or `21600s` sets `_hold_on=0`.
- That skips the adoption check and also the lib-absent `_beat_or_hold` hold.
- Adopted operator panes are then force-closed, and nothing records that the who-gate was disabled.
- Only the explicit `_DISABLE=1` kill switch is meant to do this.

---

### 7. A reap-guard PROCEED on a shared cwd is trusted, although it was evaluated on the wrong tree

**What:** The code already recognises that reap-guard's verdict on a shared (lead's) cwd is uninformative. It discounts only DEFER results; a PASS still licenses the close.

**Where:** lines 693 and 712
```
  if ! "$REAP_GUARD" decide --worktree "$WORKTREE" --member "$TEAMMATE_NAME" --spawn-time "$_spawn_s" --session-id "$SESSION_ID" >/dev/null 2>&1; then
```
```
    if ! $WORKTREE_OWNED; then
```

**Why it is wrong:**
- When `WORKTREE_OWNED=false`, the tree is the lead's checkout.
- If the lead produced commits since spawn, the effect-read "has products" check passes and the teammate proceeds to close.
- That decision is based on the lead's work, not the teammate's, so a teammate with no products (the R-b case the gate exists to hold) gets reaped.

---

### 8. The env-method pane fallback can resolve an inherited, outer iTerm2 session

**What:** The `--agent-id` check proves which *process* this is, not which *pane* it owns. `ITERM_SESSION_ID` is inherited.

**Where:**
- line 247
  ```
    line=$(ps eww -p "$pid" 2>/dev/null | tr ' ' '\n' | grep -m1 '^ITERM_SESSION_ID=')
  ```
- line 834
  ```
      PANEID=$(_pane_from_env "$TEAMMATE_PID" || true)
  ```

**Why it is wrong:**
- Consider a teammate running in a tmux pane inside an iTerm2 session, or one spawned without its own iTerm2 session, where the config lookup missed (the race this fallback exists for).
- The process carries the hosting session's `ITERM_SESSION_ID`, which is the lead's session.
- `close_pane` then runs `it2 session close -f` on that UUID, force-closing the lead's pane.

---

### 9. `_it2_bin` does not guarantee the shim it claims is REQUIRED

**What:** The function returns whichever `it2` comes first on PATH and falls back to the shim only when none is found.

**Where:** line 105
```
_it2_bin() { command -v it2 2>/dev/null || echo "$HOME/.claude/bin/it2"; }
```

**Why it is wrong:**
- Under the hook's PATH, a real `it2` (for example a pip-installed one) may precede `~/.claude/bin`, or the shim dir may be absent from PATH.
- The real CLI does not propagate `-f`, per the comment at lines 99–104.
- So every close pops iTerm2's running-job modal and the pane stays open.

---

### 10. The teardown marker is written even when the close then fails

**What:** The marker is written before `close_pane`, on the premise that the close "is inevitable", but the close can fail and the marker is never withdrawn.

**Where:** lines 186–187
```
  write_teardown_marker "$pane" "${SESSION_ID:-}" teammate-idle
  close_pane "$pane"
```

**Why it is wrong:**
- On an RPC error or timeout (rc≠0, logged at line 195), the pane stays alive but carries a fresh `mode=teammate-idle` marker.
- If that session genuinely crashes within the reader's freshness window, it is classified as a deliberate teardown rather than a crash.

---

### 11. The worktree is removed even when no pane was closed

**What:** Worktree removal runs regardless of whether any pane close happened or succeeded.

**Where:** lines 962 and 970
```
      log "  ! no pane id resolved for $MEMBER_NAME — left for CC session-end cleanup"
```
```
  if [[ -n "$WORKTREE" ]] && $WORKTREE_OWNED; then
```

**Why it is wrong:**
- When no pane is resolved, or `close_pane` fails, the teammate's claude process is still running.
- Its cwd is nonetheless `--force`-removed from under it, leaving a live session in a deleted directory.

---

### 12. The fallback patch reports success without checking the write

**What:** The "✓ fallback patch" line is logged unconditionally after the redirect.

**Where:** lines 797–798
```
    } > "$PATCH" 2>/dev/null
    log "  ✓ fallback patch: $PATCH"
```

**Why it is wrong:**
- If `/tmp` is full, or the path is unwritable, the redirect fails silently.
- The log still claims a patch exists, which matters most when the checkpoint also failed and this patch is the only trace.

---

### 13. The SURFACE messages overstate the number of defers

**What:** After the `DEFER_COUNT + 1 < MAX_DEFERS` change, only `MAX_DEFERS-1` defers occur, but the messages report `MAX_DEFERS`.

**Where:**
- line 721
  ```
      log "⚑ SURFACE $TEAMMATE_NAME (team=$TEAM_NAME): reap-guard has deferred $MAX_DEFERS times on a SHARED cwd ($WORKTREE) — ...
  ```
- line 756
  ```
    log "⚑ SURFACE $TEAMMATE_NAME (team=$TEAM_NAME): WORKTREE unresolved after $MAX_DEFERS defers — refusing ungated close, paging desk (session=$SESSION_ID)"
  ```

**Why it is wrong:**
- With the default of 3, the forensic log and the desk page say "3 defers" when 2 happened.
- The shared counter also includes dirty-tree defers, so "reap-guard has deferred N times" can be true of none of them.
- With `TEAMMATE_MAX_DEFERS=1`, zero defers happen but the message says 1.
