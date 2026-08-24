Land claude-infrastructure's current work onto the remote trunk, safely, under a
machine-wide landing lock with **content-level** verification. This project-local
`/ship` OVERRIDES the global `/ship` **inside this repo only** — infra is the
`~/.claude` symlink source and is frequently worked on by several concurrent
sessions, so its landing flow must be fail-closed against a sibling session moving
`origin/main` mid-flight. (Global light `/ship` still applies to every other repo.)

## v2 in one paragraph (LAND_PIPELINE_V2 — read this before anything below)

**The land no longer proves the corpus.** Landing is the *fast lane*: O(diff) statics
(shellcheck / `bash -n` / py_compile on changed files, hermeticity + wall-clock ratchets)
plus a **bounded direct-suite smoke** (`SHIP_LAND_SMOKE_BUDGET_S=120`, `nice`d, **skipped
outright — never waited — under load**), then the seconds-long locked push. Typical land
≈ 20-40s; worst case ≈ 3 min, load-indifferent. ⚠ **That pair of numbers has never been
measured and the first measurement disagrees with it.** `total_s` shipped 2026-08-11 (P0);
the first land carrying it took **592s** — 506s of that inside the gate, 243s of that in the
ratchet arms, across 2 rounds — and the two attempts before it took 256s and 556s. **n=3, on
one branch, during heavy contention, and two of the three include a stale re-round**, so that
is not a replacement figure and is deliberately not written as one: it is the reason to read
`bash scripts/gate-red-census.sh` (LAND LATENCY + GATE COST, each with its coverage) instead
of either number here. Revisit this sentence once the panel clears its 8-row floor. The full-suite claim moved to **one
background verifier** (`postland-verify.sh`, every 300s, fresh worktree, background QoS)
which is now the **only** party that may assert "this tree is green": a GREEN stamp is
what advances the `gate-green` marker, and a reproducible red is **auto-reverted** with
the author notified. **Deploy** (`deploy-live.sh --auto`, every 600s) is fail-closed on
those stamps — the live `~/.claude` only ever advances to a full-suite-proven tree, then
runs the host-suite partition against it. Why: the old frame ran the corpus per land, per
session, load-gated — 43 lands/day × a 20-53 min corpus on a box whose ambient load never
drops below the gate's own ceiling. P(green) for the monolith measured **2.3%**; one branch
died 37 consecutive times and then landed first-try, 0 not-ok, when load fell. That is not
a tuning problem, so the verdict moved off the land path instead.

**What that changes for you when you run `/ship`:**
- **exit 6 = your diff is red.** A smoke suite named a failing test. It is O(your diff)
  and the highest-value seconds in the pipeline — actionable, never retry it unchanged.
- **a CUT smoke never blocks.** Load-killed or budget-overrun smoke ⇒ `smoke:"partial"`
  or `"skipped"` attested in `land.log`, and the land **proceeds**. A non-verdict is not a
  red (R6), and the verifier is the net that catches what smoke skipped.
- **exit 9 is now rare** — no corpus runs on the land path, so there is almost nothing
  left to be cut. If you see it, it is still a claim about the *machine*, not your tree.
- **green ≠ deployed.** Your land is on trunk in seconds; the live layer advances on the
  next verifier+deploy cycle. `📦 → ✅` is earned at the land; deployment is observable
  separately (below), not something to wait on.
- **…but that transition is BUDGETED, and the ledger owns the verdict — not this line.** Inside
  the converge budget the land is a `✅` carrying a converging note, which is why you never wait
  on the 600s cycle. Past it — `LIVE_LAG` > `WRAP_LIVE_BUDGET_COMMITS`, HEAD older than
  `WRAP_LIVE_BUDGET_MIN`, or a FAILED migration — `wrap-ledger.sh` computes **`🚀 Landed but NOT
  live`**, and that is the rung to emit: converge with `bash scripts/deploy-live.sh`, then re-read.
