# B1-VERIFY — adversarial verification of B1 (in-process teammate, lever L5)

**Verifier:** independent agent, 2026-08-19 14:00-14:10 UTC · **Box:** MacBookPro18,2 (M1 Max,
hw.ncpu=10, 64 GiB) · **Binary:** 2.1.220 `~/.claude-220/.../claude.exe` (256,908,272 B)
**Method:** re-ran every binary grep; ran **3 fresh probe sessions of my own** (2 interactive
in-process, 1 headless); executed the rails B1 only reasoned about; and — instead of quoting the
paned control — **sampled a LIVE paned teammate read-only** (pid 17602, `A10-hostile-reviewer@session-84bde2e9`).
Subject: [`B1-inprocess-teammate.md`](B1-inprocess-teammate.md).

---

## 1. VERDICT

**B1 survives. Every load-bearing claim is CONFIRMED, most of them by my own re-execution rather than
by re-reading its evidence — and its two weakest labels ("delivery INFERRED", "load UNMEASURED") are
now closed, one in its favour and one against it.**

- **CONFIRMED and strengthened:** the ~40× memory win is NOT an artifact of a toy teammate. I re-ran it
  with teammates carrying ~8,000 lines of real file context each and the marginal cost stayed **+7.0 MB**.
- **CONFIRMED, upgraded from INFERRED:** `shutdown_request` really does abort an in-process teammate —
  exercised, 1-of-3 attribution.
- **REFUTED (the hopeful branch of B1 §5):** in-process does **not** move the load gate. It removes ~28
  *threads*, and threads are not runnable threads. L5 relocates burn, it does not reduce it.
- **NEW, and B1 missed it:** every in-process teammate's permission prompts render in the **lead's one
  TUI modal** and serialise there. My first probe deadlocked on exactly this. It is a hard cap on
  unattended in-process fan-out that no amount of config fixes.
- **Config safety: CLEAN.** No live `settings.json` or `accounts.json` was touched by B1 (one unrelated
  anomaly found and exonerated — §5).

---

## 2. PER-CLAIM ADJUDICATION

| # | B1's claim | Verdict | What I did |
|---|---|---|---|
| **1** | Legal values `tmux·iterm2·in-process·auto`; `DEFAULT_TEAMMATE_MODE="in-process"` @232656323; schema @77748048 | **CONFIRMED** | Re-ran all 5 greps; **every byte offset matches exactly** (§3.1) |
| **2** | `--teammate-mode <mode>` CLI override exists @150375152 | **CONFIRMED — and used** | Offsets match; I **launched 3 sessions with the flag** and it took effect |
| **3a** | 4 named teammates ran in ONE process — 0 new processes/panes/MCP | **CONFIRMED (positive-controlled)** | Reproduced with 4 and with 3 teammates; detector positive-controlled twice (§3.2) |
| **3b** | "+9.0 MB each, **42×**" | **CONFIRMED in magnitude, over-precise as stated** | B1's own baseline is ±7 MB on a 34 MB delta ⇒ 8.5-10.25 MB. Mine: **+7.0 MB**. Honest ratio **≥28-40×**, not 42× (§3.3) |
| **3c** | *(untested by B1)* does it hold for a **context-loaded** teammate? | **CONFIRMED — my test, B1's biggest unexamined assumption** | 3 teammates × 4 full Reads of large files: still +7.0 MB each (§3.3) |
| **3d** | "+1 thread total for 4" | **CONFIRMED, stronger** | Lead thread count **flat at 19** with 3 and with 4 teammates (21 during startup) |
| **4** | `claude -p` silently demotes `Agent({name})` to an async subagent | **CONFIRMED independently** | Ran headless: **0 new team dirs (59→59)**, tool returned a bare `agentId:` handle (§3.4) |
| **5a** | `assignee-pane-residency.sh` drops the member on a `^[0-9]+$` filter | **CONFIRMED** | Read the jq at the stated site — `select(...|test("^[0-9]+$"))` |
| **5b** | `cc-mail` keyed on paneUUID ⇒ unaddressable | **CONFIRMED** | Store is `~/.claude/mailbox/<recipient-paneUUID>.md`; no pane exists |
| **5c** | `cc-teardown` REFUSES loudly, exit 2 | **CONFIRMED BY EXECUTION** (B1 did not show it ran this) | `verdict=REFUSE reason_kind=unknown-target exit=2` (§3.5) |
| **5d** | crash harvest writes `NO-TRANSCRIPT / SKIP-UNHARVESTED` | **CONFIRMED — and it is WORSE than B1 said** | My 4-teammate crash: status.tsv had **one row**; 3 of 4 were **not enumerated at all** (§3.6) |
| **5e** | k/k_work counts 4 teammates as 1 (lead sid) | **CONFIRMED — B1 under-quoted its own evidence** | **4** rows at 13:40:27-31, all sid `865210e0`; B1 quoted only 2 |
| **6** | Generation cap structurally inert (stamp written at pane creation) | **CONFIRMED on mechanism, RE-SCOPED on danger** | Cap is *"fed by a stamp bin/it2-kitty puts on the launch"* (line 317). But the hook's own refusal text **names in-process as the sanctioned alternative** — inertness is by DESIGN for non-session-minting units (§3.7) |
| **7** | BURST-only, box-not-quota | **CONFIRMED** | 4 in-process teammates = 4 billed conversations; nothing in this path touches the token rate |
| **8** | Load cost UNMEASURED; "if load-cheap, L5 moves the first wall" | **MEASURED BY ME → the hopeful branch is REFUTED** | Threads ≠ load; work is relocated, not removed (§3.8) |
| **9** | iterm2 control not re-derived; 382 MB QUOTED | **SUPERSEDED — no longer needs quoting** | I measured a **live** paned teammate read-only: **282 MB, 28 threads** (§3.8) |
| **10** | Residue cleaned, no live config edited | **CONFIRMED** | mtimes + probe-footprint discriminator (§5) |

