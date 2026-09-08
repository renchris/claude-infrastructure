# The third fire of the same row — and why all three filed remedies would have let it through

**2026-08-19.** Backlog item `8f59467c92b0` — *"MASTER: product repos"*, project
`claude-infrastructure` — was dispatched to a `--venue cloud` session for the **third** time
(08-15, 08-17, 08-19). Same VM shape each time: one checkout (`renchris/claude-infrastructure`),
GitHub scope of one repository, no `~/Development`. Every open wave the row carries (`R1`-`R4`)
edits `~/Development/reso-management-app` or `~/Development/doc_classifier`.

The class was located on 08-16 and the two prior fires each wrote a correct disproof. This file
does not re-derive any of that. It records the one measurement that changes the remedy, and the
fix that landed because of it.

**R1-R4 are NOT adjudicated here.** The trees do not exist on this host; nothing about `pnpm lint`
on reso, the four unlanded branches, the Amplify/Fly split-brain, or `doc_classifier`'s
`require_role` holes was readable. They remain open, correct as filed, and unstarted. What is
refuted is the venue — never the plan.

---

## 1 · The measurement: this row's span names nothing, and every filed guard reads the span

`cc-eligible` classifies on the **span** — `title · dodRef · condition · source`, the item's
specification (`bin/cc-eligible:419`). For `8f59467c92b0` that is:

| field | value |
|---|---|
| `title` | MASTER: product repos — the operator's actual products, one wave per repo |
| `dodRef` | `docs/plans/MASTER_PRODUCT_REPOS.md` |
| `condition` | `master-product-repos` |
| `source` | `plan-open` |

Grepped against every project label in `scripts/dispatch-projects.conf`, that span returns **no
project row**. All four fields are *accurate*; the foreign checkouts appear only in the plan BODY.

That is fatal to all three remedies on file, and this is the finding:

