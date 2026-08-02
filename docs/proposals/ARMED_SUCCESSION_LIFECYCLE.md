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
