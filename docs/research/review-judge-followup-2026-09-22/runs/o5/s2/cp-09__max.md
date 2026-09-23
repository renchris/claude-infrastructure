I read the whole file. It has defects; nine are below, ordered by blast radius. Line numbers count `#!/bin/bash` as line 1.

---

### 1. The operator-adoption belt is skipped entirely — not held — when no transcript file is found

**What.** When `_find_transcript` returns nothing for the session, the who-gate block simply falls off the end and the hook proceeds to force-close the pane, instead of consulting `_beat_or_hold` as the design requires.

**Where.** Lines 890, 896, 930 (plus the trigger at 64 vs. 87):

```bash
    _adopt_tj="$(_find_transcript "$SESSION_ID" || true)"
```
```bash
    if [[ -n "$_adopt_tj" ]]; then
```
```bash
    fi
```
```bash
readonly PROJECT_ROOTS="${CC_CLASSIFY_PROJECT_ROOTS:-$HOME/.claude/projects $HOME/.claude-secondary/projects $HOME/.claude-tertiary/projects $HOME/.claude-quaternary/projects}"
```
```bash
_team_roots+=("$HOME"/.claude*/teams)
```

**Why it is wrong.** `if [[ -n "$_adopt_tj" ]]` has no `else`. If the transcript cannot be located — `SESSION_ID` is the literal `"unknown"`, the `.jsonl` sits deeper than `-maxdepth 2`, or the session belongs to a config dir not in the hardcoded four-element `PROJECT_ROOTS` — execution reaches line 942 and closes the pane with the who-gate having evaluated nothing and logged nothing. That is the exact state the adjacent `rc == 2` arm (line 899) and `_beat_or_hold` (line 349, "Consulted whenever the transcript WHO-oracle could not answer") exist to hold on; "cannot read the answer" holds, but "cannot find the file" falls open. The trigger is self-evidenced in this file: `TEAM_ROOTS` is globbed as `~/.claude*/teams` precisely because a hardcoded root list dropped teams led from an unlisted dir, while `PROJECT_ROOTS` is still that same hardcoded list — so a team led from any fifth config dir resolves a pane id (globbed roots) but no transcript (listed roots), and an operator-adopted pane in that dir is force-closed. The same miss silently disables `_tool_in_flight` (line 383) for those sessions.

---

### 2. `git worktree remove --force` runs regardless of whether the checkpoint succeeded, and the fallback patch contains no untracked work

**What.** `CHECKPOINT_OK` is computed but never gates the destructive removal, and the "fallback" patch captures only tracked changes, so a failed checkpoint plus untracked files means the work is destroyed.

**Where.** Lines 774, 795–796, 970, 973:

```bash
CHECKPOINT_OK=false
```
```bash
      echo "# --- diff HEAD (tracked changes only) ---"
      git -C "$WORKTREE" diff HEAD 2>/dev/null || true
```
```bash
  if [[ -n "$WORKTREE" ]] && $WORKTREE_OWNED; then
```
```bash
      git -C "$MAIN_REPO" worktree remove "$WORKTREE" --force 2>/dev/null \
```

**Why it is wrong.** `CHECKPOINT_OK` is read in exactly one place — the patch header string at line 792. The header of the file promises "FALLBACK to /tmp/…patch if the checkpoint fails for any reason", and line 946 asserts "Work is already checkpointed above, so removing the worktree here cannot lose work." When `teammate-checkpoint.sh` exits non-zero (corrupt repo, permission issue — the two cases named at line 10) and the teammate's work is in files git does not track, `git diff HEAD` emits nothing for them; the patch records only their *names* via `status --porcelain`, and then line 973 deletes the directory with `--force`. The content is gone with no copy anywhere. The same removal also fires when the pane close failed (line 195) or no pane id resolved at all (line 962), deleting the working directory of a teammate that is still alive.

---

### 3. The ownership test compares a `/private`-stripped path against unstripped config values, so the count is always 0

**What.** `cfg_cwd` is normalized before being used as the jq comparison key, but the `.cwd` values it is compared against are read raw, so any `/private`-prefixed config path yields `_occupants=0` and the tree is classified shared.

**Where.** Lines 611, 616–617:

```bash
    cfg_cwd="${cfg_cwd#/private}"
```
```bash
    _occupants=$(jq -r --arg c "$cfg_cwd" '[.members[]? | select((.cwd // "") == $c)] | length' "$TEAM_CONFIG" 2>/dev/null)
    if [[ "$_occupants" == "1" ]]; then
```

