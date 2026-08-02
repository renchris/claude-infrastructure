# Armed-Succession Lifecycle — design (READ-MOSTLY investigation, 2026-08-01)

**Status**: PROPOSAL. Nothing here is built. The handoff rails retire live panes; a bug loses an
operator's session, so this document is the ratification gate, not a changelog.

**Provenance**: 14-agent investigation (7 mapping lenses, each adversarially verified) plus
first-hand reads of the 2026-08-01 incident artifacts. Every claim below was re-checked at source
by a second agent whose only job was to refute it; the refutations are folded in and named where
they changed the answer.

> ⚠️ **Anchors are CONTENT, not line numbers.** `scripts/handoff-fire.sh` was being edited by a
> concurrent session throughout this investigation — it moved 4537 → 4553 → 4559 lines mid-audit
> and every verifier independently reported the same drift. Grep the quoted string; do not trust a
> line number in this document or in any report it cites.

---

## 0 · The finding in one line

**A fire is a record; a recycle is only a process.** The fire path writes a durable per-pane
lifecycle record (`~/.claude/cc-fired/<pane>.json`, schema 2, carrying `firedStartedAt` /
`engagedAt` / `engageProof` / `closedAt` / `succession`) plus a `handoffs.jsonl` event. The recycle
path writes **neither**. Its entire durable footprint is a teardown marker whose declared purpose is
the *opposite* of invalidation — it tells the crash watchdog the pane's death was planned.

So an armed recycle is an action with no name, no owner, no reader, and no handle. That is why a
scope pivot became an operator fork: there was nothing to supersede, because there was nothing
there.

---

## 1 · What the incident actually was — and why it is worse than reported

The armed watcher (pid 94001) **never fired**. It hit its 600 s ceiling, wrote

```
!! CC still alive after 600s — giving up. Relaunch manually: …
```

to stderr — i.e. to a TMPDIR log — and `exit 1`. Three things make this the worst of its six
terminal states:

1. **It is the quietest.** No `emit_fire_event`, no `cc-notify`. (Verifier correction: the report
   that called it "the loudest of the silent three" had it inverted — the 90 s path at least types
   `# HANDOFF RELAUNCH FAILED` *into the pane*. The give-up leaves nothing anywhere a human looks.)
2. **The give-up branch sits ABOVE the binding of `$5`/`$6`/`$7`.** At the moment it fires, `RCWD`,
   `RCY_OLD_SID` and `RCY_MARKER` are structurally unbound. It is not declining to emit telemetry;
   it *cannot* — it returns before the watcher has finished reading its own arguments. Any fix must
   hoist those three bindings above the poll loop.
3. **The verdict may not even be true.** `cc_alive` is `ps -o comm= -t <tty> | grep -qE 'node|claude'`
   — the exact tty-grep false-positive class that the `SUCCESSOR_PIN` work already convicted and
   fixed on the self-close path. Any long-lived `node` the pane owns (a dev server, a `vitest`, an
   `npx`) holds `cc_alive` true forever. "CC still alive after 600s" is an inference from a process
   *name*, not an observation of CC.

**Bounded second-order damage** (verifier correction — the first read called it indefinite): the
teardown marker is honored on a 30-minute freshness window (`lead-crash-watchdog.sh`, `-mmin -30`;
`session-continue.sh wf_teardown_marked`, 1800 s). The watcher gives up at arm + 600 s. So there is
a **~20-minute window in which a still-live, un-recycled session's genuine crash is classified
`RECYCLE/deliberate-teardown` instead of `CRASH`.** Bounded, real, and previously unnamed.

### Prevalence — the un-fakeable measurement

Census of every real recycle watcher log surviving in TMPDIR (the store is swept at `-mtime +2`, so
this is a **2-day window**, not all time):

| Outcome | n |
|---|---|
| ENGAGEMENT CONFIRMED | **1** |
| `it2 relaunch write failed twice` — pane exited, relaunch never typed, **left at a bare shell** | **5** |
| gave up at 600 s (the incident) — pane alive, succession silently dead | **1** |

**One of seven succeeded. None of the six failures produced a `handoffs.jsonl` row, a `cc-fired`
record, a page, or anything any hook reads.**

