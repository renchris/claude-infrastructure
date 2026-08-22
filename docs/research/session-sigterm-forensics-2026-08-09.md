# Three sessions died at one instant, and nothing said so — 2026-08-09

**Status:** root cause **CONVICTED 2026-08-09** (§1c) — a peer session's `pkill -f "next dev" -P $$`,
whose `-P` scope was never parsed and became a *pattern* that matches every handoff brief. Four
defects are now convicted: §1c (the kill), §1d (the guard that would have allowed it), §2 (why
nothing alarmed), §3 (why both hunts died).

Scope (frozen): investigate and resolve why three sessions closed abruptly and unintended — two
fired `/handoff` peers that were expected to re-ping, and one independent main session with no
handoff involved.

---

## 1. What happened, verified

Three Claude Code sessions were killed by an **external SIGTERM at `2026-08-09T07:38:17Z`**
(00:38:17 local). One signal, one instant, three sessions, two different account config dirs.

| session | cwd | account dir | role |
|---|---|---|---|
| `e55264aa-dec4-44bd-b26f-60d8fd8a1690` | `.worktrees/wt-bs-footer-motion` | `.claude-quaternary` | fired handoff peer |
| `d505227f-4e93-4a10-bd1c-876d5d58a79c` | `.worktrees/wt-rum-iad-endpoints` | `.claude-quaternary` | fired handoff peer |
| `49e10824-0c58-4a73-a1ad-69030c613780` | `lakehouse-lecture` | `.claude-next` | **independent main session** |

Evidence: `~/.claude/logs/close-records/{13020,71821,17151}-*.json` — all `exit_code 143`,
`signal 15`, `version 2.1.220`, identical `ended_at`. Identity confirmed against
`lead-crash-watchdog.log` registration rows (pid ↔ sid). All three last wrote a transcript row of
type `queue-operation` at `07:38:14.5Z`, ~2.5 s before the kill; all three of those rows are
`<task-notification>` payloads, **not** operator prompts — no queued human intent was lost.

### 1a. The misdiagnosis this cost, and why it is the interesting part

The in-flight analysis concluded these sessions had *exited cleanly of their own accord*, reasoning:
*"It printed `Resume this session with: claude --resume …` — that's Claude Code's normal exit banner.
A SIGKILL prints nothing. So the process exited cleanly."*

**That inference is invalid. SIGTERM is catchable**, and Claude Code catches it: it runs SessionEnd
hooks and prints its ordinary resume banner. A killed session and a voluntary `/exit` are
**byte-identical on screen**. The banner exonerates nothing.

Generalisable: *a graceful-looking exit is not evidence of a voluntary one.* The discriminator is
`close-records`' `signal` field, never the pane's last line.

### 1b. Exonerated, by their own evidence stores

- **`cc-teardown`** — writes a teardown marker unconditionally at the point where "the first kill is
  the next statement" (`bin/cc-teardown:275`, `write_teardown_marker`). **No marker exists** for any
  of the three. The only marker in the window is pane `894` (`mode:terminal`, `07:38:39Z`) — a
  different session.
- **`handoff-fire.sh self-close` / the SELF-RETIRE trailer** — `~/.claude/logs/close-attrib.jsonl`
  holds exactly ONE row in the window (`07:38:44Z`, pane `894`, `caller_pid 5154`). Self-close types
  `/exit`; it sends no signal.
- **`cc-reaper`'s `garbage` arm** — TERMs 2–5 processes every ~10 min and fired at `07:36:07Z`, but
  its awk predicate contains `if (comm[p]=="claude.exe") continue` and marks every ancestor of a
  live claude untouchable (`bin/cc-reaper:310-390`). Not convicted; not fully excluded either.

### 1c. CONVICTED — a `pkill` whose `-P` scope was never parsed, and became a pattern

The sender is `bash-execution.log [2026-08-09T07:38:16Z]`, session
`54400a9d-2d49-4edc-b914-89c9266510f6` (pane `894`, `wt-bs-header-phone`), shutting down its own dev
server one turn before self-closing:

```
pkill -f "next dev" -P $$ 2>/dev/null; lsof -nP -iTCP:3381 -sTCP:LISTEN -t 2>/dev/null | xargs -r kill
```

**`-P $$` is placed after the operand, so `pkill` never parses it as an option.** BSD `getopt` stops
at the first non-option argument; `pgrep`/`pkill` then treat every remaining word as an *additional
pattern*, OR'd. The intended "only my own children" became a third pattern list:

> kill anything whose full argv matches `next dev` **OR** `-P` **OR** `<the shell's pid>`

`-P` is a two-character substring, and **every fired handoff peer carries its brief in `argv`** —
`HANDOFF-PING` alone contains it. So the command's real selection was *the fleet's handoff peers*.

Verified three ways, read-only, on the live box:

| claim | evidence |
|---|---|
| `-P` after the operand is not an option | `pgrep -P 99999` → 0 procs (a true ppid filter); `pgrep -f zzzz-unique -P 99999` → 18 procs |
| operands are OR'd, not intersected | `pgrep -f MARKERALPHA` → 1; `pgrep -f MARKERALPHA -P 99999` → that 1 **plus** every `-P` match |
| the shape still selects live sessions | `pgrep -f "next dev" -P $$` today selects **20** processes — 3 live `claude` sessions in 3 different account dirs, their `cc-close-attrib` wrappers, ~10 Bash-tool shells (their argv ends `pwd -P`), and the 3 real dev servers. Every claude match attributes to the `-P` operand, in `HANDOFF-PING` |

All three victims' argv contained `-P`: `e55264aa` (`cc-fired/891.json`) and `d505227f`
(`cc-fired/895.json`) are fired peers whose briefs carry `HANDOFF-PING`; `49e10824` was launched
with a prompt that also contains the substring. This is the same class as
`pgrep-f-matches-agent-briefs` — argv carries whole briefs — one level worse, because here the
*pattern* was an accident rather than the *subject*.

