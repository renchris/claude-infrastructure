---
axis: A6-VERIFY — adversarial verification of the quota/account-economics finding
date: 2026-08-19
verifies: docs/research/orchestration-units-2026-08-19/A6-quota-economics.md
posture: REFUTE by default. Every number below was re-derived independently; nothing was accepted on the finder's word.
headline: >
  The finder's MEASUREMENTS survive intact — its per-agent token table reproduces byte-exact, its
  billing-attribution chain is now closed rather than merely suggestive, and its readout is genuine.
  Its ORDERING VERDICT does not survive: it compared "8-23 continuously-WORKING units" against
  "~15 RESIDENT panes", two different denominators, and the conversion factor it never applied is
  measured here at 0.36. Corrected, quota does NOT bind before hardware on either horizon; the
  crossover is at 26 resident panes and the operator's ceiling is 15. Two new mechanisms surface:
  fan-out concentrates OAuth-refresh-herd risk on the same 4× axis it concentrates quota (and that
  failure mode is discontinuous, not gradual), and cache-read≈0 silently kills a still-live standing
  policy line in the prior wall-ranking doc.
---

## 1. Verdict (≤5 lines)

1. **CONFIRMED, byte-exact — the token sums.** Three agent transcripts re-summed independently
   reproduce the finder's table to the digit (A10 `6497/91956/816846`, A11 `7914/115431/1243019`,
   A7 `40381/178190/5184756`). It **did** dedupe on `message.id`, and dedupe is lossless (0 of 62
   duplicated ids disagree on usage). *Correction:* the inflation is **not** "exactly 2.00×" — that
   is a record-count ratio; token inflation is **2.05–2.88× and class-dependent**, which distorts
   the out:cc *ratio*, not just the scale.
2. **CONFIRMED and strengthened — billing attribution.** Re-measured on a different pid: the agent
   carries the parent's `CLAUDE_CONFIG_DIR`, holds **zero** credential-shaped env vars (positive
   control passes), **no config dir contains an on-disk credentials file**, and the keychain service
   is `sha256(NFC(config_dir))[:8]` — all four derived hashes exist in `login.keychain`. That closes
   the argument: the only credential *reachable* by the agent is the parent's.
3. **REFUTED as stated — which ceiling binds first.** MEASURED fleet duty cycle `k_work/k` = **0.36**
   (n=517). So 15 resident panes = **5.4 working units**, and the model-free sustainable weekly rate
   is **9.4 working units fleet-wide** (6.08 %/day per unit vs a 14.29 %/day allowance). **Hardware
   binds first on BOTH horizons.** The crossover is **26 resident panes (17–30)** — nobody stated it.
4. **NEW, and it survives the finder's own logic better than quota does.** Agents inherit the
   parent's config dir ⇒ the same `.oauth_refresh.lock` and the same *rotating* refresh token. An
   11-agent wave puts **12 contenders on one account's lock**; a lost race is documented as
   **account-wide logout**. Fan-out concentrates herd risk 4× on the same axis as quota, and this
   failure mode is discontinuous.
5. **PARTIALLY REFUTED — two overclaims.** "Cache-read is confirmed free" contradicts the finder's
   own cited source (`cond(X)=23,556`, "reported as a bound, not a point"); and `RMSE=1.73 pp, n=23`
   is arithmetically incompatible with a published in-criteria residual of 17.7 pp. Neither damages
   the practical answer, because §2.3 below is model-free.

---

## 2. The numbers, with the command that produced each

### C1 · THE TOKEN SUMS — CONFIRMED (exact), with one correction

**Method.** Independent re-implementation. Walked each agent `.jsonl`, kept `type=="assistant"`
records carrying `message.usage`, and compared raw-line sums against `message.id`-deduped sums.
Script: `scratchpad/a6v/sum1.py`.

```
$ python3 sum1.py ~/.claude-tertiary/projects/-Users-chrisren-Development--worktrees-wt-pool-8/<agent>.jsonl
```

