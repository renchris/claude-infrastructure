I read the whole file. Here are the defects I can point at.

**1. Pane lookup can resolve a sibling teammate's pane and force-close it.**

Where, lines 814–816:
```
  RESOLVED=$(jq -r --args \
    '.members[]? | select(.name as $n | $ARGS.positional | index($n)) | "\(.name)\t\(.tmuxPaneId // "")"' \
    "${MEMBER_CANDIDATES[@]}" < "$CONFIG" 2>/dev/null | head -1)
```
Why: `MEMBER_CANDIDATES` holds both the exact name and the suffix-stripped base name, and the filter accepts any member matching either, in config order, then takes the first. CC only auto-increments to `quality-keeper-2` when `quality-keeper` already exists in the team, so both members are typically listed, with the base-named one earlier. When `quality-keeper-2` goes idle, the hook resolves `quality-keeper`'s pane and name, and the detached block runs `it2 session close -f` or `tmux kill-pane` on the live sibling's pane, while the marker and log record the sibling as torn down. This is exactly the wrong-pane close the file says must be impossible.

**2. The operator-adoption belt falls open when no transcript is found.**

Where, line 896:
```
    if [[ -n "$_adopt_tj" ]]; then
```
Why: there is no else branch. If the transcript for `SESSION_ID` is not found under the scanned project roots, and the pane-to-sid registry lookup on lines 891–895 also misses, the whole who-gate is skipped and execution reaches the close on line 942. That happens whenever the payload has no `session_id` (it defaults to the literal `unknown`, so `_find_transcript` searches for `unknown.jsonl`), or when the transcript lives under a root not in `PROJECT_ROOTS`. The tool-in-flight gate on line 676 also returns "not in flight" for the same inputs, so an adopted pane is force-closed on unproven absence, the case the surrounding comments say must hold and page.

**3. The dirty-tree test can report a dirty tree as clean under `pipefail`.**

Where, line 640 (and the same pattern on line 785):
```
  if git -C "$WORKTREE" status --porcelain 2>/dev/null | grep -q .; then
```
Why: `set -o pipefail` is on (line 45). `grep -q` exits on the first match. If git still has output to write (status output larger than one stdio flush, and certainly larger than the 64 KiB pipe buffer, e.g. many changed or untracked paths), git dies of SIGPIPE, the pipeline status is non-zero, and `TREE_DIRTY` stays false. The dirty-tree defer is then skipped and the hook proceeds toward reap. On line 785 the same failure suppresses the fallback patch, so the "always has a recoverable trace" promise is also broken for exactly the largest dirty trees.

**4. Occupant count compares a stripped path against raw config paths, so a dedicated `/private` cwd is never owned.**

Where, line 616:
```
    _occupants=$(jq -r --arg c "$cfg_cwd" '[.members[]? | select((.cwd // "") == $c)] | length' "$TEAM_CONFIG" 2>/dev/null)
```
Why: `cfg_cwd` had its `/private` prefix removed on line 611, but the members' `.cwd` values are compared raw. For a cwd recorded as `/private/tmp/...`, the count is 0, including the member itself. The tree is then treated as shared, the log on line 620 says "SHARED by 0 members", and the reap-guard shared-cwd branch on lines 712–724 charges defers and finally pages "records the LEAD's cwd", a claim that is false. The member never reaps and its worktree is never removed.

**5. Name-based worktree resolution can claim a sibling's worktree as owned and force-remove it.**

Where, line 518:
```
      if [[ "$base" == "$m" && -d "$wt" ]]; then printf '%s\n' "$wt"; return 0; fi
```
Why: the outer loop is over worktrees and the inner loop over candidates, so the first worktree whose basename matches either the exact name or the stripped base name wins. For teammate `quality-keeper-2`, a sibling worktree named `quality-keeper` listed earlier by `git worktree list` is returned and marked `WORKTREE_OWNED=true` on line 541, ahead of the member's own tree. The detached block then runs `git worktree remove --force` on the sibling's tree, discarding its uncommitted work.

**6. Legacy glob matches on suffix, resolving another member's worktree as owned.**

Where, line 585:
```
    for candidate in /tmp/wt-*-"${m}" /tmp/worktree-*-"${m}"; do
```
Why: the `*` is unanchored, so member `keeper` matches `/tmp/wt-team-quality-keeper`, and the stripped candidate for `quality-keeper-2` matches `/tmp/wt-team-quality-keeper`. Either sets `WORKTREE_OWNED=true` on line 588 and the close path force-removes a tree that belongs to a different member.

**7. Birth-grace defer becomes permanent and silent when the spawn time cannot be resolved.**

Where, line 692:
```
  if [[ "$_started_ms" =~ ^[0-9]+$ ]]; then _spawn_s=$(( _started_ms / 1000 )); else _spawn_s="$(date +%s)"; fi
```
Why: if `cc-sessions` is absent or the session is not in the registry, the spawn time is recomputed as "now" on every event. Reap-guard sees a just-born teammate every time and returns DEFER, which the owned-worktree branch on line 726 treats as unbounded and self-resolving. It never resolves, is never charged to `MAX_DEFERS`, and never pages, so the teammate stays up indefinitely with no alarm.

**8. `TEAMMATE_MAX_DEFERS=N` yields N-1 defers, and the surfaced messages report the wrong count.**

Where, line 654 (same test on lines 715 and 749):
```
if $TREE_DIRTY && (( DEFER_COUNT + 1 < MAX_DEFERS )); then
```
Why: with the default of 3, only two defers happen before the hook acts, so the header's "Max defers: 3" and the log format `($DEFER_COUNT/$MAX_DEFERS)` never reach 3/3. Setting `TEAMMATE_MAX_DEFERS=1` disables deferral entirely. The SURFACE lines 721 and 756 and the desk pages then state "deferred 3 times" and "after 3 defers" when two occurred.
