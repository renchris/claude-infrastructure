# A3 · Pricing four cloud-VM configuration changes

Measured 2026-09-10 against `~/.claude/autonomy/backlog.jsonl`, `bin/cc-eligible` (re-run per row,
not read off the census), the Anthropic control plane (GETs only), and the official
`code.claude.com` docs. Read-only throughout; the private ref namespace `refs/cc-research-a3/*` was
created, read, and deleted (verified 0 refs remaining).

---

## THE HEADLINE, BEFORE THE TABLE

**All four changes together move 13 rows from refused to eligible. Zero are claimed. 86 are
blocked. Of the 13 open, 9 are `project=personal` and 7 of those are phone calls, a Zelle transfer
and a PayPal payment.** The genuinely agent-drainable incremental yield is **4 rows**, all
`sevenrooms-bridge`, all unlocked by change 1 alone.

Baseline for scale: the cloud tap's *current* agent-drainable supply is **7 rows** — the `eligible`
bucket is 22 rows, of which 15 are blocked, 2 claimed, 5 open (`/private/tmp/claude-501/-Users-chrisren-Development--worktrees-cloud-lane-research/dc4eb0fa-3191-4b17-acc3-c3a1e6050e33/scratchpad/eligible-sweep.json .eligible`).

**Two of the four changes are already made and are not costed as work:**
`gh` is pre-installed in every cloud VM and pre-authenticated by the GitHub proxy (change 3), and
`git fetch --unshallow` has been run successfully inside a real cloud VM and the evidence is a
landed commit body (change 2). What remains in both cases is deleting a stale refusal in
`bin/cc-eligible`, not provisioning anything.

---

## THE TABLE

Rows counted with the rule **"a row becomes eligible iff EVERY class it fires is cleared"** — the
census buckets by *leading* verdict only, and 18 of the 22 `visual` rows fire 2-4 classes. Derived
by re-running `bin/cc-eligible why <id> --json` on all 126 rows in the four classes plus the
eligible bucket (`/private/tmp/claude-501/-Users-chrisren-Development--worktrees-cloud-lane-research/dc4eb0fa-3191-4b17-acc3-c3a1e6050e33/scratchpad/work-A3/why-all.jsonl`).

