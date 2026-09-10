---
name: recover
description: Recover perfectly from ANY interruption to delegated work — not just a usage cap. Use when a session comes back from a network drop or reconnect ("reconnected to the internet, continue", "wifi came back", "API Error: Can't reach the API server", ENOTFOUND/ECONNRESET/socket hang up), when a workflow or agent STALLED ("agent stalled on all N attempts", "no progress for 180000ms", "stream watchdog did not recover"), when a background task came back failed/killed/stopped, when a session was RESUMED and you need to know what its delegations were doing when the process died, when workflow/subagent/teammate results came back null/partial/empty, or after a crash, a reboot or an /exit. Also covers the quota classes (5-hour / weekly / model-scoped Fable / monthly-spend cap) and the auth login cliff — those select a different recovery MODE, not a different engine. Modes: limit | resume-in-place | stall.
allowed-tools: Bash, Read, Write, Edit, Grep, Glob, Agent, Workflow, TaskList, TaskCreate, TaskUpdate, AskUserQuestion
argument-hint: "[audit | limit | resume-in-place | stall | fleet [--locate] ] — bare = audit, then the mode the audit's own evidence selects"
---

# /recover — interrupted-work recovery, no partial-result acceptance

**The engine was never limit-specific; only its trigger was.** `lr-audit.py` classifies every
delegated unit from disk terminal state and the verdict never consults the *reason* for the death —
`slot_verdict` returns NULL on ANY `api_error`, and `classify_limit_text` is called only to LABEL
the evidence string. So the whole audit → forced re-run → re-audit fixpoint, the verdict table, the
Teams member table and Iron rules 1-6 already applied verbatim to a network death. What did not
apply was the quota-shaped half: headroom check, wait-vs-switch, reset time, transplant, and the
login cliff — all of which presuppose the ACCOUNT is the problem.

**The gap was DISCOVERY, not capability.** `/limit-recover`'s description named only quota and
auth-cliff triggers, so "(Reconnected to internet, continue)" loaded none of it and the operator
landed in exactly the failure that command's own opening paragraph refutes: the model reconciles
from CONTEXT, which still holds the pre-kill narrative and reads plausible, satisfices on the units
it remembers, and smooths the gaps into the conclusion. This file is that description, widened to
the class.

## The trigger is structural — it names no error text

A denylist of spellings is not a class. There are exactly **three** ways the harness can end
delegated work, and every future death class (a new watchdog, a new HTTP code, a kernel-killed
process) arrives as one of them:

| # | predicate | what it means |
|---|---|---|
| 1 | **the process boundary** — `SessionStart` with `source=resume` | every open delegation is DEAD *by construction*, whatever killed the process: quota, network, crash, reboot, `/exit` |
| 2 | **the api-error record** — the last assistant record before this prompt has `isApiErrorMessage:true`, **any** `error` value | a turn ended abnormally. `rate_limit` and `server_error` differ only in which recovery MODE is legal |
| 3 | **the non-success notification** — a `<task-notification>` whose `<status>` is not `completed` (`failed` · `killed` · `stopped`) for a tool-use-id that spawned a delegation | the harness has spoken, and it did not say "done" |

The envelope in #2 is worth quoting, because it is what makes a text-widened read safe:

```json
{"type":"assistant","message":{"model":"<synthetic>","role":"assistant",
 "content":[{"type":"text","text":"API Error: Can't reach the API server — check your internet or DNS (ENOTFOUND)"}]},
 "error":"server_error","isApiErrorMessage":true,"version":"2.1.260"}
```

`model:"<synthetic>"` + `isApiErrorMessage:true` is the structural pair. A session merely
*discussing* ENOTFOUND in prose (this repo does constantly) is not a synthetic api-error record and
cannot match. **A network death's envelope is byte-identical to a cap's** — only `error` and the
text differ.

## Step 1 — always audit, and read the two gating lines first

```bash
mkdir -p ~/.reso/limit-recover/$CLAUDE_CODE_SESSION_ID
python3 ~/.claude/scripts/limit-recover/lr-audit.py \
  --json ~/.reso/limit-recover/$CLAUDE_CODE_SESSION_ID/audit-$(date -u +%H%M%S).json \
  --md   ~/.reso/limit-recover/$CLAUDE_CODE_SESSION_ID/audit-latest.md \
  --salvage-dir ~/.reso/limit-recover/$CLAUDE_CODE_SESSION_ID/salvage
```

Exit 0 = no gaps · 1 = gaps · 2 = artifacts missing (⇒ everything is UNVERIFIABLE: report and
STOP-ASK). Two lines gate everything after:

1. **`lead process: DEAD | IN-FLIGHT | IDLE | UNKNOWN`** — a measured pid, never an assumption, and
   every in-process verdict inherits it. **A quota kill ends the session; a network drop usually
   does not.** Measured 2026-09-09: the whole fleet produced nothing from 14:40Z to 17:20Z while
   every process stayed alive, and the first api-error record landed **107 minutes** after the
   silence began. Disk silence is therefore not death, and one retry ladder ran **93.4 minutes**
   before writing anything. `UNKNOWN` means neither liveness census could run; it is deliberately
   NOT folded into DEAD, because DEAD is the state that authorises a re-run.
