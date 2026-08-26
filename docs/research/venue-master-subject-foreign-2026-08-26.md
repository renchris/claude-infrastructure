# The cross-repo arm landed, is healthy, and still admits the row it was predicted to miss

**Filed 2026-08-26, from the cloud VM that received the dispatch.** Sixth in the `venue-*` family
and the **third fire of one row** — `8f59467c92b0`, *"advance MASTER: product repos"*, project
`claude-infrastructure`, whose every wave edits `reso-management-app` or `doc_classifier`.

Prior occurrences: 2026-08-15 (`venue-foreign-subject-repo-2026-08-15.md`) and 2026-08-17
(`venue-foreign-master-redispatch-2026-08-17.md`). Both are recorded in
`docs/plans/MASTER_PRODUCT_REPOS.md` § Status log. **Nothing in R1–R4 was touched, again, because
nothing in R1–R4 was reachable, again.**

What is refuted is the **venue**, never the plan. R1–R4 are open, correct as filed, and unstarted.

---

## 1 · What this fire measured that the first two could not

On 08-17 the remedies were hypothetical and the prediction was that all of them would pass this
row. Since then `ineligible-cross-repo` has **landed** (`bin/cc-eligible`, 2026-08-23, measured
over 133 cloud sessions: 106 on a repo the VM was never given). So the prediction is now checkable
against shipped code rather than against a proposal. It checks out.

### 1a · The landed arm is healthy and still admits this row — both directions, one command

```sh
SP=$(mktemp -d); mkdir -p "$SP/Development"
for p in claude-infrastructure reso-management-app; do
  git init -q "$SP/Development/$p"
  git -C "$SP/Development/$p" remote add origin "https://github.com/renchris/$p.git"
  git -C "$SP/Development/$p" commit -q --allow-empty -m seed
done
cat > "$SP/backlog.jsonl" <<'EOF'
{"ts":"2026-08-12T00:00:00Z","id":"8f59467c92b0","op":"add","project":"claude-infrastructure","title":"advance MASTER: product repos — the operator's actual products, one wave per repo","dodRef":"/Users/chrisren/Development/claude-infrastructure/docs/plans/MASTER_PRODUCT_REPOS.md","condition":"master-product-repos"}
{"ts":"2026-08-12T00:00:00Z","id":"b0be87487228","op":"add","project":"reso-management-app","title":"--bs-cap under-reserves the caption","dodRef":"","condition":"master-product-repos"}
EOF
HOME="$SP" CC_BACKLOG_FILE="$SP/backlog.jsonl" \
  CC_ELIGIBLE_CLOUD_REPO="$SP/Development/claude-infrastructure" \
  bin/cc-eligible check 8f59467c92b0   # → verdict=eligible              exit 0
HOME="$SP" CC_BACKLOG_FILE="$SP/backlog.jsonl" \
  CC_ELIGIBLE_CLOUD_REPO="$SP/Development/claude-infrastructure" \
  bin/cc-eligible check b0be87487228   # → verdict=ineligible-cross-repo exit 3
```

| Row | `project` | Work lives in | Verdict | Exit |
|---|---|---|---|---|
| `b0be87487228` — **control** | `reso-management-app` | reso | `ineligible-cross-repo` | **3** |
| `8f59467c92b0` — **this item** | `claude-infrastructure` | reso + doc_classifier | `eligible` | **0** |

The control is the load-bearing half: it proves the `eligible` above is **not** an arm that is
broken or disabled. The arm measures, convicts, and exits 3 on a label-foreign row — and then
admits this one, because `cross_repo(project)` (`bin/cc-eligible:766`) is a function of the
**project label alone**, and this row's label is *correct*. `~/Development/claude-infrastructure`
resolves to the lane, so `elsewhere` is False and nothing fires. `why` prints `refused : (nothing
fired)`.

This is the **subject-foreign** residual named in `venue-foreign-subject-repo-2026-08-15.md` § "The
discriminator that would catch both", whose 🚨 block predicted exactly this outcome and asked for
the discriminator to be **restored as a conjunct**. It was not. The 08-23 arm closes the
label-foreign class — 106 of 133 sessions, by far the larger one — and leaves this class open.

Question 1b (`ineligible-dod-offtrunk`, `bin/cc-venue`) does not reach it either, and correctly so:
this row's `dodRef` **is** on trunk. Every arm answers truthfully; no arm asks the question.

### 1b · `cc-backlog block` fails SILENTLY from a VM — rc **0**, not rc 1

