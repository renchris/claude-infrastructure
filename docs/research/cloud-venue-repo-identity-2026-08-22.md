# The venue gate asks whether the VM can REACH the repo, never whether it CLONES it

**2026-08-22 · written from inside a cloud VM that could not do its assigned work.**
Companion to `cloud-vm-roundtrip-2026-08-10.md` (what the VM is) and
`cloud-vm-shallow-clone-blast-radius-2026-08-11.md` (how deep it sees). This one is about a repo
the VM does not have at all.

Backlog item **`40c7207a96b1`** — a `reso-management-app` perf item (`/floor-plan` pays 2 sequential
DB round trips) — was classified `eligible`, routed to `venue=cloud`, and fired into a Firecracker
microVM whose only `git_repository` source is **`claude-infrastructure`**. The item's repo,
`~/Development/reso-management-app`, does not exist here and cannot be fetched: GitHub reaches this
VM only through MCP tools scoped to the one cloned repository. The work is unreachable by
construction. **One burned worker slot.**

The item was not driven to done. It was not driven anywhere — see § 5.

---

## 1 · The chain, each link measured

**The fire.** This session's branch is `claude/fire-20260822T130616Z-77090-1`. The sole producer of
that shape in the tree is `bin/cc-offload:526`:

```sh
local br; br="claude/fire-$(date -u +%Y%m%dT%H%M%SZ)-$$-$i"
```

(`grep -rn 'claude/fire-' bin/ scripts/` — every other hit is prose *about* such a branch, never a
mint.) So this VM was created by `cc-offload up`.

**The repo the fire carries.** `cc-offload` does not take a repo flag. `:434`:

```
# The create bundles the CALLER'S cwd, not a flag. Chdir so it is always the repo, never a
# transient worktree the operator happens to be sitting in.
```

and `:519-523` derives the slug from that same tree's `origin`:

```sh
remote_url="$(cd "$REPO" 2>/dev/null && git remote get-url origin 2>/dev/null)"
repo_slug="$(printf '%s' "$remote_url" | awk -F'[/:]' 'NF>1{print $(NF-1)"/"$NF}')"
```

**Therefore the VM's single source is always the OFFLOADING repo** — never the item's project repo.
`cc-offload up` refuses a create that does not read back with exactly one `git_repository` source
(`CLOUD_BACKLOG_PIPELINE.md` § 1), so "one" is enforced; *which* one is simply wherever the
dispatcher stood.

**What the gate said.** Run against a faithful fixture of the row — reproducible anywhere:

```sh
printf '%s\n' '{"id":"40c7207a96b1","event":"add","status":"open","project":"reso-management-app","title":"floor-plan: bare /floor-plan pays 2 sequential DB round trips — page.tsx:33 passes neither urlEventID nor hints so initialData.ts:517 speculativeKey is null and the L-3 parallel geometry read is off; /floor-plan/[id] pays 1","source":"perf-audit"}' > /tmp/fx.jsonl
CC_BACKLOG_FILE=/tmp/fx.jsonl cc-eligible why 40c7207a96b1
```

```
verdict : eligible
project : reso-management-app
refused : (nothing fired)
history : no-repo — NOT CERTIFIED: no readable git repo for this project — reach is unknown
          repo=$HOME/Development/reso-management-app ref=- depth=50
```

`check` exits 0. The claim is authorised.

---

## 2 · Why no arm caught it — and why none could

All six `CLASSES` key on the work's **subject**: a spelling that betrays local-only state
(`launchd`, `pane`, `screenshot`, `wt-…`, `github`). This item's subject is impeccably repo-only —
two file paths, a line number, a null variable, a redundant round trip. There is nothing local about
it. **The item is ineligible for a reason that is not a property of the work at all**: it is a
property of the pairing between the work's repo and the VM's repo. No denylist over the item's text
can express a relation to something the text never mentions.

The seventh arm, `deep-history`, *is* a measurement rather than a spelling — and it is the near
miss, because it measures the adjacent quantity:

> `HistoryOracle` (`bin/cc-eligible:488`) — "Can a cloud clone of `<repo>` SEE the commits this
> item cites?"

It asks how *deep* the VM's clone of `<repo>` goes. It never asks whether the VM clones `<repo>`.
The presupposition is baked into `repo_for(project)` (`:613`), which resolves
`~/Development/<project>` — **the path on the laptop**. On the operator's box that directory exists,
so the oracle happily measures a horizon inside a clone the VM will never receive; here it reports
`no-repo` and, per the fail-open rule, **certifies nothing and refuses nothing**.

