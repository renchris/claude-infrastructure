# A04 — Transplant-side rails, and the minimal generalisation to `cause = VOLUNTARY`

Read-only audit, 2026-09-22. Every claim is `file:line` against the working tree at
`/Users/chrisren/Development/claude-infrastructure` (branch `main`, HEAD `8e3ab2e38`). No lock,
tombstone, pane or repo file was touched.

## Headline

**The transplant machinery is already cause-agnostic. The quota coupling lives in exactly five
places, and only ONE of them is on the irreversible path.** `lr-transplant.sh`, the lock, the
tombstone, `lr_transplanted_to` / `lr_transplant_target` / `lr_husk_state`, `hf_transplant_evidence`,
`handed-off-session-guard.sh` and `cc-husk-sweep` read *"a transplant happened"* and nothing else —
not one of them reads an api-error record, a quota kind, or an account's headroom.

The five quota gates are: `handoff-fire.sh:7833` (the pre-check's `REFUSED:not-limited`),
`bin/cc-lr:265`, `lr-fleet.sh:1191` + its disposition switch, `lr-ingest-verify.sh:167` (clause A4),
and `handoff-fire.sh:9716-9722` (the subagent-gate auto-override). Only the last is dangerous:
it is the one that makes a voluntary move *lose work* rather than merely be refused.

**The self-recycle arm is already open.** `lr-handoff.sh:797-822` landed today and states the
voluntary case by name: *"a healthy session probes `REFUSED:not-limited` and exits 5: letting that rc
reach the branch above would refuse every self-recovery of a session that is merely low on context
**or being moved to a fresher account**."* The rc is deliberately discarded on the self branch
(`:805-811`). So `lr-handoff --in-place` *without* `--source-pane` already performs a voluntary move.
What is closed is the **driver/remote** form and the **ingest verifier**.

---

## 1. Rail-by-rail

| # | Rail | file:line | What it asserts today | Quota-gated? | Minimal change for `cause=VOLUNTARY` |
|---|---|---|---|---|---|
| R1 | **Same-store refusal** | `lr-transplant.sh:36-43` | `--from`/`--to` resolve to different `projects/` stores | **No** | none |
| R2 | **Idempotence / same-target retry** | `lr-transplant.sh:132-183` | lock names THIS target ∧ target copy present ∧ (if a live source copy survives) `bytes(dst) ≥ bytes(src)` | **No** | none (see §4) |
| R3 | **Split-brain refusal, site 1 (target mismatch)** | `lr-transplant.sh:166-176` | lock owner ≠ `--to` ∧ not a hop ⇒ refuse | **No** | none |
| R4 | **Split-brain refusal, site 2 (bare existence)** | `lr-transplant.sh:209-212` | lock exists ∧ not a hop ∧ not `--force` ⇒ refuse | **No** | none |
| R5 | **Hop / custody test** | `lr-transplant.sh:116-130` | lock `owner` (fallback `to`) == `--from` ⇒ this is a hand-on, admit | **No** | none — a voluntary hop is the same shape as a quota hop |
| R6 | **The LOCK itself** | written `lr-transplant.sh:242-243` | `{sid,from,to,ts,pid,host,owner,ts_first,chain[]}` — **no cause field** | **No** | **add `cause` + `cause_detail`** (§3) |
| R7 | **The TOMBSTONE** | written `lr-transplant.sh:267-269` | `{handed_off_to,target_transcript,ts,lock}` — **no cause field** | **No** | **add `cause`** (§3) |
| R8 | **Source retirement** | `lr-transplant.sh:271-274` | renames `<sid>.jsonl` → `.handed-off` unless `--keep-source` or the driver IS the session | **No** | none |
| R9 | `lr_transplanted_to` | `lr-lib.sh:542-565` | lock `.to` ≠ here ∧ target holds `<sid>.jsonl` | **No** | none — but see §5 (it reads `to`, never `owner`) |
| R10 | `lr_transplant_target` | `lr-lib.sh:575-604` | lock first, else a `handed_off_to` tombstone naming a DIFFERENT store whose successor copy exists | **No** | none |
| R11 | **HUSK predicate** | `lr-lib.sh:628-710` | (a) live registry row on this store `:651-662` ∧ (b) `lr_transplant_target` `:639` ∧ (c) no `__recycle` watcher `:673-678` and no fresh `handoffs.jsonl` row `:683-707` | **No** | none — all three conjuncts are cause-free |
| R12 | **HUSK disposition in the census** | `lr-fleet.sh:223-227, 285` | `_husk=1` short-circuits the limit filter at `:229` and `:246`, and outranks every other disposition at `:285` | **No** (deliberately bypasses the limit filter) | none |
| R13 | **`TRANSPLANTED→acct`** | `lr-fleet.sh:271` | `lr_transplanted_to` on this store | **No** | none |
| R14 | **Mirror-dedup HUSK precedence** | `lr-fleet.sh:298-311` | a husk row never loses the `~/.claude`/`~/.claude-next` collapse — "two objects with OPPOSITE dispositions" | **No** | none |
| R15 | `hf_transplant_evidence` | `handoff-fire.sh:2256-2337` | unique+parseable tombstone, `.handed_off_to` ≠ this cfg, named lock still on disk | **No** | none for the happy path; see §5 (two tombstones ⇒ refuse) |
| R16 | **`--recycle --transplanted-source` preconditions** | `handoff-fire.sh:9683-9694` | flag present ∧ `--resume-launcher`/`--resume-cfg` ∧ registry bind ∧ tty pin ∧ R15 ∧ `HF_TS_TO == RESUME_CFG` | **No** | none |
| R17 | **self-close `--transplanted-source`** | `handoff-fire.sh:8168-8200` | six preconditions (0)-(5); named `--successor`, never `--terminal`; successor engagement gate not re-implemented | **No** | none |
| R18 | **Class exemption from the origin gate** | `handoff-fire.sh:8211-8214` | `transplanted-source` exempts stale/spent fired-peer-stamp refusals | **No** | none |
| R19 | 🚨 **Subagent-gate auto-override** | `handoff-fire.sh:9716-9722` | `--transplanted-source` ⇒ `ALLOW_LIVE_SA=1`, *"A limit-blocked lead's subagents died with it"* | **YES — implicitly, and this is the one that loses work** | **gate it on `cause=LIMIT`; a VOLUNTARY move must take `subagent_gate`'s refusal (`handoff-fire.sh` `subagent_gate`, rc 4)** |
| R20 | **Live-teammate gate** | `handoff-fire.sh:8405-8408` | self-close refuses on a live teammate unless `--allow-live-teammates`; **not** auto-granted by the class | **No** | none — already correct for VOLUNTARY |
| R21 | 🚨 **Pre-check limit gate** | `handoff-fire.sh:7831-7836` | `lr_last_api_error` kind must be `limit`, else `REFUSED:not-limited` exit 5 | **YES** | **admit when the caller declares `--cause voluntary`; keep `not-limited` as the default refusal** |
| R22 | **Pre-check, the rest** | `handoff-fire.sh:7775-7779, 7843-7847, 7856-7877, 7883-7892` | binding · teammate · pane-holds-a-claude · empty composer | **No** | none — all four bind harder for a voluntary move |
| R23 | **`live_subagents:` emission** | `handoff-fire.sh:7819-7822` | counted, never a refusal, emitted **before** every `prp_verdict` | **No** | none (this is what makes R19's replacement cheap — the number is already on the wire) |
| R24 | 🚨 **`cc-lr recover` RULE 2** | `bin/cc-lr:265-268` → `cl_refuse_not_limited:178-212` | class must be `LIMITED`; `:202` asserts *"every downstream rail (recycle, transplant, tombstone, self-close) is gated on the quota predicate"* | **YES** | **add a `--voluntary` verb/flag; and fix `:202`, which is FALSE — see §2** |
| R25 | 🚨 **`lr-fleet --recover` / `--enqueue`** | `lr-fleet.sh:984-1000` (disposition), `:1191` (`[ "$kind" = limit ] \|\| continue`) | only a `RECOVERABLE`/`NO-PANE` row whose last api error is `limit` is swept | **YES** | none needed — a voluntary move is never a *sweep*; it is `--one`, which does **not** check (`lr-fleet.sh:1096-1135` only refuses `TRANSPLANTED*`) |
| R26 | `lr-fleet --one` | `lr-fleet.sh:1096-1135` | refuses only ambiguity, no-transcript, and already-TRANSPLANTED | **No** | none — already the voluntary entry point |
| R27 | 🚨 **Ingest verifier clause A4** | `lr-ingest-verify.sh:163-169` | `last_api_error.kind ∈ {session,weekly,monthly_spend}`, else FAIL | **YES** | **PASS when `cause=VOLUNTARY` and the transcript's last assistant word is a normal turn** |
| R28 | **Ingest verifier C3 (lock target)** | `lr-ingest-verify.sh:328-350` | lock `.to` == manifest target, or the target appears in `.chain[]` | **No** | none |
| R29 | **Ingest verifier C4 (tombstone)** | `lr-ingest-verify.sh:352-359` | a source tombstone exists | **No** | none |
| R30 | **Ingest verifier A6 (killed_inflight)** | `lr-ingest-verify.sh:215-226` | the run's `events.jsonl` must carry `killed_inflight=<n>`; any `n>0` FAILS | **No** | none — and for VOLUNTARY it becomes the *primary* safety clause (§6, I4) |
| R31 | **`handed-off-session-guard.sh`** | `hooks/handed-off-session-guard.sh:62-78, 138, 175` | UserPromptSubmit exit 2 when a `handed_off_to` tombstone names another store | **No** | none |
| R32 | **`cc-husk-sweep` TRANSPLANTED verdict** | `bin/cc-husk-sweep:135-147, 296-301, 317` | `lr_transplant_target` on the store it was found in; `TRANSPLANTED*` is excluded from `--resume --all` | **No** | none |
| R33 | **`cc-limited` unresolved-claim reaper** | `bin/cc-limited:954-979` | a lock older than `CLAIM_GRACE_S` (120 s) with **no live registry row and no resume leaf** renders as a CLAIM fault | **No** | see §6, I5 — it is structurally blind to the state a voluntary move can strand |
| R34 | **`lr_tier_from_transcript`** | `lr-lib.sh:56-119` | picks the last non-error turn *before* the last limit; `pick = turns[-1]` when there is none (`:113-114`) | **No** | none — already degrades correctly with no limit record |
| R35 | **`lr-audit.py` verdicts** | per `NONLIMIT_RESUME_LADDER.md:159-182` | `slot_verdict` returns NULL on ANY api_error; the reason never gates the verdict | **No** | none — *"the gap was DISCOVERY, not capability"* |

---

## 2. (a) Which rails read a quota fact, versus merely "a transplant happened"

**Reads a quota/limit fact (5 sites, all on the ADMISSION side, none on the state side):**

| file:line | predicate | effect |
|---|---|---|
| `handoff-fire.sh:7831-7836` | `lr_last_api_error(tx) \| cut -f3 != limit` | `prp_verdict REFUSED:not-limited 5` — the driver/remote pre-check |
| `bin/cc-lr:265-268` | `klass != LIMITED` (from `cc-find`) | refuses before any mutex |
| `bin/cc-lr:198-207` | `lr_last_api_error` kind ≠ limit | the routing refusal, whose text at `:202` over-claims (below) |
| `lr-fleet.sh:1191` | `[ "$kind" = limit ]` | `--enqueue` only; `--recover`'s switch at `:984-1000` admits only `RECOVERABLE`/`NO-PANE`, both of which require a limit record via `lf_locate`'s `:229`/`:246` filter |
| `lr-ingest-verify.sh:165-169` | `last_api_error.kind ∈ {session,weekly,monthly_spend}` | clause A4 FAIL ⇒ no fast-path ingest |

**Reads only "a transplant happened" (everything else):** R1-R20, R22, R23, R26, R28-R35 above. Their
entire evidence set is: the lock file's existence and its `owner`/`to`/`chain` fields, the
tombstone's `handed_off_to`/`lock`/`target_transcript`, the presence of a `<sid>.jsonl` under the
target, a live registry row, and a live `__recycle` watcher. **None of these is derivable from, or
correlated with, why the move was made.**

🚨 **`bin/cc-lr:202` states the opposite and is false as written.** It tells a caller that *"every
downstream rail (recycle, transplant, tombstone, self-close) is gated on the quota predicate"* and
therefore *"it cannot be retired by the sanctioned path"*. Measured against the code: `lr-transplant.sh`
has no limit read at all; the tombstone is a `printf` (`:267-269`); `hf_transplant_evidence`
(`:2256-2337`) reads three files and no error record; self-close's class (`:8168-8200`) lists six
preconditions and not one of them is a quota fact. The line is a **refusal bounding the tool being
read as a fact about the world** — the exact defect its own header (`bin/cc-lr:163-177`) was written
to fix, reproduced one paragraph lower. This single sentence is the strongest evidence in the tree
that a voluntary move is believed impossible; it should be corrected whether or not the feature ships.

**Residual quota coupling that is REAL but not a gate:** `lr-handoff.sh`'s `--target auto` routes
through `claude-accounts --rank … --recovery` (`lr-fleet.sh:726`), whose floors are calibrated for
recovery (weekly ≥ 90 excluded, 5h projected ≤ 0.60). A voluntary move wants a *headroom* ranking,
not a *recovery* ranking — but this is a routing-quality question, not a correctness rail, and
`--target next3` bypasses it entirely.

---

## 3. (b) The cause field: it does not exist, and where it must go

**Today's schemas, verbatim:**

```
lock      lr-transplant.sh:242-243
          {"sid","from","to","ts","pid","host","owner","ts_first","chain":[…]}

tombstone lr-transplant.sh:267-269
          {"handed_off_to","target_transcript","ts","lock"}
```

Neither carries a cause. The **only** precedent in the transplant surface is the *same-account*
`--mark` tombstone (`lr-fleet.sh:1261`), which already writes a free-text
`reason:"same-account duplicate — …"` — read by **nobody** (`handoff-fire.sh:2314` reads
`superseded_by_pid`; `handed-off-session-guard.sh:97,101` reads the same; neither touches `reason`).
So the file format already tolerates an extra key and no consumer will break on one.

### Where it goes, and why that placement keeps HUSK / DUPLICATE / TRANSPLANTED→acct correct

**Put `cause` on BOTH artifacts, as a closed vocabulary, and make no consumer dispatch on it.**

| artifact | field | value set | written by | read by |
|---|---|---|---|---|
| lock | `cause` | `limit` · `login-cliff` · `voluntary` · `unknown` | `lr-transplant.sh:242-243` | reporting only (`lr-fleet --report`, `cc-lr status`) |
| lock | `cause_chain` | one entry per hop, parallel to `chain[]` | `lr-transplant.sh:236-243` | ingest verifier A4 |
| tombstone | `cause` | same set | `lr-transplant.sh:267-269` | `lr-ingest-verify` A4, `handed-off-session-guard`'s message text |

**Why the dispositions stay correct by construction:** `lr_husk_state`, `lr_transplant_target`,
`lr_transplanted_to` and `hf_transplant_evidence` are *existence + different-store + successor-present*
predicates. A husk is a husk because the pane is live on a store the session has left — a sentence in
which the cause does not appear. Adding a key those functions never read cannot change their output.
The invariant to hold is therefore **negative**: *no state predicate may branch on `cause`.* Only
ADMISSION (R19, R21, R24, R27) and REPORTING may.

🚨 **The absent value must be `unknown`, never a default of `limit`.** Every lock and tombstone on
disk today predates the field. `lr_transplant_target`'s pre-W5-B fallback (`lr-transplant.sh:104-109`,
`:222-228`) is the pattern: read the new field, fall back to a derivable one, never invent. An
unstated cause is `unknown`, and `unknown` must be admissible everywhere `limit` is — otherwise the
field's introduction retroactively breaks every existing husk. (Repo lesson:
`closed-vocabulary-swallows-an-unrecognized-value` — a fail-open default turns a terminal state into
a re-dispatched one. Here the *safe* direction is the opposite one: cause is advisory, so fail-open
is correct precisely because nothing dispatches on it.)

