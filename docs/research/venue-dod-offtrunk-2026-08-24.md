# A cloud dispatch whose specification was never committed — item 4ce239d21d67

**Filed 2026-08-24, from the cloud session that received the dispatch.**
Cure: `bin/cc-venue` question 1b (`ineligible-dod-offtrunk`), tests `cc-venue.bats` 23-29.
⚠️ **That cure sat UNLANDED for 7h28m and the same mis-route recurred — see §6, written by the
second cloud session, which is what actually carried both commits onto trunk.**
⚠️ **Then it recurred a THIRD time, 3h04m AFTER question 1b was on trunk — see §7.** A landed
classifier cannot re-decide a row it has already labelled, so the cure could not reach the row it
was written for. Second cure: `ready_rule_moved` in `bin/cc-dispatch`, tests
`cc-dispatch-readiness.bats` 31-37. Per §6's own rule, this header does not certify either cure's
landedness — only `git merge-base --is-ancestor` does.

This is the fifth entry in the `venue-*` family and the first whose defect is not about *which
repo* an item names. It is about whether the item's **own specification** exists anywhere a VM can
reach.

---

## 1. What was dispatched, and what arrived

Backlog item `4ce239d21d67` — *"RATIFY DECISIONS — triage, evidence, and the open remainder"*,
project `claude-infrastructure` — was dispatched to a cloud session with:

```
DoD ref: /Users/chrisren/Development/claude-infrastructure/docs/plans/RATIFY_DECISIONS_TRIAGE.md
PLAN-OPEN SNAPSHOT — 18 of 40 section(s) not DONE — showing the first 8: …
```

The brief was internally consistent and its falsifier had been re-run at fire time (`NOT REFUTED`).
Both facts were true **on the filing box**. Neither survived the trip.

`docs/plans/RATIFY_DECISIONS_TRIAGE.md` is on **no commit reachable from any ref** in this
repository. Two independent proofs, both run from a fresh clone standing exactly on trunk
(`git rev-list --count HEAD..origin/main` = 0):

| Probe | Result |
|---|---|
| `git log --all --oneline -- '*RATIFY*'` | zero commits |
| `git log --all -S"escalation classifier is wrong" --oneline` — a distinctive phrase from the brief's own section listing | zero commits |
| `grep -rn "escalation classifier is wrong\|exits 0 on refusals\|below 90% conviction" --include='*.md' .` | zero hits |

So the plan is an **uncommitted working-tree file**. `plan-phase-scan.sh` read it because the
scanner ran on the machine that holds it; every consumer downstream of the fire sees nothing at
all. The eight headings relayed inside the dispatch brief are the entire reachable specification,
and they are section *titles* — the decisions, the evidence and the conviction scores they name all
live in the unreachable body.

The container is also cut off from the ledger: `~/.claude/autonomy/` does not exist here, so
`cc-backlog done|block|reopen` and `cc-notify` have no store to append to. The disproof therefore
lands on trunk, which is the only durable store this venue can reach — see §5.

## 2. The premise this refutes

Not *"the RATIFY triage work is finished"* — that claim is untouched and unmeasurable from here.
What is refuted is narrower and mechanical:

> **REFUTED:** item `4ce239d21d67` is workable from the venue it was routed to.

It is not, and no amount of work inside this container could have made it so. The correct
disposition for the item is **local**, unchanged in every other respect.

## 3. Why no arm caught it — an asymmetry between two folds over one field

The gap is provable from the code alone, independently of this item's routing record (which lives
in a ledger this session cannot read). Each leg below was verified by *executing* the module, not
by reading it:

```
SPAN_FIELDS (cc-eligible)   : ('title', 'dodRef', 'condition', 'source')
classify_all(title+dodRef)  : []                      ← no local-only spelling fires
cc-premise spec text        : ('title','needs','evidence')   ← dodRef ABSENT
cited_paths(premise text)   : []                      ← the path arm has nothing to convict with
```

- **`cc-eligible` carries `dodRef`** into its spec text (`SPAN_FIELDS`, :450) — but its two arms
  are the spelling classes (a word list; a plan path fires none) and `HistoryOracle.unreachable`,
  which resolves **HEX** tokens against the clone horizon. Neither asks about a path.
