### 2. The `--force` worktree removal is not conditioned on the checkpoint having succeeded

**What** — `CHECKPOINT_OK` is computed but never gates the destructive `git worktree remove --force`; the removal fires on a checkpoint failure exactly as it does on success.

**Where** — lines 774, 777, 792, 970–974:
```bash
CHECKPOINT_OK=false
```
```bash
      echo "# Checkpoint status: $($CHECKPOINT_OK && echo 'written' || echo 'failed — rely on this patch')"
```
```bash
  if [[ -n "$WORKTREE" ]] && $WORKTREE_OWNED; then
```
```bash
      git -C "$MAIN_REPO" worktree remove "$WORKTREE" --force 2>/dev/null \
```

**Why it is wrong** — `CHECKPOINT_OK`'s only consumer is the cosmetic patch header on line 792. When `teammate-checkpoint.sh` fails (the corrupt-repo / permission case the header calls out at lines 9–10), the fallback is the patch block — and that block captures `git -C "$WORKTREE" diff HEAD` (line 796), i.e. tracked changes only, plus a `git status --porcelain` listing that names untracked files without their contents. The header at lines 6–8 claims the checkpoint preserves "tracked + untracked work." So for a teammate whose work is untracked files (new test files, new scripts), a failed checkpoint leaves *no* copy of the content anywhere, and the detached block then force-removes the directory holding it. The comment at lines 946–947 — "Work is already checkpointed above, so removing the worktree here cannot lose work" — is the unproven premise the removal acts on; it is false on precisely the branch that logs `✗ checkpoint failed`.

---

### 3. The base-name candidate can resolve another member's pane id, and that pane is force-closed

**What** — The pane lookup accepts any member whose name is in `MEMBER_CANDIDATES` and keeps the first one the config happens to list, so a teammate named `foo-2` can resolve the pane of the distinct member `foo`.

**Where** — lines 814–819:
```bash
  RESOLVED=$(jq -r --args \
    '.members[]? | select(.name as $n | $ARGS.positional | index($n)) | "\(.name)\t\(.tmuxPaneId // "")"' \
    "${MEMBER_CANDIDATES[@]}" < "$CONFIG" 2>/dev/null | head -1)
```
```bash
    PANEID="${RESOLVED#*$'\t'}"
```

**Why it is wrong** — `MEMBER_CANDIDATES` is `("foo-2" "foo")` whenever `TEAMMATE_NAME` matches the trailing-`-N` pattern (lines 432–435). The name `foo-2` exists *because* auto-increment found `foo` already taken, so both members normally coexist in the same `config.json`. The jq filter emits both rows in config order and `head -1` keeps whichever appears first — `foo`, the earlier-created member. `MEMBER_NAME` and `PANEID` then both describe a different teammate, `close_and_log "$PANEID" "$MEMBER_NAME"` force-closes that teammate's pane while it may still be working, and the log records `✓ closed pane <id> (foo)` as a success. There is no preference for an exact `name == "$TEAMMATE_NAME"` match and no check that the row returned is the one that idled. The safety note at line 220 — "A forced close must never be able to hit the wrong pane" — is not upheld by this path; the reasoning that protects it (UUIDs are never recycled, line 132) only rules out *stale* ids, not ids belonging to a live sibling.

---

### 4. The same base-name fallback can resolve another member's worktree, which is then checkpointed and force-removed

**What** — Both the manifest leg and the worktree-name leg iterate the *candidate list* innermost, so the first manifest entry or first `git worktree list` path matching *any* candidate wins — and each marks the result `WORKTREE_OWNED=true`.

**Where** — lines 457–463 and 517–518:
```bash
  for (( i=0; i<count; i++ )); do
    name=$(yq eval ".members[$i].name" "$manifest" 2>/dev/null)
    for m in "${MEMBER_CANDIDATES[@]}"; do
      if [[ "$name" == "$m" ]]; then
```
```bash
    for m in "${MEMBER_CANDIDATES[@]}"; do
      if [[ "$base" == "$m" && -d "$wt" ]]; then printf '%s\n' "$wt"; return 0; fi
```

**Why it is wrong** — With `TEAMMATE_NAME=foo-2`, a manifest listing `foo` at index 0 returns `foo`'s worktree before index 1 (`foo-2`) is ever examined; likewise `~/Development/.worktrees/foo` matches on basename before `.../foo-2` is reached in the porcelain stream. Both callers then set `WORKTREE_OWNED=true` (lines 470–471, 540–541), which is the sole gate on line 970. Consequences on that wrong tree: the busy-marker, dirty-tree and reap-guard gates all evaluate `foo`'s state instead of `foo-2`'s; the checkpoint at line 776 writes `foo`'s content under `foo-2`'s ref namespace; and the detached block runs `git worktree remove --force` on `foo`'s worktree, discarding a live sibling's uncommitted and untracked work. The ordering that would prevent this — try the exact name across the whole search space before trying the stripped name — is present in the TSV leg and the config-cwd leg (candidates outermost) but inverted in these two.

---

