# cluster-C memory + hooks + comms — triage vs origin/main @ 51bdb524

Measured 2026-08-09. Trunk tip `51bdb524` ("test(it2-kitty-operator-safety)…", 2026-08-09 16:51 -0700).
All verification was git reads / file reads / grep. No suite was run, nothing was mutated.

## Summary

counts: PRUNE 5 / UPDATE 5 / KEEP 8 / MERGE 1   (= 19, slice size 19)

Three headline results, each of which changes what the lead should do:

1. **Three of the four blocked "operator must decide which lever" memory items are dead, and they
   died by measurement, not by decision.** They were filed at 128–132 index entries, where the
   arithmetic genuinely said no shortening pass could reach the limit. Today the index holds **105**
   entries at **165 B/hook**; a pass to the skill's own 115 B target lands at **21,061 B** against a
   24,985 B limit — **3.9 KB of slack**. The question that made them class-C operator decisions no
   longer has two sides.
2. **The remedy those items prescribed is already built, and better placed than they asked for.**
   They asked for an append-time byte budget inside `hooks/memory-nudge.sh`. `16dfe3b5` moved it to
   the PreToolUse chokepoint instead (`hooks/backup-before-write.sh` + `hooks/lib/memory-index-budget.sh`,
   269-line test suite), because a budget measured at UserPromptSubmit bound nothing across 12
   compactions. Verified live: both files are symlinked into `~/.claude/hooks/`.
3. **The lead's deploy-parity hypothesis is refuted for `hooks/`.** I swept all 90 files in
   `hooks/` + `hooks/lib/` against `~/.claude/`: **90 symlinked, 0 missing, 0 diverged.** No new
   file is unlinked. The real inertness surface is one layer up — `settings.json` — where four
   built, symlinked, tested hooks are registered **zero** times.

## Verdicts

> **Completeness check — count verdict ROWS, not substring occurrences.** Each row matches
> `^\`<id>\` \| \*\*<VERDICT>\*\*` and there are exactly 19. A naive `grep -c <id>` will over-count
> two ids for legitimate reasons: `150c50055e1c` is also named as the MERGE target (the contract
> requires naming the canonical id), and `02ba4e52389a` also appears inside the branch name
> `wt-02ba4e52389a`, which is its own evidence.

### cluster-C-memory (10)

`150c50055e1c` | **KEEP** | **Canonical for the index.** Re-measured today and its model is exactly right, only its size moved. It said 101 hooks @167 B vs a 115 B target, ~5,252 B recoverable, hook length is the binding lever. Today: 105 hooks @**165 B**, **5,250 B** recoverable, floor **21,061 B**. Size 25,489 → **26,382 B** (over by **1,397**, not 504). Loader limit 24,985 confirmed as `MEMORY_INDEX_LIMIT` default at `hooks/memory-nudge.sh:87`.

`e27d37eac4cd` | **MERGE** → `150c50055e1c` | Same subject, same measurement (26,415 B filed vs 26,382 B today), and it is precisely the operator-approval half of 150c5's remedy: "approve the lossy half of /compact-memory". It is not a separate item, it is 150c5's gate.

`7e2df754d0b8` | **UPDATE** | Two halves, opposite fates. The **append-time budget half is LANDED** — `fc3cfed9` built it, `16dfe3b5` relocated it to the PreToolUse chokepoint (`hooks/lib/memory-index-budget.sh`, symlinked live), and `tests/memory-index-budget.bats` gates it. The **compaction half is still live** (26,382 > 24,985). Its stated size (23.8 KB / 125 entries) is stale. Should now read: run the shortening pass only; the append-time lever is done, do not rebuild it in `memory-nudge.sh`.

`6267e2e3c707` | **UPDATE** | Premise holds (index still over), **remedy analysis refuted**. It says "102 entries × 257 B avg; hitting the 17.1 KB target needs ~167 B/entry, i.e. a restructure of an accumulating-context file — CLAUDE.md requires approval before restructuring." Three errors today: the target is **24,985 B, not 17.1 KB**; entries are **245 B/line at 165 B/hook**, so the 115 B target is a *shortening*, not a restructure; and the two-tier hot/cold split it offers as option (b) is unnecessary. Downgrade from class-C decision to mechanical pass.

