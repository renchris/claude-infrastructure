# Axis L — false-positive rate of historical teammate pane closes

**Question.** Of the `✓ closed pane N (member)` events emitted by `hooks/teammate-auto-shutdown.sh`,
how many terminated a teammate that was still mid-legitimate-work or holding undelivered output?

**Answer (headline).** **17 of 105 decidable closes = 16.2 % premature** (95 % CI 9.1–23.2 %);
**17.1 %** after one ground-truth correction the mechanical classifier missed. A further **10.5 %
of closes (11/105) did not actually stop the member** — the `✓` is a claim about a *pane*, and in
those cases the agent process went on writing records for up to 3.5 h afterwards. Every proposed
fix must therefore carry a **must-NOT-wrap** clause around four things this measurement shows are
load-bearing today: the tool-in-flight hold, the dirty-tree defer, the identity pin, and the
`it2-kitty` rc=67 composer guard.

Raw per-close table: `L-closes.csv` (555 rows, same directory).
All timestamps: log = America/Chicago (CDT, UTC−5); transcripts = ISO UTC. Converted before every
comparison (`close_utc = log_local + 5 h`); the conversion is validated empirically — median age of
the last assistant record before a close is **7 s**, which is exactly the hook's `CLOSE_GRACE_S=3`
plus write latency.

---

## 1. Layer / mechanism / evidence

