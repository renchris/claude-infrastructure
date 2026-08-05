# Git identity contamination — blast radius and repair options

**Date:** 2026-08-05 · **Mode:** read-only census (no writes to git, no history touched)
**Subject:** the test-fixture identity `t <t@t>` authoring/committing real commits in two repos
**Canonical identity:** `Chris Ren <ren.chris@outlook.com>` (GitHub user `renchris`)

---

## 0. Headline

| | commits carrying `t@t` (all refs) | **pushed** to GitHub | of which on the **default branch** | local-only |
|---|---|---|---|---|
| `claude-infrastructure` | 46 | **9** | **9** (`origin/main`) | 37 |
| `reso-management-app` | 3,396 | **349** | **214** (`origin/main`) | 3,047 |

Both contaminated regions are **contiguous tails** of their default branch — the newest
9 commits of `claude-infrastructure/main`, and the newest 214 of
`reso-management-app/main`. Everything older is clean.

**The leak is already closed at the config layer** (see §4): neither repo carries a local
`user.name`/`user.email` override today; both resolve to `~/.gitconfig` →
`Chris Ren <ren.chris@outlook.com>`. New commits are already attributed correctly.

---

## 1. Blast radius

### 1.A `claude-infrastructure`

- Layout: `.git` in the repo root (not bare), **138 linked worktrees**, 246 local branches,
  2 remote branches. Remote `https://github.com/renchris/claude-infrastructure.git`.
- Identity census across **all** refs (`%ae|%ce`, 9,336 commits):

  ```
  9265 ren.chris@outlook.com|ren.chris@outlook.com
    46 t@t|t@t
    14 ren.chris+claude@outlook.com|ren.chris@outlook.com
     5 ichris96+claude@hotmail.com|ren.chris@outlook.com
     4 ren.chris+claude@outlook.com|ren.chris+claude@outlook.com
     2 ichris96+claude@hotmail.com|ichris96+claude@hotmail.com
  ```

- **All 46 `t@t` commits have author == committer == `t <t@t>`.** No split-attribution case here.
- Date range of the 46: **2026-08-05 03:23:28 −0700 → 2026-08-05 13:06:03 −0700** (a single day).
- **Pushed: 9**, all reachable from `origin/main`, and they are exactly `origin/main~0..origin/main~8`
  — the branch tip. Full list (newest first):

  | short sha | full sha | author date | subject |
  |---|---|---|---|
  | `65b6290a` | `65b6290a741fab1572eafe521e68ddfab70c1cf6` | 2026-08-05 12:57:02 −0700 | fix(claude-md): ship policy delegates landing cost to the target repo, never restates it |
  | `c3b10572` | `c3b1057213d1f5ca673da756dbffa66e6421168f` | 2026-08-05 12:56:46 −0700 | docs(readme): compressor-panic causal-chain diagram … |
  | `47ead9b8` | `47ead9b8414969d82932aa41c5c99218edc27787` | 2026-08-05 12:50:07 −0700 | docs(readme): the machine-death class — macOS compressor-segment panics … |
  | `be65d4db` | `be65d4db3e26ca4855165ce6675399ddd782593f` | 2026-08-05 12:44:09 −0700 | chore(fleet): compressor-sentinel manifest row staged→run … |
  | `8f19f909` | `8f19f909f84f71e615fc62c35a8ae4598d2514d1` | 2026-08-05 12:42:12 −0700 | fix(activation): 31-compressor-sentinel foreign-writer check excluded the daemon but not ITSELF … |
  | `388909ca` | `388909ca52e9d93ffa213bae141d1f528bbed865` | 2026-08-05 12:36:55 −0700 | docs(compact-memory): the two-tier hot/cold split was undocumented … |
  | `4353c85f` | `4353c85f9ed39820f993c3de47e857ccb19e057b` | 2026-08-05 12:34:13 −0700 | fix(handoff-fire): daemon/headless callers now detect a live kitty … |
  | `3a4642b5` | `3a4642b5fa23a1602eaae07ff41bb37c1082d5e0` | 2026-08-05 12:33:40 −0700 | fix(handoff-fire): a missing desk-role file printed a shell error … |
  | `29b7a1b5` | `29b7a1b526ab146285c3f0f2dfc728ba0e4c4ca6` | 2026-08-05 10:54:06 −0700 | fix(cc-blockers tests): the suite executed the operator's live reap alarm, once per test |

  (`29b7a1b5` is the oldest pushed contaminant; `29b7a1b5^..origin/main` = exactly 9 commits.)

