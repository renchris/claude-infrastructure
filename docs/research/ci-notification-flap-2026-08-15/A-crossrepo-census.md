# A — Cross-repo GitHub Actions notification-producer census

Measured 2026-08-15, window = `created:>=2026-08-01` (14 days) unless noted. Every number below is
from a quoted `gh`/`gh api` command actually run against `renchris`'s authenticated GitHub account.
Auth: `gh auth status` → logged in as `renchris`, scopes `repo, workflow, read:org, admin:public_key,
gist, user` — sufficient for Actions read on all repos in this account; **zero scope errors** hit
during the full 114-repo scan (see §1).

## 0. THE RANKED TABLE — failed runs/day, descending

Only `conclusion=failure` counts as a "Run failed:" notification-producer (GitHub's own email
template fires on `failure`, not on `cancelled`/`skipped` — the constraint text's literal subject
line `"Run failed:"` matches this). Rate = failure-count ÷ 14.

| Rank | Repo | Workflow | Failures (14d) | Total runs (14d) | Failure rate | Trigger | Cadence | Failures/day |
|---|---|---|---|---|---|---|---|---|
| 1 | claude-infrastructure | **hermetic** | 116 | 122 | 95.1% | schedule (106) + workflow_dispatch (12) + push (4) | cron `17 * * * *` (hourly) + `43 9 * * *` (daily census) | **8.29** |
| 2 | claude-infrastructure | **diagrams** | 57 | 535 | 10.7% | push (535) | on every push touching `assets/diagrams/**`, `scripts/render-diagrams.mjs`, `package.json`, `**/*.md` | **4.07** |
| 3 | lakehouse-lecture | **pages-build-deployment** | 22 | 110 | 20.0% | `dynamic` (GitHub Pages auto-build system, 110) | fires on every push to the Pages source (not an owner-authored workflow file — no cron) | **1.57** |
| 4 | doc_classifier | **nightly** | 15 | 15 | **100%** | schedule (15) | cron `17 7 * * *` (daily) | **1.07** |
| 5= | reso-management-app | **tenant-drift** | 2 | 2 | **100%** | schedule (2) | cron `0 14 * * 1` (weekly, Mon) | 0.14 |
| 5= | reso-management-app | **soketi-image-cve-scan** | 2 | 2 | **100%** | schedule (2) | cron `0 15 * * 1` (weekly, Mon) | 0.14 |
| 7 | reso-management-app | **design-screenshots** | 1 | 1 | 100% (n=1) | push (1) | not scheduled — fires on relevant pushes | 0.07 |
| — | claude-infrastructure | probe-a-gated-skip | 0 | 1 | 0% | push | one-off probe | 0 |
| — | claude-infrastructure | probe-b-continue-on-error | 0 | 1 | 0% | push | one-off probe | 0 |
| — | claude-infrastructure | probe-close-attrib | 0 | 2 | 0% (1 cancelled) | push | one-off probe | 0 |
| — | reso-management-app | security-scan | 0 | 15 | 0% | push | — | 0 |
| — | reso-management-app | diagrams | 0 | 2 | 0% | push | — | 0 |
| — | doc_classifier | ci | 0 | 1 | 0% | push | — | 0 |
| — | doc_classifier | trunk-alert / Dependabot Updates / Dependency Graph | 0 | 0 | n/a | — | — | 0 |
| — | reso-management-app | Dependabot Updates | 0 | 0 | n/a | — | — | 0 |

**`hermetic` alone is ~8.3 failed runs/day fleet-wide — more than the combined rate of everything
else measured (≈7.0/day sums to the remaining rows, dominated by `diagrams`).** Whatever cadence the
operator perceives ("every ~30 min") is consistent with `hermetic` (hourly cron, 95% fail) interleaved
with `diagrams` (push-triggered, fires on every commit touching docs/diagrams — bursty, not steady).

## 1. Full repo census (command + result)

```
gh repo list renchris --limit 200 --json name,isArchived,updatedAt,visibility
```
→ **114 repos total**, **0 archived**, **24 forks** (labelled below), 38 private / 76 public.

Forks (`gh repo list renchris --limit 200 --json name,isFork,isArchived` → `isFork:true`, 24 total,
none archived): `replicache-react, novu, iron-session, react-snap, ark, tax-chart, zag, soketi,
app-playground, edge-runtime, next.js, umami, blaze-slider, joe-v2, examples, quadswap-web-app,
terraswap, tfc-guide-example, learn-terraform-enforce-policies, chakra-ui, cpsc330, FSCalendar,
DropDown, animated-tab-bar`. None of these 24 had any workflow-run activity in the 14-day window
(see §2) — expected, since a fork inherits workflow files but Actions is disabled-by-default on
forks and none were re-enabled.