| # | change | rows unlocked open / claimed / blocked | verified (citation) | unverified | eng. cost | operator steps | risk |
|---|---|---|---|---|---|---|---|
| **1** | Attach the item's own repo (`--repo` per item) | **9 / 0 / 58** — but 7 of the 9 open are `personal` operator-only actions and `personal` has **no GitHub repo at all**; genuine agent-drainable yield **4** (all `sevenrooms-bridge`) | Control plane returns **HTTP 200** for `renchris/{reso-management-app, doc_classifier, sevenrooms-bridge, pivot-table-library}` on `/api/oauth/organizations/<org>/code/repos/<repo>`, account next3, with a **negative control** (nonsense repo → 404). Docs: *"a cloud session can access any repository the connecting GitHub account can see, not just the repositories the Claude GitHub App is installed on"* (code.claude.com/docs/en/claude-code-on-the-web § GitHub authentication options). `renchris/personal` → **404**; local `~/Development/personal` has **no `origin` remote**. The site is `bin/cc-offload:84` `REPO="${CC_OFFLOAD_REPO:-$ROOT}"` + `:690-693` slug derivation; `--repo` already exists (`scripts/cloud-create-api.py:454`) | whether a VM given `reso-management-app` can do reso work at all (needs Turso creds + a live DB; see § 1 risk); whether `cc-offload`'s FOREIGN-REPO GATE (`bin/cc-offload:409-438`) retargets cleanly rather than needing rewrite | **6-10 h.** `bin/cc-offload` (REPO selection + the two-arm foreign-repo gate), `bin/cc-eligible` (`cross_repo()` at `:1239` must become *"the project has no GitHub remote"*, not *"≠ the lane repo"* — `cloud_repo()` `:955-968` derives the lane from its own checkout), `bin/cc-dispatch` (worktree/branch per repo) | none for the 4 sevenrooms rows. For reso: add Turso/API credentials to the cloud environment — **GUI-only** (§ Operator-step reality below) | attaching reso mints `eligible` for 47 rows that are all blocked and all operator-owned; a wrong `eligible` is silent by construction (`bin/cc-eligible:44-49`) |
| **2** | Full-depth clone (`git fetch --unshallow` in the VM) | **2 / 0 / 2** — and **both open rows were already worked by cloud sessions on 09-09 and 09-10**; genuine new yield **0-2** | **The VM side is DONE and PROVEN.** `bin/cc-dispatch:3126` `staleness_rail` instructs the unshallow (landed `22b8824c6`, 2026-09-01). A cloud session executed it: commit `26af2dc3b` (branch `claude/fire-20260909T004425Z-75839-1`) body reads verbatim *"Checkout arrived shallow at depth 50 and was unshallowed first"*; a second branch body reads *"after `git fetch --unshallow` — at depth 50 every trunk read"*. Container-level control: `docs/research/cloud-shallow-horizon-2026-08-29.md` §1 — `rev-list --count origin/main` 50 → 3832 across one `--unshallow` | that every fire runs it (the rail is prose with **no assert-and-abort interlock**, which §A2b explicitly prescribed); that depth is always 50 (two instances now, not a fleet measurement — §5 *Honest limits*) | **1-2 h.** `bin/cc-eligible:756-761` `CLOUD_DEPTH=50` → retire or raise; `bin/cc-dispatch` add the abort-if-still-shallow assertion §A2b prescribed | none | raising `CLOUD_DEPTH` without the interlock mints cloud labels for work the VM still cannot see — §A2b calls this "the §5 anti-goal exactly" |
| **3** | `gh` CLI + token in the VM | **0 / 0 / 1** | **Already present, zero cost.** Docs § Installed tools: *"Utilities: git, gh, jq, yq, ripgrep, tmux, vim, nano"* and *"GitHub's `gh` CLI is pre-installed… `gh` reads `GH_TOKEN` automatically, so you don't need to run `gh auth login`"*; the GitHub proxy substitutes real credentials outbound. The one row `a7460321494d` is **blocked** and is a *decision* (*"Decide: renchris/pivot-table-library commits as 'contributors@pivot-table.dev'…"*), not a capability gap | nothing material | **0.5 h.** `bin/cc-eligible` `GITHUB` class — its description *"no gh CLI off-box"* is factually false today. Narrow or retire | none | the proxy's **repo scope** (*"GitHub API… requests reach only repositories attached to the session"*) and its **GraphQL restriction** (*"a pinned set of GraphQL operations… `This GraphQL query is not enabled for this session`"*, applies even to a `GH_TOKEN` you set) mean retiring the class wholesale re-opens cross-repo GitHub reads that will 403 |
| **4** | Headless browser + dev server | **0 / 0 / 3** | Class overlap: only **3** of the 22 visual rows fire `visual` alone; the other 19 also fire cross-repo / deep-history / branch-banking / external-deploy. Seeded sample of 6 (`random.seed(20260910)`) — **6 of 6 would not be fixed by a browser**: production session **cookie** the operator must supply (`3e3177d8c377`); a **real locally-registered passkey** (`72fba915d597`); an **aesthetic ruling** on banner placement (`38b79edd0e90`); a comment on an **unlanded 39-commit branch** (`420af2f142dd`, also branch-banking); an operator **sign-off** (`a87519d6dde5`); and a **false-positive token** — `render` matching a shell env-map renderer in `preflight-golive.sh` (`c6d897731567`) | **whether a browser can even be installed**: the docs' tool table lists `chromedriver` but **no Chrome/Chromium**, and there is **no in-repo measurement of a browser in a cloud VM** (grep of `docs/research/cloud-*`, `CLOUD_BACKLOG_PIPELINE.md` → 0 hits). Install would be a setup script under a **5-minute** cap | **unbounded, ≥12 h** and not the binding constraint — the rows are not browser-shaped | environment dialog is **GUI-only** at claude.ai/code (*"There's no settings page or direct URL for the selector"*) | building a rendering capability for a class whose members need credentials, a passkey, a local branch, or the operator's eyes |

---

## Per-change evidence chains

### 1 · Attach the item's own repo — the only change with real yield, and it is 4 rows

**The shape is per-session repo SELECTION, not multi-repo.** Official docs, verbatim: *"`--cloud`
works with a single repository at a time."* `scripts/cloud-create-api.py:376` sends
`"sources": [source]` — a one-element list mirroring the binary's own
`session_context.sources: v?[v]:[]`. Nothing verified says the API accepts two.

**Access is verified positively, with a control.** Five GETs to
`/api/oauth/organizations/1a71eca0-…/code/repos/<owner>/<repo>` under account next3:

```
200  renchris/claude-infrastructure   200  renchris/reso-management-app
200  renchris/doc_classifier          200  renchris/sevenrooms-bridge
200  renchris/pivot-table-library     404  renchris/definitely-not-a-repo-xyz   ← negative control
404  renchris/personal
```

`gh api /user/installations` **refuses** (HTTP 403, *"You must authenticate with an access token
authorized to a GitHub App"*) — gh holds a `gho_` CLI-OAuth token, not a GitHub App user token. That
refusal is uninformative anyway: the docs say App installation *"is not a session-level access
control."* The control-plane GET is the instrument that answers the question, and it did.

**Where the yield goes.** 95 rows fire `cross-repo` (77 lead with it). By project:

| project | rows | status |
|---|---|---|
| reso-management-app | 47 | **47 blocked, 0 open** |
| personal | 34 | 27 blocked, **7 open** — and no GitHub repo exists |
| sevenrooms-bridge | 6 | 2 blocked, **4 open** ← the entire real yield |
| doc_classifier | 4 | 4 blocked |
| reso | 3 | 3 blocked |
| lakehouse-lecture | 1 | 1 blocked |

The four sevenrooms rows are `b44d993ecdc4` (CI runs no test suite — 618 tests gate nothing),
`3c3bdc5be447` (un-narrated sidecar restarts), `45a0073b9ea4` and `c6d897731567` (two
`preflight-golive.sh` flakes). All four pass `cc-premise check` → `verdict=clear`.

**Blocked rows are the operator's whatever the venue, and their block reasons prove the change is
irrelevant to them.** Last-`block` `needs` text for the 68 blocked cross-repo rows, bucketed: 14
physical/GUI (*"Work phone: Settings > Privacy & Security >"*, *"Phone call to Ahmed"*,
*"Run 'sudo pmset -a powermode 1'"*), 7 credential (*"Set TURSO_AUTH_TOKEN_ASHBURN_GROUP"*), 4
explicit value calls (*"Your product call"*, *"Pricing call, yours"*), 43 other operator prose.
**Zero name cross-repo as the blocker.** The one I read end-to-end (`dcd894ef1cb5`) is blocked on a
*stale local worktree* — `"pre-existing worktree /Users/chrisren/Development/.worktrees/wt-dcd894ef1cb5
is behind origin/main and cannot be fast-forwarded"` — a box condition attaching a repo cannot touch.

### 2 · Full-depth clone — already done in the VM; the refusal is ours

The §A2b blocker, verbatim (2026-08-11): *"Named blocker, and the 15-row unlock is CONDITIONAL until
it clears: **nobody has run `git fetch --deepen` inside a cloud VM.**"* That is **refuted**, twice:
a container-level `--unshallow` on 2026-08-29 (`docs/research/cloud-shallow-horizon-2026-08-29.md`
§1: `rev-list --count origin/main` 50 → 3832; `merge-base --is-ancestor a42f107a origin/main` rc 1 →
rc 0), and an in-VM run on 2026-09-09 recorded in a landed commit body (`26af2dc3b`).

**§A2b's own numbers no longer hold and should not be re-quoted.** It claimed *"every one of the 14
live open `deep-history` items has exactly one class firing — so the deepen unlocks all of them and
double-refuses none."* True when the `CROSS_REPO` / `FOREIGN_TREE` arms did not exist (added
2026-08-23/24). Today **21 rows fire `deep-history` and only 4 fire it alone**: `cross-repo+dh` 10,
`cross-repo+dh+visual` 3, `branch-banking+cross-repo+dh+visual` 3, `dh+visual` 1. The deepen alone
unlocks 4 of 21, and 2 of those 4 are blocked.

**Both open deep-history rows have already been driven off-box.** `8e67a1fa2d40` was worked by a
cloud session on 09-09 whose commit says the cure landed *19 h before its row was dispatched* and
that the row is a **DUPLICATE** of `b0ee53b5f737`; `9f8a985115a9` was worked on 09-10
(`c9790b29a`, *"fix(read-twitter): the test loader imports importlib.machinery it references"*).
So the eligible-vs-drained gap here is a *return-path* problem, not a horizon problem.

Incidental, useful: the same session recorded *"bats-core cloned to the scratchpad (no bats on this
VM)"* — the docs' tool table indeed omits `bats` and `shellcheck`, which is what
`scripts/cloud-venue-provision.sh` exists to install. A setup script would make that permanent via
the environment cache (docs: *"the environment cache keeps what the setup script installs"*).

### 3 · `gh` in the VM — the class is a stale spelling, not a capability gap

