# Never-wait-on-the-dead — ACTIVATION runbook (C10: human-only)

The five-layer build (L0..L4) is **complete, RED-proven, and landed on trunk**; `scripts/wait-safety-gate.sh`
is fully GREEN (`13 met · 0 failed · 0 NOT BUILT`). What remains is **activation — wiring the built tools
into the live runtime — which is C10 (human-only) by policy.** The agent built + tested and wrote this
runbook + `/tmp/never-wait-activate.sh`; **the operator runs it.** The agent never symlinks, never edits
`settings.json`, never loads launchd, never registers a hook.

## What each layer needs, and why

| Layer | Tool (on trunk) | Activation | Why it is C10 |
|---|---|---|---|
| **L2** wait contracts | `bin/cc-wait`, `scripts/wait-contract-lint.sh` | symlink `cc-wait` → `~/.claude/bin`; schedule `wait-contract-lint.sh --sweep ~/.claude/wait-contracts` on the supervisor sweep (pages a dead-waiter OPEN contract); migrate `cc-await-ping` consumers to `cc-wait` | runtime persistence + supervisor wiring |
| **L1** death-watcher | `bin/cc-deathwatch-kqueue`, `scripts/lead-deathwatch.sh` | symlink `cc-deathwatch-kqueue` → `~/.claude/bin`; run `lead-deathwatch.sh --watch <watch-file>` as a persistent watcher (launchd), watch-file built from the P8 registry (spawn-instant `{pid,start,label,waiter,worktree}` rows) | launchd persistence |
| **L4** reconciler | `scripts/lead-reconciler.sh` | schedule `lead-reconciler.sh --once` on the supervisor sweep with a REAL `CC_RECON_ROSTER_TASKS` (a reader of the harness task table); a heartbeat monitor on `~/.claude/reconciler/heartbeat.json` | supervisor wiring + the harness-API reader |
| **L3** heartbeats | `bin/cc-run` | symlink `cc-run` → `~/.claude/bin`; wrap long ops as `cc-run --label <l> -- <cmd>`; a monitor watches `~/.claude/cc-run/*.beat` mtime freshness | monitor wiring |

## The composition (why activating all of it is one system, not four tools)

Every layer declares its structural blindness and names the layer that covers it — that is what turns five
PARTIAL detectors into one COMPLETE one:

- **L3** silent-compute op (no output) → indistinguishable from a hang by output alone → covered by **L1**
  (pid death) + its L2 contract's `heartbeat_expectation=none` (so it does not false-page).
- **L1** a pid it never registered fires nothing → covered by the **P8 registry** (spawn-instant
  registration) + **L2**'s unregistered-waitee RED (an event-driven wait on an unwatched waitee lints RED).
- **L2** a dead-waiter's open contract → covered by **L4**'s roster divergence (the contract outlives its
  author on disk; the reconciler sees tasks-say-alive / registry-say-dead).
- **L4** three-way AGREEMENT on a wrong state → the named residual; mitigated (not closed) by three
  INDEPENDENT sources (harness API / pid `kill -0` / disk mtime). Nobody checks this by hand — declared.

A blindness declared WITHOUT a covering route would be an open hole. Here every one is another layer's
covered case, so activating the set closes the loop the 77-minute-strand incident opened.

## Activation steps

Run `/tmp/never-wait-activate.sh` (the agent opened it in Cursor). It is idempotent and does only the SAFE
symlinks + prints the wiring templates for you to adapt to your launchd/supervisor. In order:

1. **Symlinks** — `ln -sf` the three `bin/` tools into `~/.claude/bin` (idempotent; no-op if already linked).
2. **Post-activation verification** — each tool resolves on PATH AND its `selftest` fires GREEN *deployed*
   (not just in the repo) — the `cc-board`-shipped-un-symlinked trap; a committed tool is not a live tool.
3. **Wiring templates (you adapt + install)** — the launchd plist for `lead-deathwatch --watch`, the
   supervisor-sweep lines for `lead-reconciler --once` + `wait-contract-lint --sweep`, and the beat-freshness
   monitor. These reference YOUR supervisor/launchd, which the agent cannot see — so they are templates.
4. **Consumer migration** — replace ad-hoc `cc-await-ping` loops with `cc-wait --waitee … --deadline …
   --on-timeout reobserve --note …` (the desk's hourly listener is the first migrated consumer).

## Verify after activation

```
command -v cc-wait cc-deathwatch-kqueue cc-run     # all resolve to this repo's bin/
cc-wait selftest && cc-run selftest                 # deployed selftests GREEN
scripts/wait-safety-gate.sh                         # still 13 met · 0 failed · 0 NOT BUILT
```

## Rollback

Every step is a symlink or a scheduled invocation; to back out, `rm` the symlinks in `~/.claude/bin` and
remove the launchd plist / supervisor lines. No data migration, nothing destructive. The tools on trunk are
untouched.
