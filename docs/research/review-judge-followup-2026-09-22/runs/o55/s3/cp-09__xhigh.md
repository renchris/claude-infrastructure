# Review of `hooks/teammate-auto-shutdown.sh`

I found 11 defects. Line numbers are counted from `#!/bin/bash` as line 1.

---

### 1. The pane lookup can return a sibling's pane, so the wrong teammate's pane is force-closed

**What:** The config lookup takes the first config member whose name matches *any* candidate. It does not prefer the exact name, so the stripped base-name candidate can pick up a different member's pane.

**Where:** lines 815–816
```
    '.members[]? | select(.name as $n | $ARGS.positional | index($n)) | "\(.name)\t\(.tmuxPaneId // "")"' \
    "${MEMBER_CANDIDATES[@]}" < "$CONFIG" 2>/dev/null | head -1)
```
(Candidates are built at line 434: `  MEMBER_CANDIDATES+=("${BASH_REMATCH[1]}")`)

**Why it is wrong:**
- Take teammate `quality-keeper-2`. It was auto-incremented because a member `quality-keeper` already exists. Its candidates are `(quality-keeper-2, quality-keeper)`.
- `config.json` lists `quality-keeper` before `quality-keeper-2`. The jq filter walks members in config order, so the first matching row is `quality-keeper`.
- `head -1` keeps that row. `PANEID` becomes the sibling's pane and `MEMBER_NAME` becomes the sibling's name.
- Line 951 then force-closes a live sibling's pane.

---

### 2. The manifest and worktree-name legs can claim a sibling's worktree as OWNED

**What:** Both legs test the candidate list inside the per-record loop. The base-name candidate therefore matches an earlier sibling record before the exact name is ever tried, and the result is marked `WORKTREE_OWNED=true`.

**Where:**
- line 460: `      if [[ "$name" == "$m" ]]; then` (inside `for (( i=0; i<count; i++ ))`, line 457)
- line 518: `      if [[ "$base" == "$m" && -d "$wt" ]]; then printf '%s\n' "$wt"; return 0; fi` (inside the `git worktree list` loop, line 506)
- lines 471 and 541: `  WORKTREE_OWNED=true` / `      WORKTREE_OWNED=true`

**Why it is wrong:**
- For `quality-keeper-2`, the manifest (or `git worktree list`) may list `quality-keeper` first. That is the member whose existence caused the auto-increment.
- The record matches the stripped candidate and is returned as this member's dedicated tree, even if a `quality-keeper-2` record exists further down.
- The effects:
  - All gates read the sibling's tree.
  - The checkpoint is filed under the wrong member.
  - Line 973 runs `git worktree remove "$WORKTREE" --force` on the sibling's live worktree.

---

### 3. The glob fallback is a bare suffix match but is treated as proof of per-member ownership

**What:** `/tmp/wt-*-<member>` matches any worktree whose name merely *ends* in `-<member>`. That includes other members and other teams, yet the match is marked OWNED.

**Where:** line 585 and line 588
```
    for candidate in /tmp/wt-*-"${m}" /tmp/worktree-*-"${m}"; do
        WORKTREE_OWNED=true
```

**Why it is wrong:**
- Suppose member `reviewer` has no `/tmp` worktree of its own. Then `/tmp/wt-*-reviewer` matches `/tmp/wt-teamA-code-reviewer`, or another team's `/tmp/wt-teamB-reviewer`.
- `*` absorbs any prefix, including `code-` or another team slug.
- The teammate is then gated and checkpointed against someone else's tree, and that tree is force-removed at line 973.

---

### 4. The worktree is force-removed even when the checkpoint failed, which loses untracked work

**What:** `CHECKPOINT_OK` is computed but never consulted before removal, and the "fallback" patch does not contain untracked file contents.

**Where:**
- lines 970 and 973:
  ```
    if [[ -n "$WORKTREE" ]] && $WORKTREE_OWNED; then
      git -C "$MAIN_REPO" worktree remove "$WORKTREE" --force 2>/dev/null \
  ```
- lines 795–796:
  ```
      echo "# --- diff HEAD (tracked changes only) ---"
      git -C "$WORKTREE" diff HEAD 2>/dev/null || true
  ```

**Why it is wrong:**
- Suppose `teammate-checkpoint.sh` fails (line 780 logs "checkpoint failed") and the tree holds new untracked files.
- The patch records only their names (via `status --porcelain`), not their contents.
- `--force` removal then deletes those files permanently.
- The premise at lines 946–947 ("Work is already checkpointed above, so removing the worktree here cannot lose work") is not checked.

---

### 5. The fallback patch is logged as written without checking the write

**What:** The success log fires unconditionally after the redirect.

**Where:** lines 797–798
```
    } > "$PATCH" 2>/dev/null
    log "  ✓ fallback patch: $PATCH"
```

**Why it is wrong:**
- If the redirect fails (for example `/tmp` is full, or a name contains `/` so the path is invalid), the block does not run and no patch exists.
- The log still reports `✓ fallback patch`.
- The worktree is then removed anyway (defect 4).

---

### 6. With the who-oracle library present, a missing transcript falls straight through to the close

