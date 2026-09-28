I found six defects. Line numbers count `#!/bin/bash` as line 1.

## 1. An idle auto-incremented teammate resolves to the sibling's pane and gets that pane closed

**What:** The pane lookup returns the first config member that matches any name candidate. It does not prefer the exact name, so `worker-2` can resolve to `worker`'s `tmuxPaneId`.

**Where:** lines 815–816
```
    '.members[]? | select(.name as $n | $ARGS.positional | index($n)) | "\(.name)\t\(.tmuxPaneId // "")"' \
    "${MEMBER_CANDIDATES[@]}" < "$CONFIG" 2>/dev/null | head -1)
```

**Why it is wrong:** `MEMBER_CANDIDATES` for `quality-keeper-2` is `(quality-keeper-2 quality-keeper)`. The `select` accepts either name, and `head -1` keeps whichever member comes first in `.members[]`. The original `quality-keeper` is normally listed before `-2`, so it wins. `MEMBER_NAME` and `PANEID` then belong to the sibling, and `close_and_log` force-closes the sibling's live pane. This contradicts the "close the EXACT pane" premise.

## 2. The worktree name leg and the manifest leg can hand back a sibling's worktree as "owned", and it is then force-removed

**What:** Both resolvers loop over worktrees or manifest entries in the outer loop and over candidates in the inner loop. The exact name therefore has no precedence over the `-N`-stripped name.

**Where:** line 518 (`resolve_by_worktree_name`)
```
      if [[ "$base" == "$m" && -d "$wt" ]]; then printf '%s\n' "$wt"; return 0; fi
```
The same shape is at line 460 (`resolve_from_manifest`)
```
      if [[ "$name" == "$m" ]]; then
```

**Why it is wrong:** Take idle teammate `worker-2` while `worker` also exists. The stripped candidate `worker` matches the first entry in `git worktree list` or the manifest, which is usually the older `worker`. `WORKTREE` becomes `worker`'s tree and `WORKTREE_OWNED=true` is set (lines 470–471 for the manifest leg, 540–541 for the name leg). The dirty, busy and reap-guard gates then read the wrong tree. The detached block runs `git worktree remove "$WORKTREE" --force` (line 973) on it. The live sibling's uncommitted work is destroyed.

## 3. When the operator-adoption oracle has no transcript to read, the close proceeds anyway

**What:** If no transcript can be found, the who-oracle never answers, yet the code falls through to the force-close. The beat second oracle is consulted only when the lib is absent.

**Where:** line 896
```
    if [[ -n "$_adopt_tj" ]]; then
```
There is no `else` branch. The block closes at lines 930–932, and execution continues to the stop JSON at line 942 and the close.

**Why it is wrong:** `SESSION_ID` can be `"unknown"` (payload lacks `session_id`), or the `.jsonl` can sit outside `PROJECT_ROOTS`. In either case `_find_transcript` fails, and the `cc-sessions` pane-UUID fallback (lines 891–895) can also fail. `_adopt_tj` is then empty, so the whole adoption check is skipped and the pane is force-closed. That is "cannot prove absent" treated as "absent". The file's own comments (lines 345, 349–352 and 873–887) say `_beat_or_hold` is consulted whenever the transcript WHO-oracle could not answer, and that absence of evidence must not license the close.

## 4. The worktree is force-removed even when the checkpoint failed or the teammate may still be running

**What:** The `--force` removal depends only on `WORKTREE_OWNED`. It ignores `CHECKPOINT_OK` and the result of the pane close.

**Where:** line 973
```
      git -C "$MAIN_REPO" worktree remove "$WORKTREE" --force 2>/dev/null \
```
The comment at lines 946–947 asserts "Work is already checkpointed above, so removing the worktree here cannot lose work."

**Why it is wrong:** That assertion holds only if the checkpoint succeeded. The fallback patch uses `git diff HEAD` (line 796, "tracked changes only") and never contains untracked files. When `teammate-checkpoint.sh` fails (line 780) and the tree has untracked work, that work is not preserved anywhere and the removal deletes it. The removal also runs when `close_and_log` logged `✗ pane close FAILED`, or when no pane was resolved (line 962, "left for CC session-end cleanup"). A live teammate session then has its working directory deleted, and anything it writes after the checkpoint is lost.

## 5. `grep -q` under `pipefail` can report a dirty tree as clean

**What:** Both dirty-tree tests pipe `git status` into `grep -q .` inside an `if`, with `set -o pipefail` in effect (line 45).

**Where:** line 640
```
  if git -C "$WORKTREE" status --porcelain 2>/dev/null | grep -q .; then
```
and line 785
```
  if git -C "$WORKTREE" status --porcelain 2>/dev/null | grep -q .; then
```

**Why it is wrong:** `grep -q` exits on the first line. If the status output is larger than one write or pipe buffer, `git` can still be writing and dies of SIGPIPE (rc 141). With `pipefail` the pipeline status becomes 141, the `if` is false, and `TREE_DIRTY` stays `false` at line 640. The dirty-defer is skipped for exactly the teammates with the most uncommitted changes. At line 785 the fallback patch is skipped.

## 6. A failed fallback-patch write is logged as a success

**What:** The `✓ fallback patch` line is logged unconditionally after a redirection whose failure is discarded.

**Where:** lines 797–798
```
    } > "$PATCH" 2>/dev/null
    log "  ✓ fallback patch: $PATCH"
```

**Why it is wrong:** If `/tmp/...patch` cannot be created (no space, permissions, name collision with a directory), the redirection fails and the group body never runs. The log still says the patch was written. When the checkpoint also failed, the log claims a recoverable trace exists that does not. Combined with defect 4, the worktree is then removed.