Two honesty caveats, both load-bearing:
- Four of the five write-failures fall in one 10-minute window (01:26–01:36) and each log shows a
  doubled `could not disarm zsh spell-correction` — that is one it2/AppleScript breakage, not five
  independent failures. There has since been churn in exactly that area (`a10a0461` *"iTerm2 was
  addressed by a name that only resolves while it runs"*), so the **rate** may already be better.
- The **silence is not rate-dependent.** Whatever the success rate becomes, every failure mode
  except one remains invisible, and the only artifact self-destructs after 48 h.

### The ledger proves the blind spot structurally

`~/.claude/logs/handoffs.jsonl` holds 1082 rows in three classes — `admitted`, `refused`,
`self-retire-peer`. **`grep -c recycle` = 0.** `emit_fire_event` has exactly four call sites; the
two recycle ones are both *failure* branches, and the **success path emits nothing**. So
`class=="recycle-*"` is a pure failure sample with no denominator — a rate that cannot be computed
even in principle. And the recycle branch runs before `CHOSEN` and `FIRING_SID` are assigned, and
neither is exported, so a recycle row would be unjoinable even if one existed.

**Two paths, very different visibility** (verifier correction that sharpens the whole finding): the
*deterministic* path — `waiting-recycle.sh` firing the actuator autonomously — **does** write
`recycle-events.jsonl` + an `idl.jsonl` row carrying `prompt_file`. The *model-fired* path
(`/handoff`, the skill, what the incident used) writes **only** the teardown marker. The path the
agent is instructed to use is the blind one.

---

## 2 · Arm-time state vs fire-time checks — the gap, precisely

**Frozen at arm (11 items):** pane sid · tty path · CMDFILE path · the whole `$CMD` line · `$PWD` ·
the worktree fallback · pre-recycle CC sid · `RECYCLE_MARKER` · the payload copy `PF_NB` (a `cp`,
plus trailers) · launcher/account/model/effort · the watcher's inherited environment.

**Checked at fire (2 things):** is a `node|claude` process on the tty; does `$PWD` still exist —
and the second is an `echo` with **no branch and no abort** (`test -d` + a warning; the comment
says so explicitly: *"EVIDENCE, not control flow"*).

| Arm-time premise | Re-validated? |
|---|---|
| Payload content is still what the session wants said | **No.** `$CMD` does `"$(cat $QP)"`, so the file *is* read at relaunch — but `$QP` is a frozen `cp`, and **nothing in the system ever writes to it after arm.** Re-reading an immutable snapshot is not re-derivation. |
| The command is still right (account, model, effort) | No — read verbatim. |
| The cwd is still valid | Existence only, advisory. Cannot detect *wrong* directory (branch switched, worktree recreated). |
| The relaunch should still happen at all | **No.** No disarm file, no lock, no generation check, no kill-switch read anywhere in the watcher. |
| Scope is unchanged | **Never checked and unknowable** — scope is not among the 11 frozen items. |
| The session still wants it | No. The design is the inverse: the watcher's success condition *is* that session's death. |

**The disarm handle does not exist.** `WATCHER_PID` occurs four times, all foreground inside
`recycle_fire`, and is **never written to any file**. The two disarms that exist (`heartbeat never
appeared`, `/exit untypeable`) both fire *within the arming turn*, while the arming process is still
alive. **There is no post-arm invalidation path of any kind.**

### But the mechanism is closer than it looks — three corrections that make the fix small

1. **A generation token already exists.** `RECYCLE_MARKER` is minted on every non-dry recycle,
   written into the payload, *and* passed as arg 7. Both TMPDIR filenames embed the arm epoch
   (`handoff-recycle-133-1785631453-…`). `(pane, arm-epoch)` is already unique-per-generation.
2. **A mutable per-pane file is already on the watcher's fire-time read path.** `recycle_engaged`
   calls `cc_sid_for_pane`, which greps `~/.claude/cc-registry/<pane>.json`. So "no channel exists"
   overstates it: no *content* encodes scope, but a **read path already reaches a session-owned,
   mutable, per-pane JSON file.**
3. **The watcher survives.** It is `setsid` with its own pgid and PPID 1 — *"immune to group kill
   and parent-tree walk alike, no race to win"*, proven empirically by the incident log (it outlived
   the `/exit` by a full 600 s). So the objection *"no writer exists for the terminal transition"* is
   **false**: the watcher is a surviving writer. It simply has **no `trap`** and four unlogged exits.

---

## 3 · The lifecycle model

### Does "armed" belong on disk rather than being a detached process with a frozen payload?

**Both — they answer different questions, and conflating them is the design error to avoid.**

- **Keep the process.** It is the *actuator*, and it is correct. Its setsid survivability is
  hard-won (two 2026-07-13 strandings bought it), and nothing about a disk record replaces the need
  for something that watches a tty and types.
- **Add the record.** An arm without a record is an action nobody can name, supersede, audit, or
  see. Everything the rest of the system needs — disposition reads, readouts, GC, the next arm — is
  a question about the *record*, never about the process.

The rule: **the process actuates; the record decides.** The watcher must consult the record
immediately before typing and obey it.

### States, transitions, owners

| State | Set by | Meaning |
|---|---|---|
| `armed` | `handoff-fire.sh --recycle`, foreground, before `/exit` | a relaunch will happen when this pane's CC exits |
| `fired` | the watcher | relaunch typed and engagement confirmed |
| `expired` | the watcher | ceiling reached — CC never exited |
| `failed` | the watcher | typed but never engaged / never booted / write failed |
| `disarmed` | the session, or a superseding arm | the premise no longer holds; do not fire |
| `superseded` | a later arm on the same pane | a newer generation owns this pane |
| `abandoned` | a boot-time sweep | record `armed`, watcher pid dead, no terminal transition — the box rebooted |

Owners, stated so no state is orphaned:
- **arm** — the arming process, synchronously, *before* the heartbeat gate (so a failure to record
  is a failure to arm, not a silent arm).
- **every terminal transition** — the **watcher**, via a `trap` so that all six-plus exits are
  covered rather than the current two. This is the correction that makes the design feasible: the
  watcher provably survives, so it can be trusted to close its own record.
- **`abandoned`** — a boot/session-start sweep, the only case the watcher cannot write because it
  no longer exists.

**What invalidates an arm:** a scope pivot (§4), a superseding arm, an explicit disarm, or the
record's own generation being stale. **What must NOT invalidate it: a TTL.**

### The hazard this design must refuse: TTL-as-reaper

This fleet has already paid for this lesson once — `scripts/land-lock.sh`, where a TTL stale-reap
OR'd over the liveness probe turned a **mutex into an admission rate-limiter**, and where the TTL
was read by the *acquirer* so a holder-side override protected nothing. The transferable rules:

- **Liveness, never age.** An arm is invalid because its *premise* changed or its *watcher* is gone
  — never because a clock elapsed. A 10-minute-old arm on a live watcher is perfectly valid.
