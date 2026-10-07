# C1 — Hostile review: what the cloud-sessions post leaves out for an UNATTENDED 24/7 drain

Written 2026-10-07T02:10Z (local 2026-10-06). Subject repo read-only at
`/Users/chrisren/Development/.worktrees/wt-cc-205652-27362` (`renchris/claude-infrastructure-private`).
Post: <https://claude.dev/blog/claude-code-in-the-cloud/> (Addy Osmani, 2026-10-06), fetched by curl 2026-10-07T02:01Z.
Docs: `code.claude.com/docs/en/*.md` fetched the same hour (copies: `/tmp/cloud-blog-eval/.c1-doc-*.md`; line numbers below are into those copies).
Confidence tags: **M** measured here (command named) · **D** documented (primary source quoted) · **I** inferred (reasoning; a hypothesis).

## 0 · Headline

- The post's central safety claim is wrong for this repo, and the repo has already paid for it. Post: the session "gets a short-lived credential that can push only to its own working branch" (post, "Under the hood", takeaway 2). Docs the same day: the proxy "doesn't limit which branches a push can update" (`cloud-environments.md:242`); "A rule that access can bypass doesn't block a session's push" (`security.md:104`). Repo: 93 commits were pushed straight to `main` by cloud VMs 2026-08-24..09-04 and "Still open: a VM can push `main`" (`docs/research/off-identity-commits-trace-2026-10-02.md:7-12,72-74`). `main` is unprotected today (**M**, §3).
- `main` of this repo is the symlink source of the live `~/.claude` layer, so an unrestricted push is a path from a disposable VM to code that runs on the operator's Mac with full credentials. The post's "run code you don't fully trust" workflow inverts here.
- Every "24/7" number in the post is bounded by the shared Max quota first (repo-measured same pool), then by the desk's serialized land gate, then by routine caps. None of the post's features adds quota or land capacity.

## 1 · Marketing-shaped claims vs primary sources

| Post claim (2026-10-06) | Primary source | Verdict for an unattended lane |
|---|---|---|
| Credential "can push only to its own working branch" | `cloud-environments.md:242` "It doesn't limit which branches a push can update. To do that, use branch protection rules or rulesets"; `security.md:103` credential is "scoped to that session" (not to a branch); public #85454 (2026-08-10): `git push -f origin main` succeeded from a cloud session | **False as stated (D).** Not re-measured on a live session today (out of scope) |
| Three sessions done in 61/65/72 s | Post's own caveat: "small sample repository… made up", repo recreated from files in the prompt, a Node API with 3 harbors | Toy. Repo's measured cloud wall for a one-file task is 437 s mean, n=2 (`docs/plans/CLOUD_BACKLOG_PIPELINE.md:146`, 2026-08-11); desk land gate median 344 s, max 3,977 s (`docs/research/cloud-lane-redesign-2026-09-10/LEAD-notes.md:15`) |
| "The repository's Claude config comes along" | `cloud-environments.md:271-281` | Here that is 1 command and 2 rule files; see §2 (**M**) |
| "Routines run without approval prompts" | Issues #94004, #92797, #95384, #97266, #99820 (§5); changelog 2.1.292/2.1.275 still changing which artifact writes prompt | **Contradicted by public reports (D)** |
| "come back to a branch that's ready for review" | `routines.md:306`: "A green status… does not mean the task in your prompt succeeded"; changelog 2.1.286: never-started runs "showing as Succeeded" until fixed | Green is an infra signal only (D) |
| "Idle VMs get reclaimed… conversation restored" | `claude-code-on-the-web.md:417-422`: not restored = "background work that was still running… subagents and shell commands"; `cloud-environments.md:390`: pause "after a few minutes without activity" | No number given for the idle window anywhere (gap). A session waiting on the desk's inbox answer is idle by definition |
| VM "about 4 vCPUs, 16 GB, 30 GB" | `cloud-environments.md:373-379` "approximate… may change"; "The VM may stop tasks that need significantly more memory" | Matches. Post omits the OOM-stop sentence |
| "Foreground commands time out after 2 minutes (10 at most)… background up to 30 more" | `cloud-environments.md:385-387` | Matches. 600 s + 1,800 s = 2,400 s default ceiling per command (calculated) vs this repo's 3,977 s max gate (**I**: VM is 4 vCPU vs the desk's 10 cores, so slower still) |
| Clone | Docs never state clone depth (**M**: `grep -i 'shallow\|depth'` over 9 fetched doc pages hits only review/unshallow error text) | Repo measured a 50-commit shallow clone 2026-08-10/11 (`CLOUD_BACKLOG_PIPELINE.md:104-106`). Post and docs are silent on the lane's "single biggest determinant of cloud-suitability" |
| `Claude-Session` trailer links the transcript | `cloud-environments.md:335`; off switch `attribution.sessionUrl=false` | Here the trailer is a land refusal: `commit-msg: BLOCKED — the message carries an AI-authorship trailer` (`CLOUD_BACKLOG_PIPELINE.md:1272-1281`) |

