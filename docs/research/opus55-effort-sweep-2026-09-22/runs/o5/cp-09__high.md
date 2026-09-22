## Findings

Line numbers are counted with `#!/bin/bash` as line 1; the quoted line is the authoritative anchor if my count is off by one or two.

---

### 1. The operator-adoption belt is skipped entirely when the transcript cannot be located, and falls through to the force-close

**Where** — ~888, ~894, ~928–930:
```bash
    _adopt_tj="$(_find_transcript "$SESSION_ID" || true)"
```
```bash
    if [[ -n "$_adopt_tj" ]]; then
```

**Why it is wrong** — The belt handles three states explicitly: lib absent (`_beat_or_hold`), oracle rc 2 "unreadable" (hold + page), oracle says nobody typed (proceed). It does **not** handle "no transcript file found": if `_find_transcript` misses and the `paneUUID` registry fallback also misses, the `if [[ -n "$_adopt_tj" ]]` body is never entered, no hold and no page occur, and control falls straight through to `echo '{"continue": false...}'` and the detached `close_and_log`. A missing transcript is the same epistemic state as rc 2 ("cannot read the answer"), which the comment at ~853 says "HOLDS + pages... absence of evidence is not evidence of absence on an actuator that force-closes a pane." `PROJECT_ROOTS` (~64) is a hardcoded four-entry list that, unlike `TEAM_ROOTS`, does not include `$CLAUDE_CONFIG_DIR/projects` and does not glob `~/.claude*/projects` — so a session led from any config dir outside those four has no findable transcript, the only who-gate silently no-ops, and an operator-adopted pane is force-closed. This is the exact hardcoded-root class the file documents and fixes for `TEAM_ROOTS` at lines 76–83.

---

### 2. The occupants count compares a `/private`-stripped path against the unstripped `.cwd`, so a dedicated worktree is misread as shared

**Where** — ~610 and ~615:
```bash
    cfg_cwd="${cfg_cwd#/private}"
```
```bash
    _occupants=$(jq -r --arg c "$cfg_cwd" '[.members[]? | select((.cwd // "") == $c)] | length' "$TEAM_CONFIG" 2>/dev/null)
```

**Why it is wrong** — `cfg_cwd` is read from `.cwd`, then has `/private` stripped; the jq count then compares that stripped value against the *raw* `.cwd` values in the same file. When the config records a `/private`-prefixed path (the exact spelling the file says macOS produces for anything under `/var` or `/tmp`, see the comment at ~508–513), the count matches zero rows: `_occupants` is `0`, `WORKTREE_OWNED` stays false, and the log emits the self-contradictory `worktree <path> is SHARED by 0 members` even though this member demonstrably occupies it. The teammate's own dedicated worktree is then never removed, and it is routed into the shared-cwd defer/SURFACE arm (~711–723), where after the defer cap it is permanently held open and paged as "records the LEAD's cwd" — a false diagnosis of a member that owns its tree.

---

### 3. The ownership test only counts member rows in this one config, so a one-member team always reads as sole occupant

**Where** — ~615–617:
```bash
    _occupants=$(jq -r --arg c "$cfg_cwd" '[.members[]? | select((.cwd // "") == $c)] | length' "$TEAM_CONFIG" 2>/dev/null)
    if [[ "$_occupants" == "1" ]]; then
      WORKTREE_OWNED=true
```

**Why it is wrong** — The comment at ~613 asserts "any sibling (**the lead counts**) sharing it ⇒ shared", but nothing in the code counts the lead; it counts rows in `.members[]`, which elsewhere in this file is only ever queried for *teammate* names (~485, ~812). If the lead is not itself a `.members[]` row, a team with a single teammate — whose `cwd` is by construction the lead's spawn cwd on the implicit-team model — yields `_occupants == 1`, sets `WORKTREE_OWNED=true`, and the detached block runs `git worktree remove "$WORKTREE" --force` on the **lead's** checkout, discarding the lead's uncommitted and untracked work. That is precisely the outcome the whole `WORKTREE_OWNED` mechanism (lines 416–428) exists to make impossible, and the premise it rests on is never checked.

---

### 4. The teardown marker is written before the close and is never retracted when the close fails

**Where** — ~186 and ~195:
```bash
  write_teardown_marker "$pane" "${SESSION_ID:-}" teammate-idle
```
```bash
    log "  ✗ pane close FAILED (rc=$rc) for $pane ($who): ${err:-<no stderr>}"
```

**Why it is wrong** — The marker's contract is deterministic evidence that this session was *deliberately torn down*, so `lead-crash-watchdog`'s classify ladder does not call CRASH. The comment justifies the placement with "the close is inevitable" — but inevitable is not the same as successful. When `close_pane` fails (an `it2` RPC error, or the 8s `tas_bounded` timeout on a wedged iTerm2 — the exact failure mode `tas_bounded` was added for), rc is non-zero, the `✗ pane close FAILED` branch runs, and the pane and its session stay alive — with the teardown marker already on disk and never deleted ("Writers never delete markers"). If that still-live session later genuinely crashes, the reader finds the marker and classifies a real crash as a deliberate teammate-idle teardown, which is the masking the marker design explicitly forbids (~157–159).

---

### 5. The fallback patch omits untracked files, and the worktree is then force-removed

**Where** — ~793–794 and ~973:
```bash
      echo "# --- diff HEAD (tracked changes only) ---"
      git -C "$WORKTREE" diff HEAD 2>/dev/null || true
```
```bash
      git -C "$MAIN_REPO" worktree remove "$WORKTREE" --force 2>/dev/null \
```

