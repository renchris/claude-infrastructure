---
status: open
---

# Cloud-session observability — the observable set, designed before the first fire

**Filed** 2026-08-07 · backlog `191d4d056c98` · DoD ref
`docs/plans/CONCURRENCY_PROGRAM.md#s5-scale-beyond-this-box-the-only-route-to-100`.

**Scope (frozen):** design the observable set for cloud sessions — the repo-side liveness + progress
signals that replace `ps`/`lsof`/`launchd`/load-average — *before* cloud sessions are fired, not after.

**Scope (grown):** +the `cc-backlog` cloud-venue abstention guard. Follow-On Gate F1–F4 PASS — see §6
for why the design cannot land as prose alone.

---

## 0 · The verdict

**Firing a cloud session against today's fleet does not merely go unmonitored — it gets the session's
own work item reopened and handed to a second worker.** The item asked for an observable set on the
premise that cloud liveness is *invisible*. It is worse than invisible: two independent local oracles
return **confident, wrong, actionable verdicts** about a worker on another machine, and their
conjunction is exactly the input the reaper's dead-worker path consumes.

This is the reason the item's framing — *design the observables before firing, not after* — is
correct, and it is stronger than the framing assumed. The cost of firing first is not a blind spot.
It is silent duplicate execution against a shared trunk.

Three findings, in dependency order. Each is confirmed against the code, not inferred from naming:

1. **Both liveness oracles convict a cloud worker** (§2) — and they do it via their *success* paths,
   so every abstention valve in the file is bypassed.
2. **The coordination ledger is unreachable from a cloud VM** (§3) — it is an untracked local file, so
   a cloud session cannot claim, complete, or report at all.
3. **Therefore the observable set cannot be a watcher. It must be a bridge** (§4) — a local proxy that
   holds the claim and translates repo-side evidence into ledger transitions.

---

## 1 · What goes blind, and why adaptation is not available

A cloud session runs in an Anthropic-managed VM: no shared filesystem, no `ps`, no `lsof`, no
`launchd`, no load average, no iTerm2 pane, no `/tmp/cc-telemetry`. The fleet's liveness and progress
instruments are, without exception, built on those signals.

The important property is not that each instrument breaks. It is **how** each one breaks. An
instrument that *fails to run* is safe here — this codebase already models that as a non-verdict and
abstains (`rc 2`, §2). An instrument that **runs correctly and answers a question about the wrong
machine** is not safe, because nothing marks its answer as inapplicable. Every instrument below is in
the second class.

| instrument | reads | on a cloud worker |
| --- | --- | --- |
| `claimer_live` oracle 1 (`bin/cc-backlog:1185`) | `kill -0 <pid>`, else the local `cc-sessions` registry | **answers NOT-LIVE** (§2) |
| `owned_wait` oracle 2 (`bin/cc-backlog:1377`) | processes whose cwd is under `~/Development/.worktrees/wt-<id>` | **answers NOT-OWNED** (§2) |
| `cc-dispatch` `live_workers` (`bin/cc-dispatch:408`) | the ledger's `claimed` fold | survives — it is already ledger-keyed, not process-keyed |
| the ledger itself (`~/.claude/autonomy/backlog.jsonl`) | a local untracked file | **unreachable** (§3) |

`cc-dispatch`'s capacity oracle is the one piece of this stack that already works off-box, and it
works for the reason the whole design should follow: **it counts ledger state, never processes**
(`bin/cc-dispatch:52` — "*never a session count*"). That choice, made for unrelated reasons, is the
template for everything below.

---

## 2 · The confirmed defect — cloud work is adjudicated *proven dead*

### The chain

`cc-reaper` is live (`launchctl list` → `com.chrisren.cc-reaper`, pid 93567) on a **300 s**
`StartInterval` (`launchd/com.chrisren.cc-reaper.plist`). Every tick runs `cc-backlog reap`. For an
item claimed by a cloud worker:

1. **Rule A opens** once the claim is idle past `CC_BACKLOG_STALE_CLAIM_S` — default **5400 s / 90 min**
   (`bin/cc-backlog:1562`). A repo-only cloud task of any substance crosses this.
2. **Oracle 1 — `claimer_live`** (`bin/cc-backlog:1185`). The claimer is not `<this-host>-<pid>`, so
   the `kill -0` branch is skipped and the local `cc-sessions` registry is asked. The registry
   **answers**, and does not list the cloud session. `jq -e` exits 1 → **`rc 1`, PROVEN NOT-LIVE**
   (`bin/cc-backlog:1229–1231`) — the one verdict the reopen path may act on.
3. **Oracle 2 — `owned_wait`** (`bin/cc-backlog:1377`). The worktree root exists, so the abstention at
   `:1387` does not fire. The item's local worktree `wt-<id>` does not exist, and
   **`[ -d "$wt" ] || return 1`** (`bin/cc-backlog:1391`) → **`rc 1`, NOT-OWNED** — again a real verdict.
4. **The conjunction reopens.** At `bin/cc-backlog:1735` the block path requires
   `claims ≥ maxattempts` **or** `owned` **or** `clrc == 2` **or** `starved`. A cloud worker satisfies
   none: `clrc=1`, `owned=""`, `starved=""`, `claims=1`. Control falls to the `else` → **`reopen`**.
5. **`reopen` sets `status=open`, which is `cc-dispatch`'s fire predicate** (`bin/cc-backlog:73`) → the
   item is re-dispatched to a second worker while the first is still running.

### Why every existing safety valve misses this

`bin/cc-backlog` has fought this exact failure class three times, and its defences are extensive and
well-argued: three-valued oracles (`:1169`), an abstain-on-non-verdict path (`:1701`), a total-oracle-
starvation path (`:1717`), bounded ceilings that end at a human rather than a reopen (`:1735`). The
file's own header states the asymmetry correctly — *"a false dead verdict SPAWNS a duplicate peer, a
missed dead worker only STRANDS an item, visibly and recoverably"* (`:1324–1326`).

**All of it triggers on probe *failure*.** `rc 2` means "the probe could not run". Not one of those
valves fires here, because on a cloud-claimed item **both probes run perfectly**. They resolve a
registry, they stat a directory, they get clean answers. The answers are about this Mac.

The comment at `:1380–1385` is where the gap is visible in the source's own words. It enumerates what
a missing `wt-<id>` under an existing root can mean — *"the item is worked in place, or its worktree
was torn down"* — and both readings presuppose **on this box**. Cloud execution is a third world-state
the enumeration does not contain, and it falls into the `rc 1` bucket that the comment says exists "to
keep the dead-worker path reachable at all".

This is the fleet's own recorded pattern `sibling-auditors-must-share-the-state-model`: *two checks
over one population disagreed because only one modeled "unlinked BY DESIGN" ⇒ the other convicted the
live layer for obeying it.* Here the oracle convicts a cloud worker for obeying the cloud execution
model.

### Severity, stated precisely

- The **reopen** — the claim is lost, the item re-enters the open pool — fires **today**, automatically,
  within 5 min of the 90-min threshold. `cc-reaper` is loaded and running.
- The **duplicate spawn** additionally requires `cc-dispatch`, whose plist is deployed to
  `~/Library/LaunchAgents` but **not currently loaded** (`launchctl list` → no match; the plist is
  marked "*TEMPLATE — NOT auto-loaded*"). So the second half is latent *right now*.
- It stops being latent exactly when the program succeeds. Loading the dispatcher for autonomous
  overnight drain is **S4 of `CONCURRENCY_PROGRAM.md`** and is the stated goal. Cloud routing (S5) and
  dispatcher loading (S4) are parallel tracks in the same program: **whichever lands second arms this.**

- And it requires a cloud claim to exist at all. **None does yet** — §7 measures no `--cloud` session
  flag on either installed CC version, so nothing currently writes `--venue cloud`. The defect is
  **armed, not firing.**

