# R7 — Landing Ground Map: `claude-infrastructure`

Research date **2026-08-11**. Every claim below cites the command or `file:line` that produced it.
Policy/workflow files were read from `origin/main` blobs, not the working tree.

---

## 0. TL;DR for the implementer

| Question | Answer |
|---|---|
| Repo | `/Users/chrisren/Development/claude-infrastructure` (`readlink -f ~/.claude/bin/claude-accounts`) |
| Remote | `https://github.com/renchris/claude-infrastructure.git` |
| Trunk | `origin/main`. Local `main` was **2 commits behind** at research time (`git rev-list --count HEAD..origin/main` = 2) |
| Landing cost | **FREE and pre-authorized.** No `CLAUDE.md` in this repo says landing spends money; `.claude/CLAUDE.md` grants *standing-land*. Land via project-local `/ship`, never `git push` |
| Live layer | Per-file symlinks `~/.claude/**` → repo, **plus three COPY surfaces** |
| Converger | `bash ~/Development/claude-infrastructure/scripts/deploy-live.sh` (launchd `com.claude.deploy-live`, `StartInterval` 600) |
| Migration | New wiring = `migrations/0011-<slug>.sh`, class `c10` (settings.json / zshrc / plists are C10) |
| **The trap** | `.claude-next` (account 1, the default) is **NOT** sharing the knowledge layer: it has its own real `hooks/` (53 files vs 75) and its own real `statusline.sh`. Five wired hooks are missing there *today* |

---

## 1. Repo + deployment model

### 1.1 Identity

```
$ readlink -f ~/.claude/bin/claude-accounts
/Users/chrisren/Development/claude-infrastructure/bin/claude-accounts
$ readlink -f ~/.claude/lib/claude-launcher.zsh
/Users/chrisren/Development/claude-infrastructure/lib/claude-launcher.zsh
```

Branch at research time: `main`, clean-ish (one deleted doc + untracked backlog JSON). **Do not commit in the
shared checkout** — `.claude/CLAUDE.md` § "Never commit or land in the shared checkout" records incident
2026-07-11 where commit `dfacccd` (5 new files) was silently rebase-dropped by a sibling `/ship`, and
`git rev-list origin/main..HEAD` read **0** while the files were absent from main. **Work in a dedicated
worktree on your own branch.**

### 1.2 How a change reaches the live layer — FOUR classes, not one

`install.sh` is the only thing that creates the live links. `deploy-live.sh` is the only sanctioned advance.

| Change class | Live mechanism | What makes it live | Cite |
|---|---|---|---|
| **EDIT to an already-linked file** (`hooks/*.sh`, `scripts/*.sh`, `bin/cc-*`, `commands/*.md`, `agents/*.md`, `lib/*.zsh`, `skills/*/*`) | per-file symlink → repo | the **checkout advancing** (`git merge --ff-only` inside `deploy-live.sh`). No install needed — the link already points at the file | `install.sh:266,274,278,362,374,391,641`; `copy_file` vs `link_file` |
| **ADD of a new tracked file in any of those dirs** | per-file symlink that **does not exist yet** | `install.sh` must run to create the link. `deploy-live.sh` runs it on every advance, **and also runs `link_refresh` UNCONDITIONALLY ahead of the fetch** | `scripts/deploy-live.sh:930-965` (`link_refresh`), `:1024` (unconditional call), `:283-284` (install.sh) |
| **COPY surfaces** — `statusline.sh`, `CLAUDE.md`, `~/bin/*` self-updating launchers | `cp`, not a link | **`install.sh` must run even for an EDIT.** A repo edit is inert until then | `install.sh:613` `copy_file "$REPO_DIR/statusline.sh" "$CONFIG_DIR/statusline.sh"`; parity `scripts/deploy-parity-assert.sh:593` |
| **`migrations/*.sh`** | read **repo-side**, never linked | the checkout advancing. `~/.claude/migrations` does not exist (`ls` → No such file) | `scripts/deploy-migrations.sh:103,106` (`MIG_DIR="${CC_MIGRATIONS_DIR:-$REPO/migrations}"`) |

**The ADD-is-not-live mechanism, confirmed at source with its incident record**
(`scripts/deploy-parity-assert.sh:19-29`, "SECOND LEG"):

> *"`~/.claude/{hooks,hooks/lib,commands,scripts,bin}` are real dirs of PER-FILE symlinks, so a brand-new
> tracked file is never linked at all, however current the checkout. The operator's documented deploy step
> (ff-sync the shared checkout) cannot create the link — only `./install.sh` can. That hole shipped live:
> `hooks/lib/cc-interactive.sh` landed and stayed unlinked … silently disabling the operator-adoption hold."*

Restated in `.claude/commands/ship.md:120`: *"Never raw-ff the shared checkout … `deploy-live.sh --auto` is
the only sanctioned advance … it runs `install.sh` on every advance, which is what actually creates the links."*

### 1.3 What the implementer runs, per change type