- **Local-only: 37.** These live almost entirely in the repo's own session machinery —
  `refs/checkpoints/<session>/<ts>`, `refs/wip/<session>/LAST`, `ship/backup-8184738f`, and a
  handful of dangling `a`/`b` fixture commits on a branch named `up`. None of these refs are
  pushed and none are user-facing; they will age out with the checkpoint machinery.

### 1.B `reso-management-app`

- Layout: `.git` in the repo root, **75 linked worktrees**, 373 local branches, 38 remote
  branches. Remote `git@github.com:renchris/reso-management-app.git`, default branch `main`
  (`refs/remotes/origin/HEAD → refs/remotes/origin/main`).
- Identity census across **all** refs:

  ```
  10492 ren.chris@outlook.com|ren.chris@outlook.com
   3393 t@t|t@t
      3 ren.chris@outlook.com|t@t      ← split attribution (author OK, committer wrong)
      2 ichris96@hotmail.com|ichris96@hotmail.com
      2 57972348+renchris@users.noreply.github.com|noreply@github.com
  ```

- Census on `origin/main` (5,590 commits total):

  ```
  5372 ren.chris@outlook.com|ren.chris@outlook.com
   211 t@t|t@t                          ← author AND committer wrong
     3 ren.chris@outlook.com|t@t        ← committer only
     2 ichris96@hotmail.com|ichris96@hotmail.com
     2 57972348+renchris@users.noreply.github.com|noreply@github.com
  ```

  **214 contaminated commits on `origin/main` = 3.8% of the branch.** They occupy positions
  1–214 from the tip: positions 1–211 are author+committer `t@t`, positions 212–214 are the
  author-correct/committer-wrong trio. `d888000e1^..origin/main` = exactly 214 commits, i.e.
  every commit in that window is affected.

- **Date range on `origin/main`: 2026-07-26 19:08:52 −0700 → 2026-08-05 13:06:03 −0700** — ten days.
- The three **committer-only** cases (author correctly `ren.chris@outlook.com`, committer `t@t`
  — the signature of a rebase/cherry-pick performed by a `t@t`-configured session):

  | short sha | date | subject |
  |---|---|---|
  | `739b5499c` | 2026-07-26 23:40:20 | fix(admin): hold the settings rail on its pin at the end of the scroll |
  | `1661326df` | 2026-07-26 19:10:07 | fix(admin): center the Groups status dots via a shared StatusDot |
  | `d888000e1` | 2026-07-26 19:08:52 | fix(admin): pin the settings rail to the viewport on lg+ |

  GitHub will show these with the *correct* author avatar (author is what the commit list
  attributes) but a `t` committer badge on the commit detail page.

- **Pushed beyond `main`: 135 further `t@t` commits** are reachable from other `origin/*`
  branches but not from `origin/main` (349 remote-reachable − 214 on main). These are open/stale
  feature branches on GitHub.
- **Local-only: 3,047** — checkpoint/wip/backup refs and unmerged local branches.

  Full pushed-sha lists are not reproduced here for reso (214 + 135 entries); regenerate with:
  `git log origin/main --format='%h %ae %ce %s' | awk '$2=="t@t"||$3=="t@t"'`.

### 1.C Every other repo under `~/Development`

Scanned all 191 git repos under `/Users/chrisren/Development` for
`t@t | tester@ | @example.com | selftest | @e.com | test@test | @localhost`:

- `wt-cc-queue`, `wt-kitty-term`, `wt-mailbox-key`, `wt-terminal-arm`, `wt-terminal-land`,
  `wt-tmux-isid` — **not separate repos**; all six are linked worktrees whose
  `git-common-dir` is `claude-infrastructure/.git`. Same 46 commits, counted once.
- `reso-design-automation`, `reso-playwright`, `reso-qa-runner` — likewise linked worktrees of
  `reso-management-app/.git`. Same 3,396 commits, counted once.
- All remaining hits are **upstream third-party authors in vendored/cloned OSS repos**, not the
  operator's commits: `t@tobiasjordans.de` (next.js, zod, tailwindcss.com — a real contributor
  whose address merely resembles `t@t`), `your.email@example.com` (voiceink — upstream author
  "Deborah Mangan"), `muralikrishna@localhost` (supabase), `git@terron.me`, `*@theqtcompany.com`,
  `matt@tighten.co`, `albert@tugraz.at`, `gwenael.larmet@teamto.com`.

