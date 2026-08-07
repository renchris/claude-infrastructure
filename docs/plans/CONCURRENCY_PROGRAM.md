---
status: open
---

# Concurrency program — driving the fleet to durability and completion

**Status:** briefed 2026-08-07. Evidence: `docs/research/concurrency-census-2026-08-07.md`
(same branch — read it first; every number below comes from there).

---

## Phase 0 — Agent Team orchestration

**Roster is deliberately SMALL, and the reason is the plan's own subject matter:** every teammate is
a session, every session costs ~511 MB plus its gate runs, and the fleet is already oversubscribed
at 14-on-10. A wave sized by task count rather than by capacity would worsen the exact condition
this program exists to fix. Spawn waves, not a fleet.

| # | member | track | writes | worktree | model / effort |
| --- | --- | --- | --- | --- | --- |
| 1 | `gate-contention` | **S2** | `scripts/ship-land.sh`, `scripts/postland-verify.sh`, reso `package.json` lint script | own worktree | Opus @ max |
| 2 | `backlog-triage` | **S3** mechanical pass | a triage report + `cc-backlog` state changes | none (read-only) | Opus @ high |
| 3 | `dispatch-scope` | **S4** | `launchd/com.claude.dispatcher.plist`, `bin/cc-dispatch` | own worktree | Opus @ max |

**Dependency graph** (strict — later members are unsafe before earlier ones complete):

```text
S0 (operator, 1 line)  ─┐
                        ├─→ everything below can LAND autonomously
S1 (push branches)     ─┘    …but S1 does not wait for S0

S2 gate-contention ──→ S3 backlog-triage ──→ S4 dispatch-scope
   (releases items)      (must precede         (drains what
                          the release)          triage approved)
```

**Spawn wave order:** wave 1 = member 1 alone (S2 is the unlock and touches the gate every other
member depends on). Wave 2 = members 2 and 3 in parallel once S2 is green — they share no file.

🚨 **Member 1 is a SOLE-OWNER track.** It edits the landing gate itself, so no other session may
land while it is mid-change. Serialise it, and re-run its own gate after every rebase.

**Not teammates:** S1 (one `git push` loop — no code), S5 (an entitlement check plus an operator
decision), and the S3 *durable* half (a premise-check clause added to the worker protocol, which
belongs to whoever owns that protocol, not to a parallel worker).

**The operator's goal:** grow from ~14 concurrent Claude Code sessions toward **~100**, with queued
work firing autonomously overnight.

---

## 0 · The bootstrap deadlock — why nothing is finishing

This is not a list of independent tasks. It is one cycle, and naming it fixes the ordering:

```text
many concurrent sessions
  → concurrent full-suite LANDING gates
    → gates SIGTERM-killed by contention (zero assertion failures)
      → the land fails → the item is recorded `blocked` — a DURABLE state needing a manual unblock
        → the dispatcher starves (8 open vs 323 blocked) and cannot drain overnight
          → work is done in interactive sessions instead
            → more concurrent sessions  ⟲
```

**Every exit from this cycle runs through LANDING, and landing is currently free but blocked by
mechanism rather than cost** (LAND_SHIP_V2, 2026-08-02: Amplify `autoBuild:False` on `main`, Path F
filters `refs/heads/release`; `/ship` bills nothing, only `/deploy` spends money).

🔑 **The single most load-bearing defect: a land killed by contention and a land that genuinely
failed are recorded in the SAME state.** 205 of 333 backlog items sit `blocked` on "the worker
cannot land" / "persistent thrash". One documents its gate SIGTERM-killed on all four attempts with
**zero test failures across ~1,700 green executions**. That conflation is what converts a transient
load spike into permanent queue rot, and no amount of unjamming helps while it stands.

---

## 1 · The critical path, in dependency order

Each step unblocks the next. Do not reorder — later steps are unsafe or impossible before earlier ones.

### S0 · Unblock agent-driven landing — OPERATOR, one line

