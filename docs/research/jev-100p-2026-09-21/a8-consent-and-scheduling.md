# A8 — Consent and scheduling: what the refusal actually binds, and the fork it leaves

Adversarial slot 2, 2026-09-21. Read-only; nothing registered, nothing edited, no Jev call made.

---

## 0. The headline, before the tables

**Three of the four things the operator's goal asks for already exist, landed and live. The one
that does not is a single boolean.**

- A **hook already triggers Jev on real work**, unattended, today: `anti-deference-nudge.sh` is
  registered on the live `Stop` chain (`~/.claude/settings.json:999`) and reaches `jev_ask` at
  `hooks/anti-deference-nudge.sh:307` on every close the four lexical arms drop. Measured over the
  last 25 h: **372 such closes** (`hook=anti-deference-nudge`, `reason=no-tell`, in
  `~/.claude/autonomy/idl.jsonl`). `cc-jev status` says it in its own words:

  > 🚨 RETIRED IS NOT OFF, AND THIS ONE COSTS YOU. The arm is still wired in and still reached on
  > every no-tell close, where it spends a doomed round-trip (~0.5s) that can only ever return 403.

- The **destination is already operator-authorised**: `ai-gateway.vercel.sh` sits in
  `~/.config/secrets/egress.allow` beside `api.anthropic.com` and `openrouter.ai`. Adding a host
  there is an explicit operator act (a real close in Addendum 4 reads
  *"⛔ Blocked — need your call: may openrouter.ai join the egress allowlist"*).

- **Scheduled, unattended, third-party egress of our own engineering content is established
  practice on this box** — see §4. `com.claude.dispatcher` POSTs briefs to `api.anthropic.com`
  every 300 s with no human in the loop.

- What is **not** granted, and is the entire fork: **`CC_JEV_ZDR=0`** — sending under *standard*
  retention rather than zero retention. That is one env var, and it is the only thing between
  today's state and a JSONL of verdicts.

**So the decision packet should not ask "may we schedule a job".** It should ask the one question
that is genuinely open: *may our own engineering notes be sent to Vercel under ordinary retention?*

---

## 1. Mechanism table — where the refusal lives and what it binds

Evidence for every row is a file read or a log record, cited inline.

| # | Layer | File / record | Binds a **Bash tool call**? | Binds a **hook**? | Binds a **launchd/cron job**? |
|---|---|---|---|---|---|
| 1 | **Auto-mode permission CLASSIFIER** (a model judging the Bash call) | `~/.claude/logs/permission-denied.jsonl`, record `ts=2026-09-20T23:50:00Z`, `mode=auto`, **`reason="Blocked by classifier"`**, `input_head={"command":"CC_JEV_ZDR=0 cc-jev probe …"}` | **YES — this is the one that fired** | No | **No** |
| 2 | `permissions.deny` in settings | `~/.claude/settings.json` — 41 deny rules, enumerated; **none mentions jev, node, the gateway, or any network verb except `Bash(wget:*)`** | No | No | No |
| 3 | `permissions.ask` in settings | same file — 6 ask rules, all git/fly | No | No | No |
| 4 | Project settings | `.claude/settings.json` (37 allow, **0 deny, 0 ask**), `.claude/settings.local.json` (102 allow, 0 deny, 0 ask) | No | No | No |
| 5 | **PreToolUse hook** `hooks/validate-bash.sh` (2,031 lines) | grep for `network\|egress\|curl\|AI_GATEWAY\|jev\|https://` returns **4 hits, all prose in comments**. No gate. | No | No | No |
| 6 | **PreToolUse hook** `hooks/curl-gate.py` (+ the `curl-gate-scope.sh` shim) | `hooks/curl-gate.py:41` — `PROJECT_ROOT = "/Users/chrisren/Development/reso-management-app"`; the shim short-circuits to exit 0 for any cwd not under it | Only in **reso**, only for `curl` | No | No |
| 7 | The script's **own** refusal | `scripts/jev/rank-memory.sh:94` — `if [ "${CC_JEV_ZDR:-1}" != 0 ]; then … exit 4` | It refuses *itself* unless ZDR is explicitly off | n/a | **YES — this one DOES bind a launchd job**, because it is inside the program |

