I read the whole file. It contains real defects — several serious ones — all clustered around the name-candidate matching, the fail-open adoption gate, and the detached close/remove block. Line numbers below count the shebang as line 1 of the listing; they may drift by a line or two, but each verbatim line is unique in the file.

---

**1. Pane resolution can return a *different live member's* pane, which is then force-closed.**

- **Where:** ≈814–816
  ```
  '.members[]? | select(.name as $n | $ARGS.positional | index($n)) | "\(.name)\t\(.tmuxPaneId // "")"' \
  ```
- **Why it is wrong:** `MEMBER_CANDIDATES` for `quality-keeper-2` includes the stripped base `quality-keeper` — and the auto-increment convention exists precisely because a member named `quality-keeper` may *also* exist in the same team. The jq filter is a pure membership test with no preference for the exact name, matches are emitted in config order, and `| head -1` keeps the first. If the base-named sibling is listed before this member, `PANEID` becomes the *sibling's* pane and the detached block runs `it2 session close -f` / `tmux kill-pane` on a live, working teammate — violating the file's own stated invariant, "A forced close must never be able to hit the wrong pane."

**2. The manifest and worktree-name resolution legs have their loops nested the wrong way, so a base-named sibling's *dedicated* worktree can be resolved, marked OWNED, and force-removed.**

- **Where:** ≈457–460 and ≈518
  ```
  for (( i=0; i<count; i++ )); do
  ```
  ```
      if [[ "$base" == "$m" && -d "$wt" ]]; then printf '%s\n' "$wt"; return 0; fi
  ```
- **Why it is wrong:** Both `resolve_from_manifest` and `resolve_by_worktree_name` iterate members/worktree-list entries in the *outer* loop and candidates in the inner loop (unlike the TSV and /tmp legs, which correctly try the exact name first). For idle teammate `quality-keeper-2`, if the manifest or `git worktree list` output lists `quality-keeper` first, the sibling's tree is returned with `WORKTREE_OWNED=true`. Every gate (busy marker, dirty defer, reap-guard) then evaluates the wrong tree, the checkpoint records the sibling's work under this member's name, and the detached block runs `git worktree remove --force` on the live sibling's worktree, destroying its uncommitted and untracked work.

**3. When the checkpoint fails, untracked files have no fallback copy — yet the worktree is still force-removed, permanently deleting them.**

- **Where:** ≈796 and ≈972
  ```
        git -C "$WORKTREE" diff HEAD 2>/dev/null || true
  ```
  ```
        git -C "$MAIN_REPO" worktree remove "$WORKTREE" --force 2>/dev/null \
  ```
- **Why it is wrong:** The header promises the checkpoint preserves "tracked + untracked work" and the patch is the fallback "if the checkpoint fails for any reason." But the patch captures only a status listing and `diff HEAD` (tracked changes; the patch even says so). The removal in the detached block is gated on `WORKTREE_OWNED` but *not* on `CHECKPOINT_OK`, so in exactly the scenario the fallback exists for — checkpoint failed, tree has new untracked files — the `--force` remove deletes those files with no recoverable trace. The comment "removing the worktree here cannot lose work" is false precisely when the fallback matters.

**4. The operator-adoption who-gate silently falls open when the transcript cannot be *found* — including for every payload with a missing session_id.**

- **Where:** ≈889 and ≈895
  ```
      _adopt_tj="$(_find_transcript "$SESSION_ID" || true)"
  ```
  ```
      if [[ -n "$_adopt_tj" ]]; then
  ```
- **Why it is wrong:** The belt's own contract is three-valued and explicit: lib absent → hold via the beat; transcript unreadable (rc 2) → hold + page; "absence of evidence is not evidence of absence." But when `_find_transcript` misses (transcript in an unlisted project root, deleted transcript, or `SESSION_ID` defaulted to the literal `"unknown"`, which makes `find -name unknown.jsonl` miss) and the pane-based alt-sid lookup also misses, the `if [[ -n "$_adopt_tj" ]]` block has no else branch: execution falls straight through to the close with no hold, no beat consult, no log, no page. An unlocatable transcript — the same "cannot read the answer" class as rc 2 — licenses a who-blind force-close. Compounding it, `_tool_in_flight` (≈382) explicitly returns 1 for sid `"unknown"`, so for such payloads the liveness gate is silently skipped too.

**5. The worktree is removed even when the pane close failed or no pane was ever resolved, leaving a live session running in a deleted working directory.**

- **Where:** ≈962 and ≈969
  ```
        log "  ! no pane id resolved for $MEMBER_NAME — left for CC session-end cleanup"
  ```
  ```
    if [[ -n "$WORKTREE" ]] && $WORKTREE_OWNED; then
  ```
- **Why it is wrong:** In the detached block the removal runs unconditionally after the close attempt. If no pane id resolved, the code deliberately leaves the session alive ("left for CC session-end cleanup") — and then deletes its worktree anyway. If `close_and_log` reports a *real* failure (RPC error, timeout — the rc≠0 branch it distinguishes for exactly this reason), the pane and session survive but the removal still fires. Either way a running teammate (or the operator, in the still-open pane) is left on a force-removed tree; anything done there after the `{"continue": false}` lands in a deleted directory.

**6. `_it2_bin` prefers whatever `it2` PATH finds; the shim the comment declares REQUIRED is only the last-resort fallback.**