### 5. `_spawn_s=0` on a registry miss silently disables the spawn-brief exclusion

**What** — When `_spawn_epoch` cannot answer, the fallback of `0` makes the "is this prompt newer than the spawn brief" test vacuously true, so the spawn brief itself counts as operator adoption.

**Where** — lines 919 and 921:
```bash
        _spawn_s="$(_spawn_epoch "$SESSION_ID" || echo 0)"; [[ "$_spawn_s" =~ ^[0-9]+$ ]] || _spawn_s=0
```
```bash
        if (( _iage < INTERACTIVE_HOLD_S )) && (( _iep > _spawn_s + FIRE_PROMPT_SLACK_S )); then
```

**Why it is wrong** — `_spawn_epoch` returns 1 whenever `cc-sessions` is unavailable or the sid is absent from the registry (lines 314–316). With `_spawn_s=0`, the second conjunct reduces to `_iep > 300`, which every real epoch timestamp satisfies. The gate then reduces to "was there *any* user prompt in the last `INTERACTIVE_HOLD_S` seconds" — and the spawn brief is delivered as a user prompt, as line 850 states explicitly ("the spawn brief arrives as a user prompt and must NOT count as adoption"). Every teammate idling within the 6-hour default window is therefore classified ADOPTED, held, and desk-paged, and the hook never closes anything. Note that `cc-sessions` is invoked bare on lines 314 and 690 while `timeout`, `it2` and python are all resolved by absolute path precisely because, per line 111, "hooks run with a minimal PATH excluding Homebrew" — so the miss branch is a live configuration, not a corner case. The failure direction is the "single point of INERTNESS / fail-closed-as-amplifier" outage lines 884–887 say this design avoids.

---

### 6. The teardown marker is written before the close is known to have succeeded, and is never retracted

**What** — `write_teardown_marker` runs unconditionally ahead of `close_pane`, so a close that fails still leaves a durable "this session was torn down deliberately" record for a teammate that is still alive.

**Where** — lines 186–187 and 195:
```bash
  write_teardown_marker "$pane" "${SESSION_ID:-}" teammate-idle
  close_pane "$pane"
```
```bash
    log "  ✗ pane close FAILED (rc=$rc) for $pane ($who): ${err:-<no stderr>}"
```

**Why it is wrong** — `close_pane` can fail for reasons the code itself enumerates at line 134 (RPC error, timeout — `tas_bounded` returns 124 after 8s against a wedged iTerm2). On that branch the pane stays open and the teammate keeps running, but `$_tm_dir/$_tm_sid.json` and `$_tm_dir/$_tm_pane.json` are already on disk, and line 160 states "Writers never delete markers; the reader GCs them." If that teammate subsequently crashes for real, `lead-crash-watchdog.sh classify_death` finds a `mode=teammate-idle` marker keyed to its sid and classifies the crash as a deliberate teardown. That is the exact hazard lines 184–185 identify as the reason to place the marker late — "A marker written at any earlier decision point would mask a genuine crash of a teammate we then chose to KEEP for the reader's whole freshness window" — and being one line earlier than the close is enough to reproduce it.

---

### 7. The sole-occupant test compares a `/private`-stripped path against the raw config values

**What** — `cfg_cwd` is `/private`-stripped on line 611, but the occupancy count on line 616 matches that stripped string against the unmodified `.cwd` values in the same file, so the count is 0 for any `/private`-recorded cwd.

**Where** — lines 611, 616–617, 620:
```bash
    cfg_cwd="${cfg_cwd#/private}"
```
```bash
    _occupants=$(jq -r --arg c "$cfg_cwd" '[.members[]? | select((.cwd // "") == $c)] | length' "$TEAM_CONFIG" 2>/dev/null)
    if [[ "$_occupants" == "1" ]]; then
```
```bash
      log "  ↳ $TEAMMATE_NAME: worktree $WORKTREE is SHARED by ${_occupants:-?} members — gating on it, removal refused"
```

**Why it is wrong** — The file establishes on line 511 that config cwd values can carry the `/private` prefix (that is why lines 534 and 611 strip it). For a team whose members record `cwd=/private/tmp/wt-x`, `cfg_cwd` becomes `/tmp/tmp/wt-x`-style stripped form, `-d` succeeds because both spellings resolve, and the jq `select` then matches zero members. `_occupants` is `0`, never `1`, so a genuinely dedicated worktree can never be marked owned, and the log emits the self-contradictory "is SHARED by 0 members" — zero occupants means the path was not found at all, which is a lookup failure, not a sharing verdict. Separately, the comment on line 614 asserts "any sibling (the lead counts)", but the expression counts only `.members[]`; if the lead is recorded outside that array, a cwd held by the lead plus one member yields `_occupants=1`, sets `WORKTREE_OWNED=true`, and line 973 force-removes the lead's checkout — the outcome lines 424–425 and 966–969 exist to prevent.

---

### 8. `pipefail` plus `grep -q` can report a dirty tree as clean

**What** — Both dirty-tree checks read the exit status of a pipeline under `set -o pipefail`, where `grep -q` exits on the first match and can leave `git status` with a SIGPIPE status that overrides grep's success.