```bash
# after /ship lands, in ALL cases (the one safe command):
bash ~/Development/claude-infrastructure/scripts/deploy-live.sh
#   --dry-run   decide + print, mutate nothing
#   --offline   decide against already-fetched origin/main, no network
#   --force     escape hatch when stamps exist but none is green
```

`deploy-live.sh` is **fail-closed on a green post-land stamp**, with a documented degradation ladder
(`scripts/deploy-live.sh:16-40`): **T1** newest GREEN tree descending live HEAD → **T1H** off-box hermetic
green with no on-box red → **T2** lag past budget + no RED stamp (loud banner + page) → **T3** all red ⇒ refuse.
`CC_DEPLOY_MAX_LAG_COMMITS=25` / `CC_DEPLOY_MAX_LAG_HOURS=6` is the T2 budget.

Current live state (measured): parity **green** across all 18 classes; provenance `GATED`, verification
`DEGRADED` (*"no green stamp, but deploy-live DECLARED this advance degraded (e0c6b4e877d7) — sanctioned,
not drift"*). Live layer sits at `e0c6b4e87`, **2 behind** `origin/main`.

**Verify your own change went live** with `bash scripts/deploy-parity-assert.sh` — exit 0 parity, 1 named
failure, **3 = NO VERDICT** (never conflate 3 with 0).

---

## 2. The migration system

### 2.1 Migration vs plain edit

From `migrations/README.md`:

- A migration is for **registration state** — "*executable, idempotent state landed in the same diff as its
  subject and run by the converger at deploy*". It replaced `docs/activation/pending-activation/`, which was
  an advisory store (measured 2026-08-07: 38 pending, 11 rotting past 24h, 8 SSOT drifts).
- A **plain edit** suffices when the change is entirely inside a file the live layer already links/copies and
  needs no registration step. Editing `lib/claude-launcher.zsh` is a plain edit; **wiring** it into `~/.zshrc`
  or flipping a `settings.json` hook is a migration.
- README verbatim: *"**New** operator-owned wiring should be a `c10` migration instead: it lands in the same
  diff as its subject, files itself once into a store a renderer already reads, and promotes to automatic with
  a one-word change."*

### 2.2 What `c10` means

Two classes, and **an undeclared class is a hard FAILED, never a default** (both defaults are wrong — README
§ "An undeclared class is a hard error"):

| Class | Behavior |
|---|---|
| `mechanical` | Run at converge, unattended. Derived state the converger already owns |
| **`c10`** | **STAGED, NEVER RUN.** The runner files exactly one operator-owned step into `cc-backlog needs` (event-keyed id, so re-filing folds onto the same id) and records it staged |

`c10` exists because the doc's rescope of **C10** — *"operator **runs**" becomes "operator **can revert**"* —
is the one clause a human must ratify once, and **that ratification has not happened**. So a migration
touching `settings.json`, a launchd plist, `~/.zshrc`, or credentials **declares `c10` and waits**.
Promotion later is a one-word diff: `c10` → `mechanical`.

`tests/deploy-migrations.bats:104` fails a `mechanical` that reaches a C10 surface.

### 2.3 Header contract (all required unless noted)

```bash
#!/bin/bash
# migration-class: c10                 # mechanical | c10 — NO DEFAULT
# migration-step: <one line naming the operator-owned step>     # c10 only, REQUIRED
# migration-run: <the exact command the operator pastes>        # c10, optional
# migration-verify: <one command; exit 0 ⇒ effect IS live>      # ALWAYS REQUIRED
# migration-conflict: <exit 0 ⇒ a DIFFERENT value at the same key ⇒ overridden>  # optional
# migration-subject: <path to the arm itself>                   # optional
set -uo pipefail
```

- `migration-verify` is **not optional and not the runner's business** — it is read by
  `scripts/registration-state.sh`. Three migrations (`0001`,`0003`,`0004`) landed unanswerable because the
  README omitted the row until 2026-08-11 (fixed by trunk commit `117e8aad4`).
  `tests/deploy-migrations.bats` case 9 asserts every migration declares one **and rejects a tautology**
  (`true`, `:`, `exit 0`).
- Three earned rules: **verify the EFFECT not the paperwork** · **don't re-derive what the subject derives**
  (call the subject's own `--status`) · **mind the per-config-dir loop** — `registration-state.sh` re-runs each
  verifier once per config dir with `CC_CLAUDE_DIR` re-aimed, which is right for `settings.json` things and
  **wrong for anything singular** (a launchd job, the ledger) ⇒ spell those config-dir-invariant or the oracle
  manufactures a permanent `partial`.

### 2.4 Body rules

1. **Idempotent by its own construction**, not merely by the ledger.
2. **Exit 0 = applied (including already-applied).** Non-zero stops the ordered run, retries next converge with
   a climbing `attempts`, and **blocks the close protocol's ✅** (`scripts/wrap-ledger.sh` counts `failed/*.json`).
3. **Bounded** — `CC_MIGRATION_TIMEOUT_S` = 120s (`scripts/deploy-migrations.sh:109`); a converge tick is 600s.
4. **Back up before you clobber** (`superseded/<name>.<epoch>`).
5. **Never write repo-side** — the converger must not dirty the checkout (`hooks/activation-watch.sh:249`).
6. `$CC_MIGRATION_REPO` and `$CC_MIGRATION_STATE` are exported; cwd is the repo root.

### 2.5 Numbering, running, recording

- **Naming**: `migrations/NNNN-<slug>.sh`, executable, run in **lexical order**.
- ⚠️ **Numbers are NOT enforced unique.** Two `0009`s coexist on trunk (`0009-claude-next-guardrail-parity.sh`
  and `0009-start-latency-router.sh`) and both are staged. No test asserts uniqueness (grepped
  `tests/deploy-migrations.bats` for `uniq|duplicate` → nothing). The ledger keys on the **full name**, so it
  works — but **use `0011`** for new work; `0010-postland-band-plist.sh` is the highest.
- **Running**: the converger calls `scripts/deploy-migrations.sh` with no args (materialise, then migrate)
  from `deploy-live.sh` — **twice**, once unconditional pre-fetch and once post-advance, so LANDED ⇒ LIVE
  holds within one cycle (`scripts/deploy-live.sh:996-1025`). A migration failure **never** aborts the deploy.
- **Recording**: `~/.claude/autonomy/migrations/{applied,staged,failed,superseded}/<name>.json`.
- **Operating it** (safe, read-only first two):
  ```bash
  scripts/deploy-migrations.sh --status      # applied / pending / failed / staged
  scripts/deploy-migrations.sh --dry-run     # decide + print, mutate nothing
  scripts/deploy-migrations.sh --selftest    # 22 cases, throwaway tree, no side effects
  ```

### 2.6 Current ledger (measured `--status`, 2026-08-11)

`0001` applied. **`0002`–`0010` ALL staged (operator-owned).** Directly relevant:

- **`0009-start-latency-router`** — *"the interactive account router is built, tested and landed but NOT wired"*.
- **`0009-claude-next-guardrail-parity`** — *"restore the 5 guardrail hooks that `.claude-next` alone is missing"*.

---

## 3. 🚨 The router is HALF-ACTIVATED — the ledger says `staged`, the shell says otherwise

This is directly the "(a) bare-`claude` account routing" work item, and the state is inconsistent:

| Half | State | Evidence |
|---|---|---|
| `~/.zshrc` sources the lib | **DONE** | `~/.zshrc:701` — `[ -r ".../lib/claude-launcher.zsh" ] && source ...   # start-latency router (migration 0009)` |
| `claude1` exists as a pinned wrapper | **DONE** | `zsh -ic 'whence -w claude1'` → `claude1: function` (also `claude`, `claude2`) |
| `accounts.json` `accounts[0].launcher` flipped `claude` → `claude1` | **NOT DONE** | `jq '.accounts[] \| .launcher'` → `claude`, `claude4`, `claude3`, `claude2`. `git diff origin/main -- accounts.json` is **empty**, and the file is byte-identical to the untracked backup `accounts.json.pre-router.20260811T083246Z` |
| Migration ledger | still `staged` | `deploy-migrations.sh --status` |

Migration `0009-start-latency-router.sh:20-26` says the two surfaces **must move together**, because
`scripts/handoff-fire.sh:6070` resolves `accounts[N].launcher` and **types it into a pane** to pin the account
it just charged with `--assign` (`:6087`). With `launcher = claude` and the router live, a fire that resolved
account 1 types the **router**, not a pin.

**Why it does not currently mis-route** (read the guards before "fixing" this):
`lib/claude-launcher.zsh:109` routes only when `! _resume && -z CLAUDE_CONFIG_DIR && -z CC_ACCOUNT_PINNED`.
`handoff-fire` sets `CC_ACCOUNT_PINNED`, so its own pick is not overridden. The header
(`lib/claude-launcher.zsh:10-17`) explains why an unset-`CLAUDE_CONFIG_DIR` test **alone** would be dead on
every automated path. Kill switch: `CC_CLAUDE_ROUTE=off` (`:48-49`) restores byte-identical pinned behaviour.
`--max-wait 0` forbids the sweep on the launch path (`:19-27`) — an abstention falls back to pinned.

---

## 4. Test surface

Corpus: **508 files** under `tests/` (`git ls-tree -r origin/main --name-only -- tests | wc -l`).

### 4.1 The suites that pin behavior you intend to change

| Suite | Tests | Measured runtime | What it pins |
|---|---|---|---|
| `tests/claude-accounts-core.bats` | **69** | **54.9 s** (`/usr/bin/time -p`, load 14.06, exit 0) | Router **math**, `--route`/`--rank` **exit contract**, `--readout` format, `frontier_window` parse, SSOT parsing, degradation paths, `--assign` ledger row (unknown account ⇒ **exit 64**). Hermetic: scratch SSOT in `BATS_TEST_TMPDIR`, unreachable endpoints, keychain-miss config_dir. **Router/frontier constants are DERIVED from the repo `accounts.json`**, so adding a constant cannot make the fixture silently disagree. `setup()` pins `CC_FIRE_CAPACITY_GATE=off` + `CC_FIRE_HEADROOM_GATE=off` |
| `tests/claude-launcher-router.bats` | **15** | **2.3 s** (exit 0) | The `claude1`/`claude` split, `_cc_route_config_dir`. Fully hermetic: fixtured `$HOME`, `CC_LAUNCHER_ACCOUNTS_BIN` pinned, and **`CLAUDE_CONFIG_DIR`/`CC_ACCOUNT_PINNED`/`CC_CLAUDE_ROUTE` deliberately UNSET** — *"inside a Claude session `CLAUDE_CONFIG_DIR` is always set, which silently disables routing — every routing assertion would pass vacuously"* |
| `tests/settings-drift.bats` | **11** | (fast) | CLI exit contract of `settings-drift-assert.sh` (0 = agree, 1 = drift) via `CC_DRIFT_DIRS` fixtures |
| `tests/handoff-fire-launcher-map.bats` | **7** | — | The launcher NAME a fire spawns comes from `accounts.json`, not composed. Fixtures use names the convention cannot reach (`cc-three`, `ax`) because live launchers *do* follow the convention |
| `tests/deploy-migrations.bats` | — | — | Every migration declares a class (case 3) and a non-tautological verify (case 9); a `mechanical` may not reach a C10 surface (case 5) |

Also in scope if touched: `claude-accounts.bats` (last-good quota ledger), `claude-accounts-providers.bats`,
`claude-accounts-fresh-lock-bound.bats`, `account-cliff-routing.bats`, `account-fact-derivation.bats`,
`cc-route.bats`, `settings-hook-timeouts.bats`, `settings-dedup-stop.bats`, `hook-chain.bats`,
`hook-chain-live-parity.bats`, `install-wire-hooks.bats`, `statusline-identity.bats`.

### 4.2 Running them reliably — `bats` is `cc-bats`

`bats` on PATH is the repo's **QoS chokepoint** shim (`bin/cc-bats`). Two mechanisms:

1. **Demotion** — `taskpolicy -c utility` (PRI 20), **not** `background` (measured ~84-89× tax) and **not**
   `nice -n 19` (which never moves PRI off 31 on Darwin). `bin/cc-bats:24-40`.
2. **Admission bound** — refuses when concurrent bats execution roots ≥ `CC_BATS_MAX_ROOTS` (default **2**)
   **AND** 1-min load/core ≥ `CC_BATS_MAX_LOAD_PER_CORE`. All four seams **fail OPEN**.

**How to tell a deferral from a pass** — a deferral is *loud on stderr and never exit 0*
(`bin/cc-bats:574-592`):

```
cc-bats: REFUSED — N concurrent bats execution root(s) (ceiling CC_BATS_MAX_ROOTS=2) AND 1-min load/core at or above ...
cc-bats: nothing ran, nothing was verified — this is a DEFERRAL, not a test result. Re-run when a slot frees:
cc-bats:   <the exact re-run command>
cc-bats: holders: pid <N> ...
cc-bats: override for this run: CC_BATS_MAX_ROOTS=0 <cmd>
```

**Detection recipe** (never pipe — `cmd | tail` returns tail's status):

```bash
bats tests/<suite>.bats > /tmp/out.log 2> /tmp/err.log; rc=$?
grep -q 'cc-bats: REFUSED' /tmp/err.log && echo "DEFERRAL — not a result"
tail -3 /tmp/out.log; echo "exit=$rc"
```

Escape hatches: `CC_BATS_MAX_ROOTS=0` (admission only) · `CC_BATS_QOS=off` (whole shim, also bypasses the bound).
Both suites above ran **green with zero refusals** at load 14.06 during this research.

---

## 5. SSOT inventory

| File | Live form | Tracked? | Hand-edited or generated | Regenerate / validate |
|---|---|---|---|---|
| `~/.claude/accounts.json` | **symlink** → repo `accounts.json` (`install.sh:446`) | **yes**, tracked on trunk | **hand-edited** | Consumed by `bin/claude-accounts`, `/accounts`, `scripts/handoff-fire.sh`, `skills/account-relogin`. Holds `accounts[]` (identity map), `router{}` (S_CUT .85, S_SOFT .5, SF_FLOOR .05, KMAX 8, KFLOOR .1, MARGIN_H .5, EPS_H .25, NO_RESET_H 168, WEEKLY_FLOOR .005, FABLE_FLOOR .02, JB_BONUS 1.25, + M7: URGENCY_EXP 2.0, KWORK_WINDOW_MIN 10, ASSIGN_TTL_MIN 15, PROJ_LOOKAHEAD_H 1.0), and `spend{usage_credits_authorized:false}` |
| `~/.claude/lib/account-map.generated.sh` | **symlink** → repo (`install.sh:366`) | **yes** | **GENERATED** — header says *"GENERATED by `scripts/gen-account-map.sh` from `accounts.json` — do not hand-edit"* | `scripts/gen-account-map.sh`. Maps `next\|claude`, `fable`, `next4\|claude4`, … → `CC_ACCT_DIR` (+ `CC_ACCT_IS_FABLE`). **Sets globals, never echoes** — a `$(...)` call site loses the fable flag |
| `~/.claude/model-config.yaml` | **symlink** → repo (`install.sh:454`) | **yes** | hand-edited | Declared as `model_config_ssot` inside `accounts.json`. Owns `opus_latest`, `frontier_access` |
| `~/.claude/providers.json` | **symlink** → repo (`install.sh:463`) | **yes** | hand-edited | `tests/claude-accounts-providers.bats` |
| **`~/.claude/settings.json`** | **REAL FILE, one per config dir, 5 distinct inodes** | ❌ **NOT tracked** (repo's `.claude/settings.json` is the repo's *project* settings; `settings-templates/settings.example.json` is the template) | hand-edited / merged | `./install.sh --config-dir <dir> --wire-hooks` **additively merges** the template hook/deny/ask roster (`install.sh:773-855`). Validated by `scripts/settings-drift-assert.sh` (cross-dir), `settings-hooks-lint.sh`, `settings-hook-timeouts.sh`, `settings-dedup-stop.sh` |
| `~/.claude/statusline.sh` | **REAL FILE — COPY, not symlink** | **yes** (`statusline.sh` on trunk) | hand-edited in repo | `install.sh:613` `copy_file`. Live copy currently **identical** to trunk. Parity-asserted at `deploy-parity-assert.sh:593` |
| `~/.claude/CLAUDE.md` | **REAL FILE — COPY** | **yes** (repo root `CLAUDE.md`) | hand-edited | Currently byte-identical (`md5` both `44a5190d3b9d81c449b10c7c45d230ef`). `.claude/CLAUDE.md` warns: *"`~/.claude/CLAUDE.md` is a separate real file — apply the same edits there"* |
| `~/bin/claude-accounts` | **symlink** (deliberately, `install.sh:424`) | yes | — | Strictly asserted by `deploy-parity-assert.sh` after the 2026-07-17→19 two-day-stale incident |

Migration ledger state lives at `~/.claude/autonomy/migrations/` (machine-local, not tracked).

---

## 6. 🚨 The four config dirs — shared vs isolated (DECISIVE for the startup banner)

### 6.1 The mirror model

`lib/config-mirror.zsh` symlinks **everything** from `~/.claude` into each account dir **except** a per-dir
isolate set, via `_cc_sync_config_mirror` (aliased `_cc_sync_account`), called from `~/.zshrc:479` at launch
and again by the `config-mirror-assert.sh` SessionStart hook.

| Dir | Account | Isolate set (`lib/config-mirror.zsh:35-38`) |
|---|---|---|
| `~/.claude-next` | account **1** (same account as `~/.claude`, different binary track) | `.claude.json .claude.json.backup` only |
| `~/.claude-secondary` | account 2 | `.claude.json*`, `.credentials.json`, `projects`, `sessions`, `session-env`, `shell-snapshots`, `history.jsonl`, `session-index.db*`, `stats-cache.json`, `statsig`, `telemetry`, `watchdog`, `teams`, `logs`, `file-history`, `run`, `ide`, `state`, `debug`, `plan-history`, `plan-versions`, `drafts`, `mcp-needs-auth-cache.json`, `.last-session`, `.last-interaction`, `.last-search-results.json` |
| `~/.claude-tertiary` | account 3 | same as secondary |
| `~/.claude-quaternary` | account 4 | same as secondary |

Notes with teeth:
- **Auth is NOT in the isolate list** — it lives in the macOS Keychain keyed by
  `sha256(CLAUDE_CONFIG_DIR)[:8]`, so a distinct dir isolates it automatically.
- `tasks` / `tasks-index.json` are **deliberately NOT isolated** since 2026-07-29 (a task board is work state,
  not account state; four divergent boards with colliding ids was the measured cost).
- Anything matching `*.lock`, `*.lock.d`, `*.pid`, `*.sock` is **never shared** — a dangling lock symlink reads
  as ELOCKED forever (this is what broke OAuth refresh on all four accounts, 2026-07-31).

### 6.2 The propagation answer — measured, not inferred

```
$ ls -lLi ~/.claude/settings.json ~/.claude-next/settings.json ~/.claude-secondary/settings.json \
          ~/.claude-tertiary/settings.json ~/.claude-quaternary/settings.json
452849554 ... 35228 .claude-next/settings.json
453104257 ... 35928 .claude-quaternary/settings.json
452849549 ... 35908 .claude-secondary/settings.json
452849551 ... 35938 .claude-tertiary/settings.json
452849547 ... 35921 .claude/settings.json
```

**FIVE distinct inodes, five different sizes.** `ls -li` (no deref) is identical, so they are not symlinks and
not hardlinks either.

**Why**, despite `settings.json` NOT being in any isolate list: `_cc_sync_config_mirror`'s default (safe) mode
**refuses to touch a forked real file** — `[[ -e "$dst/$name" && ! -L ... ]]` → `(( convert )) || continue`
(`lib/config-mirror.zsh`, the `--convert` branch). Each dir already had a real `settings.json`, so the mirror
skips it **forever**. Only `--convert` would replace it, and that is run only under an lsof-guarded one-shot
with all panes closed.

> ### ⇒ **A `settings.json` hook edit does NOT propagate. It must be made 5 times.**
> Sanctioned mechanism: `./install.sh --config-dir <dir> --wire-hooks` per dir (additively merges the
> `settings-templates/settings.example.json` roster; never clobbers a populated event) — `install.sh:773-855`.
> Then verify with `bash scripts/settings-drift-assert.sh` (exit 0 = agree, 1 = drift).
> **And because `settings.json` touches the live permission/hook surface, wiring it is C10** — that is exactly
> why migrations `0002`, `0005`, `0006`, `0007`, `0009-claude-next-guardrail-parity` are all `staged`.

### 6.3 The shared/isolated matrix that actually matters

Measured with `ls -ld` per dir:

| Surface | `~/.claude` | `.claude-next` | `.claude-secondary` | `.claude-tertiary` | `.claude-quaternary` |
|---|---|---|---|---|---|
| `settings.json` | real | **real (own)** | **real (own)** | **real (own)** | **real (own)** |
| `hooks/` | real dir (75 entries, per-file symlinks → repo) | **real dir (53 entries) — FORKED** | symlink → `~/.claude/hooks` | symlink → `~/.claude/hooks` | symlink → `~/.claude/hooks` |
| `statusline.sh` | real (copy of repo) | **real (own) — FORKED** | symlink → `~/.claude/statusline.sh` | symlink → | symlink → |
| `commands/` | real dir | **real dir — FORKED** | symlink → | symlink → | symlink → |
| `accounts.json` | symlink → repo | symlink → `~/.claude/accounts.json` | symlink → | symlink → | symlink → |
| `agents/`, `skills/`, `bin/`, `scripts/`, `lib/`, `autonomy/`, `backups/`, `cc-*` | source | shared (symlink) | shared | shared | shared |
| `.credentials.json` / Keychain, `projects/`, `sessions/`, `history.jsonl`, `session-index.db`, `statsig`, `telemetry`, `teams`, `logs`, `state`, `debug`, `plan-history` | — | **shared with `~/.claude`** (same account!) | **isolated** | **isolated** | **isolated** |
| `.claude.json` | own | **isolated** | isolated | isolated | isolated |
| `tasks/`, `tasks-index.json` | source | shared | shared | shared | shared |
| `*.lock`, `*.pid`, `*.sock` | own | never shared | never shared | never shared | never shared |

### 6.4 🚨 `.claude-next` is the odd one out — and it is account 1, the default

```
$ ls ~/.claude-next/hooks | wc -l   →  53
$ ls ~/.claude/hooks     | wc -l   →  75
```

22 hook files present in `~/.claude/hooks` are **absent** from `~/.claude-next/hooks`, including
`operator-readout.sh`, `mailbox-drain.sh`, `mailbox-wake-arm.sh`, `desk-brief-inject.sh`, `session-beat.sh`,
`cc-unattended-ask-guard.sh`, `goal-inert-watch.sh`, `coldcompile-admit.sh`, `hook-chain.sh`,
`escalation-watch.sh`, `curl-gate.py`, `curl-gate-scope.sh`, `keychain-guard.sh`, `relay-verbatim.sh`,
`qos-rewrite.sh`, `dispatch-assert.sh`, `cc-permission-beacon.sh`, `reset-hard-shadow-allow.sh`.

Live `settings-drift-assert.sh` run, 2026-08-11:

```
DRIFT [hooks] "PreToolUse|cc-unattended-ask-guard.sh"    — missing in: .claude-next
DRIFT [hooks] "SessionEnd|session-deregister.sh"         — missing in: .claude-next
DRIFT [hooks] "SessionStart|desk-brief-inject.sh"        — missing in: .claude-next
DRIFT [hooks] "Stop|session-beat.sh stop"                — missing in: .claude-next
DRIFT [hooks] "UserPromptSubmit|session-beat.sh prompt"  — missing in: .claude-next
settings-drift-assert: DRIFT — 5 divergence(s) across 5 config dirs
```

Migration `0009-claude-next-guardrail-parity` (staged) is the filed remedy: *"restore the 5 guardrail hooks
that `.claude-next` alone is missing … it links 3 hook files and edits `settings.json`, which is C10."*

**Implication for the banner work:** a new SessionStart hook wired only into `~/.claude/settings.json` reaches
**zero** of the four accounts a session actually launches into. The `hooks/` **file** propagates for
secondary/tertiary/quaternary (symlinked dir) but **NOT for `.claude-next`** (forked dir, needs its own
`ln -sf` or an `install.sh --config-dir ~/.claude-next` pass). The **registration** propagates to none of them.

### 6.5 The zero-model-token render channel

`settings.json` `statusLine` is `{"type":"command","command":"~/.claude/statusline.sh"}` — a per-turn render
with no model tokens. For a hook, the proven channel is a **top-level `{"systemMessage": …}`**:
global `CLAUDE.md` records that `additionalContext` *"forces a turn and increments the same
consecutive-block counter"* while *"`systemMessage` is the only field that does not extend the turn"*.
Precedents: `hooks/operator-readout.sh:12,1131,1166` (*"pure-advisory `{"systemMessage": …}`"*),
`hooks/goal-inert-watch.sh:48-51,129`, `hooks/mailbox-drain.sh:334-359`.

⚠️ **Open uncertainty the implementer must probe, not assume:** every `systemMessage` precedent in this repo is
a **Stop** or **UserPromptSubmit** hook. Grepping the three SessionStart hooks most likely to use it
(`frontier-status.sh`, `activation-watch.sh`, `config-mirror-assert.sh`) returns **0** `systemMessage`
occurrences — and `hooks/session-start.sh:207-226` returns `hookSpecificOutput.additionalContext`, i.e. the
token-costing path. **Whether SessionStart honors a top-level `systemMessage` is unproven here.** Probe it
before building on it. (The 15 SessionStart hooks currently wired are listed in §7 evidence.)

---

## 7. Gates + landing cost

### 7.1 Landing-cost verdict — **FREE**

There is **no** statement in this repo's `CLAUDE.md` or `.claude/CLAUDE.md` that landing spends money. Grepping
both for `spends money` returns only the *global boilerplate* describing the policy for other repos
(`CLAUDE.md:27,50,412,425,434`), never a claim about this repo. `.claude/CLAUDE.md` is unambiguous the other way:

> **"## Standing-land authorization (this repo only)**
> In THIS repo, work that is **complete + gate-green + committed on your own branch** lands via the
> project-local `/ship` flow **without a fresh ask** — the 📦-offer/wait cycle is waived here … Why scoped
> here: parked commits leave the LIVE `~/.claude` layer stale (this repo is its symlink/source), so
> committed-not-landed is itself 'work left on the table'. The authorization is exclusively for the
> fail-closed project-local `/ship` (landing lock + last-moment re-fetch + full gate + content-verify +
> stranded sweep) — **never a bare `git push`**."

⚠️ **Use the PROJECT command, not the global one.** Both exist and they are different files:
`.claude/commands/ship.md` (tracked, 25,444 B, the fail-closed `scripts/ship-land.sh` pipeline) vs
`~/.claude/commands/ship.md` → repo `commands/ship.md` (the global). When cwd is this repo the project file
wins — read `.claude/commands/ship.md` and confirm before landing.

### 7.2 What must be green

| Gate | Where | Notes |
|---|---|---|
| **Commit-time** | `.git/hooks/pre-commit` (machine-local, 11,477 B) | git-identity lint + related. **Never `--no-verify`** |
| **`/ship` preflight** | `scripts/ship-land.sh` | Refuses landing from the shared checkout on a non-session branch (**exit 4**); refuses a dirty tree (**exit 2**); escalation-scans the range (DISCLOSURE class never exemptible, EFFECT class exemptible via `scripts/esc-exempt.manifest` **read from the range's BASE revision**) → parks a class-B packet and **exit 3** |
| **Fast gate (default lane)** | inside `/ship`, **unlocked** | `shellcheck` + `bash -n` + `py_compile` on changed shell/python (incl. extensionless python by shebang) · **`scripts/test-hermeticity-lint.sh` ratchet, fail-fast, runs BEFORE smoke** · wall-clock ratchet · **bounded smoke** over `--direct` suites (`SHIP_LAND_SMOKE_BUDGET_S` 120s total) |
| **Locked window** | `scripts/land-lock.sh` | seconds only: fetch → CAS → `push origin HEAD:main` → content-verify. p50 3s / p90 5s |
| **Content-verify** | `scripts/land-verify.sh` | every changed path present on trunk **AND** `git diff` empty. **A `rev-list --count` of 0 proves nothing** (the 2026-07-11 incident) |
| **Post-land** | `scripts/postland-verify.sh` (background QoS) | the **only** party that may assert "this tree is green"; a GREEN stamp is what advances `gate-green`. Emits ~0.17 greens/day — **do not wait on it**; a red `gate-green` marker you did not cause is not your loose end |
| **Deploy** | `scripts/deploy-parity-assert.sh` | run by `deploy-live.sh` as `link_refresh`; also run it yourself after converging |

Exit codes worth memorising: `2` dirty · `3` escalation-parked · `4` shared-checkout · `5` rebase-conflict ·
**`6` your diff is red (a verdict — never retry unchanged)** · `7` non-ff · `8` verify-failed after retries ·
**`9` GATE-KILLED (a non-verdict — a claim about the machine)** · **`75` lock-starved (non-verdict, re-run)**.

**Never** free a stuck gate with a bare `pkill -f bats` — it kills every concurrent session's gate machine-wide.
Use `scripts/gate-cleanup.sh --dry-run` first. `hooks/validate-bash.sh` denies the unscoped form.

---

## 8. The recipe, end to end

```bash
# 0. fresh worktree off origin/main — NEVER work in the shared checkout
cd ~/Development/claude-infrastructure && git fetch origin main
git worktree add /tmp/wt-<slug> -b <branch> origin/main

# 1. edit. New wiring (settings.json / zshrc / plist / credentials) ⇒ migrations/0011-<slug>.sh, class c10,
#    with migration-step + a NON-TAUTOLOGICAL migration-verify. Lands in the SAME diff as its subject.

# 2. verify (read the stderr, never pipe)
bats tests/claude-launcher-router.bats   > /tmp/a.log 2>/tmp/a.err; echo $?   # ~2.3s / 15 tests
bats tests/claude-accounts-core.bats     > /tmp/b.log 2>/tmp/b.err; echo $?   # ~55s / 69 tests
grep -q 'cc-bats: REFUSED' /tmp/a.err /tmp/b.err && echo 'DEFERRAL — nothing was verified'
bash scripts/deploy-migrations.sh --selftest      # if you added a migration
bash scripts/deploy-migrations.sh --dry-run
bash scripts/settings-drift-assert.sh             # if you touched any settings.json

# 3. commit atomically, then land — FREE, standing-authorized, project-local /ship
/ship

# 4. converge (LANDED ≠ LIVE)
bash ~/Development/claude-infrastructure/scripts/deploy-live.sh
bash ~/Development/claude-infrastructure/scripts/deploy-parity-assert.sh   # 0 parity · 1 named · 3 NO VERDICT
bash scripts/deploy-migrations.sh --status
```

---

## 9. Adversarial pass — what I nearly missed

1. **`statusline.sh` and `CLAUDE.md` are COPY surfaces, not symlinks.** I assumed the "edit rides its link"
   rule was universal. It is not: `install.sh:613` uses `copy_file`, so even a plain **EDIT** to
   `statusline.sh` is inert until `install.sh` runs. Both are parity-asserted
   (`deploy-parity-assert.sh:593` and the `CLAUDE.md (copy)` class), so drift is caught — but only after.
2. **`.claude-next` is forked, and it is account 1.** The obvious reading of `config-mirror.zsh` ("everything
   is symlinked except the isolate set") predicts `.claude-next` shares `hooks/`. It does not — `ls -ld`
   proves a real dir with 53 vs 75 entries and `settings-drift-assert.sh` names 5 live divergences. The
   mechanism is safe-mode's refusal to convert a forked real dir, the same clause that keeps the 5
   `settings.json` files independent. Predicting from the model would have been wrong.
3. **The router is half-activated with a `staged` ledger.** I nearly reported `0009-start-latency-router` as
   simply "not done" from `--status`. `~/.zshrc:701` and `whence -w claude1` say otherwise; `accounts.json` is
   byte-identical to origin/main *and* to its own pre-router backup, so the `launcher` flip the migration calls
   inseparable never happened. **A migration ledger row is a claim about the ledger, not about the machine** —
   run the `migration-verify` oracle, don't read the status word.
4. **Duplicate migration number `0009`.** No test asserts uniqueness. Harmless (the ledger keys on full name)
   but it means "next number = highest + 1" needs `ls`, not arithmetic on the last row.
5. **`systemMessage` on SessionStart is unproven.** Every precedent in this tree is Stop/UserPromptSubmit;
   the SessionStart hooks all use the token-costing `additionalContext`. I did not assume it works.

### Evidence: the 15 currently-wired SessionStart hooks (`jq` over `~/.claude/settings.json`)

`session-start.sh`(10s) · `setup-plan-symlinks.sh`(5) · `setup-task-symlinks.sh`(5) ·
`pre-session-validate.sh`(10) · `lead-crash-watchdog.sh`(10) · `session-register.sh`(5) ·
`activation-watch.sh`(5) · `dod-persist.sh`(5) · `desk-brief-inject.sh`(5) · `mailbox-wake-arm.sh`(**14400**) ·
`session-index-start.sh`(5) · `config-mirror-assert.sh`(8) · `frontier-status.sh`(5) ·
`live-session-registry.sh`(5) · `mailbox-drain.sh session-start`(5).
Event totals: PreToolUse 14 · PostToolUse 12 · SessionStart 15 · SessionEnd 7 · Stop 12 · UserPromptSubmit 6 ·
Notification 5 · PermissionRequest 4 · TeammateIdle 1 · WorktreeCreate 1 · TaskCompleted 1 · PreCompact 3.

---

## 10. Open blockers / uncertainties

| Item | Status |
|---|---|
| Does SessionStart honor top-level `systemMessage`? | **UNPROVEN** — probe before designing the banner around it |
| `accounts[0].launcher` flip (`claude` → `claude1`) | **NOT DONE**; `0009-start-latency-router` still `staged`. Deciding whether to flip it is part of work item (a) and is C10 — the operator's call |
| `.claude-next` guardrail parity | 5 hook divergences live; `0009-claude-next-guardrail-parity` staged and unrun |
| Live layer 2 commits behind `origin/main`; verification state `DEGRADED` (sanctioned T2 advance) | Not a blocker; re-check with `deploy-parity-assert.sh` after landing |
| Untracked `accounts.json.pre-router.20260811T083246Z` in the shared checkout | Someone ran the activation script today at 08:32 and it left a backup with no corresponding change. Worth one question before touching `accounts.json` |