| agent | finder's out / cc / cr | MY dedup out / cc / cr | finder pp | MY pp | verdict |
|---|---|---|---|---|---|
| A10-hostile-reviewer | 6,497 / 91,956 / 816,846 | **6,497 / 91,956 / 816,846** | 0.22 | **0.222** | exact |
| A11-redteam-widening | 7,914 / 115,431 / 1,243,019 | **7,914 / 115,431 / 1,243,019** | 0.28 | **0.276** | exact |
| A7-single-user | 40,381 / 178,190 / 5,184,756 | **40,381 / 178,190 / 5,184,756** | 0.65 | **0.650** | exact |

**Dedupe is lossless — proven, not assumed.** For every duplicated `message.id`, all its lines carry
*identical* usage tuples: `message.ids whose dup lines DISAGREE on usage: 0` across all three files.
So collapsing on `message.id` cannot drop a distinct billed response.

**CORRECTION — "exactly 2.00×" is a record ratio, not a token ratio.**

| file | multiplicity histogram | out inflation | cc inflation | cr inflation |
|---|---|---|---|---|
| A10 | `{1:2, 2:4, 3:4}` | 2.298× | **2.879×** | 2.047× |
| A11 | `{1:4, 2:5, 3:4}` | 2.145× | **2.624×** | 1.870× |
| A7  | `{1:8, 2:15, 3:15, 4:1}` | 2.486× | **2.793×** | 2.145× |

Lines-per-response is **1–4, not 2**; the fleet-scale `48326/24174 = 1.9991` is a mean over a spread.
And because cc inflates ~2.8× while output inflates ~2.3× and cache-read ~2.0×, a raw-summed
regression **shifts the out:cc ratio**, it does not merely rescale it. This is the likeliest
mechanical origin of the finder-vs-A1 disagreement (4.3 vs 9.0) that its §4 Q5 leaves open — and it
supports the finder: `exchange-rate.md:162` shows the prior study deduped by **`os.path.realpath`**
(the store-symlink trap), with no mention anywhere of `message.id` (positive control: the file's own
dedupe grep returns exactly one hit, line 162). The finder's characterisation of A1 is correct.

> **Impact on the conclusion: none.** A 2–3× inflation would have *lowered* how many agents an
> account can carry. It is not present.

---

### C2 · BILLING-ATTRIBUTION PROOF — CONFIRMED, and upgraded from inheritance to closure