**NEW findings B1 did not have:** N1 shared permission modal (§3.9) · N2 shutdown abort exercised
(§3.10) · N3 the inbox file stays `read:false` after a *successful* abort (§3.10) · N4 harvest
under-enumeration (§3.6) · N5 the conversation is not in `projects/*.jsonl` at all (§3.6).

---

## 3. NUMBERS, WITH THE COMMAND BEHIND EACH

### 3.1 Binary anchors — all five reproduce byte-exact

```bash
B=~/.claude-220/node_modules/@anthropic-ai/claude-code/bin/claude.exe
LC_ALL=C grep -a -o -b 'How spawned teammates execute (tmux, iterm2, in-process, auto)' "$B"
LC_ALL=C grep -a -o -b 'How to spawn teammates: "tmux", "iterm2", "in-process", or "auto"' "$B"
LC_ALL=C grep -a -o -b 'var nrn="in-process"' "$B"
LC_ALL=C grep -a -o -b 'if(Lrn())return ivd(e,t)' "$B"
LC_ALL=C grep -a -o -b -- '--teammate-mode' "$B"
```

| Anchor | B1 said | I measured |
|---|---|---|
| settings schema enum | @77748048, @226849944 | **@77748048, @226849944** ✓ |
| CLI flag help | @150375152, @246548508 | **@150375152, @246548508** ✓ |
| `DEFAULT_TEAMMATE_MODE` | @232656323 | **@232656323** ✓ |
| in-process checked before backend detect | @234645526 | **@234645526** ✓ |
| `--teammate-mode` literal | *(not given)* | **@150375104, @246548483** |

### 3.2 "0 new processes" — positive-controlled TWICE, which B1 never did

The attack asked whether the negative came from a blind instrument. It did not.

**Positive control A — a known paned teammate was live the whole time.**

```bash
ps -o args= -p 17602
#  …/claude.exe --agent-id A10-hostile-reviewer@session-84bde2e9 --agent-name A10-hostile-reviewer …
ps -Ao comm= | grep -c 'claude-220.*claude'      # B1's detector → sees it
pgrep -f 'claude\.exe .*--agent-id' | wc -l      # clean detector    → 1
```

