Review of `hooks/teammate-auto-shutdown.sh` (line numbers counted from the brief text, starting at the shebang as line 1).

---

**1. Worktree removal is not gated on checkpoint success, so a failed checkpoint plus untracked files ends in `--force` deleting the only copy.**

Where: lines 970 and 973
```bash
  if [[ -n "$WORKTREE" ]] && $WORKTREE_OWNED; then
      git -C "$MAIN_REPO" worktree remove "$WORKTREE" --force 2>/dev/null \
```
Why: when `teammate-checkpoint.sh` fails (line 776 else-branch), the only preservation left is the fallback patch, and that patch captures `git diff HEAD` only (line 796, labelled "tracked changes only"). Untracked new files show up in `status --porcelain` but their content is written nowhere. The detached block then removes the worktree with `--force` regardless of `CHECKPOINT_OK`, destroying those files. The comment at lines 946-947 ("cannot lose work") is false in exactly the case the fallback exists for.

**2. Teardown marker is written before the close and never removed on close failure, so a teammate that survives a failed close carries a marker that will mask its later genuine crash.**

Where: lines 186-187 and 195
```bash
  write_teardown_marker "$pane" "${SESSION_ID:-}" teammate-idle
  close_pane "$pane"
    log "  ✗ pane close FAILED (rc=$rc) for $pane ($who): ${err:-<no stderr>}"
```
Why: on an RPC error or timeout the pane stays open and the teammate keeps running, but `<sid>.json` and `<pane>.json` markers with `mode=teammate-idle` already exist. The file states writers never delete markers (line 160), so the watchdog reader will classify a subsequent real crash of that live session as a deliberate teammate-idle close. Lines 182-185 argue the marker must only exist once the close is "inevitable"; a close that fails is not.

**3. Pane-id lookup returns the first config member matching any candidate, not the exact teammate name, so a sibling's pane can be closed.**

Where: lines 814-816
```bash
  RESOLVED=$(jq -r --args \
    '.members[]? | select(.name as $n | $ARGS.positional | index($n)) | "\(.name)\t\(.tmuxPaneId // "")"' \
    "${MEMBER_CANDIDATES[@]}" < "$CONFIG" 2>/dev/null | head -1)
```
Why: for teammate `quality-keeper-2`, `MEMBER_CANDIDATES` is `(quality-keeper-2 quality-keeper)`. If the config lists both members and `quality-keeper` appears first, `head -1` returns `quality-keeper`'s row. `PANEID` and `MEMBER_NAME` become the sibling's, the marker is written for the sibling, and its pane is force-closed while `quality-keeper-2` stays up. The other config lookups (lines 485-489, 609-623) iterate candidates exact-first; this one does not, violating the line 220 invariant.

**4. Worktree-name leg matches the stripped candidate against any worktree in list order, so a sibling's dedicated tree can be adopted as OWNED and force-removed.**

Where: lines 517-518
```bash
    for m in "${MEMBER_CANDIDATES[@]}"; do
      if [[ "$base" == "$m" && -d "$wt" ]]; then printf '%s\n' "$wt"; return 0; fi
```
Why: the outer loop is over `git worktree list` records, inner over candidates. For member `gu5-verdict-2`, if worktree `.../gu5-verdict` is listed before `.../gu5-verdict-2`, the first record matches the stripped candidate and wins. `WORKTREE_OWNED=true` is set at line 541, so every gate runs on the sibling's tree and the detached block `--force`-removes it. The same stripped-candidate acceptance applies to the TSV (line 555-558) and `/tmp` legs (565-575, 584-591).

**5. Operator-adoption belt is silently skipped when no transcript can be located, falling through to close.**

Where: line 896
```bash
    if [[ -n "$_adopt_tj" ]]; then
```
Why: there is no else branch. If `_find_transcript` misses for `SESSION_ID` (including the literal `"unknown"` from line 404) and the pane-UUID lookup at lines 891-895 also fails, `_adopt_tj` is empty and execution reaches the close at line 942 with no who-gate evaluated. The file's own rule (lines 58-60, 874-876) is that an unanswerable oracle must go through `_beat_or_hold`, as the lib-absent branch does at line 888. `_tool_in_flight` also returns 1 for a missing transcript (line 383), so both transcript-based gates vanish together.

