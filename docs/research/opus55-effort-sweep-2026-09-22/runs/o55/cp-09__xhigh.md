# Review of `hooks/teammate-auto-shutdown.sh`

I found 15 defects. They are ordered roughly by severity. Line numbers come from my count of the brief. The quoted code is verbatim.

---

### 1. Pane lookup can resolve to a sibling's pane and force-close it

**What:** The pane-id lookup takes the first config member whose name matches *any* candidate. When the teammate's name ends in `-N`, that can be the sibling with the base name.

**Where:** 816–818
```
  RESOLVED=$(jq -r --args \
    '.members[]? | select(.name as $n | $ARGS.positional | index($n)) | "\(.name)\t\(.tmuxPaneId // "")"' \
    "${MEMBER_CANDIDATES[@]}" < "$CONFIG" 2>/dev/null | head -1)
```

**Why it is wrong:**
- Take teammate `quality-keeper-2`. Its candidates are `(quality-keeper-2 quality-keeper)`.
- The config lists `quality-keeper` first. Auto-increment only happens because that member already existed, so this is the normal order.
- `head -1` then returns the sibling's row, so `PANEID` and `MEMBER_NAME` belong to the sibling.
- Line 953 force-closes the live sibling's pane and writes a teardown marker for it. The idle teammate's own pane stays open.

---

### 2. The `-N`-stripped candidate lets a sibling's worktree be marked owned

**What:** The stripped-suffix candidate is treated as the same identity. Two legs also iterate their data source before the candidate list. Together this resolves a *sibling's* worktree and marks it `WORKTREE_OWNED=true`.

**Where:** 433–434, 457–460, 518–519 (and 470–472, 541–543)
```
if [[ "$TEAMMATE_NAME" =~ ^(.+)-[0-9]+$ ]]; then
  MEMBER_CANDIDATES+=("${BASH_REMATCH[1]}")
```
```
  for (( i=0; i<count; i++ )); do
    name=$(yq eval ".members[$i].name" "$manifest" 2>/dev/null)
    for m in "${MEMBER_CANDIDATES[@]}"; do
      if [[ "$name" == "$m" ]]; then
```
```
    for m in "${MEMBER_CANDIDATES[@]}"; do
      if [[ "$base" == "$m" && -d "$wt" ]]; then printf '%s\n' "$wt"; return 0; fi
```

**Why it is wrong:**
- The manifest and `git worktree list` legs return the first matching *record*. That can be `quality-keeper` even though `quality-keeper-2` has its own entry later.
- If `quality-keeper-2` has no worktree of its own, every leg falls through to the base name and returns the sibling's tree.
- Every gate and the checkpoint then run on the wrong tree.
- Line 975 then runs `git worktree remove --force` on the live sibling's worktree.
- A name that legitimately ends in a number (e.g. `phase-2` next to `phase`) collides the same way.

---

### 3. `/tmp` and glob legs are not scoped to this team, yet claim ownership

**What:** The single-segment and glob fallbacks match other teams' and other members' directories and mark them owned.

**Where:** 571, 587, 589–590
```
      "/tmp/worktree-${m}"; do
```
```
    for candidate in /tmp/wt-*-"${m}" /tmp/worktree-*-"${m}"; do
```
```
        WORKTREE="$candidate"        # per-member path ⇒ dedicated
        WORKTREE_OWNED=true
```

**Why it is wrong:**
- `/tmp/wt-*-tests` matches `/tmp/wt-otherteam-tests`.
- It also matches `/tmp/wt-x-vt-tests`, which belongs to member `vt-tests`.
- `/tmp/worktree-reviewer` matches any team's `reviewer`.
- The first hit is gated on, checkpointed and then force-removed at 975, while it may belong to a live teammate of another team.
- The basename match at 519 has the same cross-team problem for repos shared by several teams.

---

### 4. Worktree is force-removed even when the checkpoint failed

**What:** `CHECKPOINT_OK` is computed but never consulted before `git worktree remove --force`.

**Where:** 779, 972, 975 (comment 948–949: "Work is already checkpointed above, so removing the worktree here cannot lose work.")
```
    CHECKPOINT_OK=true
```
```
  if [[ -n "$WORKTREE" ]] && $WORKTREE_OWNED; then
```
```
      git -C "$MAIN_REPO" worktree remove "$WORKTREE" --force 2>/dev/null \
```