The 08-17 entry warned *"the rails fail at rc 0 from a VM, so verify the block took rather than
assuming it."* Confirmed directly this fire:

```
$ bin/cc-backlog block 8f59467c92b0 --needs "…"
cc-backlog block: unknown id 8f59467c92b0
$ echo $?
0
```

`~/.claude/autonomy/backlog.jsonl` does not exist on this VM, so every id is unknown. **A caller
that checks `$?` is told the block succeeded.** This is why three fires have produced three
disproofs and zero parked rows: the dispatch rails' own escape hatch is a no-op here, and it does
not say so in its exit code. Any future worker following the standard rails from a cloud VM will
believe it parked the item.

### 1c · The prose disproof bought 9 days, not 0

08-15 → 08-17 was 2 days. 08-17 → 08-26 is **9**. The 08-17 finding — *"a disproof in plan prose
does not park an item — nothing in the dispatch chain reads it"* — stands, and the interval is the
measurement of how much a `docs/` write buys: real, bounded, and not a park.

---

## 2 · Why the remedy was not built here — two independent blockers, both measured

**(a) `bin/cc-venue`'s header forbids it, and the rationale is literally true of this VM.**

> 🚨 THE GUARD … A cloud VM must never build or run the venue rule: it would be deciding its own
> admission, and its 50-commit clone cannot read the history that justifies the exclusions.

Measured here: `git rev-parse --is-shallow-repository` → `true`; `git rev-list --count HEAD` → **50**;
`.git/shallow` present. Not an analogous situation — the exact one the guard names.

**(b) The gate cannot be run on a rails change.** `bats` → ABSENT, `shellcheck` → ABSENT (`jq` and
`python3` are present). The rails require gate-green before commit. Landing an ungated guard into
the fire path — where a wrong refusal starves the cloud tap — trades a bounded waste for an
unbounded one. This is the same call `cloud-venue-project-repo-mismatch-2026-08-16.md` § 3 made,
for the same reason, from the same tooling shape.

The four-mechanism option list in `MASTER_PRODUCT_REPOS.md` § Status log (08-15) is also unreachable
from here on its own terms: the plan index is `~/.claude/plans-index.json`, absent on this VM.

---

## 3 · What the desk needs to do

**Park the row.** It is blocked on *where it is sent*, not on information — so `block`, not
`reopen`; `reopen` re-cycles it into the wave and buys a fourth fire.

```sh
cc-backlog block 8f59467c92b0 --needs "route this row away from --venue cloud: its waves edit reso-management-app and doc_classifier, neither of which a cloud VM receives"
cc-backlog list --all --json | jq -r '.[]|select(.id=="8f59467c92b0")|.status'   # must read: blocked
```

The second line is not ceremony — per § 1b the first line exits 0 whether or not it did anything.

**Then resolve the residual**, which is now a *smaller and sharper* decision than the one filed on
08-16, because the label-foreign majority is already closed by the landed arm. What remains is one
conjunct: **an item is subject-foreign when its text or its `dodRef` plan body names a
`scripts/dispatch-projects.conf` project other than its own `project`.** Both inputs are already on
the row; it needs no new store. The standing caveats from 08-15 still apply — a genuine cross-repo
claude-infrastructure item (a census, a fleet sweep) names every project by construction and would
be refused, which is the safe direction: a wrong INELIGIBLE leaves the item claimable locally, a
wrong ELIGIBLE burns a slot and invites a confident answer about invisible state.

Placement is the open half and is a desk call: `bin/cc-offload` at the fire (08-16 § 2–3), or
`bin/cc-eligible` beside `cross_repo` as a second reach arm. Whichever is chosen must be gated on a
box that has `bats` and `shellcheck`.

**A note on `MASTER_PRODUCT_REPOS.md` itself.** Its own Phase 0 says *"The master row is a
coordination header, not a unit of work; advancing it means advancing members."* If that is right,
the row should not be dispatchable to **any** venue, cloud or local — which is the fourth mechanism
on the 08-15 list (a not-dispatchable plan declaration) and the only one of the four that a
two-tree master can express, since the other three carry a single project value.

---

## 4 · This file is the notification

Per `venue-foreign-subject-repo-2026-08-15.md`: a cloud VM's only durable channel to the desk is the
branch it pushes. The ledger transition could not be written from here (§ 1b), and — measured this
fire — could not have been *detected* as unwritten by a caller reading the exit code.
