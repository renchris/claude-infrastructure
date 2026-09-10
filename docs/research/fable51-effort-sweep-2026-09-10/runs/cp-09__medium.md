I read the full hook text and traced each gate, resolver, and the close path. Findings below. Line numbers are counted from the brief text as given, starting at `#!/bin/bash` as line 1.

## Defects

**1. The pane-id resolver can close a different live member's pane when names collide with the stripped `-N` candidate.**

Where: lines 814 to 816 and 821

```bash
  RESOLVED=$(jq -r --args \
    '.members[]? | select(.name as $n | $ARGS.positional | index($n)) | "\(.name)\t\(.tmuxPaneId // "")"' \
    "${MEMBER_CANDIDATES[@]}" < "$CONFIG" 2>/dev/null | head -1)
```

Why it is wrong: the jq filter accepts any member whose name is in the candidate list, and `head -1` keeps whichever appears first in file order. For teammate `quality-keeper-2` the candidates are `quality-keeper-2` and `quality-keeper`. If a live member named `quality-keeper` is listed earlier in the config, the resolved pane is that member's pane. The detached close then force-closes `quality-keeper`'s pane and writes a teardown marker for it, while `quality-keeper-2` stays open. The other legs iterate candidates in preference order. This one does not, and the header comment on line 133 claims a stale id "can never hit the wrong pane".

**2. The by-name worktree leg has the same ordering problem and marks the wrong tree as owned and removable.**

Where: lines 517 to 519

```bash
    for m in "${MEMBER_CANDIDATES[@]}"; do
      if [[ "$base" == "$m" && -d "$wt" ]]; then printf '%s\n' "$wt"; return 0; fi
    done
```

Why it is wrong: the outer loop walks `git worktree list` output in git's order and returns the first worktree whose basename matches either candidate. For `foo-2`, a worktree named `foo` listed before `foo-2` wins. The caller then sets `WORKTREE_OWNED=true` on line 541. All gates run against member `foo`'s tree, and the detached block on line 973 runs `git worktree remove --force` on it, discarding a different live member's uncommitted work.

**3. A teardown marker is written before the close, and it is not removed when the close fails, so a kept-alive teammate's later genuine crash is masked.**

Where: lines 186 and 187

```bash
  write_teardown_marker "$pane" "${SESSION_ID:-}" teammate-idle
  close_pane "$pane"
```

Why it is wrong: when `close_pane` returns a real failure (RPC error, or the timeout wrapper's exit 124), the branch on line 194 logs it and the pane stays open with a live session inside. The marker under both keys stays on disk because writers never delete markers. The next time that session dies for real, the watchdog reader finds the marker and classifies the death as a teammate-idle close. The comment on lines 182 to 185 states the marker must only exist once the close is inevitable, and this path violates that.

**4. The operator-adoption belt falls open when no transcript can be found, closing the pane with no who-gate evaluated.**

Where: lines 890, 896, and 930 to 932

```bash
    _adopt_tj="$(_find_transcript "$SESSION_ID" || true)"
```
```bash
    if [[ -n "$_adopt_tj" ]]; then
```

Why it is wrong: if the transcript for the session id is missing from every project root, and the pane-keyed lookup on lines 891 to 895 also misses, the belt does nothing and execution reaches the close on line 942. The lib-absent case calls `_beat_or_hold`, and the unreadable case holds and pages, but the "cannot locate the transcript at all" case is not routed to either. When reap-guard is not executable, the log line on line 737 says this belt is the only who-gate. In that combination an operator-adopted pane is force-closed with zero presence evidence, which is the exact failure the surrounding comments say must be impossible.

**5. The defer cap honours one fewer defer than the documented tuning value, and a value of 1 yields no defer at all.**

Where: lines 654, 715, and 749

```bash
if $TREE_DIRTY && (( DEFER_COUNT + 1 < MAX_DEFERS )); then
```

Why it is wrong: the file header on line 14 and the tuning note on line 40 describe `TEAMMATE_MAX_DEFERS=<N>` as the number of defers. The condition defers only while the incremented count is strictly below N, so the last logged defer is `(N-1/N)`. With the default of 3 a dirty tree is deferred twice, not three times. With `TEAMMATE_MAX_DEFERS=1` a dirty tree is never deferred and is reaped on the first idle event. The counter also never reaches N on disk, so the on-disk value no longer matches the log line's denominator. The comment on line 653 describes this as intended, but the exported contract and the header still promise N.

**6. Empty parse results are not normalised to `unknown`, so a missing jq produces empty identifiers rather than the documented sentinel.**

Where: lines 402 to 404

```bash
TEAMMATE_NAME=$(echo "$INPUT" | jq -r '.teammate_name // "unknown"' 2>/dev/null)
```

Why it is wrong: the `// "unknown"` default only applies inside jq. If jq is absent or fails, the substitution yields an empty string. `MEMBER_CANDIDATES` becomes a single empty name, the defer counter path on line 634 becomes `defer--.count` shared by every teammate, and the teardown marker guard on line 164 only checks for the literal `unknown`, so an empty session id is treated as "no sid" while an empty pane id is still possible. The comments on lines 157 to 159 assume the sentinel is always `unknown`.

## Lower confidence

**7. The teardown marker and transcript lookups assume the hook payload's `session_id` is the teammate's session.**

Where: line 404 and line 186

```bash
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null)
```

Why it may be wrong: the header on line 3 says the hook fires on the lead. If the payload's session id is the lead's, the tool-in-flight check, the adoption check, and the marker file on line 170 all key on the lead. A marker named after the lead's session would make a later genuine lead crash read as a teammate-idle close. The fallback on lines 891 to 895 resolving a session by pane suggests the author was not certain the id maps to the teammate. I cannot confirm from the text which session the payload carries, so this is a premise to verify rather than a proven fault.
