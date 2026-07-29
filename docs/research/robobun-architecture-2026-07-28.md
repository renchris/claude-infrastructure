# robobun — architecture, configuration, and a recreation blueprint

**Date:** 2026-07-28 · **Subject:** `github.com/robobun` (id `117481402`), the autonomous agent
account operating in `oven-sh/bun` · **Question:** how is it built, and can we rebuild an
equivalent proactive GitHub agent account?

**Answer up front: yes, and most of it is already public.** Bun's repo-side agent configuration
(`CLAUDE.md`, `REVIEW.md`, `.claude/hooks/`, `.claude/commands/`, `.claude/skills/`) is committed
in the open and is directly copyable. What is *not* public is the orchestrator — the queue, the
fleet, and the harness that emits the evidence block. That layer has to be rebuilt, and §7 gives a
runnable substitute for every piece of it.

The single most important finding is not the plumbing. It is that **robobun's leverage comes from a
publication gate, not from the model**: no PR ships without either a machine-checked
fails-before/passes-after proof, or a structured abstention drawn from a closed vocabulary. That one
mechanism is what separates 6,691 PRs from 6,691 pieces of slop, and it is the part most
recreations would skip.

---

## Method and provenance

13 agents over ~34 min (1.53M tokens, 387 tool calls): 8 parallel evidence sweeps → 4 adversarial
verifiers instructed to *refute* the load-bearing claims → 1 synthesis. All findings rest on the
authenticated GitHub REST/GraphQL API, the `oven-sh/bun` git tree, and public web sources. The lead
then ran four further experiments directly (§0) that corrected the synthesis.

**Two of the four seed claims were refuted by the verifiers**, which is the main reason to read §6
before acting on anything: the branch token is *not* a per-task id, and the work is *not*
predominantly self-directed (it was 75.6% issue-linked in 2026-01). A confident-but-wrong
architecture claim here would poison the rebuild.

**Epistemic key**, used throughout: **OBSERVED** = the bytes were read. **INFERRED** = reasoned to
from observed facts. **UNKNOWN** = not determinable from public evidence; where a blueprint step
depends on one, a defensible modern substitute is given and marked.

**Reproducibility note.** Every count below is a live API read on 2026-07-28/29 against a moving
target — robobun opens ~142 PRs/day, so absolute counts drift daily. Ratios are stable; absolute
numbers are timestamped, not permanent.

---

## 0. Lead-run experiments (these CORRECT the synthesis below)

Four experiments the synthesis flagged as unrun-and-load-bearing. Two overturned its conclusions,
so they are stated here, ahead of the body.

### 0.1 Who closes robobun's unmerged PRs — REFUTES the "stale-bot inflates the merge rate" theory

§5 warns that the 90-day auto-closer inflates the closed-unmerged denominator. It does not. Over a
400-PR sample of `is:closed is:unmerged` (GraphQL `ClosedEvent.actor`):

| closer | n | share |
|---|---|---|
| **robobun (itself)** | **332** | **83.0%** |
| Jarred-Sumner | 35 | 8.8% |
| github-actions (stale-bot) | 22 | 5.5% |
| alii | 8 | 2.0% |
| dylan-conway | 3 | 0.8% |

**The dominant close reason is self-suppressed duplicates.** Sampling the closing comments, they
are overwhelmingly of this literal shape:

> `Duplicate of #N, which opened first with the same … re-arm removal.`
> `Duplicate of #N (opened a few minutes earlier). The writevAll piece this PR adds on top is noted there; branch farm/2fbac61b/writestream-short-wr…`
> `Duplicate of #N, which landed the same clang-cl bypass a moment earlier (the two handoffs were different … files from the same build #N)`
> `Closing: this is an investigation with a negative result (benchmark shows no speedup, slight regression on wide directories).`

**Architectural consequence, and it is a big one: the queue does not deduplicate before dispatch.**
Parallel workers independently pick the same bug, race to a PR, and the collision is cleaned up
*after the fact* — which is exactly why `.claude/commands/find-duplicate-prs.md` exists in-tree.
Phrases like "a few minutes earlier" and "~40 min earlier" put the collision window in minutes,
confirming wide concurrency. **A rebuild must either lease work items at dispatch (cheap, do this)
or budget for ~50% of its output being withdrawn duplicates (what Bun evidently accepts).**

The "negative result" close is also notable: abandoning work with a published reason is a
first-class outcome, not a failure.

### 0.2 Revert rate of merged agent PRs — the quality question, answered

The synthesis called this "the highest-value unrun experiment." Method: collect revert-subject
commits on `main` (137 found), extract the referenced PR numbers (102 resolvable), look up each
PR's author.

| cohort | merged PRs | explicitly reverted | rate |
|---|---|---|---|
| **robobun** | **1,776** | **6** | **0.34%** |
| all humans | 7,238 | 96 | 1.33% |
| robobun, created <2026-04 | 590 | 6 | 1.02% |
| **robobun, created ≥2026-04** | **1,186** | **0** | **0%** |

The six reverted robobun PRs are `#25602, #25667, #27114, #27175, #27214, #27829` — **all from
2025-12 → 2026-03, none from the current gated era.** Authors of reverted PRs overall are led by
`Jarred-Sumner 26, nektro 16, dylan-conway 13, paperclover 7, 190n 6, robobun 6`.

**Read this carefully — four caveats, and they matter more than the headline.** (1) It counts
*explicit* reverts only; a silent fix-forward is invisible, and agent bugs may be
disproportionately fixed forward. (2) Humans merge the large, risky changes (WebKit upgrades,
mimalloc v3) that get reverted wholesale; robobun's median PR is 150 LOC / 4 files, so its blast
radius is structurally smaller — this is a comparison of *populations*, not of *equal work*.
(3) Recency: the post-2026-04 cohort has had ~4 months, less than the earlier one. (4) The real
quality filter may simply be the two humans refusing to merge — a 26.6% merge rate means the
selection happens before `main`, so this measures *what survived review*, not *what the agent
produced*.

With those caveats stated: there is **no evidence in the public record that merged agent PRs
destabilise `main` more than human PRs**, and the zero-revert post-gate cohort is consistent with
the evidence gate working as designed.

### 0.3 Merge-rate denominators (timestamped 2026-07-28)

`is:pr is:merged` repo-wide = **9,014**; robobun's share = **1,776 (19.7% of all merges)** against
**~38% of all PRs ever opened**. Agent PRs are merged at roughly half the rate of human PRs.

### 0.4 What `AGENTS.md` actually returns

`AGENTS.md` is `mode 120000` — a symlink to `CLAUDE.md`. Fetching it over
`raw.githubusercontent.com` returns the **9-byte string `CLAUDE.md`**, not the instructions. Any
scraper that concludes "this repo has no agent instructions" has been fooled by a symlink.

---

## 1. What robobun is

**Identity (OBSERVED).** `robobun` is a plain GitHub **User** account — `id 117481402`, `createdAt 2022-11-04T19:40:24Z`, `type: User`, `isEmployee: false`, `isSiteAdmin: false`, `company: "@oven-sh"`, `websiteUrl: bun.com`, `location: San Francisco, CA`, `organizations.totalCount: 0`, `repositories.totalCount: 24`. It is **not** a GitHub App, not a `[bot]` account (`gh api users/robobun%5Bbot%5D` → 404; `gh api apps/robobun` → 404).

**Not app-driven (OBSERVED, with a positive control).** `performed_via_github_app` is `null` on **600/600** sampled robobun issue comments across 10 pages (`repos/oven-sh/bun/issues/comments?per_page=100&page=1..10`), and null across 8 historical `since=` epochs back to its first comment `2022-11-10T20:40:07Z`. The field is live on that endpoint — same responses carry `('coderabbitai[bot]','Bot','coderabbitai') 206` and `('github-actions[bot]','Bot','github-actions') 128`. The critical control the recon lacked and the adversary supplied: **a User-type actor driven by a GitHub App DOES populate the field** — `gh api "repos/vercel/next.js/issues/comments?..."` returns `{"login":"lukesandberg","type":"User","app_slug":"graphite-app","app_id":158384,"app_owner":"withgraphite"}`. robobun's null is therefore decisive, not a type artifact.

**Credential (OBSERVED mechanism, UNKNOWN which token).** A long-lived **user token** is directly evidenced in-tree: `.github/workflows/release.yml` uses `token: ${{ secrets.ROBOBUN_TOKEN }}` twice. `gh api users/robobun/keys` → `[]` (no authentication SSH key published), and `CreateEvent` payloads report `"pusher_type": "user"` — so the push credential is a token over HTTPS, not a deploy key. PAT vs OAuth-App token is **not externally distinguishable** (both yield a null app field).

**Two distinct write channels (OBSERVED).**

| Channel | Identity on commit | Signature | Origin |
|---|---|---|---|
| "farm" — the AI PR fleet | `robobun <117481402+robobun@users.noreply.github.com>` as **both** author and committer, TZ `+0000` | SSH ed25519, `verified: true, reason: "valid"` | local `git commit -S` on a real machine |
| release plumbing | `robobun <robobun@oven.sh>` | PGP, key `8EAB4D40A7B22B59` (fingerprint `F3DCC08A8572C0749B3E18888EAB4D40A7B22B59`, created 2023-01-25) | GitHub Actions in oven-sh/bun using `ROBOBUN_TOKEN`, pushing to `oven-sh/homebrew-bun` + `oven-sh/DefinitelyTyped` |

The farm signing key: `gh api users/robobun/ssh_signing_keys` → `[{"id":930414,"key":"ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGB+6ij0Wwzjp/9kw1Ke0ffFi6D2Akl10K2EPzBfYvBu","title":"Robobun on farm signing key","created_at":"2026-05-04T17:54:58.944-07:00"}]`. The embedded pubkey in commit `2ec5b47455`'s signature blob (`U1NIU0lHAAAAAQAAADMAAAALc3NoLWVkMjU1MTkAAAAgYH7qKPRbDOOn/2TDUp7R98WLoPYCSXXQrYQ/MF9i8G4`) matches byte-for-byte. **The 2026-05-04 key creation date dates the farm architecture**; the account itself predates it by 3.5 years as CI/release plumbing.

**Permission model (OBSERVED / partially UNKNOWABLE).** `author_association` = `COLLABORATOR` on 201/201 comments and 99/100 recent PRs. This is **not** evidence of outside-collaborator status: `Jarred-Sumner` (org owner) also returns `COLLABORATOR`, while public org members (`alii`, `cirospaciari`, `dylan-conway` — confirmed via `gh api orgs/oven-sh/public_members`) return `MEMBER`. The field tracks membership *visibility*. Either way robobun holds **direct push** to `oven-sh/bun` — 477/477 sampled PR head repos are `oven-sh/bun`, **never a fork**. The literal permission level is unobtainable: `gh api repos/oven-sh/bun/collaborators/robobun/permission` → 403 `"Must have push access to view collaborator permission."`

**The asymmetry that makes it safe (OBSERVED).** robobun **assigns** `Jarred-Sumner` to its own PRs 1 second after creation, and **never merges**. Over 60 recently-updated merged robobun PRs: `mergedBy Counter({'Jarred-Sumner': 42, 'dylan-conway': 18})`. Write + triage for the fleet; merge is human-only.

**Also a shared service account (OBSERVED — critical disambiguation).** `robobun` is the Buildkite fleet orchestrator (`scripts/agent.mjs: const requiredTags = ["robobun", "robobun2"];`, `scripts/machine.mjs: "robobun": "true", "robobun2": "true"`, `.buildkite/ci.mjs: robobun: true, robobun2: true`, `scripts/packer/windows-x64.pkr.hcl: // robobun launches runners from this image`) **and** the release signer (`packages/bun-release/scripts/upload-assets.ts: "F3DCC08A8572C0749B3E18888EAB4D40A7B22B59", // robobun@oven.sh`). ~30% of its issue-comment volume is the Buildkite CI notifier, not agent output. **Filter on `<!-- generated-comment id=` before drawing any behavioral conclusion.** Occurrences of "robobun" in bun's *source* are about CI, not AI.

---

## 2. Architecture (as best established)

### Stage-by-stage epistemic status

