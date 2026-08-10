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
| `bin/cc-spawn-verify` | `:89-97` | argv scan of the **local** process table ⇒ exit 1 `ABSENT`, "Died, or never launched". Callers are told at `:24` to branch on that three-state vocabulary. *(That vocabulary has since grown a FIFTH member — exit 4 `WEDGED`, backlog `75c2e3e2bde7` — and the rank note below applies to it.)* |
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

🔧 **Second correction, 2026-08-08 17:26 — it is now `true` on ALL FOUR, and that is the real
finding: the distribution is not a fact, it is a decaying reading.** Re-measured (JSON-parsed, not
grepped) 16 h after the correction above landed: `~/.claude-secondary` and `~/.claude-tertiary` had
flipped, their `.claude.json` written at **17:22 and 17:23 the same afternoon** — minutes before the
sweep, while the fleet was probing cloud paths. Three measurements, three answers, each correct when
taken: **1 of 4** (2026-08-07) → **2 of 4** (`99aad939`, 01:08) → **4 of 4** (17:26).

The spread is monotone and written by the client (`bin/cc-cloud` does not write the key), so the act
of probing cloud paths moves the reading — **the local negative control no longer exists.** The
record-vs-entitlement verdict is strengthened a third time and from a new direction: the key's value
changes while entitlement does not. Practical rule — **do not cite a distribution for this key, cite
the command**; a table of it is stale on a timescale of hours
(`[[published-figure-decays-with-its-source]]`). The two traps above still bind, and the table
immediately above is kept as the 01:08 reading, not as current state. Detail:
`docs/research/cloud-observability-2026-08-07.md` §7.

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
| 4 | `agents --json` blind to cloud rows (§7.1) | ✅ **PROVEN BLIND 2026-08-08** — probed *with a live cloud session as the positive control*; `kind` ∈ {`background`,`interactive`}, zero cloud rows, the live id absent from the array (§7.3) |
| 5 | `refs/cc/*` per-branch vs per-refspec (§S5a line 586) | ✅ **ANSWERED per-REFSPEC 2026-08-08 — from the vendor's docs, NOT from a probe** (§7.4). The push never reached the proxy: **no cloud session has ever been observed to execute** (§7.5) — which is now the bigger open item |

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

### 7.3 · `agents --json` is blind to cloud sessions — PROVEN 2026-08-08 (ledger row 4)

```bash
CLAUDE_CONFIG_DIR=$HOME/.claude-secondary claude agents --json --all </dev/null \
  | grep -oE '"kind": *"[a-z]*"' | sort -u        # → "background", "interactive". Nothing else.
```

**The control is what makes this a finding rather than an empty list.** The same probe was run
earlier and returned the same answer, but at that moment every declared cloud session was of unknown
liveness — so a blind instrument and an empty world were indistinguishable, which is
`[[lookup-miss-is-not-absence]]` exactly. It was re-run **while `session_01TYUBVAqDxXPQ6hpZhpWpUP`
was live** (created minutes earlier; the headless send arm had just returned `{"ok":true}` against
that id). The array still contained 8 rows, none of them cloud, and `grep -c` for the live session id
returned **0**.

⇒ **`agents --json` is a LOCAL pane census and must never be used as a cloud inventory.** `cc-cloud
list` remains the only cloud-session inventory this box has, and it reads declarations, not the world
— which is why §8.1's declare-before-fire is load-bearing rather than tidy.

### 7.4 · The `refs/cc/*` question — answered from docs, unmeasurable from here (ledger row 5)

**Answer: per-REFSPEC.** The vendor documents the rule under *GitHub proxy*:

> **Push protection**: `git push` works only against the session's current working branch; cloning,
> fetching, and PR operations work normally.
> — <https://code.claude.com/docs/en/cloud-environments>

⇒ `refs/cc/heartbeat/<id>` is not writable from a cloud VM. The O1 design in
`cloud-observability-2026-08-07.md` §4.1 is **retracted** there, with the consequence
`CONCURRENCY_PROGRAM.md` §S5a pre-committed to: a working-branch commit, or leave git.

**The probe was designed, fired twice, and never reached the proxy.** Recorded because the *design*
is reusable the moment a cloud session executes:

| arm | target | separates |
| --- | --- | --- |
| **C** (control) | `HEAD:refs/heads/<own working branch>` | "refused" from "never ran" — without it, absence is unreadable |
| P1 | `HEAD:refs/cc/probe/<id>` | is a non-`refs/heads` namespace reachable? ← the question |
| P2 | `HEAD:refs/tags/<id>` | is the rule namespace-scoped or branch-scoped? |
| P3 | `HEAD:refs/heads/<a different branch>` | own-branch-only vs any-branch |

Two traps the first fire walked into, both fixed in the second brief and worth keeping:

1. **The control was void as first written.** It said "push the branch you are on", but a VM that has
   not branched yet is on `main`, and a refused push to `main` is refused *for a different reason* —
   it would have been read as evidence about ref namespaces. The fix is `git switch -c` **first**, so
   the control is a real session branch.
2. **The report needs a channel that survives the thing being measured.** If every push is refused
   the worker cannot report by pushing. The brief therefore also encodes each exit code in a *branch
   name* (`cc-rc-<id>-c<n>-p1-<n>-…`), readable by `ls-remote` with no fetch. The push-independent
   alternative — `gh issue comment`, which the docs say works through the proxy regardless of push
   protection — is the right channel and was not used: creating a public issue on the operator's repo
   is an outward-facing action, and it is theirs to authorise.

### 7.5 · Why it could not be measured: eleven sessions, zero actions

| | | re-read with |
| --- | --- | --- |
| cloud sessions declared (≥2 accounts) | **11** | `cc-cloud list` |
| that produced any remote-visible artifact, ever | **0** | `git ls-remote origin` → 2 refs, both `main` |
| longest | **17h** — `session_01TYUBVAqDxXPQ6hpZhpWpUP` (next2) | `cc-cloud show <id>` → `NOT-STARTED` |
| best-conditions arm | `session_01DcTULYmXVnUnrwyFKm8LGH` (next3, `--verify`d link, clone mode, four-`git push` brief) — **0 refs in 7h** | same |

