Line numbers below are counted from the brief and may be off by one or two. The verbatim lines are the anchor.

**1. Base-name candidate matching can select a sibling member, so the hook can close another teammate's pane and force-remove its worktree.**
Where (~line 433-434, 815-816, 518, 457-460):
```
if [[ "$TEAMMATE_NAME" =~ ^(.+)-[0-9]+$ ]]; then
  MEMBER_CANDIDATES+=("${BASH_REMATCH[1]}")
'.members[]? | select(.name as $n | $ARGS.positional | index($n)) | "\(.name)\t\(.tmuxPaneId // "")"' \
    "${MEMBER_CANDIDATES[@]}" < "$CONFIG" 2>/dev/null | head -1)
      if [[ "$base" == "$m" && -d "$wt" ]]; then printf '%s\n' "$wt"; return 0; fi
```
Why: names get auto-incremented exactly when the base name already exists, so `quality-keeper` and `quality-keeper-2` are usually both live members. The jq filter selects any member whose name is in the candidate list and `head -1` takes config order, so for `quality-keeper-2` it returns `quality-keeper`'s `tmuxPaneId` and `MEMBER_NAME`. The worktree-name and manifest legs iterate worktrees/members in list order and accept the first candidate match, so `WORKTREE` becomes the base member's tree with `WORKTREE_OWNED=true`. The detached block then closes the wrong pane and runs `git worktree remove --force` on the wrong teammate's tree, destroying its uncommitted work. The file's own invariant, "a forced close must never be able to hit the wrong pane", does not hold.

**2. The forced worktree removal runs even when the checkpoint failed or the pane close failed, and the fallback patch does not carry untracked files.**
Where (~line 780, 796, 970-973):
```
    log "  ✗ checkpoint failed for $WORKTREE — writing fallback patch"
      git -C "$WORKTREE" diff HEAD 2>/dev/null || true
  if [[ -n "$WORKTREE" ]] && $WORKTREE_OWNED; then
      git -C "$MAIN_REPO" worktree remove "$WORKTREE" --force 2>/dev/null \
```
Why: when `teammate-checkpoint.sh` fails, the only remaining trace is a patch of tracked changes. `git worktree remove --force` deletes untracked files, so new files the teammate created are lost, contradicting the comment "removing the worktree here cannot lose work". The removal also does not consult the result of `close_and_log`, so a pane whose close failed (rc≠0, logged as FAILED) leaves a live teammate running inside a directory that is deleted from under it.

**3. The teardown marker is written before the close and never retracted when the close fails.**
Where (~line 186-187):
```
  write_teardown_marker "$pane" "${SESSION_ID:-}" teammate-idle
  close_pane "$pane"
```
Why: on a real close failure (RPC error, timeout) the teammate stays alive, but a `mode=teammate-idle` marker now exists under its sid and pane keys. If that teammate later crashes within the reader's freshness window, the watchdog classifies the death as a planned teardown. The comment justifies the placement with "the close is inevitable", which the FAILED branch of the same function shows is not true.

**4. An unresolvable registry row turns birth-grace into a permanent, unbounded, unpaged defer.**
Where (~line 692, 726-728):
```
  if [[ "$_started_ms" =~ ^[0-9]+$ ]]; then _spawn_s=$(( _started_ms / 1000 )); else _spawn_s="$(date +%s)"; fi
    log "defer $TEAMMATE_NAME (team=$TEAM_NAME): reap-guard DEFER (birth-grace / no-products / operator-adopted)"
    # Do NOT emit {"continue": false}; let the just-born teammate keep working.
    exit 0
```
Why: if `cc-sessions` has no row for the session (the file itself notes registry rows get overwritten) or is not on the hook's minimal PATH, spawn-time is recomputed as "now" on every invocation. Reap-guard's birth-grace therefore never expires. For an owned worktree this exits without charging the defer counter or paging, so the teammate is never reaped and nothing surfaces, which is the silent-guard class the comment at the shared-cwd branch says must not exist.

**5. The operator-adoption belt falls open when no transcript can be located.**
Where (~line 890, 896):
```
    _adopt_tj="$(_find_transcript "$SESSION_ID" || true)"
    if [[ -n "$_adopt_tj" ]]; then
```
Why: an absent lib is held via `_beat_or_hold`, and an unreadable transcript is held and paged, but a transcript that cannot be found at all (including `SESSION_ID` equal to `unknown`, which `_find_transcript` does not reject) skips the whole block and proceeds to the close. When reap-guard is not executable, the WARN at line 737 says this belt is "the only who-gate", so a missing transcript licenses an ungated force-close.

**6. The sole-occupant test compares a normalized path against raw config values.**
Where (~line 611, 616):
```
    cfg_cwd="${cfg_cwd#/private}"
    _occupants=$(jq -r --arg c "$cfg_cwd" '[.members[]? | select((.cwd // "") == $c)] | length' "$TEAM_CONFIG" 2>/dev/null)
```
Why: the file acknowledges that `/private/tmp/x` and `/tmp/x` are two spellings of one directory. If this member recorded `/tmp/x` and siblings recorded `/private/tmp/x`, the count is 1, `WORKTREE_OWNED` becomes true, and the shared tree is force-removed. In the opposite mix the count is 0 and the log reports "SHARED by 0 members".
