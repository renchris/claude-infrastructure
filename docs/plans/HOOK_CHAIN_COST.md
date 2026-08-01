---
status: open
---

# Hook-chain cost — the durable record

**Owner:** row 6 (guardrail/hook layer). **Origin:** backlog `2193948bb00e`, handed over from row 13
in plan prose only (`MACHINE_CAPACITY_V2.md` §8.5.4) — this file is the durable record that item
asked for.

**Scope (frozen):** drive `2193948bb00e` to finished-verified-landed — establish what the hook chain
actually costs, decide broker-vs-collapse on measured grounds, and land what the measurement
supports.

---

## 1. The headline: the item's own premises are half-stale, and its cost model is wrong

§8.5.4 said three things. Measured today, one is stale, one is mis-modelled, and one holds but
against a much smaller base than implied.

| §8.5.4 claim | Verdict | Evidence |
|---|---|---|
| "waiting-recycle.sh does a FULL-FILE jq parse of the session transcript on every PostToolUse" | **STALE — already fixed** | M13 bounded reads landed in `b4590d68` (2026-07-30 02:02:38 -0700 = `09:02:38Z`) with `tests/waiting-recycle-bounded-read.bats`. The item was filed `2026-07-30T08:10:57Z` — **52 minutes before the fix landed**. Measured 438 ms → 24 ms on a 5.5 MB fixture (18×). |
| "waiting-recycle.sh has 131 fork sites" | **Mis-modelled** — the count is not a cost proxy | Static `$(` is now **144** (the script grew), but a `$(` around a **builtin** costs 0.75–1.06 ms while a `$(` around an **external** costs 3.58–6.03 ms — a 5× spread. `printf`, `command -v`, `[` are builtins; counting them as forks overstates. See §2. |
| "the hook chain is O(N²) — 49% of its cost is scheduler queueing it causes itself" | **Mechanism HOLDS, base is ~6–17× smaller than §1 implied** | Fork cost really does scale with load (§2). But the whole Bash chain costs **0.054 cores mean / 0.149 at p95-hour**, not the "~0.9 cores" §1 cited. |

**The one-line correction:** the chain is not expensive because there are many hooks. It is expensive
because **the hooks that do not apply to this session spend the most to discover that** — ~30% of the
chain's cost is hooks abstaining.

---

## 2. The measured model

All figures: this box, **load 14–18** (recorded per block; `uptime` before and after each), median of
10–15 iterations, positive control passing (`bash -c 'sleep 0.05'` measured 63.93 ms vs `bash -c :`
8.39 ms — a 55.5 ms delta for a 50 ms sleep, so the instrument is sound).

### 2.1 Process creation, not interpretation, is the cost

| | median | p95 |
|---|---|---|
| `/usr/bin/true` | 7.06 ms | 7.80 ms |
| `bash -c :` | 7.35 ms | 9.55 ms |
| `jq -n 1` | 9.29 ms | 11.23 ms |
| `zsh -c :` | 10.23 ms | 12.50 ms |
| `python3 -c pass` | **31.45 ms** | 33.48 ms |

`bash -c :` costs 0.29 ms more than `/usr/bin/true`. **Bash's own startup is ~0.3 ms; the other 7 ms
is `fork`+`exec` itself.** So the only metric that matters is *total process creations per event* —
and `python3` is worth **4.3 bash forks**.

### 2.2 `$(` is not a fork count

| construct | per-site cost |
|---|---|
| `$(command -v …)` — builtin | 0.754 ms |
| `$(printf …)` — builtin | 1.058 ms |
| `$(/usr/bin/true)` — external | 3.582 ms |
| `$(date -u …)` — external | 3.763 ms |
| `$(jq -n 1)` — external | 6.025 ms |

A `$(` around a builtin forks a subshell but never `exec`s. **Any future audit of hook cost must
count external execs on the *executed* path, not `$(` occurrences.** The static count conflates two
things that differ 5×, and it counts unreached branches at full price.

### 2.3 The chain, per Bash tool call