That timing is the whole argument for the item's premise. Three conditions have to coincide — a cloud
claim exists · the reaper crosses the stale gate · the dispatcher is loaded — and the program's own
roadmap supplies the two that are missing. There is no window in which firing cloud sessions first is
cheap, and the window in which the guard is free is **now**, while nothing exercises it.

### A second, narrower hazard: PID collision

If a cloud claim were ever written in the `<host>-<pid>` shape and the cloud host's short hostname
happened to match this Mac's, `claimer_live` would run `kill -0 <pid>` **against a local pid**
(`bin/cc-backlog:1190–1192`). An unrelated local process at that number yields a false **LIVE**, pinning
the item until `LIVE_CLAIM_MAX_S` and then blocking it as a "wedged live worker". The failure direction
inverts, which is why the venue must be encoded explicitly rather than left to shape-inference (§5).

---

## 3 · The constraint underneath: the ledger is not reachable from the cloud

The backlog store is `${CC_BACKLOG_FILE:-$HOME/.claude/autonomy/backlog.jsonl}` (`bin/cc-backlog:299`)
— measured 2026-08-07 at **1.4 MB and untracked** (`git ls-files` → no match). The verdict journal
`idl.jsonl` is the same. A cloud VM cloning this repo receives **no ledger at all**.

Every coordination verb — `claim`, `done`, `block`, `reopen`, `reap` — is a local binary writing a
local file. So a cloud session cannot claim its item, cannot record evidence, and cannot mark itself
done. The `cc-backlog done <id> --evidence <sha>` contract that every dispatched worker closes on is
unavailable to it.

**This reorders the design.** "How do I watch a cloud session" is downstream of "how does a cloud
session participate in the work protocol at all". An observable set that only *watches* would leave the
ledger permanently stale, which is precisely the state §2 punishes.

---

## 4 · The observable set

The design follows from §3: **the cloud session is not a ledger participant. A local proxy is, on its
behalf.** The observables are the evidence that proxy adjudicates.

### 4.1 The transport: git refs, not branches

The only channel a cloud VM and this Mac reliably share is the git remote. Branches are the obvious
carrier and the wrong one — a branch push is coarse (minutes to hours apart), and using branch tips as
a heartbeat pollutes history with beat commits.

**Use a dedicated ref namespace instead.** A cloud worker force-updates a ref per item:

```text
refs/cc/heartbeat/<item-id>   → a commit-ish whose committer date IS the beat
refs/cc/progress/<item-id>    → the worker's current head (what it would land)
```

Properties that make this the right primitive: refs are writable without touching branch history;
`git ls-remote` reads them in one round trip without a fetch; they are namespaced away from
`refs/heads/*` so no branch-reaper, land-lock, or `/ship` path sees them; and force-update is atomic.

