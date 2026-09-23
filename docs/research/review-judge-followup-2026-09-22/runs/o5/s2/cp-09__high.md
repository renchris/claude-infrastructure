## Review of `hooks/teammate-auto-shutdown.sh`

Line numbers are counted with `#!/bin/bash` as line 1; where a count could be off by a line or two, the verbatim text is the anchor.

---

### 1. The checkpoint subprocess's stdout is not redirected, so it lands on the hook's protocol channel

**What** — Both invocations of `teammate-checkpoint.sh` suppress only stderr; anything the child writes to stdout becomes this hook's stdout, which is the JSON hook-response channel.

**Where** — L658–659 and L774:
```bash
  "$HOOK_DIR/teammate-checkpoint.sh" <<<"{\"hook_event_name\":\"TeammateIdle\",\"session_id\":\"$SESSION_ID\",\"cwd\":\"$WORKTREE\",\"team_name\":\"$TEAM_NAME\",\"teammate_name\":\"$TEAMMATE_NAME\"}" \
    2>/dev/null || true
```
```bash
  if "$HOOK_DIR/teammate-checkpoint.sh" <<<"{\"hook_event_name\":\"TeammateIdle\",\"session_id\":\"$SESSION_ID\",\"cwd\":\"$WORKTREE\",\"team_name\":\"$TEAM_NAME\",\"teammate_name\":\"$TEAMMATE_NAME\"}" 2>/dev/null; then
```

**Why it is wrong** — `teammate-checkpoint.sh` is itself a TeammateIdle hook being fed a synthetic TeammateIdle payload; if it prints anything on stdout (a hook JSON object, a progress line), that output is emitted by *this* hook. On the defer path (L658) the very next lines are `# Do NOT emit {"continue": false}` / `exit 0` — but if the child emits a stop directive, the teammate is stopped anyway and the defer is defeated. On the reap path (L774) the child's output is prepended to the `{"continue": false, ...}` at L939, producing two concatenated objects that cannot be parsed, so the graceful stop is lost while the detached pane close still fires 3 s later. Every other subprocess in this file (`close_pane`, `_page_desk`, the detached block) is redirected; these two are not.

---

### 2. A failed patch write is logged as a success, immediately before a `--force` worktree removal

**What** — The "✓ fallback patch" log line is unconditional; it is not gated on the redirection or the command block succeeding.

**Where** — L795–796:
```bash
    } > "$PATCH" 2>/dev/null
    log "  ✓ fallback patch: $PATCH"
```

**Why it is wrong** — Redirections are processed left to right, so if `> "$PATCH"` cannot be opened the compound command never runs and its exit status is discarded (no `set -e`). This happens whenever `$PATCH` is unopenable — e.g. `TEAM_NAME` or `TEAMMATE_NAME` from the JSON payload contains a `/` (`/tmp/feat/ui-…​.patch` → no such directory), or `/tmp` is full/read-only. The lifecycle log then records a preserved patch that does not exist, and the detached block goes on to `git worktree remove --force` (L970) on the strength of it, discarding the uncommitted work the patch was supposed to hold.

---

### 3. The "fallback patch" cannot hold the class of work it is the fallback for

**What** — The fallback patch records untracked files by *name* only, yet it is the designated recovery path when the checkpoint — whose stated job is "tracked + untracked" — fails.

**Where** — L793–794 (contrast header L7–L10):
```bash
      echo "# --- diff HEAD (tracked changes only) ---"
      git -C "$WORKTREE" diff HEAD 2>/dev/null || true
```

**Why it is wrong** — Condition: the checkpoint fails (`CHECKPOINT_OK=false`) and the teammate's work is untracked files (a new test file, a new module) — precisely the case header L7 says the checkpoint exists to cover. `git status --porcelain` reports them, so the tree reads dirty and the patch is written, but `git diff HEAD` emits nothing for them. The patch contains a `?? path` status line and no content. The detached block then force-removes the worktree (L970) under the comment "Work is already checkpointed above, so removing the worktree here cannot lose work" — the file contents are unrecoverable.

---

### 4. The operator-adoption belt falls open when the transcript cannot be found at all

**What** — When `_find_transcript` yields nothing, the code drops out of the belt with no `else`, and proceeds to close the pane — the one "oracle could not answer" case that is *not* routed to `_beat_or_hold`.