That fail-open is right in its own terms (§ header: "a classifier that refused on 'I could not tell'
would block the whole cloud tap on a missing file"). It is simply answering a different question
than the one that decides this case. The gate's own asymmetry names the cost of getting it this way
round:

> a wrong ELIGIBLE puts a worker in a VM that CANNOT do the work at all and cannot tell you so — it
> will improvise something plausible against state it cannot see.

Which is the exact failure this VM was one prompt away from committing: the brief's FIRST STEP is
`git -C ~/Development/reso-management-app fetch origin` against a path that is not here.

---

## 3 · This was already written down — as a spelling

`BANKING`'s `wt-slug` entry (`bin/cc-eligible:312-331`, pattern at `:331`) documents the identical
outcome for backlog `4abcbbbbc997`:

> …so it was classified `eligible` and dispatched to a cloud VM — **where the reso-management-app
> repo, the branch, the worktree and the backlog store all do not exist**, so the land it asks for
> is unreachable by construction. One burned worker slot per dispatch.

Same project, same VM, same sentence. The fix applied then was a *spelling* — match `wt-[a-z0-9-]+`,
because that row happened to name its worktree. `40c7207a96b1` names no worktree, no branch and no
sha, and so walks straight past it. The file's own header predicted this precisely:

> A denylist enumerates spellings, never the class it is standing in for.

The class standing behind both rows is **repo identity**, and it wants the same treatment
`deep-history` got: a measurement, appended after the spellings.

---

## 4 · The shape of the fix — and why this session must not apply it

The predicate is one comparison, available at claim time without network:

> the item's `project_repo(project)` `origin` slug ≠ the offload source repo's `origin` slug
> ⇒ **ineligible-foreign-repo**

It composes with what is already there rather than replacing it: `repo_for()` already resolves the
project's tree by `cc-dispatch`'s own convention (so the venue arm and the worktree provisioner
"can never disagree about which tree an item's project means"), and the offload source is the
dispatcher's repo. Note it is strictly **stronger** than the history arm and should run before it —
an unclonable repo has no horizon to measure, so today's `no-repo` fail-open is the branch that
actually fires on every foreign-repo row.

Two properties worth keeping if someone builds it:

- **It is a measurement, so it belongs after the spelling classes**, like `DEEP_HISTORY`, and it
  should report its own uncertainty token when either slug is unreadable (fail-open on *reading*,
  refuse on a *read* mismatch — the file's existing asymmetry, unchanged).
- **The cost of a wrong INELIGIBLE stays cheap**: the row remains exactly where it is, claimable
  locally. `reso-management-app` is a dispatchable local project
  (`scripts/dispatch-projects.conf:49`), so refusing it off-box strands nothing — it routes it.

**🚨 This session did not write that patch, deliberately.** `cc-eligible`'s *first* refusal class is
`ineligible-offbox-lane` (`bin/cc-eligible:212-238`), and its comment at `:229` names this exact
attempt:

> `venue` is in the list for the sharpest case of all: **it would refuse an item asking to edit THIS
> FILE.** … A SESSION THIS LANE CREATED CANNOT VERIFY A CHANGE TO THE LANE. … It is not a statement
> about difficulty; it is that the observer and the subject are the same object.

A cloud VM patching the gate that admitted it is the circularity the class exists to forbid, and the
gate cannot be verified from inside a session it produced. **The patch is local-box work.** This
document is the report; it changes no behaviour and asserts no verification, which is the same
standing the two prior `cloud-vm-*` research docs have.

---

## 5 · Ledger state — NOT transitioned, and it could not be

`40c7207a96b1` is still `claimed` by this session. It was **not** marked done, blocked or reopened,
because none of those verbs can reach the store from here:

```
$ cc-backlog list --open
(empty — rc 0)
$ ls ~/.claude/autonomy/backlog.jsonl
No such file or directory
```

`CLOUD_BACKLOG_PIPELINE.md` § 3 states the rule this obeys: "`~/.claude` does not exist there …
the backlog store is machine-local. **Claim locally BEFORE firing; the VM commits and pushes, the
laptop lands and marks done.**" A `cc-backlog` write here would have minted a *fresh* JSONL in a
container that is reclaimed at session end — a transition recorded nowhere, which is worse than no
transition at all, because the item would read as handled.

So the two transitions this event needs are **local-box actions**, and neither is `done`:

| row | verb | why |
|---|---|---|
| `40c7207a96b1` | `cc-venue … --venue local --why "foreign-repo: reso repo is not the VM's one clone"` then release the claim | Ordinary local work. Not operator-gated — do **not** `block` it; nothing here needs a human, only a venue. |
| *(new)* | `cc-backlog add --project claude-infrastructure --title "cc-eligible: refuse an item whose project repo is not the offload source repo (venue=cloud) — 40c7207a96b1 was fired into a VM without its repo"` | The § 4 patch. Local-only by its own `ineligible-offbox-lane` rule. |

---

## 6 · The generalisable bit

The census in `CLOUD_BACKLOG_PIPELINE.md` § (class table) buckets every refusal by what the *work*
needs — a browser, a window server, this box's `~/.claude`, deep history. Every one is a predicate
over one object. This case is the first that is a predicate over a **pair**: the work is fine, the
venue is fine, and only the *match* between them fails. A gate built entirely from one-object
predicates has no place to put that, which is why it read `eligible` with `(nothing fired)` — not a
missed spelling, a missing arity.