The finder proved *inheritance*. Inheritance alone leaves the attack open ("a subagent could use a
different credential path"). Four measurements close it.

**(a) Inheritance replicates on a different pid.** The finder used pid 8435; I used **pid 17602**
(`A10-hostile-reviewer@session-84bde2e9`, `--agent-type deep-research`):

```
$ ps -E -ww -p 17602 -o command= | tr ' ' '\n' | grep -E '^[A-Z_]+='
CLAUDE_CONFIG_DIR=/Users/chrisren/.claude-tertiary
CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1
CC_SPAWN_GEN=1
CC_SPAWN_ROOT=p54762            ← names its spawning session's pid
…
```

**(b) The agent carries NO credential of its own — with a positive control.**

```
$ ps -E -ww -p 17602 -o command= | tr ' ' '\n' | grep -icE 'API_KEY|TOKEN|OAUTH|BEARER|SECRET'
0
$ ps -E -ww -p 17602 -o command= | tr ' ' '\n' | grep -c 'CLAUDE_CONFIG_DIR'
1          ← the instrument is not blind
```

**(c) No config dir holds an on-disk credential, so the keychain is the only store.**

```
$ for d in ~/.claude ~/.claude-secondary ~/.claude-tertiary ~/.claude-quaternary; do
    ls -la "$d"/.credentials.json "$d"/credentials.json 2>/dev/null; done
(no output — 0 of 4)
```

**(d) The keychain item is a pure function of the config dir, and all four exist.**

```
$ python3 -c 'sha256(NFC(dir))[:8]'          # derivation read from bin/claude-accounts:349-352
/Users/chrisren/.claude            -> Claude Code-credentials-7b461744
/Users/chrisren/.claude-secondary  -> Claude Code-credentials-0503d474
/Users/chrisren/.claude-tertiary   -> Claude Code-credentials-6a49a3e4
/Users/chrisren/.claude-quaternary -> Claude Code-credentials-136fa815
$ security dump-keychain | grep -o '"Claude Code-credentials-[0-9a-f]*"' | sort -u
… all four present, among 22 items total …
```

**Closure.** The agent inherits exactly one identity input (`CLAUDE_CONFIG_DIR`), carries no
credential material of its own, and the credential store is keyed on that input with no on-disk
alternative. There is no path by which an `--agent-id` process can bill a different account.
**CONFIRMED.**

*Instrument note:* `strings`-grepping the binary for the literal `Claude Code-credentials` returns
**0** while `CLAUDE_CONFIG_DIR` returns **27** and `Claude Code` returns 709 — i.e. the service name
is *constructed at runtime*, not stored. A null there is construction, not absence; I did not use it
as evidence either way.

---

### C3 · THE REFRESH HERD — agents are NOT exempt; they AMPLIFY it 4× (NEW)

The brief asked whether agent processes make the known refresh herd worse or are exempt. **Worse.**

**The lock exists, and it is per-config-dir.** Strings extracted from the 2.1.220 Mach-O:

```
$ LC_ALL=C strings -a .../bin/claude.exe | grep -i 'oauth.*refresh.*lock'
.design_oauth_refresh.lock
.oauth_refresh.lock
OAuth refresh lock compromised:
tengu_oauth_refresh_legacy_lock_contended
OAuth refresh legacy-lock acquire failed:
OAuth refresh new-lock release failed:
```

Prior repo research already established the scope and the blast radius
(`scaling-bottlenecks-2026-08-09/08-platform-terms.md:78-82`, QUOTED-FROM-DOC): *"one credential /
expiry instant per ~37 sessions … rotation MEASURED: rt `0023ef9690b1→a9f8aadf29eb` … a losing racer
that proceeds presents a stale refresh token → `invalid_grant` → **account-wide** logout."*

**Measured token lifetime — this sets the exposure window.**

```
$ security find-generic-password -s "Claude Code-credentials-<hash>" -w   # per account, read-only
next2  expiresAt=2026-08-19T15:24:13Z  in=3.25h   subType=max
next3  expiresAt=2026-08-19T14:56:55Z  in=2.80h   subType=max
next4  expiresAt=2026-08-19T19:26:02Z  in=7.28h   subType=max
next   expiresAt=None  rtHash=e3b0c44298fc (= sha256 of empty string) ← different credential shape
```

Access-token TTL is ~8 h. **The argument:** the herd at an expiry instant is the count of *live
processes holding that account's credential*, and an agent holds the parent's. A dispatched-session
shape spreads N units over up to 4 locks; an Agent-Teams wave puts all N + the lead on **one**. The
live wave measured here is 11 agents + 1 lead = **12 contenders on `~/.claude-tertiary`'s single
lock**, where the same work dispatched would have been ~3 per lock.

So fan-out concentrates herd risk on **exactly the same 4× axis** the finder identified for quota —
and this consequence is worse in kind: quota degrades gradually and resets; a lost refresh race is a
**discontinuous account-wide logout** with no reset to wait for. This *strengthens* the finder's
claim 5 by a second, independent mechanism it did not consider.

**Label: mechanism + inheritance = INFERRED.** I did not observe a lost race, and I did not test
whether an agent short-circuits refresh by reading a parent-cached token. That is the one experiment
that would settle it (see §4).

---

### C4 · WHICH CEILING BINDS FIRST — REFUTED as stated (unit error); corrected answer inverts it

**The defect.** The finder's §2.8 table compares:

| its row | its unit |
|---|---|
| "SUSTAINED … **2-6** working units per account, **8-23** fleet" | continuously-**WORKING** units |
| "vs the ~15 hardware ceiling" | resident **PANES** |

These are different denominators. The conversion factor is the duty cycle, which the finder never
measured. It is measurable directly, because the utilization log records both: `k` = the **pane**
census, `k_work` = **transcript-writers inside `KWORK_WINDOW_MIN`** (`bin/claude-accounts:1356`).

**Measured duty cycle** (`scratchpad/a6v/duty.py` over 7,653 rows, 2026-08-10 → 08-19):

```
=== FLEET TOTALS at each timestamp (all 4 accounts measured) ===
  n=517 minutes
  fleet k (panes)          med=15   p95=37   max=51
  fleet k_work (writers)   med= 5   p95=22   max=46
  fleet k_work/k           med=0.36 p95=0.81 max=1.84
```

Two things fall out at once. The operator's "~15" is **confirmed as the median pane count**, and the
fleet's working fraction is **0.36**, not 1.0.

**Model-free sustainable rate.** Rather than chain the finder's two ratios (pp/h per unit × a
weekly:5h allowance ratio), I measured the weekly meter's own slope against `k_work`. This touches no
token model, so it is immune to every §C5/§C6 objection below (`scratchpad/a6v/weekly2.py`):