`bin/cc-eligible:456` describes the class as *"NEEDS GITHUB beyond the one cloned repo — no gh CLI
off-box."* The second clause has been false for as long as the docs have described the environment.
Both halves of the fix are one edit each; neither buys an agent-drainable row.

The *first* clause is still true and is the reason not to retire the class outright: the GitHub
proxy scopes API reads to **repositories attached to the session**, so `a7460321494d`'s subject
(`renchris/pivot-table-library`) is reachable only if that repo is the attached one — i.e. this row
is really a change-1 row wearing a change-3 label. Its actual blocker is that it is a **decision**.

### 4 · Headless browser + dev server — the class is not browser-shaped

The seeded sample is in the table. Two structural points behind it:

- **The `visual` bucket is 22 rows but only 3 fire `visual` alone.** A browser clears the *leading*
  verdict on 19 rows that stay refused for a second reason.
- **The tokens that fire the class are frequently false positives**, exactly as §A2b's closing
  parenthetical warned: token histogram over the 22 rows is `visual` 4, `render` 4, `css` 4,
  `browser` 3, `screenshot` 2, `pixel` 2, `localhost` 2, `dev-server` 2, `banner` 2, `ui` 1,
  `click` 1. `render` matched a shell env-map renderer; `css` has previously matched the path
  fragment `styled-system/{css,jsx,recipes}`.

---

## Operator-step reality (applies to changes 3 and 4, and to reso under change 1)

The environment's network level, environment variables, setup script and API credentials are edited
**only** in a dialog at claude.ai/code. Docs, verbatim: *"On claude.ai/code, select the cloud icon
showing the current environment's name… There's no settings page or direct URL for the selector."*
API credentials additionally need *"an organization admin role"* and are **Pro/Max only**.

