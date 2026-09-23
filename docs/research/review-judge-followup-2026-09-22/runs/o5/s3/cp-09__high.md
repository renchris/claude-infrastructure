## Defects

---

### 1. The pane-id lookup matches *any* member-name candidate in config order, so it can resolve — and force-close — a sibling teammate's pane

**Where** — lines 813–818 (plus the candidate list built at 432–435):

```bash
  RESOLVED=$(jq -r --args \
    '.members[]? | select(.name as $n | $ARGS.positional | index($n)) | "\(.name)\t\(.tmuxPaneId // "")"' \
    "${MEMBER_CANDIDATES[@]}" < "$CONFIG" 2>/dev/null | head -1)
  if [[ -n "$RESOLVED" && "$RESOLVED" == *$'\t'* ]]; then
    MEMBER_NAME="${RESOLVED%%$'\t'*}"
    PANEID="${RESOLVED#*$'\t'}"
```

**Why it is wrong** — `MEMBER_CANDIDATES` is `("quality-keeper-2" "quality-keeper")`, and the jq filter selects a member whose name is in *either* slot, iterating `.members[]` in **config order**; `head -1` then takes whichever appears first in the file, not the exact-name match. The auto-increment convention the code itself documents at line 412 (`quality-keeper → quality-keeper-2`) is precisely the situation where both names exist in the same `config.json`. If `quality-keeper` is listed first, a TeammateIdle for `quality-keeper-2` resolves `quality-keeper`'s `tmuxPaneId`, and the detached block calls `it2 session close -f -s` on a *live, unrelated* teammate's pane. `MEMBER_NAME` is overwritten too, so the log records `✓ closed pane X (quality-keeper)` and the incident is invisible. This directly violates the stated invariant at line 220 ("A forced close must never be able to hit the wrong pane") — the `--agent-id` safety gate only protects the *fallback* resolver, not this primary one.

---

### 2. The same candidate-priority inversion in two worktree resolvers marks a sibling's worktree `WORKTREE_OWNED=true`, which then `--force`-removes it

**Where** — lines 459–460 (`resolve_from_manifest`) and 517–518 (`resolve_by_worktree_name`):

```bash
    for m in "${MEMBER_CANDIDATES[@]}"; do
      if [[ "$name" == "$m" ]]; then
```

```bash
    for m in "${MEMBER_CANDIDATES[@]}"; do
      if [[ "$base" == "$m" && -d "$wt" ]]; then printf '%s\n' "$wt"; return 0; fi
```

**Why it is wrong** — in both functions the *record* loop is outer and the *candidate* loop is inner, so the first record matching **any** candidate wins rather than the exact name. With members `gu5-verdict` and `gu5-verdict-2` both present (manifest entry, or two worktrees in `git worktree list`), a TeammateIdle for `gu5-verdict-2` returns `gu5-verdict`'s tree. Because a basename/manifest match is treated as per-member proof of ownership (lines 470–471 and 540–541 set `WORKTREE_OWNED=true`), the detached block at line 972 runs `git worktree remove "$WORKTREE" --force` on the *other, still-running* teammate's worktree, discarding its uncommitted work — and every gate above (busy-marker, dirty-defer, reap-guard, checkpoint) was evaluated against that wrong tree as well. The TSV, `/tmp`, glob and config-cwd legs all loop candidates outermost and are correct; only these two are inverted.

---

### 3. The operator-adoption belt fails **open** when no transcript is found — including the documented `SESSION_ID="unknown"` default

**Where** — lines 889–895 and 929–930:

```bash
    _adopt_tj="$(_find_transcript "$SESSION_ID" || true)"
```
```bash
    if [[ -n "$_adopt_tj" ]]; then
```
```bash
    fi
  fi
```