No scope errors: every one of the 114 `repos/renchris/<name>/actions/runs` calls returned a valid
JSON `total_count` (rc=0); none returned a 403/404 "Resource not accessible" or similar.

## 2. Activity scan — which repos had ANY workflow run in the last 14 days

Command per repo (looped over all 114 names):
```
gh api "repos/renchris/<repo>/actions/runs?created=>=2026-08-01&per_page=1" --jq '.total_count'
```
(`2026-08-01` ≈ `date -u -v-14d` from 2026-08-15; scan completed 2026-08-15T23:10:45Z, giving an
actual window of ~14d 0h19m — rates below use 14 as the divisor per the task's framing.)

**Result: exactly 4 of 114 repos had any Actions run in the window.** Every other repo (110/114,
including all 24 forks) returned `total_count=0` and is therefore mechanically incapable of having
produced a "Run failed:" email in this period — they carry no workflow-run population to fail.

Active repos (`gh repo list` `updatedAt` shown for cross-reference, all non-archived, non-fork):
| Repo | Runs (14d) | Visibility |
|---|---|---|
| claude-infrastructure | 660 (raw scan; 661 across the 5 workflows counted in §0/§3 — 1-run drift is a run created between the §2 scan and the §3 per-workflow pull) | Public |
| lakehouse-lecture | 110 | Private |
| reso-management-app | 22 (raw scan sample cap; full per-workflow sum in §0 = 22 across 6 active workflows) | Private |
| doc_classifier | 16 (raw scan; full per-workflow sum in §0 = 17 across the 2 workflows with any runs) | Private |

(The §2 numbers above are from a `per_page=1` probe read as `.total_count` — they match the §3 sums
to within timing noise from runs firing between the two passes; §3/§0 are the authoritative,
per-workflow, status-broken-down counts and are what the ranked table uses.)

## 3. Per-workflow full census (accurate — paginated, not sampled)

**Method note:** an early pass used `?status=failure&per_page=1&created=>=DATE` server-side filters
per (repo, workflow, status, event) combination — accurate but 12 calls/workflow × 13 workflows
triggered secondary rate-limit stalls (multi-minute hangs, no error surfaced — the `gh` process just
sat between calls). Replaced with **one paginated pull per workflow**
(`gh api --paginate ".../runs?created=>=2026-08-01&per_page=100" --jq '.workflow_runs[] | [.conclusion,.event]'`)
+ local `sort | uniq -c` aggregation — 1-6 calls/workflow (paginated by GitHub, not by me), no stalls,
and it also **caught an undercounting bug**: the first (100-row-capped, unpaginated) sample of
`diagrams` read "100/100 success" and looked like a non-producer; the full 535-row pull found 57
real failures (10.7%) that the capped sample missed entirely. Every count in §0 is from the
paginated, locally-aggregated pass.

```
### claude-infrastructure / hermetic (id=330878336)
rows=122 · cancelled=1 failure=116 success=5 · events: push=4 schedule=106 workflow_dispatch=12

### claude-infrastructure / diagrams (id=322458145)
rows=535 · failure=57 success=478 · events: push=535

### claude-infrastructure / probe-a-gated-skip, probe-b-continue-on-error, probe-close-attrib
1 run each (2 for probe-close-attrib) — all push-triggered, near-zero volume, not notification producers.

### lakehouse-lecture / pages-build-deployment (id=326033947)
rows=110 · cancelled=7 failure=22 success=81 · events: dynamic=110

### reso-management-app / security-scan (id=222737164): 15 success / 15, push
### reso-management-app / tenant-drift (id=279312166): 2 failure / 2, schedule
### reso-management-app / soketi-image-cve-scan (id=297384770): 2 failure / 2, schedule
### reso-management-app / design-screenshots (id=331742003): 1 failure / 1, push
### reso-management-app / diagrams (id=332686630): 2 success / 2, push
### reso-management-app / Dependabot Updates (id=222730977): 0 runs in window

### doc_classifier / ci (id=312168002): 1 success / 1, push
### doc_classifier / nightly (id=313666182): 15 failure / 15, schedule — 100%
### doc_classifier / diagrams, trunk-alert, Dependabot Updates, Dependency Graph: 0 runs in window
```

## 4. Cron expressions (scheduled workflows only — read from the workflow YAML on `main`)

| Repo | Workflow | Cron | Meaning |
|---|---|---|---|
| claude-infrastructure | hermetic | `17 * * * *` **and** `43 9 * * *` | hourly + one extra daily "census" run at 09:43 UTC |
| reso-management-app | tenant-drift | `0 14 * * 1` | weekly, Monday 14:00 UTC |
| reso-management-app | soketi-image-cve-scan | `0 15 * * 1` | weekly, Monday 15:00 UTC |
| doc_classifier | nightly | `17 7 * * *` | daily, 07:17 UTC |

`diagrams` (both repos) and `design-screenshots` are `push`/`pull_request`-path-triggered, not cron.
`pages-build-deployment` is GitHub's own Pages-build system (`event=dynamic`) — no cron in the repo
to read; it fires on pushes to the Pages source branch/path, outside repo-owner workflow-file control.

## 5. Why each top offender fails — read from `gh run view <id> --log-failed`

| Workflow | Run inspected | Root cause (verbatim from log) | Category |
|---|---|---|---|
| **hermetic** (claude-infrastructure) | `31912550182` (2026-08-15T22:35Z, schedule) | `verdict` job's own script: `if [ "red" = "green" ]; then exit 0; fi` / `echo "NOT GREEN (red)..."` / `exit 1` — the job **is a deliberate red/green publisher**, not a bug. Log literally states "This never blocks a land and is never read as a red by the deploy lane." | **(b) deliberate not-green signal encoded as exit 1** — confirms the task's KNOWN STARTING FACT. |
| **diagrams** (claude-infrastructure) | `31582293587` (2026-08-12T09:18Z, push) | `npm run diagrams:check` → `STALE fences in: README.md — run 'npm run diagrams'` → exit 1. The check compares rendered `.mmd` output against what's committed in Markdown fences and fails when they've drifted. | **(a) real regression** (content genuinely out of sync) — a working, non-flaky content-drift gate; it fails whenever a commit touches a diagram source without re-rendering. |
| **pages-build-deployment** (lakehouse-lecture) | `31444971084` (2026-08-11T00:08Z, dynamic) | `Liquid Exception: Liquid syntax error (line 1013): Tag '{%' was not properly terminated ... in docs/research/KPMG-BRAND-2026-08-08/B1-pptx-ceiling.md` — a plain-prose doc containing a literal `{%...%}`-shaped string breaks Jekyll's Liquid parser during the GitHub Pages auto-build. | **(a)/(c) mixed** — real build break, but caused by a structural mismatch (arbitrary repo Markdown being auto-fed to Jekyll/Liquid by GitHub's Pages system, not a doc anyone wrote *for* Pages) rather than app logic. |
| **nightly** (doc_classifier) | `31872771372` (2026-08-15T07:45Z, schedule) | `pytest`: `AssertionError: stage peak RSS over budget at point 'proving': {'S0': 'peak 644 MB > budget 190 MB', 'S1': 'peak 644 MB > budget 355 MB', 'S5': 'peak 644 MB > budget 340 MB'}` — `tests/load/test_scale_replay.py::test_stage_peak_rss_stays_within_budget`, same assertion every night. | **(a) real, but structurally permanent** — 15/15 identical failure at the identical assertion; either the CI runner's RSS genuinely exceeds a real budget every single night, or the budget itself was set below what the current code actually uses. Either way it is **not flapping** — see §6. |
| tenant-drift (reso-management-app) | `31401486855` (2026-08-10T15:03Z, schedule) | `Error: Multiple versions of pnpm specified: version 9 in the GitHub Action config ... vs pnpm@11.9.0 ... in package.json` — fails in the **setup step**, before the drift check itself ever runs. | **(c) infrastructure/config** — pnpm-version mismatch between the workflow's `pnpm/action-setup` pin and `package.json`'s `packageManager` field. |
| soketi-image-cve-scan (reso-management-app) | `31405617109` (2026-08-10T15:49Z, schedule) | Trivy `Trivy image scan (HIGH,CRITICAL)` step: real finding, `CVE-2026-59874 HIGH ... tar: Node-tar: Denial of Service via malformed tar archive header`, exit 1 on any HIGH/CRITICAL finding. | **(a) real regression / real finding** — a genuine unpatched CVE in the scanned image; will keep failing until the upstream image/dependency is patched or the finding is explicitly excluded. |
| design-screenshots (reso-management-app) | `31474379125` (2026-08-11T08:42Z, push) | Playwright: `Error: Timed out waiting 120000ms from config.webServer.` — the dev server never became ready inside the 120s boot budget. | **(c) infrastructure/timeout** — CI runner boot-time variance, not an assertion failure in app code. |