**What:** When `_find_transcript` finds nothing, there is no else-branch. The close proceeds with no who-gate at all and the beat oracle is never consulted.

**Where:** line 896 (no `else`), following lines 890–895
```
    if [[ -n "$_adopt_tj" ]]; then
```

**Why it is wrong:**
- `_beat_or_hold` is documented as "Consulted whenever the transcript WHO-oracle could not answer" (line 342), but it is called only when the library is absent (line 888).
- Suppose the teammate's transcript is not under `PROJECT_ROOTS` at depth ≤2, or `SESSION_ID` is `unknown` and `PANEID` is empty or unregistered.
- Presence is then unprovable, yet the pane is force-closed. This is exactly the "cannot prove present ⇒ treated as absent" failure the block says it prevents. It is also the only who-gate for worktree-less teammates (lines 904–906).

---

### 7. The spawn-brief slack is measured against the wrong session when the transcript came from `_alt_sid`

**What:** The transcript can be resolved through the pane's session id, but the spawn time is always looked up for `$SESSION_ID`.

**Where:** line 919
```
        _spawn_s="$(_spawn_epoch "$SESSION_ID" || echo 0)"; [[ "$_spawn_s" =~ ^[0-9]+$ ]] || _spawn_s=0
```

**Why it is wrong:**
- The `_alt_sid` path (lines 891–894) runs precisely when `$SESSION_ID` has no transcript, typically when it is `unknown` or not the teammate's session.
- `_spawn_epoch` then misses and returns 0, so any prompt after epoch 300 counts as adoption, including the spawn brief itself.
- Every such teammate is held and paged as "operator-adopted" for the full 6-hour hold window. If `$SESSION_ID` instead maps to a different registry row, the slack window is anchored to an unrelated spawn time.

---

### 8. The worktree is force-removed even when the pane was not closed

**What:** Removal in the detached block does not depend on the close succeeding.

**Where:**
- line 962: `      log "  ! no pane id resolved for $MEMBER_NAME — left for CC session-end cleanup"`
- line 195: `    log "  ✗ pane close FAILED (rc=$rc) for $pane ($who): ${err:-<no stderr>}"`
- followed unconditionally by line 973: `      git -C "$MAIN_REPO" worktree remove "$WORKTREE" --force 2>/dev/null \`

**Why it is wrong:**
- Suppose no pane id resolves, or the close fails with an RPC error or timeout. The teammate's session is still alive.
- Its cwd is then deleted underneath it, and anything written after the checkpoint is discarded by `--force`.
- The ordering "close the EXACT pane → remove the worktree" (lines 945–946) assumes a close that was never confirmed.

---

### 9. A teardown marker is written before the close, and it persists when the close fails

**What:** The marker asserts a deliberate teardown before the close result is known.

**Where:** lines 186–187
```
  write_teardown_marker "$pane" "${SESSION_ID:-}" teammate-idle
  close_pane "$pane"
```

**Why it is wrong:**
- Lines 182–185 justify this placement by saying the close is "inevitable", but `close_pane` can fail (the branch at lines 194–195).
- The session is then live yet carries a `mode=teammate-idle` teardown marker.
- If it genuinely crashes within the reader's freshness window, the watchdog classifies the crash as a deliberate teardown. The comment names this as the exact masking it must avoid.

---

### 10. A reap-guard PROCEED on a shared cwd is trusted, although the code states that tree is the wrong one

**What:** On a shared cwd, only the DEFER outcome is treated as uninformative. A PROCEED from that same wrong-tree evaluation licenses the close.

**Where:** line 693 and line 712
```
  if ! "$REAP_GUARD" decide --worktree "$WORKTREE" --member "$TEAMMATE_NAME" --spawn-time "$_spawn_s" --session-id "$SESSION_ID" >/dev/null 2>&1; then
    if ! $WORKTREE_OWNED; then
```

**Why it is wrong:**
- With `WORKTREE_OWNED=false`, reap-guard reads the lead's shared checkout. Lines 694–698 say it "evaluated the WRONG TREE".
- If the lead or a sibling produced work products there since this teammate's spawn, reap-guard returns 0.
- The teammate is then closed on the basis of products that are not its own. The effect-read passes for the wrong reason.

---

### 11. The occupancy count compares a `/private`-stripped path against unstripped recorded cwds

**What:** `cfg_cwd` is normalised before the count, but the `.cwd` values it is compared against are not.

**Where:** lines 611 and 616
```
    cfg_cwd="${cfg_cwd#/private}"
    _occupants=$(jq -r --arg c "$cfg_cwd" '[.members[]? | select((.cwd // "") == $c)] | length' "$TEAM_CONFIG" 2>/dev/null)
```

**Why it is wrong:**
- Suppose the member's cwd was recorded as `/private/tmp/...` or `/private/var/...`. The count excludes the member itself and yields `0`.
- A genuinely sole-occupant, dedicated tree is then treated as shared. Removal is refused, and if reap-guard defers, the teammate is SURFACEd as "records the lead's cwd" with "SHARED by 0 members".
- In the reverse case, the member is recorded unprefixed and a sibling or the lead is recorded with `/private`. The count is 1, so a shared tree is marked OWNED and becomes eligible for `--force` removal.
