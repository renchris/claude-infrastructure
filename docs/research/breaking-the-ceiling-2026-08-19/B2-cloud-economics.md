---
axis: B2 — CLOUD: does it buy capacity, and is the friction removable
status: measured
date: 2026-08-19
binary: 2.1.220 (/Users/chrisren/.claude-220/node_modules/@anthropic-ai/claude-code/bin/claude.exe)
builds_on: docs/research/orchestration-units-2026-08-19.md (commit 4a3bd3373, esp. A7)
supersedes_on_one_point: A3-VERIFY's `maxConcurrent: default(1)` handover (see §2.4)
---

# B2 — Cloud economics: it relieves the BOX, not the QUOTA

Method labels: **[M]** measured here · **[Q]** quoted from a vendor doc · **[I]** inferred, reasoning stated.

---

## 1 · Verdict (≤5 lines)

1. **Cloud bills the SAME 5-hour meter as a local session — measured, not quoted.** One cloud job on
   `next4` (810,556 tokens, 110 s) moved that account's `five_hour` utilization **21.0 → 22.0**, 46 s
   after the fire, after **six consecutive flat reads over 8 m 38 s**, while a co-sampled control
   account sat at 27.0 for all eight samples. **[M]**
2. **So cloud raises BURST without limit and adds ZERO sustained throughput.** It costs the box
   nothing (0 processes, 0 panes, 0 worktrees, 0 load — positive-controlled) and costs the quota
   exactly what a local session costs: **~1 point of a 5-hour window per ~0.8 M tokens, venue-independent.** **[M]**
3. **The ~15 target is therefore unreachable on 4 Max accounts by any amount of cloud.** The settled
   quota wall is 9.4 sustained working units fleet-wide; cloud's whole gain is that it lets the fleet
   *reach* 9.4 instead of stalling at the load gate's 4–8. That is **+1.4 to +5.4 sustained units, and
   it is the entire prize.** 15 needs ~6.4 Max accounts, or overage — and overage is
   `org_level_disabled` / `can_toggle: false` on **all four** accounts. **[M]**
4. **The friction the operator felt is already solved at the FIRE and unsolved at the OUTCOME.**
   One command, no TTY, 7 s: `cc-offload up --task <file> -n N --account auto`. But over 12 days,
   **168 fires → 101 pushed (60%) → 52 landed by content (31%)**. **[M]**
5. **`maxConcurrent: default(1)` is not a cloud limit at all** — it is the local cron-task runner's
   config. No per-account cloud concurrency cap is evidenced anywhere; the binding limit is quota. **[M]**

---

## 2 · Numbers, with the command behind each

### 2.1 THE DECISIVE MEASUREMENT — does a cloud session bill the Max meter?