- **`cc-premise` owns the path-vs-trunk arm** — `cited_paths` → `cat-file -e origin/main:<p>` →
  `verdict=suspect` (:2497-2556) — but its spec text is `("title","needs","evidence")` (:500) and
  `dodRef` is folded to a **separate field** (:535), read only by the `plan-open` probe (:1863),
  which is scoped to `source == "plan-open"` **and** gated on `os.path.exists` on the local box.

**The field reaches the classifier that cannot check paths, and is withheld from the one that
can.** The verdict stays `clear`, and `clear` is the producer's green light (`PREMISE_OK`).

Two adjacent gates are correct and are *not* the defect:

- `cc-dispatch:1749` — `[ -f "$sdod" ] || continue  # not a plan path ⇒ fail OPEN`. Failing open
  is right for a **local** dispatch: an unread premise is "I could not tell", never "it is
  finished" (I6), and the file genuinely is on disk there. It says nothing about a VM.
- `cc-eligible` failing open generally — by design; a wrong INELIGIBLE only leaves an item where
  it already is.

The producer is the one place in the chain that is *supposed* to fail closed, and it is where the
question was missing.

## 4. The cure

`bin/cc-venue` gains **question 1b — is the specification itself on trunk?** — between the history
certification and the premise probe:

- Four kept-apart answers: `n/a` (not a path claim — `decision:<id>` is untouched) · `ok` ·
  `absent` (the only proof) · `unknown` (could not ask → route local, never promote).
- An **absolute** dodRef — the spelling `cc-dispatch`'s own `[ -f "$sdod" ]` gate reads, and the
  one the live store carries — is tried as progressive suffixes, so a path recorded from the filing
  box's filesystem still resolves against trunk. A suffix matching some *other* file of the same
  name is a false **acquit**, which is the direction this file is safe to be wrong in.
- Ordered **before** `premise_verdict`, which executes the item's stored falsifier: a side effect
  spent on work that can never go off-box buys a verdict nobody reads.

**Why not widen `cc-premise`'s spec text instead.** Adding `dodRef` there would flip every row with
an off-trunk plan to `suspect` store-wide — the fabricated-finding class that file measured at 80
false convictions in 156 (`bin/cc-premise:697`) — and `suspect` is read by workers and sweeps, not
only by this decision. The producer arm's blast radius is one bit in one direction, cloud → local,
which `cc-venue`'s own header prices at nothing.

**Red-proof** (stash `bin/cc-venue`, re-run): cases 23, 24, 26, 29 fail against the unfixed
producer. Cases 25, 27, 28 pass in both directions **on purpose** — they pin that the arm does not
convict a row it has nothing to say about.

Suite 28/29 green. Case 11 fails **in this container only**: it `chmod 000`s the ledger and the
session runs as root, so the read still succeeds. Verified identical with `bin/cc-venue` stashed —
not from this change, and expected green on the operator's box.

## 5. What is still open, and who owns it

The cure stops the **next** mis-route. It does not do the RATIFY work, and cannot.

1. **`docs/plans/RATIFY_DECISIONS_TRIAGE.md` is still uncommitted** on the operator's box. Until it
   lands, item `4ce239d21d67` is a local-only item by construction — and after this change the
   producer will say so in its `venueWhy` instead of routing it off-box again.
2. **The item was not closed.** Its premise about the *work* is untested; only its premise about
   the *venue* was refuted. It should stay open and be claimed locally.
3. **This disproof is not in the ledger.** No `~/.claude/autonomy/` store exists in a cloud
   container, so the `cc-backlog add … 4ce239d21d67` the dispatch contract asks for could not be
   written. Filing it against this document is an operator step:

   ```
   cc-backlog add --project claude-infrastructure \
     --title "4ce239d21d67 was routed off-box against an uncommitted DoD — cure landed in cc-venue q1b; land the plan or keep the item local" \
     --dod-ref docs/research/venue-dod-offtrunk-2026-08-24.md
   ```

4. **Worth a census, not assumed:** how many live rows carry a `dodRef` that resolves nowhere on
   trunk? `cc-venue run --json` now answers it directly — count `token:ineligible-dod-offtrunk`.
   That census needs the live ledger and so belongs on the box.

---

## 6. The cure was never landed, so the mis-route recurred — measured on the second dispatch

*Added 2026-08-25 by the SECOND cloud session dispatched against this same item.*