---

## 4. (c) Idempotence on a same-target retry — VERIFIED, with its exact conditions

`lr-transplant.sh:132-183`. The documented claim (`:45-59`, W11 / `LIMIT_RECOVER_100P` §10) holds.
`lrt_already_done()` returns the existing target transcript and the script exits 0 with
`already_transplanted:true` **iff ALL of:**

1. `$FORCE -ne 1` (`:177`) — `--force` skips the check entirely and re-copies.
2. The lock file exists (`:133`).
3. `lrt_lock_owner` is non-empty — `owner`, falling back to `to` for a pre-W5-B lock (`:104-109`, `:136-137`).
4. `realpath(owner) == realpath($TO)` (`:137-139`). A different owner is a genuine split brain and falls to the refusal at `:166-176`.
5. A file matching `$TO/projects/*/$SID.jsonl` exists (`:144-145`).
6. **Conditionally** — if a live source copy `$FROM/projects/*/$SID.jsonl` still exists (i.e. `--keep-source` was used, or the driver was the session itself so `:271` skipped the rename), then `bytes(dst) ≥ bytes(src)` (`:150-155`). Bytes, not sha, deliberately: the successor has been appending since the move.

**The three refusal sites it must sit above, and does (`:50-54`):** `$DST already exists` (`:201-203`),
`lock exists` (`:209-212`), and — the one the plan missed — `no transcript $SID under $FROM/projects`
(`:189-190`), which is the shape an rc-4 retry actually has once `:272` has renamed the source.

