# The cross-repo arm SHIPPED, it works, and `8f59467c92b0` is the case it cannot reach

**2026-08-26 · written from inside a cloud VM fired at the product-repos master, branch
`claude/fire-20260826T222644Z-28984-1`.** Fourth recorded dispatch of this row (08-15, 08-17, and
this one; `b0be87487228` on 08-20 is the member-row twin). The three earlier writeups
(`venue-foreign-master-redispatch-2026-08-17.md`, `cloud-venue-project-repo-mismatch-2026-08-16.md`
§3, `tenant-drift-venue-refusal-2026-08-24.md`) established the class. This one adds the single
fact none of them could have: **the remedy has since landed, it demonstrably closes the member
rows, and it structurally cannot close this master row.** The 08-17 entry predicted that. It is now
measured.

## 1 · The venue, re-measured

Unchanged from `cloud-vm-reachability-2026-08-23.md`:

```
pwd                          → /home/user/claude-infrastructure
ls ~/Development             → No such file or directory
ls -d ~/Development/reso-management-app ~/Development/doc_classifier → both absent
GitHub MCP scope             → renchris/claude-infrastructure only
command -v cc-backlog        → (nothing)
ls ~/.claude/autonomy/       → No such file or directory
```

Every open wave in the plan (R1-R3 `reso-management-app`, R4 `doc_classifier`) edits a tree that is
not here and cannot be fetched. The ledger this item must be closed in is likewise absent, so the
item cannot even record its own transition — the same dead end `b0be87487228` hit on 08-20.

## 2 · The arm shipped, and it is not a no-op

`bin/cc-eligible` now carries `CROSS_REPO = "ineligible-cross-repo"` (:430), the classifier row
(:436), `BLOCKING` membership (:442), `cross_repo()` (:766) and its call site in `assess_full()`
(:857-862). This is option (a) *fail closed* from `cloud-venue-project-repo-mismatch-2026-08-16.md`
§3, landed since that doc was written.

Executed against a faithful reproduction of the operator-box geometry — three git repos under a
fixture `~/Development` with their real origins, `CC_ELIGIBLE_CLOUD_REPO` set to the
`claude-infrastructure` lane, calling the shipped predicate unmodified:

```
lane (the ONE repo the cloud VM is given): <fixture>/Development/claude-infrastructure

  cross_repo('claude-infrastructure')  -> unreachable=False  PASSES the arm -> eligible
  cross_repo('reso-management-app')    -> unreachable=True   REFUSED (ineligible-cross-repo)
       why: project 'reso-management-app' is renchris/reso-management-app;
            the VM is given only renchris/claude-infrastructure
  cross_repo('doc_classifier')         -> unreachable=True   REFUSED (ineligible-cross-repo)
       why: project 'doc_classifier' is renchris/doc_classifier;
            the VM is given only renchris/claude-infrastructure
```

**The arm works.** The 08-20 CORRECTION in this plan's Phase 0 — *"a correctly-projected member row
misroutes too"* — is now stale: `b0be87487228` (project `reso-management-app`) would today be
refused before it could burn a slot. That paragraph should be read as history, not as current
behaviour.

## 3 · Why this row is the residual, by construction

`cross_repo()` returns at :781-782 for this item, and the path is deterministic rather than
measured:

| step | value for `8f59467c92b0` |
|---|---|
| `cloud_repo()` → `_lane_from_self()` (:757) | `~/Development/claude-infrastructure` |
| item's `project` (from `find-plan.sh:70 project_name_for()`, path basename) | `claude-infrastructure` |
| `repo_for(project)` (:790) → `~/Development/<project>` | `~/Development/claude-infrastructure` |
| `realpath(item_repo) == realpath(lane)` | **True** → `return False, ""` |

The arm keys on `item.project`, and this item's project label is **correct** — the plan file really
does live in `claude-infrastructure/docs/plans/`. The foreign trees appear only in the plan BODY,
which nothing in the chain reads. So the predicate is not wrong; it is answering a question about
the label while the work lives somewhere the label never mentions.

This is the same residual `tenant-drift-venue-refusal-2026-08-24.md` §1 names — *filed under X,
specified against Y* — and it is why widening the spelling list (`classify_all()`, :445, pure regex
over `title · dodRef · condition · source`) cannot help either: a repo name is not a spelling of
local-only state, and this row's span fields name no foreign tree.

## 4 · What this changes about the filed remedy

The open decision keyed on (`item.project`, `session.attached_repo`) is **now landed and now
sufficient for the member rows** — that is new, and it retires most of the class. What remains is
exactly the 08-17 prediction, confirmed: the master row needs a **subject** discriminator (the plan
body's target trees), not a project one, or the ~0-cost data entry the 08-17 entry identified —
`scripts/find-plan.sh:73` already prefers `.plans[$k].projectName` over the path basename, so
setting this plan's `projectName` to a foreign project composes with the shipped fail-closed arm and
parks this row specifically.

**Neither is done here, by rule.** `bin/cc-venue:55-56` — *a cloud VM must never build or run the
venue rule: it would be deciding its own admission, and its 50-commit clone cannot read the history
that justifies it.* §2 above characterises the shipped predicate in a throwaway fixture; it changes
no predicate and decides no admission (this VM's admission was already settled by `ls ~/Development`
in §1). The plan index is runtime state under `~/.claude/`, absent here and C10-protected besides.

## 5 · Premise check

**NOT refuted, and untouched.** R1-R4 are all still open, still correct as filed, and still
unstarted — nothing readable from this venue contradicts any claim in them, and nothing in them was
attempted, because nothing in them was reachable. What is refuted is only the venue's ability to
work this row, which is the same disproof the 08-15 and 08-17 entries wrote. The plan's frontmatter
`status: open` is accurate.

**Disposition: `cc-backlog block`, not `reopen`** — unchanged from 08-17, and still unrunnable from
here (§1). It is an operator step.
