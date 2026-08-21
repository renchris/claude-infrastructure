# The cloud venue gate never asks which REPO an item is for

**Date:** 2026-08-21 · **Measured on:** a cloud VM clone of `renchris/claude-infrastructure`,
branch `claude/fire-20260821T064958Z-19839-1`, HEAD `cad3b59e`. Written from inside the VM, in the
posture of `cloud-vm-roundtrip-2026-08-10.md` and `cloud-vm-shallow-clone-blast-radius-2026-08-11.md`.

**Finding, in one line:** `cc-eligible` classifies an item's *words* and never its *project*, so an
item whose repo the cloud VM cannot clone is admitted to `--venue cloud` — measured end-to-end
through `cc-backlog claim`, exit 0 — and the worker arrives in a VM where the repo, the file it was
sent to edit, the evidence it was sent to read, and the backlog store it was sent to close all do
not exist.

This is a **false `eligible`**, which `CLOUD_BACKLOG_PIPELINE.md` §A2b names as the direction that is
*"silent by construction"*. That section measured the six refusal classes exhaustively; nothing has
measured the admissions. This is one.

---

## 1 · How it was found

This session was dispatched into a cloud VM to drive backlog item `0dafb03ed73d` — *"Amplify build
cache never WRITTEN since ~2026-06-12 … Fix `cache.paths` in `amplify.yml`"* — whose project is
**`reso-management-app`** and whose brief names `/Users/chrisren/Development/reso-management-app`.

What the VM actually holds:

```
$ ls -d /Users/chrisren/Development/reso-management-app   → No such file or directory
$ find / -name backlog.jsonl                              → (nothing)
GitHub MCP scope                                          → renchris/claude-infrastructure only
```

The repo is absent, `~/.claude/autonomy/backlog.jsonl` is absent, and GitHub reaches this VM scoped
to the one cloned repository (§3). Every step of the brief — read `amplify.yml` on trunk, check the
cited sha against `origin/main`, edit `cache.paths`, `cc-backlog done` — is unreachable **by
construction**, not by difficulty.

## 2 · Reproduction — the gate admits it, and the same project is refused on a spelling

Both runs use a fixture `$HOME` and a fixture store; both carry the **same** `--project
reso-management-app`. The only difference is the words in the title.

```
$ cc-backlog add --title "Fix cache.paths in amplify.yml — Amplify build cache never written since 2026-06-12" \
      --project reso-management-app --source docs/research/DEP_AUDIT_2026-08-11/b2-turbopack-build-cache.md
89de95c75cd2
$ cc-backlog claim 89de95c75cd2 --by test-sid --venue cloud
89de95c75cd2
claim exit=0                                  ← ADMITTED to a VM that has no such repo

$ cc-backlog add --title "reload the launchd plist for the dispatcher" \
      --project reso-management-app --source ctl
1b524f189d04
$ cc-backlog claim 1b524f189d04 --by test-sid2 --venue cloud
cc-backlog claim: REFUSED verdict=cloud-ineligible — 1b524f189d04
  verdict=ineligible-box   named: launchd, plist
claim exit=4
```

Directly against the predicate, on the real item's own text:

```
$ cc-eligible why 0dafb03ed73d
  verdict : eligible
  project : reso-management-app
  refused : (nothing fired)
  history : no-repo — NOT CERTIFIED: no readable git repo for this project — reach is unknown
            repo=/root/Development/reso-management-app ref=- depth=50
```

**The project field is read, printed, and never consulted.** A `reso-management-app` item is refused
when it happens to say `launchd` and admitted when it happens not to.

## 3 · Why — the code path

`bin/cc-eligible` refuses on two kinds of evidence and neither is repo identity:

| arm | keyed on | what it can see |
|---|---|---|
| `CLASSES` (6 spelling classes) | regexes over `title`+`dodRef`+`condition`+`source` | words |
| `DEEP_HISTORY` (measured) | `HistoryOracle` over `repo_for(project)` | whether a *cited sha* is inside the 50-commit horizon |

`project` enters at exactly one place — `repo_for(project)` → `$HOME/Development/<project>` — and its
only use is to pick the tree the **history** arm measures against. It is never asked the prior
question: *is that tree one the cloud VM can clone at all?*

`bin/cc-venue:decide()` inherits the hole. Its ladder is: unknown-item → spelling classes → history
`state != ok` → premise → **`cloud`**. On the operator's box `~/Development/reso-management-app` is a
full clone, so the history arm certifies `ok` and the item falls through to `venue = cloud` — and
the *better* the local clone, the more confidently it promotes.

The VM here is the degenerate case that makes the hole legible: `repo=/root/Development/…` does not
exist, the history arm reports `no-repo` — and `no-repo` is fail-open for the gate (correctly: an
instrument outage must not starve the tap), so the claim is still granted.

## 4 · This is a structural property, and it has already been patched once as a spelling

