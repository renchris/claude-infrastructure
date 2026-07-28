## Land → Deploy → Live pipeline (claude-infrastructure, disk truth 2026-07-28)

### 1 · Live-layer topology

`~/.claude` is a **real directory**, never a symlink. Deployment is per-entry, by four different mechanisms:

| Live path | Mechanism | Count (repo→live) | Guarded? |
|---|---|---|---|
| `~/.claude/hooks/*.sh` | per-file symlink → checkout | 60 → 60 | ✅ `deploy-parity-assert.sh` |
| `~/.claude/hooks/lib/*.sh` | per-file symlink | 8 → 8 | ✅ |
| `~/.claude/commands/*.md` | per-file symlink | 22 → 22 | ✅ |
| `~/.claude/scripts/*.sh` | per-file symlink (top-level glob only) | 81 → 81 | ✅ |
| `~/.claude/scripts/limit-recover/*` | per-file symlink | — | ✅ |
| `~/.claude/bin/cc-*` | per-file symlink | 50 links | ✅ |
| `~/.claude/skills/<name>/*` | real dir + per-file symlink | 12 repo dirs → 29 live dirs (17 Anthropic-shipped) | ❌ **not asserted** |
| `~/.claude/CLAUDE.md`, `rules/*.md`, `statusline.sh`, `bin/it2` | **copy** (`copy_file`) | identical today | ❌ no parity leg |
| `~/bin/{claude-latest,claude-update,claude-versions,browsermcp-wrapper.sh,claude-kimi}` | **copy** | identical | ✅ (content) |
| `~/bin/claude-accounts` | symlink (deliberately — drifted 2 days as a copy) | — | ✅ strict |
| `~/Library/LaunchAgents/*.plist` | **copy** + `bootout`/`bootstrap` | 13 files, all byte-identical | ❌ |
| `~/.claude/agents/*.md` | **nothing — install.sh has no `agents/` leg** | 4 repo files NOT live; 4 live files NOT in repo | ❌ |
| `~/.claude/{tools,tests,docs,launchd,templates}` | not deployed (repo-only) | — | n/a |

`install.sh:43 link_file` / `:53 copy_file` / `:66 ensure_real_dir` are the three primitives; the globs at `install.sh:88,95,104,150,170,197,266` define the whole deployed surface.

**Fan-out to the 4 alt config dirs** (`~/.claude-{next,secondary,tertiary,quaternary}`): each is a real dir of **directory-level** symlinks into `~/.claude` for `skills/ agents/ rules/ autonomy/ bin/ CLAUDE.md`, but `hooks/ commands/ scripts/` are **their own real dirs** — populated once by `install.sh --config-dir` on **2026-07-18 16:39** and never since. All 4 `settings.json` are separate real files; every hook command in them is the absolute `~/.claude/hooks/…` path (67/69, 63/65, 64/66), so the alt dirs' own `hooks/` are dead weight — but `commands/` is not (2 commands, `desk.md` + `relogin.md`, are missing there) and `scripts/` there are **copies: 23 drifted, 27 absent**.

### 2 · The pipeline as it actually runs

1. **Land** — `scripts/ship-land.sh` from a dedicated worktree (`ship-land.sh:1053` refuses to land from the shared checkout on `main`, exit 4). Gate → `git push origin HEAD:$TRUNK` (`:1030`) as a **subprocess**, so it never hits the `Bash(git push:*)` ask. Content-verify (`land-verify.sh`) + `stranded-sweep.sh` + `land.log` attest line.
2. **Post-land verify (async)** — `ship-land.sh:1101-1107` writes `$POSTLAND_DIR/queue` and Popen-detaches `postland-verify.sh --run-if-needed`. **This — not launchd — is the only thing that has ever produced stamps.**
3. **Stamp** — `~/.claude/autonomy/postland/stamps/<tree-sha>.json`, `{"verdict":"green"|"red"}`.
4. **Deploy (operator, C10)** — `scripts/deploy-live.sh`: `fetch origin main` → walk `rev-list origin/main -n 200` newest-first → first tree with a **green** stamp = TARGET → `git merge --ff-only $TARGET` → run `install.sh` → report un-stamped commits still queued.
5. **Link refresh** — `install.sh` (idempotent) is the *only* thing that creates a symlink for a brand-new tracked file. Its **only** programmatic caller is `deploy-live.sh:118`.
6. **Surfacing** — `hooks/operator-readout.sh:113-123` (Stop hook, registered in all config dirs) prints `▶ bash ~/.claude/scripts/deploy-live.sh [deploy: live layer N behind origin/main]` when the shared checkout is on trunk and `rev-list --count HEAD..origin/main > 0`. **That is the definition of "deploy-lag".** `hooks/activation-watch.sh` (SessionStart) surfaces un-run activations + REPO-ONLY drift. `/wrap` renders the same block via `operator-readout.sh --render`.

