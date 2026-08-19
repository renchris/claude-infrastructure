---
axis: B2-VERIFY — adversarial verification of B2 (cloud economics)
subject: docs/research/breaking-the-ceiling-2026-08-19/B2-cloud-economics.md
status: measured, independent re-derivation
date: 2026-08-19
verifier_window: 13:36Z – 14:10Z
binary: 2.1.220 (~/.claude-220/node_modules/@anthropic-ai/claude-code/bin/claude.exe)
---

# B2-VERIFY — the conclusion survives; the measurement under it does not

Labels: **[M]** measured here · **[R]** re-derived independently and agrees · **[Q]** quoted.

---

## 1 · Verdict (≤5 lines)

1. **B2's decisive claim is UNPROVEN and its calibration is REFUTED.** A meter point costs
   **4.9–10.6 M raw tokens ($4.06–$7.29 cost-weighted)** — measured on local burn across all four
   accounts. B2's "~1 point per ~0.8 M tokens" is **6–13× too cheap**, so the +1 step it attributed
   to one 810 K-token cloud session is **5–13× larger than that session could possibly have caused.**
2. **My own k=4 burst (1,104,268 tokens, $2.23) moved next4 by exactly ZERO points over 24 min** —
   which is *also* not a refutation: at the true rate it predicts 0.1–0.3 pt, below resolution.
   **Neither experiment can see a single cloud session. The question is open, not settled either way.**
3. **B2's cited independent corroboration disclaims itself.** `cloud-local-cost-ab-2026-08-11.md`
   §5.6 states verbatim: *"The published figure is 1-point granular, so **it cannot attribute
   consumption per arm**."* B2 read a 1.25 pt/session calibration out of a document that refuses it.