2. **`No genuine QUOTA limit events…`** — the quota SUBSET, and **empty on every network death,
   crash and stall**, sitting beside a fully correct gap ledger. Reading that emptiness as "nothing
   was interrupted" is the trap. The general death record is `last_api_error`; the delegation
   population line names its strata so a zero cannot read like a clean session.

Then reconcile: every delegated call you remember or see in context MUST appear in the audit, and
anything in one source but not the other is itself a finding — say so.

**Verdict → action is the table in
[`/limit-recover` § Verdict → action](limit-recover.md), which is authoritative for all
modes.** Execute it, do not re-judge it. The three wait verdicts are the ones this class added:

- **PENDING** (lead IDLE, unit has no terminal record) → **WAIT-FOR-NOTIFICATION, never re-run.**
  The harness owns the promise and will settle it; that notification re-enters this audit on
  arrival, so waiting is the action, not idling.
- **UNSETTLED-INFLIGHT** (lead IN-FLIGHT) → **NONE. Do not touch.** Re-running doubles a live unit.
- **RUNNING** (a teammate whose OWN pid is alive) → **never respawn over a live member.** Wake it.

## Step 2 — the mode the evidence selects

The mode is chosen by the audit's evidence, not by the phrase the human typed.

### `limit` — the account is the problem
Quota (`rate_limit` + a "You've hit your…" text) or the auth login cliff. Headroom check,
wait-vs-switch, reset time, cross-account transplant, salvage bundle: **run
[`/limit-recover`](limit-recover.md)** — modes `recover` / `handoff` / `fleet` / `ingest` there are
unchanged and remain the deep runbook.

### `resume-in-place` — the account is FINE
A network death, a crash, a reboot, an `/exit`. The pane is usually still alive and the session
resumes where it stood; **a transplant would spend an account move on a problem that no longer
exists.** Read `KIND` per unit from `lr-fleet.sh --locate` (`network` rows are resume-in-place;
`limit` rows are transplant) and note the error record's AGE — a census snapshot of "blocked" rows
expires within the hour, because every one of the six panes measured on 2026-09-09 was re-engaged
within ~40 minutes.

Then: consume zero-spend units first (COMPLETE_UNDELIVERED / COMPLETE_SALVAGED from disk), review
VACUOUS_SUSPECT, and only then re-run — **gated on the lead state**, and never over a PENDING,
UNSETTLED-INFLIGHT or RUNNING unit.

### `stall` — the harness already exhausted its own retries
A `STALLED` verdict is N attempts under ONE journal key with no result and a terminal run error.
The `[Request interrupted by user]` marker in each dead attempt is the **watchdog's**, byte-identical
to a human Ctrl-C; only the run json's `error:` separates them, which is why a stall is never
reported as "the user did this".

**A stall is a SYMPTOM, not a third cause.** On the measured incident it was the shortest watchdog's
view of the same outage seen through three ladders (an 18-minute watchdog, a 51.5-minute and a
93.4-minute turn ladder). What separates a stall that will clear from a deterministic one is a
**control, never the stall's own text**:

1. **The fleet arm** — any real-model assistant record from ANY session in the stall window proves
   the API path was live, which convicts the request rather than the network.
2. **A probe independent of the request** — DNS+TCP+TLS on the API host, no quota, and **two greens
   30 s apart**; recovery needs hysteresis, and one green is a coin flip.
3. **The re-fire itself, as the last discriminator** — **at most one**, under a green control. A
   second stall under a green control convicts the REQUEST (prompt size, a blocking tool, a headless
   permission prompt) and the remedy is to change the request, never a third fire.

Receipt for why a blind re-fire is not free: the harness re-issued one journal key five times into a
live outage — **85 minutes, six attempts, nothing produced**.

## Iron rules (unchanged, and they were never quota-specific)

1. **Never accept a partial result** *for a read-only research unit* — re-run it. But the rule is
   not universal: for a **side-effecting** unit (a teammate committing on its branch) a blank re-run
   is a DOUBLING hazard, so resume from the worktree/branch state instead. The verdict space needs
   the unit's class, and "no partial results" was written for the first kind.
2. **Never bridge a gap from memory or context.** Disk is the only ground truth.
3. **Never re-run a unit a live process still holds.** PENDING / UNSETTLED-INFLIGHT / RUNNING are
   verdicts, not delays.
4. **Never read an empty `limit_events` as an all-clear**, and never read disk silence as death.
5. **Re-audit after every re-run**, to a fixpoint.
6. **A zero names its strata.** Report the delegation population by tool with the settled/open
   split; an audit that missed a spawn tool would otherwise print "0 open" and read clean.

## Why the scripts are still called `limit-recover`

Deliberate, not neglect. `scripts/limit-recover/` and the `lr-*` names keep their spelling because
the live layer is a farm of **per-file symlinks**: a rename is an ADD that does not exist until the
converger runs, and 40+ memory and doc citations name the path. The same reasoning applies to THIS
file — it is an ADD, so until it is live `/limit-recover` remains the working front door, and its
own `description:` has been widened to catch the non-quota trigger phrases in the meantime.