| Stage | PROVEN | INFERRED | UNKNOWN |
|---|---|---|---|
| **Task generation** | Two streams exist: issue-linked (32.9% of 6,691 PRs carry a `closingIssuesReferences`) and unlinked. `.claude/commands/find-issues.md` retro-attaches `Fixes #N` to already-open PRs. | An internal work queue produces the unlinked stream (spec-conformance, dead-code, hardening, Node/Web gaps). | The queue's source (fuzzing? test-suite diffing? crash telemetry? — robobun's own gists reference "9,081 crashes from Discord with stack traces (15MB)") and its scheduler. No in-tree definition. |
| **Agent execution** | Stock Claude Code reading in-repo `.claude/` config. `pre-bash-guard.js:178` hardcodes `cwd === "/workspace/bun"`. `.claude/skills/verify/SKILL.md` instructs `PATH="$HOME/.cargo/bin:$PATH"` to dodge Homebrew shadowing the pinned rust nightly. | Persistent **macOS** developer machines (Homebrew/rust collision is macOS-specific) with warm checkouts, containerized at `/workspace/bun`; likely Bun's own EC2/Azure fleet tagged `robobun=true`. Full local debug+ASAN builds → minutes-to-tens-of-minutes per iteration. | Model, effort, harness code, concurrency, per-task budget. `gh search code 'robobun:evidence'` → `[]` globally — the harness is nowhere public. |
| **Branch push** | Local `git commit -S` with the SSH farm key; `pusher_type: "user"`; pushed into `oven-sh/bun` directly. | HTTPS + token remote. | Whether the token is `ROBOBUN_TOKEN` or a separate farm PAT. |
| **PR open** | Self-assigns `Jarred-Sumner` at `createdAt` exactly. Body carries a harness-generated evidence footer. | PR opened by the same token, immediately after the gate passes. | Whether the gate runs pre- or post-push. |
| **CI** | Buildkite is the real gate (`buildkite/bun/{darwin-aarch64,darwin-x64,linux-x64,linux-aarch64,linux-aarch64-musl,linux-x64-asan}-build-cpp`). GitHub Actions runs only lints: `Source lints`, `Format`, `cargo clippy`, `Lint JavaScript`, `comment-cop`, plus app `claude`'s `Claude Code Review`. `actions/runs?actor=robobun` → **122,535**, 100% reactive `pull_request`/`pull_request_target`. | — | — |
| **Review** | Reviewers are `claude[bot]` (Anthropic's App `anthropics/claude`, id 209825114, install 1236702), `coderabbitai[bot]`, and repo-local `comment-cop`. robobun replies to threads and pushes fixes. | Review-comment webhooks re-invoke the worker. | The webhook plumbing. |
| **Merge** | 100% human: Jarred-Sumner (42/60) + dylan-conway (18/60). Median open→merge **3.2h**. No auto-merge. | — | — |

### Where the orchestrator is NOT (OBSERVED, exhaustively)

- All 35 workflow files on `main` downloaded and grepped: only PR-creating mechanisms are 11× `update-*.yml` + `update-vendor.yml` (`peter-evans/create-pull-request` with `GITHUB_TOKEN`, branch `deps/update-<dep>`, authored by github-actions[bot]) and `release.yml` (`ROBOBUN_TOKEN`, `push-to-fork: oven-sh/DefinitelyTyped`).
- The string `farm` appears in **zero** of the 20,713 tree paths.
- `actions/runs?event=repository_dispatch` → **total_count 0**.
- `event=push` runs with `head_branch` starting `farm` → 0 of latest 100.
- Full workflow registry (44 incl. deleted/off-main): `Droid Focused Review` and `UB Review Packet` each have `total_count: 1`.
- A `.github/workflows/claude.yml` **did** exist 2025-05-19 → deleted 2025-11-27 (`69b571da41`, "Delete claude.yml workflow (#25157)"). It ran `anthropics/claude-code-action@v1` with `claude_code_oauth_token`, but on **self-hosted runners** (`runs-on: claude`, `container: image: localhost:5000/claude-bun:latest`, `--privileged`) under a *different* identity: `git config --global user.email "claude-bot@bun.sh" && git config --global user.name "Claude Bot"`. Deleted ~8 months before the current firehose.
- `gh search code "claude-code-action" --repo oven-sh/bun` → **zero results**. No `@claude`-mention responder exists.

**Residual unknown, stated plainly:** a private-repo GitHub Actions workflow holding a robobun PAT would be publicly *indistinguishable* from a laptop push. "Not in oven-sh/bun's workflows" is OBSERVED; "off-GitHub entirely" is strongly INFERRED (SSH farm key, `/workspace/bun`, abstention reasons like *"Platform-specific test(s) that do not run on this machine"*).

### Branch grammar

```
farm/<token>/<slug>              861/1000 recent PRs
claude/farm/<token>/<slug>        99/1000
claude/<token>/<slug>             23/1000
claude/<slug>                     17/1000
claude/farm-<token>-<slug>        rare dash-flattened variant
farm/<slug>                       rare (oven-sh/WebKit only, no token)
```

Dash-flattened literals: `claude/farm-3639d39d-serve-http2`, `claude/farm-23bb6507-exec-maxbuffer-cap`, `claude/farm-442a7a0c-serve-status-text`, `claude/farm-75208987-blocked-notice-without-hasinstallscript`. Non-farm task class: `claude/webkit-upgrade-2e37adcc23b7`, `claude/autoinstall-concurrent-cache-race`.

The slash/dash inconsistency + intermittent `claude/` prefix (Claude Code's own default) means **the model names the branch freehand from an instruction**; the orchestrator supplies only the `farm/<token>` convention as prompt text. Do not build a parser that assumes a rigid contract.

### What the token actually is — REFUTED and corrected

**It is NOT a git sha prefix (confirmed).** 11/11 sampled tokens → HTTP 422 `{"message":"No commit found for SHA: 05142769","status":"422"}`. 0/255 branch head oids start with their own token. Three sibling branches all share `merge_base_commit.sha = 59242d6c891b576c55b61bfff823ae9e55b8648e` regardless of token.

**It is NOT a per-task/per-session unique id (refuted).** Full enumeration via GraphQL `refs(refPrefix:"refs/heads/", query:"farm/")` paged to exhaustion:

| repo | farm branches | distinct tokens | reused tokens | branches in reused sets | max set |
|---|---|---|---|---|---|
| oven-sh/bun | 3,652 | 3,586 | 47 | 113 (3.1%) | 6 |
| oven-sh/WebKit | 65 | 60 | 3 | — | 2 |

Expected random 32-bit collisions at n=3,586 is **0.0015** → observed reuse is **~31,000× above chance**, i.e. deliberate. Reused sets are unrelated tasks producing **separate PRs**:

- `farm/d8266e41/` — 6 branches → #28313, #28349, #28368, #28413, #28529, #28550 (null-deref family, 5 days)
- `farm/898354b3/` — 5 branches → #28353, #28355, #28365, #30667, #31605 — spanning **70 days** (2026-03-21 → 2026-05-30), which kills "session id"
- `farm/73f947d6/` — 6 branches, a binary-size *program*: `binary-size-phase1`→#33224, `embedded-js-zstd`→#33250, `icu-repack-extend`→#33205, `lto-mergefunc`→#33247, `win-gs-minus`→#33248, `size-research`→**no PR at all**
- `farm/ed3e2d19/` — 3 unrelated SQL fixes same hour → #35115, #35116, #35119
- `claude/farm/8061134f/` — #34995 (junit outfile mkdir) + #34980 (tsconfig-override resolver warning), 1h apart, unrelated

Token is **not always 8 hex**: `farm/6BHM4p7X/update-readme`, `farm/iZZnDLtE/process-title-os`, `farm/xVz2jnWM/fix-esm-bytecode-barrel-test` are 8-char **base62, mixed case**. Sometimes absent entirely: `farm/dispatchtimer-stop-break-cycle`, `farm/yarr-named-groups-quadratic` (WebKit).

**Namespace is global across repos:** 39 tokens appear in *both* oven-sh/bun and oven-sh/WebKit — `07410bab, 0ad637d2, 178d285e, 1e6f708f, 20d9f949, 32d4c039, 379092be, 39e70373, 3a44b927, 502a9a64, 50a7f08f, 536434af, 57165bac, 5768709b, 5cc6cbfd, 7009659f, 73bfe023, 8188f1bf, 88b4f9af, 89e6ff1f, 8c72807a, 91fe31b9, 9b0a76df, c73052e6, c842455a, caec3ad2, cb50e83f, cf75b48b, d0de70bd, d1ce41e9, d738e9b8, d889cf53, e9e0550c, eb3d4eac, ebd23fe3, ee589aa8, f86769cf, fbe5fb68, fcb484e0`. `d889cf53` is the confirmed cross-repo pair: bun#36321 ↔ oven-sh/WebKit#371, both `farm/d889cf53/sync-queue-realm`.

**Correct model: `<token>` is an opaque, orchestrator-allocated, globally-namespaced, cross-repo, REUSABLE run/campaign handle. The `<slug>` branch is the unit of work (~1 branch ≈ 1 work item, usually but not always → 1 PR).**

### Flow

```mermaid
flowchart TB
  subgraph EXT["PRIVATE / OFF-GITHUB (inferred: Bun's own macOS+cloud fleet, robobun-tagged)"]
    Q["work queue<br/>issue-triggered stream + self-directed stream<br/>(source UNKNOWN)"]
    ALLOC["allocate run token<br/>8-char hex or base62<br/>reusable, cross-repo"]
    WT["git worktree per work item<br/>checkout at /workspace/bun"]
    CC["Claude Code worker<br/>reads in-repo .claude/, CLAUDE.md, REVIEW.md<br/>PreToolUse deny-hook + PostToolUse prettier"]
    BUILD["local debug+ASAN build<br/>bun bd  (10-100x slower than release)"]
    GATE{"named gate<br/>[review] / [stamp-90s]<br/>[decide:webkit] / [decide:dep]"}
    EV["harness emits evidence footer<br/>fail-on-main / pass-on-PR / diff hotspot /<br/>per-file reads·edits·tests"]
  end
  Q --> ALLOC --> WT --> CC --> BUILD --> GATE
  GATE -->|reject, iteration++ (0-8 observed)| CC
  GATE -->|pass| EV --> PUSH
  PUSH["git push origin farm/&lt;token&gt;/&lt;slug&gt;<br/>SSH-signed, author==committer==robobun"] --> PR
  PR["open PR into oven-sh/bun (never a fork)<br/>assignee=Jarred-Sumner at t+0s"]
  PR --> LBL["github-actions applies label 'claude' at ~t+16s"]
  PR --> BK["Buildkite: 6 platform build-cpp lanes + ~200 test jobs"]
  PR --> GA["GH Actions lints: Source lints, Format,<br/>cargo clippy, Lint JavaScript, comment-cop"]
  PR --> REV["reviewers: claude[bot] (anthropics/claude App),<br/>coderabbitai[bot], comment-cop"]
  REV --> LOOP["robobun replies in-thread + pushes fix commits<br/>'address review: ...' / 'Trimmed in &lt;sha&gt;.'"]
  LOOP --> BK
  BK --> STATUS["robobun posts CI-triage prose:<br/>my-diff-red vs known-flake vs fleet-infra-broken"]
  STATUS --> HUMAN{{"Jarred-Sumner / dylan-conway<br/>squash-merge — the ONLY merge path"}}
  HUMAN -->|merge, median 3.2h| MAIN["main"]
  HUMAN -->|label 'slop'| SLOP["on-slop.yml: retitle 'ai slop', overwrite body, close"]
  HUMAN -->|ignore 90d| STALE["close-stale-robobun-prs.yml: auto-close"]
```

---

## 3. Behavioral surface

### 3.1 PR authoring — the evidence footer (the single most reusable artifact)

**187 of 200 sampled recent PRs (93.5%)** contain the marker `robobun:evidence:begin`. The block is emitted by the *harness*, not the model — fixed delimiters, fixed section order, fixed counters.

Full tail of PR **#36326**, verbatim:

````markdown
<!-- robobun:evidence:begin -->

---

**[review]** gate passed · iteration 0 · 3 files touched

<details><summary>fails on main (without fix)</summary>

```console
ASAN without fix: 3 failed, 3 skipped
$ BUN_DEBUG_QUIET_LOGS=1 bun scripts/build.ts --profile=debug --quiet test "--reporter=junit" "--reporter-outfile=/tmp/mechgate.xml" test/bundler/bundler_naming.test.ts
bun test v1.4.0 (972a7fdf0)
...
release without fix: 4 failed, 3 skipped
bun test v1.4.0-canary.1 (1498d7b77)
...
```

</details>

<details><summary>passes on PR (with fix)</summary>

```console
ASAN with fix: 3 skipped
...
release with fix: 3 skipped
$ bun scripts/build.ts --profile=release
...
```

</details>

<details><summary>diff hotspot</summary>

```
src/bundler/linker_context/computeChunks.rs        | 17 ++++--
 .../linker_context/generateChunksInParallel.rs     | 20 ++-----
 test/bundler/bundler_naming.test.ts                | 67 +++++++++++++++++++++-
 3 files changed, 84 insertions(+), 20 deletions(-)
```

</details>

**gate history** · 1 passed · 0 rejected · iteration 0

<details><summary>evidence per changed file</summary>

```
file                                                    reads  edits  tests
src/bundler/linker_context/computeChunks.rs                 4      4      0
src/bundler/linker_context/generateChunksInParallel.rs      2      3      0
test/bundler/bundler_naming.test.ts                         2      3      0
```

</details>

<!-- robobun:evidence:end -->
````

**Gate line grammar** (invariant across all 99 gate lines in the 200-body sample):
`**[<gate>]** gate passed · iteration N · M files touched` … `**gate history** · P passed · R rejected · iteration N`

| gate name | count /200 |
|---|---|
| `[review]` | 82 |
| `[stamp-90s]` | 13 |
| `[decide:webkit]` | 3 |
| `[decide:dep]` | 1 |

Iteration distribution: `0:88, 1:106, 2:55, 3:20, 4:9, 5:3, 6:3, 7:1, 8:2`. **Zero `gate rejected` lines are ever published** — rejection is only visible via the tally, e.g. #36318 `**[review]** gate passed · iteration 1 · 35 files touched` + `**gate history** · 1 passed · 1 rejected · iteration 1`; #36317 `iteration 3` + `3 passed · 1 rejected`.

### 3.2 The abstention footer (88/200 PRs)

When the fail-before/pass-after proof cannot be produced, the harness emits a *structured abstention* instead. Full tail of PR **#36327**:

```markdown
<!-- robobun:evidence:begin -->

---

**no test proof** · iteration 0 · Platform-specific test(s) that do not run on this machine. Deferring to CI, which covers all platforms: test/bundler/esbuild/loader.test.ts

<!-- robobun:evidence:end -->
```

Closed reason vocabulary over 200 bodies:

| n | reason |
|---|---|
| 70 | `Platform-specific test(s) that do not run on this machine. Deferring to CI, which covers all platforms: <PATH>…` |
| 8 | `Platform-specific test-only change; deferring to CI.` |
| 7 | `docs-only change; test-proof not applicable` |
| 2 | `build/CI scripts only; test-proof not applicable` |
| 1 | `Test-infrastructure speedup; no \`src/**\` change. Coverage is unchanged (same test bodies, same assertions), the addon build path is what changed. CI is the real measurement.` |

### 3.3 PR prose schema

Heading frequency over 200 bodies: `Fix 157 · Verification 132 · Cause 106 · Repro 82 · What 58 · Problem 32 · "What does this PR do?" 32 · "How did you verify your code works?" 28 · Tests 18 · Why 17 · Reproduction 17`. Bodies typically open with a bare `Fixes #NNNNN`.

The repo template is only two lines (`.github/pull_request_template.md`, in full):

```markdown
### What does this PR do?

### How did you verify your code works?
```

PR **#36322**, prose portion verbatim — the canonical shape:

````markdown
### What does this PR do?

Node creates `events.errorMonitor` with `Symbol('events.errorMonitor')`, a unique unregistered symbol. Bun was using `Symbol.for('events.errorMonitor')`, which put it in the global symbol registry.

Consequence: any listener added under `Symbol.for('events.errorMonitor')` (a bundled copy of `node:events`, a polyfill, cross-realm code, or a name collision) became the real error monitor in Bun: it fired on every `'error'` emit and was counted by `listenerCount(errorMonitor)`. In Node that listener is an ordinary event that never fires for `'error'`. It also leaked the identity into the global registry (`Symbol.keyFor(events.errorMonitor)` returned a string in Bun, `undefined` in Node).

### Repro

```js
import { EventEmitter, errorMonitor } from 'node:events';
const S = Symbol.for('events.errorMonitor');
…
```

Node v26.3.0:
```
{"sameAsSymbolFor":false,"keyFor":"not-registered","threw":true,"symbolForListenerFired":"no","listenerCount_errorMonitor":1}
```

Bun before:
```
{"sameAsSymbolFor":true,"keyFor":"events.errorMonitor","symbolForListenerFired":"yes:boom","threw":true,"listenerCount_errorMonitor":2}
```

### Fix

`src/js/node/events.ts`: `SymbolFor("events.errorMonitor")` -> `Symbol("events.errorMonitor")`, matching [Node's definition](https://github.com/nodejs/node/blob/main/lib/events.js).

The other `SymbolFor` uses in that block (`nodejs.rejection`, `nodejs.watermarkData`) are correctly registered in Node and were left alone.

### How did you verify your code works?

- `USE_SYSTEM_BUN=1 bun test test/js/node/events/event-emitter.test.ts -t "errorMonitor is an unregistered Symbol"` fails
- `bun bd test test/js/node/events/event-emitter.test.ts` passes (76/76)
````

Two load-bearing conventions: **(1)** always show the differential — the reference implementation's literal console output beside Bun's; **(2)** always name the exact command pair — `USE_SYSTEM_BUN=1 bun test …` (released binary, must FAIL) vs `bun bd test …` (built-with-fix, must PASS).

Commit messages use git-style subsystem prefixes, not strict Conventional Commits: `event_loop:`, `install:`, `js_parser:`, `h2:`, `bundler:`, `resolver:`, `ptr:`, `test:`, `ci:`. Example:

```
bundler: implement dataurl and base64 loaders

The dataurl and base64 loaders were accepted by the option validator and
documented in the bundler docs, but emitted an empty-string module with
success: true and no warning. …
```

Real observed subjects for the review loop: `ci: retrigger`, `ci: retrigger [skip size check]`, `ci: retrigger now that autobuild-preview-pr-370-06ee8632 is published`, `address review: pendingDelete in handleRstStream, drain is_closed guard, §8.2.1 field-name validation, endWithoutBody backpressure, Alt-Svc on H2, FFI widths, test hardening`, `trim multi-line comments flagged by comment-cop`, `collapse validate_function_name comment to one line`.

### 3.4 Issue authoring — four genres (188 issues authored)

**(i) Conventional bug report** — issue **#36320**:

````markdown
### What version of Bun is running?

main

### What steps can reproduce the bug?

```ts
// in.ts
if (1) {
  function f() {}
}
console.log(f.name);
```

```
$ bun build --keep-names in.ts
```

### What is the expected behavior?

esbuild emits:
…
### Additional information

The block-level function-declaration lowering (`visit_stmts`, "Transform block-level function declarations into variable declarations") clears `func.name` when building the `let` initializer and does not route through the `--keep-names` wrapper…
````

**(ii) CI-flake triage with hit-rate statistics** — issue **#33187**:

```markdown
### What happens

`test/js/bun/terminal/terminal.test.ts > Bun.spawn with terminal option > creates subprocess with terminal attached` times out after 90000ms on the `darwin 14 x64 - test-bun` lane. …

It failed on 8 of the last 60 finished builds of the `bun` pipeline, on branches that have nothing in common with each other. …

| build | branch |
| --- | --- |
| [67572](https://buildkite.com/bun/bun/builds/67572) | farm/13b38596/htmlrewriter-streaming (#32988) |
| [67548](https://buildkite.com/bun/bun/builds/67548) | farm/db55f617/nul-byte-path-args |
…
### Notes for whoever picks this up

- Only `darwin 14 x64` (macOS 14, Intel) is affected; …
- The file has been deflaked before (f7e94413d4, 32a40ae1f5).
```

**(iii) Architectural race/UAF analysis, filed from reviewing someone else's PR** — issue **#33936**:

```markdown
### What

A `TranspilerJob` that is still on the work pool when its owning worker VM is terminated reads freed memory, because the job itself is stored inside the `VirtualMachine` allocation.

- `RuntimeTranspilerStore.store` is a `HiveArrayFallback<TranspilerJob, 64>` (src/jsc/RuntimeTranspilerStore.rs:394) embedded by value in `VirtualMachine.transpiler_store`; …

### Why the checked-enqueue pattern cannot close this one
…
### Possible fixes (structural)
…
Same limitation shape as #33313 … Spotted in review of #32071.
```

**(iv) Perf characterization with explicit epistemic caveats** — issue **#35436**:

```markdown
## Observation

| framework | node rps | bun rps | node cpu-us/req | bun cpu-us/req |
|---|---|---|---|---|
| express | 16,200 | 11,800 | 63 | 122 |
…
## Repro

Harness is on branch [`farm/e2f93162/heap-growth-characterization`](https://github.com/oven-sh/bun/tree/farm/e2f93162/heap-growth-characterization/bench/heap-growth):
…
## Caveats / open questions

- **Build flavor**: measured with a local release build, not release+LTO …
- **Not bisected**: this is a single-point measurement, not a regression claim. Prior behavior unknown.

## Investigation plan (per @cirospaciari)
…
cc @Jarred-Sumner
```

### 3.5 Third-party issue triage (2,547 issues commented that robobun did not author)

**Verdict 1 — already fixed on main** (issue #36328, reporter `quigor`; robobun then **closed** it):

````markdown
**Bun version tested:** `1.3.14` (release binary) vs current main (`1.4.0` canary) on `linux x64`

This reproduces exactly as described on 1.3.14, but it is already fixed on main. The fix landed in the fs.watch backend rewrite in #31830 (commit dae2e872, merged after the 1.3.14 release), …

**On bun 1.3.14** (10 consecutive runs, all identical):

```console
$ ./bun-1.3.14 repro.mjs
events: rename:app.tsx.tmp
saw destination 'app.tsx': false
```

**On current main:**

```console
$ bun repro.mjs
events: rename:app.tsx.tmp | change:app.tsx.tmp | rename:app.tsx.tmp | rename:app.tsx
saw destination 'app.tsx': true
```
````

**Verdict 2 — cannot reproduce** (issue #36305), note the signature footer:

```markdown
Unable to reproduce this.
…
If you still hit this, it would help a lot if you could:
1. Share the `bun.report` link the crash screen prints (it contains the actual stack frames).
2. Try `bun upgrade` and re-run, since newer builds also work here.
3. Check whether deleting `node_modules` and reinstalling … could explain a segfault at load time on one machine only.

If you can provide a minimal reproduction (exact command, Bun version, platform), please update the issue.

---
*Automated investigation. Reopen with more context if this is wrong.*
```

That footer appears on exactly **5 of 307** sampled comments — used **only** on unsolicited sweeps. A deliberate confidence-scoping marker.

**Verdict 3 — wontfix with a compat argument** (issue #36268): `Closing as not planned: this would break Node.js compatibility or existing applications.` … `Bun's compatibility target for server-side globals like `fetch` is Node.js. Node's `fetch` (undici) is a plain function with no brand check on the receiver, …`

**Verdict 4 — stale-issue revalidation** (issue #4136, opened 2023): `**Bun version:** `1.4.0-canary.1+1498d7b77` on `linux x64`` … `**Conclusion:** TypeORM works with Bun. `emitDecoratorMetadata` is honored, …`

**Verdict 5 — investigated hard, still stuck** (issue #18113): `Spent a fair amount of time trying to reproduce this in an automated harness and could not get Bun to behave differently from Node, so I need a hand from anyone who can reproduce it locally.` — plus a Linux×Windows / bun-version × next-version matrix table, a tarball diff of `next` canary.56 vs canary.57, and an attached `instrument.mjs` patch script for the reporter.

### 3.6 Review-RESPONSE loop (this is robobun's actual "review" behavior)

Full thread from PR **#36324**, in order:

`github-actions[bot]` (comment-cop) root comment:
```markdown
<!-- comment-cop:src/runtime/node/types.rs:c8af3a9dfc14 -->
If you need a paragraph-long comment to justify why the workaround is OK, the code is wrong — fix the code
```

robobun reply 1 (**accept**): `Trimmed to a two-line contract in 9c9453317c.`

robobun reply 2 (**refuse**): `Two-line doc comment describing the return contract of a trait method, same as the surrounding trait methods in this file (e.g. the six-line comment on `NameTooLong` above). Not a workaround justification.`

robobun reply 3 (**partial refuse, citing repo policy**): `Trimmed in 19e99eb9d8. The remaining one/two lines explain why the check lives here rather than in the shared parser (non-obvious after this PR moves the shared check); that is the CLAUDE.md bar for keeping a comment. Not a workaround justification.`

After `coderabbitai[bot]` asked for watcher coverage:
```markdown
Added in 1865f87905: `fs.watch` and `fs.watchFile` each get an `it` asserting `{code: ENAMETOOLONG, syscall: "watch", hasPath: true}` for an over-PATH_MAX path. Both fail on the released bun (syscall undefined, no path) and pass with this change.
```
…and coderabbitai replied: ``@robobun`, thanks—this directly covers the changed watcher error path and asserts the expected error identity for both APIs.``

On a `claude[bot]` 🔴 finding: `Addressed in 97334b68c7: the `#[cfg]` split is dropped so both branches go through `slice_z_sys(buf, Tag::rmdir)` / `slice_z_sys(buf, Tag::lstat)` and bail with `ENAMETOOLONG` (syscall + path) before `zig_delete_tree` on every platform. `fs.rm(BIG, {recursive: true}, cb)` is now in the callback ops table.`

On #36327: `Good catch, added both to the `NoSideEffectsPureData` arm in dabcc3b23a and added a DCE test covering an unused base64 import and an unused dataurl import-attribute.`

`Leaving as is.` (PR #34549) is a real terminal disposition.

**Invariants:** one or two sentences; always names the fixing commit SHA; concedes or argues from a cited repo standard. Never a wall of text.

### 3.7 CI-status triage prose (~half the non-generated comment volume)

Of 307 sampled robobun comments: 214 prose, **142 contain `buildkite.com` links**, 26 mention `flake`.

PR **#36181** — infra-blame:
```markdown
CI is blocked on build-cpp agent availability, not this diff: in builds [84660](https://buildkite.com/bun/bun/builds/84660) and [84753](https://buildkite.com/bun/bun/builds/84753) the Rust compile succeeded on every lane that ran, but 7+ `build-cpp` jobs expired or stayed scheduled under the current queue backlog, so the downstream `build-bun` jobs fail with "Sibling step ...-build-cpp errored, nothing to link" and ~150 test jobs never run. The test lanes that did run show only parallel-batch flakes (`08965`, `spawn-streaming-stdout`, `svelte`, `bun-lock`, `bun-install-streaming-extract`), all of which passed alone; `socket.test.ts` is green. Locally both new tests pass on `bun bd` and SIGABRT on `USE_SYSTEM_BUN=1`. Ready for review; CI will need the backlog to clear.
```

PR **#36256** — the only place the gate is named in public prose:
```markdown
**Status**: diff is green; waiting on a maintainer.

- `robobun/evidence` passed: the new test fails without the fix and passes with it on both ASAN and release.
- 195/196 Buildkite jobs passed on [build 84447](https://buildkite.com/bun/bun/builds/84447); every test failure in the annotations is marked `[flaky]` and passed on its solo retry. …
- The one red job is a `darwin-14-x64` test shard that hit the Buildkite step timeout after stalling ~30 min inside `test/integration/svelte/client-side.test.ts` (unrelated; known flake). …
- Review bot signed off and deferred to a maintainer for the scheduling-policy decision.
```

`robobun/evidence` is **not** a GitHub commit status or check-run — `/statuses` returns only `buildkite/*` from `buildkite-limited-access[bot]`, `/check-runs` only `Source lints, Format, cargo clippy, Lint JavaScript, comment-cop, Claude Code Review`. It is an internal gate name that leaked into prose.

### 3.8 `**Status**` hand-off token (5/307 comments)

PR **#36327**:
````markdown
**Status**: ready for review

Reproduced with:
```sh
USE_SYSTEM_BUN=1 bun test test/bundler/bundler_loader.test.ts -t "loader-base64|loader-dataurl"
# 6 fail (emit "")
bun bd test test/bundler/bundler_loader.test.ts -t "loader-base64|loader-dataurl"
# 7 pass
```

Also addressed: `Loader::side_effects()` now marks `Base64`/`Dataurl` as `NoSideEffectsPureData` so unused imports tree-shake (dabcc3b23a).
````
Other observed variants: `**Status**: diff is green; CI failures are unrelated flakes / infra. Ready for review/merge.` (#36244), `**Status**: diff is green; waiting on a maintainer.` (#36256).

### 3.9 Buildkite CI notifier posting AS robobun (93/307 comments — NOT agent output)

```markdown
<div><sup>Updated 10:41 PM PT - Jul 28th, 2026</sup></div>

@robobun, your commit dabcc3b23a59e51478f2e2086522561364504937 is building: [`#84912`](https://buildkite.com/bun/bun/builds/84912)
<!-- generated-comment id=oven-sh/bun#36327 -->
```
Superseded-build variant:
```markdown
<div><sup>Updated 10:45 PM PT - Jul 28th, 2026</sup></div>

:arrows_counterclockwise: @robobun, the build for [`97334b68`](https://github.com/oven-sh/bun/commit/97334b68…) was cancelled — [`19e99eb9`](…) is building instead in [`Build #84914`](https://buildkite.com/bun/bun/builds/84914). Stay tuned...
<!-- generated-comment id=oven-sh/bun#36327 -->
```
Bun's own filter, `scripts/pr-comments.ts:350-353`:
```ts
// robobun's auto-updated CI status comment (the one it edits in place on
// every push) carries this watermark so the bot can find it again. Other
// robobun comments are kept.
if (e.user === "robobun" && e.body.includes("<!-- generated-comment ")) return true;
```

### 3.10 @-mention interface: there is none (free-form only)

`"@robobun" in:comments` → **6,006** total; `type:issue` 347; `type:pr` 5,659; `in:body type:issue` 23. On a 200-PR sample of the PR-side hits, mention-comment authors are `Counter({'robobun': 164, 'coderabbitai': 109, 'dylan-conway': 1})` — i.e. PR-side mentions are **~100% CI/bot noise**.

Across all 347 mention-bearing issues: 256 human @robobun comments. Top mentioners: `alii 43, dylan-conway 24, Electroid 21, Jarred-Sumner 20, Lillious 4, HaleTom 4, mizulu 4, panva 4`. Literals — no command grammar: `@robobun go`, `@robobun Evaluate`, `@robobun please can you fix this :star:`, `@robobun WDYT?`, `@robobun have a good day bro`, `@robobun Try make a `Bun.QR` let's see what you come up with`, `@robobun other poc?`, `move on @robobun`.

Response protocol — **ack-then-justify, ~1-2 min latency**. `alii` on #34107 at `2026-07-14T02:11:47Z` → robobun at `02:13:00Z` (**73 seconds**):
```markdown
✅ `Bun.QR.generate` + `Bun.QR.parse` implemented (37 tests, cross-validated with jsQR).
Fix in progress → #34108
```
then 3 min later a prior-art survey table (`| | generate | decode |` across npm qrcode / jsqr / qrcode-terminal / Go / Rust / Python / Swift CoreImage), then 4 min later an API-design proposal grounded in `crate::image` internals.

Security-report response (#32741) — note the explicit partial-decline:
```markdown
✅ Reproduced two install-path sites of this class (the headline trustedDependencies RCE is already fixed on main by #31218):

- Scoped-registry token leak: a request for `@scopeA/pkg` was routed to a hash-colliding scope's registry with that scope's token.
- Folder resolution: two `file:` deps with colliding absolute paths shared one package identity.

Fix (compare the stored name/path, not just the hash) in progress → #32745
```
…followed by an enumeration of PoC3/PoC4 fixed in #32749 and explicit scope-outs: `PoC6 … is not addressed by #32749: maintainer review scoped it out of that PR, so it remains open here`.

### 3.11 Co-implementation on maintainers' branches

PR **#34549** `node:crypto: ML-DSA and ML-KEM key support` — author `cirospaciari`, head `claude/node-crypto-pqc`, commit authorship `[{"Ciro Spaciari":3},{"Ciro Spaciari MacBook":1},{"Dylan Conway":1},{"robobun":6}]`.

PR **#30328** — author `Jarred-Sumner`; **all** substantive commits are robobun's: `Give File its own prototype that inherits from Blob.prototype` / `Address review: LazyClassStructure, slice() returns Blob, File.prototype accessors` / `Address review: File identity does not propagate through Blob dupes` / `Report extra memory for File wrappers; wire worker test onerror` / `DOMFormData::append/set normalize a null filename to empty`.

### 3.12 Cross-repo chaining

`oven-sh/WebKit#371` (`farm/d889cf53/sync-queue-realm`, title `SynchronousModuleQueue: replay diverted reactions against their own realm`) ↔ bun PR **#36321** (`state=OPEN draft=True`), same token:
```markdown
### Fix

JavaScriptCore side: oven-sh/WebKit#371 stores the realm on `SynchronousModuleTask`, replays against it in the drain loop (including the exception-path `queueMicrotask`), and marks it in `VM::visitAggregateImpl`.

This PR bumps `WEBKIT_VERSION` to that PR's preview build (parent is the currently pinned `549170099`, so nothing else rides along) and adds a regression test.
```
Blocked-on-dependency is expressed as **GitHub draft state**: `Draft while the WebKit preview build for oven-sh/WebKit#371 (`autobuild-preview-pr-371-4e9…`) …`

### 3.13 Public gists as an out-of-band artifact channel (13 gists)

Gist `817d81d2860db6f9624e5b61ae1129a3` is a **task prompt written for another agent** (second person, step-numbered), created 2026-01-06:
```markdown
## Task: Verify Windows DNS SRV Regression Fix
You are testing a fix for a DNS SRV regression on Windows that was introduced in Bun 1.3.5.
### Step 1: Create a Test Script
Create a file called `test-dns-srv.js` with the following content:
```
Other titles (self-reported fan-out width of 10-15): `Bun Crash Analysis - GitHub Cross-Reference (10 parallel searches, 500+ issues reviewed)`, `Bun Crash Analysis - Root Causes Identified (10 parallel investigations)`, `Bun Crash Analysis: 9,081 crashes from Discord with stack traces (15MB)`, `Analysis of Non-Useful Lifecycle Scripts in Bun Trusted Dependencies`. **No credentials or orchestrator config in any gist** — outputs only.

### 3.14 What robobun does NOT do

- **Not a code reviewer.** 98/98 recent `PullRequestReviewCommentEvent`s are `in_reply_to` replies, **0 root**. All 76 `PullRequestReviewEvent`s are `state=commented, body=null` — empty containers. Zero APPROVE, zero CHANGES_REQUESTED. The `reviewed-by:robobun` counts (225 non-self PRs; 3,735 total) are generated by reply threads.
- **No routine benchmarks.** 2/200 bodies contain benchmark output; 0 contain `npm install bun@`; 0 contain bundle-size deltas. Benchmarking is invoked only for perf-shaped changes, and then with real methodology (#36201: `Windows Server 2019, NTFS, release builds, warm cache, 20-50 iterations per case, alternating build order across 4 runs. Tree: `node_modules` from a `next`/`react`/`webpack`/`vite`/`eslint` install (16,787 entries across 1,555 directories), plus a synthetic 5,000-file flat directory.`).
- **No dashboard/session backlink anywhere.** The 8-char run token in the branch name is the only opaque handle exposed publicly.
- **Mostly appends, rarely force-pushes** (~1 in 7 PRs). Merges `origin/main` in rather than rebasing (`Merge remote-tracking branch 'origin/main' into claude/webkit-upgrade-2e37adcc23b7`). Combined with the human squash-merge, this is why the **PR body is the durable message**, not the commit log.

---

## 4. Repo-side configuration

### 4.1 Inventory

```
CLAUDE.md                                    16219 B / 239 lines   (43 commits, first 2025-06-24, latest 2026-07-21)
AGENTS.md                          mode 120000 symlink -> "CLAUDE.md"   (9 bytes)
REVIEW.md                                    ~26 KB                (4 commits, first 2026-07-17)
src/CLAUDE.md                                14911 B
src/js/CLAUDE.md                              2606 B
src/jsc/bindings/v8/CLAUDE.md                10263 B
scripts/build/CLAUDE.md                      24133 B
scripts/verify-baseline-static/CLAUDE.md     13501 B
test/CLAUDE.md                                7553 B
test/js/node/test/parallel/CLAUDE.md           467 B
.github/workflows/CLAUDE.md                   4462 B
src/AGENTS.md, src/js/AGENTS.md, test/AGENTS.md      mode 120000 symlinks
src/jsc/bindings/v8/AGENTS.md                        mode 100644 (the one real-file exception)

.claude/settings.json                          509 B  (2 commits, first 2025-10-04 #23241)
.claude/hooks/pre-bash-guard.js              204 lines
.claude/hooks/post-edit-format.js
.claude/commands/{dedupe(43L),find-duplicate-prs(47L),find-issues(57L),
                  upgrade-boringssl(101L),upgrade-nodejs(91L),upgrade-webkit(41L)}.md
.claude/skills/implementing-jsc-classes-cpp/SKILL.md      184 L
.claude/skills/implementing-jsc-classes-rust/SKILL.md     131 L
.claude/skills/javascriptcore-garbage-collector/SKILL.md  366 L
.claude/skills/rust-system-calls/SKILL.md                  96 L
.claude/skills/slowest-tests/SKILL.md                      50 L
.claude/skills/verify/SKILL.md                             44 L
.claude/skills/writing-bundler-tests/SKILL.md             222 L
.claude/skills/writing-dev-server-tests/SKILL.md           94 L
.claude/skills/sync-react-compiler.md   79 L  (loose file, has description: but NO name:, and not
                                               in a directory -> almost certainly not loadable)
.claude/docs/landing-prs.md                  ~7,000 words
.cursor/environment.json                       197 B
```

**AGENTS.md is a symlink to CLAUDE.md** (`mode 120000`). One instruction corpus, two vendor filenames, zero drift. Gotcha: `raw.githubusercontent.com/oven-sh/bun/main/AGENTS.md` returns the 9-byte **link target string** `CLAUDE.md`, not the content — a naive fetcher concludes there are no agent instructions.

**ABSENT** (verified against the full 20,713-path tree): no `.claude/agents/`, no `.mcp.json`, no `.claude/settings.local.json`, no `permissions` block, no `.github/copilot-instructions.md`, no `.github/dependabot.yml`, no `.github/labeler.yml`, no `.cursor/rules` (converted to `.claude/skills` 2025-12-25, `chore: convert .cursor/rules to .claude/skills (#25683)`).

### 4.2 The RED-proof rule — the single most transferable idea

```
CLAUDE.md:11   **CRITICAL**: Never use `bun test` directly - it won't include your changes
CLAUDE.md:108  **CRITICAL**: Verify your test fails with `USE_SYSTEM_BUN=1 bun test <file>` and
               passes with `bun bd test <file>`. Your test is NOT VALID if it passes with
               `USE_SYSTEM_BUN=1`.
CLAUDE.md:193  1. **Never use `bun test` or `bun <file>` directly**
CLAUDE.md:203  11. **Be humble & honest** - NEVER overstate what you got done or what actually
               works in commits, PRs or in messages to the user.
CLAUDE.md:204  12. **Branch names must start with `claude/`** - This is a requirement for the CI to work.
CLAUDE.md:205  13. **If you need a paragraph-long comment to justify why the workaround is OK,
               the code is wrong — fix the code.**
CLAUDE.md:206  14. After every code comment you write, ask yourself, "Is this information the
               next Claude would spend multiple tool calls trying to understand?". If the
               answer isn't clearly yes, the code comment is noise - delete it.
CLAUDE.md:208  **ONLY** push up changes after running `bun bd test <file>` and ensuring your tests pass.
CLAUDE.md:229  `gh pr view --comments` silently omits review summaries and line-level review
               comments. For the complete picture — especially when responding to a review —
               use `bun run pr:comments`, which fetches issue comments, reviews, and line
               comments in one chronological, labelled listing.
CLAUDE.md:225  If output from these commands looks wrong (mis-parsed annotation HTML, a field
               BuildKite changed shape on), fix `scripts/find-build.ts` directly rather than
               working around it — it's a thin presenter over `bk`.
```

Note rule 12 does **not** match observed robobun branches (861/1000 are bare `farm/`) — CLAUDE.md governs the interactive/human `claude/*` path, and the farm has drifted off it.

### 4.3 Deterministic enforcement — `.claude/settings.json` in full (509 bytes)

```json
{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/pre-bash-guard.js"}]}],"PostToolUse":[{"matcher":"Write|Edit|MultiEdit","hooks":[{"type":"command","command":"\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/post-edit-format.js"}]}]}}
```

`pre-bash-guard.js` (204 lines, a Bun script reading `Bun.stdin.json()`, emitting `{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":…}}`) denies six shapes:

1. direct `rustfmt` → *"Run `cargo fmt --all` — it's what CI checks"*
2. `timeout … bun bd` → *"error: Run `bun bd` without a timeout"*
3. `bun test -u` combined with `-t`
4. the Bash tool's own `timeout` parameter on `bun bd`
5. `bun test <file>` without `USE_SYSTEM_BUN=1` → *"error: In development, use `bun bd test <file>` to test your changes"*
6. `bun bd test` with no file path from repo root or `test/` → *"will run all tests. Use `bun bd test <path>` with a specific test file."*

**The adversarial-model comment, verbatim, line 92:** `// Claude is a sneaky fucker` — immediately above ~30 lines that splice `2>&1`, `1>&2`, `>`, `>>`, `>file`, and everything after `|` out of the positional-arg list before testing `positionalArgs.length === 1 && positionalArgs[0] === "bd"`. It also strips inline `FOO=1` env assignments and then re-reads `USE_SYSTEM_BUN` out of them. **A deny-hook that regexes the raw command string is bypassed by appending ` 2>&1`. Normalize to argv semantics first.**

Line 178 leaks the execution environment: `const isBunRepoRoot = cwd === "/workspace/bun" || cwd.endsWith("/bun");`

`post-edit-format.js` L23-27, verbatim:
```js
// Format only — NO organize-imports plugin. That plugin strips imports
// it thinks are unused, which breaks split edits (add import → use it
// in next edit). CI's `bun run prettier` runs the plugin, so imports
// still get cleaned up before merge.
```
Runs `./node_modules/.bin/prettier --config .prettierrc --write <file>` for 20 extensions. **Split the formatter: idempotent-safe rules in the hook, destructive rules at CI only.**

### 4.4 REVIEW.md — a data-derived prompt

```
# Landing PRs: What Bun Reviewers Catch

Distilled from the review history of ~2,500 merged PRs where review feedback led to fix
commits; everything here has blocked merges. Before writing code that makes a non-obvious
choice, pre-emptively ask "why this and not the alternative?" — if you can't answer,
research until you can.
```
Sections: `## Tests reviewers reject` · `## Native code: memory safety (the most-blocked category)` · `## Correctness: the bug class, not the bug` · `## Error handling` · `## Code style & idioms reviewers enforce` · `## Architecture & layering` · `## Security`. Contains quoted real reviewer objections: *"Do not solve quadratic behavior by limiting the count"*, *"JavaScriptCore is a different engine. Do you have a benchmark?"*

**The method is the transferable part**: mine your own merged-PR review threads where feedback *caused a fix commit*, cluster, write the clusters back as rules.

### 4.5 Three-tier context budget

`CLAUDE.md:187-189`:
```
The code review rules — what blocks merges, distilled from ~2,500 merged PRs — live in
`REVIEW.md`. Read it before writing code that makes a non-obvious choice.

Several situational sections live in `.claude/docs/landing-prs.md` — read the relevant one
before the work it covers: **Node/Web compat** (touching `node:*` modules, Web APIs, or
`src/runtime/node/`), **API design** …, **Performance** …, **Cross-platform** …,
**Dependencies & vendoring** …, **Docs, types, and comments** …, and **PR process** …
```
CLAUDE.md (always) → REVIEW.md (before non-obvious code) → landing-prs.md §X (only for that surface). Skill lazy-loading implemented in plain markdown with a hand-written trigger table.

### 4.6 Skill descriptions enumerate literal symbols

`javascriptcore-garbage-collector`: `JSC GC reference for Bun. Use for use-after-free, JS object leaks, "collected too early", or when touching WriteBarrier, visitChildren, … IsoSubspace, HeapAnalyzer, finalize.` — auto-trigger fires reliably in a C++/Rust codebase because the description names strings that will literally be on screen.

`.claude/skills/verify/SKILL.md` — the effect-read rule:
```
- **A `src/js/**` edit can silently not reach the binary.** `bundle-modules` regenerates
  `build/<cfg>/codegen/InternalModuleRegistryConstants.h`, but the C++ TU that embeds it is
  not always recompiled, so the build succeeds while the binary still runs the OLD JS. Gate
  on the binary, not the build: ask the binary you just built —
  `bun bd -e 'console.log(<Class>.toString().includes("<new-id>"))'` … If false,
  `touch src/jsc/bindings/InternalModuleRegistry.cpp` and rebuild.
```
And the macOS-fingerprint line:
```
**Prefix every `bun bd` with `PATH="$HOME/.cargo/bin:$PATH"`** — Homebrew's `rust` formula
shadows the pinned nightly, and `bun bd` dies with `the option 'Z' is only accepted on the
nightly compiler`. `bun bd` re-runs cargo on every invocation, so this is needed for
follow-up runs too, not just the first build.
…
The debug+asan build is 10-100× slower than release; large-allocation stress tests can time
out locally while passing in CI.
```

### 4.7 Slash commands ARE the CI prompts

`.claude/commands/find-issues.md`, step structure verbatim:
```
1. Use an agent to check if the PR (a) is closed/merged, or (b) already has a related-issues comment …
2. Use an agent to view the PR title, body, and diff …
3. Then, launch 5 parallel agents to search GitHub for open issues …
   Each agent should try a different search strategy:
   - Agent 1: Search using error messages or symptoms described in the diff
   - Agent 2: Search using feature/module names from the changed files
   - Agent 3: Search using API names or function names that were modified
   - Agent 4: Search using keywords from the PR title and description
   - Agent 5: Search using broader terms related to the area of code changed
4. Next, feed the results from Steps 2 and 3 into another agent, so that it can filter out false positives …
5. Finally, comment on the PR
```
`dedupe.md` uses 5 search agents; `find-duplicate-prs.md` uses 3. **The subagent lenses are enumerated by the prompt author, not chosen by the lead** — anti-under-spawn discipline hardcoded so it cannot degrade.

Per-command permissioning (there is no repo-wide allowlist) — `dedupe.md` frontmatter:
```yaml
allowed-tools: Bash(gh issue view:*), Bash(gh search:*), Bash(gh issue list:*), Bash(gh api:*), Bash(gh issue comment:*)
```

**Idempotency markers**: step 1 of every command is "check for the exact marker and abort if present" — `<!-- dedupe-bot:marker -->`, `<!-- find-issues-bot:marker -->`, `<!-- find-duplicate-prs-bot:marker -->`. Each mandated comment template ends `🤖 Generated with [Claude Code](https://claude.ai/code)` then the marker. **The state store IS the output surface.**

`comment-cop.yml` uses a *content-keyed* variant enabling auto-resolve:
```js
const keyFor = g => `${g.path}:${crypto.createHash('sha256').update(g.text).digest('hex').slice(0,12)}`;
// -> `<!-- comment-cop:${keyFor(g)} -->`
```
Any thread whose key is no longer in the diff gets `resolveReviewThread`.

### 4.8 The two live agent workflows (complete)

`.github/workflows/claude-dedupe-issues.yml`:
```yaml
on:
  issues:
    types: [opened]
  workflow_dispatch:
    inputs: {issue_number: {...}}
jobs:
  claude-dedupe-issues:
    runs-on: ubuntu-latest
    timeout-minutes: 10
    concurrency:
      group: claude-dedupe-issues-${{ github.event.issue.number || inputs.issue_number }}
      cancel-in-progress: true
    permissions: {contents: read, issues: write}
    steps:
      - uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5 # v4
      - name: Run Claude Code slash command
        uses: anthropics/claude-code-base-action@98d41f9809750c4c96f2cd285746ecef889f14bc
        env:
          ANTHROPIC_MODEL: claude-opus-4-6[1m]
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        with:
          prompt: "/dedupe ${{ github.repository }}/issues/${{ github.event.issue.number }}"
          anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}
```
`claude-find-issues-for-pr.yml` is identical in shape, `timeout-minutes: 20`, `permissions: {contents: read, pull-requests: write, issues: read}`, and runs **two** base-action steps in sequence (`/find-issues` then `/find-duplicate-prs`, the second with `if: always()`).

Three details worth stealing: `[1m]` buys the 1M-context model for whole-corpus search; `GH_TOKEN` is injected as an **env var** so the agent's own `gh` calls authenticate transparently while the action itself gets no GitHub credentials; `checkout` runs purely so `.claude/commands/*.md` exist on disk for the slash command to resolve.

### 4.9 Reactive guardrails

`auto-label-claude-prs.yml`:
```yaml
name: Auto-label Claude PRs
on:
  pull_request:
    types: [opened]
jobs:
  auto-label:
    if: github.event.pull_request.user.login == 'robobun' || contains(github.event.pull_request.body, '🤖 Generated with')
    runs-on: ubuntu-latest
    permissions: {contents: read, pull-requests: write}
    steps:
      - uses: actions/github-script@f28e40c7f34bde8b3046d885e986cb6290c5673b # v7
        with:
          script: |
            github.rest.issues.addLabels({ …, labels: ['claude'] });
```

`close-stale-robobun-prs.yml`:
```yaml
name: Close stale robobun PRs
on:
  schedule:
    - cron: "30 0 * * *"
  workflow_dispatch:
jobs: … permissions: {pull-requests: write}
    run: |
      ninety_days_ago=$(date -u -d '90 days ago' +%Y-%m-%dT%H:%M:%SZ)
      gh pr list --author robobun --state open --json number,updatedAt --limit 1000 \
        --jq ".[] | select(.updatedAt < \"$ninety_days_ago\") | .number" |
      while read -r pr_number; do
        gh pr close "$pr_number" --comment "Closing this PR because it has been inactive for more than 90 days."
      done
```
(Contrast the human policy: `stale.yaml` uses `actions/stale` with `days-before-pr-stale: 30 / days-before-pr-close: 14` and its `schedule:` trigger is **commented out**.)

`comment-cop.yml` header + gate:
```yaml
# Flags multi-line code comments added in src/ by claude-labeled PRs and
# asks for them to be deleted. Groups containing a SAFETY: marker are
# skipped. Runs entirely against the GitHub API (no checkout of PR code).
on:
  pull_request_target:
    types: [opened, synchronize, reopened, labeled]
permissions: {contents: read, pull-requests: write}
timeout-minutes: 5
if: github.repository == 'oven-sh/bun'
   && contains(github.event.pull_request.labels.*.name, 'claude')
   && (github.event.action != 'labeled' || github.event.label.name == 'claude')
```
`const MIN_LINES = 2;` · `if (!/SAFETY:/.test(text)) out.push(...)` · posted body is CLAUDE.md rule 13 **verbatim**: `` `If you need a paragraph-long comment to justify why the workaround is OK, the code is wrong — fix the code` ``.

**The pattern: for each behavioral rule the model reliably violates, build a CI lint that re-states the SAME SENTENCE at the violation site.**

`on-slop.yml` — the human kill switch:
```yaml
name: Close AI Slop PRs
on:
  pull_request_target:
    types: [labeled]
jobs:
  on-slop:
    if: github.event.label.name == 'slop' && github.repository == 'oven-sh/bun'
    permissions: {issues: write, pull-requests: write}
```
Comment body:
```
This PR has been closed because it was flagged as AI slop.

Many AI-generated PRs are fine, but this one was identified as having one or more of the following issues:
- Fails to verify the problem actually exists
- Fails to test that the fix works
- Makes incorrect assumptions about the codebase
- Submits changes that are incomplete or misleading

If you believe this was done in error, please leave a comment.
```
then `pulls.update({ title: 'ai slop', body: '…the description has been updated to avoid confusion or misleading reviewers…', state: 'closed' })`. The superseded copy in `.github/workflows/labeled.yml.disabled` additionally called `git.deleteRef({ ref: `heads/${pr.data.head.ref}` })`.

**Those 4 bullets are Bun's operational definition of AI slop, and the `robobun:evidence` fail-before/pass-after block is engineered to be the un-fakeable answer to them. Treat them as a matched pair.**

### 4.10 Config timeline

| date | event |
|---|---|
| 2025-06-24 | first `CLAUDE.md` commit ("Update some docs") |
| 2025-06-25 | first `.claude/commands` (`Create upgrade-webkit.md`) |
| 2025-05-19 → 2025-11-27 | `.github/workflows/claude.yml` lived and died (deleted in `69b571da41`, #25157) |
| 2025-10-04 | `.claude/settings.json` — *"Add Claude Code hooks to prevent common development mistakes (#23241)"* |
| 2025-12-25 | `.cursor/rules` → `.claude/skills` (#25683) |
| 2026-05-04 | "Robobun on farm signing key" created → the farm architecture begins |
| 2026-06-25 | `.claude/docs/landing-prs.md` latest |
| 2026-07-17 | `REVIEW.md` split out of CLAUDE.md |
| 2026-07-25 | `comment-cop.yml` latest |

The hooks arrived *specifically* "to prevent common development mistakes" — i.e. **after prose alone demonstrably failed.**

---

## 5. Scale, economics, reception

### Population (GraphQL `search type:ISSUE issueCount`)

| query | count |
|---|---|
| `repo:oven-sh/bun author:robobun type:pr` | **6,691** |
| `… is:merged` | **1,776** |
| `… is:open` | **2,671** |
| `… is:closed` | **4,019** |
| `… is:closed is:unmerged` | **2,243** |
| `… is:draft` | **74** |
| `… linked:issue` | **2,201** (32.9%) |
| `… is:merged linked:issue` | **431** (24.3% of merged) |
| all repos `author:robobun type:pr` | 6,892 (1,862 merged) |
| `repo:oven-sh/bun is:pr` (everyone, all time) | **17,709** |
| `repo:oven-sh/bun is:pr label:claude` | **6,711** |
| `label:claude -author:robobun` | 100 |
| `author:robobun -label:claude` | 79 (pre-date the workflow) |
| robobun issues authored | 188 |
| issues commented, not authored | 2,547 |
| PRs reviewed-by robobun, not authored | 225 |
| `"@robobun" in:comments` | 6,006 (issue 347 / PR 5,659) |
| `"find-issues-bot" in:comments` | 1,862 |
| `"issues this PR may fix" in:comments` | 1,012 |
| Actions runs `actor=robobun` | 122,535 (100% reactive CI) |

**Headline: 26.6% of all robobun PRs merged; 44.2% of DECIDED PRs merged (1776/4019). robobun is ~38% of every PR oven-sh/bun has ever received. The open backlog (2,671) exceeds the merged total (1,776).**

**Caveat that must ship with the 44.2% — now MEASURED, and it is not the stale-bot (see §0.1).** Only **5.5%** of closed-unmerged PRs are closed by `github-actions` (the 90-day stale job). **83.0% are closed by robobun itself**, overwhelmingly as self-detected duplicates of a sibling worker's PR opened minutes earlier. So the closed-unmerged population is dominated by *fleet-internal collision*, not by merit rejection and not by timeout. "Rejected as bad by a human" is only ~9.6% (Jarred-Sumner 8.8% + dylan-conway 0.8%).

### Cadence (477 PRs, 2026-07-25T20:51:50Z → 2026-07-29T05:23:53Z = 3.36 days)

**142.2 PRs/day.** Hour-of-day histogram (UTC):

| 00 | 01 | 02 | 03 | 04 | 05 | 06 | 07 | 08 | 09 | 10 | 11 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 36 | 31 | 23 | 21 | 18 | 14 | 13 | 15 | 16 | 24 | 33 | 19 |

| 12 | 13 | 14 | 15 | 16 | 17 | 18 | 19 | 20 | 21 | 22 | 23 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 8 | 10 | 17 | 18 | 23 | 16 | 13 | 18 | 20 | 35 | 16 | 20 |

Inter-arrival: median **354s**, mean 609s, **max quiet gap 92 min**. 218 gaps <300s, 62 gaps <60s, **8 gaps <10s**. Max/min hour ratio only **4.5×**. Unattended daemon + queue, not cron batches; sub-10s gaps confirm concurrent workers finishing independently. A 43-min event-stream window held 100 public events: `PullRequestReviewCommentEvent 25, PullRequestReviewEvent 24, PushEvent 23, IssueCommentEvent 12, PullRequestEvent 10, CreateEvent 5, IssuesEvent 1` — all on oven-sh/bun, with same-second pairs. That is roughly the ceiling of GitHub's secondary rate limits on one token; Bun lives inside it rather than sharding identities.

### PR size (GraphQL over 100 most recent)

| metric | min | p25 | median | p75 | p90 | max |
|---|---|---|---|---|---|---|
| additions | 2 | 74 | **150** | 291 | 506 | 1,579 |
| deletions | 0 | 3 | **12** | 50 | 109 | 13,007 |
| changedFiles | 1 | 2 | **4** | 6 | 10 | 35 |
| commits | 1 | 3 | **5** | 7 | 10 | 18 |

Task decomposition target ≈ **150 LOC / 4 files**. The 13,007-deletion outlier is a dead-code-removal class (`dead-code-*` slugs recur ~7× in the sample); the 1,579-addition max is a feature port (`serve-http2`). Multiple task classes share one fleet.

### Human bottleneck

| metric | value |
|---|---|
| open→merge | min 0.3h · **median 3.2h** · p90 21.0h · max 449.7h |
| mergedBy (60 recent merges) | Jarred-Sumner 42, dylan-conway 18 |
| closers (100 recent) | Jarred-Sumner 4, robobun 2 (self-dedupe) |
| supply | 142 PRs/day |

**Two humans against 142 PRs/day. Generation is cheap; adjudication is the constraint. 2,671 PRs sit open.** This is the single most important economic fact in the corpus.

### Issue-linkage over time (`… linked:issue created:<month>` / `… created:<month>`)

| month | total PRs | linked | share |
|---|---|---|---|
| 2025-08 | 149 | 31 | 20.8% |
| 2025-09 | 177 | 46 | 26.0% |
| 2025-10 | 210 | 57 | 27.1% |
| 2025-11 | 142 | 48 | 33.8% |
| 2025-12 | 70 | 10 | 14.3% |
| **2026-01** | 312 | 236 | **75.6%** |
| **2026-02** | 388 | 263 | **67.8%** |
| 2026-03 | 450 | 239 | 53.1% |
| 2026-04 | 566 | 212 | 37.5% |
| 2026-05 | 711 | 263 | 37.0% |
| 2026-06 | 864 | 290 | 33.6% |
| 2026-07 | 2,595 | 498 | 19.2% |

Volume grew ~17× from 2025-08 to 2026-07 while issue-linkage inverted. Fast-reactive (≤24h from issue filing) share of *all* PRs: 2026-01 **35.3%** → 2026-03 37.2% → 2026-05 33.0% → 2026-06-late 6.2% → 2026-07-late **2.1%**.

Issue→PR lag over 1,234 links (median **130 days**):

| bucket | n |
|---|---|
| PR before issue | 6 |
| ≤1 day | **442** |
| 2-7d | 17 |
| 8-30d | 59 |
| 31-180d | 123 |
| 181-365d | 103 |
| >365d | **484** |

Who filed the linked issues (1,234 links): **97.9% not robobun**. `authorAssociation: Counter({'NONE': 1007, 'CONTRIBUTOR': 186, 'COLLABORATOR': 35, 'MEMBER': 6})`. 338 distinct authors; top `paperclover 13, huseeiin 8, robobun 5, infrahead 4, kevgeoleo 4, mizulu 3, VityaSchel 3`.

Retrofit rate (40+40 sampled PRs, checked for `<!-- find-issues-bot:marker -->`): fast ≤1d `{no-retrofit 33, retrofit 7}` · slow >1d `{no-retrofit 20, retrofit 20}`. So roughly **half the long-lag links were attached after the fact by Bun's own tooling**, not by the authoring agent.

### Reception / quality signal

- **`ai slop` is a real, used verdict.** Two PRs in the `farm/d8266e41/` set carry the title `"ai slop"` — #28313 and #28349, both retitled+closed by `on-slop.yml`.
- Merged PRs are squash-merged by a human, so `main` shows `committer name=GitHub, login=web-flow`, PGP-signed, 30/30 at both a 2026-01 and a 2026-07 sample point. **Do not read that as an API push** — pre-merge branch commits remain SSH-signed with the farm key.
- Force-pushes ~1 in 7 PRs; the agent merges `origin/main` in rather than rebasing.
- **Revert rate: MEASURED by the lead (§0.2), not unobtainable.** robobun 6 reverts / 1,776 merges = **0.34%**; humans 96 / 7,238 = **1.33%**. All six robobun reverts predate 2026-04; the 1,186 merges since have **zero** explicit reverts. See §0.2 for the four caveats that must ship with these numbers.

---

## 6. Corrections

**Read this section before acting on anything above.** Four load-bearing claims went through adversarial verification; **two were refuted**.

### C1 — REFUTED: "the 8-hex token is a per-task/per-session id"

**Wrong.** The token is an opaque, orchestrator-allocated, **globally-namespaced, cross-repo, REUSABLE** run/campaign handle.

- 47 of 3,586 bun tokens cover 2-6 branches (113 branches, 3.1%) — **~31,000× above random-collision expectation** (expected 0.0015 collisions at n=3,586).
- Reused sets produce **separate PRs for unrelated tasks**, spanning up to **70 days** (`farm/898354b3/` → #28353, #28355, #28365, #30667, #31605, 2026-03-21 → 2026-05-30). That kills "session id" outright.
- `farm/73f947d6/` is a 6-branch binary-size *program* including `size-research` with **no PR at all** — so branch ≠ PR, always.
- Token is not always 8 hex: base62 exists (`farm/6BHM4p7X/update-readme`, `farm/iZZnDLtE/process-title-os`, `farm/xVz2jnWM/fix-esm-bytecode-barrel-test`). Sometimes absent entirely (`farm/dispatchtimer-stop-break-cycle` in WebKit).
- 39 tokens appear in **both** oven-sh/bun and oven-sh/WebKit.

**Survives:** the token is NOT a git sha prefix (11/11 → HTTP 422 "No commit found for SHA"; 0/255 head oids prefix-match; three siblings share `merge_base 59242d6c891b…` regardless of token). And the `<slug>` branch is ~1 unit of work (96.9% of branches have a token unique to them).

**Do not build a parser that assumes token uniqueness or 8-hex-ness.**

### C2 — REFUTED: "the bulk of PRs are self-directed, NOT one-to-one responses to human issues"

**Half wrong, and inverted for early 2026.** There are **two streams** and the mix shifted hard over time.

- **2,201 of 6,691 (32.9%)** robobun PRs carry a `closingIssuesReferences`; **97.9%** of those linked issues were filed by someone else, **81.6% by outside users** (`authorAssociation: NONE`).
- **442 links were opened within 24h of the issue being filed** — genuinely reactive one-to-one. Literal cases:
  - Issue #35936 `{"author":"thorbm1500","created":"2026-07-26T11:49:00Z","title":"Navigator missing from Bun Globals"}` → PR #35937 `created=2026-07-26T11:51:43Z`, `head=farm/48a7b53d/docs-navigator-global`, body line 1 `Fixes #35936` — **2 min 43 s**.
  - Issue #28030 `{"author":"DavidBuchanan314","created":"2026-03-12T07:13:45Z"}` → PR #28031 `created=07:15:39Z`, `head=claude/fix-range-request-docs-28030`, `Closes #28030` — **1 min 54 s**.
- **In 2026-01 and 2026-02, 75.6% and 67.8% of ALL robobun PRs closed a human-filed issue.** The "self-directed queue" framing is flatly wrong for that period.
- Today it is right: 2026-07 linked share is 19.2%, fast-reactive share 2.1%.
- Mechanism reconciling both: `.claude/commands/find-issues.md` retro-attaches `Fixes #N` to already-authored PRs. Proven case — PR #28200 created `16:00:01`, find-issues-bot comment at `16:07:44` listing `.../issues/11255`, PR body `lastEditedAt 16:46:58`, final closing ref `#11255`. **~half of long-lag links are retrofits.** But retrofits cannot explain the ≤24h bucket.

**Survives intact:** the @-mention channel is a rounding error (≤5% upper bound). Only 347 issues in repo history contain an @robobun comment mention; PR-side mentions are ~100% CI/bot noise (200-PR sample: robobun 164, coderabbitai 109, **dylan-conway 1**).

**Also:** the unlinked stream genuinely is self-directed. Of 500 recent bodies: 90 closingRef, 191 bare `#N`, 219 no ref at all — and resolving 251 bare refs gives **219 PullRequests vs only 32 Issues**. The unlinked stream cross-references *prior PRs*, not issues.

### C3 — CORRECTED (not refuted): "no `🤖 Generated with` / `Co-Authored-By` trailer ever"

The recon's finding B1d ("0 hits across 200 bodies and 13 commits") is true for the **current** farm output, but **PR #28031 (2026-03-12) ends with `🤖 Generated with [Claude Code](https://claude.com/claude-code)`**. The trailer was present in the `claude/<slug>` era and was stripped later. `auto-label-claude-prs.yml`'s `contains(body,'🤖 Generated with')` disjunct is a live historical artifact, not dead code, for older PRs.

### C4 — CORRECTED: "robobun files code-review findings on other people's PRs"

**No.** 98/98 recent `PullRequestReviewCommentEvent`s are `in_reply_to` replies, **0 root**. All 76 `PullRequestReviewEvent`s are `state=commented, body=null`. Zero APPROVE, zero CHANGES_REQUESTED. The `reviewed-by:robobun` counts (225 / 3,735) are reply threads. Root review findings on human PRs come from `claude[bot]` (1) and `coderabbitai[bot]` (2). **Model robobun as the author side only; the reviewer is a separate identity.**

### C5 — SCOPE-CORRECTED: "robobun never acts via GitHub Actions"

Some robobun writes **do** originate in oven-sh/bun's Actions — via the `ROBOBUN_TOKEN` PAT, producing GPG-signed `robobun <robobun@oven.sh>` commits in `oven-sh/homebrew-bun` (verified: `gh api repos/oven-sh/homebrew-bun/commits/3d294964` → `{"msg":"Release bun-v1.3.14","payload_committer":{"email":"robobun@oven.sh"},"ver":"valid","sigstart":"-----BEGIN PGP SIGNATURE-----"}`) and a `bun-types` PR pushed to the `oven-sh/DefinitelyTyped` fork. This is **release plumbing, never agent PRs**, and it uses a user PAT, never `GITHUB_TOKEN`. It confirms rather than contradicts the PAT mechanism.

### C6 — CORRECTED: `author_association: COLLABORATOR` is not evidence of outside-collaborator status

`Jarred-Sumner` (org owner) also returns `COLLABORATOR`; public members return `MEMBER`. The field tracks membership **visibility**. robobun is indistinguishable from a private org member. Direct push is proven independently (477/477 head repos = `oven-sh/bun`, `pusher_type: "user"`).

### C7 — Endpoint traps (do not repeat these)

- `repos/*/pulls/<N>/comments` (review comments) carries **no** `performed_via_github_app` at all — `github-actions[bot]` and `claude[bot]` both read null there. A null from that endpoint proves nothing.
- `repos/*/issues/events` nulls the field for **every** actor including `github-actions[bot]`. Insensitive; cite neither way.
- `users/robobun/events/public --paginate` returns only **300 events (~1 day)**. It showed 0 root review comments and 22/23 self-authored PRs, which naively reads as "robobun never touches others' PRs" — contradicted by `reviewed-by:robobun -author:robobun` → 225. **Use search, not the event firehose, for prevalence.**
- `raw.githubusercontent.com/.../AGENTS.md` returns the 9-byte symlink target, not content.
- `repos/oven-sh/bun/issues/comments --paginate` (all repo comments) times out. Use bounded `&page=1..N`.

### C8 — Named dead ends

- `scripts/agent.mjs` (453 lines) is the **Buildkite** agent installer (`BUILDKITE_TOKEN_SECRET = "buildkite/agent-token"`, `AZURE_KEYVAULT = "bun-ci"`, zero Anthropic references). Pure name collision. Do not reopen.
- `gh api orgs/oven-sh/memberships/robobun` → 403; `collaborators/robobun/permission` → 403; org 2FA/SAML → `INSUFFICIENT_SCOPES … requires ['admin:org']`. Unobtainable.
- The string `farm` appears in **zero** of 20,713 tree paths (only `farmhash`, `worker-farm`, `ahfarmer/calculator`, base64 noise in `root_certs.h`, "had a farm" in a Buffer test).
- `gh search code 'robobun:evidence'` → `[]` **globally**. The harness is not public anywhere.
- `scripts/label-issue.ts` (353 lines, `import { Anthropic } from "@anthropic-ai/sdk"`) has **no live caller** — invoked only from a commented-out job inside `.github/workflows/labeled.yml.disabled`. Double-dead.
- All 13 gists fully enumerated: analysis outputs, no credentials, no orchestrator config, no topology.

---

## 7. Recreation blueprint

Everything below is runnable. **UNKNOWN** markers flag where robobun's real approach is unobservable and I am substituting a defensible modern equivalent.

### 7.1 Identity + credentials

Two identities, deliberately split — this is the safety boundary that makes high volume tractable.

```bash
# ---- AUTHOR identity: one machine account, write access, NO merge rights ----
# 1. Create a user account (e.g. `acmebot`). Do NOT create a GitHub App for the author.
#    Reason: robobun is a plain User (performed_via_github_app null on 600/600 comments),
#    which keeps commits human-shaped and avoids installation-token plumbing.

# 2. Fine-grained PAT, repo-scoped, minimum viable:
#      Contents: Read and write      (push branches)
#      Pull requests: Read and write (open, comment, assign)
#      Issues: Read and write        (triage, close)
#      Metadata: Read
#    Do NOT grant Administration, and do NOT add the account to a team with merge rights.
#    Store as ACME_BOT_TOKEN.

# 3. SSH signing key (signing only — do NOT register it as an authentication key).
ssh-keygen -t ed25519 -C "acmebot farm signing key" -f ~/.ssh/farm_signing -N ""
gh api -X POST /user/ssh_signing_keys \
  -f title='Acmebot on farm signing key' \
  -f key="$(cat ~/.ssh/farm_signing.pub)"

# 4. Per-worker git config (identical across the whole fleet — one identity, not one per worker)
git config --global user.name  "acmebot"
git config --global user.email "<USER_ID>+acmebot@users.noreply.github.com"   # GitHub noreply, NOT the profile email
git config --global gpg.format ssh
git config --global user.signingkey ~/.ssh/farm_signing.pub
git config --global commit.gpgsign true

# 5. Push over HTTPS with the token (matches pusher_type: "user")
git config --global credential.helper store
printf 'https://acmebot:%s@github.com\n' "$ACME_BOT_TOKEN" > ~/.git-credentials
```

**REVIEWER identity: do not build it.** Install the off-the-shelf GitHub App (`https://github.com/apps/claude`, `anthropics/claude`, created `2025-04-30T17:54:24Z`). Bun's reviewer is that App plus `coderabbitai[bot]` plus a repo-local lint. Keeping author and reviewer on different identities makes the review adversarial instead of self-graded.

**Merge: humans only.** Do not grant the bot maintain/admin. Do not enable auto-merge.

### 7.2 Run-token allocator

Model the token as Bun does (per C1): opaque, global, cross-repo, **reusable** to group a campaign.

```ts
// orchestrator/token.ts
import { randomBytes } from "node:crypto";

/** A run token groups 1..N work items. Reuse it deliberately for a campaign;
 *  allocate a fresh one for an unrelated task. NOT unique per PR. */
export const newRunToken = (): string => randomBytes(4).toString("hex"); // 8 hex

export const branchFor = (token: string, slug: string): string =>
  `farm/${token}/${slug}`;   // slug is model-authored, kebab-case, <= ~40 chars
```

Store the mapping durably — this is the piece Bun keeps private:

```sql
-- UNKNOWN: robobun's queue schema is not observable. This is a reasonable equivalent.
CREATE TABLE work_item (
  id            BIGSERIAL PRIMARY KEY,
  run_token     TEXT NOT NULL,               -- reusable campaign handle
  slug          TEXT NOT NULL,
  repo          TEXT NOT NULL,               -- token namespace spans repos
  source        TEXT NOT NULL,               -- 'issue' | 'conformance' | 'ci-flake' | 'dead-code' | 'perf' | 'mention'
  source_ref    TEXT,                        -- e.g. 'oven-sh/bun#35936'
  state         TEXT NOT NULL DEFAULT 'queued',
  iteration     INT  NOT NULL DEFAULT 0,     -- survives gate rejections
  gate_passed   INT  NOT NULL DEFAULT 0,
  gate_rejected INT  NOT NULL DEFAULT 0,
  branch        TEXT,
  pr_number     INT,
  worktree      TEXT,
  UNIQUE (repo, run_token, slug)
);
CREATE INDEX ON work_item (state, id);
```

### 7.3 Task generation — both streams

Bun runs two. Build both; expect the mix to drift the way Bun's did (75.6% issue-linked in 2026-01 → 19.2% in 2026-07).

```bash
#!/usr/bin/env bash
# orchestrator/enqueue-reactive.sh — stream A: new human-filed issues, one-to-one.
# Bun's fast path: PR opened 2m43s after the issue (#35936 -> #35937).
set -euo pipefail
REPO="${REPO:-acme/proj}"
SINCE="$(date -u -v-15M +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '15 minutes ago' +%Y-%m-%dT%H:%M:%SZ)"

gh api "search/issues?q=repo:${REPO}+type:issue+state:open+created:>${SINCE}&per_page=50" \
  --jq '.items[] | {n:.number, t:.title, a:.user.login}' |
while read -r row; do
  n=$(jq -r .n <<<"$row")
  enqueue --repo "$REPO" --source issue --source-ref "${REPO}#${n}" --token "$(newRunToken)"
done
```

```bash
#!/usr/bin/env bash
# orchestrator/enqueue-selfdirected.sh — stream B.
# UNKNOWN: robobun's actual generators. Observable task CLASSES (from branch slugs
# and issue genres) are: node/web API conformance gaps, dead-code sweeps, CI-flake
# triage, binary-size programs, perf characterization, hardening.
# Below are defensible modern generators for each.

# B1. Conformance gaps: diff your runtime against the reference impl's own test suite.
#     (Bun's PR bodies always show reference-vs-ours transcripts — build that comparison
#      into the generator so the evidence is free.)
# B2. Dead code: `cargo udeps` / ts-prune / coverage-zero symbols in src/.
# B3. CI flakes: mine your CI API for tests failing on >=N of the last 60 builds on
#     UNRELATED branches. Bun files these as ISSUES with a build table, not PRs.
# B4. Crash telemetry: robobun's gists reference "9,081 crashes from Discord with
#     stack traces (15MB)" clustered into "Root Causes Identified (10 parallel
#     investigations)". Cluster your crash reports, enqueue one item per root cause.
```

**Also build the retrofit linker** — Bun's `find-issues` slash command attaches `Fixes #N` to already-open PRs (1,862 marker hits; ~half of long-lag links). Copy `.claude/commands/find-issues.md` verbatim: 5 parallel search agents with *prescribed distinct strategies*, then a filter agent, then one idempotent comment.

### 7.4 Worker execution

```dockerfile
# UNKNOWN: robobun's exact image. Two hard facts constrain it:
#   pre-bash-guard.js:178  cwd === "/workspace/bun"
#   verify/SKILL.md        Homebrew shadows the pinned rust nightly  => macOS hosts
# For Linux CI-class work a container is fine; for the macOS-only lanes you need real
# macOS hardware (that is exactly why 70/200 PRs abstain with
# "Platform-specific test(s) that do not run on this machine. Deferring to CI").
FROM ubuntu:24.04
WORKDIR /workspace/proj
RUN apt-get update && apt-get install -y git curl build-essential ca-certificates
RUN curl -fsSL https://bun.sh/install | bash
# ... toolchain, pinned compiler, deps ...
```

```bash
#!/usr/bin/env bash
# worker/run.sh — one work item, start to finish.
set -euo pipefail
: "${RUN_TOKEN:?}" "${SLUG:?}" "${REPO:?}" "${ACME_BOT_TOKEN:?}"

BRANCH="farm/${RUN_TOKEN}/${SLUG}"
WT="/workspace/wt/${RUN_TOKEN}-${SLUG}"

# Persistent bare mirror -> worktrees are cheap and the build cache stays warm.
git -C /workspace/mirror fetch --prune origin
git -C /workspace/mirror worktree add -B "$BRANCH" "$WT" origin/main
cd "$WT"

# Record the pristine pre-fix tree so the gate can replay it (see 7.5).
git rev-parse HEAD > .gate/base-sha

# Headless agent. UNKNOWN: robobun's model/effort. Bun's own CI jobs pin
# ANTHROPIC_MODEL: claude-opus-4-6[1m], which is the only public model signal in the repo.
claude -p "$(cat /workspace/prompts/task.md)" \
  --output-format stream-json \
  --permission-mode acceptEdits \
  --add-dir "$WT" \
  2>&1 | tee "/workspace/logs/${RUN_TOKEN}-${SLUG}.jsonl"
```

The task prompt must carry the four things Bun's system carries. Minimal version:

```markdown
<!-- /workspace/prompts/task.md -->
You are working in {{REPO}} at /workspace/proj on branch farm/{{RUN_TOKEN}}/{{SLUG}}.

Task: {{TASK}}
{{#SOURCE_REF}}This closes {{SOURCE_REF}}. Put `Fixes {{SOURCE_REF}}` as the first line of the PR body.{{/SOURCE_REF}}

Non-negotiable:
1. Read CLAUDE.md, then REVIEW.md before writing code that makes a non-obvious choice.
2. Write a test that FAILS on the released binary and PASSES on your build. A test that
   passes on the released binary is NOT VALID.
3. Show the differential in the PR body: the reference implementation's literal console
   output beside ours.
4. Never overstate what you got done. If you cannot prove the fix locally, say so with a
   reason from the closed vocabulary in .gate/abstention-reasons.txt.
5. Do NOT add a Co-Authored-By or "Generated with" trailer to commits or the PR body.
6. Commit subjects use `subsystem: lowercase imperative`, wrapped at 72 cols, with a
   prose body naming cause and fix.
```

### 7.5 The gate — the load-bearing mechanism

This is what makes the output un-fakeable and is Bun's direct answer to its own 4-bullet slop definition.

```bash
#!/usr/bin/env bash
# worker/gate.sh — emits the evidence block or a structured abstention.
# Terminal states: PROVED | ABSTAINED(<reason>) | REJECTED(-> iterate)
set -euo pipefail
BASE=$(cat .gate/base-sha)
TESTS="$*"                 # test files the agent claims to prove the fix
OUT=.gate/evidence.md

# --- 1. FAILS ON MAIN: replay the PRISTINE pre-fix tree, not a hand-edited approximation.
git archive "$BASE" | (mkdir -p /tmp/prefix && tar -x -C /tmp/prefix)
cp -R $TESTS /tmp/prefix/                     # new tests onto the OLD source
FAIL_ASAN=$( cd /tmp/prefix && build --profile=debug   --asan && run-tests $TESTS ; echo "rc=$?" )
FAIL_REL=$(  cd /tmp/prefix && build --profile=release        && run-tests $TESTS ; echo "rc=$?" )

# --- 2. PASSES ON PR
PASS_ASAN=$( build --profile=debug   --asan && run-tests $TESTS ; echo "rc=$?" )
PASS_REL=$(  build --profile=release        && run-tests $TESTS ; echo "rc=$?" )

# --- 3. Verdict. A gate that could not RUN is a THIRD state, never a pass.
if   grep -q 'rc=0' <<<"$FAIL_ASAN$FAIL_REL"; then verdict=REJECTED   # test passes without the fix => invalid
elif grep -q 'rc=0' <<<"$PASS_ASAN" && grep -q 'rc=0' <<<"$PASS_REL"; then verdict=PROVED
else verdict=REJECTED; fi

ITER=$(cat .gate/iteration); PASSED=$(cat .gate/passed); REJECTED=$(cat .gate/rejected)

# --- 4. Emit, byte-for-byte in robobun's shape.
{
  echo '<!-- acme:evidence:begin -->'; echo; echo '---'; echo
  echo "**[${GATE_NAME:-review}]** gate passed · iteration ${ITER} · $(git diff --name-only "$BASE" | wc -l | tr -d ' ') files touched"; echo
  printf '<details><summary>fails on main (without fix)</summary>\n\n```console\n%s\n%s\n```\n\n</details>\n\n' "$FAIL_ASAN" "$FAIL_REL"
  printf '<details><summary>passes on PR (with fix)</summary>\n\n```console\n%s\n%s\n```\n\n</details>\n\n' "$PASS_ASAN" "$PASS_REL"
  printf '<details><summary>diff hotspot</summary>\n\n```\n%s\n```\n\n</details>\n\n' "$(git diff --stat "$BASE")"
  echo "**gate history** · ${PASSED} passed · ${REJECTED} rejected · iteration ${ITER}"; echo
  printf '<details><summary>evidence per changed file</summary>\n\n```\n%s\n```\n\n</details>\n\n' "$(telemetry-per-file)"
  echo '<!-- acme:evidence:end -->'
} > "$OUT"
```

Abstention path (Bun: 88/200 PRs — a first-class outcome, publicly declared):

```text
# .gate/abstention-reasons.txt  — CLOSED vocabulary. Anything not on this list is a REJECT.
Platform-specific test(s) that do not run on this machine. Deferring to CI, which covers all platforms: {{PATHS}}
Platform-specific test-only change; deferring to CI.
docs-only change; test-proof not applicable
build/CI scripts only; test-proof not applicable
```
```bash
{ echo '<!-- acme:evidence:begin -->'; echo; echo '---'; echo
  echo "**no test proof** · iteration ${ITER} · ${REASON}"; echo
  echo '<!-- acme:evidence:end -->'; } > "$OUT"
```

Per-file tool-call telemetry (`reads / edits / tests`) comes from the stream-json log:

```bash
# telemetry-per-file — derive from the agent's own tool calls.
jq -r 'select(.type=="assistant") | .message.content[]? | select(.type=="tool_use")
       | [.name, (.input.file_path // .input.path // "")] | @tsv' \
  "/workspace/logs/${RUN_TOKEN}-${SLUG}.jsonl" |
awk -F'\t' '$2!=""{ if($1=="Read")r[$2]++; else if($1~/Edit|Write/)e[$2]++; else if($1=="Bash")t[$2]++ }
  END{ printf "%-55s %6s %6s %6s\n","file","reads","edits","tests";
       for(f in r) printf "%-55s %6d %6d %6d\n", f, r[f], e[f], t[f] }'
```

Gate registry keyed by change class (Bun's observed names and rough frequencies):

```yaml
# gates.yml
review:        {match: "**",                          weight: 82}   # default
stamp-90s:     {match: ["docs/**","**/*.md"],         weight: 13}   # fast path, small/obvious
decide:webkit: {match: ["vendor/WebKit/**","WEBKIT_VERSION"], weight: 3, escalate: true}
decide:dep:    {match: ["package.json","Cargo.toml","vendor/**"],  weight: 1, escalate: true}
max_iterations: 8    # robobun's observed max; distribution 0:88 1:106 2:55 3:20 4:9 5:3 6:3 7:1 8:2
```

### 7.6 PR mechanics

```bash
#!/usr/bin/env bash
# worker/open-pr.sh
set -euo pipefail
git push -u origin "$BRANCH"

BODY=$(mktemp)
{ [ -n "${SOURCE_REF:-}" ] && printf 'Fixes %s\n\n' "$SOURCE_REF"
  cat .gate/prose.md          # agent-written: What / Repro / Cause / Fix / Verification
  cat .gate/evidence.md       # harness-written, never model-written
} > "$BODY"

PR=$(gh pr create --repo "$REPO" --head "$BRANCH" --base main \
      --title "$TITLE" --body-file "$BODY" \
      --assignee "$HUMAN_REVIEWER" --json number --jq .number)

# Machine-parseable state token, posted as a COMMENT (distinct from the body).
gh pr comment "$PR" --repo "$REPO" --body "$(cat <<'EOF'
**Status**: ready for review

Reproduced with:
```sh
USE_SYSTEM_BIN=1 run-tests <file>   # fails
build && run-tests <file>           # passes
```
EOF
)"
```

Suppress default trailers (robobun's commits carry none):

```bash
# Strip any model-added attribution before committing.
git filter-branch -f --msg-filter \
  'grep -v -e "Co-Authored-By: Claude" -e "🤖 Generated with"' "$BASE..HEAD"
```
Cleaner: instruct in the prompt (rule 5 above) and enforce with a `commit-msg` hook:
```bash
#!/bin/sh
# .git/hooks/commit-msg
grep -qE 'Co-Authored-By: Claude|🤖 Generated with' "$1" && {
  echo "error: attribution trailer is stripped by policy — see prompts/task.md rule 5"; exit 1; }
exit 0
```

### 7.7 Repo-side rails (copy these nearly verbatim)

```
repo/
├── CLAUDE.md                       # build + run-one-test in the first 45 lines
├── AGENTS.md -> CLAUDE.md          # ln -s, zero-cost dual-vendor
├── REVIEW.md                       # mined from YOUR merged-PR review threads
├── src/CLAUDE.md, test/CLAUDE.md   # directory-scoped, so no agent loads all ~90 KB
├── .claude/
│   ├── settings.json               # hooks ONLY, no permissions block
│   ├── hooks/pre-bash-guard.js     # argv-normalized deny
│   ├── hooks/post-edit-format.js   # format only, NO organize-imports
│   ├── commands/*.md               # the CI prompts live here, versioned + reviewable
│   ├── skills/*/SKILL.md           # descriptions naming literal SYMBOLS
│   └── docs/landing-prs.md         # situational tier, trigger table at top
└── .github/workflows/
    ├── auto-label-agent-prs.yml
    ├── on-slop.yml
    ├── close-stale-agent-prs.yml
    └── comment-cop.yml
```

`.claude/settings.json` — copy Bun's exactly:
```json
{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/pre-bash-guard.js"}]}],"PostToolUse":[{"matcher":"Write|Edit|MultiEdit","hooks":[{"type":"command","command":"\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/post-edit-format.js"}]}]}}
```

`.claude/hooks/pre-bash-guard.js` — the argv-normalization core, which is the part that actually works:
```js
#!/usr/bin/env bun
const input = await Bun.stdin.json();
const raw = input?.tool_input?.command ?? "";

// Claude will append ` 2>&1` / pipe to evade a naive string match.
// Normalize to argv semantics BEFORE deciding.
let toks = raw.trim().split(/\s+/);
const pipeAt = toks.indexOf("|"); if (pipeAt >= 0) toks = toks.slice(0, pipeAt);
toks = toks.filter(t => !/^(2>&1|1>&2|>>?|>\S+)$/.test(t));
const env = {};
while (toks.length && /^[A-Z_][A-Z0-9_]*=/.test(toks[0])) {
  const [k, ...v] = toks.shift().split("="); env[k] = v.join("=");
}
const [cmd, ...args] = toks;

const deny = r => (console.log(JSON.stringify({
  hookSpecificOutput: { hookEventName: "PreToolUse", permissionDecision: "deny",
                        permissionDecisionReason: r }})), process.exit(0));

if (cmd === "run-tests" && env.USE_SYSTEM_BIN !== "1")
  deny("error: In development, use `build && run-tests <file>` to test your changes");
if (args[0] === "test" && args.length === 1)
  deny("will run all tests. Use `run-tests <path>` with a specific test file.");
if (cmd === "timeout" && args.includes("build"))
  deny("error: Run `build` without a timeout");
process.exit(0);
```

`auto-label-agent-prs.yml` (complete):
```yaml
name: Auto-label agent PRs
on:
  pull_request:
    types: [opened]
jobs:
  auto-label:
    if: github.event.pull_request.user.login == 'acmebot' || contains(github.event.pull_request.body, 'acme:evidence:begin')
    runs-on: ubuntu-latest
    permissions: {contents: read, pull-requests: write}
    steps:
      - uses: actions/github-script@f28e40c7f34bde8b3046d885e986cb6290c5673b # v7
        with:
          script: |
            github.rest.issues.addLabels({
              owner: context.repo.owner, repo: context.repo.repo,
              issue_number: context.payload.pull_request.number,
              labels: ['agent'],
            });
```

`on-slop.yml` (complete — the one-label human kill switch):
```yaml
name: Close AI Slop PRs
on:
  pull_request_target:
    types: [labeled]
jobs:
  on-slop:
    if: github.event.label.name == 'slop'
    runs-on: ubuntu-latest
    permissions: {issues: write, pull-requests: write}
    steps:
      - uses: actions/github-script@f28e40c7f34bde8b3046d885e986cb6290c5673b # v7
        with:
          script: |
            const n = context.payload.pull_request.number;
            await github.rest.issues.createComment({ owner: context.repo.owner, repo: context.repo.repo,
              issue_number: n, body:
`This PR has been closed because it was flagged as AI slop.

Many AI-generated PRs are fine, but this one was identified as having one or more of the following issues:
- Fails to verify the problem actually exists
- Fails to test that the fix works
- Makes incorrect assumptions about the codebase
- Submits changes that are incomplete or misleading

If you believe this was done in error, please leave a comment.` });
            await github.rest.pulls.update({ owner: context.repo.owner, repo: context.repo.repo,
              pull_number: n, title: 'ai slop',
              body: 'This PR was flagged as AI slop; the description has been updated to avoid confusion or misleading reviewers.',
              state: 'closed' });
```

`close-stale-agent-prs.yml` (complete — mandatory GC; without it the backlog buries the humans):
```yaml
name: Close stale agent PRs
on:
  schedule:
    - cron: "30 0 * * *"
  workflow_dispatch:
jobs:
  close-stale:
    runs-on: ubuntu-latest
    permissions: {pull-requests: write}
    env:
      GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
      GH_REPO: ${{ github.repository }}
    steps:
      - run: |
          ninety_days_ago=$(date -u -d '90 days ago' +%Y-%m-%dT%H:%M:%SZ)
          gh pr list --author acmebot --state open --json number,updatedAt --limit 1000 \
            --jq ".[] | select(.updatedAt < \"$ninety_days_ago\") | .number" |
          while read -r pr_number; do
            gh pr close "$pr_number" --comment "Closing this PR because it has been inactive for more than 90 days."
          done
```

`comment-cop.yml` — the general pattern (restate the violated rule's exact sentence at the violation site, with a content-keyed marker for auto-resolve):
```yaml
name: Comment Cop
on:
  pull_request_target:
    types: [opened, synchronize, reopened, labeled]
permissions: {contents: read, pull-requests: write}
jobs:
  cop:
    if: contains(github.event.pull_request.labels.*.name, 'agent')
       && (github.event.action != 'labeled' || github.event.label.name == 'agent')
    runs-on: ubuntu-latest
    timeout-minutes: 5
    steps:
      - uses: actions/github-script@f28e40c7f34bde8b3046d885e986cb6290c5673b # v7
        with:
          script: |
            const crypto = require('crypto');
            const MIN_LINES = 2;
            const RULE = 'If you need a paragraph-long comment to justify why the workaround is OK, the code is wrong — fix the code';
            const keyFor = g => `${g.path}:${crypto.createHash('sha256').update(g.text).digest('hex').slice(0,12)}`;
            // ... walk the diff via pulls.listFiles, collect added comment groups >= MIN_LINES in src/,
            //     skip any group matching /SAFETY:/, post one review comment per group with
            //     `<!-- comment-cop:${keyFor(g)} -->` prefixed, and resolveReviewThread any
            //     existing thread whose key no longer appears in the diff.
```

Idempotency for every event-triggered agent job — **the state store is the output surface**:
```markdown
<!-- .claude/commands/dedupe.md, step 1 -->
1. Use an agent to check if the issue already has a dedupe comment: check for the exact
   HTML marker `<!-- dedupe-bot:marker -->` in the issue comments - ignore other bot
   comments. If present, STOP.
```

The CI invocation carries zero prompt engineering:
```yaml
      - uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5 # v4   # so .claude/commands/*.md exist on disk
      - uses: anthropics/claude-code-base-action@98d41f9809750c4c96f2cd285746ecef889f14bc
        env:
          ANTHROPIC_MODEL: claude-opus-4-6[1m]     # [1m] = 1M context, for whole-corpus search
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}    # env var -> the agent's own `gh` calls authenticate
        with:
          prompt: "/dedupe ${{ github.repository }}/issues/${{ github.event.issue.number }}"
          anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}
```

### 7.8 Rails checklist

| Rail | Bun's mechanism | Why it is non-optional |
|---|---|---|
| RED-proof | `USE_SYSTEM_BUN=1` must FAIL, `bun bd` must PASS | The anti-slop primitive. Everything else is downstream. |
| Deny-hook | argv-normalized `PreToolUse` | Prose alone demonstrably failed (hooks added 2025-10-04 "to prevent common development mistakes"). |
| Format split | idempotent in hook, destructive at CI | organize-imports between agent edits corrupts multi-step sequences. |
| Publication gate | evidence block or structured abstention | Makes the 4-bullet slop test un-fakeable. |
| Provenance label | `claude` label at open time | Everything downstream keys on it. |
| Kill switch | `slop` label → retitle + close | Retitling removes the misleading AI description from review queues. |
| Backlog GC | 90-day auto-close, `--limit 1000` | 142 PRs/day vs 2 human mergers. Without GC the queue is unusable. |
| Merge boundary | humans only, bot has write not maintain | The single safety property that makes 6,691 agent PRs tractable. |
| Adversarial review | separate identity (`claude[bot]` App) | Self-graded review is not review. |
| Tooling honesty | `bun run pr:comments` because `gh pr view --comments` silently drops review data | **An agent cannot detect silent truncation.** Ship a wrapper and name the omission in CLAUDE.md. |

**UNKNOWN, substituted:** model/effort per worker (Bun's only public signal is `claude-opus-4-6[1m]` on its CI jobs, not the farm); fleet size and concurrency; per-task token/time budget; the queue's generators; how the gate is invoked (in-agent vs harness-supervised); how review-comment webhooks re-enter a worker; the exact reuse policy for run tokens.

---

## 8. Open questions

| # | Question | Why unresolved | Experiment that would settle it |
|---|---|---|---|
| 1 | **Is the farm's push credential the same token as `secrets.ROBOBUN_TOKEN`?** | `performed_via_github_app: null` cannot distinguish classic PAT / fine-grained PAT / OAuth-App token. | Requires org-admin: read the account's token audit log, or diff the token's `X-OAuth-Scopes` on a request you control. Not obtainable externally. |
| 2 | **Is robobun a private org member or a repo collaborator, and at what permission level?** | `orgs/oven-sh/memberships/robobun` → 403; `collaborators/robobun/permission` → 403; `author_association` tracks visibility, not role. | Ask a maintainer, or observe a write only maintainers can do (e.g. `resolveReviewThread` on someone else's thread, branch-protection bypass). |
| 3 | **Where does the orchestrator actually run?** | Off-GitHub is *inferred* from the SSH farm key, `/workspace/bun`, and platform-abstention reasons — but a private-repo Actions workflow with a robobun PAT is publicly byte-identical. | Correlate push timestamps against GitHub Actions' hosted-runner IP egress windows; or check whether pushes ever occur during a GitHub Actions incident window. Weak either way. Only a maintainer statement settles it. |
| 4 | **What generates the self-directed stream?** | `farm` appears in zero of 20,713 tree paths; no gist leaks config; `robobun:evidence` returns `[]` in global code search. | Cluster ~1,000 unlinked PR titles/slugs and look for a generator signature (e.g. every `dead-code-*` PR touching files with zero coverage would implicate a coverage-driven generator). Inferential only. |
| 5 | **Fleet size and concurrency.** | 8 inter-arrival gaps <10s prove ≥2 concurrent; nothing bounds above. | Take the max number of *distinct branches receiving a push within any 60s window* over 30 days of push events — a hard lower bound on worker count. Cheap and worth running. |
| 6 | **What is the gate's rejection rate?** | `gate rejected` lines never appear in a published body; only the `gate history · P passed · R rejected` tally survives, and only for the PR that eventually shipped. Work rejected to death is invisible. | Sum `R` across all 6,691 bodies to get a *floor* on rejections-that-still-shipped. The rejected-to-death population is unobservable by construction. |
| 7 | ~~**Revert/regression rate of merged robobun PRs**~~ **RESOLVED — see §0.2.** robobun 0.34% vs humans 1.33%; zero reverts post-2026-04. | ~~No public data~~ now measured. | `gh api "search/commits?q=repo:oven-sh/bun+Revert"` cross-joined against merged robobun PR SHAs; plus `git log --grep='^Revert'` on main with `git log -S` blame back to a robobun commit. **This is the highest-value unrun experiment in the whole corpus** — it is the only direct measure of whether the 1,776 merges were actually good. |
| 8 | **Which model / effort / harness runs the worker?** | The only in-repo model pin (`claude-opus-4-6[1m]`) is on the two triage CI jobs, not the farm. | Statistical fingerprinting of prose style against known model outputs — weak. A maintainer statement or a leaked config settles it. |
| 9 | **When exactly did the trailer get stripped?** | PR #28031 (2026-03-12) has `🤖 Generated with [Claude Code](https://claude.com/claude-code)`; PRs from 2026-07 have none. | Binary-search PR bodies by `created:` for the last occurrence of `🤖 Generated with` among `author:robobun`. One `gh api search/issues` call per bisection step. |
| 10 | ~~**Auto-closed at 90d vs rejected on merit?**~~ **RESOLVED — see §0.1.** Neither: 83.0% are robobun self-closing duplicates; stale-bot only 5.5%; humans 9.6%. | The stale-closer inflates the denominator of the 44.2% merge rate by an unknown amount. | For each closed-unmerged PR, check whether its last comment is exactly `Closing this PR because it has been inactive for more than 90 days.` and its closer is `github-actions[bot]`. Fully determinable with `gh api` — **run this before quoting 44.2% anywhere.** |
| 11 | **Is the run-token reuse policy campaign-scoped, worker-slot-scoped, or retry-scoped?** | 47 reused tokens show all three shapes: same-family retries (`d8266e41`, 6 null-deref fixes in 5 days), a named program (`73f947d6`, binary-size), and 70-day-apart unrelated work (`898354b3`). | Correlate reuse gaps against a worker-slot hypothesis: if a token is a slot id, reuses should cluster by machine — testable if any per-machine signal (build-timing fingerprints in the evidence blocks) can be extracted. |
| 12 | **Does the gate run before or after the branch push?** | Iteration counters survive rejections, and rejected iterations never appear publicly — consistent with either. | Check whether any `farm/*` branch exists in `refs/heads` with no PR *and* no evidence block, or whether force-push counts correlate with `gate history` rejection counts. Partially determinable from the ref graveyard. |
