# A cloud dispatch whose specification was never committed — item 4ce239d21d67

**Filed 2026-08-24, from the cloud session that received the dispatch.**
Landed cure: `bin/cc-venue` question 1b (`ineligible-dod-offtrunk`), tests `cc-venue.bats` 23-29.

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
