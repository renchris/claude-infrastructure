# Runbook — the cloud-session fleet

**What this is for.** Running Claude Code sessions in Anthropic-managed VMs instead of on this box,
so fleet size stops being bounded by local CPU and RAM. Every step below is runnable with no
judgment calls; where a judgment call genuinely exists, it is named as one and the runbook says who
owns it.

**Read this if** you are firing a cloud session, messaging one, looking for one, or staring at a
failure string you do not recognise. The *design* lives in `docs/plans/CLOUD_OBSERVABILITY.md` and
`docs/plans/CONCURRENCY_PROGRAM.md` §S5 — do not re-derive it here.

---

## 0 · The five facts that make everything below make sense

Read these once. Every confusing failure in §6 is one of them showing up as an error string.

1. **A cloud session shares nothing with this box** — no kernel, no filesystem, no process table, no
   terminal. `ps`, `kill -0`, `lsof`, the pane registry and the telemetry files are all *structurally*
   blind to it. Not degraded: blind.
2. **Three local tools used to convert that blindness into a death verdict**, and one of them
   archived teams on a 600s timer. They now abstain instead. See §5 — you need to know this is
   handled, because the whole fleet plan rests on it.
3. **A session id is NOT a global handle. It is scoped to the account that created it.** Sending to
   someone else's session fails with `Session not found`, which reads exactly like a dead session.
   This is the single most misleading error in the system; see §6.
4. **The channel is asymmetric, permanently.** here→cloud is a real push (a message queue).
   cloud→here is *pull only*, over git — the VM can push its own working branch and nothing else,
   and this box has no reachable inbound endpoint. Do not try to symmetrise it.
5. **A declaration must exist at fire time or the session is permanently unobservable.** A cloud
   session that was never declared and pushed nothing leaves zero trace anywhere this box can read.
   There is no forensic path back. `cc-cloud declare` is not bookkeeping, it is the observability.

---

## 1 · Link an account (once per account, and on re-link)

Linking connects an account's CLI to GitHub, which is what makes `claude --cloud "<desc>"` able to
create a session at all.

**Current state (2026-08-08): all four accounts — `next`, `next2`, `next3`, `next4` — are linked.**
So you are here for a *re-link*, a new account, or a rebuild on another box, not to unblock.

**You do not have to remember any of this.** The link drive is filed as a staged migration
(`migrations/0003-cloud-fleet-link-drive.sh`, class `c10`), so it surfaces itself as one counted
operator step in the session close block and as one `cc-do` entry. It is **staged, never run by the
converger** — on an unlinked account the drive opens a window on your desk and types into it, and
`deploy-live.sh` runs unattended. "Usually a no-op" is exactly the shape that makes an unattended
actuator look safe until the one run that does something is the run nobody is watching.

**See where every account stands** (read-only, spends nothing):

```
scripts/cloud-websetup-drive.sh --status
```

**Link one account, or all of them:**

```
scripts/cloud-websetup-drive.sh --account next4
scripts/cloud-websetup-drive.sh --all
```

An account already recorded as linked is a no-op. To re-drive it anyway — which is what you want
when you suspect the marker is lying — add `--force`.

**Read the exit code; it has four states and the fourth is the one that matters:**

| rc | State | What it means, and what to do |
| --- | --- | --- |
| 0 | `LINKED` | The pane printed `Connected as `, or the account was already recorded linked. |
| 1 | `FAILED` | An error was **observed** and named (no config dir, no window id, `GitHub CLI not found`). Fix the named cause. |
| 2 | `PRECONDITION` | This box cannot run the drive at all (no `kitten`, remote control refused, no repo) or the argv was bad. **Nothing was attempted.** |
| 3 | `NOT-SUCCESS` | The drive ran, nothing errored, and `Connected as ` never appeared. **INDETERMINATE — not a failure and not a success.** No state file is written. Go look at the pane, or re-run with a longer `CC_WEBSETUP_POLL_MAX`. Do **not** record a link. |

Across several accounts the run reports the worst outcome, with an observed error outranking an
indeterminate one: any `FAILED` ⇒ 1, else any `NOT-SUCCESS` ⇒ 3, else 0. An observed error names a
cause; an indeterminate says only that nothing was named, so the one carrying information wins.

**Why rc 3 exists at all** is the entire point of §1: folding "nothing was named" into either
neighbour is how a link that was never made gets recorded as made, or how a healthy-but-slow pane
gets torn down as broken.

