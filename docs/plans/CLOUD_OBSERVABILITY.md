---
status: open
---

# Cloud-session observability — the observable set, designed before the first fire

**Status:** designed + instrument landed 2026-08-07. Owns the observability half of
`docs/plans/CONCURRENCY_PROGRAM.md#s5-scale-beyond-this-box-the-only-route-to-100`.
Instrument: `bin/cc-cloud`. Suite: `tests/cc-cloud.bats`.

Every number in this document was measured on this box on 2026-08-07 and carries its command in
§7 so it can be re-measured rather than believed. Two of them are already known to be version- or
account-scoped and **will** rot; §7 says which.

---

## Phase 0 — Agent Team orchestration

**No teammates for the work in this document, and the reason is structural, not a sizing call.**
The design + the reconciler is one file plus its suite, written by one session. The follow-on
(§5.2) is three edits to three *live* actuators, one of which archives teams on a false verdict —
that work is serialised behind an entitlement fact that does not yet exist (§6), so a wave spawned
now would be a wave spawned against an unanswerable question.

When §5.2 does become live, it is **three teammates, one per liar**, no shared file, each
self-verifiable against its own suite:

| # | member | writes | worktree | why it is safe alone |
| --- | --- | --- | --- | --- |
| 1 | `spawn-verify-abstain` | `bin/cc-spawn-verify`, `tests/cc-spawn-verify.bats` | own | read-only verdict; no actuation |
| 2 | `board-offbox-column` | `bin/cc-board`, `tests/cc-board.bats` | own | render-only |
| 3 | `orphan-reaper-abstain` | `scripts/team-orphan-reaper.sh`, `tests/team-orphan-reaper.bats` | own | **destructive** — archives teams; lands last, alone |

Member 3 is a sole-owner track. It is the only one of the three whose failure mode destroys state.

---

## 1 · The problem, stated so the ordering is forced

A session inside an Anthropic-managed VM shares no kernel, no filesystem and no terminal with this
box. Every instrument the fleet is built on is therefore blind to it: `ps`, `lsof`, `kill -0`,
`launchctl`, load average, `vm_stat`, `~/.claude/cc-registry`, `~/.claude/cc-beats`,
`/tmp/cc-telemetry`, and the iTerm2 pane UUID.

**Blindness is not the hazard. Most of the stack goes silent, and silence is survivable.** The
hazard is that three components do not go silent — they convert *"not on this box"* into *"dead"*:

| Component | Line | What it does with a healthy cloud session |
| --- | --- | --- |
| `bin/cc-spawn-verify` | `:89-97` | argv scan of the **local** process table ⇒ exit 1 `ABSENT`, "Died, or never launched". Callers are told at `:24` to branch on that three-state vocabulary. |
| `bin/cc-board` | `:126-141` | a registry row with no local telemetry whose pid fails `kill -0` prints as **`DIED-UNRENDERED`** — a fabricated death verdict from a pid that is simply not on this box. |
| `scripts/team-orphan-reaper.sh` | `:61-70` | treats a failed `kill -0` as *"POSITIVE evidence of death"* and **archives the team**. Destructive, on a 600 s launchd timer. |

A fourth is a false negative rather than a false positive, and it is the one that hides the other
three: `bin/cc-reaper`'s blind-spot detector (`:27`, `:455`) compares enumerated sessions against
**local** `ps` panes, so it reports the fleet as fully enumerated while N cloud sessions burn quota.

This is why the observable set is designed **before** firing rather than after. A false death is
not recoverable by looking harder — by the time you look, member 3 has already archived the team.

**And there is a second, harder reason.** Attribution cannot be retrofitted. A cloud session that
was never declared and pushed nothing leaves *zero* trace anywhere this box can read: no transcript
under `~/.claude/projects`, no registry row, and no backlog write — `cc-backlog`'s store is
`~/.claude/autonomy/backlog.jsonl` and `git ls-files autonomy/` is **0**, so the store is not in the
repo and a cloud VM cannot reach it at all. **A cloud session cannot close its own backlog item.**
There is no forensic path back from an undeclared fire. The declaration has to exist at fire time
or the session is permanently unobservable.

