# Is hiradp/git-forest worth applying to our worktree workflows?

**2026-09-19. Verdict: do not adopt the tool — it is disqualified by DATA MODEL, not by quality —
and of its twenty ideas, three are worth porting, none of which closes a recorded incident. The
highest-value thing this investigation produced is not from git-forest at all.**

Method: a 20-candidate adjudication workflow (68 agents, 0 errors, 12.5M subagent tokens,
~35 min) — characterize → adjudicate → adversarially refute each verdict in the OPPOSITE
direction → tiebreak the disputes → completeness critic → synthesize. Journal:
`~/.claude-secondary/projects/-Users-chrisren-Development-claude-infrastructure/cb227486-f06c-46f0-99d2-3e38af3c4f93/subagents/workflows/wf_bbd61d2e-379/journal.jsonl`.
Every number below was re-verified by hand afterwards; where the workflow's figure and the
hand measurement differ, the hand measurement is given and the drift noted.

## 1. What git-forest is, measured

A Rust CLI, MIT. **1 star, 0 forks, 0 releases, 0 tags, 26 commits (24 by one human + 6
dependabot), created 2026-08-08, last push 2026-09-14**, 4 open issues (all dependabot bumps).

Its unit is a **workspace: one named slice across N repositories**, each a linked worktree at
`<workspaces.root>/<workspace>/<repo>[@slot]`, branches from a template (`user/{checkout}`),
declared in a `.forest.toml` `repositories.members` list. Design axiom, its own words: *"It does
not reset or delete branches, start runtime services, or maintain a separate worktree registry.
Git worktree metadata and the filesystem are authoritative."* Its `attach` verb targets **Herdr**.

## 2. Why the tool is disqualified here

Three independent blockers, each sufficient:

1. **Layout.** `checkout_for_path` (`src/workspace.rs:358-370`) demands exactly one normal path
   component below the workspace root. Pointed at `~/Development/.worktrees` it reads each of our
   ~202 flat entries as a *workspace name* and finds no configured member inside — our entire live
   fleet reports as unexpected entries.
2. **Its removal safety is weaker than ours, on the axis we already had an incident on.** A single
   `git status --porcelain --ignored=matching` emptiness test (`src/commands/remove.rs:288-305` via
   `src/git.rs:431-453`) — the exact clean-tree gate `hooks/git-worktree-guard.sh:2-8` names as the
   2026-06-12 root cause. It ships **zero `--dry-run`** (`grep -rniE 'dry.run|dry_run' src tests
   README.md docs` → 0).
3. **Its headline UX has no runtime here.** `herdr` is ABSENT from this machine, and so is `just`
   (cargo/rustc are present). The interactive launcher and `attach` are dead on arrival.

## 3. The candidate table (20 adjudicated, each adversarially refuted)