**Where** — line 45, and lines 640 and 785:
```bash
set -uo pipefail
```
```bash
  if git -C "$WORKTREE" status --porcelain 2>/dev/null | grep -q .; then
```
```bash
  if git -C "$WORKTREE" status --porcelain 2>/dev/null | grep -q .; then
```

**Why it is wrong** — `grep -q` exits immediately after matching the first line. If `git status --porcelain` has more output than the pipe buffer holds (~64 KiB, i.e. a worktree with thousands of modified or untracked entries — an un-ignored build or `node_modules` directory is enough), git is killed by SIGPIPE and exits 141; `pipefail` makes the pipeline status 141 and the `if` takes the false branch despite grep having matched. At line 640 the result is `TREE_DIRTY=false`, so the rule-3 defer and its protective checkpoint are skipped for a teammate that has uncommitted work. At line 785 the result is that no fallback patch is written at all, immediately before the `--force` removal at line 973. The outcome is timing-dependent — the same worktree can be judged dirty on one invocation and clean on the next.

---

### 9. `_it2_bin` resolves whatever `it2` is first on PATH, not the shim the close depends on

**What** — The force-close correctness argument rests on calling `~/.claude/bin/it2`, but the resolver takes any `it2` on PATH and only falls back to the shim's absolute path if none is found.

**Where** — line 105:
```bash
_it2_bin() { command -v it2 2>/dev/null || echo "$HOME/.claude/bin/it2"; }
```

**Why it is wrong** — If PATH resolves `it2` to the real 0.2.3 CLI (e.g. `/opt/homebrew/bin/it2` or `/usr/local/bin/it2`) before `~/.claude/bin`, line 142 invokes a binary that, per lines 102–104 and 25–27, "does NOT propagate force to the API and pops iTerm2's running-job confirmation modal on every live teammate pane." The pane then sits on a modal instead of closing; the CLI having accepted the request, `close_pane` returns 0 and line 191 logs `✓ closed pane <id>` — a non-close reported as a success, with no defer counter left (it was cleared on line 768) and no further TeammateIdle event guaranteed. The comment on line 99 asserts the shim is "first in PATH" as a premise; nothing in the code verifies it, and line 111 documents that this hook runs under a PATH the author does not otherwise trust for binary resolution.

---

### 10. The detached block walks `$PPID` after the parent has exited

**What** — `_find_teammate_pid` starts its ancestry walk at `$PPID`, and one of its two call sites runs inside the backgrounded subshell, after `sleep "$CLOSE_GRACE_S"` and after the main shell has exited.

**Where** — line 226, and line 956 inside the `( ... ) &` block:
```bash
  local pid="$PPID" depth=0 cmd m
```
```bash
    [[ -z "$TEAMMATE_PID" ]] && TEAMMATE_PID=$(_find_teammate_pid || true)
```

**Why it is wrong** — `PPID` is fixed at shell startup and is not updated in the subshell, so the background block reads the same numeric pid the hook started with. Lines 30–35 document what that pid is on the LEAD-side model — the `/bin/sh -c` shim, "already dead by the time the backgrounded kill fired," hitting "a PID-RECYCLED process (intermittently the lead or an unrelated shell)." This block re-creates that situation: it reads a pid that may have exited during the grace window and may have been reused. Ordinarily the walk simply finds no `claude.exe` and the code logs "no pane id resolved," but if the recycled pid's ancestry contains any `claude.exe` whose command matches `--agent-id <m>@` for *any* member of `MEMBER_CANDIDATES` — which includes the trailing-number-stripped base name, per defect 3 — `_pane_from_tty` resolves that unrelated process's pane and `close_and_log` force-closes it. The `--agent-id` gate on lines 230–231 narrows the class but does not pin it to the teammate that idled.

---

### 11. The fallback-patch success line is logged unconditionally

**What** — `log "  ✓ fallback patch: $PATCH"` runs whether or not the redirection that creates the patch succeeded.

**Where** — lines 797–798:
```bash
    } > "$PATCH" 2>/dev/null
    log "  ✓ fallback patch: $PATCH"
```

**Why it is wrong** — If the output redirection fails — `/tmp` not writable, the filesystem full, or a `TEAM_NAME`/`TEAMMATE_NAME` value from the payload that makes the path invalid — the compound command does not execute and no file is produced, but nothing inspects that status and the next line records a checkmark and a path that does not exist. This is the last recoverable trace written before the force-remove on line 973, so the log asserts that work was preserved at exactly the moment it was not. The same line fires when the checkpoint already succeeded, which is harmless; it is the `CHECKPOINT_OK=false` path where the claim is load-bearing and unverified.

---

I did not find defects in the `TEAM_ROOTS` construction (lines 84–91), `write_teardown_marker`'s `"unknown"` suppression (line 164), the three-way defer arithmetic `DEFER_COUNT + 1 < MAX_DEFERS` (which does act on event *N* as its comment claims), `_tool_in_flight`'s trailing-`tool_use` predicate, or the `_beat_or_hold` case arms.