`.claude/commands/ship.md` carries `disable-model-invocation: true` in its frontmatter. That is a
harness-level block: **no agent can fire `/ship` in ANY session**, whatever policy says. It was
correct before 2026-08-02, when `/ship` *was* the deploy and every land billed Amplify + Fly.
LAND_SHIP_V2 removed the cost and rewrote that file's prose to *"free and agent-driven"* — but left
the flag, so the documentation and the mechanism have disagreed since, and the mechanism wins
silently.

```bash
sed -i '' '/^disable-model-invocation: true$/d' .claude/commands/ship.md
```

**`deploy.md` KEEPS the flag and must** — that is where the money and the door-staff-visible change
live. Landing is not deploying; v2's whole point is two decisions, so they get two gates.

⚠️ An agent cannot make this change itself — removing the flag that stops the agent from invoking a
command is self-granting, and the permission classifier correctly refuses it.

**Until S0 lands, every track below terminates in a manual paste.** It is the keystone.

### S1 · Bank the stranded work — pure durability, needs no gate

`scripts/land-status.sh` reports **2,304 commits across 199 branches that exist on NO remote** —
"one disk failure from gone." This needs no lint, no dispatcher, no capacity: the commits are
already made. Pushing a **non-`main`, non-`release`** branch triggers nothing (both deploy triggers
watch other refs), so this is free and safe by construction.

Do this BEFORE S2/S3 — it is the only step whose value is unconditional, and the only loss that is
irreversible.

### S2 · Make the landing gate survive concurrency — the actual unlock

Two changes, in order:

1. **Discriminate killed-from-failed.** A gate run terminated by SIGTERM/timeout with **zero
   assertion failures** did not FAIL — it could not RUN. It must retry or defer, never flip an item
   to `blocked`. Same discrimination the fleet already learned about `nice`/`taskpolicy`
   (deprioritising re-specifies every wall-clock timeout inside a suite, so it does not slow
   gracefully — it fails). **Read the failure TEXT, not the exit code.**
2. **Stop N worktrees paying N cold full-tree lints.** reso's `pnpm lint` is
   `eslint src/ lib/ replicache/ --cache --cache-location .eslintcache` — the cache is
   **worktree-local**, so it never amortises across the fleet. Two concurrent runs at ~2.4 GB each
   were measured in different worktrees. Share the cache, or scope the gate to changed files.
   (Only then consider a faster engine — see the census §4 on why an oxlint port cannot be
   byte-identical.)

Optionally serialise full-suite gates fleet-wide (one at a time) — the backlog item that failed four
times prescribes exactly this in its own words: *"when the machine is quiet, run ship-land.sh."*

### S3 · Triage the backlog BEFORE unjamming it — safety precondition

🚨 **Do not release 205 items into an unattended overnight dispatcher.** A jammed queue is *inert*;
205 stale items dispatched at ceiling 6 while nobody watches is strictly worse. Measured staleness:

| signal | count |
| --- | --- |
| items whose own text says CORRECTION / superseded / RETRACTED / "is FALSE" / stale | **55** (16.5%) |
| distinct SHAs cited in premises — mechanically checkable | **127** |
| items dated 2026-07-26 → 07-31, the window the jam accumulated in | **89** |

55 is only the **self-declared** rate; an item silently superseded does not announce it. A live
example already in the store: `bbad96d163ab` exists solely to record that `23eccae755a9`'s central
claim is **false — a time-confounded comparison**. A worker claiming the latter today would very
plausibly roll back a version on a refuted premise.

**Mechanical first** (scriptable, no reasoning): resolve the 127 SHAs against `origin/main`
(landed / reverted / absent); pair the explicit `CORRECTION to backlog item <id>` references and
flag their targets; age-bucket; dedupe by title.

