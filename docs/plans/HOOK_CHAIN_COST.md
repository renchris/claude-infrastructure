---
status: complete
---

# Hook-chain cost — the durable record

**Owner:** row 6 (guardrail/hook layer). **Origin:** backlog `2193948bb00e`, handed over from row 13
in plan prose only (`MACHINE_CAPACITY_V2.md` §8.5.4) — this file is the durable record that item
asked for.

**Scope (frozen):** drive `2193948bb00e` to finished-verified-landed — establish what the hook chain
actually costs, decide broker-vs-collapse on measured grounds, and land what the measurement
supports.

**CLOSED 2026-08-09.** All of AC1–AC9 met: the cost is established (§2), the broker is rejected and
the collapse deferred on measured grounds (§3), and everything the measurement supported is built
and landed — the abstain class of §2.5 is now closed on **all three** hooks it named (M1, M2, M3).

*Why the status flipped to `complete` rather than staying open with a remainders table.* This file
being open is what mints the recurring "advance Hook-chain cost" dispatch item (`cc-discover` C2 →
`find-plan.sh --list-open`, gated by `cc-premise`), so an open plan whose scope is discharged
re-dispatches workers against work that no longer exists — and this item had already logged three
fast claim→reopen thrash cycles. The surviving remainders were therefore moved to the **enforcing**
store first, so closing this file drops nothing:

| Remainder | Backlog id |
|---|---|
| ~~R-3~~ — **ADJUDICATED 2026-08-17: the corpus exists and its answer is no.** See §5. | `8942f3b1506d` |
| R-5 — `bash-execution.log` unbounded, and it is the decay window of every rate here | `9a25cbc24799` |
| R-7 — no all-tool-call census, so no match-all hook's cost can be stated per-hour | `f6cc5c79885b` |

R-6 is deliberately **not** filed: it is a reconcile-at-point-of-use note and already lives in
`config/hook-chains.d/pretooluse-bash` itself, where the person wiring the dispatcher will read it.
A backlog row would be a second copy that can rot away from the first.

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

`bash -c :` costs 0.29 ms more than `/usr/bin/true`. **Bash's own startup is ~0.3 ms; the rest is
`fork`+`exec` itself.** So the only metric that matters is *total process creations per event* — and
`python3` is worth ~4 bash forks.

> ⚠ **These absolutes are ~2× inflated and the correction is `5c88633f`'s, not this row's.** Timing a
> child *from a wrapper* bills the wrapper's own fork too; the marginal cost of an extra exec of a
> page-cached binary is **~2–4 ms**, not ~7 ms. Every figure in this subsection was taken with
> `subprocess.run(["bash", …])` from python and carries that bias. Use the **ratios** (python3 ≈ 4×
> bash; external `$()` ≈ 5× builtin `$()`) and the **interleaved deltas** in §4 — those are
> bias-cancelling — and do **not** quote the absolute floor. See §3.

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
validated, and it says the registered-hook count is the *minority* term: **11 × 7 ms = 77 ms = 19% of
the chain; the other 81% is inside the hooks.** Corrected for the wrapper bias above, the registered
term is nearer **11 × ~3 ms ≈ 33 ms (~8%)** and the share inside the hooks rises to ~92% — the
direction of the conclusion is unchanged and its margin is larger. `5c88633f` measured the collapse
directly and found it does not pay, which is the same answer arrived at by measurement rather than
by this model.

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

**Collapse-into-one-process — ALREADY BUILT AND MEASURED NEGATIVE, by a sibling session, `5c88633f`
(2026-07-31), landed INERT.** `hooks/hook-chain.sh` (331 lines) + `config/hook-chains.d/` +
`tests/hook-chain.bats` + `tests/hook-chain-live-parity.bats`. Its measurement:

| | serial | dispatcher |
|---|---|---|
| real 6-guard PreToolUse/Bash chain | 174 ms | ~180 ms |
| 6 **no-op** members | 60 ms | 41 ms |

It wins only on trivial members, and `validate-bash.sh` — the chain's biggest member — gets **worse**
under sourcing (94 → 142 ms). So the dispatcher is deliberately not wired: default mode `exec`,
process model unchanged, landed so the next session does not rebuild it.