**Why it is wrong** — the `if [[ -n "$_adopt_tj" ]]` block has no `else`. When `_find_transcript` misses (session id is the literal `"unknown"` from the line 404 parse; the transcript lives outside `$PROJECT_ROOTS` or deeper than `-maxdepth 2`; `$HOME` contains a space, since line 302 word-splits `$PROJECT_ROOTS` unquoted) **and** the `paneUUID` registry lookup at 890–893 also misses, execution falls straight through to the pane close with no log line, no desk page, and — unlike the missing-lib branch at 887 — no `_beat_or_hold` consult. This is exactly the fail-open the adjacent comments forbid ("absence of evidence is not evidence of absence on an actuator that force-closes a pane", 854–855): `rc 2` holds, an absent lib holds, but a *missing transcript* silently closes. The same input also disables the other transcript gate — `_tool_in_flight` line 382, `[[ -n "$sid" && "$sid" != "unknown" ]] || return 1`, returns "no tool in flight", which the caller reads as licence to proceed. So a payload with no `session_id` reaches `close_and_log` with both who-gates and the liveness gate silently skipped.

---

### 4. The worktree is `--force`-removed even when the checkpoint failed and the fallback patch cannot hold the work it is claimed to hold

**Where** — lines 779, 794–795, and 969–972:

```bash
    log "  ✗ checkpoint failed for $WORKTREE — writing fallback patch"
```
```bash
      echo "# --- diff HEAD (tracked changes only) ---"
      git -C "$WORKTREE" diff HEAD 2>/dev/null || true
```
```bash
  if [[ -n "$WORKTREE" ]] && $WORKTREE_OWNED; then
```

**Why it is wrong** — `CHECKPOINT_OK` is computed at 773–780 and then never consulted again except to print a header string at 791. The removal at 969 gates only on `$WORKTREE_OWNED`. The header comment (lines 6–10) promises the checkpoint preserves "tracked + untracked work" and that the `/tmp` patch is the fallback "if the checkpoint fails for any reason". But the patch body is only `git status --porcelain` plus `git diff HEAD`, i.e. tracked changes; untracked files are listed by name and never captured. So for a teammate whose worktree contains untracked new files (the common case for a teammate that just wrote new source/test files) and whose checkpoint failed — corrupt repo, permission issue, `teammate-checkpoint.sh` missing → rc 127 — `git worktree remove --force` deletes those files, and the patch that the log at 791 tells the operator to "rely on" does not contain them. The comment at 945–946 ("Work is already checkpointed above, so removing the worktree here cannot lose work") asserts a premise the code never verified.

---

### 5. The teardown marker is written before the close and is never retracted when the close fails, so a surviving teammate carries a "we closed it" record

**Where** — lines 186–195:

```bash
  write_teardown_marker "$pane" "${SESSION_ID:-}" teammate-idle
  close_pane "$pane"
  local rc=$?
```
```bash
    log "  ✗ pane close FAILED (rc=$rc) for $pane ($who): ${err:-<no stderr>}"
```

**Why it is wrong** — the marker records an *intention*, but the reader (`lead-crash-watchdog.sh classify_death`) consumes it as the fact that this session was deliberately torn down. When `close_pane` returns non-zero for a real reason — `timeout` fires (rc 124) because the iTerm2 API is wedged, the it2 shim errors, `tmux` is not on the hook's minimal PATH (rc 127) — the pane stays open and the teammate keeps running, yet `<sid>.json` and `<pane>.json` now exist. Per the comment at 160, writers never delete markers, so if that teammate genuinely crashes inside the reader's freshness window it will be classified as an intentional close, not a crash. That is the exact masking hazard the comment at 182–185 says it placed the write here to avoid; the guard it chose (call site) does not cover a close that is attempted and fails.

---

### 6. With `pipefail` set, `git status --porcelain | grep -q .` can report a dirty tree as clean

**Where** — line 45, and lines 640 and 784:

```bash
set -uo pipefail
```
```bash
  if git -C "$WORKTREE" status --porcelain 2>/dev/null | grep -q .; then
```