**Then the durable fix, which is not a sweep:** a **premise-check at CLAIM time** in the worker
protocol. A one-time review goes stale the moment it finishes — the same decay that produced this.
A work item's premise is a CLAIM, not a fact: it is written out of context by construction, facts
decay, and imperative voice reads as settled. Verify (`git log --all -- <path>`,
`git cat-file -e origin/main:<path>`, `npm view <pkg> version`) and **when the premise is refuted,
the disproof IS the deliverable** — write it back into the store, never silently close.

This track is **read-only and perfectly parallel** — 333 independent items, no worktree, no shared
file. It is the one piece of this program that fans out cleanly.

### S4 · Restore autonomous overnight drain

The dispatcher is healthy and starved, not missing: `com.claude.dispatcher`, `StartInterval` **300 s**,
`CC_DISPATCH_CEILING` **6**, admission `free_slots = max(0, CEILING − live_workers)`.

- After S2+S3 it drains on its own.
- ~~**Widen its scope.** `CC_DISPATCH_PROJECT="claude-infrastructure"` pins it to one project, so
  reso's **56** items and doc_classifier's **23** have no overnight path at all.~~
  **CLOSED 2026-08-07 — and this bullet's premise was ALREADY FALSE when it was written.** The
  widening landed in **`d249f460`** *(feat(dispatch): multi-project coverage — one queue, one
  ceiling, one lock)*, which is an ancestor of `origin/main`. It does not widen the env var: a
  `repo=` row in **`scripts/dispatch-projects.conf`** is unioned with `CC_DISPATCH_PROJECT`, so
  coverage is an agent action needing no plist edit and no `launchctl bootstrap` (C10). The plist's
  pin stays deliberately — a bad conf edit can never un-cover the incumbent.
- **Verified OPERATING in production, not merely landed** — live IDL pass `20260807T102125Z-3091`
  emitted real per-item verdicts for the foreign project: **3× `reso-management-app` `defer`
  (`at-ceiling`) + 1× `skip` (`already-done`)**. `at-ceiling` is the S2 ceiling, i.e. these items
  are *in the queue competing for slots* — the S4 symptom (no path at all) is gone; what remains is
  S2's throughput problem, which is a different track.
- **Residual leak found and closed: the label, not the mechanism.** One item sat under project
  `reso` — an alias hand-passed as an explicit `cc-backlog add --project reso` (source
  `wave7-close-2026-08-07`); `~/Development/reso` does not exist. It was journalled
  `{verdict:"skip", reason:"project-not-dispatched"}` on every pass and could never drain. Migrated
  `333aed941b6b` → **`0c9d92ba9a0a`** under `reso-management-app` (a mislabel is not a retraction —
  closing it would have destroyed a live OrderBar clipping defect), and `reso` declared in the conf
  as NEVER-DISPATCHABLE. Post-state: **`reso` open=0 · reso-management-app 59 · doc_classifier 23**,
  all inside the dispatch set; the dispatcher's uncovered-project warning is silent.
- ⚠️ **Why the premise went stale, and the generalisable trap.** This bullet's counts (56 / 23)
  matched the ledger almost exactly (58 / 23) — a *true metric beside a refuted cause*, which reads
  as corroboration and is the most persuasive way to be wrong. The fix had landed from a **sibling
  stream** between filing and dispatch; open item `0c5d47c863bf` is precisely "nothing re-checks
  whether an open item's requested fix already landed from a sibling". Check a work item's
  **remedy** against `origin/main` before building it, not just its symptom against the world.
- **Do not rebuild what exists**: `cc-backlog` / `cc-queue` / `cc-dispatch` are the sanctioned store,
  queue and dispatcher, and `com.claude.devserver-gc` already reaps dev servers — find out why five
  survived it before writing another. *(This warning earned its keep: the S4 remedy was already
  built, landed and running — searching the graveyard first is what turned a rebuild into a
  20-line declaration.)*

### S5 · Scale beyond this box — the only route to ~100

**100 local sessions is arithmetically unreachable**: 511 MB/session × 100 = **51.1 GB of 64 GB**,
before dev servers, before a 2.4 GB eslint, before macOS and a browser. No display-layer change
touches this — tmux saves ~0.6 cores and 0.6 GB (~2%) and costs a rewrite of the whole iTerm2-based
session lifecycle; a session switcher saves nothing if it is a view over the same processes.

