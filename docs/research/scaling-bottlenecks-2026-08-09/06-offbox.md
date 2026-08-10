# 06 · Off-box — what stands between `ca7db1a1` and real session capacity

**Verdict.** The create is real and ~91%-reliable per fire. Everything after the create is unbuilt or
structurally refused, and the **App install named as the "earned next step" is aimed at the wrong
mechanism** — the vendor documents that App installation "is not a session-level access control" and
that a *bundle* session **can** push when GitHub auth is configured (it is). Two independent
structural blockers, neither of them bundle mode, explain the 19-for-19 zero-push record. Working
off-box sessions today: **0**. Reachable in one build wave: **~10**. Reachable ceiling: **not capped
by cloud concurrency** (no numeric cap exists in vendor docs or in our measurements) — it is capped
by 4 accounts' shared rate limits, and by an O(N)-serial local observe/land loop that reintroduces
the local cost off-box was bought to escape.

---

## 1 · Lane state diagram — where the round trip stops

```
  ┌─────────┐   ┌──────────┐   ┌──────────┐   ┌──────────┐   ┌────────────┐   ┌──────┐
  │ ADMIT   │──▶│ CREATE   │──▶│ DECLARE  │──▶│  BOOT    │──▶│   WORK     │──▶│ PUSH │──┐
  └─────────┘   └──────────┘   └──────────┘   └──────────┘   └────────────┘   └──────┘  │
      ✅ built      ✅ built       ✅ built       ✅ observed      ❓ UNKNOWN       ⛔ STOP  │
   boolean gate   90.6%/fire    immediate,     BOOTING seen    never observed   0 refs, │
   (not a count)  (3 attempts)  account-scoped  live once      by any instrument 19/19   │
                                                                                        │
  ┌──────────┐   ┌─────────────┐   ┌──────────┐   ┌────────┐                            │
  │ OBSERVE  │◀──│ RECONCILE   │◀──│  LAND    │◀──│ VERIFY │◀───────────────────────────┘
  └──────────┘   └─────────────┘   └──────────┘   └────────┘
   ✅ built       ✅ built           ✅ built        ⚠️ inert
   NO SCHEDULER   NO SCHEDULER      desk-land →     paths= empty ⇒ a landed
   (manual only)  (manual only)     ship-land       branch reads ELIGIBLE forever
```

**The stop point is PUSH, and it is reached by a session whose execution has never been observed.**
`git ls-remote origin` measured live in this session returns **2 lines — `HEAD` and
`refs/heads/main`, nothing else**. That is stronger than the plan's `claude/*`-scoped check: no
cloud session has pushed *any* ref under *any* name, so "it pushed somewhere we did not look" is
excluded by measurement, not by assumption.

| Stage | Built? | Evidence |
|---|---|---|
| ADMIT | ✅ but boolean | `scripts/handoff-fire.sh:3570-3618` — `claude-accounts --route general`; no per-account session count, no in-flight count |
| CREATE | ✅ | `scripts/lib/cloud-create.sh:185-223`; `scripts/handoff-fire.sh:5479-5635` |
| DECLARE | ✅ | `handoff-fire.sh:5620-5627`; 19 `.decl` files in `~/.claude/autonomy/cloud/` |
| BOOT | ✅ observed | `session_01Kpc1kwHjwsRjERad1tTDuG` → `BOOTING`, then `NOT-STARTED` at 15m (`CLOUD_OBSERVABILITY.md:1370-1374`) |
| WORK | ❓ never observed | `CLOUD_OBSERVABILITY.md:1380-1393` — send arm delivered, `read:null` in the `.sends` file; no local reader exists |
| PUSH | ⛔ | live `git ls-remote origin` = 2 lines, `refs/heads/main` only |
| OBSERVE | ✅ code, ❌ scheduler | `bin/cc-cloud:470` `cmd_poll`; **zero callers** — no launchd plist, no hook, no daemon |
| RECONCILE | ✅ code, ❌ scheduler | `scripts/cloud-reconcile.sh`; only referenced in `handoff-fire.sh:5633` as a printed hint |
| LAND | ✅ | `cloud-reconcile.sh:234-243` → `desk-land.sh` (throwaway worktree, so the shared-checkout refusal at `desk-land.sh:166` does **not** bite) |

