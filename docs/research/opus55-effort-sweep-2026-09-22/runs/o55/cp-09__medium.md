# Review of `hooks/teammate-auto-shutdown.sh`

I found five defects. Line numbers are counted from the `#!/bin/bash` line as line 1.

---

### 1. The stripped member name can resolve to a different, live teammate

**What:** The script adds a second candidate name with the numeric suffix removed. Every resolver then accepts the first member, worktree or config entry matching *either* name, so a sibling teammate's pane or worktree can be chosen.

**Where:**
- Lines 433–434:
  `if [[ "$TEAMMATE_NAME" =~ ^(.+)-[0-9]+$ ]]; then`
  `  MEMBER_CANDIDATES+=("${BASH_REMATCH[1]}")`
- Consumed at line 815:
  `'.members[]? | select(.name as $n | $ARGS.positional | index($n)) | "\(.name)\t\(.tmuxPaneId // "")"' \`
- Consumed at line 518:
  `if [[ "$base" == "$m" && -d "$wt" ]]; then printf '%s\n' "$wt"; return 0; fi`
- Consumed at line 460:
  `if [[ "$name" == "$m" ]]; then`

**Why it is wrong:**
- Take a team with members `quality-keeper` and `quality-keeper-2`. When `quality-keeper-2` idles, the candidates are `quality-keeper-2` and `quality-keeper`.
- The jq pane lookup walks `.members` in config order and keeps the first match (`head -1`). If `quality-keeper` is listed first, `PANEID` is set to the sibling's pane, which is then force-closed.
- The worktree-name leg and the manifest leg iterate worktrees or members in the outer loop. They can therefore return the sibling's worktree first and mark it `WORKTREE_OWNED=true`.
- That worktree is then gated on, checkpointed and removed with `git worktree remove --force`, destroying the sibling's uncommitted work.
- The same happens with the `cfg_cwd` leg (line 610).

---

### 2. The `/tmp` glob fallback matches other members by suffix

**What:** The glob fallback matches any directory whose name *ends* with `-<member>`, not one whose member segment *is* `<member>`, and marks that directory as owned.

**Where:** Line 585:
`for candidate in /tmp/wt-*-"${m}" /tmp/worktree-*-"${m}"; do`
(followed by `WORKTREE_OWNED=true` at line 588)

**Why it is wrong:**
- For a member named `keeper`, the `*` in `/tmp/wt-*-keeper` also matches `team-quality`. So `/tmp/wt-team-quality-keeper`, which belongs to member `quality-keeper`, is selected.
- It is marked owned, so it is gated on, checkpointed and then removed with `--force` in the detached block, deleting another member's worktree.

---

### 3. A missing transcript lets the close through with no presence check

**What:** When the WHO-oracle lib is present but no transcript can be found for the session, the operator-adoption belt simply falls through to the close. It never consults the beat oracle, even though `_beat_or_hold` exists for exactly this case.

**Where:** Line 896:
`if [[ -n "$_adopt_tj" ]]; then`
This `if` has no `else`, and the enclosing blocks close at lines 930–932 straight into the close.

**Why it is wrong:**
- The doc for `_beat_or_hold` (line 342) says it is "Consulted whenever the transcript WHO-oracle could not answer."
- Suppose `_find_transcript` misses, for example because the session's project root is not in `PROJECT_ROOTS` or the sid is `unknown`, and the `paneUUID` lookup also misses.
- Then presence is unprovable, yet no hold, no page and no log line occurs. The script emits `{"continue": false}` and force-closes the pane.
- This is the "cannot prove present" read as "proven absent" failure the file says it eliminated. It is also the only who-gate for teammates where reap-guard was skipped.

---

### 4. The worktree is force-removed even when the checkpoint failed, losing untracked files

**What:** The detached block runs `git worktree remove --force` without checking `CHECKPOINT_OK`. The only fallback, the patch, captures tracked changes only, so untracked files are lost.

**Where:**
- Line 973:
  `git -C "$MAIN_REPO" worktree remove "$WORKTREE" --force 2>/dev/null \`
- The justifying comment at line 947:
  `#   the worktree here cannot lose work.`
- Line 795–796:
  `echo "# --- diff HEAD (tracked changes only) ---"` / `git -C "$WORKTREE" diff HEAD 2>/dev/null || true`

**Why it is wrong:**
- If `teammate-checkpoint.sh` fails (line 780 logs "checkpoint failed"), the script still proceeds to the close and the forced removal.
- New untracked files appear in the patch only as `??` status lines, never as content.
- `--force` then deletes them. The premise "work is already checkpointed" is never verified before this destructive action.

---

### 5. A failed fallback patch is logged as success

**What:** The patch write's failure is swallowed, and a success line is logged unconditionally.

**Where:**
- Line 797:
  `} > "$PATCH" 2>/dev/null`
- Line 798:
  `log "  ✓ fallback patch: $PATCH"`

**Why it is wrong:**
- If `/tmp` is full or unwritable, or the redirection fails for any other reason, no patch file exists.
- The log still records `✓ fallback patch: <path>`.
- Combined with defect 4, the removal then proceeds on the belief that a recoverable trace exists when none does.