- **Verify identity inside the reap.** pids recycle. Any sweep that concludes "watcher dead" must
  re-verify `(pid, start-time)` — `ps -o lstart=`, the exact defense land-lock already carries.
- **Never signal a pid you reaped *because it was dead*.** That is how you kill an innocent process.
- **The record and the watcher can diverge in both directions.** Record `armed` + watcher dead ⇒
  `abandoned` (sweep). Watcher alive + record `disarmed` ⇒ the watcher must **obey the record** —
  which is exactly why it must re-read it before typing, not merely at arm.

### One store constraint, learned the hard way

**Do not put the arm record in `~/.claude/cc-fired/`.** `bin/cc-reaper` keys auto-reap on **bare
file presence** (`[ -f "$FIRED_DIR/$pane.json" ]`) plus `.firedBy`/`.firedAt` — it does *not* read
`selfRetire`, despite a test comment claiming it does. Any new record dropped there is read as a
fired-peer stamp, with no field available to exclude it. Use a sibling store with the reciprocal
`(pane, sid)` dual-key idiom the teardown markers already use.

---

## 4 · The smallest change that makes a scope pivot self-resolving

**Delete the fork rather than add a prompt.** The operator was handed a choice
(*"your armed recycle is stale — disarm, or let it fire?"*) only because two things were absent:
nothing surfaced the arm, and nothing could act on it. Restore either and the question disappears;
restore both and it cannot recur.

Three changes, smallest first. **(A) alone resolves the incident.**

### (A) Make a second arm supersede the first — the fork-deleting change

Persist the arm record (pane, sid, watcher pid + start-time, arm epoch, marker, payload path,
state). Then make `--recycle` **supersede by default**: on arm, read any existing record for this
pane; if its watcher is provably live, disarm it (kill by verified `(pid, lstart)`), stamp the old
record `superseded`, and arm the new one.

A scope pivot then resolves by the lead doing the *normal* thing — arming a succession for the new
scope. No question, no disarm ceremony, no fork. The old succession dies because a newer one exists,
which is exactly what "the scope changed" means.

This also fixes an unrelated latent bug: today, arming twice on one pane leaves **two live watchers
racing to type into the same shell.**

### (B) Make the payload a pointer to live state, not a snapshot

The staleness class exists because `PF_NB` is a `cp` that nothing ever writes to again. The
infrastructure already has the live equivalent: `dod-persist.sh get` is documented as *"SSOT read
for the /handoff + waiting-recycle DoD-carry."* If the relaunch payload is re-derived from the DoD
store at fire time rather than frozen at arm time, a scope pivot propagates **automatically**,
because the session already persists scope changes there as it works.

This deletes the staleness class instead of detecting it — strictly better than any staleness check,
and it removes the need for a `stale` state entirely.

### (C) Close the observability holes the incident exposed

- Hoist the `$5`/`$6`/`$7` bindings above the poll loop so the give-up branch can see its own
  arguments.
- Add a `trap` so **every** watcher exit writes its terminal state to the record and emits a
  `handoffs.jsonl` event — including **the success path**, so the class finally has a denominator.
- Page on expiry the way `recycle-dead` already pages. An armed succession that expires while the
  operator is at the pane is exactly a `cc-notify`-worthy event.
- Fix `cc_alive` to the `SUCCESSOR_PIN` standard (`(sid, pid)` pinned at arm, re-verified at the
  instant of irreversibility). The pattern is already written, already tested, and already used by
  the sibling watcher — the recycle path just never adopted it.
- Reconcile the teardown marker on a non-fire terminal state, closing the ~20-minute crash-
  misclassification window.

**Explicitly NOT proposed:** a staleness TTL, a new disposition R-code (§6), a new prompt, or any
question put to the operator. Each is a fork where a decision belongs.

---

## 5 · Which decisions are the infrastructure's, and which are genuinely the operator's

The second signal holds, and its mechanism is sharper than "two masks on one defect."
`anti-deference-nudge.sh` and `completion-assert.sh` are the **same function with opposite signs
over an identical, incomplete state vector**: both read only `{DIRTY, UNLANDED, REMAINDER}` from
`wrap-ledger.sh`; both encode the universal rule `clean ∧ unlanded ⇒ drivable`. One punishes
*asking*; the other punishes *not doing*. In reso, asking is correct — so the model is squeezed from
both sides toward the single action that spends the operator's money without consent.

### The policy is already machine-readable, and no hook reads it

This is the finding that makes the fix small. Verified first-hand:

| Repo | `commands/ship.md` frontmatter | Effect |
|---|---|---|
| `reso-management-app` | `disable-model-invocation: true` | the model **cannot** invoke `/ship` — the operator's call |
| `claude-infrastructure` | *(absent)* | the model can — auto-ship |

**The policy is written down, in machine-readable form, in the one place the harness enforces it,
and it is already exactly correct.** Meanwhile every autonomy hook is repo-blind by construction and
hardcodes `/ship` as universally right. The harness forbids the action the hooks demand. And
`bin/cc-dispatch` — the only code with *any* per-repo landing awareness — tests `[ -f
.claude/commands/ship.md ]`, i.e. *"does a ship rail exist"*, when the question is *"may I fire
it"*; those two diverge in exactly one repo. The correct-for-reso branch is already written and
already implemented, keyed off the wrong test.

Compounding it: `hooks/lib/idl-log.sh` records no `cwd`/`repo`, so of 128 `completion-assert` fires
an unknown number are reso false positives, and **no query over the existing telemetry can separate
them.** The false-positive rate in the one repo where these hooks are wrong is not merely unmeasured
— it is unmeasurable as built.