Everything in §1-§5 was correct. It was also **stranded**: both commits sat on
`origin/claude/fire-20260824T173421Z-26819-1` and neither ever reached trunk. The item stayed open
with its `dodRef` unchanged, the producer still had no question 1b, and the dispatcher did the only
thing an unfixed producer can do — **it sent the same item off-box again**:

| Event | Time (UTC) | Evidence |
|---|---|---|
| Cure committed | 2026-08-24 17:46:58 | `262e7848` (`fix(cc-venue)`) |
| Disproof committed | 2026-08-24 17:48:01 | `0ec44a65` (`docs(research)`) |
| **Neither landed** | — | `git merge-base --is-ancestor <sha> origin/main` → **false** for both; `git branch -a --contains` names one branch and it is not `main` |
| **Same item dispatched again** | **2026-08-25 01:15:39** | this session's own branch, `claude/fire-20260825T011539Z-45220-1` |

**7h28m between the fix and the recurrence it was written to prevent.** The second VM arrived, ran
the same two probes from a fresh clone standing on trunk, and reproduced §1's table exactly —
because from trunk's point of view nothing had happened.

**This is the third face of the same defect and it belongs beside the other two.** §3 explains why
no *classifier* asked the question; this section is why asking it would not yet have mattered. A
cure that is committed but not landed is, to every consumer, indistinguishable from a cure that was
never written — the `📦`-stranded class the root `CLAUDE.md` prices at "one crash, stale worktree,
or forgotten branch from being lost". Here the loss was not hypothetical: it was **a whole second
cloud session**, spent re-deriving a conclusion that already existed on a branch nobody read.

⚠️ **The doc asserted its own landing.** This file's header read *"Landed cure: `bin/cc-venue`
question 1b"* while the commit carrying it had never been an ancestor of `main` — written in the
future tense of a `/ship` that did not run. **A document may not certify its own landedness**; the
only admissible proof is `git merge-base --is-ancestor` against the trunk ref, which is the check
this section ran and the previous header did not. The header now says `Cure:` and points here.

### What this session verified before landing, rather than inheriting

The §4 claims were **re-run from scratch**, not taken on trust — a stale tree reproduces a
post-land RED faithfully, so an inherited green is worth nothing:

- **Red-proof, both directions.** With trunk's `bin/cc-venue` restored in place: **24 ok / 5 not-ok**
  — cases **23, 24, 26, 29** fail, exactly as §4 claims. With the fix: **28 ok / 1 not-ok**. Cases
  **25, 27, 28** pass in both directions, confirming the arm is scoped rather than blanket.
- **Case 11 is a container artifact, confirmed by control.** It `chmod 000`s the ledger and asserts
  a refusal; this VM runs as **uid 0** (`id -u` → `0`), so root reads the file anyway and the
  refusal never fires. It fails **identically with the fix stashed**, so it is not from this change.
  The `cc-dispatch-readiness` suite — the other suite `gate-select.sh --direct` names for this diff
  — is **30/30 green**.
- **The arm convicts this item's own `dodRef`**, which §4 argued but never executed against the
  real value. Calling `dod_trunk_state()` directly, `repo` = this clone, `ref` = `origin/main`:

  | `dodRef` | verdict |
  |---|---|
  | `/Users/chrisren/…/docs/plans/RATIFY_DECISIONS_TRIAGE.md` (the live value) | **`absent`** → routes LOCAL |
  | `/Users/chrisren/…/docs/plans/BACKLOG_DRAIN_24_7.md` (a plan on trunk) | `ok` → still eligible |
  | `decision:5f0a1b2c3d4e` | `n/a` → untouched |

  The absolute filing-box path is convicted **by suffix**, which is the mount-prefix case §4 says is
  the whole reason the candidate ladder exists. Had question 1b been on trunk at 01:15, this
  session would not have been dispatched.

### What is STILL open after this land

§5's four items are **unchanged and still the operator's** — landing the cure does not do the RATIFY
work, and this VM still has no `~/.claude/autonomy/`, so the §5.3 `cc-backlog add` remains unfiled
from here. One item is added:

### Correction to §5.3 — the ledger call does not fail, it succeeds into nothing