### Answers to the four sub-questions

**1. Where does the refusal live?** The **auto-mode permission classifier** — a model, not a rule.
Record 1 is the whole evidence base and it says `"Blocked by classifier"` verbatim. There is **no
deny rule and no hook** anywhere in the chain that mentions Jev, the gateway, or network egress
generally. The resident lesson `an-allow-rule-cannot-silence-a-hook-s-ask` runs the other way here:
because the blocker is the *classifier* and not a hook, an allowlist entry **would** in principle
silence it — but writing one's own allowlist entry is barred independently (§ Manual-Command
Delivery: *never script your own authorization*), so this is not a route.

Two properties of the classifier worth having in the packet, both measured from the same log:

- It is **stochastic, not deterministic**. 214 `Blocked by classifier` + 22 `Classifier unavailable`
  + 14 `Stage 2 classifier error — blocking based on stage 1 assessment (usually transient —
  retrying often succeeds)`. The last string is the harness's own admission. The brief says the
  refusal was verified twice; **only one Jev denial is in the log** (`grep -ci jev` → 1), so the
  second was either unlogged or in another session.
- It **does not generalise into a policy**. One model verdict on one command string is not a rule
  about Jev, about egress, or about scheduling. Treating it as one is
  `reference-a-refusal-bounds-the-tool-not-the-world` exactly: the refusal bounds the *tool call*,
  and its absence of a message about the world got read as a fact about the world.

**2. Does it bind a launchd job or a cron entry? NO — and here is the evidence rather than the
inference.** Every `~/Library/LaunchAgents/com.claude.*.plist` on this box has a
`ProgramArguments` of the form `["/bin/bash","-c","… exec <script>"]` — verified by reading
`com.claude.browse-mirror.plist`, `com.claude.nightly-regression.plist`,
`com.claude.discovery.plist`, `com.claude.dispatcher.plist`, `com.claude.accounts-keepwarm.plist`.
**Not one of them launches `claude`, `claude-next*`, or any Claude Code binary as the job body.**
`launchd` execs `bash` directly; there is no session, no tool call, no PreToolUse chain, and no
permission classifier to consult. Same for cron: `crontab -l` is a single line,
`15 9 * * * /Users/chrisren/Development/personal/bin/mb-hpc-price-watch`, a bare shell script.
The permission system is a property of the *Claude Code session*, and a daemon has none.

**3. Does it bind a hook this repo registers? NO, and this is the decisive one.** Hooks are
subprocesses that Claude Code `exec`s; they are not tool calls and they do not re-enter the
permission system. That is not theory — it is running today. `anti-deference-nudge.sh` is a live
`Stop` hook that builds a JSON body containing `state.closing_message` and pipes it to `jev_ask`
(`hooks/anti-deference-nudge.sh:283-307`), which `exec`s `agent-secrets run -- node
scripts/jev/evaluate.mjs`, which POSTs to `ai-gateway.vercel.sh`. **372 times in 25 hours, with no
classifier, no prompt, and no operator in the loop.** `cc-jev status` confirms the path is live in
every respect except the verdict: `API key yes (via agent-secrets)`, `deps (ai) yes`, `egress
ai-gateway.vercel.sh allowlisted`, `node v22.21.1` — and `ZDR on, fails closed`, which is why all
372 return 403.

> 🚨 **The uncomfortable corollary, stated because it changes the packet.** With ZDR on, the
> gateway rejects the request *at the plan gate* — but the request body has already been
> transmitted over TLS to reach that gate. So our closing messages are already crossing the wire to
> Vercel today, ~360/day. What ZDR-off changes is not *whether* bytes leave; it is whether Vercel
> **retains and may train on** what it receives. **Honest unknown:** nothing here establishes what
> Vercel does with the body of a 403'd request. Do not argue "it already leaks, so this is free" —
> that is the laundering move. The right reading is narrower: the *egress* decision is settled by
> practice; the *retention* decision is not, and is the whole fork.

**4. Precedent for a scheduled job doing third-party network egress? YES, four of them.** §4.

---