## 2 · What happens on a repo whose tooling lives in `~/.claude`

Measured in the worktree 2026-10-07 (`ls | wc -l`, `python3 json.load`, `grep -rIl`):

| Thing | Count here | Travels to a VM? |
|---|---|---|
| `.claude/skills/` | 0 | — |
| root `skills/` (symlinked into `~/.claude/skills`) | 37 | No: not under `.claude/` |
| root `hooks/` | 99 | No: `.claude/settings.json` has keys `_what, _why_disabledMcpjsonServers, disabledMcpjsonServers, permissions` and **no `hooks`** |
| `bin/` tools | 140 | Files yes, PATH and stores no (`~/.claude/autonomy/backlog.jsonl` is machine-local, plan `:113-116`) |
| `tests/*.bats` | 974 | Files yes; runner version not (Ubuntu archive bats 1.10.0 could not load 3 of 556 suites; `docs/research/venue-runner-version-2026-08-29.md:8-13`) |
| `.mcp.json` | absent | — |
| `.claude/commands/` | 1: `ship.md` (28,495 bytes) | **Yes** |
| `.claude/rules/` | 2 files (78,647 + 10,026 bytes) | Yes |
| tracked code reading `CLAUDE_CODE_REMOTE` | 0 files outside `docs/` | No cloud-only hook exists |

