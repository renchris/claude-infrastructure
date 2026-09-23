# Review of `hooks/teammate-auto-shutdown.sh`

I found 11 defects. Line numbers are my own count of the brief's listing. The quoted code is exact, so use it as the anchor if a number is off by a line or two.

---

### 1. Pane lookup can close a sibling teammate's pane
**What:** The pane resolver takes the first config member that matches *any* name candidate, so an auto-incremented teammate can resolve to its base-named sibling's pane.

**Where:** L814–816
```
  RESOLVED=$(jq -r --args \
    '.members[]? | select(.name as $n | $ARGS.positional | index($n)) | "\(.name)\t\(.tmuxPaneId // "")"' \
    "${MEMBER_CANDIDATES[@]}" < "$CONFIG" 2>/dev/null | head -1)
```

**Why:** Take teammate `quality-keeper-2`.
- `MEMBER_CANDIDATES` is `(quality-keeper-2 quality-keeper)` (L432–434).
- The `-2` suffix exists only because `quality-keeper` was already a member, so that sibling normally comes first in `.members`.
- `head -1` therefore returns the sibling's name and `tmuxPaneId`.
- The detached block then force-closes the live sibling's pane (L951) and writes a teardown marker for it.

---

### 2. Worktree-by-name and manifest legs can claim a sibling's worktree as OWNED
**What:** Both legs accept the suffix-stripped candidate as per-member evidence, and do so before an exact-name match is considered.

**Where:**
- L518 `      if [[ "$base" == "$m" && -d "$wt" ]]; then printf '%s\n' "$wt"; return 0; fi`
- L541 `      WORKTREE_OWNED=true`
- Also the manifest leg at L460 `      if [[ "$name" == "$m" ]]; then`

**Why:**
- The outer loop walks worktrees (or manifest members) and the inner loop walks candidates. A `quality-keeper` worktree or manifest entry listed before `quality-keeper-2`'s therefore wins.
- The same happens when the teammate has no own-named worktree at all.
- The same happens for a distinct member whose real name ends in digits, e.g. `phase-2` stripping to `phase`.
- `WORKTREE_OWNED=true` is then set. After the close, `git worktree remove "$WORKTREE" --force` (L973) destroys the sibling's worktree and its uncommitted work.

---

### 3. `/tmp` glob fallback matches other members' and other teams' worktrees and marks them OWNED
**What:** The `*` in the glob matches any characters, including `-`, so the match is only a suffix match on the member name.

**Where:** L585 `    for candidate in /tmp/wt-*-"${m}" /tmp/worktree-*-"${m}"; do` (followed by L588 `WORKTREE_OWNED=true`)

**Why:**
- A teammate named `tester` matches `/tmp/wt-anyteam-unit-tester`, which belongs to member `unit-tester` or to another team entirely.
- A stripped candidate widens this further.
- The resolved tree is marked owned, so it is `--force`-removed at L973.

---

### 4. `pipefail` plus `grep -q` makes a heavily dirty tree read as clean
**What:** Under `set -o pipefail`, the dirty-tree test fails whenever `git status` is killed by SIGPIPE after `grep -q` exits on its first match.

**Where:**
- L640 `  if git -C "$WORKTREE" status --porcelain 2>/dev/null | grep -q .; then`
- L785 `  if git -C "$WORKTREE" status --porcelain 2>/dev/null | grep -q .; then`

**Why:**
- When the porcelain output exceeds the pipe buffer (many changed or untracked files), `git` gets SIGPIPE and exits 141, so the pipeline returns non-zero.
- At L640, `TREE_DIRTY` stays `false`, so the dirty-tree defer is skipped.
- At L785, the fallback patch is not written.
- Both failures hit exactly the trees with the most unsaved work.

---

### 5. Worktree is force-removed even when the checkpoint failed, and the fallback patch omits untracked files
**What:** Removal is gated only on `WORKTREE_OWNED`, never on `CHECKPOINT_OK`, even though the fallback patch contains only tracked diffs.

**Where:** L973 `      git -C "$MAIN_REPO" worktree remove "$WORKTREE" --force 2>/dev/null \`, with L796 `      git -C "$WORKTREE" diff HEAD 2>/dev/null || true`

**Why:**
- If `teammate-checkpoint.sh` fails (L780 path), the only preserved trace is the patch.
- The patch holds a `git status` listing plus `diff HEAD`, which is tracked changes only.
- `--force` then deletes the untracked files' contents permanently.
- The comment at L947 ("Work is already checkpointed above, so removing the worktree here cannot lose work") is false on this path.

---

### 6. Fallback patch is logged as written even when the write failed
**What:** The success log is unconditional.

**Where:** L797–798
```
    } > "$PATCH" 2>/dev/null
    log "  ✓ fallback patch: $PATCH"