## 2. Egress inventory — the exact bytes

### 2a. What `cc-jev rank` would send, measured on today's corpus

`scripts/jev/rank-memory.sh:120` — `CAP="${CC_JEV_RANK_CAP_B:-3000}"`, applied as
`head -c "$CAP" "$MEM/$f"` per file. `hooks/lib/jev.sh:81,141` imposes a second, outer ceiling:
`CC_JEV_MAX_STATE_B=24000`, enforced mechanically on the whole spec before any call.

Measured against `~/.claude-secondary/projects/-Users-chrisren-Development-claude-infrastructure/memory`:

| quantity | value |
|---|---|
| index lines naming a topic file | 146 |
| topic files that resolve (the population) | **146** (0 missing) |
| bytes actually sent, at cap 3000 | **388,462 B (≈ 379 KiB)** |
| mean per call | 2,660 B |
| files truncated by the cap | 75 of 146 |
| full uncapped corpus, for comparison | 626,252 B — so **the cap withholds 38% of it** |
| calls per full run | 146 (+1 preflight) |
| est. input tokens | ≈ 100 K |

**Per call, the JSON body is:** one `state` string = the first ≤3,000 bytes of one
`docs/lessons`-class memory topic file, plus two fixed question definitions (~1.1 KB of our own
prompt text). Nothing else. No path, no sha, no session id, no transcript.

**What is in those 3,000 bytes, said plainly for the packet:** our own engineering post-mortems.
They contain file paths in this repo, commit shas, tool names, launchd job names, measured
timings, and occasionally an operator instruction quoted back. They are the same class of content
as a commit body in this repo.

### 2b. What the live hook sends today

`state.closing_message` = one final assistant message of a turn, ≤24,000 B
(`hooks/lib/jev.sh:141`). ~372/day at the current rate.

### 2c. What is definitively NOT sent — the standing refusal, unchanged

| corpus | status | why it cannot leak |
|---|---|---|
| session transcripts | **never** | no caller passes one; `CC_JEV_MAX_STATE_B` would reject it anyway |
| the Outlook mailbox | **never** | no jev caller touches ms365 |
| the 213,995-message `msg` corpus | **never** | no jev caller touches `msg` |
| customer/tenant data (reso, venue rows, bottle menus) | **never** | different repo; no jev caller reads it |
| the API key itself | **never** | `agent-secrets run --` decrypts into the child only; `evaluate.mjs`'s contract line says *"stdout … Never the state, never the key."* |
| `.env*`, `*.pem`, `*credentials*` | **never** | also `Read`-denied at `~/.claude/settings.json` |

The candidate corpora named in the brief, priced the same way:

| corpus | bytes at cap 3000 | already in scope? |
|---|---|---|
| memory topic files (146) | 388 KB | **yes — this is the built one** |
| commit bodies | ~250 words mean × 45/50 carry a body — a 146-commit window ≈ 250 KB | not built |
| backlog rows | ~121–200 rows, short | not built |
| plan sections | `docs/plans/*.md` are large; a cap of 3,000 B truncates most | not built |
| bats tests | source code — a *different* disclosure class from prose; would want its own ruling | not built |

---

## 3. The vendor's terms, as this repo has recorded them

Source: `docs/research/jev-at-cost-api-2026-09-18.md`, §C (lines 237–283), with its own correction.

1. **§C's original claim** — that the Gateway route is *materially weaker on privacy* than the
   direct `api.typesafe.ai` route, because ZDR is a **per-request flag**
   (`providerOptions.gateway.zeroDataRetention`) that **fails closed**, rather than an enterprise
   contract term. Mechanism verified on the wire (`tests/jev-evaluate.bats`).
2. **The correction, same section, 2026-09-19, measured** — the mechanism held; the *availability*
   claim did not. The first real calls from this machine returned HTTP 403 verbatim:
   *"Zero Data Retention (ZDR) is only available for Pro and Enterprise plans. Current plan:
   **hobby**."* So ZDR **is** plan-gated, §4's original "enterprise-gated ZDR" reading was closer
   to the truth, and **§C's conclusion does not hold on this account.**