```
acct    window start       hrs   dW%   %/day  mean kw  n kw  %/day/unit
next    2026-08-16T04:04  80.0    52    15.6     2.57   475        6.08
next2   2026-08-15T18:50  89.2    31     8.3     0.90   497        9.23
next3   2026-08-11T17:56 162.0    98    14.5     2.79   322        5.21
next3   2026-08-18T15:04  21.0    11    12.6     2.09   150        6.01
next4   2026-08-16T09:04  75.0    26     8.3     1.26   492        6.59

weekly %/day per continuously-working unit: n=5 median=6.08 mean=6.62 range=5.21-9.23
sustainable weekly rate = 100%/7d = 14.29 %/day
  => per account: 2.3 working units (median) | 1.5-2.7 (range)
  => FLEET (4)  : 9.4 working units (median) | 6.2-11.0 (range)
```

**Sanity check against the live readout, which I did not use to fit:** this predicts `next` at 15.6
%/day → 109% by reset; the readout independently renders *"next burn 1.11× → ~111% by reset ⚠ WALL"*.
Agreement to 2 points from two unrelated derivations.

**The corrected ordering:**

| quantity | value | source |
|---|---|---|
| hardware ceiling | **15 resident panes** | operator + measured fleet median |
| ⇒ working units at 15 panes | **5.4** | 15 × 0.36 (MEASURED) |
| sustainable working units, fleet | **9.4** (6.2–11.0) | weekly-meter slope (MEASURED, model-free) |
| **⇒ crossover: sustainable resident panes** | **26 (17–30)** | 9.4 ÷ 0.36 |

**So hardware binds first on BOTH horizons, not just the burst one.** At the operator's ceiling the
fleet uses ~57% of its sustainable weekly budget. Quota only becomes the binding wall **above ~26
resident panes.**

**Two sub-verdicts against the finder:**

- Its **burst** row (quota looser than hardware) — **CONFIRMED**, and by a wider margin than stated.
- Its **sustained** row (quota tighter than hardware) — **REFUTED**. Its band is also ~2× too wide at
  the top: measured 1.5–2.7 per account / 6.2–11.0 fleet, against its 2–6 / 8–23.

**What survives, sharpened.** The finder's claim 5 — *"raising 15 → 40 concurrent sessions raises the
burn rate against an unchanged weekly allowance"* — is **CONFIRMED and is the operationally important
result**, and it now has a number: 40 panes × 0.36 = **14.4 working units against a 9.4 sustainable
budget = 1.53× over**. The process-engineering win turns harmful at **26 panes**, not at 15.

*Caveat I checked rather than assumed:* is the 0.36 duty cycle itself a quota artifact (sessions
idling because they were throttled)? No — only **88 of 7,653 samples (1.1%)** sit at ≥90% of a 5-hour
window. Quota-forced idling cannot explain a 64% idle fraction.