| remedy | filed in | fires on this row? | why not |
|---|---|---|---|
| **(a) fail closed** on (`item.project`, `session.attached_repo`) | `cloud-venue-project-repo-mismatch-2026-08-16.md` §3 | **no** | both terms are `claude-infrastructure`; the label is correct (`scripts/find-plan.sh:70` derives it correctly from the plan's path) |
| **(b) route by `item.project`** | same, §3 | **no** | resolves to the VM it already went to; and a cross-repo master spans two trees, which a single-valued field cannot express at all |
| **(c) the 08-15 subject discriminator**, restored as a conjunct at `cc-offload` | `venue-foreign-master-redispatch-2026-08-17.md` §3 | **no** | it reads the item's *text* against `dispatch-projects.conf` — and the text names no project |

The 08-17 file proposed (c) precisely to catch this row. Measured: it does not. Its author could
not have known — the check requires enumerating the span against the conf, which is what §1 above
finally did.

**The common cause:** the one field that knows where the work lives is a **pointer**, and nothing
dereferenced it. `dodRef` is classified as *text* (`tests/cc-eligible.bats:14` pins that) and never
as a *path*.

## 2 · What landed

A second measured class in `bin/cc-eligible`, alongside `ineligible-deep-history` and modelled on
it: **`ineligible-foreign-tree`**.

- Plans may declare, in YAML frontmatter, which checkouts their work edits:
  `work-repos: reso-management-app, doc_classifier`.
- `cc-eligible` resolves `dodRef` → that plan → the declared labels. Any label ≠ the item's own
  project ⇒ refuse, naming the trees.
- **ANY** foreign tree refuses, not *all*: a cloud session holds exactly one repository,
  permanently (`cc-offload up --via api` exits 5 unless the session reads back exactly one
  `git_repository` source, `CLOUD_BACKLOG_PIPELINE.md:48-49`), so own-plus-foreign is no more
  completable off-box than foreign-plus-foreign.
- `MASTER_PRODUCT_REPOS.md` now carries that declaration, so this row refuses.

**It reads a DECLARATION, never the prose.** A frontmatter key is the plan author stating a fact
about the work; the body is not. That keeps the span rule this file guards intact (memory:
`assertion-span-must-equal-its-subject`), and `tests/cc-eligible.bats` pins it from the other side —
every fixture plan carries `body: reso-management-app` in its body and must stay eligible.

### Why this was safe to land, when 08-17 refused to land anything

Three refusal grounds were re-measured rather than inherited, and two are gone:

| 08-17 ground | 2026-08-19 |
|---|---|
| *"`bats` and `shellcheck` are both ABSENT — the repo's gate cannot be run"* | **refuted.** `npm i -g bats@1.11.0` succeeds through the proxy. The suite ran: 37/37 green, and the five refusal tests RED-prove against pristine `bin/cc-eligible`. |
| *"`bin/cc-offload` fires paid cloud sessions — an ungated guard there trades a bounded waste for an unbounded one"* | **avoided, not overridden.** The fire path is untouched. `cc-venue` imports `bin/cc-eligible` **as a module** — *"the same code object the claim gate runs"* (`bin/cc-venue:90`) — so a new entry in `BLOCKING` reaches the routing decision with no edit to `cc-offload`. |
| *"`OFFBOX_LANE` — a session this lane created cannot verify a change to the lane"* | **stands, and is why the class is opt-in.** The arm fires only on a plan carrying `work-repos:`, and exactly one plan in the tree carries it. Every uncertainty — no dodRef, unresolvable path, unreadable file, no frontmatter, no key — returns `[]` and the item stays eligible. This session could not verify a change that could starve the tap, so it did not write one. |

Five of the ten new tests exist only for that last row: they assert the *absence* of a refusal, and
they pass against pristine code as well as against the change. A regression here would not look
like a wrong refusal in the census — it would look like the cloud tap quietly refusing every item
whose plan it merely could not read.

## 3 · What this does NOT fix

- **The class**, only this shape of it. A subject-foreign row whose plan carries no `work-repos:`
  key is still eligible, and the open decision (`…mismatch-2026-08-16.md` §3) is still open. §1
  above widens it: whichever of (a)/(b) is chosen needs a conjunct that can see a row whose span is
  correct, and (c) is not that conjunct. The declared-tree arm is a working instance of one — a
  dereference rather than a match — but it needs the plan to opt in, and the class does not.
- **Local dispatch.** `cc-eligible` answers only *"may this go off-box?"*. A *local*
  `claude-infrastructure` worker is equally unable to edit those trees under the dedicated-worktree
  rail (`MASTER_PRODUCT_REPOS.md` 2026-08-15 status entry). All three observed fires of this row
  were cloud fires; this stops those and no others.
- **The store.** The item itself is untouched. See §4.

## 4 · The rails, re-measured — both still fail at rc 0

Not inherited from 08-17; re-run here:

```
$ bin/cc-backlog block 8f59467c92b0 --needs "…"
cc-backlog block: unknown id 8f59467c92b0                           # rc 0

$ bin/cc-notify --role desk "…"
cc-notify: verdict=unresolvable enqueued=0 reason=role-unset        # rc 0
```

The ledger lives at `~/.claude/autonomy/backlog.jsonl` and is absent here, so the id resolves to
nothing and both commands report success having done nothing. Both are also off `PATH` — invoked as
the brief spells them they exit 127. **A worker trusting either exit code would report this item
parked when it is not**, which is the most likely explanation for why 08-15's and 08-17's
dispositions did not hold.

Consequently the branch is the only durable channel, and — per 08-17 §1, *"a disproof written to a
markdown file does not park the item, because nothing in the dispatch chain reads plan prose"* —
this time the branch carries a mechanism and not only a paragraph. The operator action below is
still worth running (it parks the row in the store as well as at the gate), but the row is now
refused at `cc-eligible` whether or not it is:

```
cc-backlog block 8f59467c92b0 --needs "cross-repo master — claim only from a session HOLDING reso-management-app and doc_classifier; now also refused off-box by cc-eligible's ineligible-foreign-tree class (docs/research/venue-declared-foreign-tree-2026-08-19.md)"
```

## 5 · Measured from inside this session

| what | value |
|---|---|
| host / `$HOME` | `vm` / `/root` |
| `HEAD..origin/main` | **0** — this tree IS trunk; every read above is a trunk read |
| `~/Development`, `/Users` | both absent |
| GitHub scope | `renchris/claude-infrastructure`, one repository |
| span ∩ `dispatch-projects.conf` | **∅** — no project label appears in the item's specification |
| `bats` | ABSENT, then installed (1.11.0) via npm — the 08-17 blocker is not a property of the host |
| `tests/cc-eligible.bats` | 37/37 green; new refusal tests RED-prove on pristine `bin/cc-eligible` |
| pre-existing RED, not this diff | `tests/cc-venue.bats` #11, `tests/test-hermeticity-lint.bats` #19 — both fail identically with the change stashed |
