I found 10 defects. Line numbers are my hand count of the listing; the quoted code is verbatim.

---

### 1. A heavily dirty tree can be read as clean
- **What:** With `set -o pipefail`, `git status --porcelain | grep -q .` can come out false even when the tree is dirty.
- **Where:** L640 `  if git -C "$WORKTREE" status --porcelain 2>/dev/null | grep -q .; then` and L785 `  if git -C "$WORKTREE" status --porcelain 2>/dev/null | grep -q .; then`
- **Why it is wrong:** `grep -q` exits on the first match. When the status output is longer than one stdio buffer (many dirty or untracked files), git's next write gets SIGPIPE and git exits 141. Under pipefail the pipeline then returns non-zero.
  - At L640 `TREE_DIRTY` stays false, so the dirty-tree defer is skipped.
  - At L785 the fallback patch is not written.
  - The more uncommitted work there is, the more likely both are skipped.

### 2. The worktree is force-removed even when the checkpoint failed
- **What:** `git worktree remove --force` runs whether or not the checkpoint succeeded, and the fallback patch does not hold untracked files.
- **Where:** L973 `      git -C "$MAIN_REPO" worktree remove "$WORKTREE" --force 2>/dev/null \`. `CHECKPOINT_OK` is set at L777 but never read before the removal. The patch body is L796 `      git -C "$WORKTREE" diff HEAD 2>/dev/null || true`.
- **Why it is wrong:** Suppose `teammate-checkpoint.sh` fails (corrupt repo, permissions) on an owned tree with untracked files. The patch records only their names (via `status`) plus the tracked diff. The removal then deletes the untracked contents. So the claim at L946–947 ("Work is already checkpointed above, so removing the worktree here cannot lose work") rests on an unproven premise.

### 3. A failed fallback-patch write is logged as success
- **What:** The patch write's failure is discarded, and success is logged unconditionally.
- **Where:** L797–798 `    } > "$PATCH" 2>/dev/null` / `    log "  ✓ fallback patch: $PATCH"`
- **Why it is wrong:** If `/tmp` is full or unwritable, or the redirect fails, the log still says `✓ fallback patch`. In the checkpoint-failed case this patch is the only claimed recovery trace, so the log reports a success that did not happen.

### 4. The suffix-stripped name can resolve a sibling's pane
- **What:** The pane lookup matches any `MEMBER_CANDIDATES` entry and takes the first hit in config order. The suffix-stripped candidate can therefore select a different, live teammate's pane.
- **Where:** L814–816 `  RESOLVED=$(jq -r --args \` / `    '.members[]? | select(.name as $n | $ARGS.positional | index($n)) | "\(.name)\t\(.tmuxPaneId // "")"' \` / `    "${MEMBER_CANDIDATES[@]}" < "$CONFIG" 2>/dev/null | head -1)`
- **Why it is wrong:** Take a team with both `quality-keeper` and `quality-keeper-2`, where `quality-keeper-2` goes idle. The candidates are `{quality-keeper-2, quality-keeper}`. If config lists `quality-keeper` first, `head -1` returns its row, and `quality-keeper`'s pane is force-closed. There is no preference for the exact name.

### 5. Worktree legs can claim a sibling's tree as owned
- **What:** Several resolution legs can resolve a sibling's worktree for this teammate and mark it `WORKTREE_OWNED=true`.
- **Where:**
  - L459–460 `    for m in "${MEMBER_CANDIDATES[@]}"; do` / `      if [[ "$name" == "$m" ]]; then` (the member loop is outer, so an earlier `quality-keeper` entry wins)
  - L517–518 `    for m in "${MEMBER_CANDIDATES[@]}"; do` / `      if [[ "$base" == "$m" && -d "$wt" ]]; then printf '%s\n' "$wt"; return 0; fi`
  - L585 `    for candidate in /tmp/wt-*-"${m}" /tmp/worktree-*-"${m}"; do`
- **Why it is wrong:**
  - Stripped-suffix case: `quality-keeper-2` resolves `quality-keeper`'s manifest entry or `.../quality-keeper` worktree when that one appears first.
  - Glob case: the `*` in L585 also absorbs hyphens, so member `keeper` matches `/tmp/wt-team-quality-keeper`.
  - In each case `WORKTREE_OWNED=true`. The sibling's tree is then gated on, checkpointed under the wrong member, and `git worktree remove --force`d at L973, destroying the sibling's uncommitted work.

### 6. The adoption belt fails open when the transcript is not found
- **What:** When the who-oracle lib is present but no transcript can be found, the adoption check is skipped and the close proceeds. The beat oracle is never consulted.
- **Where:** L896 `    if [[ -n "$_adopt_tj" ]]; then` (there is no `else`; control falls through to L942 and the close)
- **Why it is wrong:** Examples of a missing transcript:
  - `SESSION_ID="unknown"`
  - the transcript sits deeper than `-maxdepth 2`
  - the root is not in `PROJECT_ROOTS`
  - `PANEID` is empty, so the alt-sid lookup is skipped

  In any of these, operator presence is unprovable. Yet the pane is force-closed without `_beat_or_hold`, which is documented as "Consulted whenever the transcript WHO-oracle could not answer". The unreadable case (rc 2) holds, but the not-found case does not.

### 7. The teardown marker is written before the close outcome is known
- **What:** The marker is written first and is never retracted if the close fails.
- **Where:** L186–187 `  write_teardown_marker "$pane" "${SESSION_ID:-}" teammate-idle` / `  close_pane "$pane"`
- **Why it is wrong:** If `close_pane` fails (RPC error, timeout rc 124, it2 failure), the pane and its session stay alive, but a `mode=teammate-idle` marker exists for its sid and pane. A genuine crash of that session within the reader's freshness window is then classified as a deliberate teardown. That is the masking the comment at L182–185 says the marker placement avoids. The comment's premise that the close is "inevitable" is false.

### 8. The shared-cwd occupant count compares mismatched path forms
- **What:** The occupant count compares the `/private`-stripped `cfg_cwd` against the raw, unstripped `.cwd` values in the config.
- **Where:** L611 `    cfg_cwd="${cfg_cwd#/private}"` and L616 `    _occupants=$(jq -r --arg c "$cfg_cwd" '[.members[]? | select((.cwd // "") == $c)] | length' "$TEAM_CONFIG" 2>/dev/null)`
- **Why it is wrong:** Suppose this member recorded `/tmp/x` while the lead or siblings recorded `/private/tmp/x`. The count is `1`, so `WORKTREE_OWNED=true` and the shared tree is `--force`-removed at L973. The reverse mixture yields `0`, which is merely mislabelled.

### 9. Birth-grace deferral can never end when spawn time is unresolvable
- **What:** When the registry spawn time cannot be resolved, spawn time is set to "now" on every invocation. On an owned tree the resulting reap-guard defer is unbounded, silent, and never terminates.
- **Where:** L692 `  if [[ "$_started_ms" =~ ^[0-9]+$ ]]; then _spawn_s=$(( _started_ms / 1000 )); else _spawn_s="$(date +%s)"; fi` and L726 `    log "defer $TEAMMATE_NAME (team=$TEAM_NAME): reap-guard DEFER (birth-grace / no-products / operator-adopted)"`
- **Why it is wrong:** If `cc-sessions` is missing from the hook's minimal PATH, or has no row for the sid, every event evaluates birth-grace against spawn=now. Every event therefore defers, and it is never charged to `MAX_DEFERS` or surfaced. This is the "always-defers, zero bits" failure the shared-cwd branch was changed to escape. Birth-grace is not self-resolving here.

### 10. The worktree is removed even when the pane was not closed
- **What:** Worktree removal runs regardless of whether the pane close succeeded or a pane was resolved at all.
- **Where:** L970 `  if [[ -n "$WORKTREE" ]] && $WORKTREE_OWNED; then` (reached after the L958–963 branches, including `log "  ! no pane id resolved ... left for CC session-end cleanup"`, and after `close_and_log` failures)
- **Why it is wrong:** When the close fails, or no pane id resolves, the teammate's claude session is still alive. Its working directory is force-removed underneath it, and any later turn (for example, the lead messaging it) runs in a deleted worktree.
