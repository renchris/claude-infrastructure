# The third cloud fire of `8f59467c92b0` — the return rails are rc-0 no-ops, and that is the generator

**2026-08-27 · written from inside the cloud VM that received the dispatch.**
Branch `claude/fire-20260827T062244Z-2364-1`, HEAD `050569c3`, shallow depth 50.
Sixth entry in the `venue-*` family; direct successor to
`venue-foreign-master-redispatch-2026-08-17.md` (the second fire of this same row) and
`cloud-venue-foreign-project-2026-08-21.md` (which specified the fix).

**Finding, in one line:** backlog item `8f59467c92b0` — the `MASTER: product repos` row, whose every
open wave edits `reso-management-app` or `doc_classifier` — was fired into a cloud VM for the
**third** time in twelve days, and the two things this fire adds to the record are that **(1) all
three filed remedies are keyed on `item.project`, which for this row is the cloud lane's OWN repo,
so none of them catches it**, and **(2) the brief's own completion rails exit 0 while writing
nothing** — so a cloud fire of a foreign-tree item is structurally incapable of parking itself, and
the next discovery pass re-mints it. The recurrence is not a policy gap. It is a no-op that reports
success.

---

## 1 · The venue, measured

Identical in shape to the 08-15, 08-17, 08-21 and 08-22 fires:

```
$ ls ~/Development                          → No such file or directory   (HOME=/root)
$ ls -d ~/Development/reso-management-app   → No such file or directory
$ ls -d ~/Development/doc_classifier        → No such file or directory
$ ls /home/user                             → claude-infrastructure
$ git rev-list --count HEAD                 → 50            (shallow)
$ git rev-list --count HEAD..origin/main    → 0             (standing on trunk)
$ ls ~/.claude/autonomy/                    → No such file or directory
GitHub MCP scope                            → renchris/claude-infrastructure only
```

The plan's four open waves are `R1`–`R3` (reso) and `R4` (doc_classifier). Both trees are absent and
neither is fetchable: GitHub reaches this VM only through MCP tools pinned to the one cloned
repository. **Unreachable by construction, not by difficulty.** Nothing in R1–R4 was touched,
because nothing in R1–R4 was readable.

## 2 · Every existing arm PASSES this row — and so does the one that was specified as the cure

`bin/cc-venue`'s ladder is questions 1, 1b, 2, 3, 4. Taken in order against this row:

| Arm | What it reads | Verdict on `8f59467c92b0` |
|---|---|---|
| 1 · spelling classes (`bin/cc-eligible` `CLASSES`) | regexes over `title`+`dodRef`+`condition`+`source` | **passes** — "advance MASTER: product repos" names no local-only state |
| 1b · `dod_trunk_state` | is the dodRef on trunk | **passes** — `docs/plans/MASTER_PRODUCT_REPOS.md` is on `origin/main`; verified here with `git show` |
| 2 · `DEEP_HISTORY` | cited shas vs the 50-commit horizon | **silent** — this item cites no sha |
| 3 · `bin/cc-premise` | is the premise still standing | **passes** — the falsifier was re-run at fire time and declined to retract (`NOT REFUTED`), correctly: R1–R4 are genuinely open |
| 4 · horizon oracle | can this box certify 2 | n/a on the dispatching box |

Every arm answers truthfully and the composite answer is wrong. That much the 08-17 entry already
established. What is **new** here is the fate of the remedy filed since:

`cloud-venue-foreign-project-2026-08-21.md` §5 specifies a third measured arm —
`CLOUD_PROJECTS = {"claude-infrastructure"}`, verdict token `ineligible-foreign-project`, refusing
any item whose `project` is not in the set. It is the most concrete remedy in the family, and it is
**not landed** (verified this session: `grep -n 'CLOUD_PROJECTS\|ineligible-foreign' bin/cc-eligible
bin/cc-venue bin/cc-backlog` → zero hits, 6 days after filing).

More important than its landedness: **it would not catch this row.** `scripts/find-plan.sh:70
project_name_for()` derives the project from the plan FILE's path, so this row is labelled
`claude-infrastructure` — the dispatch brief carries it verbatim: *"cc-backlog item 8f59467c92b0
(project claude-infrastructure, repo /Users/chrisren/Development/claude-infrastructure)"*. That label
is *in* `CLOUD_PROJECTS`, so the arm acquits.

That is now **three** filed remedies that all pass this row:

| Remedy | Filed | Keyed on | On this row |
|---|---|---|---|
| `cloud-venue-project-repo-mismatch-2026-08-16.md` §3, both options | 08-16 | (`item.project`, `session.attached_repo`) | passes — noted by the 08-17 entry |
| `cloud-venue-foreign-project-2026-08-21.md` §5 `ineligible-foreign-project` | 08-21 | `item.project ∈ CLOUD_PROJECTS` | **passes — this file's finding** |
| a plan-index `projectName` set to a foreign project | 08-17 | `item.project` | would park it, but only *composed with* an arm that convicts on foreign projects — i.e. it depends on row 2, which acquits today |