An API path exists and is the one `scripts/cloud-create-api.py:279-298` already mirrors
(`POST /v1/environment_providers/cloud/create`, the binary's `zMt` body) — it carries `init_script`,
`environment: {}`, `languages`, and `network_config: {allowed_hosts, allow_default_hosts}`. But the
shipped body sends `init_script: None`, so **this box has never exercised a setup script through the
API**, and the live environment reads back `config: null`:

```
GET /v1/environment_providers  (account next3) →
  1 environment: env_01AEW7TUe4BctTyPqozNvRRG  anthropic_cloud  "Default"
  state=active  created_at=2026-06-12  config=null  bridge_info=null
```

Measured on one account (next3) only. VM ceilings: 4 vCPU / 16 GB RAM / 30 GB disk; setup scripts
must exit zero and finish inside ~5 minutes or the session fails to start.

---

## Adversarial pass — for each change, the failure mode where the class does NOT vanish

1. **Attach the repo, cross-repo persists.** `cross_repo()` compares the item's project to
   `cloud_repo()`, which `_lane_from_self()` derives from cc-eligible's *own checkout*
   (`bin/cc-eligible:955-968`). Per-item attachment does not change what that function reads. The
   arm must be *rewritten* to "does this project resolve to a GitHub remote", and for `personal` the
   honest answer stays **no** — 34 rows keep the refusal, correctly. Second mode: the row becomes
   eligible and the VM still cannot do it — the 7 credential-blocked reso rows need Turso data-plane
   tokens; attaching the repo hands over the code and none of the secrets. Third mode: the two
   sevenrooms `preflight-golive.sh` rows fire **deep-history** as well, so change 1 alone leaves
   `45a0073b9ea4` refused.
2. **Unshallow, deep-history persists.** The class is emitted by `bin/cc-eligible`'s
   `HistoryOracle` against `CLOUD_DEPTH=50`, not by the VM. Doing the fetch and not moving the
   constant changes nothing. The inverse is worse: moving the constant while any fire skips the
   fetch mints cloud labels for unreachable work — and the rail is **prose with no abort**, so a
   worker that ignores it leaves no trace. Third mode: the horizon *moves* — a sha inside the window
   at filing falls out later (`docs/research/cloud-shallow-horizon-2026-08-29.md` title), so rows
   re-enter the class faster than a one-time deepen retires them.
3. **`gh` present, `ineligible-github` persists.** It already is present, and the row is still
   refused — because the row is a decision and because its subject repo is unattached. Retiring the
   class on "gh exists" would produce a worker that runs `gh api` against an unattached repo and
   gets a proxy **403**, or a GraphQL query the proxy rejects with *"This GraphQL query is not
   enabled for this session"* — a policy denial no retry moves, i.e. the exact failure
   `scripts/cloud-create-api.py:19-24` was written about.
4. **Browser installed, `visual` persists.** 19 of 22 rows fire a second class. Of the 3 that do
   not, a browser still cannot supply a production session cookie, register a platform passkey
   bound to the operator's Secure Enclave, or *rule* on where a banner sits. A screenshot is not a
   sign-off; the disposition, not the pixels, is what the row is waiting on.

**A fifth failure mode spanning all four: eligible ≠ drained.** Both open `deep-history` rows were
already worked by cloud sessions and their rows are still `open` — the branches exist, the verdicts
are written, the ledger has not moved. Adding supply to a lane whose return path is the measured
bottleneck (`bin/cc-eligible:490-510` on the `f85fce7c26f5` deadlock: eleven dispatches for one
unchanged verdict) converts configuration spend into more un-returned branches.

---

## Ranked by rows-unlocked-per-hour — agent-drainable rows only

"Agent-drainable" = status `open` or `claimed`, minus rows whose content is an operator action
(phone call, payment, sign-off, decision, credential) or whose subject is box state a VM cannot see.

| rank | change | agent-drainable rows | hours | rows/hour | note |
|---|---|---|---|---|---|
| **1** | **3 · `gh` CLI** | **0** | **0.5** (edit one class description) | 0 | Free to *correct*, worth doing as hygiene, buys no throughput. Do it in whatever commit touches `cc-eligible` next. |
| **2** | **2 · full-depth clone** | **0-2** | **1-2** (`CLOUD_DEPTH` + the abort interlock) | 0-2 | VM side already proven. The 2 rows are already worked off-box — treat this as *removing a silent-wrong-answer surface from every dispatch we already make* (§A2b's own second-order argument), not as an unlock. |
| **3** | **1 · per-item repo attach** | **4** (all `sevenrooms-bridge`) | **6-10** | **0.4-0.7** | The only change with real yield, and the yield is one small repo. Scoping it to `sevenrooms-bridge` + `doc_classifier` and leaving reso alone captures 100% of today's drainable rows at a fraction of the risk. |
| **4** | **4 · headless browser + dev server** | **0** | ≥12, unbounded | 0 | Refuted at the row layer (6/6 sample) before the tool layer was ever reached. Do not build. |

**The one-line conclusion.** Configuration is not the binding constraint. Four changes, ~8-13 hours,
yield **four** drainable rows — while 86 of the 99 rows they touch are blocked on the operator and
two already-drained rows sit unreturned. §A2b's generative statement still holds and this
measurement strengthens it: *"if the cloud share is to rise materially past 20%, it will be because
the backlog changes shape — more repo-only work filed — not because the VM changes shape."*

---

## Blockers and uncertainties, named

- **`gh api /user/installations` refuses** (403, wrong token class). Answered instead by the
  control-plane GET with a negative control. Not a gap in the answer; a gap in that instrument.
- **One account measured** (next3) for the environment list and the repo GETs.
- **No browser has ever been observed in a cloud VM** by this repo or named in the docs' tool table.
  Change 4's tool layer is unverified; its row layer is refuted, which is why I did not pursue it.
- **`config: null`** on the live environment record means the shipped list endpoint cannot tell us
  what the current environment is configured with. The only certain read is the dialog.
- **The unshallow rail has no assert-and-abort**, so "every fire runs it" is inferred from two
  commit bodies, not measured across fires.
- **`3c3bdc5be447`** (sevenrooms sidecar restarts) may need live runtime logs rather than repo
  content; counted in the 4 but it is the softest of them.
- Row statuses re-derived from the ledger event stream, not taken from the sweep — all 13 agreed.

Working files: `/private/tmp/claude-501/-Users-chrisren-Development--worktrees-cloud-lane-research/dc4eb0fa-3191-4b17-acc3-c3a1e6050e33/scratchpad/work-A3/why-all.jsonl` (per-row full class sets), `/private/tmp/claude-501/-Users-chrisren-Development--worktrees-cloud-lane-research/dc4eb0fa-3191-4b17-acc3-c3a1e6050e33/scratchpad/work-A3/block-reasons.tsv`
(last-block `needs` text per row), `/private/tmp/claude-501/-Users-chrisren-Development--worktrees-cloud-lane-research/dc4eb0fa-3191-4b17-acc3-c3a1e6050e33/scratchpad/work-A3/ineligible-*.tsv`.
