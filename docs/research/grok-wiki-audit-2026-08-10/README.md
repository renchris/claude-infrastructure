---
status: open
---

# grok-wiki audit, 2026-08-10 — five shards over claude-infrastructure

**What this is.** A repo-wide defect sweep run through `grok-wiki ask` against the local Codex CLI,
five shards, each scoped to one subsystem but reading the whole repo as context. The per-shard agent
output is preserved verbatim in `shard-*.md` — these are the ONLY durable copies; the originals were
in `/tmp`.

**How it was run** (reproduce with a different shard by editing the first line of the question):

```
env PATH="$(echo "$PATH"|tr : '\n'|grep -v fnm_multishells|paste -sd: -)" \
  grok-wiki ask /Users/chrisren/Development/claude-infrastructure \
  "$(cat /tmp/gw-q-<shard>.txt)" --agent codex --reasoning high --mode deep
```

Two configuration facts made the difference and are worth keeping:

- The `fnm_multishells` PATH entry holds a **broken npm `claude` stub** (a non-executable 500-byte
  postinstall-failed shim). grok-wiki's agent detector spawns every candidate unconditionally, so
  that one `EACCES` threw the whole scan and NO agent was detectable — including `codex`. Stripping
  that PATH entry is what made the tool work at all.
- Every audit inherits `~/.codex/config.toml`, not the flags you pass. The first two shards silently
  ran at `gpt-5.5`/`medium` while `--reasoning high` produced no error and changed nothing. The
  config now pins `gpt-5.6-sol` @ `xhigh` (Codex CLI 0.147.0). **Update the CLI before reading its
  model list** — a stale `models_cache.json` was simultaneously unreadable by the old client and
  hiding three `gpt-5.6` models.

## Ledger — what the sweep produced

**Verified and FIXED (7, all landed on origin/main):**

| Defect | Shape |
|---|---|
| `hooks/curl-gate.py` + `hooks/curl-gate-scope.sh` | gate inert in reso's 64 linked worktrees, in BOTH the python gate and the bash shim fronting it |
| `hooks/task-quality-gate.sh` | `\|\| true` made the Phase 0 rejection branch unreachable — dead since it shipped |
| `scripts/land-verify.sh` | an unresolvable range returned `✓ 0 path(s) … rc=0` — certified a land it never inspected |
| `scripts/lib/worker-claim-gate.sh` | read only the final path component, so the gate was blind one directory into a worktree; also a locale-dependent `[!0-9a-f]` that accepted uppercase |
| `scripts/ship-land.sh` ×2 | afunix + tsv-pad arms printed "NON-VERDICT, not a claim about your tree" then called `gate_red` |
| `docs/activation/*-activate.sh` ×3 | a config that failed to wire printed `FAILED (left intact)` and then `DONE`, exit 0 |

**Verified then RETRACTED (1)** — `session-index-sweep.sh`, backlog `7324ff60174c`. Filed as a
"permanent silent no-op", disproved on follow-up: `session-index-start.sh:46` and
`session-index-end.sh:29` own DB creation, so the sweep was never the bootstrapper and a missing DB
means nothing to sweep. Recorded because the retraction is the useful artifact: the original repro
proved only `rc=0 with no DB` and could not distinguish "failed to bootstrap" from "nothing to do".

**UNVERIFIED leads (8 filed)** — backlog `d96fe0f575d1` (scripts, 5) and `9ea31151dd94` (tests, 3).
**Verify each before fixing.** Two of the first shard's six findings were artifacts of a too-narrow
shard scope, and one more was retracted after verification, so the base rate of a raw finding being
real is well under 100%.

### `d96fe0f575d1` (scripts+bin, 5) — adjudicated 2026-08-11: **5 FIXED, 0 disproved**

Every one was reproduced against the real `origin/main` artifact BEFORE any fix, and every new test
was mutant-verified in both directions (red on the unfixed subject, green after). All five landed.

| # | Defect | Pre-fix observed | Landed |
|---|---|---|---|
| 1 | `cc-bus` writes escaped JSON, reads it with `[^"]*` | `inbox` delivered `he said \`; `work --json` emitted `"evidence":"fixed in \"}` — unparseable | `3ec3da12` |
| 2 | `cc-relogin-poll` watchdog TERM-only + unbounded `wait` | TIMEOUT_S=3 + TERM-trapping child ⇒ still waiting at an outer 15s bound (rc 124) | `f8872689` |
| 3 | `cc-respawn` matches `--agent-name` by substring | with only `tm-api-worker` live: verify-spawned rc 0 "live" (FALSE GO), verify-stopped rc 5 "STILL ALIVE" | `247f01be` |
| 4 | `CC_DEPLOY_HOST_CUT_MAX=0` documented as disable | end-to-end via the suite's own harness: PAGED-ON-FIRST-CUT | `8fafb6ae` |
| 5 | postland mutex honours any live pid | lock aged 208572449s (TTL 900) + live stranger pid ⇒ REFUSED, forever | `78711374` |

Candidate 2's filed trigger was overstated and the commit says so: today's `cc-relogin` is python3
with **no** signal handler and dies on a plain TERM, so nothing is hanging now. The defect is that
nothing in the file MADE the bound true — it held only by a property of a child the file does not
own, and `$RELOGIN_BIN` is env-overridable.

**Follow-on filed, not fixed:** `abab60591342` — `cc-bus emit` interpolates `CC_BUS_ACTOR` RAW, so
`ev"il` writes invalid JSON *and* becomes the shard filename `ev"il.jsonl`. The WRITER mirror of
candidate 1, and candidate 1's fix makes it louder rather than quieter. Needs an actor-id
validation decision, not an escape one-liner.