- **The budget covers an EDIT, and your land may not be one.** `~/.claude` is per-file symlinks
  into the live checkout: an edited file rides its link and runs OLD until the fast-forward, but a
  file your diff ADDS has no link and is absent from every tree the box can reach — each
  `[ -f x ] && . x` / `command -v fn` guard on it silently skips, so the feature is a no-op, not a
  stale one. `LIVE_ADDS` > 0 therefore breaches at a lag of **1**, with no budget (2026-08-09,
  backlog `99b715f31a98`). If your land adds a file, expect `🚀` and converge it.
  This repo IS the live layer's source, so it is the one repo where "landed" and "running" can
  diverge for weeks (measured: 104 commits, eight correct analyses that changed nothing). Re-read
  the ledger after the land rather than asserting `✅ Complete & live on trunk` from the push.

**Where to look when something feels stuck** — all disk truth, no narration:
```
cc-blockers                                   # VERIFIER-INERT / DEPLOY-LAG alarms + the exact fix
ls -lt ~/.claude/autonomy/postland/stamps | head   # newest verdicts (<tree>.json, "verdict":"green")
tail -20 ~/.claude/autonomy/postland/deploy.log    # the autonomous deploy lane's own log
tail -5  ~/.claude/land.log                        # your land's attested line (smoke/verify/sweep/total_s)
bash scripts/gate-red-census.sh                    # the pipeline's own census — latency, gate cost, red rate, staleness
```
An inert net is **detected, not assumed**: if the two launchd jobs were never activated,
`cc-blockers` says so and names `14-land-pipeline-v2-activate.sh` (the one operator step).

**Kill switches** (env, independently pullable — a revert would need the pipeline):
```
SHIP_LAND_LANE=v1                 # land: restore the old full-corpus gate (one release only)
POSTLAND_AUTOREVERT=off           # verifier: stamp reds, never auto-revert the culprit
POSTLAND_VERIFY=off               # verifier: abstain entirely
launchctl bootout gui/$(id -u)/com.claude.deploy-live    # deploy: stop advancing the live layer
```

Arguments: `$ARGUMENTS`
- `--dry-run` — do everything except the final push; stop and print the reconciled plan.
- `--trunk <branch>` — target branch (default: auto-detected `origin/HEAD`, else `main`).

## 1. Preflight (read-only)
- **Trunk** = `git symbolic-ref --quiet refs/remotes/origin/HEAD | sed 's@^refs/remotes/origin/@@'`, else `main` (honor `--trunk`).
- Record: current branch, whether this is a linked worktree, `git status --short`, and — after `git fetch origin <trunk>` — `git rev-list --count origin/<trunk>..HEAD` (how much is unpushed). Note the count is a *starting* reference only; it is NOT the landing proof (see step 6).

## 2. Shared-checkout guard (root fix)
- **NEVER commit or land from `~/Development/claude-infrastructure`.** It is the source of the `~/.claude` symlink and often sits on a *foreign session's* feature branch — committing there risks landing onto a branch you did not create, and a concurrent `/ship` of that branch can rebase-drop your commit.
- Resolve the real CWD (`git rev-parse --show-toplevel`). If it is `~/Development/claude-infrastructure` → **STOP**: tell the user to re-run from a dedicated worktree (`claude -w <name>`), then land from there.
- Proceed only from a dedicated worktree on your **own** branch.

## 3. Commit in-scope work
- Stage **only** the files belonging to the current task — explicit paths, **never** a blind `git add -A`. Make one atomic Conventional Commit (lowercase, no redundant verbs).
- Unrelated or foreign changes present → **STOP**, do not sweep them in. Save them (`git diff > /tmp/stash.patch`), commit only the task, restore after.
- Already clean → continue.

## 4. Land via `scripts/ship-land.sh` (the whole fail-closed pipeline, as code)
The reconcile → gate → push → content-verify → stranded-sweep flow is **no longer prose you hand-execute** — it is one fail-closed script, so a paraphrase or an early stop can never skip the content-verify that caught the 2026-07-11 incident (G-P9-2). Steps 1-3 above (preflight read, shared-checkout guard, in-scope commit) are still yours to do first; then land with:

```
scripts/ship-land.sh [--trunk <branch>] [--dry-run]
```