Both probe sessions accepted work: the create returned a session id and an auto-generated title
derived from the brief (*"Measure git ref namespace push behavior"*), and the headless send arm
returned `{"ok":true}`. **Accepting is not executing**, and nothing downstream of the accept has ever
been observed. Per §4.4 of the design doc, `NOT-STARTED` separates *alive* from seven other worlds
collectively and names none of them — so this is a **wall, not a diagnosis**.

⚠️ **One live defect found on the way, worth its own line:** `cloud-websetup-drive.sh --status`
reported `next2  linked`, and a create on next2 minutes later fell back to **bundle mode**
(`Bundle upload failed … Please setup GitHub`) — the exact signal §6.5 identifies as *the link is
missing*. The store records that a link was once made; it does not observe that one still holds. Its
own `--verify` is the un-fakeable check and is opt-in, so **`--status` alone must not be read as a
precondition being satisfied** — pick the `--verify`d account, which is what the second fire did.

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

**BUILT 2026-08-08 — and `cc-panes` above names no binary in this tree.** The rendering line was
written against a tool that does not exist; one letter off `cc-pane` (the spawn/address/send/close
seam), and `bin/cc-where`'s own header says it is *deliberately* not called that. The two real
targets, and why the split falls where it does:

- **`bin/cc-sessions` = ENUMERATION.** It is the view §9.3 already indicts by name, so it grew an
  `OFF-BOX` block sourced from `cc-cloud list --json --state`, plus `--offbox [--json|--names]` as
  the machine surface. `--json`/`--names` stay LOCAL-ONLY by default: they are the addressing views
  cc-notify resolves a friendly name → pane UUID through, and a row with no local delivery path must
  never resolve there. With zero declarations every mode is byte-identical to the feature's absence.
- **`bin/cc-where` = LOOKUP.** `--go` on a declared off-box session now exits **5** — *found,
  off-box, nothing local to focus* — printing `kind=offbox · addr · state · open <url>`, instead of
  the `nothing matches` that is §5.2's lie in its purest form. `--json` stays a pane census: an
  off-box session has no kitty window, so a synthesised row would be focusable and countable as a
  pane. It is never faked into one.

State is **never re-derived** by either consumer. `cc-cloud list` gained an opt-in `--state` that
calls `classify` and emits its verdict verbatim (the default stays probe-free, which is that verb's
whole point); a probe that cannot run degrades to the literal `UNKNOWN`, never to a dropped row.
Suites: `tests/cc-sessions-offbox.bats`, `tests/cc-where-offbox.bats`.

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
3. ~~`claude agents --json` — does a cloud row appear, or is it local-only?~~ ✅ **DONE 2026-08-08 —
   BLIND** (§7.3). It needed no *successful* fire, only a live id: the probe is local and the session
   only had to exist.
4. Which branch the VM pushes — settles bundle-vs-clone (§6.5) and §8 step 2. ⬜ **still unrun, and
   now known to be unrunnable by this route** — the VM never pushes anything (§7.5).
5. ~~`git push origin HEAD:refs/cc/<id>` **from inside the session**~~ ✅ **ANSWERED from the vendor's
   docs, not from the fire** (§7.4) — per-REFSPEC; the design is retracted in
   `cloud-observability-2026-08-07.md` §4.1. The probe itself is **still unrun** and its brief is
   preserved in §7.4 for whenever a session executes.

🚨 **This checklist's own premise is now the open question.** It is titled *"what one successful fire
validates"* and it assumed the scarce thing was a **live session id**. Two ids were obtained cheaply;
what none of them produced was a session that **acts**. Steps 4 and 5 do not need another id — they
need the first observed cloud execution (§7.5). Re-firing to collect more ids validates nothing.

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

> **A FIFTH member arrived 2026-08-09 (backlog `75c2e3e2bde7`), and it changed how the `--all` fold
> is written — read this before adding a sixth.** `cc-spawn-verify` now also resolves exit **4
> `WEDGED`** (the agent process EXISTS and is inert on a startup modal). The fold used to be
> `max(rc)`, i.e. "the highest exit code is the worst outcome" — a rule that held only by arithmetic
> luck up to 3 and breaks at 4, because `OFFBOX` must stay on top: it is the set's only NON-VERDICT,
> and a wave carrying a question this box could not ask must never report as one whose members were
> all answered. The rank is now an explicit table (`rank_of`) reading
> `RUNNING < ABSENT < PARKED < WEDGED < OFFBOX`, with an unmapped code sorting above every verdict
> and below the abstain. **The `OFFBOX`-outranks-everything property this section established is
> therefore now asserted by a test rather than by the choice of integer** —
> `tests/cc-spawn-verify.bats` "the fold RANK, not max(rc)". `4` rather than a renumber because 3 is
> landed and published here; two meanings behind one number is strictly worse than a gap.

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

### 10.2b · What waves B and D built

| Wave | Landed | The one thing worth knowing about it |
| --- | --- | --- |
| **B** — `scripts/cloud-websetup-drive.sh` (+15 tests) | `66ef4d8c` | Success is the **verdict line** `Connected as `, never the absence of an error. Four exit codes, and the fourth is the point: **rc 3 NOT-SUCCESS** — the drive ran, nothing errored, and the string never appeared. Folding that into either neighbour is how a link that was never made gets recorded as made, or a healthy-but-slow pane gets torn down. Across accounts an OBSERVED error outranks an indeterminate one, because it names a cause. |
| **D** — `bin/cc-sessions --offbox`, `bin/cc-where`, `cc-cloud list --state` (+12 tests) | `66ef4d8c` | Rows come from `cc-cloud`, never the registry. `--state` is an **opt-in** flag that hands out `classify`'s verdict rather than a copy of it — the probe-free default stays probe-free, and no consumer re-implements the state function outside its owner. |