Real hook scripts, real 18 MB transcript, real session id. The plan's chain lengths were stale-low
(it said PreToolUse 5 / Stop 9):

| PreToolUse/Bash — **7 hooks** | ms | | PostToolUse/Bash — **4 hooks** | ms |
|---|---|---|---|---|
| `validate-bash.sh` | 70.26 | | `waiting-recycle.sh` | 96.55 |
| `qos-rewrite.sh` | 43.30 | | `teammate-checkpoint.sh` | 51.57 |
| `curl-gate.py` | 35.41 | | `log-bash.sh` | 29.07 |
| `git-worktree-guard.sh` | 20.46 | | `cc-permission-beacon.sh` | 14.76 |
| `keychain-guard.sh` | 15.30 | | | |
| `rm-safe-allowlist.sh` | 14.22 | | | |
| `ship-rail-push-allow.sh` | 13.50 | | | |
| **subtotal** | **212.44** | | **subtotal** | **191.94** |

**Total 404 ms per Bash tool call at load 16** (~800 ms at the load 58 §8.5.4 measured at).

The model predicts each hook: `7 ms (fork) + ~3.5 ms × external execs`. Traced dynamically,
`validate-bash.sh` performs 18 external execs → predicted 70 ms, **measured 70.26 ms**. The model is
validated, and it says the registered-hook count is the *minority* term:
**11 × 7 ms = 77 ms = 19% of the chain; the other 81% is inside the hooks.**

### 2.4 Absolute stakes — the number that decides how much to spend

From `~/.claude/logs/bash-execution.log`, 18,723 timestamped calls over a 39.0 h window:

| | rate | cost at load 16 | at load ~58 |
|---|---|---|---|
| mean | 480/h | **0.054 cores** | 0.108 |
| median hour | 595/h | 0.067 | 0.134 |
| p95 hour | 1332/h | 0.149 | 0.299 |

**Not ~0.9 cores.** On the 10-core box that is **0.54% of the machine at the mean and 3.0% at
p95-hour under load 58** — against a fleet target of 30 concurrent sessions. This is the finding that
governs §3: the hook layer is a real but third-order term, and an intervention's risk budget has to
be sized against 0.5–3%, not against the 9% the §1 figure implied.

### 2.5 The abstain class — where the 81% actually goes

Traced with `bash -x` on the common case (non-desk, non-teammate, not reso-management-app):

| hook | externals before it abstains | what it pays for |
|---|---|---|
| `curl-gate.py` | — | 31 ms of python3 startup to reach `if not cwd.startswith(PROJECT_ROOT): sys.exit(0)` at **:409 of 466** |
| `waiting-recycle.sh` | **17** | 4 separate `jq -r` on the *same* payload; `head -1 cc-roles/desk`+`tr` **3×**; `shasum`+`cut` **2×**; then a `jq -cn` to log that it did nothing |
| `teammate-checkpoint.sh` | **9** | `.team_name` via jq at :57, on a session that has no team |

≈ **123 ms of the 404 ms chain (30%)** is spent by hooks establishing that they do not apply — and
the majority of fleet Bash calls are exactly that common case.

Cross-cutting duplication, counted across the hot-path hooks: **12** independently `jq`-parse the
same stdin for `.session_id`, **9** for `.cwd`, **6** for `.transcript_path`. Every hook re-derives
facts every other hook in the same chain already derived, from a payload that is identical for all
of them.

---

## 3. Decision: the broker is REJECTED; the collapse is deferred

§8.5.4's named structural answer was "one long-lived per-session hook **broker** over a pipe, or as a
bounded fallback collapse the PreToolUse/Bash hooks into one process and the Stop hooks into one."

**Both target the 19% term, not the 81% term.** A broker or a collapse removes registered-hook
`fork`+`exec`s; neither, by itself, removes a single external exec *inside* a hook.

**Broker — rejected, on four grounds:**

1. **Yield vs stakes.** It addresses at most 19% of a chain measured at 0.054–0.149 cores. The
   ceiling on the whole intervention is ~0.03 cores.