**Where** — L888–894 (and the closing `fi` at L928):
```bash
    _adopt_tj="$(_find_transcript "$SESSION_ID" || true)"
    if [[ -z "$_adopt_tj" && -n "$PANEID" ]]; then
      _alt_sid="$(cc-sessions --json 2>/dev/null | jq -r --arg p "$PANEID" \
                  '.[] | select(.paneUUID==$p) | (.session_id // .sessionId) // empty' 2>/dev/null | head -1)"
      [[ -n "$_alt_sid" ]] && _adopt_tj="$(_find_transcript "$_alt_sid" || true)"
    fi
    if [[ -n "$_adopt_tj" ]]; then
```

**Why it is wrong** — `_beat_or_hold` is documented (L342) as "Consulted whenever the transcript WHO-oracle could not answer", and rc 2 ("could not READ the answer") holds and pages. A *missing* transcript is the strongest form of "could not read", and it silently closes instead. Concrete trigger: `PROJECT_ROOTS` (L64) is a fixed list of four roots while `TEAM_ROOTS` (L87) is the glob `~/.claude*/teams` — a team resolved from a fifth config dir (the exact class of bug the `TEAM_ROOTS` glob was introduced to fix) has a reachable pane id but no reachable transcript, so `_adopt_tj` is empty, no hold fires, and an operator-adopted pane is force-closed. Same outcome when `SESSION_ID` is the literal `"unknown"` and `PANEID` is empty (the `_alt_sid` leg is gated on `-n "$PANEID"`).

---

### 5. Pane-id resolution discards `MEMBER_CANDIDATES` priority and can select a sibling member

**What** — The jq selector matches *any* candidate name as a set and `head -1` takes whichever member appears first in the config file, rather than preferring the exact `$TEAMMATE_NAME`.

**Where** — L812–814:
```bash
  RESOLVED=$(jq -r --args \
    '.members[]? | select(.name as $n | $ARGS.positional | index($n)) | "\(.name)\t\(.tmuxPaneId // "")"' \
    "${MEMBER_CANDIDATES[@]}" < "$CONFIG" 2>/dev/null | head -1)
```

**Why it is wrong** — `MEMBER_CANDIDATES` contains both `quality-keeper-2` and the stripped `quality-keeper` (L431–434). Name auto-increment happens *because* a member named `quality-keeper` already exists in that same team, so both are listed in `config.json`, with the un-suffixed one first. When `quality-keeper-2` goes idle, this returns `quality-keeper`'s row: `MEMBER_NAME` and `PANEID` both belong to a different, still-working teammate, and the detached block force-closes its pane and writes a teardown marker keyed to it. This is the outcome L220 declares impossible ("A forced close must never be able to hit the wrong pane"); every other resolution leg iterates `for m in "${MEMBER_CANDIDATES[@]}"` so the exact name wins, only this one does not.

---

### 6. `resolve_by_worktree_name` and `resolve_from_manifest` iterate candidates in the inner loop, so a sibling's worktree can be marked OWNED and force-removed

**What** — Both resolvers loop over *records* outer and over candidate names inner, so the first record matching the stripped base name wins even when a record matching the exact member name exists later.

**Where** — L505–518:
```bash
  while IFS= read -r line; do
```
```bash
    for m in "${MEMBER_CANDIDATES[@]}"; do
      if [[ "$base" == "$m" && -d "$wt" ]]; then printf '%s\n' "$wt"; return 0; fi
    done
```
and L456–459:
```bash
  for (( i=0; i<count; i++ )); do
    name=$(yq eval ".members[$i].name" "$manifest" 2>/dev/null)
    for m in "${MEMBER_CANDIDATES[@]}"; do
      if [[ "$name" == "$m" ]]; then
```

**Why it is wrong** — For member `gu5-verdict-2`, if `git worktree list` reports `~/Development/.worktrees/gu5-verdict` before `…/gu5-verdict-2`, the base-name match fires first and returns the *other* member's tree. `WORKTREE_OWNED` is then set to `true` (L540) on the stated premise that "A basename match is per-MEMBER evidence" — and the detached block runs `git worktree remove … --force` (L970) on a live sibling's checkout, discarding its uncommitted work. The `--force` gate is exactly the data-loss guard described at L416–427, and this resolution order defeats it.

---

### 7. The sole-occupant test compares a normalized path against unnormalized config values

**What** — `cfg_cwd` is `/private`-stripped before being fed back to jq as the value to match against the raw `.cwd` fields.

**Where** — L610 and L615:
```bash
    cfg_cwd="${cfg_cwd#/private}"
```
```bash
    _occupants=$(jq -r --arg c "$cfg_cwd" '[.members[]? | select((.cwd // "") == $c)] | length' "$TEAM_CONFIG" 2>/dev/null)
```