⚠️ **§9.3 named a binary that has never existed.** It specified "cc-panes / cc-where"; `bin/cc-panes`
is not in this tree and never was — `bin/cc-where`'s own docstring says it is "deliberately NOT
called `cc-panes`". Wave D corrected the section in place rather than building to the name. Recorded
because the failure is generic and this repo has hit it before: **a plan's identifiers are not
checked against the tree by anything**, so a cited mechanism can be prose-only for as long as nobody
tries to run it (`[[spec-named-mechanism-may-be-prose-only]]`).

### 10.2d · Wave C — the send arm, and the two things it got righter than its brief

`cc-notify --cloud <id>` implements §9.2's three steps, dispatched **before** role resolution and the
liveness classification, because an off-box target is a different *kind* of address rather than a
different value of the same one — it has no pane uuid to resolve and no inbox to enqueue into.

Two decisions worth keeping:

- **`--receipt` is answered UNKNOWN (rc 7) BEFORE the is-offbox check**, not after. The answer does
  not depend on the declaration, on `cc-cloud` being installed, or on anything else that could fail:
  there is no off-box read cursor, so no configuration of this box could make the answer 0. Ordering
  it first is what makes "never 0" an *invariant* rather than a property of the happy path. And rc 7
  is deliberately distinct from the local rc 1 — "not read" is a fact somebody measured; this is not
  measurable at all.
- **Flag support is decided from the REAL call's own refusal**, and only when the refusal *names the
  option*. The lead had filed a `strings`-based pre-check as a required fix; that was wrong. A
  pre-check is a second implementation of a question the call already answers, and it cannot tell a
  semantic refusal ("no such session") from a version one — laundering the first into "your binary
  is too old" sends the caller off upgrading something that was fine. Actuator-as-arbiter wins.

**What the lead did add**, after the account-scoping finding landed mid-build (§10.2): the send now
routes `CLAUDE_CONFIG_DIR` to the declared owning account, with **three** states — routed · refused
when the account's config dir does not exist · warned-and-sent when the declaration predates the
`account` field. That third state matters: refusing it would strand every earlier declaration, while
silently assuming the current account is exactly the guess that manufactures the misleading
"Session not found".

### 10.2e · The kitten permission rule was already granted at user scope

Wave B added `Bash(kitten @ send-text:*)` (plus `get-text`/`launch`/`close-window`/`ls`) to a new
project-scope `.claude/settings.json`. Verified after the fact: **the operator's own
`~/.claude/settings.json` already carries `Bash(kitten @ send-text:*)` at line 184** — so the
intermittent classifier block the rule was meant to cure was **never a missing user-scope grant**,
and the project-scope entry is belt-and-braces rather than the fix.

Recorded because the obvious next move on a recurrence — "add the allow rule" — is the one move
already known not to work. The real cause of the intermittency is still unidentified.

### 10.2c · A false ALIVE, from declaring against trunk

Using `cc-cloud` for real surfaced a hole in its own state function that §4.3's design did not close.
A probe session declared `--branch main` reported:

```
state=ALIVE    detail=ref at 55c18e2
```

`55c18e2` was a **sibling local session's commit**. O2 — "the declared ref advanced" — is the only
heartbeat off-box, and trunk advances constantly from everything else on this box. So a session
declared against a shared branch reads `C5 ALIVE` forever, *including after it dies*: the arm that
is supposed to be the liveness signal has been wired to the fleet's own background traffic.

It is not a bug in `classify` — every arm behaved as specified. It is a **declaration-time hazard**
the tool does not refuse, and it produces the one failure this whole document is organised against:
a confident verdict about a session, computed from evidence that has nothing to do with it. The
runbook now says never to declare `--branch main`; the stronger fix is for `declare` to refuse a
branch that is the remote's default. ~~or for the fire protocol to use the per-session `refs/cc/<id>`
that `CONCURRENCY_PROGRAM.md` §S5a already specifies (still unrun — §6.7 claim 5).~~ **← that second
option is DEAD (2026-08-08, §7.4): a cloud VM cannot write `refs/cc/*` at all, so a fire protocol
keyed on one would declare against a ref that can never appear — a permanent false `NOT-STARTED`,
which is this section's own hazard with the sign flipped.** The `declare`-refuses-the-default-branch
fix is therefore the only one of the two left standing, and it is now the whole remedy.

### 10.3 · Account linking — all four are linked, and the marker set already disagrees

All four accounts (`next`, `next2`, `next3`, `next4`) were reported GitHub-linked, and `next3` was
verified end-to-end with `session_019uShq6mQCgKYkPvyUqg24d`. So
`scripts/cloud-websetup-drive.sh` exists for **repeatability and re-link**, not to open the path.

🚨 **"Linked" and "can create" turned out to be different facts, measured later the same day.**
`next2` carries a `.linked` marker and **cannot create** — its attempt falls back to bundle mode
(`Bundle upload failed … Please setup GitHub`), which §6.5 establishes is what the CLI does when the
GitHub link is unavailable. Wave B's own `verify_account()` reads that string as `NOT LINKED`, so
the driver and an independent probe agree against the marker. See §S5-CEILING in
`CONCURRENCY_PROGRAM.md`: the create is also **intermittent** on an account that does work, so a
single bundle-mode failure is not by itself proof of an unlink — retry before concluding.

⚠️ **A refuted explanation, recorded so it does not re-emit.** The wave-B teammate reported that
every `.linked` file was written by the draft driver, whose `.linked` meant only *"consent keystroke
sent"* rather than *"verdict line read"* — which would make the markers weak-signal claims and the
whole discrepancy benign. **The artifacts refute it.** The draft (`/tmp/cloud-fleet-brief-driver.sh`
line 126, and its sibling `/tmp/cloud-websetup-drive.sh`) writes exactly
`printf '%s consent-sent\n'` — no account token. Every marker on disk reads
`… consent-sent Connected-as-renchris`. Neither script can produce that string, so an
**unidentified third producer** wrote them, and it recorded the STRONG signal.

