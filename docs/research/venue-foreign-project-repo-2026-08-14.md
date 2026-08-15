# A cloud VM attaches ONE repo, and nothing in the venue decision asks whether it is the item's

**2026-08-14.** Backlog item `1cc794cbc6c4` (project `doc_classifier`) was dispatched to a
`--venue cloud` session. The VM it landed in has `renchris/claude-infrastructure` cloned and
GitHub access scoped to that one repository. `~/Development/doc_classifier` does not exist there
and cannot be fetched, so **the item was unworkable on arrival** — before a single line of its
premise could be checked.

This is not a bad label on one row. It is a question the venue decision never asks.

## The measurement

From inside the misrouted session (`git rev-list --count HEAD` → 50 — the measured CLOUD_DEPTH;
`.git/shallow` present):

```
$ CC_BACKLOG_FILE=<fixture with the real row> CC_ELIGIBLE_REPO=~/Development/doc_classifier \
    cc-eligible why 1cc794cbc6c4 --json
  "verdict": "eligible",
  "description": "repo-only work — no local-only state named",
  "classes": [],
  "history": { "state": "no-repo", "repo": ".../Development/doc_classifier", "depth": 50 }
```

`eligible` is **correct under every rule cc-eligible has**. The work really is repo-only: it names
no local-only state, cites no sha, needs no browser, no pane, no launchd. The four questions
`bin/cc-venue` asks (spelling classes · cited-history reach · premise currency · can this box
certify) all pass on the desk, where `$HOME/Development/doc_classifier` is a full clone and
`HistoryOracle.certify()` returns `ok`.

Every answer is right. The item still cannot run, because *repo-only* is measured against **the
item's own repo** and a cloud fire attaches **the dispatching repo**. When those differ, no other
answer matters.

## Why the existing arms cannot catch it

- `cc-eligible`'s spelling classes enumerate *kinds of work* (box state, visual, github-beyond-the-
  one-cloned-repo). A foreign project has no spelling — its title reads like any other repo task.
- The measured history arm asks *can a 50-commit clone of this repo see the cited shas*. It
  presupposes the VM has a clone of that repo. Here there is none, and the state it reports —
  `no-repo` — is one the gate deliberately **fails open** on, because a missing repo on the desk is
  an instrument outage, not a verdict. Off-box it is not an outage: it is the answer.
- `cc-venue` fails closed on uncertainty, which would be the right posture — but it is never
  uncertain here. It is confidently right about the wrong repo.

The discriminator is one comparison nothing performs: **is the item's `project` the project the
cloud fire will attach?** For `CC_DISPATCH_PROJECT`-labelled work the answer is yes by
construction; `scripts/dispatch-projects.conf` deliberately widened the dispatch set to two foreign
projects (`doc_classifier`, `reso-management-app`), and the cloud lane's producer landed
independently. Neither change is wrong; their intersection is where this item fell.

## What this cost, and what it nearly cost

Cost: one burned cloud slot and one account's quota, with the item still `open`.

Nearly cost — the anti-goal `cc-venue`'s own header names (§5, "a wrongly-routed item improvises a
plausible answer against history it cannot read, and reports success"). This item's brief cites
`tests/fixtures/gen/scenarios.py::_frozen_file` and
`pipeline/s1_substrate/native_probe.py::source_type_of`. Neither file is readable from the VM.
Nothing in the environment *announces* that; a worker that assumed a stale checkout rather than an
absent repo could have written a confident diagnosis of two files it never opened.

## Not fixed here, deliberately

`bin/cc-venue`'s guard is explicit: *a cloud VM must never build or run the venue rule — it would
be deciding its own admission, and its 50-commit clone cannot read the history that justifies the
exclusions.* This session is that VM, on that 50-commit clone. Writing the guard from here is the
thing the guard forbids, so this file records the measurement and stops.

The shape a desk-side fix would take (one comparison, before the four questions):

- The venue decision resolves the item's project to a repo path today (`CC_ELIGIBLE_REPO`, else
  `$HOME/Development/<project>` — `bin/cc-eligible` docstring). The missing conjunct is that a
  `cloud` label additionally requires that repo to be the one a cloud fire attaches.
- Refusal token in the existing family (`ineligible-foreign-repo`), which `bin/cc-dispatch` already
  handles: its `verdict=cloud-ineligible` arm treats such a row as a **skip, not a failure** — the
  item stays `open` and claims locally untouched, which is exactly the desired end state.

🚨 **That comparison is necessary and NOT sufficient — measured 2026-08-15, one day later.** Item
`9333991e4544` is labelled project `claude-infrastructure`, which *is* the repo a cloud fire
attaches, so the conjunct above passes — and its subject is doc_classifier's nightly scale-run, so
the item was unworkable on arrival exactly as this one was. The label is not the subject. The
discriminator that refuses both is the project named in the item's own TEXT versus its `project`
field, both already on the row; the measurement, the two `cc-eligible` resolutions, and the caveats
are in `venue-foreign-subject-repo-2026-08-15.md`. Implement the conjunct from the text, not from
the label alone.

## The item itself

`1cc794cbc6c4` is **not adjudicated**. Its premise — authored `FrozenFile.source_type` disagreeing
with `source_type_of()` on 3 files — was neither confirmed nor refuted, and the possible
supersession by sibling `7bc597f698a7` (evidence `ae9f2075`) was not checked. Both require reading
`doc_classifier` on trunk. No claim about either is made here, and none should be inferred from
this file. The item needs a **local** claim.