| candidate | do they | do we | delta | conv% | action |
|---|---|---|---|---|---|
| multi-repo-workspace | workspace = N repos in one slice, `config.rs:203-205` | flat root, 7 repos, ~202 entries, no session holds 2 | per-entry attribution | 85 | drop |
| named-checkout-slots | `repo@slot` + charset path validator `config.rs:291-308` | 0 slot referent | refuse an unowned path vs adopt it | 72 | drop |
| origin-head-discovery | 1 rung + refuse, `git.rs:73-90` | 4-rung verified ladder, `wrap-ledger.sh:485-506` | none; ours stricter | 88 | already-have-it |
| preflight-then-mutate | pure verdict then act, `create.rs:143-205` | mutating gate ABOVE two refusals, `handoff-fire.sh:10256` vs `:10261` | ordering only | 80 | declined (see §6) |
| mutation-serialization | flock on config dir, `workspace.rs:40-64` | `land-lock.sh:13-19` + pid reaping | 0 observed collisions | 85 | already-have-it |
| rename-repair | 2-phase fs-rename + repair + resume, `rename.rs:78-207` | 0 `worktree move`, 0 `worktree repair` in tree | no relocation verb at all | 90 | steal (#0 below) |
| archive-not-delete | refuses on ignored files, `remove.rs:296-299` | deletes them; ledger on 2 of 3 actuators | landed lane records nothing | 90 | steal (#1) |
| clean-stale-registrations | attempt-all prune, `clean.rs:11-58` | `worktree-gc.sh:1103-1108` + 5 residue counters | forest weaker | 88 | already-have-it |
| drift-reconciliation-report | dir-vs-registry diff, `workspace.rs:199-246` | `cloud-reconcile.sh:336-366` | ours scoped to roots we own, deliberately | 88 | already-have-it |
| machine-contract | `--json` on 14/16, `cli.rs:84-101` | named-field counts line, `worktree-gc.sh:1450` | 2 residue classes never reach it | 88 | steal (#2) |
| no-registry-axiom | no registry; fs + git authoritative | both clauses held (`worktree-gc.sh:13`) | typing only | 92 | already-have-it |
| bounded-concurrency-update | worker pool over repos, `fetch.rs:77-119` | `claude-accounts:1525` same pattern | none (single-repo here) | 93 | drop |
| conservative-removal | 0 `remove_dir_all`, force opt-in | janitor identical + 6-gate liveness | invariant SCOPE | 85 | already-have-it |
| ux-surface | 13 completers, TUI, man page | oh-my-zsh compinit + git's `_git` + fzf | no referent | 94 | drop |
| fail-fast-with-not-run-ledger | 2-state per-unit report | 3-state + resolved override, `deploy-live.sh:2678-2680` | ours stricter | 93 | already-have-it |
| compare-and-swap-ref-update | `update-ref <ref> <new> <old>`, `git.rs:512-520` | 0 CAS | 2 lines; does not close `:413`'s `fetch --force` | 70 | declined |
| ignored-path-overlap-refusal | hand-rolled set intersection, `git.rs:227-281` | `read-tree -n -u -m` dry run, `deploy-live.sh:1577` | ours stricter, git-oracled | 82 | already-have-it |
| git-env-scrubbing | 12 vars scrubbed before every spawn, `git.rs:7-20` | 1 deliberate export, no boundary | blinds `loaded-untracked-lint.sh:76` | 78 | steal (#3) |
| charset-restriction | closed charset on path components | `check-ref-format`, `%q` at the sink | 0 incidents | 80 | drop |
| case-folding-by-backend | models git's rule in userspace | delegates every question to git | ours stricter | 93 | already-have-it |

**Never adjudicated** (from `AGENTS.md`, which no phase cited): argv-arrays-never-shell-strings
(`AGENTS.md:10-11` — forest's real injection invariant, which we cannot hold because we are shell);
no-implicit-network (`:13-14` — we violate it at `handoff-fire.sh:8363`); the typed exit taxonomy
(`src/error.rs:78-90`); the self-auditing supply-chain CI ratchet.

## 4. The measurements that reframed the question

Taken by hand on this machine, 2026-09-19:

- `~/Development/.worktrees` holds **~202 directories / 101 GB shared across 7 repos**:
  claude-infrastructure 64, doc_classifier 61, reso-management-app 30, reso-web-app 13,
  lakehouse-lecture 12, sevenrooms-bridge 4, personal 4. **`worktree-gc.sh` says "5 repos" at
  :14, :80, :311, :525, :880 — the root grew by two and nothing noticed.**
- **claude-infrastructure owns only 4.2 GB of that 101 GB** (mean 66 MB/worktree). The mass is
  reso (43.4 GB) and doc_classifier (43.0 GB) — per-worktree dependency installs. **git-forest
  never installs deps by design, so it is irrelevant to the single largest measurable cost.**
- `git worktree prune --dry-run -v` → **empty**. We have no stale-registration problem.
- **64 of 86** live worktrees carry gitignored content (the workflow said 60/82; population moved).
- The real residue is our own gc's closing line, printed in **7 of 7 sweeps**: *"15 unlanded
  worktree(s) are past the 72h horizon with NO ownership oracle at all — nothing will ever rule on
  them."*

## 5. The comparator the workflow missed, and the answer it gives

The workflow's own completeness critic found that 60 agent passes went to a 1-star repo while
**`worktree-harness` (`/opt/homebrew/bin/worktree-harness`, v0.2.0) has been installed here since
2026-06-03** and our own `scripts/new-worktree.sh:49-56` adjudicated only its `new` verb, calling
the tool "generic and good". `gc`, `status`, `merge`, `doctor` were never assessed. So it was run:

```
worktree-harness --dry-run -C <repo> gc     # preview is the default
```

It is genuinely good and conservative — `KEEP … open by a live process` (it HAS a liveness oracle),
`KEEP … dirty (uncommitted work)`, `KEEP … N commit(s) not in main (merge first)`, `KEEP … detached
HEAD (manual review)`, `WOULD remove … clean + merged + idle`; branches always preserved; a global
`--dry-run`; a `status --porcelain` machine contract; and per-worktree port assignment plus
`wh_git_exclude ".harness.env"` (`cmd_new.sh:42`), which our four creation lanes lack.

**On the overlapping population the two janitors AGREE exactly** — both propose removing the same
four (`wt-jev-{lessons,pace,secrets,zdr}`), and the one apparent disagreement was my own stale
reading: `wt-jev-pace` showed 4 cwd-holders 90 minutes earlier, and by the time of the comparison
that session had finished and landed (`9ee09166e`), leaving 0 holders and an empty `git cherry`.
No safety gap. *(Method note: re-read liveness immediately before acting on it.)*

**But it does not solve our actual pain.** worktree-harness keeps the un-ownable residue under
"N commit(s) not in main (merge first)" — identical to our gate 6 — with **no abandon horizon, no
ownership oracle, no dispose warrant, no disposal ledger**. So the critic's claim that it "answers
three of my four recommendations at zero lines of new code" is right on dry-run, machine contract
and liveness-gated gc, and **wrong on the one that matters**: the 15-never-rulable class is ours to
solve either way.

## 6. What is actually worth doing, ranked

**#0 — NOT from git-forest, and it outranks everything else. DONE this session.**
`hooks/validate-bash.sh:1425` — the most-read worktree instruction on this box, fired on every
attempted shared-checkout commit — prescribed `git worktree add -b <branch> /tmp/wt-<topic>
origin/main`; `commands/handoff.md:78-79` said the same. **`/private/tmp` does not survive a reboot
here**: `kern.boottime` = 2026-09-16 16:28:30 and of 980 entries the *minimum* birth time is 16:28.
13 registrations of this repo sat there; 3 were already GONE directories with surviving
registrations. The prescription arrived 2026-09-17 in `1e9acf553`, incidental to that commit's
subject, and contradicted the repo's own record — `docs/research/SESSION_AUTONOMY_RESEARCH.md:447`
already prescribed *"worktrees OUT of /tmp"*, and
`docs/lessons/perishable-input-is-what-makes-a-wave-urgent.md` records the 2026-09-16 reboot that
"reaped all of `/private/tmp`", taking one wave's in-flight patch. **Landed: `e2d8c9816`.**
Residual, deliberately not done: relocating the ten surviving `/tmp` worktrees. `git worktree move`
is the right verb (it preserves the gitignored and uncommitted content a remove+re-add destroys —
this is the one place forest's `rename.rs` idea applies), but liveness must be re-read at the moment
of the move.

**#1 — record the blast radius on the landed removal lane. Conviction 90.** `worktree-gc.sh` has
three removal actuators; the dispose lane (`:1084`) reads `ignored_inventory` at `:1056` and writes
`log_disposal` at `:1090`, the dirt lane (`:1236`) does the same at `:1226`/`:1249`, and the
**landed lane (`:1275`) does neither** — verified. 64 of 86 live worktrees carry gitignored content
that `git worktree remove` deletes at exit 0 with no `--force` and no warning; the log holds 148
`remove` lines and 0 `dispose` lines over 7 sweeps. ~5 lines at `:1274-1279` mirroring `:1226`/`:1249`.
Do NOT add forest's refusal arm — `:858-864` measured that a KEEP gate on ignored content makes
oracle 3 inert. Honest payload: mostly `__pycache__`/`node_modules`, with two real items. Filed open
as backlog `ef5f9ea26926`.

**#2 — put the un-ownable residue on the machine line. Conviction 88.** `worktree-gc.sh:1450` emits
12 named fields and carries neither `unowned=` nor `owner_active=`; `grep -o 'unowned='` over the
log returns **nothing**, while the human prose at `:1467-1472` has printed the 15-worktree line in
7 of 7 sweeps, each followed by `--warrant <path>` with a **literal unresolved `<path>`** — a
Manual-Command-Delivery violation on a surface read nightly. Caveat that must ship with it:
`worktree-gc-infra-run.sh:506` extracts five named fields positionally, so a new field is readable
by `_f` but reaches no surface unless also added to `_eff` at `:522` — the adjacent
`stranded_patches` field has read `n-a` on 7 of 7 rows ever written. Add the field *and* the `_eff`
entry, or you have built another `n-a`.

**#3 — unset the routing env before a verdict-producing child reads it. Conviction 78 → now ~90.**
Forest's real transferable rule (`src/git.rs:7-20`, scrubbed at `:473`, `:661`). `ship-land.sh:5011`
exports `GIT_INDEX_FILE` and `:5013-5016` `git add -N`s every untracked file into it, process-wide;
`loaded-untracked-lint.sh:76` is `git ls-files --others --exclude-standard`. The workflow left the
inversion DERIVED; it is now **measured**: in a throwaway repo, `ls-files --others` printed `f.txt`
before `git add -N f.txt` and **nothing** after. So `--precheck --working` — the one mode built to
bring untracked files into scope — is the one mode where the untracked-file lint reports GREEN over
its own population. Fix: `unset GIT_INDEX_FILE GIT_DIR GIT_WORK_TREE` at the top of `lint_repo()`,
plus `env -u GIT_INDEX_FILE` on `ship-land.sh:3137`'s selftest spawn. Must ship with a red-proof.

**Free, unrelated to forest:** `.worktreeinclude` is documented in resident global CLAUDE.md, exists
in 6 other repos here (`doc_classifier`, `reso-management-app`, `reso-management-app-release`,
`reso-qa-runner`, `dc-corpus`, `dc-wiring`) and **does not exist in claude-infrastructure**.

**Declined, with the price stated.** The gate reorder at `handoff-fire.sh:10255-10268` is a genuine
defect, but `handoff-fire.sh` is 134 fix/revert of 210 commits (63.8%) in 90 days, the ff arm has
fired 28 times and the occupancy refusal below it has fired **zero times ever**. Same for the
`cloud-reconcile.sh:703` CAS (75% fix rate, and it leaves `:413`'s unguarded `fetch --force`).

## 7. Unverified, and the command that settles each

| claim | status | settling command |
|---|---|---|
| Every git-forest behavioural claim | **never executed** — all 60 passes are code reads | `cd <clone> && cargo test --locked --all-features` |
| Our `read-tree` probe catches an IGNORED path the advance ADDS | from two flags, never run | add `@test "L8e …"` after `tests/deploy-live.bats:1767`, `bats -f L8e` |
| Whether the `handoff-fire` freshness/occupancy inversion ever bit | 28 ff events, 0 occupancy refusals ever | no read settles it — the instrument is itself the change |
| `git worktree move -f` preserves gitignored content on the dirty `/tmp` trees | inferred from the flag's usage line | move ONE clean tree first and diff |

`git add -N` blinding `ls-files --others`, and the worktree-harness comparison, were listed
unverified by the workflow and are **settled above**.