3. **No middle ground at the call level.** `@ai-sdk/gateway` 4.0.87 exposes exactly one privacy
   option, `zeroDataRetention?: boolean`. **There is no per-request no-training flag.** With ZDR
   off, standard retention is the only posture available.
4. **Verified against Vercel's own pricing page, 2026-09-19:** `/docs/ai-gateway/pricing` —
   *"Zero Data Retention, per-request: No additional cost — Availability: **Pro and Enterprise**."*
   And *"Free tier requests are **also rate limited per model**, with lower limits than the paid
   tier."*
5. Vercel's Jev changelog states ZDR **and No-Training** support for this model — but both are
   reached through the same plan gate we do not hold.

**So the packet's privacy sentence is:** *under standard retention, Vercel retains what we send and
we hold no no-training term. ZDR costs $20/mo (Pro) and would restore both.*

---

## 4. Precedent: scheduled jobs that already egress to a third party

All four verified by reading the plist and the target script.

| job | cadence | what leaves the box | third party | file |
|---|---|---|---|---|
| **`com.claude.dispatcher`** | **StartInterval 300 s**, `CC_FIRE_CLOUD=on` | **a full brief** — plan text, branch names, repo URL, task description — in the create-request body | **Anthropic** | plist `ProgramArguments` → `~/.claude/bin/cc-dispatch --once`; egress at `scripts/cloud-create-api.py:101` `BASE = os.environ.get("CC_CLOUD_API_BASE", "https://api.anthropic.com")`, `:290` `method="POST"`, `:294` `urlopen` |
| `com.claude.discovery` | StartInterval 3600 s | ledger/plan-derived candidate text via `cc-discover --once` | Anthropic | `com.claude.discovery.plist` |
| `com.claude.accounts-keepwarm` | StartInterval 180 s | OAuth/limits polling | Anthropic | `com.claude.accounts-keepwarm.plist` → `claude-accounts --keepwarm --max-age 90` |
| `com.claude.browse-mirror` | StartInterval 600 s | `git fetch` (rate-limited, once per repo) | GitHub | `scripts/browse-mirror-sync.sh:147` |
| `mb-hpc-price-watch` (**cron**) | daily 09:15 | HTTP GET only (no upload) | mercedesbenzhpc.com | `/Users/chrisren/Development/personal/bin/mb-hpc-price-watch:38,61` |

**The consent question for the CLASS is therefore already settled, and by the strongest possible
precedent:** `com.claude.dispatcher` is a launchd job that, every five minutes, unattended, POSTs
this fleet's own engineering briefs to a third-party API. It was activated the same way any new job
would be (`~/.claude/autonomy/pending-activation/02-load-dispatcher-activate.sh`, now `.done`).

**What that precedent does NOT settle:** *which* third party, and under *what retention*. Anthropic
is the operator's existing vendor under a Max plan with its own terms. Vercel + `typesafe-ai/jev`
is a distinct sub-processor whose free tier gives us no ZDR and no no-training term. A honest
packet says: *the schedule is precedented; the sub-processor's retention posture is the new fact.*

---

## 5. The 2026-09-25 billing cliff, and the exact guard

**The cliff, sourced:** "free until 2026-09-25" appears at `scripts/jev/rank-memory.sh:13`,
`scripts/jev/evaluate.mjs:133`, and `docs/research/jev-at-cost-api-2026-09-18.md:470,509`. It is
**free pricing, not free throughput** — free-tier requests are rate-limited per model *today*
(HTTP 429, `GatewayRateLimitError`, measured 2026-09-19 after ~a dozen calls).

**What happens on 2026-09-26 if a job is registered and nothing changes — three branches, and two
of them are safe by construction:**

| branch | outcome | already handled? |
|---|---|---|
| no payment method on the Vercel account | requests fail (402 / insufficient credits) → `evaluate.mjs` catch-all → `abstain('http')` → exit 10 → caller falls through | **YES.** `evaluate.mjs:139` classifies-never-collapses and every abstain leaves the caller on its existing path. Cost: $0, plus a JSONL of zero rows. |
| payment method present, spend cap holds | billing up to the cap, then refusal | **PARTIALLY.** The key is documented in packet `c3752f5fca96` as *"minted, capped $5/mo"*. So the worst case is **bounded at $5/month by the vendor**, and the bound is the operator's own, not the agent's. |
| cap raised or absent | unbounded spend | **NO GUARD EXISTS.** |