**The fix is one field, not a new subsystem**: a `SHIP_POLICY=auto|ask` on `wrap-ledger.sh`,
sourced from the frontmatter flag that already exists. All four consumers (`anti-deference`,
`completion-assert`, `operator-readout`, `cc-dispatch`) already delegate ground truth to that one
place. Under `ask`, `UNLANDED` stops setting `contra` and instead files
`cc-backlog needs "/ship reso" --run "/ship"` — converting a block into a `👤` rung. Both the
`needs` verb and the `yours` render class already exist; nothing new is built.

### (1) Genuinely the operator's — the enumerated set

A real taxonomy exists in code; it is not prose. `scripts/gate-manifest.sh` classes C1–C10 as
`presignable` (C1–C5, C7) / `conditional` (C6, C8) / **`excluded` (C9, C10)**, and
`gate-classify.sh` returns C for *"human-only, never demotable to A."*

| # | Decision | Why it is theirs | Anchor |
|---|---|---|---|
| 1 | `/ship` in `reso-management-app` | each land bills a real Amplify + Fly deploy | `ship.md:3` `disable-model-invocation: true` |
| 2 | Money **commitment** (not spend *limit*) | irreversible external obligation | `gate-classify.sh` `C_SURFACE` |
| 3 | Credentials, `sudo`, GUI-only, physical acts | the agent structurally cannot | C10, `activation-watch.sh` *"operator hand-steps"* |
| 4 | Editing `settings.json` / live hooks / launchd in place | C10; the agent never loads launchd | `cc-dispatch` rails string |
| 5 | Destructive migrations (`DROP TABLE`/`COLUMN`) | data loss, unrecoverable | reso CLAUDE.md G2 |
| 6 | Auth / session / cookie / token handling | security blast radius | reso CLAUDE.md G2 |
| 7 | Navigation pattern, DB-timeout constants | named architectural invariants | reso CLAUDE.md G2 |
| 8 | A genuine value fork (two defensible options, different outcomes) | preference, not fact | `gate-classify.sh` B/C split |

That is the whole set. It is short, it is enumerable, and **seven of eight are already encoded
somewhere a machine can read.**

### (2) Structurally the infrastructure's, currently escalated

| Decision | Missing state |
|---|---|
| **Should a stale armed succession fire?** (this incident) | the arm record — §3 |
| Land clean, gate-green, verified work in a non-billed repo | none — `gate-classify.sh` already returns **A**; the hooks simply never ask it |
| Is `📦` drivable *here*? | `SHIP_POLICY` on the ledger — the source bit already exists |
| Which repo did a hook fire in? | `cwd` on the IDL record |
| Did a recycle succeed? | a success-path event — the class has no denominator |

**A load-bearing corroboration:** across the decisions store, operator vetoes of agent-classified
work number **zero** — all 11 class-B vetoes were resolved agent-side. The escalations are not
catching operator disagreement. They are spending round-trips on decisions the operator was never
going to decide differently.

---

## 6 · Should `handoff-disposition.sh` read armed-succession state?

**A field, yes. An R-code, no. And the field must never flip the exit.**

The disposition taxonomy (`commands/handoff.md`) is closed by explicit contract — *"No other reason
exists… a candidate 6th reason is a PROPOSAL in the plan's status log, never a silent addition."*
Every code answers one question — **"why must THIS session stay OPEN?"** — and every row discharges
into `re-emit`.

An armed succession is the **mirror image**: not a reason to stay open, but a pending *outbound*
action about what happens when the session closes. Filing it as an R-code would be a category error
twice over:

- It would file, under *reasons to stay open*, a thing whose whole purpose is that the session
  **closes**. An armed pane is precisely a pane that should die.