---

## 2 · What the landed create actually does (`ca7db1a1` / `1b2b8a94`)

`scripts/handoff-fire.sh:5479-5635` — a 157-line branch placed **before** the typed command is
composed, so no pane/composer/registry machinery runs. In order:

1. Resolve `scripts/lib/cloud-create.sh` over 4 candidate paths; **fail-closed** at `:5496-5500`
   (exit 10) — deliberately unlike the box-local capacity library, which fails open.
2. Resolve the account config dir from `$CHOSEN`; refuse `--launcher` (`:5511-5521`, exit 10).
3. Assign the branch: `cc_cloud_branch_name()` → `claude/fire-<UTC>-<pid>`
   (`cloud-create.sh:238`). **Assigned, not guessed** — the prior fire-shaped declaration
   `claude/fire-20260809T101645Z-78351` had no producer anywhere in the tree.
4. Compose payload = brief + a push instruction (`:5540-5552`).
5. `cc_cloud_create` (`cloud-create.sh:210-223`): pty-allocated create with **bounded retry over
   `refused-bundle` only**, 3 attempts, 5 s backoff. Binary default
   `$HOME/.claude-220/node_modules/.bin/claude` — **verified present, 2.1.220**.
6. Four exit classes: `created` → declare → exit 0 · `created-unidentified` → exit 11 ·
   `refused-{bundle,quota,harness,other}` → exit 10 · declare failure → exit 11.

**Not on the fire path:** `cc-cloud preflight`. Grepped at tip — the only `preflight` hits in
`handoff-fire.sh` are `:2445` and `:4386`, both unrelated. This is blocker B2 below.

### NOT-STARTED, measured

`bin/cc-cloud:279-286` — `NOT-STARTED` = `remote_sha` returned rc 0 with empty stdout **and**
`age > boot_s`. `DEF_BOOT=900` (`bin/cc-cloud:151`). The verdict is a statement about the ref, not
about the VM; `bin/cc-cloud:274-277` keeps sensor failure (`rc 2`) separate as `UNKNOWN`, so the
instrument cannot forge a death. Prior sessions ran **7 h** and **17 h** with 0 refs
(`CLOUD_OBSERVABILITY.md:754-755`), so the 15 m budget is not the reason.

---

## 3 · Blockers, in the order they bite

### B1 · 🚨 Push protection refuses the ref the payload names — and the repo already found the fix

Vendor, `code.claude.com/docs/en/cloud-environments` § GitHub proxy:

> **Push protection**: `git push` works only against the session's **current working branch**;
> cloning, fetching, and PR operations work normally.

The payload (`handoff-fire.sh:5547`) instructs:

```
git push origin HEAD:claude/fire-<UTC>-<pid>
```

`claude/fire-…` is a name **the firing side invented**. It is not the session's working branch, so
the proxy refuses the push — and the session has no way to tell us, because the cloud→here arm does
not exist. **This repo already learned this exact lesson and did not carry it forward:**
`CLOUD_OBSERVABILITY.md:737-740` records that §7.4's push probe was void as first written and *"the
fix is `git switch -c` **first**, so the control is a real session branch."* Grepped at tip:
`switch -c` / `checkout -b` appear **nowhere** in `handoff-fire.sh` or any `cloud-*.sh` — only in
that one prose line.

**Fix (one line in the payload):** `git switch -c <branch>` before the push, then
`git push -u origin HEAD`. Cost: ~3 lines. This is the highest-value change in the whole lane.

### B2 · 🚨 The fire clones a branch that does not exist on the remote, and the guard built for it is never called

Vendor, `…/claude-code-on-the-web` § From terminal to web:

> The session clones your current directory's GitHub remote **at your current branch**, so push
> first if you have local commits, **since the VM clones from GitHub rather than your machine**.

