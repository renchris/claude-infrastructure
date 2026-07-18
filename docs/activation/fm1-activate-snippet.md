# FM1 kill-stack — activation snippet (Program B: P0-2 / P0-3 / P0-4)

**C10 ceiling:** the agent builds + tests these; the **operator** (or the `wiring-author`
consolidation bundle) performs the live wiring below. Nothing here edits `settings.json`, a
plist, or a live hook in place — this file is the hand-off.

## What was built (repo files, all landed on `feat/desk-fm1-stack`)

| Artifact | Kind | Needs wiring? |
|---|---|---|
| `scripts/wrap-ledger.sh` | pure-read ledger (`--machine` / `--full` / readout) | **symlink** into `~/.claude/scripts/` (consumed by both hooks below) |
| `commands/wrap.md` | `/wrap` command doc | none — commands auto-resolve from the repo |
| `hooks/completion-assert.sh` | **new** Stop hook (confident/tell-free false-done) | **symlink + Stop-array entry** in each config dir |
| `hooks/anti-deference-nudge.sh` | **edited in place** (P0-4 triple fix) | none new — already Stop-wired 4/4 dirs (symlink already exists); it now *reads* `wrap-ledger.sh` |

Live wiring today (verified read-only): `anti-deference-nudge.sh` is on the Stop chain in all four
config dirs (`~/.claude`, `-secondary`, `-tertiary`, `-quaternary`) as a symlink to the repo, so
the P0-4 edit takes effect the moment the branch lands to `main` (the symlink target). The desk
runs on `.claude-tertiary`/`.claude-secondary`.

## Policy note — why completion-assert + the anti-deference ship-narrowing belong on the DESK dirs

Both encode the **2026-07-17 strengthening**: *ship/land of clean, verified, net-positive work is
DRIVABLE, not a hold* (design-law #8; G-P11-2). So a `📦 Done, only on a branch — say the word to
ship` close **fires** (drive the `/ship`) instead of parking. This is correct for the 24/7
no-human desk (which has a project-local `/ship` that lands autonomously). The resident CLAUDE.md
still frames push as the user's call for *interactive* sessions — so wire these on the **desk
config dirs**; if you also wire them on a purely interactive dir, expect `📦`-park closes there to
be nudged toward `/ship`. Both hooks are latched + capped (≤3 fires/session) and fail-safe
(exit 0 on every error), so the worst case is a bounded, ignorable nudge — never a wedged session.

## Step 1 — land the branch (so the symlink targets exist on `main`)

Land `feat/desk-fm1-stack` via the project-local `/ship` (content-verified). Until then the repo
files live only in the worktree.

## Step 2 — symlinks (one `scripts/` link covers every config dir)

```sh
# wrap-ledger: the hooks try $(dirname $0)/../scripts, then $CLAUDE_CONFIG_DIR/scripts, then
# $HOME/.claude/scripts — so this single link under ~/.claude satisfies the fallback for ALL dirs.
ln -sfn ~/Development/claude-infrastructure/scripts/wrap-ledger.sh ~/.claude/scripts/wrap-ledger.sh

# completion-assert hook symlink, per config dir that will run it (desk dirs shown):
for d in ~/.claude ~/.claude-secondary ~/.claude-tertiary ~/.claude-quaternary; do
  ln -sfn ~/Development/claude-infrastructure/hooks/completion-assert.sh "$d/hooks/completion-assert.sh"
done
```

If `wrap-ledger.sh` is absent, both hooks **degrade safely**: the ship-hold narrowing reverts to
the old carve-out (abstain) and done-assertions abstain (`done-ledger-clean`) — no false blocks.
The *feature* (ship-drivable fire, false-done fire) needs the link present.

## Step 3 — add completion-assert to the Stop chain (each desk config dir)

Add this object to `hooks.Stop[0].hooks` (the obj-1 array that already holds `session-continue` +
`anti-deference-nudge`), positioned **after** `anti-deference-nudge.sh`:

```json
{ "type": "command", "command": "~/.claude/hooks/completion-assert.sh", "timeout": 10 }
```

Non-interactive apply (operator/wiring-author runs it; repeat per config dir):

```sh
for d in ~/.claude ~/.claude-secondary ~/.claude-tertiary ~/.claude-quaternary; do
  f="$d/settings.json"
  jq '(.hooks.Stop[0].hooks) |=
        (if any(.[]; .command | test("completion-assert")) then .
         else . + [{type:"command", command:"~/.claude/hooks/completion-assert.sh", timeout:10}] end)' \
     "$f" > "$f.tmp" && mv "$f.tmp" "$f"
done
```

Both `anti-deference` and `completion-assert` may emit `decision:block` on the same Stop; Claude
Code merges the reasons (harness-dependent) — acceptable, and each is independently latched so
neither loops.

## Verify (after wiring)

```sh
# ledger link resolves:
~/.claude/scripts/wrap-ledger.sh --machine | grep '^RUNG='
# completion-assert is on the Stop chain in every desk dir:
for d in ~/.claude ~/.claude-secondary ~/.claude-tertiary ~/.claude-quaternary; do
  echo "$d: $(jq '[.. | .command? // empty | select(test("completion-assert"))] | length' "$d/settings.json")"
done
# IDL shows records once a real Stop fires (was 0/176 for anti-deference before P0-4):
tail -5 ~/.claude/autonomy/idl.jsonl | grep -E 'completion-assert|anti-deference' || echo "no records yet"
```

## Rollback (one-liner per concern)

```sh
# remove the Stop-array entry in every dir:
for d in ~/.claude ~/.claude-secondary ~/.claude-tertiary ~/.claude-quaternary; do
  f="$d/settings.json"
  jq '(.hooks.Stop[0].hooks) |= map(select(.command | test("completion-assert") | not))' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
done
# drop the symlinks:
rm -f ~/.claude/scripts/wrap-ledger.sh
for d in ~/.claude ~/.claude-secondary ~/.claude-tertiary ~/.claude-quaternary; do rm -f "$d/hooks/completion-assert.sh"; done
# the P0-4 anti-deference edit reverts with the branch (git revert of the landed commit).
```