**Positive control B — B1's own census contains an unclaimed internal control.** In
`B1-P5-4teammate.census`, `cc_procs` reads **17** before the lead starts and **19** the moment it does
(+2). The *same instrument*, in the *same run*, then reads **19→18** across the arrival of four
teammates. An instrument that registered +2 for one lead and 0 for four teammates is not blind.

**My independent runs:** `cc_procs` flat at **17** across the whole life of 4 teammates (probe V1) and
3 teammates (probe V2); `agentid` flat at **1** (the live paned teammate) throughout.

⚠️ One methodological note: B1's second detector, `ps -Ao args= | grep -c -- '--agent-id '`,
**self-matches** — it read `2` where the truth was `1`. It over-counts, so it cannot manufacture a
false zero, but it is not a clean instrument. `pgrep -f 'claude\.exe .*--agent-id'` is.

### 3.3 Memory — B1's headline survives the test B1 did not run

B1's `+9.0 MB` comes from `(262−228)/4` on a baseline that itself wandered **221-228 MB** in the six
seconds before the spawn. Taking the honest baseline band gives **8.5-10.25 MB/teammate**. So `42×` is
inside the band but is over-precise; the defensible statement is **≥28-40×**.

**The claim I actually attacked:** B1's teammates read one file and printed a line count. A working
teammate carries a real context window. So I re-ran it with teammates forced to load real context —
four full `Read` calls each on `handoff-fire.sh`, `postland-verify.sh`, `ship-land.sh`,
`BACKLOG_DRAIN_24_7.md` (~8,000 lines ≈ 80K tokens per teammate), Read-only, no Bash.

```bash
# probe V2 — 3 named teammates, --teammate-mode in-process, sampler = /usr/bin/footprint -p <lead pid>
/usr/bin/footprint -p 79663 | awk '/phys_footprint:/{print $2}'
```

| | value | source |
|---|---|---|
| lead settled, pre-spawn | **219-223 MB** | V2 census 14:01:26-14:01:35 |
| peak, 3 context-loaded teammates alive | **244 MB** | V2 census max |
| **marginal cost per context-loaded teammate** | **+7.0 MB** | (244−223)/3, paired differential, same pid |
| lead threads, pre-spawn → 3 teammates | **21 → 19** (never rose) | `ps -M` |
| **live PANED teammate, measured not quoted** | **282 MB phys_footprint, 28 threads** | `/usr/bin/footprint -p 17602`; `top -l 2 -pid 17602` |

**So the cheapness is real and it is not a toy-teammate artifact.** 282 / 7.0 = **40×** on the
process alone, before counting the paned teammate's separate MCP child (`node`, pid 18451).

### 3.4 The headless trap — CONFIRMED, my own run

```bash
BEFORE=$(ls -d ~/.claude-secondary/teams/session-* | wc -l)      # 59
CLAUDE_CONFIG_DIR=~/.claude-secondary CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 \
  claude -p --teammate-mode in-process --model claude-opus-5 --permission-mode acceptEdits \
  'Make exactly ONE Agent tool call with name="hprobe" …'
AFTER=$(ls -d ~/.claude-secondary/teams/session-* | wc -l)       # 59
```

`59 → 59`: **no team was created**. And the tool result was the async-subagent shape —
`agentId: adabc170f30b83dfc (use SendMessage with to: 'adabc170f30b83dfc' …)`. Per the SendMessage
tool's own contract a raw `agentId` handle is what you get *"when the agent has no name"*. The `name:`
was silently discarded. **Any plan that dispatches headless sessions to run Agent-Teams waves is
blocked here**, exactly as B1 said.

### 3.5 `cc-teardown` — executed, not reasoned

```bash
bin/cc-teardown 't1@session-865210e0' --done-evidence 'B1-VERIFY adversarial probe'
# cc-teardown: verdict=REFUSE reason_kind=unknown-target exit=2 target=t1@session-865210e0 pane=- pid=-
bin/cc-teardown 't1' --done-evidence '…'      # same verdict
```