---

## 2 · The observable set

Five observables, all read from the repo side, all read-only, none requiring anything of the VM
except that it pushes.

| # | Observable | Sensor | Proves | Granularity | Verified |
| --- | --- | --- | --- | --- | --- |
| **O1** | remote ref exists | `git ls-remote --heads <remote> <branch>` | the VM booted, had network + auth, and got far enough to push | one event | ✅ 0.43–0.51 s, no fetch |
| **O2** | remote ref **advances** | O1's sha vs the stored last-seen | progress — **the only heartbeat that exists** | per push | ✅ |
| **O3** | `Claude-Session:` trailer | `git log --format='%(trailers:key=Claude-Session,valueonly)'` | *which* cloud session produced a commit, plus the URL to open it | per commit | ⚠️ version-gated — §7 |
| **O4** | landed on trunk **by content** | `git ls-tree <trunk> -- <path>` | completion | terminal | ✅ reuses `scripts/land-verify.sh:56-69` |
| **O5** | PR state | `gh pr list --head <branch> --json state` | a durable review-side handle; `claude --from-pr` resumes a session from it | poll | ✅ `gh` 2.96.0 authed, `repo` scope |

**O4 is by CONTENT, never by count.** `rev-list --count` reads 0 after a sibling rebase and proves
nothing — this repo lost a commit to exactly that misreading (incident 2026-07-11, `.claude/CLAUDE.md`).

**O3 is the one the product gives us for free, and it is the one most likely to rot.** The trailer
is emitted by Claude Code itself, on by default, for precisely the off-box surfaces this document
is about. From the 2.1.220 binary's own settings help, verbatim:

> Whether to append the claude.ai session link to commits and PRs created from web or Remote
> Control sessions (default: true). Set to false to omit the Claude-Session trailer and PR-body link.

It is **absent from the pinned 2.1.114 binary the launcher actually runs** (§7). `bin/cc-cloud`
therefore *measures* the gate (`trailer_supported()`) rather than assuming it — a design that
hardcoded "the trailer is available" would be wrong on the very binary the fleet uses.

---

## 3 · What is NOT observable — recorded so it is not re-proposed

- **Every local process/host instrument.** `ps`, `pgrep`, `lsof`, `kill -0`, `launchctl`,
  load average, `vm_stat`, `sysctl`. Not merely useless — actively wrong (§1).
- **Everything under `~/.claude/**` and `/tmp/**`.** `cc-registry`, `cc-beats`, `cc-telemetry`,
  `backlog.jsonl`, `land.log`, the postland stamps, the land lock. All home- or `/tmp`-rooted; a
  cloud VM shares none of them.
- **`.git`-local and local-ref-only artifacts.** The `gate-green` marker lives in
  `$(git rev-parse --git-common-dir)`, and `ship/backup-*` refs are never pushed. A land's *only*
  pushed artifact is the commit itself.
- **iTerm2 / kitty pane identity.** No terminal exists.
- **The `Session-Id:` / `Land-Session:` trailer as a *cloud* signal.** The convention, its
  structural reader (`scripts/stranded-sweep.sh:60`) and its aggregator (`bin/cc-value:160`) all
  exist, but the **producer was never built**: 0 of the last 200 trunk commits carry it. Reviving
  it is worthwhile for local attribution and is a smaller change than inventing a signal — but it
  is orthogonal to this document, because O3 already carries cloud attribution and is emitted by
  the product rather than by us.
- **The web UI (claude.ai/code).** Real, and the only place a cloud session's transcript can be
  read — but **operator-only**. Neither binary on this box exposes a cloud-session query verb
  (§7), and there is no public REST API for web sessions. It is an *escalation path*, never an
  automation input. That is why every alarm row `bin/cc-cloud` emits carries `open <url>` as its
  `recover_cmd`: the honest recovery is a human opening a browser.