*Instrument caveat, stated because it bounds this section:* `k_work` is `None` in **73%** of samples
(the census walk goes over budget and records absent rather than a fabricated 0). Every figure above
is computed on the measured 27%. If the walk aborts preferentially when the fleet is busiest, mean
`k_work` is biased **low**, which would make %/day-per-unit biased **high** and the sustainable count
biased **low** — i.e. the correction above is conservative in the direction that favours the finder.

---

### C5 · THE FIT'S INTERNAL CONSISTENCY — PARTIALLY REFUTED

The finder publishes `R^2 = 0.974  n=23  RMSE=1.73 pp` and states the fit set is windows with
`cov ≥ 4.0h`, `0 < pp < 100`, no Fable. Its own published window table then contains:

```
next3  08-17 04:30Z      4.8   46  28.3   …
```

`cov=4.8` ✓, `0 < 46 < 100` ✓, next3 Fable = 0% ✓ — so this row meets every stated criterion and
carries a residual of **17.7 pp**. But `RMSE=1.73` at `n=23` implies a *total* sum of squared
residuals of `23 × 1.73² = 68.8`, and this single residual contributes `313` — **4.5× the entire
budget**. The two cannot both be true.

Either an unstated exclusion applies to that window, or the quoted RMSE/R² are not the fit-set
values. **The quoted goodness-of-fit cannot be taken at face value**, and with it the "±" implied
around 7.93 / 1.85 pp-per-Mtok. I could not resolve which, because the fit-set membership list is in
the finder's scratchpad, not in the file (see §3).

---

### C6 · "CACHE-READ IS CONFIRMED FREE" — PARTIALLY REFUTED (overclaim), plus a live consequence

The finder writes: *"Cache-read is confirmed free… A charged term could not hide in that."* Its own
cited source says the opposite, in a section headed by what is null
(`usage-telemetry-100p-2026-08-16/exchange-rate.md:145`, QUOTED-FROM-DOC):

> | Whether **cache-read is truly free or list-priced** | corr(out, cr) = 0.936; cond(X) = 23,556.
> Both hypotheses fit (R² 0.813 vs 0.797). **Reported as a bound, not a point.** |

The finder **forced** `cr = 0` and then argued from the residual of the constrained model. That tests
whether the constrained model fits; it does not test the coefficient. It reports no condition number
for its own design matrix, and with `corr(out, cr) = 0.936` in the prior study there is no reason to
think its own is better conditioned. The correct label is the source's: **a bound, not a point.**

**Why this does not damage the practical answer:** §C4's sustainable-count derivation never touches
the token model. It survives whichever way cache-read resolves.

**A live consequence nobody has filed.** If cache-read ≈ 0, the prior wall-ranking doc's headline
quota lever is dead — and that doc is still the repo's standing reference
(`scaling-bottlenecks-2026-08-09.md:36`, QUOTED-FROM-DOC):

> **68% of quota cost is cache-read at median ~200K contexts ⇒ halving context ≈ +50% active
> capacity** — bigger than a fifth account.

and line 150 carries it into standing policy: *"context stewardship IS capacity — median turn context
~200K, 68% of quota…"*. The 2026-08-16 meter experiment already refutes the premise
(`exchange-rate.md:45`: Opus-5 cache-read = **0.000**, p95 ≤ 0.0017, over ≥590M tokens) and its own R1
says the opposite of the policy line: *"Stop treating long cached context as quota-expensive… it
authorises MORE context."* Two repo documents give directly opposite advice and neither cites the
other.