**Why it is wrong** — `grep -q` exits as soon as it reads the first line. If `git status` is still writing when that happens (its output exceeds the ~64 KB pipe buffer, i.e. roughly 800+ modified/untracked paths — a worktree with untracked build output or a vendored dependency tree), git dies on `SIGPIPE` with status 141. Under `pipefail` the pipeline status is 141, the `if` is false, and `TREE_DIRTY` stays `false`. The dirty-tree defer (Rule 3) is then skipped for the *dirtiest* trees, and the fallback-patch block at 784 is skipped too — after which line 972 removes the worktree with `--force`. The same construct at line 396, `| grep -qxF "$tu_id" && return 1`, fails the same way: if jq is SIGPIPE'd after grep matches, the `&&` does not fire and `_tool_in_flight` reports "in flight" for a tool that already returned.

---

### 7. The sole-occupant ownership test compares a `/private`-stripped path against the raw config values, so it can never hold for a `/private`-recorded cwd

**Where** — lines 611 and 616:

```bash
    cfg_cwd="${cfg_cwd#/private}"
```
```bash
    _occupants=$(jq -r --arg c "$cfg_cwd" '[.members[]? | select((.cwd // "") == $c)] | length' "$TEAM_CONFIG" 2>/dev/null)
```

**Why it is wrong** — `cfg_cwd` has had its `/private` prefix removed, but the jq comparison is against the untransformed `.cwd` strings still in the file. When the config records `/private/tmp/...` or `/private/var/...` (the macOS realpath form this file acknowledges at lines 509–511), the count is `0`, not `1`, for a genuinely dedicated single-member cwd. `WORKTREE_OWNED` stays false, the log at 620 emits the false statement "SHARED by 0 members", and the worktree is never removed. The check therefore decides ownership on a string that is guaranteed absent from the data it queries rather than on occupancy.

---

### 8. The defer accounting performs `MAX_DEFERS - 1` defers while the log lines and pages state `MAX_DEFERS`

**Where** — lines 654, 720 and 755:

```bash
if $TREE_DIRTY && (( DEFER_COUNT + 1 < MAX_DEFERS )); then
```
```bash
      log "⚑ SURFACE $TEAMMATE_NAME (team=$TEAM_NAME): reap-guard has deferred $MAX_DEFERS times on a SHARED cwd ($WORKTREE) — this member records the lead's cwd, so no gate can ever read its real tree and it will never self-reap. Pane NOT closed. Fix at spawn (give the member its own cwd) or close manually (session=$SESSION_ID)"
```
```bash
  log "⚑ SURFACE $TEAMMATE_NAME (team=$TEAM_NAME): WORKTREE unresolved after $MAX_DEFERS defers — refusing ungated close, paging desk (session=$SESSION_ID)"
```

**Why it is wrong** — with the default `MAX_DEFERS=3` the predicate is true for `DEFER_COUNT` 0 and 1 only, so two defers occur and the third event acts. The counter file never reaches 3, the log never prints `(3/3)`, and both SURFACE lines and the operator-facing page assert "deferred 3 times"/"after 3 defers" when two happened — a wrong count in the record the file itself treats as forensic. The boundary also makes the documented tuning knob degenerate: `TEAMMATE_MAX_DEFERS=1` produces zero defers, so the dirty-tree backstop never runs at all rather than running once.

---

### 9. The reap is logged as having happened before the who-gate that can still refuse it

**Where** — line 769:

```bash
log "Auto-shutdown idle teammate: $TEAMMATE_NAME (team: $TEAM_NAME)"
```

**Why it is wrong** — this line, plus the counter reset at 767 and the checkpoint/patch at 774–799, all execute before the operator-adoption belt at 860–931, which can `exit 0` on three separate paths (`_beat_or_hold` at 887, unreadable oracle at 914, adoption hold at 926) without closing anything. For an operator-adopted pane the lifecycle log records "Auto-shutdown idle teammate: X" on every single idle event while the teammate is never shut down, and the defer counter that the dirty-tree backstop depends on is cleared on each of those passes.

*(Line numbers are counted from the file exactly as presented in the brief and may be off by one or two in the long comment blocks; the quoted lines are verbatim.)*
