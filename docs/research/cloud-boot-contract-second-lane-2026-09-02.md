# The boot contract was cured on one lane, and the fire lane still times its push at the end

**Row:** `cc-backlog 0c8b39b67665` — *"CLOUD_OBSERVABILITY.md's 'first act = push an empty commit'
contract is PROSE-ONLY, never implemented — it is the sole basis for C1 NOT-STARTED being readable
as 'never booted'."*
**Venue:** cloud VM, `session_01QPGxfh5gz5SA5NAYE8hbG1`, branch
`claude/fire-20260902T105306Z-79956-1`, 2026-09-02T10:53:06Z.
**Disposition:** the row is **DISCHARGED for the dispatcher lane** by `0efcc073`, its "sole basis"
clause stays **REFUTED**, and a **second lane is still live** — which is this diff.

This is the successor reading to `docs/research/cloud-boot-contract-restrandings-2026-09-02.md`
(the cure's own artifact, written 6 h earlier from `session_01Y6CYm6KezSikd3KVGCnEjL`). That
document's §7 said the cure's effect "cannot be observed from here; it is observable on the next
cloud dispatch as a ref appearing inside the boot budget." **This session is that next cloud
dispatch**, and §3 below is the observation it asked for. It did not go the way the cure intended.

---

## 1 · The discharge, verified on trunk rather than re-derived

`0efcc073` — *feat(cloud-boot): the absence contract stops being prose* — is an ancestor of
`origin/main` (`git merge-base --is-ancestor 0efcc073 origin/main` → 0), landed 2026-09-02
04:46:15 +0000. It actuates §4.1/§8 step 2 inside `bin/cc-dispatch`'s brief composer: a cloud brief
now opens with a BOOT PING requiring `git push -u origin HEAD` before the worker reads anything.

Verified live in this venue on trunk, not recalled:

```text
git show origin/main:bin/cc-dispatch | grep -c 'BOOT PING'        →  3
bin/cc-dispatch selftest                                          →  180 passed, 0 failed
  …including 12 (c7) arms that pin exactly this contract, e.g.
  "(c7) a CLOUD brief carries the boot ping"
  "(c7) …and forbids the empty commit that would land as trunk noise"
  "(c7) a LOCAL brief has NO boot ping"
```

No commit between `0efcc073` and `origin/main` reverts it. **For the dispatcher lane the row is
done, and nothing below re-litigates it.**

## 2 · The clause that stays refuted

The row calls the contract *"the sole basis"* for reading C1 as never-booted. §16.4 of
`CLOUD_OBSERVABILITY.md` already refuted that on trunk and this session confirms the refutation
stands: since 2026-08-27 `scripts/cloud-inbox.py` reads the control plane per session
(`worker_status`, `status_bucket`, `post_turn_summary.*`) and separates "never ran a turn" from "ran
turns, pushed nothing" with no worker cooperation at all — 222 of 262 sessions the board filed
NOT-STARTED had ended a turn asking a question.

The ping is the *weaker* discriminator and the one `classify()` can afford (git-only, offline,
inside an `ls-remote` it already makes). Recorded, not acted on: the change that would move ~85% of
the board is wiring `inbox`'s projection into `cc-cloud classify()`, and it is not in this diff
either.

## 3 · §7's predicted observation, made — and the cure did not run on the session sent to check it

The cure landed at **04:46:15Z**. This session was fired at **10:53:06Z**, **6 h 06 m 51 s later**,
and its brief was composed by a `bin/cc-dispatch` that predates the cure. Five independent marks on
the brief this VM actually received, each checkable against `origin/main`:

| what the brief shows | what trunk has | landed |
| --- | --- | --- |
| no BOOT PING at all | the ping, cloud-only | `0efcc073` 09-02 04:46:15Z |
| no DISPATCHER VINTAGE line | `vintage_rail`, the blob stamp + its one-read check | `f9cbe177` 09-02 02:15:02Z |
| no `--unshallow` clause in the staleness rail | the deepen-first clause | `22b8824c` 09-01 20:58:52Z |
| `git -C /Users/chrisren/Development/claude-infrastructure …` | cloud briefs drop the prefix | `0efcc073` |
| `cc-backlog done` / `block` / `cc-notify` as the dispositions | cloud tail routes through the branch | `0efcc073` |

So the live dispatcher is **at least 13 h 54 m behind trunk** (bounded by the oldest of the three
absent rails). Landed is not live — `CLOUD_OBSERVABILITY.md` §13.6, and the `🚀` rung.

**The sharper half, because it is a sensor and not just a lag.** `bin/cc-premise`'s EVIDENCE AGE arm
computes its churn list off `origin/main` (`rev-list --count --since=<first_ts> origin/main --
<paths>`, then `log --since=… origin/main`). The brief told this worker:

```text
2 commit(s) have landed on the file(s) it cites
  landed since:
    da729350d 2026-08-29 feat(cloud-park): …
    7a67b3265 2026-08-26 docs(cloud): …
```

Re-run here with cc-premise's own query, on a fully deepened clone, against the same timestamp:

```text
git rev-list --count --since=2026-08-23T21:26:48Z origin/main -- docs/plans/CLOUD_OBSERVABILITY.md
  →  3
    0efcc073 2026-09-02 feat(cloud-boot): the absence contract stops being prose …   ← ABSENT from the brief
    da729350 2026-08-29
    7a67b326 2026-08-26
```

The arm under-reported by **exactly the commit that cured this row**. The one signal built to tell a
worker "your cure may already be on trunk" pointed away from the cure, on the row whose subject is
the cure. Whatever the mechanism — a stale remote-tracking ref at compose time, or a dispatcher old
enough to predate `refresh_trunk`'s cloud-scoped fetch (`d877dc7e` / `4a26a751`) — the desk composed
this brief against a git view that did not contain `0efcc073`.

Two consequences worth stating plainly:

- **This VM was the boot-budget probe and it produced no boot ref**, because it was never asked to.
  A reader of the board would file this session C1 NOT-STARTED for the first six hours of its life
  and be wrong, six hours after the fix for that shipped.
- **The clone did arrive shallow** (`git rev-parse --is-shallow-repository` → `true`, depth 50;
  `--unshallow` yields 3,984 commits), and the brief carried no deepen clause — the precise hazard
  `22b8824c` exists to prevent, live on this session 13 h after its fix landed.

Nothing here is a defect in `0efcc073`. It is a convergence fact about the deploy layer, and the one
read that settles it is on the operator box: compare `~/.claude/bin/cc-dispatch` against
`git rev-parse origin/main:bin/cc-dispatch`.

## 4 · The second lane — what this diff actually changes

`0efcc073` reached `bin/cc-dispatch` only. There is a second surface that composes cloud payloads,
and `bin/cc-offload` delegates its **whole** create to it (`bin/cc-offload:448,453` →
`handoff-fire.sh --cloud`):

```text
scripts/handoff-fire.sh   CLOUD_PAYLOAD   (line ~8039)
```

It has told cloud workers to run exactly the right two commands since `ca7db1a1` (2026-08-09),
refined by `3516251c` (2026-08-21) — **both before this row was filed on 2026-08-23**:

```text
── HOW TO RETURN YOUR WORK (this session runs off-box; read this before you finish) ──
    git switch -c <branch>
    git push -u origin HEAD
… Push whatever you have before you finish, even if the work is incomplete
```

**So §16's "nothing emitted it — no brief, no hook, no script" is true of the FIRST-ACT ping and
overstated about this file.** The commands were there; the *timing* was not. And the timing is the
entire contract:

> A completion-timed push cannot disambiguate absence **at all**. A VM that boots and dies, one that
> never booted, and one refused entitlement all reach the end with nothing to push — so all three
> produce no ref, and `classify()` files all three C1 NOT-STARTED. Only a push at t=0 separates
> "never started" from "started and produced nothing".

That is why the incumbent suite could not catch it: `tests/handoff-fire-cloud.bats` test 17 pins
`switch -c` **before** `push`, and stays green over a payload that asks for both at the very end.
Ordering was tested; timing was not.

This diff restructures the payload into two beats — a **BOOT PING** block ("your first act, before
you read anything else") carrying the same two commands and the reason they matter, then the
unchanged return rail, now pointing at the branch the ping already created. Per §16.1 it is a **bare
ref creation, never `commit --allow-empty`**: `reauthor_branch` replays a branch's commits with
`commit-tree` and replays an empty one happily, so an empty commit would put one content-free commit
on `main` per cloud fire. Eight of the nine stranded implementations of this row prescribed exactly
that.

**Safe only because the downstream half is already on trunk.** §16.2's arms — `cloud-reconcile.sh`
exit 66 (*nothing to land*) and `cloud-return.sh` reading 66 as a non-verdict — are what stop the
moved population (boot-and-die sessions, the majority) from generating a land-refused artifact, a
`LAND REFUSED` wake and open custody apiece. Without them this change would be a regression, which
is why it lands after them and not before.

## 5 · Verification

Baseline first, on the pristine tree in this venue, so every number below has a control:

```text
PRISTINE          handoff-fire-cloud 19/19 · cloud-reconcile 33/33 · cloud-return 45/45
                  bin/cc-dispatch selftest 180/180
WITH THIS DIFF    handoff-fire-cloud 23/23 (4 new arms) · payload lints 8/8, 15/15, 5/5
RED-PROOF         the 4 new arms on the PRISTINE script → 4 not ok, and incumbent test 17
                  stays GREEN — the proof that ordering-only coverage could not see this
shellcheck        scripts/handoff-fire.sh → 0 findings under the repo's .shellcheckrc
bash -n           clean
```

The four arms each fail on pristine for a different reason: `17b` no ping / no "first act"; `17c`
the ping does not precede the return rail; `17d` no prohibition on the empty commit; `17e` the ping
does not say what its absence is confused with.

**The gate's own scope, run in full, with a pristine control on every red.** The suite list is
`scripts/gate-select.sh --direct origin/main..HEAD` — 83 suites, the same selection `ship-land.sh`
will make:

```text
83 scoped suites   →   67 GREEN   ·   16 RED
```

Every one of the 16 was then re-run on a detached `origin/main` worktree
(`git worktree add --detach /tmp/pristine origin/main`) and **all 16 fail identically there, to the
same failing-test count**:

| suite | mine | pristine | | suite | mine | pristine |
| --- | --- | --- | --- | --- | --- | --- |
| `account-fact-derivation` | 1 | 1 | | `handoff-fire-stamp-daemon-path` | 1 | 1 |
| `cc-classify` | 68 | 68 | | `handoff-lifecycle-record` | 3 | 3 |
| `desk-invariant` | 3 | 3 | | `handoff-recycle-durable-cwd` | 2 | 2 |
| `fire-goal-disposition` | 1 | 1 | | `it2-wrapper` | 1 | 1 |
| `handoff-fire-account-sweep` | 1 | 1 | | `kitty-split-launch-stamp` | 1 | 1 |
| `handoff-fire-argv-launch` | 1 | 1 | | `spawn-presence` | 6 | 6 |
| `handoff-fire-capacity-gate` | 3 | 3 | | `teammate-auto-shutdown` | 2 | 2 |
| `handoff-fire-completion-push` | 2 | 2 | | `handoff-fire-kitty-daemon` | 1 | 1 |

**Zero failures attributable to this diff.** The population is what a reader should expect of this
venue rather than of this change — terminal/daemon suites (`it2-wrapper`, `kitty-*`,
`spawn-presence`, `teammate-auto-shutdown`, `handoff-fire-kitty-daemon`) that need a mac, an iTerm2
or a live pane, none of which exists on a Linux VM. This is the same "red on unmodified trunk *in
this venue*" class `d92d773c` measured and the predecessor reproduced; it is reported here rather
than filtered out, because a suite excluded from the run is indistinguishable from one that passed.

## 6 · Honest limits

- **The effect still cannot be observed from here**, exactly as the predecessor said of its own
  diff. What §3 adds is that the predecessor's prediction has now been *tested once and failed* —
  not because the ping is wrong, but because the dispatcher that fires never ran it. **A third
  implementation of this contract is not what this row needs; a converged `~/.claude` is.**
- **The `handoff-fire` lane's ping is unobserved for the same reason.** It is verified by suite, not
  by a ref appearing. The next `cc-offload` fire is the probe.
- **Whether this diff lands is not decided here.** Nine prior implementations of this row were full,
  tested diffs on nine branches and none reached trunk; if this strands too, the row's blocker was
  never the code, and the evidence is on the desk
  (`~/.claude/autonomy/cloud/<id>.land-refused`).
- **The 16 red suites are red on unmodified trunk in this venue**, proved by the control in §5 and
  reported rather than filtered. `cc-classify` (68/87) dominates the count; the predecessor found
  the general cause for this class in `cc-dispatch-v2` — a fixture pinning `A2_BASE_SHA=ec92e68c` as
  an "immutable ancestor of origin/main" that resolves in no fresh clone, not even after
  `--unshallow`. Whether `cc-classify`'s 68 share that root cause is **not established here**; only
  its non-attribution to this diff is.
- **This session pushed no boot ref of its own**, because its pre-cure brief never asked for one.
  The dogfood the predecessor performed from inside its VM is therefore not repeated here, and §3 is
  the reason — which is the finding, not an omission.

---

## 7 · Addendum, dispatch #14 (2026-09-04) — the sensor gap is NOT the shallow clone, and the depth numbers refute it from inside the VM

§3 and §18.3 of `CLOUD_OBSERVABILITY.md` attributed `bin/cc-premise`'s EVIDENCE AGE under-report to
**the VM's shallow clone**: *"the mechanism is visible from here and is the shallow clone, not the
query… `git log --since` silently answers over a truncated graph."* That attribution is **wrong**,
and this dispatch's own brief falsifies it without any desk access.

### 7.1 · The falsifying measurement

This container's clone arrived shallow at **depth 50** (root `8bbf1d9f`). The brief's EVIDENCE AGE
arm reported **2 commits** on `docs/plans/CLOUD_OBSERVABILITY.md` since the row's `first_ts`
(2026-08-23T21:26:48Z). A deepened clone (4,040 commits) answers **4**:

| commit | committed | depth from `origin/main` tip | in the brief? |
|---|---|---|---|
| `95ae4da9` | 2026-09-03T18:22:51Z | **36** | **no** |
| `0efcc073` | 2026-09-02T04:46:15Z | 85 | **no** — this is the cure |
| `da729350` | 2026-08-29T17:43:43Z | **201** | yes |
| `7a67b326` | 2026-08-29T07:08:04Z | 232 | yes |

**A depth horizon truncates by depth.** It cannot omit a commit at depth 36 while reporting one at
depth 201. The horizon is therefore not the filter; **recency** is. The two omitted commits are the
two newest, and the newest *reported* one predates the cure.

### 7.2 · Where the query actually runs, which is what the shallow-clone theory got wrong

`bin/cc-premise`'s arm is `git rev-list --count --since=<ts> origin/main -- <paths>`
(cc-premise:1333) and `git log --since=… origin/main` (:1336). It runs **on the desk, at brief-
compose time**, over the desk's `origin/main` ref — not in the container, and not over the
container's clone, which does not exist yet. `grep -n 'git fetch' bin/cc-premise` returns **nothing**:
the arm never fetches, so it reports whatever the desk's last fetch left behind.

So the under-report is a **stale ref on the desk**, and it bounds that ref precisely: at compose
time (fire stamp `20260903T234011Z`) the desk's `origin/main` was **at or after `da729350`
(08-29T17:43Z) and strictly before `0efcc073` (09-02T04:46Z)**.

### 7.3 · The same bound, derived a second and independent way, from the brief's missing rails

The brief carries none of three rails that are on trunk and are composed **unconditionally**:

| rail | landed |
|---|---|
| `BOOT PING` | `0efcc073` — 2026-09-02T04:46:15Z |
| `DISPATCHER VINTAGE` line | `f9cbe177` — 2026-09-02T02:15:02Z |
| the `--unshallow` staleness clause (`cc-dispatch:2910`) | `22b8824c` — 2026-09-01T20:58:52Z |

so the live `cc-dispatch` **bytes** predate `22b8824c` (09-01T20:58Z). The brief also hands a VM the
desk-absolute `git -C /Users/chrisren/…` prefix that `0efcc073` §16.3 removed, and names
`cc-backlog` / `cc-notify` for all three terminal dispositions — neither on `PATH` here, with no
`~/.claude/autonomy/` to write into.

**The two windows intersect at `[08-29T17:43Z, 09-01T20:58Z]` — one desk state, roughly three days
behind trunk, explaining the ref and the bytes together.** A *current* dispatcher would not have
produced this brief for a second reason: `refresh_trunk()` (`d877dc7e`, 2026-09-01T06:43:13Z) fetches
once per project per pass, expressly so downstream ref reads are current. Its absence is consistent
with bytes that predate it.

### 7.4 · What this changes about the cure

§18.1/§18.3 concluded *"the convergence gap and the sensor gap are the same defect — `--unshallow`
running too late or not at all."* The unification is right; the defect named is not. `--unshallow` in
the brief is a **worker-side** rail against a **worker-side** hazard (§7.1's own table shows it does
not touch this). The sensor gap is **desk-side and upstream of the brief**, so no clause added to the
brief can close it. Two candidate cures, in order of cost:

1. **The live layer converges** — the one cure for both halves at once. Settling read, still only
   available on the desk: `git rev-parse origin/main:bin/cc-dispatch` against
   `~/.claude/bin/cc-dispatch`, plus `git -C <desk repo> rev-list --count HEAD..origin/main`.
2. **`cc-premise` stops reading a ref it never fetched** — either a memoized fetch of its own, or
   ordering its arm after `refresh_trunk`. Not attempted here: it sits in the claim path of every
   wave row, `--sweep` already spends ~675 s over 466 declarations, and an unmemoized fetch per item
   would be a regression. Filed as the recommendation, not the diff.

**Honest limit.** The bound in §7.2/§7.3 is derived entirely from artifacts this VM can read (its own
brief, and trunk). It establishes *that* the desk was ~3 days stale and *when*; it cannot establish
**why** — an unfetched checkout, a `~/.claude/bin/cc-dispatch` that is a copy rather than a symlink,
or a pass composed from an older worktree remain indistinguishable from here, exactly as `c240e96a`
recorded. What is new is that the shallow clone is now **excluded** as the mechanism for the sensor
half, so a future session need not re-run that hypothesis.