**Bonus: the two documents reconcile numerically once you remove cache-read.**
`scaling-bottlenecks` rank 4 says the fleet sustains **~3.9 concurrent active 24/7**. If that figure
was priced with cache-read as 68% of cost and cache-read is ~free, the true capacity is
`3.9 / 0.32 = 12.2` — which sits at the top of my independently measured **6.2–11.0**. Three
derivations (the prior doc corrected, the finder's, and my model-free one) converge on **~9–12 working
units fleet-wide**. That convergence is the strongest thing in this file.

---

### C7 · THE READOUT — CONFIRMED verbatim (not paraphrased)

Re-run directly, not under `bash`:

```
$ /Users/chrisren/.claude/bin/claude-accounts --readout
| account | live | 5h used | 5h resets | weekly used | Fable used | weekly resets | login expires |
|---|---|---|---|---|---|---|---|
| **next** ➤ | 2 | 3% | Wed 07:30 (in 2.5h) | 53% | 21% | Sat 21:00 (in 3d 16h) | Tue Sep 15 15:44 (in 27d 10h) |
| **next4** ➤ᵍ | 3 | 8% | Wed 09:20 (in 4.3h) | 27% | 15% | Sun 02:00 (in 3d 21h) | Sat Sep 12 23:02 (in 24d 18h) |
| next3 | 7 | 24% | Wed 06:59 (in 2.0h) | 11% | 0% | Tue Aug 25 04:59 (in 6d) | Thu Sep 03 10:27 (in 15d 5h) |
| next2 ← you | 5 | 12% | Wed 08:49 (in 3.8h) | 30% | 0% | Sat 03:59 (in 2d 23h) | Mon Sep 07 04:28 (in 18d 23h) |

➤ desk (bare `claude`) → **next** — earliest weekly reset among 5h-safe accounts · weekly ↻ 3d 16h · 5h 3% · safe set
➤ general → **next4** · ➤ fable → **next**
weekly burn (1.00× = lands exactly at the 100% wall): next2 burn 0.52× → ~52% by reset, needs 24%/d over 2d (recent 18%/d) · next burn 1.11× → ~111% by reset ⚠ WALL, needs 13%/d over 3d (recent 4%/d) · next4 burn 0.60× → ~60% by reset, needs 19%/d over 3d (recent 6%/d) · next3 burn 0.77× → ~77% by reset, needs 15%/d over 6d (recent 14%/d)
Fable window: **permanent** (no expiry).

**Agent backends beyond Claude** — registry `~/.claude/providers.json`

| backend | routable | version | auth | plan | bills outside it? | model pinned |
|---|---|---|---|---|---|---|
| Codex CLI | ✅ | codex-cli 0.147.0 | ok | ChatGPT Plus | no | gpt-5.6-sol @ xhigh ✓proven |
| Pi · Codex backend | ✅ | 0.84.1 | ok | ChatGPT Plus | no | gpt-5.6-sol ✓proven |
| Pi · Claude backend | ⊘ skipped | 0.84.1 | credentials_not_configured | Claude Pro/Max (auth works, usage does NOT draw on the plan) | 🚨 **YES** | — |
| Antigravity | ⊘ skipped | 1.107.0 | ok | UNKNOWN | UNKNOWN | — |
| Gemini CLI | ⊘ skipped | 0.29.5 | ok | UNKNOWN | UNKNOWN | gemini-3-pro-preview ⚠unproven |
| Grok CLI | ⊘ skipped | not installed | — | UNKNOWN | 🚨 **YES** | — |
- ⊘ `pi-claude` — COST GATE FAIL — bills per token outside the Max plan
- ⊘ `antigravity` — NOT AN AGENT BACKEND — the binary is the VS Code editor launcher, no non-interactive mode
- ⊘ `gemini` — DEFERRED — plan tier UNKNOWN, so the cost gate cannot clear it
- ⊘ `grok` — COST GATE FAIL — API-key-only, and we hold no xAI plan

➤ non-Claude backends ready now: **2 of 2 routable** (6 known)
- 🚨 rows marked **YES** bill OUTSIDE a plan we hold — not wired, by policy (`accounts.json spend.usage_credits_authorized=false`)
```

Every column and every footer line the finder published is present. Differences are pure live drift
(next3 9→7 live, 23→24% 5h; next 52→53% weekly; the desk/general routing pick moved). **The finder
reproduced the renderer, it did not paraphrase it.** CONFIRMED.

**Its brief-correction also reproduces exactly.** `bash /Users/chrisren/.claude/bin/claude-accounts
--readout` dumps a wall of an unrelated pnpm-global CC 2.0.5 bundle and dies on
`TypeError: B.allowedTools is not iterable` at
`.../@anthropic-ai+claude-code@2.0.5/.../cli.js:763`. The file is `#!/usr/bin/env python3`; invoke it
directly. **Other axes in this wave should apply this correction.**

---

### C8 · MACHINE-FACTS CORRECTION (challenge, per the brief's invitation)

> "Claude Code in use: v2.1.220 … (cli.js is the bundled binary; bin/claude.exe is the launched executable)."

**There is no `cli.js` in 2.1.220.**

```
$ ls /Users/chrisren/.claude-220/node_modules/@anthropic-ai/claude-code/
bin/  cli-wrapper.cjs  install.cjs  LICENSE.md  package.json  README.md  sdk-tools.d.ts
$ file .../bin/claude.exe
Mach-O 64-bit executable arm64      # 256,908,272 bytes
```

Any axis in this wave that greps `cli.js` gets a **blind null** and will read it as absence. Use
`strings -a` on `bin/claude.exe` (positive control: `CLAUDE_CONFIG_DIR` → 27 hits, `Claude Code` →
709; `Claude Code-credentials` → 0 because it is constructed at runtime).

---

### C9 · `k_work > k` — a pane-free-unit signal, but a WEAK one (NEW, and I am refuting my own lead)

`k` counts panes and `k_work` counts transcript-writers, so `k_work − k` looked like a direct census
of units that write transcripts without owning a pane — a clean test of the operator's hypothesis.
Measured, it mostly is not:

```
acct    kw>k %   kw-k med   kw-k max
next      3.5%        -1         25
next2     6.0%        -1          5
next3     3.9%        -4          8
next4     0.8%        -2          1
fleet: k_work exceeds k in 3.5% of samples; median excess -2, p95 0, max 25
```

`k_work` exceeds `k` in only **3.5%** of samples. The `max=25` excess on `next` proves the census
*can* see 25 more writers than panes, but the median says pane-free units are not the normal state —
partly because `k_work` has a time window and idle agents fall out of it, and partly because of the
73% `None` censoring. **This is not usable evidence for the pane question; A1–A5 own that axis with
process-level instruments.** Recording it so no one else re-derives it and over-reads it.

---

## 3. What I tried that did NOT work / could not be measured

1. **I could not re-run the finder's regression.** The fit-set membership (which 23 of the 48
   windows) lives in its scratchpad `windows.json`, and the file publishes only 10 of 48 rows. I
   could detect the RMSE/residual contradiction (§C5) but not resolve it. **Ask the finder to publish
   the fit-set list and the design-matrix condition number.**