That inverts the comfort: `next2`'s marker carries the very `Connected as` token that is this
system's definition of success, and `next2` **still cannot create**. So the correct statement is not
"the markers were written on a weak test" — it is that **a marker recording the right signal is
still not a statement about current capability**, because the link can lapse after it was truly
established. The remedy is unchanged (`--force` re-drive) but the reason matters: re-driving on a
stronger test would not have prevented this.

⚠️ **`~/.claude/autonomy/websetup/<acct>.linked` is a cache, and it has already drifted.** Measured
2026-08-08: the directory holds `next2.linked`, `next3.linked`, `next3.verified`, `next4.linked` —
**and no `next.linked`**, for an account reported and believed linked. Nothing reconciles the marker
against the account, so a reader that trusts the marker set will conclude `next` is unlinked and
re-drive a link it does not need. Treat the markers as a progress log, never as the authority.

### 10.4 · The tap gate — what must be TRUE before backlog work is fired into cloud sessions

This is the acceptance list for opening the tap, moved here from `/tmp` so it stops living somewhere
nothing reads. **The tap is DEFAULT-OFF and stays off until every row is green.** G7 is the row that
gates the rest, because an unmeasured ceiling is how "15 sessions" became folklore.

| # | Gate | State |
|---|---|---|
| **G1** | The three local oracles ABSTAIN on off-box sessions (`cc-spawn-verify`, `cc-board`, `team-orphan-reaper.sh` consult `cc-cloud is-offbox`). Without it the reaper ARCHIVES healthy cloud sessions on a 600 s timer. | ✅ `d0765876` |
| **G2** | Account affinity in `cc-cloud` — `declare --account`, `show`/`list --json` surface it, `account-of <id>`, legacy declarations read UNKNOWN and never crash. | 🔄 in flight (cloud `session_01EuB5…`) |
| **G3** | `cc-notify --cloud <id>` per §9.2 — route via the OWNING account, refuse a mismatch with a WRONG-ACCOUNT message rather than the bare `Session not found`, and `--receipt` must exit UNKNOWN off-box (`{ok:true}` means *queued*, not read). | 🔄 in flight (`cloud-fleet`) |
| **G4** | Off-box rendering — `cc-sessions --offbox` + `cc-where` answer for off-box ids, sourced from `cc-cloud`, never the registry. | ✅ `66ef4d8c` |
| **G5** | `handoff-fire.sh --cloud` + `cc-dispatch` venue — honour `--venue local\|cloud`, record the owning account at claim, declare immediately after create (§8.1), and BRANCH the box-local capacity gate onto account headroom. Ships default-off. | ✅ **CLOSED 2026-08-09, §10.5** — `c06a13ad` built the venue flag, the default-off gate and the account-headroom term; the create + declare that its own wording assumed was **never built** (regraded 🔄 earlier the same day, census below) and now is. Validated by a live fire: `session_01Kpc1kwHjwsRjERad1tTDuG` created and declared, exit 0. |
| **G6** | The landing path — a cloud VM pushes only its own branch and cannot run `/ship`, so something local must reconcile and land `claude/*` or every result strands. | ✅ `c8b2b446` |
| **G7** | The measured ceiling, recorded with its command. | ✅ **MEASURED** — `CONCURRENCY_PROGRAM.md` §S5.2. **Lower bound ≥2, no ceiling reached.** |
| **G8** | Eligibility as a REFUSAL, not a doc note — repo-only ✅ · visual/design ❌ · anything about this box ❌. | ✅ `01f1bf33` |
| **G9** | Repeatable + documented — the link drive, its tests, and a runbook. | ✅ `66ef4d8c` |
| **G10** | The wake path — `cc-await-ping` self-disarms (exit 5 on a stale registry pid; a group-TERM prints nothing), and §9 names it as *the* wake path, so cloud→here pings can vanish. | ✅ `f7c1948a` |

~~🚨 **The one finding that changes how G5 must fire, and it was not predicted by any row above.**~~
~~A cloud create issued from a **git worktree** hit `Bundle upload failed: Socket is closed after 3
attempts` on 3 of 3 ramps, while the same account from the **main checkout** created 2 of 2
back-to-back. Suspected mechanism: the bundle upload walking a `.git` that is an 86-byte gitdir
pointer rather than a directory.~~ **Not established** (main checkout n=1; one worktree create did
succeed) — but this repo's standing rule gives every concurrent writer its own worktree, and Agent
Teams isolate teammates in worktrees by construction, so *the default configuration for firing cloud
work is the one that failed*. Full evidence table: `CONCURRENCY_PROGRAM.md` §S5.2.

🚨 **REFUTED 2026-08-09 — G5 needs a RETRY, not a cwd change** (`CONCURRENCY_PROGRAM.md` §S5.3,
instrument `scripts/cloud-bundle-probe.sh`, commit `70f0cbba`). Both cwds share ONE object store, so
both build the same bundle — 99,778,280 B from the worktree vs 99,712,572 B from the main checkout,
a 0.07% difference, both at **95% of the CLI's 100 MiB cap**. An interleaved live A/B then had the
main checkout fail with the *identical* refusal while the worktree created; failures cluster by
round, not by cwd. The real defect is a ~95 MiB upload with 3 retries — marginal by construction.
`handoff-fire.sh --cloud` may keep inheriting the caller's worktree; ~~what it must not do is treat
the first `Bundle upload failed` as terminal~~. The upload disappears entirely once the Claude GitHub
App is installed on the repo (the create then uses a `git_repository` source and bundles nothing).

🚨 **G5 IS NOT ✅ — THE FIRE PATH HAS NO CREATE AT ALL (measured 2026-08-09).** The strike-through
above was written on the assumption that `handoff-fire.sh --cloud` issues a create that could be
retried. It does not. A repo-wide census of every invocation:

```bash
grep -rnE -- '--cloud' bin/ scripts/ | grep -E 'claude|CLAUDE_BIN|pty-run'
```
returns **only** `scripts/cloud-ceiling-probe.sh`, `scripts/cloud-bundle-probe.sh` and
`scripts/cloud-websetup-drive.sh` — the two probes and the web-setup driver. `handoff-fire.sh`
parses `--cloud` (L4975), gates it default-off (L4991-5009) and prices it against account headroom
(L3523-3576), then **never invokes a create, never calls `cc-cloud declare`, and never touches the
claude binary.** `grep -nE 'cc-cloud (preflight|declare)|claude .*--cloud' scripts/handoff-fire.sh`
is empty.

So G5's own wording — *"declare immediately after create (§8.1)"* — describes a create that does not
exist on the fire path, and the row's ✅ (`c06a13ad`) covers the venue flag, the default-off gate and
the capacity term, **not the ability to fire cloud work**. This is
`[[spec-named-mechanism-may-be-prose-only]]` inside our own gate table: the gate was graded on the
parts that were built.

**Consequence for sequencing, and it outranks the retry:** opening the tap would change nothing
today — with G2/G3 green and the GitHub App installed, `handoff-fire.sh --cloud` would still create
no session. The unbuilt create is the real G5, and it should be graded 🔄, not ✅. Note also that the
one existing end-to-end create+declare implementation lives in `cloud-websetup-drive.sh`, which a
sibling session owns — so the fire path's create should be factored out of a probe rather than
written a fourth time.

**→ NEXT STEP, and why it is this one rather than the GitHub App.** Both are open; the ORDER matters
and is not obvious, so it is recorded rather than left to be re-derived:

1. **Build the create into the fire path FIRST** (this is the work). Factor the create+declare out
   of `scripts/cloud-bundle-probe.sh:fire_one` — it is the smallest correct implementation and it
   already carries the two things a naive one gets wrong: the pty allocator (`scripts/lib/pty-run.py`,
   because the create path is interactive-only and refuses on its own capture) and an ANSI normaliser
   that maps cursor-absolute `CSI n G` to a space (without it a real refusal classifies as a
   non-verdict). Add a bounded retry there — §S5.3 measured create success at roughly 50-75% per
   attempt, reaching a session on attempt 2 of 4 twice over. Declare immediately after create (§8.1),
   which is the half G5's ✅ never covered.
   ⚠️ Do NOT edit `scripts/cloud-websetup-drive.sh` — a sibling session owns it. Read it, do not write it.
2. **Then one fire settles everything T2/T3 needs**, in a single observation: whether bundle mode
   holds, whether the session executes, whether it can push `claude/*` back, and whether
   `cloud-reconcile.sh` can land it. That is why this ordering beats installing the App first —
   the App install alone can only be read from SILENCE (a session that still does nothing tells you
   nothing about why), whereas a fire with a real create produces a positive or negative on all four
   at once. Install the App when the fire proves bundle mode is the blocker, not before.

**The DoD for that work, frozen here so it is not re-judged:** `handoff-fire.sh --cloud` creates a
declared cloud session, or refuses with a named reason — and one item traverses create → execute →
`claude/*` push → `cloud-reconcile.sh` → land. Anything short of that leaves T2/T3 exactly where
§S5.5 left them.

⚠️ **The classifier control is VOID and cannot currently be restored.** `--control` was designed
around a free known-refusal: an account already at 100% weekly. Measured 2026-08-08, an account at
100% weekly **creates cloud sessions normally** — so weekly quota does not gate cloud CREATE, the
control validates nothing, and no *ceiling* from this instrument is trustworthy yet. Lower bounds
remain safe because they count successes and do not depend on the classifier at all.

🚨 **RESOLVED-AS-UNMEASURABLE 2026-08-09 (`CONCURRENCY_PROGRAM.md` §S5.4).** The replacement control
was searched for and **does not exist**: every candidate is either void (100% weekly — measured),
not free (the 5-hour cap), the wrong category (auth / policy refusals), or vacuous (feeding the
classifier a string we invented). The stronger finding is that the instrument may be hunting an
event with no reachable instance — if cloud create is not capped at all, `refused-quota` can never
occur and the ramp can only ever exhaust its own `--max`. **The ceiling is therefore marked
UNMEASURABLE BY THIS INSTRUMENT, not merely unmeasured**, and G7 publishes a lower bound only.
What is validatable is the classifier's **specificity** — that it never *invents* a quota refusal —
and §S5.3 supplied the live artifact to control it with.

---

## 11 · The fire path can now fire — built, and validated by a live create (2026-08-09)

§10.4's NEXT STEP, in the order it forced: the create FIRST, the fire second. Landed `1b2b8a94`.

`handoff-fire.sh --cloud` now issues a create and declares it. The create itself was **factored out
of `cloud-bundle-probe.sh:fire_one`** into `scripts/lib/cloud-create.sh`, per §10.4's instruction
not to write it a fourth time; the probe now sources that library. The branch is
`scripts/lib/cloud-create.sh` + a 176-line branch in `handoff-fire.sh` placed BEFORE the typed
command is composed — everything below that point is box-local machinery a cloud fire must not
reach (no pane to spawn, no composer to type into, no engagement to verify, no pane uuid to
register). **35 tests**, in `tests/cloud-create-lib.bats` (19, new) and `tests/handoff-fire-cloud.bats`
(8 → 16).

### 11.1 · The live fire, step by step

Account `next3`, from a worktree, 2026-08-09 23:14Z:

| step | outcome |
| --- | --- |
| capacity gate | ADMIT — account headroom read from `claude-accounts --route general`; box load/RAM not evaluated |
| create attempt 1 | **`refused-bundle`** — §S5.3's marginal ~95 MiB-against-100 MiB upload, reproduced live on the first try |
| create attempt 2 | **`session_01Kpc1kwHjwsRjERad1tTDuG`** |
| declare | immediate, carrying branch + **owning account** + repo + url + item |
| exit | **0** |
| `cc-cloud show` | `state=BOOTING · no ref yet, 1m into a 15m budget` — the state function's first honest verdict on a session this path fired |

**The retry is load-bearing, and this fire is the proof rather than the argument for it.** Attempt 1
refused; without the bounded retry the fire would have reported a named refusal and stopped, and
§10.4's frozen DoD would still be open. §S5.3's "roughly 50-75% per attempt, reaching a session on
attempt 2 of 4 twice over" reproduced on the very first live use.