---

## 4 · The absence contract, and the state function

### 4.1 Absence is ambiguous, and only a contract fixes it

A declared cloud session that has pushed nothing is indistinguishable from one that never started,
one that died at boot, and one that was refused entitlement. All four read as "no ref". There is no
inbound channel to a cloud VM, so this cannot be resolved by asking.

It can only be resolved by **contract**: the fire declares a branch and a boot budget, and the
session's brief requires its **first act** to be pushing that branch — an empty commit is enough.
Absence then becomes informative: no ref inside the budget is `BOOTING` (expected); no ref past it
is `NOT-STARTED` (actionable — re-fire, or check entitlement).

### 4.2 The discriminator the whole design rests on

Measured, not assumed:

```text
git ls-remote, remote REACHABLE + ref absent   → rc=0,   empty stdout
git ls-remote, remote UNREACHABLE              → rc=128, empty stdout
```

**Both are empty.** A `[ -z "$out" ]` test conflates them, and that conflation would convict a live
cloud session as `NOT-STARTED` on a wifi blip — the same shape of defect as reading a lookup miss
as an absence. The exit code is the only discriminator; `rc != 0` yields `UNKNOWN` and never a
verdict.

### 4.3 The state function

Total, first match wins, every arm terminal — the shape `bin/cc-fleet` uses, so one fault emits
exactly one row and `bin/cc-blockers` can consume it unchanged.

| Arm | Condition | Row? |
| --- | --- | --- |
| **U0 UNKNOWN** | a sensor could not run (`ls-remote` rc≠0, unreadable declaration) | no row; `--table` says UNKNOWN; **`--check` fails** |
| **C1 NOT-STARTED** | no ref, past `declared_at + boot_s` | ROW |
| **C2 BOOTING** | no ref, inside the boot budget | no row |
| **C3 LANDED** | every declared path content-present on trunk | no row |
| **C4 STALLED** | ref exists, sha unchanged past `stall_s` — **sidecar history required** | ROW |
| **C5 ALIVE** | ref exists and advanced inside the budget | no row |
| **C6 ABANDONED** | ref exists, not landed, past `life_s` | ROW |

Two orderings are load-bearing:

- **C3 precedes C4.** A finished session stops pushing *on purpose*. STALLED-first would alarm
  forever on every successful cloud session — an alarm that always fires carries exactly as many
  bits as one that never fires.
- **C4 requires history, and abstains without it.** The sidecar records "sha X was first seen at
  T"; only `cc-cloud poll` writes it. With no history there is no evidence the sha ever differed,
  so no verdict is available and none is invented.

`--json` / `--table` / `--check` are pure reads; `declare` / `retire` / `poll` are the only
mutators, and they write only under `CC_CLOUD_STATE`. Nothing fetches, and nothing writes a git ref.

---

## 5 · What is built, and what is deliberately not

### 5.1 Built and green — `bin/cc-cloud`

```text
cc-cloud preflight [--repo P] [--branch B]   can a fire HERE be observed at all? exit 1 = no
cc-cloud declare --id <id> --branch <b> [--remote --repo --paths --trunk --url --surface --item --boot --stall --life]
cc-cloud retire  --id <id>
cc-cloud poll                     the ONLY mutator of the heartbeat sidecar
cc-cloud is-offbox <id>           exit 0 iff declared and not retired — the abstain lookup
cc-cloud show <id>
cc-cloud list [--json]            the declaration inventory from DISK — no probe, no network
cc-cloud --json | --table | --check | --selftest
```

