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

**EXECUTION LOCUS PER WAVE** (added 2026-08-07 — the field was absent, so every wave silently
defaulted to the lead's own context):

| Wave | Locus | Why |
| --- | --- | --- |
| W1 · unblock the fire path (§6.7) | **L** lead-inline | Not code: two operator web actions plus a re-measure. Nothing to fan out — it is one `claude --cloud` retry and one command block. |
| W2 · validate against the first live session (§6.7's five unproven claims, §9.4) | **L** lead-inline | Serial by nature: all five claims address ONE session id, and the session is short-lived. Fanning out would race five workers onto one subject. |
| W3 · §5.2, the three liars | **S** dispatched session | The default. Three actuator edits + three suites; none of it is judgment the lead needs to retain, and member 3 is destructive — it should not share a window with the deciding work. |
| W4 · §9's off-box `cc-notify` arm | **S** dispatched session | Implementation over a settled design; blocked on W2. |

**Lead context budget:** W1+W2 are cheap reads and one fire — hold ≥50% for W3/W4 dispatch and for
adjudicating the bundle-vs-clone contradiction (§6.5), which is a judgment call, not a measurement.
**Succession point:** after W2 records its verdicts in §7 — everything past that is
disk-reconstructible from this doc, so a successor loses nothing.

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

> ✅ **§6's headline question is CLOSED as of 2026-08-08: a cloud session CAN be fired from this box,
> programmatically, and one was** — `claude --cloud "<desc>"` → `session_01CHQoFxvsoDQ9KgJFSLrKno`
> (§6.5), with the headless send arm proven to deliver into it (§6.3). The section is kept whole
> because it is the record of how three wrong answers were reached and corrected; read the ✅/🔧
> markers as the current state and the struck-through text as history.

~~**Whether a cloud session can be fired from this box at all is unresolved, and it is the operator's
to resolve.**~~ ~~Measured 2026-08-07: neither the pinned 2.1.114 binary nor the 2.1.220 binary exposes
a `--cloud` verb.~~ **← SUPERSEDED 2026-08-07 (later same day); see §6.1. The verb DOES exist on
2.1.220 — it is HIDDEN, and `--help` is structurally incapable of showing it.** What 2.1.220 does
expose is `--bg/--background` (a **local** background agent), `--remote-control`, `--from-pr`,
`agents --json`, and `ultrareview` (cloud-hosted, but a review, not a work session). Entitlement for
cloud/remote execution is per-account and gated (`CONCURRENCY_PROGRAM.md` §S5), and `/accounts` is
the check — never an assumption.

This does not weaken the design; it is the reason for its timing. The observable set, the absence
contract and the abstain primitive all have to exist **before** the first fire, and they now do.
The first real cloud session is the validation — and until one runs, this instrument has never been
exercised against a real cloud VM. It has been exercised against real `git ls-remote` behaviour
(§7), which is the part that decides whether it lies.

📌 **Still true after 2026-08-08, and worth stating precisely so the ✅ above is not over-read.** A
session was *created* and *messaged* — the **fire path** is validated. `cc-cloud`'s own observables
(O1–O5, the state function, `declare`/`poll`/`is-offbox`) were **not** run against it, so *this
instrument* remains unexercised against a real cloud VM. Fire-path proven ≠ instrument validated;
§9.4 steps 3–5 are what close the second one.

### 6.1 · The `--cloud` verb DOES exist — and how a controlled measurement still missed it

The claim struck through above, and `CONCURRENCY_PROGRAM.md` §S5a's rival claim that "`--cloud` is a
real hidden flag on v2.1.220 and refuses without a TTY", were re-measured against the actual binaries
2026-08-07. **Both were partly wrong, and the disagreement was never a disagreement — it is a version
split plus one shared mis-reading.**

| Binary | `--cloud` | Evidence |
| --- | --- | --- |
| **2.1.114** (pinned stable) | genuinely **absent** | `error: unknown option '--cloud'` — identical to the bogus-flag control |
| **2.1.215 · 2.1.219 · 2.1.220** | **present, HIDDEN** | `Error: --cloud cannot be combined with --print.` — a *semantic* refusal, where the control gets `unknown option` |

So §6's "absent" was **correct for 2.1.114 and wrong for 2.1.220**; §S5a's "hidden on 2.1.220" was
correct. Anthropic's shipped docs, which document `--cloud` as supported with `--remote` as its
deprecated alias, agree with the binaries — and the alias is confirmed here, because `--remote`'s
refusal names `--cloud`.

🚨 **Why §7's positive control did not save this row, which is the transferable lesson.** The
measurement was `claude --help | grep`, with `ultrareview → 48 hits` as the control. That control is
real and it did its job: it proved **the grep could find something**. It could not prove **the
instrument could see the subject's class** — and `--help` cannot, *by construction*, because a hidden
flag's defining property is being omitted from `--help`. The control was placed on the pipeline's
last stage while the blindness sat in its first. **A positive control must be able to fail in the
same way the subject would** (`[[verification-harness-vacuous-pass-traps]]`): here that means a
control that is *itself a known hidden flag*, or dropping `--help` for a probe that reads the
parser — which is what the table above does, discriminating `unknown option` from a semantic refusal.

### 6.2 · `--cloud` is a POLYMORPHIC argument — and that is what manufactured "refuses without a TTY"

`--cloud` takes one argument and **branches on its shape**:

```text
claude --cloud "<free text>"          → CREATE a new cloud session; the text IS the task description
claude --cloud <id-shaped>            → address an EXISTING session  (id ≈ ^(session_|cse_)[A-Za-z0-9_]+$)
```

Measured: `session_abcDEF123`, `session_abc_def`, `cse_abcdefgh` all take the **existing-session**
path; `session_abc-def` does **not** — a single hyphen drops it back to the create path, where it is
read as a task description. `claude --cloud` with no argument says
`Error: --cloud requires a description.`, which is the create path naming itself.

**This is the trap.** A mis-shaped session id does not error as a bad id. It silently becomes a
*description*, and the create path then refuses `--print` with
`Error: --cloud cannot be combined with --print. Cloud sessions are interactive only.` — a message
about the wrong path entirely. That refusal, read as though it were about the id you passed, is
almost certainly the origin of §S5a's "refuses without a TTY": the create path *is* interactive-only,
but the send path is not, and one mis-shaped id makes the second look like the first.

### 6.3 · A headless, TTY-free arm EXISTS — and the product names it

```text
claude -p "<message>" --cloud <session-id> --output-format json   →  {"ok":true,"session_id":…,"url":…}
```

Reached with a well-shaped id on 2.1.215/219/220, from a Bash tool call with `stdin < /dev/null` and
no pty. It is not an accident of argument parsing: the bundle's own telemetry event for the success
path is `tengu_remote_send_headless_success` with `entry_point: "cloud_attach_headless"`. **The
product has a named headless cloud-attach path**, which is the single most important fact for a
2-way design — `cc-notify`'s send side has an off-box transport (§9).

~~⚠️ **What this does NOT establish.** With no real cloud session to address, every id tried was
rejected as `invalid session ID: must be a cse_… or session_… tagged ID`, so the arm is proven to
**exist, parse, and need no TTY** — it is **UNPROVEN that a message reaches a live session**. That
verification is gated behind the same operator step as everything else (§6.5). Also UNPROVEN: whether
this arm is subject to the attach entitlement gate in §6.4; the CLI error ordering puts the id
validator first, so the two could not be separated.~~

✅ **PROVEN 2026-08-08 on 2.1.220 — the arm DELIVERS, and the `invalid session ID` wall was an
artifact of having nothing to address.** Once §6.5's blocker cleared and a real session existed
(`session_01CHQoFxvsoDQ9KgJFSLrKno`), the same command with **no pty and stdin closed** returned:

```text
{"ok":true,"session_id":"session_01CHQoFxvsoDQ9KgJFSLrKno","url":"…"}
```

Two of the three unknowns above are now closed: the send arm **delivers**, and it is **not** covered
by §6.4's attach entitlement gate — that gate refuses every account interactively, yet this headless
send succeeded on a live session, so **attach-interactive and attach-headless are separately gated**.
The third (error ordering) is moot: there is no longer a need to separate the validators, because the
real id passes both. The struck-through paragraph's *reasoning* was sound — it is retained because
its error is the instructive part: **every id was fake, so the only thing being measured was the id
validator.** A wall that only ever fires on synthetic input says nothing about the real path
(`[[lookup-miss-is-not-absence]]`).

### 6.4 · Entitlement, measured per account — attach is gated OFF on ALL FOUR

~~`hasRemoteEnvironment: true` in `~/.claude-quaternary/.claude.json` (account 4 only)~~ **← the
"account 4 only" half is WRONG; corrected 2026-08-08 below.** `hasRemoteEnvironment: true` was the
open UNVERIFIED question in `CONCURRENCY_PROGRAM.md` §S5a: entitlement, or merely a record?
**Measured: a record.** The accounts carrying the key are gated exactly like the ones that do not:

```text
CLAUDE_CONFIG_DIR=<each of the 4> claude --cloud session_0000000000000000000000000000   # under a pty
→ Error: Attaching to an existing cloud session is not enabled for your account.       # all 4, identical
```

🔧 **Correction 2026-08-08 — the key is on TWO accounts, not one. The conclusion is unchanged; the
distribution was never re-measured.** Re-read across all four account config dirs (the SSOT map is
`~/.claude/accounts.json`, whose `accounts[]` order is *spend priority*, not an account numbering):

| Config dir | Account | `hasRemoteEnvironment` |
| --- | --- | --- |
| `~/.claude-next` | next | **`true`** |
| `~/.claude-quaternary` | next4 | **`true`** |
| `~/.claude-tertiary` | next3 | absent |
| `~/.claude-secondary` | next2 | absent |

```text
for d in ~/.claude-next ~/.claude-quaternary ~/.claude-tertiary ~/.claude-secondary; do
  grep -o '"hasRemoteEnvironment":[^,}]*' "$d/.claude.json" || echo ABSENT; done
```

**2 of 4, both `true`** — so "account 4 only" understated it by half, and the record-vs-entitlement
verdict is *strengthened*, not weakened: two accounts carry the key and both are refused identically
to the two that do not. ⚠️ **Two traps this correction walked into, worth the ink because either one
re-manufactures the wrong sentence.** (a) `~/.claude` is **not** an account config dir — it is the
live symlink layer; sweeping it in place of `~/.claude-secondary` silently drops a real account and
adds a non-account, and it still reports a plausible-looking 2-of-4. (b) The doc's "account 4"
referred to `~/.claude-quaternary` by *name*, but `accounts[]` orders by spend priority, so ordinal
labels and directory names do not agree — **cite the config dir, never the ordinal**
(`[[caller-census-keyed-on-path-misses-the-name]]`: an identifier that resolves two ways will
eventually resolve the wrong one).

Two properties make this probe usable rather than merely repeatable: the entitlement gate is checked
**before** id validation, so a fake id is enough and **nothing is created**; and the same binary
emits three *distinct* refusals across the sibling paths above, so the instrument is not a
constant-emitter. This is a **rollout gate on Anthropic's side** — the one blocker on this whole page
that the operator cannot clear.

**Attach and create are gated separately.** The create path is NOT entitlement-gated: it runs past
argument validation into a real upload attempt (§6.5). So the interactive-attach refusal, quoted in
the brief that opened this work as though it governed cloud access, governs only *attach*.

### 6.5 · ~~What actually blocks the CLI create path — and it is ONE operator step~~ · RESOLVED 2026-08-08

> ✅ **The CLI create path WORKS.** `claude --cloud "<desc>"` returns
> `Created cloud session: … session_01CHQoFxvsoDQ9KgJFSLrKno`. The blocker was the **CLI-side GitHub
> link**, cleared by `/web-setup` (a TUI-only command), **not** the web app's GitHub App
> authorization and **not** the bundle size. The original diagnosis below is kept in full because
> both of its wrong turns are instructive. **Do not re-run a create to re-confirm this** — each one
> spends weekly quota.

From a trusted repo dir, `claude --cloud "<description>"` reached (2026-08-07):

```text
Error: Bundle upload failed: Socket is closed after 3 attempts.
Please setup GitHub on https://claude.ai/code
```

Reproduced twice, so **not transient** (`[[memory-hygiene]]`: a one-off would not be recorded here).
The repo is not the problem: `origin` is `https://github.com/renchris/claude-infrastructure.git`,
public, and local `gh` is authenticated as `renchris` with `repo` + `workflow` scopes. ~~**Connecting
GitHub to the claude.ai account is a web-only action** — that is the operator step, and after it the
measurement must be re-run rather than assumed.~~

🔑 **The real cause was narrower, and the error string named the wrong side of it.**
`Please setup GitHub on https://claude.ai/code` reads as *authorize the GitHub App for your claude.ai
account* — and **that was already connected the entire time.** Four cloud sessions on
`renchris/claude-infrastructure` were visible at `claude.ai/code` while this error still reproduced,
which is decisive: the web app cannot list sessions for a repo it has no GitHub access to. What was
missing was the **CLI-side** link — the local `gh` token synced up to the account — and the only
thing that establishes it is `/web-setup`, a **TUI-only slash command** with no headless equivalent.
Running it cleared the error; the next `claude --cloud "<desc>"` created a session.

**The transferable shape:** a remediation string is a *fallback*, not a diagnosis. This one names a
surface (`claude.ai/code`) that was healthy, for a link (CLI→account) that lives somewhere else
entirely, and it is emitted by whatever fails last regardless of why. It sent an investigation to the
web UI, where everything looked correct, which then made a **second** wrong cause look attractive
(the bundle reading below). *Same class as §6.1's `--help` lesson: an instrument that cannot see the
subject's class will still return a confident answer.*

🔑 **A mechanism finding that contradicts a cited source.** "Bundle upload" means the CLI create path
**uploads a bundle of the local tree**. §S5a states, citing `sdk-tools.d.ts` L3764, that "the VM
clones from the *pushed* remote, not local disk". Both can be true of *different* surfaces — a
web/cloud-environment session cloning the remote vs the CLI's `--cloud` create shipping a bundle —
but they cannot both describe this route. ~~Consequence if the bundle reading holds: `cc-cloud
preflight`'s load-bearing refusal (an **unpushed branch** makes the session invisible, because the VM
clones the remote) **does not bind on the CLI create route**, since the local tree travels in the
bundle. Recorded as a **contradiction to settle with the first successful fire**, not as a decided
fact — the refusal stays in place until then, because it is safe when wrong in that direction.~~

✅ **SETTLED 2026-08-08, in favour of CLONE for the linked path — and the bundle numbers survive as a
cost, not a cause.** The contradiction was never one: **bundle mode is what the CLI falls back to
when the GitHub link is missing** (the docs say exactly this — bundle mode activates when GitHub
access is unavailable). With the link established, the VM clones the remote and **no bundle is
uploaded, so the 100MB cap never applies**. §S5a's `sdk-tools.d.ts` L3764 reading is therefore
correct for the route we will actually use, and `cc-cloud preflight`'s unpushed-branch refusal
**does bind** — it was safe when uncertain and is now simply right. It stays.

**KEEP the measurement — it is real, and it is the price of the fallback path** (taken 2026-08-08,
before the link was fixed):

| Quantity | Measured | Against |
| --- | --- | --- |
| `.git` on this repo | **231 MB** | — |
| all-branches bundle | **104 MB** | documented **100 MB** cap → over |
| single-branch fallback bundle | **94 MB** | under the cap, but the socket still died |

So bundle mode on this repo is **at the cap on day one**, driven by 286 upstream-less local branches
(§7). That matters the moment anything drops the GitHub link — a revoked token, a private fork, a
repo with no remote — because the fallback is then a 94–104 MB upload that is already marginal.
**Recorded as a standing cost of bundle mode, explicitly NOT as the create blocker.**

⚠️ **How the false cause was manufactured, since the mechanism is repeatable.** The bundle numbers
were measured *after* the web UI had been checked and found healthy, so they arrived as the only
remaining anomaly — real, quantitative, and sitting right next to a documented cap the larger number
exceeded. That is a **true measurement corroborating a wrong cause**
(`[[wrong-cause-corroborated-by-true-metric]]`): nothing in 104-vs-100 distinguishes "the bundle is
too big" from "we should not be building a bundle at all", and the question that *would* have
distinguished them — *why is this in bundle mode when a GitHub remote exists?* — was never asked. The
94 MB single-branch fallback is the tell that was there all along: it was **under** the cap and failed
anyway.

### 6.6 · The third route is real: the routines `/fire` endpoint

Neither plan considered it, and it needs no `--cloud` verb, no TTY, and no attach entitlement:

```text
POST https://api.anthropic.com/v1/claude_code/routines/<trig_id>/fire
  Authorization: Bearer <per-routine token>   ·   anthropic-beta: experimental-cc-routine-2026-04-01
→ {"type":"routine_fire","claude_code_session_id":"session_…","claude_code_session_url":"…"}
```

**Endpoint existence is measured, with a control** — the discipline §7 demands:

| Probe | Result |
| --- | --- |
| `POST /v1/claude_code/routines/trig_0000000000/fire`, no auth | **HTTP 401** `authentication_error` — the route exists and demands auth |
| control: `POST /v1/claude_code/zzz_not_a_real_surface/trig_0/fire` | **HTTP 404** `404 page not found` |

The 401/404 split is the whole evidence: an unauthenticated 401 cannot be produced by a path that
does not exist. Corroborating, `routineFiredWatermark` is present in **all four** account configs
(next 2026-05-29 · next3 2026-06-11 · next2 2026-06-22 · next4 2026-06-25), so routines are an
already-live surface on this fleet, not a speculative one. **The returned `claude_code_session_id` is
exactly the id `cc-cloud declare --id` wants**, and routines load skills from the **cloned repo**,
which is how `.claude/skills/` reaches a VM that has no `~/.claude` (§S5a fact 1).

⚠️ Its one operator step: the per-routine bearer token is minted **web-only**
(`claude.ai/code/routines` → edit → Add trigger → API), shown once, and the CLI can neither mint nor
revoke it. No token exists on this box today (checked: no `routines*` path under any of the four
config dirs, and the keychain holds only `Claude Code-credentials-*`). ⚠️ Second trap, for the
dispatch design rather than the plumbing: `text` arrives at the routine wrapped in
`<routine-fire-payload>` and **labelled untrusted**, so the routine's *saved* prompt must explicitly
opt in to acting on it or the payload is inert context.

### 6.7 · The residual open question, now narrow and operator-shaped

The question is no longer "does a fire path exist" — three do, and their blockers are now named and
disjoint:

| Route | Blocker | Whose |
| --- | --- | --- |
| CLI create — `claude --cloud "<desc>"` | ~~connect GitHub at `claude.ai/code`, then re-measure §6.5~~ **NONE — CLEARED 2026-08-08 via `/web-setup` (§6.5); creates work** | — |
| routines `/fire` | mint a per-routine bearer token (web-only, shown once) | **operator**, one web action |
| CLI interactive attach — `claude --cloud <id>` | `not enabled for your account`, all 4 accounts | **Anthropic** — rollout; not clearable here |
| browser agent | last resort; not needed to decide, and not attempted | — |

~~**Everything downstream bottlenecks on one of the two operator actions**, because each unproven
claim on this page needs a live `session_…` id to test:~~ **← the bottleneck BROKE 2026-08-08.** The
five claims it named have split three ways:

| # | Claim | Status after 2026-08-08 |
| --- | --- | --- |
| 1 | headless send arm **delivers** (§6.3) | ✅ **PROVEN** — `{"ok":true,…}`, no pty, stdin closed |
| 2 | attach gate also covers the send arm (§6.3) | ✅ **SETTLED — it does not**; interactive and headless attach are gated separately |
| 3 | bundle-vs-clone (§6.5) | ✅ **SETTLED — CLONE** on the linked path; bundle mode is the unlinked fallback |
| 4 | `agents --json` blind to cloud rows (§7.1) | ⬜ still **UNPROVEN** — not re-probed against the live session |
| 5 | `refs/cc/*` per-branch vs per-refspec (§S5a line 586) | ⬜ still **UNRUN** — needs a push *from inside* a session |

**The remaining two are no longer operator-shaped — they are ours to run**, and both now have a
live-session precondition that is satisfiable on demand rather than blocked. Their one real cost is
quota: creating a session spends against the weekly limit (the account was at **77%** when this
correction was written), so they should be batched onto **one** fire, in §9.4's order, not taken one
per session. Of the original operator actions only the **routines bearer token** (§6.6) remains, and
it gates only the routines route. **The browser route stays unattempted deliberately** — it is the
operator's preference order (programmatic first), and a browser fire would produce a session id
without producing a *programmatic* path, so it would answer the downstream questions while leaving
the question that matters open. That reasoning is now moot for the CLI route, which *is* the
programmatic path and works.

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
| ~~`--cloud` verb~~ | ~~absent in 2.1.114 **and** 2.1.220~~ | ~~`claude --help`~~ | **WRONG — retracted, see below** |

⚠️ **The two binary-scoped rows are the ones to distrust first.** A grep over a binary is only
evidence if the grep can find anything at all: the first attempt at this measurement returned
`0` for every pattern because it was pointed at a path that did not exist. Every row above that
says "absent" was taken with a **positive control in the same command** (`ultrareview` → 48/96
hits). Re-measure with a control, or do not re-measure.

🚨 **…and the row that was retracted anyway (2026-08-07, later same day) is the one that carried a
control.** `--cloud` is present-but-HIDDEN on 2.1.220 (§6.1). The control proved the *grep* worked; it
could not prove `--help` can see a hidden flag, and `--help` cannot. **A control belongs on the stage
that can be blind, not the stage that is easy to check** — the rule above is hereby strengthened to:
re-measure with a control **that could fail the way the subject would**.

### 7.1 · Cloud-control measurements (2026-08-07, later same day)

Positive/negative controls are named per row; none of these is a `--help` read.

| Fact | Value | Command / control | Decay |
| --- | --- | --- | --- |
| `--cloud` on 2.1.114 | **absent** (truly) | `claude --cloud x --print` → `unknown option`; control `--zzz-nope` → same | ⚠️ version-scoped |
| `--cloud` on 2.1.215/219/220 | **present, hidden** | same probe → `--cloud cannot be combined with --print`; control → `unknown option` | ⚠️ version-scoped |
| `--remote` | alias of `--cloud` | its refusal text names `--cloud` | ⚠️ version-scoped |
| create vs address split | argument is **polymorphic** | `--cloud session_abc_def` → send path · `--cloud session_abc-def` → create path (hyphen) · `--cloud` bare → `requires a description` | ⚠️ version-scoped |
| headless send arm | exists, **no TTY** | `claude -p m --cloud <id> --output-format json` reaches the id validator with `stdin</dev/null`; bundle telemetry `tengu_remote_send_headless_success` / `cloud_attach_headless` | ⚠️ version-scoped |
| ~~headless send **delivers**~~ | ~~**UNPROVEN**~~ **PROVEN 2026-08-08** | `claude -p "<msg>" --cloud session_01CHQoFxvsoDQ9KgJFSLrKno --output-format json`, no pty, `stdin</dev/null` → `{"ok":true,…}` | ⚠️ version-scoped |
| interactive attach entitlement | **gated OFF, 4/4 accounts** | `CLAUDE_CONFIG_DIR=<dir> script -q /dev/null claude --cloud session_0000…` → `not enabled for your account`; gate precedes id validation, so nothing is created | Anthropic rollout — recheck |
| `hasRemoteEnvironment: true` | a **record**, NOT entitlement | ~~account 4 has it and is gated identically to 1–3~~ **corrected 2026-08-08: on 2 of 4 — `.claude-next` AND `.claude-quaternary`; both gated identically to the two without it (§6.4)** | stable finding |
| CLI create entitlement | **not gated** | reaches a real upload attempt (row below) | Anthropic rollout |
| ~~CLI create blocker~~ | ~~`Bundle upload failed: Socket is closed after 3 attempts. Please setup GitHub on https://claude.ai/code`~~ **CLEARED 2026-08-08 — create returns `Created cloud session: … session_01CHQoFxvsoDQ9KgJFSLrKno`** | cleared by `/web-setup` (TUI-only, links the CLI's `gh` token to the account) — **NOT** the web GitHub App, which was connected throughout (§6.5) | ⚠️ re-links on token revoke |
| bundle sizes on this repo | `.git` **231 MB** · all-branches bundle **104 MB** vs a **100 MB** cap · single-branch **94 MB** | measured 2026-08-08 pre-fix; **a cost of bundle mode, NOT the create blocker** — with GitHub linked the VM clones and no bundle is built (§6.5) | grows with the 286 upstream-less branches |
| routines `/fire` endpoint | **exists** | unauth `POST /v1/claude_code/routines/trig_0000000000/fire` → **401**; control `…/zzz_not_a_real_surface/trig_0/fire` → **404** | beta header dated |
| routine token on this box | **none** | no `routines*` under any of the 4 config dirs; keychain holds only `Claude Code-credentials-*` | operator can change |
| routines already used | `routineFiredWatermark` in **4/4** configs | `grep -o '"routineFiredWatermark":[^,}]*' <each>/.claude.json` | stable |
| `agents --json` sees cloud rows | **UNPROVEN — do not read as "no"** | 5 rows returned, all local (`pid`, `kind:"interactive"`); **zero cloud sessions existed**, so this is a lookup miss, not an absence (`[[lookup-miss-is-not-absence]]`) | blocked on §6.7 |
| `agents --json` as a local observable | real, **TTY-free** | `claude agents --json [--all]` → `pid·cwd·kind·sessionId·name·status·waitingFor` | ⚠️ version-scoped |

### 7.2 · Harness traps — the measurement rig lying about the subject

Every row on this page is taken through a harness, and a harness can fail in ways that read exactly
like a finding. Two are now recorded, because each one produced a confident wrong answer.

**T1 · A `kitten @ launch` of the binary DIRECTLY skips the login shell (2026-08-08).** Driving a
TUI-only command headlessly (here `/web-setup`, §6.5) means launching `claude` under kitty remote
control. Launched directly, the process inherits kitty's environment rather than the operator's
interactive one, so `~/.zshrc`'s PATH additions never run — **`gh` is off PATH**, and `/web-setup`
reports:

```text
GitHub CLI not found
```

That string is about the **harness**, not the subject: `gh` 2.96.0 is installed and authenticated
(§7). Taken at face value it manufactures a whole false branch of investigation — "install/repair
`gh`" — for a tool that was never broken. **Launch through the login shell instead:**

```text
kitten @ launch --type=os-window /bin/zsh -l -i -c '<the claude command>'
```

🚨 **Same class as §6.1's `--help` lesson, one layer down.** There, the *instrument* could not see
the subject's class (a hidden flag is omitted from `--help` by construction). Here, the *environment*
could not see the subject's dependency — and in both cases the tool answered anyway, in a register
indistinguishable from a real negative. **A negative result must first be attributed to the rig**:
before recording "X is not found / not present / not supported", re-run it in the context that
normally runs it, and confirm the rig can see a control that is *known present*. `command -v gh`
inside the same launched shell is that control, and it costs one line.

**T2 · `~/.claude` is not an account config dir (2026-08-08, §6.4).** It is the live symlink layer.
Any per-account sweep must enumerate from `~/.claude/accounts.json`, never from a hand-written list —
a hand-written one silently substituted `~/.claude` for `~/.claude-secondary` and still returned a
plausible 2-of-4.

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

### 8.1 · Step 1 is not orderable on either real route — the id does not exist until after the fire

The protocol above was written before any fire path was known, and it assumes the operator brings an
`<id>` from the web UI. **Both programmatic routes invert that**: the id is a *return value* of the
fire, so `declare`-before-fire is unsatisfiable as written.

| Route | When the id exists | Gap |
| --- | --- | --- |
| routines `/fire` | in the HTTP response — `claude_code_session_id` | milliseconds; declare on the next line |
| CLI `--cloud "<desc>"` | after bundle upload + session create | seconds, and the VM may already be running |

The gap is not academic: §5.2's three liars — `cc-spawn-verify`, `cc-board`, and the destructive
`com.claude.team-orphan-reaper` on its 600s timer — key their abstention on `cc-cloud is-offbox <id>`.
A session that exists but is not yet declared is exactly the window in which a false death verdict
can be issued, and the reaper's is destructive.

**Fix, and it is a two-phase `declare`** (not a retry loop, which cannot shrink the window below one
poll interval): split the declaration so the *unobservable* half is written first.

1. `cc-cloud declare --reserve --branch <b> --paths <…>` → writes the declaration with the branch,
   paths, baseline sha and `declared_at`, and a **reservation token** in place of `--id`. Everything
   §4's state function needs except the id, all of it known *before* the fire.
2. Fire. Capture the id from the route's own output.
3. `cc-cloud declare --bind <token> --id <id> --url <url>` → binds. Idempotent.

The property that makes this correct rather than merely earlier: **`is-offbox` must answer `true` for
a reservation that has not yet bound**, for its whole boot budget. That converts the race from "a
live session reads as dead" into "a reserved slot reads as not-yet-dead" — the abstain direction, which
is the safe one. A reservation that never binds expires into `U0 UNKNOWN` (never a death verdict) and
`--check` fails, so a leaked reservation is loud rather than silent.

⚠️ Step 2 of §8 ("push the declared branch as its first act") **needs re-checking against the bundle
finding** (§6.5). If the CLI create route ships a bundle of the local tree rather than cloning the
remote, then the branch the VM pushes may not be the branch this box declared. Until one fire
settles it, declare the branch the *brief* names and treat a mismatch as `U0`, not as absence.

---

## 9 · The 2-way binding — how an off-box session joins the local comms stack

The local stack is `cc-notify` (send) + the inbox at `~/.claude/mailbox/<pane-uuid>.md` +
`mailbox-drain.sh` (deliver as context) + `cc-await-ping` (wake) + `cc-sessions` (enumerate).
`CONCURRENCY_PROGRAM.md` §S5a establishes that **none of it has a network transport**, and that the
channel is asymmetric. §6.3 changes exactly one thing about that: **the send side now has an off-box
transport.**

⚠️ **Pointer, not a finding — the local wake arm named above has an open defect** (`cc-backlog`
`a116d60af388`): `cc-await-ping` self-disarms with exit 5 (*"the session that armed me is GONE"*) on a
**stale registry row**, while the pane is alive. It is a purely local bug and nothing in §9 depends on
it, but §9's stack sentence names `cc-await-ping` as the wake path, so anyone wiring cloud→here
delivery on top of this stack should know the wake arm can go silent underneath them. Tracked there,
not here.

### 9.1 · The two arms are different mechanisms, and that asymmetry is permanent

| Arm | Transport | Latency | Why not the other one |
| --- | --- | --- | --- |
| **here → cloud** | `claude -p "<msg>" --cloud <id> --output-format json` (§6.3) | push, immediate | git would work but needs the VM to poll; this is a real message queue |
| **cloud → here** | `cc-bus` shards over git (§S5a) + `cc-cloud poll` observables O1–O5 | pull, nothing arrives until someone syncs | the VM can push **only its own working branch** (§S5a fact 3) — there is no inbound socket to this box |

**Do not try to symmetrise this.** The temptation is to make cloud→here a message push too; there is
nothing to push *to* — this box has no reachable endpoint, and the one channel the VM is guaranteed to
have is the git remote it cloned from. The asymmetry is a property of the network topology, not a gap
in the design.

### 9.2 · `cc-notify --cloud <id>` — the send-side seam, **transport VALIDATED 2026-08-08**

✅ **The transport this seam specifies is no longer a hypothesis.** Step 2 below — `claude -p
"<message>" --cloud <id> --output-format json` — was executed against a live session with **no pty
and stdin closed** and returned `{"ok":true,"session_id":"session_01CHQoFxvsoDQ9KgJFSLrKno","url":…}`
(§6.3). The seam therefore moves from *specified* to *validated*: what remains unbuilt is `cc-notify`'s
own dispatch layer, not the mechanism it dispatches to. **The `--receipt` refusal below is unchanged
and now more load-bearing, not less** — `{ok:true}` is precisely the ack that was just observed, and
it means *queued*, so a validated transport makes the temptation to read it as *read* stronger.

`cc-notify` resolves an address through three layers (role file → forward chain → pane uuid) and then
appends to a local inbox file. An off-box target has **no pane uuid and no inbox file**, so it cannot
enter any of those layers — it is a fourth address *kind*, dispatched before the liveness
classification:

```text
cc-notify --cloud <session-id> "<message>"
  1. cc-cloud is-offbox <id>   → refuse (exit 3) if undeclared: an undeclared cloud target is
                                 unobservable, so a "delivered" claim about it could never be checked
  2. claude -p "<message>" --cloud <id> --output-format json
  3. ok:true  → record the send in the declaration's sidecar, with the returned url
     ok:false → exit non-zero with the API's own reason, NEVER a bare failure
```

🚨 **`--receipt` must refuse, not guess.** The local receipt is a line-count cursor over the target's
inbox (`<uuid>.seen`), and there is no such cursor off-box — `{ok:true}` from the API means *queued*,
which is precisely the DELIVERED-IS-NOT-READ distinction `cc-notify`'s own header calls out. So
`--receipt` on a `--cloud` target must exit **UNKNOWN**, never 0. Returning "read" from a queue ack
would rebuild the exact false-confidence this repo has already paid for
(`[[claimed-outcome-vs-checked-outcome]]`): a claim that a session was told must cite `acked ≥ line`,
and off-box there is no `acked`.

### 9.3 · Rendering an off-box session in a kitty pane

`cc-sessions` enumerates from `~/.claude/cc-registry/<pane>.json` with `kill -0` on a **local pid** —
structurally unable to represent a session with no pid on this box, and one of §5.2's three liars for
exactly that reason. An off-box row therefore comes from `cc-cloud list --json`, not the registry,
and joins the view as a distinct kind:

```text
cc-panes / cc-where:   kind=offbox   addr=session_…   state=C0–C6 (cc-cloud's state function)
                       liveness=O2 ref-advance age    action=open <session url>
```

Three rules, each one a re-statement of something already paid for:

- **Never a pid column, never `kill -0`.** The state comes from `cc-cloud`'s state function, whose
  arms are total and whose `U0` is a non-verdict. A blank pid rendered next to live local pids reads
  as "dead" to a human scanning the column.
- **`U0 UNKNOWN` renders as UNKNOWN, not as a gap.** An empty cell in a table of live sessions is read
  as absence; §4's whole point is that absence is ambiguous.
- **The recover action is `open <url>`, not a kill.** There is no local process to signal, and the web
  UI is the operator escalation path (`cc-cloud`'s header, §3).

### 9.4 · What one successful fire validates, in order

This is the W2 checklist from Phase 0 — five claims, one session, and the order matters because the
session is short-lived. **Steps 1–2 are DONE as of 2026-08-08; the live list is 3–5.** Batch them
onto ONE fire: a create spends weekly quota (77% used when this was written), so re-running the
settled steps to watch them pass again is pure cost.

1. ~~`cc-cloud declare` binds the returned id, and `is-offbox` answers `true` (§8.1).~~ ✅ a real id
   exists — `session_01CHQoFxvsoDQ9KgJFSLrKno` (§6.5).
2. ~~`claude -p "<msg>" --cloud <id>` returns `{ok:true}` — the send arm **delivers** (§6.3), and
   whether the §6.4 attach gate also covers it.~~ ✅ **both settled** — it delivers, and the attach
   gate does **not** cover the headless arm (§6.3).
3. `claude agents --json` — does a cloud row appear, or is it local-only? Settles the row §7.1 marks
   UNPROVEN rather than "no". **← now the first live step.**
4. Which branch the VM pushes — settles bundle-vs-clone (§6.5) and §8 step 2.
5. `git push origin HEAD:refs/cc/<id>` **from inside the session** — the per-branch vs per-refspec
   experiment `CONCURRENCY_PROGRAM.md` §S5a line 586 calls the deciding measurement for the
   `refs/cc/*` heartbeat design. Run it last: it is the only step that can fail in a way that tells
   us nothing about the others.

---

## 10 · What was built after the fire path opened (2026-08-08)

§6.7's bottleneck broke, so the work this document deliberately deferred became live. This section
records what landed, in the order the dependency forced.

### 10.1 · §5.2's three liars now ABSTAIN — landed `d0765876`

The gate the rest waited on. `cc-cloud is-offbox` had existed since the reconciler landed and had
**zero references on trunk**; all three call sites now branch on it.

| Site | Was | Now |
| --- | --- | --- |
| `bin/cc-spawn-verify` | exit 1 `ABSENT` — "Died, or never launched" | exit **3 `OFFBOX`**, a fourth verdict in the exit-code vocabulary |
| `bin/cc-board` | `DEAD` (telemetry loop) · `DIED-UNRENDERED` and **`NO-RENDER?`** (registry join) | `OFFBOX` on all three |
| `scripts/team-orphan-reaper.sh` | archive, on a 600s launchd timer | KEEP + log, checked **before** `lead_liveness` |

Three things about the shape of the fix that are worth more than the fix:

- **The reaper's guard could not go on the `DEAD` arm.** An off-box lead has no watchdog pid file at
  all, so it never reaches the dead-pid branch — it enters **UNKNOWN**, and the UNKNOWN arm archives
  too once its ceiling passes. A guard on the word "DEAD" would have read as correct and been
  completely inert. The same shape appears in `cc-board`: an off-box registry row has no local pid,
  so it fell past `DIED-UNRENDERED` to the softer `NO-RENDER?`, whose own gloss ("up, but never
  rendered: hung/GO-deaf") is just as much a claim about a local process. **In both files the
  dangerous branch was the one that did not say "dead".**
- **`cc-spawn-verify` checks before its wait loop**, not after. Waiting `$TIMEOUT` for a process that
  can never appear spends the clock to arrive at a wrong answer. And `OFFBOX` outranks `PARKED` in
  the `--all` worst-verdict fold, because it is a **non-verdict**: a wave containing an off-box
  member is not verified-green, and folding it down to 0 would be the tool claiming an answer it
  never got.
- **Every site fails CLOSED toward its existing verdict.** No `cc-cloud`, an unreadable state dir, an
  undeclared id, or a retired one — all leave the old behaviour byte-for-byte. Each site can only
  ever suppress a false death, never invent a false life. Seam `CC_CLOUD_BIN`, honored as
  SET-including-EMPTY (`${VAR+set}`), so a test can genuinely turn the lookup off.

**29 tests across three suites** (`tests/cc-board.bats` is new — the file had no coverage at all),
each off-box case paired with a control proving the abstain is not blanket.

⚠️ **Two harness defects were caught in this change's own verification, both vacuous-pass shaped, and
they are the transferable part.**

1. **The RED control was vacuous.** The pre-fix subject was replayed from a scratchpad directory, so
   the suite's own `REPO="$(dirname $BATS_TEST_FILENAME)/.."` resolved somewhere with no
   `bin/cc-cloud` — every "RED" was the **lookup being absent**, not the subject convicting. It
   produced the right-looking red set for entirely the wrong reason, and it would have certified a
   subject that did nothing. Redone as a real `git worktree add --detach` at the parent commit,
   where the whole tree resolves. A partial replay had already lied once in the same session, on
   `cc-board`'s `dirname $0` sibling resolution. **A control must replay the real artifact, in a
   tree where everything it reaches still resolves.**
2. **Five assertions were dead.** `echo … | grep -q X && false` is and-absorbed — it can never fail
   — and they sat in exactly the tests carrying the load-bearing half ("it must not utter the death
   verdict at all"). The **land gate's** dead-assertion ratchet caught them, not the author and not
   the green suite. Revived to `! A || false`, then mutation-verified per site: a single-anchor
   mutant that keeps the `OFFBOX` word and re-adds the death word reddens exactly one test each,
   which is the property the rewrite restored — the positive half passes on that mutant, so only a
   live negative can catch it.

### 10.2 · Cloud sessions are ACCOUNT-SCOPED — measured 2026-08-08, backlog `95422d3518bc`

A finding from a sibling session, recorded here because it changes §9.2 and nothing in §9 predicted
it. Clean A/B: **same session id, same command, only `CLAUDE_CONFIG_DIR` differs** — the owning
account (`next3`) returns `{ok:true}`; another account (`next`) returns
`{ok:false, error:"Session not found"}`.

**A `session_…` id is therefore not a globally-addressable handle**, and §9.2's three-step dispatch
is incomplete without an account: the declaration must record the owning account, and the send must
route through that account's config dir.

🚨 **The trap is the error string, not the scoping.** A wrong-account send fails as *"Session not
found"* — it reads as a **dead session**. So the honest-looking behaviour §9.2 already specifies
("exit non-zero with the API's own reason, NEVER a bare failure") is, on this one path, how the
wrong diagnosis gets laundered into the operator's face with the API's authority behind it. The send
arm must detect the mismatch itself and name it, rather than letting the API's word be the whole
verdict. This is the *same class* as §5.2's three liars — a condition converted into a different,
scarier one on its way to a human — arriving through a channel §5.2 did not cover.

### 10.3 · Account linking — all four are linked, and the marker set already disagrees

All four accounts (`next`, `next2`, `next3`, `next4`) are GitHub-linked; `next3` is verified
end-to-end with `session_019uShq6mQCgKYkPvyUqg24d`. The CLI create path (§6.5) is unblocked for all
of them, so `scripts/cloud-websetup-drive.sh` exists for **repeatability and re-link**, not to open
the path.

⚠️ **`~/.claude/autonomy/websetup/<acct>.linked` is a cache, and it has already drifted.** Measured
2026-08-08: the directory holds `next2.linked`, `next3.linked`, `next3.verified`, `next4.linked` —
**and no `next.linked`**, for an account reported and believed linked. Nothing reconciles the marker
against the account, so a reader that trusts the marker set will conclude `next` is unlinked and
re-drive a link it does not need. Treat the markers as a progress log, never as the authority.