**Instrument.** `bin/claude-accounts` reads `https://api.anthropic.com/api/oauth/usage` per account
(`fetch_usage`, line 641). I called that endpoint directly with each account's keychain OAuth token
(scratchpad `meter.py`, reusing `claude-accounts`' own `keychain_service()` sha256 derivation) —
**zero token cost**, so the instrument cannot contaminate the thing it measures. Sampled every ~46 s
across all four accounts, so three untouched accounts run as concurrent controls.

**Design.** `next4` was chosen because it was the only account showing zero ambient drift, and its
5-hour window resets at 16:20Z — no reset inside the experiment. Fire at **13:25:12Z**:

```
~/.claude/bin/cc-offload up --task /…/b2-brief.txt -n 1 --account next4
→ ✓ session_01CqQ7QRZPRtcBdXm9dHCxSd on next4 — anthropic_cloud VM, repo ATTACHED,
    branch claude/fire-20260819T132512Z-24086-1        (returned in 7 s)
```

**`five_hour` utilization, one row per sample** (`python3 meter.py`; UTC):

| sample | next4 (**target**) | next3 (control) | next | next2 |
|---|---|---|---|---|
| 13:16:33 | **21.0** | 27.0 | 19.0 | 26.0 |
| 13:22:05 | **21.0** | 27.0 | 22.0 | 30.0 |
| 13:22:52 | **21.0** | 27.0 | 22.0 | 31.0 |
| 13:23:38 | **21.0** | 27.0 | 23.0 | 31.0 |
| 13:24:25 | **21.0** | 27.0 | 23.0 | 32.0 |
| 13:25:11 | **21.0** | 27.0 | 23.0 | 33.0 |
| — | *— FIRE 13:25:12Z —* | | | |
| 13:25:58 | **22.0** ⬅ | 27.0 | 23.0 | 33.0 |
| 13:26:44 | **22.0** | 27.0 | 24.0 | 33.0 |
| 13:27:30 | **22.0** | 27.0 | 24.0 | 34.0 |
| 13:29:03 | **22.0** | 27.0 | 24.0 | 34.0 |

**The cloud session, from the control plane** (`GET /v1/code/sessions/<id>`, via
`scripts/cloud-create-api.py`'s own `get_session`):

| field | value |
|---|---|
| `environment_kind` | `anthropic_cloud` |
| `config.sources` | 1 (repo attached) |
| `created_at` → last `updated_at` | 13:25:14.19Z → 13:27:04.79Z = **110 s** |
| `external_metadata.usage.cache_read_tokens` | **728,786** |
| `external_metadata.usage.cache_write_tokens` | **76,138** |
| `external_metadata.usage.input_tokens` | 22 |
| `external_metadata.usage.output_tokens` | **5,610** |
| **total** | **810,556 tokens** |
| `post_turn_summary.status_detail` | `rangefmt.py + test_rangefmt.py written, 12 tests pass, pushed` |

**Reading.** The step is +1 point, on the owning account only, appearing inside the cloud session's
110-second life, bracketed by an 8 m 38 s flatline before and a 3 m 30 s flatline after, with a
control account showing **zero** movement across the whole window. Cloud consumption lands on the
subscription's 5-hour meter.

**Independent calibration.** `docs/research/cloud-local-cost-ab-2026-08-11.md` §5.6 recorded next3's
5-hour moving 3% → 8% across four sessions (2 cloud + 2 local) at 785 K–1.09 M cache-read each ⇒
**1.25 pt/session**. This probe: 810 K total ⇒ 1 pt. Consistent to within the instrument's resolution.
⇒ **~1 point of a 5-hour window per ~0.8 M tokens, and the venue does not change it.**

### 2.2 The structural corroborant — there is no cloud bucket to bill

Two independent reads, both negative, both positive-controlled.

**(a) The binary's own rate-limit header parser**, verbatim from 2.1.220
(`LC_ALL=C strings -a -n 6 claude.exe | grep -oE 'function kOu\(e\)\{.{0,900}'`):

```js
function kOu(e){let t={};
  for(let[r,n] of [["five_hour","5h"],["seven_day","7d"],
                   ["seven_day_overage_included","7d_oi"],["overage","overage"]]){
    let o=e.get(`anthropic-ratelimit-unified-${n}-utilization`),
        i=e.get(`anthropic-ratelimit-unified-${n}-reset`);
    if(o!==null&&i!==null) t[r]={utilization:Number(o),resets_at:Math.round(Number(i))}}
  return t}
```

Every `anthropic-ratelimit-*` header name in the whole binary
(`grep -oE 'anthropic-ratelimit[a-z0-9-]*' | sort -u`): `unified-{5h,7d,overage}-{utilization,reset,status}`,
`unified-grace-{5h,7d}-utilization`, `unified-grace-status`, `unified-fallback`,
`unified-overage-{disabled-reason,in-use,period-channel-utilization,period-monthly-utilization}`,
`unified-representative-claim`, `unified-{reset,status,upgrade-paths}`. **No cloud, remote, ccr or
vm bucket exists.** *Positive control for the corpus (A7, re-used): `remote_agent` → 58 hits, so
cloud vocabulary IS present; `self-hosted-runner` → 0 hits, correctly absent at 2.1.220.*

**(b) Live response headers.** A 1-token `/v1/messages` call with `next4`'s OAuth bearer returns
exactly 12 rate-limit headers and the same four buckets — identical across
`claude-opus-5` / `claude-haiku-4-5` / `claude-sonnet-4-5`:

```
anthropic-ratelimit-unified-5h-utilization = 0.21      ← matches oauth/usage 21.0
anthropic-ratelimit-unified-7d-utilization = 0.29
anthropic-ratelimit-unified-representative-claim = five_hour
anthropic-ratelimit-unified-overage-status = rejected
anthropic-ratelimit-unified-overage-disabled-reason = org_level_disabled
```

**(c) The oauth/usage endpoint exposes 15 buckets and 12 are null on every account.** Raw dump:
`five_hour`, `seven_day`, `seven_day_oauth_apps`, `seven_day_opus`, `seven_day_sonnet`,
`seven_day_cowork`, `seven_day_omelette`, `tangelo`, `iguana_necktie`, `omelette_promotional`,
`nimbus_quill`, `cinder_cove`, `amber_ladder`, `extra_usage`, `spend`. On all four accounts only
`five_hour`, `seven_day` and `nimbus_quill` (=0.0) are non-null. **`seven_day_cowork` — the one
plausible "cloud" candidate — is null on all four**, including accounts that have fired 49 cloud
sessions.

### 2.3 The money lever is closed — measured on all four accounts

`extra_usage` + `spend` from the same endpoint (clean t0 read, 13:16:51Z):

| account | `extra_usage.is_enabled` | `credits_ever_enabled` | `spend.enabled` | `can_purchase_credits` | `can_toggle` |
|---|---|---|---|---|---|
| next | false | **true** | false | false | false |
| next4 | false | false | false | false | false |
| next3 | false | false | false | false | false |
| next2 | false | **true** | false | false | false |

Corroborated by the live header `overage-disabled-reason = org_level_disabled`, `overage-status = rejected`.
**The operator cannot buy past the quota wall from the usage panel** — `can_toggle: false` everywhere.
`credits_ever_enabled: true` on two accounts says it was once available, which makes this a
*support/plan* question rather than a settings question. **[M]**

### 2.4 Concurrency — the handed-over `maxConcurrent: default(1)` is not about cloud

The schema exists exactly as A3-VERIFY reported, but reading its **sibling** settles what it governs:

```js
UKs = E.object({ id, cron, prompt, directory, enabled, permissionMode,
                 model, runTimeoutMinutes:.max(10080).default(30),
                 maxQueued:.int().positive().default(1) }).strict()

qKs = E.object({ tasks: E.array(UKs()).default([]) .refine(unique ids),
                 maxConcurrent: E.number().int().positive().default(1) }).strict()
```

Every field is a **local cron task's** field (`cron`, `directory`, `permissionMode`), and the loop
that consumes `maxConcurrent` (identifier `i`) drives the **local Agent SDK**:

```js
… pathToClaudeCodeExecutable:O.cmd, settingSources:["user","project","local"],
  systemPrompt:{type:"preset",preset:"claude_code"} …
while(!t.aborted){ while(v.size<i && c.length>0 && !t.aborted){ … } }
```

⇒ **`maxConcurrent` caps how many LOCAL scheduled tasks run at once (default 1). It says nothing
about cloud sessions.** Do not price it as a cloud limit. **[M]**

**What the actual cloud concurrency limit is:** no evidence of one.

| probe | result |
|---|---|
| `grep -oE '.{110}(concurrent session\|too many sessions\|session limit\|maximum number of.{0,30}session\|concurrent_session).{110}'` over the 412,384-line strings corpus | only `BPt={five_hour:"session limit", …}` — a *quota* label, not a slot cap **[M]** |
| A7's Agent-tool control flow | `q==="remote"` **skips** the local `P()` concurrency check entirely **[M]** |
| observed max overlapping declared cloud sessions, from `cc-cloud list --json` windows | **15 fleet-wide**; per account next2 = 6, next3 = 4, next4 = 4, next = 3 **[M]** |
| any create refusal in 168 fires | none recorded **[M]** |

### 2.5 Zero local footprint — positive-controlled

`pgrep -f <session-id>` returned 4 — and **all four were the measurement's own shell**, the
documented `pgrep -f matches agent briefs` trap. Re-run against a `ps -eo pid,args` snapshot with the
needle in a *file* (so it is not in any argv):

```
grep -c -f needle.txt psnap.txt   → 1     ← and that 1 is my own /bin/zsh -c measuring shell
grep -c -f needle2.txt psnap.txt  → 5     ← POSITIVE CONTROL ("claude.exe"), method can match
git worktree list | grep -c 20260819T132512Z → 0
```

⇒ **0 claude processes, 0 panes, 0 worktrees for the cloud session.** Its whole local cost was a
`python3` POST that exited in 7 s.

### 2.6 The historical fleet — what cloud has actually delivered

`bin/cc-cloud list --json` (168 declarations) joined against `git ls-tree -r --name-only origin/main`:

| day | fired | pushed a ref | all declared paths on origin/main |
|---|---|---|---|
| 08-08 | 11 | 9 | 2 |
| 08-09 | 8 | 0 | 0 |
| 08-10 | 4 | 1 | 0 |
| 08-11 | 9 | 8 | 3 |
| 08-12 | 15 | 12 | 9 |
| 08-13 | 17 | 13 | 8 |
| 08-14 | 18 | 13 | 11 |
| 08-15 | 18 | 17 | 12 |
| 08-16 | 12 | 8 | 4 |
| 08-17 | 19 | 10 | 3 |
| 08-18 | 20 | 6 | 0 |
| 08-19 | 17 | 4 | 0 |
| **TOTAL** | **168** | **101 (60%)** | **52 (31%)** |

⚠️ **08-17…08-19 are lag, not failure.** `paths=` is filled *post hoc* by `cc-cloud fill-paths`, so
recent rows are structurally under-counted. The honest cohort is the mature window **08-11…08-16**:
**89 fired · 71 pushed (80%) · 47 landed (53%) ⇒ 7.8 landed items/day, off-box, at zero local slots.**

Live board today (`cc-cloud --table`, non-retired only, n=84): 65 NOT-STARTED · 7 STALLED ·
7 ABANDONED · 2 LANDED · 2 ALIVE · 1 BOOTING.

### 2.7 The lifecycle, step by step — what is scriptable TODAY

| step | the exact command | scriptable? |
|---|---|---|
| create + brief | `cc-offload up --task <file> -n N --account auto` → `scripts/cloud-create-api.py` → `POST /v1/sessions` | **YES** — no PTY, 7 s **[M]** |
| monitor | `cc-offload ls` · `cc-offload watch [--pane]` · `cc-cloud show <id>` | **YES [M]** |
| read its output | `GET /v1/code/sessions/<id>` → `post_turn_summary.status_detail` + `external_metadata.usage` | **YES [M]** |
| steer it | `cc-notify --cloud <id> "<msg>"` — routes to the owning account; `{ok:true}` = **queued, never read** | **YES**, with rc 7 = receipt UNKNOWABLE off-box **[Q runbook]** |
| get its commits | `git ls-remote --heads origin <branch>` · `cc-offload land [--all]` | **YES [M]** |
| know it finished | `cc-cloud` state fn (C3 LANDED, checked before C4 STALLED) · notify-back wake · `cc-custody` | **YES [M]** |
| **kill it** | **none.** `cc-cloud retire` retires the *declaration*, not the VM. Escalation is `cc-offload open <id>` → web UI | **NO [M]** |

**What `handoff-fire.sh` solves, and why it turned out not to matter.** A7 correctly found that
2.1.220's `Shp()` refuses `--cloud` without a TTY, and `handoff-fire.sh` supplies one in a pane. But
the API path does not invoke `claude --cloud` at all, so the TTY rule is *bypassed, not satisfied*.
The real blockers `scripts/cloud-create-api.py` was built to fix are documented in its own header and
are worse than the TTY: **(a)** `claude --cloud` always uploads a BUNDLE ⇒ `config.sources: []` ⇒ the
VM's git proxy refuses to inject a push credential (`403 … not in this session's authorized repository
set`), so the work completes and is stranded; **(b)** the legacy `/v1/code/sessions` create sends
`bridge:{}` ⇒ `environment_kind: bridge` ⇒ the "cloud" session's CPU **is this box**. A real VM is a
different endpoint (`/v1/sessions`, `environment_id` top-level, `anthropic-beta: ccr-byoc-2025-07-29`),
which is what the script posts. My probe confirms both axes land correctly:
`environment_kind: anthropic_cloud` **and** `sources: 1`. **[M]**

**A `--cloud` lane still needs exactly one thing our rails do not have: a kill.**

### 2.8 The deferred control-plane tools

| tool | locus | evidence |
|---|---|---|
| **`RemoteTrigger`** | **CLOUD — a real programmatic surface for a local session** | Schema **[Q]**: `list`/`get`/`create`/`update`/`run` against `/v1/code/triggers`; `run` = `POST /{id}/run`. Live `HTTP 200` this session **[M]**. The one routine returned carries `job_config.ccr.environment_id`, `session_context:{allowed_tools, model}`, `mcp_connections[]`, `cron_expression` — i.e. prompt + model + tools + environment are all settable over HTTP. *(Payload redacted: it contains the operator's personal financial details. Structure only.)* |
| **`CronCreate`/`CronList`/`CronDelete`** | **LOCAL — not an off-box lever** | Schema **[Q]**: *"Jobs live only in this Claude session — nothing is written to disk, and the job is gone when Claude exits"*; `durable` — *"Has no effect"*; *"Jobs only fire while the REPL is idle"*; recurring auto-expire at 7 days. **It holds a local session open, so it CONSUMES the ceiling.** |

⇒ `RemoteTrigger create` + `run` is a second, fully headless way to fire cloud compute — useful where
a job is recurring or event-triggered rather than one-shot. It is **not** a way around quota.

### 2.9 The unpushed-work trap — what the workflow actually is

The VM clones the **remote**, so local-only work is invisible. But the branch the VM *writes* need not
pre-exist: `cloud-create-api.py` sends `sources:[{type:"git_repository", url, revision}]` (revision
default `main`) plus `outcomes:[{git_info:{repo, branches:[B]}}]`, and `outcomes` is what authorizes
the proxy to push to exactly branch `B`.

**Measured on this probe.** `claude/fire-20260819T132512Z-24086-1` did not exist anywhere before
13:25:12Z (the name is minted by `cc-offload` at fire time). Afterwards:

```
git ls-remote --heads origin claude/fire-20260819T132512Z-24086-1
→ 64be0bc3d5b12d50e89b0229a78b653e722f4ac5
git log --format="%H %an %ae %ad %s" -2 64be0bc3
→ 64be0bc3 Claude noreply@anthropic.com Wed Aug 19 13:26:47 2026 +0000 test(b2): rangefmt probe
→ f5f4e99f7 Chris Ren …                                    (a commit on origin/main)
```

⇒ **The rule is: whatever the VM must READ has to be on the remote; whatever it WRITES does not.**
`cc-cloud preflight --branch B` enforces the read half by refusing an unpushed base.

🚨 **`CCR_FORCE_BUNDLE=1` is the wrong remedy and should not be reached for.** Bundling is precisely
the path that yields `sources: []`, and `sources: []` is the 403 that strands the work inside a
container that is later reclaimed. Push the base; never bundle. **[M, from cloud-create-api.py's own
measured header + this probe's `sources: 1`]**

---

## 3 · What I could NOT measure, and why

1. **A per-account cloud concurrency CAP.** I never provoked a refusal — 168 historical fires
   produced none, and I fired one, not a burst. *Absence of a cap string in the binary is not proof
   of absence server-side*; the cap could be enforced only at `POST /v1/sessions`. Settling it costs
   one burst of ~8 simultaneous creates on one account and reading for a 429/4xx.
2. **A controlled A/B on the quota question.** n=1 fire, and `next4` had 3 live local sessions
   throughout. The 8 m 38 s pre-flatline, the 3 m 30 s post-flatline, the zero-drift control account
   and the 1.25 pt/session calibration from the 2026-08-11 A/B all point the same way, but **this is
   a strong single observation, not a controlled experiment.** No account on this box is ever idle,
   which is what forecloses the clean version.
3. **Sub-point meter resolution.** *Both* instruments quantise to one percentage point — the
   oauth/usage `utilization` returns whole floats (21.0, 27.0) and the response header returns two
   decimals of a fraction (0.21), which is the same grain. **A cloud job under ~0.8 M tokens is
   invisible to either.** *The arithmetic that would settle it decisively:* fire **k = 5** sessions
   back-to-back on one account; at ~1 pt per 0.8 M tokens the predicted delta is **~5 points = 5×
   the instrument's resolution**, which no plausible ambient drift on a quiet account reproduces.
4. **Whether a cloud session bills the model-scoped buckets** (`seven_day_opus` / `seven_day_sonnet`
   / `seven_day_overage_included`). All are null on all four accounts, and my session reported
   `last_served_model: null`, so the model-tier axis is untested.
5. **`tengu_neapolitan`**, the server flag gating in-session `isolation:"remote"`. Unchanged from A7:
   not cached in any local file, default false. Unrelated to `--cloud`, which is proven live.
6. **Why 47% of mature-cohort cloud sessions do not land.** I measured the rate, not the causes. The
   live board's 65 NOT-STARTED is a mixture of genuine non-starts, wrong-branch declarations, and
   items that were no-ops — I did not classify them.
7. **`claude-accounts --readout` could not be reproduced verbatim as the brief asked.** It exits 2 and
   floods stdout: its `--json`/`--readout` paths call `probe_provider()`, which execs third-party
   agent CLIs whose stdout leaks into the payload (observed: an ImageMagick `import` usage block and a
   crash trace from a stale pnpm-global `@anthropic-ai/claude-code@2.0.5`). That is a **real defect in
   a rendering tool this repo relies on**, and it is why every meter figure above comes from the
   underlying endpoint instead. Not filed — out of this axis's scope, but it should be.

---

## 4 · The decision this axis changes

**Cloud is a BURST lever, not a SUSTAINED one, and the wave should stop treating it as the answer to
"more than 15".**

- **Sustained.** A cloud working unit consumes the same 5-hour/weekly meter as a local one at the same
  rate. The settled ceiling of **9.4 sustained working units fleet-wide** is therefore *unchanged by
  cloud*. Reaching **15 sustained** needs 15 ÷ (9.4/4) ≈ **6.4 Max accounts — i.e. +3 accounts** — or
  overage, which is `org_level_disabled` and `can_toggle: false` on all four. **Those are the only two
  levers that move the sustained number, and neither is a cloud decision.**
- **Burst.** Here cloud is the best lever in the wave and it is already built. No slot cap, no pane, no
  worktree, no load contribution; 15 concurrent declared sessions already observed; 7 s to fire. Where
  the settled load gate (`CC_FIRE_MAX_LOAD_PER_CORE`, ~4–8 concurrent mid-turn) is what actually stops
  a wave today, **routing that wave to cloud converts the binding constraint from the box to the
  quota** — worth roughly **+1.4 to +5.4 sustained working units**, purely by letting the fleet reach a
  ceiling it currently cannot touch.
- **Do not spend effort on the fire path.** It is solved: one command, headless, 7 s, real VM, repo
  attached, branch pushed. **Spend it on the 47%.** At the mature-cohort rate the cloud lane already
  produces **7.8 landed items/day**; lifting the land rate from 53% to 80% is worth **+4 items/day**
  and costs no quota at all — strictly more capacity per token than any new fire.
- **Build the one missing verb: a kill.** Every other lifecycle step is scriptable; there is no way to
  stop a running cloud VM from a local session, so a wedged session burns quota until its own timeout.
  On a quota-bound fleet, an un-killable runaway is a *capacity* bug.

**The one command that fires a cloud session from a local session:**

`cc-offload up --task /tmp/brief.txt -n 1 --account auto`

---

## 5 · Durable evidence

- Cloud session `session_01CqQ7QRZPRtcBdXm9dHCxSd` (next4, `anthropic_cloud`, `sources: 1`), declaration
  **retired** and custody **abandoned** after measurement (`cc-custody` rows 13:25:15Z open →
  13:32:00Z abandon).
- Throwaway branch left on origin as the evidence for §2.9: `claude/fire-20260819T132512Z-24086-1`
  @ `64be0bc3` (3 files under `tools/b2-quota-probe/`, never landed, never merged).
- Scratchpad instruments (not landed): `meter.py` (zero-cost oauth/usage reader), `hdr.py` (the
  binary's own `quota_check`-shaped header probe), `sess.py` (control-plane session/usage reader),
  `meter-series.tsv` (the 4-account sample series above).