⚠️ **Do not trust `~/.claude/autonomy/websetup/<acct>.linked` as the authority.** It is a progress
log, and it has already drifted: measured 2026-08-08, the directory held markers for `next2`,
`next3`, `next4` and **none for `next`**, an account that was linked. Nothing reconciles the marker
against the account. Read it as "we did this at some point", never as "this is true now".

**Success is a string, not the absence of an error.** The link succeeded iff the pane printed
`Connected as ` — confirmed live on `next3`, which printed
`Connected as renchris. Opened https://claude.ai/code`. A run that produced no error and no
`Connected as ` is **NOT-SUCCESS**, and is a different state from a run that failed loudly.

---

## 2 · Fire a cloud session

**The create needs a PTY. This is the single most surprising thing on this page.**

```
script -q /dev/null claude --cloud "<what the session should do>" </dev/null
```

Without a pty you get `Error: --cloud requires an interactive terminal.` A script captures stdout by
construction, so the plain form is refused on its own capture. 🚨 **Do not go looking for a flag to
turn this check off.** Its own message says what would otherwise happen: the run *"would silently
ignore `--cloud`"* and execute **locally** — a fleet that believes it is off-box while every session
runs on this machine. The check is protecting you from a much worse failure than the one it causes.

⚠️ **The create is INTERMITTENT today.** Measured 2026-08-08: 1 of 4 attempts succeeded in a
~15-minute window on one account. The failures all read
`Error: Bundle upload failed: Socket is closed after 3 attempts. Please setup GitHub on
https://claude.ai/code` — the CLI falling back to **bundle mode**, which is what it does when the
GitHub link is unavailable. If you get that, **retry before you conclude the account is unlinked**;
and note that a `.linked` marker does not mean the account can create (see §1).

**Before you fire**, run the preflight. It refuses when a fire here could not be observed at all:

```
cc-cloud preflight --branch <your-branch>
```

Its load-bearing refusal is an **unpushed branch**. A cloud VM clones from the *remote*, so
local-only work is invisible to it and the session silently runs against the default branch instead.
Measured on this repo: `origin` carried one head against 286 local branches with no upstream, so the
failing case is the overwhelmingly likely one.

**After you fire**, declare immediately — including the owning account:

```
cc-cloud declare --id <session-id> --branch <branch> --url <url>
```

This is not bookkeeping. Until the declaration exists the session is invisible to every local tool
**and unprotected from the reaper** — §5 explains why the two are the same fact. Confirm it took:

```
cc-cloud is-offbox <session-id>; echo $?
```

---

## 3 · Message a session

<!-- WAVE-C: exact command + exit codes filled in when the cc-notify --cloud arm lands -->

🚨 **`{ok:true}` means QUEUED, not read.** There is no `acked` cursor off-box — the local read
receipt is a line count over the target's inbox file, and an off-box target has no inbox file. A
read receipt against a cloud target therefore returns **UNKNOWN**, never 0. If you are about to
report "I told session X", off-box you cannot; you can only report that it was queued.

---

## 4 · See a session

**List every session, local and off-box together:**

```
cc-sessions
```

Off-box rows carry `kind=offbox`, and they come from `cc-cloud`, never from the pane registry — the
registry cannot represent a session with no local pid, which is what made it one of the three liars
in the first place. Narrow to just the cloud ones with `cc-sessions --offbox` (composes with
`--json` and `--names`).

**Find one you have lost:**

```
cc-where <name-or-id>
```

For an off-box session this answers instead of reporting absence: it says the session is on **no
screen, by construction**, gives its state, and prints the one action that exists —
`open <url>`. §9.3 of the design doc called this tool `cc-panes`, which has never existed; the doc
now records what was actually built.

Three rules the views obey, so you can read them correctly:

- **No pid column, ever, and no `kill -0`.** State comes from `cc-cloud`'s state function.
- **`UNKNOWN` is printed as the word UNKNOWN**, never as a blank cell. A blank in a table of live
  sessions reads as absence, and absence is ambiguous — that ambiguity is the whole reason the state
  function exists.
- **The recover action is `open <url>`, never a kill.** There is no local process to signal; the web
  UI is the escalation path.

The state function (`docs/plans/CLOUD_OBSERVABILITY.md` §4.3), total and first-match-wins:

| State | Means | Alarms? |
| --- | --- | --- |
| `U0 UNKNOWN` | a sensor could not run — a non-verdict, not a state | no row; `--check` fails |
| `C1 NOT-STARTED` | no remote ref, past the boot budget | ROW |
| `C2 BOOTING` | no remote ref, inside the boot budget | no |
| `C3 LANDED` | every declared path is content-present on trunk | no |
| `C4 STALLED` | ref exists, sha unchanged past the stall budget | ROW |
| `C5 ALIVE` | ref exists and advanced inside the budget | no |
| `C6 ABANDONED` | ref exists, not landed, past the life budget | ROW |

`C3` is checked before `C4` on purpose: a finished session stops pushing deliberately, and
STALLED-first would alarm forever on every *successful* run. `C4` needs sidecar history and abstains
without it — only `cc-cloud poll` writes that history, so **nothing advances until something polls**.

---

## 5 · The safety property you are relying on

Landed `d0765876`. Three local tools used to report a healthy cloud session as dead, because their
oracles are local and answered correctly about a box the session is not on:

| Tool | Used to say | Now says |
| --- | --- | --- |
| `cc-spawn-verify` | `ABSENT — Died, or never launched` (exit 1) | `OFFBOX` (exit **3**) |
| `cc-board` | `DEAD` · `DIED-UNRENDERED` · `NO-RENDER?` | `OFFBOX` |
| `team-orphan-reaper.sh` | **archived the team**, on a 600s launchd timer | KEEP + log |

Each abstains only on a **declared, unretired** id (`cc-cloud is-offbox`), and each fails closed
toward its old verdict: no `cc-cloud`, an undeclared id, or a retired one all behave exactly as
before. **This is why §0.5 matters operationally**: an undeclared cloud session is not merely
unobservable, it is *reapable* — the reaper's protection keys on the declaration.

To confirm the protection is live on this box:

```
cc-cloud is-offbox <session-id>; echo $?
```

`0` = declared and protected. `1` = undeclared or retired — **the reaper will treat it as a local
team**. `2` = you passed no id.

---

## 6 · Failure strings — what each one actually means

| You see | It means | Do this |
| --- | --- | --- |
| `{"ok":false,…,"error":"Session not found: session_…"}` | **Usually the WRONG ACCOUNT, not a dead session.** A session id is scoped to the account that created it; the API reports another account's live session as not-found. | Check the declaration's `account`, and send from that account's config dir. Only after that reads correct is "genuinely retired" the diagnosis. |
| `cc-spawn-verify: ✗ ABSENT … Died, or never launched` **for a cloud id** | The id is **not declared** (or is retired) — the abstain did not engage. | `cc-cloud is-offbox <id>`; if 1, declare it. |
| `cc-board: OFFBOX` | Working as intended — the board is abstaining, not reporting a problem. | Nothing. Use `cc-cloud show <id>` for real liveness. |
| `Error: --cloud requires an interactive terminal` | You are running the create without a pty. | Wrap it: `script -q /dev/null claude --cloud "…" </dev/null`. Never suppress the check — without it the session runs **locally** while looking off-box. |
| `Error: Bundle upload failed: Socket is closed after 3 attempts` | The CLI fell back to **bundle mode**, which it does when the GitHub link is unavailable. Measured intermittent — it is not always a real unlink. | Retry first. If it persists on that account, re-link it (§1). Do not read a `.linked` marker as proof it is fine. |
| `cc-cloud preflight` refuses on the branch | Your branch is not on the remote; the VM would clone the default branch instead. | Push the branch first. |
| `cc-cloud: never polled` | No sidecar history, so `C4 STALLED` cannot be evaluated. | Run `cc-cloud poll`. Until something polls, "stalled" is unknowable, not false. |
| `cc-await-ping` exits 5, *"the session that armed me is GONE"* | A known local defect on a stale registry row (backlog `a116d60af388`) — **not** a cloud problem. | Re-arm it. The mailbox write is durable regardless. |
| `cc-bats: REFUSED … DEFERRAL` | The test harness declined to run under load. **Nothing ran and nothing was verified.** | Re-run when a slot frees. Never read it as a pass. |

---

## 7 · What is NOT possible, recorded so it is not re-proposed

- **Interactive attach** (`claude --cloud <id>` with a TTY) is gated OFF on all four accounts —
  `not enabled for your account`. That is an Anthropic rollout gate; it is not clearable here. The
  **headless** send arm is gated separately and *does* work.
- **A push from the cloud into this box.** There is no inbound endpoint. cloud→here is git, pulled.
- **Retrofitting attribution.** See §0.5 — declare at fire time or lose the session.