4. **Everything structural in B2 CONFIRMS, some of it strengthened:** `maxConcurrent` is the local
   cron runner (re-derived from the binary, stronger evidence than B2's) · no cloud concurrency cap
   (**4 simultaneous creates on ONE account, 21 s, zero refusals**) · no kill verb exists anywhere ·
   the VM creates-and-pushes a branch that did not pre-exist (**n=4**, not n=1).
5. **The outcome funnel is arithmetically exact but semantically hollow.** 168 fired / 101 pushed
   re-derive to the row — but "52 landed by content" is a **path-EXISTENCE** test, and for **42 of
   the 52 every declared path already existed on origin/main before the session was declared.**

---

## 2 · Claim-by-claim

| # | B2's claim | Verdict |
|---|---|---|
| 1a | Cloud bills the SAME 5-hour meter | **UNPROVEN** — §3.1 |
| 1b | "~1 pt per ~0.8 M tokens, venue-independent" | **REFUTED** — §3.2 |
| 1c | 2026-08-11 A/B corroborates at 1.25 pt/session | **REFUTED** — §3.3 |
| 2 | It fired a real cloud job (not doc-only) | **CONFIRMED** + re-fired ×4 — §3.4 |
| 3 | No cloud bucket exists in headers/oauth-usage | **CONFIRMED as a fact; does NOT support the conclusion** — §3.5 |
| 4 | `maxConcurrent: default(1)` is the LOCAL cron runner | **CONFIRMED**, independently re-derived — §3.6 |
| 5 | No per-account cloud concurrency cap | **CONFIRMED, strengthened** — §3.7 |
| 6 | Zero local footprint | **CONFIRMED** — §3.7 |
| 7 | Fire is solved: one command, headless, ~7 s | **CONFIRMED with a material caveat on MONITORING** — §3.8 |
| 8 | 168 → 101 pushed → 52 landed → 7.8 items/day | **funnel CONFIRMED · landedness UNPROVEN** — §3.9 |
| 9 | VM writes a branch that need not pre-exist; never bundle | **CONFIRMED, n=4** — §3.4 |
| 10 | RemoteTrigger cloud / Cron local | **NOT RE-TESTED** — §4 |
| 11 | There is no way to kill a running cloud VM | **CONFIRMED** — §3.10 |
| 13 | `claude-accounts --readout` exits 2 and corrupts stdout | **NOT REPRODUCIBLE** — §3.11 |

---

## 3 · Numbers, with the command behind each

### 3.1 The meter claim — re-derived, and the attribution fails

I built an independent zero-token reader (`meter.py`: `GET api/oauth/usage` per account with each
account's keychain OAuth token, `sha256(NFC(config_dir))[:8]` service derivation, `keychain_account`
read from `accounts.json`). It agrees with B2's instrument at t+9 min on all four accounts. **[M]**

**Extending B2's own observation.** B2 sampled next4 to 13:29:03. I continued the same account:

| time (UTC) | next4 `five_hour` | event |
|---|---|---|
| 13:16:33 – 13:25:11 | 21.0 (6 samples) | B2's pre-flatline |
| 13:25:12 | — | **B2 fires 1 cloud session (810,556 tok)** |
| 13:25:58 – 13:29:03 | 22.0 | B2's step, and its 3m30s post-flatline |
| 13:38:23 → 13:53:49 | **22.0** (6 samples, mine) | still flat |
| 13:50:22 – 13:50:43 | — | **I fire 4 cloud sessions** |
| 13:57:49 → 14:12:06 (8 samples) | **22.0** | **no movement at all, 21.5 min after the 4 jobs finished** |

The 4 sessions all reached `status_bucket: review_ready`, `worker_status: idle`, and consumed
**1,104,268 tokens** combined (`cloud-create-api.py` `get_session` → `external_metadata.usage`):
276,559 + 275,960 + 275,877 + 275,872. `seven_day` also unchanged (29.0 → 29.0), and every other
bucket null or 0.0. **[M]**

**Why this is NOT a refutation, and why B2's is not a proof — both are the same defect.** §3.2 gives
the true price of a point (next4's own window: 7.08 M raw / $5.20; next2's short-window
replication: 10.14 M raw / $6.71). At that price **my 4-session burst predicts 0.11–0.16 pt raw,
0.33–0.43 pt cost-weighted**, and **B2's single session predicts 0.08–0.11 pt raw, 0.15–0.19 pt
cost-weighted**. Both are far below the instrument's 1-point grain. **A single cloud session cannot move this meter by a whole point, so a
whole-point step observed next to one is not evidence about the session.** B2 fired, saw a
quantised counter cross an integer 46 s later, and read the whole step as the session's cost — with
three live local sessions on that account, which B2's own §3.2 acknowledges.

### 3.2 The calibration — REFUTED, measured four ways

`utilization` at time *T* = consumption since the window start (= `resets_at` − 5 h). So local burn
summed from each account's own transcripts over its own live window, against its own meter, gives
the price of a point **with no cloud involved at all**. Dedup on `message.id` (one API response is
written per content block — summing lines inflates 2–3×).

| account | transcript root | window start | responses | raw tokens | cost-wt | util | **raw/point** | **$/point** |
|---|---|---|---|---|---|---|---|---|
| next | `~/.claude-next/projects` | 09:29:59 | 1,411 | 186,849,580 | $154.35 | 38.0 | 4,917,094 | 4.06 |
| next2 | `~/.claude-secondary/projects` | 10:50:00 | 1,862 | 323,940,946 | $243.44 | 43.0 | 7,533,510 | 5.66 |
| next3 | `~/.claude-tertiary/projects` | 08:59:59 | 1,137 | 285,162,897 | $196.92 | 27.0 | 10,561,589 | 7.29 |
| next4 | `~/.claude-quaternary/projects` | 11:20:00 | 1,007 | 155,763,624 | $114.49 | 22.0 | 7,080,165 | 5.20 |

Cost weights: input $5/M · cache-write $6.25/M · cache-read $0.50/M · output $25/M (Opus 5).

**A short-window replication, independent of the window-start assumption:** next2 read 39.0 at
13:38:23 and 43.0 at 13:53:56 (+4.0 pt in 15.5 min). Its local burn over exactly that interval was
**40,574,643 raw tokens / $26.82** ⇒ **10.14 M raw ($6.71) per point** — inside the table's band.
Even the most conservative quantisation reading (a "+4" step could be a true delta as small as 3.0)
gives ≥ 8.5 M raw/point, still **10× B2's figure**. **[M]**

⚠️ **The inter-account spread is a PRICING artifact, not a cloud signal — and this kills the obvious
follow-up test.** I checked whether accounts that fired more cloud sessions show an inflated meter
(a lower $/point): next fired 9 in its window and is cheapest at $4.06; next2/next3 fired 0 and are
$5.66/$7.29. That ordering looks like cloud — until you read the `Fable used` column of
`claude-accounts --readout`: next 22%, next4 15%, next2 0%, next3 0%. **The ordering is monotone in
Fable share, not in cloud fires**, and Fable is $10/$50 — 2× the Opus rates I priced everything at,
so a Fable-heavy account's true cost is understated and its computed $/point falls. The correlation
is fully explained without cloud. **This test is uninformative, and I am recording it as refuted
rather than as weak support.** **[M]**

### 3.3 B2's independent corroboration disclaims the inference [M]

`docs/research/cloud-local-cost-ab-2026-08-11.md` §5.6, verbatim:

> **Account throttle state was not a factor** but is not controlled either: next3 sat at 1% weekly
> before and 2% after, with the 5-hour window moving 3%→8% across all four sessions. The published
> figure is 1-point granular, so **it cannot attribute consumption per arm** — the per-session token
> counts above are the only per-arm quota evidence.

B2 §2.1 converts that same 3%→8% into "**1.25 pt/session**" and calls it a calibration that
"consistent[ly]" corroborates its own probe. The source says the opposite in the same sentence. And
at §3.2's price, those four ~1 M-token sessions total ≈ 0.4–0.8 pt — so ~90% of that 5-point move
was ambient local burn on next3.

### 3.4 It really fired — and I re-fired it, ×4 [M]

```
cc-offload up --task <brief> -n 4 --account next4        # 4 creates in 21 s
python3 scripts/cloud-create-api.py --account next4 --verify <id>
  → {"environment_kind":"anthropic_cloud","sources":1,"accepted":true,
     "status_bucket":"review_ready","worker_status":"idle"}   × 4
git ls-remote --heads origin 'claude/fire-20260819T1350*'
  → b898898e …-48051-1 · fee58fc3 …-2 · 6cd7cf92 …-3 · 9998dacf …-4
```

None of the four branches existed before 13:50:22Z. All four were created, committed and pushed by
the VMs, finishing 13:56:33–13:56:42Z (≈ 6 min each, not B2's 110 s). **B2 §2.9's rule — whatever
the VM READS must be on the remote, whatever it WRITES need not — is confirmed at n=4.**

### 3.5 The structural argument is true and does not carry the conclusion [M]

I re-dumped next4's full `oauth/usage` payload after the burst. Non-null: `five_hour`, `seven_day`,
`nimbus_quill` (0.0), `extra_usage`, `limits[]`, `spend`. Null: `seven_day_oauth_apps`,
`seven_day_opus`, `seven_day_sonnet`, **`seven_day_cowork`**, `seven_day_omelette`, `tangelo`,
`iguana_necktie`, `omelette_promotional`, `cinder_cove`, `amber_ladder`. Confirms B2's §2.2(c).

**But "no cloud bucket is visible to this endpoint" is not "cloud lands in `five_hour`."** It is a
statement about what the local CLI can *see*, and it is equally consistent with cloud being metered
somewhere this endpoint does not expose. B2 presents it as a *corroborant* of the same-meter
verdict; it is neutral between the two hypotheses. The money lever being closed
(`extra_usage.is_enabled=false`, `can_toggle=false`, `can_purchase_credits=false`, `spend.enabled=false`)
re-confirms on next4 verbatim. **[M]**

### 3.6 `maxConcurrent` — CONFIRMED, re-derived, with a stronger citation [M]

`LC_ALL=C strings -a -n 6 claude.exe > strings.txt` (412,384 lines), then extracting the **consumer**
`Zmp` rather than the schema:

```js
Zmp=async(e,t,r,n)=>{let{tasks:o,maxConcurrent:i}=qKs().parse(e); …
  r(`scheduled worker started tasks=${o.length} maxConcurrent=${i}`); …
  let H=l({prompt:A.prompt,options:{cwd:A.directory,permissionMode:A.permissionMode,…
      pathToClaudeCodeExecutable:O.cmd, executableArgs:O.prefixArgs, abortController:D, …}});
  … while(!t.aborted){ while(v.size<i && c.length>0 && !t.aborted){ … } } }
```

`pathToClaudeCodeExecutable` + `executableArgs` prove it **spawns the LOCAL binary**; the `v.size<i`
loop gates how many of those local spawns run at once. `PT()` — the refusal inside the loop — is
`MQr().error`, a *launcher-validity* check (`launcher \`…\` was deleted or is not executable`), not a
concurrency or quota gate. **A3-VERIFY's handover is a string match, not a semantic; B2's refutation
of it stands.**

### 3.7 No concurrency cap, no local footprint [M]

Four `POST /v1/sessions` creates against **one** account inside 21 s: all four accepted, all four
ran to completion, **zero refusals, zero 429s on the create path**. Grep over the strings corpus for
`concurrent session|too many sessions|session limit|concurrent_session` yields only
`BPt={five_hour:"session limit",…}` — a quota label. Local cost of the fire was one `python3` POST
per session; no panes, no worktrees, no `claude.exe` appeared.

### 3.8 The lifecycle — fire is solved, MONITORING has a silent-empty failure [M]

| step | command | result |
|---|---|---|
| create ×4 | `cc-offload up --task <f> -n 4 --account next4` | **21 s**, 4 real VMs, repo attached ✓ |
| read state | `cloud-create-api.py --account next4 --verify <id>` | ✓ instant |
| **monitor** | `cc-offload ls` | **74 s wall** (`5.82 s user, 7.03 s system, 17% cpu, 1:13.95 total`) |
| monitor | `cc-cloud --table` | ✓ ~60–80 s, 84 rows |
| kill | — | **does not exist** (§3.10) |

🚨 **`timeout 60 cc-offload ls` prints NOTHING and the pipeline reports rc 0.** I hit this on my
first attempt and briefly concluded the monitor was broken. Any operator or script wrapping the
board in a sub-74-second timeout gets **an empty board that reads as "no cloud sessions"** — an
absence-is-evidence inversion in the exact tool the operator says is their pain point. B2 lists
monitoring as "**YES [M]**" with no latency figure. The claim is true; the number is the finding.

**What the board actually says right now** (`cc-offload ls` tail): **`0 working · 2 landed · 75 need
you · 7 UNKNOWN`**; `cc-cloud --table` tallies **66 NOT-STARTED · 9 STALLED · 7 ABANDONED · 2
LANDED · 0 ALIVE · 0 BOOTING**. B2 recorded "2 ALIVE · 1 BOOTING" ~30 min earlier; those are now
gone. **The lane B2 calls "the best lever in the wave and already built" is, at this instant,
producing nothing.**

### 3.9 The outcome funnel — exact on the first two stages, hollow on the third [M/R]

`cc-cloud list --json` (JSONL, 168 rows) joined against `git ls-tree -r --name-only origin/main`
(2,053 paths). `paths` is **comma**-delimited (`cc-cloud`'s `landed()` splits on `,`).

| day | fired | pushed (`last_sha`≠"") | all declared paths on main |
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
| **TOTAL** | **168** | **101** | **52** |

Row-for-row identical to B2. Mature cohort 08-11…08-16 = **89 / 71 / 47**. **[R]**

**But the third column does not mean landed.** For each declaration I asked whether any declared
path was *absent from origin/main at that declaration's own timestamp* — i.e. whether the branch
genuinely added anything:

- **42 of 52** have **every** declared path already present on main before the session started.
  `git ls-tree origin/main -- bin/cc-backlog` returns non-empty whether or not that session's
  content ever landed. **The test passes vacuously.**
- **10 of 52** declared at least one genuinely new path.
- A patch-level re-check is impossible retrospectively: **47 of 52 branch refs no longer resolve**,
  so `git cherry` / patch-id cannot adjudicate. (2 have `last_sha` as an ancestor of `origin/main`;
  that is a weak lower bound — a rebased land rewrites the object.)

So **"31% landed" and "7.8 landed items/day" are UNPROVEN.** The true figure lies somewhere in
[10, 52] over 12 days. This is not B2 inventing a metric — it is `cc-cloud`'s own `landed()`, whose
comment cites `land-verify.sh`. That rule is correct for a session verifying **its own** just-written
diff; applied to another agent's branch 12 days later, existence ≠ landedness.

*Method note against myself: my first pass split `paths` on whitespace and reported 18. That was my
instrument, not the data. A null from a blind instrument is not absence — I corrected it by reading
`cc-cloud`'s own splitter before trusting the number.*

### 3.10 The missing kill — CONFIRMED [M]

Every `/v1/(code/)?sessions/...` path in the binary: `""`, `${e}`, `/archive`, `/bridge`,
`/client/presence`, `/events`, `/events?limit=…`, `/mark_read`, `/teleport-events`, `/events/stream`.
**No `stop`, `abort`, `cancel` or `terminate`.** Positive control: the grep returns 20 session
endpoints, so the corpus is reachable and the negative is real. No kill verb in `cc-cloud`
(`declare fill-paths is-offbox list poll preflight retire show`) or `cc-offload`
(`gc land ls open say setup up watch`). `/archive` is the nearest neighbour and archives a record,
not a VM. **B2's item 11 stands unmodified.**

### 3.11 The incidental defect — NOT REPRODUCIBLE [M]

```
claude-accounts --readout   → rc 0, 2,873 bytes, clean markdown table, no stderr
```

B2 §3.7 reports exit 2 with an ImageMagick `import` usage block and a `claude-code@2.0.5` crash
trace leaking into stdout. It did not reproduce here, ~35 min later, same binary, same config. It
may be a genuine intermittent (the `probe_provider()` path B2 names does exec third-party CLIs), but
**as filed it is an unreproduced single observation and should not be filed as a standing defect
without a second sighting.** The `--readout` table it produced is what supplied the Fable column
that overturned §3.2's correlation test — so the tool was not merely working, it was load-bearing.

---

## 4 · What I could NOT measure, and why

1. **Whether cloud bills the 5-hour meter at all.** Both experiments to date (B2's n=1, my n=4) are
   ~4–12× below the instrument's resolution. **A valid test needs ≈ 3 points of clean signal ≈ $17–20
   of cloud consumption on one account** — roughly 18–20 sessions of my brief's size, or 4–5 heavy
   multi-turn sessions. Ideally on an account with zero live local sessions, which does not currently
   exist on this box.
2. **The zero-cost version of that test, which is the right one and I ran out of budget for it.**
   Regress observed 5-hour utilization against *transcript-derived local burn* across many
   account-windows where cloud fire counts are known, **controlling for Fable share** (§3.2 shows an
   uncontrolled version is dominated by model mix). All inputs are already on disk; it costs nothing
   and it would settle the question with real statistical power.
3. **A cloud concurrency cap above 4.** I provoked no refusal at k=4 on one account; 8–10 would be
   the next rung.
4. **The true landed count in [10, 52].** 47 of 52 branch refs are gone, so no patch-level oracle is
   reachable retrospectively. Fixing this forward is cheap: have `fill-paths` also record the
   branch's **added** paths separately, so landedness is asserted against files the branch created.
5. **`RemoteTrigger` / `CronCreate` (B2 item 10).** I did not call `/v1/code/triggers`; B2's evidence
   is schema-level plus one live 200 and I have no reason to doubt it, but I did not re-verify it.
6. **Sub-1-point meter resolution.** Confirmed as B2 states: `oauth/usage` returns whole floats and
   the response header returns two decimals of a fraction — the same grain. There is no finer field
   in the payload (I dumped it in full).
7. **Instrument constraint B2 did not record:** `api/oauth/usage` **429s under ~20 s polling**. My
   first sampler took 4 accounts × 3 calls in 20 s and every one returned
   `{"type":"rate_limit_error"}`. Any future sampler needs ≥ 45 s spacing and a backoff ladder, or it
   will manufacture gaps that read as outages.

---

## 5 · The decision this verification changes

**B2's *conclusion* is not overturned — its *evidentiary status* is, and the difference decides
where the wave spends its next hour.**

- **The capacity arithmetic is untouched.** B2 §4's "+1.4 to +5.4 sustained units, cloud converts the
  binding constraint from the box to the quota" rests on B4's settled 9.4 sustained figure and on the
  load gate, **not** on the 0.8 M-tokens-per-point number. Refuting the calibration does not move it.
- **But "cloud adds ZERO sustained throughput" is now an assumption, not a measurement**, and it is
  the single highest-leverage open question in the wave. If cloud *does* bill the same meter, B2's
  answer is right and 15 sustained needs +3 accounts. If it bills less — or elsewhere — **cloud
  becomes a sustained lever and the answer to "more than 15" changes completely.** Nothing measured
  so far distinguishes these.
- **Settle it the free way first (§4.2), before spending $20 on a burst.** The transcript ledger is a
  complete local-burn oracle and the meter is a complete total-burn oracle; the difference between
  them *is* the cloud contribution, and both are already on disk.
- **Do not price the cloud lane on "7.8 landed items/day."** The funnel's first two stages are solid
  (168 → 101 pushed, 60%); the land rate is measured by a path-existence test that passes vacuously
  in 81% of its positives, and the live board reads **0 working · 75 need you** right now. B2's own
  best recommendation — *spend the effort on the 47%, not on the fire path* — survives this and gets
  stronger, because the denominator is less certain than stated.
- **Two concrete defects to file, both cheap:** `cc-offload ls` takes 74 s and returns **empty at
  rc 0** under a shorter timeout (silent-absence on the operator's stated pain point); and
  `fill-paths` should record branch-**added** paths separately so `landed()` stops passing vacuously.

**The one command a verifier should run before trusting any future meter claim:**

`python3 - <<'PY'` … sum `message.usage` deduped on `message.id` from the account's transcript root
over its 5-hour window, divide by its `utilization` `PY` — *because a whole-point step is never
evidence about a sub-point contribution.*

---

## 6 · Durable evidence

- 4 probe sessions on next4, all `anthropic_cloud` / `sources: 1`, **declarations retired**, custody
  discharged (0 open rows matching): `session_0158MJbVccoMxwWAfghmXbWV` ·
  `session_01Gb1Qnj1hsfH67VopayGTVz` · `session_01QbJa6bUiadqw7RS6u3AGCH` ·
  `session_011VJti1NrYeU9PVBUeAs2Sq`.
- 4 throwaway branches left on origin as §3.4 evidence, never landed:
  `claude/fire-20260819T135022Z-48051-{1..4}` @ `b898898e`, `fee58fc3`, `6cd7cf92`, `9998dacf`
  (one file each under `tools/b2v-probe/`).
- Scratchpad instruments (not landed): `meter.py` (independent zero-token 4-account reader),
  `one.py` / `watch4.py` (focused post-burst watchers), `series.tsv` (baseline series),
  `watch4.log`, `decls.json` (168 declarations), `strings.txt` (binary corpus).
- **Nothing live was mutated:** no config file written, no process killed, no pane closed, no session
  torn down. The only writes were 4 cloud creates (retired) and their 4 remote branches.