`eec945d6e2ec` | **UPDATE** | **Its warning is confirmed, and it convicts its own body.** It cautioned "the hook's KB figure and `wc -c` disagree by ~1 KB, re-derive the true limit before cutting". Directly observed this session: the harness-injected reminder reads "MEMORY.md is 24.8KB (limit: 24.4KB)" while `wc -c` reads **26,382 B**. But the item's own "<17.1 KB" target is itself the stale derived figure it warns about — the real limit is 24,985 B, and a 6.4 KB cut is ~5 KB more than needed. Should now read: caution retained, target corrected to 24,985 B, cut sized at ~1.4 KB minimum / ~5.2 KB available.

`7021e89884df` | **PRUNE** | Every load-bearing fact refuted. Filed at "27,810 B / 132 entries; the per-hook budget to reach 17.1 KB is 52 B, BELOW the skill's own 115 B floor, so **NO shortening pass can succeed**". Today: **26,382 B / 105 entries**; a 115 B pass reaches **21,061 B**, under the real 24,985 B limit with 3.9 KB slack. Its lever (a), the append-time budget, is built (`16dfe3b5`). Its lever (c), raise the limit, is moot. The operator decision it demands has no live fork.

`c302a3af457c` | **PRUNE** | Same refutation, stated as "the index is ENTRY-COUNT-bound, not hook-length-bound … at 128 entries the floor is ~17 KB with ZERO slack even at a perfect 59 B/hook". The cardinality ceiling `memory-nudge.sh` computes is **128 entries**; the index sits at **105**, under it. Hook length *is* the binding lever today (165 B actual vs 115 B target). Its lever (A) is built. Its lever (C), a 4th lossy pass, is now sufficient rather than a treadmill.

`ae2321e411a8` | **PRUNE** | **The CPU dimension landed.** `scripts/capacity-alarm.sh` now has `read_load()` at :751 reading `vm.loadavg` field 1 and `hw.ncpu`; `classify()` at :790 takes `load_per_core` as a scored rung; the emitted JSON at :1096 carries `load_1m`/`load_5m`/`load_15m`/`ncpu`/`load_per_core`/`load_warn_per_core`/`load_alarm_per_core`. The header (:123–164) documents the fatal-vs-survived calibration the item asked for. Not memory-only any more.

`1a4e292830ae` | **KEEP** | Verified live: `docs/plans/CONCURRENCY_PROGRAM.md` §S6.6 "Phase D — fix what the gate measures" is present at line 1365. This is a genuine operator value judgment (it adds a REFUSING term to the box-wide spawn path, G2) and it depends on Waves A+B slopes. **Mis-clustered** — see Notes.

`7b762bcbbe11` | **KEEP** | Confirmed never built. `memorystatus_control` appears only in `docs/research/{panic-compressor-2026-08-05,resource-guard-2026-08-08,crash-rootcause-2026-08-09}.md` — zero occurrences in `scripts/`, `bin/`, `hooks/`. `crash-rootcause-2026-08-09.md:152` states it directly: "The one kernel-enforced per-process cap available on macOS (root; phys_footprint ledger); **never built**". **Mis-clustered** — see Notes.

### cluster-C-hooks (6)

`7ea31ffa1a08` | **KEEP** | Re-verified today across **all four** config dirs, not just one: `subagent-stop` appears **1×** in `settings-templates/settings.example.json` and **0×** in `~/.claude`, `~/.claude-next`, `~/.claude-tertiary`, `~/.claude-quaternary`. `hooks/subagent-stop.sh` is present on trunk and symlinked into `~/.claude/hooks/`. Still inert. Its "settle the trace question first" caveat is untouched by anything I found.

`f30fa039f98f` | **KEEP** | `coldcompile-admit` = **0** registrations in every settings.json on the box. `hooks/coldcompile-admit.sh` present on trunk; `migrations/0006-coldcompile-admit-registration.sh` present, declares `migration-class: c10`, and is therefore **staged and never run** by the converger by design.

`72f5d3842313` | **KEEP** | `goal-inert-watch` = **0** registrations. `hooks/goal-inert-watch.sh` present; `migrations/0005-goal-inert-watch-registration.sh` present, `c10`, staged.

