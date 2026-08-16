# D — GitHub Actions failure-notification mechanism + solution-space map

Research axis: MECHANISM + SOLUTION SPACE for the `hermetic` workflow's "not green ⇒
hourly failure email" problem. Read-only research; no recommendation made (lead
synthesizes). All claims below are cited to a live `docs.github.com` fetch or a
GitHub `community` discussion fetched 2026-08-15, or explicitly marked
**UNVERIFIED**/**DISPUTED** where the docs did not settle it.

## Levers table

| Lever | Surgical? | Preserves real-failure visibility? | Cost |
|---|---|---|---|
| L1. Global `Settings > Notifications > Actions` dropdown → "Don't notify" | **No — global, all repos** | No — mutes every repo's Actions notifications, the naive fix #2 the brief told us to avoid | Zero engineering; total signal loss org-wide |
| L2. Global Actions dropdown → "Only notify for failed workflows" | No (global) | Yes for genuine failures, but **does nothing for `hermetic`** — a `not-green` result is already encoded as `exit 1`/failure, so this setting doesn't suppress it; it only avoids *success* emails elsewhere | Zero cost, but not a fix for this problem |
| L3. Unwatch / set repo to "Custom" (minimal categories) for `renchris/claude-infrastructure` only | Repo-scoped, not workflow-scoped | **No within that repo** — silences Actions notifications for every workflow in the repo, hiding a real CI failure in an unrelated workflow | Zero engineering; blast radius = one repo, not the org, but still too wide per the brief's own no-blunt-mute framing |
| L4. Job-level `continue-on-error: true` on the final job | Workflow-scoped (surgical at the YAML level) | **Yes, UI-visible** (job shows failed/red inside the run) but run-conclusion behavior is **DISPUTED — see §4a**; may or may not still email | Small YAML change; the visibility-vs-email tradeoff is exactly unresolved by docs |
| L5. Always `exit 0`; publish the real verdict as a **self-created check-run** (`POST /repos/{o}/{r}/check-runs`, e.g. via `actions/github-script`) with `conclusion: neutral\|failure\|success` | **Yes — most surgical** | Yes — a consumer (or a human clicking into the PR/commit) can see the check-run's own conclusion; a red check-run still renders red in the PR UI | Requires `permissions: checks: write`; one extra API call/step; the run's own conclusion is now decoupled from the "real" verdict, so anyone reading only run-conclusion loses signal unless they read the check-run |
| L6. Always `exit 0`; publish the verdict as a **commit status** (`POST /repos/{o}/{r}/statuses/{sha}`, states `success\|pending\|failure\|error`) with its own `context` | **Yes — surgical, no `neutral` state** | Yes, in the commit-status UI / PR checks list under its own context name | No native "neutral" — only success/pending/failure/error; same decoupling cost as L5 |
| L7. Workflow status **badge** (`.../actions/workflows/<file>/badge.svg`) as the published signal, consumed by a separate reader | Yes — fully pull-based | Yes, if the reader actually polls it | Badge reflects the **run's own conclusion**, so it inherits whichever conclusion L4/L5/L6 produced — not independent of those levers |
| L8. `workflow_run` event / `gh run list --json conclusion` polling by a downstream consumer, bypassing human notifications entirely | Yes — fully surgical, zero notification surface touched | Yes — full-fidelity `conclusion` value available to the poller | Requires a poller/consumer to exist; humans get nothing unless they also poll |
| L9. `jobs.<id>.if: <condition>` to make the job **`skipped`** rather than run-and-fail | Workflow-scoped | **No** — skipping means the test never ran; this loses the signal outright, doesn't apply once the job has already executed and detected non-green | Not viable for `hermetic`'s actual shape (job runs, then must report) |
| L10. Native `neutral` conclusion on an Actions **job** | N/A | N/A | **Does not exist** — see §2. Only a self-created check-run (L5) can carry `neutral`; a job/workflow itself cannot |
| L11. `cancelled` conclusion as a "silent non-success" | N/A | N/A | **Does not silently work** — community-observed, cancelled runs still trigger the failure-style notification even under "Only notify for failed workflows" (§2) |
| L12. Per-workflow `notifications:` YAML key | N/A | N/A | **Does not exist** — confirmed absent from workflow syntax reference (§4b) |

---

## 1. What exactly triggers a "Run failed" email

- **Subscription is per-user, tied to "Watching."** GitHub's docs: "For repositories that are set up with GitHub Actions and that you are watching, you can choose how you want to receive workflow run updates." Watching a repo is a **prerequisite** for Actions notifications at all.
  Source: https://docs.github.com/en/subscriptions-and-notifications/how-tos/managing-github-actions-notifications
- **Delivery is configured at `Settings > Notifications`, under `System > Actions`.** Verbatim procedure: *"On the 'Notification settings' page, under 'System', then under 'Actions', select the **Don't notify** dropdown menu"* and choose one of: **Don't notify** (default) / **On GitHub** (web) / **Email** / **Only notify for failed workflows**.
  Source: same URL (fetched raw markdown from `github/docs` main branch, 2026-08-15).
- **This is a single ACCOUNT-WIDE setting, not per-repository, and not per-workflow.** The docs give no repository-selection step in the procedure — it's one dropdown that governs Actions notification delivery for every repo you watch. This directly contradicts an earlier AI-summarized read that implied per-repo configurability; the raw-markdown fetch settled it: no repo-picker exists in this flow. **(Resolved via direct raw-markdown fetch after an initial ambiguous WebFetch summary — flagging the correction so the lead doesn't inherit the wrong read.)**
- **Per-repository "Custom" watch does NOT include an Actions/CI-activity checkbox.** Verbatim: *"If enabled, customize the types of event you receive notifications for (issues, pull requests, releases, security alerts, or discussions)"* — no Actions/CI item in that list.
  Source: https://docs.github.com/en/account-and-profile/managing-subscriptions-and-notifications-on-github/managing-subscriptions-for-activity-on-github/managing-your-subscriptions
  This means **L3 (repo-level opt-out) is NOT achievable via the Custom-watch event-type checkboxes** — the only repo-level lever is un-watching (or downgrading watch level) entirely, which is blunter than it first appears (loses ALL notification types for that repo, not just Actions).
- **Notification includes these run statuses**: "successful, failed, neutral, and canceled runs" per the docs' own enumeration — **skipped and timed_out are conspicuously not named** in that list (§2 covers what's actually known about skipped/timed_out).
  Source: https://docs.github.com/en/actions/concepts/workflows-and-actions/notifications-for-workflow-runs
- **"Only notify for failed workflows"** exists today, current semantics per docs: filters delivery to failed-conclusion runs only, still a per-account (not per-workflow) toggle. **Cannot be scoped per-workflow** — confirmed absent from every doc surface checked (§4b).
- **Scheduled-workflow notification routing is special**: notifications go to whoever *created* the workflow; if someone else edits the `schedule:` cron syntax, notifications reroute to that editor; if the workflow was disabled then re-enabled, notifications go to whoever re-enabled it (not the last cron editor).
  Source: https://docs.github.com/en/actions/concepts/workflows-and-actions/notifications-for-workflow-runs
  Practical implication for `hermetic`: the hourly emails are going to whichever single GitHub user is currently on record as "creator" (or last re-enabler) of that workflow — check `git blame` / the Actions UI "who last touched the schedule" to find exactly whose inbox this is.

## 2. Non-emailing non-success states — what's real vs aspirational

- **`neutral` conclusion does NOT exist for a plain Actions job/workflow.** Confirmed via the canonical community feature request (`orgs/community/discussions/9875`, opened 2022, GitHub PM acknowledged interest, "on our backlog," **still unimplemented as of the most recent 2026-04 comments** — 4+ years, 100+ upvotes, no ship). A workflow job's own `conclusion` enum is `success | failure | cancelled | skipped | timed_out | action_required` — no `neutral` member.
  Source: https://github.com/orgs/community/discussions/9875 (fetched 2026-08-15)
- **`neutral` DOES exist for the Checks API** — a check-run you create yourself via `POST /repos/{owner}/{repo}/check-runs` accepts `conclusion: neutral` (full enum: `success, failure, neutral, cancelled, skipped, timed_out, action_required, null`).
  Source: https://docs.github.com/en/rest/checks/runs?apiVersion=2022-11-28
- **`cancelled` still notifies as a failure, empirically, per multiple community reports, and this is NOT configurable separately.** A user running concurrency-cancelled runs confirmed cancelled runs still generate the "failed workflow" email under "Only notify for failed workflows," with **no GitHub staff confirmation either way** on whether this is intended — logged as an open, unresolved community discussion.
  Source: https://github.com/orgs/community/discussions/166045 (fetched 2026-08-15) — **treat the underlying mechanism as UNVERIFIED-by-GitHub-staff but empirically-observed by multiple independent reporters.**
- **`skipped`**: a job skipped via `if:` reports **status "Success"** ("This check was skipped" — downstream `needs` treats it as success-shaped) per multiple docs/community sources. Whether a wholly-skipped RUN (not just skipped job) sends a notification email at all is **UNVERIFIED** — not stated explicitly in the notification docs' own enumeration ("successful, failed, neutral, and canceled" — skipped is absent from that list, which is suggestive but not a direct statement that skipped is notification-silent).
- **`timed_out`**: **UNVERIFIED** whether this is treated as "failed" for notification-filter purposes. Not named in the docs' enumeration either. Given `timed_out` is treated as equal-or-higher priority than `failure` in check-suite conclusion aggregation (Checks API docs: "if three check runs have conclusions of timed_out, success, and neutral, the check suite conclusion will be timed_out" — i.e. timed_out outranks success), the safer assumption is it notifies same as failure, but this is inference, not a direct citation.
- **Practical reading of §2**: there is no native "quiet non-success" for an Actions job/workflow's OWN conclusion. The only quiet non-success channel is a **separately created check-run** (`neutral`), which lives outside the run-conclusion/notification pipeline entirely (§3).

## 3. What the check-runs endpoint actually exposes

`POST /repos/{owner}/{repo}/check-runs` (and the paired `PATCH .../check-runs/{id}` to update it), requires `permissions: checks: write` on the calling token — `GITHUB_TOKEN` is sufficient with that permission block; **no elevated `pull_request_target` trick is required** (a community answer floating that idea was over-cautious/incorrect for the ordinary create-check-run-from-your-own-workflow case — flagging that as a corrected read, since it surfaced in search results as a stated "requirement").

Fields exposed on the check-run object, per the REST reference:
- `status`: `queued | in_progress | completed | waiting | requested | pending`
- `conclusion`: `success | failure | neutral | cancelled | skipped | timed_out | action_required | null`
- `details_url`, `external_id`
- `output.{title, summary, text, annotations_count, annotations_url}`
- `name`, `head_sha`, `started_at`, `completed_at`

Source: https://docs.github.com/en/rest/checks/runs?apiVersion=2022-11-28

**The docs make zero statement about check-runs triggering email notifications** — no notification-behavior claim exists in that reference at all. Combined with §2's confirmation that `neutral` check-runs are a Checks-API-only construct decoupled from the "workflow run" notification pipeline described in §1, the working (but not GitHub-staff-confirmed-in-writing) inference is: **a check-run you create yourself is notification-silent through the personal-email Actions-notification channel**, because that channel is keyed on *workflow run* conclusion, not on arbitrary check-runs a job creates. **Flag this specific inference as UNVERIFIED** — no doc page directly states "creating a check-run does not email watchers"; it's an absence-of-statement inference from reading both pipelines separately, not a positive citation.

A consumer can poll the check-run via `GET /repos/{owner}/{repo}/commits/{ref}/check-runs` or `GET /repos/{owner}/{repo}/check-runs/{check_run_id}` to read `conclusion` directly — this is the shape of "the meaningful signal lives in a check-run rather than the run conclusion" the brief asked about, and it is a supported, documented pattern (used by e.g. Codecov-style third-party status reporters).

## 4. Surgical (non-global) suppression levers

- **a) Job-level `continue-on-error: true` — DISPUTED, not settled by official docs.** Two claims found in circulation, contradicting each other, neither traceable to an official GitHub docs page (the official workflow-syntax reference page could not be fetched cleanly — returned truncated/404 content on both attempts, so this is a genuine doc gap, not just search noise):
  - Claim A (from a synthesized community-discussion read): *"If used at the job level, then the job is marked as failed... and the whole workflow is still marked as successful when looking in the Actions tab."* (i.e., run conclusion = success)
  - Claim B (Ken Muse, kenmuse.com, cited blog post — not an official doc): *"the overall workflow will report a failure"* when job-level `continue-on-error` is used.
  A separate community discussion (`orgs/community/discussions/15452`, "Properly show continue-on-error jobs/steps in PR UI") shows this exact ambiguity is a live, acknowledged pain point — GitHub Actions "reflects [continue-on-error] extremely poorly (= not at all) in the UI," and there is an open feature request (since 2023, "In Backlog," GitHub PM said they'd do user interviews, no update since) for a proper warning/yellow state. **VERDICT: whether L4 emails or not cannot currently be established from documentation and should be empirically tested against the actual `hermetic` workflow before relying on it** — this is the single highest-value cheap experiment the lead could run.
  Sources: https://github.com/orgs/community/discussions/15452 ; https://www.kenmuse.com/blog/how-to-handle-step-and-job-errors-in-github-actions/ (blog, not github.com — lower authority)
- **b) No per-workflow `notifications:` YAML key exists.** Workflow syntax has exactly three required top-level keys (`name`, `on`, `jobs`) plus documented optional keys (`env`, `permissions`, `concurrency`, `defaults`, `run-name`) — none of them govern notification delivery. Confirmed absent across every workflow-syntax-reference search result surfaced.
- **c) `gh api /repos/{o}/{r}/subscription`** (`GET`/`PUT`/`DELETE`) — this is the API surface for the Watch/Custom/Ignore state, fields `subscribed` (bool — "should notifications be received from this repo") and `ignored` (bool — "should ALL notifications be blocked from this repo"). This is **repo-level, not workflow-level, and not Actions-specific** — same blast radius as L3, just scriptable instead of UI-driven.
  Source: https://docs.github.com/en/rest/activity/watching?apiVersion=2022-11-28
- **d) Inbox `reason:ci-activity` filter** exists for triaging the notifications **inbox/web UI** ("On GitHub" notifications), not for suppressing **email** delivery — it's a read-side filter (`repo:owner/repo reason:ci-activity` in the notifications search), useful for a human triaging their inbox but irrelevant to stopping the hourly email itself.
  Source: https://docs.github.com/en/subscriptions-and-notifications/reference/inbox-filters
- **e) No "mute this one workflow" feature exists anywhere in the surfaces checked** — every suppression lever found operates at the account level (L1/L2) or the repository level (L3/subscription-API), never at the individual `.yml` file / workflow-name level.

## 5. `workflow_run` / badges / commit-status "green stamp" pattern

This is the **established pattern** other projects use to publish a verdict without a red run, confirmed across badge docs + commit-status docs + real-world commit-status-updater actions:

- **Status badge**: `https://github.com/OWNER/REPO/actions/workflows/WORKFLOW-FILE/badge.svg` — defaults to the default branch's most recent run; purely reflects the run's own `conclusion`. Not independent signal — it's a *view* onto whatever L4/L5/L6 already decided the run's conclusion is.
  Source: https://docs.github.com/actions/managing-workflow-runs/adding-a-workflow-status-badge
- **Commit status** (`POST /repos/{owner}/{repo}/statuses/{sha}`): the classic pre-Checks-API pattern — `state: pending|success|failure|error`, a `context` string to namespace it (e.g. `context: "hermetic/off-box"`), `description`, `target_url`. Rate-limited to 1000 statuses per sha+context. This creates an independent, separately-named status line in the PR checks list, decoupled from the workflow run's own conclusion — the run can `exit 0` (green, silent) while `context: "hermetic/off-box"` shows red for anyone who looks.
  Source: https://docs.github.com/en/rest/commits/statuses
- **Real-world idiom confirmed**: `if: always()` on a final "report status" step/job that runs regardless of upstream pass/fail, POSTing the real result as a commit status — this is the standard "hermetic CI reports itself, host workflow stays green" shape, matching exactly what the brief describes wanting.
- **`workflow_run` event**: a *second* workflow can trigger on `workflow_run: {workflows: [...], types: [completed]}` and read `github.event.workflow_run.conclusion` — this is the poll/consume side (L8), letting a deploy-lane or dashboard react to the real conclusion without any human notification involved at all, since `workflow_run`-triggered workflows are driven by the API event, not by anyone "watching."

## 6. Scheduled-workflow auto-disable — inactivity vs. failures

- **Confirmed**: GitHub auto-disables a **scheduled** workflow after **60 days with no repository activity**, in both public and private repos, and emails about it. **Only new commits reset the inactivity clock** — issues, PRs, releases, tags do NOT count as qualifying activity.
  Sources (community-corroborated, multiple independent threads, consistent claim): `github.com/orgs/community/discussions/86087`, `github.com/orgs/community/discussions/184653`, `github.com/efrecon/gh-action-keepalive` (README states the mechanism plainly), `github.com/PhrozenByte/gh-workflow-immortality`. **Could not locate the primary docs.github.com page stating this explicitly in this session's searches** — flag the 60-day figure itself as **community-sourced/well-corroborated but not directly cited to a docs.github.com page**; if precision matters, verify against `docs.github.com/en/actions/using-workflows/events-that-trigger-workflows#schedule` directly before relying on the exact day-count.
- **Repeated-failure-triggered auto-disable: NO EVIDENCE FOUND.** Every source surfaced ties auto-disable strictly to the 60-day inactivity clock, not to the number or rate of failed runs. **Treat "hourly red hermetic runs could themselves cause GitHub to auto-disable the schedule" as UNVERIFIED-NEGATIVE** — no mechanism found, but this is an absence-of-evidence result from search, not an exhaustive read of every doc page; worth a targeted re-check if the workflow ever does go silent unexpectedly.
- Mitigation pattern used against the 60-day disable (irrelevant to the notification problem itself, but adjacent and cited in case it matters): a monthly keepalive commit/workflow.

## Gaps / could not verify this session

1. **L4 (`continue-on-error: true` job-level → run conclusion) is a live, disputed unknown** — the single most actionable unresolved question; needs an empirical test (push a deliberately-failing `hermetic`-shaped job with job-level `continue-on-error: true` and observe whether the email arrives), not another doc search.
2. Whether `skipped` or `timed_out` run conclusions are filtered by "Only notify for failed workflows" — absent from the docs' own enumeration but not explicitly excluded either.
3. Whether "creating a check-run yourself never emails watchers" (§3) is a positive GitHub guarantee or just an absence-of-documented-linkage — no page makes this claim directly.
4. The exact 60-day scheduled-workflow-disable figure's primary-source doc URL (only community corroboration found, not a direct docs.github.com fetch, despite two searches).