```

**Why:**
- If the redirect fails (e.g. `/tmp` full, or a name collision with an unwritable file), no patch exists.
- The log still records `✓ fallback patch`.
- Combined with #5, a failed checkpoint and a failed patch are both followed by a `--force` removal, while the log claims the work was preserved.

---

### 7. Worktree is removed regardless of whether the pane was actually closed
**What:** The removal block runs after every close outcome, including a failed close and "no pane id resolved".

**Where:** L970 `  if [[ -n "$WORKTREE" ]] && $WORKTREE_OWNED; then`

**Why:**
- When `close_and_log` logs `✗ pane close FAILED`, or the else-branch logs `no pane id resolved … left for CC session-end cleanup` (L962), the teammate process is still alive.
- Its working directory is `--force`-deleted underneath it anyway.
- Any work it produced after the checkpoint is lost.

---

### 8. Operator-adoption belt falls open when the transcript can't be found or the oracle's answer isn't numeric
**What:** If no transcript is located, or `ci_last_interactive_epoch` returns something other than rc 2 with a non-numeric value, the belt proceeds to close without consulting `_beat_or_hold`.

**Where:**
- L896 `    if [[ -n "$_adopt_tj" ]]; then`
- L917 `      if [[ "$_iep" =~ ^[0-9]+$ ]]; then`
- Root cause for the missing transcript: L64, the hardcoded `PROJECT_ROOTS` of four dirs.

**Why:**
- `_beat_or_hold` is documented as "Consulted whenever the transcript WHO-oracle could not answer" (L342), but it is only called when the lib is absent.
- The transcript goes missing when the session runs under a config dir not in `PROJECT_ROOTS`. This is the same unlisted-root class the file fixed for `TEAM_ROOTS` via `~/.claude*`.
- It also goes missing when `SESSION_ID` is `unknown` and the `_alt_sid` lookup misses.
- It also happens when the lib returns an unexpected rc such as 127.
- In every such case "could not answer" is treated as "nobody typed", and an adopted pane is force-closed.

---

### 9. Teardown marker is written before the close outcome is known
**What:** The marker is written on the premise that the close will succeed. On the lead-side model it is also keyed to the wrong session.

**Where:** L186 `  write_teardown_marker "$pane" "${SESSION_ID:-}" teammate-idle`

**Why:**
- The marker is written before `close_pane`. When the close fails with a real error (the `✗` branch at L195), the pane stays live but a `mode=teammate-idle` marker exists. A genuine crash of that session within the reader's freshness window is then misclassified as a deliberate teardown, which is exactly what the comment at L185 says must not happen.
- The header says the hook "Fires (LEAD-side)" (L3). On that model the payload's `session_id` is the lead's. The sid-keyed `<sid>.json` marker then masks a crash of the *lead*.

---

### 10. A malformed hold window silently disables the only remaining who-gate
**What:** A non-numeric or zero `CC_CLASSIFY_INTERACTIVE_HOLD_S` turns the operator-adoption belt off with no log line.

**Where:** L860 `{ [[ "$INTERACTIVE_HOLD_S" =~ ^[0-9]+$ ]] && (( INTERACTIVE_HOLD_S > 0 )); } || _hold_on=0`

**Why:**
- A value like `6h` or `21600s` fails the regex, so `_hold_on=0`.
- The whole adoption block is skipped and the close proceeds.
- The documented kill switch is `…_HOLD_DISABLE=1`, but a typo in the tuning variable has the same effect silently. That contradicts the file's own "absence is loud" posture (L732–736).

---

### 11. SURFACE log lines and pages overstate the number of defers taken
**What:** The messages say the teammate was deferred `$MAX_DEFERS` times, but the `DEFER_COUNT + 1 < MAX_DEFERS` logic allows only `MAX_DEFERS − 1` defers before acting.

**Where:**
- L721 `      log "⚑ SURFACE $TEAMMATE_NAME (team=$TEAM_NAME): reap-guard has deferred $MAX_DEFERS times on a SHARED cwd …`
- L756 `  log "⚑ SURFACE $TEAMMATE_NAME (team=$TEAM_NAME): WORKTREE unresolved after $MAX_DEFERS defers …`

**Why:**
- With the default `MAX_DEFERS=3`, only `defer (1/3)` and `(2/3)` occur; the third event surfaces.
- The shared counter can also already be at the cap from dirty-tree defers, in which case this leg deferred zero times.
- Either way the forensic log and desk page report defers that never happened.