2. **It does not remove the per-hook fork it is meant to remove.** Claude Code forks one process per
   *registered entry*; a broker client is still a process. Getting the saving requires the
   registration collapse **as well**, i.e. the broker is strictly additive risk on top of it.
3. **Blast radius exceeds the add-on.** Row 6's standing constraint is *"a hook failure must never
   block a tool by accident"*. A broker makes one daemon a shared dependency of 20+ hooks across 12
   events — the exact shape the `addon-failure-exceeds-its-blast-radius` rule forbids.
4. **Daemons in this repo demonstrably rot.** 9 pending activations un-run, 8 of them >24 h; 10 of 28
   launchd plists absent from the live layer (§8.5.5). A new long-lived per-session process is a new
   instance of a class this repo is already failing to keep loaded.

**Collapse-into-one-process — deferred, not rejected.** It is the honest fallback and needs no new
daemon: one registered command per (event, matcher) running each hook in a subshell preserves `exit`
semantics and saves 11 × 7 ms − ~17 ms ≈ **60 ms (15%)**. It is deferred because (a) it changes the
execution model for every hook at once, (b) the stdout-merge contract for multiple JSON emitters in
one chain is not yet pinned by any test, and (c) at 0.054 cores the yield does not yet justify that.
**Revisit if the fleet's Bash rate rises materially above the measured p95 of 1332/h**, which is the
condition under which the arithmetic changes.

**What the measurement supports instead:** attack the abstain class (§2.5). It needs no new process
model, no daemon, and no change to any hook's decisions — only to what a hook spends before
reaching a decision it was always going to reach.

---

## 4. Built and landed

### M1 — `curl-gate-scope.sh` (`89838241`)

A bash scope gate in front of `curl-gate.py`, because python is already running by the time :409 is
reachable and no edit inside the `.py` can recover its own startup.

- **Measured:** 10.72 ms vs 41.13 ms out-of-project (**−30.4 ms**), +13.5 ms in-project.
  reso-management-app is **0.32%** of 18,911 logged calls ⇒ expected value **+30.3 ms per Bash call,
  7.5% of the chain.**
- **Security posture unchanged by construction.** The shim replicates exactly **one** of the gate's
  four no-op preconditions (the `cwd` test) against raw payload bytes. `cwd` is serialized by Claude
  Code, not the user, so it cannot be `\u`-escaped; a crafted *command* can only add occurrences of
  the path, which delegates **more**. The `"curl"` substring test is deliberately **not** replicated —
  that one *is* attacker-influenced, and a raw-bytes copy of it would open the bypass the gate exists
  to close.
- **Tests:** `tests/curl-gate-scope.bats`, 14 cases. The anchor is a **poisoned-python positive
  control** — an always-delegate shim satisfies every equivalence case and buys nothing, so one case
  puts a `python3` on `PATH` that prints a marker and exits 9: the incumbent visibly breaks (proving
  the poison works), the shim must not. Mutant-proved: *always-delegate* reds case 1, *never-delegate*
  (the bypass) reds 3. A `\u`-escape anchor fails the moment someone adds the tempting substring fast
  path.
- **Wiring is C10** — `docs/activation/pending-activation/26-curl-gate-scope-activate.sh` *repoints*
  the existing entry (asserted: chain length unchanged), per-dir backup, idempotent, `--undo`,
  smoke-gated. Verified dry-run → apply → re-apply → undo against a fixture config dir; live layer
  confirmed untouched.

---

## 5. Remainders (named, with owners — none silently dropped)

