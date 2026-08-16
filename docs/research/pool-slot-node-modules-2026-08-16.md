# Pool slots 6/7/8 lost `node_modules` while `styled-system` survived — what a cloud VM can and cannot settle

**Backlog item:** `1d25b0e07668` (project `reso-management-app`) — *"refresher now self-heals it, cause
still unidentified"*. **Status after this pass: still open, and deliberately so.**

**Verdict, first.** The item cannot be diagnosed from here, and the reason is structural rather than
effortful: every artifact that could name the culprit lives on the operator's Mac, and this session is
a cloud VM whose single source is `renchris/claude-infrastructure`. What this pass *can* do — and
does below — is cut the cause space from "unidentified" to **three falsifiable hypotheses, ranked,
each with the one local command that discriminates it**, plus a hard exclusion list so the local
successor does not re-walk ground that is already closed.

---

## 1 · Where this was written from, and why that bounds every line of it

| fact | measured |
|---|---|
| venue | Firecracker cloud VM, `/home/user`, no `~/Development`, no `~/.claude` |
| clone | `git rev-parse --is-shallow-repository` → `true`; `git rev-list --count HEAD` → **50** |
| sources | exactly one — `renchris/claude-infrastructure`; GitHub tool scope names that repo and only it |
| the item's repo | `~/Development/reso-management-app` (`scripts/dispatch-projects.conf:49`) — **absent, and out of scope to fetch** |

So the brief's mandated FIRST STEP — *read what the item cites on reso's trunk* — was **unexecutable**,
not skipped. Nothing below was derived against reso's tree. Treating any of it as a diagnosis would be
exactly the failure `docs/plans/CLOUD_BACKLOG_PIPELINE.md` §5 names as the anti-goal: *"a plausible-looking
wrong answer against missing history"*.

---

## 2 · Settled from this repo (do not re-derive)

- **The refresher is reso's, and has never existed here.** `scripts/worktree-pool.sh` — `cmd_claim` /
  `refresh_slot` / `ensure` — is `~/Development/reso-management-app/scripts/worktree-pool.sh`, with the
  self-updating installed copy at `~/.reso/bin/worktree-pool.sh`. `git log --all -- scripts/worktree-pool.sh`
  in this repo is empty (`docs/plans/GROUND_UP_REBUILD_MAP.md:59`).
- **This repo holds only callers**: `lib/claude-launcher.zsh:239-248` (resolution order), `hooks/worktree-setup.sh:154-170`
  (claim + ownership gate), `scripts/handoff-fire.sh:7576-7640` (eligibility, ownership, claim, freshness).
- **Its reverse-engineered composition** is recorded at `docs/research/R3-shell-latency.md:45-53`:
  `git status --porcelain` → `db-ensure.sh` → `git reset --hard origin/main` (stale only) →
  `pnpm install --frozen-lockfile` → `prepare-cached.sh` (styled-system codegen, stale only), plus
  `git checkout -- .` (`docs/research/eslint-cache-cross-worktree-2026-08-07.md:103`).

**Excluded, with the reason:**

| candidate | why it is not the mechanism |
|---|---|
| this repo's `scripts/worktree-gc.sh` | it enumerates from the **infra** repo's `git worktree list`, which contains no `wt-pool-*` entry — the reso pool is structurally invisible to it (`docs/plans/WORKTREE_MANAGEMENT_V2.md:701-705`; zero `pool` matches in the script) |
| any `git clean` | the only shape this repo runs is `git clean -fd`, **never `-x`** (`scripts/postland-verify.sh:11`), and without `-x` it does not touch gitignored `node_modules` |
| `git reset --hard` / `git checkout -- .` in `refresh_slot` | neither removes an ignored directory |
| pnpm store pruning | no `pnpm store prune` exists anywhere in this repo; the 11 s `--offline` claim cost is local verify/relink (`docs/research/R3-shell-latency.md:102-105`) |

---

## 3 · The three hypotheses that survive, ranked

### H1 — an agent deleted it, and the allowlist let it through silently

This is the only candidate that **predicts the asymmetry rather than tolerating it**:

- `hooks/rm-safe-allowlist.sh:68` — `SAFE_NAMES='node_modules .next … .terraform'`. `node_modules` is the
  first entry; **`styled-system` is not on the list**. The hook returns `permissionDecision: allow` with no
  operator prompt (`:110-160`), and `hooks/tests/validate-bash.test.sh:184` pins that allow as a regression
  test. `hooks/validate-bash.sh:776` carries the same asymmetry in its warn layer.
- So `rm -rf node_modules` runs unattended and `rm -rf styled-system` does not — which is the observed
  end state, exactly.
- **The consequence is then invisible**: `hooks/task-quality-gate.sh:309` skips typecheck entirely when
  `node_modules` is absent, so a slot in this state passes its completion gate rather than failing it.
- **Aggravator, documented in this repo**: `scripts/handoff-fire.sh:6374-6379` records that `$REPO` was
  hardcoded to reso, so *every* `--worktree` fire from another repo silently targeted it — observed
  2026-07-24, a claude-infrastructure peer landed in **reso's `wt-pool-2`**. A session that believes it is
  in a different codebase is precisely the session that clears `node_modules` to "fix" an install.

**Discriminator (local):** search the fleet transcripts and the hook logs for an `rm` of `node_modules`
whose cwd is `wt-pool-6|7|8`.

### H2 — an interrupted `pnpm install --frozen-lockfile` inside `refresh_slot`

pnpm removes the previous tree before it relinks. A kill mid-install — session end, machine sleep, or the
box's documented memory pressure — leaves `node_modules` gone and `styled-system` intact, because the
codegen is a **separate, later, sha-cached step** (`prepare-cached.sh`) that the interrupted run never
reached and never had reason to touch. **Three *adjacent* slots is the signature**: the background `ensure`
replenisher walks slots in order, so 6/7/8 is what one sweep dying partway through looks like — where H1
would have to be three independent sessions that happened to pick consecutive slots.

**Discriminator (local):** `~/.reso/worktree-pool.log` — were 6, 7, 8 consecutive in a single `ensure`
sweep, and does that sweep end without its matching completion line?

### H3 — served, never re-provisioned (the *persistence* half, not the deletion)

reso `1211088d7` (2026-08-12) made the claim path provision nothing: *"`cmd_claim` provisions NOTHING —
no `fetch_guarded`, no `refresh_slot`, no unconditional db-ensure … Residual gates: db-ensure only when
`sqlite.db` is absent, `.env.local` copy only when missing"* (`docs/research/R3-shell-latency.md:214-218`).
**There is no `[ -d node_modules ]` residual gate in that list**, so a slot missing its deps is handed to a
session as-is and stays broken until `ensure` independently judges it stale.

H3 explains why the hole *persisted and was met by three sessions*; it does not explain the original
deletion. Note the item's own words — *"refresher now self-heals it"* — most likely name precisely the
`node_modules` gate that `1211088d7` dropped. **If the self-heal on reso's trunk is that gate, H3 is
confirmed as the persistence half and the deletion half is still H1 vs H2.**

---

## 4 · The one next step

This item is **local-only work**, and should be re-dispatched as such rather than re-attempted off-box:

```
cc-backlog reopen 1d25b0e07668 && cc-backlog venue 1d25b0e07668 --venue local \
  --why "off-box-blind: the deciding evidence (reso scripts/worktree-pool.sh, ~/.reso/worktree-pool.log, fleet transcripts) is not in the VM's single claude-infrastructure source"
```

The local successor's first three reads, in order: reso trunk's `refresh_slot`/`cmd_claim` (does the
self-heal gate on `node_modules`? → settles H3), `~/.reso/worktree-pool.log` (→ H2), the transcript sweep
for auto-allowed `rm -rf node_modules` (→ H1).

---

## 5 · Routing note (why this reached a cloud VM at all)

`bin/cc-eligible` classifies an item by **spelling** and by **history reach**. Neither arm compares the
item's *project repo* against the single `git_repository` source the VM is actually provisioned with, so
a `reso-management-app` item reads eligible and is fired into a `claude-infrastructure` VM that cannot see
one line of the code in question. `CLOUD_BACKLOG_PIPELINE.md` §5 already names this class as worse than
leaving an item unrouted. Recorded here as an observation for the venue producer's own backlog — **not
fixed in this pass**, which would be a fleet-rail change on a different item, made from the one venue that
cannot test it.