So: **route repo-only work off-box.** Entitlement for remote/cloud execution is per-account and
gated — check `/accounts`, never assume. Viability is split (census §5): repo-only work ✅ · visual
design ❌ (needs the local browser + dev server) · anything about this box ❌ · branch banking ⚠️
(the 199 branches exist only here, which is the whole problem).

Cheap local wins meanwhile: **consolidate to one terminal emulator** (kitty *and* iTerm2 are both
running — 27% of a core), and stop dev servers when idle (1.9 GB each, five up).

#### S5a · The comms prerequisite — LANDED (backlog `5341a9e5fc4d`, 2026-08-07)

"Route repo-only work off-box" was blocked on something the census did not price: **the entire 2-way
comms stack is local-filesystem-only, and a sandbox can reach none of it.** Not "is awkward from" —
*cannot reach*. `cc-notify` appends to `~/.claude/mailbox/<pane-uuid>.md`; the session registry is
`~/.claude/cc-registry/<pane>.json` whose liveness signal is `kill -0` on a **local pid**;
`cc-backlog` is one untracked local JSONL; `cc-dispatch` spawns an **iTerm2 pane** via
`handoff-fire.sh`. None of them has a network transport of any kind. A cloud worker could not see
work, claim it, report it, or talk to a peer.

**Built: `bin/cc-bus` + `bus/`** — git as the bus, because it is the one channel a sandbox is
designed to reach, and because cloning the repo delivers the transport *and* the CLI in one
operation (nothing to install, no endpoint to authenticate beyond the remote it already has).

The load-bearing design property is the **one-writer law**: every file under `bus/actors/` has
exactly one writer, so shards cannot conflict. Measured with a positive control before the tool was
written, and pinned in `tests/cc-bus.bats`:

```text
two actors appending to ONE shared file  →  git pull --rebase  rc=1, CONFLICT
two actors appending to their OWN files  →  rc=0, clean merge, push OK, fold intact
```

State is the FOLD over all shards, last-transition-wins — the semantics `cc-backlog` already uses,
so this changes *where* records live and *how* they are partitioned, not what a record means.

**Two decisions worth not re-litigating:**

- **No wholesale migration.** The item said "move backlog + messages + session registry into the
  repo". Rejected on two independent counts. (1) *Publication* — the default bus is this repo, this
  repo is PUBLIC, and git history is not retractable; dumping 4,836 ledger records and 1,500+
  mailbox messages of the operator's back-traffic into it is not a transport change. (2)
  *Relevance* — a cloud worker needs the one item it was sent to do, and the registry is pane-uuid
  and pid keyed, so those rows cannot mean anything off-box even if copied. An item crosses when
  someone `offer`s it; a result crosses when a worker reports it; nothing crosses implicitly.
  `emit` enforces the publication rule on the write path: `$HOME` → `~`, and a secret-shaped record
  is **refused** (exit 3, nothing written), never silently redacted.
- **The claim stays local.** Complementary work under this same DoD ref
  (`docs/research/cloud-observability-2026-08-07.md`, backlog `191d4d056c98`) establishes that both
  local liveness oracles return *confident, wrong* verdicts about an off-box worker — so a cloud
  worker holding a **local** claim gets its item reopened and handed to a second worker. The bus
  avoids this by construction: a cloud worker claims on the **bus**; the local session that offered
  keeps the local claim. That is the "local proxy is the ledger participant" shape that doc
  prescribes, so the two designs compose rather than collide.

**Boundary with `refs/cc/*`:** that sibling design carries *liveness* (heartbeat/progress) over a
ref namespace — high-frequency, and it must NOT enter history. This bus carries *messages and work
transitions* — low-frequency, and the record trail IS the audit. The bus therefore has no heartbeat
kind, deliberately, so it never becomes a second and worse liveness oracle.

