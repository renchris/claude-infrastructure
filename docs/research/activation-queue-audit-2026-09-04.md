# Activation queue audit — 2026-09-04

**All eleven pending activations audited, one auditor each, read-only, verified against live disk
rather than against each script's own prose. Ten were already in effect. One was a real gap.**

The operator's question was "eleven config activations await your authorization — which do I run?"
The answer is *one*, and the queue that produced the question is measuring the wrong thing.

## The headline

`hooks/activation-watch.sh` reports a script as pending when its `.done` **marker file** is absent.
Ten of eleven had already taken effect — labels loaded, plists byte-identical to their SSOT, jobs
with hundreds or thousands of runs — and were pending only because nobody touched a marker. So the
nightly "11 rotting activations" line has been reporting **absent markers, not absent wiring**.

That is the same defect shape as several others found the same night: a sensor keyed on a proxy
rather than on the state it stands for.

## Per item

| # | item | verdict | conv. | driving fact |
|---|---|---|---|---|
| 33 | escalation-watch | **RUN** | 96% | Genuinely unregistered; 223 records/24h expiring UNREAD with no reader |
| 13 | mailbox-gc | SKIP | 93% | Payload never merged — `bin/cc-mailbox-gc` absent at HEAD, flag has no reader |
| 18 | fleet | SKIP | 93% | All 21 `expect=run` labels loaded; work loop empty, tail prints a false "degraded" |
| 27 | worktree-gc-infra | SKIP | 97% | Reaping unattended 2 weeks; installed plist byte-identical |
| 30 | teammate-reap-alarm | SKIP | 96% | 696 runs; staged two days *after* the job was already ticking |
| 34 | deploy-plist-fallback | SUPERSEDED | 96% | Live argv already carries the exact fallback string it tests for |
| 35 | auth-timeseries | SKIP | 96% | Live since Aug 24, 12,647 rows; read-only on credentials |
| 36 | start-latency-router | **DO NOT RUN** | 93% | Ran Aug 11; step 2 reverted an hour later — it killed every fire |
| 37 | postland-band | SKIP | 97% | Applied Aug 21; running it discards the in-flight verifier sweep |
| 38 | accounts-board | **DO NOT RUN** | 97% | Its vehicle re-forks all six config directories |
| 41 | browser-spin-guard | SUPERSEDED | 97% | 2,372 runs; reaper already armed by a later commit |

### The two that would cause harm

**36-start-latency-router.** Already executed 2026-08-11 — `~/.zshrc.pre-router.20260811T083246Z`
and `accounts.json.pre-router.20260811T083246Z` are its artifacts. Step 1 is live at `~/.zshrc:701`.
Step 2 was applied and **deliberately reverted an hour later** by `088875158`: *"Within minutes every
fire on the box died with `zsh: command not found: claude1`… The activation flipped the SSOT and the
rc together, which is what I checked; it could not flip the shells, which is what mattered."* Its
step-2 guard expects exactly the current value, so a re-run fires and re-creates the incident. Its
own step-4 self-check would still pass, because it tests in a synthetic `zsh -fc` harness that cannot
see the long-lived panes that are the actual failure surface. The mechanism is superseded anyway:
`handoff-fire.sh:8379` pins with `CC_ACCOUNT_PINNED=1`, not a launcher name.

**38-accounts-board.** Its *goal* is live and worth doing — the keepwarm producer has rendered a
board 3,261 times that no session has ever displayed. Its *vehicle* is `install.sh --wire-hooks`,
which is the generator described below.

## The generator: install.sh re-forks every config directory

`install.sh:230`:

```bash
ensure_real_dir() {
  local dir="$1"
  if [[ -L "$dir" ]]; then
    echo "  ⚠ $dir is a directory symlink — replacing with real directory"
    run rm "$dir"
  fi
  run mkdir -p "$dir"
}
```

Measured via `install.sh --config-dir ~/.claude-quaternary --wire-hooks --dry-run`:

```
⚠ .claude-quaternary/hooks is a directory symlink — replacing with real directory
⚠ .claude-quaternary/lib …    ⚠ .claude-quaternary/commands …
⚠ .claude-quaternary/agents … ⚠ .claude-quaternary/scripts …  ⚠ .claude-quaternary/vendor …
```

Six surfaces, any config dir it is pointed at. **This is why `~/.claude-next/commands` was frozen at
2026-07-18 for seven weeks**, and why `config-mirror.zsh` could never heal it: the mirror creates the
whole-directory symlink, install.sh destroys it and rebuilds per-file links, and install.sh wins
whenever it runs. The two mechanisms fight, silently, and the loser is the one with no alarm.

Consequence: the 2026-09-04 converge of `.claude-next` (commands/hooks/scripts → directory symlinks)
is **not durable**. The next `install.sh --config-dir` run undoes it.

## Corrections this audit forced

- **The verifier's green rate is not 14%.** That figure blends two eras. Split at the 2026-08-21
  band change: PRE n=347 → 9.2% green; POST n=213 → **25.4% green**, red share 39%→11%, ≥3h timeout
  rate halved. The blended figure understates the current regime by ~11 points. It was quoted in
  this session's own commit `9221fe208`.
- **The corpus does not run under `nice -n 19 taskpolicy -c background`.** That prefix is still at
  `postland-verify.sh:428` but is a measured no-op: `$BATS_BIN` resolves to `cc-bats`, which re-execs
  `taskpolicy -c utility`. The live process reads **PRI 20**, not PRI 4.
- **`41-browser-spin-guard` does not guard the retired BrowserMCP.** It guards `agent-browser`-owned
  headless Chrome and matches on the automation argv flag so the operator's own Dia is excluded. Its
  post-retirement staging date is consistent, not contradictory.

## What was done

`33-escalation-watch` activated, sequenced `cc-escalations ack --all` first so it starts from a clean
baseline. Unseen went **1,016 → 2** (both `page`, both zero minutes old, i.e. arriving after the ack).
The hook renders per-class aggregates, timed at **0.82 s** producing 788 bytes against its 10 s
timeout — volume was never the risk, polarity was.

Note the ack is **not a repair**: 471 of the 816 `announce-alarm` records are one root cause,
`cc-notify: target 'desk' is UNKNOWN`, which will refill the class until the desk role is registered.

## Open, and deliberately not decided here

The ten already-in-effect scripts still have no `.done` marker. Touching them asserts something false
by the system's own doctrine (`18-fleet`: a marker records *that the script ran*, not that the effect
landed); leaving them means the queue misreports ten phantom items indefinitely. The durable fix is
to make `activation-watch.sh` assert **effect** rather than marker presence — filed separately.