**Why it is wrong** — Rule 1 (lines 6–8) says the checkpoint preserves "tracked **+ untracked** work"; Rule 2 (lines 9–10) designates the `/tmp/*.patch` as the fallback for when that checkpoint fails. But the patch body contains only `git diff HEAD`, which excludes untracked files — it records their *names* via `status --porcelain` and none of their contents. So on the one path the fallback exists to cover (`CHECKPOINT_OK=false` on a tree with new, never-added files), the hook writes a patch that cannot restore those files and then runs `worktree remove --force`, which deletes the unclean tree including its untracked content. The work is destroyed while the log reports `✓ fallback patch: <path>`.

---

### 6. The fallback patch is logged as written without checking that the write succeeded

**Where** — ~795–796:
```bash
    } > "$PATCH" 2>/dev/null
    log "  ✓ fallback patch: $PATCH"
```

**Why it is wrong** — The redirection's status is never examined and stderr is discarded. If `/tmp` is not writable, the filesystem is full, or the name collides with something undeletable, the block produces no usable file, yet the very next line unconditionally logs a success with a path that may not exist. The operator's only record of the last-resort recovery artifact then points at nothing — a failure reported as a success, immediately before the worktree is removed.

---

### 7. `MAIN_REPO` is derived from `--git-common-dir` without `--path-format=absolute`, and the `sed` cannot strip the bare `.git` form

**Where** — ~971:
```bash
    MAIN_REPO=$(git -C "$WORKTREE" rev-parse --git-common-dir 2>/dev/null | sed 's|/\.git$||')
```

**Why it is wrong** — `rev-parse --git-common-dir` is not guaranteed to return an absolute path; from a main working tree it returns the literal `.git`, and relative forms are possible elsewhere. The same file already knows this and passes `--path-format=absolute` in `resolve_from_manifest` (~450), but not here. With output `.git`, the `sed` anchor `/\.git$` does not match (no leading slash), so `MAIN_REPO=".git"`, and `-d "$MAIN_REPO"` is then evaluated against the hook process's arbitrary cwd: it either fails — silently skipping the removal with no log line at all, since `log` only runs on the `&&` success side — or accidentally succeeds against an unrelated repository's `.git`, in which case `git -C .git worktree remove` is issued in the wrong repository. Either way the `WORKTREE_OWNED=true` removal that the code believes it performed never happens and nothing records that.

---

### 8. The "this teammate only" pane-resolution gate accepts the `-N`-stripped member name, so it can match a different agent

**Where** — ~231 (with the candidate list built at ~431–434):
```bash
        if [[ -n "$m" && "$cmd" == *"--agent-id ${m}@"* ]]; then
```

**Why it is wrong** — The safety claim at lines 217–220 is "only ever resolve from a process whose command contains `--agent-id <THIS teammate>@` ... never another teammate. A forced close must never be able to hit the wrong pane." But `MEMBER_CANDIDATES` also contains the trailing-`-N`-stripped form, so for idle teammate `quality-keeper-2` the walk up the ancestor chain matches any `claude.exe` running as `--agent-id quality-keeper@...`. On the LEAD-side model (which this hook still supports, per lines 30–35) that ancestor chain runs through the lead's own `claude.exe`; when that lead is itself an agent of a parent team named `quality-keeper`, `_find_teammate_pid` returns the **lead's** pid, `_pane_from_env`/`_pane_from_tty` resolve the lead's pane, and `close_and_log` force-closes it. The name-collision-modulo-`-N` case is exactly the case the auto-increment suffix exists to create.

---

### 9. A non-numeric `CC_CLASSIFY_INTERACTIVE_HOLD_S` silently disables the whole who-gate, including its fail-closed arms

**Where** — ~858:
```bash
{ [[ "$INTERACTIVE_HOLD_S" =~ ^[0-9]+$ ]] && (( INTERACTIVE_HOLD_S > 0 )); } || _hold_on=0
```

**Why it is wrong** — The variable is documented at line 41 purely as a tuning knob for the hold *window*; `CC_CLASSIFY_INTERACTIVE_HOLD_DISABLE=1` is the documented kill switch. But a malformed or `0` value here sets `_hold_on=0`, which skips the entire `if (( _hold_on ))` block — not just the window comparison, but the lib-absent `_beat_or_hold`, the rc-2 unreadable hold, and the adoption hold. Setting `CC_CLASSIFY_INTERACTIVE_HOLD_S=6h` (or any typo) therefore turns off the only who-gate on this force-close actuator with no log line and no page, while the operator believes they only adjusted a duration. Every other unprovable-presence path in this file fails closed; this one fails open.

---

### 10. The defer cap permits `MAX_DEFERS - 1` defers, so the documented count and the `(N/N)` log line are unreachable

**Where** — ~653 (and identically at ~714 and ~747), with the contract stated at line 14:
```bash
if $TREE_DIRTY && (( DEFER_COUNT + 1 < MAX_DEFERS )); then
```

**Why it is wrong** — With the default `MAX_DEFERS=3`, the predicate is true for `DEFER_COUNT` 0 and 1 only: the teammate defers twice and acts on the third event. The header contract ("Max defers: 3 (backstop)"), the SURFACE messages ("after `$MAX_DEFERS` defers", "has deferred `$MAX_DEFERS` times"), and the `($DEFER_COUNT/$MAX_DEFERS)` progress log all describe three defers; `(3/3)` can never be logged and the SURFACE text overstates the number of deferrals actually performed by one. Under `TEAMMATE_MAX_DEFERS=1` the hook reaps on the first idle event with zero defers, which reads from the configuration as "defer once".