- **The one thing that travels is the land command; every control that makes it safe stays home.** `/ship` reaches the VM as a project command. The identity gate is `githooks/` installed per machine by `scripts/git-identity-assert.sh` (trace doc `:8-10`); git never clones hooks or `core.hooksPath`. That is exactly how the 93 commits landed: "cloud VMs ran `/ship` from their own hookless clones and pushed main" (commit `13d8a9d98` body). **M** (repo's own trace).
- **The landing lock is not a cross-machine mutex.** `scripts/land-lock.sh:21`: lock dir is `/tmp/land-lock-<hash(shared-git-dir)>/lock.d`. A VM running `/ship` holds a lock in its own `/tmp` and serializes with nothing; the "last-moment re-fetch" is its only race guard. **I** from the file path.
- **The post's remedy collides with this repo's architecture.** Post: "move what the team needs into the repository: commit skills and commands under `.claude/`". This repo *is* the user layer; a project-scope copy of the same skills or hooks would load twice locally. The repo already measured that class once: a root `CLAUDE.md` duplicated ~20.7K tokens per session (`.claude/CLAUDE.md:82-91`). Repo hooks in `.claude/settings.json` would also fire alongside the user-level ones unless each exits early on `CLAUDE_CODE_REMOTE != true`. **I**.
- **Widening to multi-repo sessions drops even that.** "A session with several repositories… starts above the clones and doesn't read them" for hooks, permission rules and `.mcp.json` (`cloud-environments.md:272-273`, `:492`). Plugins declared in repo settings are never installed (`:276`). **D**.
- **`claude --cloud` may not clone this repo at all.** Docs: from a repo "the Claude GitHub App isn't installed on, Claude Code bundles your local repository… This applies even if you connected GitHub with `/web-setup`" (`claude-code-on-the-web.md:134`). The lane links by `/web-setup` (`scripts/cloud-websetup-drive.sh:26-27`, "Connected as renchris"). Bundle limit is 100 MB with fallback to current branch, then a squashed snapshot (`:152`); GitHub reports this repo at 341,642 KB (**M**: `gh api repos/renchris/claude-infrastructure-private --jq .size`), local pack 1.15 GiB (**M**: `git count-objects -vH`, shared object store). Bundles also refuse linked worktrees with sparse config (`:161`). Disagreement to resolve: the repo's 2026-08-08 note treats a `/web-setup` link as ending bundle fallback (`cloud-websetup-drive.sh:22-24`); today's docs say otherwise. Whether the App is installed on this repo could not be read (gap).

## 3 · Security and blast radius

**Chain (each link cited):**

1. VM push to any branch of an attached repo: `cloud-environments.md:242` (D); #85454 force-push to default branch (D, 2026-08-10); 93 direct-to-main commits here (M, trace doc).
2. `main` has no server-side guard. **M** 2026-10-07: `gh api repos/renchris/claude-infrastructure-private/branches/main/protection` → `404 Branch not protected`; `…/rulesets` → `[]`; `…/rules/branches/main` → `[]`.
3. `main` feeds the live layer: "`~/.claude` is a per-file symlink farm over THIS checkout" and the converge takes "the newest NOT-RED commit"; "T1 is structurally unreachable and every real advance already comes through T2's absence-of-evidence door" (`.claude/CLAUDE.md:38-41,48-51,63-66`).
4. Live hooks and `bin/` then run as the operator, whose local sessions reach "SSH keys, cloud CLIs and `~/.claude`" (post's own comparison table).

- **What stands between link 1 and link 3 today:** one sentence of prose in the brief, "Do NOT run /ship, do NOT push to trunk" (`bin/cc-dispatch:3084`), plus a detective pager: `postland-verify.sh identity_landed_sweep`, one 5-minute tick, keyed on author/committer email (trace doc `:76-84`). The repo's own words: "Stopped by instruction, not closed mechanically" (`:62`).
- **The pager is keyed on a value the VM controls (I).** The sanctioned email is in every commit of the 50-commit clone; `git config user.email <that>` in the VM yields on-identity commits. A brief regression or an injected instruction (Trusted network reaches GitHub and registries, so fetched content is an injection surface) would then be silent.
- **A server-side rule is harder than the post's "use branch protection" (I, partly D).** The `/web-setup` path pushes with the operator's own `gh` token ("Anthropic stores it… your cloud sessions use it for GitHub access", `web-quickstart.md:93`), and the desk lands as the same GitHub user. GitHub sees one actor, and "a rule that access can bypass doesn't block" (`security.md:104`). The trace doc ruled out only the author-email metadata rule (Enterprise Cloud; `:86-95`). Not evaluated there: a `main` ruleset with an empty bypass list plus a distinct landing actor (deploy key or machine user), or pointing cloud sessions at a mirror repo that the desk fetches from. Both are hypotheses; neither is tested.
- **Token reach is wider than one repo (D).** "/web-setup (your gh token)… Whatever your token can reach" (post table); "A cloud session you start yourself can then access any repository that token can access" (`web-quickstart.md:93`). The proxy scopes *API* calls to attached repos (`cloud-environments.md:243`); the repo observed the attached set enforced for git too (`CLOUD_BACKLOG_PIPELINE.md:1400`, August).
- **Setting `GH_TOKEN` to get `gh` working defeats the proxy model (D).** "If you set a token, it passes through to the container unchanged" and "anyone who uses the environment can read it" (`cloud-environments.md:322-325`).
- **Exfiltration survives network level None (D).** "Claude Code still sends requests to the Anthropic API, so data can leave the VM that way, and the session can still push to its own branch" (post, workflow 7; `claude-code-on-the-web.md:367`). At Trusted, package registries are reachable; publishing to one is an outbound channel (**I**).
- **Cleanup is one-way (D + M).** The proxy "rejects branch deletions" (`:242`; #99384, 2026-10-04, 12 stale branches). **M**: `git ls-remote --heads origin 'claude/*' | wc -l` → 341 heads on this remote.
- **Auto-fix speaks as the operator (D).** Replies "post under your GitHub username"; a comment can trigger comment-driven automation (`claude-code-on-the-web.md:356-359`).

## 4 · What makes "24/7" structurally bounded

| Bound | Number | Source / method |
|---|---|---|
| Quota pool | Same pool as local; +0.143 to +0.145 weekly-pp per fire | Repo **M** 2026-09-10 (`cloud-lane-redesign-2026-09-10/C1-quota-pool.md`, E1 p=6.5e-06, E2); docs **D** `claude-code-on-the-web.md:428`; post "five sessions use them about five times as fast" |
| Quota ceiling | ~694 fires per account-week (~99/day) if the whole weekly meter went to cloud | **Estimated**: 100 pp / 0.144 pp. Fires span a 28x token range (plan `:124-130`), so this is an order of magnitude |
| Quota headroom when last read | next 100% LIMITED, next2 95%, next4 73%, next3 51%; "all four on pace to fill" | `LEAD-notes.md:19` (2026-09-10; stale, not re-read today) |
| At the limit | Plain sessions: "Claude Code blocks further requests until the reset" (`errors.md:695`). Routines: "additional runs are rejected" without usage credits (`routines.md:392`). Projects threads wait and retry (`claude-projects.md:399`) | **D**. Three different behaviours for one meter |
| Desk land arm | 12-24 lands/day capacity; 7.3 branches/day arrival; ~2 fires/day post-cure | `cloud-lane-redesign-2026-09-10.md:151-171` (2026-09-10) |
| Lands actually reaching trunk | `Cloud-session:` commits by ISO week: W37 34, W38 18, W39 24, W40 46, W41 2 | **M**: `git log origin/main --since=2026-09-01 --grep='Cloud-session:' --date=format:%G-W%V`. Newer than the memo's "delivered 0" (09-10): the arm has since been repaired; counts include doc-rescue commits |
| Routine schedule | Minimum interval 1 hour; faster cron "rejected" → 24 runs/routine/day | `routines.md:145` (**D**; division) |
| Scheduled runs | 100/hour per account; over limit "waits" | `routines.md:384` |
| Run now + API fire + one-off re-arm | 30/hour per routine (shared) → 720/routine/day | `routines.md:385`; `routines-fire.md:148` (multiplication) |
| API fires | 100/hour per account → 2,400/day | `routines.md:387`. "None of these hourly limits has overage" (`:390`) |
| GitHub-event triggers | "per-routine and per-account hourly caps. Events beyond the limit are dropped" — no number published | `routines.md:237` |
| Projects | 200 new threads/day; concurrent-thread limit you ask for "is a preference rather than a cap" | `claude-projects.md:407,240` |
| Fire idempotency | "There is no idempotency key. If a webhook caller retries, the endpoint creates multiple sessions." | `routines-fire.md:144` |
| GitHub link expiry | Routine "skips runs… for up to 72 hours", then "turns off" | `routines.md:328` |
| Env cache | Rebuilt "roughly seven days"; setup over ~5 min "isn't cached"; non-zero exit = "session fails to start" | `cloud-environments.md:413-423` |
| Stability class | Routines "research preview. Behavior, limits, and the API surface may change"; `/fire` under `experimental-cc-routine-2026-04-01` | `routines.md:10,223` |

- Ordering (**I**): quota binds first (accounts already near 100%), the desk's serialized gate second, vendor caps a distant third. No feature in the post moves the first two.
- Concurrency: no per-plan concurrent cloud-session cap is published in any page fetched (gap). The repo's own probe file calls "~15 concurrent" folklore (`scripts/cloud-ceiling-probe.sh:13-16`).

## 5 · Public failure reports since 2026-09-01 (anthropics/claude-code)

Search totals (**M**, `gh api search/issues`, 2026-10-07): `"cloud session" created:>2026-08-31` → 299; `routine in:title` same window → 77; `label:area:claude-code-web label:bug created:>2026-09-15` → 164. Bodies read unless marked (t) = title only.

| Class | Issues (created, state) | What breaks an unattended drain |
|---|---|---|
| Never starts / PENDING | #92910 (09-08, open) 30-300+ min PENDING across manual, one-shot and cron; #95450 (09-18, open) silent no-op, multi-day delay, duplicate fires; #99527 (10-04, open) schedule skipped, `next_run_at` pushed back, no run recorded; #91758 (09-03, t); #99640 (10-05, open) GitHub `pull_request.edited` trigger never fired; #94260 (09-14, closed) | Fire returns an id; nothing runs; no error |
| Hangs after start | #97266 (09-25, open) frozen after `set_permission_mode`, >1 h; #95384 (09-18, open) "no available force-stop", three surfaces disagree on status; #94779 (09-16, dup) ~11 fires over a month, 0 completions | Row held forever; status untrustworthy |
| Green with no work | #94295 (09-14, open) prompt never delivered, run marked complete; #97895 (09-28, open) side-effect tool no-ops, run `SUCCEEDED`; #92797 (09-08, open) five `tool_use` with null results then `run_once_fired`; changelog 2.1.286 fix | Success signal is not completion evidence |
| Prompts nobody can answer | #94004 (09-13, open) ~3 Allow prompts in one scheduled run; #91883, #92006, #91748, #94595, #96967 (t) | Contradicts "run without approval prompts" |
| Auto-mode classifier denials | #99820 (10-06, dup) "no human turn… The run dies silently"; #97654 (09-27, open) since ~2.1.268, users forced to `bypassPermissions`; #95200 (09-17, open) 12x denials since 2.1.270; #98109 (09-29, open) identical command allowed on retry | Non-deterministic refusal mid-task. **I**: a repo made of permission hooks, launchd plists and settings is a likely target |
| Repo access / GitHub scope | #97480 (09-26, open) API-created triggers start with no repository; #98588 (10-01, open) attached repo unreadable, no `add_repo`; #93106 (09-09, open) personal private repo 403 with App installed; #99528 (10-04, open) `claude --cloud` auth fails under `url.insteadOf`; #92529 (09-06, open) OAuth tokens missing `user:sessions:claude_code`; #96075, #96609, #98524 (t) | Applies to a user-owned private repo like this one |
| Push | #85454/#85456 (08-10, closed inactive) force-push to default allowed, delete denied; #99384 (10-04, open) same, still; #95576 (09-19, open) tag push 403 | See §3 |
| Network | #96260 (09-23, dup) scheduled runs ignore "Full" network setting; #95671, #92706 (t) | Environment setting not honoured on the routine path |
| Wrong model | #96219 (09-23, open) API-fired routine runs Sonnet though set to Opus, every fire since 09-07; #99881 (10-06, t) | Silent quality change per trigger path |
| Quota / credit | #99597 (10-05, open) credit shown, unusable at weekly limit; #99166 (10-03, open) "wrong usage pool"; #98888, #97021 (t); #99852 (10-06, open) Max account closed after claiming credit and running heavy cloud workloads (single unverified report); #97218 (09-25, open) ~30x background API activity in long web sessions; #99568 (10-05, open) 41%→92% weekly in one day with 3 cloud sessions | Meter and credit behaviour are disputed in public |
| Lifecycle | #93549 (09-11, open) finished routine sessions never ended, 14 resident after 10 days until capacity fills; #94836 (09-16, open) `--teleport` restores only the first turn; #99271 (10-03, open) Projects shared folder EIO at exactly 24 h | Long-lived containers and slots leak |

- Status page (**M**: `curl status.claude.com/api/v2/incidents.json`, 50 returned): 9 incidents tagged with the Claude Code component since 2026-09-01, all model-error incidents; none names cloud sessions or routines. The PENDING reports of 09-08 and 09-18 have no matching incident, so a status poll will not explain a non-start (**I**).
- Third-party write-up of the same class: <https://runbook.scosovan.com/claude-code-routine-reported-success-did-nothing/> (HN 49970942, 2026-10-05).
- The post itself drew 2 points, 0 comments on HN (item 49980091, **M** via Algolia 2026-10-07): no independent field reports of the post exist yet. Reddit search returned nothing dated after March 2026 (not a negative finding; search was shallow).

## 6 · Releases after v2.1.284: fixes that describe our version's behaviour

Changelog fetched 2026-10-07 (`raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md`); newest is 2.1.292, eight versions past ours. Cloud-tagged share: 15 of 92 entries in 2.1.292, 17 of 190 in 2.1.290 (**M**, regex count).

| Version | Entry (verbatim, trimmed) | Reading |
|---|---|---|
| 2.1.286 | "Fixed routine runs whose cloud session never started showing as Succeeded… they now show as Failed" | At 2.1.284 a non-start read green |
| 2.1.287 | "Fixed occasional failures to fetch from or push to GitHub when GitHub briefly refused a newly issued access token" | The push is the lane's completion signal |
| 2.1.283 | "Fixed cloud sessions occasionally redoing an already-finished step, such as posting a duplicate comment or push, after recovering from a server-side restart" | Duplicate side effects existed through 2.1.282 |
| 2.1.283 | "routines set exactly on the hour can start several minutes late" | Schedule jitter is acknowledged |
| 2.1.290 | "Fixed cloud sessions staying asleep after a container restart lost a pending `/loop` wakeup or scheduled task" | Container restarts drop timers |
| 2.1.291 | "Fixed a regression in 2.1.290 where cloud sessions could drop answers to permission prompts" | A two-entry release fixing the prior one |
| 2.1.292 | "Fixed routine runs occasionally staying listed as running for hours after they had finished"; "Fixed a cloud session showing a turn that never ended when its worker was stopped just as the turn finished" | Status still being repaired this week |

- Caveat (**I**): "[Cloud sessions]" entries are largely service-side and the VM runs Anthropic's runner, not the desk's binary. Upgrading the local CLI does not pin the VM's behaviour, and the operator cannot hold the VM at a known-good version. The cadence itself (8 releases after 2.1.284, through 2.1.292) is the cost: lane behaviour changes without a local diff.

## 7 · The promotional credit

- Terms: "you authorize Anthropic to enable Usage Credit on your account if it is not already enabled" (<https://www.anthropic.com/legal/promotion-credit-terms>, fetched 2026-10-07). Credit is "applied automatically before your payment method is charged"; forfeited on cancel, downgrade or suspension.
- Consequence (**I**): claiming switches metered overage on. With usage credits on, routines "keep running… on metered overage" past the plan limit (`routines.md:392`). An unattended lane on such an account can bill the card once the $250 is spent or expires 2026-11-04, unless a spend cap is set. Whether these four accounts already have usage credits on was not read.
- Post: the credit "isn't eligible for Projects or Routines". Whether sessions created by `POST /v1/sessions` (the lane's path, `scripts/cloud-create-api.py`) count as "cloud sessions" for the credit is unstated (gap).
- Claim deadline is 2026-10-07, so this decision has a clock; the overage switch above is the reason not to claim by reflex. Public confusion: #99597, #99166, #98888, #97021; one closure report #99852.

## 8 · Alternatives considered

| Alternative from the post | Why it does not rescue an unattended drain |
|---|---|
| Routines with API fire as the dispatcher | No idempotency key; 30/hour/routine; research preview; model selector ignored on the API path (#96219); API-created triggers start with no repo (#97480); PENDING without error (#92910, #95450); credit-ineligible |
| Projects coordinator | Pro/Max public beta; 200 threads/day; thread cap is "a preference"; coordinator does not load the repo's `CLAUDE.md`/hooks and is replaced "routinely and invisibly" (#99610, 10-05); multi-repo threads read no repo hooks |
| Self-hosted environment (would restore `~/.claude`) | "in beta for Team and Enterprise" (post); the accounts are Max. It would also run on the box, which removes the only edge the VM has |
| `/autofix-pr` | Needs the Claude GitHub App and a PR flow; this repo lands by gated direct push under a lock, and its commit-msg hook refuses the session trailer |
| `claude -p "…" --cloud <id>` for steering | Returns `{ok, session_id, url}` for the *send* only (`claude-code-on-the-web.md:196`). No completion webhook or status API appears in the cloud pages fetched (**M**: grep for webhook/notif/poll/completion hit only the auto-fix conflict note), so "no wake on completion" (plan `:87`) is unchanged |

## 9 · Adversarial pass on these findings

- **"The post is newer than the docs, so the credential may now be branch-scoped."** Both were read the same hour and disagree; `security.md` and `cloud-environments.md` agree with each other and with the repo's 2026-10-02 trace. The live behaviour was not re-tested (it would need a cloud session). Treat the push as open until a probe says otherwise.
- **"93 commits is history; the brief fixed it."** True for 2,463 commits since 09-05 (trace doc `:24-25`). The control is prose, and the detector keys on a VM-settable field. A cure that has held for a month is evidence about the brief, not about the boundary.
- **"Routine failures don't apply; the lane creates sessions by API, not routines."** Correct that the lane uses `POST /v1/sessions`. The hang, classifier, repo-access and push classes are session-level and apply; PENDING and schedule-skip classes apply only if the lane moves to routines, which is what the post invites.
- **"The quota ceiling is made up."** It is one division on a repo-measured marginal from 09-10 and is labelled estimated; fires vary 28x. Its use is ordering the bounds, not planning.
- **"Issue counts prove little."** Agreed: search totals are full-text and noisy. The table rests on bodies read, each dated, most open, several with session ids and repro.
- **Disagreements left standing:** `gh` in the VM — repo says absent (2026-08-10, plan `:107`), docs say pre-installed (`cloud-environments.md:306`), #97973 (09-28, t) says absent in some sessions. `/web-setup` vs bundle fallback — §2.

## 10 · Gaps

- Whether a cloud session can push `main` of this repo today (docs and repo history say yes; not probed).
- Whether the Claude GitHub App is installed on `renchris/claude-infrastructure-private` (`gh api /user/installations` → 403 for this token type), which decides clone vs bundle for `claude --cloud`.
- The idle window before pause/reclaim, and any per-plan concurrent-session cap: no number in any page fetched.
- Numeric caps for GitHub-event triggers.
- Which GitHub actor the proxy presents on the App path, and therefore whether a ruleset could tell a VM push from a desk push.
- Whether API-created sessions are credit-eligible; whether the four accounts have usage credits enabled.
- Permission mode of the lane's API-created sessions (not found in `scripts/cloud-create-api.py` by grep).
- Current account utilization (last read 2026-09-10).
- Reddit and HN carry no substantive discussion of the post yet.

Receipts: scratch copies of every fetched page are `/tmp/cloud-blog-eval/.c1-*`. Nothing in the subject repo was modified; no session, routine, credit claim or dispatch was started.
