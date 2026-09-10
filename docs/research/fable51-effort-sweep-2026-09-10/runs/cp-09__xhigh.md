I read the whole hook and traced each gate. I found three defects, ordered by severity.

## Defect 1 — The operator-adoption who-gate falls open when the transcript file is absent

**What.** When the interactive-lib is present but no transcript file can be located for the session, the hook skips every hold and proceeds to force-close the pane, even though a missing transcript is exactly the "cannot prove the operator is absent" case the gate exists to catch.

**Where.** In the operator-adoption block, the lib-present branch:

```bash
    _adopt_tj="$(_find_transcript "$SESSION_ID" || true)"
```
```bash
    if [[ -n "$_adopt_tj" ]]; then
```

When `_adopt_tj` is empty (and the `paneUUID` fallback also fails to find one), this `if` is false, there is no `else`, and control falls through to `echo '{"continue": false}'` and the detached close.

**Why it is wrong.** The three sibling cases all hold the close: a missing lib calls `_beat_or_hold`, and an unreadable transcript (rc 2) holds and pages. The rc-2 contract explicitly counts an *empty* transcript file as "unreadable → hold." But a transcript that cannot be found at all never reaches `ci_last_interactive_epoch`, so it produces no rc 2 and no hold. An empty transcript file holds, yet an absent one closes. This triggers whenever the session's project lives outside the four `PROJECT_ROOTS` (for example a future `~/.claude-quinary` launcher), or when `SESSION_ID` parsed as `"unknown"`. In that state a pane a human has been typing into can be force-closed, the precise outcome the belt is documented to prevent.

## Defect 2 — Shared-worktree occupant count compares a normalized path against raw config values

**What.** The sole-occupant test strips a `/private` prefix from the path it searches for but compares it against the raw, unstripped `cwd` values in the config, so the count is computed against mismatched spellings.

**Where.** In the last worktree-resolution leg:

```bash
    cfg_cwd="${cfg_cwd#/private}"
```
```bash
    _occupants=$(jq -r --arg c "$cfg_cwd" '[.members[]? | select((.cwd // "") == $c)] | length' "$TEAM_CONFIG" 2>/dev/null)
```

**Why it is wrong.** When the config records `cwd` under `/private` (macOS realpaths for `/var` and `/tmp`), `$c` is the stripped form while each `.cwd` inside `jq` is still `/private/...`, so no member matches and `_occupants` is `0`. The `[[ "$_occupants" == "1" ]]` branch then never fires, so a genuinely dedicated single-member worktree is misclassified as shared, `WORKTREE_OWNED` stays false, and the worktree is never removed. The logged count is also wrong ("SHARED by 0 members"). The inverse, mixed-spelling case is worse: if one member records `/private/X` and another records `/X`, the count can come out as `1`, marking a shared tree as owned and licensing a `--force` removal of it. The other spellings in this file (`PAYLOAD_CWD`, the config-cwd seeds) are all `#/private`-stripped, confirming the prefix is expected here.

## Defect 3 — Worktree removal resolves the main repo without forcing an absolute path

**What.** The removal computes the main repo from `git rev-parse --git-common-dir` without `--path-format=absolute`, unlike the manifest resolver, so a relative common-dir defeats the existence guard and the removal silently no-ops.

**Where.** In the detached close, before `git worktree remove`:

```bash
    MAIN_REPO=$(git -C "$WORKTREE" rev-parse --git-common-dir 2>/dev/null | sed 's|/\.git$||')
```

**Why it is wrong.** `resolve_from_manifest` deliberately calls the same command with `--path-format=absolute`, because `--git-common-dir` can return a path relative to the worktree rather than an absolute one. When it does, `MAIN_REPO` is a relative path (or bare `.git`), the subsequent `[[ -d "$MAIN_REPO" ]]` is evaluated against the hook's own working directory and fails, and neither the `git worktree remove` nor its success/failure log runs. An owned worktree is then left behind with no trace, while the pane is still closed. This is the leak that `--path-format=absolute` was added elsewhere to prevent.

I did not find defects in the defer/off-by-one logic, the fail-closed unresolved-worktree path, the `jq --args` pane lookup, the tool-in-flight predicate, or the marker writer. Those behave as their comments describe.