**Census is therefore complete: exactly two affected repos.**

---

## 2. Any other wrong identity?

**No.** On real commits in either repo the only non-canonical identities are:

| identity | where | verdict |
|---|---|---|
| `t <t@t>` | both repos | **the contamination** |
| `ren.chris+claude@outlook.com` | claude-infrastructure, 18 commits (7 on `origin/main`) | operator's own plus-alias. Attributed on GitHub **only if** that exact address is added+verified on the `renchris` account; otherwise it renders unlinked too. Worth checking in GitHub → Settings → Emails. |
| `ichris96+claude@hotmail.com` | claude-infrastructure, 7 commits (7 on `origin/main`) | same — operator alias, same caveat. |
| `ichris96@hotmail.com` | reso, 2 commits on `origin/main` | operator's older address, same caveat. |
| `57972348+renchris@users.noreply.github.com` | reso, 2 commits on `origin/main` | GitHub-issued noreply — **always correctly linked**, nothing to fix. |

The other fixture identities that exist in this codebase — `tester@example.com`
(`tests/land-verify.bats`, `tests/land-gate-cas.bats`), `t@e.com` (11 bats files),
`sib@example.com`, `b@example.com` — appear **only in test source**, never in commit metadata of
either repo. `pv@selftest.local` does not appear anywhere in either repo's commit metadata or tree.
No leak from those.

---

## 3. Repair options

### The fact that decides this

Verified against GitHub's own documentation and a GitHub-staff answer, not assumed:

- **GitHub does not read `.mailmap`. At all.** GitHub staff, community discussion #22518
  (July 2020, still the standing answer as of 2026): *"Unfortunately at the present time, GitHub
  does not support using mailmap files. We do have an open feature request for this."* The
  discussion has run ~6 years without implementation. GitHub's own suggested workaround in that
  thread is history rewriting.
- The contributions-graph doc
  (*Troubleshooting missing contributions* / *Why are my contributions not showing up*) states the
  rule positively and never mentions mailmap: a commit is linked and counted **iff** it was
  authored with an email connected to the account (or the GitHub `noreply` address), **and** it is
  on the default or `gh-pages` branch of a non-fork.
- Therefore the cheap escape hatch — *add the bad address to your GitHub account and let it
  retroactively link* — **is unavailable here**: `t@t` is not a deliverable address (no valid TLD),
  so GitHub cannot send it a verification mail and will not accept it as an account email.

**Net: nothing except a history rewrite changes what GitHub displays.**

### Option 1 — commit a `.mailmap`

**What it fixes:** local/CLI tooling only, and only where mailmap is honoured —
`git shortlog -sne`, `git log --use-mailmap` / `git log --format=%aN <%aE>`, `git blame`
(mailmap-aware since 2.20), `git check-mailmap`, and any downstream tool that shells out to those
(cgit, some changelog generators, `git-cliff` with mailmap enabled).

**What it does NOT fix — the entire stated problem:**

- the GitHub **commit list** and commit detail pages (still `t`, still unlinked, still a grey
  generic avatar);