What it does, in order — it stops **LOUD at the first failure** with the backup ref intact:
1. **Preflight** — refuses **in code** to land from the shared checkout on a non-session branch (exit 4; the prose guard of step 2 is now also enforced), refuses a dirty tree (exit 2), then **escalation-scans** the landing range: an escalation-surface pattern **PARKS** a class-B decision packet under `~/.claude/autonomy/decisions/` and exits 3 — such changes are **never auto-landed**. The scan runs **two classes**, because they answer different questions and so cannot share a scope: the **DISCLOSURE** class (credential material, `SHIP_LAND_ESC_RE_SECRET`) asks *does this LEAK a secret* — a private key is exactly as leaked in a doc as in code, so it scans **every** changed file and is **never exemptible**; the **EFFECT** class (destructive SQL, `SHIP_LAND_ESC_RE`) asks *could auto-landing this DESTROY durable data* — only meaningful where the statement can execute, so it is **exemptible per path** by the declared `scripts/esc-exempt.manifest`. Hits are **file-attributed** (`<file>: <class>: <line>`) — the old whole-range scan printed diff-relative line numbers that named no file, so a packet could not be reviewed without re-deriving the diff. The manifest is read from the landing range's **BASE revision**, never the working tree, so an entry added *inside* a range is **inert for the land that adds it**: the exemption set can never be widened and relied on in one move, enforced by construction rather than by review (a change to it is still announced loudly, and takes effect from the next land). Being a git-object read, it is also immune to the new-file symlink deploy-lag. Why the split exists: measured over its whole life (`land.log`: 506 clean / 11 hit, 9 packets) the single-regex scan's precision was **zero** — 4 parks were a rebuildable-cache retention GC it blocked for days, 3 were docs *describing* the defect (one author respelled the SQL as prose to evade it, and it matched anyway), 1 was the classifier matching its own test corpus. An alarm that only fires on benign input carries the same zero bits as one that cannot fire, and it trains the operator to rubber-stamp the one packet class meant to stop a real destructive land. (auth/session/navigation code is escalation-worthy too, but is *not* in the default scan for this repo — its normal churn is saturated with those words; extend `SHIP_LAND_ESC_RE` for app repos.) It then runs the **P6 gate-batching backstop** (`scripts/gate-manifest.sh backstop <range>`, T-P7-7): the dual of the escalation-scan — where esc_scan *parks* out-of-class surfaces, this only **surfaces** in-class auto-ratifications (commits carrying a `Ratified-By: operator (pre-signed class Cn, …)` trailer) for **early-veto**, and is **non-blocking by contract** (never changes the exit code). Then it writes the `ship/backup-<sha>` rollback ref.
2. **Fast lane, unlocked; lock only the race window** (the 2026-07-25 invariant survives v2 intact: the gate proves the FINAL rebased tree; the LOCK covers only fetch-compare → push → content-verify). Optimistic rounds, **UNLOCKED** so concurrent landers never serialize behind each other: `git fetch` → `git rebase origin/<trunk>` (conflict ⇒ exit 5, rebase left in progress, never forced) → **fast gate**: `shellcheck` + `bash -n` + `py_compile` on changed shell/python **including extensionless python by shebang**, the **test-hermeticity ratchet** (`scripts/test-hermeticity-lint.sh`, own-scope), the wall-clock ratchet, then **bounded smoke** over the `--direct` suites only. The hermeticity ratchet runs **before** the smoke and **fail-fasts**: a suite that does not fixture `$HOME` runs against the operator's live `~/`, contaminating every other result and, once landed, redding the lint for every subsequent lander. It cannot be left to `tests/test-hermeticity-lint.bats` alone — the scoped selector never maps a new `tests/*.bats` to that suite. Two leaks landed that way in one session before this moved into the gate. **What v2 deletes here:** `bats tests/` (the corpus — the verifier owns that claim now), every load-based **wait** before a suite (smoke *skips* under load instead — R7: shedding must never pick the more expensive path), the in-lock full-gate fallback (nothing heavy may ever enter the lock; that fallback is what produced the 3h36m lock holders), and `stamp_gate_green` from the land path (a land makes no full-suite claim). Then the **locked child** (`scripts/land-lock.sh`, the machine-wide-per-repo mutex keyed on the **shared git dir** so every worktree serializes, G-P9-1) holds the lock for **seconds**: last-moment `git fetch` → CAS check — `origin/<trunk>` and `HEAD` still exactly the gated pair? A sibling landed mid-gate ⇒ release, re-rebase, re-run **statics + smoke only** (seconds, not a second corpus). On a CAS pass the gated tree IS the pushed tree → `git push origin HEAD:<trunk>`, never force `main`; a non-fast-forward rejection means a non-pipeline pusher beat you inside the window ⇒ exit 7, re-run `/ship`. Design + proof + benchmark: `docs/research/land-gate-serialization-2026-07-25.md` (v1 lock design, still current) and `docs/plans/LAND_PIPELINE_V2.md` §4.1 (what the gate now contains).
3. **Content-verify (+ bounded auto-retry + rollback, T-P9-7)** — `scripts/land-verify.sh` asserts, for **every changed path**, that it is present on the trunk **AND** `git diff` against what you shipped is empty. A bare `git rev-list --count origin/<trunk>..HEAD == 0` proves **nothing** after a sibling rebase — it read 0 in the 2026-07-11 incident while the files were absent from `main`. Content-verify is the real landing proof. On a **content-drop** the pipeline no longer strands you on manual recovery: it **auto-reconciles** (re-fetch + rebase onto the moved trunk + re-gate + re-push) up to `SHIP_LAND_VERIFY_RETRIES` times (default 2; `=0` restores single-shot). A retry rebase-**conflict** rolls back (`git rebase --abort`, never a wedged tree) ⇒ exit 5; retries **exhausted** and still not intact ⇒ clean tree + exit 8, backup ref intact.
4. **Stranded-sweep** — `scripts/stranded-sweep.sh` sweeps **every local branch** for commits whose content never reached the trunk (this is what catches a sibling's rebase-drop of *your* commit even when it landed from a branch you do not own). **Exit 1 is a REVIEW verdict, never an automatic failure and never an auto-recover**: recover ONLY your **own** just-dropped work via the printed recipe; a peer session's live feature branch (unlanded WIP — expected on a multi-session box) you **leave** — **never** cherry-pick a peer's WIP onto the trunk (the very cross-session interference this flow exists to prevent). `stranded-sweep.sh --mine <session-id>` narrows the sweep to your own drops for a decidable pass/fail.
5. **Self-attesting `land.log`** — each landing appends `{verify, sweep, esc_scan, sid}` so the audit trail can prove a given land was content-verified, plus the v2 fields `gate_scope:"fast"` and `smoke` / `smoke_n` / `smoke_s`, and the P0 self-measurement fields `total_s` · `gate_rounds` · `gate_s` · `gate_arms_s` · `gate_statics_s` · `stage`. **Every terminal exit writes a row** — exits 2/4/7/42 and the in-lock fallback's 6 wrote none until 2026-08-11, so a land could die in five ways that left the ledger reading *never attempted*. This log is the acceptance read for v2's latency target (p50 ≤ 30s, p99 ≤ 3 min, `wait_s` ≈ 0), and until `total_s` shipped **there was no duration in it at all** — the criterion named an artifact that could not answer it, for the whole life of v2. Read it with **`bash scripts/gate-red-census.sh`** (latency · gate cost · gate-red rate + causes · staleness · mutex hold, each with its own coverage), not by hand.

`--dry-run` runs everything up to and including the gate, then stops before the push and prints the reconciled plan — it never takes the landing lock (a dry run cannot queue a real land). `--trunk <branch>` overrides the auto-detected trunk.

## 5. Report
- The landing lock releases automatically (its `EXIT` trap) — no manual unlock.
- On **exit 0**, `ship-land.sh` has already emitted the landed SHA, gate result, content-verify ✓ (paths present + diff-empty), and the stranded-sweep verdict — only then is the 📦 → ✅ transition earned. On any **non-zero** exit, surface the code and its meaning (2 dirty · 3 escalation-parked · 4 shared-checkout · 5 rebase-conflict — initial *or* an auto-retry rebase rolled back · 6 gate-red · 7 non-ff · 8 verify-failed **after the bounded auto-retries** · **9 GATE-KILLED** · **75 LOCK-STARVED**) and **STOP** — each is a fail-closed state above, backup ref intact.
- **6 vs 9 — a verdict vs a non-verdict, and the difference decides what you do next.** **6** means a **smoke** suite named a failing test in *your* diff's direct scope: a claim about your code, actionable, **never** retry it unchanged. **9** means a suite was **cut** — it exited non-zero while naming **zero** failing tests (bats masks the signal behind its own `pipefail`'d pipeline, so the TAP body, not the exit code, is the honest discriminator) — and therefore proved **nothing**: a claim about the *machine*. In v2 a cut smoke **does not fail the land at all** (it attests `smoke:"partial"` and proceeds — the verifier is the net), so **9 is now rare by construction**; it survives only for the paths that still run a suite under `SHIP_LAND_LANE=v1`. Both remain fail-closed (nothing pushed, `gate-green` never advanced — that marker now moves only on a verifier GREEN stamp — backup ref intact). Collapsing the two into 6 is what let a load spike read as a code failure and drove the 2026-07-26 kill → "RED" → re-block → dispatcher-retry runaway (backlog `f8e40b4c577d` / `9c5d0ba74e79`).
- **75 — the lock was never acquired, which is a third kind of non-verdict.** `land-lock.sh` exits **75** (`EX_TEMPFAIL`) when it waited the whole `LAND_LOCK_WAIT` (default 3600s) without getting the mutex. Like **9** this is a claim about the *machine*, not your tree — the gate may well have run **GREEN** and nothing was ever pushed — so re-running **is** correct. In v1 this was common: the lock is a `mkdir` race with no FIFO fairness, and holders held it for the length of a *corpus* (3h36m observed) whenever the in-lock fallback fired. **v2 removes the cause rather than the symptom** — the hold is now fetch → push → content-verify, **p50 3s / p90 5s** across the 110 completed holds since `145fab7d` (2026-08-11T01:32Z) moved the sweep and the reap out of the mutex, with **p50 0s wait**; the p99 is **139s** and that tail is real (it is the in-lock fallback lane, which re-gates statics + ratchets under the mutex when the optimistic rounds are exhausted). *This figure replaced "84-302s across 230 successful lands", which was measured before P1 and had been false for a day; it has a half-life, so re-derive it with `bash scripts/gate-red-census.sh` rather than quoting this sentence.* So a 75 in v2 means something is genuinely wedged (a dead holder's stale lock, a hung fork). Read `cc-blockers` and the holder's pid before re-running; `land-lock.sh` reaps a dead holder by pid+lstart, so restarting the wedged session self-clears it. **Never** set `LAND_SERIALIZE=off`.
- **Never free a stuck gate with a bare `pkill`.** Every bats command line on this box contains `/libexec/bats-core/bats`, so `pkill -f bats…` SIGKILLs **every concurrent session's** landing gate machine-wide — the measured root cause of the false-RED epidemic (`a0718a5d78b3`). Use **`scripts/gate-cleanup.sh --dry-run`** to see the selection, then the same without `--dry-run`: it signals only processes whose cwd is inside **this** worktree, plus their descendants. `hooks/validate-bash.sh` denies the unscoped form outright.
- **Load shedding is SKIP, never WAIT — nothing in the pipeline waits on load.** The land's smoke is **skipped outright** when 1-min loadavg is at or above `CC_GATE_MAX_LOAD` and the land proceeds with `smoke:"skipped"` attested; `CC_GATE_MAX_LOAD=0` never sheds. **The default ceiling is DERIVED from the box** — `hw.ncpu × CC_GATE_MAX_LOAD_PER_CORE` (factor 8, so 80 on a 10-core Mac) — not the constant `8` it was until 2026-08-08. That constant was inherited from the v1 gate, where the predicate guarded a 20–53 min 126-suite corpus; v2 put a ≤120s bounded smoke behind it and kept the number, leaving a ceiling of 0.8/core on a box whose own capacity work (`MACHINE_CAPACITY_V2` §8.5.7) measured it *surviving* 2.92–5.98/core in ordinary operation. Measured effect: **352 of 405 lands that reached the check were shed (87%)** — "landed green" meant "statically green only" for ~7 lands in 8. At the measured band the new default is effectively load-insensitive by design; what remains is a **runaway circuit-breaker, not a capacity model**. A shed land now says so out loud (`behaviorally UNGATED`, with the load and ceiling printed), because the post-land verifier is a backstop that trails trunk by hours, not a proof completed at land time. An **explicit** `CC_GATE_MAX_LOAD` is still an absolute ceiling, so existing callers are unaffected. The smoke's own ceiling is `SHIP_LAND_SMOKE_BUDGET_S` (default 120s, one TOTAL budget across all direct suites): on overrun the process group is killed, the remaining suites are skipped, and the land proceeds with `smoke:"partial"`. The verifier likewise never waits — it runs in the Darwin **background QoS band** (`nice -n 19` + `taskpolicy -c background`), where its wall time under load is deploy *latency*, never blockage. **Why shed-by-skip and not shed-by-wait:** a degradation path must never pick the more expensive action (R7). Waiting starved lands *and* amplified the load it was shedding — the waiters were the load, since each waiting gate's own suite was what the others were waiting to drop below.
- **Lane selector and what `land.log` attests.** `SHIP_LAND_LANE` selects the lane: **`fast`** (default — statics + ratchets + bounded smoke) or **`v1`** (the old full-corpus gate, kept for one release as the kill switch). Every land appends `gate_scope` (the lane that actually ran), `smoke`, `smoke_n` (suites run), `smoke_s` (seconds), and `net` — read these, don't infer them. **`smoke` names its CAUSE, not just its class:** `green|red|partial|skipped` as before, plus `none-unreached` (a fail-fast ratchet arm went red before the smoke phase), `none-nosuites`, `none-locked` (the in-lock fallback lane — bats is structurally banned under the mutex), `none-noselector`, `none-undecided` (the selector's fail-closed *cannot decide*), `none-nodirect` (a lint-only land). Until 2026-08-11 those were one token `none` across **83% of lands**, which pooled a deliberate cheap path with an instrument outage and made the pipeline's largest coverage fact unbreakdownable. A bare `none` in the store is a pre-split row: an absence of attribution, never a seventh cause.
- **Never raw-ff the shared checkout.** `git pull --ff-only` / `git merge --ff-only` in `~/Development/claude-infrastructure` advances the *files* but creates **no symlinks**, and `~/.claude/{hooks,commands,scripts,bin,skills}` are real directories of **per-file** symlinks — so a brand-new tracked file lands unlinked and silently does nothing (`hooks/lib/cc-interactive.sh` shipped that way and disabled an operator hold; `skills/video-understanding` was live-missing for a day). **`deploy-live.sh` is the only sanctioned advance** — the launchd job runs it `--auto`, a session runs it by hand, and `--force` is its escape hatch; all three reach the same green-stamp-gated, `install.sh`-running merge, which is what actually creates the links. `scripts/deploy-parity-assert.sh` is the check that catches a bare-ff deploy after the fact — its provenance leg discriminates on ref-vs-SHA in the reflog, so a raw ff scores `UNGATED` **until the next advance overwrites it**, not permanently: the leg reads `git log -g -1` (`deploy-parity-assert.sh:885`), i.e. the NEWEST reflog entry only, so the very next sanctioned SHA ff erases the finding rather than preserving it. ⚠️ **And `deploy.log` is not an attribution instrument.** It is the launchd job's `StandardOutPath` and `deploy-live.sh` has no log wiring of its own (`say()` at `:304` prints to stdout), so it records `--auto` runs and nothing else. A resolved-SHA ff with no `deployed` line in `deploy.log` is therefore a MANUAL `deploy-live` run — 28 of 71 measured 2026-08-24 — and is **not** evidence of a foreign actor; backlog `7e2e0ab9c358` was filed on exactly that inference and closed refuted. **The operator entrypoint is not a second path**: `bash ~/.claude/DEPLOY-NOW.sh` (`scripts/deploy-now.sh`) raw-ff'd the checkout itself until 2026-08-10 and is now a thin front-end that `exec`s `deploy-live.sh` with every flag passed through, so the escape hatch is `bash ~/.claude/DEPLOY-NOW.sh --force` and there is no un-gated spelling left on trunk.

## Why locked + content-verified
On 2026-07-11 a concurrent land in claude-infrastructure silently dropped commit
`dfacccd` (the limit-recover skill — 5 new files) from `main`: a sibling session's
rebase-land of `feat/two-way-session-comms` moved `origin/main` between this
session's rebase and push, and the post-land check used only
`git rev-list origin/main..HEAD`, which read **0** — so the land "looked" complete
while the files never reached trunk. The lock closes the rebase→push race; the
last-moment re-fetch lets mid-flight sibling commits ride along instead of being
clobbered; the **content-verify** and **stranded-sweep** catch what a count check
structurally cannot. All four are now enforced in code inside `scripts/ship-land.sh`
(step 4) rather than left to prose — a model can no longer skip the check that caught
this incident.