**That session's methodology critique lands on this document, and it is right.** It found that timing
`bash -c 'exit 0'` *from a wrapper* bills the wrapper's own fork, so the marginal cost of an extra
exec of a page-cached binary is **~2–4 ms, not the ~7 ms** §2.1 measures — §2.1 used
`subprocess.run(["bash", …])` from python and carries the same bias. **Two consequences, stated
separately because they differ:**

- **The absolute fork-floor attribution in §2.1 and §2.3 is inflated ~2×.** The registered-hook term
  is nearer 11 × ~3 ms ≈ 33 ms (**~8%**) than 77 ms (19%). This does not weaken the §3 conclusion —
  **it strengthens it**: the collapse targets an even smaller share than this document first claimed,
  which is exactly what `5c88633f` then measured directly.
- **Every *delta* in this document is unaffected**, because each was measured as an interleaved A/B
  under one method, so a constant wrapper bias cancels: M1's −30.4 ms and M2's −32.6 ms stand. The
  per-site figures in §2.2 are also unaffected — they are deltas measured *inside* a single `bash -c`
  loop, with no wrapper fork per site.

**Both sessions independently reached the same verdict from opposite directions** — that one is worth
recording. `5c88633f` built the collapse and measured it not to pay; this row measured the cost
distribution and predicted it would not pay, because the collapse addresses the minority term. It
also independently flagged the same `curl-gate.py` waste (its live-parity suite calls it "a 46 ms
no-op that can never decide anything"), documented it, and left it — M1 is that fix.

**Remaining condition for revisiting:** `5c88633f`'s finding 3 is the sharp one — load swung
10.6→24.0 *during* its runs at constant session count, so every delta sat inside the noise. The win
scales with cost-per-fork, which is O(load), **so a collapse pays only in the regime it exists to
prevent and cannot be validated at normal load.** Any future attempt must therefore be measured under
*sustained, controlled* high load, not at the ambient load either of us had.

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

### M2 — per-invocation memo in `waiting-recycle.sh`

The chain's single most expensive hook recomputed the same values within one invocation: 4 `jq` on
one payload, the desk-role file read **3×**, `key_cwd`'s `shasum`+`cut` **2×**.

- **The constraint that makes it non-obvious:** every caller reaches these through a command
  substitution (`[ -f "$(arm_for "$CWD")" ]` → `sentinel_for` → `key_cwd`), and a `$( )` runs in a
  **subshell**, so anything it assigns dies at the closing paren. A self-populating memo could never
  hit. The values depend only on `$CFG`/`$DESK_ROLE`/`$CWD` — all known before the first substitution
  — so the parent fills the memo once and the functions only ever *read* it. Unset memo ⇒ compute
  exactly as before, so the CLI modes and the bats suite are byte-identical.
- **`CMD` is now lazy**, extracted at its one use site: the abstain paths that precede it never read
  it, so the incumbent paid a `jq` fork for a value it discarded.
- **The role key is precomputed only for an actual role-holder** — a builder never calls `key_role`,
  so precomputing it unconditionally would have added a `shasum`+`cut` to the common path to serve a
  branch it never takes. (First draft did exactly that; caught by re-tracing rather than by a test.)
- **Measured, interleaved A/B at load 14** (same payload, alternating arms so drift hits both
  equally): **100.08 ms → 67.46 ms median (−32.6%)**, p95 139.10 → 96.89 ms, **20 → 13 external
  execs**, stdout byte-identical on the abstain path.
- **Verification:** `waiting-recycle.bats` 106/0 and `waiting-recycle-bounded-read.bats` 12/0,
  identical before and after. Because identical-before-and-after means those suites cannot
  *distinguish* a correct memo, two things were done rather than assumed: (a) the lazy-`CMD` move was
  **mutation-proved** against the existing suite — forcing `CMD` empty reds *"guard: a handoff-fire
  --recycle command does not trigger a fresh advisory"*; (b) `tests/waiting-recycle-memo.bats` (5
  cases) pins what nothing covered, with case 5 keying an arm marker on a hash the test computes
  independently, so memo-vs-uncached drift of one byte is visible.