**The cloud environment, verified — three facts that FORCED the shape** (Anthropic's
cloud-environments docs + the shipped `sdk-tools.d.ts` + the changelog, 2026-08-07):

1. **A cloud VM has no `~/.claude`.** Only the repo's own `.claude/` arrives, since it is part of the
   clone; user-scope CLAUDE.md, skills, agents, commands and MCP servers do not carry over. So
   shipping the CLI *in the repo* is not tidiness — anything under `~/.claude/bin` is unreachable
   there by construction.
2. **GitHub Issues — the item's own alternative carrier — is refuted.** `gh` is not preinstalled and
   `GITHUB_TOKEN` reads as the literal placeholder `proxy-injected`. Recorded so it is not
   re-proposed.
3. **The channel is ASYMMETRIC.** here→cloud is a full git remote (clone/fetch unrestricted, and the
   VM clones from the *pushed* remote, not local disk — `sdk-tools.d.ts` L3764). cloud→here is a
   **one-branch pipe**: the GitHub proxy's push protection allows `git push` only against that
   session's own working branch. An off-box worker's records therefore cannot reach trunk by its own
   action, which is why reading the bus is `sync --gather` + `fold --refs` (read *out of* refs, never
   copied into the tree — copying another actor's shard would be the cross-write the one-writer law
   forbids).

⚠️ **This lands on the `refs/cc/*` heartbeat design and is the next experiment to run.** Whether push
protection is enforced per-*branch* (leaving `git push origin HEAD:refs/cc/…` a loophole) or
per-*refspec* (blocking it outright) is settled by no doc, changelog entry, or binary string. If
per-refspec, `refs/cc/*` cannot be written from a cloud VM at all and O1 must become a working-branch
commit — the shape that design rejected — or leave git. One `--cloud` session and one attempted ref
push decides it. This bus does not depend on the answer; that design does.

**What this does NOT establish.** Cloud entitlement is per-account and remains unverified — the same
limit §7 of the sibling doc records. Measured on this box: `hasRemoteEnvironment: true` appears in
`~/.claude-quaternary/.claude.json` (**account 4 only**; absent for accounts 1–3), and
`remote.defaultEnvironmentId` is absent everywhere, so `/remote-env` has never been run. Whether that
key means *entitlement* or merely *an environment record exists* is unverified, as is the org's
`allow_remote_sessions` policy (the binary carries `allow_remote_sessions policy denied` as a live
error path). `--cloud` is a real hidden flag on v2.1.220 and refuses without a TTY. This is the
prerequisite that must exist *before* cloud execution is used; it is not evidence that cloud
execution is available. Latency is push/pull, not poll: nothing arrives until someone syncs.

---

## 2 · What is NOT on this path

Recorded so they are not re-proposed:

- **A byte-identical oxlint/oxfmt/oxc port** of reso's eslint config. Rejected on categorical
  grounds, not effort — census §4. The 78 airbnb stylistic rules are a category mismatch with a
  formatter, and the 13 plugin/custom rule-uses (`@pandacss`, `reso-design`, tailwind) have no
  eslint-plugin ABI. Those 13 are precisely the ones that bite in practice.
- **A frontier-tier (Fable) session** for any of this. Every open question here is answerable by
  measurement, and the two that looked frontier-shaped dissolved once measured (the "load average
  is the wrong metric" hypothesis was built on a misreading; the oxlint question is a coverage audit).
- **`nice` / `taskpolicy` / QoS throttling** to shed load — it re-specifies every wall-clock timeout
  and fails suites rather than slowing them.
- **Building a second queue.** S4.

---

## 3 · Sequencing note

S0 is the operator's, and gates the automation of everything else. **S1 is independent of S0** and
should not wait for it — it is pure loss-avoidance and needs no gate. S2 → S3 → S4 is a strict
chain: contention-fix RELEASES the items, so triage must exist before the release, not after. S5 is
parallel to all of it and is the only track that changes the ceiling rather than the throughput.