`8942f3b1506d` | **UPDATE** | Blocker intact, **number stale**. The differential corpus still does not exist: `tests/hook-chain-live-parity.bats` proves *dispatcher-vs-member* verdict parity, not *`grep -E`-vs-bash-`=~`* verdict parity on DANGER patterns, which is what R-3 is blocked on. But `hooks/validate-bash.sh` now carries **~30** grep invocations, not the 12 in the title (and in `HOOK_CHAIN_COST.md:353`), so the ~42 ms estimate understates the current cost. Update the count and keep the block.

`9a25cbc24799` | **UPDATE** | **"Unbounded" is refuted; the concern it names is now realised.** `scripts/rotate-autonomy-logs.sh:326` explicitly rotates `$HOME/.claude/logs/bash-execution.log`, and it has run — four archives on disk (`…20260719T…`, `…20260730T…`, `…20260805T…`, `…20260809T222138Z.gz`, the last one today). Live size is **705,175 B**, not 9.46 MB. So the second half of the item is now *more* true: rotation exists, therefore the decay window of every fleet rate in `HOOK_CHAIN_COST.md` §2.4 has already silently shrunk. `HOOK_CHAIN_COST.md:395` half-anticipates this ("if it is ever rotated or truncated the 39 h window shrinks silently. Re-derive, do not quote") — but the rates in §2.4 are still quoted. Remedy flips from "add rotation" to "re-derive §2.4 against the surviving window and state the window in the doc".

`c9cad66730b1` | **PRUNE** | **Already done.** Both live config dirs register `~/.claude/hooks/curl-gate-scope.sh` on PreToolUse/Bash — the scoped shim, not `curl-gate.py`. `hooks/curl-gate-scope.sh` is on trunk (`bbfcce87`). Landed via `migrations/0002-curl-gate-scope-registration.sh` (`a7cba56d`) and `be5dd3d1` ("perf(hooks): a project-scoped gate charged every Bash call for python startup"). The pending-activation script `26-curl-gate-scope-activate.sh` this item points at is a superseded duplicate of migration 0002.

### cluster-C-comms (3)

`02ba4e52389a` | **KEEP** | Premise fully intact after two weeks. Branch `wt-02ba4e52389a` still exists and `git rev-list --count origin/main..wt-02ba4e52389a` = **8** — the same 8 atomic commits (D4, D5, D9, D10, D11, D12, D6/D13 + docs), still unlanded. The land blocker was machine-wide test contention, and the machine is under *more* load now (4 kernel panics this week), so it has not self-cleared.

`894cf4b2ba03` | **PRUNE** | The distinction it exists to preserve is landed **in the subject's own header**. `bin/cc-await-ping:18` documents `--timeout` as "exit 2"; :560 has the banner "THE TIMEOUT IS A VERDICT, NOT A FAULT — SAY SO IN THE STREAM THAT SURVIVES"; :38–47 separates 143/144 as external process-group SIGTERM with the research doc cited. Commit `3c123bfc` ("docs(await-ping): exit 144 is an EXTERNAL process-group SIGTERM — not SIGURG…") is literally this item.

`8acb25430a42` | **KEEP** | `mailbox-wake-arm` = **0** registrations in every settings.json. `hooks/mailbox-wake-arm.sh` present on trunk and symlinked live; `migrations/0007-mailbox-wake-arm-registration.sh` present, `c10`, staged. Its header records the operator's own words for why this matters — arming is currently something a *model* must remember, re-armed by hand **five times** in one session, "brittle between armed and unarmed state".

## Master item(s)

### M-C1 — Every session is inbox-armed and subagent-traced at birth, because the four staged hook registrations are converged and the mail branch is landed

**Encompasses:** `8acb25430a42`, `72f5d3842313`, `f30fa039f98f`, `7ea31ffa1a08`, `02ba4e52389a`

**Why one effort.** Four hooks are built, tested, symlinked into `~/.claude/hooks/`, and registered in **zero** live `settings.json`. They are not four independent oversights — three of them (`0005`, `0006`, `0007`) are already written as idempotent migrations that the converger runs at every deploy, and all three are held by **one unratified sentence**. `migrations/README.md` states it outright:

> `c10` exists because §3's rescope of C10 — *"operator **runs**" becomes "operator **can revert**"* — is explicitly the one clause the doc says a human must ratify, once. **That ratification has not happened**, so the runner does not self-authorize it.