**Why it is wrong.** When `config.json` records `"cwd": "/private/tmp/wt-team-foo"` (the macOS realpath form this file documents at lines 509–511), line 611 sets `cfg_cwd=/tmp/tm-…` — i.e. `/tmp/wt-team-foo` — and line 616 then asks how many members recorded exactly `/tmp/wt-team-foo`. The member whose entry we just read does not match its own row, so the answer is `0`, never `1`. A genuinely *dedicated* per-member worktree is therefore always marked `WORKTREE_OWNED=false`: it is never removed (leaked), and line 620 logs "SHARED by 0 members". Worse, on the next reap-guard DEFER the `! $WORKTREE_OWNED` branch (line 712) fires and pages the desk with `SHARED-CWD-NEVER-REAPS`, telling the operator this member "records the LEAD's cwd" when it does not.

---

### 4. Pane-id lookup picks the first member matching *any* candidate name in file order, so a teammate `X-N` can resolve to member `X`'s pane

**What.** The jq filter tests candidate *membership* with no preference for the exact teammate name, and `head -1` then takes whichever matching member appears first in the config.

**Where.** Lines 814–816, 819:

```bash
  RESOLVED=$(jq -r --args \
    '.members[]? | select(.name as $n | $ARGS.positional | index($n)) | "\(.name)\t\(.tmuxPaneId // "")"' \
    "${MEMBER_CANDIDATES[@]}" < "$CONFIG" 2>/dev/null | head -1)
```
```bash
    PANEID="${RESOLVED#*$'\t'}"
```

**Why it is wrong.** `MEMBER_CANDIDATES` is `("quality-keeper-2" "quality-keeper")` (lines 432–435). If the team config lists both members — which is what the auto-increment described at line 412 implies happened — the filter emits both rows and `head -1` returns whichever is listed first, normally the un-suffixed original. `PANEID` and `MEMBER_NAME` then belong to a *different, possibly working* teammate, and lines 951/186 force-close that pane and write a teardown marker for it, defeating the invariant stated at line 220 ("A forced close must never be able to hit the wrong pane") and at lines 132–133 ("it can never hit the wrong pane"). Note the `/tmp` legs at 565–566 loop candidates on the *outside* precisely to give the exact name priority; this lookup and the two in defect 5 do not.

---

### 5. Worktree resolution can select another member's — or another team's — worktree and mark it removable

**What.** The name-based and glob-based legs match on the truncated candidate and a wildcarded team slug, and any hit sets `WORKTREE_OWNED=true`, licensing `--force` removal of a tree this member does not own.

**Where.** Lines 517–518 (and identically 459–460), 585–588:

```bash
    for m in "${MEMBER_CANDIDATES[@]}"; do
      if [[ "$base" == "$m" && -d "$wt" ]]; then printf '%s\n' "$wt"; return 0; fi
```
```bash
    for candidate in /tmp/wt-*-"${m}" /tmp/worktree-*-"${m}"; do
      if [[ -d "$candidate" ]]; then
        WORKTREE="$candidate"        # per-member path ⇒ dedicated
        WORKTREE_OWNED=true
```