**One tool, not two** (backlog `163676679912`, 2026-08-07). `bin/cc-cloud-watch` was an independent
implementation of this same observable set, written by a second session of the 9-way dispatch storm
on `191d4d056c98` and landed in the same commit (`07f9707c`). It has been deleted, because two
tools reading one observable set drift and a caller cannot tell which is authoritative. Three things
it had and this one did not were migrated in; nothing else was lost, and the verb map is recorded in
`bin/cc-cloud`'s own header so it survives this document:

- **`preflight`** — the executable form of this document's own §8 rule. Its load-bearing refusal is
  an **unpushed branch**: a cloud VM clones from the *remote*, so local-only work is invisible to it
  and the session silently runs against the default branch instead. Measured 2026-08-07, §7: origin
  carried **1** head against **286** local branches with no upstream, so the failing case is the
  overwhelmingly likely one. Corroborated independently by backlog `6be74142f98d` reading the
  2.1.220 binary — cloud agents require a GitHub remote and cannot see an unpushed local branch.
- **`list`** — the inventory, disk-only. It departs from the tool it replaces on purpose: that one
  replayed a stored `lastVerdict` labelled "last known", but every arm of §4.3 is a function of the
  **clock** as well as the sha, so BOOTING becomes NOT-STARTED with no new observation at all. A
  replayed verdict is not stale-but-directional; it is wrong in the direction that reads as healthy.
  `list` therefore reports only what does not decay — what was declared, and what was last observed.
- **the fire-time baseline** — `declare` now probes once and records the sha the branch held *before*
  the fire. §4.3's C1/C2 keyed on "no ref", so a declaration onto a **re-used branch name** read C5
  ALIVE from the instant it was made and stayed silent for the whole `life_s` budget (6 h) — the
  likeliest real failure, a session that never boots, hidden behind a green verdict. "Produced
  nothing" is now `sha == base_sha`, which takes the same two arms. It is checked **after** C3 for
  the same reason C3 precedes C4: a session whose content is on trunk is finished, and how its ref
  moved has stopped being a question worth alarming on. The baseline is MEASURED, never assumed — if
  the fire-time probe could not run, no `base_probe=ok` is written and the arm abstains entirely,
  which is §4.2's law one level down.

Its verdict vocabulary maps onto §4.3 with nothing dropped: `nofetch`→U0, `waiting`→C2/C5,
`fresh`→C5 after a poll advance, `dark`→C1/C4/C6, `retired`→retired. Its suite was absorbed into
`tests/cc-cloud.bats` (22 tests).

Row schema, matching `bin/cc-fleet`'s frozen shape:

```json
{"kind":"cloud-session","state":"<S>","detail":"<ascii, <=44 bytes>","subject":"<id>","recover_cmd":"<paste-ready>","ts":<epoch>}
```

`state ∈ NOT-STARTED|STALLED|ABANDONED`. Consumers must filter on `.kind` only, never on the
`.state` enum, so a state added later still reaches the operator instead of being silently dropped
(`bin/cc-blockers:921-922`).

### 5.2 Built as a primitive, NOT yet wired — the three liars

`cc-cloud is-offbox <id>` exists precisely so §1's three components can abstain instead of convict.
**It is not called from any of them yet, and that is a deliberate stop, not an oversight.**

The wiring is gated on a fact that does not exist yet: **no cloud session can be fired from this box
today** (§6). Editing three live actuators — one of which archives teams — against an unanswerable
entitlement question would be changing a destructive path for a hazard that is not live. The moment
§6 resolves, §5.2 becomes the blocking prerequisite to the first fire, and Phase 0 above is its
roster.

Filed as backlog work, not left as a recommendation to a future reader.

### 5.3 Not built, and why

- **A launchd poller for `cc-cloud poll`.** Correct eventually; premature now. With zero
  declarations it would be a job whose every run is a no-op, and this repo already carries 10 dark
  labels it is trying to reduce. It becomes a one-line `fleet.manifest` declaration the day a real
  cloud session is declared.
