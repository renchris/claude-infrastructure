# dispatcher — activation snippet (T-P7-4/5 L4 dispatcher spine wiring)

**C10 ceiling:** the `dispatcher` agent builds + RED-proves `bin/cc-dispatch` (backlog-pull →
quota-place → claim + spawn, with an abstention-law quota-cliff) and the additive `cc-backlog
list --json`. The **operator** performs the live wiring below. Nothing here is auto-loaded: this
file is the hand-off. The agent never `launchctl load`s, never edits `settings.json`, never
symlinks, and never runs the cron itself. **Autonomous "Claude kicks off Claude" spawning begins
ONLY when the human loads the launchd job.** Until then `cc-dispatch` is a plain CLI you can run by
hand (`--dry-run` first).

## What was built (repo files, on `feat/desk-dispatcher`)

| Artifact | Kind | Needs wiring? |
|---|---|---|
| `bin/cc-dispatch` | the dispatcher spine (`--once` cron entry · `--dry-run` · `selftest`) | **symlink** into `~/.claude/bin/` + load the plist below |
| `bin/cc-backlog` (`list --json`) | additive machine-readable list branch (default table unchanged) | already symlinked (this is an in-place additive change to a live tool) |
| `tests/cc-dispatch.bats` + `selftest` | branch RED-proofs (empty / cliff / green / spawn-fail / dry-run / cap) | none (CI/regression only) |
| `launchd/com.claude.dispatcher.plist` | TEMPLATE plist (RunAtLoad **false**, StartInterval 900) | **operator** `launchctl bootstrap` |

## Interface contract

```
cc-dispatch --once        one cron pass: pull open backlog → quota-place → claim + spawn (≤MAX_SPAWN)
cc-dispatch --dry-run     steps 1-4 as READS only; PRINT the plan; NO claim / spawn / page / IDL
cc-dispatch selftest      RED-proves every branch against stubbed actuators
    exit 0 = normal (passed | abstained-cliff | fired/failed loop)
    exit 3 = config-fail LOUD (jq / a required actuator unresolvable, or wave-plan non-cliff error)
```

Env knobs (the plist sets `CC_DISPATCH_PROJECT`; the rest default sanely):
`CC_DISPATCH_PROJECT` (repo whose backlog is dispatched) · `CC_DISPATCH_MAX_SPAWN` (default 2) ·
`CC_DISPATCH_BACKLOG_BIN` · `CC_DISPATCH_WAVEPLAN_BIN` · `CC_DISPATCH_SPAWN_BIN` ·
`CC_DISPATCH_PAGES_DIR` · `CC_DISPATCH_IDL` · `CC_DISPATCH_SID`.

## 🚨 Hard dependency — `cc-wave-plan` (T-P7-6) must exist first

`cc-dispatch` quota-places every wave through **`cc-wave-plan`** (axis d), which is **UNBUILT at the
time of this hand-off** (T-P7-6). By design `cc-dispatch` **fail-LOUDs (exit 3)** rather than firing
blind when the wave-planner is unresolvable — it never spawns on an unknown quota. So the activation
ORDER is fixed:

1. Build + land `cc-wave-plan` (T-P7-6) and symlink it: `ln -sfn …/bin/cc-wave-plan ~/.claude/bin/cc-wave-plan`.
2. Confirm the contract: `cc-wave-plan --items '[{"id":"x","slot":"lead"}]' --json` emits a JSON
   array of placements `{id, account, fire_line:[argv…]}`, and **exit 4 on a quota-cliff**.
3. Only then load the dispatcher plist (below). A `--dry-run` on a seeded backlog verifies the join
   before you ever load the cron.

Until step 1, `cc-dispatch --once` on a non-empty backlog exits 3 (loud, no spawn) — the correct
fail-closed behavior, not a silent no-op.

## Step 1 — land the branch, then symlink `cc-dispatch`

```sh
# land feat/desk-dispatcher via the project-local /ship (content-verified) first, then:
ln -sfn ~/Development/claude-infrastructure/bin/cc-dispatch ~/.claude/bin/cc-dispatch
cc-dispatch selftest | tail -1        # → "cc-dispatch selftest: 18 passed, 0 failed"
```

`bin/cc-backlog` is already a live symlink; its `list --json` addition is additive (default table
output is byte-unchanged), so no re-linking is needed.

## Step 2 — dry-run against the real backlog (no spawn, no writes)

```sh
# seed one item, then see the plan cc-dispatch WOULD execute (needs cc-wave-plan linked; §dependency):
cc-backlog add --title "smoke: dispatcher dry-run" --project "$HOME/Development/claude-infrastructure"
CC_DISPATCH_PROJECT="$HOME/Development/claude-infrastructure" cc-dispatch --dry-run
```

## Step 3 — load the launchd job (this is what turns autonomy ON)

```sh
# copy (or symlink) the template into LaunchAgents, then bootstrap it:
cp ~/Development/claude-infrastructure/launchd/com.claude.dispatcher.plist ~/Library/LaunchAgents/
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.claude.dispatcher.plist
launchctl print gui/$(id -u)/com.claude.dispatcher | grep -E 'state|program'   # confirm loaded
```

(The classic form is `launchctl load -w ~/Library/LaunchAgents/com.claude.dispatcher.plist`.)
`RunAtLoad` is false, so nothing fires at load time — the first pass runs one `StartInterval` (900s)
later. Edit `StartInterval` / `CC_DISPATCH_PROJECT` in the plist before loading if needed.

**Page channel:** a quota-cliff writes `~/.claude/autonomy/pages/cc-dispatch-quota-cliff.page` (epoch
+ message) and abstains — it does NOT spawn. That page surfaces only if the desk **autonomy-sweep**
(`scripts/autonomy-sweep.sh`) is draining `pages/`; ensure that job is loaded too, or the cliff
signal sits unread.

## Verify (after loading)

```sh
launchctl print gui/$(id -u)/com.claude.dispatcher >/dev/null && echo "loaded"
tail -5 ~/.claude/autonomy/idl.jsonl | jq -c 'select(.actor=="cc-dispatch")'   # run records
tail -20 /tmp/claude-dispatcher.stderr.log                                     # any exit-3 config-fail
```

## Rollback / kill-switch

```sh
launchctl bootout gui/$(id -u)/com.claude.dispatcher      # stop autonomous spawning immediately
rm -f ~/Library/LaunchAgents/com.claude.dispatcher.plist  # (optional) remove the job
# cc-dispatch remains runnable by hand; unlink to fully retract:
rm -f ~/.claude/bin/cc-dispatch
```

Booting out the job is the single kill-switch: with the launchd job gone, no autonomous spawn can
occur — `cc-dispatch` only ever acts when something invokes it.