- **Where:** ≈105
  ```
  _it2_bin() { command -v it2 2>/dev/null || echo "$HOME/.claude/bin/it2"; }
  ```
- **Why it is wrong:** The file itself establishes that hooks run with a minimal PATH (that is why `timeout` is resolved by absolute path at ≈119–121) and that the *real* CLI's `close -f` pops iTerm2's running-job modal because force is never propagated. If the minimal PATH contains a real `it2` (e.g. `/usr/local/bin/it2`, which minimal PATHs typically include) but not `~/.claude/bin`, `command -v` resolves the real CLI, the close silently degrades to a modal prompt that nobody answers, the pane survives — and defect 5 then removes its worktree anyway. Correct behavior is only guaranteed by a PATH ordering the code does not enforce.

**7. When the registry lookup misses, `_spawn_s=0` makes the spawn-brief slack vacuous, so the spawn brief itself counts as operator adoption.**

- **Where:** ≈919 and ≈921
  ```
          _spawn_s="$(_spawn_epoch "$SESSION_ID" || echo 0)"; [[ "$_spawn_s" =~ ^[0-9]+$ ]] || _spawn_s=0
  ```
  ```
          if (( _iage < INTERACTIVE_HOLD_S )) && (( _iep > _spawn_s + FIRE_PROMPT_SLACK_S )); then
  ```
- **Why it is wrong:** The slack exists because "the spawn brief arrives as a user prompt and must NOT count as adoption." With `_spawn_s=0` (registry row missing or overwritten — a case the file itself documents as real), `_iep > 300` is true for any epoch timestamp. A never-adopted teammate spawned within the 6-hour hold window, whose only user prompt is its own spawn brief, is then held as "operator-adopted" on every idle event and pages the desk, and is never reaped. Fail-safe direction, but the gate reaches its verdict from a premise it did not prove.

**8. The sole-occupant check compares the `/private`-stripped path against the raw recorded strings, so occupancy is miscounted — in one direction dangerously.**

- **Where:** ≈611 and ≈616–617
  ```
    cfg_cwd="${cfg_cwd#/private}"
  ```
  ```
    _occupants=$(jq -r --arg c "$cfg_cwd" '[.members[]? | select((.cwd // "") == $c)] | length' "$TEAM_CONFIG" 2>/dev/null)
  ```
- **Why it is wrong:** If the config records `/private/tmp/x` for this member, `cfg_cwd` becomes `/tmp/x` and the jq string-equality count misses the member's own row (`_occupants=0`, logged as "SHARED by 0 members" and never removable — a genuinely dedicated tree leaks and later trips the false "records the LEAD's cwd" SURFACE page). Worse, if this member records `/private/tmp/x` while exactly one *other* member records the same directory spelled `/tmp/x`, the count is 1, the test passes, `WORKTREE_OWNED=true` — and a tree actually shared by two members is force-removed.

**9. A malformed `CC_CLASSIFY_INTERACTIVE_HOLD_S` silently disables the entire operator-adoption belt.**

- **Where:** ≈859
  ```
  { [[ "$INTERACTIVE_HOLD_S" =~ ^[0-9]+$ ]] && (( INTERACTIVE_HOLD_S > 0 )); } || _hold_on=0
  ```
- **Why it is wrong:** The designed disable path is the explicit `CC_CLASSIFY_INTERACTIVE_HOLD_DISABLE=1` flag. A typo'd tuning value (e.g. `"6h"`) turns off the last who-gate before a force-close with no log line and no page — the exact "guard disappears without saying so" failure the WARN at ≈737 was added to prevent for reap-guard.

**10. The teardown marker is written before the close is attempted, so a *failed* close leaves a marker that will misclassify a genuine later crash of the still-live teammate.**

- **Where:** ≈186–187
  ```
    write_teardown_marker "$pane" "${SESSION_ID:-}" teammate-idle
    close_pane "$pane"
  ```
- **Why it is wrong:** The marker contract's stated hazard is a marker that masks "a genuine crash of a teammate we then chose to KEEP." When `close_pane` fails with a real error (the rc≠0 branch `close_and_log` itself distinguishes), the teammate is kept — alive, in an open pane — yet the sid- and pane-keyed teardown markers already exist. If that teammate later crashes within the reader's freshness window, the watchdog reads `mode=teammate-idle` and classifies the death as an intended teardown: a failure reported as a success.

**11. `PAYLOAD_CWD` and the config cwds get the unconditional `/private` strip that the file's own rule says is wrong.**

- **Where:** ≈442 (also ≈534, ≈611)
  ```
  PAYLOAD_CWD="${PAYLOAD_CWD#/private}"
  ```
- **Why it is wrong:** The by-name leg (≈515) strips only when the stripped path still resolves, because "an unconditional strip would break a path that genuinely lives under /private with no /-rooted twin." These three sites strip unconditionally. For a worktree genuinely under `/private` with no `/`-rooted twin, the seed becomes a nonexistent path, the strongest resolution legs (manifest, by-name) are silently disabled, and the teammate falls through to the weaker legs or the WORKTREE-unresolved SURFACE path despite its worktree being perfectly resolvable.

---

Not reported as defects: the `DEFER_COUNT + 1 < MAX_DEFERS` cap performing only `MAX_DEFERS−1` deferrals (it contradicts the header's "Max defers: 3" but matches the newer, explicit 2026-08-01 intent comment, so I read it as intended), and the various fail-safe holds, which behave as their comments specify.