**Cost, for scale:** 146 calls × ~2,660 B ≈ 100 K input tokens. At the doc's own reference rate
($10.55 for ~238 M input tokens ≈ $0.044/M), **one full rank run ≈ half a US cent**; weekly ≈
**$0.26/year**. The $5/mo cap is ~1,000× headroom. Cost is not the risk here. *Unguarded, silent,
indefinite* spend is the risk, and it is a governance defect regardless of magnitude.

### The guard I would build — three arms, cheapest first, ALL inside the script

Stated as a design, not built (read-only slot).

```
ARM 1 — DATE FENCE (deterministic, no network, 4 lines)
  CC_JEV_FREE_UNTIL=20260925                       # pinned data, not a guess: sourced from the
                                                   # Vercel changelog, cited in 4 files today
  [ "$(date -u +%Y%m%d)" -lt "$CC_JEV_FREE_UNTIL" ] || {
      [ "${CC_JEV_PAID_OK:-0}" = 1 ] || {
        echo "✗ REFUSING: the free window closed on $CC_JEV_FREE_UNTIL and this run would BILL."
        echo "  Nothing has been sent. The operator re-arms with CC_JEV_PAID_OK=1."
        exit 5; }
  }
```
  Cheap and correct, but it is a *calendar* guard: it fires on a date rather than on the event, and
  the date can move. That is `a-falsifier-resting-on-a-frozen-pointer-is-inert` — so it is the
  cheap arm, never the only one.