**The survivor is explained by the same command.** `pgrep`/`pkill` exclude themselves **and all
their ancestors** by default (`man pgrep`: *"-a Include process ancestors in the match list. By
default, the current pgrep or pkill process and all of its ancestors are excluded"*). Pid `82520`
started `07:10:17Z` and exited rc 0 at `07:38:42Z` — that is pane `894` itself
(`cc-fired/894.json`: fired `07:10:10Z`, `closedAt 07:38:37Z`). It matched the pattern as squarely
as the three that died and lived **only** because it was the caller's own ancestor. The fingerprint
§1b called distinguishing was not a predicate at all.

**Why the first pass exonerated it.** `close-records` reports `argv` as **`argv[first 3]` only** —
`bin/cc-close-attrib:55,147` writes a fixed three-slot array. The recorded
`claude --permission-mode auto` is a *truncation*, so testing the pattern against the record returns
"no match" for a process whose real argv matched. The store that identifies the victims cannot
answer why they were selected, and it does not say so.
*Generalisable: a fixed-arity capture of a variable-length field is indistinguishable from a short
value, and every negative drawn from it is unsound.*

**Excluded with evidence, this pass:** `~/.zsh_history` is live on both sides of the window
(`06:48:32Z`, then `07:43:29Z`) with **nothing between** — the operator did not type it.
`devserver-gc` is dry-run only (`act=0`, "would TERM") and its run in that hour was `07:40:07Z`,
*after* the kill. `devserver-census.sh:266` TERMs an ancestor chain but stops climbing at the first
parent that is not `next dev`/`pnpm dev`, so it cannot reach a session. Memory pressure is out:
`compressor-sentinel` read `pct 8.5`, `strk 0` across the window; the 774 MB drop at `07:38:19Z` is
the deaths, not their cause (and jetsam sends SIGKILL, not SIGTERM).

### 1d. CONVICTED — the guard against exactly this accepts `-P` as proof of scoping

`hooks/validate-bash.sh:243` exists because an unscoped `pkill -f bats` killed every concurrent
session's landing gate (the 2026-07-26 false-RED epidemic, backlog `a0718a5d78b3`). Its allowlist of
"this one is scoped, let it pass" includes `(^|[[:space:]])-P[[:space:]]` — **the very token that is
inert when it follows the pattern.** So `pkill -f "bats" -P $$` reads as scoped to the guard and
runs machine-wide, which is the epidemic the guard was written to end.

It did not fire here for a second reason: it only engages when the occurrence names
`bats|ship-land|postland-verify`, and this one named `next dev`. Both halves are defects — the
scope test accepts a token it never validates the *position* of, and the target test assumes the only
thing worth protecting is a gate process.

---

## 2. CONVICTED — the crash watchdog cannot fire on a caught signal

This is why nothing alarmed, and it is the more durable defect.

All three sessions **were** covered: `lead-crash-watchdog.log` shows a registration and a spawned
watchdog daemon for each. All three watchdogs then logged `pid file gone — exit`.

```
hooks/lead-crash-watchdog.sh:899
  # pid file gone = clean shutdown elsewhere
  [[ -f "$pid_file" ]] || { echo "[watchdog $sid] pid file gone — exit"; return 0; }
```

But `hooks/session-end.sh:32` removes `~/.claude/watchdog/<sid>.pid` on **any** exit — and SessionEnd
runs on a caught SIGTERM. So:

- the pid-file check sits **first** in the poll loop and wins the race against the death check;
- it returns 0 **before** reaching the crash ladder (~line 279) — the ladder that consults the
  teardown marker and classifies *marker absent* as a genuine **CRASH**;
- therefore **every externally-TERMed session launders itself into "clean shutdown elsewhere."**

The watchdog can only ever fire on a death where SessionEnd did **not** run (SIGKILL, panic). The
commonest kind of unexpected death — a caught signal — is structurally invisible to it.

**Fix direction:** on the `pid file gone` branch, do not return 0 unconditionally. Consult the same
teardown marker the crash ladder uses: marker present ⇒ sanctioned teardown, exit quietly; marker
absent **and** the process is gone ⇒ this is a crash, raise it. The discriminator already exists in
this file; it is simply on the branch these deaths never reach.

---

## 3. CONVICTED — the reaper kills read-only agents for producing no git refs

Both subagents dispatched to convict the SIGTERM sender were themselves reaped mid-work.

```json
{ "kind":"reap-decision", "member":"killer-hunt", "decision":"REAP",
  "reason_kind":"shared-no-refs", "age_s":995, "grace_s":300,
  "reason":"SHARED cwd: no refs/wip|checkpoints ref for this member, and a read-only member
            writes none by construction (teammate-checkpoint.sh:201-204 exits 0 with no ref
            when the tree matches HEAD) — birth grace, not R-b, is what holds a just-born
            member here; accepted residual: produced-nothing is reaped like
            produced-nothing-durable" }
```
— `~/.claude/reap-guard/reap-killer-hunt-20260809T080526Z-47874-10614.json`

The reason string **states the defect and accepts it as residual**. A read-only member writes no
`refs/wip` ref *by construction*, so "no refs ⇒ produced nothing ⇒ reapable" convicts every
read-only agent that outlives the 300 s birth grace. `killer-hunt` was killed at 995 s having
produced nothing *durable* — because it was explicitly briefed to produce nothing durable.

`loss-audit` survived its first idle only because the birth grace happened to cover it by **five
seconds** (`age 295s < 300s`, `decision: DEFER`), got its report out, and was reaped on its next
idle.

**Compounding surface defect:** Claude Code's own agent list kept showing both as live (`Vibing…
18m`), and clicking through showed only the brief — the agents were killed mid-turn, so nothing was
written back, and CC never learned they died. The UI asserted "working" over two corpses.

**Fix direction:** reap-eligibility must not use "wrote a git ref" as a proxy for "produced
something" for members that cannot write one. Either classify read-only members explicitly and
exempt them, or key the proxy on evidence a read-only member *does* leave (messages sent, transcript
growth) — not on an artifact its brief forbids.

---

## 4. Work disposition (all recovered or protected)

| session | verdict | evidence / action |
|---|---|---|
| `bs-footer-motion` | **SAFE** — landed, content-verified | `origin/main:docs/plans/BOTTLE_SERVICE_MOTION_GROUND_UP.md` line 3608 reads `(LANDED 2026-08-09)`; a sibling rescued it via rebase at `00:42:59`, 4 m 42 s after the kill. ⚠️ It landed **without its `pnpm build` gate ever going green** — the build task was killed by the same SIGTERM. |
| `rum-iad-endpoints` | **STRANDED → protected** | 310 uncommitted lines + a new 177-line test existing nowhere else. Salvaged non-destructively: patch `~/.claude/salvage/rum-iad-endpoints-sigterm-20260809T073817Z.patch` (21,888 B) and ref `refs/wip/rum-iad-endpoints/sigterm-salvage` → `dee9d33b9`. Working tree left byte-identical. |
| `lakehouse-lecture` | **STRANDED (mild) → resumed** | 1 unpushed commit `6db845f`; was idle 13 min at death, nothing in flight. Resumed 2026-08-09 ~00:55 and re-engaged. |

**Undelivered mail — the "reping" that structurally could not arrive.** The lead's reply to
`bs-footer-motion` was sent `07:37:31Z` and sits at `~/.claude/mailbox/891.md` (899 B, 1 line). There
has never been an `891.acked`, `891.seen`, or any `.watchers/891.*` entry — it was written to disk
and **never surfaced to the model**. The session had 46 s of life left and no turn boundary in them.
`cc-notify`'s `no-watcher` verdict was not a warning that delivery might be late; it was delivery
failing.

Its second ask died with it and is now filed as backlog `a44eef543cfa`: *does production
`MoneyTicker`/`CartDrawer` share the caption-vs-figure clock split that rendered a figure $1,787
wrong in the largest type facing the guest, for ~30 frames?* Nobody has checked production.

---

## 5. Repo-membership gap found while documenting the resume path

The `resume-sessions` runbook is in the repo; **its actuators are not.**

| piece | tracked |
|---|---|
| `skills/resume-sessions/{SKILL,REFERENCE}.md` | ✅ |
| `scripts/limit-recover/lr-select.py` + 7 siblings | ✅ |
| `bin/kitty-split-launch.sh` | ✅ |
| `~/.reso/bin/reso-resume-one`, `reso-keepalive`, `reso-quota` | ❌ **untracked** |

Consequence, measured today: `reso-resume-one` hardcodes `bin=$HOME/.claude-183/…` (that path now
holds **2.1.215**) and `model=claude-opus-4-8 effort=max`. The session it was used to resume ran
**2.1.220 / claude-opus-5** in every one of its versioned rows. Using the tool as shipped would have
silently downgraded both binary and model on a recovery. No lint, test, or review can catch this
because the file is not in the repo.

The resume performed today therefore used a corrected one-off launcher (same `expect` wrapper —
auto-answers "Resume from summary", forwards SIGWINCH — with `.claude-220` / `claude-opus-5 @ high`).

**Fix direction:** bring the three `reso-*` actuators into `bin/`, or delete them and fold their one
load-bearing part (the `expect` wrapper) into a tracked script the skill can name.

---

## 6. Next actions

1. ~~Convict the SIGTERM sender.~~ **DONE — §1c.** Follow-on, now that the mechanism is known:
   fix §1d's guard (accepts an unvalidated `-P` as proof of scope; only defends gate programs), and
   widen `cc-close-attrib`'s three-slot `argv` capture so a close record can answer *why* a process
   was selected, not merely that it died.
2. **Fix §2** (`lead-crash-watchdog.sh:899` consults the teardown marker before exiting quietly).
3. **Fix §3** (reap-eligibility must not convict members that cannot write refs).
4. Land the README row in §4 of `README.md` documenting `resume-sessions` (in this branch).
5. Decide on §5 (track the `reso-*` actuators, or retire them). **CLOSED — see §7: trunk already
   did it, better, on 2026-08-10 and 2026-08-17.**

---

## 7. Recovery of this branch, 2026-08-22 — and the measurement that bounds it

This document, and three of the four fixes it prescribes, sat reachable only from
`refs/heads/fix/sigterm-forensics` for thirteen days (backlog `41099442ae0e`). Recovered today by
`cherry-pick -x`, each verified absent from trunk *before* picking — marker present in the commit,
absent at its parent, absent on `origin/main`, against a positive control proving the probe could
see the file at all — and each red-proofed in a scratch tree against trunk's own subject:

| patch | disposition | red-proof at trunk |
|---|---|---|
| `30017e2a4` guard: an option after the pattern is another pattern | **RECOVERED** | 3 red (22, 23, 24) of plan 28 |
| `23406cbe4` watchdog: a caught SIGTERM is not a clean exit | **RECOVERED** | 4 red (27, 28, 30, 31) of plan 31 |
| `a3db53228` reap-guard: ref-absence is not idleness | **RECOVERED** | 1 red (20) of plan 23 |
| `db1f92470` this document's §1c/§1d conviction | **RECOVERED** | n/a — docs |
| `410f920c9` track the `reso-*` actuators | **SUPERSEDED — deliberately NOT recovered** | would REGRESS trunk |

**Why `410f920c9` is a refusal and not a gap.** Its two `bin/` files exist on trunk already, tracked
by another route, and trunk's copies are strictly newer: `bin/reso-resume-one`'s header on
`origin/main` names *this branch by ref* and records three defects fixed on 2026-08-10 (a pinned
`--effort`, a stale binary path, a stale model id), and `bin/reso-keepalive` gained a kitty arm on
2026-08-17. Cherry-picking the branch version would revert all four. A patch that is
content-absent from trunk by patch-id can still be *superseded by a better cure*, and the oracle
that answers "are these bytes on main" cannot tell the two apart.

### The 2026-08-09 conviction does NOT explain the cuts running today

§1c convicts a specific `pkill` on a specific day, and that conviction stands. It is tempting —
and wrong — to read the surviving cut rate as the same bug still running. Measured 2026-08-22 over
the whole 368-stamp history in `~/.claude/autonomy/postland/stamps`:

- The corpus runner is cut, with zero not-ok, in **27 of the last 40 stamps (67.5%)**; over the
  last 80, **60 (75%)**. `runner.log` attributes almost all of them to *"KILLED by signal 15|9 from
  OUTSIDE this runner (sender unidentified)"*.
- **`run_s` for cuts and for greens is the same distribution** — cut median 2590 s (n=186), green
  median 2566 s (n=37), and 70% of cuts vs 27 of 37 greens fall in the same 2100–3100 s band.

That equality is the discriminating fact, and it refutes both easy stories. A stray pattern-kill
from a sibling session arrives at a time uncorrelated with the run, so it would truncate runs at
*uniformly distributed* points and cuts would be markedly **shorter** than greens. A wall-clock
bound would pin cuts to a **narrower** band than greens. Neither holds: the kill arrives when the
run is approximately finished, which is a third mechanism nobody has named.

So the three patches recovered here are sound and independently justified — the guard genuinely
would have allowed the 2026-08-09 kill, and trunk today genuinely cannot tell an external SIGTERM
from a recycle (`lead-crash-watchdog` test 27, red at trunk) — but **none of them is licensed as a
cure for the 67.5% rate.** Backlog `b7252a3bb015` stays open on that ground. Whoever works it next:
close it on the RATE across a window, measured with the same instrument on both sides, never on one
reading — a probe sampling the single newest stamp exits 0 one time in three with the bug fully
present, which is how that row was auto-closed for six days in August.
