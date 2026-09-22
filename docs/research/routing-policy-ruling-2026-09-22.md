# Account-routing policy — the ruling (2026-09-22)

Frontier-tier judgment session (Fable 5.1, xhigh), fired by claude-infrastructure-502 to settle
two operator asks in one document and stop the routing system from being re-tuned every time
one account looks fuller than another:

1. "how come our self recycle didnt self recycle into account 3"
2. "its all systems go on getting account 3 usage to 100% by weekly limit reset. do we need to
   fine-tune/tweak our self recycle auto router?"

Every number below was re-derived from disk between 06:15Z and 06:45Z on 2026-09-22 and carries
the command that re-derives it. The board is a 90 s cache and the concurrency census moves
every 3 min, so **re-run, never re-quote**. Design record: `docs/plans/ACCOUNT_ROUTING_V2.md`
§13-§15.

---

## 1 · THE RULING

**The recycle/route policy is correct as built. Change no routing constant — not `REPICK_RATIO`
(4.0), not `KMAX` (8), not `URGENCY_EXP` (2), not the exclusion order — and do not tune anything
toward next3. Conviction: 92%.** The recycle the operator asked about did re-pick: it moved pane
502 **off** next3 onto next4, because next3 carried 26 working sessions plus phantoms against an
active cap of 8 (§2). That was the right move, and it remains right: next3 will reach 100% before
its 07:00 reset on the sessions already on it, under every burn pace measured in the last six
hours (§3), while next4 and next2 hold ~90 pp that die at their own resets. Putting more onto
next3 cannot fill it faster — the box admits at most 8 sessions mid-turn fleet-wide — it can only
bring next3's wall forward and strand the quota those sessions would have burned elsewhere. The
two objectives the brief poses as a conflict, headroom-with-urgency and strand minimisation, are
the same objective here and both say the same thing. **The ONE change is not a policy knob. It is
the instrument that makes the policy execute:** `KWORK_BUDGET_S` (the working-session walk's time
budget, `bin/claude-accounts:654`) from 5.0 to 15.0 s. Today that walk fails its budget on 46% of
sweeps, and on every such sweep the active-concurrency gate silently disappears and the router
itself names next3 first by 25× — the router is oscillating on its own, every three minutes, on an
instrument outage rather than on load (§4). Conviction on this change: 90%.

---

## 2 · Why the recycle did not move to next3 — the brief's mechanism read, corrected

The brief's read — *"this pane is on next4 … ratio 1.07 against a threshold of 4, so the pane
stayed on next4 BY DESIGN"* — is right about the code and wrong about the event. The pane was on
**next3** before the recycle. Three stores agree:

| evidence | reads | re-derive |
|---|---|---|
| predecessor transcript | `62f822da-…` lives under `~/.claude-tertiary/projects/` = next3 (mtime 06:19:53Z, the recycle's exit) | `find ~/.claude*/projects -maxdepth 2 -name '62f822da-*.jsonl'` |
| assignment ledger | `06:19:41Z acct=next4 src=recycle-repick` — `recycle_repick()` charges only after `[ "$new" = "$cur" ] && return`, so `cur` ≠ next4 | `grep recycle-repick ~/.claude/logs/account-assignments.jsonl \| tail -1` |
| handoff ledger | `06:19:49Z recycle-intent target_pane=502 account=next4` · `06:20:12Z recycle-engaged prev_sid=62f822da…` | `grep '"gate":"recycle"' ~/.claude/logs/handoffs.jsonl \| tail -2` |

So the question is not "why did the pressure ratio not move it" (the 1.07 was computed *after*
the move, between the two accounts that were left) but "why did the exclusion move it off next3".
The answer is the first arm of `recycle_repick()` (`scripts/handoff-fire.sh:9427-9600`): the
current account was named in `--rank general`'s stderr exclusion map, reason `kmax-concurrency`.
The sweep serving that call (06:17Z) measured next3 at **k_work = 26** against `KMAX = 8`
(`_excluded`, `bin/claude-accounts:3477`) — not 7, the pane count the board shows; `k_work` counts
transcripts written in the last 10 min including subagents (landed f30cab163, 2026-09-04).

```
python3 -c "
import json,datetime as dt
for l in open('$HOME/.claude/logs/account-utilization.jsonl'):
    r=json.loads(l)
    if r.get('acct')=='next3' and r['ts']>='2026-09-22T05:50' and r['ts']<='2026-09-22T06:35':
        print(r['ts'][11:16],'k_work=',r.get('k_work'),'panes=',r.get('k'))"
```

reads `05:56 21 · 06:03 None · 06:11 None · 06:17 26 · 06:22 20 · 06:29 11` (plus a fresh sweep at
06:3x reading 8). The mechanism in the brief is confirmed; only its subject was misidentified.
**The recycle worked exactly as §14.1 shipped it, and moved a pane off the one account that was
over its cap.**

---

## 3 · The objective conflict — and why there is none today

**The general lane already IS strand minimisation.** `score_general` = `headroom / T² × SF × KF`
(`bin/claude-accounts:3488-3501`); §13 derived γ=2 from the operator's own sentence about
exhausting the soonest expiry. If next3 were eligible it would win every lane by a wide margin:

```
w_rem/T²  = 0.10 / (5.3−0.5)²  = 0.0043      (weekly 91%, reset 5.3 h, MARGIN_H 0.5)
× SF      = (0.85 − 0.68)/0.35 = 0.49         (5h 48% + 19.7 %/h × 1 h lookahead)
× KF      = 1 − 11/40          = 0.73         (the census path, cap 40)   → 0.0015
next4     = 0.92 / 121.8² × …  ≈ 0.00006                                  → 25×
```

Measured live on the census path at 06:33Z: `next3 0.001467 · next4 0.000059 · next2 0.000058`
(method warning below). So the SCORE is not what keeps new sessions off next3 — the
active-concurrency gate is, and the whole question reduces to whether that gate is right.

**It is right, for three independent reasons, each measured today.**

1. **next3 fills without help.** Weekly 91% at 06:42Z, reset in 5.3 h. Measured burn over the
   last 3 h: **3.32 pp/h** (80→90, 03:29-06:29Z); 6 h: 1.81; 12 h: 1.41; 24 h: 1.00; router EWMA
   2.09 pp/h. Wall ETA at each pace: 2.7 h / 5.0 h / 6.4 h — i.e. under every pace of the last
   six hours next3 hits 100% **before** its reset (by 20 min to 2.6 h); only the 12 h pace leaves
   1.5-2.5 pp. `wk_strand_pp = 0`, `burn_ratio = 0.94`. The operator's goal for next3 is already met
   by the sessions on it.
   ```
   claude-accounts --json | jq '.rows[]|select(.acct=="next3")|{weekly_pct,weekly_reset_h,burn_wk_ewma_ph,wk_strand_pp}'
   ```
2. **A session moved onto next3 is a session taken from an account that strands.** The box admits
   at most **8 sessions mid-turn fleet-wide** (`CC_ADMIT_ACTIVE_CEILING`,
   `scripts/lib/capacity-admit.sh:1347`; 6 in use at 06:21-06:24Z per `handoffs.jsonl`
   `gate=capacity`), and one account's throughput saturates in the 5-6 concurrent band
   (GH#62426, `docs/research/scaling-bottlenecks-2026-08-09/07-accounts-api.md:272`). Total burn
   is throughput-bound, so allocation is zero-sum: every slot on next3 (strand 0) is a slot not
   on next4 (49 pp dying) or next2 (39 pp dying). Under strand minimisation next3 must receive
   **nothing new** while at cap.
3. **The wall is real and long.** Accounts have sat at weekly 100% for 218 h in total in the
   utilisation series; next3's two episodes ran 24.4 h and 11.2 h. A session that walls is dead in
   place until reset; a recovery costs ~2.5 min automated + up to 15 min manual per session
   (`accounts.json` `_recovery` note, measured 2026-09-19).
   ```
   python3 -c "
   import json;runs={};cur={}
   for l in open('$HOME/.claude/logs/account-utilization.jsonl'):
       r=json.loads(l);a=r['acct']
       if (r.get('weekly_pct') or 0)>=100: cur[a]=cur.get(a,[r['ts'],r['ts']]);cur[a][1]=r['ts']
       elif a in cur: runs.setdefault(a,[]).append(cur.pop(a))
   print({a:len(v) for a,v in runs.items()})"
   ```

**Which objective the router should serve: strand minimisation — and it already does.** The
brief's premise that M7 serves "headroom" *against* strand is not the code: `headroom/T²` is the
strand objective, and `kmax-concurrency` is a physical throughput ceiling, not a preference. A
future session that re-opens this must bring one of: next3 stranding >5 pp at a reset while
excluded; or a measured per-account throughput above 8 concurrent working sessions.

**What is actually driving next3 to an early wall is not the router.** All three handoff-fires
that landed on next3 in the hour before the recycle (05:45:52, 06:20:13, 06:21:02 in the
assignment ledger, panes 500/506/507) were fired with an explicit `--account next3` — the
router never sees an explicit account (§14.1: *"an explicit --account/--launcher is the
operator's choice and is never second-guessed"*). The three desk launches onto next3 (05:55,
06:15, 06:16, `src=claude-launcher`) each read a sweep whose walk had timed out (§4).
```
grep -F 'fire-cf-resume-2026-09-22.txt' ~/.claude-tertiary/projects/*/7c8201f8-*.jsonl | grep -oF -- '--account next3' | wc -l   # 2
```
So "all systems go on account 3" is being executed by leads naming next3, and the router is the
one component saying no, correctly. **Read the instruction as "let the router fill it", i.e.
`--account auto`, not as "name it."**

**The `next` relogin (73 pp nowcast strand, the board's largest number).** It does not change
this ruling and does not by itself move the weekly number. The fleet is demand-bound today:
next4 and next2 hold 12 of their 16 active slots free (`k_eff` 1 and 3 after the 06:3x sweep),
and the box is at 6 of 8 mid-turn — a fourth account adds capacity nothing is filling. It is
still worth doing, for next week and for the desk lane's 5h-safe set, and it is already filed with
its command: backlog `8636b8f829fe` ("re-authenticate the 'next' Claude Max account"), run
`cc-relogin next` (no refresh token → phase-2 browser OAuth, identity ichris96+claude@hotmail.com,
Dia profile "Personaly"). Ranking: **fired demand onto next4/next2 > relogin next > any router
change (≤ 0).**

---

## 4 · The ONE change — `KWORK_BUDGET_S` 5.0 → 15.0

| | |
|---|---|
| knob | `KWORK_BUDGET_S` — code default `bin/claude-accounts:654`; SSOT key `router.KWORK_BUDGET_S` in `~/.claude/accounts.json` (absent today, so the default applies); env `CC_ROUTE_KWORK_BUDGET_S` |
| current → proposed | `5.0` → `15.0` |
| what it governs | how long `working_concurrency()` (`:676`) may walk `projects/*/` before returning `None`, at which point `k_src` flips from `work` to `panes`, `k_cap` from 8 to 40, and the active gate is gone for that sweep (`k_cap`, `:2175`; `_excluded`, `:3477`) |
| policy touched | none — no score, threshold, cap or exclusion changes; `--route`/`--rank` contracts unchanged |

**The defect, measured.** Over the last 24 h the walk timed out on **101 of 220** utilisation
samples (46%) and logged **220** `k_work UNMEASURED` events; in the 05:40-06:15Z hour alone,
nine. The walk is not slow — foreground it stats 4,269 transcripts across 3,706 dirs in
**1.21 s** — it is starved: the only sweeper (`com.claude.accounts-keepwarm`, `StartInterval 180`,
`ProcessType Background`) runs in the band `taskpolicy -c background` reproduces, where the same
walk measured **5.63 / 8.30 / 11.29 s** — every sample over the 5 s budget. The scanned-at-timeout
distribution says the same: p25 662 · p50 1,392 · p75 2,259 of 3,026 dirs.
```
grep -c "$(date -u +%F).*k_work UNMEASURED" ~/.claude/logs/claude-accounts.log
grep 'k_work UNMEASURED' ~/.claude/logs/claude-accounts.log | grep -o 'after [0-9]*' | awk '{print $2}' | sort -n | awk '{a[NR]=$1}END{print a[int(NR/4)],a[int(NR/2)],a[int(NR*3/4)]}'
for i in 1 2 3; do taskpolicy -c background python3 /tmp/rp-walk.py; done   # the walk under the sweeper's band
```

**What it would have done today.** Rate-linear, a 15 s budget completes any walk that reached
≥1,009 dirs at 5 s: **131 of 220** timeouts (60%) → unmeasured ≈ 46% → ≈ 18%. Honest limit: in
the loaded 05:40-06:15Z hour the nine timeouts scanned 34-1,291 dirs and only ONE would have
completed — this change halves the flicker on an ordinary day and does not touch the extreme
starvation tail (min 21 dirs in 5 s). It would not have retro-prevented this morning's three desk
launches; it would have prevented the router naming next3 for ~60% of the windows in which it did.

**Why 15 and not 20 or 30.** The recycle's `--rank` call is bounded by `perl -e 'alarm 25'`
(`scripts/handoff-fire.sh:9482`), and a caller with a >90 s cache sweeps inline. The walk runs in
a thread beside the four account probes (`:1746`), so sweep ≈ max(probes ≈ 3-5 s, walk budget):
15 keeps a ≥10 s margin under the alarm; 20 would recover 71% at a 5 s margin; 30 would trip the
alarm on a starved box and turn every loaded-hour recycle into a silent no-repick. 15 is the
largest value that cannot regress the path §14.1 built.

**What it breaks.** Nothing in policy. Cost: up to +10 s on sweeps that were already timing out,
on the keepwarm path (180 s period) and on inline sweeps; `--max-wait 0` cache readers (the
launcher, `claude-launcher.zsh:59`) never reach the walk. Tests pass `budget_s=5.0` explicitly
(`tests/claude-accounts-core.bats:115,122`) and do not pin the default. Update the budget note in
`working_concurrency`'s docstring (`:697-706`, which sized 5 s against the FOREGROUND distribution)
and the `:1743` comment. Same knob, same argument as W1.7's 2→5 raise: *"the number was sized
against the wrong distribution."* Kill/override: `CC_ROUTE_KWORK_BUDGET_S`.

**Residual, named so it is not re-discovered as a surprise.** The tail (walks reaching <500 dirs
in 5 s) is the sweeper's QoS band, not its budget. If the unmeasured fraction stays above 30% after
this lands, the next lever is the plist's `ProcessType` — a launchd edit, operator-owned (c10
class) — never a router constant.

---

## 5 · What NOT to change — for the session that arrives in six weeks with the same itch

Each row was priced against TODAY's numbers. Bring new numbers or leave it alone.

| the itch | what it would do today | why not |
|---|---|---|
| **lower `REPICK_RATIO` (4.0)** | the two routable accounts sit at 0.000054 / 0.000040 = **1.35×**; a threshold under that moves panes between next4 and next2 on jitter and back | §14's spread for a real pile-up was 80-130×; the threshold lives in the router's SSOT (`:1967`) precisely so no caller re-authors it — do not move it into `handoff-fire.sh` either |
| **raise `KMAX` (8), or exempt an account "under quota" from `kmax-concurrency`** | next3 becomes eligible at **25×** everything; every auto fire and every recycle in the fleet (ratio ≫ 4) lands on it until phantoms (15 min TTL) push `k_eff` past the new cap — 2026-08-10 replayed (36 sessions on one account) | throughput is the ceiling (box 8 mid-turn; per-account band 5-6); more sessions on next3 add no burn, they remove it from stranding accounts. `KMAX` is the ACTIVE cap by §15 and `cc-wave-plan` reads the same integer |
| **`URGENCY_EXP` 2 → 1** | does not decide today's case: next3 leads under γ=1 too (0.021 vs 0.0076) if eligible; the cap decides, not γ | §13's frozen snapshot is a fixture that proves γ=1 inverts the 2026-08-10 case |
| **carry a stale `k_work` through a grace when the walk times out** (considered here, killed by measurement) | P(still ≥ KMAX 10 min after it was) = **44%** (n=64); 15 min: 21%; 30 min: 20% — a coin flip at the cache grace, wrong past it | the at-cap verdict is short-lived; inheriting it is inheriting noise. The pane census inherits well (`inherit_k`) because residency IS long-lived |
| **charge the pane census against `KMAX` on a timed-out walk** (revert §15's split) | today it would exclude next3 correctly (9 panes) and refuse nothing wrongly (13 panes fleet-wide) | §15's objection stands at the design point (32 residents fleet-wide → the 33rd refused) and the 2026-08-10 shape (28 idle panes, 0 working) is exactly the case the split fixed. Fix the instrument's availability, not its fallback |
| **re-pick Fable or desk panes on recycle** (R14A-2) | untouched by this incident — every session in question was general-lane | Fable rides a separate entitlement; the desk lane has its own hysteresis |
| **fire `--account next3` to "get it to 100%"** | three such fires this hour are what will wall next3 ~2.6 h early at the 3 h pace, with panes 500/506/507 dead until 07:00 | the router cannot override an explicit account and must not; the instruction is satisfied by `--account auto` |
| **move the sweeper out of `ProcessType Background`** | would end the starvation tail (§4 residual) | operator-owned launchd edit; do it only on the falsifier below, never pre-emptively — it trades foreground latency for a census |

**The general rule this incident teaches**, so the next itch is tested before it is acted on:
*when the router's answer looks wrong, first read `k_src=` on the route-meta line.* If it says
`panes` or `panes-stale`, the answer was produced without the active gate and is not the
policy's answer at all. `claude-accounts --rank general 2>&1 | grep -o 'k_src=[a-z-]*'`.

**Method warning, paid for here:** `CC_ROUTE_KWORK=off claude-accounts --rank general` is not a
read-only probe — when the cache is past its TTL it SWEEPS under the kill switch and writes a
`k_work`-less cache that every consumer then reads for up to 180 s. At 06:33Z that handed next3
to the fleet's routing for one keepwarm period. Probe the census path by arithmetic over `--json`
(§3), or restore with `claude-accounts --readout --fresh` immediately after.

---

## 6 · Falsifiers — what retracts each claim

| claim | retracted by | re-derive |
|---|---|---|
| the recycle moved 502 off next3 by exclusion, not by ratio | a `recycle-repick` ledger row whose predecessor transcript is NOT under `~/.claude-tertiary`, or route-meta at the same minute reading `k_src=work` with next3 absent from the exclusion map | the three commands in §2 |
| next3 fills before reset on its current load | next3 reading < 97% at its 07:00 reset (12:00Z) with no session on it having walled | `claude-accounts --json \| jq '.rows[]\|select(.acct=="next3")\|.weekly_pct'` at 11:55Z; `grep -c 'weekly limit' ` in the transcripts of panes 500/506/507 |
| burn is throughput-bound (more sessions on one account ≠ more burn) | a per-account weekly pp/h that keeps rising past 8 working sessions — plot `burn_wk_ewma_ph` against `k_work` over a week and find a positive slope beyond 8 | `python3` over `account-utilization.jsonl`, bucket by `k_work` |
| the fleet is demand-bound, so relogin ≤ demand | next4 AND next2 both at `k_eff ≥ 6` with fires being refused `kmax-concurrency` while `next` still strands | `claude-accounts --route general 2>&1 \| head -1` reading both in the exclusion map |
| the walk is starved by band, not by size | the walk under `taskpolicy -c background` completing in <5 s on three consecutive runs on a box at ≥5 mid-turn | `for i in 1 2 3; do taskpolicy -c background python3 /tmp/rp-walk.py; done` |
| `KWORK_BUDGET_S=15` recovers ~60% of timeouts | post-change unmeasured fraction still >30% over 24 h — then the lever is the plist band, and the row above says so | the first §4 command, 24 h after landing |
| the stale-`k_work` grace is worthless | P(≥KMAX at +10 min \| ≥KMAX) rising above 85% over a 14-day window | the persistence script in this session's transcript (lags 5-60 min, pooled) |
| 15 is under the recycle alarm | a `recycle_repick` stderr line absent on a recycle whose route call took >25 s (perl alarm, exit empty) after the change | `grep -c 'handoff-repick' ~/.claude/logs/handoffs.jsonl` before/after; `k_stale_s`/`kwork_to=` on route-meta |
| no policy constant needs to move | next3 stranding ≥5 pp at a reset while excluded for `kmax-concurrency` on a MEASURED (`k_src=work`) sweep — that is the one observation that reopens `KMAX` | `--rank general 2>&1` route-meta at the reset, beside the strand line |

Conviction summary: ruling 92% · the one change 90% · "next3 fills unaided" 95% · "relogin does
not change the ruling" 93% · the explicit-fire finding 97% (three transcripts, string-matched).