§5.3 says the contract's `cc-backlog add … 4ce239d21d67` "could not be written". **Measured here, that
is wrong in mechanism, and the true mechanism is worse.** `bin/cc-backlog` ships *in the repo*, so a
cloud worker has the binary; what it lacks is `~/.claude/autonomy/`. Probed in an isolated `HOME`:

| Call | rc | Effect |
|---|---|---|
| `cc-backlog add --project … --title …` | **0** | prints a well-formed id (`7de6dbc73870`) and **creates** `$HOME/.claude/autonomy/backlog.jsonl` |
| `cc-backlog done 4ce239d21d67 --evidence …` | 3 | `unknown id` — correct refusal |
| `cc-backlog block 4ce239d21d67 --needs …` | 3 | `unknown id` — correct refusal |

The verbs that need an **existing row** cannot be faked: the empty store has no such id and they exit
3. But `add` — **the one verb the dispatch contract names for writing a disproof back** ("write it
back into the store (`cc-backlog add`, naming this item's id)") — has no row to miss. It exits 0,
returns a plausible id, and silently mints a **phantom store** that dies with the container. A worker
that follows the contract literally gets every signal of success and files nothing.

So the disproof-filing half of the dispatch contract is not merely unavailable off-box; it is
**unavailable while reporting success**. Landing the disproof on trunk instead is not a workaround
for a missing tool — it is the only write from this venue that leaves a trace, which is why §5.3's
`cc-backlog add` stays an operator step and this document is its evidence.

*(Caveat on the measurement: `bin/cc-backlog list --all --json` also returns `[]` at rc 0 against the
absent store — an empty ledger and a missing one are indistinguishable to a caller. Both readings
above were re-taken without a pipe after a first pass read `$?` from `head` and mis-scored the two
rc-3 refusals as rc 0.)*

5. **Item `4ce239d21d67` must not be dispatched a third time.** With question 1b on trunk the
   producer now refuses it by itself (`venueWhy: ineligible-dod-offtrunk`), so no operator action is
   needed to *stop* the loop. What remains is the disposition: either commit
   `docs/plans/RATIFY_DECISIONS_TRIAGE.md` so the item becomes workable anywhere, or leave it
   uncommitted and work the item locally. Until one of those happens the RATIFY triage itself —
   the 18 not-DONE sections — has been touched by nobody, twice.

---

## 7. It WAS dispatched a third time — the cure landed and could not reach the row it was written for

*Added 2026-08-25 by the THIRD cloud session dispatched against this same item.*
*Cure: `037144e0` — `ready_rule_moved` / `venue-rule-moved` in `bin/cc-dispatch`, tests*
*`cc-dispatch-readiness.bats` 31-37.*

§6 closed on a prediction, and it is the one thing in this document that was wrong:

> **Item `4ce239d21d67` must not be dispatched a third time.** With question 1b on trunk the
> producer now refuses it by itself, so no operator action is needed to *stop* the loop.

**REFUTED, by this session's own existence.** Question 1b was on trunk. The producer did not refuse
it. The measurement:

| Event | Time (UTC) | Evidence |
|---|---|---|
| Question 1b landed on trunk | 2026-08-25 **01:18:11** | `fc7f4ac1`, `git merge-base --is-ancestor fc7f4ac1 origin/main` → **true** |
| **Same item dispatched a THIRD time** | 2026-08-25 **04:22:38** | this session's branch, `claude/fire-20260825T042238Z-7446-1` |

**3 h 04 m after the cure landed, and it went off-box anyway.** §6 was right that a cure which never
lands is invisible; it did not consider that a cure which HAS landed can still be invisible to the
rows it was written for.

### 7.1 Why the landed producer never spoke

Not because it was wrong. Executed here, from a fresh clone standing on trunk, the landed classifier
decides this row correctly:

```
cc-venue label 4ce239d21d67   →   local
```

The producer was simply **never asked again**. Nothing re-derives a settled label inside the window,
and each of the three arms that could have was verified by executing it, not by reading it:

| Arm | Why it did not fire |
|---|---|
| `venue_label_new` — label on write (cc-dispatch:1429) | selects `(.venuePlan // "") == ""` **and** a 900 s recency window. This row is labelled and old; it is in neither population. |
| the admission-time repair (cc-dispatch:1189) | fires only on `venue-unlabelled` or `trunk-moved`. Not the first — the row has a label. Not the second — see 7.2. |
| `cc-venue run --apply` — the 6 h pass (autonomy-sweep.sh:694) | `CC_VENUE_PASS_EVERY_S` defaults to **21600**. 3 h 04 m < 6 h, so it need not have run at all. |

That the row still carried `cloud` at 04:22 is not inferred: the live dispatcher runs
`CC_DISPATCH_VENUE_ONLY=cloud` (cc-dispatch:2496, read from launchd argv), and that filter is an
**element-exact** match on `venuePlan`. A row labelled `local` cannot reach the cloud lane. This
session reached it.

### 7.2 The generalisable defect: staleness is measured per-ITEM, never per-RULE

`ready_moved` asks *"did trunk move under the paths THIS ITEM cites"*. That is a question about the
item's **subject matter**. A landed change to the **classifier** moves no item's cited paths — so a
rule that starts convicting a row **can never invalidate the label it already wrote**. The cure's own
landing is structurally invisible to the machinery that would propagate it.

Its blast radius therefore reaches unlabelled rows at once and settled rows only on a 6 h timer, and
in between the dispatcher goes on acting with full confidence on the verdict that was just replaced.

**For THIS class of row the admission repair could never have helped, at any cadence** — and that is
the sharper half. Executed:

```
cc-venue paths 4ce239d21d67   →   {"paths": [], "repo": …}   rc 0
```

An empty path set, because the premise text is `title + needs + evidence` (cc-premise:500) and
`dodRef` is folded to a **separate field** — the same asymmetry §3 found in the decision path,
reappearing in the invalidation path. So `readiness_verdict` short-circuits at `cites-nothing`,
which is **deliberately not repairable**. The rows whose whole specification is a `dodRef` — exactly
the rows question 1b exists to convict — are precisely the rows whose labels the admission seam
structurally cannot refresh.

### 7.3 The cure

`ready_rule_moved` adds the **routing rule's own surface** (`bin/cc-venue`, `bin/cc-eligible`,
`bin/cc-premise`) as an invalidation basis: if any of them landed a change since this item's basis
sha, the label reads `venue-rule-moved` and is re-derived. It joins the repair list as its most
literal member — the cure for *"the producer changed"* is to re-run the producer.

Four properties, each pinned by a case:

- **Ordered ABOVE the item-path arms** (case 34). Below them it would be dead for exactly the rows it
  rescues, which reach `cites-nothing` first.
- **Not folded into `cites-nothing`** by adding the rule paths to the item's own set — that would
  make every row cite something and destroy the empty-set signal, laundering a void into a ready
  (the trap case 7 exists to pin).
- **Fail-open** (case 35): only rc 0 convicts, so an unreadable repo or an absent basis falls through
  unchanged. Scoped by construction — the rule paths exist only in this repo, so an item in another
  project diffs an absent path and is never convicted by a rule it does not run (case 33).
- **Self-limiting** (case 36): the repair advances the basis, so one landing costs one re-derivation
  per row rather than a treadmill.

Effect on the loop: the window between a landed routing cure and the rows it governs falls from **up
to 6 h** to **one dispatch pass**.

⚠️ **Case 37 was written against this diff's own first draft and failed it.** The arm used
`${VAR:-…}` while its env doc promised *"empty ⇒ the arm never convicts"* — so the off switch it
documented did not exist. The switch is now the word `off`, and an empty value deliberately falls
back to the default: the two spellings differ by a character easy to type by accident, and only one
of those accidents may be allowed to silently restore the bug this arm closes.

### 7.4 What this session verified before landing

- **37/37** on `cc-dispatch-readiness.bats`, including the per-site mutant (case 32: delete the arm
  and the same fixture keeps its stale label).
- **20 direct suites** from `gate-select.sh --direct`. Four carry reds — `cc-dispatch-fire-evidence`
  (2), `cc-dispatch-projects` (1), `operator-readout` (43), `cc-venue` (1) — and **all four
  reproduce identically with trunk's own `bin/cc-dispatch` restored in place**, so none is from this
  change. They are the container artifacts this family already documents: BSD `stat -f` on Linux, and
  `chmod 000` fixtures that a uid-0 session reads anyway.
- `assert-liveness` **0 dead** · `testname-eval` clean · `hermeticity` clean ·
  `shellcheck -S error` clean.

### 7.5 What is STILL open, and who owns it

§5's items stand, **unchanged and still local**. The cure stops the mis-route; it does not do the
RATIFY work, and no session in this venue can:

1. **`docs/plans/RATIFY_DECISIONS_TRIAGE.md` is still on no commit reachable from any ref.** Re-probed
   from this clone standing on trunk: `git log --all --oneline -- '*RATIFY*'` → zero commits;
   `grep -rn "below 90% conviction"` over the repo → zero hits. The 18 not-DONE sections have now
   been touched by nobody, **three times**.
2. **The item is not closed by this session either.** Its premise about the *work* remains untested
   from here; what was refuted, again, is its premise about the *venue*.
3. **The disproof is still not in the ledger** — no `~/.claude/autonomy/` exists in a cloud
   container, and per §6's correction `cc-backlog add` would exit 0 into a phantom store. Trunk
   remains the only durable store this venue can reach.

The disposition has not changed since §5 wrote it, and is now overdue: **either commit the plan so
the item becomes workable anywhere, or work the item locally.** What HAS changed is that the
dispatcher will no longer keep choosing for you — with `037144e0` on trunk the stale `cloud` label is
re-derived on the next pass rather than on a 6 h timer, so the fourth dispatch does not happen.

### 7.6 …and this cure could not be landed from this venue either — the fourth face

§6's finding was that a cure which never lands is invisible. §7's is that a landed cure cannot reach
rows already labelled. This section is the third member of that family, discovered while trying to
land §7.3: **`scripts/ship-land.sh` cannot complete in a cloud container at all**, so a cloud
worker's only sanctioned landing rail is closed to it.

```
✗ gate: unattended-path-lint --selftest FAILED — the detector no longer discriminates.
✗ ship-land: GATE RED — not pushing.                                            EXIT=6
```

**It is not a verdict about this diff.** `scripts/unattended-path-lint.sh` decides whether a bare
binary name is reachable by asking *"does this box install such a binary at all"* — and a NO
**drops** the finding (`:889-897`, the lint's own founding example). Its fixtures are macOS stock
binaries in `/usr/sbin:/sbin`, which do not exist on Linux, so on this platform the detector cannot
discriminate in either direction and its self-check fails by construction. Proven, not inferred:

| Probe | Result |
|---|---|
| `unattended-path-lint.sh --selftest` in this branch | FAILED, 9 of 39 |
| the same, in a clean `git worktree` at **`origin/main`** | FAILED, **9 of 39** |
| `diff` of the two failing-case sets | **byte-identical** |
| the lint's real scan over this land's own files (`CC_UNATTENDED_OWN`) | **rc 0 — clean** |

So the arm that blocks the land is red on trunk, in a tree this change never touched, and says
nothing whatever about the two files being landed.

**Not bypassed, deliberately.** `SHIP_LAND_UNATTENDED_LINT` would skip the arm in one assignment and
the land would go green. That is disabling a guard to get green — prohibited outright, and the guard
is real on the operator's macOS box where it *can* discriminate. A bare `git push origin HEAD:main`
is prohibited by both this repo's `.claude/CLAUDE.md` (standing-land is "exclusively for the
fail-closed project-local `/ship`") and this session's own rails. Neither escape is legitimate, so
the work is committed and pushed to its own branch and **the land is the operator's step**.

**Why this belongs in this family rather than in a note.** The pipeline's own law, quoted in the
`/ship` skill, is that a cut suite is a **non-verdict** — *"a claim about the machine, not your
tree"* — and R6 says a non-verdict is not a red. This arm produces exactly such a non-verdict and is
nonetheless classified `gate_red`, which closes the only sanctioned rail for every cloud lander. The
measured cost of that class is already on the record two sections above: **§6 is what a stranded
cloud cure costs, and it cost a whole session.** This is the same trap one layer down — §7's cure
against a fourth dispatch is, as of this writing, exactly as stranded as §6's was, and for a reason
the author cannot fix from inside the venue.

**The narrow fix is NOT attempted here, on purpose.** Giving the lint (or the gate arm) a platform
guard is a change to the land pipeline every session on the operator's box depends on, and it cannot
be validated on the platform where it matters from a Linux container. Filing it beats landing an
unvalidatable change to the thing that does the landing.