- **A `gh`-based O5 poller.** O5 is specified and its dependency is verified, but PRs are not part
  of this repo's flow today (`origin` carries exactly one branch, `main`); building a poller for a
  workflow nobody uses would be inventing the observable rather than observing.

---

## 6 · The open question this design does not close

**Whether a cloud session can be fired from this box at all is unresolved, and it is the operator's
to resolve.** Measured 2026-08-07: neither the pinned 2.1.114 binary nor the 2.1.220 binary exposes
a `--cloud` verb. What 2.1.220 does expose is `--bg/--background` (a **local** background agent),
`--remote-control`, `--from-pr`, `agents --json`, and `ultrareview` (cloud-hosted, but a review, not
a work session). Entitlement for cloud/remote execution is per-account and gated
(`CONCURRENCY_PROGRAM.md` §S5), and `/accounts` is the check — never an assumption.

This does not weaken the design; it is the reason for its timing. The observable set, the absence
contract and the abstain primitive all have to exist **before** the first fire, and they now do.
The first real cloud session is the validation — and until one runs, this instrument has never been
exercised against a real cloud VM. It has been exercised against real `git ls-remote` behaviour
(§7), which is the part that decides whether it lies.

---

## 7 · Measurements — with their commands, so they can be re-measured rather than believed

All taken 2026-08-07 on this box.

| Fact | Value | Command | Decay |
| --- | --- | --- | --- |
| `ls-remote` absent-vs-unreachable | rc=0 vs **rc=128**, both empty | `git ls-remote --heads <remote> refs/heads/nope; echo $?` | stable (git semantics) |
| `ls-remote` cost | 0.43 / 0.50 / 0.51 s | `/usr/bin/time -p git ls-remote --heads origin` | network-dependent |
| remote branch count | **1** (`refs/heads/main`) | `git ls-remote --heads origin` | changes on first cloud push |
| local branches with no upstream | **286** | `git for-each-ref --format='%(refname:short) %(upstream:short)' refs/heads \| awk '$2==""'` | grows daily |
| `gh` availability | 2.96.0, authed `renchris`, scopes incl. `repo`, `workflow` | `gh auth status` | token can expire |
| `Claude-Session:` in **2.1.220** | present (default on, web + Remote Control) | `strings -a <bin> \| grep -c Claude-Session` → 5 | ⚠️ version-scoped |
| `Claude-Session:` in **pinned 2.1.114** | **absent** | same, control `ultrareview` → 48 | ⚠️ version-scoped |
| `Claude-Session:` on trunk | 0 of last 200 | `git log origin/main -200 --format='%(trailers:key=Claude-Session,valueonly)'` | 0 until a cloud session lands |
| `Session-Id:` on trunk | 0 of last 200 | same, key `Session-Id` | producer never built |
| cc-backlog store tracked? | **0 files** | `git ls-files autonomy/` | stable |
| `--cloud` verb | absent in 2.1.114 **and** 2.1.220 | `claude --help` | ⚠️ changes with the binary |

⚠️ **The two binary-scoped rows are the ones to distrust first.** A grep over a binary is only
evidence if the grep can find anything at all: the first attempt at this measurement returned
`0` for every pattern because it was pointed at a path that did not exist. Every row above that
says "absent" was taken with a **positive control in the same command** (`ultrareview` → 48/96
hits). Re-measure with a control, or do not re-measure.

---

## 8 · The fire-time protocol

Before any cloud session is fired, in this order:

1. `cc-cloud declare --id <id> --branch <b> --paths <what it will land> --url <session url>` —
   an undeclared cloud session is unobservable, and `declare` refuses without `--id`/`--branch`.
2. The session's brief must require **pushing the declared branch as its first act**, so that
   absence past the boot budget means something (§4.1).
3. §5.2 must be wired first — otherwise `com.claude.team-orphan-reaper` may archive the team
   while the session is healthy.
4. On completion, `cc-cloud retire --id <id>` — or let C3 `LANDED` render it silent, which it does
   by content, not by count.