- the GitHub **contributions graph** (those 214 + 9 commits stay off the operator's graph forever);
- the repo **Contributors** graph / Insights (`t` remains a separate contributor row);
- `git blame` **in the GitHub UI**, PR author attribution, `@`-mention linking, and the REST/GraphQL
  `author.user` field (which resolves by email→account, ignoring mailmap).

**Verdict:** worth committing as hygiene and as a durable, greppable record of the alias set —
but it is **not a fix for GitHub attribution**, and describing it as one would be false. Content in §5.

### Option 2 — `git filter-repo --mailmap` (or `--commit-callback`) + force-push

**What it fixes:** everything. Rewritten commits carry `Chris Ren <ren.chris@outlook.com>`, GitHub
re-links them on push, and they enter the contributions graph (per the doc above, subject to the
default-branch rule and up to 24h lag).

**Concrete cost in *this* situation:**

| cost | `claude-infrastructure` | `reso-management-app` |
|---|---|---|
| commits whose sha changes | 9 (the whole contaminated tail) | 214 on `main`, + up to 135 more if the other pushed branches are included |
| **linked worktrees stranded on pre-rewrite shas** | **138** | **75** |
| local branches to re-anchor | 246 | 373 |
| remote branches to force-push | 2 | 38 (or a partial rewrite that permanently forks them from `main`) |
| force-push to `main` required | **yes** | **yes** |

Plus the repo-specific damage that makes this materially worse than the raw counts suggest:

- **`claude-infrastructure` is the symlink source for the live `~/.claude` layer.** A rewrite +
  force-push desynchronises every worktree that holds staged/uncommitted work, and this repo's own
  project `CLAUDE.md` already documents an incident (2026-07-11, `dfacccd`) where a *routine* land
  in a sibling worktree silently dropped five files. A 138-worktree force-push is that failure mode
  deliberately, at scale.
- **`reso-management-app` stores commit shas as data.** Its landing/deploy machinery keys on refs
  and shas (land-lock, `gate-green`, land-log, Path F's watched `refs/heads/release`,
  `postland-verify` stamps), and its **own `CLAUDE.md` cites `fb76c35bb` by sha at line 420** — a
  commit inside the rewrite window. Every such pointer becomes a dangling reference, in exactly the
  way this repo's memory already records ("Key type fakes a dangling record"). The `docs/research/`
  and `docs/plans/` corpus likewise cites landed shas throughout the 10-day window.
- Anything already referenced externally — a GitHub permalink, a PR body, a deploy record — 404s.
- `git rerere` caches, `refs/checkpoints/*`, `refs/wip/*` and `ship/backup-*` all keep the old
  objects alive locally, so the "cleanup" is not even clean without a `--force` gc.

**Verdict:** technically straightforward (contiguous tails, `--mailmap` handles author *and*
committer in one pass) and disproportionate. The repair is larger and riskier than the defect.

### Option 3 — leave history, fix forward

**What it fixes:** all future commits — which, as measured in §4, is **already true**: the local
`user.*` override is gone from both repos and both now resolve to `~/.gitconfig`.

**What it leaves broken:** 223 commits (9 + 214) on two default branches display as an unlinked
`t` and never enter the contributions graph. 135 more sit on stale reso feature branches.

**Cost:** zero.

---

## RECOMMENDATION

**Option 3 — leave history as-is — plus the §4 hardening, plus the §5 `.mailmap` committed as
local-tooling hygiene and NOT sold as a GitHub fix.**

Reasoning, sized to what these repos actually are:

1. **The only repair that touches the stated symptom is Option 2, and its cost is denominated in
   the thing these repos are least able to absorb.** 213 live linked worktrees across the two repos
   are anchored to pre-rewrite shas; both repos have documented, already-experienced failure modes
   around exactly that (silent commit loss in `claude-infrastructure`; sha-keyed deploy/gate state
   in reso). Trading a cosmetic attribution defect for a real risk of losing work is a bad trade.
2. **The damage is cosmetic and bounded.** These are single-contributor personal repos. Nobody is
   mis-credited; no one else's work is attributed to `t`. The only concrete loss is 223 squares of
   contribution graph over an 11-day window, in a repo whose value is not its graph.
3. **The window is closed and small.** Contamination is confined to 2026-07-26 → 2026-08-05 and to
   contiguous branch tails. It is not spreading; §4 confirms new commits are already correct.
4. **Option 1 is not a substitute and must not be presented as one.** Committing `.mailmap` is
   still worth doing — it makes `git shortlog`/`blame` locally correct, canonicalises the four
   operator aliases, and leaves a self-documenting record of this incident — but if the goal is
   "GitHub stops showing `t`", `.mailmap` achieves exactly nothing.
5. **If the graph matters more than the risk**, the *only* defensible partial is
   `claude-infrastructure` alone: 9 commits, a clean tip-tail, 2 remote branches, and a rewrite
   base one commit deep. Even there it requires re-anchoring 138 worktrees, so it should be done
   with every worktree quiesced and committed, never opportunistically. reso should not be rewritten.

---

## 4. The leak: current state and hardening

**Current state, measured:**

```
$ git -C claude-infrastructure config --show-origin --get-all user.email
file:/Users/chrisren/.gitconfig   ren.chris@outlook.com
$ git -C reso-management-app  config --show-origin --get-all user.email
file:/Users/chrisren/.gitconfig   ren.chris@outlook.com
```

Neither repo has a local `[user]` block, neither has `extensions.worktreeConfig` or any
`config.worktree` file, no `GIT_AUTHOR_*` / `GIT_COMMITTER_*` are exported, and `~/.gitconfig`
has no `includeIf`. **The override has already been removed.** Going-forward attribution is
correct with no further action.

**Likely vector (named, not asserted):** `claude-infrastructure/tests/` contains **34 sites** that
run a *bare* `git config user.email …` — i.e. writing to whatever repo the process cwd resolves to
— after an **unguarded `cd`** into a temp dir. Representative:

```bash
# tests/gate-manifest.bats:226-227
repo="$BATS_TEST_TMPDIR/repo"; mkdir -p "$repo"; cd "$repo"
git init -q; git config user.email t@t; git config user.name t
```

If that `cd` ever fails (or the temp dir is gone), the very next line writes `user.email = t@t`
into the *checkout's* `.git/config` and it persists for every subsequent commit — which matches
the observed 10-day reso window exactly. `bin/cc-teardown-safety-gate.sh:128` uses the same
identity but is correctly `-C`-scoped. reso's own tests have **zero** bare-config sites.

**Hardening worth doing (not done here — this was a read-only census):**

1. Convert the 34 bare sites to `git -C "$repo" config …`, or better to per-invocation
   `git -c user.email=t@t -c user.name=t commit …`, which **never writes config at all**.
   Several files already use that safe form (`desk-assert.bats`, `branch-reaper.bats`, `cc-tlid.bats`).
2. Make every `cd "$dir"` in the bats suite `|| return 1`.
3. Add a commit-time guard: reject a commit whose author or committer email is not in an allowlist
   (`ren.chris@outlook.com`, `*+claude@outlook.com`, `*@users.noreply.github.com`). This is the
   chokepoint fix — a hook that refuses catches the leak on commit #1 instead of commit #214.

---

## 5. `.mailmap` — exact content (for local tooling only; NOT created by this report)

Place at the repo root of each repo. Identical content works for both; the reso file may drop the
`+claude` aliases (they do not occur there) and the `claude-infrastructure` file may drop
`ichris96@hotmail.com`. Keeping both lists complete in both files is harmless and future-proof.

```
# .mailmap — canonicalise commit identities for mailmap-aware git tooling.
#
# SCOPE: this file affects `git shortlog`, `git log --use-mailmap` / %aN/%aE,
# `git blame`, and `git check-mailmap` ONLY. GitHub does NOT read .mailmap
# (GitHub staff, community discussion #22518; open feature request since 2020),
# so the GitHub commit list, contributor graph and contributions calendar are
# UNAFFECTED by anything below. See docs/research/git-identity-blast-radius-2026-08-05.md
#
# Format:  Proper Name <proper@email>  Commit Name <commit@email>

# --- test-fixture identity that leaked into a local .git/config, 2026-07-26 → 2026-08-05 ---
Chris Ren <ren.chris@outlook.com> t <t@t>

# --- the operator's own alias addresses ---
Chris Ren <ren.chris@outlook.com> <ren.chris+claude@outlook.com>
Chris Ren <ren.chris@outlook.com> <ichris96+claude@hotmail.com>
Chris Ren <ren.chris@outlook.com> <ichris96@hotmail.com>
Chris Ren <ren.chris@outlook.com> <57972348+renchris@users.noreply.github.com>
```

Note the first entry uses the four-field form (`Proper <proper> Commit <commit>`) because the
committed *name* is `t`, not just the address; the remaining entries use the two-field
email-only form since the committed name is already correct.

---

## Sources checked

- [GitHub Docs — Why are my contributions not showing up on my profile / Troubleshooting missing contributions](https://docs.github.com/en/account-and-profile/setting-up-and-managing-your-github-profile/managing-contribution-settings-on-your-profile/why-are-my-contributions-not-showing-up-on-my-profile)
- [GitHub Community Discussion #22518 — "How to get mailmap to work and record contributions in relevant user's profile?"](https://github.com/orgs/community/discussions/22518) (GitHub staff: mailmap unsupported)
- [GitHub Docs — Viewing a project's contributors](https://docs.github.com/en/repositories/viewing-activity-and-data-for-your-repository/viewing-a-projects-contributors)
- Local: `git log --all --format='%ae|%ce'`, `git log --remotes=origin`, `git for-each-ref --contains`,
  `git config --show-origin`, `git worktree list`, full repo sweep of `/Users/chrisren/Development`.