**6. Only exit code 2 from the who-oracle is treated as "unreadable"; any other unexpected nonzero code licenses the close.**

Where: lines 898-899
```bash
      _iep="$(ci_last_interactive_epoch "$_adopt_tj" 2>/dev/null)" || _irc=$?
      if (( _irc == 2 )); then
```
Why: if the sourced lib fails internally (missing dependency, `set -u` error, rc 127, rc 3), `_iep` is empty and `_irc` is neither 0 nor 2. The `=~ ^[0-9]+$` test at line 917 then fails and control reaches the close. The three-valued contract (lines 853-856) says only rc 1 is the "nobody typed" fact; every other failure is being read as that fact.

**7. Reap-guard verdict on a shared, non-owned cwd is distrusted when it defers but trusted when it passes.**

Where: lines 693 and 712
```bash
  if ! "$REAP_GUARD" decide --worktree "$WORKTREE" --member "$TEAMMATE_NAME" --spawn-time "$_spawn_s" --session-id "$SESSION_ID" >/dev/null 2>&1; then
    if ! $WORKTREE_OWNED; then
```
Why: when `WORKTREE_OWNED` is false the tree is the lead's checkout (lines 694-698 say so explicitly). A DEFER is charged as "gates evaluated the wrong tree", but a PASS from the same wrong tree is accepted and the hook proceeds to reap. Any lead commit since spawn produces "work products" and passes the effect-read, so a pool teammate is closed on evidence about the lead. The dirty-tree gate at line 640 has the same wrong-tree input.

**8. Occupancy count compares the `/private`-stripped path against unstripped config values, so a dedicated tree can be counted as shared by zero members.**

Where: lines 611 and 616
```bash
    cfg_cwd="${cfg_cwd#/private}"
    _occupants=$(jq -r --arg c "$cfg_cwd" '[.members[]? | select((.cwd // "") == $c)] | length' "$TEAM_CONFIG" 2>/dev/null)
```
Why: if config.json records `/private/tmp/x`, `cfg_cwd` becomes `/tmp/x`, and the jq equality matches no member, including this one. `_occupants` is `0`, the tree is logged "SHARED by 0 members", `WORKTREE_OWNED` stays false, and the teammate is driven into the shared-cwd SURFACE page at line 721 that asserts it "records the LEAD's cwd", which is untrue.

**9. SURFACE messages report `MAX_DEFERS` defers when only `MAX_DEFERS - 1` occurred.**

Where: lines 721, 756, and 763
```bash
      log "⚑ SURFACE $TEAMMATE_NAME (team=$TEAM_NAME): reap-guard has deferred $MAX_DEFERS times on a SHARED cwd ($WORKTREE) — this member records the lead's cwd, so no gate can ever read its real tree and it will never self-reap. Pane NOT closed. Fix at spawn (give the member its own cwd) or close manually (session=$SESSION_ID)"
  log "⚑ SURFACE $TEAMMATE_NAME (team=$TEAM_NAME): WORKTREE unresolved after $MAX_DEFERS defers — refusing ungated close, paging desk (session=$SESSION_ID)"
```
Why: the guards at lines 654, 715 and 749 use `DEFER_COUNT + 1 < MAX_DEFERS`, so with the default 3 the counter tops out at 2 and the third event acts. The log and desk page tell the operator three defers happened. Header line 14 ("Max defers: 3") and the line 40 tuning note describe the pre-fix semantics.

**10. An invalid hold window silently disables the who-gate instead of holding.**

Where: line 860
```bash
{ [[ "$INTERACTIVE_HOLD_S" =~ ^[0-9]+$ ]] && (( INTERACTIVE_HOLD_S > 0 )); } || _hold_on=0
```
Why: a typo such as `CC_CLASSIFY_INTERACTIVE_HOLD_S=6h` turns the entire adoption belt off with no log line, and the close proceeds. The documented kill switch is a different variable (line 42). This is the "guard that can disappear without saying so" the file warns about at lines 736-737.

**11. Fallback patch is logged as written without checking the write succeeded.**

Where: lines 797-798
```bash
    } > "$PATCH" 2>/dev/null
    log "  ✓ fallback patch: $PATCH"
```
Why: if `/tmp` is unwritable or the redirect fails, the success line is still logged, and the operator is told a recoverable trace exists when it does not. Combined with defect 1, the worktree is then force-removed.