> 🚨 **RETRACTED as the transport, 2026-08-08 (item `40b46a34e1ce`). The cloud worker cannot write
> these refs.** Every property listed above is a property of *git*, and every one of them is real.
> None of them is a property of **the proxy standing between the worker and the remote**, which is
> what actually adjudicates the push — and it allows exactly one destination:
>
> > **Push protection**: `git push` works only against the session's current working branch;
> > cloning, fetching, and PR operations work normally.
> > — [Configure cloud environments § GitHub proxy](https://code.claude.com/docs/en/cloud-environments)
>
> `refs/cc/heartbeat/<id>` is not the session's current working branch, so **O1 as designed is not
> writable from a cloud VM.** `CONCURRENCY_PROGRAM.md` §S5a set the consequence in advance and it now
> binds: **O1 must become a working-branch commit — the shape this section rejected — or leave git.**
>
> **What this section got wrong is its first sentence, not its ref design.** *"The only channel a
> cloud VM and this Mac reliably share is the git remote"* is false, and believing it is what made a
> ref namespace look like the only place to put a heartbeat. Two non-git channels were found while
> measuring this (§4.6): the CLI's hidden `--teleport` and the `/v1/code/sessions/{id}/events` REST
> surface it reads. A heartbeat does not have to be a git object at all, and the strongest reason not
> to force it into one is that the git path is the single most restricted channel of the three.
>
> ⚠️ **The retraction rests on the vendor's stated rule, NOT on a measurement — and the measurement
> that would have closed it could not be run.** The loophole hypothesis (a proxy that enforces
> "your working branch" by checking `refs/heads/*` only, leaving `refs/cc/*` unexamined) is
> **untested**: eleven cloud sessions across three accounts have now been created and *none has ever
> produced an observable push* (§4.7), so the probe never reached the proxy. That gap does not
> reopen the design decision. Building a liveness channel on an undocumented gap in a stated
> security control is the wrong design **even in the world where the gap is real**: it is one
> proxy patch from silently going dark, and a heartbeat that fails silent is the one failure mode
> §4.4 exists to prevent.

### 4.2 The four observables

| # | observable | question it answers | read by |
| --- | --- | --- | --- |
| **O1** | `refs/cc/heartbeat/<id>` committer timestamp | *is it alive right now?* | `git ls-remote` — one round trip |
| **O2** | `refs/cc/progress/<id>` sha, and whether it advanced | *is it making progress, or spinning?* | `git ls-remote` + `git log` on fetch |
| **O3** | a commit trailer `Cc-Item: <id>` / `Cc-Venue: cloud` / `Cc-Session: <sid>` | *whose work is this?* — attribution | `git log --format=%(trailers)` |
| **O4** | branch pushed / PR opened | *did it finish, and with what?* | `git ls-remote` / `gh pr list --json` |

**O1 is the load-bearing one, and it is the one that does not exist today.** O2–O4 are all *outcome*
signals: they move only when work completes. Liveness needs a signal that moves while work is *in
progress*, and nothing in the repo-side surface provides one unless the worker is instructed to emit
it. That is the single most important design consequence of this item: **a heartbeat is not
observable — it must be emitted.** Designing after firing would have meant discovering this with
sessions already in flight and no way to retrofit them.

### 4.3 Attribution — key on the trailer, not the branch or the author

Multiple cloud sessions push to one remote, so attribution must be explicit. Each candidate key fails
differently:

- **branch name** — collides with the local `wt-<id>` convention (`bin/cc-backlog:1236`) and with a
  local session working the same item; a rename orphans the mapping.
- **commit author** — every cloud session authors as the same operator identity. Zero discrimination.
- **push time** — a proxy for the wrong thing; concurrent pushes interleave and a rebase rewrites it.
- **commit trailer (O3)** — survives rebase and cherry-pick, is machine-readable, and states venue and
  session explicitly rather than inferring them from shape. **This is the key.**

### 4.4 Silence is not one state

The design's hardest requirement. A quiet `refs/cc/heartbeat/<id>` is produced by at least seven
distinct worlds: the worker is thinking · rate-limited · crashed · never started · finished but failed
to push · pushed to a ref nobody watches · sandboxed without network egress.

O1 separates *none* of them from each other — it separates all of them **collectively** from "alive".
That is the honest limit of a repo-side instrument, and the design must not pretend otherwise. The
correct disposition for a stale heartbeat is therefore **abstain-and-escalate, never reopen** — the
same bounded-abstention shape `bin/cc-backlog:1717` already implements. A repo-side observer may prove
life; it may never prove death.

### 4.5 The observer's own liveness

The poller is an instrument and has its own failure modes: expired `gh` auth, a rate limit, an
unreachable remote, a hung `git ls-remote`. Every one of them looks identical to "the subject stopped
beating". So the poller must **time-cap its probe and report `UNRESOLVED` distinctly from `STALE`** —
the same `rc 2` discipline `claimer_live` already applies to a wedged `it2` (`bin/cc-backlog:1204–1206`),
for the same stated reason: *our own timeout must never forge the kill evidence.*

### 4.6 The git remote is not the only shared channel — added 2026-08-08

§4.1's premise was that it is. Two others exist on 2.1.220, both found while measuring `40b46a34e1ce`:

| channel | what it is | evidence |
| --- | --- | --- |
| `claude --teleport <session-id>` | **hidden** flag (in `strings`, absent from `--help`); pulls a cloud session down to continue locally | binary carries `teleportFromSessionsAPI`, `checkOutTeleportedSessionBranch`, `[teleport] Fetching events from:` |
| `/v1/code/sessions/{id}` and `…/events` | the REST surface teleport reads; siblings `/events/stream`, `/teleport-events`, `/archive`, `/client/presence` | string-extracted from the 2.1.220 bundle |

**Why this matters more than the ref question it displaced.** These are *pull* channels the observer
drives, so they do not depend on the worker emitting anything — which is the exact defect §4.2 named
as O1's reason to exist (*"a heartbeat is not observable — it must be emitted"*). A session-events
read is closer to a real liveness oracle than a beat ref ever was, and it is not behind the push
proxy.

⚠️ **Both are UNVALIDATED as instruments, and neither is free.** `--teleport` was driven to a real
session and stopped at an interactive **folder-trust dialog**; scripting past that is bypassing a
safety prompt, so it was not done. The REST path needs the account's OAuth token, which is
credential material this box's own tooling correctly refuses to hand an agent. So both are **named,
not commissioned** — the next design pass should cost them properly rather than assume them.

### 4.7 Eleven sessions, zero observable actions — the wall this design now sits behind

The `refs/cc/*` probe could not be run, and the reason is upstream of the proxy: **no cloud session
created from this box has ever been observed to do anything.**

| | | re-read with |
| --- | --- | --- |
| sessions declared (≥2 accounts — 6 tagged `next2`, 1 `next3`, 4 untagged) | **11** | `cc-cloud list` |
| that pushed any ref, opened any PR, or produced any remote-visible artifact | **0** | `git ls-remote origin` → 2 refs, both `main` |
| longest observed | **17h** (`session_01TYUBVAqDxXPQ6hpZhpWpUP`, next2) | `cc-cloud show <id>` |
| fired on a `--verify`-linked account, clone mode, explicit push instructions | `session_01DcTULYmXVnUnrwyFKm8LGH` (next3) — **0 refs in 7h** | same |

The next3 row is the one that carries the weight: it is the arm with every known precondition
satisfied — an account whose CLI→GitHub link is not merely recorded but **end-to-end `--verify`d**,
a create that returned in clone mode rather than falling back to a bundle, and a task description
whose entire content is four `git push` commands. It behaved exactly like the other ten.

The create path returns a real session id, the headless send arm returns `{"ok":true}`, and
`cc-cloud` classifies the result `NOT-STARTED · no ref after 9h (boot budget 15m)`. Per §4.4 that
verdict is honest and **collectively** unrevealing: it separates *alive* from the other seven
worlds and does not name which one holds.

🚨 **This retires the premise the program has been sequencing on.** `CONCURRENCY_PROGRAM.md` §S5.2
already narrowed it once — *"creating a session and running tokens through it are different
questions, and only the first has been measured"* — and this is the second question measured, with
a null result. **Cloud capacity is not capacity until a cloud session is observed doing work.**
Nothing downstream of "a cloud worker does X" should be built until one has been.

---

## 5 · What this change lands: the venue guard

Per `conclusion-must-reach-the-enforcing-store`, the design does not land as prose. The enforcing
store here is `bin/cc-backlog`'s adjudication path, and the minimum correct change is to **give the
oracles the missing state** so that a cloud-venue claim can never be convicted by a local probe.

**Convention — an explicit, closed-set `--venue`, never an inferred one.** A claim records where its
worker runs: `cc-backlog claim <id> --by <worker> --venue cloud`. `venue ∈ {local, cloud}` is
validated at the transition writer; an unknown value is **rc 2, refused** — never silently accepted.

The closed set is the load-bearing half. This string *selects which oracles may convict*, so a typo'd
`--venue clod` accepted as free text would fall through every venue test back onto the local oracles
and re-arm the exact false-dead the gate exists to stop — a mislabel that reads as a verdict
(`default-path-hardening-is-blind-to-the-explicit-argument`).

Encoding venue as an explicit field rather than inferring it from the shape of `by` is also what
closes the §2 PID-collision hazard: venue is *declared*, never guessed.

**Folding.** `venue` rides the **last claim** and **resets on re-claim** — deliberately not
`$r.venue // $p.venue`. A carry-forward fails closed-then-stuck: a cloud claim → reopen → ordinary
local re-claim writes no venue field, so the carry-forward would keep `cloud` while `by` correctly
became the local worker. That worker would then be permanently unobservable to oracles that can see
it perfectly well, and its item would never be reaped again — silently, for the rest of its life.
An absent field folds to `local`, which is what makes the whole change inert for every pre-existing
record and every local claim.

**Behaviour.** For a non-`local` venue **both** oracles return **`rc 2` UNRESOLVED** — not `rc 0`,
not `rc 1`. Both, not one: `claimer_live` and `owned_wait` are sibling auditors over one population,
and a pair that disagrees about what the population *is* re-creates the defect through whichever
half was left behind (`sibling-auditors-must-share-the-state-model`). All four call sites —
`reopen`'s live-claim guard, `claim`'s lease, `reclaim`'s anti-steal, and `reap`'s Rule A — pass the
**incumbent's** venue, never the caller's: where the caller runs says nothing about whether the
holder is visible.

- **not `rc 0` LIVE** — that would be a lie. We have no evidence it is alive, and it would pin the item
  until `LIVE_CLAIM_MAX_S`.
- **not `rc 1` NOT-LIVE** — that is the defect.
- **`rc 2` UNRESOLVED is exactly true**: *the probe that could see this worker cannot run here.* It
  routes to the existing abstain path, stays bounded by `UNRESOLVED_MAX_S`, and terminates at a human
  `block` rather than a `reopen`.

The three-valued contract this file already carries has precisely the right slot for cloud. Nothing
new is invented — the oracles simply stop misclassifying "somewhere I cannot see" as
"answered, and absent". Critically, the gate does **not** blunt local dead-worker detection: an
absent venue folds to `local`, so every pre-existing record and every local claim behaves exactly as
before. Inferring the venue from *"the registry didn't list it"* would have been the bug — that is
the normal, correct way a dead **local** worker is detected.

Once O1 exists (§4.2), the heartbeat becomes the affirmative half: a fresh beat absolves as an owned
wait, a stale one leaves the abstention in place until the ceiling. The guard is correct and safe
*without* the heartbeat, and strictly better *with* it.

---

## 6 · Provenance, and why this ships as one diff

**The guard was already implemented in this item's own worktree, uncommitted and untested**, by an
earlier session on this same backlog id that stopped before landing. This session found it only after
independently deriving the same defect and starting a narrower fix — a `cloud:` prefix on `by`, i.e.
exactly the *inferred* venue the built version's closed-set argument rejects. The pre-existing
implementation is the better design and is what ships; the duplicate was discarded.

That near-miss is itself the recorded lesson `search-branch-graveyard-before-building` /
`inventory-before-building`, and it earned its keep again here: **the first thing to inspect for a
dispatched item is its own worktree's uncommitted state.** The independent derivation was not wasted —
it corroborates the defect from a cold start and supplied the call-site audit — but the build was.

What this diff adds to the pre-existing implementation:

- **The tests** (none existed): the population sweep with its local positive control, the bounded
  abstention, the venue-reset trap, the closed-set rejection, the claim-only rejection, and the lease.
- **This document**: the observable set (§4), which the guard is a prerequisite for rather than a
  substitute for.

A design doc naming a live double-dispatch path and leaving it uncommitted is behind a diode: the
enforcing store never reads it (`conclusion-must-reach-the-enforcing-store`), and a mechanism named
only in prose is not built (`spec-named-mechanism-may-be-prose-only`). An *implemented but untested
and unlanded* mechanism is the same diode with more sunk cost.

---

## 7 · What is actually available today — measured, not assumed

Run on this box, 2026-08-07. These bound how urgent §2 is and which channels §4 can rely on.

| probe | result |
| --- | --- |
| `claude --help \| grep -ci cloud` @ **2.1.220** (eval track, what these sessions run) | **1** — and it is only `ultrareview … Run a cloud-hosted multi-agent code review` |
| same @ **2.1.114** (stable) | **0** |
| `gh auth status` | ✅ logged in as `renchris`, scopes incl. `repo`, `workflow` |
| `git remote -v` | `https://github.com/renchris/claude-infrastructure.git` — GitHub |
| `git ls-remote origin 'refs/cc-heartbeat/*'` | **rc 0 in ~0.5 s** — arbitrary ref namespaces are readable, so O1/O2 need no new infrastructure |

**There is no `claude --cloud` session flag on either installed version.** The cloud surfaces that
do exist are:

- **`Agent(isolation: "remote")`** — the tool contract states it "launches the agent in a remote cloud
  environment (always runs in background; availability is **gated**)". This is the real off-box
  execution path an agent can reach, and the one S5 would route work through.
- **`ultrareview` / `/code-review ultra`** — a cloud-hosted multi-agent review. User-triggered and
  billed; an agent cannot launch it.

**So the fleet is genuinely pre-first-fire, which is exactly the window the item named.** §2's
double-dispatch is armed rather than firing: no cloud claim exists yet to be convicted. That is the
argument for landing the guard now — the cost of being early is one abstention branch nothing
currently exercises; the cost of being late is silent duplicate execution against a shared trunk.

⚠️ **This table is a perishable measurement, not a standing fact** — CLI surfaces change per release
(`published-figure-decays-with-its-source`). Re-run the probes rather than citing this table.

### Settled since — entitlement was never ONE fact (2026-08-08)

~~**Cloud entitlement is per-account and remains unverified.** … Settling this needs a probe that
does not exist yet, or an operator check in the web UI.~~ **← SETTLED BY EXECUTION. All three
clauses are false: the probe exists, it was run, and no web-UI check is required.** The question was
unanswerable as posed because it asked *one* thing about **three separately-gated surfaces**, which
is why "is cloud enabled?" kept returning contradictory answers:

| Surface | Gate | Measured on this box |
| --- | --- | --- |
| `Agent(isolation: "remote")` | `ian()` = `hasUsedRemoteSession && hasRemoteEnvironment && Ke("tengu_neapolitan")` | **OFF, all four accounts** — `hasUsedRemoteSession` ABSENT everywhere and `tengu_neapolitan` in no `cachedStatsigGates`, so the conjunction is false regardless of the third term |
| CLI attach — `claude --cloud <id>` | Anthropic rollout | **OFF, uniformly** — `not enabled for your account` ×4 (`CLOUD_OBSERVABILITY.md` §6.4) |
| CLI create — `claude --cloud "<desc>"` · routines API | none found | **WORKS** — creates land (§6.5); `RemoteTrigger{action:"list"}` returned **HTTP 200** live from this session |

🚨 **`isolation:"remote"` reportedly does not fail loudly when gated — it silently downgrades to
`isolation:"worktree"` and logs a line.** *Provenance: that behaviour is a **binary read**, relayed
from the filing session and NOT re-derived here* (`spec-named-mechanism-may-be-prose-only`). What
**is** confirmed here: all four identifiers — `tengu_neapolitan`, `hasRemoteEnvironment`,
`remote_launched`, `async_launched` — are present as fixed strings in the running 2.1.220 binary
(`~/.claude-220/…/bin/claude.exe`, 257 MB, compiled — grep it with `-a -F` and a timeout, it is not
readable JS). Two distinct status values existing is consistent with a downgrade but does not prove
one. Either way the experimental rule is forced: branch on the returned **status**, never on call
success, or a naive test reports cloud success while having run locally
(`claimed-outcome-vs-checked-outcome`).

🚨 **`hasRemoteEnvironment` is a mutable RECORD, and quoting its distribution is publishing a
decaying figure.** Measured three times, three answers — each correct when taken:

| When | Reading | Source |
| --- | --- | --- |
| 2026-08-07 | **1 of 4** — `~/.claude-quaternary` only | the backlog item this section answers |
| 2026-08-08 01:08 | **2 of 4** — `+ ~/.claude-next` | landed correction `99aad939` |
| 2026-08-08 17:26 | **4 of 4** — all four | this section (`~/.claude-secondary` and `~/.claude-tertiary` written 17:22 / 17:23) |

The spread is monotone and client-written (`bin/cc-cloud` does not write the key), and it happened
*while* the fleet was probing cloud paths — so the act of measuring moves the reading, and the local
negative control is now gone. Two consequences: the key can never be an entitlement oracle (which is
the same verdict §6.4 reached from the refusal probe, reached independently from the other
direction), and **no document may cite its distribution** — cite the command
(`published-figure-decays-with-its-source`):

```text
for d in ~/.claude-next ~/.claude-secondary ~/.claude-tertiary ~/.claude-quaternary; do
  grep -o '"hasRemoteEnvironment":[^,}]*' "$d/.claude.json" || echo ABSENT; done
```

⚠️ `~/.claude` is the live symlink layer, **not** an account dir — sweeping it in place of a real
account still reports a plausible count.

**Routines are account-scoped, and one already exists.** The item recorded `{"data":[]}` on account
`next`; the same call from this session (`next3`, `~/.claude-tertiary`) returns **one** enabled
routine — `trig_019FHJArDsm8KaMqNRNq2CX6`, created `via http_api` 2026-06-14, next run 2027-06-01,
carrying a materialized `job_config.ccr.environment_id`. So "zero routines exist" was an
account-scoped reading, not a fleet fact — the same scoping §10.2 of the plan found for cloud
sessions. **`CronCreate`/`CronList` are NOT this path**: they are local, in-memory, session-only and
expire in 7 days. The cloud path is `/schedule` → `RemoteTrigger` → CCR.

`bin/claude-accounts` still has **no cloud-entitlement concept** — that part of the original bullet
stands. It is no longer a blocker, just the wrong instrument: read the per-account `.claude.json`
keys, or run the refusal probe (§6.4). The `CONCURRENCY_PROGRAM.md` S5 instruction to "check
`/accounts`" still points at a surface that cannot answer it
(`spec-named-mechanism-may-be-prose-only`).

~~**Nothing yet passes `--venue cloud`.**~~ **← also stale: `bin/cc-dispatch:1122` is the producer**
(`claim_args+=(--venue cloud)`, landed `b25b5c24`), and `bin/cc-backlog:1112` gates off-box
eligibility on it. The flag is no longer inert.

### Still open

- **The heartbeat emitter (O1) is worker-side.** It belongs in the cloud worker's brief, not in
  `cc-backlog`, and cannot be written until the dispatch path above is chosen. Still unbuilt — no
  `cc-heartbeat` producer exists in `bin/` or `scripts/`.

---

## 8 · Traps — do not rediscover

- **A probe that succeeds is not a probe that is applicable.** Both oracles in §2 answer cleanly and
  wrongly. Every abstention valve in `bin/cc-backlog` keys on the probe *failing*, so a probe that
  confidently answers about the wrong machine bypasses all of them. When adding a venue, ask what each
  existing oracle's success path now means — not whether it still runs.
- **Do not "fix" this by making `owned_wait` fail-open for a missing worktree.** That would break the
  positive control at `tests/cc-backlog.bats:700` and re-open the genuine dead-worker path for local
  workers. The state to add is *venue*, not *doubt*.
- **A repo-side observer can prove life, never death** (§4.4). Any consumer that reopens on silence
  re-creates the §2 defect through a new door.
