# U05 — the capacity gate on the limit-recovery path

Repo root `/Users/chrisren/Development/claude-infrastructure` (all paths below are relative to it).
Subject: `scripts/lib/capacity-admit.sh` (963 lines, read in full), `scripts/lib/spawn-presence.sh`
(514), `scripts/limit-recover/lr-fleet.sh` (514), `scripts/limit-recover/lr-fire-resume.sh`,
`tests/capacity-admit.bats` (302).

---

## 0. THE ONE-LINE FINDING

`handoff-fire.sh:8270` **exempts a recycle from the capacity gate** — `if [ "$RECYCLE" = 0 ]; then
capacity_gate || exit 9; fi` — because (`:5620-5622`) *"A RECYCLE is EXEMPT: it REPLACES a session
(net-zero panes), so gating it would strand the very handoff that SHEDS load — the gate would
amplify the contention it exists to relieve."* **The in-place limit recovery IS that recycle**
(`lr-handoff.sh:619` `RCY_ARGS=(--recycle --transplanted-source --resume-launcher "$LAUNCHER" …)`),
so handoff-fire correctly does not gate it — and then the relaunch it types, `bash $LAUNCHER` →
`lr-fire-resume.sh:324` `cc_capacity_admit lr-fire-resume "resume $SID on $ACCT"`, **re-gates the
same net-zero operation with all four terms ON, the load term included.** One net-zero operation,
two gates, and the only one that fires is the one the exemption's author did not know existed. That
produced 4 husks today.

---

## 1. THE FOUR TERMS + THE RESERVE, DEFAULTS, THE BOUND, AND WHO CHARGES

### 1.1 Terms, in evaluation order (`capacity-admit.sh:547-885`)

| # | term | switch (default) | threshold var (default) | instrument | line |
|---|---|---|---|---|---|
| 1 | `load` | `CC_ADMIT_LOAD_TERM` (**on**) | `CC_ADMIT_MAX_LOAD_PER_CORE` ← `CC_HW_DEFAULT_MAX_LOAD_PER_CORE=2.0` | `sysctl -n vm.loadavg` ÷ `hw.ncpu` | `:636-646`, default `:170` |
| 2 | `headroom` | `CC_ADMIT_HEADROOM_TERM` (**on**) | `CC_ADMIT_MIN_HEADROOM_GB` ← `CC_HW_DEFAULT_MIN_HEADROOM_GB=4` | `vm_stat` free+speculative+inactive+purgeable | `:648-698`, probe `:209-224` |
| 3 | `segments` | `CC_ADMIT_SEGMENT_TERM` (**on**) | `CC_ADMIT_MAX_SEGMENT_PCT` (**50**, self-described PROVISIONAL `:721-727`) | `vm.compressor_segment_limit` / `_buffer_size` / `vm.swapusage` / `Pages occupied by compressor` | `:700-757`, probe `:294-327` |
| 4 | `active` | `CC_ADMIT_ACTIVE_TERM` (**on**) | `CC_ADMIT_ACTIVE_CEILING` (**8**) | `cc_sp_active` (beat `kind:"prompt"` × live `(pid,lstart)`) | `:759-836` |

Reserve terms, evaluated LAST and only over an otherwise-admitting box (`:838-885`), and only when
`_cc_admit_presence_read` (`:491-506`) resolved a presence of `self|present|absent|unknown`:

| term | fires when | constant | line |
|---|---|---|---|
| `reserve-headroom` | `head_gb < floor + cc_sp_reserve_gb(presence)` | from `spawn-presence.sh` | `:845-851` |
| `reserve-active` | presence is **`present` only**, `act + 1 > ceiling − CC_ADMIT_ACTIVE_RESERVE` (**1**) | 1 | `:862-872` |
| `reserve-slots` | `cc_sp_trees + 1 > CC_ADMIT_SESSION_CEILING (54) − cc_sp_reserve_slots` | 54 | `:874-884` |

Whole-gate kill switch `CC_ADMIT_GATE=off` (`:560-565`, recorded as `basis:"gate-off"`, never silent).
Bound `CC_ADMIT_BUDGET` default **3** (`:583`).

### 1.2 The budget-release mechanism

`cc_hw_budget_charge()` — `capacity-admit.sh:381-395` — is **pure mechanism, shared with
`capacity_gate()`** (header `:355-379`):

```
rc 0  = charged; caller may still REFUSE (budget remains)
rc 10 = RELEASED; budget spent and reset — caller must ADMIT and page
rc 1  = UNTRACKABLE (no state file / bad budget) — caller must ADMIT
```

It increments the integer in the state file, and at `n > budget` truncates the file and returns 10.
Policy lives in `_cc_admit_spend()` (`:923-963`): rc 10 → `basis:"budget-expired"` + `_cc_admit_page`
(`:535-542`, `cc-notify --page`); otherwise `basis:"measured"`, `term:<which>`, rc 9.

**State file keying is the first defect.** `_cc_admit_state_file()` (`:509-514`) keys on `<caller>`
ALONE: `${CC_ADMIT_STATE_DIR:-$HOME/.claude/autonomy/capacity-admit}/<caller>.refusals`. Live:

```
ls -la ~/.claude/autonomy/capacity-admit/
 =>  agent-tool.refusals  boot-resume-launch.refusals  cc-resume-layout.refusals
     lr-fire-resume.refusals  reso-resume-one.refusals
```

Five files for the whole box. Every concurrent recovery of every session shares **one** counter, and
any admit anywhere resets it (`_cc_admit_reset`, `:516`). Measured consequence today, §3.3 below.

### 1.3 Charge vs probe — the full caller census

`cc_capacity_probe()` (`:526-533`) sets `_CC_ADMIT_PROBE=1`, calls `cc_capacity_admit`, restores.
The flag makes `_cc_admit_reset` a no-op (`:516`) and makes `_cc_admit_spend` return 9 with
`basis:"probe"` **without touching the budget file, without paging, without releasing** (`:925-931`).