- **A claim this section does NOT make:** the set-but-empty role-value distinction is a *performance*
  choice, not a correctness one. Mutating the existence guard into a truthiness guard reds **zero**
  cases, because the truthiness form falls through to a re-read yielding the same empty value. The
  suite header says so explicitly, so no future reader infers a contract no test enforces.

### M3 — the abstain path of `teammate-checkpoint.sh` (closes R-2)

The last hot-path hook in §2.5, and the one with the widest blast radius: it is registered on the
**match-all** PostToolUse matcher (`"matcher": ""`), so unlike M1 and M2 — both scoped to `Bash` —
its abstain path runs on **every tool call of every session**. §2.5's "9 externals to find no team"
was re-measured today and is exactly right: `cat`, **5 × `jq` over one payload**, `git rev-parse
--git-common-dir`, the GC damper's `find`, and `cat` of the counter.

Four changes, each "spend less before a decision you were always going to reach":

- **One `jq` instead of five.** The three fields the abstain path needs come from a single `jq`,
  newline-separated. `.team_name` / `.teammate_name` are now **lazy** — read at their only use site
  on the snapshot path (M2's lazy-`CMD` pattern), so an abstaining call never pays for them.
- **`read` instead of `cat`**, twice: the stdin slurp (`read -r -d ''`) and the per-session counter
  (`read < file`). Both are builtin redirects; both replaced a subshell *and* an exec.
- **The abstain gate now precedes the GC block.** The GC is damped to once/day, but its damper is a
  `find` — an exec — and it sat *in front of* the gate, so 4 of every 5 calls paid it only to be
  turned away immediately after. The sweep is not rationed by the move: Stop always passes the gate
  and fires at the end of every turn. The block itself moved **byte-identical** (asserted
  programmatically, not by eye).
- **The counter is validated numerically.** Not cosmetic: `read` of a corrupt counter (`not-a-number`
  from a half-written file) reaches `$(( COUNT + 1 ))`, which under `set -u` is a *fatal* unbound-
  variable error that kills the hook before it can checkpoint. Measured, not assumed — an empty file
  and `007` are both harmless, so the fixture had to be the one that actually errors.

**Measured — 9 → 2 external execs** on the steady-state abstain path (per-binary counting shims),
and **−27.75 ms median (−37.5%)**, p95 82.05 → 56.33 ms (−25.73), n=30 **interleaved** A/B at load
16.9→16.5. Interleaving is not decoration: §3 records that load swung 10.6→24.0 *during* a sibling's
block-sequential runs and buried its deltas in noise.

**The alignment guard is what makes the batched parse safe rather than merely fast.** Splitting one
`jq`'s output on newlines assumes no field contains a newline — always true of a session uuid and an
event name, but a *directory* may hold one. So `jq` emits a trailing sentinel; if it does not arrive
intact, the hook re-reads per field. Without it the failure is silent and fail-**quiet**: `CWD` takes
only the first line, `git rev-parse` rejects it, and the hook abstains — a session in such a
directory loses its crash-recovery net with nothing logged. `tests/teammate-checkpoint-parse.bats`
pins it with a real newline-in-path repo, with the newline in a *parent* component because git will
not accept a ref name containing one.

**Verification:** 11 new cases; `teammate-checkpoint-gc.bats` 13/0, `teammate-auto-shutdown.bats`
50/0, `store-bounds.bats` 23/0, `rotate-autonomy-logs.bats` 14/0 — all unchanged. **Five mutants,
one per site, all killed:** deleting the sentinel guard, re-eagering the payload fields, restoring
the per-field `jq` fan-out, moving the GC back in front of the gate, and dropping the counter's
numeric guard each red their named case.

**A harness defect recorded because it nearly shipped a false verdict.** The first mutation pass
reported three mutants SURVIVED. They had not — `bats` here is the `cc-bats` wrapper, which
**refuses to start** above a concurrency/load ceiling and exits *without emitting TAP*, saying in
its own words: "nothing ran, nothing was verified — this is a DEFERRAL, not a test result".
Counting `not ok` lines then yields zero, byte-indistinguishable from a clean pass. The harness now
requires the `1..N` plan line **and** N result lines before it will call anything a verdict, plus a
green baseline before spending any mutant; with that control all three were killed. Any harness in
this repo that shells out to `bats` needs the same positive control — this failure reads as success.

**Claims this section does NOT make.** (a) The **fleet** value is larger than M1's and M2's because
the matcher is match-all rather than `Bash` — but *how much* larger is **unmeasured**, and is not
inferable from §2.4: that rate comes from `bash-execution.log`, which logs only Bash. Filed as R-7.
The per-call delta above is measured; the per-hour one is not. **Narrowed 2026-08-19 (§5.2): the
all/Bash ratio is 1.40x on the 49% of sessions that keep a transcript, so the direction is now a
magnitude on a named stratum — but the fleet figure is still unmeasured, because the other 51% of
sessions leave no transcript to count.** (b) `basename` on the snapshot path
is still a fork, left alone deliberately — it feeds the member-name derivation that recovery refs
are keyed on, and ~3 ms on 1-in-5 calls does not buy perturbing it.

---

## 5. Remainders (named, with owners — none silently dropped)

| # | Remainder | Measured value | Owner |
|---|---|---|---|
| ~~R-1~~ | **DONE — see M2 below.** | — | — |
| ~~R-2~~ | **DONE — see M3 above.** Re-measured before it was touched: the 9 externals were exactly as filed. 9 → 2, −27.75 ms median. | ~~~32 ms~~ → **−27.75 ms measured** | — |
| ~~R-3~~ | **ADJUDICATED 2026-08-17 — the corpus was built and it RETIRES the remedy. See §5.1.** The original text is kept verbatim below because its reasoning was right and its numbers were not: *"`validate-bash.sh` performs **12 `grep` forks** for pattern matching bash can do natively. Deliberately not taken here — it is a DANGER-pattern safety gate, `grep -E` and bash `=~` differ subtly, and `denylist-enumerates-spellings-not-the-class` is a live scar on this exact file. Needs a differential corpus proving identical verdicts on every pattern before a line changes."* | ~~~42 ms~~ → **36.7 ms measured, of which ~2.6 ms is convertible** | — |
| ~~R-4~~ | **Superseded before it was filed** — the collapse is built and measured negative in `5c88633f`, landed inert. Not a remainder; see §3. Any revival must be measured under *sustained controlled* high load, since the win is O(load) and vanishes into noise at ambient. | — | — |
| R-6 | **Registry/settings coupling introduced by M1.** `config/hook-chains.d/pretooluse-bash` names `curl-gate.py` because that is what settings.json registers today. If the operator runs `26-curl-gate-scope-activate.sh`, settings.json will name `curl-gate-scope.sh` and the two sets diverge. **No runtime effect while the dispatcher is inert** (it cannot run), and `tests/hook-chain-live-parity.bats`'s drift guard compares the registry against a test-internal `MEMBERS` array rather than live settings, so nothing reds either. But whoever wires the dispatcher must reconcile them — a note to that effect is in the registry file itself, at the point of use. | — | 6 |
| R-7 | **No census of ALL-tool calls exists**, only of Bash. §2.4's fleet rate comes from `bash-execution.log`, so every per-hour figure in this document is scoped to `matcher: "Bash"` hooks. M3's subject runs on the **match-all** matcher, i.e. on a strictly larger population that nothing measures — so M3's fleet value is known only in direction, not magnitude, and the same blind spot covers `cc-permission-beacon.sh` and `mailbox-drain.sh`, which are also registered match-all. Needs a tool-call counter before any match-all hook's cost can be stated per-hour. **PARTIALLY MEASURED 2026-08-19 — see §5.2. The all/Bash ratio is 1.40x on the transcript-bearing stratum, and the obvious shortcut (count `tool_use` records in the transcripts) is REFUTED as a fleet denominator: 51% of sessions carry no transcript at all. R-7 stays OPEN — the counter is still needed for a fleet figure.** | **1.40x on 49% of sessions; fleet still unmeasured** | 6 |
| R-5 | `bash-execution.log` is **9.46 MB** and unbounded (§8.5.5 flagged it at 23% over its stated cap; it has since grown). It is the *only* source for the fleet Bash rate in §2.4, so its rotation policy silently sets the decay window of every figure in this document. | — | 6 / 10 |

---

### 5.1 R-3 adjudicated — the corpus was built, and it says no (2026-08-17)

R-3 blocked itself on its own terms: *"a differential corpus proving identical verdicts on every
DANGER pattern first."* The corpus is the deliverable, and the optimization was only ever whatever
the corpus authorized. It now exists — `scripts/validate-bash-differential.sh`,
`tests/validate-bash-differential.bats`, 31 site rows × 66 corpus cases = **1,672 scored pairs, 56
diverging** — and it authorizes almost nothing. Full report:
`docs/research/validate-bash-grep-differential-2026-08-17.md`.

**10 of 30 sites are safe to convert; 20 are not. On the modal path — the only path where the forks
are actually spent — exactly 1 of the 10 always-executed greps is convertible.** The remedy's real
prize is therefore **~2.6 ms, not 42 ms**, against a danger-pattern gate with a live scar on this
exact file. It is not worth taking, and that is now a measurement rather than a caution.

**The dominant cause is not subtlety, it is a silent semantic inversion.** `\b` is a word boundary
in the BSD grep the hook resolves and a **literal `b`** in bash's `=~`, whose `regcomp` has no `\b`
and drops the backslash — 13 of the sites carry one. Both directions were measured, with a control:

```
pattern '\bconfig\b'   input 'git config --get x'    grep=MATCH   bash=no       ← guard goes SILENT
pattern '\bconfig\b'   input 'git bconfigb --get x'  grep=no      bash=MATCH    ← guard FIRES on noise
pattern 'config'       input 'git config --get x'    grep=MATCH   bash=MATCH    (control: agrees)
```

The second cause is anchoring: `grep` anchors `^`/`$` **per line**, bash `=~` over the **whole
string**, and `$CMD` is routinely multi-line here — which is exactly why `61826e193` (heredoc bodies
are stdin, not argv) had to exist. A converted `^`-anchored pattern stops seeing line 2 onward.

**The census corrected the premise in both directions at once**
(`docs/research/validate-bash-fork-census-2026-08-17.md`, load bands matched to §2's, so the
comparison is legitimate):

| | R-3 filed | measured 2026-08-17 | direction |
|---|---|---|---|
| `grep` forks, modal path | 12 | **14** | count decayed **upward** |
| ms attributed to them | ~42 | **36.7** | value decayed **downward** |
| forks inside `validate-bash.sh` itself | 12 | **10** | 4 live in `hooks/lib/is-true-flag.sh:41`, which R-3 never names |

The two errors partly cancel, which is why the headline scalar still looked about right. **The
durable unit is the exec count, not the millisecond** — counts were byte-identical across three
independent runs while the wall clock moved with load inside ten minutes.

**Three things larger than R-3 that R-3 does not contain**, all newly measured:
`grep` is **51%** of the modal path, not the whole story (24 externals, 14 of them grep) ·
one `python3` exec costs **24.45 ms**, 9.3× a `grep`, and is the single most expensive fork in the
file (off the modal path — the layer-1 grep short-circuit is the fix, and it works) ·
the hook parses the **same stdin payload three times** with three `jq` execs (lines 46, 185, 1008),
the same defect §2's audit named in `waiting-recycle.sh` and left unfixed here.

**Taken this land:** the audit logger's own two forks (`7aefce5d6`) — `mkdir -p` recreating a
directory that already exists, and a `date` duplicating a stamp the `jq` beside it can emit. It
changes no danger pattern (it runs after every decision is made) and measures **+2.28 ms median
paired, faster in 96/120 pairs** at load 11.0–14.3. **Not taken:** the remaining 2-of-3 `jq` parses,
because that IS the gate's input path and its fail-open guard is the thing that must not be
perturbed for ~7 ms — filed rather than done.

**Method note, because the first measurement said the opposite.** A blocked A-then-B at n=41 read
67.36 ms vs 67.59 ms — no saving, nominally slower — and would have been reported as a refutation.
An interleaved paired design at n=120 resolves the same change at +2.28 ms with 80% paired wins.
Load drifts over minutes; a blocked design charges that drift to whichever variant ran second. **At
this effect size the experimental design, not the sample size, is what decides whether the effect is
visible at all.**

---

### 5.2 R-7 partially measured — the shortcut is refuted, and the ratio has a stratum (2026-08-19)

R-7 says a tool-call counter is needed. The obvious objection is that one already exists: every
`tool_use` block in `~/.claude/projects/**/*.jsonl` is a tool call, un-consumed. **Measured, that
objection is wrong, and the way it is wrong is this document's own R-7 defect a second time.**

**The window is the whole method.** A Bash-only numerator over one span and an all-tool denominator
over another is exactly the span mismatch R-7 names, so both counts are bounded to
`bash-execution.log`'s own span — `2026-08-16T22:22:09Z` → now, which is all the log retains (R-5:
it is unbounded but rotates, so this span is the measurement's decay window too).

| | in-window |
|---|---|
| `bash-execution.log` entry-starts | **20,071** |
| distinct session ids in that log | **214** |
| …of which have a transcript in EITHER root | **104** (9,069 Bash entries) |
| …of which have NO transcript at all | **110** (11,000 Bash entries — **55% of Bash volume**) |
| `tool_use` blocks in transcripts, deduped on tool_use id | **13,388** — Bash 9,566, Read 2,215, Edit 657, Write 342 |
| **all / Bash, transcript-bearing stratum** | **1.40x** |

**Cross-validation:** the transcript census's 9,566 Bash calls closely matches the 9,069 the log
attributes to transcript-bearing sessions. Two independent instruments agree on the stratum they
share, which is what makes the 1.40x usable at all.

**What this licenses, and what it does not.** A match-all hook's per-hour cost is the Bash rate
× 1.40 **on the 49% of sessions that keep a transcript**. It does NOT give a fleet figure: the
missing 51% is not sampling noise, it is a structurally absent population, and nothing in the
transcripts can say whether its tool mix resembles the stratum that is visible. So R-7 stays OPEN
with its remainder narrowed rather than closed — the counter it asks for is still the only thing
that would produce a fleet number (memory `zero-claim-must-name-its-excluded-strata`).

**Three instrument defects were found and fixed inside this measurement**, each the failure mode
this document keeps re-encountering, and each invisible in its output:
- The first census globbed `~/.claude/projects/*/*.jsonl` and saw **899 of 1,817** files, and it
  missed the **second transcript root entirely** (`~/.claude-secondary/projects`, 1,725 files). It
  reported a confident 1.84x over roughly a quarter of the corpus.
- A hand-typed epoch in the file-level prefilter was **a year off** (Aug 2025, not Aug 2026), so the
  prefilter excluded nothing and said so nowhere. It is now derived from the window string itself.
- The have/without split was first taken with `find … | grep -q .`, which under `pipefail` fails on
  the very input it matched (memory `grep-q-under-pipefail-inverts-the-verdict`), and the follow-up
  tally used `for u in $misslist` **under zsh, which does not word-split** — together they produced
  "110 sessions with 0 entries", an arithmetic impossibility that is what exposed both. The final
  figures carry a conservation check against the log total (20,069 vs 20,071, the log being live).

Reproduce: the census script is not landed — it is a one-shot whose only durable output is this
table, and a scanner over 3,500 transcript files is not something to leave rotting in the tree.
Its method is fully specified above; the two sources are `~/.claude/logs/bash-execution.log` and
both `projects/` roots.

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
| AC8 | The abstain class §2.5 identified is closed on all three hooks it named, each re-measured before being touched rather than trusted from the filing | M1 (`curl-gate.py`), M2 (`waiting-recycle.sh`), M3 (`teammate-checkpoint.sh` — 9 externals re-measured as filed, then 9 → 2) |
| AC9 | No fast path is asserted by a test that cannot fail on its absence | M3's 5 mutants, one per site, all killed — over a baseline proved green first, through a harness that now proves the suite RAN (§M3, the `cc-bats` deferral) |

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