**Conditions under which idempotence does NOT hold** (all correct, all worth stating):

- `--force` (`:177`) — re-copies and rewrites the lock unconditionally.
- **A different `--to`** — refused at `:171-174`, not idempotent, by design.
- **A lock-less retry.** If the lock is gone (measured as the common case on this box —
  `lr-lib.sh:555-573` records ONE lock fleet-wide against three tombstoned husks), `:133` fails, the
  script falls to the source lookup, finds nothing (`:189`), and dies with *"no transcript … under
  $FROM/projects"*. So **idempotence is a property of the LOCK, and the lock is the artifact measured
  to be transient.** A voluntary move that wants a retryable actuator should either (i) make the
  already-done check fall back to the tombstone the way `lr_transplant_target` already does, or
  (ii) accept that a lock-less retry is a manual case.
- **A truncated target** (condition 6 fails) — refuses to call it done, which is right: returning ok
  over a truncated target would strand the tail of a session.

---

## 5. (d) A voluntary move on a session that ALREADY carries a tombstone

Four distinct outcomes depending on whether the lock survived. All read out of the code; none
executed.

| situation | what happens | file:line | correct? |
|---|---|---|---|
| **Lock alive, `owner == --from`** (A→B done, now B→C) | `SECOND_HOP=1` (`:127-130`); both refusals exempted (`:166`, `:209`); lock rewritten with `owner=C`, `ts` refreshed, `ts_first` preserved, `chain=[A,B,C]` (`:216-243`) | `lr-transplant.sh:61-73` | **Yes.** This is W5-B's custody model and it is cause-free — a voluntary second hop needs no change. |
| **Lock alive, `owner == some third store`** | REFUSED at `:171-174` with the three-way remedy (recover at the current target · `--from <owner>` · `--force`) | `lr-transplant.sh:166-176` | **Yes** — this is the split brain the lock exists to prevent. |
| 🚨 **Lock GONE, second hop attempted** | `LRT_OWNER` empty ⇒ `SECOND_HOP=0`; `lrt_already_done` returns 1 at `:133`; both refusals are skipped (they test `-e "$LOCK"`); the move **proceeds** and writes a FRESH lock with `chain=[B,C]` — **the A hop is erased from custody** (`:230`) | `lr-transplant.sh:133`, `:218-231` | **No.** The A→B hop is lost. `lr-ingest-verify` C3 (`:337-348`) then FAILS any older bundle whose manifest target was A or B. |
| 🚨 **Lock gone, and then the census is asked about store A** | `lr_transplant_target(sid, A)` takes the tombstone arm (`lr-lib.sh:580-163`); A's tombstone says `handed_off_to=B`; the successor test `for pd in "$to"/projects/*/"$sid".jsonl` fails because B's copy was renamed `.handed-off` at `:272`; returns rc 1 | `lr-lib.sh:559-163` | **No.** Store A's pane silently stops being a HUSK. The first husk becomes invisible again — the exact false green `LIMIT_RECOVER_100P` §10 W10b was written to end. |
| **Any remote close/recycle after two hops** | `hf_transplant_evidence` enumerates tombstones across **all** of `$CC_PROJECTS_DIRS` (`handoff-fire.sh:2273-2283`); two *distinct* realpaths set `dupes=1` (`:2279`) ⇒ `REFUSED: more than one transplant tombstone … disambiguate by hand` (`:2285-2288`) | `handoff-fire.sh:2273-2288` | **Correct refusal, wrong reason.** It cannot tell "two hops of one chain" from "two independent moves". |