**Why it is wrong** — When the config records `/private/tmp/wt-…` (the macOS realpath form this file strips everywhere else), the stripped `$c` matches zero records, so `_occupants` is `0`, the `== "1"` test fails, and the log at L619 asserts the tree is "SHARED by 0 members" — an occupancy claim derived from a comparison that can never succeed rather than from any measurement. Related: the comment at L613 says "any sibling (the lead counts)", but the jq counts only `.members[]`; if the lead is not recorded as a member entry, a single teammate sharing the lead's cwd yields `_occupants == 1` → `WORKTREE_OWNED=true` → the lead's worktree is force-removed, the precise failure L424 says the gate prevents.

---

### 8. `--git-common-dir` can return a relative path, which is then tested and used from the wrong directory

**What** — `MAIN_REPO` is taken from `git rev-parse --git-common-dir` without `--path-format=absolute`, so it can be the literal `.git`; the subsequent `-d` test and `git -C` then resolve it against the hook's own cwd, not `$WORKTREE`.

**Where** — L968–971:
```bash
    MAIN_REPO=$(git -C "$WORKTREE" rev-parse --git-common-dir 2>/dev/null | sed 's|/\.git$||')
    if [[ -n "$MAIN_REPO" && -d "$MAIN_REPO" ]]; then
      git -C "$MAIN_REPO" worktree remove "$WORKTREE" --force 2>/dev/null \
        && log "  ✓ worktree removed: $WORKTREE"
```

**Why it is wrong** — In a main working tree (which the `/tmp/wt-*`, TSV and manifest legs can all resolve to, and all of which set `WORKTREE_OWNED=true`), `rev-parse --git-common-dir` prints `.git`; `sed 's|/\.git$||'` does not match, so `MAIN_REPO=".git"`. `[[ -d ".git" ]]` is then evaluated in the lead's cwd — if the lead sits in a repo it is true, and `git -C .git worktree remove` runs against an unrelated repository. `resolve_from_manifest` at L450 uses `--path-format=absolute` for the same call, so the pitfall is known elsewhere in this file. Secondary: the removal's failure branch is unlogged — `&&` only logs success, so a refused or misdirected removal leaves no trace at all.

---

### 9. A malformed hold window silently disables the only remaining who-gate

**What** — Any non-numeric `CC_CLASSIFY_INTERACTIVE_HOLD_S` turns the entire operator-adoption belt off with no log line and without going through the documented kill switch.

**Where** — L858:
```bash
{ [[ "$INTERACTIVE_HOLD_S" =~ ^[0-9]+$ ]] && (( INTERACTIVE_HOLD_S > 0 )); } || _hold_on=0
```

**Why it is wrong** — With e.g. `CC_CLASSIFY_INTERACTIVE_HOLD_S=6h` or `21600s`, `_hold_on` becomes 0, the whole `if (( _hold_on ))` block is skipped, and neither the lib check, the unreadable-transcript hold, nor `_beat_or_hold` runs. When reap-guard is also undeployed (L735's WARN path), the pane is force-closed with zero who-evidence. Every other degradation in this file logs a WARN or pages; this one is silent, and L733 ("a guard that can disappear without saying so…") states that is the property being avoided.

---

### 10. The teardown marker is written on the premise that the close will succeed

**What** — `write_teardown_marker` runs before `close_pane`, and is never retracted when the close fails.

**Where** — L186–188:
```bash
  write_teardown_marker "$pane" "${SESSION_ID:-}" teammate-idle
  close_pane "$pane"
  local rc=$?
```

**Why it is wrong** — The justification at L182–185 is that "the close is inevitable", which establishes only that the close is *attempted*. When `close_pane` returns non-zero for a real failure (iTerm2 RPC error, the `tas_bounded` 8 s timeout, `tmux` not installed) the code logs `✗ pane close FAILED` at L195 while the sid- and pane-keyed markers remain on disk. The teammate is still alive; if it genuinely crashes inside the reader's freshness window, `lead-crash-watchdog`'s `classify_death` finds a `mode=teammate-idle` marker and suppresses the crash — the exact masking L158 forbids for the `"unknown"` key.

---

### Minor

- **L768** — `log "Auto-shutdown idle teammate: $TEAMMATE_NAME (team: $TEAM_NAME)"` is emitted before the operator-adoption hold (L859–930), which can `exit 0` without closing anything. The lifecycle log, which the header instructs operators to grep, records shutdowns that never happened.