**The push half did NOT complete, and the instrument's own terminal verdict is below (§11.4).**

### 11.2 · Three findings, each measured rather than assumed

**1. `refused-other` was never measuring an unknown refusal — it was measuring the normaliser.**
Across both probe ledgers, all 10 rows in that bucket have an identifiable cause and NONE is
unknown: 7 real bundle refusals and 3 rig faults. A TUI positions text with cursor motion instead of
runs of spaces, and every classifier pattern contains a space, so a refusal rendered that way
matches nothing and is filed as a non-verdict — the instrument lying in the one direction that looks
like honest abstention.

🚨 **The producer is `scripts/lib/pty-run.py:strip_ansi`, NOT the probes' own `normalise()` — and
the obvious attribution would have sent the fix to the wrong file.** `cloud-bundle-probe.sh` had
already learned this lesson and handles both `CSI n C` and `CSI n G`; its own fused ledger row
predates that fix. Replaying the real bytes through `strip_ansi` verbatim reproduces the ledger
shape exactly — `Error:\x1b[8GBundle\x1b[15Gupload…` → `Error:Bundleuploadfailed:Socketis closed`,
fused where the sequence was G and spaced where it was C, which is precisely the
`Error:Bundleuploadfailed:…Pleasesetup  GitHubon` signature in `ceiling-probe.jsonl`. The shared
allocator converted cursor-FORWARD and let cursor-ABSOLUTE fall through to its generic delete,
**one line below a comment lecturing about that exact defect**. Fixed at the source, with the
pre-fix behaviour pinned as a RED control (`tests/cloud-create-lib.bats` case 2) so the wrong file
is not re-fixed later.