2. **Grepping the 257 MB Mach-O is slow enough to time out.** Two `grep -o '.\{0,240\}…'` passes over
   the extracted 652,094-line strings dump exceeded 120 s. Extract to a file first
   (`strings -a > /tmp/x`), then use fixed-string greps. This is why §C3 cites the *presence* of the
   lock strings rather than their surrounding construction code.
3. **I could not determine whether an agent short-circuits refresh.** The decisive question for §C3
   is whether an `--agent-id` process ever *attempts* a refresh or only ever reads a token the parent
   already refreshed. Answering it needs either a `dtrace`/`fs_usage` watch on `.oauth_refresh.lock`
   across an expiry instant, or an instrumented spawn — neither is read-only-safe on a live fleet at
   an unpredictable time. **The 4× contention claim is INFERRED from inheritance + lock scope.**
4. **`next`'s keychain record has a different shape.** `expiresAt=None` and `refreshToken` hashing to
   `e3b0c44298fc` (= sha256 of the empty string) while the account is demonstrably authenticated and
   the readout shows a login expiry of Sep 15. So either the credential lives under a different JSON
   key for that account, or `next` uses a longer-lived grant. I did not chase it; flagging it because
   any tool that reads `claudeAiOauth.expiresAt` uniformly will mis-handle `next`.