| Layer | Mechanism | Evidence |
|---|---|---|
| **Trigger** | `TeammateIdle` → hook emits `{"continue": false}` (stops the teammate's turn), sleeps `TEAMMATE_CLOSE_GRACE_S=3`, then closes the recorded pane id | `hooks/teammate-auto-shutdown.sh:1-30`, `:77`, `:1288-1300` |
| **Holds that must not be wrapped** | dirty-tree defer (`:885-891`, 184 events/45 d) · `.teammate-busy` marker (`:790-792`, 12) · **tool-in-flight** (`:898-909`, 20) · reap-guard birth-grace/no-products/operator-adoption (`:911-1001`, 274+7) | 508 defer events, 295 distinct members, 45 d |
| **Preservation** | checkpoint first (`refs/wip/<m>/LAST`), fallback `/tmp/*.patch` (`:1047-1094`) | 256 checkpoint + 232 patch lines against 560 closes |
| **Actuator refusals** | rc=66 identity pin (170 events) · rc=67 `it2-kitty` "composer state is UNKNOWN" (166) · rc=1 (21) · rc=124 (7) | `bin/it2-kitty:1251-1257`; `teammate-lifecycle.log` |
| **Outcome signal** | `✓ closed pane` is emitted only after `pane_present()` says the pane is gone (`:290-307`) — so the `✓` is verified **about the pane**, and provably not about the process (§5) | 11 closes with post-close member records |

**The one code-level defect this axis found.** `_tool_in_flight()` (`:523-560`) reads
**`tail -n 1`** of the teammate transcript and requires `.type=="assistant"`. A teammate that issues
a tool call and then has *any* non-assistant record appended — CC writes an `attachment` record in
the same second — presents a last line that is not an assistant record, so the predicate returns
"not in flight" and the close proceeds **with a Bash call outstanding**. Verified on all four P1
cases; file-order tail before the close, in each case:

```
custody-ttl   2026-08-18T03:31:46Z assistant [tool_use Bash]   ← in flight
              2026-08-18T03:31:46Z attachment                  ← what tail -n 1 read
              2026-08-18T03:50:54Z  ✓ closed pane
              2026-08-18T05:35:43Z user [tool_result …]        ← the call returned 1 h 45 m later
```

Same shape at `palace-menu` (tool_use 12:13:17Z, attachment last, closed 14:14:43Z, tool_result
15:42:14Z — 3 h 29 m) and `evolve-plan` (12:19:13Z / attachment / 14:34:20Z / returned). *Empirical.*
The guard's own failure-direction comment (`:536-546`) reasons carefully about a `grep -q` SIGPIPE
inversion being safe — and the whole predicate is defeated one line earlier by `tail -n 1`.
**Must-NOT-wrap:** a replacement must key on *the last ASSISTANT record*, not the last record.

---

## 2. Population and why the denominator is 105, not 555

| | count |
|---|---|
| `✓ closed pane` lines, 2026-08-05 → 2026-09-19 | 560 |
| unique close events after dedupe on (member, ts) — 5 lines duplicated | **555** |
| …with a findable transcript **for the instance that was closed** | **105 (18.9 %)** |
| …undecidable: the closed instance's transcript no longer exists | 450 |

Coverage is **not random in time and is random with respect to outcome**: Claude Code's transcript
retention reaps by mtime, so coverage is ~0 before 2026-08-30 and **105 of the 115 closes from
2026-08-30 → 2026-09-18 (91 %)**. Per-day coverage is in `L-closes.csv`. The decidable sample is
therefore a *recency* sample, not a *severity* sample — the risk is that the closer's behaviour
changed over the window, not that easy cases were selected. 115 of the 450 undecidable rows do have
a transcript for a **later, re-spawned** instance of the same member name; those were rejected
(`first_ts > close`), never counted as clean. Per the brief, all 450 count as **uncertain**.

---

## 3. The classifier, stated exactly

For each close at time `T` (UTC), over the closed instance's own transcript:

**PREMATURE if any of:**

- **P1 — tool in flight.** A `tool_use` id issued at or before `T` with no matching `tool_result`
  at or before `T` (`SendMessage`/`TaskStop` excluded — the harness does not record results for them).
- **P2 — self-declared pending work.** One of the last two assistant *text* records matches
  `still (running|pending|executing) | I'll (send|report|finish|continue|write|deliver) | once it
  (finishes|completes) | waiting for it | will notify me | I'll hold | hold here until | next I'll |
  about to (run|write|check)` **and** does not also match a completion phrase
  (`good to close: yes | ending here | nothing further | awaiting the shutdown | standing by |
  report is written`). The second clause is required: without it the rule fires on 20/94 instead of
  3, almost all of them finished reports containing the word "I'll" in a non-promise sense.
- **P3 — named deliverable absent.** A **durable** path (not `/tmp`, not `/private/tmp`) named in the
  member's brief does not exist today. *Inferred, not empirical* — existence is measured now, not at `T`.
- **P4 — the lead wanted more.** A lead `SendMessage` with `to == <member>` in `(T, T+10 min]` whose
  summary+body does not match `stand ?down | shut ?down | no further work | you are done`.
  `to == member` is required: a mention-based match pulled in a broadcast about a member and
  produced two false positives.

**CLEAN** = none of the above **and** the last assistant record before `T` is a text record.
**UNCERTAIN** = no transcript for the closed instance, or the transcript begins after `T`, or the
last assistant record is `thinking`/empty with nothing else to go on.

**What it cannot decide.** (i) Whether a `/tmp` scratchpad deliverable existed at `T` — reboot
evaporates them, so P3 is restricted to durable paths and only fires twice. (ii) Whether a member
that was *idle awaiting a lead answer* should count — flagged separately as `Q:blocked_on_lead_question`
(3 CLEAN rows), not counted premature. (iii) Anything about the 450 reaped rows.

---

## 4. The rate

| Verdict | n | of decidable |
|---|---|---|
| **PREMATURE** | **17** | **16.2 %** (95 % CI 9.1–23.2) |
| CLEAN | 85 | 81.0 % |
| UNCERTAIN (transcript present but undecidable) | 3 | 2.9 % |
| **decidable total** | **105** | |
| UNCERTAIN (no transcript — retention) | 450 | — |

**Trigger mix among the 17** (rows overlap): P4 lead-wanted-more **11** · P1 tool-in-flight **4** ·
P2 self-declared-pending **3** · P3 deliverable-absent **2**.
**Work actually stopped in 14 of the 17**; the other 3 kept running past the `✓` (§5).

**Corrected rate: 18/105 = 17.1 %.** One documented false negative — see the ground truth below.

**Bounds, stated rather than hidden.**
- *Lower*: 17/105 is a floor. The classifier is deliberately conservative, and has ≥1 known miss.
- *Upper*: 36/105 = **34.3 %** if every grey row is charged as premature — the 3 blocked-on-lead
  CLEANs plus 16 CLEANs that named a deliverable path in their brief with **no write evidence** for
  it before the close. Most of those 16 name a pre-existing plan doc (a read/update target, not a
  write target), so the true value sits much nearer the floor.

**Ground truth — an independent, contemporaneous confirmation.** The lead of `session-59ed2093`
wrote this at `2026-09-15T19:54:10.876Z` (`~/.claude/projects/-Users-chrisren-Development-mac-bootstrap/59ed2093-065d-46fe-8a98-03623c69c4c9.jsonl`, SendMessage `to: agent-cli`):

```
URGENT, lead: the idle-teammate hook REAPS a teammate that goes idle while a background job runs.
It removed the agent-config, local-apps and ci-currency worktrees and killed their characterize
runs. Before you wait on anything in the background, `touch .teammate-busy` in your worktree root,
which makes the hook defer. Remove it only when you send your final report.
```

The classifier calls **agent-config** and **local-apps** premature (P2) and **ci-currency** CLEAN —
so ci-currency is a measured **false negative**: it went idle waiting on a background suite without
saying so in its last two records. Its close (2026-09-15 14:50:45, checkpoint written) is the
correction applied above. It also confirms the class is real and that the *operator-visible* cost is
worktree removal plus a killed background job, not merely a closed pane.

---

## 5. The `✓` that closed nothing — 11 closes (10.5 %)

In 11 decidable closes the member's transcript continues **after** the `✓ closed pane`, same session
id, same file. The most legible case is an entire wave:

```
2026-08-30 18:32:32–18:32:45  ✓ closed pane ×8  (A2-LAX A3-ALT A4-GROUND A5-ARRIVAL A6-POLICY
                                                 A7-RISK B1-TONIGHT …, team session-dcb07c44)
2026-08-31T01:32:20Z  lead → A5-ARRIVAL  {"type":"shutdown_request", … "Wave complete."}
2026-08-31T01:32:24Z  A5-ARRIVAL: "Acknowledged — shutting down. A5 findings are delivered at
                      `scratchpad/flight-A5-arrival.md`; nothing left open on my side."
```
(`~/.claude-quaternary/projects/-Users-chrisren-Development-personal-frontier-gowild/048e62df-6101-48ef-beb8-20f683c15722.jsonl`)

Two hours after the hook logged `✓ closed pane`, the member was alive, answered a shutdown request
and delivered. Either the closed pane was not the member's, or closing the pane did not reach the
process. **Consequence for every fix downstream:** `✓ closed pane` is verified against
`pane_present()` only — it is *not* evidence the member stopped, and no plan may treat the log line
as a termination record. It is also the reason the premature rate and the "work destroyed" rate are
different numbers: 17 premature *intents*, 14 of which actually stopped a member.

---

## 6. Named examples (≥5 required; 8 given, each with file + timestamp)

**E1 — `agent-config`, 2026-09-15 14:44:06, team session-59ed2093 · P2 · PREMATURE.**
`~/.claude/projects/-Users-chrisren-Development-mac-bootstrap/afb75145-4ff3-475c-97ae-55445a22c47f.jsonl`
```
last assistant text, 6 s before the close:
  "The characterize suite is still running; I'll send the final report once it finishes."
✓ closed pane — no checkpoint, no fallback patch
lead, 2026-09-15T19:54:10Z: "…killed their characterize runs."
```

**E2 — `unifi-access`, 2026-09-15 16:49:29, team session-cd5eee6e · P2+P4 · PREMATURE.**
`~/.claude-quaternary/projects/-Users-chrisren-Development-personal/9081d1da-6c6f-419a-a9ff-c3283bd19079.jsonl`
```
member, 77 s before the close: "I'll hold here until the agents complete."
lead, 2026-09-15T21:51:29Z (2 min AFTER the close) — summary "Finish Part B safety net":
  "Part B of your brief is missing — please finish it now. You are not waiting on anyone;
   no other agent's output is an input to your task."
```
The lead's instruction was addressed to a pane that no longer existed.

**E3 — `custody-ttl`, 2026-08-17 22:50:54, team session-ab431fa3 · P1 · PREMATURE + survived.**
`~/.claude-secondary/projects/-Users-chrisren-Development--worktrees-drain-recycle-11/fa4ee353-04fd-422c-8091-a191939e1c1b.jsonl` — excerpt in §1. Checkpoint **and** fallback patch were both written,
so the *work* was preserved; the *tool call* was not, and it returned 1 h 45 m after the close.

**E4 — `dfs-risk`, 2026-09-15 16:49:24, team session-cd5eee6e · P1 · PREMATURE.**
`~/.claude-quaternary/projects/-Users-chrisren-Development-personal/5cefbd99-44f8-429e-abb5-43acdf9214ee.jsonl`
```
2026-09-15T21:49:23Z  assistant [tool_use Bash]
2026-09-15T21:49:24Z  ✓ closed pane        ← 1 second later; no tool_result, ever
```
Neither checkpoint nor patch was written for this one. Closest thing to a clean kill in the sample.

**E5 — `station-forensics` / `evgo-policy` / `polestar-side`, 2026-09-07 19:27–19:37, team session-5ff033cd · P4 ×3 · PREMATURE.**
`~/.claude-secondary/projects/-Users-chrisren-Development-personal/2bed67bb-05c1-436d-88ee-6835d5e5bfbe.jsonl` (+ siblings)
```
lead, 2026-09-08T00:37:34Z, 17 s after the close — "Need the site-condition driver reports for DALE":
  "Excellent work — the stall map is exactly what I needed and it changes the advice.
   Your report truncated at \"100 kW\" in section 2 …"
```
Three members of one wave closed inside 10 minutes, all three with the lead mid-conversation. The
recurring sub-pattern: a member's report was **truncated by the message drain**, the lead asked for
the missing half, and the member was already gone.

**E6 — `variant-b-interview` / `variant-c-neuegrafik` / `variant-d-archive`, 2026-09-13 00:13:27–48, team session-4be23526 · P4 ×3 · PREMATURE.**
`~/.claude-tertiary/projects/-Users-chrisren-Development-personal-mario-followalong/0afd45a2-73c9-4514-a5b6-196d41bfc0f1.jsonl` (+ siblings)
```
lead, 2026-09-13T05:13:51Z (24 s after the close) — "margin column is overlapping — timecodes collide with notes":
  "Rendered B at 1600x1000 in dark. The identity is right and it is the strongest of the four so far…"
```
A design-iteration wave: the lead reviewed each variant and sent revisions into three closed panes.
Checkpoint + patch existed for all three, so the code survived; the *iteration* did not.

**E7 — `rewrite-model-local`, 2026-09-15 07:45:46, team session-085ee6d8 · P4+Q · PREMATURE.**
`~/.claude/projects/-Users-chrisren-Development-mac-bootstrap/6e6b9db2-cd9d-44ce-9066-0c3a5ab0619d.jsonl`
```
member's own last line: "Good to close: no — task 1 remains mine, waiting on the lead merging
                         `local-only-check` to main."
lead, 2026-09-15T12:54:22Z: "…I see 6239ac2 and 1872dc0 on wt/rewrite-model-local and your worktree
                             is gone. Did you finish tasks 2-7 …?"
```
The member declared itself **not** closeable in the very record the hook treated as idle; the lead
then discovered the worktree already removed.

**E8 — `openai-plan-limits`, 2026-09-16 19:16:11, team session-d3f43cf5 · P4 · PREMATURE.**
`~/.claude-quaternary/projects/-Users-chrisren-Development-claude-infrastructure/08a559c1-fb9f-495b-ad4c-6f70c01defbd.jsonl`
```
lead, 2026-09-17T00:19:41Z (3.5 min after the close) — "Ask for truncated follow-up in 200 words":
  "Your second message was truncated by the drain (>16000 chars). Please re-send it in UNDER 200 words…"
```

### Required table (the 17 premature rows; full 555 in `L-closes.csv`)

| close ts (local) | team | member | last assistant record (kind, age) | pending tool_use? | deliverable written before close? | lead msg after close? | patch / ckpt at close | verdict |
|---|---|---|---|---|---|---|---|---|
| 2026-08-17 22:50:54 | session-ab431fa3 | custody-ttl | tool_use:Bash, 1148 s | **yes (1)** | no evidence | — | patch + ckpt | PREMATURE (survived) |
| 2026-09-04 09:14:43 | session-8a020c93 | palace-menu | tool_use:Bash, 7286 s | **yes (2)** | no evidence | — | ckpt | PREMATURE (survived) |
| 2026-09-04 09:34:20 | session-8a020c93 | evolve-plan | tool_use:Bash, 8107 s | **yes (1)** | no evidence | — | ckpt | PREMATURE (survived) |
| 2026-09-07 19:27:22 | session-5ff033cd | evgo-policy | text, 7 s | no | no path in brief | **1** | patch + ckpt | PREMATURE |
| 2026-09-07 19:35:57 | session-5ff033cd | polestar-side | text, 10 s | no | no path in brief | **1** | patch + ckpt | PREMATURE |
| 2026-09-07 19:37:17 | session-5ff033cd | station-forensics | text, 8 s | no | no path in brief | **1** | patch + ckpt | PREMATURE |
| 2026-09-10 00:25:14 | session-25de8822 | drain-rates | text, 7 s | no | **no (durable path absent)** | **1** | patch + ckpt | PREMATURE |
| 2026-09-10 00:26:19 | session-25de8822 | backlog-floor | text, 6 s | no | **no (durable path absent)** | — | patch + ckpt | PREMATURE |
| 2026-09-13 00:13:27 | session-4be23526 | variant-b-interview | text, 6 s | no | yes | **1** | patch + ckpt | PREMATURE |
| 2026-09-13 00:13:33 | session-4be23526 | variant-c-neuegrafik | text, 7 s | no | yes | **1** | patch + ckpt | PREMATURE |
| 2026-09-13 00:13:48 | session-4be23526 | variant-d-archive | text, 7 s | no | yes | **1** | patch + ckpt | PREMATURE |
| 2026-09-15 07:45:46 | session-085ee6d8 | rewrite-model-local | text, 5 s | no | no evidence | **1** | — | PREMATURE |
| 2026-09-15 14:44:06 | session-59ed2093 | agent-config | text, 6 s | no | no evidence | — | — | PREMATURE |
| 2026-09-15 14:46:07 | session-59ed2093 | local-apps | text, 6 s | no | no evidence | — | — | PREMATURE |
| 2026-09-15 16:49:24 | session-cd5eee6e | dfs-risk | tool_use:Bash, **1 s** | **yes (1)** | no evidence | — | — | PREMATURE |
| 2026-09-15 16:49:29 | session-cd5eee6e | unifi-access | text, 77 s | no | no evidence | **1** | ckpt | PREMATURE |
| 2026-09-16 19:16:11 | session-d3f43cf5 | openai-plan-limits | text, 781 s | no | yes | **1** | patch + ckpt | PREMATURE |
| *(2026-09-15 14:50:45* | *session-59ed2093* | *ci-currency* | *text, 6 s* | *no* | *no evidence* | *—* | *ckpt* | *CLEAN by classifier — **premature by lead's own account**)* |

---

## 7. Question (b) — is a `fallback patch` line a marker of prematurity?

**No, not usefully; a *checkpoint* line is the better marker, and only weakly.**

| context at close | premature | rate | Fisher (2-sided) |
|---|---|---|---|
| `✓ fallback patch` written | 10 / 49 | 20.4 % | vs no-patch 7/56 = 12.5 % → **p = 0.58** |
| `✓ final checkpoint written` | 13 / 53 | 24.5 % | vs `~ nothing to checkpoint` 3/37 = 8.1 % → **p = 0.053** |
| neither patch nor checkpoint | 4 / 52 | 7.7 % | — |

*Empirical.* Reading: a member with nothing to checkpoint is ~3× less likely to have been cut off —
which is what you would expect, since an empty tree means it had produced nothing to interrupt. But
the sample cannot certify it (p = 0.053, n = 90), and the causal arrow is ambiguous: a dirty tree is
also what triggers the defer path, so patched/checkpointed closes are the ones that already survived
three defers. **Do not build a gate on the patch line.** Its real value is the opposite of a
predictor: it is the *mitigation* — in E3 and E6 the patch/checkpoint is why the work still exists.

---

## 8. Question (c) — does the rc=67 "composer UNKNOWN" guard have true positives?

**Yes, decisively.** `bin/it2-kitty:1251-1257` refuses to close a window whose composer state cannot
be read ("The pane is running a full-screen TUI whose composer could not be read"), exiting 67;
`teammate-auto-shutdown.sh:322-334` logs `✗ pane close FAILED (rc=67)` and pages.

- **166 rc=67 refusals over 80 distinct members** in the 45-day window (plus 170 rc=66 identity-pin
  refusals over 165 members — a separate guard, same direction).
- Of the 24 rc=67 events whose member transcript survives (9 distinct members), **20 events (83 %)
  and 8 of 9 members produced further assistant work after the refusal.**

| member | refusal | further assistant records | further work span |
|---|---|---|---|
| band-hooks (session-dc73c0ce) | 2026-09-08 01:24:22 | 31 | **724 min** |
| q-relaunch (session-6cda2e02) | 2026-09-08 21:24:34 | 42 | **691 min** |
| B2-screencapture-internals (session-681ac0ed) | 2026-09-11 00:30:05 | 3 | 525 min |
| F2-main-thread-audit (session-681ac0ed) | 2026-09-11 00:35:49 | 5 | 519 min |
| shared-folders-local (session-085ee6d8) | 2026-09-15 08:24:02 | 2 | 112 min |
| rc-consumer-audit (session-671c70c6) | 2026-09-17 22:18:49 | 1 | delivered its audit verdict immediately after |
| adj-wlt-probe (session-29781a2d) | 2026-09-08 15:01:20 | 6 | 3 min |
| bottle-menu-verify (session-1eee2cde) | 2026-09-09 17:15:13 | 1 | replied immediately |
| t17-resident-reload (session-671c70c6) | 2026-09-17 22:18:54 | 0 | — |

Two members were saved **≈12 hours of further work each**. *Empirical.* **Must-NOT-wrap:** the rc=67
refusal is not noise to be suppressed — it is the highest-yield guard measured on this axis. Any fix
that converts rc=67 into a forced close, a retry with `--force`, or a fallback to a different
actuator must first reproduce this table and show the members were in fact finished.

---

## 9. Question (d) — what a more aggressive closer would have destroyed

Three named populations, in descending size:

1. **The 508 defer events (295 distinct members, 45 d).** A closer without the dirty-tree /
   birth-grace / busy-marker / tool-in-flight holds would have closed all of them. Of the 43 defer
   events whose member transcript survives, **38 (88 %) were followed by more assistant work**
   (10 of 13 distinct members; median further-work span 4 min, p90 **615 min**). Reason mix:
   reap-guard 274, dirty tree 184, tool-in-flight 20, `.teammate-busy` 12, unresolved worktree 11,
   birth grace 7.
2. **The 336 refusals (rc=66 pin 170 + rc=67 composer 166).** §8: 8 of 9 measurable members went on
   working, two of them for ~12 h.
3. **The 11 survivors of a logged `✓`.** §5. These are the ones a closer that *also killed the pid*
   would newly destroy — including the whole `session-dcb07c44` wave of 8, which delivered two hours
   after the hook believed it had closed them, and `palace-menu` / `evolve-plan`, whose
   still-outstanding Bash calls returned 1.5–3.5 h later.

Concretely destroyed by a hypothetical no-holds, pid-killing closer, from the decidable sample
alone: a 12-hour `band-hooks` run, a 12-hour `q-relaunch` run, the 8-member `dcb07c44` research wave
mid-delivery, and three outstanding tool calls that had not yet returned. That is the **must-NOT-wrap**
budget: any redesign has to preserve (a) a tool-in-flight hold keyed on the last *assistant* record,
(b) the dirty-tree defer with its checkpoint-first snapshot, (c) the identity pin, (d) the rc=67
composer refusal, and (e) the invariant that `✓ closed pane` never implies process death.

---

## 10. Adversarial self-pass

**(1) "A Stop-hook-blocked or looping teammate looks active but is going nowhere — P1/P2 would
over-count it as premature."** Checked, bounded, and it does not bite here. All four P1 cases carry
positive evidence of *real* work rather than a loop: three had their `tool_result` actually arrive
after the close (custody-ttl +1 h 45 m, palace-menu +3 h 29 m, evolve-plan, all visible as
`X:tool_result_after_close` in the CSV), and the fourth (`dfs-risk`) issued its call **1 s** before
the close, leaving no time to loop. All three P2 cases are corroborated by an independent lead-side
record (the URGENT message for two, the "finish Part B now" message for the third). So the
loop-masquerade bound on this sample is **0 of 7** self-evidence rows; the residual risk lives
entirely in rows I called CLEAN, where a loop would present as a normal finished turn.

**(2) The classifier over-counts CLEAN, and that is the larger error.** Three mechanisms, each
measured: (a) **16 CLEAN rows name a deliverable in their brief with no write evidence before the
close** — the ceiling this puts on the rate is 34.3 %; (b) **3 CLEAN rows were idle *blocked on a
lead answer*** (`t3-call-sites`: "I'm waiting for the lead's shutdown request"; `browser`: "waiting
on the lead for the README row"; `agentenv`: "Waiting on the lead: whether the unverifiable
spawn-depth key ships") — closing those is defensible but it disposes of the question, not the work;
(c) **one proven false negative** (`ci-currency`) where a member idled on a background job without
saying so, invisible to every member-side signal. The honest reading of 16.2 % is *a floor with a
34 % ceiling*, not a point estimate.

**(3) The axis I nearly assumed away: lead-transcript coverage.** P4 fires only when the lead's own
transcript survives. I expected this to bias the rate downward on older rows. It does not —
**all 105 decidable closes also have a resolvable lead transcript**, because member and lead
transcripts are reaped by the same retention clock, so they survive and die together. P4 was
eligible on 105/105.

**(4) A near-miss worth recording.** 115 undecidable rows *do* have a transcript for the same
(team, member) key that begins 1.5–2 h **after** the close. Taking those as "the member's transcript"
would have inverted every signal (a re-spawned instance's fresh work read as post-close survival).
They are rejected on `first_ts > close` and counted uncertain. The recurring 1.5–2 h gap is a
lead-side batching artefact, not a timezone error — the timezone is independently pinned by the
7-second median idle→close latency.

---

## 11. Uncertainties, named

- **81 % of the 45-day population is unmeasurable** (450/555) and no instrument can recover it:
  transcripts are gone. Every rate here describes 2026-08-30 → 2026-09-18.
- **P3 is inferred, not empirical** — file existence is read today, not at close time. It contributes
  2 of 17.
- **Whose transcript `_tool_in_flight` reads** is not independently proven. `SESSION_ID` comes from
  the hook payload's `.session_id` (`:568`) and the code comment claims it is the teammate's; the
  behaviour is *consistent* with that (it fired 20 times, and stayed silent in exactly the four
  attachment-last cases), but I did not observe the resolved path. If it is ever the lead's session,
  the guard is measuring the wrong subject and the `tail -n 1` defect is the lesser of two.
- **The checkpoint correlation is p = 0.053** — suggestive, not certified; do not quote it as a finding.
- **rc=66 (identity pin, 170 events / 165 members) was not evaluated for true positives** — only
  rc=67 was. The pin's members are older than the retention window almost without exception.
- I did not verify whether the `.teammate-busy` remedy the `session-59ed2093` lead prescribed was
  actually adopted by later waves; that is a separate axis.

**Method note for the next session.** Build the index on `(teamName, agentName)` from the first
~25 records of each `~/.claude*/projects/<slug>/<sid>.jsonl`, but recover `team` for a close from the
**`PPID-forensic` line's `--team-name` argv**, not only from the preceding `Auto-shutdown` line —
40 of 560 closes have no matching `Auto-shutdown` block in the log, and dropping them silently
removed 14 decidable rows including two of the sharpest cases (`dfs-risk`, the `A5-ARRIVAL` wave).