The through-line is one sentence: **`project` is a label derived from where the plan FILE sits, and
for a cross-repo master the file and the work sit in different repos.** Every project-keyed
discriminator inherits that, and none of them can see the disagreement.

## 3 · What WOULD catch it — measured, not proposed in the abstract

The discriminating evidence is in the plan BODY, and question 1b has already paid for reaching it:
1b resolves the dodRef to a trunk pathspec and proves it readable, so the body is one `git show`
away at zero extra resolution cost.

Run here against the trunk copy:

```
$ git show origin/main:docs/plans/MASTER_PRODUCT_REPOS.md \
    | grep -oE '~/Development/[A-Za-z0-9._-]+|/Users/[^/]+/Development/[A-Za-z0-9._-]+' \
    | sed -E 's#.*/Development/##' | sort | uniq -c | sort -rn
      3 reso-management-app
      1 doc_classifier
      1 claude-infrastructure
```

Two `~/Development/<repo>` roots outside the lane's clone set, named three and one times, in a
document the gate already opens. **The conjunct the 08-17 entry asked for — "the 08-15 subject
discriminator restored" — is decidable from bytes question 1b already holds.**

Spec, for the local session that implements it:

- A conjunct at the promotion point, alongside 1b rather than inside `CLASSES` (which is the pure
  spelling table): when `dod_trunk_state` returns `ok`, scan the resolved body for
  `~/Development/<repo>` and `/Users/<u>/Development/<repo>` roots; refuse when the set of roots
  found contains any repo outside the venue's clone set.
- **Fail-open on every uncertainty**, per the family's founding rule: body unreadable → do not
  refuse; zero roots found → do not refuse (a plan may legitimately name no path). The arm may only
  convict on a POSITIVE reading of a foreign root, which makes it the same shape as 1b's
  "may only acquit on a positive resolution", inverted.
- It composes with, and does not replace, the 08-21 `ineligible-foreign-project` arm: that one
  catches a *correctly-labelled* foreign row (`b0be87487228`, `40c7207a96b1`, `0dafb03ed73d`); this
  one catches a *correctly-labelled home* row whose work is foreign. The family has now measured
  both directions, and they need different evidence.

## 4 · 🚨 The generator — the return rails exit 0 and write nothing

The 08-17 entry recorded that "the rails fail at rc 0 from a VM" and told the next session to verify
the block rather than assume it. This session measured it at verb level. Against the VM's exact
store shape (an empty ledger — `cc-backlog list --all` returns zero rows here):

```
$ cc-backlog block 8f59467c92b0 --needs "…"
cc-backlog block: unknown id 8f59467c92b0
block exit=0
$ wc -l < "$CC_BACKLOG_FILE"
0

$ cc-backlog done 8f59467c92b0 --evidence "…"
cc-backlog done: unknown id 8f59467c92b0
done exit=0
```

Both terminal verbs of the dispatch brief — `On completion: cc-backlog done …` and `If blocked …:
cc-backlog block …` — **print a diagnosis to stderr and exit 0 having appended nothing.**

The brief's third rail, the one meant to reach a human when the first two cannot, is the same:

```
$ cc-notify --role desk "…"
cc-notify: verdict=unresolvable enqueued=0 uuid= reason=role-unset target=--role desk
cc-notify: role 'desk' is not set — no live pane at /root/.claude/cc-roles/desk
cc-notify: fallback=phone-unwired — push-send is INERT (PUSHOVER_TOKEN/PUSHOVER_USER unset)
notify exit=0
```

`enqueued=0`, both channels dead, **exit 0**. So **all three return rails the brief names — `done`,
`block`, `notify` — are rc-0 no-ops in this venue.** There is no verb a cloud worker can run that
changes any state the dispatching box will ever read. The only channel that survives the trip is the
git branch, which is why this file exists and why it is the whole deliverable.

This is the generator of the whole recurrence, and it reframes the 08-17 finding that *"a disproof
in plan prose does not park an item — nothing in the dispatch chain reads it, so the 08-15 entry
bought two days"*. Prose is not the weak part. **No action available to a cloud worker can park a
foreign-tree item**, because the only rail that parks anything writes to a store the venue does not
have, and it reports success when it fails. So the row stays `open`, the next discovery pass sees an
open plan with an unrefuted falsifier, and re-mints. Twelve days, three fires, each ending in an
exit 0 that means nothing happened.

Two consequences worth separating:

1. **For this family.** A venue arm that refuses at promotion is the *only* place this can be fixed.
   A remedy that depends on the worker recording its own refusal cannot work in this venue — the
   recording is the part that is broken.
2. **For the ledger, filed not fixed.** `unknown id` exiting 0 makes every caller that trusts the
   exit code blind. Not patched here: `bats` is absent from this VM (`command -v bats` → nothing;
   `bin/cc-bats` wraps a binary that is not installed), and `cc-backlog` is the shared work-ledger,
   so an exit-code change is a fleet-wide blast radius that must be run against the suite, not
   reasoned about. **Why it will still be true:** the rc-0 path is structural, in the store-fold, and
   nothing in the family touches it. **Who it is for:** a local `claude-infrastructure` session with
   the suite.

## 5 · Why this file carries no patch

Same reason as `cloud-venue-foreign-project-2026-08-21.md` §6, and it is stated in the code this
session would be editing. `bin/cc-eligible`'s `OFFBOX_LANE` class exists precisely so that **a
session this lane created cannot verify a change to the lane**, and `bin/cc-venue`'s header states
the guard in its own terms: *"A cloud VM must never build or run the venue rule: it would be
deciding its own admission, and its 50-commit clone cannot read the history that justifies the
exclusions."*

The arm in §3 is a change to the venue rule, written from inside the venue, with no test runner. The
VM does what a VM can do soundly: **measure, and hand the measurement back.**

## 6 · Disposition of the item

`8f59467c92b0` is **not done and not advanced.** R1–R4 are open, correct as filed, and unstarted —
nothing about the plan's content is refuted. What is refuted, for the third time, is that this row
can be worked by the venue it is fired at.

The disposition remains `cc-backlog block`, not `reopen` — but per §4 that verb **cannot be executed
from here**, so it is an operator-owned step on the box that holds the ledger:

```
cc-backlog block 8f59467c92b0 --needs "route this row off the cloud lane: its waves edit \
reso-management-app and doc_classifier, which no cloud VM clones — see \
docs/research/venue-foreign-master-third-fire-2026-08-27.md §3 for the conjunct that convicts it"
```

Until an arm refuses it at promotion, a fourth fire is the default behaviour of the system, not an
accident.

## 7 · A third finding, found by trying to land this file: the land gate cannot go green on Linux

Landing this commit via `scripts/ship-land.sh --dry-run` exits **6 (GATE RED)** — on a lint that is
not in the diff (this commit changes two `.md` files) and cannot be:

```
✗ gate: unattended-path-lint --selftest FAILED — the detector no longer discriminates, so
  its clean verdict would mean nothing. Fix the lint before landing.
✗ ship-land: GATE RED — not pushing.
EXIT=6
```

`scripts/unattended-path-lint.sh --selftest` reports **11 of 42** arms failed, and the failures are
almost all `want 1, got 0` — the detector finds nothing at all. The cause is the platform, not the
tree. The lint's whole subject is the **launchd/macOS stock floor**
(`STOCK_PATH="/usr/bin:/bin:/usr/sbin:/sbin"`), and its fixtures are built out of binaries that
exist only there — its own header block is explicit: *"md5 on macOS exists ONLY at /sbin/md5"*, and
fixture `t14` is literally `before="$(find . | sort | md5)"`. On this VM:

```
md5        ABSENT
plutil     ABSENT
launchctl  ABSENT
sysctl     /usr/sbin/sysctl
lsof       /usr/bin/lsof
```

With no `md5`, no `plutil` and no `launchctl`, every detection arm resolves zero findings, and the
selftest's verdict — *"the detector does not discriminate"* — is **correct as written** and true only
of this platform. There is no Darwin guard on the arm, so it fails closed the same way for any
Linux caller.

**Consequence, and it is the practical one:** the cloud lane cannot land in `claude-infrastructure`
at all. A cloud worker in this repo can commit and push a branch; it cannot complete `/ship`,
because a gate arm that is macOS-only goes red before the diff is ever considered. So the venue's
limits are wider than the `venue-*` family has recorded: alongside *"cannot reach a foreign tree"*
(this file §1) and *"cannot park an item"* (§4) sits **"cannot land in its own"**. All three are the
same shape — a rail whose implementation assumes the operator's box.

Not fixed here, for the same reason as §4 and §5: `bats` is absent, the arm is a fleet-wide gate,
and a platform guard added from inside a venue that cannot run the suite would be exactly the
unverified change the `OFFBOX_LANE` rule exists to prevent. **Why it will still be true:** the arm's
subject is macOS launchd and its fixtures are macOS binaries; nothing in the family touches it.
**Who it is for:** a local `claude-infrastructure` session — either a `uname`-guarded skip with a
loud `n/a` verdict, or a fixture set that does not require the stock floor to be present.