Measured on this box: **429 local branches with no upstream**, and `git ls-remote --heads origin`
returns exactly **1** head. Every worktree this repo fires from is on an upstream-less branch —
`cloud-g5-create` (the cloud worktree) is at `ce865318 [cloud-g5-create]`, absent from origin.

`bin/cc-cloud:560-571` (`cmd_preflight`) exists precisely to refuse this:

```
✗ branch <b> is NOT on <remote> — the cloud VM would clone without it.
  git push -u <remote> <b>
```

…and `handoff-fire.sh --cloud` never calls it. Under §6.5's own reading (`CLOUD_OBSERVABILITY.md:
499-501`) the consequence is that *"the session silently runs against the default branch instead."*

### B3 · ⚠️ The App-install "earned next step" is aimed at a mechanism the vendor says is not the gate

`CLOUD_OBSERVABILITY.md:1408-1415` makes installing the Claude GitHub App the next move, on the
reasoning that it eliminates bundle mode and *"gives the VM an authenticated remote to push to."*
Two vendor sentences contradict the second half, and one contradicts the framing:

> With either method, a cloud session can access any repository the connecting GitHub account can
> see, **not just the repositories the Claude GitHub App is installed on**. App installation enables
> PR webhooks for Auto-fix; **it is not a session-level access control**.

> *(Troubleshooting → Session creation failed)* The connecting GitHub account must have access to
> the repository … either through the Claude GitHub App authorization **or a `gh` token synced via
> `/web-setup`**. **Installing the App on the repository isn't required.**

> Sessions created from a bundle **can't push back to a remote unless you also have GitHub
> authentication configured**.

We have `/web-setup` configured (`CLOUD_OBSERVABILITY.md:478-485`, and 4 sessions were visible at
claude.ai/code). So **bundle mode is not a categorical push blocker for this account** — which
removes the mechanism §S5.5 hypothesised (`CONCURRENCY_PROGRAM.md:1077-1082`) and removes the
premise §11.4's next step rests on.

**What survives, and it is narrower:** §S5.3 decompiled 2.1.220 and found the CLI's own
bundle-vs-clone branch keys on `x = appInstalled` from
`GET /api/oauth/organizations/{org}/code/repos/{owner}/{repo}` → `status.app_installed`
(`CONCURRENCY_PROGRAM.md:984-989`). A binary read outranks a doc on *what the CLI does*
(`[[spec-named-mechanism-may-be-prose-only]]`, shipping side wins). So installing the App plausibly
still flips the CLI to a `git_repository` source and **removes the ~95 MiB upload** — a real
reliability win worth ~9 points of per-fire success. It is **not** the thing that makes a push
possible. Grade it a *create-reliability* fix, not a *round-trip* fix, and do B1+B2 first: they are
free, they are ours, and a post-App fire that still leaves `claude/*` empty would be read as
evidence about the App when the cause was the payload.

⚠️ Corollary — an internal contradiction to settle: `CLOUD_OBSERVABILITY.md:504-510` declares
bundle-vs-clone "SETTLED — CLONE on the linked path" as of 2026-08-08, i.e. `/web-setup` ⇒ clone.
§11.1's attempt 1 (`refused-bundle`, 2026-08-09) is a live refutation: the link is established and
the CLI still bundled. §6.5's row 3 in the claims table (`:588`) is **stale** and should be marked.

### B4 · ⚠️ Nothing schedules observation or reconciliation

`bin/cc-cloud:470` (`cmd_poll`, "the ONLY mutator") and `scripts/cloud-reconcile.sh` have **zero
automated callers**. Checked: no `~/Library/LaunchAgents/*.plist` references either
(`grep -rl 'cc-cloud\|cloud-reconcile'` → empty), 20 `com.claude.*` jobs loaded, none of them cloud.
Consequence: `O2 remote ref ADVANCES` — described in `bin/cc-cloud` as *"the only heartbeat there
is"* — is never advanced, so `ALIVE` and `STALLED` are unreachable states in practice, and a cloud
branch that *did* push would sit unlanded until a human ran `--list`.

### B5 · ⚠️ The admission gate is a boolean, and it prices the wrong account when `--account` is explicit

`handoff-fire.sh:3592` calls `claude-accounts --route general` → one routable account, ADMIT/REFUSE.
There is no per-account cloud-session count and no in-flight count anywhere in the branch: **150
concurrent cloud fires would pass this gate 150 times.** Worse, the routed account is only recorded
(`:3611-3617`) — the fire spends `CLOUD_ACCT="$CHOSEN"` (`:5509`), which is `$ACCOUNT` verbatim when
`--account nextN` is passed (`:5410-5412`). With `--account auto` they agree (same router); with an
explicit account — which is what the live fire used (`next3`) — **the headroom term and the charged
account are different accounts.**

### B6 · ⚠️ Send arm is broken by default; one live session is undeclared

- `CC_CLAUDE_BIN` is unset in env and in `~/.claude/settings*.json`. `bin/cc-notify:482-490` then
  falls back to `command -v claude` → the 2.1.114 pin, which has no `--cloud`. It self-diagnoses
  correctly (`verdict=cloud-transport-unavailable reason=flag-unsupported`, exit 4) rather than
  lying — but the send arm is **non-functional out of the box** for every future session.
- `session_01L7oug9Pgz2H…` was created by `cloud-ceiling-probe.sh` at 2026-08-08T10:19:06Z and has
  **no `.decl` file**. A live create that spent quota, invisible to `cc-cloud list` and to the 600 s
  orphan reaper — the exact failure `created-unidentified` was built to make loud, arriving through
  the probe, which does not declare.

### B7 · ⚠️ `paths=` empty ⇒ a landed cloud branch reads ELIGIBLE forever

Already recorded at `CLOUD_OBSERVABILITY.md:1347-1363`. `bin/cc-cloud:223` returns 1 on empty paths,
so `classify()` never reaches `LANDED`. Confirmed in the live declaration: `paths=` and `base_sha=`
are both empty in `session_01Kpc1kwHjwsRjERad1tTDuG.decl`. Cost is a wasted re-offer, not a wrong
land. Honest fix needs the cloud→here channel that does not exist.

### B8 · 📝 Two refusal classes the classifier has never seen

Vendor names `Session creation failed` / "stalls at provisioning" as a **VM-allocation** failure
("Retry after a minute, as capacity is provisioned on demand") and *environment expiry* as a
reclaim. Neither string matches `cc_cloud_classify`'s patterns (`cloud-create.sh:150-167`), so both
land in `refused-other` — the bucket the retry rule deliberately does **not** retry
(`cloud-create.sh:95-97`), and the one §11.2 argues has no true members. A transient
capacity refusal filed as "genuinely new, do not retry" is the wrong disposition. This is also the
first candidate for the ceiling instrument's missing calibration control (`CONCURRENCY_PROGRAM.md:
1040-1042` asks for exactly this: "one observation, anywhere, of a cloud *create* refused for a
limit").

---

## 4 · Create reliability — now vs the historic 50-75%

**Unchanged per attempt; ~91% per fire because of the retry.** Recomputed from the two ledgers plus
the live fire (rig faults excluded — `refused-harness` is our instrument, not the fleet):

| Ledger | created | real refusals (bundle) | rig faults | per-attempt |
|---|---|---|---|---|
| `ceiling-probe.jsonl` | 6 | 6 | 3 | 50.0% |
| `bundle-probe.jsonl` | 5 | 3 | 1 | 62.5% |
| live fire 2026-08-09 23:14Z | 1 | 1 | 0 | 50.0% |
| **total** | **12** | **10** | **4** | **54.5%** |

What changed is only the wrapper: `CC_CLOUD_CREATE_ATTEMPTS=3`, retrying **`refused-bundle` only**
(`cloud-create.sh:215`). At p=0.545 that is **1 − 0.455³ = 90.6% per fire**, ≈1.83 attempts per
successful create. Verified by the classifier hardening that makes the rate readable at all:
`cc_cloud_normalise` maps `CSI n C` **and** `CSI n G` to a space (`cloud-create.sh:136`) — without
the G arm every spaced pattern misses and a real refusal files as `refused-other`. The producer was
`scripts/lib/pty-run.py:strip_ansi`, fixed at source in the same commit.

The retry does **not** wrap the probes: `cloud-bundle-probe.sh` keeps the single-attempt entry point
so its number stays a per-attempt rate (`CLOUD_OBSERVABILITY.md:1341-1345`). Correct, and it is why
the table above is computable.

---

## 5 · Local cost of an off-box session — the ~zero claim, verified and bounded

**True for execution. False for observation and landing.**

| Local cost | Measured | Note |
|---|---|---|
| CPU/RAM while the VM works | **0** | no local process; `agents --json` proves the local census cannot even see it (`CLOUD_OBSERVABILITY.md:694-711`) |
| `cc-cloud is-offbox <id>` (the abstain lookup the 3 oracles call) | **0.00–0.13 s**, 2 file tests, no network | measured this session, 3 runs |
| `classify()` per session | **1 × `git ls-remote`** | measured 0.39 / 0.42 / 0.41 s this session |
| `cc-cloud --check` / `--table` / `--json` over N sessions | **N × ~0.4 s, SERIAL** | `emit_rows`/`emit_table`/`do_check` each loop one `classify` per id, no parallelism (`bin/cc-cloud:329-375`) |
| landing one cloud branch | **one throwaway git worktree + the full ship gate** | `desk-land.sh:144-155` creates the worktree; `ship-land.sh` runs shellcheck+bats |

At today's 19 declarations a full sweep is ~8 s. **At 150 it is ~60 s of serial network per sweep**,
single-threaded — which makes any polling cadence under ~2 min impossible without parallelising
`classify`. And the *landing* half is unambiguously local, expensive work: off-box moves execution,
not integration.

---

## 6 · Build list, dependency-ordered, to the first 10 working off-box sessions

| # | Item | Where | Why here in the order |
|---|---|---|---|
| **1** | Payload: `git switch -c <branch>` before the push | `handoff-fire.sh:5540-5552` | B1. Without it the proxy refuses every push. ~3 lines. Nothing downstream can be tested until this is true. |
| **2** | Call `cc-cloud preflight --repo --branch --remote` in the cloud branch; refuse or auto-`git push -u` the current branch | `handoff-fire.sh` before `:5532` | B2. The VM clones the remote at the current branch; 429 of our branches are not on it. The guard is already written. |
| **3** | One live fire, from a **pushed** branch, with a task that MUST produce a diff | — | This is the single observation that settles execute/push/reconcile/land at once — §10.4's own argument for ordering, now with the two defects it did not know about removed. |
| **4** | Add `refused-capacity` (`Session creation failed`, `provisioning`) to the classifier, **ahead of** the quota arm, and make it retryable | `cloud-create.sh:150-167`, `:215` | B8. Vendor calls it transient-and-retryable; today it is `refused-other`, which is explicitly not retried. Also the first real calibration artifact for G7. |
| **5** | Export `CC_CLAUDE_BIN` at a 2.1.220+ binary (settings or the launcher) | `~/.claude/settings.json` | B6. Send arm is the only steering channel and it is dead by default. |
| **6** | `cc-cloud declare` inside `cloud-ceiling-probe.sh` | `scripts/cloud-ceiling-probe.sh` | B6. Stop minting undeclared live sessions (1 already exists). |
| **7** | Scheduler: a launchd job running `cc-cloud poll` + `cloud-reconcile.sh --list` on a cadence | new plist, sibling of `com.claude.team-orphan-reaper` | B4. Without it O2 never advances and results strand. Do it after #3 so the cadence is set against a real push interval. |
| **8** | Parallelise `classify` (bounded fan-out) | `bin/cc-cloud:329-375` | Only binds above ~30 sessions; #7 makes the serial cost recurring. |
| **9** | Gate arithmetic: count in-flight declared sessions per account; refuse above a measured bound; price the account that will be **charged**, not the routed one | `handoff-fire.sh:3570-3618` | B5. Needed before any wide fan-out, not before 10. |
| **10** | Install the Claude GitHub App on `renchris/claude-infrastructure` (operator, GUI) | github.com/apps/claude | B3. Reliability: removes the ~95 MiB upload, taking per-fire from ~91% to ~100%. **Re-graded from "unlocks the round trip" to "unlocks reliability."** File it; do not block on it. |

Items 1–3 are one small session. Items 1–7 are the DoD for "10 working off-box sessions".

**Work supply is not a constraint:** `bin/cc-eligible sweep` run this session — **311 non-done
backlog items, 128 ELIGIBLE off-box** (140 `ineligible-box`, 23 `ineligible-branch-banking`, 20
`ineligible-visual`). The tap has ~13× the work it needs for 10 sessions.

---

## 7 · Realistic off-box count, and what caps it

| Horizon | Count | Binding constraint |
|---|---|---|
| **Today** | **0 working** (19 declared, 12 created, 0 executed-and-returned) | B1 + B2 — the push cannot land on the named ref, and the clone may not have the branch |
| **After build items 1–3** | **~10 per wave**, at ~11 fires (90.6%/fire) ≈ 20 create attempts | create reliability, and whether execution works at all — still unobserved |
| **After 1–7 + App** | **~40–60 sustained** | account rate limits across 4 accounts; the observe/land loop at ~0.4 s × N serial |
| **150** | not blocked by a *cloud* cap | see below |

**What does NOT cap it (measured / documented):**
- **No numeric concurrent-session cap exists.** Vendor § Limitations names only rate limits and
  says *"each `--cloud` command creates its own cloud session that runs independently… they'll all
  run simultaneously in separate sessions."* Our own probe reached ≥2 on one account with no ceiling
  (`CONCURRENCY_PROGRAM.md:852`), and §S5.4 marks the ceiling **UNMEASURABLE BY THIS INSTRUMENT**
  because a create refusal for a limit may be an event with no reachable instance.
- **Weekly quota does not gate create** — `next2` at 100% weekly created 4 sessions
  (`CONCURRENCY_PROGRAM.md:859-867`). Create and token-spend are different boundaries; only the
  first has ever been measured.
- **Box CPU/RAM** — 0 per session, verified §5.

**What actually caps it:**
1. **Account rate limits, 4-way shardable, volatile.** Vendor: *"Claude Code on the web shares rate
   limits with all other Claude and Claude Code usage within your account. Running multiple tasks in
   parallel consumes more rate limits proportionately."* This is the real economic ceiling and
   nothing in the fire path meters it — B5's gate is a boolean.
2. **T3 (token load per cloud session) is NOT MEASURED and has no instance**
   (`CONCURRENCY_PROGRAM.md:1083-1084`). Until one session executes, the per-session rate-limit draw
   is unknown, so the 4-account budget cannot be divided. **This, not the create, is what makes any
   number above ~10 a guess.**
3. **The local observe/land loop** — O(N) serial `ls-remote`, plus a worktree and a full gate run per
   landed branch. At 150 this is minutes of local work per sweep and a genuine local CPU cost.
4. **Environment expiry** — vendor: *"Cloud sessions stop after a period of inactivity and the
   session's VM is reclaimed."* No local instrument models this; `DEF_LIFE=21600` (6 h) is our own
   guess, not a vendor number.

---

## 8 · Adversarial pass — what I went looking for and what it changed

| Challenge | Outcome |
|---|---|
| "Is bundle mode really the blocker?" | **No.** Vendor says a bundle session can push with GitHub auth configured, which we have. B3 re-grades the App install from round-trip fix to reliability fix. |
| "Is there a datapoint already refuting the bundle hypothesis?" | **Yes, partially.** `session_01DcTULYmXVnUnrwyFKm8LGH` — next3, `--verify`d link, believed clone mode, an explicit four-`git push` brief — produced **0 refs in 7 h** (`CLOUD_OBSERVABILITY.md:755`). Under §6.5's model that session was in clone mode and refutes bundle-as-cause outright. Under §S5.3's `appInstalled` model it was in bundle mode and is consistent. **Unresolvable from here** — it was created outside both probes, so no create output was captured. Named rather than smoothed. |
| "Did they push under a different name?" | **No.** `git ls-remote origin` (all refs, live) = 2 lines. Excludes the alternative by measurement. |
| "Is the historic 19-for-19 record even evidence?" | **Weaker than it looks.** 9 of 19 declarations name `main`, 6 name `cloud-hardening`, 2 name `cc-probe-…`, 1 names a branch with no producer. Only **1 of 19** was declared against a branch the session was actually told to push. But the total-refs check above rescues it: nothing pushed anywhere, so the record stands. |
| "Is there a local read of a cloud session nobody considered?" | **Yes — `/tasks` and `--teleport`.** Neither appears anywhere in `CLOUD_OBSERVABILITY.md`, `CONCURRENCY_PROGRAM.md` or `bin/cc-cloud`. §9.1's *"the answer is unreachable from here by construction"* is overstated: `--teleport <id>` "loads the full conversation history into your terminal". It is blocked for a NOT-STARTED session (teleport requires the branch to be on the remote), so it does not rescue today's case — but `/tasks` is a live progress read the design never priced. |
| "Does the shared-checkout rule break the landing arm?" | **No.** `cloud-reconcile.sh` passes `--repo <shared checkout>` but `desk-land.sh:144-155` builds a **throwaway worktree** off the branch tip, so `TARGET_TOP != SHARED_RESOLVED` and the refusal at `:166` does not fire. |
| "Is the create binary actually there?" | **Yes** — `~/.claude-220/node_modules/.bin/claude` → 2.1.220. The default is correct. |
| "Is the tap on?" | **No** — `CC_FIRE_CLOUD` unset in env and settings; `--cloud` exits 2 (`handoff-fire.sh:5061-5069`). Correct and deliberate. |

---

## 9 · Sources

Code (read at `origin/main` tip `e13910ff`, worktree `/Users/chrisren/Development/.worktrees/scale-150`):
`scripts/handoff-fire.sh:3545-3620, 5035, 5051-5069, 5400-5433, 5461-5635` ·
`scripts/lib/cloud-create.sh:110-238` · `bin/cc-cloud:151-153, 186-234, 250-330, 329-375, 470, 523-598` ·
`scripts/cloud-reconcile.sh:1-90, 234-243` · `desk-land.sh:100-200` · `bin/cc-notify:478-500` ·
`bin/cc-eligible:1-45` · `bin/cc-dispatch:458-475, 1110-1223`

Plans: `docs/plans/CLOUD_OBSERVABILITY.md` §6.5 (`:456-534`), §6.7 (`:568-601`), §7.4 (`:713-746`),
§7.5 (`:748-768`), §10.4 (`:1156-1259`), §11–11.4 (`:1263-1425`) ·
`docs/plans/CONCURRENCY_PROGRAM.md` §S5 (`:559-664`), §S5.2 (`:839-933`), §S5.3 (`:935-1013`),
§S5.4 (`:1015-1056`), §S5.5 (`:1058-1084`) · `docs/research/session-capacity-ceiling-2026-08-09.md`
§5 (`:174-192`)

Commits: `ca7db1a1` / `1b2b8a94` (create; 938 insertions, 35 tests) · `4855c273` (§11) ·
`61799d76` (§11.4)

Live measurements taken this session (read-only): `git ls-remote origin` → 2 refs · `git ls-remote`
timing 0.39–0.42 s ×3 · `cc-cloud is-offbox` timing 0.00–0.13 s ×3 · 19 `.decl` files tabulated ·
both probe ledgers tallied · `cc-eligible sweep` → 311/128 · `git worktree list` · 429 upstream-less
branches · `launchctl list` + LaunchAgents grep · `~/.claude-220/…/claude --version` → 2.1.220

Vendor docs (fetched 2026-08-09): `code.claude.com/docs/en/cloud-environments` (§ GitHub proxy,
§ Access levels, § Setup scripts) · `code.claude.com/docs/en/claude-code-on-the-web`
(§ GitHub authentication options, § From terminal to web, § Send local repositories without GitHub,
§ Troubleshooting, § Limitations)