```
ARM 2 — MEASURED COST FENCE (the real one; fires on money, not on a date)
  · evaluate.mjs currently emits {ok,answers,usage,warnings}. Add providerMetadata.gateway.cost
    (or the usage cost field the Gateway returns) to that object — ~2 lines at evaluate.mjs:99.
  · rank-memory.sh's existing PREFLIGHT (already one call before committing to 146,
    rank-memory.sh:110-119) then asserts cost == 0 — or <= CC_JEV_MAX_RUN_USD/TOT — and ABORTS
    on anything else.
```
  This is the arm that matters, and the preflight it hangs off **already exists** — it was added
  for exactly this class of failure ("the first version went straight into the loop … and would
  have reported SCORED 0 of 146 … a confident, well-formatted verdict over a path that never
  worked"). A cost fence there costs one call, catches the cliff arriving early *or* late, and
  catches a price change nobody announced.

```
ARM 3 — VENDOR-SIDE CAP (already in place; state it, do not rebuild it)
  The key is capped $5/mo at Vercel. Past it the gateway refuses, evaluate.mjs abstains, the
  caller falls through. This is the backstop and it requires no code.
```

**Polarity note (`alarm-polarity-and-attention-budget`):** arms 1 and 2 must refuse **before the
first call**, in the preflight, and print *"Nothing has been sent"* — never mid-loop after 40 calls
have been billed. `rank-memory.sh` already has exactly this shape at `:94-107` for ZDR; the cost
fence is the same pattern one slot down.

---

## 6. Reversibility

| act | undo | residue |
|---|---|---|
| `launchctl bootout gui/$UID/com.claude.jev-rank` | immediate; job stops on the next tick boundary | none — job never starts again |
| `rm ~/Library/LaunchAgents/com.claude.jev-rank.plist` | immediate | none |
| the **committed** template `launchd/com.claude.jev-rank.plist` | `git revert` | **the plist in the repo is inert.** 26 templates sit in `launchd/` today; `com.claude.desk-invariant.plist` and `com.claude.team-orphan-reaper.plist` are in `~/Library/LaunchAgents` and **absent from `launchctl list`** — i.e. present and unloaded. Committing a plist loads nothing. |
| `CC_JEV=0` (the kill switch) | one env var; kills **every** jev path including the live hook | this is a settings change ⇒ operator's, per `cc-jev status` |
| bytes already sent | **NOT REVERSIBLE** | this is the only irreversible edge, and it is the whole decision |

**Governance rail this repo already uses, and the one to follow:** the agent ships a **template**
plist in `launchd/` + a `docs/activation/<name>-activate-snippet.md`, and the **operator** runs
`launchctl bootstrap`. Verbatim from `docs/activation/discovery-activate-snippet.md`:

> **C10 ceiling:** the `discovery` agent builds + RED-proves `bin/cc-discover` … and ships a
> TEMPLATE plist; the **operator** performs the live wiring below. Nothing here loads launchd,
> edits `settings.json`, or symlinks **in place** — this file is the hand-off.

Ten such activations are on disk under `~/.claude/autonomy/pending-activation/`, each an
`NN-…-activate.sh` with a `.done` sibling. The one-command hand-off is
`cc-backlog needs "<step>" --run "<cmd>"` → the operator runs `cc-do <id>`.

---

## 7. The armed-sentinel design — evaluated, with a verdict

**The design, as the brief states it:** a launchd job on a durable schedule that runs the batch
**only when a sentinel file exists** which the operator creates with one command, and which the job
consumes/expires.

### Verdict: **HONEST — but only under three conditions, and it is consent-laundering without all three.**

**Why it is honest in principle.** It is a *capability* on a schedule and a *consent* per window,
which is the correct factoring: the schedule is the part the operator does not want to re-decide
(when, how often, with what backoff, at what hour the rate limits are loose), and the egress is the
part they do. The precedent for separating them is already on this box — every
`pending-activation/NN-*-activate.sh` is the same shape at coarser grain. And the alternative the
brief implicitly compares it to is worse in a measurable way: `cc-jev rank` on 146 files takes
**24–73 minutes** by its own printed estimate, which is a thing a human should not have to babysit
in the foreground.

**Condition 1 — CONSUME BEFORE CALLING, never after.** The job must `rm` (or rename to `.done`) the
sentinel **before the preflight call**, not after the loop. Otherwise any crash, kill, panic or
`launchd` reap leaves the sentinel in place and the next tick re-fires it. That converts a
per-window consent into a standing one *by accident*, and it is exactly
`resolution-signal-must-match-the-occurrence` — a clear signal that does not match the occurrence
disarms nothing. A sentinel that survives its own run is a permanently-on switch wearing a
consent's clothes.

**Condition 2 — THE SENTINEL MUST EXPIRE ON A CLOCK, NOT ONLY ON CONSUMPTION.** If the operator
arms it and the job cannot run for a week (box asleep, gateway down, job unloaded), the consent
must lapse, not wait. `scripts/dated-park-arm.sh` is the in-repo precedent for a dated arm. Without
this, arming is indistinguishable from enabling.

**Condition 3 — THE SENTINEL MUST CARRY WHAT IT CONSENTS TO, and the job must refuse a mismatch.**
A bare `touch ~/.claude/autonomy/jev-rank.arm` consents to nothing in particular. The file should
carry the corpus, the byte cap, and the call ceiling (`corpus=memory cap_b=3000 max_calls=150
armed=<ts>`), and the job must abort if the run it is about to make exceeds any of them. Otherwise
a later edit widens the payload from memory files to plan sections and the same sentinel authorises
it — which is `a-gate-s-surface-is-not-its-traffic` precisely.

### Where it WOULD be consent-laundering

- **If the arming command is one the agent can run.** It must be operator-only. If any agent path
  can create the sentinel, the design is a laundering machine: the agent arms, the daemon fires,
  and the classifier that refused the direct call is routed around with the refusal's own reason
  intact. State this in the plist doc and make the arm path unwritable from a session
  (`permissions.deny` on the exact path is the right lever — and it *would* work here, since the
  blocker for that path would be a deny rule, not a hook).
- **If it is sold as "no new decision".** It IS a new decision — the first standing arrangement
  under which our notes are sent with retention. Presenting the sentinel as a safety feature that
  makes the packet unnecessary is the laundering move. The sentinel makes the decision *revocable
  and windowed*; it does not make it *unnecessary*.
- **If the operator is told the schedule is the point.** The schedule is nearly worthless on its
  own for this corpus (§8). If the honest value is "run it unattended overnight when the free-tier
  rate limit is loose", say that.

### The cheaper, more honest variant worth putting beside it

**No sentinel at all: the job runs on a schedule and is simply not armed until the packet is
ruled.** Register nothing; ship the template plist + activation snippet; file
`cc-backlog needs "launchctl bootstrap com.claude.jev-rank" --run "<cmd>"`. The operator's single
`cc-do <id>` IS the consent, it is durable, it is revocable with `launchctl bootout`, and it needs
no new mechanism. The sentinel only earns its complexity if the operator wants *per-window* rather
than *once* — and that is a preference, not a safety property.

---

## 8. Adversarial pass — three things a hostile reviewer would say

**(a) "You are about to schedule a job whose output nothing reads."** This is the strongest
objection and it is correct today. `rank-memory.sh` writes
`~/.claude/autonomy/jev-rank-<ts>.jsonl` and prints a demotion-candidate list, and its own header
says *"Eviction stays a human read of a ranked list."* **No consumer exists.** A weekly job
producing an artifact nobody opens is `mirroring-a-corpus-is-not-using-it` and
`detector-with-no-owner-is-not-an-actuator` in one — and this repo has burned a plan on exactly
that shape before. **The fix is cheap and it already has a socket:** `cc-discover` runs a critic
set (C1 frontier-hole, C2 plan-open, C3 wiring-inert, C4 gate-red) that *appends candidates to
`cc-backlog`*. A **C5 critic** reading the newest `jev-rank-*.jsonl` and filing one idempotent row
— *"review N low-bite memory rules for demotion"* — closes the loop without any agent evicting
anything. **Any packet that proposes the schedule should propose the consumer in the same breath**,
or the honest answer is that the schedule is ceremony.

**(b) "The memory index barely changes — what does a schedule buy?"** `MEMORY.md` is at its hard
cap (24,333/25,000 UTF-16 units) and `cc-memory-rotate` reads `verdict=exhausted`, so **every
append is already an eviction decision** and the index churns at roughly the rate lessons are
learned. A weekly cadence is defensible; a daily one is not, and would 7× the egress for nothing.
Put **weekly, Sunday, off-peak** in the packet as the measured cadence, not "hourly like the rest".

**(c) "You never checked whether this needs a third party at all."** Checked. **Ollama is running
locally** (`sh.brew.ollama.plist` loaded; `127.0.0.1:11434/api/tags` returns
`gemma4:26b-a4b-it-qat`, 15.6 GB). Zero egress, zero cost, no vendor. **Ruled out, with the
reason:** the whole point of Jev in `§4 rank 3` is a *calibrated ordinal* — 101 distinct
probability values, a high-precision tail at p≥0.98 — and a local instruct model returns a token,
not a calibrated posterior. Swapping it in would produce a ranking with the same shape and none of
the property the ranking was chosen for, and nobody would be able to tell the difference from the
output. Worth naming in the packet as the third option **only if labelled honestly**: *"a free
local ranking that measures something else."*

**Residual I could not close:** whether Vercel persists the body of a ZDR-403'd request. Nothing on
this box can answer it and the vendor's docs as recorded here do not address it. It bounds how much
weight "it already leaks" can carry — which is why §0 refuses to let that argument into the fork.

---

## 9. Draft decision-packet body

Class C. No codenames, no hex ids in the question.

```
what_plain:
  May our own engineering lesson notes — about 380 KB of them, 146 short post-mortems we wrote
  about this machine — be sent to Vercel's AI gateway under ordinary retention, once a week, by a
  scheduled job, so a model can rank which of them still earn their place in the memory index that
  is now full?

conviction: <the lead's number>
receipt:    docs/research/jev-100p-2026-09-21/a8-consent-and-scheduling.md
            (and the two commands under "receipts" below)
```

**Option 1 — send under ordinary retention, weekly, operator-armed.**

*Outcome in operator terms:* about 380 KB of our own engineering notes go to Vercel once a week
and are retained by them; we hold no no-training term on the free tier. Cost is about half a cent a
run, hard-capped at $5/month by the key itself. Nothing customer-facing, nothing from the mailbox,
nothing from the 213,995-message archive, no transcripts — the job can only read the 146 memory
topic files, and the cap is in the code. It is reversible in one command
(`launchctl bootout gui/$UID/com.claude.jev-rank`) and every window needs you to arm it. What it
buys: the first semantic read of every memory rule we have, so the index that is now at its hard
cap stops being trimmed by file age and citation counts.

*Receipt:*
```
grep -c '](.*\.md)' ~/.claude-secondary/projects/-Users-chrisren-Development-claude-infrastructure/memory/MEMORY.md
  => 146
# and the measured egress, 388,462 B at the in-code cap of 3,000 B/file:
sed -n '120p' scripts/jev/rank-memory.sh
  => CAP="${CC_JEV_RANK_CAP_B:-3000}"
```

**Option 2 — pay Vercel $20/month for Pro so zero-retention works, then schedule it.**

*Outcome in operator terms:* the same job runs with the retention protection the code was designed
around — Vercel's zero-data-retention flag already fails closed, so a run either gets full
protection or refuses outright. $20/month standing, for a job whose own usage costs under a dollar
a year. Buys the retention question away permanently and makes every future Jev use free of it too.

*Receipt:*
```
bash bin/cc-jev status
  => ZDR         on, fails closed
# and the gateway's own words, recorded 2026-09-19:
grep -n "Current plan" docs/research/jev-at-cost-api-2026-09-18.md
  => "Zero Data Retention (ZDR) is only available for Pro and Enterprise plans. Current plan: hobby."
```

**Third option, if the lead wants it on the table:** rank locally with the Ollama model already
running on this box — zero egress, zero cost — accepting that it returns a label rather than a
calibrated probability, which is the property the ranking was chosen for.

*Receipt:* `curl -s http://127.0.0.1:11434/api/tags` → `gemma4:26b-a4b-it-qat`, 15.6 GB, live.

**What the packet must NOT say:** that this is about whether a job may be scheduled. It may —
`com.claude.dispatcher` has been POSTing our briefs to a third-party API every five minutes,
unattended, since its activation, and `anti-deference-nudge.sh` has been calling this very gateway
372 times a day. The only open question is retention.

---

## 10. Re-derive, never re-quote

```
# the refusal, and that it is the classifier rather than a rule or a hook
grep -i jev ~/.claude/logs/permission-denied.jsonl | python3 -m json.tool
python3 -c "import json;p=json.load(open('/Users/chrisren/.claude/settings.json'))['permissions'];print(p['deny'])"
grep -nE 'network|egress|curl|AI_GATEWAY|jev|https://' hooks/validate-bash.sh

# the hook that already calls out, and how often
grep -n 'jev_ask' hooks/anti-deference-nudge.sh
python3 - <<'PY'
import json,collections
c=collections.Counter(); ts=[]
for l in open('/Users/chrisren/.claude/autonomy/idl.jsonl'):
    try: d=json.loads(l)
    except: continue
    if d.get('hook')=='anti-deference-nudge': ts.append(d['ts']); c[d.get('reason','?')]+=1
print(len(ts), min(ts), max(ts), c.most_common(5))
PY
bash bin/cc-jev status          # read-only, no network — prints the RETIRED-IS-NOT-OFF banner

# no launchd job runs Claude Code
for p in ~/Library/LaunchAgents/com.claude.*.plist; do grep -o 'exec [^<]*' "$p"; done

# the scheduled third-party egress precedent
sed -n '101p;290p;294p' scripts/cloud-create-api.py
grep -o 'CC_FIRE_CLOUD=[a-z]*' ~/Library/LaunchAgents/com.claude.dispatcher.plist

# the egress bytes
MEM=~/.claude-secondary/projects/-Users-chrisren-Development-claude-infrastructure/memory
grep -o '](\([^)]*\.md\))' "$MEM/MEMORY.md" | sed 's/](//;s/)//' | while read -r f; do
  [ -f "$MEM/$f" ] && head -c 3000 "$MEM/$f" | wc -c; done | paste -sd+ - | bc
```
