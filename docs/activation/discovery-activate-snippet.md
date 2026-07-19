# discovery — activation snippet (Program D phase 3, the discovery feed)

**C10 ceiling:** the `discovery` agent builds + RED-proves `bin/cc-discover` (C1 frontier-hole,
C2 plan-open, C3 wiring-inert, C4 gate-red) and ships a TEMPLATE plist; the **operator** performs
the live wiring below. Nothing here loads launchd, edits `settings.json`, or symlinks **in place** —
this file is the hand-off. The feed only ever APPENDS candidates to `cc-backlog` (idempotently,
event-keyed), so a mis-fire adds nothing new; there is no destructive edge to gate.

## What was built (repo files, on `feat/desk-discovery`)

| Artifact | Kind | Needs wiring? |
|---|---|---|
| `bin/cc-discover` | standing-critic feed (`--once` \| `--dry-run` \| `selftest`) | **symlink** into `~/.claude/bin/` + load the plist |
| `tests/cc-discover.bats` + `selftest` | C1-C4 + idempotency + dry-run RED-proofs | none (CI/regression only) |
| `launchd/com.claude.discovery.plist` | TEMPLATE job (RunAtLoad false, hourly) | **install + bootstrap** (Step 2) |

## What each critic reads (the source → candidate map)

```
C1 frontier-hole  OPEN holes in docs/research/FRONTIER_HOLES.md   → "frontier hole: <id · hole>"
C2 plan-open      find-plan.sh --list-open                        → "advance <plan>"
C3 wiring-inert   a hook abstained 100% over N>=10 IDL evals (D9) → "inert hook <name>: re-observe"
C4 gate-red       any gate (never-stuck-gate.sh, premortem-gate.sh) exiting non-zero → "fix red gate <name>"
```

A critic whose source is **ABSENT abstains** (logs it to the IDL) — it never passes silently and
never fabricates a candidate. Idempotency is load-bearing: a second run over unchanged sources adds
**zero** new records (cc-backlog keys on project+title+source).

## Step 1 — land the branch, then symlink `cc-discover`

```sh
# land feat/desk-discovery via the project-local /ship (content-verified) first, then:
ln -sfn ~/Development/claude-infrastructure/bin/cc-discover ~/.claude/bin/cc-discover
```

`cc-discover` resolves `cc-backlog`, `find-plan.sh`, and the gate scripts from
`~/.claude/{bin,scripts,hooks}` — so those must already be symlinked (they are, via the standard
`wiring-all.sh` / per-file links). If `cc-backlog` is unresolvable at run time, `cc-discover` exits
**3 LOUD** rather than silently adding nothing.

## Step 2 — install + bootstrap the launchd job (operator only)

```sh
# 1. copy the template into LaunchAgents
cp ~/Development/claude-infrastructure/launchd/com.claude.discovery.plist \
   ~/Library/LaunchAgents/com.claude.discovery.plist

# 2. sanity-lint it
plutil -lint ~/Library/LaunchAgents/com.claude.discovery.plist        # → OK

# 3. bootstrap (modern launchctl; replaces the deprecated `load`)
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.claude.discovery.plist

# 4. (optional) kick one run now — the template has RunAtLoad=false, so it is otherwise hourly
launchctl kickstart -k gui/$(id -u)/com.claude.discovery
```

The plist pins `CC_DISCOVER_FRONTIER_LEDGER` to an absolute path and `CC_DISCOVER_PROJECT` to
`claude-infrastructure` (launchd runs with cwd=`/`, where the tool's repo-relative ledger default
would not resolve). Adjust either env line if the ledger lives elsewhere.

## Step 3 — verify before trusting the interval

```sh
# dry-run first: prints candidates, writes NOTHING (backlog + IDL untouched)
CC_DISCOVER_FRONTIER_LEDGER=~/Development/claude-infrastructure/docs/research/FRONTIER_HOLES.md \
  cc-discover --dry-run

# then a real pass; confirm the backlog GREW by the expected candidate count
cc-backlog list --open | tail
```

Logs land at `/tmp/claude-discovery.stdout.log` (+ `.stderr.log`). The stdout of each run is a
per-critic action line (`fired`/`passed`/`abstained`) plus a one-line summary.

## Kill-switch + degradation

- **Stop the feed:** `launchctl bootout gui/$(id -u)/com.claude.discovery`.
- **Tune cadence:** edit `StartInterval` (seconds) in the installed plist, then bootout + bootstrap.
- **Missing symlink degrades safely:** with `~/.claude/bin/cc-discover` absent the job simply fails
  to exec and logs to stderr — nothing is added, no state is corrupted.
- **Narrow the gates (C4):** set `CC_DISCOVER_GATES` in the plist to a subset (or empty) if running
  every gate hourly is undesirable; an empty/absent gate list makes C4 abstain, never error.