Nothing else advances the checkout: `grep 'pull --ff-only|merge --ff-only'` across `scripts/ hooks/ bin/ commands/ lib/` hits only `deploy-live.sh:114` (plus prose in activation scripts). No launchd job, no cron, no hook, no `WatchPaths` anywhere. `claude-infrastructure` is **not** registered with `git maintenance` (only `reso-management-app` is) — `origin/main` ref freshness is incidental.

### 3 · Current state — the pipeline is deadlocked

- **0 of 24 stamps are green.** Every stamp since 2026-07-25 is `"verdict":"red"` on the same 6 suites (`deploy-parity`, `desk-arm-live`, `desk-recycle-durable`, `lr-team-audit`, `session-continue`, `waiting-recycle`). Newest: `stamps/292374fe….json` → `ea6f7b5a`, 2026-07-27T10:02:43Z.
- **`deploy-live.sh` therefore refuses.** Simulated read-only over `rev-list origin/main -n 200`: no green tree → `die "no GREEN stamp…"` + page. Proof it already happened: `~/.claude/autonomy/pages/deploy-blocked-1f19ac0ef552.page` (2026-07-25 22:55, "the live layer is FROZEN until a tree verifies green").
- **So the actual deploys bypassed it.** `git reflog show HEAD` on the shared checkout: `merge origin/main: Fast-forward` at 07-26 22:34, 23:12, 07-27 01:24. `deploy-live.sh` passes a resolved **SHA** to `git merge --ff-only`, so a reflog naming the **ref** `origin/main` cannot be it — these were raw `git merge/pull --ff-only origin/main`, i.e. the ungated path, with no `install.sh` afterwards.
- **Live lag right now:** HEAD `ebad3250` (07-27 00:39), `origin/main` `ea6f7b5a` — **2 commits behind**.
- The same reflog shows a `commit:` **made in the shared checkout** at 07-27 01:25 then `reset: moving to HEAD~1` — the project rule against committing there was violated in the last 36h.

### 4 · Gaps (each with its evidence)

**G1 — new-file symlink gap, currently live.** `skills/video-understanding/SKILL.md` landed in `ebad3250` (land.log 2026-07-27T08:24:48Z, worktree `wt-video-understanding`), the checkout ff'd to it 3 min later — and `~/.claude/skills/video-understanding` **does not exist**. It is the only repo skill dir with no live counterpart, and it is absent from this session's skill listing. Cause: the ff ran without `install.sh`.

**G2 — the parity guard cannot see G1.** `deploy-parity-assert.sh:167` scopes its existence leg to `git ls-files -- hooks commands scripts bin`. `skills/`, `lib/`, `agents/` are excluded by construction. It returned **RC=0 (parity)** today while `skills/video-understanding/SKILL.md` was unlinked. An independent sweep over `git ls-files hooks commands scripts bin skills lib` finds 20 unlinked tracked files: 15 are `lib/cc-upgrade-gate/*` + `hooks/tests/` + `scripts/*-tests|relogin-probes/*` (install.sh never links those — legitimately out of scope), 1 is `skills/video-understanding/SKILL.md` (a real miss).

**G3 — all 13 `com.claude.*` launchd labels are DISABLED.** `launchctl print-disabled gui/501` lists every one; `launchctl list | grep com.claude` returns nothing; `/tmp/claude-postland-verify.{stdout,stderr}.log` (declared in the plist) **do not exist** — the job has never run under launchd. `install.sh:270-274` does `bootout` then `bootstrap … || load … || true` and **never calls `launchctl enable`**, so every `install.sh` run silently fails to load them. `docs/activation/pending-activation/09-postland-verify-activate.sh:42-49` documents the exact cause: legacy `launchctl unload -w` wrote the disabled bit; `bootout` doesn't clear it; `bootstrap` then fails EIO. That activator is the only code path that calls `launchctl enable`.