I checked first that no live session collides with `t1` (13 live rows, none named `t1`). I also ran the
no-done-evidence control: it returns the **same** `reason_kind=unknown-target`, i.e. resolution precedes
the evidence check — so the branch is genuinely the unknown-target one and the test is not vacuous.

### 3.6 Crash harvest — confirmed, and worse than reported

My 4-teammate probe lead (v1..v4) was killed by my own bound. The binary wrote
`teams/session-e34bb366/CRASH_REPORT.md` + `HARVEST/status.tsv`. Contents:

```
v1	in-process	NO-TRANSCRIPT	0	-
```

**That is the entire file.** v2, v3 and v4 appear in the report's *Members* list and then **nowhere in
the harvest at all** — not even as a NO-TRANSCRIPT row. So a lead crash does not merely fail to recover
in-process teammates' reports; three of four were never enumerated by the recovery path.

**N5, a caveat that cuts B1's way and against it:** on this binary the conversation is **not** in
`projects/<sid>.jsonl` for *anyone*. That file held 5 metadata records and a
`bridgeSessionId: cse_01Q3dJmA41KbSA4rpRV4E6A2` pointer. So "NO-TRANSCRIPT" is partly a property of this
binary's storage, not solely of in-process mode. The operative fact — the harvester emits
NO-TRANSCRIPT and skips — is unchanged.

### 3.7 The generation cap — mechanism confirmed, danger re-scoped

`hooks/agent-teams-enforce.sh:317` states it outright: the cap is *"fed by a stamp `bin/it2-kitty` puts
on the launch."* No pane launch ⇒ no stamp ⇒ the ladder cannot advance. **B1 is right on mechanism.**

But B1 frames this as the cap becoming *"inert for the very unit that has no other cap"*, and the hook's
own refusal text contradicts that reading. It tells a refused caller to *"drop the name/team_name and run
this as an in-process subagent if it is read-only work (**those mint no session and are not capped**)"*.
The 224-spawn / 167-session / kernel-panic runaway the cap exists to stop was a **session** runaway; an
in-process teammate mints no session and no pane, so it is not that class. This repo has already ruled on
exactly this shape — commit `60f6ca46e`, *"the pane-spawn primitive is ungated BY DESIGN."*

**The real risk, stated correctly:** flipping `teammateMode` fleet-wide would silently move NAMED
teammates — which the cap **does** police today, precisely because they mint panes — into the unpoliced
class. That is a genuine loss of coverage. **B1's recommendation stands; its reason should be
"it reclassifies a policed unit as an unpoliced one", not "the cap is broken".**

### 3.8 Load — B1's open question, now closed AGAINST L5

| | in-process (3-4 teammates) | live paned teammate |
|---|---|---|
| threads added | **0** (lead flat at 19) | **28** (`top -l 2 -pid 17602`) |
| %CPU, `top -l 2` second sample | lead **0.1-5.5%**, 12 samples | **0.4-1.1%**, 6 samples |
| phys_footprint | +7.0 MB/teammate | 282 MB |

**Darwin load average counts RUNNABLE threads, and `top` reported `1086 processes, 7 running, 6198
threads`.** A paned teammate's 28 threads are overwhelmingly idle runtime threads; they cost memory and
a process slot, not load. And the in-process teammate still generates tokens and runs tools — that work
now happens *inside the lead's* event loop. **The burn is relocated, not removed.**

So of B1 §5's two branches, the one that fires is the second: *"if they are load-neutral, L5 only
converts a memory/terminal problem into a load problem and its ranking drops behind whatever lever
addresses the load gate."* Given the settled finding that the **load gate is the FIRST wall** and that
non-Claude ambient load already sits at 20.19/20.0, **L5 does not raise the ceiling the wave is
actually asking about.** It raises the ceiling on the *third* wall (memory) and removes the *fourth*
(terminal).

### 3.9 N1 — the shared permission modal (B1 missed this; it bounds the lever)

My first probe (4 in-process teammates, `--permission-mode acceptEdits`) **deadlocked**. The lead's TUI
rendered:

```
Bash command · from the v2 agent
wc -lc …/handoff-fire.sh …/postland-verify.sh …
Do you want to proceed?
❯ 1. Yes   2. Yes, allow reading from scripts/ from this project   3. No
```