**2. The declared branch was being GUESSED, and a guess here is a permanent false verdict.**
Baseline measured before the fire: `git ls-remote --heads origin 'claude/*'` returns **zero rows** —
no cloud session had ever pushed — and the one prior fire-shaped declaration on this box names
`claude/fire-20260809T101645Z-78351`, a branch with **no producer anywhere in the tree**. Nothing
would ever have pushed to it, so it reads C1 NOT-STARTED forever: §10.2c's hazard with the sign
flipped, and the same failure this document is organised against — a confident verdict computed
from evidence that has nothing to do with the session. The fire now **assigns** the branch and the
payload instructs the push, which also closes §10.2c from the other side: the name is unique per
fire, so unlike `--branch main` (where trunk's own background traffic reads as a heartbeat forever)
nothing but that session can advance it, and O2 becomes a real signal.

**3. `created-unidentified` is its own outcome, because both ways of folding it lose the fact that
matters.** A create can succeed while id extraction fails. Folding it into `created` hands the
caller an empty id to declare; folding it into a refusal reports "no session" while one is running.
It is neither — it is a live session spending an account's quota that no local instrument can
observe, address or reap, and the 600 s orphan reaper cannot see it either. It exits **11**, names
the account, and prints the exact `cc-cloud declare` line to recover it by hand.

Two smaller ones, both from `fire_one` and both harmless in a probe that only tallies: a bare
`session_…` counted as a create (on the fire path that declares a session which does not exist), and
the CSI sweep used a hand-written character class instead of the ECMA-48 grammar, so a private-mode
sequence *inside* a phrase broke the match. Both now carry RED controls proving the predecessor got
them wrong.

⚠️ **The probe keeps the SINGLE-attempt entry point, and that is not an oversight.**
`cloud-bundle-probe.sh` exists to measure the PER-ATTEMPT success rate; wrapping its attempt in the
retry would report the success of up to N attempts under the name of one, inflating the rate and
erasing the marginality it was built to measure. `cc_cloud_create_once` is the measurement, the
retry is a consumer's policy on top of it.

### 11.3 · Known residual — `paths=` is empty, so a landed cloud branch reads ELIGIBLE forever

The declaration written at fire time carries `paths=` empty, because the firing side genuinely does
not know which files an off-box session will touch. `scripts/cloud-reconcile.sh:landed()` treats
empty paths as *"nothing declared ⇒ landing is not assertable"* (`:137`) and returns 1, so
`classify()` files the branch **ELIGIBLE** — including after it has actually landed. Landedness is
decided BY CONTENT in this repo precisely because counts lie, and with no paths there is no content
to check.

This is recorded rather than fixed, and the reason is that the two available fixes are both worse
than the residual: inventing a path at fire time would be the dispatcher asserting something it
cannot know, and the alternative — an ancestry test (`is the branch tip reachable from trunk`) — is
the count-shaped oracle `scripts/land-verify.sh:6-11` already refuses. The honest fix is for the
cloud session to declare its own paths on the way out, which needs a channel that does not exist
yet (§9.1: the cloud→here arm is a different mechanism, permanently). Until then a landed
`claude/*` branch stays eligible and can be re-offered; `ship-land` finds an empty diff and refuses,
so the cost is a wasted invocation rather than a wrong land.

### 11.4 · The round trip does NOT complete — `NOT-STARTED`, and what that does and does not prove

The instrument's own terminal verdict on the first fire, at the end of its budget rather than at an
arbitrary give-up point:

```
state=NOT-STARTED
detail=no ref after 15m (boot budget 15m)
recover=open https://claude.ai/code/session_01Kpc1kwHjwsRjERad1tTDuG
```

`git ls-remote --heads origin 'claude/*'` returned **0** throughout, and still does. So **§10.4's
frozen DoD is half closed**: `handoff-fire.sh --cloud` creates a declared cloud session (proven),
and one item does NOT yet traverse `create → execute → claude/* push → cloud-reconcile → land`.

🚨 **This is `NOT-STARTED`, which under §4.1 means "the declared ref never appeared" — NOT "the
session did nothing".** The distinction is this document's founding one and it must not be quietly
collapsed here of all places. What is established: a create happened, a bundle was uploaded (attempt
1's `Bundle upload failed` is positive evidence that the CLI took the BUNDLE path, not a GitHub
one), the session was declared, and no ref reached the remote inside 15 minutes. What is **not**
established: whether the VM executed at all, whether it attempted the push, and what it saw if it
did.

**And this box structurally cannot find out.** §9.1's asymmetry is permanent: the send arm works —
`cc-notify --cloud` delivered a status probe to this very session, correctly routed through the
owning account (`{ok:true}`, recorded in `<id>.sends`) — but "queued is not read", there is no
off-box cursor, and the session's reply lands in a transcript no local instrument can open. A probe
was sent asking it to paste `git remote -v`, its branch, and any push error. **The answer is
unreachable from here by construction, not by omission.**

⚠️ Two smaller things the fire settled on the way past, both worth more than the negative result:

- **The retry is what produced the session at all.** Attempt 1 refused with a live
  `Bundle upload failed: Socket is closed after 3 attempts`; attempt 2 created. §S5.3's 50-75%
  reproduced on first use, and a fire path without the bounded retry would have reported a named
  refusal and stopped.
- **`cc-notify --cloud` self-diagnosed a binary-version fault correctly**, and it is a trap worth
  recording: the default resolution picked `~/Library/pnpm/claude` (the 2.1.114 pin, which has no
  `--cloud`), and rather than reading `unknown option '--cloud'` as a bad address it reported
  `verdict=cloud-transport-unavailable reason=flag-unsupported`, said the id was **UNVERIFIED, not
  invalid**, and named the fix (`CC_CLAUDE_BIN` at a 2.1.220+ binary). That is §10.2d's
  actuator-as-arbiter rule paying off live — a `strings` pre-check would have had to guess.

**→ NEXT STEP, and the fire is what makes it the right one.** §10.4 said to install the Claude
GitHub App only once a fire proved bundle mode was the blocker, "not before", because an App
install read from silence tells you nothing. The fire has now supplied the missing half: the create
demonstrably took the bundle path, and nothing came back. Installing the App on this repo makes the
create use a `git_repository` source and **bundle nothing** — which simultaneously removes the ~95
MiB marginal upload (the retry's whole reason for existing) and gives the VM an authenticated
remote to push to. It is a GUI consent flow on the operator's own GitHub account, so it is
**operator-only** and is filed as such rather than described here.

If a session fired AFTER the App install still leaves `claude/*` empty, that result is meaningful in
a way today's is not — bundle mode would be eliminated as the cause, and the next suspect is the
VM's push credentials, which §7.4 already showed are restricted (a cloud VM cannot write
`refs/cc/*` at all).

*(The declaration is deliberately left un-retired: `NOT-STARTED` with a recover URL is a true
statement, and retiring it would stop the three abstaining oracles treating the id as off-box while
the session may still exist. It costs one row.)*

---

## 12 · The one command — `bin/cc-offload` (2026-08-10)

Everything §1–§11 built worked and **none of it was reachable**. Offloading one item required
knowing five tool names, one env var whose value must be the literal string `on`, and which of two
adjacent exit codes means *a session is burning quota that nothing local can see*. That is not a
usability complaint — an entrypoint nobody can drive is
`[[conclusion-must-reach-the-enforcing-store]]` in its purest form: eleven sessions were fired
across §7.5 and §11, and the capability never entered the operator's hands.

`bin/cc-offload` is the entrypoint over the existing parts. **It owns no state and computes no
verdict.** Suite: `tests/cc-offload.bats`, 31 tests.

| verb | delegates to | what it adds |
| --- | --- | --- |
| `setup` | `cc-cloud preflight` · `claude-accounts --route` · websetup state | grades 8 preconditions PASS/FAIL/**UNKNOWN**, each FAIL carrying its own one-line fix |
| `up --task <f> [-n N]` | `handoff-fire.sh --cloud` | supplies the literal `on` opt-in, chdirs so the bundle is the repo, maps exit 10/11 to what the operator must do |
| `ls` (default) | `cc-cloud list --json --state` | the board — state verbatim from the arbiter, coloured, never re-derived |
| `watch [--pane]` | itself + `kitty-split-launch.sh` | live redraw; `--pane` puts the board in its own kitty split |
| `say <id\|all>` | `cc-notify --cloud` | fans out to live sessions; reports **QUEUED**, never delivered |
| `land [--all]` | `cloud-reconcile.sh` | read-only by default; `--all` supplies `CONFIRM=1` |
| `open` · `gc` | `cc-cloud show` · `retire` | the escalation URL; retiring terminally-dead declarations behind `CONFIRM=1` |

**The design rule, and the only one that matters here:** never re-derive a verdict a sibling already
computes. This repo has paid for that twice — a checker holding its own stale copy convicted a green
asset (`[[uniform-error-ratio-indicts-the-model]]`), and two sibling auditors over one population
disagreed because only one modelled a state (`[[sibling-auditors-must-share-the-state-model]]`). So
`ls` calls `--state` and prints what it gets; a test pins that by feeding it a state string
cc-offload has never heard of and asserting it survives to the output.

### 12.1 · The laundering defects, which are the only ones available to a composer

cc-offload cannot be *wrong* — its siblings own every answer. It can only take an honest refusal and
re-emit it as success. Each of the four is pinned by a test with a positive control:

- **A sensor that could not run must not degrade to "nothing is there."** `cc-cloud list --json`
  prints **zero bytes** for an empty store, so an empty read is ambiguous *by construction*. Reading
  it as "no sessions" reports a healthy silent fleet while N sessions burn quota —
  `[[lookup-miss-is-not-absence]]`. cc-offload re-probes and returns UNKNOWN with exit 1.
- **UNKNOWN renders as the word UNKNOWN.** A blank cell in a table of live sessions reads as
  absence, which is the exact ambiguity §4 exists to refuse.
- **A queue ack is never a read.** `say` prints `QUEUED` and the reason; `--receipt` stays
  cc-notify's exit 7. `[[claimed-outcome-vs-checked-outcome]]`.
- **Exit 11 is louder than a failure and is never retried.** 10 = nothing exists (safe). 11 = a live
  session nothing local can observe, address or reap. A retry buys a *second* invisible session, so
  `-n 3` fires exactly once on an 11 — pinned by counting stub invocations.

### 12.2 · The GitHub App became measurable — one-directionally, and the fire is what measured it

§11.4 filed the App install as the next step. Two things are now settled.

**It is NOT detectable read-only, and the wall is a credential CLASS, not a missing scope**
(measured 2026-08-10). Every installation endpoint refuses a `gh` token: `/repos/:owner/:repo/
installation` → 401 *"A JSON web token could not be decoded"* (needs an App JWT); `/user/
installations` → 403 *"must authenticate with an access token authorized to a GitHub App"*. `gh`
holds a `gho_` **OAuth** token, so no scope reaches those. The one user-token path GitHub documents
— `GET /orgs/{org}/installations`, needing `admin:org` — **cannot apply**: `renchris/
claude-infrastructure` is owned by a **User**, and GitHub ships no user-account analogue. The
check-suites proxy can only ever prove *present*; its silence proves nothing, so `setup` reports
UNKNOWN and never asserts absence from it.

**But a create settles it, one-directionally, and one did.** The CLI bundles only when it has no
`git_repository` source — so `refused-bundle` **proves** the App is absent, while any other refusal
says nothing about it. Live fire through `cc-offload up`, account `next4`, 2026-08-10 06:34Z:

```
attempt 1/3 → refused-bundle · attempt 2/3 → refused-bundle · attempt 3/3 → refused-bundle
Error: Bundle upload failed: Socket is closed after 3 attempts. Please setup GitHub on https://claude.ai/code
exit 10 — NOTHING is running, safe to retry
```

Three for three, where §S5.3 measured ~50-75% per attempt and §11.1 reached a session on attempt 2.
The bundle is ~95 MiB against a 100 MiB cap: **marginal by construction**, which is why the rate
moves. `up` therefore writes `~/.claude/autonomy/cloud/github-app.observed` on a bundle refusal and
`setup` reads it, so the evidence — which cost a create attempt — is bought once. The marker is
written **only** in that direction; a test pins the negative control by changing the refusal reason
to `refused-quota` and asserting no marker appears.

**Consequence for the whole plan: this is the ONE blocker, and it is operator-only.** It is a GUI
consent flow on the operator's own GitHub account, filed as `cc-backlog needs` `87619d846d88` rather
than described here. Installing it removes the upload from the create path entirely *and* gives the
VM an authenticated remote to push to — i.e. it addresses both §11.4's open halves at once. Until
then `setup` exits 3 and says so in one line, which is the honest state: this box **cannot** offload
yet, and it now names why in the first command an operator runs.

### 12.3 · What is still not closed

- **The round trip remains unproven** (§11.4 unchanged) — no `claude/*` ref has ever appeared, and
  today's fire never reached a session to try. What today adds is the *cause*: bundle mode, proven,
  rather than inferred from silence.
- **§11.3's empty `paths=` residual is untouched**, so a landed cloud branch still reads ELIGIBLE
  forever. `cc-offload land` inherits it; the honest fix still needs the cloud→here channel that
  §9.1 says cannot exist.
- **`gc` is new surface, not a new verdict.** It retires only what `cc-cloud` already classifies
  terminal (`NOT-STARTED`/`ABANDONED`), behind `CONFIRM=1`. 17 of the 19 live declarations are
  probe/fire junk from §7.5's eleven sessions; retiring them is one command but it is the
  operator's, because a retired id stops being reconciled.

### 12.4 · The App went in, the create got clean — and the session STILL never pushed

§11.4 named the decisive experiment and said the result would be *"meaningful in a way today's is
not"*. It has now been run, and it is.

The operator installed the Claude GitHub App on the repo at ~07:10Z. The immediately following fire,
same command, same brief, account `next3`:

| | before the App (06:34Z) | after the App (07:12Z) |
| --- | --- | --- |
| create | `refused-bundle` **3/3** | **`session_018YsHzozWKCzxx5cifEQw1L` on attempt 1**, no bundle |
| `git ls-remote --heads origin 'claude/*'` | 0 | **0** |
| terminal verdict | `NOT-STARTED — no ref after 15m` | **`NOT-STARTED — no ref after 15m`** |

**The create half is fixed and the execute half is untouched.** Bundle mode is now *eliminated* as
the cause rather than merely suspected: the upload is gone, the create is clean and first-try, the
App is independently confirmed present (a `claude` check-suite now appears on trunk — the proxy's
one sound direction, §12.2), and the ref count did not move. §11.4's fallback suspect is therefore
promoted to the live hypothesis: **the VM's push credentials** (§7.4 already showed a cloud VM
cannot write `refs/cc/*`), or the VM not executing the brief at all.

🚨 **And that is now the SAME finding as §7.5's, which makes it the generator-class one.** Thirteen
sessions have been created across this document; **zero have ever acted.** Two distinct create
blockers have been found and fixed — the ceiling probe's, then bundle mode — and neither moved the
number, because neither was ever the binding constraint. The scarce thing was never a session id;
it is an **observed cloud execution**, and this box structurally cannot see one (§9.1's asymmetry:
the send arm delivers, `{ok:true}` means queued, and the reply lands in a transcript no local
instrument can open).

**→ NEXT, and it is deliberately NOT another fire.** Two creates bought the same verdict today;
a third buys it again. The next step is the first one that could produce *new* information, and it
is operator-shaped because only the web UI can see inside a session: **open
`https://claude.ai/code/session_018YsHzozWKCzxx5cifEQw1L` and read what it did** — whether it ran
the brief, whether it attempted the push, and what it saw. That single observation discriminates
"never executed" from "executed and could not push", which is the fork every remaining hypothesis
hangs on. Filed rather than described.

*(`cc-offload setup` reads `✓ READY` and that is honest — every precondition it can measure is
green. READY is a statement about the FIRE path, which is now genuinely unblocked end to end; it
has never claimed the round trip, and §4's whole discipline is that the two are different facts.)*