### The correct refusal for a voluntary move over an existing tombstone

**Do not refuse the move; refuse the ambiguity, and name the chain.** The rule that generalises
cleanly, in priority order:

1. **Lock present and `owner == --from`** ⇒ admit as a hop. Unchanged. Record `cause` for the new
   hop in `cause_chain`, leaving earlier entries intact (same read-modify-write discipline as
   `ts_first`, `lr-transplant.sh:214-231`).
2. **Lock present and `owner ≠ --from`** ⇒ refuse as today (`:171-174`).
3. **Lock ABSENT but a tombstone chain is reconstructible** ⇒ *rebuild custody from the tombstones
   before deciding.* Walk `handed_off_to` transitively from `--from`; if the walk terminates at
   `--from` itself, it is a hop — re-mint the lock with the reconstructed `chain` rather than a
   two-element one. This is exactly the fallback `lr-transplant.sh:222-228` already performs for a
   pre-W5-B lock, applied one level out.
4. **Lock absent and the walk is ambiguous or cyclic** ⇒ **refuse**, with the message naming every
   tombstone found and the store each points at. A voluntary move is elective; refusing it costs a
   message. This is the same calibration `hf_transplant_evidence:2285` already uses.
5. **`hf_transplant_evidence` must stop counting a chain as a duplicate.** Two tombstones whose
   `handed_off_to` values form a chain ending at one store are ONE move, not two. Today they are
   `dupes=1`. Minimal change: after collecting the set, if the `handed_off_to` values form a total
   order (each is the directory of the next tombstone found), take the LAST one and proceed.