One human decision releases all three at once; `subagent-stop.sh` is the fourth of the same class, lacking only its migration file. `02ba4e52389a` is on the same surface with a *different* blocker (machine load, not ratification) and is called out as such below — its 8 commits build the mailbox lifecycle that `mailbox-wake-arm.sh` arms, so landing it first is a dependency, not a coincidence: `migrations/0007`'s own header cites `docs/plans/CROSS_SESSION_COMMS_V2.md` §10 as its finding source.

**Impact.** This is the enforcing-store effort, and it is the one that matches the cluster's shared surface — *what actually reaches a running session*. Evidence:

- **The wake path is the fleet's only cross-session channel and it is voluntarily armed.** `0007`'s header measures the cost: one session re-armed by hand **five times**. `asyncRewake` is confirmed live on 2.1.220 (the binary all live sessions run, re-verified 2026-08-09 by reading the binary — the field is consumed at the hook-dispatch call site, not merely present as a string). Registering it converts arming from a thing a model must remember into a declarative line of JSON.
- **It touches four enforcing stores, not one.** The config dirs are separate **real files**, already divergent: `~/.claude` 35,940 B · `~/.claude-next` 35,270 B · `~/.claude-tertiary` 35,955 B · `~/.claude-quaternary` 35,947 B. Registering in one leaves every session launched against another unarmed — the same silent half-coverage the hooks exist to abolish. `0007` already writes all four; the others must be checked for the same.
- **It retires the `pending-activation` diode.** 40 scripts are rotting in `docs/activation/pending-activation/`; `c9cad66730b1` in this very slice was one of them, already superseded by migration `0002`. Converging the migration path is what stops that store re-accumulating.
- **`7ea31ffa1a08` may be a live data-loss path, not tidiness** — if unnamed `Agent()` subagents leave no harvestable transcript, an unwired SubagentStop hook loses the record permanently. That trace question is unresolved and must be settled *before* wiring, per the item.

**DoD.** The C10 rescope is ratified once, in writing, in the doc that defines it. `migrations/0005`, `0006`, `0007` are promoted from `c10` to `mechanical` (the README calls this "the one-word diff") or run under an explicit operator grant, and `scripts/deploy-migrations.sh` has applied all three across **all four** config dirs with the ledger recording success. `subagent-stop.sh` has its trace question settled and, if the answer warrants, its own migration written and applied. Branch `wt-02ba4e52389a` is landed by content (`git ls-tree origin/main` on its paths), gates green. Every registration verified by reading the live `settings.json`, never by the migration's own exit code.

**Falsifier:**
```
for h in subagent-stop coldcompile-admit goal-inert-watch mailbox-wake-arm; do for d in ~/.claude ~/.claude-next ~/.claude-tertiary ~/.claude-quaternary; do grep -q "$h" "$d/settings.json" || exit 1; done; done; [ "$(git -C ~/Development/claude-infrastructure rev-list --count origin/main..wt-02ba4e52389a 2>/dev/null || echo 0)" = 0 ]
```

**First move.** Read `docs/research/inertness-generator-2026-08-07.md` §3 and `migrations/README.md` § "The two classes", then put the C10 rescope to the operator as **one** yes/no question with its blast radius stated — `0007`'s header already drafts it (three independent bounds: add-only, both binary tracks carry `asyncRewake`, `CC_WAKE_ARM=0` is a total no-op). Do not open four questions.

**Order.**
1. `02ba4e52389a` — land the mail branch first (needs a quiet box; `pgrep -f bats-exec-file` near zero). It is the lifecycle `0007` arms, and it is the only member whose blocker is load rather than ratification.
2. **C10 ratification** — the single operator gate. Blocks 3, 4, 5.
3. `8acb25430a42` (migration `0007`) — highest value: it is the wake path, and it is the only one whose absence is measured in re-arm count.
4. `72f5d3842313` (`0005`), `f30fa039f98f` (`0006`) — independent of each other, run in either order.
5. `7ea31ffa1a08` — settle the subagent-trace question, then write migration `0008` if wiring is warranted. Deliberately last: it is the only member where the *right action is uncertain*, and the item says settle before wiring.

---