**Why it is wrong.** In `resolve_by_worktree_name` the candidate loop is *inside* the worktree loop, so the first `git worktree list` record whose basename matches any candidate wins: for teammate `gu5-verdict-2`, worktree `~/…/gu5-verdict` (member `gu5-verdict`'s live tree) is returned if it is listed first. `resolve_from_manifest` inverts the loops the same way. In the glob leg the team segment is `*`, so for member name `quality-keeper` the pattern `/tmp/wt-*-quality-keeper` matches a *concurrent other team's* worktree. In all three cases the result is stamped "per-member evidence ⇒ dedicated ⇒ removable", so the gates run on the wrong tree and line 973 force-removes another live teammate's uncommitted work.

---

### 6. `pipefail` plus `grep -q` makes a heavily dirty tree read as clean

**What.** With `set -o pipefail`, `git status --porcelain | grep -q .` returns non-zero when `git` is killed by SIGPIPE after `grep -q` exits on the first line, so a dirty tree is reported clean.

**Where.** Lines 45, 640, 785:

```bash
set -uo pipefail
```
```bash
  if git -C "$WORKTREE" status --porcelain 2>/dev/null | grep -q .; then
```
```bash
  if git -C "$WORKTREE" status --porcelain 2>/dev/null | grep -q .; then
```

**Why it is wrong.** `grep -q` exits 0 the instant it matches. If the status output exceeds the ~64 KiB pipe buffer (a tree with a few thousand modified/untracked entries), `git` is still writing when the reader goes away, dies on SIGPIPE with status 141, and pipefail makes the pipeline status 141 — so the `if` is false. Line 640 then sets `TREE_DIRTY=false` and the Rule-3 defer never happens: the teammate with the *most* uncommitted work is the one reaped on its very first idle event. Line 785 skips the fallback patch for exactly the same tree. Combined with defect 2, a checkpoint failure on such a tree leaves no recoverable trace at all.

---

### 7. The teardown marker is written before a close that can fail, and is never retracted

**What.** `write_teardown_marker` runs unconditionally ahead of `close_pane`, so a failed close leaves a durable record claiming the session was deliberately torn down.

**Where.** Lines 186–187, 195:

```bash
  write_teardown_marker "$pane" "${SESSION_ID:-}" teammate-idle
  close_pane "$pane"
```
```bash
    log "  ✗ pane close FAILED (rc=$rc) for $pane ($who): ${err:-<no stderr>}"
```

**Why it is wrong.** When `close_pane` returns non-zero for a real failure — `timeout` fires (rc 124) against a wedged iTerm2, or the shim raises an RPC error — the pane and its CC session are still alive, but `$_tm_dir/$sid.json` and `$_tm_dir/$pane.json` already assert `mode=teammate-idle`. Writers never delete markers (line 160), so for the reader's whole freshness window `lead-crash-watchdog` will classify a genuine later crash of that still-live session as an intentional teardown. This is the failure mode the comment at lines 182–185 claims is prevented by writing "only once… the close is inevitable" — attempted is not inevitable.

---

### 8. `_it2_bin` resolves via PATH, so the force-close shim is not guaranteed to be the binary that runs

**What.** The function returns whatever `it2` PATH resolution finds first and only falls back to the shim when no `it2` exists at all, despite its own comment stating the shim is required.

**Where.** Line 105:

```bash
_it2_bin() { command -v it2 2>/dev/null || echo "$HOME/.claude/bin/it2"; }
```

**Why it is wrong.** Lines 99–104 state that calling `~/.claude/bin/it2` is "REQUIRED, not incidental" because the real CLI's `close -f` does not propagate force and pops iTerm2's running-job modal. Nothing in this hook puts `~/.claude/bin` on PATH, and line 111 records that hooks run with a minimal PATH — under which a real `it2` installed in, say, `/usr/local/bin` resolves first while the shim's directory is absent. The close then reaches the un-forced API path, iTerm2 raises its confirmation modal, the call blocks until `tas_bounded` kills it at 8s, and `close_and_log` reports rc 124 with the pane still open.

---

### 9. The detached block closes the pane before removing the worktree, from a process descended from that pane

**What.** `close_and_log` and the `git worktree remove` run sequentially in one background subshell whose ancestor is the very session being closed, so everything after the close may never execute.

**Where.** Lines 951, 970–974:

```bash
    close_and_log "$PANEID" "$MEMBER_NAME"
```
```bash
  if [[ -n "$WORKTREE" ]] && $WORKTREE_OWNED; then
    MAIN_REPO=$(git -C "$WORKTREE" rev-parse --git-common-dir 2>/dev/null | sed 's|/\.git$||')
    if [[ -n "$MAIN_REPO" && -d "$MAIN_REPO" ]]; then
      git -C "$MAIN_REPO" worktree remove "$WORKTREE" --force 2>/dev/null \
```

**Why it is wrong.** Lines 208–211 and 934–938 establish that on the implicit-team model this hook runs as a descendant of the idle teammate's own `claude.exe`, i.e. inside the pane whose id it resolves. The subshell is backgrounded but not detached from that process group (no `setsid`/`nohup`), so when the pane close succeeds and iTerm2 tears down the session's job, this subshell can be signalled along with it — after `close_pane` and before lines 190–196 log the outcome and 973 removes the worktree. The observable result is a successful close with no `✓ closed pane` line and a leaked worktree; on the LEAD-side model (lines 30–35) the same code is fine, which is what makes the failure intermittent by model rather than absent.