---

## 6. (e) Lock lifetime, and an interrupted voluntary move

### Nothing reaps, expires or deletes the lock

A tree-wide grep for deletions under `locks/` returns nothing. `lr-transplant.sh:242-243` is the only
writer; `lr-lib.sh:454` is a *different* lock (`lr_state_append`'s event mutex). The readers are
`lr-lib.sh:544`, `lr-fire-resume.sh:245`, `lr-fleet.sh` (via lr-lib), `bin/cc-limited:954`,
`hooks/recover-inject.sh:55`, `lr-ingest-verify.sh:332`, and `hf_transplant_evidence` via the
tombstone's `.lock` key. **There is no TTL, no reaper and no release verb.**

The nearest thing to expiry is `bin/cc-limited:954-979`, which renders an un-acked lock as an
UNRESOLVED CLAIM once `NOW - ts > CLAIM_GRACE_S` (default 120 s, `bin/cc-limited:93`). It reports;
it does not reap. **And it is structurally blind to the state that matters here:** `:971` skips any
sid with a live registry row or a live `--resume` leaf — and a transplanted-but-not-recycled source
pane *is* a live registry row for that sid. So the one state a voluntary move can strand is the one
state `cc-limited` acquits.

The consequence is already documented as a measurement rather than a theory:
`lr-lib.sh:555-573` records that on 2026-09-20 the whole box held **one** lock, belonging to an
unrelated sid, while three panes with completed transplants had tombstones and **no lock at all**.
Locks are transient in practice; tombstones are durable.

### What an interrupted voluntary move leaves behind

Interruption window = after `lr-transplant.sh` exits 0, before the `/exit` + relaunch verifies.
This is `lr-handoff.sh`'s **exit 4** (`lr-handoff.sh:53-56`).

| artifact | state | who notices |
|---|---|---|
| target copy `<sid>.jsonl` | present, sha-verified (`lr-transplant.sh:259-263`) | `lr_transplant_target` ✅ |
| source `<sid>.jsonl` | renamed `.handed-off` (`:272`) — unless the driver WAS the session (`:271`), in which case it survives | `lf_locate` enumerates `.handed-off` for husks (`lr-fleet.sh:206-227`) ✅ |
| tombstone | written (`:267-269`) | guard, `hf_transplant_evidence`, `cc-husk-sweep` ✅ |
| lock | written, never released | `cc-limited` — but acquitted by the live source row ❌ |
| source pane | alive, session moved ⇒ **HUSK** | `lr_husk_state` ✅, but conjunct (c) suppresses it for `LR_HUSK_MIN_AGE_S` (900 s default, `lr-lib.sh:684`) if a `handoffs.jsonl` row exists |
| source prompts | **blocked** (`handed-off-session-guard.sh:138,175`, exit 2) | ✅ this is the load-bearing safety |
| target session | **not running** — nothing was relaunched | ❌ nothing owns re-firing it |

**So an interrupted voluntary move degrades into exactly the documented husk state, and every rail
that observes it is cause-free.** The recovery path is `--retire-husks` (`lr-fleet.sh:93`) or
`cc-husk-sweep`, both of which work unchanged. The one genuinely new exposure is that a *voluntary*
mover is a **healthy** session: unlike a limit-killed one it could have kept working, so the window
between transplant and relaunch is a window in which productive capacity is deliberately destroyed.
That argues for ordering, not for a new rail — see I6 below.

---

## 7. Proposed state model for a voluntary move

### The object

A move is one record with three parts, and the cause is a **property of the move, not of the session**:

```
MOVE := {
  sid,                       # unchanged across every hop — the whole point
  chain   : [store, …],      # lr-transplant.sh:234-241, unchanged
  owner   : store,           # the store that holds it NOW, lr-transplant.sh:104-109
  cause_chain : [cause, …],  # NEW, parallel to chain; |cause_chain| == |chain| - 1
  ts_first, ts               # unchanged
}
cause ∈ { limit, login-cliff, voluntary, unknown }
```

### The lifecycle (identical for every cause)

```
 LIVE ──lr-transplant──▶ MOVED(lock+tombstone written, target copy sha-verified)
                              │
             ┌────────────────┼─────────────────┐
             │                │                 │
      recycle verified   recycle refused   driver died
             │                │                 │
             ▼                ▼                 ▼
        CONTINUED          HUSK              HUSK
     (same pane, same    (source pane alive, session elsewhere,
      uuid, new store)    prompts blocked by the guard)
                              │
                     --retire-husks / cc-husk-sweep
                              ▼
                           RETIRED
```

**The cause never appears in the transition function.** It appears in exactly three places:

| where | why |
|---|---|
| **Admission** — `handoff-fire.sh:7833`, `bin/cc-lr:265`, `lr-ingest-verify.sh:167` | these decide whether a move is *owed*, which is a question about the cause |
| **Safety calibration** — `handoff-fire.sh:9716-9722` | what the move is allowed to destroy depends on whether it was already destroyed |
| **Reporting** — `lr-fleet --report`, `cc-lr status`, the guard's message text | the operator needs to know why their pane moved |

### Minimal change set (5 edits, 4 files)

| # | edit | file:line | risk |
|---|---|---|---|
| M1 | `--cause <limit\|login-cliff\|voluntary>` on `lr-transplant.sh`; default `unknown`; write it into lock and tombstone | `lr-transplant.sh:16-27, 242-243, 267-269` | none — additive JSON keys, no consumer dispatches |
| M2 | 🚨 gate the subagent auto-override on `cause = limit` | `handoff-fire.sh:9716-9722` | **this is the only edit that changes an existing outcome**; it makes a voluntary move REFUSE where a limit move proceeds, which is the safe direction |
| M3 | `--cause voluntary` on `--probe-recycle-preconditions` ⇒ skip the limit clause only, keep binding/teammate/pane/composer | `handoff-fire.sh:7831-7836` | low — every other clause binds harder |
| M4 | clause A4 PASSes on `cause=voluntary` when the tombstone says so | `lr-ingest-verify.sh:163-169` | low — A4 is advisory for the fast path, not a blocker |
| M5 | a `cc-lr move <ref> --to <acct>` verb that bypasses RULE 2; **and correct the false sentence at `bin/cc-lr:202`** | `bin/cc-lr:198-212, 265-268` | none for the correction; the verb is new surface |

---

## 8. Invariants the design must preserve

| # | Invariant | Enforced today by | What would break it |
|---|---|---|---|
| **I1** | **One transplant owner per session uuid.** Two live copies of one uuid is the split brain. | `lr-transplant.sh:166-176, 209-212`; `handoff-fire.sh:2328-2335` (lock must still exist); `:9688-9691` (`HF_TS_TO == RESUME_CFG`) | admitting a voluntary move by weakening the lock refusals instead of the limit gate |
| **I2** | **No state predicate branches on `cause`.** HUSK / DUPLICATE / `TRANSPLANTED→acct` must be computable from files alone. | `lr-lib.sh:542-710`; `bin/cc-husk-sweep:135-147` | adding `cause` to `lr_husk_state`'s conjunction, which would make every pre-field husk invisible |
| **I3** | **Tombstone before keystroke.** The completion certificate exists before anything is typed into a pane. | `handoff-fire.sh:9687` runs `hf_transplant_evidence` before `SID` is even assigned; `LIMIT_RECOVER_100P` §7 item 4 (operator requirement 2026-09-09) | driving a voluntary move as "recycle first, transplant after" |
| **I4** | 🚨 **A voluntary move may not destroy in-flight work.** | **Nothing, today** — `handoff-fire.sh:9721` grants the override unconditionally. `lr-ingest-verify.sh:222-226` (A6) is the only downstream detector and it fires *after* the loss. | shipping M1/M3/M5 without M2 |
| **I5** | **A teammate is never transplanted.** | `handoff-fire.sh:7843-7846` (probe), `lr-fleet.sh:225` (husk arm skips `agentName`), `bin/cc-lr:261-264` | a voluntary path that skips the probe entirely rather than skipping one clause of it |
| **I6** | **A move that cannot complete must not start.** The whole point of W2's pre-check ordering. | `lr-handoff.sh:851-853`, `handoff-fire.sh:7743-7749` | a voluntary path that sets `LRH_PRECHECK=off` to get past the limit clause — that disables the *pane*, *composer* and *teammate* reads too |
| **I7** | **The source's prompts stay blocked while a tombstone names another store.** | `hooks/handed-off-session-guard.sh:138, 175` | none identified; the guard is cause-free and correct |
| **I8** | **Custody survives every hop.** `ts_first` and `chain[]` are read-modify-written, never truncated. | `lr-transplant.sh:214-241` | a lock-less second hop (§5, row 3) — already broken today, independent of this feature |
| **I9** | **An absent `cause` is `unknown`, and `unknown` is admissible wherever `limit` is.** | n/a (new) | defaulting the field to `limit`, which would retroactively re-classify every existing artifact |
| **I10** | **Every refusal names the way forward.** | `lr-transplant.sh:172`; `bin/cc-lr:202-204`; `handoff-fire.sh:2290-2296` | a voluntary refusal that says "not limited" and stops — the defect `bin/cc-lr:163-177` was written to fix |

---

## 9. Adversarial pass — what a hostile reviewer would say I missed, and what I found

Three gaps investigated with real reads after the first pass:

1. **"You checked the actuators and called the surface cause-free; you did not check the VERIFIER."**
   Correct, and it found `lr-ingest-verify.sh:163-169` clause A4 — a hard `kind ∈ {session,weekly,
   monthly_spend}` assertion that no actuator-side audit would reach. Added as R27/M4.
2. **"Live subagents."** This is the sharpest hole and it is not in the transplant surface at all —
   it is `handoff-fire.sh:9721`, whose justification (*"A limit-blocked lead's subagents died with
   it"*) is a **true premise about the limit case and a false one about the voluntary case**. A
   healthy session electing to move has live subagents by construction, and the gate that would
   protect them (`subagent_gate`, rc 4) is switched off by the very flag the move requires.
   `NONLIMIT_RESUME_LADDER.md:238-244` (Finding 5) already names this hazard class for network
   deaths: *"A quota kill ends the session. A network drop usually does not… a still-live one reads
   PARTIAL and a blind re-run doubles it."* A voluntary move is that hazard at maximum severity.
   This is I4 / M2 and it is the one edit that must not be deferred.
3. **"Is the voluntary path actually closed, or just undocumented?"** Half closed. The **self**
   branch was opened today: `lr-handoff.sh:797-822` runs the probe RECORD-ONLY and discards its rc,
   naming *"being moved to a fresher account"* as a case it must not refuse. Only the **driver /
   `--source-pane`** branch (`lr-handoff.sh:757-771`) propagates the rc and therefore the limit gate.
   Anyone scoping this work from the driver path alone would over-estimate it by half.

## 10. Uncertainties, named

- **Not executed.** Every finding is from reading source. `lr-transplant.sh`'s idempotence (§4) is
  verified by code path, not by running it — the brief forbade touching a real lock. The bats suites
  `tests/lr-lib.bats`, `tests/handoff-selfclose-transplanted-source.bats` and
  `tests/lr-handoff-launcher-quoting.bats` exist and pin these paths; I did not run them.
- **`hf_transplant_evidence`'s `dupes` arithmetic under `set -euo pipefail`** (`handoff-fire.sh:326`,
  `:2278-2279`): line `:2278` is an `a && b && c` chain that evaluates false on the first tombstone.
  I read it as safe only because `:2279` follows immediately and returns 0, and because the function
  is called from `|| exit 2` contexts which suppress errexit. **I did not prove this**; if `:2278` can
  abort the shell it would be a live bug in the existing quota path, not something this feature
  introduces. Worth one `bash -x` run before touching that function.
- **`cc-limited`'s lock arm reads `rec.get("to")`** (`bin/cc-limited:977`), never `owner`. After a
  second hop the lock's `to` and `owner` are written identically (`lr-transplant.sh:242-243`, both
  `"$TO"`), so this is currently harmless — but it is a field-name coupling that a schema change
  could break silently.
- **Routing quality, not correctness.** `--target auto` uses the *recovery* lane's floors. Whether a
  voluntary move should use the general lane instead is a design question I did not resolve.
- **I did not audit** `lr-reset-poller.sh`'s request drain end-to-end (only its disposition filter at
  `:952`), nor `hooks/recover-inject.sh`, nor `bin/cc-route`. All three touch the lock path; none is
  on the irreversible path for a hand-driven voluntary move.