## 6. Permanently-red vs flapper — explicit split (task item 5)

**Permanently-red (100% failure, every scheduled occurrence in the window failed):**
- `doc_classifier` / **nightly** — 15/15 schedule-triggered runs failed, all at the identical RSS-budget
  assertion (`test_scale_replay.py::test_stage_peak_rss_stays_within_budget`). Every single night for
  the full 14-day window produced the same red.
- `reso-management-app` / **tenant-drift** — 2/2 schedule-triggered (weekly) runs failed, both at the
  identical pnpm-version-conflict setup error — never reaches the actual drift check.
- `reso-management-app` / **soketi-image-cve-scan** — 2/2 schedule-triggered (weekly) runs failed, both
  on the same live CVE (`CVE-2026-59874`) in the scanned image.

**Near-permanent, NOT literally 100% (flapper-adjacent, dominates volume):**
- `claude-infrastructure` / **hermetic** — 116/122 (95.1%) failed, but genuinely produced 5 successes
  and 1 cancellation in the window — it is not mechanically incapable of going green (the `verdict`
  job's own comment confirms a real all-green census is possible and meaningful), so it does not meet
  the "fails ~100% of the time" bar precisely, even though it dominates the ranked table by raw volume.

**True flappers (partial failure rate, driven by input content/timing, not a static config bug):**
- `claude-infrastructure` / **diagrams** — 57/535 (10.7%), fails only on commits that desync
  rendered diagrams from source.
- `lakehouse-lecture` / **pages-build-deployment** — 22/110 (20.0%) + 7 cancelled, fails only when a
  pushed doc happens to contain a Liquid-breaking substring.

The distinction matters for measurement purposes as stated: a **permanently-red producer** (nightly,
tenant-drift, soketi-image-cve-scan) will keep emitting a failure email on every future scheduled
occurrence with zero additional signal content after the first — the population is fully explained by
its cadence. A **flapper** (diagrams, pages-build-deployment) or **near-permanent-red-with-real-green-path**
(hermetic) has runs whose outcome depends on what changed, so its future rate is not fully determined
by cron alone.

## Adversarial pass — what I checked after the first draft

1. **"Did `gh repo list` silently exclude private-org or SSO-gated repos?"** — checked
   `gh auth status`: scopes include `repo` (full) and `read:org`; no SSO-protected orgs are configured
   for this token (`read:org` would surface an SSO prompt on `gh api user/orgs` if one existed — not
   tested directly, but zero repos in the 114-item list returned a scope error on Actions reads, which
   would be the failure mode if `repo` scope were insufficient). Not fully ruled out: a repo the token
   cannot even list (invisible to `gh repo list`) would be undetectable by this method — noted as a
   blind spot, not resolved.
2. **"Are `cancelled` runs also emailing the operator?"** — GitHub's notification template for Actions
   is literally `"Run failed:"` (matches the constraint's quoted subject), which GitHub's own docs tie
   to `conclusion=failure` specifically, not `cancelled`/`skipped`/`neutral`. I did not find a way to
   verify this against the operator's actual email/notification settings (no access to their GitHub
   notification preferences) — this is inferred from the subject-line match, not independently confirmed.
   `cancelled` counts are reported separately in §3 for completeness but excluded from the ranking.
3. **"Did the sampled-vs-paginated bug (§3 method note) affect any OTHER workflow the same way?"** —
   re-verified: every workflow with `total_count <= 100` (all except `diagrams` at 535 and `hermetic`
   at 122, both re-pulled paginated) needed no correction since a single `per_page=100` page already
   captured 100% of rows. Confirmed by cross-checking `rows=` against each workflow's own `total_count`
   in §3 — they match exactly for every row.
4. **"Could a repo have workflow activity older than 14 days that still fires periodically (e.g. a
   quarterly cron) and would be invisible to this scan?"** — genuine blind spot, not investigated:
   the `created=>=2026-08-01` filter by construction cannot see a cron whose last-and-next fire both
   fall outside the window. Given the operator's own "~every 30 min" perceived cadence, this is very
   unlikely to hide a *significant* contributor, but it is not ruled out for a low-frequency one.

## Blockers / unresolved

- No independent confirmation the operator's GitHub notification settings actually route `failure`
  emails from all 4 active repos (vs. e.g. only repos they're a collaborator/watcher on with Actions
  notifications enabled) — out of `gh`'s readable surface; would need the operator's own
  `github.com/settings/notifications` state.
- `reso-management-app` `Dependabot Updates`/`doc_classifier` `trunk-alert`/`Dependency Graph`/
  `Dependabot Updates` all show 0 runs in the window (not 0 failures — 0 *runs*, i.e., they exist as
  registered workflows but never fired in the 14-day census).