**Why it is wrong:**
- When `teammate-checkpoint.sh` fails, the only remaining trace is the fallback patch.
- That patch holds only `git diff HEAD` (line 798). Untracked files appear by name but their contents are not saved.
- The patch may also not be written at all (see #6 and #7).
- The removal still runs, so new, never-added files are destroyed.

---

### 5. Worktree is removed even when the pane was never closed

**What:** Worktree removal is not conditioned on the pane close succeeding or even being attempted.

**Where:** 964 then 972–975
```
      log "  ! no pane id resolved for $MEMBER_NAME — left for CC session-end cleanup"
```
```
  if [[ -n "$WORKTREE" ]] && $WORKTREE_OWNED; then
```

**Why it is wrong:**
- Two cases leave the teammate process alive in its pane:
  - no pane id resolves, or
  - `close_pane` fails (RPC error or timeout, logged at 195).
- Its working directory is still `--force`-deleted underneath it.
- Anything written after the checkpoint is lost.

---

### 6. Operator-adoption belt fails open when the transcript cannot be found

**What:** If no transcript is found, the adoption belt falls straight through to the close. It never consults `_beat_or_hold`.

**Where:** 892, 898, 64
```
    _adopt_tj="$(_find_transcript "$SESSION_ID" || true)"
```
```
    if [[ -n "$_adopt_tj" ]]; then
```
```
readonly PROJECT_ROOTS="${CC_CLASSIFY_PROJECT_ROOTS:-$HOME/.claude/projects $HOME/.claude-secondary/projects $HOME/.claude-tertiary/projects $HOME/.claude-quaternary/projects}"
```

**Why it is wrong:**
- The transcript is not found when:
  - `session_id` is missing ("unknown") or empty after a jq failure, or
  - the transcript lives under a config dir not in this hardcoded list (the same class of bug the `TEAM_ROOTS` comment at 76–83 describes), and
  - no `paneUUID` registry row matches.
- "Cannot read who typed" is then treated as "nobody typed".
- The pane is force-closed with no hold, no log and no page. That contradicts line 342 ("Consulted whenever the transcript WHO-oracle could not answer").
- An rc other than 2 with non-numeric output falls open the same way at 919.

---

### 7. Dirty-tree check reads a very dirty tree, or an unreadable one, as clean

**What:** Under `pipefail`, `git status | grep -q .` can report false for a heavily dirty tree. It also reports false whenever `git status` itself fails.

**Where:** 45, 642
```
set -uo pipefail
```
```
  if git -C "$WORKTREE" status --porcelain 2>/dev/null | grep -q .; then
```

**Why it is wrong:**
- `grep -q` exits on the first line. If the status output is larger than the pipe buffer (hundreds to thousands of entries, e.g. an un-ignored build directory), git takes SIGPIPE and exits 141.
- `pipefail` makes the whole pipeline fail, so `TREE_DIRTY=false`. The dirtier the tree, the likelier it is to be treated as clean.
- A corrupt index, a non-repo path or a `safe.directory` refusal also produce no output, which reads as clean.
- In all these cases the dirty-tree defer is skipped and the reap proceeds.

---

### 8. Fallback patch is skipped in the case it exists for, and success is logged unconditionally

**What:** The patch is gated on the same broken check as #7, and success is logged whether or not the write worked.

**Where:** 787, 799–800
```
  if git -C "$WORKTREE" status --porcelain 2>/dev/null | grep -q .; then
```
```
    } > "$PATCH" 2>/dev/null
    log "  ✓ fallback patch: $PATCH"
```

**Why it is wrong:**
- The header (rule 2) promises the patch "if the checkpoint fails for any reason (corrupt repo…)".
- A corrupt repo makes `git status` fail, and a large dirty tree hits SIGPIPE, so exactly then no patch is written.
- When the patch *is* attempted, a failed write (disk full, unwritable path) is still logged as "✓ fallback patch", which the removal in #4 then relies on.

---

### 9. "Gate-only" cwd leg can grant removal rights on a shared tree

**What:** The last leg is documented as "GATE-ONLY, never removable", yet it sets `WORKTREE_OWNED=true` from an occupancy count. That count compares a `/private`-stripped path against raw recorded values.

**Where:** 598, 613, 618–620
```
# ── LAST LEG: the team config's recorded cwd — GATE-ONLY, never removable (2026-07-29) ───────────
```
```
    cfg_cwd="${cfg_cwd#/private}"
```
```
    _occupants=$(jq -r --arg c "$cfg_cwd" '[.members[]? | select((.cwd // "") == $c)] | length' "$TEAM_CONFIG" 2>/dev/null)
    if [[ "$_occupants" == "1" ]]; then
      WORKTREE_OWNED=true
```

**Why it is wrong:**
- By line 600's own premise, this cwd is the lead's.
- Occupancy is 1 whenever the lead's entry is absent, has no `cwd`, or spells it differently (e.g. `/private/tmp/x` vs `/tmp/x`).
- In that case the lead's linked worktree is `--force`-removed at 975.
- In the reverse direction, when all members recorded `/private/…` paths, the count is 0. A genuinely dedicated tree is then treated as shared.

---

### 10. On a shared cwd, a reap-guard pass on the wrong tree licenses the close

**What:** On a shared cwd the code treats reap-guard's DEFER as meaningless but still trusts its PASS. It also charges every DEFER reason to the bounded counter.

**Where:** 695, 714, 724
```
  if ! "$REAP_GUARD" decide --worktree "$WORKTREE" --member "$TEAMMATE_NAME" --spawn-time "$_spawn_s" --session-id "$SESSION_ID" >/dev/null 2>&1; then
```
```
    if ! $WORKTREE_OWNED; then
```
```
      _page_desk_damped "SHARED-CWD-NEVER-REAPS:$TEAM_NAME:$TEAMMATE_NAME" \
```

**Why it is wrong:**
- Lines 697–700 admit reap-guard evaluated "the WRONG TREE" when the cwd is shared.
- Products committed there by the lead or a sibling since spawn still make reap-guard exit 0, and the teammate is closed on that evidence.
- In the other direction, birth-grace and operator-adopted DEFERs are charged to `MAX_DEFERS`, contrary to line 712–713.
- That produces a false "defers forever — will never self-reap… confirm-close manually" page.

---

### 11. Env fallback trusts an inherited `ITERM_SESSION_ID` as the teammate's own pane

**What:** The fallback assumes the `ITERM_SESSION_ID` in the teammate's environment names the teammate's pane, but that variable is inherited.

**Where:** 247, 836
```
  line=$(ps eww -p "$pid" 2>/dev/null | tr ' ' '\n' | grep -m1 '^ITERM_SESSION_ID=')
```
```
    PANEID=$(_pane_from_env "$TEAMMATE_PID" || true)
```

**Why it is wrong:**
- Under the tmux backend, the value comes from the iTerm2 session that started the tmux server. The same applies to any claude.exe launched from another pane.
- A config-write race leaves `PANEID` empty, so this fallback runs.
- `it2 session close -f` then force-closes that other iTerm2 session, often the lead's.
- The `--agent-id` gate only validates the process, not the pane.

---

### 12. A stale root's tmux pane id can override the live root

**What:** Root resolution skips a live root whose entry has an empty pane id and accepts any root with a non-empty id. tmux ids are closed with no identity check.

**Where:** 823, 140
```
    [[ -n "$PANEID" ]] && break
```
```
    CLOSE_ERR=$(tmux kill-pane -t "$pane" 2>&1 >/dev/null)   # tmux backend: synchronous, no prompt
```

**Why it is wrong:**
- The live root may be mid-write (empty `tmuxPaneId`) while a stale same-named team dir in another root still holds an old `%N`.
- The stale id is used.
- Unlike iTerm2 UUIDs (the only no-recycle guarantee claimed at 132), tmux `%N` ids restart after a server restart. `kill-pane` can hit an unrelated live pane.

---

### 13. Tool-in-flight check only looks at the last transcript line

**What:** `_tool_in_flight` inspects only the final transcript record.

**Where:** 385
```
  last_rec="$(tail -n 1 "$f" 2>/dev/null)"
```

**Why it is wrong:**
- Suppose a turn issues several `tool_use` blocks and one's `tool_result` is appended while a later tool is still running.
- Any other record appended after the outstanding `tool_use` has the same effect.
- The last line is then not an assistant `tool_use`, so the function returns "not in flight" and a working teammate proceeds to close.
- (The `tool_result` grep at 394–396 can never match in the case it guards, because such a result would itself be the last line.)

---

### 14. Detached close block can be killed by the hangup it causes

**What:** The "detached" close block is only backgrounded. It is not separated from the pane's session or process group.

**Where:** 981
```
) >/dev/null 2>&1 &
```

**Why it is wrong:**
- On the implicit-team model, the file states the hook is a descendant of the teammate's claude.exe in the very pane being closed (208–210).
- Closing that pane hangs up its tty and SIGHUPs the foreground process group, which includes this subshell.
- The subshell can die mid-block. The close log line and the worktree removal after `close_and_log` are then silently skipped.

---

### 15. Teardown marker survives a failed close

**What:** The teardown marker is written before the close and is never retracted when the close fails.

**Where:** 186
```
  write_teardown_marker "$pane" "${SESSION_ID:-}" teammate-idle
```

**Why it is wrong:**
- If `close_pane` fails (RPC error or timeout, logged "✗ pane close FAILED"), the teammate stays alive.
- It still carries a marker that says it was deliberately torn down.
- A genuine crash of that teammate within the reader's freshness window is then classified as a teardown. This is the masking the comment at 184–185 says must not happen.
