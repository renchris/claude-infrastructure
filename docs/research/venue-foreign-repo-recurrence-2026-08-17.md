# Third foreign-repo dispatch in four days — the guard was specified twice and built zero times

**2026-08-17.** Backlog item `c33f3b1cb278`, **project `reso-management-app`**, was dispatched to a
`--venue cloud` session. Its brief names
`/Users/chrisren/Development/reso-management-app` as the repo and cites `operationBuilder.ts:553-562`,
`batchPrefetch.ts:350-355` and `appActions.ts`. None of that is reachable from the VM, so the item
was **unworkable on arrival** — the same end state as `1cc794cbc6c4` (08-14) and `9333991e4544`
(08-15).

The two prior files each recorded a **new route** to that end state, which is what earned them.
This one records no new route, and that is precisely the finding.

## Measured from inside the misrouted session

| what | value |
|---|---|
| clone | `git rev-list --count HEAD` → **51**, `.git/shallow` present |
| `~/Development` | absent (`/root/Development`) |
| `/Users` | absent |
| GitHub scope | `renchris/claude-infrastructure`, one repository |
| the three cited files | not in this tree (`find` over the checkout: 0 hits) |

`cc-eligible` reads the row as cloud-suitable, correctly under every rule it has:

```
classify(<the item's full text>)  →  ('eligible', 'repo-only work — no local-only state named', [])
```

The item names no local-only state, cites no sha, needs no browser, no pane, no launchd. Its
absolute repo path is read as nothing — measured, all four spellings, all `eligible` with zero
classes:

| probe | verdict |
|---|---|
| the item's full text | `eligible` · classes `[]` |
| `/Users/chrisren/Development/reso-management-app` alone | `eligible` · classes `[]` |
| `project reso-management-app, repo /Users/chrisren/…` | `eligible` · classes `[]` |
| `~/Development/reso-management-app` | `eligible` · classes `[]` |

## Both specified discriminators would have refused this row

This is the point of the file. The remedy is not under-specified; it is unimplemented.

- **The 08-14 conjunct** — *a `cloud` label additionally requires the item's project repo to be the
  one a cloud fire attaches* — refuses on the label alone. The row's `project` is
  `reso-management-app`; the attached repo is `claude-infrastructure`.
- **The 08-15 discriminator** — *an item whose text names a dispatch-set project other than its own
  `project`* — is not even needed here, but the text does carry the word, inside the path.
  `scripts/dispatch-projects.conf` line 3 enumerates `reso-management-app`.

So this is the **first repeat of route 1** (label-foreign), not a fourth route. The class has
stopped producing new spellings and started producing recurrences, which changes what the open
question is: it is no longer *what is the discriminator* but *why has neither form reached an
enforcing store in three days*. `grep -rn foreign-repo` over this repo returns three hits, all in
`docs/research/`, none in `bin/` or `scripts/` — the conclusion has not reached the gate
(memory: `conclusion-must-reach-the-enforcing-store`, the same diode `bin/cc-eligible`'s own header
names about the plan sentence it was built to replace).

Cost to date: three cloud slots and three accounts' quota, 08-14 / 08-15 / 08-17, with all three
items still needing a local claim.

## Not fixed here, deliberately — the same refusal as its two predecessors

`bin/cc-eligible`'s `OFFBOX_LANE` class states the rule this session is bound by: *a session this
lane created cannot verify a change to the lane — the observer and the subject are the same object.*
`bin/cc-venue`'s header says the same about a 50-commit clone deciding its own admission. This
session is that VM on that clone. Adding the conjunct from here is the thing the guard forbids, and
it is outside this item's frozen scope besides. The guard is its own item, on the desk.

Refusal token stays `ineligible-foreign-repo`, in the family `bin/cc-dispatch` already handles: its
`verdict=cloud-ineligible` arm treats such a row as a **skip, not a failure**, so the item stays
`open` and claimable locally — the desired end state, unchanged from 08-14.

## The ledger disposition could not be written from here — identically, for the third time

The rails handed to this dispatch call for `cc-backlog block` / `cc-backlog reopen` plus
`cc-notify --role desk`. Neither reaches, and both fail *quietly*:

```
$ cc-backlog reopen c33f3b1cb278
cc-backlog reopen: unknown id c33f3b1cb278          # rc 0

$ cc-notify --role desk "…"
cc-notify: verdict=unresolvable enqueued=0 reason=role-unset          # rc 0
```

`~/.claude/autonomy/` does not exist on this VM, so the store the rails name is empty and both
commands exit **0** while enqueuing nothing. A worker that ran them and trusted the exit code would
report the item parked when it is not. A cloud VM's only durable channel to the desk is the branch
it pushes, so — as on 08-15 — **this file is the notification.** The desk must reopen
`c33f3b1cb278` and claim it locally.

## The item itself — NOT adjudicated

No claim is made here about the `/list` concurrent-delete orphan, and none should be inferred. The
`LIST_HAS_ITEMS` guard, `batchPrefetch`'s `deleteList` case and `appActions.ts`'s admin CVR scoping
were never readable from this session. The brief's own first step — *read what this item cites on
TRUNK, check the cited sha against `origin/main`, because a post-land RED reproduces faithfully in a
stale tree* (`cc-backlog 6110fc45141e`) — is unrunnable here for the strongest possible reason:
there is no tree, stale or otherwise. Diagnosing it from the brief's prose is exactly the anti-goal
`bin/cc-venue` §5 names — *"a wrongly-routed item improvises a plausible answer against history it
cannot read, and reports success."*
