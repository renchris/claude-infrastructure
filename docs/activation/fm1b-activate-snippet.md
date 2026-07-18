# FM1b continuity — activation snippet (Program B: P0-16 continue/DoD halves)

**C10 ceiling:** the agent builds + tests these; the **operator** (or the `wiring-author`
consolidation bundle) performs the live wiring below. Nothing here edits `settings.json`, a plist,
or a live hook in place — this file is the hand-off.

## What was built (repo files, all landed on `feat/desk-fm1b-continuity`)

| Artifact | Kind | Needs wiring? |
|---|---|---|
| `hooks/session-continue.sh` | **edited** — kill-switch + sid-bind + cap re-arm (a19 D-7/D-8, a17 S-12) | none new — already Stop-wired 4/4 (symlink); effect lands with the branch |
| `hooks/boundary-handoff.sh` | **edited** — compose-guard reads the REAL sentinel path (G-P6-6b) | **re-register on ALL 4 dirs** (§4) — today it is on ~/.claude only, in a dead obj-2 |
| `hooks/lib/continue-sentinel.sh` | **new** — sentinel-path SSOT sourced by BOTH hooks | **symlink** into `~/.claude/hooks/lib/` (§2) — REQUIRED or session-continue goes inert |
| `hooks/dod-persist.sh` | **new** — SessionStart re-inject + PreCompact capture of the frozen DoD (a19 HOP A) | **symlink + SessionStart entry + PreCompact entry** per dir (§2/§3) |

The desk runs on `.claude-tertiary` / `.claude-secondary`; both must carry every entry below.

## Step 1 — land the branch (so the symlink targets exist on `main`)

Land `feat/desk-fm1b-continuity` via the project-local `/ship` (content-verified). Until then the
repo files live only in the worktree. `session-continue.sh` + `boundary-handoff.sh` are already
symlinked as hooks in all four config dirs, so their EDITS take effect the moment the branch lands —
but the two NEW files (`continue-sentinel.sh`, `dod-persist.sh`) still need the symlinks + Stop /
SessionStart / PreCompact array entries below.

## Step 2 — symlinks (the shared lib is LOAD-BEARING)

```sh
# continue-sentinel.sh — sourced by BOTH session-continue.sh and boundary-handoff.sh. The hooks
# resolve it at $(dirname $0)/lib, i.e. ~/.claude/hooks/lib/… — one link covers every config dir
# (the other dirs' hooks/ symlink to ~/.claude/hooks). WITHOUT it session-continue fails LOUD and
# the 🔧 loop goes inert (safe, but the continuation feature is off), so wire it FIRST.
ln -sfn ~/Development/claude-infrastructure/hooks/lib/continue-sentinel.sh ~/.claude/hooks/lib/continue-sentinel.sh

# dod-persist.sh — one link into the shared ~/.claude/hooks/ (the loop is for parity with the other
# snippets; the per-dir hooks/ all resolve to the same real dir).
for d in ~/.claude ~/.claude-secondary ~/.claude-tertiary ~/.claude-quaternary; do
  ln -sfn ~/Development/claude-infrastructure/hooks/dod-persist.sh "$d/hooks/dod-persist.sh"
done
```

If `continue-sentinel.sh` is absent, both hooks **degrade safely**: session-continue prints a FATAL
to stderr and allows the stop (loop inert); boundary's compose-guard can't compute the path and
simply does not suppress (it never wrongly fires on a missing lib). No false blocks either way.

## Step 3 — dod-persist on SessionStart (re-inject the frozen DoD) — each config dir

Add a SessionStart object that runs `dod-persist.sh` (idempotent; skips if already present):

```sh
for d in ~/.claude ~/.claude-secondary ~/.claude-tertiary ~/.claude-quaternary; do
  f="$d/settings.json"
  jq '(.hooks.SessionStart) |=
        (if any(.[]?; (.hooks // []) | any(.command | test("dod-persist"))) then .
         else . + [{hooks:[{type:"command",command:"~/.claude/hooks/dod-persist.sh",timeout:5}]}] end)' \
     "$f" > "$f.tmp" && mv "$f.tmp" "$f"
done
```

On a fresh / recycled / compacted session this re-emits the durable `~/.claude/autonomy/dod/<hash>.md`
as `additionalContext` — the frozen scope re-enters mechanically (closes a19 HOP A + HOP E).

## Step 4 — dod-persist on PreCompact (capture the frozen DoD before the summarizer) — each dir

Add `dod-persist.sh` to every existing PreCompact matcher object (the live config has `auto` +
`manual`), so the scope is captured before either compaction path:

```sh
for d in ~/.claude ~/.claude-secondary ~/.claude-tertiary ~/.claude-quaternary; do
  f="$d/settings.json"
  jq '(.hooks.PreCompact) |= ((. // []) | map(
        if (.hooks // []) | any(.command | test("dod-persist")) then .
        else .hooks += [{type:"command",command:"~/.claude/hooks/dod-persist.sh",timeout:10}] end))' \
     "$f" > "$f.tmp" && mv "$f.tmp" "$f"
done
```

Desired end-state (one matcher object shown):

```json
{ "matcher": "auto", "hooks": [
    { "type": "command", "command": "date '+[%Y-%m-%d %H:%M:%S] Auto-compact triggered' >> ~/.claude/logs/sessions.log", "timeout": 5 },
    { "type": "command", "command": "~/.claude/hooks/dod-persist.sh", "timeout": 10 } ] }
```

## Step 5 — boundary-handoff on ALL FOUR config dirs (G-P6-5b) — into the obj-1 Stop array

Today boundary lives ONLY on `~/.claude`, in a SEPARATE matcher-null Stop object via a hardcoded
absolute repo path → 0 IDL records in prod. Drop that stray entry and add boundary to the SAME Stop
array as `session-continue` + `anti-deference` (obj-1), by the `~/.claude/hooks/…` path, in every dir:

```sh
for d in ~/.claude ~/.claude-secondary ~/.claude-tertiary ~/.claude-quaternary; do
  f="$d/settings.json"
  jq '
      (.hooks.Stop) |= map(.hooks |= map(select(.command | test("boundary-handoff") | not)))
    | (.hooks.Stop) |= map(select((.hooks | length) > 0))
    | (.hooks.Stop[0].hooks) |=
        (if any(.[]; .command | test("boundary-handoff")) then .
         else . + [{type:"command",command:"~/.claude/hooks/boundary-handoff.sh",timeout:10}] end)
  ' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
done
```

**Dependency:** boundary still only FIRES once a production `gate-green` writer exists (P0-1, owned by
landing's `ship-land.sh`) — until then it correctly abstains `gate-not-green-at-head`. Registering it
on 4 dirs is the wiring half; the gate-green producer is the fire half.

## Verify (after wiring)

```sh
# shared lib resolves:
test -e ~/.claude/hooks/lib/continue-sentinel.sh && echo "lib OK"
# dod-persist path contract matches wrap-ledger (same file):
~/.claude/hooks/dod-persist.sh path "$PWD"
# per-dir Stop/SessionStart/PreCompact coverage:
for d in ~/.claude ~/.claude-secondary ~/.claude-tertiary ~/.claude-quaternary; do
  echo "$d: boundary=$(jq '[.hooks.Stop[].hooks[]?.command|select(test("boundary-handoff"))]|length' "$d/settings.json") \
dod-start=$(jq '[.hooks.SessionStart[].hooks[]?.command|select(test("dod-persist"))]|length' "$d/settings.json") \
dod-precompact=$(jq '[.hooks.PreCompact[]?.hooks[]?.command|select(test("dod-persist"))]|length' "$d/settings.json")"
done
# a real Stop / SessionStart / PreCompact then leaves records:
tail -5 ~/.claude/autonomy/idl.jsonl | grep boundary-handoff || echo "boundary: no records yet (needs gate-green)"
ls -t ~/.claude/autonomy/dod/ 2>/dev/null | head    # DoD files appear after the first PreCompact/set
```

## Rollback (one-liner per concern)

```sh
# remove dod-persist from SessionStart + PreCompact, and boundary from Stop, in every dir:
for d in ~/.claude ~/.claude-secondary ~/.claude-tertiary ~/.claude-quaternary; do
  f="$d/settings.json"
  jq '(.hooks.SessionStart) |= map(select((.hooks // []) | any(.command | test("dod-persist")) | not))
    | (.hooks.PreCompact)   |= map(.hooks |= map(select(.command | test("dod-persist") | not)))
    | (.hooks.Stop)         |= map(.hooks |= map(select(.command | test("boundary-handoff") | not)))' \
     "$f" > "$f.tmp" && mv "$f.tmp" "$f"
done
# drop the symlinks:
rm -f ~/.claude/hooks/lib/continue-sentinel.sh
for d in ~/.claude ~/.claude-secondary ~/.claude-tertiary ~/.claude-quaternary; do rm -f "$d/hooks/dod-persist.sh"; done
# the session-continue / boundary-handoff EDITS revert with the branch (git revert of the landed commits).
```