### A third rule this round earned — and it cost a false accusation

**Never mutate the subject in place in a SHARED worktree.** One agent's mutant harness mutated the
real `scripts/deploy-live.sh`, ran, and restored it. The lead sampled the tree inside that window,
read the `-gt 1` control as shipped code, and reported it to the agent as an off-by-one defect in
their fix. It was not: the shipped code was `-gt 0` throughout, and the agent was right to push
back. **The tell was available and misread** — the file's comments said `-gt 0` while the code said
`-gt 1`, and a mutant does not rewrite comments, so the correct inference was "one of these is
transient", not "the code is wrong."

Commit `8fafb6ae`'s message states "The first draft of this fix used `-gt 1`". **That sentence is
false** — it was the agent's deliberate control, never a draft. Recorded here because the commit
message cannot be amended after landing, and because the misread is more instructive than the
fix: with five agents and a lead reading one checkout, an in-place mutation makes the tree lie to
every concurrent reader. Mutate a scratch copy and point the suite at it. (Same family as
`unfixtured-sensor-executes-the-deployed-subject`.)

The `-gt 1` mutant is itself a genuine and valuable control, independently built and run against a
scratch copy: `CUT_MAX=0` passes under it while `CUT_MAX=1` fails, which is what proves the two
tests together separate "0 disables" from "off by one".

### Controls that could not fail, caught during this round

Three, all found by running them rather than reading them:

1. **A vacuous new test.** The land gate's dead-assertion ratchet flagged a mid-test bare
   `[[ ]]` in the new `cc-bus` suite — errexit cannot reach it, so the drain dry-run half asserted
   nothing. Revived via `scripts/bats-assert-liveness-fix.py`, and the revival was *proven*: against
   the pre-fix subject the test now fails AT that line instead of falling through to a later one.
2. **`bash -c 'sleep N'` exec-optimizes and drops its own argv**, so a fake teammate process was
   invisible to `ps` and `cc-respawn` "correctly" reported it absent — a false disproof of a real
   defect. The two-command form (`'sleep N; true'`), which the script's own selftest already uses,
   is what makes the fake visible.
3. **A harness that matched itself.** A repro script whose own argv contained `--agent-name tm-api`
   was found by the very field-walk under test, returning a pid that was not the sibling. Moving the
   harness into a file and splitting the flag literal fixed it; an explicit contamination check that
   must print nothing now gates the result.

**Tests shard adjudicated (3 of the 8), 2026-08-11 — all three CONFIRMED, none disproved.** Backlog
`9ea31151dd94`; landed `fe6540a6` · `28a8fba9` · `90f7be7e`. Each was adjudicated by running the
pre-fix artifact on the failing input, per rule 2 below:

| Lead | Pre-fix observed | Post-fix |
|---|---|---|
| `ship-land.sh` gated the .bats ratchet on `command -v shellcheck` | on a genuinely shellcheck-less PATH with a .bats-only diff: **`gate GREEN`, exit 0**, the word never printed | `⛔ … could not RUN (exit 2) — a NON-VERDICT`, exit 9 |
| the two `tests/*redproof*` harnesses were a manual sidecar | outside their own bodies both names appear **only in comments and plan docs** — nothing ran either | `--check-anchors` on every `bats tests/*.bats`, + a glob CENSUS |
| `alarm-polarity-lint.bats` positive control was history-derived | in a `--depth 1` clone: **`ok 1 POSITIVE CONTROL … # skip`** | baseline vendored + sha256-pinned; cannot skip |

Two lessons the shard itself did not contain, both paid for at the land gate:

- **A verifier fix is judged by the sibling verifiers.** The land gate refused this work twice on
  grounds no local run had raised — an unpinned shape-5a seam in the new suite, and
  `permission-gate-lint` going stale because rewriting two legs into the house's rc-capture form
  moved them out of its `negated()` shape (`ship-land.sh` 17 → 15, the ratchet's *downward* half).
  Neither is visible from the file you are editing.
- **The trap in rule 1's own file bit twice.** A comment line beginning with the linter's name
  parses as a malformed directive and silently stops analysis of the WHOLE file. It happened once in
  `ship-land.sh` and once in `bats-shellcheck-lint.bats` — i.e. inside the suite whose entire job is
  to ratchet that class. Run the lint over your own diff before believing a green.

**Still open from the sweep:** `d96fe0f575d1` (scripts, 5) unverified; `5d6dcbe8d462` filed —
`scripts/banner-gate-redproof.py` is the same unwired-red-proof class as the two fixed above
(nightly's step-4 globs both end in `.sh`; it is a `.py`), deferred as banner-subsystem scope.

## The two rules that earned their keep

1. **Fix the chokepoint, not just the subject.** `settings.json` invokes `curl-gate-scope.sh`, which
   substring-matches `PROJECT_ROOT` and exits before python ever runs — over a comment reading
   *"cwd cannot be under PROJECT_ROOT ⇒ gate is a proven no-op"*. Fixing only `curl-gate.py` would
   have turned the new suite green while production stayed exactly as broken.
2. **Adjudicate against the real pre-fix artifact.** For every fix here: `git show origin/main:<file>`
   into a scratch path, run it on the failing input, observe the OLD behaviour, then observe the new.
   A control that cannot fail proves nothing — and two of this session's own controls silently didn't
   (a `sed` mutant that never applied because of a `||`, and a pre-fix copy run from `/tmp` where
   `$REPO` resolved outside the checkout so it exited early at an unrelated guard).