### M-C2 — MEMORY.md loads in full, and stays that way, via one shortening pass the arithmetic now says is sufficient

**Encompasses:** `150c50055e1c` (canonical), `e27d37eac4cd`, `7e2df754d0b8`, `6267e2e3c707`, `eec945d6e2ec`
*(also retires `7021e89884df`, `c302a3af457c` as PRUNE — see Notes: closing this effort takes 7 ledger items off the board.)*

**Why one effort.** One file, one measurement, one action. All five describe the same condition — the index exceeds the loader's read limit, so the loader drops the tail silently — and they differ only in the size they were filed at and in which lever they believed was binding. That disagreement is now resolved by measurement rather than by judgment, which is what collapses them into a single mechanical pass.

**Impact, argued from evidence.**

- **It is live right now, and I watched it happen.** The index is **26,382 B** against a **24,985 B** limit. Exactly **4** entries begin past the limit and did not load: `restore-to-snapshot-pins-the-fault`, `abstain-belongs-on-the-branch-the-case-reaches`, `capture-based-probe-cannot-exercise-a-tty-gated-verb`, `guard-universalization-deletes-a-capability`. Corroborated independently: the copy injected into *this* agent's own context terminates at `abstain-belongs-on-the-branch-the-case-reaches` — I am missing the last two, and nothing in the file told me so.
- **The lesson being dropped is the newest one**, i.e. the tail is exactly the part written because something just went wrong. This is the file's whole purpose failing at its most valuable end.
- **Three blocked class-C items dissolve.** `7021e89884df` and `c302a3af457c` were correctly reasoned at 128–132 entries, where the floor genuinely exceeded the target. At **105** entries — under the 128-entry cardinality ceiling `memory-nudge.sh` itself computes — a pass to 115 B/hook lands at **21,061 B**, leaving **3.9 KB**. There is no longer a fork for the operator to pick.
- **The durable half is already paid for.** `16dfe3b5` put a refusing predicate at the PreToolUse chokepoint: a write is denied only if its *result* exceeds the limit **and** is larger than what is there now. Every shrinking or size-neutral write is allowed unconditionally, so an over-limit index can never be locked out of its own cure — the pass cannot be blocked by the gate that will hold it. Verified live: `~/.claude/hooks/lib/memory-index-budget.sh` is symlinked, and `backup-before-write.sh` sources it through a deref'd path with two fallbacks.
- **Corrected target, so the pass is not oversized.** Four items quote a 17.1 KB target. That figure is stale and `eec945d6e2ec` is the item that warned about exactly this failure ("a stale derived target invents excess on a healthy index"). The true limit is 24,985 B. Minimum cut **1,397 B**; available **5,250 B**.

**DoD.** `wc -c MEMORY.md` < 24,985 with headroom for at least ~15 further entries. No rule deleted — the reduction comes from hook shortening toward the 115 B target, with any archival done under `/compact-memory`'s SAFE-AUTO durability criterion and its lossy half shown as diffs and approved (`e27d37eac4cd` is that approval). All four currently-dropped entries verified present *and within the first 24,985 B*. `MEMORY.md` edited via `Edit`, never `Write` (INTEGRATE-never-overwrite). The three PRUNE'd decision items and the merged approval item closed in the ledger with this pass's evidence.

**Falsifier:**
```
[ "$(wc -c < /Users/chrisren/.claude-tertiary/projects/-Users-chrisren-Development-claude-infrastructure/memory/MEMORY.md)" -lt 24985 ]
```

**First move.** Re-derive before cutting — `eec945d6e2ec`'s caution is confirmed, not theoretical: the harness reminder says "24.8KB" while `wc -c` says 26,382 B, a ~1 KB disagreement. Recompute live (`LC_ALL=C`, bytes not codepoints — the index is dense UTF-8 and codepoint length under-measures by ~10%, which is the margin that decides a breach), then invoke `/compact-memory` and drive its PROPOSE-ONLY half to approval. Do **not** rebuild an append-time budget in `memory-nudge.sh` — that lever is built and better placed.