A **paned** teammate raises its own modal in its own pane and blocks only itself. An **in-process**
teammate raises it in the lead's single TUI, and the lead's whole turn stops until it is answered. With
N in-process teammates every permission decision funnels through **one** modal, in **one** window, in
serial. For an unattended wave that is not a nuisance — it is a stall with no watcher. My re-run had to
forbid Bash entirely to get a clean measurement.

### 3.10 N2/N3 — `shutdown_request` works; its on-disk record lies

B1 labelled the abort **INFERRED** ("P4/P5's leads were SIGKILLed before a shutdown round-trip"). I
exercised it. Probe V2 spawned w1, w2, w3 identically and the lead sent a `shutdown_request` to **w1
only**. Lead output:

```
⏺ Teammate @w1 finished
⏺ w1 went idle without a LOADED reply. Still waiting on w2 and w3.
⏺ Teammate @w3 finished
```

**w1 — the only one messaged — is the only one that stopped without producing its deliverable**, while
w2 and w3 completed. 1-of-3 attribution. **CONFIRMED: `shutdown_request` aborts an in-process teammate.**

**N3, the new silent-rail row.** The message file
`teams/session-ffb74461/inboxes/w1.json` still reads:

```json
{"from":"team-lead","text":"{\"type\":\"shutdown_request\",\"requestId\":\"shutdown-1787148104375@w1\",…}","read": false}
```

`read:false` — **after the shutdown was delivered and acted on.** Delivery to an in-process teammate is
in-memory; the file is a mirror whose flag is never flipped. So any disk-reading rail — including the
binary's own `CRASH_REPORT.md` "Last 5 inbox messages per member" section, which duly re-rendered it —
reports an *undelivered* protocol message over one that was delivered and obeyed. Add it to B1 §3 as a
fifth silent break, and note it fails in the **opposite** direction to the others: those hide a live
teammate, this one invents an unhandled request.

---

## 4. WHAT I COULD NOT MEASURE, AND WHY

1. **A paned-teammate control at *spawn*.** Rule 4 forbids spawning into the live fleet. I improved on
   B1's QUOTED figure by sampling a live paned teammate read-only (282 MB / 28 threads), but that is a
   teammate mid-life, not an arrival differential — so it is not a like-for-like marginal cost.
2. **Load attribution during token generation.** Both unit types are API-blocked most of the wall clock;
   isolating the runnable-thread burst of a generating teammate needs a paired A/B I cannot run without
   spawning a paned teammate. §3.8's conclusion rests on the structural argument (work relocated, not
   removed) plus a 0-thread measurement, not on a paired burst measurement.
3. **The ceiling on concurrent in-process teammates.** I proved ≥4, same as B1. Untested above that, and
   §3.9 suggests the practical ceiling is set by modal serialisation and the lead's context, not by code.
4. **Long-horizon lead footprint.** All probes were <5 minutes. A lead accumulating 15 in-process
   teammates over hours is untested; my +7.0 MB is a marginal cost at small N and short life.
5. **The `read:false` flag's downstream blast radius.** I proved the flag is wrong; I did not enumerate
   every consumer of `teams/*/inboxes/*.json`.
6. **`config_teammate_blocked` / managed-policy refusal.** Not tested (no MDM here), same as B1.

---

## 5. CONFIG SAFETY — CLEAN, with one anomaly found and exonerated

**No live `settings.json` or `accounts.json` was modified by B1.**

```bash
for d in ~/.claude ~/.claude-secondary ~/.claude-tertiary ~/.claude-quaternary ~/.claude-next; do
  stat -f '%Sm %N' -t '%Y-%m-%dT%H:%M:%SZ' "$d/settings.json"; done
```