`bin/cc-eligible`'s `BANKING` list carries this comment, added 2026-08-11:

> Backlog `4abcbbbbc997` … names its worktree ONLY as `wt-bsm-gap` … and so was classified
> `eligible` and dispatched to a cloud VM — **where the reso-management-app repo, the branch, the
> worktree and the backlog store all do not exist**, so the land it asks for is unreachable by
> construction. One burned worker slot per dispatch.

Same project, same VM, same words describing the same outcome. The remedy applied then was a new
spelling (`wt-slug`), which catches items that happen to *mention* a worktree directory. `0dafb03ed73d`
mentions none, and was admitted — which is this file's own founding law turned on itself:
**a denylist enumerates spellings, never the class it stands in for.** The class here is not a word.
It is *"this item's repo is not the repo the lane clones"*, and it is decidable from a field the
ledger already carries.

Scale of the exposed population, from `scripts/dispatch-projects.conf`: **two of the three
dispatchable projects — `doc_classifier` and `reso-management-app` — are unreachable off-box**, and
every one of their open items is cloud-eligible unless a spelling happens to fire. §A2b's own table
records the accident: *"the 7 reso rows need Turso creds the VM has no channel for"* — filed under
`ineligible-visual`, i.e. refused for the wrong reason, by a spelling collision.

## 5 · The fix, specified — for a LOCAL session

A third **measured** arm alongside `DEEP_HISTORY`, minted in `assess_full()` rather than added to
`CLASSES` (which is the pure spelling table):

- `CLOUD_PROJECTS` — the set of projects the cloud lane's `git_repository` source actually wires,
  env-overridable (`CC_CLOUD_PROJECTS`), default `{"claude-infrastructure"}`. A set, not a constant,
  because a second lane for another repo is a configuration change, not a code change.
- Verdict token `ineligible-foreign-project`; added to `BLOCKING` and to `SWEEP_ROWS` so the census
  can never render a class the gate enforces.
- **Fail-open on unknown:** a projectless item (`project == ""`) is *not* refused by this arm — that
  is a failure to read, and this file's founding rule sends every such case to exit 0. It is already
  routed `local` by `decide()`'s `history state != ok` guard.
- **Refusal order: FIRST**, ahead of the two self-referential classes. Their precedence rationale —
  *"the only entries whose wrong answer is not confined to the item"* — is unaffected in practice,
  because lane and spawn-rail files live in `claude-infrastructure` and so never carry a foreign
  project. Where the two *do* collide it is a spelling collision (§A2b measured `venue` matching a
  reso feature literally named `provision-venue`), and there the structural reason is the true one.
  This arm is the only class in the file that cannot be a false positive.

**Blast radius on the suite — measured, and it is the reason this must be done where bats runs.**
Project labels in the bats suites are fixtures, not projects — the `add()` helper in
`tests/cc-eligible.bats` hardcodes `--project probe`, and across `tests/*.bats` the literal labels
run 88 × `/r`, 43 × `proj`, 21 × `p`, against 10 × `claude-infrastructure`. Under the arm as
specified, **every
"must stay eligible" control in those suites flips to refused**: 7 files, 133 tests, ~29 assertions
that name `eligible`/`cloud`. That breakage is loud, not silent, and the fix is one `export
CC_CLOUD_PROJECTS=…` per `setup()` — but it must be *run*, and `bats` is not installed in the VM
(`command -v bats` → nothing; `bin/cc-bats` is a wrapper around a binary that is not there).

## 6 · Why this document does not carry the patch

`bin/cc-eligible` is the subject of its own `OFFBOX_LANE` class:

> `venue` is in the list for the sharpest case of all: **it would refuse an item asking to edit THIS
> FILE** … A SESSION THIS LANE CREATED CANNOT VERIFY A CHANGE TO THE LANE … it is not a statement
> about difficulty; it is that the observer and the subject are the same object.

This session was created by that lane. A patch to the admission predicate written here would be
verified — if at all — by the very mechanism it governs, with no suite to run it against. So the VM
does what a VM can do soundly: **measure, and hand the measurement back.** The implementation is a
local session's work.

Filed as such rather than as a fix: this is `cc-eligible`'s own instruction, one level up. The file
says a wrong spelling should be corrected *in the list* rather than forced past; the same logic says
a wrong *class* should be corrected in the classifier rather than worked around at the item level —
and neither can be judged from inside the lane.

## 7 · The stranded item

`0dafb03ed73d` is untouched and undiagnosed: nothing in this VM could read `amplify.yml`, the cited
evidence doc, or `origin/main` of `reso-management-app`, so no claim about the cache-paths fix —
including whether the cure is already on trunk — was possible here. It is ordinary local work and
loses nothing by being claimed on the box.

Laptop-side, once the arm above lands, this item and its class stop reaching the cloud lane at all.