| caller id | file:line | charges? | load term |
|---|---|---|---|
| `lr-fleet` | `lr-fleet.sh:286` (`cc_capacity_probe lr-fleet "$1"`) | **NO — probe** | **ON** |
| `lr-fire-resume` | `lr-fire-resume.sh:324` | yes | **ON** |
| `boot-resume-launch` | `boot-resume-launch.sh:279` | yes | **ON** |
| `reso-resume-one` | `bin/reso-resume-one:137` | yes | **ON** |
| `cc-resume-layout` | `bin/cc-resume-layout.sh:284` | yes | **ON** |
| `agent-tool` | `hooks/agent-teams-enforce.sh:229-230` | yes | **OFF** (explicit `CC_ADMIT_LOAD_TERM=off`) |
| (operator `/handoff`) `capacity_gate()` | `handoff-fire.sh:5888`, called `:8270` | yes, own budget (default 1) | **OFF** (`:6075` `${CC_FIRE_LOAD_TERM:-off}`) |

`cc_capacity_probe` has exactly **one** caller in the tree: `lr-fleet.sh:286`.

---

## 2. THE RETRACTION OF THE LOAD TERM — AND WHERE IT IS STILL ON

### 2.1 The three quotes, verbatim

`scripts/lib/capacity-admit.sh:16-27`:

```
#   §8.5.2 retraction  discard "1-min loadavg/ncpu as the saturation proxy with a fixed 2.0 ceiling
#                      and NO SUSTAINED-SATURATION ESCAPE".
#   §12.2 live proof   2026-07-31 12:13, load 21.55 on 10 cores = 2.16/core — already over the
#                      ceiling — with 13 sessions, 24 GB free and 0 B compressor. A perfectly
#                      healthy box. The existing gate bound to all seven paths refuses EVERY spawn
#                      at that moment, including every recovery path, and §8.5.7 shows it cannot
#                      recover: iTerm2 + WindowServer + XProtect are ~2.4 UNSHEDDABLE cores, so
#                      refusing spawns cannot lower the number the gate reads.
```

`:134-147` — the ceiling itself:

```
# 🚨 2.0/core WAS NEVER DERIVED, AND NO DERIVATION IS REACHABLE ON THIS AXIS. …
# The origin commit … measured its motivating incident at 2.72/core and picked 2.0 with no stated
# rule, so the shipped ceiling sits BELOW the only incident that produced it.
# … THE SURVIVED POPULATION CONTAINS THE FATAL VALUE — fatal 2026-08-05 at 2.53/core against 13
# consecutive survived samples spanning 2.92-5.98/core …
```

`:149-160` — the input, not the number:

```
# 🚨 THIS IS NOT A CASE TO RAISE THE NUMBER. `fix(fire-gate): load1 does not move with the spawn it
# was gating` (f944d6e3, 2026-08-20, ancestor of trunk) established the stronger fact: an additional
# RESIDENT session moves the 1-min runnable count by ~0, so NO value of this literal can make the
# term correct — the INPUT is wrong, not the number. The load term therefore DEFAULTS OFF in
# capacity_gate() (CC_FIRE_LOAD_TERM) and has been off on the Agent-tool path since Wave D;
# `segments` and `active` carry its intent because they DO move with the spawn. … It still binds
# only where `cc_capacity_admit` leaves the term on: the two unattended recovery callers
# (scripts/boot-resume-launch.sh, scripts/limit-recover/lr-fire-resume.sh), DELIBERATELY — see the
# load-term block below, which prices that imprecision at a delayed resume …
```

### 2.2 Where it is still ON — and the inversion

Default is ON: `capacity-admit.sh:555`, `:601`, `:636`, `:889`, `:903`, `:905` all read
`${CC_ADMIT_LOAD_TERM:-on}`. The only place it is turned off is `hooks/agent-teams-enforce.sh:229`.

So today's state of the box:

- Operator's own `/handoff` fire: load term **OFF** by default (`handoff-fire.sh:6075`).
- Highest-volume spawn surface, the Agent tool: **OFF** (`agent-teams-enforce.sh:229`).
- Every **unattended recovery** path — `lr-fire-resume`, `boot-resume-launch`, `reso-resume-one`,
  `cc-resume-layout` — and the fleet probe that fronts one of them: **ON**.

**The retracted term survives on exactly the paths whose own header says a standing refusal is an
outage.** `:157-160` calls this DELIBERATE and prices it at "a delayed resume". §3 measures the
actual price and it is not a delay; it is a husk.

Also note `lr-fleet.sh:286` is not in that header's list at all. The fleet probe was added later
(`:519-533`, "LIMIT_RECOVER_100P, 2026-09-09") and inherited `on` by default. The sentence *"it
still binds only where … the two unattended recovery callers"* has been stale since that landing —
there are five callers with the term on, not two.

---

## 3. TODAY, MEASURED — THE PROBE/LAUNCHER SPLIT

Instrument: `~/.claude/autonomy/idl.jsonl`, 84,791 rows spanning `2026-09-17T22:21:23Z ..
2026-09-19T17:55:00Z`; 127 of them `gate=="capacity-admit"`.

```
jq -rs 'map(select(.gate=="capacity-admit"))|group_by([.caller,.verdict,(.term//"-")])
       |map({k:(.[0]|[.caller,.verdict,(.term//"-")]|join("|")),n:length})|sort_by(-.n)
       |.[]|"\(.n)\t\(.k)"' ~/.claude/autonomy/idl.jsonl
 =>  35  agent-tool|admit|-
     31  lr-fleet|refuse|load
     14  boot-resume-launch|admit|-
     14  boot-resume-launch|refuse|segments
     10  lr-fire-resume|refuse|load
      5  agent-tool|refuse|active
      5  lr-fleet|admit|-
      4  lr-fire-resume|admit|-
      4  lr-fleet|refuse|reserve-active
      3  agent-tool|refuse|reserve-active
      1  agent-tool|admit|active
      1  lr-fire-resume|admit|load
```

**101 of the 127 rows (79.5%) are today's 50-minute limit recovery.** 41 of the 55 refusals in the
whole file are load-term refusals on the two limit-recovery callers.

### 3.1 Phase 1 — the 600 s park (the gate working as documented)

31 consecutive probe refusals, `2026-09-19T17:05:38Z → 17:15:48Z`, one every ~20.4 s
(`LR_FLEET_CAP_IVL_S:-20`, `lr-fleet.sh:283`), then `PARKED on capacity after 600s`
(`lr-fleet.sh:287`). Load per core walked **9.96 → 3.19**, never once below 2.0:

```
17:05:38  load 99.60 on 10 cores = 9.96/core > ceiling 2.0/core (probe — budget untouched)
…
17:15:48  load 31.92 on 10 cores = 3.19/core > ceiling 2.0/core (probe — budget untouched)
```

Result row: `~/.reso/limit-recover/fleet/one-20260919T170450Z/results.tsv` →
`d02d8feb… 112 112 next4 next2 parked capacity 2026-09-19T17:15:48Z`.

**658 s of wall clock, zero sessions recovered, budget untouched** (by design — `:925-931`). The
`sleep 20` loop is a FOREGROUND sleep in the invoking session's Bash tool call: this is the 10.1-min
tool call in the lead's transcript.

### 3.2 Phase 2 — the active/reserve term, on husks

Run `one-20260919T171706Z` (no results row — abandoned). Load term now off; the probe refused 4× on
a different term:

```
17:17:43  reserve-active  7 sessions mid-turn + 1 > active ceiling 8 − operator reserve 1 = 7 (operator present)
17:18:04  (same)   17:18:25  (same)   17:18:47  (same)
17:19:45  ADMIT headroom-only — load term off · reclaimable 29.84GB (floor 4GB) · segments 3.50% of limit (ceiling 50%) · 4 sessions mid-turn (active ceiling 8)
```

Seven "mid-turn" sessions at 17:17:43, four at 17:19:45, after exactly ONE session was recovered.
See §4.

### 3.3 Phase 3 — the split, five times, with the exact gap measured

Every recovery run has the same shape: fleet probe ADMITS (load term off, because the env var was
set on `lr-fleet.sh`'s own process), then 11–16 s later the launcher — a **fresh process tree typed
into the pane's shell**, which never saw that variable — re-evaluates with the load term ON.

| fleet probe ADMIT | launcher verdict | gap | 2nd launcher verdict | run dir | outcome |
|---|---|---|---|---|---|
| 17:19:45 (4 mid-turn) | 17:19:59 **refusal 3 of 3** 2.86/core | 14 s | 17:20:48 **budget-expired → ADMIT + page** 2.72/core | `one-20260919T171910Z` | **RECOVERED** 17:21:05 |
| 17:22:03 (6 mid-turn) | 17:22:17 refusal **1** of 3, 2.57/core | 14 s | 17:23:07 refusal **2** of 3, 2.54/core | `one-20260919T172126Z` | **PARTIAL** 17:23:54 |
| 17:44:39 (5 mid-turn) | 17:44:55 refusal 1, 2.42/core | 16 s | 17:45:45 refusal 2, 2.51/core | `one-20260919T174403Z` | **PARTIAL** 17:46:35 |
| 17:49:36 (4 mid-turn) | 17:49:47 refusal 1, 2.05/core | 11 s | 17:50:37 refusal 2, 2.12/core | `one-20260919T174851Z` | **PARTIAL** 17:51:26 |
| 17:52:54 (2 mid-turn) | 17:53:06 refusal 1, 4.15/core | 12 s | 17:53:55 refusal 2, 6.73/core | `one-20260919T175207Z` | **PARTIAL** 17:54:45 |

### 3.4 THE MECHANISM NOBODY HAS WRITTEN DOWN: the bound is unreachable inside the watcher

`docs/research/limit-recover-capacity-park-2026-09-19.md` says the env override split one evaluation
into two disagreeing ones. True and incomplete. **The deeper defect is arithmetic, and it is
independent of the override:**

- `handoff-fire.sh:6811-6816` — the relaunch watcher types the launcher, waits `15 × sleep 3` = 45 s,
  and if still at a shell **retypes ONCE**, then waits another 45 s. `handoff-fire.sh:6879`:
  `"relaunch typed but no claude process appeared within 90s"`.
- So the watcher invokes `lr-fire-resume` **exactly 2 times**. Measured inter-refusal gap: 50 s
  (17:22:17→17:23:07), 50 s, 50 s, 49 s. Consistent with 45 s + type latency.
- `CC_ADMIT_BUDGET` default is **3** (`capacity-admit.sh:583`). The release fires on invocation
  **3**, at ≈ t+150 s.

**150 s > 90 s. The budget release is structurally unreachable inside the watcher's window.** This
is `docs/lessons/inner-bound-outer-bound-starves-the-tail.md` exactly: two individually-correct
bounds, one nested inside the other, the inner one sized larger than the outer.

The one RECOVERED run proves it from the other side: its FIRST launcher call logged `refusal **3** of
budget 3` — it inherited 2 charges from an earlier attempt on the shared `lr-fire-resume.refusals`
counter (§1.2) — so its second call released. **The only recovery that survived the gate did so
because a previous, unrelated invocation had pre-spent two thirds of the budget.** The release then
RESET the counter (`cc_hw_budget_charge:389`), which is why the very next run started at `refusal 1
of 3` and could not reach the release. The bound worked once, by accident, and disarmed itself for
the next four.

### 3.5 The load term refused a demonstrably healthy box, today

Run `one-20260919T175207Z`, the same instant, from the two gates:

```
17:52:54  lr-fleet ADMIT  reclaimable 33.33GB (floor 4GB) · segments 3.18% of limit (ceiling 50%) · 2 sessions mid-turn (active ceiling 8)
17:53:06  lr-fire-resume REFUSE  load 41.45 on 10 cores = 4.15/core > ceiling 2.0/core
17:53:55  lr-fire-resume REFUSE  load 67.31 on 10 cores = 6.73/core > ceiling 2.0/core
```

33 GB reclaimable, 3.18% of the compressor-segment limit, **2** sessions mid-turn against a ceiling
of 8 — and the load term refused. This is §12.2's measurement reproduced verbatim, 50 days later, on
the recovery path §12.2 was written about. Worse: load ROSE 41.45 → 67.31 between the two refusals,
driven by the recovery machinery itself plus a sibling `bats` suite. The term the gate is charging
against is one the refusal cannot lower — §8.5.7's unsheddable-cores argument, live.

### 3.6 The refusal is invisible where the operator looks

`lr-fire-resume.sh:325` prints `✗ $(cc_capacity_admit_reason)` to **the pane's own stderr**. It is
not in the fleet's capture:

```
grep -h -i 'capacity|refusal|admit|PARKED' ~/.reso/limit-recover/fleet/one-20260919T17*Z/*.stderr
 =>  4 × "!! relaunch typed but no claude process appeared within 90s — fallback comment typed into pane"
```

and `results.tsv` says only `transplanted but the relaunch did not verify — source is a tombstoned
husk`. **The cause was on disk 40 s earlier, in the IDL, and nothing joins the two.** That is the
whole of today's "fire-and-forget husk" complaint: the data exists, the join does not.

---

## 4. THE `active` TERM COUNTS LIMIT-KILLED HUSKS

### 4.1 What `cc_sp_active` counts (`spawn-presence.sh:298-390`)

One `jq -rs` over `${CC_BEAT_DIR:-$HOME/.claude/cc-beats}/*.json` (one file per sid, latest beat
only — `hooks/session-beat.sh:5-6,100,117`). Selects every record with:

```
.kind == "prompt" and (.pid|type) == "number" and ((.lstart // "")|tostring|length) > 0
```

then charges liveness with ONE `ps -o pid=,lstart= -p "$$,<pids>"` on identity `(pid, lstart)`
(`:386-390`), counting **distinct pids**. Existence gate: `max(.t)` must be within
`CC_BEAT_LIVE_MAX_S` (900 s) or rc 1.

`spawn-presence.sh:290-293` already names half the problem:

```
# LIVENESS IS CHARGED, and it is not fastidiousness: a session that DIES mid-turn leaves its
# `kind:"prompt"` beat on disk forever, so a census that counted beats alone would refuse a little
# more with every crash until the ceiling became unreachable …
```

**It does not name the other half.** A limit-killed session does not die. The turn dies; the TUI
lives. `hooks/session-beat.sh` writes `kind:"prompt"` at UserPromptSubmit and `kind:"stop"` at Stop
(`:57-62`); a turn that terminates in an API limit error leaves the `prompt` beat standing while
the `claude` process — the one `lr-fleet --locate` reports in its PID column — stays alive and
idle at the error. `(pid,lstart)` resolves, so the husk is counted **ACTIVE**, indefinitely.

Live corroboration of the beat shape (the two panes whose recoveries went PARTIAL):

```
cd ~/.claude/cc-beats && jq -r '"\(.kind) pid=\(.pid) pane=\(.pane) t=\(.t|todate)"' e442434c*.json 28f07827*.json
 =>  prompt pid=99916 pane=121 t=2026-09-19T17:59:53Z
     prompt pid=63305 pane=114 t=2026-09-19T17:58:24Z
ps -p 99916 ; ps -p 63305   =>  both DEAD
```

Two `kind:"prompt"` beats standing over dead pids — the exact record a mid-turn death leaves. The
liveness charge excludes them **now**; it did not exclude their live predecessors at 17:17:43, when
the probe read **7 sessions mid-turn** with 5 limit-blocked sessions in the census and refused 4
consecutive probes on `reserve-active`.

*Honest limit:* I could not re-measure the 17:17:43 pid set post hoc (the beat files are overwritten
in place). The mechanism is established from code; the 7→4 drop across one recovery is consistent
with it and is not by itself proof.

### 4.2 The second, worse property: the recovery is NET-ZERO and the term charges it as +1

`capacity-admit.sh:832` is the refusal predicate: `[ $(( act + 1 )) -gt "$act_ceiling" ]`. The `+1`
is the session about to be spawned. For an in-place recycle that `+1` is **wrong by construction** —
the pane's old session is `/exit`ed *before* the launcher runs, so the operation is net-zero, which
is precisely the reason `handoff-fire.sh:8270` does not gate a recycle at all. Today the term
counted the *dying* session as one of the 7 **and** charged the *replacement* as a +1: the same
session, double-counted, on both sides of a zero.

### 4.3 Cost, measured

```
cd ~/.claude/cc-beats && ls | wc -l                       => 3767
jq -rs '<the cc_sp_active selector>' *.json   cold: real 7.24s   warm: real 0.20s / 0.18s
jq -rs 'map(select(.kind=="prompt" and (.pid|type)=="number"))|map(.pid)|unique|length' *.json => 1694
```

1,694 pids go into one `ps -p` argv, and that list grows monotonically with every session the box
has ever run (liveness bounds the COUNT, not the QUERY). The header's "~13 ms on a 1,527-file
fixture" is warm-cache; a cold `cc_sp_active` is **7.2 s**, which matters for the operator's
"identify in <2 s" target.

---

## 5. THE PROPOSED POLICY

Design constraint, restated from `lr-fire-resume.sh:306-309`: *"a limit-recovery resume must be
delayable but never permanently blockable."* Today it is both permanently blockable (the release is
unreachable, §3.4) and silently destructive (park is skipped once the transplant has run, §3.3).

Four changes. **P1 and P2 are the fix; P3 and P4 are the fault-tolerance the operator asked for.**
They are independent — P1 alone removes 41 of today's 55 refusals; P2 alone removes the split.

### P1 — the load term goes OFF on the limit-recovery callers (C18-clean: a TERM SWITCH, never a ceiling)

This is not a new policy; it is applying the one already shipped on the operator's own path
(`handoff-fire.sh:6075` `${CC_FIRE_LOAD_TERM:-off}`) and on the Agent tool
(`agent-teams-enforce.sh:229`) to the callers the retraction's own argument covers most strongly.
`segments`, `active`, `headroom`, and all three reserve terms keep binding — the terms that
`capacity-admit.sh:152-154` says *"DO move with the spawn"*.

```diff
--- a/scripts/limit-recover/lr-fire-resume.sh
+++ b/scripts/limit-recover/lr-fire-resume.sh
@@ -324,1 +324,9 @@
-  if ! cc_capacity_admit lr-fire-resume "resume $SID on $ACCT"; then
+  # LOAD TERM OFF (2026-09-19). Not a weaker gate — the term whose INPUT is wrong
+  # (capacity-admit.sh:149-156: an additional RESIDENT session moves load1 by ~0, so no ceiling
+  # value can make it correct). It defaults OFF on the operator's own fire (handoff-fire.sh:6075)
+  # and on the Agent tool (agent-teams-enforce.sh:229); leaving it ON here put the retracted term
+  # on exactly the unattended path whose own header calls a standing refusal an outage.
+  # MEASURED 2026-09-19: 10 of 10 lr-fire-resume refusals were term=load; at 17:52:54 the box read
+  # 33.33GB reclaimable, 3.18% segments, 2 active — and this gate refused at 4.15/core.
+  # An explicit CC_ADMIT_LOAD_TERM=on restores the old behaviour verbatim, ceiling and all.
+  if ! CC_ADMIT_LOAD_TERM="${CC_ADMIT_LOAD_TERM:-off}" \
+       cc_capacity_admit lr-fire-resume "resume $SID on $ACCT"; then
```

```diff
--- a/scripts/limit-recover/lr-fleet.sh
+++ b/scripts/limit-recover/lr-fleet.sh
@@ -286,1 +286,3 @@
-    if cc_capacity_probe lr-fleet "$1"; then return 0; fi
+    # Same switch as the launcher it fronts (lr-fire-resume.sh:324) — the probe and the thing it
+    # is probing FOR must evaluate the same terms, or the probe is measuring another gate.
+    if CC_ADMIT_LOAD_TERM="${CC_ADMIT_LOAD_TERM:-off}" cc_capacity_probe lr-fleet "$1"; then return 0; fi
```

Apply the same two-line change at `scripts/boot-resume-launch.sh:279` (the other caller named in
`capacity-admit.sh:157-159`) — a boot storm measured at loadavg 346 (`capacity-admit.sh:44-46`) is
the reductio: the load term cannot admit anything there, ever, and only the 3-refusal release saves
it. Leave `bin/reso-resume-one` and `bin/cc-resume-layout.sh` for a separate decision; they are not
on this path.

Then **delete the now-false sentence** at `capacity-admit.sh:157-160` ("the two unattended recovery
callers") — there are five callers with the term on today, and after P1 there are two
(`reso-resume-one`, `cc-resume-layout`).

### P2 — one admission decision, redeemed once: the probe issues a TOKEN the launcher honours

P1 does not close the split. Even with identical terms, the probe and the launcher are **two
evaluations 11–16 s apart**, straddling a `/exit` + transplant + `kitty @ send-text` that the
recovery itself performs. The fix is to make it ONE decision, and the insertion point already
exists: `lr-handoff.sh:585-592` writes an `export` block into the generated `$LAUNCHER`.

```diff
--- a/scripts/lib/capacity-admit.sh
+++ b/scripts/lib/capacity-admit.sh
@@ after _cc_admit_state_file (:514)
+# ── THE ADMISSION TOKEN (2026-09-19) ────────────────────────────────────────────────────────────
+# handoff-fire.sh:8270 does not gate a RECYCLE at all, because ":5620 a recycle REPLACES a session
+# (net-zero panes), so gating it would strand the very handoff that SHEDS load". The in-place limit
+# recovery IS that recycle — and its relaunch is a SECOND process that re-gates it. A token makes
+# the probe's decision the ONE decision, without letting a probe widen admission: it is minted only
+# by a probe that ADMITTED, it is ONE-SHOT (unlinked on redemption), TTL-bounded, uid-checked, and
+# it names the sid it was issued for, so it cannot be replayed onto a different spawn.
+_cc_admit_token_redeem() { # → 0 redeemed (caller must ADMIT) / 1 no usable token
+  local t="${CC_ADMIT_TOKEN:-}" now age issued sid
+  [ -n "$t" ] && [ -f "$t" ] || return 1
+  [ -O "$t" ] || return 1
+  issued="$(awk -F'\t' 'NR==1{print $1}' "$t" 2>/dev/null)"; cc_hw_is_int "$issued" || return 1
+  sid="$(awk -F'\t' 'NR==1{print $2}' "$t" 2>/dev/null)"
+  now="$(date +%s)"; age=$(( now - issued ))
+  rm -f "$t" 2>/dev/null || true                       # ONE-SHOT, even when it turns out stale
+  [ "$age" -ge 0 ] && [ "$age" -le "${CC_ADMIT_TOKEN_TTL_S:-180}" ] || return 1
+  CC_ADMIT_TOKEN_AGE="$age"; CC_ADMIT_TOKEN_SID="$sid"; return 0
+}
+cc_capacity_token_mint() { # $1=path $2=sid — called ONLY on a probe ADMIT
+  local d; d="$(dirname "$1")"; mkdir -p "$d" 2>/dev/null || return 1
+  printf '%s\t%s\t%s\n' "$(date +%s)" "$2" "${CC_ADMIT_TERMS:-}" > "$1" 2>/dev/null || return 1
+  chmod 600 "$1" 2>/dev/null || true
+}
@@ in cc_capacity_admit, immediately after the CC_ADMIT_GATE=off branch (:565)
+  # A redeemed token is an ADMIT on the PROBE's measurement, recorded as such: basis `token`, with
+  # the age so a stale-admission window is greppable rather than invisible. Probes never redeem.
+  if [ "${_CC_ADMIT_PROBE:-0}" != 1 ] && _cc_admit_token_redeem; then
+    CC_ADMIT_REASON="capacity-admit: ADMIT (admission token, ${CC_ADMIT_TOKEN_AGE}s old, issued for ${CC_ADMIT_TOKEN_SID}) — one decision, redeemed once"
+    _cc_admit_emit admit token "$caller" "$what" \
+      "redeemed a probe admission ${CC_ADMIT_TOKEN_AGE}s old for ${CC_ADMIT_TOKEN_SID} (TTL ${CC_ADMIT_TOKEN_TTL_S:-180}s)"
+    _cc_admit_reset "$caller"; return 0
+  fi
```

`basis:"token"` is an EIGHTH value. `tests/capacity-admit-coverage.bats:336-347` requires
`capacity_gate`'s vocabulary to be a SUBSET of this one — adding here is the legal direction; adding
to `capacity_gate` would not be.

Fleet side (`lr-fleet.sh`): on a probe ADMIT, mint, and pass the path down.

```diff
@@ lr-fleet.sh:286
-    if CC_ADMIT_LOAD_TERM="${CC_ADMIT_LOAD_TERM:-off}" cc_capacity_probe lr-fleet "$1"; then return 0; fi
+    if CC_ADMIT_LOAD_TERM="${CC_ADMIT_LOAD_TERM:-off}" cc_capacity_probe lr-fleet "$1"; then
+      LF_ADMIT_TOKEN="${CC_ADMIT_STATE_DIR:-$HOME/.claude/autonomy/capacity-admit}/tokens/$2.token"
+      cc_capacity_token_mint "$LF_ADMIT_TOKEN" "$2" || LF_ADMIT_TOKEN=""
+      return 0
+    fi
@@ lf_one: pass it through
-  lf_capacity_wait "in-place recovery of ${sid:0:8} onto $target" || { … }
+  lf_capacity_wait "in-place recovery of ${sid:0:8} onto $target" "$sid" || { … }
   local args=(--sid "$sid" … --in-place)
+  [ -n "${LF_ADMIT_TOKEN:-}" ] && args+=(--admit-token "$LF_ADMIT_TOKEN")
```

and `lr-handoff.sh` writes it into the launcher's existing export block (`:585-592`), which is the
only channel that survives into the pane's fresh process tree — the exact failure
`docs/research/limit-recover-capacity-park-2026-09-19.md` diagnosed:

```diff
 cat > "$LAUNCHER" <<EOF
 #!/bin/bash
 export CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH="\${CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH:-1}"
+${ADMIT_TOKEN:+export CC_ADMIT_TOKEN=$(printf '%q' "$ADMIT_TOKEN")}
```

**Why this is safe and not a bypass.** The token is minted only by an evaluation that ADMITTED; it
is unlinked on first read whatever the verdict, so it grants at most ONE spawn per probe-admit; it
expires in 180 s; it is uid-checked; and a probe can never redeem one. It cannot make the gate
admit anything the gate did not already admit ≤180 s earlier for that sid.

### P3 — if the bound stays, it must fit inside the watcher

P1+P2 make this mostly moot, but it is the residual and it is one constant. Either:

- **(a)** `CC_ADMIT_BUDGET` for `lr-fire-resume` → **1** (matching `capacity_gate`'s own default of
  1, `capacity-admit.sh:373-375`), so the release lands on the watcher's SECOND invocation; or
- **(b)** raise the watcher, `handoff-fire.sh:6811-6816`, from `15×3` + one retype to `15×3` + **two**
  retypes = 3 invocations / 135 s.

(a) is one env default and changes nothing else; (b) touches the universal recycle watcher. **Take
(a).** And fix the key while there: `_cc_admit_state_file` (`:509-514`) should key
`<caller>[.<CC_ADMIT_BUDGET_KEY>]` so one recovery's release cannot reset another's counter (§3.4 —
the one success today ran on an inherited counter).

### P4 — the refusal must reach the fleet report (the operator's "identify it, don't abandon it")

The cause is already on disk 40 s before the verdict (§3.6); nothing reads it back.

```diff
--- a/scripts/limit-recover/lr-fleet.sh    (in lf_one, the rc-4 arm)
-    4) verdict="PARTIAL"; note="transplanted but the relaunch did not verify — source is a tombstoned husk; see $rdir/$sid.stderr" ;;
+    4) verdict="PARTIAL"
+       # WHY it did not verify is already on disk: capacity-admit files every launcher verdict to
+       # the IDL. Join it, so a husk is never reported without its cause (2026-09-19: 4 of 4
+       # PARTIALs were term=load refusals, invisible in this file and in every .stderr).
+       why="$(jq -rs --arg t0 "$T0_ISO" 'map(select(.gate=="capacity-admit" and .caller=="lr-fire-resume" and .ts>=$t0))
+                | last | if . == null then "" else "launcher \(.verdict) term=\(.term // "-") — \(.detail)" end' \
+              "${CC_ADMIT_IDL:-$HOME/.claude/autonomy/idl.jsonl}" 2>/dev/null)"
+       note="transplanted but the relaunch did not verify — source is a tombstoned husk${why:+; $why}; see $rdir/$sid.stderr" ;;
```

Companion, one line, same file: the PARKED branch (`:287`) already names the term; the `parked`
result row (`:320`) writes only the bare word `capacity` — widen it to
`"capacity: $(cc_capacity_admit_reason)"` so `--report` says which term, not that there was one.

### 5.5 The `active` term, for §4

Two options; **(i) is the smaller and strictly better one.**

**(i) Count the recycle as net-zero — mirror the exemption that already exists one layer up.**
`capacity-admit.sh:832` becomes:

```diff
-    elif [ $(( act + 1 )) -gt "$act_ceiling" ]; then
+    # NET-ZERO CALLERS. An in-place recycle /exits one session and starts one: the `+1` is the
+    # replacement, and the session it replaces is still in `act`. handoff-fire.sh:8270 does not gate
+    # a recycle AT ALL for this reason (:5620 "net-zero panes"); this term is the same operation,
+    # counted twice, on both sides of a zero. CC_ADMIT_NET_ZERO=1 says so explicitly.
+    elif [ $(( act + ( [ "${CC_ADMIT_NET_ZERO:-0}" = 1 ] && echo 0 || echo 1 ) )) -gt "$act_ceiling" ]; then
```

(written as an `if/else` assignment to a `delta` var rather than that inline `&&/||`, which is
unreadable and mis-evaluates under `set -e`) — and `lr-fleet.sh` / `lr-fire-resume.sh` set
`CC_ADMIT_NET_ZERO=1` on the in-place path only.

**(ii) Exclude limited husks from the census.** Cheaper to state, harder to make correct: a
`kind:"prompt"` beat whose transcript's last assistant record is an api-error is not mid-turn. But
`cc_sp_active` must stay at one `jq` + ≤2 `ps` (`spawn-presence.sh:294-297` — its biggest caller is
a PreToolUse hook holding a tool slot), and reading N transcripts violates that outright. A
BOUNDED form: have `hooks/session-beat.sh` (or the limit detector) stamp `kind:"limited"` when a
turn dies on an api error, and have `cc_sp_active` select `.kind=="prompt"` only — one field, no
extra I/O. **That is the right long-term fix and it is a separate unit of work**; (i) fixes the
recovery path today.

---

## 6. THE TESTS THAT WOULD PROVE IT

`tests/capacity-admit.bats` structure (`:26-72`): `setup()` fixtures `$HOME`,
`CC_ADMIT_STATE_DIR`, `CC_ADMIT_IDL`, `CC_ADMIT_NOTIFY_BIN` (a recorder writing `pages.txt`), pins
`CC_ADMIT_LOADAVG_OVERRIDE=1.0` / `CC_ADMIT_HEADROOM_OVERRIDE=64`, and — critically —
`CC_ADMIT_RESERVE_TERM=off`, because the reserve reads a live `ps` census and made 3 of 20 cases
flip on the desk's mood (`:48-60`). Helper `admit()` (`:65-68`) runs the gate in a fresh subshell and
**ends on `exit $rc`**, never on `cc_capacity_admit_reason`, whose own 0 masked every REFUSE (`:62-64`).
`idl_field()` (`:69-71`) is `jq -r "$1" "$CC_ADMIT_IDL"`. Real-instrument probes are the P-series
(`:277-302`), deliberately outside the override regime.

### T1 — the token is one-shot, TTL-bounded, and probe-inert (P2's red-proof)

```bash
@test "15 an admission token ADMITS once over a refusing box, then is gone" {
  export CC_ADMIT_LOADAVG_OVERRIDE=99              # the box REFUSES on load
  export CC_ADMIT_TOKEN="$BATS_TEST_TMPDIR/tok"
  printf '%s\t%s\t%s\n' "$(date +%s)" "sid-abc" "load,headroom" > "$CC_ADMIT_TOKEN"
  run admit c15 "in-place recycle"
  [ "$status" -eq 0 ]
  [ "$(idl_field 'select(.basis=="token")|.verdict')" = "admit" ]
  [[ "$(idl_field 'select(.basis=="token")|.detail')" == *"sid-abc"* ]]
  [ ! -f "$CC_ADMIT_TOKEN" ]                        # ONE-SHOT: unlinked on redemption
  run admit c15 "in-place recycle"                  # second call has no token left
  [ "$status" -eq 9 ]
  [ "$(idl_field 'select(.term=="load")|.verdict')" = "refuse" ]
}

@test "15b an EXPIRED token does not admit, and is still consumed" {
  export CC_ADMIT_LOADAVG_OVERRIDE=99 CC_ADMIT_TOKEN_TTL_S=60
  export CC_ADMIT_TOKEN="$BATS_TEST_TMPDIR/tok"
  printf '%s\t%s\t%s\n' "$(( $(date +%s) - 600 ))" "sid-abc" "load" > "$CC_ADMIT_TOKEN"
  run admit c15b "s"; [ "$status" -eq 9 ]; [ ! -f "$CC_ADMIT_TOKEN" ]
}

@test "15c a PROBE never redeems a token (it would spend the caller's admission)" {
  export CC_ADMIT_LOADAVG_OVERRIDE=99 CC_ADMIT_TOKEN="$BATS_TEST_TMPDIR/tok"
  printf '%s\t%s\t%s\n' "$(date +%s)" "sid-abc" "load" > "$CC_ADMIT_TOKEN"
  run bash -c '. "$1"; cc_capacity_probe c15c "s"' _ "$LIB"
  [ "$status" -eq 9 ]
  [ -f "$CC_ADMIT_TOKEN" ]                          # untouched — a probe charges nothing, ever
}
```

`15c` is the case that keeps P2 honest: without it the token turns `cc_capacity_probe`'s
never-spend contract (`capacity-admit.sh:519-524`, `docs/plans/LIMIT_RECOVER_100P.md` §4) into a
spend.

### T2 — THE BOUND MUST FIT ITS WATCHER (the defect of §3.4, made a standing assertion)

This is the test that would have caught today, and it belongs in
`tests/handoff-recycle-pane-survives.bats` or a new `tests/lr-relaunch-bound.bats` — **not** in
`capacity-admit.bats`, because the two constants live in different files and the whole defect is
that nobody compares them. A pure-arithmetic ratchet, no fixtures, no box state:

```bash
@test "the relaunch watcher makes at least CC_ADMIT_BUDGET+0 launcher attempts" {
  # handoff-fire.sh:6811-6816 types the launcher, waits 15×3s, retypes ONCE, waits 15×3s => 2
  # attempts / 90s. capacity-admit.sh:583 defaults CC_ADMIT_BUDGET=3, so the release lands on
  # attempt 3 at ~150s and is UNREACHABLE. Measured 2026-09-19: 4 of 4 recoveries stranded at
  # exactly 2 refusals ("refusal 1 of 3", "refusal 2 of 3") and became husks.
  # inner-bound-outer-bound-starves-the-tail, as a number.
  attempts=$(awk '/^  up=0$/,/no claude process appeared within 90s/' "$REPO/scripts/handoff-fire.sh" \
             | grep -c 'it2_type_verified\|CMDFILE')          # anchor structurally, then floor it
  budget=$(grep -o 'CC_ADMIT_BUDGET:-[0-9]*' "$REPO/scripts/lib/capacity-admit.sh" | head -1 | grep -o '[0-9]*$')
  [ -n "$budget" ] && [ -n "$attempts" ]
  [ "$attempts" -ge "$budget" ] \
    || { echo "watcher makes $attempts launcher attempts but the budget releases at $budget — the release is unreachable and every refusal is a HUSK"; false; }
}
```

*(The `awk` range and the `grep -c` anchor need pinning against the real text — a stale range
endpoint SELECTS EVERYTHING, `docs/lessons/absent-range-endpoint-selects-everything`-class — so assert
the endpoint matched before believing the count.)*

### T3 — the probe and the launcher must evaluate the SAME terms (P1's ratchet)

Belongs in `tests/capacity-admit-coverage.bats`, whose existing shape is exactly this
(`calls_gate()` at `:68`, per-caller cases at `:99/:125/:152`):

```bash
@test "28 lr-fleet's probe and lr-fire-resume's admit enable the SAME term set" {
  # 2026-09-19: the fleet ran with CC_ADMIT_LOAD_TERM=off in its OWN process; the launcher, typed
  # into the pane's shell, is a fresh tree that never saw it. Probe ADMIT at 17:52:54, launcher
  # REFUSE 12s later at 4.15/core, transplant already done => husk. A probe that measures a
  # different gate than the one it fronts is not a probe.
  for t in LOAD HEADROOM SEGMENT ACTIVE; do
    a="$(grep -o "CC_ADMIT_${t}_TERM=[a-z]*" "$REPO/scripts/limit-recover/lr-fleet.sh"      | head -1)"
    b="$(grep -o "CC_ADMIT_${t}_TERM=[a-z]*" "$REPO/scripts/limit-recover/lr-fire-resume.sh" | head -1)"
    [ "${a#*=}" = "${b#*=}" ] || { echo "term $t: fleet='$a' launcher='$b' — probe fronts a different gate"; false; }
  done
}
```

### T4 — net-zero (P5(i))

```bash
@test "16 CC_ADMIT_NET_ZERO=1 does not charge the replacement against the active ceiling" {
  run bash -c '. "$1"; CC_ADMIT_LOAD_TERM=off CC_ADMIT_HEADROOM_TERM=off CC_ADMIT_SEGMENT_TERM=off \
               CC_SP_ACTIVE_OVERRIDE=8 CC_ADMIT_ACTIVE_CEILING=8 CC_ADMIT_NET_ZERO=1 \
               cc_capacity_admit c16 "in-place recycle"' _ "$LIB"
  [ "$status" -eq 0 ]
}
@test "16b WITHOUT it, the same box refuses — the control that proves 16 is not vacuous" {
  run bash -c '. "$1"; CC_ADMIT_LOAD_TERM=off CC_ADMIT_HEADROOM_TERM=off CC_ADMIT_SEGMENT_TERM=off \
               CC_SP_ACTIVE_OVERRIDE=8 CC_ADMIT_ACTIVE_CEILING=8 \
               cc_capacity_admit c16b "a net-new spawn"' _ "$LIB"
  [ "$status" -eq 9 ]
  [ "$(idl_field 'select(.caller=="c16b")|.term')" = "active" ]
}
```

`CC_SP_ACTIVE_OVERRIDE` is the seam `capacity-admit.sh:97` documents and `spawn-presence.sh:299-302`
implements, so this needs no live census.

### Red-proof discipline required by this suite's own header (`:22-25`)

*"every REFUSE case was re-run with `CC_ADMIT_GATE=off` and returned 0 instead of 9"*. Every case
above must be run once against the UNPATCHED library and shown to fail — T1 must fail with
`status 9` (no token support), T2 must fail with `2 -ge 3` false, T3 must fail on the `LOAD` row.
A test that passes in both arms is an equivalence guard, not a red-proof
(`docs/lessons/green-in-both-arms-is-an-equivalence-guard-not-a-red-proof.md`).

---

## 7. WHAT I COULD NOT ESTABLISH

1. **That the 7 "mid-turn" sessions at 17:17:43 included the limit-blocked husks.** The mechanism is
   certain from code (§4.1); the specific pid set is unrecoverable — beat files are overwritten in
   place and the pids are now dead. A future recovery should snapshot
   `jq -rs 'map(select(.kind=="prompt"))|map({sid,pid,t})' ~/.claude/cc-beats/*.json` before the
   first probe. **Labelled a mechanism claim, not a measurement.**
2. **Whether Claude Code fires the Stop hook when a turn dies on an api limit error.** If it does,
   §4's husk-counting does not occur and only §4.2's net-zero double-count stands. This is one
   cheap experiment the next live limit gives for free: read the blocked session's beat
   `kind` before recovering it. Until then §4.1 is unconfirmed on that one hinge; §4.2 is
   independent of it and holds either way.
3. **Whether `CC_ADMIT_MAX_SEGMENT_PCT=50` or `CC_ADMIT_ACTIVE_CEILING=8` are right.** Not asked,
   not touched. `capacity-admit.sh:721-727` says 50 is provisional and gives the re-derivation
   command; `:790-800` says 8 stands on a count over 127/127 refusals and explicitly forbids moving
   it as an arithmetic consequence of anything.
4. **The 4 GB headroom floor has still never fired** — 0 of 55 refusals in this ledger, consistent
   with `capacity-admit.sh:229-236`'s "0 times in 127 refusals". It is not the bottleneck and P1
   does not touch it.