| # | Remainder | Measured value | Owner |
|---|---|---|---|
| R-1 | `waiting-recycle.sh` recomputes within one invocation: 4 `jq` on one payload, the desk-role file read 3×, `key_cwd`'s `shasum`+`cut` 2×. **Memoization only — no reordering, no semantic change.** Note the constraint that makes it non-trivial: `key_cwd` is called inside `$( )` **subshells**, so a cache written there is lost; the value must be computed once in the parent before any subshell reads it. | ~48 ms of 96.55 ms | 6 |
| R-2 | `teammate-checkpoint.sh` runs on the **match-all** PostToolUse matcher and pays 9 externals to find no team. | ~32 ms | 6 |
| R-3 | `validate-bash.sh` performs **12 `grep` forks** for pattern matching bash can do natively. **Deliberately not taken here** — it is a DANGER-pattern safety gate, `grep -E` and bash `=~` differ subtly, and `denylist-enumerates-spellings-not-the-class` is a live scar on this exact file. Needs a differential corpus proving identical verdicts on every pattern before a line changes. | ~42 ms | 6 |
| R-4 | The registration collapse (§3), if the Bash rate rises above p95 1332/h. Requires first pinning the multi-emitter stdout-merge contract with a test — no such test exists today. | ~60 ms (15%) | 6 |
| R-5 | `bash-execution.log` is **9.46 MB** and unbounded (§8.5.5 flagged it at 23% over its stated cap; it has since grown). It is the *only* source for the fleet Bash rate in §2.4, so its rotation policy silently sets the decay window of every figure in this document. | — | 6 / 10 |

---

## 6. Rejected alternatives

| Rejected | Why |
|---|---|
| Long-lived per-session hook broker | §3 — four grounds; the decisive one is that it targets 19% of 0.054 cores while making one daemon a shared dependency of 20+ hooks. |
| Move `curl-gate.py`'s registration into `reso-management-app/.claude/settings.json` (architecturally the *right* home for a project-scoped hook) | Fail-**dangerous**: if the activation is skipped or that repo's settings file is absent, the gate silently stops protecting and nothing reports it. The shim keeps global registration and coverage identical, and can only ever be *more* permissive than a `python3` that failed to start — which is the posture the chain already had. |
| Rewrite `curl-gate.py` in bash | It is a 466-line security gate using `shlex` + `urllib` specifically to defeat query-string host-injection. Re-implementing that parser in bash trades 31 ms for a new bypass surface. |
| Replicate the `"curl"` substring test in the shim for a further fast path | Attacker-influenced input: `curl` in the payload evades a raw-bytes test while `json.loads` still hands the gate a curl command. Pinned RED by `tests/curl-gate-scope.bats`. |
| Treat static `$(` counts as the optimization target | §2.2 — 5× cost spread between builtin and external, and unreached branches counted at full price. |

---

## 7. Acceptance criteria

| # | Criterion | Evidence |
|---|---|---|
| AC1 | The §8.5.4 transcript claim is dated against the landed fix rather than re-fixed | §1 — `b4590d68` landed 52 min after the item was filed |
| AC2 | A cost model exists that predicts a hook's cost from its executed path | §2.3 — predicted 70 ms vs measured 70.26 ms for `validate-bash.sh` |
| AC3 | The broker decision is made on measured absolute stakes, not on a ratio | §2.4, §3 |
| AC4 | M1 lands with equivalence pinned by a control that can actually fail | poisoned-python case; mutant-proved both directions |
| AC5 | M1 changes no security verdict | 14/14 green incl. `\u`-escape anchor; byte-identical delegation asserted against the real gate as oracle |
| AC6 | Wiring respects C10 and is reversible | activation script verified dry-run/apply/re-apply/undo; live layer untouched |
| AC7 | Every unbuilt improvement is named with its measured value and owner | §5 |

---

## 8. Standing caveats

- **Every ms here is load-conditional.** Fork cost roughly doubles from load 16 to load ~58
  (`bash -c :` 7.35 ms here vs 15.5 ms measured at load 69.2 in §8.5.4). Quote figures *with* their
  load or not at all.
- **The rate in §2.4 decays with its source.** `bash-execution.log` is unbounded and unrotated
  (R-5); if it is ever rotated or truncated the 39 h window shrinks silently. Re-derive, do not quote.
- **§2.3's chain measurement invoked each hook directly**, not through Claude Code. It therefore
  measures per-hook cost faithfully but says nothing about whether Claude Code runs a chain serially
  or in parallel — which affects *latency* attribution but not the total-process-creation argument
  the decision in §3 rests on. **Unresolved, and named as unresolved.**