**G4 — `09-postland-verify-activate.sh` is REPO-ONLY.** Confirmed by direct comparison: present at `docs/activation/pending-activation/09-postland-verify-activate.sh`, **absent** from `~/.claude/autonomy/pending-activation/`. `operator-readout.sh:130-137` iterates `$ACT_DIR/*.sh` — the live dir — so this activation **can never appear in the operator's queue**. Running it (with `CONFIRM=1`) would: (0) `postland-verify.sh --selftest`, (1) symlink the script live (already linked), (2) `launchctl enable` + `cp` plist + `plutil -lint` + `bootstrap` → 5-minute polling verifier. It is the only step that would un-freeze the green-stamp supply.
Also drifted repo↔live (live copy is stale): `02-load-dispatcher`, `03-load-discovery`, `05-pmset-caffeinate`, `09-operator-readout`. Un-run (no `.done`): `04-page-channel`, `05-pmset-caffeinate`, `05-ship-rail-push-allow`, `10-close-attrib`, `10-lead-crash-orphan-close`, `12-mailbox-posttool`, `13-mailbox-gc`.

**G5 — `ship-rail-push-allow` is deployed but wired nowhere.** `~/.claude/hooks/ship-rail-push-allow.sh` is a valid symlink; `grep ship-rail-push-allow` over all 5 `settings.json` → **0 hits**, and over `settings-templates/settings.example.json` → **0 hits** (so even `install.sh --wire-hooks` won't add it). Live permissions remain `ask: ["Bash(git push:*)"]`, `deny: ["Bash(git push --force:*)","Bash(git push -f:*)"]`. What it *would* allow (`hooks/ship-rail-push-allow.sh:1-31`): exactly `git push origin HEAD:<safe-branch>` — origin only, `HEAD:<ref>` refspec, no flags, no force, no compound/substitution/redirect; everything else exits 0 silent. Activation = `docs/activation/ship-rail-push-activate.sh --apply` (idempotent, backs up + jq-validates all 5 settings files), staged as `05-ship-rail-push-allow-activate.sh` (IN-PARITY, **un-run**), runbook `docs/SHIP-RAIL-PUSH-ALLOW-ACTIVATION.md`. It does **not** affect `ship-land.sh`'s own push (subprocess, already ask-exempt); it only unblocks the model-issued land push in `commands/ship.md:43`.

**G6 — the post-land staleness guard is blind to "all red".** `ship-land.sh:266-288 postland_net_live()` computes liveness from the **newest green stamp's mtime**; `[[ "$newest" -gt 0 ]] || return 0` treats *zero greens* as "net not adopted — never brick that". With 24 red / 0 green it returns 0, so every land stays `gate_scope:"scoped"` (confirmed in `land.log` for all 4 lands on 07-27) while the full-suite net that justifies scoping has produced nothing but reds for 3 days.

**G7 — alt-config-dir hop.** `~/.claude-next/hooks` is missing 12 hooks that exist in `~/.claude/hooks` — including `operator-readout.sh`, `dispatch-assert.sh`, `mailbox-drain.sh`, `desk-brief-inject.sh`, `ship-rail-push-allow.sh`, `cc-unattended-ask-guard.sh`. Harmless *today* only because all `settings.json` reference `~/.claude/hooks/…` absolutely — a latent trap for any future relative wiring. `~/.claude-next/scripts` is 55 frozen copies (23 drifted, 27 missing). Nothing re-runs `install.sh --config-dir` for these.

**G8 — surfaces with no version control at all.** `~/.claude/agents/`: `deep-research.md`, `deep-research-sonnet.md`, `frontier-derivation.md`, `research-decomposition-critic.md` exist **only live** (untracked); `agents/{fresh-eyes-evaluator,north-star-design-agent,schema-migration,visual-design-iterator}.md` exist **only in the repo** (never deployed). Same class: `~/.claude/hooks/{curl-gate.py,keychain-guard.sh,enforce-email-formatting.py}` are real files, **not in the repo**, and all three are registered PreToolUse hooks. `install.sh` has no leg for any of them; a machine rebuild loses them.

**G9 — reverse-direction hazard.** `sync.sh` copies live `~/.claude` **back into** the repo with no direction guard (`sync.sh:20-40`, `cp -L`). For symlinked files it resolves to the repo file and short-circuits; for the copy surfaces (`statusline.sh`, `~/bin/*`, `CLAUDE.md`) a stale live copy would clobber a newer repo file. Documented as the reason `claude-accounts` was switched to a symlink (`install.sh:117-129`).

### 5 · Everything that reacts to `origin/main` advancing

Nothing does, automatically. Full launchd inventory:

| Label | State | What it does |
|---|---|---|
| `com.claude.postland-verify` | **file installed, byte-identical, DISABLED/never loaded** | every 300s: is origin/main's tree green-stamped? else full `bats tests/` + `bash -n` in a disposable worktree, bisect, page |
| `com.claude.dispatcher` | installed, disabled | 900s `cc-dispatch --once` — the L4 backlog dispatcher spine |
| `com.claude.discovery` | installed, disabled | hourly discovery feed (frontier-hole supply) |
| `com.claude.boot-resume` | installed, disabled | 300s + RunAtLoad, post-login reboot session recovery |
| `com.claude.desk-invariant` | installed, disabled | 300s desk-existence/engagement invariant |
| `com.claude.caffeinate-floor` | installed, disabled | machine-awake floor |
| `com.claude.power-policy-verify` | installed, disabled | hourly power-policy verifier |
| `com.claude.nightly-regression` | installed, disabled | 04:00 calendar full regression |
| `com.claude.log-rotation` | installed, disabled | hourly `rotate-autonomy-logs.sh` |
| `com.claude.session-search-sweep` / `-backfill` | installed, disabled | 60s sweep / calendar backfill of the session index |
| `com.claude.team-orphan-reaper` | installed, disabled | 600s orphaned-teammate reaper |
| `com.claude.lead-supervisor` | live-only plist (no repo copy), disabled | `--daemon` lead supervisor |
| `com.claude.relogin` | **`launchd/staged/` only, not installed** | hourly `cc-relogin-poll --once` |
| `com.chrisren.autonomy-sweep` | **LOADED** | 300s `autonomy-sweep.sh` |
| `com.chrisren.cc-reaper` | **LOADED** | 300s `cc-reaper sweep --reap` |
| `com.reso.lr-reset-poller` | **LOADED** | 600s limit-recover reset poller (`~/.claude/scripts/limit-recover/`) |
| `com.chrisren.{restic-claude-archive,screenshot-clipboard,verify-2114-archive,watch-claude-code-2118-hold}` | LOADED | backup / screenshot-to-clipboard / version watchers |
| `org.git-scm.git.{hourly,daily,weekly}` | LOADED | `git maintenance` — **claude-infrastructure is NOT in `maintenance.repo`** |

No plist declares `WatchPaths`. The only reactive surfaces are session-scoped hooks: `activation-watch.sh` (SessionStart) and `operator-readout.sh` (Stop).

### 6 · Adversarial pass — what I checked that the brief didn't ask

- **Is `~/.claude` even the live layer for the sessions actually running?** Partly. This session reads `~/.claude-next/CLAUDE.md` — which is a symlink to `~/.claude/CLAUDE.md`. `skills/ agents/ rules/ autonomy/ bin/` are directory symlinks to `~/.claude`, so G1's skill gap propagates to all 4 dirs. `hooks/ commands/ scripts/ settings.json` do **not** (→ G7).
- **Copy surfaces with no guard** — diffed `statusline.sh`, `bin/it2-wrapper`, `CLAUDE.md`, all 13 plists: all currently identical. Clean today, unmonitored tomorrow.
- **Who actually fetched `origin/main`** (FETCH_HEAD 10:32 today): not a scheduled job — `git fetch` appears only in `postland-verify.sh`, `stranded-sweep.sh`, `ship-land.sh`, `handoff-fire.sh`, `deploy-live.sh`, `nightly-regression.sh`, `bin/cc-dispatch:98`. So `operator-readout`'s lag number is computed against a ref whose freshness is a side-effect of unrelated activity.
- **`cc-upgrade-gate`**: `lib/cc-upgrade-gate/*` (15 files) is tracked but has **no tracked entry point** and no live counterpart; `~/.claude/bin/cc-upgrade-gate` does not exist. `lib/` has no install.sh leg at all — `~/.claude/lib/desk.zsh` was symlinked by hand at 2026-07-25 14:52 (matching `06-desk-bootstrap-activate.sh.done`), i.e. activation scripts create ad-hoc links outside the installer, unguarded.

### Blockers / uncertainties

- I could not determine **who** ran the three raw `merge origin/main` ff's (reflog records no actor). The negative claim is solid: the reflog message names a ref, `deploy-live.sh` passes a SHA.
- Whether `install.sh` ran at 07-26 23:15 by hand or via `deploy-live.sh --force/--bootstrap` is undetermined; symlink mtimes prove it ran *then*, and G1 proves it did **not** run after the 07-27 01:24 ff.
- I did **not** run `deploy-live.sh` (even `--dry-run` fetches) or any activation — all findings are read-only; the one script I executed, `deploy-parity-assert.sh`, is documented and verified read-only.