| file | mtime | verdict |
|---|---|---|
| `~/.claude/settings.json` | 2026-08-18T18:24:58Z | untouched (pre-dates the probes) |
| `~/.claude-secondary/settings.json` | 2026-08-18T18:24:59Z | untouched — **and this is the dir B1 probed** |
| `~/.claude-tertiary/settings.json` | 2026-08-18T18:24:59Z | untouched |
| `~/.claude-next/settings.json` | 2026-08-18T18:24:58Z | untouched |
| all 5 `accounts.json` | 2026-07-10/11 | untouched |
| **`~/.claude-quaternary/settings.json`** | **2026-08-19T06:39:01Z** | **written inside B1's probe window — NOT B1** |

I chased the quaternary write hard, because it is the only config file whose mtime lands between B1's
first and last probe, and because quaternary uniquely carries `skipDangerousModePermissionPrompt: true`
— which is what the binary writes when a *bypass-permissions* dialog is accepted, and B1 §4.6 admits to
driving a bypass-permissions dialog blind. **The discriminator clears B1:**

```bash
grep -c 'probe-cwd' ~/.claude-quaternary/.claude.json     # 0
ls -dt ~/.claude-quaternary/teams/* | head -1             # 2026-08-18 — nothing from today
grep -n CLAUDE_CONFIG_DIR B1-pty_run.py                   # 6: ~/.claude-secondary  (pinned)
```

Zero probe footprint in quaternary: no probe cwd registered, no team dir from today, and B1's driver
pins `CLAUDE_CONFIG_DIR=~/.claude-secondary` on every launch. The 06:39 write belongs to some other live
session on that account. **Reported for the record, not charged to B1.** The content diff vs secondary is
only `effortLevel: low` and that one flag — no `teammateMode` change anywhere.

**My own residue, cleaned:** probe teams `session-e34bb366` and `session-ffb74461` archived to
`teams/_archive/B1VERIFY-*`; both probe leads TERMed and confirmed dead; samplers/drivers killed. Live
fleet re-counted at 16 sessions, untouched. Probe cwd was a scratchpad dir; nothing was written to the
repo tree by any probe.

---

## 6. THE DECISION THIS VERIFICATION CHANGES

**B1's lever is real and B1's caution is right — but its *ranking* must move down, and the reason is
§3.8.**

| | |
|---|---|
| **Adopt as a settings flip?** | **No — B1's blocker stands, with a corrected rationale.** Flipping `teammateMode: "in-process"` fleet-wide reclassifies NAMED teammates from a pane-stamped, generation-capped unit into an unstamped, uncapped one. That is a coverage regression, not a broken cap. Re-key the stamp off `identity.parentSessionId`/`spawnDepth` first. |
| **Use per-wave via `--teammate-mode in-process`?** | **Yes, for ATTENDED, bounded, Read-heavy waves.** Confirmed working: real teammates, own model, team messaging, tools, and `shutdown_request` teardown. |
| **…but not for unattended waves** | **New blocker (§3.9).** All teammates' permission prompts serialise through the lead's single TUI modal. A `bash`-using in-process wave with nobody watching **stalls**, and it stalled for me on the first try. Either pre-authorise every tool the wave needs, or keep panes. |
| **Does it break the ~15 ceiling?** | **No — and this is the correction that matters.** The settled wall order is load < quota < terminal < memory. L5 is measured at **0 threads and ~7 MB** per teammate, so it demolishes walls 3 and 4 — the two the box was *not* hitting first. Runnable-thread burn is relocated into the lead, not removed, so **wall 1 does not move**, and quota is untouched by construction. |
| **BURST or SUSTAINED** | **BURST only.** Confirmed. Zero effect on the 24/7 token rate; the 9.4-sustainable-working-units figure is unchanged. |
| **Net** | A cheap, correct, well-scoped **relief valve for memory and terminal pressure** — worth having, and worth having *before* anything that raises the pane count. It is **not** the lever that gets the fleet past 15 concurrent session equivalents, because it does not touch either of the two walls that bind first. |

**The single follow-up that would change this verdict:** a paired A/B of runnable-thread burst — one
paned teammate vs one in-process teammate, both mid-generation, `top -l 2` second sample attributed
per-pid. If in-process generation turns out to be measurably *cheaper* in runnable threads (not just in
resident threads), §3.8 flips and L5 returns to the top of the board. Nothing I could run inside rule 4
could settle it.