- **It has no possible emitter.** An expired arm is discovered at `predecessor_exit + 600 s`, by a
  detached process, about a session the contract already declares closed (*"after a `--recycle` fire
  the recycle itself IS the close"*). A disposition code with no one alive to emit it is not a code;
  it is a wish.

The precedent confirms the shape: R-PING is the one row that handles a *peer's* death, and it does
not spawn a new code — it **escalates to R-DECIDE**. It can do that only because the firing session
is still alive to convert it. The recycle case cannot use that template for exactly one reason, and
it is the reason: **the firing session is the dead one.**

So the repo runs **two lifecycle vocabularies, partitioned by who is alive to speak** — the
disposition taxonomy for a live session's self-report, and the fire-event/pin/page layer for
sessions dead, dying, or not yet born. The recycle ceiling sits in the seam. Its correct home is the
second vocabulary, alongside `recycle-dead` and `recycle-unverified` — a `recycle-expired` event
plus a page, symmetric with the sibling branch 70 lines below it.

**What `handoff-disposition.sh` should emit**, and why it is still worth adding:

```json
"armed_succession": { "state": "armed", "pane": "133", "generation": "…", "watcher_alive": true }
```

— or `null`. Advisory, never a stay-open term in the exit-1 OR. Two uses justify it: a **pre-fire**
read needs to know a pane is already armed (that is the supersede case, §4A), and it makes the arm
visible in the one place that mechanically enumerates un-fakeable pane state. Adding it to the
verdict would invert the script's own contract — it would hold open exactly the session that is
supposed to be closing.

---

## 7 · Ratification checklist

Nothing in §4 is built. Before any of it is:

- [ ] **§4A supersede-on-arm** — needs a ruling on kill-by-pid semantics (the land-lock
      `(pid, lstart)` re-verification is the required floor, not optional).
- [ ] **§4B live payload** — needs confirmation that `dod-persist.sh get` is populated at every
      point `--recycle` can be called, including the model-fired path. If it is not, (B) degrades to
      the snapshot and must say so rather than silently freezing.
- [ ] **§4C trap + events** — the lowest-risk item and the highest-value one for observability;
      candidate to land first and alone.
- [ ] **§5 `SHIP_POLICY`** — independent of everything above; can land separately.
- [ ] **A test that fails when an armed recycle goes stale.** There is none today, and the reason is
      documented: the one suite that drives the watcher engineers a shim that **skips the ceiling**
      because a naive shim made the suite hang on it. The branch has zero coverage of any kind.

**Related prior art that must be read before building** — the same failure shape is already logged
as ESCAPING in a different subsystem: `docs/research/desk-audit-2026-07-18/a19-done-attack.md` D-8,
*"Kill-switch vs stale armed sentinel"* — an armed detached actuator whose validity is never
re-derived, where a stale sentinel defeats the operator's explicit stop. It was found, formally
recorded as escaping, and never closed. **The recycle arm is D-8 with a 600-second fuse and no
operator-visible sentinel file at all.**

---
---

# Part II — the FIRED-PEER half (added 2026-08-01, second investigation)

> **Provenance and status.** Part I above stands unamended; every claim in it that Part II touched
> was re-checked and held. Part II is the *other* half of the brief — fired peers, not armed
> recycles — investigated after Incident B (a fired peer believed to have "produced nothing and
> vanished"). Still a PROPOSAL: nothing here is built.
>
> Working notes with the full measurement:
> `docs/research/succession-observability-2026-08-01/{00-inventory,01-analysis}.md`.

## 8 · Incident B was a misdiagnosis — and the misdiagnosis is the finding

The peer did not vanish. Chain of custody, every link un-fakeable:

| Time (PDT) | Fact | Source |
|---|---|---|
| 18:04:37 | pane 158 fired into `wt-pool-9` | `cc-fired/158.json` `firedStartedAt` |
| 18:05:06 | engaged, `proof=marker`, latency **29 s** | same record — the brief's own quoted 29 s |
| 18:05→18:24 | ran a 14-agent workflow (`wf_f29f2a63-5c5`) | transcript subagent dir |
| 18:24:20 | authored + committed **this document, Part I**, 400 lines | `git show 1161b448`; the transcript's own `git commit` call |
| 18:25 | rebased onto `origin/main` and landed | reflog `HEAD@{18:25}: rebase (finish)` |
| 18:26:43 | ran `handoff-fire.sh self-close --terminal` | transcript, final tool call |
| 18:26:47 | `closedAt` + `succession.kind="terminal"` stamped | `cc-fired/158.json` |

It completed the assignment in 22 minutes, landed the deliverable, and retired through the
sanctioned path. **Part I of this document is the artifact the operator was told did not exist.**

### Why both available proxies reported the opposite

1. **"zero commits ahead in its worktree."** True, and structurally guaranteed: `wt-pool-9` is a
   **reso-management-app** worktree; the task was in **claude-infrastructure**. The fire provisions a
   worktree without reference to the repo the brief names, so commits-in-worktree can never detect
   delivery for a cross-repo fire.
2. **"absent from `cc-sessions`."** That is exactly what a *clean retirement* looks like.

**A peer that finished and one that died are identical in every operator-visible surface.** They
differ in one place — `closedAt` in the cc-fired record — and that place has no reader (§9.2).

So the defect is sharper than *"a silent death is invisible."* The infrastructure held the correct
answer on disk for five hours while the operator adjudicated from proxies and reached the opposite
conclusion **with confidence**. A missing *reader* is worse than missing *state*: absent state
yields acknowledged ignorance; an unread record yields a confident false negative.

### It is not rare — the denominator Part I could not compute for recycles, computed for fires

`cc-fired/*.json`, restricted to schema-2 records that reached engagement (the only population where
`closedAt` is initialised at fire, so its absence is meaningful). Window 2026-07-30 → 08-02:

| Outcome | n | share |
|---|---|---|
| `closedAt` set — finished and retired through the rails | **134** | 81.7 % |
| open, pane alive (correct: 157, and the session writing this) | 2 | 1.2 % |
| **engaged, then no terminal record, pane gone** | **28** | **17.1 %** |

Roughly nine a day. Incident B is the second-most-common outcome of a fire. (Unrestricted the split
is 141/301, but 129 records predate schema 2 and never had the field — 17.1 % is the honest figure.)

**What the predicate proves, precisely:** `closedAt == null AND pane gone` proves *no terminal record
was written* — **not** death. The operator may have closed the pane; a reaper may have taken it.
That indistinguishability **is** the defect: only one code path (`self_close`) writes a terminal
record, so every other ending is recorded identically to a crash.

## 9 · The fired-peer lifecycle — states, owners, and where each is observable

### 9.1 The two halves of one script disagree about whether an action leaves a record

This is the unifying statement of Parts I and II:

| | armed recycle (Part I) | fired peer (Part II) |
|---|---|---|
| durable record at arm/fire | **none** | `cc-fired/<pane>.json` schema 2 |
| durable payload | frozen `cp` in TMPDIR, swept at 2 days | `cc-fired/<pane>.prompt`, persisted |
| terminal state written | 2 of ≥6 exits, to a self-deleting log | **`closedAt` + `succession`** — but only on the self-close path |
| read by anything | no | **no** |

**The fire path already solved the state problem. The recycle path is the same script's other
branch, without the solution.** So Part I §4 is not inventing a mechanism — it is asking `--recycle`
to do what `--fire` in the same file already does. That is the strongest argument for §4A, and it
was not available until the fired half was mapped.

### 9.2 The record is written; nothing reads its outcome

```
grep -rln 'closedAt|\.succession' scripts/ hooks/ bin/ commands/   →  scripts/handoff-fire.sh
```

One hit: the writer. Seven files read the `cc-fired` directory
(`cc-classify`, `cc-reaper`, `cc-recover-safeguard`, `handoff-fire.sh`, `reaper-horizon-lint.sh`,
`desk-invariant.sh`, `growth-coverage.conf`) — **all of them for *existence*** ("is this pane a
spawner-stamped fired worker?"), **none for *outcome***.

The reason this went unnoticed is written in the code that created the field.
`record_close_succession`'s own header:

> *"the 2026-07-13 23:03 'failed handoff' was a PERFECT succession that nobody could see, because
> the handover report died with the closing pane. So the succession statement is written to the
> DURABLE record before the pane evaporates, where a successor or the operator can read it
> afterwards."*

**The identical defect was diagnosed in July, the record was built to fix it, and the reader was
never built.** Incident B is that same sentence one level up: a perfect *delivery* nobody could see.

### 9.3 The reader was not merely forgotten — it was the ratified architecture

`docs/plans/SESSION_LIFECYCLE_V2.md` §5, the plan that specified this record, states the intent in a
bolded clause of its own:

> **The inversion: row 2 keeps ONE durable, append-only-per-transition LIFECYCLE RECORD per pane,
> written by row 2 at every transition, and every lifecycle decision reads THAT first. Foreign
> oracles become CORROBORATION, never the primary read.**

and names, as the thing being *discarded*:

> *"the assumption that lifecycle facts are **derivable at read time** from foreign state (row 4's
> registry, the process table, iTerm2's pane list)"*

with the diagnosis:

> *"row 2 throws away the evidence only row 2 can produce, then re-derives it from state it does not
> own."*

**The record landed; the inversion did not.** Every lifecycle consumer still reads foreign oracles
first — `cc-classify` from registry pid, git, and the transcript; `cc-reaper` from those verdicts;
the operator from worktree commits and `cc-sessions`. The record is consulted only for *existence*
(§9.2), which is precisely the "5-field stamp" read V2 listed as an example of the incumbent defect.

That makes Incident B a textbook instance of the sentence above: the operator re-derived *"did it
deliver?"* from state nobody owned, while the evidence only the fire path could produce sat unread
four feet away. **The half-built state is worse than either end** — a record that exists but is not
primary invites exactly the foreign-oracle re-derivation V2 discarded, while looking, to anyone
grepping for it, like the problem is solved.

The corollary for §10: the reader is not a new feature. It is the unbuilt half of a design already
ratified, and building it is what makes the landed half worth anything.

### 9.4 `--terminal` is the close mode with no legibility at all — and 158 used it

The July fix is real, but it is **half a fix, and the uncovered half is the one Incident B took.**
Memory `handoff-succession-legibility` states the rule it installed:

> *"an operator judges a handoff by what their EYES land on when a pane vanishes. A close whose
> continuation is not visible is indistinguishable from a crash, no matter how clean the mechanics
> were."*

Its mechanism — `self-close` refuses without a succession statement; `--successor` verifies the
survivor is alive, **announces into it** via `cc-notify`, and **moves operator focus** — makes a
*successor* close visible. `--terminal` has no survivor to announce into, so by construction it
inherits none of that. Its entire operator-visible surface is one line (grep `post-close: terminal`):

```sh
[ -n "$SC_SUCCESSOR" ] && echo "→ post-close: operator focus hands to successor $SC_SUCCESSOR" \
                       || echo "→ post-close: terminal (nothing continues this session's work)"
```

An `echo` **into the pane that is about to disappear**. That is the July defect — *"its handover
report died with its own pane"* — reproduced verbatim inside the branch its own fix did not cover.

Pane 158 closed `--terminal`, correctly: nothing continued its work. So the single close mode that
has **no live surface to be legible through** is also the one whose **only** durable artifact —
`closedAt` + `succession` — has no reader. The two gaps compose exactly, and their product is
Incident B.

Generalising the memory's own rule one level: **a close whose DELIVERY is not visible is
indistinguishable from a death, no matter how clean the mechanics were.** For `--successor` the
survivor carries the news. For `--terminal` only the record can, which is why §10.1 (the reader) and
§10.2 (the receipt) are not two ideas but one: *`--terminal`'s announce channel is the record.*

> **Live reproduction, n=1, this session.** The fire that produced Part II is *also* one-way — no
> `--notify-back`, no `cc-notify` recipe (`cc-fired/170.prompt`) — and its closing instruction is
> `self-close --terminal`. Following it literally would land Part II on `origin/main` and then close
> a pane whose only trace is `closedAt` in an unread record: **the 29th dark peer, by the same
> mechanism, two hours after diagnosing it.** The defect is not a rare race; it is the default path,
> and it re-arms itself on every fire. This session escapes it only by hand-writing the announce
> (`cc-notify` to the firing desk) that §10.2 argues should be a field on a write that already
> happens.

### 9.5 There IS a rich reader — for the living only

`bin/cc-classify` is a 12-cause idle classifier (`active`, `rate-limited`, `owned-wait`,
`coordination-hang`, `coordination-abandoned`, `handed-off-lead`, `finished-teammate`, `finished`,
`finished-operator`, `finished-shared-review`, `crashed`, `safeguard-blocked`) driving `cc-reaper`.
It is careful, evidence-first, and it reads the cc-fired stamp. It classifies **live sessions**.

Asked about a departed peer it says:

```
$ cc-classify 55A0A553-…            # a peer that engaged 2026-07-31 and never closed
cc-classify: no live session matches '55A0A553-…'
$ echo $?
0
```

**A query about a dead peer succeeds while answering nothing.** That is the precise inverse of the
pattern the brief holds up as correct — `cc-await-ping`'s exit-2, which *explains its own designed
outcome so a non-zero exit is not misread as a failure*. Here a **zero** exit is misread as *fine*.

So: **the fleet has a first-class reader for sessions that still exist, and none for sessions that
no longer do.** The cc-fired record is the only artifact that outlives the session, and it is
exactly the one nothing consults.

### 9.6 The lifecycle, stated

| State | Set by | Where observable **today** | Where it must be |
|---|---|---|---|
| `fired` | `handoff-fire.sh` | `cc-fired/<pane>.json` | unchanged |
| `engaged` | fire path (marker/latency) | same record | unchanged |
| `working` | — | `cc-classify` (live only) | unchanged |
| `delivered` | **nothing** | — | the self-close write (§10.2) |
| `closed` | `self_close` | `closedAt` + `succession` — **unread** | a reader (§10.1) |
| `dark` (engaged, no terminal record, pane gone) | **nothing** | — | derived by the reader (§10.1) |
| `never-engaged` | fire path | record with `engagedAt: null` | derived by the same reader |

Owners: the **peer** owns `delivered` and `closed` (it is alive and already writing at that moment);
a **reader** owns `dark`, because by definition nothing that could write it still exists. That is the
same split Part I §3 reached for recycles — *the process actuates; the record decides* — and it
answers the brief's question directly: **yes, "armed" belongs on disk as durable state, for exactly
the reason the fired half already does.**

## 10 · The smallest change — a reader, and one extra field on a write that already happens

### 10.1 (a) Make a silent peer death loud — a READER, no new state

Everything needed already exists on disk for all 28 dark peers. Required: something that reads
`cc-fired × cc-sessions` and reports the four derived outcomes of §9.6. Two placements, both small:

- extend `cc-classify` with a **departed-peer domain** (its `--all` currently enumerates live
  sessions only), or add a sibling that reuses its evidence discipline; and
- make `cc-classify <unknown-target>` **exit non-zero and say which of the two things it means** —
  *"no live session, AND no fired record"* vs *"no live session, but a fired record exists: engaged
  <t>, never closed"*. Today both collapse to `rc=0`.

**Identity discipline (non-negotiable).** Pane ids in this fleet are of two kinds — iTerm2 integers
(`133`, `157`, `170`) and full UUIDs — and **integers recycle across terminal restarts**. A reader
that infers "alive" from a bare id match will attribute a new pane's life to a dead peer's record:
the same family as the `land-lock.sh` pid-recycling bug that `ps -o lstart=` exists to defeat, and
as the `cc_alive` tty-grep Part I §1.3 already convicts. Match on `(pane, firedAt)` or
`(pane, marker)`, never pane alone; treat an unreadable registry as **unknown**, never as **dead**
(`handoff-disposition.sh`'s `registry_indeterminate` already sets this precedent, failing *closed*).

### 10.2 The receipt vs the ping — why "default `--notify-back` on" is the wrong fix

The tempting conclusion is wrong, and the taxonomy says why: `--notify-back` **arms R-PING**, and
R-PING is a *stay-OPEN* term in `handoff-disposition.sh`'s exit-1 OR. Defaulting it on would make
every fire convert the **firing** session into one that mechanically cannot close until the peer
pings — a desk firing six peers could never retire. That is the opposite of autonomy.

|  | Ping (`--notify-back` → R-PING) | Receipt (`closedAt` + outcome) |
|---|---|---|
| who acts | the peer, into a **live** firer | the peer, into **its own record** |
| cost to the firer | a stay-open obligation | none |
| requires the firer alive | **yes** | no |
| right default | **opt-in** — unchanged | **on** |

**Incident B needed the receipt, not the ping.** And the receipt is not new machinery: the peer
already calls `self-close`, which already writes `closedAt` and `succession`. Adding *what it
delivered* (declared deliverable paths; landed shas; repo) to a write that already happens is the
smallest possible change — no new store, no ceremony, no stay-open term. It also fixes the
cross-repo blindness of §8, because the receipt names the repo the work landed in rather than
leaving the operator to guess from the worktree.

### 10.3 The delivery receipt is already parsed — and has no producer

`handoff-disposition.sh` parses `DELIVERABLE: <path>` from `--payload` and reports
`deliverables_missing` as a stay-OPEN reason. Its own comment describes Incident B exactly:

> *"a fired peer that returns a PARTIAL deliverable then dies leaves `fired_peers_alive=[]` → the
> mechanical read would green-light a close over incomplete work."* (a19 §4)

The string `DELIVERABLE` appears in **four files** repo-wide: two bats suites, one activation
snippet, and the consumer. It is in **neither** `handoff-fire.sh`, `commands/handoff.md`, nor the
handoff skill. Across ~290 stored payloads, **3 declare one** — about 1 %; not 157, not 158, not the
fire that produced this document.

**A parser with tests and no producer.** The change is on the producer side: the fire path (or the
skill that composes the brief) emits a `DELIVERABLE:` line, and the payload-lint that already warns
about a one-way fire gains a second, equally advisory clause when none is declared.

### 10.4 Why the existing safeguards did not fire: all three are opt-in, and the default omits them

| Mechanism | Exists | Armed by | Default |
|---|---|---|---|
| completion ping / dead-peer check | yes — R-PING | `--notify-back` | **off** |
| delivery receipt | yes — `deliverables_missing` | a `DELIVERABLE:` line nothing writes | **off** |
| terminal-state record | yes — `closedAt` | the self-close path only | on, **unread** |

`handoff-fire.sh` is explicit that this is by design — *"A pure one-way fire … is NOT gated:
fire-and-forget is the documented default"* — and the lint is correspondingly advisory:

> `⚠ payload-lint (advisory): one-way fire with no back-channel block — a fired session cannot
> announce back.`

That call is defensible (§10.2). The consequence is not: **the documented default configuration is
the one with no receipt, no ping, and no reader.** §10.1–10.3 change only the two rows that cost the
firer nothing, leaving fire-and-forget intact.

## 11 · Whose decision — extending Part I §5 with the dead-peer case

Part I §5's enumeration of genuinely-operator-owned decisions holds and is not re-opened. Part II
adds one row to §5.2 (*structurally the infrastructure's, currently escalated*):

| Decision | Missing state | Why it is not the operator's |
|---|---|---|
| **A fired peer went dark — now what?** | the reader of §10.1 | the payload is on disk; the deliverable is declarable; the re-fire path already exists |

`commands/handoff.md`'s R-PING row already specifies the dead-peer handling — *"a DEAD peer
escalates to R-DECIDE (the user rules on the lost track)"*. Even the designed happy path terminates
in an operator fork.

**That fork can be deleted, and the machine to delete it is already written.**
`bin/cc-recover-safeguard` re-fires a peer's *persisted brief* (`cc-fired/<pane>.prompt`) on a
different model and closes the dead pane through the sanctioned `self-close`. It is complete,
careful (re-fire first, close second, so a failed re-fire preserves the pane) — and scoped to
**one** cause, `safeguard-blocked`, dry-run by default, described in `cc-blockers` as *"the
operator's explicit call."*

A peer that engaged, wrote no terminal record, has a stored payload, and has a missing declared
deliverable is **a re-fire, not a question.** Generalising the recovery trigger from
`safeguard-blocked` to any *dark* cause reuses a tested path instead of adding one.

Where the operator's judgment genuinely re-enters, and only here: a re-fire that **costs money**
(reso's billed land — §5.1 row 1), a peer that has already been re-fired and went dark **again**
(loop-breaking: bound it, then surface), and a dark peer whose work is **not** reconstructible from
its payload because it had already mutated shared state.

## 12 · What `handoff-disposition.sh` should emit — a correction to Part I §6, and a producer-side fix

Part I §6 concluded *"a field, yes; an R-code, no; and the field must never flip the exit."* For the
**armed recycle** that is right and stands: an armed pane is one that should *close*, so filing it
under *reasons to stay open* is a category error, and the expiry has no live emitter.

**For a dead peer the conclusion is different, and the script already agrees.** A dead peer is not
the mirror case: the *firing* session is alive, R-PING already owns it, and the exit-1 OR already
contains two axes that are exactly this concern:

- `fired_peers_alive` — live peers matching a slug;
- `deliverables_missing` — declared outputs absent or zero-length, added precisely because
  *"fired_peers_alive=[] would green-light a close over incomplete work."*

Together those two already express *"the peer is gone AND its deliverable is not there"* — the dark
state — and they legitimately flip the exit. **Nothing needs adding to the consumer.** The reason
they never fire is upstream: `fired_peers_alive` needs slugs the caller must pass, and
`deliverables_missing` needs a `DELIVERABLE:` line nothing produces (§10.3).

So the recommendation splits by case:

| | New field | May flip exit? |
|---|---|---|
| armed succession | `"armed_succession": {...}` or `null` — Part I §6's shape, unchanged | **no** — advisory |
| peer liveness/outcome | extend `fired_peers_alive` to `fired_peers: [{slug, pane, state: alive\|closed\|dark, closedAt}]` | **only via the existing `deliverables_missing` term** — a dark peer with no declared deliverable is not a stay-open reason, because nothing was promised |

What it would have emitted:

- **Incident A** — `armed_succession: {state:"armed", pane:"133", watcher_alive:false}` at
  17:54:14, advisory, exit unchanged. The operator would have seen the arm was dead the moment it
  died, instead of five hours later in a temp file.
- **Incident B** — `fired_peers: [{pane:"158", state:"closed", closedAt:"…T01:26:47Z"}]` and
  `deliverables_missing: []`. **Exit 0, and the fork never forms** — the question "did it die?" is
  answered by the record before it can be asked.

## 13 · Ratification checklist — Part II

Part I §7's items stand. Additional, and deliberately ordered cheapest-first:

- [ ] **§10.1 the reader** — pure addition, reads only existing state, no rail touched. **Lands
      first and alone.** Needs a ruling only on placement (`cc-classify` domain vs sibling binary).
- [ ] **§10.1 self-explaining exit** for `cc-classify` on an unknown target — the `cc-await-ping`
      pattern generalised. Behaviour change to a bin used by the reaper: needs a check that no
      caller depends on the current `rc=0`.
- [ ] **§10.3 a `DELIVERABLE:` producer** — needs a decision on *who* declares it (the firing
      model, from the brief's own DELIVERABLE line, vs `handoff-fire.sh` inferring one). Inference
      is probably wrong; the firer knows what it asked for.
- [ ] **§10.2 the receipt field** on `record_close_succession` — additive to schema 2, same
      best-effort discipline ("a bookkeeping failure must never block an authorized close").
- [ ] **§11 generalised re-fire** — the highest-risk item: it spends tokens and opens a live pane
      autonomously. Needs the loop bound, the money-gate, and an explicit operator ruling. **Do not
      land it with the rest.**
- [ ] **A test for the dark state.** The fixture set already exists in the live store: 157
      (open-alive), 158 (closed-clean), any of the 28 (dark). No suite asserts any of them.