**Order.**
1. Re-derive size / entry count / hook average in bytes (`eec945d6e2ec`'s caution).
2. `/compact-memory` SAFE-AUTO archive half — reversible, needs no approval.
3. `150c50055e1c` + `e27d37eac4cd` — the shortening pass to 115 B/hook, diffs approved. This is the action.
4. `7e2df754d0b8` — confirm the append-time gate holds the new floor (its own `tests/memory-index-budget.bats`); close its landed half.
5. `6267e2e3c707` — close, recording that the two-tier hot/cold split it proposed is unnecessary at 105 entries.

---

### M-C3 — The box stops panicking under fleet load, because the four levers that could bound it are built and the instruments that measure it are re-derived

**Encompasses:** `1a4e292830ae`, `7b762bcbbe11`, `8942f3b1506d`, `9a25cbc24799`

**Why one effort — and why it is a third master item rather than folded into M-C1/M-C2.** These four share a root cause the other two do not touch: **the machine panics under fleet load, and every lever or instrument for it is unbuilt, uncalibrated, or measuring through a window that silently shrinks.** They are not "hooks" and not "memory index" — folding them into either would make that item a list. Concretely: `HOOK_CHAIN_COST.md` §8.5.4 shows hook fork cost is O(N²) under load — forks/s is O(N), cost-per-fork is O(load), load is O(forks/s) — so R-3 (`8942f3b1506d`) is a *load* term, not a tidiness term; R-5 (`9a25cbc24799`) is the decay window of every rate that argument rests on; Wave D (`1a4e292830ae`) is the admission gate that refuses spawns; and the memlimit lever (`7b762bcbbe11`) is the only kernel-enforced per-process cap. Same subject, four faces.

**Impact.** Highest-severity of the three — this is the cluster that produced **4 kernel watchdog panics in the last week**, the condition under which this very triage was ordered not to run test suites.

- **The kernel cannot save itself today.** `crash-rootcause-2026-08-09.md` §3: the entire CC fleet sits in **jetsam band 180** (killed last); only ~7.6 GB was jetsam-reachable below it at the Aug-5 04:27 event; `CONFIG_JETSAM` is off. Jetsam's only act at both near-misses was killing a 15 MB Apple daemon. `memorystatus_control` is the one lever that reaches band-180 processes, and it is **never built**.
- **The existing gate provably cannot bind.** `1a4e292830ae`: the free-bytes floor has fired **0 times in 127 refusals** — 40.55 GB ADMIT on a quiet box, 29.79 GB still-ADMIT *at the panic* while compressor segments were at 100%.
- **Half the instrument has already been fixed, which raises the value of finishing it.** `ae2321e411a8` (PRUNE'd above) landed the CPU/run-queue rung into `capacity-alarm.sh` — `read_load()`, a scored `load_per_core` term in `classify()`, and the calibration showing the fatal 2.53/core sat *below* a survived 2.92–5.98 band. The alarm now sees the axis; the *admission gate* still does not.
- **R-5 is now an active correctness bug in the doc, not a housekeeping item.** Rotation exists and has already run four times (most recently today), so `HOOK_CHAIN_COST.md` §2.4's fleet rates are quoted over a window that has since shrunk. The doc warns about this at :395 and quotes them anyway.

**DoD.** The admission gate keys on **active concurrency** with a compressor-segment term replacing the free-bytes floor, thresholds set from Waves A+B measured slopes rather than invented (this is the operator's value judgment — it adds a REFUSING term to the box-wide spawn path, G2, and stays a genuine STOP-ASK). The `memorystatus_control` per-pid memlimit lever is built and exercised against a band-180 process. `validate-bash.sh` has a differential corpus proving identical verdicts on **every** DANGER pattern before a single `grep` becomes a bash `=~`. `HOOK_CHAIN_COST.md` §2.4 rates are re-derived against the surviving log window, with the window and its decay mode stated inline.

**Falsifier:**
```
cd ~/Development/claude-infrastructure && grep -rq memorystatus_control scripts bin && ls tests/validate-bash-differential*.bats >/dev/null 2>&1 && grep -q 'segment' <(grep -A5 -i 'admission' docs/plans/CONCURRENCY_PROGRAM.md)
```

**First move.** `1a4e292830ae` is the only member that is a true operator decision and it gates the thresholds for everything else — but it needs Waves A+B's measured slopes first, or the numbers are invented. So the opening step is to read `docs/plans/CONCURRENCY_PROGRAM.md` §S6.6 (line 1365) and establish whether Waves A+B have landed their slopes; if they have not, that is the actual first task and Wave D stays blocked on data, not on the operator.

**Order.**
1. Confirm Waves A+B slopes exist (prerequisite for Wave D's thresholds).
2. `1a4e292830ae` — Wave D operator decision on the gate terms. Blocks nothing else mechanically but sets the thresholds.
3. `7b762bcbbe11` — build the memlimit lever; independent of Wave D, highest severity, root-required.
4. `9a25cbc24799` — re-derive §2.4 against the surviving window; cheap, and R-3's cost argument depends on those rates.
5. `8942f3b1506d` — the differential corpus, then the fork collapse. Last: it is a safety gate on DANGER patterns and `denylist-enumerates-spellings-not-the-class` is a live scar on this exact file.

## Notes for the lead

**1. Three items in `cluster-C-memory` are keyword-mis-clustered and belong to the concurrency/capacity slice, not this one.** `1a4e292830ae` (Wave D admission gate), `7b762bcbbe11` (kernel memlimit lever) and `ae2321e411a8` (capacity-alarm CPU rung) matched on the word "memory" but are about *machine* memory pressure, not the MEMORY.md index. I triaged them properly and folded the two survivors into M-C3, but if another agent holds a concurrency slice, M-C3 will collide with their master item — **merge M-C3 into theirs rather than the reverse**, since they will hold Waves A+B context that I do not. Only 7 of my 10 "memory" items are actually about MEMORY.md.

**2. Closing M-C2 retires 7 ledger items for one pass, and 3 of them are `blocked`.** `150c50055e1c` + `e27d37eac4cd` + `7e2df754d0b8` + `6267e2e3c707` + `eec945d6e2ec` (the effort) and `7021e89884df` + `c302a3af457c` (PRUNE on the same measurement). Three of those (`6267e2e3c707`, `7021e89884df`, `c302a3af457c`, plus `e27d37eac4cd`) are `status: blocked` awaiting an operator decision that no longer has two sides. **If you unblock nothing else from my slice, unblock these** — they are consuming the `👤` rung at every close for a question that is now arithmetic.

**3. Your deploy-parity hypothesis is refuted for `hooks/` — the inertness is one layer up.** Full sweep: 90 files in `hooks/` and `hooks/lib/`, **90 symlinked, 0 missing, 0 diverged**, including the brand-new `hooks/lib/memory-index-budget.sh`. `install.sh` is linking new files correctly. The real gap is `settings.json`, which is **four separate real files** (35,270–35,955 B, already divergent) that no symlink covers — so a hook can be perfectly deployed and still registered zero times. Any parity check that stops at `~/.claude/hooks/` will report green over this. Recommend the cross-cluster parity item, if one exists, be re-scoped from "is the file linked" to "is the file **registered**, in all four config dirs".

**4. The `pending-activation` store contains at least one superseded duplicate of a landed migration, and my slice found it by accident.** `c9cad66730b1` pointed at `docs/activation/pending-activation/26-curl-gate-scope-activate.sh`; the work landed via `migrations/0002-curl-gate-scope-registration.sh` instead. There are **40** scripts in `pending-activation/` and **7** migrations. If other clusters hold `pending-activation` items, they are worth cross-checking against `migrations/` before anyone runs one — **running a superseded activation script is a live footgun**, not just wasted effort.

**5. Landmine — a backlog item is explicitly named as WRONG inside production code.** `bin/cc-await-ping:243` reads: *"NOTE: backlog `5b77e20d9db6` reads 144 as 128+16 ⇒ SIGURG. That is WRONG on the signal."* That id is not in my slice. Whoever holds it should PRUNE or UPDATE it — it is a filed item whose premise its own subject refutes in a code comment, and acting on it would encode a signal-number error.

**6. `02ba4e52389a` is the one item in my slice a fresh session cannot simply drive.** Its blocker is machine-wide test contention — 8 commits, shellcheck clean, rebased, 4 land attempts all SIGTERM-killed mid-gate at 253/352/353/357 tests with ~1,700 cumulative green executions and **zero** red. It is not a defect and no amount of debugging will move it. It needs a quiet box. Given the 4 panics this week, M-C3 landing is arguably a prerequisite for M-C1 step 1 — which is the one genuine cross-master dependency in my slice.
