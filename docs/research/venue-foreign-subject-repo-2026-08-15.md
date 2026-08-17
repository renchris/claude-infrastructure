# The label is not the subject: a row labelled THIS repo, about ANOTHER, defeats the 08-14 guard

**2026-08-15.** Backlog item `9333991e4544`, **project `claude-infrastructure`**, was dispatched to a
`--venue cloud` session. Its subject is the nightly GitHub Actions scale-run of
`~/Development/doc_classifier` — *"100% failure 15/15, step `make scale-run SCALE_POINT=proving`
(RSS-budget assertion), ~1.07 failure emails/day; an alarm at 100% carries zero bits."*

That repo is not on the VM (`~/Development` does not exist) and is outside the session's GitHub
scope (`renchris/claude-infrastructure`, one repository). The item was **unworkable on arrival** —
the same end state as `1cc794cbc6c4` one day earlier
(`venue-foreign-project-repo-2026-08-14.md`), reached by a **different route**, which is the whole
reason this file exists.

## The 08-14 fix would not have caught this one

That doc proposes one missing conjunct: *a `cloud` label additionally requires the item's project
repo to be the one a cloud fire attaches.* On `1cc794cbc6c4` (project `doc_classifier`) the
conjunct refuses, correctly. On this row it **passes**, because the row's project label really is
`claude-infrastructure` and that really is the attached repo. Every term of the guard is satisfied
and the item is still unrunnable.

Measured from inside the misrouted session, against a fixture reproducing the row's shape
(`cc-backlog add --title "<the item's title>" --project claude-infrastructure`; the fixture keys to
`693ad28a72b2` rather than `9333991e4544` because the id hashes project+title+**source** and the
real row's source string was not readable from here — the title and project, which are what every
arm below reads, are verbatim):

| resolution | `cc-eligible why` | why it does not help |
|---|---|---|
| `CC_ELIGIBLE_REPO=~/Development/doc_classifier` — the repo the WORK needs | `eligible` · *repo-only work — no local-only state named* · `history.state: no-repo` | `no-repo` is the state the gate deliberately **fails open** on (an absent repo on the desk is an instrument outage, not a verdict) |
| `CC_ELIGIBLE_REPO=/home/user/claude-infrastructure` — the repo the LABEL resolves to, i.e. what the proposed conjunct compares | `eligible` · *repo-only work — no local-only state named* · `history.state: shallow` | this is the attached repo, so the conjunct is **satisfied** and routes `cloud` |

`eligible` is right under every rule `cc-eligible` has, exactly as on 08-14: the work names no
local-only state, cites no sha, needs no browser, no pane, no launchd. The title's only unusual
feature is the word `doc_classifier`, and no arm reads it as a repo.

### The VM-side guard fires, and is not the answer

`cc-venue assess` on this VM returns `local` / `uncertified-history` (`no-repo` for
`/root/Development/claude-infrastructure`). That is `bin/cc-venue`'s effect-keyed guard working as
designed — a shallow clone cannot certify, so a VM cannot write itself a `cloud` label. It is **not**
evidence the desk would have refused: on the desk that path is a full clone, `HistoryOracle.certify()`
returns `ok`, and every arm the producer asks is about `claude-infrastructure` and answers cleanly.
The guard bounds who may *write* the label; it does not see this row's defect at all. And it runs
after the fire, which is one burned slot too late.

## The discriminator that would catch both

Not the project label — the **subject named in the item's own text**. `scripts/dispatch-projects.conf`
already enumerates the label set (`claude-infrastructure`, `doc_classifier`, `reso-management-app`,
plus the declared skips), and this row's title *opens* with `doc_classifier`. An item whose text
names a dispatch-set project **other than its own `project`** is subject-foreign, whatever its label
says. That single comparison refuses `1cc794cbc6c4` (label-foreign) and `9333991e4544`
(subject-foreign) under one rule, and it needs no new store — both inputs are already on the row.

Refusal token stays in the existing family (`ineligible-foreign-repo`), which `bin/cc-dispatch`
already handles: its `verdict=cloud-ineligible` arm treats such a row as a **skip, not a failure** —
the item stays `open` and claimable locally, which is the desired end state.

Two caveats a desk-side implementer should not discover the hard way. A title naming another project
is not always subject-foreign — a genuine cross-repo claude-infrastructure item (a census, a fleet
sweep) names every project by construction, so the rule refuses some rows that would have run. That
is the correct direction of the asymmetry `bin/cc-eligible` already documents: a wrong INELIGIBLE
leaves an item exactly where it is, a wrong ELIGIBLE burns a slot and invites a confident answer
about invisible state. And it is a **spelling**, not the class — same standing caveat as the keyword
list it would join.

🚨 **The placement moved on 08-16, and this class recurred on 08-17.** `cloud-venue-project-repo-
mismatch-2026-08-16.md` §2-3 locates the mechanism at `bin/cc-offload:84` — the attached repo comes
from the FIRING checkout — and argues the discriminator belongs at the *fire*, not in
`bin/cc-eligible`'s spelling lists, whose widening it explicitly rejects. That does not retract the
subject-foreign route this file found; it relocates where the comparison should run. On 08-17
`c33f3b1cb278` (project `reso-management-app`) recurred on the 08-14 route: fourth in four days,
first on `reso-management-app`. `venue-foreign-repo-recurrence-2026-08-17.md`.

## Not fixed here, deliberately

`bin/cc-venue`'s header forbids a cloud VM from building or running the venue rule: it would be
deciding its own admission, and a 50-commit grafted clone cannot read the history that justifies the
exclusions. This session is that VM on that clone. It is also outside this item's frozen scope — the
guard is its own item, on the desk. So this file records the measurement and stops.

## The ledger disposition could not be written from here

The rails for this dispatch call for `cc-backlog reopen 9333991e4544` + `cc-notify --role desk`.
Neither reaches: `~/.claude/autonomy/` on this VM holds no `backlog.jsonl`, and
`cc-backlog reopen 9333991e4544` answers **`unknown id`**. A cloud VM's only durable channel to the
desk is the branch it pushes, so **this file is the notification**. The desk must reopen the row and
claim it locally.

## The item itself — NOT adjudicated

No claim is made here about doc_classifier's RSS-budget assertion, and none should be inferred. Its
`Makefile`, its scale fixtures and its nightly workflow were never readable from this session;
diagnosing them from the title alone is precisely the anti-goal `bin/cc-venue` §5 names — *"a
wrongly-routed item improvises a plausible answer against history it cannot read, and reports
success."*

What can be said without reading that repo is only the **shape** the remedy takes, already
established in this repo one day earlier by `docs/plans/CI_GREEN_PRODUCER_NOTIFICATION.md`: a
producer that is red on every run is spelling its null result in GitHub's error channel, and the fix
is to report without convicting (a gated skip), never an unconditional `exit 0` — while the
underlying red stays tracked as its own question. Whether doc_classifier's nightly is that shape, or
a genuine memory regression that should stay red and be fixed, is exactly what requires the repo.

That plan's §5 already records the failure mode to avoid on this class: prior task #157 fixed the
`diagrams` source (15/15 green) but never touched `hermetic`, and **closed anyway** — which is why
the symptom outlived its own fix. `9333991e4544` must not be marked done on the strength of this
file.