5. **The transcript carries no account identity.** `grep` for `accountUuid|organizationUuid|
   emailAddress|oauthAccount` over both an agent and its parent transcript returns nothing. The
   transcript proves which *store* a unit writes to, never which *credential* it used — which is
   exactly why §C2 had to close the loop through the env + keychain rather than through the file
   location. The finder's "Proof 3" is weaker than it reads; its Proofs 1+2 carry the claim.
6. **I spawned nothing.** No `claude -p`, no fires, nothing killed, stopped, or torn down. All of the
   above is `ps` / `security` (read) / `ls` / log + transcript reads, plus one direct invocation of
   the read-only `claude-accounts --readout` dashboard and one deliberately-failing `bash` invocation
   of the same script to reproduce the finder's brief correction.

---

## 4. Open questions for whoever synthesises this wave

1. **The one number the operator needs is 26, and it should be stated as a threshold, not a band.**
   Below ~26 resident panes hardware binds; above it, quota does. The current ceiling is 15. Every
   "break the ceiling" proposal in this wave should be scored against 26, because a proposal that
   reaches 40 panes lands 1.53× over the sustainable weekly budget and converts a capacity win into
   an earlier wall — which is the finder's own claim 5, now with a crossover attached.
2. **Does an agent process ever acquire `.oauth_refresh.lock`?** If yes, Agent-Teams fan-out is a
   *logout* risk concentrator, not merely a quota concentrator, and that reorders the recommendation
   away from wide waves on one account far more sharply than quota alone does. Test: `fs_usage -w -f
   filesys | grep oauth_refresh` on one account across a known expiry instant, with a teammate wave
   live.
3. ~~**Two repo documents give opposite advice on context size and neither cites the other.**~~
   ✅ **CLOSED 2026-08-24** (class A, backlog `564d151b76e5`).
   `scaling-bottlenecks-2026-08-09.md:36,150` ("68% of quota cost is cache-read ⇒ halving context ≈
   +50% capacity", carried into standing policy) vs `exchange-rate.md:45,223` ("cache-READ is ≤1/750
   of an output token… it authorises MORE context"). ~~One of them is live guidance and wrong. This
   needs a filed decision, not another measurement.~~ **Ruled: the measured rate governs.** Struck at
   both sites and the two docs now cite each other; ruling + arithmetic in
   `scaling-bottlenecks-2026-08-09.md` **§2a**. It survives §C6's correct *bound-not-a-point* caveat
   on the cache-read coefficient, because the 68% premise fails under the API-list hypothesis too
   (~28%), so the lever is worth 0% to ≤+16% under either fit. **Propagation completed 2026-08-27:**
   the same premise had also reached the `jcode-due-diligence-2026-08-11` wave (its C6 verdict, rank-1
   lever L7, and L6's eviction pricing) and axis `07-accounts-api.md` §4/§6.4 — the origin of the
   composition itself — none of which were in the 2026-08-24 commit's file set. All are now struck.
4. **The finder's `RMSE=1.73` and its published 17.7 pp residual cannot both be true** (§C5).
   Whichever way that resolves, the 5-hour exchange rate should be published with an interval and a
   condition number, and the repo should pick one of the two competing fits (the `USAGE_TELEMETRY_100P`
   plan currently quotes the older one).
5. **Nothing in this wave owns the two already-routable non-Claude backends.** I confirm the finder's
   §4 Q4 from the same rendered table: Codex CLI and Pi·Codex are `✅ routable` on a ChatGPT Plus plan
   and consume neither a Claude pane-slot nor a Claude meter. They are the only unit in this entire
   wave that breaks *both* ceilings, and the wave's decomposition has no axis pointed at them.
